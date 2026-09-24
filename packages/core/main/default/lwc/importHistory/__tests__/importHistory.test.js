import { createElement } from 'lwc';
import ImportHistory from 'c/importHistory';
import getRecentBatches from '@salesforce/apex/ImportController.getRecentBatches';
import previewUndo from '@salesforce/apex/ImportController.previewUndo';
import startUndo from '@salesforce/apex/ImportController.startUndo';

jest.mock('@salesforce/apex/ImportController.getRecentBatches', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.previewUndo', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.startUndo', () => ({ default: jest.fn() }), {
  virtual: true
});

const COMPLETE = {
  id: 'a01000000000001AAA',
  name: 'IB-000001',
  fileName: 'donors.csv',
  status: 'Complete',
  canUndo: true,
  undoDeadline: '2026-10-23T10:00:00.000Z'
};
const DRY_RUN = {
  ...COMPLETE,
  id: 'a01000000000002AAA',
  status: 'Dry run complete',
  canUndo: false
};
const PREVIEW = {
  allowed: true,
  people: 4,
  households: 3,
  organizations: 1,
  total: 8,
  updates: 2
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render() {
  const element = createElement('c-import-history', { is: ImportHistory });
  document.body.appendChild(element);
  await flush();
  return element;
}

function undoButtons(element) {
  return Array.from(element.shadowRoot.querySelectorAll('lightning-button')).filter(
    (button) => button.dataset.id === COMPLETE.id
  );
}

describe('the recent imports list', () => {
  beforeEach(() => {
    getRecentBatches.mockResolvedValue([COMPLETE, DRY_RUN]);
    previewUndo.mockResolvedValue(PREVIEW);
    startUndo.mockResolvedValue({ ...COMPLETE, status: 'Undoing', canUndo: false });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists recent imports and offers Undo only where the batch allows it', async () => {
    const element = await render();
    expect(element.shadowRoot.querySelectorAll('[data-id="batch"]')).toHaveLength(2);
    expect(undoButtons(element)).toHaveLength(1);
    expect(element.shadowRoot.querySelectorAll('lightning-formatted-date-time')).toHaveLength(1);
  });

  it('says so when nothing has been imported', async () => {
    getRecentBatches.mockResolvedValue([]);
    const element = await render();
    expect(element.shadowRoot.querySelector('[data-id="empty"]')).not.toBeNull();
  });

  it('shows what an undo would do before doing anything', async () => {
    const element = await render();
    undoButtons(element)[0].click();
    await flush();

    expect(previewUndo).toHaveBeenCalledWith({ batchId: COMPLETE.id });
    expect(startUndo).not.toHaveBeenCalled();
    const people = element.shadowRoot.querySelector('[data-id="people"] p');
    expect(people.textContent).toBe('4');
  });

  it("counts a module's own records, such as gifts, under their own label", async () => {
    previewUndo.mockResolvedValue({
      ...PREVIEW,
      others: [{ objectName: 'Gift__c', label: 'Gifts', count: 3 }]
    });
    const element = await render();
    undoButtons(element)[0].click();
    await flush();

    const gifts = element.shadowRoot.querySelectorAll('[data-id="other-Gift__c"] p');
    expect(gifts[0].textContent).toBe('3');
    expect(gifts[1].textContent).toBe('Gifts');
  });

  it('sends back the total it showed when the undo is confirmed', async () => {
    const element = await render();
    undoButtons(element)[0].click();
    await flush();
    element.shadowRoot.querySelector('[data-id="confirm-button"]').click();
    await flush();

    expect(startUndo).toHaveBeenCalledWith({ batchId: COMPLETE.id, confirmedTotal: 8 });
    expect(element.shadowRoot.querySelector('[data-id="notice"]')).not.toBeNull();
    expect(getRecentBatches).toHaveBeenCalledTimes(2);
  });

  it('shows the reason and cannot be confirmed when the undo is refused', async () => {
    previewUndo.mockResolvedValue({ allowed: false, reason: 'The time to undo has ended.' });
    const element = await render();
    undoButtons(element)[0].click();
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="error"]').textContent).toContain(
      'The time to undo has ended.'
    );
    expect(element.shadowRoot.querySelector('[data-id="confirm-button"]').disabled).toBe(true);
  });

  it('shows the server message when starting the undo fails', async () => {
    startUndo.mockRejectedValue({
      body: { message: 'You confirmed 8 records, but 9 now carry it.' }
    });
    const element = await render();
    undoButtons(element)[0].click();
    await flush();
    element.shadowRoot.querySelector('[data-id="confirm-button"]').click();
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="error"]').textContent).toContain('9 now');
  });

  it('can be left without undoing anything', async () => {
    const element = await render();
    undoButtons(element)[0].click();
    await flush();
    element.shadowRoot.querySelector('[data-id="cancel"]').click();
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="confirm"]')).toBeNull();
    expect(startUndo).not.toHaveBeenCalled();
  });
});
