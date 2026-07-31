// Unit tests for ratingEngine.js — this module is pure (no DB dependency for
// calculateNewRatings) except reverseRatingChange, which takes its DB client
// as the first argument and is tested here with a fake `{ query }` stub
// instead of a real Postgres connection.
const { calculateNewRatings, reverseRatingChange } = require('../ratingEngine');

describe('calculateNewRatings — continuous sports (tennis/badminton/pickleball)', () => {
  const sports = ['tennis', 'badminton', 'pickleball'];

  sports.forEach((sport) => {
    describe(sport, () => {
      test('zero-sum: team1 gains exactly what team2 loses', () => {
        const { newRating1, newRating2 } = calculateNewRatings(sport, 100, 100, true, 2, 0);
        const change1 = newRating1 - 100;
        const change2 = 100 - newRating2;
        expect(change1).toBeCloseTo(change2, 10);
      });

      test('equal ratings, team1 wins convincingly (all units) — rating goes up', () => {
        const { newRating1, newRating2 } = calculateNewRatings(sport, 100, 100, true, 2, 0);
        expect(newRating1).toBeGreaterThan(100);
        expect(newRating2).toBeLessThan(100);
      });

      test('equal ratings, team1 wins narrowly — smaller gain than winning convincingly', () => {
        const convincing = calculateNewRatings(sport, 100, 100, true, 2, 0);
        const narrow = calculateNewRatings(sport, 100, 100, true, 2, 1);
        const convincingGain = convincing.newRating1 - 100;
        const narrowGain = narrow.newRating1 - 100;
        expect(narrowGain).toBeGreaterThan(0);
        expect(narrowGain).toBeLessThan(convincingGain);
      });

      test('upset: heavy underdog winning gains more than a favorite winning', () => {
        // Underdog (team1) beats a much higher-rated team2.
        const underdogWin = calculateNewRatings(sport, 1, 1000, true, 2, 0);
        // Favorite (team1) beats a much lower-rated team2 (expected result).
        const favoriteWin = calculateNewRatings(sport, 1000, 1, true, 2, 0);
        const underdogGain = underdogWin.newRating1 - 1;
        const favoriteGain = favoriteWin.newRating1 - 1000;
        expect(underdogGain).toBeGreaterThan(favoriteGain);
      });

      test('no unit info (team1Units/team2Units both 0) falls back to win/loss only', () => {
        const won = calculateNewRatings(sport, 100, 100, true, 0, 0);
        const lost = calculateNewRatings(sport, 100, 100, false, 0, 0);
        expect(won.newRating1).toBeGreaterThan(100);
        expect(lost.newRating1).toBeLessThan(100);
        // Symmetric: winning and losing from the same starting point produce
        // equal-magnitude, opposite-sign changes.
        expect(won.newRating1 - 100).toBeCloseTo(100 - lost.newRating1, 10);
      });
    });
  });
});

describe('calculateNewRatings — table tennis (discrete USATT-style ladder)', () => {
  test('equal ratings, expected result (win) — smallest point change', () => {
    const { newRating1, newRating2 } = calculateNewRatings('table_tennis', 1500, 1500, true, 2, 0);
    // diff=0 -> pointsForUpset=8 -> pointsForExpected=max(1, round(8*0.08))=1
    expect(newRating1).toBe(1501);
    expect(newRating2).toBe(1499);
  });

  test('equal ratings, team1 loses — counts as an upset (ties favor team1)', () => {
    // favoriteIsTeam1 uses `>=`, so an exact tie always treats team1 as the
    // favorite — team1 losing here is therefore an upset (full pointsForUpset
    // swing), not the small "expected result" swing from the win case above.
    const { newRating1, newRating2 } = calculateNewRatings('table_tennis', 1500, 1500, false, 0, 2);
    expect(newRating1).toBe(1492);
    expect(newRating2).toBe(1508);
  });

  test('big gap, underdog upset — large point swing (bracket max)', () => {
    // diff = 300 (> 237) -> pointsForUpset = 50. team1 is the underdog and wins.
    const { newRating1, newRating2 } = calculateNewRatings('table_tennis', 1200, 1500, true, 2, 0);
    expect(newRating1).toBe(1250);
    expect(newRating2).toBe(1450);
  });

  test('big gap, favorite wins as expected — small point change', () => {
    // Same 300-point gap, but the higher-rated team1 wins (expected, not an upset).
    const { newRating1, newRating2 } = calculateNewRatings('table_tennis', 1500, 1200, true, 2, 0);
    // pointsForUpset=50 -> pointsForExpected=max(1, round(50*0.08))=4
    expect(newRating1).toBe(1504);
    expect(newRating2).toBe(1196);
  });

  test('bracket boundaries: diff=12 uses 8pt bracket, diff=13 uses 10pt bracket', () => {
    // Underdog (team1) wins in both cases so the full pointsForUpset value applies.
    const atTwelve = calculateNewRatings('table_tennis', 1488, 1500, true, 2, 0);
    const atThirteen = calculateNewRatings('table_tennis', 1487, 1500, true, 2, 0);
    expect(atTwelve.newRating1 - 1488).toBe(8);
    expect(atThirteen.newRating1 - 1487).toBe(10);
  });
});

describe('reverseRatingChange', () => {
  test('no-ops when playerId is null', async () => {
    const db = { query: jest.fn() };
    await reverseRatingChange(db, null, 'tennis', 'singles', 1.5, true);
    expect(db.query).not.toHaveBeenCalled();
  });

  test('no-ops when ratingChange is null', async () => {
    const db = { query: jest.fn() };
    await reverseRatingChange(db, 7, 'tennis', 'singles', null, true);
    expect(db.query).not.toHaveBeenCalled();
  });

  test('table tennis: reverses without a format filter, shared rating', async () => {
    const db = { query: jest.fn().mockResolvedValue({}) };
    await reverseRatingChange(db, 7, 'table_tennis', 'doubles', 5, true);
    expect(db.query).toHaveBeenCalledTimes(1);
    const [sql, params] = db.query.mock.calls[0];
    expect(sql).not.toMatch(/format/i);
    expect(params).toEqual([5, 1, 0, 7, 'table_tennis']);
  });

  test('non-table-tennis sport: reverses scoped to sport + format', async () => {
    const db = { query: jest.fn().mockResolvedValue({}) };
    await reverseRatingChange(db, 7, 'badminton', 'singles', -3.2, false);
    expect(db.query).toHaveBeenCalledTimes(1);
    const [sql, params] = db.query.mock.calls[0];
    expect(sql).toMatch(/format/i);
    expect(params).toEqual([-3.2, 0, 1, 7, 'badminton', 'singles']);
  });
});
