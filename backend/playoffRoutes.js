// playoffRoutes.js
const express = require('express');
const router = express.Router();
const pool = require('./db');
const { calculateNewRatings } = require('./ratingEngine');

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

async function getRating(userId, sport, format) {
  const result = await pool.query(
    'SELECT rating FROM user_sports WHERE user_id = $1 AND sport = $2 AND format = $3',
    [userId, sport, format]
  );
  if (result.rows.length === 0) return null;
  return parseFloat(result.rows[0].rating);
}

async function updateUserSportsRow(userId, sport, format, newRating, won) {
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
    });
    lo++;
    hi--;
  }
  return teams;
}

// Builds teams from confirmed league_members partnerships. Throws a
// user-facing error if any member lacks a confirmed partner.
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
    const err = new Error('Not everyone has a confirmed partner yet. All players must be paired before the bracket can be generated.');
    err.code = 'UNPAIRED_MEMBERS';
    throw err;
  }

  return teams;
}

function resolveDoublesTeams(league, members) {
  if (league.partner_mode === 'host_auto') {
    const sorted = [...members].sort((a, b) => parseFloat(b.rating) - parseFloat(a.rating));
    return zigZagPairTeams(sorted);
  }
  return buildTeamsFromConfirmedPairs(members);
}

// Applies rating changes for a confirmed playoff match, then advances the
// winner (and, for doubles, the winning partner) into the next round.
// Doubles: the "team rating" is the average of both partners' individual
// ratings; the engine's resulting delta is then applied equally to each
// partner's own current rating — same approach matchRoutes.js already uses
// for round-robin/custom doubles matches.
async function finalizePlayoffMatch(match, league) {
  const { sport, format } = league;
  const isDoubles = format === 'doubles' && match.player1_partner_id && match.player2_partner_id;

  if (!isDoubles) {
    const rating1 = await getRating(match.player1_id, sport, format);
    const rating2 = await getRating(match.player2_id, sport, format);
    const team1Won = match.winner_id === match.player1_id;

    const { newRating1, newRating2 } = calculateNewRatings(
      sport, rating1, rating2, team1Won, match.player1_units, match.player2_units
    );

    const updatedRating1 = Math.round(newRating1 * 10) / 10;
    const updatedRating2 = Math.round(newRating2 * 10) / 10;
    const change1 = Math.round((updatedRating1 - rating1) * 100) / 100;
    const change2 = Math.round((updatedRating2 - rating2) * 100) / 100;

    await updateUserSportsRow(match.player1_id, sport, format, updatedRating1, team1Won);
    await updateUserSportsRow(match.player2_id, sport, format, updatedRating2, !team1Won);

    await pool.query(
      `UPDATE playoff_matches SET status = 'confirmed',
        player1_rating_change = $1, player2_rating_change = $2
       WHERE id = $3`,
      [change1, change2, match.id]
    );
  } else {
    const r1a = await getRating(match.player1_id, sport, format);
    const r1b = await getRating(match.player1_partner_id, sport, format);
    const r2a = await getRating(match.player2_id, sport, format);
    const r2b = await getRating(match.player2_partner_id, sport, format);

    const team1Rating = (r1a + r1b) / 2;
    const team2Rating = (r2a + r2b) / 2;
    const team1Won = match.winner_id === match.player1_id;

    const { newRating1: newTeam1Rating, newRating2: newTeam2Rating } = calculateNewRatings(
      sport, team1Rating, team2Rating, team1Won, match.player1_units, match.player2_units
    );

    const team1Delta = newTeam1Rating - team1Rating;
    const team2Delta = newTeam2Rating - team2Rating;

    const updated1a = Math.round((r1a + team1Delta) * 10) / 10;
    const updated1b = Math.round((r1b + team1Delta) * 10) / 10;
    const updated2a = Math.round((r2a + team2Delta) * 10) / 10;
    const updated2b = Math.round((r2b + team2Delta) * 10) / 10;

    const change1a = Math.round((updated1a - r1a) * 100) / 100;
    const change1b = Math.round((updated1b - r1b) * 100) / 100;
    const change2a = Math.round((updated2a - r2a) * 100) / 100;
    const change2b = Math.round((updated2b - r2b) * 100) / 100;

    await updateUserSportsRow(match.player1_id, sport, format, updated1a, team1Won);
    await updateUserSportsRow(match.player1_partner_id, sport, format, updated1b, team1Won);
    await updateUserSportsRow(match.player2_id, sport, format, updated2a, !team1Won);
    await updateUserSportsRow(match.player2_partner_id, sport, format, updated2b, !team1Won);

    await pool.query(
      `UPDATE playoff_matches SET status = 'confirmed',
        player1_rating_change = $1, player1_partner_rating_change = $2,
        player2_rating_change = $3, player2_partner_rating_change = $4
       WHERE id = $5`,
      [change1a, change1b, change2a, change2b, match.id]
    );
  }

  await advanceWinner({ ...match, status: 'confirmed' });
}

// Undoes the rating/stat effects of a previously confirmed playoff match —
// used when the host edits a confirmed score, or cancels the whole bracket.
async function reversePlayoffEffects(match, league) {
  const { sport, format } = league;
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

// ---------- GENERATE PLAYOFF BRACKET (host only, once) ----------
// qualifierCount means "number of singles players" for a singles league, or
// "number of teams" for a doubles league — both must be a power of two.
router.post('/:leagueId/generate', async (req, res) => {
  const userId = req.userId;
  const leagueId = req.params.leagueId;
  const { qualifierCount } = req.body;

  if (!isPowerOfTwo(qualifierCount) || qualifierCount < 2) {
    return res.status(400).json({ error: 'Qualifier count must be a power of 2 (2, 4, 8, 16...).' });
  }

  try {
    const leagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [leagueId]);
    if (leagueResult.rows.length === 0) {
      return res.status(404).json({ error: 'League not found.' });
    }
    const league = leagueResult.rows[0];

    if (league.created_by !== userId) {
      return res.status(403).json({ error: 'Only the league host can start playoffs.' });
    }

    const existing = await pool.query('SELECT id FROM playoff_matches WHERE league_id = $1 LIMIT 1', [leagueId]);
    if (existing.rows.length > 0) {
      return res.status(409).json({ error: 'A bracket has already been started for this league.' });
    }

    if (league.format === 'singles') {
      const standingsResult = await pool.query(
        `SELECT u.id, us.rating
         FROM league_members lm
         JOIN users u ON u.id = lm.user_id
         JOIN user_sports us ON us.user_id = u.id AND us.sport = $1 AND us.format = $2
         WHERE lm.league_id = $3
         ORDER BY us.rating DESC
         LIMIT $4`,
        [league.sport, league.format, leagueId, qualifierCount]
      );
      const qualifiers = standingsResult.rows;

      if (qualifiers.length < qualifierCount) {
        return res.status(400).json({ error: `Need at least ${qualifierCount} players in the leaderboard to start this bracket size.` });
      }

      const seedOrder = generateSeedOrder(qualifierCount);
      const totalRounds = Math.log2(qualifierCount);

      for (let i = 0; i < seedOrder.length; i += 2) {
        const seedA = seedOrder[i];
        const seedB = seedOrder[i + 1];
        await pool.query(
          `INSERT INTO playoff_matches (league_id, round_number, position, player1_id, player2_id, status)
           VALUES ($1, 1, $2, $3, $4, 'ready')`,
          [leagueId, i / 2 + 1, qualifiers[seedA - 1].id, qualifiers[seedB - 1].id]
        );
      }

      for (let round = 2; round <= totalRounds; round++) {
        const matchesInRound = qualifierCount / Math.pow(2, round);
        for (let pos = 1; pos <= matchesInRound; pos++) {
          await pool.query(
            `INSERT INTO playoff_matches (league_id, round_number, position, status)
             VALUES ($1, $2, $3, 'pending')`,
            [leagueId, round, pos]
          );
        }
      }

      return res.status(201).json({ message: 'Bracket generated.' });
    }

    // Doubles: qualifierCount = number of TEAMS.
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

    if (teams.length < qualifierCount) {
      return res.status(400).json({ error: `Need at least ${qualifierCount} teams to start this bracket size. Currently have ${teams.length} team(s) from ${members.length} player(s).` });
    }
    const qualifierTeams = teams.slice(0, qualifierCount);

    const seedOrder = generateSeedOrder(qualifierCount);
    const totalRounds = Math.log2(qualifierCount);

    for (let i = 0; i < seedOrder.length; i += 2) {
      const seedA = seedOrder[i];
      const seedB = seedOrder[i + 1];
      const teamA = qualifierTeams[seedA - 1];
      const teamB = qualifierTeams[seedB - 1];
      await pool.query(
        `INSERT INTO playoff_matches
          (league_id, round_number, position, player1_id, player1_partner_id, player2_id, player2_partner_id, status)
         VALUES ($1, 1, $2, $3, $4, $5, $6, 'ready')`,
        [leagueId, i / 2 + 1, teamA.player1.id, teamA.player2.id, teamB.player1.id, teamB.player2.id]
      );
    }

    for (let round = 2; round <= totalRounds; round++) {
      const matchesInRound = qualifierCount / Math.pow(2, round);
      for (let pos = 1; pos <= matchesInRound; pos++) {
        await pool.query(
          `INSERT INTO playoff_matches (league_id, round_number, position, status)
           VALUES ($1, $2, $3, 'pending')`,
          [leagueId, round, pos]
        );
      }
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
    const leagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [leagueId]);
    if (leagueResult.rows.length === 0) {
      return res.status(404).json({ error: 'League not found.' });
    }
    const league = leagueResult.rows[0];

    if (league.created_by !== userId) {
      return res.status(403).json({ error: 'Only the league host can remove the playoff bracket.' });
    }

    const confirmedMatches = await pool.query(
      `SELECT * FROM playoff_matches WHERE league_id = $1 AND status = 'confirmed'`,
      [leagueId]
    );
    for (const match of confirmedMatches.rows) {
      await reversePlayoffEffects(match, league);
    }

    const result = await pool.query('DELETE FROM playoff_matches WHERE league_id = $1', [leagueId]);
    if (result.rowCount === 0) {
      return res.status(404).json({ error: 'No playoff bracket exists for this league.' });
    }

    res.status(200).json({ message: 'Playoff bracket removed.' });
  } catch (err) {
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

async function advanceWinner(match) {
  const nextRound = match.round_number + 1;
  const nextPosition = Math.ceil(match.position / 2);
  const isUpperSlot = match.position % 2 === 1;

  const winnerPartnerId = match.winner_id === match.player1_id ? match.player1_partner_id : match.player2_partner_id;

  const nextMatchResult = await pool.query(
    'SELECT * FROM playoff_matches WHERE league_id = $1 AND round_number = $2 AND position = $3',
    [match.league_id, nextRound, nextPosition]
  );

  if (nextMatchResult.rows.length > 0) {
    const nextMatch = nextMatchResult.rows[0];
    if (isUpperSlot) {
      await pool.query(
        'UPDATE playoff_matches SET player1_id = $1, player1_partner_id = $2 WHERE id = $3',
        [match.winner_id, winnerPartnerId, nextMatch.id]
      );
    } else {
      await pool.query(
        'UPDATE playoff_matches SET player2_id = $1, player2_partner_id = $2 WHERE id = $3',
        [match.winner_id, winnerPartnerId, nextMatch.id]
      );
    }

    const updatedNextMatch = await pool.query('SELECT * FROM playoff_matches WHERE id = $1', [nextMatch.id]);
    const um = updatedNextMatch.rows[0];
    if (um.player1_id && um.player2_id) {
      await pool.query(`UPDATE playoff_matches SET status = 'ready' WHERE id = $1`, [nextMatch.id]);
    }
  }
}

// ---------- REPORT A PLAYOFF MATCH RESULT (self, needs opponent confirmation) ----------
router.post('/match/:matchId/report', async (req, res) => {
  const userId = req.userId;
  const matchId = req.params.matchId;
  const { myUnits, opponentUnits, iWon, setScores } = req.body;

  if (myUnits == null || opponentUnits == null || iWon == null) {
    return res.status(400).json({ error: 'Missing required fields.' });
  }

  try {
    const matchResult = await pool.query('SELECT * FROM playoff_matches WHERE id = $1', [matchId]);
    if (matchResult.rows.length === 0) {
      return res.status(404).json({ error: 'Match not found.' });
    }
    const match = matchResult.rows[0];

    const leagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [match.league_id]);
    const league = leagueResult.rows[0];
    if (league.host_enters_scores) {
      return res.status(403).json({ error: 'This league requires the host to enter all scores.' });
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
        player1_units = $2, player2_units = $3, winner_id = $4, set_scores = $5
       WHERE id = $6`,
      [userId, player1Units, player2Units, winnerId, JSON.stringify(setScores || []), matchId]
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
  const { myUnits, opponentUnits, iWon, setScores } = req.body;

  if (myUnits == null || opponentUnits == null || iWon == null) {
    return res.status(400).json({ error: 'Missing required fields.' });
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

    const onSideOne = userId === match.player1_id || userId === match.player1_partner_id;
    const winnerId = iWon ? (onSideOne ? match.player1_id : match.player2_id)
                          : (onSideOne ? match.player2_id : match.player1_id);
    const player1Units = onSideOne ? myUnits : opponentUnits;
    const player2Units = onSideOne ? opponentUnits : myUnits;

    await pool.query(
      `UPDATE playoff_matches SET player1_units = $1, player2_units = $2, winner_id = $3, set_scores = $4
       WHERE id = $5`,
      [player1Units, player2Units, winnerId, JSON.stringify(setScores || []), matchId]
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
  const { player1Units, player2Units, player1Won, setScores } = req.body;

  if (player1Units == null || player2Units == null || player1Won == null) {
    return res.status(400).json({ error: 'Missing required fields.' });
  }

  try {
    const matchResult = await pool.query('SELECT * FROM playoff_matches WHERE id = $1', [matchId]);
    if (matchResult.rows.length === 0) {
      return res.status(404).json({ error: 'Match not found.' });
    }
    const match = matchResult.rows[0];

    const leagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [match.league_id]);
    const league = leagueResult.rows[0];

    if (!league.host_enters_scores || league.created_by !== userId) {
      return res.status(403).json({ error: 'Only the host can enter scores directly for this league.' });
    }

    if (match.status !== 'ready') {
      return res.status(409).json({ error: 'This match is not ready to be reported.' });
    }
    if (!match.player1_id || !match.player2_id) {
      return res.status(400).json({ error: 'Both players for this match are not yet determined.' });
    }
    if (league.format === 'doubles' && (!match.player1_partner_id || !match.player2_partner_id)) {
      return res.status(400).json({ error: 'Both teams for this match are not yet fully determined.' });
    }

    const winnerId = player1Won ? match.player1_id : match.player2_id;

    await pool.query(
      `UPDATE playoff_matches SET reported_by = $1,
        player1_units = $2, player2_units = $3, winner_id = $4, set_scores = $5
       WHERE id = $6`,
      [userId, player1Units, player2Units, winnerId, JSON.stringify(setScores || []), matchId]
    );

    const updatedMatchResult = await pool.query('SELECT * FROM playoff_matches WHERE id = $1', [matchId]);
    await finalizePlayoffMatch(updatedMatchResult.rows[0], league);

    res.status(200).json({ message: 'Match confirmed.' });
  } catch (err) {
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
  const { player1Units, player2Units, player1Won, setScores } = req.body;

  if (player1Units == null || player2Units == null || player1Won == null) {
    return res.status(400).json({ error: 'Missing required fields.' });
  }

  try {
    const matchResult = await pool.query('SELECT * FROM playoff_matches WHERE id = $1', [matchId]);
    if (matchResult.rows.length === 0) {
      return res.status(404).json({ error: 'Match not found.' });
    }
    const match = matchResult.rows[0];

    if (match.status !== 'confirmed') {
      return res.status(400).json({ error: 'Only confirmed matches can be edited.' });
    }

    const leagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [match.league_id]);
    const league = leagueResult.rows[0];
    if (league.created_by !== userId) {
      return res.status(403).json({ error: 'Only the league host can edit match scores.' });
    }

    const newWinnerId = player1Won ? match.player1_id : match.player2_id;
    const winnerChanged = newWinnerId !== match.winner_id;

    if (winnerChanged) {
      const nextRound = match.round_number + 1;
      const nextPosition = Math.ceil(match.position / 2);
      const nextMatchResult = await pool.query(
        'SELECT * FROM playoff_matches WHERE league_id = $1 AND round_number = $2 AND position = $3',
        [match.league_id, nextRound, nextPosition]
      );

      if (nextMatchResult.rows.length > 0) {
        const nextMatch = nextMatchResult.rows[0];
        if (nextMatch.status === 'reported' || nextMatch.status === 'confirmed') {
          return res.status(400).json({
            error: 'The next round has already been played with the old winner. Cancel and restart the playoffs to fix this.',
          });
        }
      }
    }

    // Reverse the old rating effects before touching anything else.
    await reversePlayoffEffects(match, league);

    await pool.query(
      `UPDATE playoff_matches SET player1_units = $1, player2_units = $2, winner_id = $3, set_scores = $4
       WHERE id = $5`,
      [player1Units, player2Units, newWinnerId, JSON.stringify(setScores || []), matchId]
    );

    if (winnerChanged) {
      const nextRound = match.round_number + 1;
      const nextPosition = Math.ceil(match.position / 2);
      const nextMatchResult = await pool.query(
        'SELECT * FROM playoff_matches WHERE league_id = $1 AND round_number = $2 AND position = $3',
        [match.league_id, nextRound, nextPosition]
      );
      if (nextMatchResult.rows.length > 0) {
        const nextMatch = nextMatchResult.rows[0];
        const isUpperSlot = match.position % 2 === 1;
        const newWinnerPartnerId = newWinnerId === match.player1_id ? match.player1_partner_id : match.player2_partner_id;
        if (isUpperSlot) {
          await pool.query(
            'UPDATE playoff_matches SET player1_id = $1, player1_partner_id = $2 WHERE id = $3',
            [newWinnerId, newWinnerPartnerId, nextMatch.id]
          );
        } else {
          await pool.query(
            'UPDATE playoff_matches SET player2_id = $1, player2_partner_id = $2 WHERE id = $3',
            [newWinnerId, newWinnerPartnerId, nextMatch.id]
          );
        }
        const refreshedNext = await pool.query('SELECT * FROM playoff_matches WHERE id = $1', [nextMatch.id]);
        const rn = refreshedNext.rows[0];
        await pool.query(
          `UPDATE playoff_matches SET status = $1 WHERE id = $2`,
          [rn.player1_id && rn.player2_id ? 'ready' : 'pending', nextMatch.id]
        );
      }
    }

    // Reapply ratings fresh, based on current (post-reversal) standings.
    const updatedMatchResult = await pool.query('SELECT * FROM playoff_matches WHERE id = $1', [matchId]);
    const updatedMatch = updatedMatchResult.rows[0];
    const isDoubles = league.format === 'doubles' && updatedMatch.player1_partner_id && updatedMatch.player2_partner_id;

    if (!isDoubles) {
      const rating1 = await getRating(updatedMatch.player1_id, league.sport, league.format);
      const rating2 = await getRating(updatedMatch.player2_id, league.sport, league.format);
      const team1Won = updatedMatch.winner_id === updatedMatch.player1_id;
      const { newRating1, newRating2 } = calculateNewRatings(
        league.sport, rating1, rating2, team1Won, updatedMatch.player1_units, updatedMatch.player2_units
      );
      const updatedRating1 = Math.round(newRating1 * 10) / 10;
      const updatedRating2 = Math.round(newRating2 * 10) / 10;
      const change1 = Math.round((updatedRating1 - rating1) * 100) / 100;
      const change2 = Math.round((updatedRating2 - rating2) * 100) / 100;

      await updateUserSportsRow(updatedMatch.player1_id, league.sport, league.format, updatedRating1, team1Won);
      await updateUserSportsRow(updatedMatch.player2_id, league.sport, league.format, updatedRating2, !team1Won);
      await pool.query(
        `UPDATE playoff_matches SET player1_rating_change = $1, player2_rating_change = $2,
          player1_partner_rating_change = NULL, player2_partner_rating_change = NULL WHERE id = $3`,
        [change1, change2, matchId]
      );
    } else {
      const r1a = await getRating(updatedMatch.player1_id, league.sport, league.format);
      const r1b = await getRating(updatedMatch.player1_partner_id, league.sport, league.format);
      const r2a = await getRating(updatedMatch.player2_id, league.sport, league.format);
      const r2b = await getRating(updatedMatch.player2_partner_id, league.sport, league.format);

      const team1Rating = (r1a + r1b) / 2;
      const team2Rating = (r2a + r2b) / 2;
      const team1Won = updatedMatch.winner_id === updatedMatch.player1_id;

      const { newRating1: newTeam1Rating, newRating2: newTeam2Rating } = calculateNewRatings(
        league.sport, team1Rating, team2Rating, team1Won, updatedMatch.player1_units, updatedMatch.player2_units
      );

      const team1Delta = newTeam1Rating - team1Rating;
      const team2Delta = newTeam2Rating - team2Rating;

      const updated1a = Math.round((r1a + team1Delta) * 10) / 10;
      const updated1b = Math.round((r1b + team1Delta) * 10) / 10;
      const updated2a = Math.round((r2a + team2Delta) * 10) / 10;
      const updated2b = Math.round((r2b + team2Delta) * 10) / 10;

      const change1a = Math.round((updated1a - r1a) * 100) / 100;
      const change1b = Math.round((updated1b - r1b) * 100) / 100;
      const change2a = Math.round((updated2a - r2a) * 100) / 100;
      const change2b = Math.round((updated2b - r2b) * 100) / 100;

      await updateUserSportsRow(updatedMatch.player1_id, league.sport, league.format, updated1a, team1Won);
      await updateUserSportsRow(updatedMatch.player1_partner_id, league.sport, league.format, updated1b, team1Won);
      await updateUserSportsRow(updatedMatch.player2_id, league.sport, league.format, updated2a, !team1Won);
      await updateUserSportsRow(updatedMatch.player2_partner_id, league.sport, league.format, updated2b, !team1Won);

      await pool.query(
        `UPDATE playoff_matches SET player1_rating_change = $1, player1_partner_rating_change = $2,
          player2_rating_change = $3, player2_partner_rating_change = $4 WHERE id = $5`,
        [change1a, change1b, change2a, change2b, matchId]
      );
    }

    res.status(200).json({
      message: 'Score updated and ratings recalculated.',
      warning: winnerChanged
        ? 'The winner changed — the next round fixture has been updated accordingly.'
        : null,
    });
  } catch (err) {
    console.error('Edit playoff score error:', err);
    res.status(500).json({ error: 'Something went wrong updating the score.' });
  }
});

// ---------- CONFIRM A PLAYOFF MATCH RESULT ----------
router.post('/match/:matchId/confirm', async (req, res) => {
  const userId = req.userId;
  const matchId = req.params.matchId;

  try {
    const matchResult = await pool.query('SELECT * FROM playoff_matches WHERE id = $1', [matchId]);
    if (matchResult.rows.length === 0) {
      return res.status(404).json({ error: 'Match not found.' });
    }
    const match = matchResult.rows[0];

    if (match.status !== 'reported') {
      return res.status(409).json({ error: 'This match has no pending report to confirm.' });
    }
    const participantIds = [match.player1_id, match.player2_id, match.player1_partner_id, match.player2_partner_id].filter(Boolean);
    if (!participantIds.includes(userId)) {
      return res.status(403).json({ error: 'You are not part of this match.' });
    }
    if (userId === match.reported_by) {
      return res.status(400).json({ error: 'You cannot confirm your own report.' });
    }

    const leagueResult = await pool.query('SELECT * FROM leagues WHERE id = $1', [match.league_id]);
    const league = leagueResult.rows[0];

    await finalizePlayoffMatch(match, league);

    res.status(200).json({ message: 'Match confirmed.' });
  } catch (err) {
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

    await pool.query(
      `UPDATE playoff_matches SET status = 'ready', reported_by = NULL, winner_id = NULL,
        player1_units = NULL, player2_units = NULL, set_scores = NULL
       WHERE id = $1`,
      [matchId]
    );

    res.status(200).json({ message: 'Result rejected. It can be reported again.' });
  } catch (err) {
    console.error('Reject playoff match error:', err);
    res.status(500).json({ error: 'Something went wrong rejecting the match.' });
  }
});

module.exports = router;