// Unit tests for matchRoutes.js's resolvePointsConfig — attached to the
// exported router the same way db.js attaches withTransaction/RouteError to
// the pool (see the comment above module.exports in matchRoutes.js), so it's
// reachable here without spinning up Express or a real Postgres connection.
//
// Requiring matchRoutes.js also requires ./db, which constructs a `pg.Pool`
// as an import-time side effect — but pg.Pool doesn't open a real connection
// until a query actually runs, so this is safe without a live database as
// long as no test here calls through the real pool (every test below passes
// its own fake `db` object into resolvePointsConfig directly).
const matchRoutes = require('../matchRoutes');
const { resolvePointsConfig } = matchRoutes;

// A league with points on, default 2/0 — matches every tournament's default
// before per-group overrides or per-tournament customization.
const baseLeague = { points_enabled: true, points_win: 2, points_loss: 0 };

describe('resolvePointsConfig', () => {
  test('match with no scheduled_match_id always uses the league config (manually added match)', async () => {
    const db = { query: jest.fn() };
    const match = { scheduled_match_id: null };
    const result = await resolvePointsConfig(db, match, baseLeague);
    expect(db.query).not.toHaveBeenCalled();
    expect(result).toEqual({ enabled: true, win: 2, loss: 0 });
  });

  test('match in a group with no override inherits every field from the league', async () => {
    const db = {
      query: jest.fn().mockResolvedValue({
        rows: [{ points_enabled: null, points_win: null, points_loss: null }],
      }),
    };
    const match = { scheduled_match_id: 42 };
    const result = await resolvePointsConfig(db, match, baseLeague);
    expect(result).toEqual({ enabled: true, win: 2, loss: 0 });
  });

  test('group overriding all three fields wins over the league config', async () => {
    const db = {
      query: jest.fn().mockResolvedValue({
        rows: [{ points_enabled: false, points_win: 5, points_loss: 1 }],
      }),
    };
    const match = { scheduled_match_id: 42 };
    const result = await resolvePointsConfig(db, match, baseLeague);
    expect(result).toEqual({ enabled: false, win: 5, loss: 1 });
  });

  test('group overriding only points_win inherits enabled/loss from the league', async () => {
    const db = {
      query: jest.fn().mockResolvedValue({
        rows: [{ points_enabled: null, points_win: 10, points_loss: null }],
      }),
    };
    const match = { scheduled_match_id: 42 };
    const result = await resolvePointsConfig(db, match, baseLeague);
    expect(result).toEqual({ enabled: true, win: 10, loss: 0 });
  });

  test('group with points_win = 0 is a real override, not treated as "unset"', async () => {
    // Regression guard: the resolver must use `!= null`, not truthiness —
    // 0 is a legitimate configured value (e.g. "no points for a win"),
    // distinct from NULL ("inherit").
    const db = {
      query: jest.fn().mockResolvedValue({
        rows: [{ points_enabled: null, points_win: 0, points_loss: null }],
      }),
    };
    const match = { scheduled_match_id: 42 };
    const result = await resolvePointsConfig(db, match, baseLeague);
    expect(result.win).toBe(0);
  });

  test('scheduled_match_id set but not part of any group (group_id IS NULL) inherits from the league', async () => {
    // The join is `... JOIN league_groups lg ON lg.id = sm.group_id WHERE
    // sm.id = $1 AND sm.group_id IS NOT NULL` — a non-group fixture returns
    // zero rows, same as "no override found."
    const db = { query: jest.fn().mockResolvedValue({ rows: [] }) };
    const match = { scheduled_match_id: 7 };
    const result = await resolvePointsConfig(db, match, baseLeague);
    expect(result).toEqual({ enabled: true, win: 2, loss: 0 });
  });

  test('league itself has points disabled and no group override — stays disabled', async () => {
    const db = {
      query: jest.fn().mockResolvedValue({
        rows: [{ points_enabled: null, points_win: null, points_loss: null }],
      }),
    };
    const disabledLeague = { points_enabled: false, points_win: 0, points_loss: 0 };
    const match = { scheduled_match_id: 42 };
    const result = await resolvePointsConfig(db, match, disabledLeague);
    expect(result.enabled).toBe(false);
  });
});
