import { createElement } from 'lwc';
import GiftTransactionMirror from 'c/giftTransactionMirror';
import getStatus from '@salesforce/apex/GiftTransactionMirrorController.getStatus';
import runNow from '@salesforce/apex/GiftTransactionMirrorController.runNow';
import stop from '@salesforce/apex/GiftTransactionMirrorController.stop';
import compare from '@salesforce/apex/GiftTransactionMirrorController.compare';
import copyRangeAgain from '@salesforce/apex/GiftTransactionMirrorController.copyRangeAgain';

jest.mock(
  '@salesforce/apex/GiftTransactionMirrorController.getStatus',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/GiftTransactionMirrorController.runNow',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/GiftTransactionMirrorController.schedule',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock('@salesforce/apex/GiftTransactionMirrorController.stop', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/GiftTransactionMirrorController.compare',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/GiftTransactionMirrorController.copyRangeAgain',
  () => ({ default: jest.fn() }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Connect_GiftTransactionMirror_DirectionGifts',
  () => ({
    default: 'Received gifts dated on or after {0} get a Gift Transaction with status {1}.'
  }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Connect_GiftTransactionMirror_DirectionGiftTransactions',
  () => ({ default: 'Gift Transactions with status {1} dated on or after {0} become gifts.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Connect_GiftTransactionMirror_GiftTransactionSide',
  () => ({ default: 'Paid Gift Transactions: {0}, total {1}' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Connect_GiftTransactionMirror_DifferenceCountAll',
  () => ({ default: 'Differences found: {0}. All are listed.' }),
  { virtual: true }
);
jest.mock(
  '@salesforce/label/c.Connect_GiftTransactionMirror_ErrorFailed',
  () => ({ default: 'Something went wrong.' }),
  { virtual: true }
);

const READY = {
  available: true,
  direction: 'GiftsToGiftTransactions',
  paidStatus: 'Paid',
  startDate: '2026-09-01',
  notReady: null,
  canRun: true,
  canManage: true,
  running: false,
  nextRunAt: null
};

const COMPARISON = {
  giftCount: 2,
  giftTotal: 150,
  giftTransactionCount: 2,
  giftTransactionTotal: 175,
  differenceCount: 1,
  differences: [
    {
      key: 'a01',
      giftId: 'a01',
      giftName: 'G-0001',
      giftAmount: 100,
      giftTransactionId: '6gt000000000001',
      giftTransactionName: null,
      giftTransactionAmount: 125,
      reason: 'Amount differs'
    }
  ]
};

const flush = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

async function mount(status) {
  getStatus.mockResolvedValue(status);
  const element = createElement('c-gift-transaction-mirror', { is: GiftTransactionMirror });
  document.body.appendChild(element);
  await flush();
  return element;
}

function find(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

describe('c-gift-transaction-mirror', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('names the start date and the paid status, and offers Run now', async () => {
    const element = await mount(READY);
    expect(find(element, 'direction').textContent).toBe(
      'Received gifts dated on or after Sep 1, 2026 get a Gift Transaction with status Paid.'
    );
    expect(find(element, 'run-now').disabled).toBe(false);
    expect(find(element, 'schedule-nightly')).not.toBeNull();
    expect(find(element, 'not-ready')).toBeNull();
  });

  it('describes Gift Transactions to Gifts in its own words', async () => {
    const element = await mount({ ...READY, direction: 'GiftTransactionsToGifts' });
    expect(find(element, 'direction').textContent).toBe(
      'Gift Transactions with status Paid dated on or after Sep 1, 2026 become gifts.'
    );
  });

  it('says what is missing, and keeps Run now and Schedule off, until it is set', async () => {
    const element = await mount({
      ...READY,
      paidStatus: null,
      notReady: 'Nothing is mirrored until you set the paid status.'
    });
    expect(find(element, 'not-ready').textContent).toBe(
      'Nothing is mirrored until you set the paid status.'
    );
    expect(find(element, 'direction')).toBeNull();
    expect(find(element, 'run-now').disabled).toBe(true);
    expect(find(element, 'schedule-nightly').disabled).toBe(true);
  });

  it('still lets a scheduled run be stopped while settings are missing', async () => {
    stop.mockResolvedValue({ ...READY, notReady: 'Missing', nextRunAt: null });
    const element = await mount({
      ...READY,
      notReady: 'Missing',
      nextRunAt: '2026-09-28T01:35:00.000Z'
    });
    expect(find(element, 'stop').disabled).toBe(false);
    find(element, 'stop').click();
    await flush();
    expect(stop).toHaveBeenCalled();
    expect(find(element, 'schedule-nightly')).not.toBeNull();
  });

  it('says so, and offers nothing, where the org has no Gift Transactions', async () => {
    const element = await mount({ ...READY, available: false });
    expect(find(element, 'unavailable')).not.toBeNull();
    expect(find(element, 'run-now')).toBeNull();
    expect(find(element, 'compare')).toBeNull();
  });

  it('points at the setting while the mirror is off, and still compares', async () => {
    const element = await mount({ ...READY, direction: 'Off' });
    expect(find(element, 'off')).not.toBeNull();
    expect(find(element, 'run-now')).toBeNull();
    expect(find(element, 'compare')).not.toBeNull();
  });

  it('explains why the buttons are off for someone without the access a run needs', async () => {
    const element = await mount({ ...READY, canRun: false });
    expect(find(element, 'no-access')).not.toBeNull();
    expect(find(element, 'run-now').disabled).toBe(true);
  });

  it('keeps the buttons off for someone who cannot manage settings', async () => {
    const element = await mount({ ...READY, canManage: false });
    expect(find(element, 'no-manage')).not.toBeNull();
    expect(find(element, 'run-now').disabled).toBe(true);
    expect(find(element, 'schedule-nightly').disabled).toBe(true);
  });

  it('starts a run and says it has started', async () => {
    runNow.mockResolvedValue({ ...READY, running: true });
    const element = await mount(READY);
    find(element, 'run-now').click();
    await flush();
    expect(runNow).toHaveBeenCalled();
    expect(find(element, 'running')).not.toBeNull();
    expect(find(element, 'run-now').disabled).toBe(true);
  });

  it('shows a refusal in the words the controller gives', async () => {
    runNow.mockRejectedValue({ body: { message: 'A run is already in progress.' } });
    const element = await mount(READY);
    find(element, 'run-now').click();
    await flush();
    expect(find(element, 'error').textContent).toBe('A run is already in progress.');
  });

  it('compares a range, lists the differences and copies the compared range again', async () => {
    compare.mockResolvedValue(COMPARISON);
    copyRangeAgain.mockResolvedValue({ ...READY, running: true });
    const element = await mount(READY);
    find(element, 'compare').click();
    await flush();
    expect(find(element, 'gift-transaction-side').textContent).toBe(
      'Paid Gift Transactions: 2, total $175.00'
    );
    expect(find(element, 'difference-count').textContent).toBe(
      'Differences found: 1. All are listed.'
    );
    const row = find(element, 'differences').data[0];
    expect(row.giftTransactionUrl).toBe('/6gt000000000001');
    expect(row.giftTransactionLabel).toBe('6gt000000000001');
    const compared = compare.mock.calls[0][0];
    const from = find(element, 'from');
    from.value = '2020-01-01';
    from.dispatchEvent(new CustomEvent('change'));
    await flush();
    find(element, 'copy-again').click();
    await flush();
    expect(copyRangeAgain).toHaveBeenCalledWith(compared);
  });

  it('does not offer to copy again in Gift Transactions to Gifts', async () => {
    compare.mockResolvedValue(COMPARISON);
    const element = await mount({ ...READY, direction: 'GiftTransactionsToGifts' });
    find(element, 'compare').click();
    await flush();
    expect(find(element, 'differences')).not.toBeNull();
    expect(find(element, 'copy-again')).toBeNull();
  });

  it('checks again until a running run has finished', async () => {
    jest.useFakeTimers();
    try {
      const element = await mount({ ...READY, running: true });
      expect(find(element, 'running')).not.toBeNull();
      getStatus.mockResolvedValue(READY);
      jest.advanceTimersByTime(10000);
      await flush();
      expect(getStatus).toHaveBeenCalledTimes(2);
      expect(find(element, 'running')).toBeNull();
    } finally {
      jest.useRealTimers();
    }
  });

  it('falls back to a plain message when a failure has none', async () => {
    getStatus.mockRejectedValue(new Error('boom'));
    const element = createElement('c-gift-transaction-mirror', { is: GiftTransactionMirror });
    document.body.appendChild(element);
    await flush();
    expect(find(element, 'error').textContent).toBe('Something went wrong.');
  });
});
