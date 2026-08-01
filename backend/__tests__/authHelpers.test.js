// Unit tests for authRoutes.js's deriveDisplayName/normalizeEmail — pure
// functions (no DB access) attached to the exported router the same way
// sportsRoutes.js exposes reconstructRatingHistory (see the comment above
// module.exports in authRoutes.js).
const authRoutes = require('../authRoutes');
const { deriveDisplayName, normalizeEmail } = authRoutes;

describe('deriveDisplayName', () => {
  test('joins first and last name with a single space', () => {
    expect(deriveDisplayName('Priya', 'Sharma')).toBe('Priya Sharma');
  });

  test('trims and collapses internal whitespace from each part', () => {
    expect(deriveDisplayName('  Priya  ', '  Sharma  ')).toBe('Priya Sharma');
  });

  test('falls back to whichever name is present when the other is missing', () => {
    expect(deriveDisplayName('Priya', '')).toBe('Priya');
    expect(deriveDisplayName('', 'Sharma')).toBe('Sharma');
    expect(deriveDisplayName(null, undefined)).toBe('');
  });

  test('collapses multi-word names with extra internal spaces', () => {
    expect(deriveDisplayName('Priya  Anne', 'Van  Sharma')).toBe(
      'Priya Anne Van Sharma'
    );
  });
});

describe('normalizeEmail', () => {
  test('lowercases and trims', () => {
    expect(normalizeEmail('  Priya.Sharma@Example.COM  ')).toBe(
      'priya.sharma@example.com'
    );
  });

  test('handles null/undefined/empty input as an empty string', () => {
    expect(normalizeEmail(null)).toBe('');
    expect(normalizeEmail(undefined)).toBe('');
    expect(normalizeEmail('')).toBe('');
  });
});
