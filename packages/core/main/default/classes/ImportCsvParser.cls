/**
 * Reads a CSV file on the server, for the one case that has no browser to read it in: a
 * recurring source loading a file nobody uploaded (R-IT6).
 *
 * The wizard still parses in the browser, and that stays the main path, because it keeps a
 * large file out of the request. This parser exists so a scheduled job is not a second, worse
 * kind of import that only understands simple files.
 *
 * It handles what a spreadsheet actually produces: quoted fields, commas and line breaks
 * inside quotes, doubled quotes as an escaped quote, both line endings, and the byte order
 * mark Excel writes at the front of a UTF-8 file.
 */
@NamespaceAccessible
public with sharing class ImportCsvParser {
    /** The byte order mark Excel writes, which is not part of the first column's name. */
    private static final String BOM = '﻿';

    /** One parsed file: the header row, and each row as values keyed by column name. */
    @NamespaceAccessible
    public class Parsed {
        @NamespaceAccessible
        public List<String> headers = new List<String>();
        @NamespaceAccessible
        public List<Map<String, Object>> rows = new List<Map<String, Object>>();
    }

    /**
     * Parses a whole file. A file with no header row, or with nothing under the header, comes
     * back empty rather than throwing: the caller reports that as an import with no rows,
     * which is a sentence an administrator can act on.
     */
    @NamespaceAccessible
    public static Parsed parse(String text) {
        Parsed result = new Parsed();
        if (String.isBlank(text)) {
            return result;
        }
        List<List<String>> lines = split(text.removeStart(BOM));
        if (lines.isEmpty()) {
            return result;
        }
        for (String heading : lines[0]) {
            result.headers.add(heading == null ? '' : heading.trim());
        }
        for (Integer i = 1; i < lines.size(); i++) {
            List<String> cells = lines[i];
            if (isEmptyLine(cells)) {
                continue;
            }
            Map<String, Object> row = new Map<String, Object>();
            for (Integer c = 0; c < result.headers.size(); c++) {
                String heading = result.headers[c];
                if (String.isBlank(heading)) {
                    continue;
                }
                row.put(heading, c < cells.size() ? cells[c] : '');
            }
            result.rows.add(row);
        }
        return result;
    }

    /** The file as rows of cells, respecting quotes. */
    private static List<List<String>> split(String text) {
        List<List<String>> lines = new List<List<String>>();
        List<String> cells = new List<String>();
        String cell = '';
        Boolean quoted = false;
        Integer length = text.length();
        for (Integer i = 0; i < length; i++) {
            String character = text.substring(i, i + 1);
            if (quoted) {
                if (character != '"') {
                    cell += character;
                    continue;
                }
                Boolean escaped = i + 1 < length && text.substring(i + 1, i + 2) == '"';
                if (escaped) {
                    cell += '"';
                    i++;
                } else {
                    quoted = false;
                }
                continue;
            }
            if (character == '"') {
                quoted = true;
            } else if (character == ',') {
                cells.add(cell.trim());
                cell = '';
            } else if (character == '\n' || character == '\r') {
                // A carriage return followed by a line feed is one ending, not two.
                if (character == '\r' && i + 1 < length && text.substring(i + 1, i + 2) == '\n') {
                    i++;
                }
                cells.add(cell.trim());
                lines.add(cells);
                cells = new List<String>();
                cell = '';
            } else {
                cell += character;
            }
        }
        cells.add(cell.trim());
        if (!isEmptyLine(cells)) {
            lines.add(cells);
        }
        return lines;
    }

    private static Boolean isEmptyLine(List<String> cells) {
        for (String cell : cells) {
            if (String.isNotBlank(cell)) {
                return false;
            }
        }
        return true;
    }
}
