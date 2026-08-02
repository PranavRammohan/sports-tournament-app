// Unit tests for matchRoutes.js's winnerUnitsAreConsistent — cross-checks
// the declared winner against the reported unit counts, since without this
// "I won" with a lower score than the opponent was silently accepted: an
// internally contradictory result that still credited a win and full
// win-points. Attached to the exported router the same way the other route
// files attach their module-private helpers (see the comment above
// module.exports in matchRoutes.js). playoffRoutes.js keeps its own local
// copy of the identical function (no shared module between the two files),
// so these tests cover both by construction.
const matchRoutes = require('../matchRoutes');
const { winnerUnitsAreConsistent } = matchRoutes;

describe('winnerUnitsAreConsistent', () => {
  test('player1 declared winner with more units passes', () => {
    expect(winnerUnitsAreConsistent(true, 21, 15)).toBe(true);
  });

  test('player2 declared winner with more units passes', () => {
    expect(winnerUnitsAreConsistent(false, 15, 21)).toBe(true);
  });

  test('player1 declared winner with fewer units fails', () => {
    expect(winnerUnitsAreConsistent(true, 15, 21)).toBe(false);
  });

  test('player2 declared winner with fewer units fails', () => {
    expect(winnerUnitsAreConsistent(false, 21, 15)).toBe(false);
  });

  test('equal units fails regardless of declared winner', () => {
    expect(winnerUnitsAreConsistent(true, 10, 10)).toBe(false);
    expect(winnerUnitsAreConsistent(false, 10, 10)).toBe(false);
  });

  test('zero-zero fails', () => {
    expect(winnerUnitsAreConsistent(true, 0, 0)).toBe(false);
  });
});
