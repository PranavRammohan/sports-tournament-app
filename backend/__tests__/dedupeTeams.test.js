// Unit tests for leagueRoutes.js's dedupeTeams — collapses a group's member
// list (which lists both partners of a doubles team as separate rows,
// always carrying identical team stats) down to one entry per team, used by
// POST /:id/groups/advance to rank/advance whole teams instead of
// individuals. Attached to the exported router the same way the other
// route files attach their module-private helpers (see the comment above
// module.exports in leagueRoutes.js).
const leagueRoutes = require('../leagueRoutes');
const { dedupeTeams } = leagueRoutes;

describe('dedupeTeams', () => {
  test('pairs up partners and preserves the first-seen order as the team position', () => {
    const members = [
      { id: 1, username: 'Alice', partner_id: 2 },
      { id: 2, username: 'Bob', partner_id: 1 },
      { id: 3, username: 'Carol', partner_id: 4 },
      { id: 4, username: 'Dave', partner_id: 3 },
    ];
    const teams = dedupeTeams(members);
    expect(teams).toHaveLength(2);
    expect(teams[0].map((m) => m.id)).toEqual([1, 2]);
    expect(teams[1].map((m) => m.id)).toEqual([3, 4]);
  });

  test('a member with no partner becomes a team of one', () => {
    const members = [
      { id: 1, username: 'Alice', partner_id: null },
    ];
    const teams = dedupeTeams(members);
    expect(teams).toEqual([[members[0]]]);
  });

  test('a partner_id pointing outside the given list is treated as unresolved (team of one)', () => {
    const members = [
      { id: 1, username: 'Alice', partner_id: 99 },
    ];
    const teams = dedupeTeams(members);
    expect(teams).toEqual([[members[0]]]);
  });

  test('never double-counts a pair regardless of which partner is listed first', () => {
    const members = [
      { id: 2, username: 'Bob', partner_id: 1 },
      { id: 1, username: 'Alice', partner_id: 2 },
    ];
    const teams = dedupeTeams(members);
    expect(teams).toHaveLength(1);
    expect(teams[0].map((m) => m.id).sort()).toEqual([1, 2]);
  });

  test('empty input returns no teams', () => {
    expect(dedupeTeams([])).toEqual([]);
  });
});
