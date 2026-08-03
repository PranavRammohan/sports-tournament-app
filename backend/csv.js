// csv.js
// A plain, pure, DB-free module — GAP-07 (results export) from the codebase
// audit. RFC-4180 style escaping: a field gets wrapped in double quotes if
// it contains a comma, a double quote, or a newline, and any double quote
// inside it is doubled. Pure and side-effect-free, so it's unit-tested like
// this codebase's other extracted pure functions (ratingEngine.js, etc).

function escapeCsvField(value) {
  if (value === null || value === undefined) return '';
  const str = String(value);
  if (/[",\n\r]/.test(str)) {
    return `"${str.replace(/"/g, '""')}"`;
  }
  return str;
}

// `rows` is an array of arrays, already in column order matching `headers` —
// callers build the row arrays themselves rather than passing objects, so
// there's no ambiguity about column order or naming.
function toCsv(headers, rows) {
  const lines = [headers.map(escapeCsvField).join(',')];
  for (const row of rows) {
    lines.push(row.map(escapeCsvField).join(','));
  }
  // CRLF is the RFC-4180 line ending and what every spreadsheet app expects.
  return lines.join('\r\n');
}

module.exports = { toCsv, escapeCsvField };
