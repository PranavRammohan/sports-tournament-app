// leagueRoutes.js
const express = require('express');
const router = express.Router();
const pool = require('./db');

const TIER_SIZE = 4;

function generateJoinCode() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  let code = '';
  for (let i = 0; i < 6; i++) {
    code += chars[Math.floor(Math.random() * chars.length)];
  }
  return code;
}

function isPowerOfTwo(n) {
  return n > 0 && (n & (n - 1)) === 0;
}

function generateSeedOrder(size) {
  let result = [1, 2];
  while (result.length < size) {
    const newSize = result.length * 2;
    const newResult = [];
    for (const seed of result) {
      newResult.push(seed);
      newResult.push(newSize + 1 - seed);
    }
    result = newResult;
  }
  return result;
}

// ---------- CREATE LEAGUE ----------
router.post('/create', async (req, res) => {
  const userId = req.userId;
  const {
    name, sport, area, seasonStart, seasonEnd, format, genderCategory,
    scheduleType, matchesPerPlayer, hostEntersScores, hostPlays, isPrivate, academyName,
  } = req.body;

  if (!name || !sport || !area || !seasonStart || !seasonEnd || !format || !genderCategory) {
    return res.status(400).json({ error: 'All fields are required.' });
  }
  if (!['singles', 'doubles'].includes(format)) {
    return res.status(400).json({ error: 'Format must be singles or doubles.' });
  }
  if (!['mens', 'womens'].includes(genderCategory)) {
    return res.status(400).json({ error: 'Gender category must be mens or womens.' });
  }

  const validScheduleTypes = ['round_robin', 'matches_per_player', 'knockout', 'custom'];
  const finalScheduleType = validScheduleTypes.includes(scheduleType) ? scheduleType : 'round_robin';

  if (finalScheduleType === 'matches_per_player' && (!matchesPerPlayer || matchesPerPlayer < 1)) {
    return res.status(400).json({ error: 'Please specify how many matches each player should play.' });
  }
  if (finalScheduleType === 'knockout' && format !== 'singles') {
    return res.status(400).json({ error: 'Knockout format is currently only supported for singles leagues.' });
  }

  try {
    let joinCode = null;
    if (isPrivate === true) {
      let unique = false;
      while (!unique) {
        joinCode = generateJoinCode();
        const existing = await pool.query('SELECT id FROM leagues WHERE join_code = $1', [joinCode]);
        if (existing.rows.length === 0) unique = true;
      }
    }

    const result = await pool.query(
      `INSERT INTO leagues (name, sport, area, season_start, season_end, created_by, format, gender_category,
                            schedule_type, matches_per_player, host_enters_scores, is_private, join_code, academy_name)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14)
       RETURNING id, name, sport, area, season_start, season_end, format, gender_category, created_by,
                 schedule_type, matches_per_player, host_enters_scores, is_private, join_code, academy_name`,
      [
        name, sport, area, seasonStart, seasonEnd, userId, format, genderCategory,
        finalScheduleType, finalScheduleType === 'matches_per_player' ? matchesPerPlayer : null,
        hostEntersScores === true, isPrivate === true, joinCode,
        academyName && academyName.trim().length > 0 ? academyName.trim() : null,
      ]
    );

    const league = result.rows[0];

    if (hostPlays !== false) {
      await pool.query(
        `INSERT INTO league_members (league_id, user_id) VALUES ($1, $2)`,
        [league.id, userId]
      );
    }

    res.status(201).json({ league });
  } catch (err) {
    console.error('Create league error:', err);
    res.status(500).json({ error: 'Something went wrong creating the league.' });
  }
});

// ---------- BROWSE LEAGUES (public only) ----------
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
      SELECT l.id, l.name, l.sport, l.area, l.season_start, l.season_end, l.format, l.gender_category,
             l.schedule_type, l.matches_per_player, l.host_enters_scores, l.is_private, l.academy_name,
             COUNT(lm.id) AS member_count
      FROM leagues l
      LEFT JOIN league_members lm ON lm.league_id = l.id
      WHERE EXISTS (
        SELECT 1 FROM user_sports us
        WHERE us.user_id = $1 AND us.sport = l.sport
      )
      AND l.gender_category = $2
      AND l.is_private = false
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
      `SELECT DISTINCT l.id, l.name, l.sport, l.area, l.season_start, l.season_end, l.format, l.gender_category,
              l.schedule_type, l.matches_per_player, l.host_enters_scores, l.is_private, l.join_code, l.academy_name,
              (SELECT COUNT(*) FROM league_members lm2 WHERE lm2.league_id = l.id) AS member_count
       FROM leagues l
       LEFT JOIN league_members lm ON lm.league_id = l.id AND lm.user_id = $1
       WHERE lm.user_id = $1 OR l.created_by = $1
       ORDER BY l.season_start ASC`,
      [userId]
    );
    res.status(200).json({ leagues: result.rows });
  } catch (err) {
    console.error('My leagues error:', err);
    res.status(500).json({ error: 'Something went wrong fetching your leagues.' });
  }
});

// ---------- JOIN LEAGUE (by id, public leagues) ----------
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

// ---------- JOIN LEAGUE BY CODE (private leagues) ----------
router.post('/join-by-code', async (req, res) => {
  const userId = req.userId;
  const { code } = req.body;

  if (!code) {
    return res.status(400).json({ error: 'Please enter a join code.' });
  }

  try {
    const league = await pool.query(
      'SELECT * FROM leagues WHERE join_code = $1 AND is_private = true',
      [code.trim().toUpperCase()]
    );
    if (league.rows.length === 0) {
      return res.status(404).json({ error: 'Invalid join code.' });
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
      [leagueData.id, userId]
    );
    if (existing.rows.length > 0) {
      return res.status(409).json({ error: 'You already joined this league.' });
    }

    await pool.query(
      'INSERT INTO league_members (league_id, user_id) VALUES ($1, $2)',
      [leagueData.id, userId]
    );

    res.status(201).json({ message: 'Joined league successfully.', leagueId: leagueData.id });
  } catch (err) {
    console.error('Join by code error:', err);
    res.status(500).json({ error: 'Something went wrong joining the league.' });
  }
});

// ---------- SEARCH USERS TO ADD (host only) ----------
router.get('/:id/search-players', async (req, res) => {
  const userId = req.userId;
  const leagueId = req.params.id;
  const { q } = req.query;

  if (!q || q.trim().length < 2) {
    return res.status(400).json({ error: 'Enter at least 2 characters to search.' });
  }

  try {
    const leagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [leagueId]);
    if (leagueResult.rows.length === 0) {
      return res.status(404).json({ error: 'League not found.' });
    }
    const league = leagueResult.rows[0];

    if (league.created_by !== userId) {
      return res.status(403).json({ error: 'Only the league host can search for players.' });
    }

    const genderChar = league.gender_category === 'mens' ? 'M' : 'F';

    const result = await pool.query(
      `SELECT DISTINCT u.id, u.username, u.location
       FROM users u
       JOIN user_sports us ON us.user_id = u.id AND us.sport = $1
       WHERE u.username ILIKE $2
         AND u.gender = $3
         AND u.id NOT IN (
           SELECT user_id FROM league_members WHERE league_id = $4
         )
       LIMIT 15`,
      [league.sport, `%${q.trim()}%`, genderChar, leagueId]
    );

    res.status(200).json({ users: result.rows });
  } catch (err) {
    console.error('Search players error:', err);
    res.status(500).json({ error: 'Something went wrong searching for players.' });
  }
});

// ---------- ADD PLAYER DIRECTLY (host only) ----------
router.post('/:id/add-player', async (req, res) => {
  const userId = req.userId;
  const leagueId = req.params.id;
  const { playerId } = req.body;

  if (!playerId) {
    return res.status(400).json({ error: 'Please select a player to add.' });
  }

  try {
    const leagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [leagueId]);
    if (leagueResult.rows.length === 0) {
      return res.status(404).json({ error: 'League not found.' });
    }
    const league = leagueResult.rows[0];

    if (league.created_by !== userId) {
      return res.status(403).json({ error: 'Only the league host can add players.' });
    }

    const genderChar = league.gender_category === 'mens' ? 'M' : 'F';
    const playerResult = await pool.query('SELECT * FROM users WHERE id = $1', [playerId]);
    if (playerResult.rows.length === 0) {
      return res.status(404).json({ error: 'Player not found.' });
    }
    if (playerResult.rows[0].gender !== genderChar) {
      return res.status(400).json({ error: 'This player does not match the league\'s gender category.' });
    }

    const hasSport = await pool.query(
      'SELECT id FROM user_sports WHERE user_id = $1 AND sport = $2 LIMIT 1',
      [playerId, league.sport]
    );
    if (hasSport.rows.length === 0) {
      return res.status(400).json({ error: 'This player has not added this sport to their profile yet.' });
    }

    const existing = await pool.query(
      'SELECT id FROM league_members WHERE league_id = $1 AND user_id = $2',
      [leagueId, playerId]
    );
    if (existing.rows.length > 0) {
      return res.status(409).json({ error: 'This player is already in the league.' });
    }

    await pool.query(
      'INSERT INTO league_members (league_id, user_id) VALUES ($1, $2)',
      [leagueId, playerId]
    );

    res.status(201).json({ message: 'Player added successfully.' });
  } catch (err) {
    console.error('Add player error:', err);
    res.status(500).json({ error: 'Something went wrong adding the player.' });
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

// ---------- REMOVE PLAYER (host only) ----------
router.delete('/:id/members/:userId', async (req, res) => {
  const hostId = req.userId;
  const leagueId = req.params.id;
  const targetUserId = parseInt(req.params.userId, 10);

  try {
    const leagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [leagueId]);
    if (leagueResult.rows.length === 0) {
      return res.status(404).json({ error: 'League not found.' });
    }
    const league = leagueResult.rows[0];

    if (league.created_by !== hostId) {
      return res.status(403).json({ error: 'Only the league host can remove players.' });
    }
    if (targetUserId === hostId) {
      return res.status(400).json({ error: 'You cannot remove yourself. Delete the league instead if needed.' });
    }

    const memberCheck = await pool.query(
      'SELECT id FROM league_members WHERE league_id = $1 AND user_id = $2',
      [leagueId, targetUserId]
    );
    if (memberCheck.rows.length === 0) {
      return res.status(404).json({ error: 'This player is not a member of this league.' });
    }

    // Remove any not-yet-played fixtures involving this player — they can no
    // longer be scheduled to play. Confirmed match history and rating changes
    // are left untouched, since that's a permanent record.
    await pool.query(
      `DELETE FROM matches
       WHERE league_id = $1 AND status IN ('pending', 'rejected')
         AND (player1_id = $2 OR player2_id = $2 OR player1_partner_id = $2 OR player2_partner_id = $2)`,
      [leagueId, targetUserId]
    );
    await pool.query(
      `DELETE FROM scheduled_matches
       WHERE league_id = $1
         AND (player1_id = $2 OR player2_id = $2 OR player1_partner_id = $2 OR player2_partner_id = $2)
         AND id NOT IN (
           SELECT scheduled_match_id FROM matches WHERE scheduled_match_id IS NOT NULL AND status = 'confirmed'
         )`,
      [leagueId, targetUserId]
    );
    await pool.query(
      `DELETE FROM playoff_matches
       WHERE league_id = $1 AND status != 'confirmed'
         AND (player1_id = $2 OR player2_id = $2)`,
      [leagueId, targetUserId]
    );

    await pool.query(
      'DELETE FROM league_members WHERE league_id = $1 AND user_id = $2',
      [leagueId, targetUserId]
    );

    res.status(200).json({ message: 'Player removed from league.' });
  } catch (err) {
    console.error('Remove player error:', err);
    res.status(500).json({ error: 'Something went wrong removing the player.' });
  }
});

// ---------- LEAGUE DETAIL + DUAL LEADERBOARD ----------
router.get('/:id', async (req, res) => {
  const leagueId = req.params.id;

  try {
    const league = await pool.query(
      `SELECT l.*, u.username as host_username
       FROM leagues l
       JOIN users u ON u.id = l.created_by
       WHERE l.id = $1`,
      [leagueId]
    );
    if (league.rows.length === 0) {
      return res.status(404).json({ error: 'League not found.' });
    }

    const leagueData = league.rows[0];

    const leaderboard = await pool.query(
      `SELECT u.id, u.username, u.gender, us.rating, lm.points,
              COALESCE(match_stats.matches_played, 0) AS matches_played,
              COALESCE(match_stats.wins, 0) AS wins,
              COALESCE(match_stats.losses, 0) AS losses
       FROM league_members lm
       JOIN users u ON u.id = lm.user_id
       JOIN user_sports us ON us.user_id = u.id AND us.sport = $1 AND us.format = $2
       LEFT JOIN (
         SELECT player_id, COUNT(*) AS matches_played,
                SUM(CASE WHEN player_id = winner_id THEN 1 ELSE 0 END) AS wins,
                SUM(CASE WHEN player_id != winner_id THEN 1 ELSE 0 END) AS losses
         FROM (
           SELECT id, league_id, winner_id, player1_id AS player_id FROM matches WHERE status = 'confirmed'
           UNION ALL
           SELECT id, league_id, winner_id, player2_id AS player_id FROM matches WHERE status = 'confirmed'
           UNION ALL
           SELECT id, league_id, winner_id, player1_partner_id AS player_id FROM matches WHERE status = 'confirmed' AND player1_partner_id IS NOT NULL
           UNION ALL
           SELECT id, league_id, winner_id, player2_partner_id AS player_id FROM matches WHERE status = 'confirmed' AND player2_partner_id IS NOT NULL
         ) all_participants
         WHERE league_id = $3
         GROUP BY player_id
       ) match_stats ON match_stats.player_id = u.id
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

// ---------- GENERATE SCHEDULE (host only, once, unless schedule was cleared) ----------
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

    if (league.schedule_type === 'custom') {
      return res.status(400).json({ error: 'Custom leagues do not use auto-generated schedules. Add matches manually instead.' });
    }

    if (league.schedule_type === 'knockout') {
      return generateKnockoutBracket(req, res, league);
    }

    const existing = await pool.query(
      'SELECT id FROM scheduled_matches WHERE league_id = $1 LIMIT 1',
      [leagueId]
    );
    if (existing.rows.length > 0) {
      return res.status(409).json({ error: 'Schedule has already been generated for this league. Use Regenerate to make a new one.' });
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
      scheduledMatches = generateNearestRatingSchedule(members, league.matches_per_player);
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

async function generateKnockoutBracket(req, res, league) {
  const leagueId = league.id;

  const existing = await pool.query('SELECT id FROM playoff_matches WHERE league_id = $1 LIMIT 1', [leagueId]);
  if (existing.rows.length > 0) {
    return res.status(409).json({ error: 'A bracket has already been generated for this league.' });
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

  if (!isPowerOfTwo(members.length) || members.length < 2) {
    return res.status(400).json({
      error: `Knockout leagues need an exact power-of-two number of players (2, 4, 8, 16...). Currently has ${members.length}.`,
    });
  }

  const size = members.length;
  const seedOrder = generateSeedOrder(size);
  const totalRounds = Math.log2(size);

  for (let i = 0; i < seedOrder.length; i += 2) {
    const seedA = seedOrder[i];
    const seedB = seedOrder[i + 1];
    await pool.query(
      `INSERT INTO playoff_matches (league_id, round_number, position, player1_id, player2_id, status)
       VALUES ($1, 1, $2, $3, $4, 'ready')`,
      [leagueId, i / 2 + 1, members[seedA - 1].id, members[seedB - 1].id]
    );
  }

  for (let round = 2; round <= totalRounds; round++) {
    const matchesInRound = size / Math.pow(2, round);
    for (let pos = 1; pos <= matchesInRound; pos++) {
      await pool.query(
        `INSERT INTO playoff_matches (league_id, round_number, position, status)
         VALUES ($1, $2, $3, 'pending')`,
        [leagueId, round, pos]
      );
    }
  }

  res.status(201).json({ message: 'Bracket generated.', matchCount: seedOrder.length / 2 });
}

// ---------- ADD A MANUAL MATCH (custom format, host only) ----------
router.post('/:id/add-manual-match', async (req, res) => {
  const userId = req.userId;
  const leagueId = req.params.id;
  const { player1Id, player1PartnerId, player2Id, player2PartnerId } = req.body;

  if (!player1Id || !player2Id) {
    return res.status(400).json({ error: 'Please select both sides of the match.' });
  }

  try {
    const leagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [leagueId]);
    if (leagueResult.rows.length === 0) {
      return res.status(404).json({ error: 'League not found.' });
    }
    const league = leagueResult.rows[0];

    if (league.created_by !== userId) {
      return res.status(403).json({ error: 'Only the league host can add matches.' });
    }
    if (league.schedule_type !== 'custom') {
      return res.status(400).json({ error: 'This league does not use manual match building.' });
    }
    if (league.format === 'doubles' && (!player1PartnerId || !player2PartnerId)) {
      return res.status(400).json({ error: 'Doubles matches need both partners selected.' });
    }
    if (league.format === 'singles' && (player1PartnerId || player2PartnerId)) {
      return res.status(400).json({ error: 'Singles matches should not have partners.' });
    }

    const allIds = [player1Id, player2Id, player1PartnerId, player2PartnerId].filter(Boolean);
    const memberCheck = await pool.query(
      `SELECT user_id FROM league_members WHERE league_id = $1 AND user_id = ANY($2::int[])`,
      [leagueId, allIds]
    );
    if (memberCheck.rows.length !== allIds.length) {
      return res.status(400).json({ error: 'All selected players must be members of this league.' });
    }

    await pool.query(
      `INSERT INTO scheduled_matches
        (league_id, tier_number, player1_id, player1_partner_id, player2_id, player2_partner_id)
       VALUES ($1, 1, $2, $3, $4, $5)`,
      [leagueId, player1Id, player1PartnerId || null, player2Id, player2PartnerId || null]
    );

    res.status(201).json({ message: 'Match added.' });
  } catch (err) {
    console.error('Add manual match error:', err);
    res.status(500).json({ error: 'Something went wrong adding the match.' });
  }
});

// ---------- REGENERATE SCHEDULE (host only) ----------
router.post('/:id/regenerate-schedule', async (req, res) => {
  const userId = req.userId;
  const leagueId = req.params.id;
  const { scheduleType, matchesPerPlayer } = req.body;

  try {
    const leagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [leagueId]);
    if (leagueResult.rows.length === 0) {
      return res.status(404).json({ error: 'League not found.' });
    }
    const league = leagueResult.rows[0];

    if (league.created_by !== userId) {
      return res.status(403).json({ error: 'Only the league host can regenerate the schedule.' });
    }

    if (scheduleType) {
      const validScheduleTypes = ['round_robin', 'matches_per_player', 'knockout', 'custom'];
      const finalScheduleType = validScheduleTypes.includes(scheduleType) ? scheduleType : 'round_robin';
      if (finalScheduleType === 'matches_per_player' && (!matchesPerPlayer || matchesPerPlayer < 1)) {
        return res.status(400).json({ error: 'Please specify how many matches each player should play.' });
      }
      if (finalScheduleType === 'knockout' && league.format !== 'singles') {
        return res.status(400).json({ error: 'Knockout format is currently only supported for singles leagues.' });
      }
      await pool.query(
        'UPDATE leagues SET schedule_type = $1, matches_per_player = $2 WHERE id = $3',
        [finalScheduleType, finalScheduleType === 'matches_per_player' ? matchesPerPlayer : null, leagueId]
      );
    }

    await pool.query(
      `DELETE FROM matches WHERE league_id = $1 AND status IN ('pending', 'rejected')`,
      [leagueId]
    );
    await pool.query(
      `UPDATE matches SET scheduled_match_id = NULL WHERE league_id = $1 AND status = 'confirmed'`,
      [leagueId]
    );
    await pool.query('DELETE FROM scheduled_matches WHERE league_id = $1', [leagueId]);
    await pool.query('DELETE FROM playoff_matches WHERE league_id = $1', [leagueId]);

    const refreshedLeagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [leagueId]);
    const refreshedLeague = refreshedLeagueResult.rows[0];

    if (refreshedLeague.schedule_type === 'custom') {
      return res.status(200).json({ message: 'Schedule cleared. Add matches manually.', matchCount: 0 });
    }
    if (refreshedLeague.schedule_type === 'knockout') {
      return generateKnockoutBracket(req, res, refreshedLeague);
    }

    const membersResult = await pool.query(
      `SELECT u.id, us.rating
       FROM league_members lm
       JOIN users u ON u.id = lm.user_id
       JOIN user_sports us ON us.user_id = u.id AND us.sport = $1 AND us.format = $2
       WHERE lm.league_id = $3
       ORDER BY us.rating DESC`,
      [refreshedLeague.sport, refreshedLeague.format, leagueId]
    );
    const members = membersResult.rows;

    const minPlayersRequired = refreshedLeague.format === 'doubles' ? 4 : 2;
    if (members.length < minPlayersRequired) {
      return res.status(400).json({
        error: refreshedLeague.format === 'doubles'
          ? 'Need at least 4 players to generate a doubles schedule.'
          : 'Need at least 2 players to generate a schedule.',
      });
    }

    let scheduledMatches = [];
    if (refreshedLeague.schedule_type === 'matches_per_player' && refreshedLeague.format === 'singles') {
      scheduledMatches = generateNearestRatingSchedule(members, refreshedLeague.matches_per_player);
    } else {
      scheduledMatches = generateRoundRobinSchedule(members, refreshedLeague.format);
    }

    for (const m of scheduledMatches) {
      await pool.query(
        `INSERT INTO scheduled_matches
          (league_id, tier_number, player1_id, player1_partner_id, player2_id, player2_partner_id)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [leagueId, m.tierNumber, m.player1Id, m.player1PartnerId, m.player2Id, m.player2PartnerId]
      );
    }

    res.status(201).json({ message: 'Schedule regenerated.', matchCount: scheduledMatches.length });
  } catch (err) {
    console.error('Regenerate schedule error:', err);
    res.status(500).json({ error: 'Something went wrong regenerating the schedule.' });
  }
});

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

function generateNearestRatingSchedule(members, matchesPerPlayer) {
  const n = members.length;
  const baseCount = Math.min(matchesPerPlayer, n - 1);

  const targetDegree = {};
  members.forEach((m) => (targetDegree[m.id] = baseCount));
  if ((n * baseCount) % 2 !== 0 && n > 0) {
    targetDegree[members[n - 1].id] = Math.max(0, baseCount - 1);
  }

  const matchCounts = {};
  const hasUp = {};
  const hasDown = {};
  members.forEach((m) => {
    matchCounts[m.id] = 0;
    hasUp[m.id] = false;
    hasDown[m.id] = false;
  });

  const pairsSet = new Set();
  const scheduledMatches = [];
  const pairKey = (a, b) => [a, b].sort((x, y) => x - y).join('-');
  const hasRoom = (p) => matchCounts[p.id] < targetDegree[p.id];

  function addMatch(a, b) {
    const key = pairKey(a.id, b.id);
    if (pairsSet.has(key)) return false;
    pairsSet.add(key);
    scheduledMatches.push({
      tierNumber: 1,
      player1Id: a.id,
      player1PartnerId: null,
      player2Id: b.id,
      player2PartnerId: null,
    });
    matchCounts[a.id]++;
    matchCounts[b.id]++;
    return true;
  }

  for (let i = 0; i < n; i++) {
    const player = members[i];
    if (hasUp[player.id] || !hasRoom(player)) continue;
    for (let j = i - 1; j >= 0; j--) {
      const candidate = members[j];
      if (!hasRoom(candidate)) continue;
      if (pairsSet.has(pairKey(player.id, candidate.id))) continue;
      if (addMatch(player, candidate)) {
        hasUp[player.id] = true;
        hasDown[candidate.id] = true;
        break;
      }
    }
  }

  for (let i = 0; i < n; i++) {
    const player = members[i];
    if (hasDown[player.id] || !hasRoom(player)) continue;
    for (let j = i + 1; j < n; j++) {
      const candidate = members[j];
      if (!hasRoom(candidate)) continue;
      if (pairsSet.has(pairKey(player.id, candidate.id))) continue;
      if (addMatch(player, candidate)) {
        hasDown[player.id] = true;
        hasUp[candidate.id] = true;
        break;
      }
    }
  }

  let progress = true;
  while (progress) {
    progress = false;
    const deficient = members.filter(hasRoom);
    if (deficient.length < 2) break;

    const pairs = [];
    for (let i = 0; i < deficient.length; i++) {
      for (let j = i + 1; j < deficient.length; j++) {
        const key = pairKey(deficient[i].id, deficient[j].id);
        if (pairsSet.has(key)) continue;
        pairs.push({
          a: deficient[i],
          b: deficient[j],
          distance: Math.abs(deficient[i].rating - deficient[j].rating),
        });
      }
    }
    if (pairs.length === 0) break;
    pairs.sort((p1, p2) => p1.distance - p2.distance);

    for (const pair of pairs) {
      if (hasRoom(pair.a) && hasRoom(pair.b)) {
        if (addMatch(pair.a, pair.b)) progress = true;
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
      `SELECT sm.id, sm.tier_number, sm.scheduled_time,
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

// ---------- EDIT LEAGUE PARAMETERS (host only) ----------
router.put('/:id', async (req, res) => {
  const userId = req.userId;
  const leagueId = req.params.id;
  const { name, area, seasonStart, seasonEnd, academyName, isPrivate, hostEntersScores } = req.body;

  try {
    const leagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [leagueId]);
    if (leagueResult.rows.length === 0) {
      return res.status(404).json({ error: 'League not found.' });
    }
    const league = leagueResult.rows[0];

    if (league.created_by !== userId) {
      return res.status(403).json({ error: 'Only the league host can edit this league.' });
    }

    const updates = [];
    const params = [];
    let idx = 1;

    if (name !== undefined) { updates.push(`name = $${idx++}`); params.push(name); }
    if (area !== undefined) { updates.push(`area = $${idx++}`); params.push(area); }
    if (seasonStart !== undefined) { updates.push(`season_start = $${idx++}`); params.push(seasonStart); }
    if (seasonEnd !== undefined) { updates.push(`season_end = $${idx++}`); params.push(seasonEnd); }
    if (academyName !== undefined) {
      updates.push(`academy_name = $${idx++}`);
      params.push(academyName && academyName.trim().length > 0 ? academyName.trim() : null);
    }

    if (hostEntersScores !== undefined) {
      const confirmedCount = await pool.query(
        `SELECT COUNT(*) FROM matches WHERE league_id = $1 AND status = 'confirmed'`,
        [leagueId]
      );
      if (parseInt(confirmedCount.rows[0].count, 10) > 0) {
        return res.status(400).json({ error: 'Cannot change scoring mode after matches have been confirmed.' });
      }
      updates.push(`host_enters_scores = $${idx++}`);
      params.push(hostEntersScores === true);
    }

    if (isPrivate !== undefined) {
      if (isPrivate === true && !league.join_code) {
        let joinCode;
        let unique = false;
        while (!unique) {
          joinCode = generateJoinCode();
          const existing = await pool.query('SELECT id FROM leagues WHERE join_code = $1', [joinCode]);
          if (existing.rows.length === 0) unique = true;
        }
        updates.push(`is_private = $${idx++}`); params.push(true);
        updates.push(`join_code = $${idx++}`); params.push(joinCode);
      } else {
        updates.push(`is_private = $${idx++}`); params.push(isPrivate === true);
      }
    }

    if (updates.length === 0) {
      return res.status(400).json({ error: 'No editable fields provided.' });
    }

    params.push(leagueId);
    const result = await pool.query(
      `UPDATE leagues SET ${updates.join(', ')} WHERE id = $${idx} RETURNING *`,
      params
    );

    res.status(200).json({ league: result.rows[0] });
  } catch (err) {
    console.error('Edit league error:', err);
    res.status(500).json({ error: 'Something went wrong updating the league.' });
  }
});

// ---------- EDIT AN UNPLAYED SCHEDULED MATCH (host only) ----------
router.put('/:id/schedule/:scheduledMatchId', async (req, res) => {
  const userId = req.userId;
  const { id: leagueId, scheduledMatchId } = req.params;
  const { player1Id, player1PartnerId, player2Id, player2PartnerId, scheduledTime } = req.body;

  if (!player1Id || !player2Id) {
    return res.status(400).json({ error: 'Please select both sides of the match.' });
  }

  try {
    const leagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [leagueId]);
    if (leagueResult.rows.length === 0) {
      return res.status(404).json({ error: 'League not found.' });
    }
    const league = leagueResult.rows[0];

    if (league.created_by !== userId) {
      return res.status(403).json({ error: 'Only the league host can edit the schedule.' });
    }

    const fixtureResult = await pool.query(
      'SELECT * FROM scheduled_matches WHERE id = $1 AND league_id = $2',
      [scheduledMatchId, leagueId]
    );
    if (fixtureResult.rows.length === 0) {
      return res.status(404).json({ error: 'Scheduled match not found.' });
    }

    const confirmedCheck = await pool.query(
      `SELECT id FROM matches WHERE scheduled_match_id = $1 AND status = 'confirmed' LIMIT 1`,
      [scheduledMatchId]
    );
    if (confirmedCheck.rows.length > 0) {
      return res.status(400).json({ error: 'This match has already been played and cannot be edited here. Edit the confirmed score instead.' });
    }

    if (league.format === 'doubles' && (!player1PartnerId || !player2PartnerId)) {
      return res.status(400).json({ error: 'Doubles matches need both partners selected.' });
    }
    if (league.format === 'singles' && (player1PartnerId || player2PartnerId)) {
      return res.status(400).json({ error: 'Singles matches should not have partners.' });
    }

    const allIds = [player1Id, player2Id, player1PartnerId, player2PartnerId].filter(Boolean);
    const memberCheck = await pool.query(
      `SELECT user_id FROM league_members WHERE league_id = $1 AND user_id = ANY($2::int[])`,
      [leagueId, allIds]
    );
    if (memberCheck.rows.length !== allIds.length) {
      return res.status(400).json({ error: 'All selected players must be members of this league.' });
    }

    await pool.query(
      `DELETE FROM matches WHERE scheduled_match_id = $1 AND status IN ('pending', 'rejected')`,
      [scheduledMatchId]
    );

    await pool.query(
      `UPDATE scheduled_matches SET player1_id = $1, player1_partner_id = $2, player2_id = $3, player2_partner_id = $4,
       scheduled_time = $5
       WHERE id = $6`,
      [player1Id, player1PartnerId || null, player2Id, player2PartnerId || null, scheduledTime || null, scheduledMatchId]
    );

    res.status(200).json({ message: 'Match updated.' });
  } catch (err) {
    console.error('Edit scheduled match error:', err);
    res.status(500).json({ error: 'Something went wrong updating the match.' });
  }
});

// ---------- DELETE AN UNPLAYED SCHEDULED MATCH (host only) ----------
router.delete('/:id/schedule/:scheduledMatchId', async (req, res) => {
  const userId = req.userId;
  const { id: leagueId, scheduledMatchId } = req.params;

  try {
    const leagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [leagueId]);
    if (leagueResult.rows.length === 0) {
      return res.status(404).json({ error: 'League not found.' });
    }
    const league = leagueResult.rows[0];

    if (league.created_by !== userId) {
      return res.status(403).json({ error: 'Only the league host can delete a scheduled match.' });
    }

    const confirmedCheck = await pool.query(
      `SELECT id FROM matches WHERE scheduled_match_id = $1 AND status = 'confirmed' LIMIT 1`,
      [scheduledMatchId]
    );
    if (confirmedCheck.rows.length > 0) {
      return res.status(400).json({ error: 'This match has already been played. Delete the confirmed score instead if needed.' });
    }

    await pool.query(
      `DELETE FROM matches WHERE scheduled_match_id = $1 AND status IN ('pending', 'rejected')`,
      [scheduledMatchId]
    );
    await pool.query('DELETE FROM scheduled_matches WHERE id = $1 AND league_id = $2', [scheduledMatchId, leagueId]);

    res.status(200).json({ message: 'Match removed from schedule.' });
  } catch (err) {
    console.error('Delete scheduled match error:', err);
    res.status(500).json({ error: 'Something went wrong deleting the match.' });
  }
});

module.exports = router;