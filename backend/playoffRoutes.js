// playoffRoutes.js
const express = require('express');
const router = express.Router();
const pool = require('./db');
const { calculateNewRatings, reverseRatingChange } = require('./ratingEngine');
const { createNotifications } = require('./notifications');
const { findSchedulingConflicts } = require('./scheduling');
const { isLeagueAdmin } = require('./authorization');
const { recordAudit } = require('./audit');
const { RouteError } = pool;

// Generates standard tournament bracket seed order for any power-of-two size,
// e.g. size=8 -> [1,8,4,5,2,7,3,6] (grouped in pairs: 1v8, 4v5, 2v7, 3v6),
// ensuring top seeds can't meet until later rounds.
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

function isPowerOfTwo(n) {
  return n > 0 && (n & (n - 1)) === 0;
}

// Smallest power of two >= n. A bracket for a non-power-of-two field is
// built at this size, with (result - n) byes — real entrants beyond a
// bracket the exact right size for them just don't exist, so those seed
// slots are left empty and their pairing partner (a real entrant) advances
// without playing. See the bye-handling in POST /:leagueId/generate below.
function nextPowerOfTwo(n) {
  let p = 1;
  while (p < n) p *= 2;
  return p;
}

// Same guard leagueRoutes.js/matchRoutes.js use — kept as a local copy here
// since this file has no shared module with them. Returns a user-facing
// error string if the league has been marked completed (read-only), or null
// if it's still active.
function checkNotCompleted(league) {
  if (league.status === 'completed') {
    return 'This tournament has been marked completed and is now read-only.';
  }
  return null;
}

// Same validation as matchRoutes.js — kept separate here since this file
// has no shared module with matchRoutes.js.
const MAX_PLAUSIBLE_UNITS = 500;

function isValidUnitCount(value) {
  return typeof value === 'number' && Number.isInteger(value) && value >= 0 && value <= MAX_PLAUSIBLE_UNITS;
}

function isValidSetScores(setScores) {
  if (setScores == null) return true;
  if (!Array.isArray(setScores)) return false;
  return setScores.every((s) => {
    if (s == null || typeof s !== 'object') return false;
    if (!isValidUnitCount(s.me) || !isValidUnitCount(s.opponent)) return false;
    return s.me !== s.opponent;
  });
}

// Same guard matchRoutes.js uses — kept as a local copy here for the same
// reason as the rest of this file's duplicated helpers. Cross-checks the
// declared winner against the reported unit counts, since without this "I
// won" with a lower score than the opponent is accepted as-is.
function winnerUnitsAreConsistent(winnerIsPlayer1, player1Units, player2Units) {
  return winnerIsPlayer1 ? player1Units > player2Units : player2Units > player1Units;
}

async function getRating(db, userId, sport, format) {
  const result = await db.query(
    'SELECT rating FROM user_sports WHERE user_id = $1 AND sport = $2 AND format = $3',
    [userId, sport, format]
  );
  if (result.rows.length === 0) return null;
  return parseFloat(result.rows[0].rating);
}

// Points config resolution for a playoff/bracket match — same tournament
// config with an optional per-group override as matchRoutes.js's
// resolvePointsConfig, but playoff_matches has no scheduled_match_id to join
// through: it carries its own group_id directly (set at bracket-generation
// time for a knockout-format group, NULL for a whole-tournament bracket).
// Kept as a local copy here since this file has no shared module with
// matchRoutes.js.
async function resolvePointsConfig(db, match, league) {
  let group = null;
  if (match.group_id) {
    const result = await db.query('SELECT * FROM league_groups WHERE id = $1', [match.group_id]);
    group = result.rows[0] || null;
  }
  const enabled = (group && group.points_enabled != null) ? group.points_enabled : league.points_enabled;
  const win = (group && group.points_win != null) ? group.points_win : league.points_win;
  const loss = (group && group.points_loss != null) ? group.points_loss : league.points_loss;
  return { enabled, win, loss };
}

// Same as matchRoutes.js's awardLeaguePoints — kept as a local copy here
// since this file has no shared module with matchRoutes.js.
async function awardLeaguePoints(db, leagueId, userId, points) {
  await db.query(
    'UPDATE league_members SET points = points + $1 WHERE league_id = $2 AND user_id = $3',
    [points, leagueId, userId]
  );
}

// Resolves and awards points for a confirmed playoff match to the winner
// (+partner) and loser (+partner), returning the two amounts so the caller
// can persist them on playoff_matches.league_points_awarded/_loser.
async function awardPlayoffPoints(db, match, league) {
  const pointsConfig = await resolvePointsConfig(db, match, league);
  const winnerPoints = pointsConfig.enabled ? pointsConfig.win : 0;
  const loserPoints = pointsConfig.enabled ? pointsConfig.loss : 0;

  const team1Won = match.winner_id === match.player1_id;
  await awardLeaguePoints(db, match.league_id, match.winner_id, winnerPoints);
  if (team1Won && match.player1_partner_id) {
    await awardLeaguePoints(db, match.league_id, match.player1_partner_id, winnerPoints);
  }
  if (!team1Won && match.player2_partner_id) {
    await awardLeaguePoints(db, match.league_id, match.player2_partner_id, winnerPoints);
  }

  const loserId = team1Won ? match.player2_id : match.player1_id;
  const loserPartnerId = team1Won ? match.player2_partner_id : match.player1_partner_id;
  await awardLeaguePoints(db, match.league_id, loserId, loserPoints);
  if (loserPartnerId) {
    await awardLeaguePoints(db, match.league_id, loserPartnerId, loserPoints);
  }

  return { winnerPoints, loserPoints };
}

async function updateUserSportsRow(db, userId, sport, format, newRating, won) {
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

// Global (non-tiered) zig-zag pairing across the whole field, used for
// host_auto doubles brackets: highest rated with lowest, 2nd-highest with
// 2nd-lowest, etc.
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
      totalPoints: (a.points || 0) + (b.points || 0),
    });
    lo++;
    hi--;
  }
  return teams;
}

// Builds teams from confirmed league_members partnerships. Throws a
// user-facing error if any member lacks a confirmed partner.
function buildTeamsFromConfirmedPairs(members, league) {
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
    if (league?.gender_category === 'mixed' && m.gender != null && m.gender === partner.gender) {
      const err = new Error(`Mixed doubles pairs must be one man and one woman — ${m.username} and ${partner.username} are not.`);
      err.code = 'UNEVEN_GENDER_SPLIT';
      throw err;
    }
    teams.push({
      player1: m,
      player2: partner,
      avgRating: (parseFloat(m.rating) + parseFloat(partner.rating)) / 2,
      totalPoints: (m.points || 0) + (partner.points || 0),
    });
  }

  if (unpaired.length > 0) {
    const err = new Error('Not everyone has a confirmed partner yet. All players must be paired before the bracket can be generated.');
    err.code = 'UNPAIRED_MEMBERS';
    throw err;
  }

  return teams;
}

// GAP-13 — mixed doubles playoff pairing, same points-first/rating-tiebreak
// balancing as the host_auto branch below, just run separately across the
// men's and women's lists so every team stays 1M + 1F.
function zigZagPairMixedTeams(members) {
  const byPointsThenRating = (a, b) => {
    const pointsDiff = (b.points || 0) - (a.points || 0);
    if (pointsDiff !== 0) return pointsDiff;
    return parseFloat(b.rating) - parseFloat(a.rating);
  };
  const men = members.filter((m) => m.gender === 'M').sort(byPointsThenRating);
  const women = members.filter((m) => m.gender === 'F').sort((a, b) => -byPointsThenRating(a, b));

  if (men.length !== women.length) {
    const err = new Error(
      `Mixed doubles needs equal numbers of men and women so everyone gets paired — currently ${men.length} men and ${women.length} women. Add or remove a player, or switch to self-select/host-manual partner mode.`
    );
    err.code = 'UNEVEN_GENDER_SPLIT';
    throw err;
  }

  return men.map((man, i) => {
    const woman = women[i];
    return {
      player1: man,
      player2: woman,
      avgRating: (parseFloat(man.rating) + parseFloat(woman.rating)) / 2,
      totalPoints: (man.points || 0) + (woman.points || 0),
    };
  });
}

function resolveDoublesTeams(league, members) {
  if (league.partner_mode === 'host_auto') {
    if (league.gender_category === 'mixed') {
      return zigZagPairMixedTeams(members);
    }
    if (members.length % 2 !== 0) {
      const err = new Error(
        `Doubles needs an even number of players so everyone gets paired — currently ${members.length}. Add or remove one player, or switch to self-select/host-manual partner mode to intentionally leave someone out.`
      );
      err.code = 'ODD_MEMBER_COUNT';
      throw err;
    }
    // Balance-pair by tournament points (season performance) rather than
    // raw rating — the whole point of Playoffs is to reward how the season
    // actually went, not just long-term skill level. Rating is kept only
    // as a tiebreaker.
    const sorted = [...members].sort((a, b) => {
      const pointsDiff = (b.points || 0) - (a.points || 0);
      if (pointsDiff !== 0) return pointsDiff;
      return parseFloat(b.rating) - parseFloat(a.rating);
    });
    return zigZagPairTeams(sorted);
  }
  return buildTeamsFromConfirmedPairs(members, league);
}

// Applies rating changes for a confirmed playoff match, then advances the
// winner (and, for doubles, the winning partner) into the next round.
// Doubles: the "team rating" is the average of both partners' individual
// ratings; the engine's resulting delta is then applied equally to each
// partner's own current rating — same approach matchRoutes.js already uses
// for round-robin/custom doubles matches.
async function finalizePlayoffMatch(db, match, league) {
  const { sport, format } = league;
  const isDoubles = format === 'doubles' && match.player1_partner_id && match.player2_partner_id;
  const isWalkover = match.is_walkover === true;

  if (!isDoubles) {
    const rating1 = await getRating(db, match.player1_id, sport, format);
    const rating2 = await getRating(db, match.player2_id, sport, format);

    // Both participants must have a rating row for this sport+format before
    // a match involving them can be scored — a missing one would otherwise
    // silently corrupt the calculation (see matchRoutes.js's finalizeMatch
    // for the same guard, kept as a local copy here for the same reason as
    // the rest of this file's duplicated helpers).
    const missingId = (rating1 == null && match.player1_id) || (rating2 == null && match.player2_id) || null;
    if (missingId) {
      throw new RouteError(
        400,
        `Player ${missingId} hasn't added ${sport.replace('_', ' ')} (${format}) to their profile yet — they need to before this match can be confirmed.`
      );
    }

    const team1Won = match.winner_id === match.player1_id;

    // A walkover didn't get played, so held at the current rating (a real
    // 0 change, not skipped — see finalizeMatch's identical comment in
    // matchRoutes.js for why 0 vs null matters for reversal later).
    const { newRating1, newRating2 } = isWalkover
      ? { newRating1: rating1, newRating2: rating2 }
      : calculateNewRatings(
          sport, rating1, rating2, team1Won, match.player1_units, match.player2_units
        );

    const updatedRating1 = Math.round(newRating1 * 100) / 100;
    const updatedRating2 = Math.round(newRating2 * 100) / 100;
    const change1 = Math.round((updatedRating1 - rating1) * 100) / 100;
    const change2 = Math.round((updatedRating2 - rating2) * 100) / 100;

    await updateUserSportsRow(db, match.player1_id, sport, format, updatedRating1, team1Won);
    await updateUserSportsRow(db, match.player2_id, sport, format, updatedRating2, !team1Won);

    const { winnerPoints, loserPoints } = await awardPlayoffPoints(db, match, league);

    await db.query(
      `UPDATE playoff_matches SET status = 'confirmed',
        player1_rating_change = $1, player2_rating_change = $2,
        league_points_awarded = $3, league_points_awarded_loser = $4
       WHERE id = $5`,
      [change1, change2, winnerPoints, loserPoints, match.id]
    );
  } else {
    const r1a = await getRating(db, match.player1_id, sport, format);
    const r1b = await getRating(db, match.player1_partner_id, sport, format);
    const r2a = await getRating(db, match.player2_id, sport, format);
    const r2b = await getRating(db, match.player2_partner_id, sport, format);

    const missingId =
      (r1a == null && match.player1_id) ||
      (r1b == null && match.player1_partner_id) ||
      (r2a == null && match.player2_id) ||
      (r2b == null && match.player2_partner_id) ||
      null;
    if (missingId) {
      throw new RouteError(
        400,
        `Player ${missingId} hasn't added ${sport.replace('_', ' ')} (${format}) to their profile yet — they need to before this match can be confirmed.`
      );
    }

    const team1Rating = (r1a + r1b) / 2;
    const team2Rating = (r2a + r2b) / 2;
    const team1Won = match.winner_id === match.player1_id;

    const { newRating1: newTeam1Rating, newRating2: newTeam2Rating } = isWalkover
      ? { newRating1: team1Rating, newRating2: team2Rating }
      : calculateNewRatings(
          sport, team1Rating, team2Rating, team1Won, match.player1_units, match.player2_units
        );

    const team1Delta = newTeam1Rating - team1Rating;
    const team2Delta = newTeam2Rating - team2Rating;

    const updated1a = Math.round((r1a + team1Delta) * 100) / 100;
    const updated1b = Math.round((r1b + team1Delta) * 100) / 100;
    const updated2a = Math.round((r2a + team2Delta) * 100) / 100;
    const updated2b = Math.round((r2b + team2Delta) * 100) / 100;

    const change1a = Math.round((updated1a - r1a) * 100) / 100;
    const change1b = Math.round((updated1b - r1b) * 100) / 100;
    const change2a = Math.round((updated2a - r2a) * 100) / 100;
    const change2b = Math.round((updated2b - r2b) * 100) / 100;

    await updateUserSportsRow(db, match.player1_id, sport, format, updated1a, team1Won);
    await updateUserSportsRow(db, match.player1_partner_id, sport, format, updated1b, team1Won);
    await updateUserSportsRow(db, match.player2_id, sport, format, updated2a, !team1Won);
    await updateUserSportsRow(db, match.player2_partner_id, sport, format, updated2b, !team1Won);

    const { winnerPoints, loserPoints } = await awardPlayoffPoints(db, match, league);

    await db.query(
      `UPDATE playoff_matches SET status = 'confirmed',
        player1_rating_change = $1, player1_partner_rating_change = $2,
        player2_rating_change = $3, player2_partner_rating_change = $4,
        league_points_awarded = $5, league_points_awarded_loser = $6
       WHERE id = $7`,
      [change1a, change1b, change2a, change2b, winnerPoints, loserPoints, match.id]
    );
  }

  await advanceWinner(db, { ...match, status: 'confirmed' });
}

// Undoes the rating/stat/points effects of a previously confirmed playoff
// match — used when the host edits a confirmed score, or cancels the whole
// bracket.
async function reversePlayoffEffects(db, match, league) {
  const { sport, format } = league;
  const team1Won = match.winner_id === match.player1_id;

  await reverseRatingChange(db, match.player1_id, sport, format, match.player1_rating_change, team1Won);
  await reverseRatingChange(db, match.player2_id, sport, format, match.player2_rating_change, !team1Won);
  await reverseRatingChange(db, match.player1_partner_id, sport, format, match.player1_partner_rating_change, team1Won);
  await reverseRatingChange(db, match.player2_partner_id, sport, format, match.player2_partner_rating_change, !team1Won);

  if (match.league_points_awarded != null) {
    const winnerIds = [match.winner_id];
    if (team1Won && match.player1_partner_id) winnerIds.push(match.player1_partner_id);
    if (!team1Won && match.player2_partner_id) winnerIds.push(match.player2_partner_id);
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

// Checks if any participant in this playoff match has played another
// confirmed match (regular or knockout, same sport/format) since this one
// happened — mirrors matchRoutes.js's checkForRatingDrift, kept separate
// here since this file has no shared module with matchRoutes.js.
async function checkForRatingDriftPlayoff(db, match, league) {
  const participantIds = [
    match.player1_id, match.player2_id, match.player1_partner_id, match.player2_partner_id,
  ].filter(Boolean);

  // Table tennis shares one rating across singles/doubles — see the same
  // note in matchRoutes.js's checkForRatingDrift.
  const formatFilter = league.sport === 'table_tennis' ? null : league.format;

  const result = await db.query(
    `SELECT COUNT(*) FROM (
       SELECT pm.id FROM playoff_matches pm
       JOIN leagues l ON l.id = pm.league_id
       WHERE pm.status = 'confirmed' AND pm.id != $1
         AND l.sport = $2 AND ($3::text IS NULL OR l.format = $3)
         AND pm.created_at > $4
         AND (pm.player1_id = ANY($5::int[]) OR pm.player2_id = ANY($5::int[])
              OR pm.player1_partner_id = ANY($5::int[]) OR pm.player2_partner_id = ANY($5::int[]))
       UNION ALL
       SELECT m.id FROM matches m
       JOIN leagues l ON l.id = m.league_id
       WHERE m.status = 'confirmed'
         AND l.sport = $2 AND ($3::text IS NULL OR l.format = $3)
         AND m.created_at > $4
         AND (m.player1_id = ANY($5::int[]) OR m.player2_id = ANY($5::int[])
              OR m.player1_partner_id = ANY($5::int[]) OR m.player2_partner_id = ANY($5::int[]))
     ) drift`,
    [match.id, league.sport, formatFilter, match.created_at, participantIds]
  );
  return parseInt(result.rows[0].count, 10) > 0;
}

// ---------- GENERATE PLAYOFF BRACKET (host only, once) ----------
// qualifierCount means "number of singles players" for a singles league, or
// "number of teams" for a doubles league — both must be a power of two.
router.post('/:leagueId/generate', async (req, res) => {
  const userId = req.userId;
  const leagueId = req.params.leagueId;
  const { qualifierCount, force } = req.body;

  if (!Number.isInteger(qualifierCount) || qualifierCount < 2) {
    return res.status(400).json({ error: 'Qualifier count must be a whole number of at least 2.' });
  }

  try {
    const leagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [leagueId]);
    if (leagueResult.rows.length === 0) {
      return res.status(404).json({ error: 'Tournament not found.' });
    }
    const league = leagueResult.rows[0];

    if (!(await isLeagueAdmin(pool, league, userId))) {
      return res.status(403).json({ error: 'Only the tournament host or a co-host can start playoffs.' });
    }
    if (league.status === 'completed') {
      return res.status(400).json({ error: 'This tournament has been marked completed and is now read-only.' });
    }

    const existing = await pool.query('SELECT id FROM playoff_matches WHERE league_id = $1 LIMIT 1', [leagueId]);
    if (existing.rows.length > 0) {
      return res.status(409).json({ error: 'A bracket has already been started for this tournament.' });
    }

    // Warn (rather than block outright) if the regular season still has
    // unplayed fixtures — the host might have a good reason to start early
    // (forfeits, time constraints), so this is a confirm-to-override rather
    // than a hard stop. The client re-sends with force: true to proceed.
    if (!force) {
      const incompleteResult = await pool.query(
        `SELECT COUNT(*) FROM scheduled_matches sm
         LEFT JOIN matches m ON m.scheduled_match_id = sm.id AND m.status = 'confirmed'
         WHERE sm.league_id = $1 AND m.id IS NULL`,
        [leagueId]
      );
      const incompleteCount = parseInt(incompleteResult.rows[0].count, 10);
      if (incompleteCount > 0) {
        return res.status(409).json({
          error: incompleteCount === 1
            ? '1 match in the regular season hasn\'t been played yet.'
            : `${incompleteCount} matches in the regular season haven't been played yet.`,
          incompleteMatches: incompleteCount,
        });
      }
    }

    if (league.format === 'singles') {
      const standingsResult = await pool.query(
        `SELECT u.id, us.rating, lm.points
         FROM league_members lm
         JOIN users u ON u.id = lm.user_id
         JOIN user_sports us ON us.user_id = u.id AND us.sport = $1 AND us.format = $2
         WHERE lm.league_id = $3
         ORDER BY lm.points DESC, us.rating DESC
         LIMIT $4`,
        [league.sport, league.format, leagueId, qualifierCount]
      );
      const qualifiers = standingsResult.rows;

      if (qualifiers.length < qualifierCount) {
        return res.status(400).json({ error: `Need at least ${qualifierCount} players in the leaderboard to start this bracket size.` });
      }

      // qualifierCount is the real number of entrants, which needn't be a
      // power of two — the bracket itself is built at the next power of two
      // up, and any seed beyond qualifierCount is a bye: whichever real
      // entrant it's paired against advances immediately, no match played.
      const bracketSize = nextPowerOfTwo(qualifierCount);
      const seedOrder = generateSeedOrder(bracketSize);
      const totalRounds = Math.log2(bracketSize);
      const byeMatches = [];

      for (let i = 0; i < seedOrder.length; i += 2) {
        const seedA = seedOrder[i];
        const seedB = seedOrder[i + 1];
        const position = i / 2 + 1;
        const playerA = seedA <= qualifierCount ? qualifiers[seedA - 1] : null;
        const playerB = seedB <= qualifierCount ? qualifiers[seedB - 1] : null;

        if (playerA && playerB) {
          await pool.query(
            `INSERT INTO playoff_matches (league_id, round_number, position, player1_id, player2_id, status)
             VALUES ($1, 1, $2, $3, $4, 'ready')`,
            [leagueId, position, playerA.id, playerB.id]
          );
        } else if (playerA || playerB) {
          const byePlayer = playerA || playerB;
          const byeMatch = await pool.query(
            `INSERT INTO playoff_matches (league_id, round_number, position, player1_id, winner_id, status)
             VALUES ($1, 1, $2, $3, $3, 'bye') RETURNING *`,
            [leagueId, position, byePlayer.id]
          );
          byeMatches.push(byeMatch.rows[0]);
        } else {
          // Mathematically shouldn't happen — bracketSize is always < 2x
          // qualifierCount, so byes can never outnumber pairs. Fail loudly
          // rather than silently leave a broken round 1.
          throw new RouteError(500, 'Unexpected bracket seeding error.');
        }
      }

      for (let round = 2; round <= totalRounds; round++) {
        const matchesInRound = bracketSize / Math.pow(2, round);
        for (let pos = 1; pos <= matchesInRound; pos++) {
          await pool.query(
            `INSERT INTO playoff_matches (league_id, round_number, position, status)
             VALUES ($1, $2, $3, 'pending')`,
            [leagueId, round, pos]
          );
        }
      }

      // Round 2+ rows now exist, so byes can advance their lone player into
      // them right away — the match they're paired against was never real,
      // so there's nothing to wait on.
      for (const byeMatch of byeMatches) {
        await advanceWinner(pool, byeMatch);
      }

      return res.status(201).json({ message: 'Bracket generated.' });
    }

    // Doubles: qualifierCount = number of TEAMS.
    const membersResult = await pool.query(
      `SELECT u.id, u.username, u.gender, us.rating, lm.partner_id, lm.partner_status, lm.points
       FROM league_members lm
       JOIN users u ON u.id = lm.user_id
       JOIN user_sports us ON us.user_id = u.id AND us.sport = $1 AND us.format = $2
       WHERE lm.league_id = $3
       ORDER BY lm.points DESC, us.rating DESC`,
      [league.sport, league.format, leagueId]
    );
    const members = membersResult.rows;

    let teams;
    try {
      teams = resolveDoublesTeams(league, members);
    } catch (buildErr) {
      if (buildErr.code === 'UNPAIRED_MEMBERS' || buildErr.code === 'ODD_MEMBER_COUNT' || buildErr.code === 'UNEVEN_GENDER_SPLIT') {
        return res.status(400).json({ error: buildErr.message });
      }
      throw buildErr;
    }

    // Seed by combined tournament points earned this season, not raw
    // rating — rating only breaks ties between equally-performing teams.
    teams.sort((a, b) => {
      const pointsDiff = b.totalPoints - a.totalPoints;
      if (pointsDiff !== 0) return pointsDiff;
      return b.avgRating - a.avgRating;
    });

    if (teams.length < qualifierCount) {
      return res.status(400).json({ error: `Need at least ${qualifierCount} teams to start this bracket size. Currently have ${teams.length} team(s) from ${members.length} player(s).` });
    }
    const qualifierTeams = teams.slice(0, qualifierCount);

    const bracketSize = nextPowerOfTwo(qualifierCount);
    const seedOrder = generateSeedOrder(bracketSize);
    const totalRounds = Math.log2(bracketSize);
    const byeMatches = [];

    for (let i = 0; i < seedOrder.length; i += 2) {
      const seedA = seedOrder[i];
      const seedB = seedOrder[i + 1];
      const position = i / 2 + 1;
      const teamA = seedA <= qualifierCount ? qualifierTeams[seedA - 1] : null;
      const teamB = seedB <= qualifierCount ? qualifierTeams[seedB - 1] : null;

      if (teamA && teamB) {
        await pool.query(
          `INSERT INTO playoff_matches
            (league_id, round_number, position, player1_id, player1_partner_id, player2_id, player2_partner_id, status)
           VALUES ($1, 1, $2, $3, $4, $5, $6, 'ready')`,
          [leagueId, position, teamA.player1.id, teamA.player2.id, teamB.player1.id, teamB.player2.id]
        );
      } else if (teamA || teamB) {
        const byeTeam = teamA || teamB;
        const byeMatch = await pool.query(
          `INSERT INTO playoff_matches
            (league_id, round_number, position, player1_id, player1_partner_id, winner_id, status)
           VALUES ($1, 1, $2, $3, $4, $3, 'bye') RETURNING *`,
          [leagueId, position, byeTeam.player1.id, byeTeam.player2.id]
        );
        byeMatches.push(byeMatch.rows[0]);
      } else {
        throw new RouteError(500, 'Unexpected bracket seeding error.');
      }
    }

    for (let round = 2; round <= totalRounds; round++) {
      const matchesInRound = bracketSize / Math.pow(2, round);
      for (let pos = 1; pos <= matchesInRound; pos++) {
        await pool.query(
          `INSERT INTO playoff_matches (league_id, round_number, position, status)
           VALUES ($1, $2, $3, 'pending')`,
          [leagueId, round, pos]
        );
      }
    }

    for (const byeMatch of byeMatches) {
      await advanceWinner(pool, byeMatch);
    }

    res.status(201).json({ message: 'Bracket generated.' });
  } catch (err) {
    console.error('Generate playoffs error:', err);
    res.status(500).json({ error: 'Something went wrong generating the bracket.' });
  }
});

// ---------- CANCEL/REMOVE PLAYOFF BRACKET (host only) ----------
// Reverses rating effects from any already-confirmed matches first, so
// cancelling a mistakenly-started bracket cleanly undoes everything.
router.delete('/:leagueId', async (req, res) => {
  const userId = req.userId;
  const leagueId = req.params.leagueId;

  try {
    await pool.withTransaction(async (client) => {
      const leagueResult = await client.query('SELECT * FROM leagues WHERE id = $1', [leagueId]);
      if (leagueResult.rows.length === 0) {
        throw new RouteError(404, 'Tournament not found.');
      }
      const league = leagueResult.rows[0];

      if (!(await isLeagueAdmin(client, league, userId))) {
        throw new RouteError(403, 'Only the tournament host or a co-host can remove the playoff bracket.');
      }

      const confirmedMatches = await client.query(
        `SELECT * FROM playoff_matches WHERE league_id = $1 AND status = 'confirmed'`,
        [leagueId]
      );
      for (const match of confirmedMatches.rows) {
        await reversePlayoffEffects(client, match, league);
      }

      const result = await client.query('DELETE FROM playoff_matches WHERE league_id = $1', [leagueId]);
      if (result.rowCount === 0) {
        throw new RouteError(404, 'No playoff bracket exists for this tournament.');
      }

      await recordAudit(client, {
        leagueId,
        actorId: userId,
        action: 'cancel_bracket',
        summary: 'Removed the playoff bracket.',
      });
    });

    res.status(200).json({ message: 'Playoff bracket removed.' });
  } catch (err) {
    if (err instanceof RouteError) {
      return res.status(err.statusCode).json({ error: err.message });
    }
    console.error('Remove playoffs error:', err);
    res.status(500).json({ error: 'Something went wrong removing the bracket.' });
  }
});

// ---------- GET BRACKET ----------
router.get('/:leagueId', async (req, res) => {
  const leagueId = req.params.leagueId;

  try {
    const result = await pool.query(
      `SELECT pm.*,
              p1.username as player1_username, p2.username as player2_username,
              pp1.username as player1_partner_username, pp2.username as player2_partner_username
       FROM playoff_matches pm
       LEFT JOIN users p1 ON p1.id = pm.player1_id
       LEFT JOIN users p2 ON p2.id = pm.player2_id
       LEFT JOIN users pp1 ON pp1.id = pm.player1_partner_id
       LEFT JOIN users pp2 ON pp2.id = pm.player2_partner_id
       WHERE pm.league_id = $1
       ORDER BY pm.round_number ASC, pm.position ASC`,
      [leagueId]
    );
    res.status(200).json({ bracket: result.rows });
  } catch (err) {
    console.error('Get bracket error:', err);
    res.status(500).json({ error: 'Something went wrong fetching the bracket.' });
  }
});

// ---------- GET ONE GROUP'S KNOCKOUT BRACKET ----------
// Same shape as GET /:leagueId above, just scoped to a single knockout-format
// group within a Groups tournament — that group's bracket is generated at
// lock time (see POST /leagues/:id/groups/:groupId/lock), not through the
// /generate route above, but every per-match action route below is already
// matchId-scoped and works unmodified for these rows.
router.get('/:leagueId/group/:groupId', async (req, res) => {
  const { leagueId, groupId } = req.params;

  try {
    const result = await pool.query(
      `SELECT pm.*,
              p1.username as player1_username, p2.username as player2_username,
              pp1.username as player1_partner_username, pp2.username as player2_partner_username
       FROM playoff_matches pm
       LEFT JOIN users p1 ON p1.id = pm.player1_id
       LEFT JOIN users p2 ON p2.id = pm.player2_id
       LEFT JOIN users pp1 ON pp1.id = pm.player1_partner_id
       LEFT JOIN users pp2 ON pp2.id = pm.player2_partner_id
       WHERE pm.league_id = $1 AND pm.group_id = $2
       ORDER BY pm.round_number ASC, pm.position ASC`,
      [leagueId, groupId]
    );
    res.status(200).json({ bracket: result.rows });
  } catch (err) {
    console.error('Get group bracket error:', err);
    res.status(500).json({ error: "Something went wrong fetching this group's bracket." });
  }
});

async function advanceWinner(db, match) {
  const nextRound = match.round_number + 1;
  const nextPosition = Math.ceil(match.position / 2);
  const isUpperSlot = match.position % 2 === 1;

  const winnerPartnerId = match.winner_id === match.player1_id ? match.player1_partner_id : match.player2_partner_id;

  // group_id must match too (via IS NOT DISTINCT FROM, since group_id is
  // nullable and plain `=` never matches NULL to NULL) — otherwise two
  // different knockout-format groups in the same league, whose round/
  // position numbering both restart at 1, could collide and advance a
  // winner into the wrong group's bracket.
  const nextMatchResult = await db.query(
    'SELECT * FROM playoff_matches WHERE league_id = $1 AND round_number = $2 AND position = $3 AND group_id IS NOT DISTINCT FROM $4',
    [match.league_id, nextRound, nextPosition, match.group_id]
  );

  if (nextMatchResult.rows.length > 0) {
    const nextMatch = nextMatchResult.rows[0];
    if (isUpperSlot) {
      await db.query(
        'UPDATE playoff_matches SET player1_id = $1, player1_partner_id = $2 WHERE id = $3',
        [match.winner_id, winnerPartnerId, nextMatch.id]
      );
    } else {
      await db.query(
        'UPDATE playoff_matches SET player2_id = $1, player2_partner_id = $2 WHERE id = $3',
        [match.winner_id, winnerPartnerId, nextMatch.id]
      );
    }

    const updatedNextMatch = await db.query('SELECT * FROM playoff_matches WHERE id = $1', [nextMatch.id]);
    const um = updatedNextMatch.rows[0];
    if (um.player1_id && um.player2_id) {
      await db.query(`UPDATE playoff_matches SET status = 'ready' WHERE id = $1`, [nextMatch.id]);
    }
  }
}

// ---------- REPORT A PLAYOFF MATCH RESULT (self, needs opponent confirmation) ----------
router.post('/match/:matchId/report', async (req, res) => {
  const userId = req.userId;
  const matchId = req.params.matchId;
  const { myUnits, opponentUnits, iWon, setScores, photoUrl } = req.body;

  if (myUnits == null || opponentUnits == null || iWon == null) {
    return res.status(400).json({ error: 'Missing required fields.' });
  }
  if (!isValidUnitCount(myUnits) || !isValidUnitCount(opponentUnits)) {
    return res.status(400).json({ error: 'Scores must be non-negative whole numbers.' });
  }
  if (!isValidSetScores(setScores)) {
    return res.status(400).json({ error: 'Invalid set scores — each set needs non-negative whole numbers and a winner.' });
  }
  if (!winnerUnitsAreConsistent(iWon, myUnits, opponentUnits)) {
    return res.status(400).json({ error: "The declared winner's score must be higher than the opponent's." });
  }

  try {
    const matchResult = await pool.query('SELECT * FROM playoff_matches WHERE id = $1', [matchId]);
    if (matchResult.rows.length === 0) {
      return res.status(404).json({ error: 'Match not found.' });
    }
    const match = matchResult.rows[0];

    const leagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [match.league_id]);
    const league = leagueResult.rows[0];
    if (league.status === 'completed') {
      return res.status(400).json({ error: 'This tournament has been marked completed and is now read-only.' });
    }
    if (league.host_enters_scores) {
      return res.status(403).json({ error: 'This tournament requires the host to enter all scores.' });
    }

    if (match.status !== 'ready') {
      return res.status(409).json({ error: 'This match is not ready to be reported.' });
    }
    const participantIds = [match.player1_id, match.player2_id, match.player1_partner_id, match.player2_partner_id].filter(Boolean);
    if (!participantIds.includes(userId)) {
      return res.status(403).json({ error: 'You are not part of this match.' });
    }

    const onSideOne = userId === match.player1_id || userId === match.player1_partner_id;
    const winnerId = iWon ? (onSideOne ? match.player1_id : match.player2_id)
                          : (onSideOne ? match.player2_id : match.player1_id);
    const player1Units = onSideOne ? myUnits : opponentUnits;
    const player2Units = onSideOne ? opponentUnits : myUnits;

    await pool.query(
      `UPDATE playoff_matches SET status = 'reported', reported_by = $1,
        player1_units = $2, player2_units = $3, winner_id = $4, set_scores = $5, photo_url = $6
       WHERE id = $7`,
      [userId, player1Units, player2Units, winnerId, JSON.stringify(setScores || []), photoUrl || null, matchId]
    );

    res.status(200).json({ message: 'Result reported, waiting for confirmation.' });
  } catch (err) {
    console.error('Report playoff match error:', err);
    res.status(500).json({ error: 'Something went wrong reporting the result.' });
  }
});

// ---------- REPORTER EDITS THEIR OWN PENDING PLAYOFF REPORT ----------
router.put('/match/:matchId/edit-report', async (req, res) => {
  const userId = req.userId;
  const matchId = req.params.matchId;
  const { myUnits, opponentUnits, iWon, setScores, photoUrl } = req.body;

  if (myUnits == null || opponentUnits == null || iWon == null) {
    return res.status(400).json({ error: 'Missing required fields.' });
  }
  if (!isValidUnitCount(myUnits) || !isValidUnitCount(opponentUnits)) {
    return res.status(400).json({ error: 'Scores must be non-negative whole numbers.' });
  }
  if (!isValidSetScores(setScores)) {
    return res.status(400).json({ error: 'Invalid set scores — each set needs non-negative whole numbers and a winner.' });
  }
  if (!winnerUnitsAreConsistent(iWon, myUnits, opponentUnits)) {
    return res.status(400).json({ error: "The declared winner's score must be higher than the opponent's." });
  }

  try {
    const matchResult = await pool.query('SELECT * FROM playoff_matches WHERE id = $1', [matchId]);
    if (matchResult.rows.length === 0) {
      return res.status(404).json({ error: 'Match not found.' });
    }
    const match = matchResult.rows[0];

    if (match.status !== 'reported') {
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

    const onSideOne = userId === match.player1_id || userId === match.player1_partner_id;
    const winnerId = iWon ? (onSideOne ? match.player1_id : match.player2_id)
                          : (onSideOne ? match.player2_id : match.player1_id);
    const player1Units = onSideOne ? myUnits : opponentUnits;
    const player2Units = onSideOne ? opponentUnits : myUnits;

    // photoUrl is optional-on-edit, same as PUT /match/:matchId/edit-score
    // below: only overwrite it when the caller actually sent one, so
    // re-editing scores without touching the photo doesn't silently wipe it.
    await pool.query(
      `UPDATE playoff_matches SET player1_units = $1, player2_units = $2, winner_id = $3, set_scores = $4,
       photo_url = COALESCE($5, photo_url)
       WHERE id = $6`,
      [player1Units, player2Units, winnerId, JSON.stringify(setScores || []), photoUrl || null, matchId]
    );

    res.status(200).json({ message: 'Report updated, still waiting for confirmation.' });
  } catch (err) {
    console.error('Edit playoff report error:', err);
    res.status(500).json({ error: 'Something went wrong updating the report.' });
  }
});

// ---------- HOST ENTERS A PLAYOFF MATCH RESULT DIRECTLY (auto-confirmed) ----------
router.post('/match/:matchId/report-as-host', async (req, res) => {
  const userId = req.userId;
  const matchId = req.params.matchId;
  const { player1Units, player2Units, player1Won, setScores, photoUrl, isWalkover } = req.body;

  if (player1Won == null) {
    return res.status(400).json({ error: 'Missing required fields.' });
  }
  if (!isWalkover) {
    if (player1Units == null || player2Units == null) {
      return res.status(400).json({ error: 'Missing required fields.' });
    }
    if (!isValidUnitCount(player1Units) || !isValidUnitCount(player2Units)) {
      return res.status(400).json({ error: 'Scores must be non-negative whole numbers.' });
    }
    if (!isValidSetScores(setScores)) {
      return res.status(400).json({ error: 'Invalid set scores — each set needs non-negative whole numbers and a winner.' });
    }
    if (!winnerUnitsAreConsistent(player1Won, player1Units, player2Units)) {
      return res.status(400).json({ error: "The declared winner's score must be higher than the opponent's." });
    }
  }

  try {
    await pool.withTransaction(async (client) => {
      const matchResult = await client.query('SELECT * FROM playoff_matches WHERE id = $1', [matchId]);
      if (matchResult.rows.length === 0) {
        throw new RouteError(404, 'Match not found.');
      }
      const match = matchResult.rows[0];

      const leagueResult = await client.query('SELECT * FROM leagues WHERE id = $1', [match.league_id]);
      const league = leagueResult.rows[0];

      if (!league.host_enters_scores || !(await isLeagueAdmin(client, league, userId))) {
        throw new RouteError(403, 'Only the host can enter scores directly for this tournament.');
      }
      if (league.status === 'completed') {
        throw new RouteError(400, 'This tournament has been marked completed and is now read-only.');
      }

      if (match.status !== 'ready') {
        throw new RouteError(409, 'This match is not ready to be reported.');
      }
      if (!match.player1_id || !match.player2_id) {
        throw new RouteError(400, 'Both players for this match are not yet determined.');
      }
      if (league.format === 'doubles' && (!match.player1_partner_id || !match.player2_partner_id)) {
        throw new RouteError(400, 'Both teams for this match are not yet fully determined.');
      }

      const winnerId = player1Won ? match.player1_id : match.player2_id;

      await client.query(
        `UPDATE playoff_matches SET reported_by = $1,
          player1_units = $2, player2_units = $3, winner_id = $4, set_scores = $5, photo_url = $6, is_walkover = $7
         WHERE id = $8`,
        [
          userId,
          isWalkover ? 0 : player1Units,
          isWalkover ? 0 : player2Units,
          winnerId,
          isWalkover ? '[]' : JSON.stringify(setScores || []),
          photoUrl || null,
          isWalkover === true,
          matchId,
        ]
      );

      const updatedMatchResult = await client.query('SELECT * FROM playoff_matches WHERE id = $1', [matchId]);
      const updatedMatch = updatedMatchResult.rows[0];
      await finalizePlayoffMatch(client, updatedMatch, league);

      await createNotifications(
        client,
        [updatedMatch.player1_id, updatedMatch.player1_partner_id, updatedMatch.player2_id, updatedMatch.player2_partner_id],
        {
          type: 'match_confirmed',
          title: 'Match result entered',
          body: `The host entered a confirmed score for your bracket match in ${league.name}.`,
          leagueId: league.id,
        }
      );
    });

    res.status(200).json({ message: 'Match confirmed.' });
  } catch (err) {
    if (err instanceof RouteError) {
      return res.status(err.statusCode).json({ error: err.message });
    }
    console.error('Host report playoff match error:', err);
    res.status(500).json({ error: 'Something went wrong entering the score.' });
  }
});

// ---------- HOST EDITS A CONFIRMED PLAYOFF MATCH SCORE ----------
// Reverses the old rating/stat effects, updates the score, then reapplies
// ratings fresh from current standings. If the winner changes and the next
// round has already been played, editing is blocked — the host should
// cancel and restart the bracket instead of risking a corrupted cascade.
router.put('/match/:matchId/edit-score', async (req, res) => {
  const userId = req.userId;
  const matchId = req.params.matchId;
  const { player1Units, player2Units, player1Won, setScores, photoUrl, isWalkover } = req.body;

  if (player1Won == null) {
    return res.status(400).json({ error: 'Missing required fields.' });
  }
  if (!isWalkover) {
    if (player1Units == null || player2Units == null) {
      return res.status(400).json({ error: 'Missing required fields.' });
    }
    if (!isValidUnitCount(player1Units) || !isValidUnitCount(player2Units)) {
      return res.status(400).json({ error: 'Scores must be non-negative whole numbers.' });
    }
    if (!isValidSetScores(setScores)) {
      return res.status(400).json({ error: 'Invalid set scores — each set needs non-negative whole numbers and a winner.' });
    }
    if (!winnerUnitsAreConsistent(player1Won, player1Units, player2Units)) {
      return res.status(400).json({ error: "The declared winner's score must be higher than the opponent's." });
    }
  }

  try {
    let hasDrift = false;
    let winnerChanged = false;

    await pool.withTransaction(async (client) => {
      const matchResult = await client.query('SELECT * FROM playoff_matches WHERE id = $1', [matchId]);
      if (matchResult.rows.length === 0) {
        throw new RouteError(404, 'Match not found.');
      }
      const match = matchResult.rows[0];

      if (match.status !== 'confirmed') {
        throw new RouteError(400, 'Only confirmed matches can be edited.');
      }

      const leagueResult = await client.query('SELECT * FROM leagues WHERE id = $1', [match.league_id]);
      const league = leagueResult.rows[0];
      if (!(await isLeagueAdmin(client, league, userId))) {
        throw new RouteError(403, 'Only the tournament host or a co-host can edit match scores.');
      }

      const newWinnerId = player1Won ? match.player1_id : match.player2_id;
      winnerChanged = newWinnerId !== match.winner_id;

      if (winnerChanged) {
        const nextRound = match.round_number + 1;
        const nextPosition = Math.ceil(match.position / 2);
        const nextMatchResult = await client.query(
          'SELECT * FROM playoff_matches WHERE league_id = $1 AND round_number = $2 AND position = $3 AND group_id IS NOT DISTINCT FROM $4',
          [match.league_id, nextRound, nextPosition, match.group_id]
        );

        if (nextMatchResult.rows.length > 0) {
          const nextMatch = nextMatchResult.rows[0];
          if (nextMatch.status === 'reported' || nextMatch.status === 'confirmed') {
            throw new RouteError(400, 'The next round has already been played with the old winner. Cancel and restart the playoffs to fix this.');
          }
        }
      }

      // Check for drift BEFORE reversing, since the reversal itself inserts a
      // change that would otherwise be picked up by the same query.
      hasDrift = await checkForRatingDriftPlayoff(client, match, league);

      // Reverse the old rating effects before touching anything else.
      await reversePlayoffEffects(client, match, league);

      await client.query(
        `UPDATE playoff_matches SET player1_units = $1, player2_units = $2, winner_id = $3, set_scores = $4,
           photo_url = COALESCE($5, photo_url), is_walkover = $6
         WHERE id = $7`,
        [
          isWalkover ? 0 : player1Units,
          isWalkover ? 0 : player2Units,
          newWinnerId,
          isWalkover ? '[]' : JSON.stringify(setScores || []),
          photoUrl || null,
          isWalkover === true,
          matchId,
        ]
      );

      if (winnerChanged) {
        const nextRound = match.round_number + 1;
        const nextPosition = Math.ceil(match.position / 2);
        const nextMatchResult = await client.query(
          'SELECT * FROM playoff_matches WHERE league_id = $1 AND round_number = $2 AND position = $3 AND group_id IS NOT DISTINCT FROM $4',
          [match.league_id, nextRound, nextPosition, match.group_id]
        );
        if (nextMatchResult.rows.length > 0) {
          const nextMatch = nextMatchResult.rows[0];
          const isUpperSlot = match.position % 2 === 1;
          const newWinnerPartnerId = newWinnerId === match.player1_id ? match.player1_partner_id : match.player2_partner_id;
          if (isUpperSlot) {
            await client.query(
              'UPDATE playoff_matches SET player1_id = $1, player1_partner_id = $2 WHERE id = $3',
              [newWinnerId, newWinnerPartnerId, nextMatch.id]
            );
          } else {
            await client.query(
              'UPDATE playoff_matches SET player2_id = $1, player2_partner_id = $2 WHERE id = $3',
              [newWinnerId, newWinnerPartnerId, nextMatch.id]
            );
          }
          const refreshedNext = await client.query('SELECT * FROM playoff_matches WHERE id = $1', [nextMatch.id]);
          const rn = refreshedNext.rows[0];
          await client.query(
            `UPDATE playoff_matches SET status = $1 WHERE id = $2`,
            [rn.player1_id && rn.player2_id ? 'ready' : 'pending', nextMatch.id]
          );
        }
      }

      // Reapply ratings fresh, based on current (post-reversal) standings.
      const updatedMatchResult = await client.query('SELECT * FROM playoff_matches WHERE id = $1', [matchId]);
      const updatedMatch = updatedMatchResult.rows[0];
      const isDoubles = league.format === 'doubles' && updatedMatch.player1_partner_id && updatedMatch.player2_partner_id;

      if (!isDoubles) {
        const rating1 = await getRating(client, updatedMatch.player1_id, league.sport, league.format);
        const rating2 = await getRating(client, updatedMatch.player2_id, league.sport, league.format);

        const missingId1 = (rating1 == null && updatedMatch.player1_id) || (rating2 == null && updatedMatch.player2_id) || null;
        if (missingId1) {
          throw new RouteError(
            400,
            `Player ${missingId1} hasn't added ${league.sport.replace('_', ' ')} (${league.format}) to their profile yet — they need to before this score can be re-applied.`
          );
        }

        const team1Won = updatedMatch.winner_id === updatedMatch.player1_id;
        const { newRating1, newRating2 } = updatedMatch.is_walkover
          ? { newRating1: rating1, newRating2: rating2 }
          : calculateNewRatings(
              league.sport, rating1, rating2, team1Won, updatedMatch.player1_units, updatedMatch.player2_units
            );
        const updatedRating1 = Math.round(newRating1 * 100) / 100;
        const updatedRating2 = Math.round(newRating2 * 100) / 100;
        const change1 = Math.round((updatedRating1 - rating1) * 100) / 100;
        const change2 = Math.round((updatedRating2 - rating2) * 100) / 100;

        await updateUserSportsRow(client, updatedMatch.player1_id, league.sport, league.format, updatedRating1, team1Won);
        await updateUserSportsRow(client, updatedMatch.player2_id, league.sport, league.format, updatedRating2, !team1Won);

        // reversePlayoffEffects already reversed the old points award above
        // (before winner/score were updated) — resolve and award fresh
        // points now, since the winner may have changed.
        const { winnerPoints, loserPoints } = await awardPlayoffPoints(client, updatedMatch, league);

        await client.query(
          `UPDATE playoff_matches SET player1_rating_change = $1, player2_rating_change = $2,
            player1_partner_rating_change = NULL, player2_partner_rating_change = NULL,
            league_points_awarded = $3, league_points_awarded_loser = $4 WHERE id = $5`,
          [change1, change2, winnerPoints, loserPoints, matchId]
        );
      } else {
        const r1a = await getRating(client, updatedMatch.player1_id, league.sport, league.format);
        const r1b = await getRating(client, updatedMatch.player1_partner_id, league.sport, league.format);
        const r2a = await getRating(client, updatedMatch.player2_id, league.sport, league.format);
        const r2b = await getRating(client, updatedMatch.player2_partner_id, league.sport, league.format);

        const missingId2 =
          (r1a == null && updatedMatch.player1_id) ||
          (r1b == null && updatedMatch.player1_partner_id) ||
          (r2a == null && updatedMatch.player2_id) ||
          (r2b == null && updatedMatch.player2_partner_id) ||
          null;
        if (missingId2) {
          throw new RouteError(
            400,
            `Player ${missingId2} hasn't added ${league.sport.replace('_', ' ')} (${league.format}) to their profile yet — they need to before this score can be re-applied.`
          );
        }

        const team1Rating = (r1a + r1b) / 2;
        const team2Rating = (r2a + r2b) / 2;
        const team1Won = updatedMatch.winner_id === updatedMatch.player1_id;

        const { newRating1: newTeam1Rating, newRating2: newTeam2Rating } = updatedMatch.is_walkover
          ? { newRating1: team1Rating, newRating2: team2Rating }
          : calculateNewRatings(
              league.sport, team1Rating, team2Rating, team1Won, updatedMatch.player1_units, updatedMatch.player2_units
            );

        const team1Delta = newTeam1Rating - team1Rating;
        const team2Delta = newTeam2Rating - team2Rating;

        const updated1a = Math.round((r1a + team1Delta) * 100) / 100;
        const updated1b = Math.round((r1b + team1Delta) * 100) / 100;
        const updated2a = Math.round((r2a + team2Delta) * 100) / 100;
        const updated2b = Math.round((r2b + team2Delta) * 100) / 100;

        const change1a = Math.round((updated1a - r1a) * 100) / 100;
        const change1b = Math.round((updated1b - r1b) * 100) / 100;
        const change2a = Math.round((updated2a - r2a) * 100) / 100;
        const change2b = Math.round((updated2b - r2b) * 100) / 100;

        await updateUserSportsRow(client, updatedMatch.player1_id, league.sport, league.format, updated1a, team1Won);
        await updateUserSportsRow(client, updatedMatch.player1_partner_id, league.sport, league.format, updated1b, team1Won);
        await updateUserSportsRow(client, updatedMatch.player2_id, league.sport, league.format, updated2a, !team1Won);
        await updateUserSportsRow(client, updatedMatch.player2_partner_id, league.sport, league.format, updated2b, !team1Won);

        const { winnerPoints, loserPoints } = await awardPlayoffPoints(client, updatedMatch, league);

        await client.query(
          `UPDATE playoff_matches SET player1_rating_change = $1, player1_partner_rating_change = $2,
            player2_rating_change = $3, player2_partner_rating_change = $4,
            league_points_awarded = $5, league_points_awarded_loser = $6 WHERE id = $7`,
          [change1a, change1b, change2a, change2b, winnerPoints, loserPoints, matchId]
        );
      }

      await recordAudit(client, {
        leagueId: match.league_id,
        actorId: userId,
        action: 'edit_playoff_score',
        summary: `Edited confirmed playoff match #${matchId}.`,
      });
    });

    const warnings = [];
    if (winnerChanged) {
      warnings.push('The winner changed — the next round fixture has been updated accordingly.');
    }
    if (hasDrift) {
      warnings.push('One or more players have played other confirmed matches since this one — their current rating may not perfectly reflect this correction.');
    }

    res.status(200).json({
      message: 'Score updated and ratings recalculated.',
      warning: warnings.length > 0 ? warnings.join(' ') : null,
    });
  } catch (err) {
    if (err instanceof RouteError) {
      return res.status(err.statusCode).json({ error: err.message });
    }
    console.error('Edit playoff score error:', err);
    res.status(500).json({ error: 'Something went wrong updating the score.' });
  }
});

// ---------- CONFIRM A PLAYOFF MATCH RESULT ----------
router.post('/match/:matchId/confirm', async (req, res) => {
  const userId = req.userId;
  const matchId = req.params.matchId;

  try {
    await pool.withTransaction(async (client) => {
      // Lock the row for the duration of the transaction — see the same
      // pattern (and why) in matchRoutes.js's /:id/confirm.
      const matchResult = await client.query('SELECT * FROM playoff_matches WHERE id = $1 FOR UPDATE', [matchId]);
      if (matchResult.rows.length === 0) {
        throw new RouteError(404, 'Match not found.');
      }
      const match = matchResult.rows[0];

      if (match.status !== 'reported') {
        throw new RouteError(409, 'This match has no pending report to confirm.');
      }
      const participantIds = [match.player1_id, match.player2_id, match.player1_partner_id, match.player2_partner_id].filter(Boolean);
      if (!participantIds.includes(userId)) {
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

      await finalizePlayoffMatch(client, match, league);

      await createNotifications(
        client,
        participantIds.filter((id) => id !== userId),
        {
          type: 'match_confirmed',
          title: 'Match confirmed',
          body: `Your bracket match in ${league.name} was confirmed and ratings were updated.`,
          leagueId: match.league_id,
        }
      );
    });

    res.status(200).json({ message: 'Match confirmed.' });
  } catch (err) {
    if (err instanceof RouteError) {
      return res.status(err.statusCode).json({ error: err.message });
    }
    console.error('Confirm playoff match error:', err);
    res.status(500).json({ error: 'Something went wrong confirming the match.' });
  }
});

// ---------- REJECT A PLAYOFF MATCH RESULT ----------
router.post('/match/:matchId/reject', async (req, res) => {
  const userId = req.userId;
  const matchId = req.params.matchId;

  try {
    const matchResult = await pool.query('SELECT * FROM playoff_matches WHERE id = $1', [matchId]);
    if (matchResult.rows.length === 0) {
      return res.status(404).json({ error: 'Match not found.' });
    }
    const match = matchResult.rows[0];

    if (match.status !== 'reported') {
      return res.status(409).json({ error: 'This match has no pending report to reject.' });
    }
    const participantIds = [match.player1_id, match.player2_id, match.player1_partner_id, match.player2_partner_id].filter(Boolean);
    if (!participantIds.includes(userId)) {
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

    await pool.query(
      `UPDATE playoff_matches SET status = 'ready', reported_by = NULL, winner_id = NULL,
        player1_units = NULL, player2_units = NULL, set_scores = NULL
       WHERE id = $1`,
      [matchId]
    );

    const reporterSide = [match.player1_id, match.player1_partner_id].includes(match.reported_by)
      ? [match.player1_id, match.player1_partner_id]
      : [match.player2_id, match.player2_partner_id];
    await createNotifications(pool, reporterSide, {
      type: 'match_rejected',
      title: 'Score rejected',
      body: `Your reported bracket score in ${league.name} was rejected. You can report it again.`,
      leagueId: match.league_id,
    });

    res.status(200).json({ message: 'Result rejected. It can be reported again.' });
  } catch (err) {
    console.error('Reject playoff match error:', err);
    res.status(500).json({ error: 'Something went wrong rejecting the match.' });
  }
});

// ---------- SET/EDIT A PLAYOFF MATCH'S SCHEDULE (host only) ----------
// Unlike scheduled_matches's equivalent route, this never touches
// player1Id/player2Id — knockout slots are filled by bracket progression
// (advanceWinner), not manually, so this only ever writes scheduled_time/venue.
router.put('/match/:matchId/schedule', async (req, res) => {
  const userId = req.userId;
  const matchId = req.params.matchId;
  const { scheduledTime, venue, force } = req.body;

  if (venue && venue.length > 200) {
    return res.status(400).json({ error: 'Venue must be 200 characters or fewer.' });
  }

  try {
    const matchResult = await pool.query('SELECT * FROM playoff_matches WHERE id = $1', [matchId]);
    if (matchResult.rows.length === 0) {
      return res.status(404).json({ error: 'Match not found.' });
    }
    const match = matchResult.rows[0];

    const leagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [match.league_id]);
    const league = leagueResult.rows[0];

    if (!(await isLeagueAdmin(pool, league, userId))) {
      return res.status(403).json({ error: 'Only the tournament host or a co-host can edit the schedule.' });
    }
    const completedError = checkNotCompleted(league);
    if (completedError) {
      return res.status(400).json({ error: completedError });
    }

    if (scheduledTime && !force) {
      const conflicts = await findSchedulingConflicts(pool, {
        userIds: [match.player1_id, match.player1_partner_id, match.player2_id, match.player2_partner_id],
        scheduledTime,
        excludePlayoffMatchId: matchId,
      });
      if (conflicts.length > 0) {
        return res.status(409).json({
          error: 'One or more players already have a match scheduled around this time.',
          conflicts,
        });
      }
    }

    await pool.query(
      `UPDATE playoff_matches SET scheduled_time = $1, venue = $2 WHERE id = $3`,
      [scheduledTime || null, venue || null, matchId]
    );

    res.status(200).json({ message: 'Match schedule updated.' });
  } catch (err) {
    console.error('Edit playoff schedule error:', err);
    res.status(500).json({ error: 'Something went wrong updating the schedule.' });
  }
});

// Attached the same way matchRoutes.js attaches resolvePointsConfig, and
// db.js attaches withTransaction/RouteError to the pool — module-private
// helpers the test suite can reach without changing how server.js consumes
// this file (`app.use('/api/playoffs', ..., require('./playoffRoutes'))`
// still gets a router).
router.resolvePointsConfig = resolvePointsConfig;
router.awardPlayoffPoints = awardPlayoffPoints;
router.reversePlayoffEffects = reversePlayoffEffects;
router.advanceWinner = advanceWinner;
router.nextPowerOfTwo = nextPowerOfTwo;

module.exports = router;