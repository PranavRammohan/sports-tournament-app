// matchRoutes.js
const express = require('express');
const router = express.Router();
const pool = require('./db');
const { calculateNewRatings, reverseRatingChange } = require('./ratingEngine');
const { RouteError } = pool;

// A reasonable ceiling for any single unit count (games/points won in a
// match) — high enough to never legitimately trigger, just a sanity guard
// against garbage input.
const MAX_PLAUSIBLE_UNITS = 500;

function isValidUnitCount(value) {
  return typeof value === 'number' && Number.isInteger(value) && value >= 0 && value <= MAX_PLAUSIBLE_UNITS;
}

// Validates the optional per-set score breakdown: must be an array (possibly
// empty) of {me, opponent} objects with non-negative integer values, and no
// set can be tied (every set needs a winner).
function isValidSetScores(setScores) {
  if (setScores == null) return true;
  if (!Array.isArray(setScores)) return false;
  return setScores.every((s) => {
    if (s == null || typeof s !== 'object') return false;
    if (!isValidUnitCount(s.me) || !isValidUnitCount(s.opponent)) return false;
    return s.me !== s.opponent;
  });
}

// Same guard leagueRoutes.js uses — kept as a local copy here since this file
// has no shared module with leagueRoutes.js. Returns a user-facing error
// string if the league has been marked completed (read-only), or null if
// it's still active.
function checkNotCompleted(league) {
  if (league.status === 'completed') {
    return 'This tournament has been marked completed and is now read-only.';
  }
  return null;
}

async function getRating(db, userId, sport, format) {
  const result = await db.query(
    'SELECT rating FROM user_sports WHERE user_id = $1 AND sport = $2 AND format = $3',
    [userId, sport, format]
  );
  if (result.rows.length === 0) return null;
  return parseFloat(result.rows[0].rating);
}

async function updateRating(db, userId, sport, format, newRating, won) {
  if (sport === 'table_tennis') {
    await db.query(
      `UPDATE user_sports SET rating = $1, matches_played = matches_played + 1,
       wins = wins + $2, losses = losses + $3
       WHERE user_id = $4 AND sport = $5`,
      [newRating, won ? 1 : 0, won ? 0 : 1, userId, sport]
    );
  } else {
    await db.query(
      `UPDATE user_sports SET rating = $1, matches_played = matches_played + 1,
       wins = wins + $2, losses = losses + $3
       WHERE user_id = $4 AND sport = $5 AND format = $6`,
      [newRating, won ? 1 : 0, won ? 0 : 1, userId, sport, format]
    );
  }
}

// Points config is set per-tournament (points_enabled/points_win/points_loss
// on leagues) with an optional per-group override (same three columns on
// league_groups, NULL meaning "inherit this field from the league"). A match
// belongs to a group only via its scheduled_match_id -> scheduled_matches.group_id;
// matches with no scheduled_match_id (manually added, or non-Groups leagues)
// always use the league's own config. Every win is worth the same regardless
// of how it happened — no bonuses for upsets or dominant (straight-set) wins.
async function resolvePointsConfig(db, match, league) {
  let group = null;
  if (match.scheduled_match_id) {
    const result = await db.query(
      `SELECT lg.* FROM scheduled_matches sm
       JOIN league_groups lg ON lg.id = sm.group_id
       WHERE sm.id = $1 AND sm.group_id IS NOT NULL`,
      [match.scheduled_match_id]
    );
    group = result.rows[0] || null;
  }
  const enabled = (group && group.points_enabled != null) ? group.points_enabled : league.points_enabled;
  const win = (group && group.points_win != null) ? group.points_win : league.points_win;
  const loss = (group && group.points_loss != null) ? group.points_loss : league.points_loss;
  return { enabled, win, loss };
}

async function awardLeaguePoints(db, leagueId, winnerId, points) {
  await db.query(
    'UPDATE league_members SET points = points + $1 WHERE league_id = $2 AND user_id = $3',
    [points, leagueId, winnerId]
  );
}

async function findMatchingFixture(db, leagueId, team1Ids, team2Ids) {
  const result = await db.query(
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

async function finalizeMatch(db, match, league) {
  const { sport, format } = league;

  const rating1a = await getRating(db, match.player1_id, sport, format);
  const rating2a = await getRating(db, match.player2_id, sport, format);
  const rating1b = match.player1_partner_id ? await getRating(db, match.player1_partner_id, sport, format) : null;
  const rating2b = match.player2_partner_id ? await getRating(db, match.player2_partner_id, sport, format) : null;

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
    await updateRating(db, playerId, sport, format, updated, won);
    return actualChange;
  };

  const player1RatingChange = await applyChange(match.player1_id, rating1a, change1, team1Won);
  const player2RatingChange = await applyChange(match.player2_id, rating2a, change2, !team1Won);
  const player1PartnerRatingChange = await applyChange(match.player1_partner_id, rating1b, change1, team1Won);
  const player2PartnerRatingChange = await applyChange(match.player2_partner_id, rating2b, change2, !team1Won);

  const pointsConfig = await resolvePointsConfig(db, match, league);
  const winnerPoints = pointsConfig.enabled ? pointsConfig.win : 0;
  const loserPoints = pointsConfig.enabled ? pointsConfig.loss : 0;

  await db.query(
    `UPDATE matches SET status = 'confirmed',
      player1_rating_change = $1, player2_rating_change = $2,
      player1_partner_rating_change = $3, player2_partner_rating_change = $4,
      league_points_awarded = $5, league_points_awarded_loser = $6
     WHERE id = $7`,
    [player1RatingChange, player2RatingChange, player1PartnerRatingChange, player2PartnerRatingChange, winnerPoints, loserPoints, match.id]
  );

  await awardLeaguePoints(db, match.league_id, match.winner_id, winnerPoints);
  if (match.winner_id === match.player1_id && match.player1_partner_id) {
    await awardLeaguePoints(db, match.league_id, match.player1_partner_id, winnerPoints);
  }
  if (match.winner_id === match.player2_id && match.player2_partner_id) {
    await awardLeaguePoints(db, match.league_id, match.player2_partner_id, winnerPoints);
  }

  const loserId = team1Won ? match.player2_id : match.player1_id;
  const loserPartnerId = team1Won ? match.player2_partner_id : match.player1_partner_id;
  await awardLeaguePoints(db, match.league_id, loserId, loserPoints);
  if (loserPartnerId) {
    await awardLeaguePoints(db, match.league_id, loserPartnerId, loserPoints);
  }
}

// Undoes the rating + league-points effects of a previously confirmed match.
// Used when a host edits or deletes a confirmed score.
async function reverseMatchEffects(db, match, league) {
  const { sport, format } = league;
  const team1Won = match.winner_id === match.player1_id;

  await reverseRatingChange(db, match.player1_id, sport, format, match.player1_rating_change, team1Won);
  await reverseRatingChange(db, match.player2_id, sport, format, match.player2_rating_change, !team1Won);
  await reverseRatingChange(db, match.player1_partner_id, sport, format, match.player1_partner_rating_change, team1Won);
  await reverseRatingChange(db, match.player2_partner_id, sport, format, match.player2_partner_rating_change, !team1Won);

  if (match.league_points_awarded != null) {
    const winnerIds = [match.winner_id];
    if (match.winner_id === match.player1_id && match.player1_partner_id) winnerIds.push(match.player1_partner_id);
    if (match.winner_id === match.player2_id && match.player2_partner_id) winnerIds.push(match.player2_partner_id);
    for (const wId of winnerIds) {
      await db.query(
        'UPDATE league_members SET points = points - $1 WHERE league_id = $2 AND user_id = $3',
        [match.league_points_awarded, match.league_id, wId]
      );
    }
  }
  if (match.league_points_awarded_loser != null) {
    const loserIds = [team1Won ? match.player2_id : match.player1_id];
    const loserPartnerId = team1Won ? match.player2_partner_id : match.player1_partner_id;
    if (loserPartnerId) loserIds.push(loserPartnerId);
    for (const lId of loserIds) {
      await db.query(
        'UPDATE league_members SET points = points - $1 WHERE league_id = $2 AND user_id = $3',
        [match.league_points_awarded_loser, match.league_id, lId]
      );
    }
  }
}

// Checks if any participant in this match has played another confirmed match
// (same sport/format) since this one happened — a signal that reversing this
// match's rating change may not perfectly restore their "true" current rating.
async function checkForRatingDrift(db, match, league) {
  const participantIds = [
    match.player1_id, match.player2_id, match.player1_partner_id, match.player2_partner_id,
  ].filter(Boolean);

  // Table tennis shares one rating across singles/doubles, so a subsequent
  // match in the *other* format still moved this player's rating and must
  // count as drift too — pass null to skip the format filter for that sport.
  const formatFilter = league.sport === 'table_tennis' ? null : league.format;

  const result = await db.query(
    `SELECT COUNT(*) FROM (
       SELECT m.id FROM matches m
       JOIN leagues l ON l.id = m.league_id
       WHERE m.status = 'confirmed' AND m.id != $1
         AND l.sport = $2 AND ($3::text IS NULL OR l.format = $3)
         AND m.created_at > $4
         AND (m.player1_id = ANY($5::int[]) OR m.player2_id = ANY($5::int[])
              OR m.player1_partner_id = ANY($5::int[]) OR m.player2_partner_id = ANY($5::int[]))
       UNION ALL
       SELECT pm.id FROM playoff_matches pm
       JOIN leagues l ON l.id = pm.league_id
       WHERE pm.status = 'confirmed'
         AND l.sport = $2 AND ($3::text IS NULL OR l.format = $3)
         AND pm.created_at > $4
         AND (pm.player1_id = ANY($5::int[]) OR pm.player2_id = ANY($5::int[])
              OR pm.player1_partner_id = ANY($5::int[]) OR pm.player2_partner_id = ANY($5::int[]))
     ) drift`,
    [match.id, league.sport, formatFilter, match.created_at, participantIds]
  );
  return parseInt(result.rows[0].count, 10) > 0;
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
  if (!isValidUnitCount(myUnits) || !isValidUnitCount(opponentUnits)) {
    return res.status(400).json({ error: 'Scores must be non-negative whole numbers.' });
  }
  if (!isValidSetScores(setScores)) {
    return res.status(400).json({ error: 'Invalid set scores — each set needs non-negative whole numbers and a winner.' });
  }

  try {
    const leagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [leagueId]);
    if (leagueResult.rows.length === 0) {
      return res.status(404).json({ error: 'League not found.' });
    }
    const league = leagueResult.rows[0];

    if (league.status === 'completed') {
      return res.status(400).json({ error: 'This tournament has been marked completed and is now read-only.' });
    }
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
      pool,
      leagueId,
      [userId, partnerId],
      [opponentId, opponentPartnerId]
    );

    // Require a matching scheduled fixture unconditionally — including when
    // the league has no scheduled_matches rows at all yet (e.g. a 'custom'
    // league before the host has added its first manual match). Without this,
    // an empty schedule let anyone self-report a fabricated matchup against
    // any other member, since there was nothing yet to fail to match against.
    if (scheduledMatchId === null) {
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
  if (!isValidUnitCount(player1Units) || !isValidUnitCount(player2Units)) {
    return res.status(400).json({ error: 'Scores must be non-negative whole numbers.' });
  }
  if (!isValidSetScores(setScores)) {
    return res.status(400).json({ error: 'Invalid set scores — each set needs non-negative whole numbers and a winner.' });
  }

  try {
    let match;

    await pool.withTransaction(async (client) => {
      const leagueResult = await client.query('SELECT * FROM leagues WHERE id = $1', [leagueId]);
      if (leagueResult.rows.length === 0) {
        throw new RouteError(404, 'League not found.');
      }
      const league = leagueResult.rows[0];

      if (!league.host_enters_scores || league.created_by !== userId) {
        throw new RouteError(403, 'Only the host can enter scores directly for this league.');
      }
      if (league.status === 'completed') {
        throw new RouteError(400, 'This tournament has been marked completed and is now read-only.');
      }

      const winnerId = player1Won ? player1Id : player2Id;

      const scheduledMatchId = await findMatchingFixture(
        client,
        leagueId,
        [player1Id, player1PartnerId],
        [player2Id, player2PartnerId]
      );

      if (scheduledMatchId === null) {
        throw new RouteError(400, 'This matchup is not part of the generated schedule.');
      }

      const alreadyConfirmed = await client.query(
        `SELECT id FROM matches WHERE scheduled_match_id = $1 AND status = 'confirmed' LIMIT 1`,
        [scheduledMatchId]
      );
      if (alreadyConfirmed.rows.length > 0) {
        throw new RouteError(409, 'This scheduled match has already been completed.');
      }

      const result = await client.query(
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

      match = result.rows[0];
      await finalizeMatch(client, match, league);
    });

    res.status(201).json({ match });
  } catch (err) {
    if (err instanceof RouteError) {
      return res.status(err.statusCode).json({ error: err.message });
    }
    console.error('Host report match error:', err);
    res.status(500).json({ error: 'Something went wrong entering the score.' });
  }
});

// ---------- GET MATCHES AWAITING MY CONFIRMATION ----------
router.get('/pending', async (req, res) => {
  const userId = req.userId;

  try {
    const result = await pool.query(
      `SELECT * FROM (
         SELECT m.id, m.league_id, NULL::int as round_number,
                m.player1_id, m.player2_id, m.player1_partner_id, m.player2_partner_id,
                m.player1_units, m.player2_units, m.winner_id, m.reported_by, m.set_scores, m.created_at,
                l.sport, l.format as league_format, l.name as league_name,
                p1.username as player1_username, p1.phone_number as player1_phone,
                p2.username as player2_username, p2.phone_number as player2_phone,
                pp1.username as player1_partner_username, pp1.phone_number as player1_partner_phone,
                pp2.username as player2_partner_username, pp2.phone_number as player2_partner_phone,
                'regular' as match_type
         FROM matches m
         JOIN leagues l ON l.id = m.league_id
         JOIN users p1 ON p1.id = m.player1_id
         JOIN users p2 ON p2.id = m.player2_id
         LEFT JOIN users pp1 ON pp1.id = m.player1_partner_id
         LEFT JOIN users pp2 ON pp2.id = m.player2_partner_id
         WHERE m.status = 'pending'
           AND m.reported_by != $1
           AND (m.player2_id = $1 OR m.player2_partner_id = $1 OR m.player1_id = $1 OR m.player1_partner_id = $1)
         UNION ALL
         SELECT pm.id, pm.league_id, pm.round_number,
                pm.player1_id, pm.player2_id, pm.player1_partner_id, pm.player2_partner_id,
                pm.player1_units, pm.player2_units, pm.winner_id, pm.reported_by, pm.set_scores, pm.created_at,
                l.sport, l.format as league_format, l.name as league_name,
                p1.username as player1_username, p1.phone_number as player1_phone,
                p2.username as player2_username, p2.phone_number as player2_phone,
                pp1.username as player1_partner_username, pp1.phone_number as player1_partner_phone,
                pp2.username as player2_partner_username, pp2.phone_number as player2_partner_phone,
                'playoff' as match_type
         FROM playoff_matches pm
         JOIN leagues l ON l.id = pm.league_id
         JOIN users p1 ON p1.id = pm.player1_id
         JOIN users p2 ON p2.id = pm.player2_id
         LEFT JOIN users pp1 ON pp1.id = pm.player1_partner_id
         LEFT JOIN users pp2 ON pp2.id = pm.player2_partner_id
         WHERE pm.status = 'reported'
           AND pm.reported_by != $1
           AND (pm.player2_id = $1 OR pm.player2_partner_id = $1 OR pm.player1_id = $1 OR pm.player1_partner_id = $1)
       ) combined
       ORDER BY created_at DESC
       LIMIT 100`,
      [userId]
    );
    res.status(200).json({ matches: result.rows });
  } catch (err) {
    console.error('Get pending matches error:', err);
    res.status(500).json({ error: 'Something went wrong fetching pending matches.' });
  }
});

// ---------- MATCHES I REPORTED THAT ARE STILL PENDING (for the reporter's own edit access) ----------
router.get('/pending-reported-by-me', async (req, res) => {
  const userId = req.userId;

  try {
    const result = await pool.query(
      `SELECT * FROM (
         SELECT m.id, m.league_id, NULL::int as round_number,
                m.player1_id, m.player2_id, m.player1_partner_id, m.player2_partner_id,
                m.player1_units, m.player2_units, m.winner_id, m.set_scores, m.created_at,
                l.sport, l.format as league_format,
                p1.username as player1_username, p2.username as player2_username,
                pp1.username as player1_partner_username, pp2.username as player2_partner_username,
                'regular' as match_type
         FROM matches m
         JOIN leagues l ON l.id = m.league_id
         JOIN users p1 ON p1.id = m.player1_id
         JOIN users p2 ON p2.id = m.player2_id
         LEFT JOIN users pp1 ON pp1.id = m.player1_partner_id
         LEFT JOIN users pp2 ON pp2.id = m.player2_partner_id
         WHERE m.status = 'pending' AND m.reported_by = $1
         UNION ALL
         SELECT pm.id, pm.league_id, pm.round_number,
                pm.player1_id, pm.player2_id, pm.player1_partner_id, pm.player2_partner_id,
                pm.player1_units, pm.player2_units, pm.winner_id, pm.set_scores, pm.created_at,
                l.sport, l.format as league_format,
                p1.username as player1_username, p2.username as player2_username,
                pp1.username as player1_partner_username, pp2.username as player2_partner_username,
                'playoff' as match_type
         FROM playoff_matches pm
         JOIN leagues l ON l.id = pm.league_id
         JOIN users p1 ON p1.id = pm.player1_id
         JOIN users p2 ON p2.id = pm.player2_id
         LEFT JOIN users pp1 ON pp1.id = pm.player1_partner_id
         LEFT JOIN users pp2 ON pp2.id = pm.player2_partner_id
         WHERE pm.status = 'reported' AND pm.reported_by = $1
       ) combined
       ORDER BY created_at DESC
       LIMIT 100`,
      [userId]
    );
    res.status(200).json({ matches: result.rows });
  } catch (err) {
    console.error('Get my pending reports error:', err);
    res.status(500).json({ error: 'Something went wrong fetching your pending reports.' });
  }
});

// ---------- UPCOMING SCHEDULED MATCHES (across all leagues) ----------
router.get('/upcoming', async (req, res) => {
  const userId = req.userId;

  try {
    const result = await pool.query(
      `SELECT sm.id, sm.tier_number,
              l.id as league_id, l.name as league_name, l.sport, l.area, l.format,
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
      `SELECT * FROM (
         SELECT m.id, m.league_id, m.player1_id, m.player2_id, m.player1_partner_id, m.player2_partner_id,
                m.player1_units, m.player2_units, m.set_scores, m.winner_id, m.created_at,
                m.player1_rating_change, m.player2_rating_change,
                m.player1_partner_rating_change, m.player2_partner_rating_change,
                l.sport, l.format as league_format, l.area, l.name as league_name,
                p1.username as player1_username, p2.username as player2_username,
                pp1.username as player1_partner_username, pp2.username as player2_partner_username,
                'regular' as match_type
         FROM matches m
         JOIN leagues l ON l.id = m.league_id
         JOIN users p1 ON p1.id = m.player1_id
         JOIN users p2 ON p2.id = m.player2_id
         LEFT JOIN users pp1 ON pp1.id = m.player1_partner_id
         LEFT JOIN users pp2 ON pp2.id = m.player2_partner_id
         WHERE m.status = 'confirmed'
           AND (m.player1_id = $1 OR m.player2_id = $1 OR m.player1_partner_id = $1 OR m.player2_partner_id = $1)
         UNION ALL
         SELECT pm.id, pm.league_id, pm.player1_id, pm.player2_id, pm.player1_partner_id, pm.player2_partner_id,
                pm.player1_units, pm.player2_units, pm.set_scores, pm.winner_id, pm.created_at,
                pm.player1_rating_change, pm.player2_rating_change,
                pm.player1_partner_rating_change, pm.player2_partner_rating_change,
                l.sport, l.format as league_format, l.area, l.name as league_name,
                p1.username as player1_username, p2.username as player2_username,
                pp1.username as player1_partner_username, pp2.username as player2_partner_username,
                'playoff' as match_type
         FROM playoff_matches pm
         JOIN leagues l ON l.id = pm.league_id
         JOIN users p1 ON p1.id = pm.player1_id
         JOIN users p2 ON p2.id = pm.player2_id
         LEFT JOIN users pp1 ON pp1.id = pm.player1_partner_id
         LEFT JOIN users pp2 ON pp2.id = pm.player2_partner_id
         WHERE pm.status = 'confirmed'
           AND (pm.player1_id = $1 OR pm.player2_id = $1 OR pm.player1_partner_id = $1 OR pm.player2_partner_id = $1)
       ) combined
       ORDER BY created_at DESC
       LIMIT 200`,
      [userId]
    );
    res.status(200).json({ matches: result.rows });
  } catch (err) {
    console.error('Match history error:', err);
    res.status(500).json({ error: 'Something went wrong fetching match history.' });
  }
});

// ---------- HEAD-TO-HEAD RECORD AGAINST ANOTHER PLAYER ----------
// Aggregates confirmed matches (regular + knockout) between the requester and
// the given player, per sport/format, from the requester's own perspective
// ("my_wins"/"my_losses"). Counts doubles matches where either side was a
// partner too, not just the exact two "representative" ids.
router.get('/head-to-head/:otherUserId', async (req, res) => {
  const userId = req.userId;
  const otherUserId = parseInt(req.params.otherUserId, 10);

  if (!otherUserId || Number.isNaN(otherUserId)) {
    return res.status(400).json({ error: 'Invalid player id.' });
  }
  if (otherUserId === userId) {
    return res.status(400).json({ error: 'Cannot compute head-to-head against yourself.' });
  }

  try {
    const result = await pool.query(
      `SELECT sport, format,
              COUNT(*) AS matches_played,
              SUM(CASE WHEN my_side_won THEN 1 ELSE 0 END) AS my_wins,
              SUM(CASE WHEN my_side_won THEN 0 ELSE 1 END) AS my_losses
       FROM (
         SELECT l.sport, l.format,
                (m.winner_id = $1
                  OR (m.player1_partner_id = $1 AND m.winner_id = m.player1_id)
                  OR (m.player2_partner_id = $1 AND m.winner_id = m.player2_id)
                ) AS my_side_won
         FROM matches m
         JOIN leagues l ON l.id = m.league_id
         WHERE m.status = 'confirmed'
           AND (
             (
               (m.player1_id = $1 OR m.player1_partner_id = $1)
               AND (m.player2_id = $2 OR m.player2_partner_id = $2)
             )
             OR
             (
               (m.player2_id = $1 OR m.player2_partner_id = $1)
               AND (m.player1_id = $2 OR m.player1_partner_id = $2)
             )
           )
         UNION ALL
         SELECT l.sport, l.format,
                (pm.winner_id = $1
                  OR (pm.player1_partner_id = $1 AND pm.winner_id = pm.player1_id)
                  OR (pm.player2_partner_id = $1 AND pm.winner_id = pm.player2_id)
                ) AS my_side_won
         FROM playoff_matches pm
         JOIN leagues l ON l.id = pm.league_id
         WHERE pm.status = 'confirmed'
           AND (
             (
               (pm.player1_id = $1 OR pm.player1_partner_id = $1)
               AND (pm.player2_id = $2 OR pm.player2_partner_id = $2)
             )
             OR
             (
               (pm.player2_id = $1 OR pm.player2_partner_id = $1)
               AND (pm.player1_id = $2 OR pm.player1_partner_id = $2)
             )
           )
       ) h2h
       GROUP BY sport, format
       ORDER BY sport, format`,
      [userId, otherUserId]
    );

    // Individual matches between the two of you, most recent first — used
    // to show an actual "recent matches against them" list, not just the
    // aggregate win/loss counts above.
    const matchesResult = await pool.query(
      `SELECT * FROM (
         SELECT m.id, l.sport, l.format, m.created_at, m.set_scores,
                m.player1_id, m.player2_id, m.player1_partner_id, m.player2_partner_id,
                m.winner_id, 'regular' as match_type,
                pp1.username as player1_partner_username, pp2.username as player2_partner_username
         FROM matches m
         JOIN leagues l ON l.id = m.league_id
         LEFT JOIN users pp1 ON pp1.id = m.player1_partner_id
         LEFT JOIN users pp2 ON pp2.id = m.player2_partner_id
         WHERE m.status = 'confirmed'
           AND (
             (
               (m.player1_id = $1 OR m.player1_partner_id = $1)
               AND (m.player2_id = $2 OR m.player2_partner_id = $2)
             )
             OR
             (
               (m.player2_id = $1 OR m.player2_partner_id = $1)
               AND (m.player1_id = $2 OR m.player1_partner_id = $2)
             )
           )
         UNION ALL
         SELECT pm.id, l.sport, l.format, pm.created_at, pm.set_scores,
                pm.player1_id, pm.player2_id, pm.player1_partner_id, pm.player2_partner_id,
                pm.winner_id, 'playoff' as match_type,
                pp1.username as player1_partner_username, pp2.username as player2_partner_username
         FROM playoff_matches pm
         JOIN leagues l ON l.id = pm.league_id
         LEFT JOIN users pp1 ON pp1.id = pm.player1_partner_id
         LEFT JOIN users pp2 ON pp2.id = pm.player2_partner_id
         WHERE pm.status = 'confirmed'
           AND (
             (
               (pm.player1_id = $1 OR pm.player1_partner_id = $1)
               AND (pm.player2_id = $2 OR pm.player2_partner_id = $2)
             )
             OR
             (
               (pm.player2_id = $1 OR pm.player2_partner_id = $1)
               AND (pm.player1_id = $2 OR pm.player1_partner_id = $2)
             )
           )
       ) combined
       ORDER BY created_at DESC
       LIMIT 20`,
      [userId, otherUserId]
    );

    res.status(200).json({ headToHead: result.rows, matches: matchesResult.rows });
  } catch (err) {
    console.error('Head-to-head error:', err);
    res.status(500).json({ error: 'Something went wrong fetching the head-to-head record.' });
  }
});

// ---------- CONFIRM A MATCH ----------
router.post('/:id/confirm', async (req, res) => {
  const userId = req.userId;
  const matchId = req.params.id;

  try {
    await pool.withTransaction(async (client) => {
      // Lock the row for the duration of the transaction so two simultaneous
      // confirms on the same match can't both pass the pending-status check
      // below and double-apply the rating/points change — the second one
      // blocks until the first commits, then sees the updated status.
      const matchResult = await client.query('SELECT * FROM matches WHERE id = $1 FOR UPDATE', [matchId]);
      if (matchResult.rows.length === 0) {
        throw new RouteError(404, 'Match not found.');
      }
      const match = matchResult.rows[0];

      if (match.status !== 'pending') {
        throw new RouteError(409, 'This match has already been processed.');
      }

      const participants = [match.player1_id, match.player1_partner_id, match.player2_id, match.player2_partner_id];
      if (!participants.includes(userId)) {
        throw new RouteError(403, 'You are not part of this match.');
      }
      if (userId === match.reported_by) {
        throw new RouteError(400, 'You cannot confirm your own report.');
      }

      const leagueResult = await client.query('SELECT * FROM leagues WHERE id = $1', [match.league_id]);
      const league = leagueResult.rows[0];

      const completedError = checkNotCompleted(league);
      if (completedError) {
        throw new RouteError(400, completedError);
      }

      await finalizeMatch(client, match, league);
    });

    res.status(200).json({ message: 'Match confirmed and ratings updated.' });
  } catch (err) {
    if (err instanceof RouteError) {
      return res.status(err.statusCode).json({ error: err.message });
    }
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

    const leagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [match.league_id]);
    const league = leagueResult.rows[0];

    const completedError = checkNotCompleted(league);
    if (completedError) {
      return res.status(400).json({ error: completedError });
    }

    await pool.query(`UPDATE matches SET status = 'rejected' WHERE id = $1`, [matchId]);

    res.status(200).json({ message: 'Match report rejected. It can be reported again with the correct score.' });
  } catch (err) {
    console.error('Reject match error:', err);
    res.status(500).json({ error: 'Something went wrong rejecting the match.' });
  }
});

// ---------- REPORTER EDITS THEIR OWN PENDING REPORT ----------
// Lets the person who reported a result fix a mistake themselves, before
// their opponent has confirmed or rejected it — an alternative to having
// the opponent reject and forcing a full re-report. No rating/points impact
// since the match isn't confirmed yet.
router.put('/:id/edit-report', async (req, res) => {
  const userId = req.userId;
  const matchId = req.params.id;
  const { myUnits, opponentUnits, iWon, setScores } = req.body;

  if (myUnits == null || opponentUnits == null || iWon == null) {
    return res.status(400).json({ error: 'Missing required fields.' });
  }
  if (!isValidUnitCount(myUnits) || !isValidUnitCount(opponentUnits)) {
    return res.status(400).json({ error: 'Scores must be non-negative whole numbers.' });
  }
  if (!isValidSetScores(setScores)) {
    return res.status(400).json({ error: 'Invalid set scores — each set needs non-negative whole numbers and a winner.' });
  }

  try {
    const matchResult = await pool.query('SELECT * FROM matches WHERE id = $1', [matchId]);
    if (matchResult.rows.length === 0) {
      return res.status(404).json({ error: 'Match not found.' });
    }
    const match = matchResult.rows[0];

    if (match.status !== 'pending') {
      return res.status(409).json({ error: 'This match has no pending report to edit.' });
    }
    if (match.reported_by !== userId) {
      return res.status(403).json({ error: 'Only the player who reported this result can edit it.' });
    }

    const leagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [match.league_id]);
    const league = leagueResult.rows[0];

    const completedError = checkNotCompleted(league);
    if (completedError) {
      return res.status(400).json({ error: completedError });
    }

    const iAmPlayer1 = userId === match.player1_id || userId === match.player1_partner_id;
    const winnerId = iWon
      ? (iAmPlayer1 ? match.player1_id : match.player2_id)
      : (iAmPlayer1 ? match.player2_id : match.player1_id);
    const player1Units = iAmPlayer1 ? myUnits : opponentUnits;
    const player2Units = iAmPlayer1 ? opponentUnits : myUnits;

    await pool.query(
      `UPDATE matches SET player1_units = $1, player2_units = $2, winner_id = $3, set_scores = $4
       WHERE id = $5`,
      [player1Units, player2Units, winnerId, JSON.stringify(setScores || []), matchId]
    );

    res.status(200).json({ message: 'Report updated, still waiting for confirmation.' });
  } catch (err) {
    console.error('Edit match report error:', err);
    res.status(500).json({ error: 'Something went wrong updating the report.' });
  }
});

// ---------- HOST EDITS A CONFIRMED MATCH'S SCORE ----------
router.put('/:id/edit', async (req, res) => {
  const userId = req.userId;
  const matchId = req.params.id;
  const { player1Units, player2Units, player1Won, setScores } = req.body;

  if (player1Units == null || player2Units == null || player1Won == null) {
    return res.status(400).json({ error: 'Missing required fields.' });
  }
  if (!isValidUnitCount(player1Units) || !isValidUnitCount(player2Units)) {
    return res.status(400).json({ error: 'Scores must be non-negative whole numbers.' });
  }
  if (!isValidSetScores(setScores)) {
    return res.status(400).json({ error: 'Invalid set scores — each set needs non-negative whole numbers and a winner.' });
  }

  try {
    let hasDrift = false;

    await pool.withTransaction(async (client) => {
      const matchResult = await client.query('SELECT * FROM matches WHERE id = $1', [matchId]);
      if (matchResult.rows.length === 0) {
        throw new RouteError(404, 'Match not found.');
      }
      const match = matchResult.rows[0];

      if (match.status !== 'confirmed') {
        throw new RouteError(400, 'Only confirmed matches can be edited.');
      }

      const leagueResult = await client.query('SELECT * FROM leagues WHERE id = $1', [match.league_id]);
      const league = leagueResult.rows[0];

      if (league.created_by !== userId) {
        throw new RouteError(403, 'Only the league host can edit match scores.');
      }

      hasDrift = await checkForRatingDrift(client, match, league);

      await reverseMatchEffects(client, match, league);

      const winnerId = player1Won ? match.player1_id : match.player2_id;
      await client.query(
        `UPDATE matches SET player1_units = $1, player2_units = $2, winner_id = $3, set_scores = $4
         WHERE id = $5`,
        [player1Units, player2Units, winnerId, JSON.stringify(setScores || []), matchId]
      );

      const updatedMatchResult = await client.query('SELECT * FROM matches WHERE id = $1', [matchId]);
      await finalizeMatch(client, updatedMatchResult.rows[0], league);
    });

    res.status(200).json({
      message: 'Match updated and ratings recalculated.',
      warning: hasDrift
        ? 'One or more players have played other confirmed matches since this one — their current rating may not perfectly reflect this correction.'
        : null,
    });
  } catch (err) {
    if (err instanceof RouteError) {
      return res.status(err.statusCode).json({ error: err.message });
    }
    console.error('Edit match error:', err);
    res.status(500).json({ error: 'Something went wrong editing the match.' });
  }
});

// ---------- HOST DELETES A MATCH (confirmed or pending) ----------
router.delete('/:id', async (req, res) => {
  const userId = req.userId;
  const matchId = req.params.id;

  try {
    let warning = null;

    await pool.withTransaction(async (client) => {
      const matchResult = await client.query('SELECT * FROM matches WHERE id = $1', [matchId]);
      if (matchResult.rows.length === 0) {
        throw new RouteError(404, 'Match not found.');
      }
      const match = matchResult.rows[0];

      const leagueResult = await client.query('SELECT * FROM leagues WHERE id = $1', [match.league_id]);
      const league = leagueResult.rows[0];

      if (league.created_by !== userId) {
        throw new RouteError(403, 'Only the league host can delete a match.');
      }

      if (match.status === 'confirmed') {
        const hasDrift = await checkForRatingDrift(client, match, league);
        if (hasDrift) {
          warning = 'One or more players have played other confirmed matches since this one — their current rating may not perfectly reflect this reversal.';
        }
        await reverseMatchEffects(client, match, league);
      }

      await client.query('DELETE FROM matches WHERE id = $1', [matchId]);
    });

    res.status(200).json({ message: 'Match deleted.', warning });
  } catch (err) {
    if (err instanceof RouteError) {
      return res.status(err.statusCode).json({ error: err.message });
    }
    console.error('Delete match error:', err);
    res.status(500).json({ error: 'Something went wrong deleting the match.' });
  }
});

module.exports = router;