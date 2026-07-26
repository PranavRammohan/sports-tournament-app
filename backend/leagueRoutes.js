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

async function checkRatingEligibility(league, userId) {
  if (league.min_rating == null && league.max_rating == null) {
    return null;
  }

  const ratingResult = await pool.query(
    'SELECT rating FROM user_sports WHERE user_id = $1 AND sport = $2 AND format = $3',
    [userId, league.sport, league.format]
  );
  if (ratingResult.rows.length === 0) {
    return 'You need to add this sport to your profile before joining.';
  }

  const rating = parseFloat(ratingResult.rows[0].rating);
  if (league.min_rating != null && rating < parseFloat(league.min_rating)) {
    return `This league requires a rating of at least ${league.min_rating}. Your current rating is ${rating}.`;
  }
  if (league.max_rating != null && rating > parseFloat(league.max_rating)) {
    return `This league requires a rating of at most ${league.max_rating}. Your current rating is ${rating}.`;
  }
  return null;
}

function checkRegistrationWindow(league) {
  const now = new Date();

  if (league.registration_start != null) {
    const start = new Date(league.registration_start);
    if (now < start) {
      return `Registration opens on ${start.toLocaleString()}.`;
    }
  }
  if (league.registration_end != null) {
    const end = new Date(league.registration_end);
    if (now > end) {
      return `Registration closed on ${end.toLocaleString()}.`;
    }
  }
  return null;
}

const VALID_PARTNER_MODES = ['host_auto', 'self_select', 'host_manual'];

// ---------- CREATE LEAGUE ----------
router.post('/create', async (req, res) => {
  const userId = req.userId;
  const {
    name, sport, area, seasonStart, seasonEnd, format, genderCategory,
    scheduleType, matchesPerPlayer, hostEntersScores, hostPlays, isPrivate, academyName,
    minRating, maxRating, registrationStart, registrationEnd, partnerMode,
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

  const finalPartnerMode = VALID_PARTNER_MODES.includes(partnerMode) ? partnerMode : 'host_auto';

  const validScheduleTypes = ['round_robin', 'matches_per_player', 'knockout', 'custom'];
  const finalScheduleType = validScheduleTypes.includes(scheduleType) ? scheduleType : 'round_robin';

  if (finalScheduleType === 'matches_per_player' && (!matchesPerPlayer || matchesPerPlayer < 1)) {
    return res.status(400).json({ error: 'Please specify how many matches each player should play.' });
  }
  // NOTE: Knockout is now supported for doubles as well as singles — the
  // singles-only restriction has been removed. (Fixed-matches-per-player
  // was already available to both formats via the schedule generator.)

  if (minRating != null && maxRating != null && parseFloat(minRating) > parseFloat(maxRating)) {
    return res.status(400).json({ error: 'Minimum rating cannot be higher than maximum rating.' });
  }

  if (registrationStart != null && registrationEnd != null &&
      new Date(registrationStart) > new Date(registrationEnd)) {
    return res.status(400).json({ error: 'Registration start must be before registration end.' });
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
                            schedule_type, matches_per_player, host_enters_scores, is_private, join_code, academy_name,
                            min_rating, max_rating, registration_start, registration_end, partner_mode)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, $11, $12, $13, $14, $15, $16, $17, $18, $19)
       RETURNING id, name, sport, area, season_start, season_end, format, gender_category, created_by,
                 schedule_type, matches_per_player, host_enters_scores, is_private, join_code, academy_name,
                 min_rating, max_rating, registration_start, registration_end, partner_mode`,
      [
        name, sport, area, seasonStart, seasonEnd, userId, format, genderCategory,
        finalScheduleType, finalScheduleType === 'matches_per_player' ? matchesPerPlayer : null,
        hostEntersScores === true, isPrivate === true, joinCode,
        academyName && academyName.trim().length > 0 ? academyName.trim() : null,
        minRating != null ? parseFloat(minRating) : null,
        maxRating != null ? parseFloat(maxRating) : null,
        registrationStart || null,
        registrationEnd || null,
        format === 'doubles' ? finalPartnerMode : 'host_auto',
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
  const { area, format, sport } = req.query;

  try {
    const userResult = await pool.query('SELECT gender FROM users WHERE id = $1', [userId]);
    if (userResult.rows.length === 0) {
      return res.status(404).json({ error: 'User not found.' });
    }
    const userGenderCategory = userResult.rows[0].gender === 'M' ? 'mens' : 'womens';

    let query = `
      SELECT l.id, l.name, l.sport, l.area, l.season_start, l.season_end, l.format, l.gender_category,
             l.schedule_type, l.matches_per_player, l.host_enters_scores, l.is_private, l.academy_name,
             l.min_rating, l.max_rating, l.registration_start, l.registration_end, l.partner_mode,
             COUNT(lm.id) AS member_count,
             EXISTS (
               SELECT 1 FROM league_members lm2 WHERE lm2.league_id = l.id AND lm2.user_id = $1
             ) AS is_member
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
      // Accepts either a single area or a comma-separated list, so the
      // Browse Tournaments screen can filter by multiple areas at once.
      const areaList = String(area)
        .split(',')
        .map((a) => a.trim())
        .filter(Boolean);
      if (areaList.length > 0) {
        params.push(areaList);
        query += ` AND l.area = ANY($${params.length}::text[])`;
      }
    }
    if (format) {
      params.push(format);
      query += ` AND l.format = $${params.length}`;
    }
    if (sport) {
      params.push(sport);
      query += ` AND l.sport = $${params.length}`;
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
              l.min_rating, l.max_rating, l.registration_start, l.registration_end, l.partner_mode,
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

    const registrationError = checkRegistrationWindow(leagueData);
    if (registrationError) {
      return res.status(403).json({ error: registrationError });
    }

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

    const ratingError = await checkRatingEligibility(leagueData, userId);
    if (ratingError) {
      return res.status(403).json({ error: ratingError });
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

    const registrationError = checkRegistrationWindow(leagueData);
    if (registrationError) {
      return res.status(403).json({ error: registrationError });
    }

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

    const ratingError = await checkRatingEligibility(leagueData, userId);
    if (ratingError) {
      return res.status(403).json({ error: ratingError });
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

// ---------- SELF-SELECT PARTNER: send a partner request ----------
// Only valid when the league's partner_mode is 'self_select'. The requester
// must already be a member with no confirmed partner. Creates a pending
// invite; the target must accept via /respond-partner before it's locked in.
router.post('/:id/select-partner', async (req, res) => {
  const userId = req.userId;
  const leagueId = req.params.id;
  const { partnerId } = req.body;

  if (!partnerId) {
    return res.status(400).json({ error: 'Please choose a partner.' });
  }
  if (parseInt(partnerId, 10) === userId) {
    return res.status(400).json({ error: 'You cannot partner with yourself.' });
  }

  try {
    const leagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [leagueId]);
    if (leagueResult.rows.length === 0) {
      return res.status(404).json({ error: 'League not found.' });
    }
    const league = leagueResult.rows[0];

    if (league.format !== 'doubles') {
      return res.status(400).json({ error: 'Partner selection only applies to doubles leagues.' });
    }
    if (league.partner_mode !== 'self_select') {
      return res.status(400).json({ error: 'This league does not allow players to pick their own partner.' });
    }

    const myMembership = await pool.query(
      'SELECT * FROM league_members WHERE league_id = $1 AND user_id = $2',
      [leagueId, userId]
    );
    if (myMembership.rows.length === 0) {
      return res.status(403).json({ error: 'You must join the league before selecting a partner.' });
    }
    if (myMembership.rows[0].partner_status === 'confirmed') {
      return res.status(409).json({ error: 'You already have a confirmed partner.' });
    }

    const partnerMembership = await pool.query(
      'SELECT * FROM league_members WHERE league_id = $1 AND user_id = $2',
      [leagueId, partnerId]
    );
    if (partnerMembership.rows.length === 0) {
      return res.status(400).json({ error: 'That player has not joined this league yet.' });
    }
    if (partnerMembership.rows[0].partner_status === 'confirmed') {
      return res.status(409).json({ error: 'That player already has a confirmed partner.' });
    }

    await pool.query(
      `UPDATE league_members SET partner_id = $1, partner_status = 'pending'
       WHERE league_id = $2 AND user_id = $3`,
      [partnerId, leagueId, userId]
    );

    res.status(200).json({ message: 'Partner request sent. Waiting for them to accept.' });
  } catch (err) {
    console.error('Select partner error:', err);
    res.status(500).json({ error: 'Something went wrong sending the partner request.' });
  }
});

// ---------- SELF-SELECT PARTNER: respond to a pending request ----------
router.post('/:id/respond-partner', async (req, res) => {
  const userId = req.userId;
  const leagueId = req.params.id;
  const { accept } = req.body;

  try {
    const requestResult = await pool.query(
      `SELECT * FROM league_members WHERE league_id = $1 AND partner_id = $2 AND partner_status = 'pending'`,
      [leagueId, userId]
    );
    if (requestResult.rows.length === 0) {
      return res.status(404).json({ error: 'No pending partner request found for you in this league.' });
    }
    const requesterId = requestResult.rows[0].user_id;

    if (accept !== true) {
      await pool.query(
        `UPDATE league_members SET partner_id = NULL, partner_status = NULL
         WHERE league_id = $1 AND user_id = $2`,
        [leagueId, requesterId]
      );
      return res.status(200).json({ message: 'Partner request declined.' });
    }

    await pool.query(
      `UPDATE league_members SET partner_id = $1, partner_status = 'confirmed'
       WHERE league_id = $2 AND user_id = $3`,
      [requesterId, leagueId, userId]
    );
    await pool.query(
      `UPDATE league_members SET partner_status = 'confirmed'
       WHERE league_id = $1 AND user_id = $2`,
      [leagueId, requesterId]
    );

    res.status(200).json({ message: 'Partner confirmed!' });
  } catch (err) {
    console.error('Respond partner error:', err);
    res.status(500).json({ error: 'Something went wrong responding to the partner request.' });
  }
});

// ---------- HOST-MANUAL PARTNER ASSIGNMENT (host only) ----------
router.post('/:id/assign-partner', async (req, res) => {
  const userId = req.userId;
  const leagueId = req.params.id;
  const { player1Id, player2Id } = req.body;

  if (!player1Id || !player2Id || player1Id === player2Id) {
    return res.status(400).json({ error: 'Please select two different players to pair.' });
  }

  try {
    const leagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [leagueId]);
    if (leagueResult.rows.length === 0) {
      return res.status(404).json({ error: 'League not found.' });
    }
    const league = leagueResult.rows[0];

    if (league.created_by !== userId) {
      return res.status(403).json({ error: 'Only the league host can assign partners.' });
    }
    if (league.format !== 'doubles' || league.partner_mode !== 'host_manual') {
      return res.status(400).json({ error: 'This league is not set up for host-manual partner assignment.' });
    }

    const membersResult = await pool.query(
      `SELECT user_id, partner_status FROM league_members WHERE league_id = $1 AND user_id = ANY($2::int[])`,
      [leagueId, [player1Id, player2Id]]
    );
    if (membersResult.rows.length !== 2) {
      return res.status(400).json({ error: 'Both players must be members of this league.' });
    }
    if (membersResult.rows.some((m) => m.partner_status === 'confirmed')) {
      return res.status(409).json({ error: 'One of these players already has a confirmed partner. Unpair them first.' });
    }

    await pool.query(
      `UPDATE league_members SET partner_id = $1, partner_status = 'confirmed'
       WHERE league_id = $2 AND user_id = $3`,
      [player2Id, leagueId, player1Id]
    );
    await pool.query(
      `UPDATE league_members SET partner_id = $1, partner_status = 'confirmed'
       WHERE league_id = $2 AND user_id = $3`,
      [player1Id, leagueId, player2Id]
    );

    res.status(200).json({ message: 'Partners paired.' });
  } catch (err) {
    console.error('Assign partner error:', err);
    res.status(500).json({ error: 'Something went wrong pairing these players.' });
  }
});

// ---------- UNPAIR (self, or host for any pair) ----------
router.post('/:id/unpair', async (req, res) => {
  const userId = req.userId;
  const leagueId = req.params.id;
  const { userId: targetUserId } = req.body;

  try {
    const leagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [leagueId]);
    if (leagueResult.rows.length === 0) {
      return res.status(404).json({ error: 'League not found.' });
    }
    const league = leagueResult.rows[0];
    const isHost = league.created_by === userId;
    const subjectId = isHost && targetUserId ? targetUserId : userId;

    if (!isHost && subjectId !== userId) {
      return res.status(403).json({ error: 'You can only unpair yourself.' });
    }

    const memberResult = await pool.query(
      'SELECT * FROM league_members WHERE league_id = $1 AND user_id = $2',
      [leagueId, subjectId]
    );
    if (memberResult.rows.length === 0 || memberResult.rows[0].partner_id == null) {
      return res.status(404).json({ error: 'No partner pairing found to remove.' });
    }
    const partnerId = memberResult.rows[0].partner_id;

    await pool.query(
      `UPDATE league_members SET partner_id = NULL, partner_status = NULL
       WHERE league_id = $1 AND user_id = $2`,
      [leagueId, subjectId]
    );
    await pool.query(
      `UPDATE league_members SET partner_id = NULL, partner_status = NULL
       WHERE league_id = $1 AND user_id = $2`,
      [leagueId, partnerId]
    );

    res.status(200).json({ message: 'Partnership removed.' });
  } catch (err) {
    console.error('Unpair error:', err);
    res.status(500).json({ error: 'Something went wrong removing the partnership.' });
  }
});

// ---------- GET PARTNER STATUS LIST (for self-select/host-manual UI) ----------
router.get('/:id/partners', async (req, res) => {
  const leagueId = req.params.id;

  try {
    const leagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [leagueId]);
    if (leagueResult.rows.length === 0) {
      return res.status(404).json({ error: 'League not found.' });
    }
    const league = leagueResult.rows[0];

    const result = await pool.query(
      `SELECT u.id, u.username, lm.partner_id, lm.partner_status, p.username as partner_username
       FROM league_members lm
       JOIN users u ON u.id = lm.user_id
       LEFT JOIN users p ON p.id = lm.partner_id
       WHERE lm.league_id = $1
       ORDER BY u.username ASC`,
      [leagueId]
    );

    res.status(200).json({ partnerMode: league.partner_mode, members: result.rows });
  } catch (err) {
    console.error('Get partners error:', err);
    res.status(500).json({ error: 'Something went wrong fetching partner status.' });
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

    const memberResult = await pool.query(
      'SELECT * FROM league_members WHERE league_id = $1 AND user_id = $2',
      [leagueId, userId]
    );
    if (memberResult.rows.length === 0) {
      return res.status(404).json({ error: "You aren't a member of this league." });
    }
    const partnerId = memberResult.rows[0].partner_id;

    await pool.query('DELETE FROM league_members WHERE league_id = $1 AND user_id = $2', [leagueId, userId]);

    if (partnerId) {
      await pool.query(
        `UPDATE league_members SET partner_id = NULL, partner_status = NULL
         WHERE league_id = $1 AND user_id = $2`,
        [leagueId, partnerId]
      );
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
      'SELECT * FROM league_members WHERE league_id = $1 AND user_id = $2',
      [leagueId, targetUserId]
    );
    if (memberCheck.rows.length === 0) {
      return res.status(404).json({ error: 'This player is not a member of this league.' });
    }
    const partnerId = memberCheck.rows[0].partner_id;

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
         AND (player1_id = $2 OR player2_id = $2 OR player1_partner_id = $2 OR player2_partner_id = $2)`,
      [leagueId, targetUserId]
    );

    await pool.query(
      'DELETE FROM league_members WHERE league_id = $1 AND user_id = $2',
      [leagueId, targetUserId]
    );

    if (partnerId) {
      await pool.query(
        `UPDATE league_members SET partner_id = NULL, partner_status = NULL
         WHERE league_id = $1 AND user_id = $2`,
        [leagueId, partnerId]
      );
    }

    res.status(200).json({ message: 'Player removed from league.' });
  } catch (err) {
    console.error('Remove player error:', err);
    res.status(500).json({ error: 'Something went wrong removing the player.' });
  }
});

// ---------- LEAGUE DETAIL + LEADERBOARD(S) ----------
// For doubles leagues, also returns a `pairLeaderboard`, grouping confirmed
// matches (round-robin/custom + knockout) by unordered partner pair.
router.get('/:id', async (req, res) => {
  const leagueId = req.params.id;

  try {
    const league = await pool.query(
      `SELECT l.*, u.username as host_username, u.phone_number as host_phone
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
           UNION ALL
           SELECT id, league_id, winner_id, player1_id AS player_id FROM playoff_matches WHERE status = 'confirmed'
           UNION ALL
           SELECT id, league_id, winner_id, player2_id AS player_id FROM playoff_matches WHERE status = 'confirmed'
           UNION ALL
           SELECT id, league_id, winner_id, player1_partner_id AS player_id FROM playoff_matches WHERE status = 'confirmed' AND player1_partner_id IS NOT NULL
           UNION ALL
           SELECT id, league_id, winner_id, player2_partner_id AS player_id FROM playoff_matches WHERE status = 'confirmed' AND player2_partner_id IS NOT NULL
         ) all_participants
         WHERE league_id = $3
         GROUP BY player_id
       ) match_stats ON match_stats.player_id = u.id
       WHERE lm.league_id = $3
       ORDER BY lm.points DESC, us.rating DESC`,
      [leagueData.sport, leagueData.format, leagueId]
    );

    let pairLeaderboard = null;
    if (leagueData.format === 'doubles') {
      const pairResult = await pool.query(
        `SELECT p_a AS player_a_id, p_b AS player_b_id,
                ua.username AS player_a_username, ub.username AS player_b_username,
                COUNT(*) AS matches_played,
                SUM(win) AS wins,
                SUM(1 - win) AS losses,
                ROUND((COALESCE(ra.rating, 0) + COALESCE(rb.rating, 0)) / 2, 1) AS avg_rating
         FROM (
           SELECT LEAST(player1_id, player1_partner_id) AS p_a, GREATEST(player1_id, player1_partner_id) AS p_b,
                  CASE WHEN winner_id = player1_id THEN 1 ELSE 0 END AS win
           FROM matches
           WHERE league_id = $3 AND status = 'confirmed' AND player1_partner_id IS NOT NULL
           UNION ALL
           SELECT LEAST(player2_id, player2_partner_id), GREATEST(player2_id, player2_partner_id),
                  CASE WHEN winner_id = player2_id THEN 1 ELSE 0 END
           FROM matches
           WHERE league_id = $3 AND status = 'confirmed' AND player2_partner_id IS NOT NULL
           UNION ALL
           SELECT LEAST(player1_id, player1_partner_id), GREATEST(player1_id, player1_partner_id),
                  CASE WHEN winner_id = player1_id THEN 1 ELSE 0 END
           FROM playoff_matches
           WHERE league_id = $3 AND status = 'confirmed' AND player1_partner_id IS NOT NULL
           UNION ALL
           SELECT LEAST(player2_id, player2_partner_id), GREATEST(player2_id, player2_partner_id),
                  CASE WHEN winner_id = player2_id THEN 1 ELSE 0 END
           FROM playoff_matches
           WHERE league_id = $3 AND status = 'confirmed' AND player2_partner_id IS NOT NULL
         ) pair_results
         JOIN users ua ON ua.id = p_a
         JOIN users ub ON ub.id = p_b
         LEFT JOIN user_sports ra ON ra.user_id = p_a AND ra.sport = $1 AND ra.format = $2
         LEFT JOIN user_sports rb ON rb.user_id = p_b AND rb.sport = $1 AND rb.format = $2
         GROUP BY p_a, p_b, ua.username, ub.username, ra.rating, rb.rating
         ORDER BY wins DESC, avg_rating DESC`,
        [leagueData.sport, leagueData.format, leagueId]
      );
      pairLeaderboard = pairResult.rows;
    }

    res.status(200).json({ league: leagueData, leaderboard: leaderboard.rows, pairLeaderboard });
  } catch (err) {
    console.error('League detail error:', err);
    res.status(500).json({ error: 'Something went wrong fetching league details.' });
  }
});

// ---------- Doubles team-building helpers ----------

// Global (non-tiered) zig-zag pairing across the whole field, used for
// host_auto knockout brackets: highest rated with lowest, 2nd-highest with
// 2nd-lowest, etc. — same balancing idea as the round-robin tier algorithm,
// just applied across the entire qualifying pool instead of per-tier.
function zigZagPairTeams(sortedMembersDesc) {
  const teams = [];
  let lo = 0;
  let hi = sortedMembersDesc.length - 1;
  while (lo < hi) {
    const a = sortedMembersDesc[lo];
    const b = sortedMembersDesc[hi];
    teams.push({
      player1: a,
      player2: b,
      avgRating: (parseFloat(a.rating) + parseFloat(b.rating)) / 2,
    });
    lo++;
    hi--;
  }
  return teams;
}

// Builds teams from confirmed league_members partnerships. Throws a
// user-facing error string if any member lacks a confirmed partner.
function buildTeamsFromConfirmedPairs(members) {
  const byId = new Map(members.map((m) => [m.id, m]));
  const seen = new Set();
  const teams = [];
  const unpaired = [];

  for (const m of members) {
    if (seen.has(m.id)) continue;
    if (m.partner_status !== 'confirmed' || !m.partner_id || !byId.has(m.partner_id)) {
      unpaired.push(m.id);
      continue;
    }
    const partner = byId.get(m.partner_id);
    seen.add(m.id);
    seen.add(partner.id);
    teams.push({
      player1: m,
      player2: partner,
      avgRating: (parseFloat(m.rating) + parseFloat(partner.rating)) / 2,
    });
  }

  if (unpaired.length > 0) {
    const err = new Error('Not everyone has a confirmed partner yet. All players must be paired before the schedule/bracket can be generated.');
    err.code = 'UNPAIRED_MEMBERS';
    throw err;
  }

  return teams;
}

// Resolves the doubles teams for a league, branching on partner_mode.
function resolveDoublesTeams(league, members) {
  if (league.partner_mode === 'host_auto') {
    const sorted = [...members].sort((a, b) => parseFloat(b.rating) - parseFloat(a.rating));
    return zigZagPairTeams(sorted);
  }
  return buildTeamsFromConfirmedPairs(members);
}

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
      `SELECT u.id, us.rating, lm.partner_id, lm.partner_status
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

    try {
      if (league.schedule_type === 'matches_per_player') {
        if (league.format === 'singles') {
          scheduledMatches = generateNearestRatingSchedule(members, league.matches_per_player);
        } else {
          const teams = resolveDoublesTeams(league, members);
          scheduledMatches = generateNearestRatingScheduleForTeams(teams, league.matches_per_player);
        }
      } else {
        scheduledMatches = generateRoundRobinSchedule(league, members);
      }
    } catch (buildErr) {
      if (buildErr.code === 'UNPAIRED_MEMBERS') {
        return res.status(400).json({ error: buildErr.message });
      }
      throw buildErr;
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
    `SELECT u.id, us.rating, lm.partner_id, lm.partner_status
     FROM league_members lm
     JOIN users u ON u.id = lm.user_id
     JOIN user_sports us ON us.user_id = u.id AND us.sport = $1 AND us.format = $2
     WHERE lm.league_id = $3
     ORDER BY us.rating DESC`,
    [league.sport, league.format, leagueId]
  );
  const members = membersResult.rows;

  if (league.format === 'singles') {
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

    return res.status(201).json({ message: 'Bracket generated.', matchCount: seedOrder.length / 2 });
  }

  // Doubles: resolve teams first, then bracket them exactly like singles but
  // with each "seed" being a team (player + partner).
  let teams;
  try {
    teams = resolveDoublesTeams(league, members);
  } catch (buildErr) {
    if (buildErr.code === 'UNPAIRED_MEMBERS') {
      return res.status(400).json({ error: buildErr.message });
    }
    throw buildErr;
  }

  teams.sort((a, b) => b.avgRating - a.avgRating);

  if (!isPowerOfTwo(teams.length) || teams.length < 2) {
    return res.status(400).json({
      error: `Knockout doubles leagues need an exact power-of-two number of teams (2, 4, 8, 16...). Currently has ${teams.length} team(s) — ${members.length} player(s).`,
    });
  }

  const size = teams.length;
  const seedOrder = generateSeedOrder(size);
  const totalRounds = Math.log2(size);

  for (let i = 0; i < seedOrder.length; i += 2) {
    const seedA = seedOrder[i];
    const seedB = seedOrder[i + 1];
    const teamA = teams[seedA - 1];
    const teamB = teams[seedB - 1];
    await pool.query(
      `INSERT INTO playoff_matches
        (league_id, round_number, position, player1_id, player1_partner_id, player2_id, player2_partner_id, status)
       VALUES ($1, 1, $2, $3, $4, $5, $6, 'ready')`,
      [leagueId, i / 2 + 1, teamA.player1.id, teamA.player2.id, teamB.player1.id, teamB.player2.id]
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
// Reverses rating + league-points effects for every CONFIRMED regular match
// in a league. Used by regenerate-schedule, which now wipes match history
// entirely rather than preserving it (a deliberate product decision — see
// the regenerate-schedule handler below).
async function reverseAllConfirmedMatchesForLeague(leagueId, league) {
  const { sport, format } = league;

  const matchesResult = await pool.query(
    `SELECT * FROM matches WHERE league_id = $1 AND status = 'confirmed'`,
    [leagueId]
  );

  for (const match of matchesResult.rows) {
    const team1Won = match.winner_id === match.player1_id;

    const reverseOne = async (playerId, ratingChange, won) => {
      if (playerId == null || ratingChange == null) return;
      if (sport === 'table_tennis') {
        await pool.query(
          `UPDATE user_sports SET rating = rating - $1, matches_played = matches_played - 1,
           wins = wins - $2, losses = losses - $3
           WHERE user_id = $4 AND sport = $5`,
          [ratingChange, won ? 1 : 0, won ? 0 : 1, playerId, sport]
        );
      } else {
        await pool.query(
          `UPDATE user_sports SET rating = rating - $1, matches_played = matches_played - 1,
           wins = wins - $2, losses = losses - $3
           WHERE user_id = $4 AND sport = $5 AND format = $6`,
          [ratingChange, won ? 1 : 0, won ? 0 : 1, playerId, sport, format]
        );
      }
    };

    await reverseOne(match.player1_id, match.player1_rating_change, team1Won);
    await reverseOne(match.player2_id, match.player2_rating_change, !team1Won);
    await reverseOne(match.player1_partner_id, match.player1_partner_rating_change, team1Won);
    await reverseOne(match.player2_partner_id, match.player2_partner_rating_change, !team1Won);

    if (match.league_points_awarded != null) {
      const winnerIds = [match.winner_id];
      if (match.winner_id === match.player1_id && match.player1_partner_id) winnerIds.push(match.player1_partner_id);
      if (match.winner_id === match.player2_id && match.player2_partner_id) winnerIds.push(match.player2_partner_id);
      for (const wId of winnerIds) {
        await pool.query(
          'UPDATE league_members SET points = points - $1 WHERE league_id = $2 AND user_id = $3',
          [match.league_points_awarded, leagueId, wId]
        );
      }
    }
  }
}

// Same idea, for confirmed knockout (playoff_matches) rows. Playoff matches
// don't award league points in this app, so only rating/stat reversal
// applies here.
async function reverseAllConfirmedPlayoffMatchesForLeague(leagueId, league) {
  const { sport, format } = league;

  const matchesResult = await pool.query(
    `SELECT * FROM playoff_matches WHERE league_id = $1 AND status = 'confirmed'`,
    [leagueId]
  );

  for (const match of matchesResult.rows) {
    const team1Won = match.winner_id === match.player1_id;

    const reverseOne = async (playerId, ratingChange, won) => {
      if (playerId == null || ratingChange == null) return;
      if (sport === 'table_tennis') {
        await pool.query(
          `UPDATE user_sports SET rating = rating - $1, matches_played = matches_played - 1,
           wins = wins - $2, losses = losses - $3
           WHERE user_id = $4 AND sport = $5`,
          [ratingChange, won ? 1 : 0, won ? 0 : 1, playerId, sport]
        );
      } else {
        await pool.query(
          `UPDATE user_sports SET rating = rating - $1, matches_played = matches_played - 1,
           wins = wins - $2, losses = losses - $3
           WHERE user_id = $4 AND sport = $5 AND format = $6`,
          [ratingChange, won ? 1 : 0, won ? 0 : 1, playerId, sport, format]
        );
      }
    };

    await reverseOne(match.player1_id, match.player1_rating_change, team1Won);
    await reverseOne(match.player2_id, match.player2_rating_change, !team1Won);
    await reverseOne(match.player1_partner_id, match.player1_partner_rating_change, team1Won);
    await reverseOne(match.player2_partner_id, match.player2_partner_rating_change, !team1Won);
  }
}

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
      await pool.query(
        'UPDATE leagues SET schedule_type = $1, matches_per_player = $2 WHERE id = $3',
        [finalScheduleType, finalScheduleType === 'matches_per_player' ? matchesPerPlayer : null, leagueId]
      );
    }

    // Regenerating the schedule wipes this league's match history entirely —
    // reverse every confirmed match's rating/points effects first, then
    // delete everything, before building the fresh schedule below.
    await reverseAllConfirmedMatchesForLeague(leagueId, league);
    await reverseAllConfirmedPlayoffMatchesForLeague(leagueId, league);

    await pool.query('DELETE FROM matches WHERE league_id = $1', [leagueId]);
    await pool.query('DELETE FROM scheduled_matches WHERE league_id = $1', [leagueId]);
    await pool.query('DELETE FROM playoff_matches WHERE league_id = $1', [leagueId]);

    const refreshedLeagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [leagueId]);
    const refreshedLeague = refreshedLeagueResult.rows[0];

    if (refreshedLeague.schedule_type === 'custom') {
      return res.status(200).json({ message: 'Schedule cleared and previous match history reversed. Add matches manually.', matchCount: 0 });
    }
    if (refreshedLeague.schedule_type === 'knockout') {
      return generateKnockoutBracket(req, res, refreshedLeague);
    }

    const membersResult = await pool.query(
      `SELECT u.id, us.rating, lm.partner_id, lm.partner_status
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
    try {
      if (refreshedLeague.schedule_type === 'matches_per_player') {
        if (refreshedLeague.format === 'singles') {
          scheduledMatches = generateNearestRatingSchedule(members, refreshedLeague.matches_per_player);
        } else {
          const teams = resolveDoublesTeams(refreshedLeague, members);
          scheduledMatches = generateNearestRatingScheduleForTeams(teams, refreshedLeague.matches_per_player);
        }
      } else {
        scheduledMatches = generateRoundRobinSchedule(refreshedLeague, members);
      }
    } catch (buildErr) {
      if (buildErr.code === 'UNPAIRED_MEMBERS') {
        return res.status(400).json({ error: buildErr.message });
      }
      throw buildErr;
    }

    for (const m of scheduledMatches) {
      await pool.query(
        `INSERT INTO scheduled_matches
          (league_id, tier_number, player1_id, player1_partner_id, player2_id, player2_partner_id)
         VALUES ($1, $2, $3, $4, $5, $6)`,
        [leagueId, m.tierNumber, m.player1Id, m.player1PartnerId, m.player2Id, m.player2PartnerId]
      );
    }

    res.status(201).json({ message: 'Schedule regenerated. All previous match history and rating changes for this tournament have been reversed.', matchCount: scheduledMatches.length });
  } catch (err) {
    console.error('Regenerate schedule error:', err);
    res.status(500).json({ error: 'Something went wrong regenerating the schedule.' });
  }
});

// NOTE: signature changed from (members, format) to (league, members) so it
// has access to partner_mode for doubles leagues.
function generateRoundRobinSchedule(league, members) {
  const format = league.format;

  if (format === 'singles') {
    return generateSinglesRoundRobin(members);
  }

  // Doubles: resolve teams (host_auto -> zig-zag by rating tier; otherwise
  // -> confirmed partner pairs), then tier the TEAMS the same way singles
  // tiers players, and round-robin within each tier.
  let teams;
  if (league.partner_mode === 'host_auto') {
    // Preserve original behavior exactly: tier players first (groups of 4),
    // then zig-zag pair within each tier, then round-robin the resulting
    // teams within that same tier.
    return generateHostAutoDoublesRoundRobin(members);
  }
  teams = buildTeamsFromConfirmedPairs(members);
  teams.sort((a, b) => b.avgRating - a.avgRating);

  const tiers = [];
  for (let i = 0; i < teams.length; i += TIER_SIZE) {
    tiers.push(teams.slice(i, i + TIER_SIZE));
  }
  while (tiers.length > 1 && tiers[tiers.length - 1].length < 2) {
    const leftover = tiers.pop();
    tiers[tiers.length - 1] = tiers[tiers.length - 1].concat(leftover);
  }

  const scheduledMatches = [];
  tiers.forEach((tier, tierIndex) => {
    const tierNumber = tierIndex + 1;
    for (let i = 0; i < tier.length; i++) {
      for (let j = i + 1; j < tier.length; j++) {
        scheduledMatches.push({
          tierNumber,
          player1Id: tier[i].player1.id,
          player1PartnerId: tier[i].player2.id,
          player2Id: tier[j].player1.id,
          player2PartnerId: tier[j].player2.id,
        });
      }
    }
  });

  return scheduledMatches;
}

function generateSinglesRoundRobin(members) {
  const tiers = [];
  for (let i = 0; i < members.length; i += TIER_SIZE) {
    tiers.push(members.slice(i, i + TIER_SIZE));
  }

  const scheduledMatches = [];
  tiers.forEach((tier, tierIndex) => {
    const tierNumber = tierIndex + 1;
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
  });

  return scheduledMatches;
}

// Original host_auto doubles behavior, unchanged from before this feature:
// tier by TIER_SIZE, zig-zag pair within tier, round-robin the two teams.
function generateHostAutoDoublesRoundRobin(members) {
  const tiers = [];
  for (let i = 0; i < members.length; i += TIER_SIZE) {
    tiers.push(members.slice(i, i + TIER_SIZE));
  }

  const minTierSize = 4;
  while (tiers.length > 1 && tiers[tiers.length - 1].length < minTierSize) {
    const leftover = tiers.pop();
    tiers[tiers.length - 1] = tiers[tiers.length - 1].concat(leftover);
  }

  const scheduledMatches = [];

  tiers.forEach((tier, tierIndex) => {
    const tierNumber = tierIndex + 1;
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

// Doubles equivalent of generateNearestRatingSchedule: treats each resolved
// team as a single "player" (pseudo id = array index, rating = team average),
// reuses the same nearest-rating matching algorithm, then maps the resulting
// pseudo-fixtures back to real player/partner ids.
function generateNearestRatingScheduleForTeams(teams, matchesPerTeam) {
  const pseudoMembers = teams.map((team, idx) => ({
    id: idx,
    rating: team.avgRating,
  }));

  const pseudoMatches = generateNearestRatingSchedule(pseudoMembers, matchesPerTeam);

  return pseudoMatches.map((m) => {
    const teamA = teams[m.player1Id];
    const teamB = teams[m.player2Id];
    return {
      tierNumber: m.tierNumber,
      player1Id: teamA.player1.id,
      player1PartnerId: teamA.player2.id,
      player2Id: teamB.player1.id,
      player2PartnerId: teamB.player2.id,
    };
  });
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
              m.id as match_id, m.status as match_status, m.set_scores, m.winner_id, m.reported_by,
              m.player1_id as reported_player1_id, m.player2_id as reported_player2_id
       FROM scheduled_matches sm
       LEFT JOIN matches m ON m.scheduled_match_id = sm.id AND m.status != 'rejected'
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
  const {
    name, area, seasonStart, seasonEnd, academyName, isPrivate, hostEntersScores,
    registrationStart, registrationEnd, partnerMode,
  } = req.body;

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

    if (registrationStart !== undefined) {
      updates.push(`registration_start = $${idx++}`);
      params.push(registrationStart || null);
    }
    if (registrationEnd !== undefined) {
      updates.push(`registration_end = $${idx++}`);
      params.push(registrationEnd || null);
    }
    if (registrationStart != null && registrationEnd != null &&
        new Date(registrationStart) > new Date(registrationEnd)) {
      return res.status(400).json({ error: 'Registration start must be before registration end.' });
    }

    if (partnerMode !== undefined) {
      if (league.format !== 'doubles') {
        return res.status(400).json({ error: 'Partner mode only applies to doubles leagues.' });
      }
      if (!VALID_PARTNER_MODES.includes(partnerMode)) {
        return res.status(400).json({ error: 'Invalid partner mode.' });
      }
      const anyPaired = await pool.query(
        `SELECT id FROM league_members WHERE league_id = $1 AND partner_status IS NOT NULL LIMIT 1`,
        [leagueId]
      );
      if (anyPaired.rows.length > 0) {
        return res.status(400).json({ error: 'Cannot change partner mode after partnerships have started forming. Unpair everyone first.' });
      }
      updates.push(`partner_mode = $${idx++}`);
      params.push(partnerMode);
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