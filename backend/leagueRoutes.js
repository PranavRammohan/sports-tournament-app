// leagueRoutes.js
const express = require('express');
const router = express.Router();
const pool = require('./db');

const TIER_SIZE = 4;

// ---------- CREATE LEAGUE ----------
router.post('/create', async (req, res) => {
  const userId = req.userId;
  const {
    sport, area, seasonStart, seasonEnd, format, genderCategory,
    scheduleType, matchesPerPlayer, hostEntersScores,
  } = req.body;

  if (!sport || !area || !seasonStart || !seasonEnd || !format || !genderCategory) {
    return res.status(400).json({ error: 'All fields are required.' });
  }
  if (!['singles', 'doubles'].includes(format)) {
    return res.status(400).json({ error: 'Format must be singles or doubles.' });
  }
  if (!['mens', 'womens'].includes(genderCategory)) {
    return res.status(400).json({ error: 'Gender category must be mens or womens.' });
  }
  const finalScheduleType = scheduleType === 'matches_per_player' ? 'matches_per_player' : 'round_robin';
  if (finalScheduleType === 'matches_per_player' && (!matchesPerPlayer || matchesPerPlayer < 1)) {
    return res.status(400).json({ error: 'Please specify how many matches each player should play.' });
  }

  try {
    const result = await pool.query(
      `INSERT INTO leagues (sport, area, season_start, season_end, created_by, format, gender_category,
                            schedule_type, matches_per_player, host_enters_scores)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10)
       RETURNING id, sport, area, season_start, season_end, format, gender_category, created_by,
                 schedule_type, matches_per_player, host_enters_scores`,
      [
        sport, area, seasonStart, seasonEnd, userId, format, genderCategory,
        finalScheduleType, finalScheduleType === 'matches_per_player' ? matchesPerPlayer : null,
        hostEntersScores === true,
      ]
    );

    const league = result.rows[0];

    await pool.query(
      `INSERT INTO league_members (league_id, user_id) VALUES ($1, $2)`,
      [league.id, userId]
    );

    res.status(201).json({ league });
  } catch (err) {
    console.error('Create league error:', err);
    res.status(500).json({ error: 'Something went wrong creating the league.' });
  }
});

// ---------- BROWSE LEAGUES ----------
router.get('/', async (req, res) => {
  const userId = req.userId;
  const { area, format } = req.query;

  try {
    const userResult = await pool.query('SELECT gender FROM users WHERE id = $1', [userId]);
    if (userResult.rows.length === 0) {
      return res.status(404).json({ error: 'User not found.' });
    }
    const userGenderCategory = userResult.rows[0].gender === 'M' ? 'mens' : 'womens';

    let query = `
      SELECT l.id, l.sport, l.area, l.season_start, l.season_end, l.format, l.gender_category,
             l.schedule_type, l.matches_per_player, l.host_enters_scores,
             COUNT(lm.id) AS member_count
      FROM leagues l
      LEFT JOIN league_members lm ON lm.league_id = l.id
      WHERE EXISTS (
        SELECT 1 FROM user_sports us
        WHERE us.user_id = $1 AND us.sport = l.sport
      )
      AND l.gender_category = $2
    `;
    const params = [userId, userGenderCategory];

    if (area) {
      params.push(area);
      query += ` AND l.area = $${params.length}`;
    }
    if (format) {
      params.push(format);
      query += ` AND l.format = $${params.length}`;
    }

    query += ` GROUP BY l.id ORDER BY l.season_start ASC`;

    const result = await pool.query(query, params);
    res.status(200).json({ leagues: result.rows });
  } catch (err) {
    console.error('Browse leagues error:', err);
    res.status(500).json({ error: 'Something went wrong fetching leagues.' });
  }
});

// ---------- MY LEAGUES ----------
router.get('/mine', async (req, res) => {
  const userId = req.userId;

  try {
    const result = await pool.query(
      `SELECT l.id, l.sport, l.area, l.season_start, l.season_end, l.format, l.gender_category,
              l.schedule_type, l.matches_per_player, l.host_enters_scores,
              COUNT(lm2.id) AS member_count
       FROM league_members lm
       JOIN leagues l ON l.id = lm.league_id
       LEFT JOIN league_members lm2 ON lm2.league_id = l.id
       WHERE lm.user_id = $1
       GROUP BY l.id
       ORDER BY l.season_start ASC`,
      [userId]
    );
    res.status(200).json({ leagues: result.rows });
  } catch (err) {
    console.error('My leagues error:', err);
    res.status(500).json({ error: 'Something went wrong fetching your leagues.' });
  }
});

// ---------- JOIN LEAGUE ----------
router.post('/:id/join', async (req, res) => {
  const userId = req.userId;
  const leagueId = req.params.id;

  try {
    const league = await pool.query('SELECT * FROM leagues WHERE id = $1', [leagueId]);
    if (league.rows.length === 0) {
      return res.status(404).json({ error: 'League not found.' });
    }
    const leagueData = league.rows[0];

    const userResult = await pool.query('SELECT gender FROM users WHERE id = $1', [userId]);
    const userGenderCategory = userResult.rows[0].gender === 'M' ? 'mens' : 'womens';
    if (leagueData.gender_category !== userGenderCategory) {
      return res.status(403).json({ error: 'This league is not in your gender category.' });
    }

    const hasSport = await pool.query(
      'SELECT id FROM user_sports WHERE user_id = $1 AND sport = $2 LIMIT 1',
      [userId, leagueData.sport]
    );
    if (hasSport.rows.length === 0) {
      return res.status(403).json({ error: 'You need to add this sport to your profile before joining.' });
    }

    const existing = await pool.query(
      'SELECT id FROM league_members WHERE league_id = $1 AND user_id = $2',
      [leagueId, userId]
    );
    if (existing.rows.length > 0) {
      return res.status(409).json({ error: 'You already joined this league.' });
    }

    await pool.query(
      'INSERT INTO league_members (league_id, user_id) VALUES ($1, $2)',
      [leagueId, userId]
    );

    res.status(201).json({ message: 'Joined league successfully.' });
  } catch (err) {
    console.error('Join league error:', err);
    res.status(500).json({ error: 'Something went wrong joining the league.' });
  }
});

// ---------- LEAVE LEAGUE ----------
router.post('/:id/leave', async (req, res) => {
  const userId = req.userId;
  const leagueId = req.params.id;

  try {
    const league = await pool.query('SELECT * FROM leagues WHERE id = $1', [leagueId]);
    if (league.rows.length === 0) {
      return res.status(404).json({ error: 'League not found.' });
    }
    if (league.rows[0].created_by === userId) {
      return res.status(400).json({ error: 'As the host, you cannot leave — you can delete the league instead.' });
    }

    const result = await pool.query(
      'DELETE FROM league_members WHERE league_id = $1 AND user_id = $2 RETURNING id',
      [leagueId, userId]
    );
    if (result.rows.length === 0) {
      return res.status(404).json({ error: "You aren't a member of this league." });
    }

    res.status(200).json({ message: 'You left the league.' });
  } catch (err) {
    console.error('Leave league error:', err);
    res.status(500).json({ error: 'Something went wrong leaving the league.' });
  }
});

// ---------- LEAGUE DETAIL + DUAL LEADERBOARD (points primary, rating shown alongside) ----------
router.get('/:id', async (req, res) => {
  const leagueId = req.params.id;

  try {
    const league = await pool.query('SELECT * FROM leagues WHERE id = $1', [leagueId]);
    if (league.rows.length === 0) {
      return res.status(404).json({ error: 'League not found.' });
    }

    const leagueData = league.rows[0];

    const leaderboard = await pool.query(
      `SELECT u.id, u.username, u.gender, us.rating, us.matches_played, us.wins, us.losses, lm.points
       FROM league_members lm
       JOIN users u ON u.id = lm.user_id
       JOIN user_sports us ON us.user_id = u.id AND us.sport = $1 AND us.format = $2
       WHERE lm.league_id = $3
       ORDER BY lm.points DESC, us.rating DESC`,
      [leagueData.sport, leagueData.format, leagueId]
    );

    res.status(200).json({ league: leagueData, leaderboard: leaderboard.rows });
  } catch (err) {
    console.error('League detail error:', err);
    res.status(500).json({ error: 'Something went wrong fetching league details.' });
  }
});

// ---------- GENERATE SCHEDULE (host only, once) ----------
router.post('/:id/generate-schedule', async (req, res) => {
  const userId = req.userId;
  const leagueId = req.params.id;

  try {
    const leagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [leagueId]);
    if (leagueResult.rows.length === 0) {
      return res.status(404).json({ error: 'League not found.' });
    }
    const league = leagueResult.rows[0];

    if (league.created_by !== userId) {
      return res.status(403).json({ error: 'Only the league host can generate the schedule.' });
    }

    const existing = await pool.query(
      'SELECT id FROM scheduled_matches WHERE league_id = $1 LIMIT 1',
      [leagueId]
    );
    if (existing.rows.length > 0) {
      return res.status(409).json({ error: 'Schedule has already been generated for this league.' });
    }

    const membersResult = await pool.query(
      `SELECT u.id, us.rating
       FROM league_members lm
       JOIN users u ON u.id = lm.user_id
       JOIN user_sports us ON us.user_id = u.id AND us.sport = $1 AND us.format = $2
       WHERE lm.league_id = $3
       ORDER BY us.rating DESC`,
      [league.sport, league.format, leagueId]
    );
    const members = membersResult.rows;

    const minPlayersRequired = league.format === 'doubles' ? 4 : 2;
    if (members.length < minPlayersRequired) {
      return res.status(400).json({
        error: league.format === 'doubles'
          ? 'Need at least 4 players to generate a doubles schedule.'
          : 'Need at least 2 players to generate a schedule.',
      });
    }

    let scheduledMatches = [];

    if (league.schedule_type === 'matches_per_player' && league.format === 'singles') {
      scheduledMatches = generateMatchesPerPlayerSchedule(members, league.matches_per_player);
    } else {
      scheduledMatches = generateRoundRobinSchedule(members, league.format);
    }

    for (const m of scheduledMatches) {
      await pool.query(
        `INSERT INTO scheduled_matches
          (league_id, tier_number, player1_id, player1_partner_id, player2_id, player2_partner_id)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [leagueId, m.tierNumber, m.player1Id, m.player1PartnerId, m.player2Id, m.player2PartnerId]
      );
    }

    res.status(201).json({ message: 'Schedule generated.', matchCount: scheduledMatches.length });
  } catch (err) {
    console.error('Generate schedule error:', err);
    res.status(500).json({ error: 'Something went wrong generating the schedule.' });
  }
});

// Original tiered round-robin generator (singles: tier-based full round robin;
// doubles: pairs strongest-with-weakest into teams, then round robins the teams).
function generateRoundRobinSchedule(members, format) {
  const tiers = [];
  for (let i = 0; i < members.length; i += TIER_SIZE) {
    tiers.push(members.slice(i, i + TIER_SIZE));
  }

  const minTierSize = format === 'doubles' ? 4 : 2;
  while (tiers.length > 1 && tiers[tiers.length - 1].length < minTierSize) {
    const leftover = tiers.pop();
    tiers[tiers.length - 1] = tiers[tiers.length - 1].concat(leftover);
  }

  const scheduledMatches = [];

  tiers.forEach((tier, tierIndex) => {
    const tierNumber = tierIndex + 1;

    if (format === 'singles') {
      for (let i = 0; i < tier.length; i++) {
        for (let j = i + 1; j < tier.length; j++) {
          scheduledMatches.push({
            tierNumber,
            player1Id: tier[i].id,
            player1PartnerId: null,
            player2Id: tier[j].id,
            player2PartnerId: null,
          });
        }
      }
    } else {
      if (tier.length < 4) return;

      const teams = [];
      let lo = 0;
      let hi = tier.length - 1;
      while (lo < hi) {
        teams.push([tier[lo], tier[hi]]);
        lo++;
        hi--;
      }

      for (let i = 0; i < teams.length; i++) {
        for (let j = i + 1; j < teams.length; j++) {
          scheduledMatches.push({
            tierNumber,
            player1Id: teams[i][0].id,
            player1PartnerId: teams[i][1].id,
            player2Id: teams[j][0].id,
            player2PartnerId: teams[j][1].id,
          });
        }
      }
    }
  });

  return scheduledMatches;
}

// "Matches per player" generator for larger singles leagues (8+ players).
// Round by round, pairs players closest in rating who haven't played each other yet.
// Each round becomes its own "tier" number just for grouping/display purposes.
function generateMatchesPerPlayerSchedule(members, matchesPerPlayer) {
  const scheduledMatches = [];
  const playedPairs = new Set();
  const matchCounts = {};
  members.forEach((m) => (matchCounts[m.id] = 0));

  const pairKey = (a, b) => [a, b].sort((x, y) => x - y).join('-');

  for (let round = 1; round <= matchesPerPlayer; round++) {
    // Players still needing a match this round, sorted by rating (closest matchups first)
    let available = members
      .filter((m) => matchCounts[m.id] < round)
      .sort((a, b) => b.rating - a.rating);

    const usedThisRound = new Set();

    for (let i = 0; i < available.length; i++) {
      const playerA = available[i];
      if (usedThisRound.has(playerA.id)) continue;

      // Find the closest-rated available opponent not yet used this round and not already played
      let opponent = null;
      for (let j = i + 1; j < available.length; j++) {
        const candidate = available[j];
        if (usedThisRound.has(candidate.id)) continue;
        if (playedPairs.has(pairKey(playerA.id, candidate.id))) continue;
        opponent = candidate;
        break;
      }

      // If everyone close by has already been played, allow a repeat rather than skipping entirely
      if (!opponent) {
        for (let j = i + 1; j < available.length; j++) {
          const candidate = available[j];
          if (usedThisRound.has(candidate.id)) continue;
          opponent = candidate;
          break;
        }
      }

      if (opponent) {
        scheduledMatches.push({
          tierNumber: round,
          player1Id: playerA.id,
          player1PartnerId: null,
          player2Id: opponent.id,
          player2PartnerId: null,
        });
        playedPairs.add(pairKey(playerA.id, opponent.id));
        matchCounts[playerA.id]++;
        matchCounts[opponent.id]++;
        usedThisRound.add(playerA.id);
        usedThisRound.add(opponent.id);
      }
    }
  }

  return scheduledMatches;
}

// ---------- GET SCHEDULE (with completion status + contact info) ----------
router.get('/:id/schedule', async (req, res) => {
  const leagueId = req.params.id;

  try {
    const result = await pool.query(
      `SELECT sm.id, sm.tier_number,
              sm.player1_id, sm.player1_partner_id, sm.player2_id, sm.player2_partner_id,
              p1.username as player1_username, p1.phone_number as player1_phone,
              pp1.username as player1_partner_username, pp1.phone_number as player1_partner_phone,
              p2.username as player2_username, p2.phone_number as player2_phone,
              pp2.username as player2_partner_username, pp2.phone_number as player2_partner_phone,
              m.id as match_id, m.status as match_status, m.set_scores, m.winner_id,
              m.player1_id as reported_player1_id, m.player2_id as reported_player2_id
       FROM scheduled_matches sm
       LEFT JOIN matches m ON m.scheduled_match_id = sm.id AND m.status = 'confirmed'
       JOIN users p1 ON p1.id = sm.player1_id
       JOIN users p2 ON p2.id = sm.player2_id
       LEFT JOIN users pp1 ON pp1.id = sm.player1_partner_id
       LEFT JOIN users pp2 ON pp2.id = sm.player2_partner_id
       WHERE sm.league_id = $1
       ORDER BY sm.tier_number ASC, sm.id ASC`,
      [leagueId]
    );
    res.status(200).json({ schedule: result.rows });
  } catch (err) {
    console.error('Get schedule error:', err);
    res.status(500).json({ error: 'Something went wrong fetching the schedule.' });
  }
});

// ---------- DELETE LEAGUE (host only) ----------
router.delete('/:id', async (req, res) => {
  const userId = req.userId;
  const leagueId = req.params.id;

  try {
    const leagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [leagueId]);
    if (leagueResult.rows.length === 0) {
      return res.status(404).json({ error: 'League not found.' });
    }
    const league = leagueResult.rows[0];

    if (league.created_by !== userId) {
      return res.status(403).json({ error: 'Only the league host can delete this league.' });
    }

    await pool.query('DELETE FROM leagues WHERE id = $1', [leagueId]);

    res.status(200).json({ message: 'League deleted.' });
  } catch (err) {
    console.error('Delete league error:', err);
    res.status(500).json({ error: 'Something went wrong deleting the league.' });
  }
});

module.exports = router;