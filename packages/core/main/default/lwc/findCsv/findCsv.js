/**
 * Writes Find's export as a CSV file (canonical model R-Q5, ADR-0047 amended, security review
 * notes: CSV injection).
 *
 * - UTF-8 with a byte-order mark, so Excel reads accented names correctly.
 * - Every cell holding a comma, a quote or a line break is quoted, and quotes are doubled.
 * - A text cell that begins with =, +, -, @, a tab or a carriage return is written with an
 *   apostrophe in front, so a spreadsheet shows it as text and never runs it as a formula.
 *   Number, date and true or false columns hold values the server typed, and are written as
 *   they are.
 */

/** The session storage key a query sent from Find to bulk update travels under. */
export const HANDOFF_KEY = 'barncrm.bulkUpdate.document';

const BOM = '\uFEFF';
const LINE = '\r\n';
const FORMULA_START = /^[=+\-@\t\r]/;
const NEEDS_QUOTES = /[",\r\n]/;
const VALUE_TYPES = new Set([
  'integer',
  'long',
  'double',
  'currency',
  'percent',
  'boolean',
  'date',
  'datetime',
  'time'
]);

/** One cell, escaped for its column's type. */
export function csvCell(value, type) {
  if (value === null || value === undefined) {
    return '';
  }
  let text = String(value);
  if (!VALUE_TYPES.has(type) && FORMULA_START.test(text)) {
    text = `'${text}`;
  }
  if (NEEDS_QUOTES.test(text)) {
    text = `"${text.replace(/"/g, '""')}"`;
  }
  return text;
}

/**
 * The whole file: a header row of the column labels, then one line per row. `rows` are maps
 * from column path to value, as the server returns them.
 */
export function toCsv(columns, rows) {
  const header = columns.map((column) => csvCell(column.label, 'string')).join(',');
  const lines = [header];
  for (const row of rows) {
    lines.push(columns.map((column) => csvCell(row[column.path], column.type)).join(','));
  }
  return BOM + lines.join(LINE) + LINE;
}

/** Offers the text to the browser as a file download. */
export function download(name, text) {
  const blob = new Blob([text], { type: 'text/csv;charset=utf-8' });
  const url = URL.createObjectURL(blob);
  const link = document.createElement('a');
  link.href = url;
  link.download = name;
  link.style.display = 'none';
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
  URL.revokeObjectURL(url);
}

/** A file name from the kind of record and today's date, with nothing a file system refuses. */
export function fileName(objectLabel, today = new Date()) {
  const date = today.toISOString().slice(0, 10);
  const safe = String(objectLabel || 'Records')
    .replace(/[^A-Za-z0-9 _-]/g, '')
    .trim();
  return `${safe || 'Records'} ${date}.csv`;
}
