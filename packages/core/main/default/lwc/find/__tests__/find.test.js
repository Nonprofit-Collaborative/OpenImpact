import { createElement } from 'lwc';
import Find from 'c/find';
import { buildDocument, operatorsFor } from '../findModel';
import getContext from '@salesforce/apex/FindController.getContext';
import getObjects from '@salesforce/apex/FindController.getObjects';
import describeObject from '@salesforce/apex/FindController.describeObject';
import describePaths from '@salesforce/apex/FindController.describePaths';
import previewQuery from '@salesforce/apex/FindController.preview';
import runQuery from '@salesforce/apex/FindController.run';
import exportPage from '@salesforce/apex/FindController.exportPage';
import getSavedQueries from '@salesforce/apex/FindController.getSavedQueries';
import openQuery from '@salesforce/apex/FindController.openQuery';
import saveQuery from '@salesforce/apex/FindController.saveQuery';
import deleteQuery from '@salesforce/apex/FindController.deleteQuery';
import { download } from 'c/findCsv';

jest.mock('@salesforce/apex/FindController.getContext', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FindController.getObjects', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FindController.describeObject', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FindController.describePaths', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FindController.preview', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FindController.run', () => ({ default: jest.fn() }), { virtual: true });
jest.mock('@salesforce/apex/FindController.exportPage', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FindController.getSavedQueries', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FindController.openQuery', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FindController.saveQuery', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/FindController.deleteQuery', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('c/findCsv', () => {
  const actual = jest.requireActual('../../findCsv/findCsv');
  return { ...actual, download: jest.fn() };
});

const CONTEXT = {
  canUse: true,
  exportRowLimit: 50000,
  gridMaxRows: 2000,
  maxSortFields: 3,
  bulkUpdateTab: 'Bulk_Update'
};
const CONTACT = {
  name: 'Contact',
  label: 'Contact',
  fields: [
    {
      name: 'LastName',
      label: 'Last Name',
      type: 'string',
      filterable: true,
      sortable: true,
      showable: true
    },
    {
      name: 'CreatedDate',
      label: 'Created Date',
      type: 'datetime',
      filterable: true,
      sortable: true,
      showable: true
    }
  ]
};
const COLUMNS = [
  { path: 'Id', label: 'Contact ID', type: 'id' },
  { path: 'LastName', label: 'Last Name', type: 'string' }
];

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render() {
  const element = createElement('c-find', { is: Find });
  document.body.appendChild(element);
  await flush();
  await flush();
  return element;
}

function byId(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

async function chooseContact(element) {
  byId(element, 'object').dispatchEvent(
    new CustomEvent('change', { detail: { value: 'Contact' } })
  );
  await flush();
  await flush();
}

describe('the Find page', () => {
  beforeEach(() => {
    getContext.mockResolvedValue(CONTEXT);
    getObjects.mockResolvedValue([{ name: 'Contact', label: 'Contacts' }]);
    getSavedQueries.mockResolvedValue([]);
    describeObject.mockResolvedValue(CONTACT);
    describePaths.mockResolvedValue([{ path: 'LastName', label: 'Last Name', type: 'string' }]);
    previewQuery.mockResolvedValue({ soql: 'SELECT Id FROM Contact LIMIT 2000' });
    runQuery.mockResolvedValue({
      columns: COLUMNS,
      rows: [{ Id: '003000000000001AAA', LastName: "O'Brien" }],
      soql: 'SELECT Id, LastName FROM Contact LIMIT 2000',
      limitReached: false
    });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    jest.useRealTimers();
  });

  it('says the permission is needed, and loads nothing else, without it', async () => {
    getContext.mockResolvedValue({ canUse: false });
    const element = await render();
    expect(byId(element, 'no-permission')).not.toBeNull();
    expect(getObjects).not.toHaveBeenCalled();
    expect(byId(element, 'object')).toBeNull();
  });

  it('lists the kinds of record the server offers', async () => {
    const element = await render();
    expect(byId(element, 'object').options).toEqual([{ label: 'Contacts', value: 'Contact' }]);
  });

  it('sends a document, never query text, and shows the rows the server returns', async () => {
    const element = await render();
    await chooseContact(element);
    byId(element, 'run').click();
    await flush();

    const sent = JSON.parse(runQuery.mock.calls[0][0].documentJson);
    expect(sent).toMatchObject({ version: 1, object: 'Contact', fields: [] });
    expect(Object.keys(runQuery.mock.calls[0][0])).toEqual(['documentJson']);
    const table = byId(element, 'results');
    expect(table.data).toEqual([
      { key: '003000000000001AAA', c0: '003000000000001AAA', c1: "O'Brien" }
    ]);
    expect(table.columns[1]).toMatchObject({ label: 'Last Name', fieldName: 'c1', type: 'text' });
    expect(byId(element, 'soql').value).toBe('SELECT Id, LastName FROM Contact LIMIT 2000');
  });

  it("shows the server's sentence when a query is refused", async () => {
    runQuery.mockRejectedValue({
      body: {
        message: 'The field Secret__c does not exist on Contact, or you do not have access to it.'
      }
    });
    const element = await render();
    await chooseContact(element);
    byId(element, 'run').click();
    await flush();
    expect(byId(element, 'error').textContent).toContain('Secret__c');
  });

  it('adds the column the picker chose', async () => {
    const element = await render();
    await chooseContact(element);
    byId(element, 'column-picker').dispatchEvent(
      new CustomEvent('fieldchange', {
        detail: { path: 'LastName', label: 'Last Name', type: 'string' }
      })
    );
    await flush();
    byId(element, 'add-column').click();
    await flush();
    expect(element.shadowRoot.querySelectorAll('[data-id="column"]')).toHaveLength(1);
  });

  it('exports every page in turn and downloads one file', async () => {
    exportPage
      .mockResolvedValueOnce({
        columns: COLUMNS,
        rows: [{ Id: '003A', LastName: '=cmd' }],
        lastId: '003A',
        done: false
      })
      .mockResolvedValueOnce({
        rows: [{ Id: '003B', LastName: 'Lee' }],
        lastId: '003B',
        done: true
      });
    const element = await render();
    await chooseContact(element);
    byId(element, 'export').click();
    await flush();
    await flush();

    expect(exportPage).toHaveBeenCalledTimes(2);
    expect(exportPage.mock.calls[1][0]).toMatchObject({ afterId: '003A', alreadyExported: 1 });
    expect(download).toHaveBeenCalledTimes(1);
    const text = download.mock.calls[0][1];
    expect(text).toContain("'=cmd");
    expect(text).toContain('003B,Lee');
    expect(byId(element, 'notice').textContent).toBe('c.Core_Find_ExportDone');
  });

  it('says so when the export stopped at the export row limit', async () => {
    exportPage.mockResolvedValueOnce({
      columns: COLUMNS,
      rows: [{ Id: '003A' }],
      lastId: '003A',
      done: true,
      stoppedAtLimit: true,
      exportLimit: 1
    });
    const element = await render();
    await chooseContact(element);
    byId(element, 'export').click();
    await flush();
    await flush();
    expect(byId(element, 'notice').textContent).toBe('c.Core_Find_ExportStopped');
  });

  it("opens a colleague's shared query and saves the person's own copy", async () => {
    getSavedQueries.mockResolvedValue([
      { id: 'a0S1', name: 'Portland', isOwn: false, ownerName: 'Priya' }
    ]);
    openQuery.mockResolvedValue({
      id: 'a0S1',
      name: 'Portland',
      isOwn: false,
      isShared: true,
      ownerName: 'Priya',
      document: JSON.stringify({
        version: 1,
        object: 'Contact',
        fields: ['LastName'],
        filter: { conditions: [] },
        orderBy: []
      })
    });
    saveQuery.mockResolvedValue({ id: 'a0S2', name: 'Portland', isOwn: true });
    const element = await render();
    byId(element, 'saved').dispatchEvent(new CustomEvent('change', { detail: { value: 'a0S1' } }));
    await flush();
    await flush();

    expect(describePaths).toHaveBeenCalledWith({ objectName: 'Contact', paths: ['LastName'] });
    expect(byId(element, 'delete')).toBeNull();
    byId(element, 'save').click();
    await flush();
    byId(element, 'save-confirm').click();
    await flush();
    expect(saveQuery.mock.calls[0][0].queryId).toBeNull();
    expect(JSON.parse(saveQuery.mock.calls[0][0].documentJson).fields).toEqual(['LastName']);
  });

  it('deletes a query the person owns', async () => {
    getSavedQueries.mockResolvedValue([{ id: 'a0S1', name: 'Mine', isOwn: true }]);
    openQuery.mockResolvedValue({
      id: 'a0S1',
      name: 'Mine',
      isOwn: true,
      document: JSON.stringify({ version: 1, object: 'Contact', fields: [] })
    });
    deleteQuery.mockResolvedValue();
    const element = await render();
    byId(element, 'saved').dispatchEvent(new CustomEvent('change', { detail: { value: 'a0S1' } }));
    await flush();
    await flush();
    byId(element, 'delete').click();
    await flush();
    expect(deleteQuery).toHaveBeenCalledWith({ queryId: 'a0S1' });
  });

  it('hands the query to bulk update through session storage', async () => {
    const element = await render();
    await chooseContact(element);
    byId(element, 'send').click();
    const handed = JSON.parse(window.sessionStorage.getItem('barncrm.bulkUpdate.document'));
    expect(handed.object).toBe('Contact');
  });

  it('refreshes the read-only query shortly after a change', async () => {
    jest.useFakeTimers();
    const element = createElement('c-find', { is: Find });
    document.body.appendChild(element);
    await Promise.resolve();
    await Promise.resolve();
    await Promise.resolve();
    element.shadowRoot
      .querySelector('[data-id="object"]')
      .dispatchEvent(new CustomEvent('change', { detail: { value: 'Contact' } }));
    jest.advanceTimersByTime(400);
    expect(previewQuery).toHaveBeenCalledTimes(1);
  });
});

describe('the query document the page builds', () => {
  it('writes relative periods, lists and the logic as R-R2 and R-Q2 say', () => {
    const document = buildDocument({
      objectName: 'Contact',
      columns: [{ path: 'LastName' }],
      filters: [
        { path: 'CreatedDate', operator: 'equals', relative: 'LAST_N_DAYS', n: '30' },
        { path: 'MailingState', operator: 'in', value: 'OR, WA,' },
        { path: 'Email', operator: 'is null', value: 'ignored' },
        { operator: 'equals' }
      ],
      logic: ' 1 AND (2 OR 3) ',
      sorts: [{ path: 'LastName', direction: 'DESC' }],
      rowLimit: '500'
    });
    expect(document).toEqual({
      version: 1,
      object: 'Contact',
      fields: ['LastName'],
      filter: {
        logic: '1 AND (2 OR 3)',
        conditions: [
          { id: 1, field: 'CreatedDate', operator: 'equals', relative: 'LAST_N_DAYS', n: 30 },
          { id: 2, field: 'MailingState', operator: 'in', value: ['OR', 'WA'] },
          { id: 3, field: 'Email', operator: 'is null' }
        ]
      },
      orderBy: [{ field: 'LastName', direction: 'DESC', nulls: 'LAST' }],
      limit: 500
    });
  });

  it('offers only the conditions the server accepts for each type', () => {
    const values = (type) => operatorsFor(type).map((option) => option.value);
    expect(values('boolean')).toEqual(['equals', 'not equals']);
    expect(values('reference')).not.toContain('contains');
    expect(values('date')).not.toContain('starts with');
    expect(values('string')).toContain('starts with');
    expect(values('base64')).toEqual(['is null', 'is not null']);
  });
});
