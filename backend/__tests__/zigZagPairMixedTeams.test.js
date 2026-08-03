// Unit tests for leagueRoutes.js's zigZagPairMixedTeams — GAP-13 mixed
// doubles pairing. Pairs one man with one woman by rule (strongest man with
// weakest woman, and so on) rather than the plain single-list zig-zag used
// for mens/womens leagues, since a mixed team must always be 1M + 1F.
const leagueRoutes = require('../leagueRoutes');
const { zigZagPairMixedTeams } = leagueRoutes;

describe('zigZagPairMixedTeams', () => {
  test('pairs the strongest man with the weakest woman, and so on', () => {
    const members = [
      { id: 1, gender: 'M', rating: '10' },
      { id: 2, gender: 'M', rating: '6' },
      { id: 3, gender: 'F', rating: '9' },
      { id: 4, gender: 'F', rating: '3' },
    ];
    const teams = zigZagPairMixedTeams(members);
    expect(teams).toHaveLength(2);
    // Strongest man (id 1, rating 10) with weakest woman (id 4, rating 3).
    expect(teams[0].player1.id).toBe(1);
    expect(teams[0].player2.id).toBe(4);
    // Second-strongest man (id 2) with second-weakest woman (id 3).
    expect(teams[1].player1.id).toBe(2);
    expect(teams[1].player2.id).toBe(3);
  });

  test('computes avgRating as the mean of the pair', () => {
    const members = [
      { id: 1, gender: 'M', rating: '10' },
      { id: 2, gender: 'F', rating: '4' },
    ];
    const teams = zigZagPairMixedTeams(members);
    expect(teams[0].avgRating).toBe(7);
  });

  test('throws UNEVEN_GENDER_SPLIT when men and women counts differ', () => {
    const members = [
      { id: 1, gender: 'M', rating: '10' },
      { id: 2, gender: 'M', rating: '6' },
      { id: 3, gender: 'F', rating: '9' },
    ];
    expect(() => zigZagPairMixedTeams(members)).toThrow();
    try {
      zigZagPairMixedTeams(members);
      throw new Error('expected to throw');
    } catch (err) {
      expect(err.code).toBe('UNEVEN_GENDER_SPLIT');
    }
  });

  test('an empty list produces no teams', () => {
    expect(zigZagPairMixedTeams([])).toEqual([]);
  });
});
