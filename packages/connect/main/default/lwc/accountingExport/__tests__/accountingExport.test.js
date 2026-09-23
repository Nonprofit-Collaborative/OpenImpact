import { createElement } from 'lwc';
import AccountingExport from 'c/accountingExport';
import getPaymentMethods from '@salesforce/apex/AccountingExportController.getPaymentMethods';
import exportGifts from '@salesforce/apex/AccountingExportController.exportGifts';

jest.mock(
  '@salesforce/apex/AccountingExportController.getPaymentMethods',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/AccountingExportController.exportGifts',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);

jest.mock(
  '@salesforce/label/c.Connect_AccountingExport_Summary',
  () => ({ default: '{0} rows from {1} gifts. Net total {2}.' }),
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Connect_AccountingExport_NoGifts',
  () => ({ default: 'No gifts in this range.' }),
  { virtual: true }
);

jest.mock(
  '@salesforce/label/c.Connect_AccountingExport_ErrorDatesRequired',
  () => ({ default: 'Choose a From date and a To date.' }),
  { virtual: true }
);

jest.mock('@salesforce/i18n/locale', () => ({ default: 'en-US' }), { virtual: true });
jest.mock('@salesforce/i18n/currency', () => ({ default: 'USD' }), { virtual: true });

const flush = () =>
  Promise.resolve()
    .then(() => Promise.resolve())
    .then(() => Promise.resolve());

function mount() {
  const element = createElement('c-accounting-export', { is: AccountingExport });
  document.body.appendChild(element);
  return element;
}

function change(element, id, detail) {
  element.shadowRoot
    .querySelector(`[data-id="${id}"]`)
    .dispatchEvent(new CustomEvent('change', { detail }));
}

function chooseAugust(element) {
  change(element, 'from', { value: '2026-08-01' });
  change(element, 'to', { value: '2026-08-31' });
}

function click(element) {
  element.shadowRoot.querySelector('[data-id="download"]').click();
}

function text(element, id) {
  const node = element.shadowRoot.querySelector(`[data-id="${id}"]`);
  return node ? node.textContent.trim() : null;
}

describe('c-accounting-export', () => {
  let clicked;

  beforeEach(() => {
    clicked = [];
    global.URL.createObjectURL = jest.fn(() => 'blob:export');
    global.URL.revokeObjectURL = jest.fn();
    jest.spyOn(HTMLAnchorElement.prototype, 'click').mockImplementation(function record() {
      clicked.push({ href: this.href, download: this.download });
    });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    jest.restoreAllMocks();
  });

  it('offers every payment method after All payment methods', async () => {
    const element = mount();
    getPaymentMethods.emit([
      { label: 'Card', value: 'Card' },
      { label: 'Check', value: 'Check' }
    ]);
    await flush();

    const options = element.shadowRoot.querySelector('[data-id="method"]').options;
    expect(options.map((option) => option.value)).toEqual(['', 'Card', 'Check']);
  });

  it('downloads the file and says what it held', async () => {
    exportGifts.mockResolvedValue({
      csv: 'Date,Gift Number\r\n',
      fileName: 'accounting-export-2026-08-01-to-2026-08-31.csv',
      rowCount: 5,
      giftCount: 4,
      total: 410
    });
    const element = mount();
    chooseAugust(element);
    change(element, 'fund', { recordId: 'a01000000000001AAA' });
    change(element, 'method', { value: 'Check' });
    await flush();

    click(element);
    await flush();

    expect(exportGifts).toHaveBeenCalledWith({
      fromDate: '2026-08-01',
      toDate: '2026-08-31',
      fundId: 'a01000000000001AAA',
      paymentMethod: 'Check'
    });
    expect(clicked).toEqual([
      { href: 'blob:export', download: 'accounting-export-2026-08-01-to-2026-08-31.csv' }
    ]);
    expect(text(element, 'message')).toBe('5 rows from 4 gifts. Net total $410.00.');
  });

  it('sends empty choices as null and saves nothing for an empty range', async () => {
    exportGifts.mockResolvedValue({ csv: null, rowCount: 0, giftCount: 0, total: 0 });
    const element = mount();
    chooseAugust(element);
    await flush();

    click(element);
    await flush();

    expect(exportGifts).toHaveBeenCalledWith({
      fromDate: '2026-08-01',
      toDate: '2026-08-31',
      fundId: null,
      paymentMethod: null
    });
    expect(clicked).toEqual([]);
    expect(text(element, 'message')).toBe('No gifts in this range.');
  });

  it('asks for both dates before calling the server', async () => {
    const element = mount();
    change(element, 'from', { value: '2026-08-01' });
    await flush();

    click(element);
    await flush();

    expect(exportGifts).not.toHaveBeenCalled();
    expect(text(element, 'error')).toBe('Choose a From date and a To date.');
  });

  it("shows the server's refusal in its own words", async () => {
    exportGifts.mockRejectedValue({ body: { message: 'The To date is before the From date.' } });
    const element = mount();
    chooseAugust(element);
    await flush();

    click(element);
    await flush();

    expect(clicked).toEqual([]);
    expect(text(element, 'error')).toBe('The To date is before the From date.');
  });
});
