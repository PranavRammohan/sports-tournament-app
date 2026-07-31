// Unit tests for sportsRoutes.js's reconstructRatingHistory — a pure
// function (no DB access) that rebuilds a rating-over-time series from the
// current rating snapshot and a chronologically-ordered list of per-match
// deltas, since there's no materialized rating-history table. Attached to
// the exported router the same way the other route files attach their
// own module-private helpers (see the comment above module.exports in
// sportsRoutes.js).
const sportsRoutes = require('../sportsRoutes');
const { reconstructRatingHistory } = sportsRoutes;

describe('reconstructRatingHistory', () => {
  test('no matches: history is just the current rating as a single point', () => {
    const history = reconstructRatingHistory(1500, []);
    expect(history).toEqual([{ date: null, rating: 1500 }]);
  });

  test('walks forward from a baseline that nets back out to the current rating', () => {
    const matches = [
      { id: 1, created_at: '2026-01-01', my_rating_change: '5' },
      { id: 2, created_at: '2026-01-05', my_rating_change: '-2' },
      { id: 3, created_at: '2026-01-10', my_rating_change: '3' },
    ];
    const history = reconstructRatingHistory(1506, matches);
    // baseline = 1506 - (5 - 2 + 3) = 1500
    expect(history).toEqual([
      { date: null, rating: 1500 },
      { date: '2026-01-01', rating: 1505 },
      { date: '2026-01-05', rating: 1503 },
      { date: '2026-01-10', rating: 1506 },
    ]);
  });

  test('last point in the series always equals the current rating exactly', () => {
    const matches = [
      { id: 1, created_at: '2026-02-01', my_rating_change: '1.7' },
      { id: 2, created_at: '2026-02-02', my_rating_change: '-0.4' },
      { id: 3, created_at: '2026-02-03', my_rating_change: '2.1' },
    ];
    const history = reconstructRatingHistory(1234.5, matches);
    expect(history[history.length - 1].rating).toBe(1234.5);
  });

  test('null/non-numeric deltas are treated as zero, not skipped', () => {
    const matches = [
      { id: 1, created_at: '2026-01-01', my_rating_change: null },
      { id: 2, created_at: '2026-01-02', my_rating_change: '4' },
    ];
    const history = reconstructRatingHistory(1004, matches);
    expect(history).toEqual([
      { date: null, rating: 1000 },
      { date: '2026-01-01', rating: 1000 },
      { date: '2026-01-02', rating: 1004 },
    ]);
  });

  test('rounds to one decimal place', () => {
    const matches = [
      { id: 1, created_at: '2026-01-01', my_rating_change: '0.03' },
    ];
    const history = reconstructRatingHistory(1000.03, matches);
    expect(history[0].rating).toBe(1000);
    expect(history[1].rating).toBe(1000);
  });
});
