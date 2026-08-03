// Unit tests for sql.js's escapeLikePattern — GAP-08. Without this, a user
// typing a literal '%' or '_' into a search box gets it treated as a SQL
// LIKE/ILIKE wildcard instead of a literal character.
const { escapeLikePattern } = require('../sql');

describe('escapeLikePattern', () => {
  test('leaves an ordinary string untouched', () => {
    expect(escapeLikePattern('Alice')).toBe('Alice');
  });

  test('escapes a percent sign', () => {
    expect(escapeLikePattern('50%')).toBe('50\\%');
  });

  test('escapes an underscore', () => {
    expect(escapeLikePattern('a_b')).toBe('a\\_b');
  });

  test('escapes a literal backslash', () => {
    expect(escapeLikePattern('a\\b')).toBe('a\\\\b');
  });

  test('escapes multiple special characters in one string', () => {
    expect(escapeLikePattern('100%_off')).toBe('100\\%\\_off');
  });
});
