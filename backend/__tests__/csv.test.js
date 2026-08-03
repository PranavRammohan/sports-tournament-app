// Unit tests for csv.js's toCsv — GAP-07 results export. Pure module, no DB.
const { toCsv, escapeCsvField } = require('../csv');

describe('escapeCsvField', () => {
  test('leaves a plain value untouched', () => {
    expect(escapeCsvField('Alice')).toBe('Alice');
  });

  test('null and undefined become an empty string', () => {
    expect(escapeCsvField(null)).toBe('');
    expect(escapeCsvField(undefined)).toBe('');
  });

  test('numbers are stringified', () => {
    expect(escapeCsvField(42)).toBe('42');
  });

  test('a value containing a comma is quoted', () => {
    expect(escapeCsvField('Smith, John')).toBe('"Smith, John"');
  });

  test('a value containing a double quote is quoted and the quote doubled', () => {
    expect(escapeCsvField('6\'2" tall')).toBe('"6\'2"" tall"');
  });

  test('a value containing a newline is quoted', () => {
    expect(escapeCsvField('line1\nline2')).toBe('"line1\nline2"');
  });
});

describe('toCsv', () => {
  test('joins headers and rows with commas and CRLF', () => {
    const csv = toCsv(['Name', 'Wins'], [['Alice', 5], ['Bob', 3]]);
    expect(csv).toBe('Name,Wins\r\nAlice,5\r\nBob,3');
  });

  test('escapes fields that need it within a full CSV', () => {
    const csv = toCsv(['Name'], [['Smith, John']]);
    expect(csv).toBe('Name\r\n"Smith, John"');
  });

  test('an empty rows array produces just the header line', () => {
    expect(toCsv(['A', 'B'], [])).toBe('A,B');
  });
});
