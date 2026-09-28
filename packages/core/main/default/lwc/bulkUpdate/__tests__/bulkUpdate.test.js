import { createElement } from 'lwc';
import BulkUpdate from 'c/bulkUpdate';
import getContext from '@salesforce/apex/BulkUpdateController.getContext';
import getSavedQueries from '@salesforce/apex/BulkUpdateController.getSavedQueries';
import openQuery from '@salesforce/apex/BulkUpdateController.openQuery';
import describeQuery from '@salesforce/apex/BulkUpdateController.describeQuery';
import previewUpdate from '@salesforce/apex/BulkUpdateController.preview';
import startUpdate from '@salesforce/apex/BulkUpdateController.start';
import getRecentJobs from '@salesforce/apex/BulkUpdateController.getRecentJobs';
import previewUndo from '@salesforce/apex/BulkUpdateController.previewUndo';
import startUndo from '@salesforce/apex/BulkUpdateController.startUndo';

jest.mock('@salesforce/apex/BulkUpdateController.getContext', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkUpdateController.getSavedQueries', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkUpdateController.openQuery', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkUpdateController.describeQuery', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkUpdateController.preview', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkUpdateController.start', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkUpdateController.getRecentJobs', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkUpdateController.previewUndo', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/BulkUpdateController.startUndo', () => ({ default: jest.fn() }), {
  virtual: true
});

const DOCUMENT = JSON.stringify({ version: 1, object: 'Contact', fields: ['MailingCity'] });
const QUERY = {
  objectName: 'Contact',
  objectLabel: 'Contacts',
  soql: 'SELECT Id, MailingCity FROM Contact LIMIT 49000',
  targets: [
    {
      name: 'MailingCity',
      label: 'Mailing City',
      type: 'string',
      nillable: true,
      sources: [{ label: 'Other City', value: 'OtherCity' }]
    },
    {
      name: 'HasOptedOutOfEmail',
      label: 'Email Opt Out',
      type: 'boolean',
      nillable: false,
      sources: []
    }
  ]
};
const PREVIEW = {
  count: 12,
  maximum: 49000,
  sample: [
    {
      id: '003A',
      name: 'Ana Lee',
      changes: [{ field: 'MailingCity', label: 'Mailing City', before: 'Salem', after: 'Portland' }]
    }
  ]
};
const JOB = {
  id: 'a01B',
  name: 'IB-000002',
  status: 'Complete',
  objectName: 'Contact',
  matched: 12,
  updated: 11,
  unchanged: 1,
  failed: 0,
  canUndo: true,
  undoDeadline: '2026-10-27T10:00:00.000Z'
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render() {
  const element = createElement('c-bulk-update', { is: BulkUpdate });
  document.body.appendChild(element);
  await flush();
  await flush();
  return element;
}

function byId(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

function edit(element, part, value) {
  const control = element.shadowRoot.querySelector(`[data-id="change"] [data-part="${part}"]`);
  control.dispatchEvent(new CustomEvent('change', { detail: { value } }));
}

async function previewCity(element) {
  edit(element, 'field', 'MailingCity');
  await flush();
  edit(element, 'value', 'Portland');
  await flush();
  byId(element, 'preview').click();
  await flush();
}

describe('the bulk update page', () => {
  beforeEach(() => {
    getContext.mockResolvedValue({ canUse: true, maximum: 49000, maxChanges: 5 });
    getSavedQueries.mockResolvedValue([{ id: 'a0S1', name: 'Salem people', isOwn: true }]);
    openQuery.mockResolvedValue({ id: 'a0S1', document: DOCUMENT });
    describeQuery.mockResolvedValue(QUERY);
    previewUpdate.mockResolvedValue(PREVIEW);
    startUpdate.mockResolvedValue({ id: 'a01C', name: 'IB-000003' });
    getRecentJobs.mockResolvedValue([JOB]);
    previewUndo.mockResolvedValue({ allowed: true, updates: 11, total: 0 });
    startUndo.mockResolvedValue();
    window.sessionStorage.clear();
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('says the permission is needed without it', async () => {
    getContext.mockResolvedValue({ canUse: false });
    const element = await render();
    expect(byId(element, 'no-permission')).not.toBeNull();
    expect(getRecentJobs).not.toHaveBeenCalled();
  });

  it('takes the query Find handed over, once', async () => {
    window.sessionStorage.setItem('barncrm.bulkUpdate.document', DOCUMENT);
    const element = await render();
    expect(describeQuery).toHaveBeenCalledWith({ documentJson: DOCUMENT });
    expect(byId(element, 'soql').value).toBe(QUERY.soql);
    expect(window.sessionStorage.getItem('barncrm.bulkUpdate.document')).toBeNull();
  });

  it('asks for a query when none was handed over', async () => {
    const element = await render();
    expect(byId(element, 'no-query')).not.toBeNull();
    expect(describeQuery).not.toHaveBeenCalled();
  });

  it('opens a saved query', async () => {
    const element = await render();
    byId(element, 'saved').dispatchEvent(new CustomEvent('change', { detail: { value: 'a0S1' } }));
    await flush();
    await flush();
    expect(openQuery).toHaveBeenCalledWith({ queryId: 'a0S1' });
    expect(byId(element, 'object-line')).not.toBeNull();
  });

  it('previews, and starts only once the count is typed, sending that count', async () => {
    window.sessionStorage.setItem('barncrm.bulkUpdate.document', DOCUMENT);
    const element = await render();
    await previewCity(element);

    expect(JSON.parse(previewUpdate.mock.calls[0][0].changesJson)).toEqual([
      { field: 'MailingCity', action: 'set', value: 'Portland' }
    ]);
    expect(element.shadowRoot.querySelectorAll('[data-id="sample-row"]')).toHaveLength(1);
    expect(byId(element, 'start').disabled).toBe(true);

    const confirm = byId(element, 'confirm-count');
    confirm.dispatchEvent(new CustomEvent('change', { detail: { value: '11' } }));
    await flush();
    expect(byId(element, 'start').disabled).toBe(true);
    confirm.dispatchEvent(new CustomEvent('change', { detail: { value: '12' } }));
    await flush();
    expect(byId(element, 'start').disabled).toBe(false);

    byId(element, 'start').click();
    await flush();
    expect(startUpdate).toHaveBeenCalledWith({
      documentJson: DOCUMENT,
      changesJson: JSON.stringify([{ field: 'MailingCity', action: 'set', value: 'Portland' }]),
      confirmedCount: 12
    });
    expect(byId(element, 'notice').textContent).toBe('c.Core_BulkUpdate_Started');
  });

  it('drops the preview when a change is edited, so a stale count is never confirmed', async () => {
    window.sessionStorage.setItem('barncrm.bulkUpdate.document', DOCUMENT);
    const element = await render();
    await previewCity(element);
    expect(byId(element, 'preview-box')).not.toBeNull();
    edit(element, 'value', 'Eugene');
    await flush();
    expect(byId(element, 'preview-box')).toBeNull();
  });

  it("shows the server's refusal, such as more records than confirmed", async () => {
    window.sessionStorage.setItem('barncrm.bulkUpdate.document', DOCUMENT);
    startUpdate.mockRejectedValue({
      body: { message: 'More records match now than the 12 you confirmed.' }
    });
    const element = await render();
    await previewCity(element);
    byId(element, 'confirm-count').dispatchEvent(
      new CustomEvent('change', { detail: { value: '12' } })
    );
    await flush();
    byId(element, 'start').click();
    await flush();
    expect(byId(element, 'error').textContent).toContain('you confirmed');
  });

  it('offers clear only for a field that may be empty', async () => {
    window.sessionStorage.setItem('barncrm.bulkUpdate.document', DOCUMENT);
    const element = await render();
    edit(element, 'field', 'HasOptedOutOfEmail');
    await flush();
    const actions = element.shadowRoot
      .querySelector('[data-id="change"] [data-part="action"]')
      .options.map((option) => option.value);
    expect(actions).toEqual(['set']);
  });

  it('undoes a bulk update after showing what it would put back', async () => {
    const element = await render();
    element.shadowRoot.querySelector('lightning-button[data-id="a01B"]').click();
    await flush();
    expect(previewUndo).toHaveBeenCalledWith({ jobId: 'a01B' });
    expect(startUndo).not.toHaveBeenCalled();
    byId(element, 'undo-confirm-button').click();
    await flush();
    expect(startUndo).toHaveBeenCalledWith({ jobId: 'a01B', confirmedTotal: 0 });
    expect(getRecentJobs).toHaveBeenCalledTimes(2);
  });
});
