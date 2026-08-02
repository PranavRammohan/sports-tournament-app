// Unit tests for notifications.js's uniqueRecipientIds — drops null/undefined
// ids and de-dupes before fanning a notification out to a list of
// recipients, so a doubles match's four participant ids (which can include
// nulls for singles matches, or the same id twice in an edge case) never
// produce a duplicate or crashing insert. Exported directly off the module
// (notifications.js is a plain module, not a router, so there's no
// router.export attachment step like the other route-file helpers).
const { uniqueRecipientIds } = require('../notifications');

describe('uniqueRecipientIds', () => {
  test('drops duplicate ids', () => {
    expect(uniqueRecipientIds([1, 2, 2, 3, 1])).toEqual(expect.arrayContaining([1, 2, 3]));
    expect(uniqueRecipientIds([1, 2, 2, 3, 1])).toHaveLength(3);
  });

  test('drops null and undefined', () => {
    expect(uniqueRecipientIds([1, null, 2, undefined, 3])).toEqual(
      expect.arrayContaining([1, 2, 3])
    );
    expect(uniqueRecipientIds([1, null, 2, undefined, 3])).toHaveLength(3);
  });

  test('empty array in, empty array out', () => {
    expect(uniqueRecipientIds([])).toEqual([]);
  });

  test('all-null input returns an empty array', () => {
    expect(uniqueRecipientIds([null, undefined, null])).toEqual([]);
  });

  test('a single valid id passes through unchanged', () => {
    expect(uniqueRecipientIds([5])).toEqual([5]);
  });
});
