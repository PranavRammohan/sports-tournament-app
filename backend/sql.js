// sql.js
// Tiny, pure SQL-string helpers shared across route files — GAP-08 from the
// codebase audit surfaced that every ILIKE search site (search-players,
// /sports/search, and now the browse-leagues name search) interpolates
// `%${q}%` without escaping, so a `%` or `_` typed by the searching user
// still acts as a wildcard instead of a literal character (e.g. searching
// for "50%" matches every username, not just ones containing "50%").
function escapeLikePattern(value) {
  return value.replace(/[%_\\]/g, (ch) => `\\${ch}`);
}

module.exports = { escapeLikePattern };
