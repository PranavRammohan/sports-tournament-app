// Unit tests for leagueRoutes.js's nested-groups helpers — buildGroupTree,
// collectDescendantIds, wouldCreateCycle, attachCombinedMembers, and
// compareStanding. Groups can nest inside other groups to arbitrary depth
// (see the comment above buildGroupTree in leagueRoutes.js); these are the
// pure functions that turn a flat league_groups row list into a tree, guard
// against cycles when re-parenting, and build the combined-standings
// roll-up shown for a group that has sub-groups. Attached to the exported
// router the same way the other route files attach their module-private
// helpers (see the comment above module.exports in leagueRoutes.js).
const leagueRoutes = require('../leagueRoutes');
const {
  buildGroupTree,
  collectDescendantIds,
  wouldCreateCycle,
  attachCombinedMembers,
  compareStanding,
} = leagueRoutes;

describe('buildGroupTree', () => {
  test('nests rows 3 levels deep by parent_group_id', () => {
    const rows = [
      { id: 1, name: 'Summer Slam', parent_group_id: null },
      { id: 2, name: "Men's Open", parent_group_id: 1 },
      { id: 3, name: 'Group A', parent_group_id: 2 },
      { id: 4, name: 'Group B', parent_group_id: 2 },
    ];
    const tree = buildGroupTree(rows);

    expect(tree).toHaveLength(1);
    expect(tree[0].name).toBe('Summer Slam');
    expect(tree[0].children).toHaveLength(1);
    expect(tree[0].children[0].name).toBe("Men's Open");
    expect(tree[0].children[0].children.map((c) => c.name)).toEqual(['Group A', 'Group B']);
    expect(tree[0].children[0].children[0].children).toEqual([]);
  });

  test('preserves sibling ordering from the input array', () => {
    const rows = [
      { id: 1, name: 'Root', parent_group_id: null },
      { id: 2, name: 'Zebra', parent_group_id: 1 },
      { id: 3, name: 'Alpha', parent_group_id: 1 },
      { id: 4, name: 'Mid', parent_group_id: 1 },
    ];
    const tree = buildGroupTree(rows);
    expect(tree[0].children.map((c) => c.name)).toEqual(['Zebra', 'Alpha', 'Mid']);
  });

  test('a row with a dangling parent_group_id still surfaces as a root', () => {
    const rows = [
      { id: 1, name: 'Orphan', parent_group_id: 999 },
      { id: 2, name: 'Normal Root', parent_group_id: null },
    ];
    const tree = buildGroupTree(rows);
    expect(tree.map((n) => n.name).sort()).toEqual(['Normal Root', 'Orphan']);
  });

  test('multiple top-level groups with no children each become their own root', () => {
    const rows = [
      { id: 1, name: 'Tournament A', parent_group_id: null },
      { id: 2, name: 'Tournament B', parent_group_id: null },
    ];
    const tree = buildGroupTree(rows);
    expect(tree).toHaveLength(2);
    expect(tree[0].children).toEqual([]);
    expect(tree[1].children).toEqual([]);
  });
});

describe('collectDescendantIds', () => {
  test('collects every id beneath a node across multiple levels', () => {
    const rows = [
      { id: 1, parent_group_id: null },
      { id: 2, parent_group_id: 1 },
      { id: 3, parent_group_id: 2 },
      { id: 4, parent_group_id: 2 },
    ];
    const tree = buildGroupTree(rows);
    expect(collectDescendantIds(tree[0]).sort()).toEqual([2, 3, 4]);
  });

  test('a leaf node (no children) returns an empty array', () => {
    const rows = [{ id: 1, parent_group_id: null }];
    const tree = buildGroupTree(rows);
    expect(collectDescendantIds(tree[0])).toEqual([]);
  });
});

describe('wouldCreateCycle', () => {
  const rows = [
    { id: 1, parent_group_id: null },
    { id: 2, parent_group_id: 1 },
    { id: 3, parent_group_id: 2 },
  ];

  test('moving a group to be its own parent is a cycle', () => {
    expect(wouldCreateCycle(rows, 1, 1)).toBe(true);
  });

  test('a direct A -> B -> A cycle is detected', () => {
    // Group 1 is already B's ancestor (1 -> 2); parenting 1 under 2 closes the loop.
    expect(wouldCreateCycle(rows, 1, 2)).toBe(true);
  });

  test('a deep cycle (moving a group under its own grandchild) is detected', () => {
    expect(wouldCreateCycle(rows, 1, 3)).toBe(true);
  });

  test('a legitimate move to an unrelated parent is not a cycle', () => {
    const wider = [...rows, { id: 4, parent_group_id: null }];
    expect(wouldCreateCycle(wider, 3, 4)).toBe(false);
  });

  test('moving a group to the top level (null) is never a cycle', () => {
    expect(wouldCreateCycle(rows, 3, null)).toBe(false);
  });
});

describe('compareStanding', () => {
  test('ranks by points first', () => {
    const a = { points: 4, wins: 0, rating: '1000' };
    const b = { points: 6, wins: 0, rating: '1000' };
    expect(compareStanding(a, b)).toBeGreaterThan(0); // b ranks ahead of a
  });

  test('falls back to wins when points tie', () => {
    const a = { points: 4, wins: 1, rating: '1000' };
    const b = { points: 4, wins: 3, rating: '1000' };
    expect(compareStanding(a, b)).toBeGreaterThan(0);
  });

  test('falls back to rating (parsed from string) when points and wins tie', () => {
    const a = { points: 4, wins: 2, rating: '1200.5' };
    const b = { points: 4, wins: 2, rating: '1300.0' };
    expect(compareStanding(a, b)).toBeGreaterThan(0);
  });

  test('a full standings list sorts into rank order via Array.sort', () => {
    const members = [
      { id: 1, points: 2, wins: 1, rating: '1000' },
      { id: 2, points: 6, wins: 3, rating: '1100' },
      { id: 3, points: 6, wins: 2, rating: '1400' },
    ];
    expect(members.sort(compareStanding).map((m) => m.id)).toEqual([2, 3, 1]);
  });
});

describe('attachCombinedMembers', () => {
  test('a leaf node (no children) gets no combinedMembers field', () => {
    const rows = [{ id: 1, parent_group_id: null, members: [{ id: 10, points: 2, wins: 1, losses: 0, rating: '1000' }] }];
    const tree = attachCombinedMembers(buildGroupTree(rows));
    expect(tree[0].combinedMembers).toBeUndefined();
  });

  test('unions members from own roster and every descendant with no overlap', () => {
    const rows = [
      { id: 1, name: 'Parent', parent_group_id: null, members: [] },
      {
        id: 2,
        name: 'Child A',
        parent_group_id: 1,
        members: [{ id: 10, username: 'Alice', points: 4, wins: 2, losses: 0, matches_played: 2, rating: '1200' }],
      },
      {
        id: 3,
        name: 'Child B',
        parent_group_id: 1,
        members: [{ id: 20, username: 'Bob', points: 2, wins: 1, losses: 1, matches_played: 2, rating: '1100' }],
      },
    ];
    const tree = attachCombinedMembers(buildGroupTree(rows));
    const ids = tree[0].combinedMembers.map((m) => m.id).sort();
    expect(ids).toEqual([10, 20]);
  });

  test('a player placed both in the parent itself and in a child group has stats summed, not overwritten', () => {
    const rows = [
      {
        id: 1,
        name: "Men's Open",
        parent_group_id: null,
        members: [{ id: 10, username: 'Alice', points: 2, wins: 1, losses: 0, matches_played: 1, rating: '1200' }],
      },
      {
        id: 2,
        name: 'Group A',
        parent_group_id: 1,
        members: [{ id: 10, username: 'Alice', points: 4, wins: 2, losses: 1, matches_played: 3, rating: '1200' }],
      },
    ];
    const tree = attachCombinedMembers(buildGroupTree(rows));
    const alice = tree[0].combinedMembers.find((m) => m.id === 10);
    expect(alice).toMatchObject({ points: 6, wins: 3, losses: 1, matches_played: 4 });
  });

  test('combinedMembers is ranked by compareStanding, not insertion order', () => {
    const rows = [
      { id: 1, name: 'Parent', parent_group_id: null, members: [] },
      {
        id: 2,
        name: 'Child A',
        parent_group_id: 1,
        members: [{ id: 10, points: 2, wins: 1, losses: 0, matches_played: 1, rating: '1000' }],
      },
      {
        id: 3,
        name: 'Child B',
        parent_group_id: 1,
        members: [{ id: 20, points: 8, wins: 4, losses: 0, matches_played: 4, rating: '1000' }],
      },
    ];
    const tree = attachCombinedMembers(buildGroupTree(rows));
    expect(tree[0].combinedMembers.map((m) => m.id)).toEqual([20, 10]);
  });

  test('propagates up through 3 levels of nesting', () => {
    const rows = [
      { id: 1, name: 'Summer Slam', parent_group_id: null, members: [] },
      { id: 2, name: "Men's Open", parent_group_id: 1, members: [] },
      {
        id: 3,
        name: 'Group A',
        parent_group_id: 2,
        members: [{ id: 10, points: 2, wins: 1, losses: 0, matches_played: 1, rating: '1000' }],
      },
    ];
    const tree = attachCombinedMembers(buildGroupTree(rows));
    expect(tree[0].combinedMembers.map((m) => m.id)).toEqual([10]);
    expect(tree[0].children[0].combinedMembers.map((m) => m.id)).toEqual([10]);
  });
});
