import { createElement } from 'lwc';
import ReceiptActions from 'c/receiptActions';
import getGiftReceiptState from '@salesforce/apex/ReceiptController.getGiftReceiptState';
import issueReceipt from '@salesforce/apex/ReceiptController.issue';
import voidAndReissue from '@salesforce/apex/ReceiptController.voidAndReissue';

jest.mock(
  '@salesforce/apex/ReceiptController.getGiftReceiptState',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ReceiptController.issue',
  () => ({ default: jest.fn(() => Promise.resolve({ receiptNumber: 'HFH-2026-000001' })) }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ReceiptController.voidAndReissue',
  () => ({ default: jest.fn(() => Promise.resolve({ receiptNumber: 'HFH-2026-000002' })) }),
  { virtual: true }
);
jest.mock('@salesforce/apex', () => ({ refreshApex: jest.fn(() => Promise.resolve()) }), {
  virtual: true
});

const GIFT_ID = 'a00000000000001';

function build() {
  const element = createElement('c-receipt-actions', { is: ReceiptActions });
  element.recordId = GIFT_ID;
  document.body.appendChild(element);
  return element;
}

function flush() {
  return Promise.resolve();
}

describe('c-receipt-actions', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('offers to issue a receipt when the gift has none', async () => {
    const element = build();
    getGiftReceiptState.emit({ canIssue: true, alreadyReceipted: false, receipts: [] });
    await flush();

    const buttons = element.shadowRoot.querySelectorAll('lightning-button');
    expect(buttons).toHaveLength(1);
    expect(buttons[0].label).toBe('Issue receipt');
  });

  it('offers void and reissue once the gift is receipted, and never a plain edit', async () => {
    const element = build();
    getGiftReceiptState.emit({
      canIssue: true,
      alreadyReceipted: true,
      receipts: [
        {
          id: 'a02000000000001',
          receiptNumber: 'HFH-2026-000001',
          status: 'Issued',
          amount: 250
        }
      ]
    });
    await flush();

    const labels = Array.from(element.shadowRoot.querySelectorAll('lightning-button')).map(
      (button) => button.label
    );
    expect(labels).toEqual(['Void and reissue']);
  });

  it('refuses to void without a reason, and does not call the server', async () => {
    const element = build();
    getGiftReceiptState.emit({
      canIssue: true,
      alreadyReceipted: true,
      receipts: [
        {
          id: 'a02000000000001',
          receiptNumber: 'HFH-2026-000001',
          status: 'Issued',
          amount: 250
        }
      ]
    });
    await flush();

    element.shadowRoot.querySelector('lightning-button').click();
    await flush();

    expect(voidAndReissue).not.toHaveBeenCalled();
  });

  it('issues a receipt when asked', async () => {
    const element = build();
    getGiftReceiptState.emit({ canIssue: true, alreadyReceipted: false, receipts: [] });
    await flush();

    element.shadowRoot.querySelector('lightning-button').click();
    await flush();

    expect(issueReceipt).toHaveBeenCalledWith({ giftId: GIFT_ID });
  });

  it('offers nothing to a user who cannot issue receipts', async () => {
    const element = build();
    getGiftReceiptState.emit({ canIssue: false, alreadyReceipted: false, receipts: [] });
    await flush();

    expect(element.shadowRoot.querySelectorAll('lightning-button')).toHaveLength(0);
  });
});
