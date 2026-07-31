// Unit tests for playoffRoutes.js's resolvePointsConfig — the knockout/
// bracket-match sibling of matchRoutes.js's resolvePointsConfig. Attached to
// the exported router the same way (see the comment above module.exports in
// playoffRoutes.js). Differs from the matches-table version in one important
// way: playoff_matches has no scheduled_match_id, so the group lookup reads
// match.group_id directly against league_groups instead of joining through
// scheduled_matches.
const playoffRoutes = require('../playoffRoutes');
const { resolvePointsConfig } = playoffRoutes;

const baseLeague = { points_enabled: true, points_win: 2, points_loss: 0 };

describe('playoffRoutes resolvePointsConfig', () => {
  test('whole-tournament bracket match (group_id null) uses the league config directly, no query', async () => {
    const db = { query: jest.fn() };
    const match = { group_id: null };
    const result = await resolvePointsConfig(db, match, baseLeague);
    expect(db.query).not.toHaveBeenCalled();
    expect(result).toEqual({ enabled: true, win: 2, loss: 0 });
  });

  test('knockout-format group with no override inherits from the league', async () => {
    const db = {
      query: jest.fn().mockResolvedValue({
        rows: [{ points_enabled: null, points_win: null, points_loss: null }],
      }),
    };
    const match = { group_id: 9 };
    const result = await resolvePointsConfig(db, match, baseLeague);
    expect(db.query).toHaveBeenCalledWith(
      'SELECT * FROM league_groups WHERE id = $1',
      [9]
    );
    expect(result).toEqual({ enabled: true, win: 2, loss: 0 });
  });

  test('knockout-format group overriding all three fields wins over the league', async () => {
    const db = {
      query: jest.fn().mockResolvedValue({
        rows: [{ points_enabled: false, points_win: 5, points_loss: 1 }],
      }),
    };
    const match = { group_id: 9 };
    const result = await resolvePointsConfig(db, match, baseLeague);
    expect(result).toEqual({ enabled: false, win: 5, loss: 1 });
  });

  test('group row not found still falls back to the league config', async () => {
    const db = { query: jest.fn().mockResolvedValue({ rows: [] }) };
    const match = { group_id: 9 };
    const result = await resolvePointsConfig(db, match, baseLeague);
    expect(result).toEqual({ enabled: true, win: 2, loss: 0 });
  });
});

describe('playoffRoutes awardPlayoffPoints', () => {
  const { awardPlayoffPoints } = playoffRoutes;

  function makeDb(groupRow) {
    const query = jest.fn((sql) => {
      if (sql.includes('FROM league_groups')) {
        return Promise.resolve({ rows: groupRow ? [groupRow] : [] });
      }
      return Promise.resolve({});
    });
    return { query };
  }

  test('singles: awards win points to winner, loss points to loser', async () => {
    const db = makeDb(null);
    const league = { points_enabled: true, points_win: 3, points_loss: 1 };
    const match = {
      league_id: 1, group_id: null,
      winner_id: 10, player1_id: 10, player2_id: 20,
      player1_partner_id: null, player2_partner_id: null,
    };
    const { winnerPoints, loserPoints } = await awardPlayoffPoints(db, match, league);
    expect(winnerPoints).toBe(3);
    expect(loserPoints).toBe(1);

    const memberUpdates = db.query.mock.calls.filter(([sql]) => sql.includes('UPDATE league_members'));
    expect(memberUpdates).toEqual([
      ['UPDATE league_members SET points = points + $1 WHERE league_id = $2 AND user_id = $3', [3, 1, 10]],
      ['UPDATE league_members SET points = points + $1 WHERE league_id = $2 AND user_id = $3', [1, 1, 20]],
    ]);
  });

  test('doubles: awards both members of the winning team and both of the losing team', async () => {
    const db = makeDb(null);
    const league = { points_enabled: true, points_win: 2, points_loss: 0 };
    const match = {
      league_id: 1, group_id: null,
      winner_id: 10, player1_id: 10, player2_id: 20,
      player1_partner_id: 11, player2_partner_id: 21,
    };
    await awardPlayoffPoints(db, match, league);

    const memberUpdates = db.query.mock.calls.filter(([sql]) => sql.includes('UPDATE league_members'));
    const recipients = memberUpdates.map(([, params]) => params[2]);
    expect(recipients.sort()).toEqual([10, 11, 20, 21]);
  });

  test('points disabled (league-level) awards zero to everyone', async () => {
    const db = makeDb(null);
    const league = { points_enabled: false, points_win: 3, points_loss: 1 };
    const match = {
      league_id: 1, group_id: null,
      winner_id: 10, player1_id: 10, player2_id: 20,
      player1_partner_id: null, player2_partner_id: null,
    };
    const { winnerPoints, loserPoints } = await awardPlayoffPoints(db, match, league);
    expect(winnerPoints).toBe(0);
    expect(loserPoints).toBe(0);
  });

  test('group override changes the awarded amounts for a knockout-format group', async () => {
    const db = makeDb({ points_enabled: true, points_win: 10, points_loss: 5 });
    const league = { points_enabled: true, points_win: 2, points_loss: 0 };
    const match = {
      league_id: 1, group_id: 9,
      winner_id: 10, player1_id: 10, player2_id: 20,
      player1_partner_id: null, player2_partner_id: null,
    };
    const { winnerPoints, loserPoints } = await awardPlayoffPoints(db, match, league);
    expect(winnerPoints).toBe(10);
    expect(loserPoints).toBe(5);
  });
});
