import { csvCell, toCsv, fileName, download } from 'c/findCsv';

describe('the Find CSV file', () => {
  it('starts with a byte-order mark and ends every line with CRLF', () => {
    const text = toCsv([{ path: 'Name', label: 'Name', type: 'string' }], [{ Name: 'Ana' }]);
    expect(text.charCodeAt(0)).toBe(0xfeff);
    expect(text.slice(1)).toBe('Name\r\nAna\r\n');
  });

  it('quotes a cell with a comma, a quote or a line break, doubling the quotes', () => {
    expect(csvCell('Smith, Jane', 'string')).toBe('"Smith, Jane"');
    expect(csvCell('say "hi"', 'string')).toBe('"say ""hi"""');
    expect(csvCell('two\nlines', 'textarea')).toBe('"two\nlines"');
  });

  it.each(['=SUM(A1:A2)', '+1', '-2+3', '@cmd', '\tx', '\rx'])(
    'writes a text cell that starts like a formula (%s) as text',
    (value) => {
      expect(csvCell(value, 'string').replace(/^"/, '').startsWith("'")).toBe(true);
    }
  );

  it('leaves numbers, dates and true or false values as they are', () => {
    expect(csvCell(-12.5, 'currency')).toBe('-12.5');
    expect(csvCell('2026-09-27', 'date')).toBe('2026-09-27');
    expect(csvCell(true, 'boolean')).toBe('true');
  });

  it('writes an empty cell for a missing value, and reads each row by column path', () => {
    const columns = [
      { path: 'Id', label: 'Record ID', type: 'id' },
      { path: 'Account.Name', label: 'Account > Account Name', type: 'string' }
    ];
    const text = toCsv(columns, [{ Id: '003A', 'Account.Name': null }]);
    expect(text.slice(1).split('\r\n')[1]).toBe('003A,');
    expect(text.slice(1).split('\r\n')[0]).toBe('Record ID,Account > Account Name');
  });

  it('names the file after the kind of record and the date', () => {
    expect(fileName('Contacts', new Date('2026-09-27T12:00:00Z'))).toBe('Contacts 2026-09-27.csv');
    expect(fileName('<bad>/name', new Date('2026-09-27T12:00:00Z'))).toBe('badname 2026-09-27.csv');
  });

  it('offers the text as a download', () => {
    global.URL.createObjectURL = jest.fn(() => 'blob:x');
    global.URL.revokeObjectURL = jest.fn();
    const click = jest.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(() => {});
    download('Contacts.csv', 'a,b');
    expect(global.URL.createObjectURL).toHaveBeenCalled();
    expect(click).toHaveBeenCalled();
    expect(global.URL.revokeObjectURL).toHaveBeenCalledWith('blob:x');
    click.mockRestore();
  });
});
