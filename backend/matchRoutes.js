// matchRoutes.js
const express = require('express');
const router = express.Router();
const pool = require('./db');
const { calculateNewRatings } = require('./ratingEngine');

// Approximate real-world scale for each sport's rating system, used only to
// judge how "big" a rating gap is (as a fraction of the sport's typical
// range) when deciding league-points upset bonuses. Does not affect the
// actual rating engine at all.
const SPORT_RATING_RANGES = {
  badminton: 7000,
  tennis: 15.5,
  table_tennis: 2300,
  pickleball: 6.0,
};

async function getRating(userId, sport, format) {
  const result = await pool.query(
    'SELECT rating FROM user_sports WHERE user_id = $1 AND sport = $2 AND format = $3',
    [userId, sport, format]
  );
  if (result.rows.length === 0) return null;
  return parseFloat(result.rows[0].rating);
}

async function updateRating(userId, sport, format, newRating, won) {
  if (sport === 'table_tennis') {
    await pool.query(
      `UPDATE user_sports SET rating = $1, matches_played = matches_played + 1,
       wins = wins + $2, losses = losses + $3
       WHERE user_id = $4 AND sport = $5`,
      [newRating, won ? 1 : 0, won ? 0 : 1, userId, sport]
    );
  } else {
    await pool.query(
      `UPDATE user_sports SET rating = $1, matches_played = matches_played + 1,
       wins = wins + $2, losses = losses + $3
       WHERE user_id = $4 AND sport = $5 AND format = $6`,
      [newRating, won ? 1 : 0, won ? 0 : 1, userId, sport, format]
    );
  }
}

// League Points: base 2 for a win. If the winner was rated LOWER than the
// loser going in (a genuine upset), add a bonus scaled to how big that gap
// was — a small upset earns +1, a big one earns +2. Beating someone rated
// lower (an expected win) earns no upset bonus at all. A dominant win
// (didn't drop a single set/game) adds +1 on top, regardless of the above.
function calculateLeaguePoints(sport, winnerRating, loserRating, setScores, winnerWonTeam1) {
  let points = 2;

  if (winnerRating != null && loserRating != null && winnerRating < loserRating) {
    const range = SPORT_RATING_RANGES[sport] || 1;
    const gapFraction = (loserRating - winnerRating) / range;
    points += gapFraction > 0.15 ? 2 : 1;
  }

  try {
    const sets = JSON.parse(setScores);
    const wonEverySet = sets.length > 0 && sets.every((s) => {
      const winnerScore = winnerWonTeam1 ? s.me : s.opponent;
      const loserScore = winnerWonTeam1 ? s.opponent : s.me;
      return winnerScore > loserScore;
    });
    if (wonEverySet) points += 1;
  } catch (err) {
    // if parsing fails, just skip the dominant-win bonus
  }

  return points;
}

async function awardLeaguePoints(leagueId, winnerId, points) {
  await pool.query(
    'UPDATE league_members SET points = points + $1 WHERE league_id = $2 AND user_id = $3',
    [points, leagueId, winnerId]
  );
}

async function findMatchingFixture(leagueId, team1Ids, team2Ids) {
  const result = await pool.query(
    'SELECT id, player1_id, player1_partner_id, player2_id, player2_partner_id FROM scheduled_matches WHERE league_id = $1',
    [leagueId]
  );

  const sortedTeam1 = [...team1Ids].filter(Boolean).sort((a, b) => a - b);
  const sortedTeam2 = [...team2Ids].filter(Boolean).sort((a, b) => a - b);

  for (const fixture of result.rows) {
    const fixtureTeamA = [fixture.player1_id, fixture.player1_partner_id]
      .filter(Boolean)
      .sort((a, b) => a - b);
    const fixtureTeamB = [fixture.player2_id, fixture.player2_partner_id]
      .filter(Boolean)
      .sort((a, b) => a - b);

    const sameSet = (a, b) => a.length === b.length && a.every((val, i) => val === b[i]);

    const straightMatch = sameSet(sortedTeam1, fixtureTeamA) && sameSet(sortedTeam2, fixtureTeamB);
    const swappedMatch = sameSet(sortedTeam1, fixtureTeamB) && sameSet(sortedTeam2, fixtureTeamA);

    if (straightMatch || swappedMatch) {
      return fixture.id;
    }
  }

  return null;
}

async function finalizeMatch(match, league) {
  const { sport, format } = league;

  const rating1a = await getRating(match.player1_id, sport, format);
  const rating2a = await getRating(match.player2_id, sport, format);
  const rating1b = match.player1_partner_id ? await getRating(match.player1_partner_id, sport, format) : null;
  const rating2b = match.player2_partner_id ? await getRating(match.player2_partner_id, sport, format) : null;

  const team1Rating = rating1b != null ? (rating1a + rating1b) / 2 : rating1a;
  const team2Rating = rating2b != null ? (rating2a + rating2b) / 2 : rating2a;

  const team1Won = match.winner_id === match.player1_id;

  const { newRating1, newRating2 } = calculateNewRatings(
    sport, team1Rating, team2Rating, team1Won, match.player1_units, match.player2_units
  );

  const change1 = newRating1 - team1Rating;
  const change2 = newRating2 - team2Rating;

  const applyChange = async (playerId, individualRating, change, won) => {
    if (individualRating == null) return null;
    const updated = Math.round((individualRating + change) * 10) / 10;
    const actualChange = Math.round((updated - individualRating) * 100) / 100;
    await updateRating(playerId, sport, format, updated, won);
    return actualChange;
  };

  const player1RatingChange = await applyChange(match.player1_id, rating1a, change1, team1Won);
  const player2RatingChange = await applyChange(match.player2_id, rating2a, change2, !team1Won);
  const player1PartnerRatingChange = await applyChange(match.player1_partner_id, rating1b, change1, team1Won);
  const player2PartnerRatingChange = await applyChange(match.player2_partner_id, rating2b, change2, !team1Won);

  await pool.query(
    `UPDATE matches SET status = 'confirmed',
      player1_rating_change = $1, player2_rating_change = $2,
      player1_partner_rating_change = $3, player2_partner_rating_change = $4
     WHERE id = $5`,
    [player1RatingChange, player2RatingChange, player1PartnerRatingChange, player2PartnerRatingChange, match.id]
  );

  // League points, based on the PRE-MATCH ratings (team1Rating/team2Rating),
  // so an upset is judged on who was actually favored going in.
  const winnerRating = team1Won ? team1Rating : team2Rating;
  const loserRating = team1Won ? team2Rating : team1Rating;
  const points = calculateLeaguePoints(sport, winnerRating, loserRating, match.set_scores, team1Won);

  await awardLeaguePoints(match.league_id, match.winner_id, points);
  if (match.winner_id === match.player1_id && match.player1_partner_id) {
    await awardLeaguePoints(match.league_id, match.player1_partner_id, points);
  }
  if (match.winner_id === match.player2_id && match.player2_partner_id) {
    await awardLeaguePoints(match.league_id, match.player2_partner_id, points);
  }
}

// ---------- REPORT A MATCH (self, needs opponent confirmation) ----------
router.post('/report', async (req, res) => {
  const userId = req.userId;
  const {
    leagueId,
    opponentId,
    partnerId,
    opponentPartnerId,
    myUnits,
    opponentUnits,
    iWon,
    setScores,
  } = req.body;

  if (!leagueId || !opponentId || myUnits == null || opponentUnits == null || iWon == null) {
    return res.status(400).json({ error: 'Missing required fields.' });
  }

  try {
    const leagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [leagueId]);
    if (leagueResult.rows.length === 0) {
      return res.status(404).json({ error: 'League not found.' });
    }
    const league = leagueResult.rows[0];

    if (league.host_enters_scores) {
      return res.status(403).json({ error: 'This league requires the host to enter all scores.' });
    }

    if (league.format === 'doubles' && (!partnerId || !opponentPartnerId)) {
      return res.status(400).json({ error: 'Doubles matches need a partner and opponent partner.' });
    }
    if (league.format === 'singles' && (partnerId || opponentPartnerId)) {
      return res.status(400).json({ error: 'Singles matches should not have partners.' });
    }

    const winnerId = iWon ? userId : opponentId;

    const scheduledMatchId = await findMatchingFixture(
      leagueId,
      [userId, partnerId],
      [opponentId, opponentPartnerId]
    );

    const scheduleExists = await pool.query(
      'SELECT id FROM scheduled_matches WHERE league_id = $1 LIMIT 1',
      [leagueId]
    );
    if (scheduleExists.rows.length > 0 && scheduledMatchId === null) {
      return res.status(400).json({
        error: 'This matchup isn\'t part of the generated schedule. Report matches against your scheduled opponents only.',
      });
    }

    if (scheduledMatchId !== null) {
      const alreadyConfirmed = await pool.query(
        `SELECT id FROM matches WHERE scheduled_match_id = $1 AND status = 'confirmed' LIMIT 1`,
        [scheduledMatchId]
      );
      if (alreadyConfirmed.rows.length > 0) {
        return res.status(409).json({ error: 'This scheduled match has already been completed.' });
      }

      await pool.query(
        `DELETE FROM matches WHERE scheduled_match_id = $1 AND status IN ('pending', 'rejected')`,
        [scheduledMatchId]
      );
    }

    const result = await pool.query(
      `INSERT INTO matches
        (league_id, player1_id, player1_partner_id, player2_id, player2_partner_id,
         player1_units, player2_units, winner_id, reported_by, status, format, set_scores, scheduled_match_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'pending', $10, $11, $12)
       RETURNING *`,
      [
        leagueId,
        userId,
        partnerId || null,
        opponentId,
        opponentPartnerId || null,
        myUnits,
        opponentUnits,
        winnerId,
        userId,
        league.format,
        JSON.stringify(setScores || []),
        scheduledMatchId,
      ]
    );

    res.status(201).json({ match: result.rows[0] });
  } catch (err) {
    console.error('Report match error:', err);
    res.status(500).json({ error: 'Something went wrong reporting the match.' });
  }
});

// ---------- HOST ENTERS A MATCH SCORE DIRECTLY (auto-confirmed) ----------
router.post('/report-as-host', async (req, res) => {
  const userId = req.userId;
  const {
    leagueId,
    player1Id,
    player1PartnerId,
    player2Id,
    player2PartnerId,
    player1Units,
    player2Units,
    player1Won,
    setScores,
  } = req.body;

  if (!leagueId || !player1Id || !player2Id || player1Units == null || player2Units == null || player1Won == null) {
    return res.status(400).json({ error: 'Missing required fields.' });
  }

  try {
    const leagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [leagueId]);
    if (leagueResult.rows.length === 0) {
      return res.status(404).json({ error: 'League not found.' });
    }
    const league = leagueResult.rows[0];

    if (!league.host_enters_scores || league.created_by !== userId) {
      return res.status(403).json({ error: 'Only the host can enter scores directly for this league.' });
    }

    const winnerId = player1Won ? player1Id : player2Id;

    const scheduledMatchId = await findMatchingFixture(
      leagueId,
      [player1Id, player1PartnerId],
      [player2Id, player2PartnerId]
    );

    if (scheduledMatchId === null) {
      return res.status(400).json({ error: 'This matchup is not part of the generated schedule.' });
    }

    const alreadyConfirmed = await pool.query(
      `SELECT id FROM matches WHERE scheduled_match_id = $1 AND status = 'confirmed' LIMIT 1`,
      [scheduledMatchId]
    );
    if (alreadyConfirmed.rows.length > 0) {
      return res.status(409).json({ error: 'This scheduled match has already been completed.' });
    }

    const result = await pool.query(
      `INSERT INTO matches
        (league_id, player1_id, player1_partner_id, player2_id, player2_partner_id,
         player1_units, player2_units, winner_id, reported_by, status, format, set_scores, scheduled_match_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'confirmed', $10, $11, $12)
       RETURNING *`,
      [
        leagueId,
        player1Id,
        player1PartnerId || null,
        player2Id,
        player2PartnerId || null,
        player1Units,
        player2Units,
        winnerId,
        userId,
        league.format,
        JSON.stringify(setScores || []),
        scheduledMatchId,
      ]
    );

    const match = result.rows[0];
    await finalizeMatch(match, league);

    res.status(201).json({ match });
  } catch (err) {
    console.error('Host report match error:', err);
    res.status(500).json({ error: 'Something went wrong entering the score.' });
  }
});

// ---------- GET MATCHES AWAITING MY CONFIRMATION ----------
router.get('/pending', async (req, res) => {
  const userId = req.userId;

  try {
    const result = await pool.query(
      `SELECT m.*, l.sport, l.format as league_format,
              p1.username as player1_username, p1.phone_number as player1_phone,
              p2.username as player2_username, p2.phone_number as player2_phone,
              pp1.username as player1_partner_username, pp1.phone_number as player1_partner_phone,
              pp2.username as player2_partner_username, pp2.phone_number as player2_partner_phone
       FROM matches m
       JOIN leagues l ON l.id = m.league_id
       JOIN users p1 ON p1.id = m.player1_id
       JOIN users p2 ON p2.id = m.player2_id
       LEFT JOIN users pp1 ON pp1.id = m.player1_partner_id
       LEFT JOIN users pp2 ON pp2.id = m.player2_partner_id
       WHERE m.status = 'pending'
         AND m.reported_by != $1
         AND (m.player2_id = $1 OR m.player2_partner_id = $1 OR m.player1_id = $1 OR m.player1_partner_id = $1)
       ORDER BY m.created_at DESC`,
      [userId]
    );
    res.status(200).json({ matches: result.rows });
  } catch (err) {
    console.error('Get pending matches error:', err);
    res.status(500).json({ error: 'Something went wrong fetching pending matches.' });
  }
});

// ---------- UPCOMING SCHEDULED MATCHES (across all leagues) ----------
router.get('/upcoming', async (req, res) => {
  const userId = req.userId;

  try {
    const result = await pool.query(
      `SELECT sm.id, sm.tier_number,
              l.id as league_id, l.sport, l.area, l.format,
              p1.username as player1_username, pp1.username as player1_partner_username,
              p2.username as player2_username, pp2.username as player2_partner_username,
              sm.player1_id, sm.player1_partner_id, sm.player2_id, sm.player2_partner_id
       FROM scheduled_matches sm
       JOIN leagues l ON l.id = sm.league_id
       LEFT JOIN matches m ON m.scheduled_match_id = sm.id AND m.status = 'confirmed'
       JOIN users p1 ON p1.id = sm.player1_id
       JOIN users p2 ON p2.id = sm.player2_id
       LEFT JOIN users pp1 ON pp1.id = sm.player1_partner_id
       LEFT JOIN users pp2 ON pp2.id = sm.player2_partner_id
       WHERE m.id IS NULL
         AND (sm.player1_id = $1 OR sm.player1_partner_id = $1 OR sm.player2_id = $1 OR sm.player2_partner_id = $1)
       ORDER BY l.season_end ASC
       LIMIT 10`,
      [userId]
    );
    res.status(200).json({ upcoming: result.rows });
  } catch (err) {
    console.error('Get upcoming matches error:', err);
    res.status(500).json({ error: 'Something went wrong fetching upcoming matches.' });
  }
});

// ---------- MY FULL MATCH HISTORY (across all leagues) ----------
router.get('/history', async (req, res) => {
  const userId = req.userId;

  try {
    const result = await pool.query(
      `SELECT m.id, m.player1_id, m.player2_id, m.player1_partner_id, m.player2_partner_id,
              m.player1_units, m.player2_units, m.set_scores, m.winner_id, m.created_at,
              m.player1_rating_change, m.player2_rating_change,
              m.player1_partner_rating_change, m.player2_partner_rating_change,
              l.sport, l.format as league_format, l.area,
              p1.username as player1_username, p2.username as player2_username,
              pp1.username as player1_partner_username, pp2.username as player2_partner_username
       FROM matches m
       JOIN leagues l ON l.id = m.league_id
       JOIN users p1 ON p1.id = m.player1_id
       JOIN users p2 ON p2.id = m.player2_id
       LEFT JOIN users pp1 ON pp1.id = m.player1_partner_id
       LEFT JOIN users pp2 ON pp2.id = m.player2_partner_id
       WHERE m.status = 'confirmed'
         AND (m.player1_id = $1 OR m.player2_id = $1 OR m.player1_partner_id = $1 OR m.player2_partner_id = $1)
       ORDER BY m.created_at DESC`,
      [userId]
    );
    res.status(200).json({ matches: result.rows });
  } catch (err) {
    console.error('Match history error:', err);
    res.status(500).json({ error: 'Something went wrong fetching match history.' });
  }
});

// ---------- CONFIRM A MATCH ----------
router.post('/:id/confirm', async (req, res) => {
  const userId = req.userId;
  const matchId = req.params.id;

  try {
    const matchResult = await pool.query('SELECT * FROM matches WHERE id = $1', [matchId]);
    if (matchResult.rows.length === 0) {
      return res.status(404).json({ error: 'Match not found.' });
    }
    const match = matchResult.rows[0];

    if (match.status !== 'pending') {
      return res.status(409).json({ error: 'This match has already been processed.' });
    }

    const participants = [match.player1_id, match.player1_partner_id, match.player2_id, match.player2_partner_id];
    if (!participants.includes(userId)) {
      return res.status(403).json({ error: 'You are not part of this match.' });
    }
    if (userId === match.reported_by) {
      return res.status(400).json({ error: 'You cannot confirm your own report.' });
    }

    const leagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [match.league_id]);
    const league = leagueResult.rows[0];

    await finalizeMatch(match, league);

    res.status(200).json({ message: 'Match confirmed and ratings updated.' });
  } catch (err) {
    console.error('Confirm match error:', err);
    res.status(500).json({ error: 'Something went wrong confirming the match.' });
  }
});

// ---------- REJECT A MATCH ----------
router.post('/:id/reject', async (req, res) => {
  const userId = req.userId;
  const matchId = req.params.id;

  try {
    const matchResult = await pool.query('SELECT * FROM matches WHERE id = $1', [matchId]);
    if (matchResult.rows.length === 0) {
      return res.status(404).json({ error: 'Match not found.' });
    }
    const match = matchResult.rows[0];

    if (match.status !== 'pending') {
      return res.status(409).json({ error: 'This match has already been processed.' });
    }

    const participants = [match.player1_id, match.player1_partner_id, match.player2_id, match.player2_partner_id];
    if (!participants.includes(userId)) {
      return res.status(403).json({ error: 'You are not part of this match.' });
    }
    if (userId === match.reported_by) {
      return res.status(400).json({ error: 'You cannot reject your own report.' });
    }

    await pool.query(`UPDATE matches SET status = 'rejected' WHERE id = $1`, [matchId]);

    res.status(200).json({ message: 'Match report rejected. It can be reported again with the correct score.' });
  } catch (err) {
    console.error('Reject match error:', err);
    res.status(500).json({ error: 'Something went wrong rejecting the match.' });
  }
});

module.exports = router;