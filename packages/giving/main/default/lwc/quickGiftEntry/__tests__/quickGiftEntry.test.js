import { createElement } from 'lwc';
import QuickGiftEntry from 'c/quickGiftEntry';
import getDefaults from '@salesforce/apex/QuickGiftEntryController.getDefaults';
import saveGift from '@salesforce/apex/QuickGiftEntryController.saveGift';

jest.mock('@salesforce/apex/QuickGiftEntryController.getDefaults', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock('@salesforce/apex/QuickGiftEntryController.saveGift', () => ({ default: jest.fn() }), {
  virtual: true
});

const DEFAULTS = {
  giftDate: '2026-09-07',
  hasPersonAccounts: false,
  defaultFundId: '001000000000000AAA',
  defaultFundName: 'Annual Fund',
  defaultAppealId: '002000000000000AAA',
  defaultAppealName: 'Spring Appeal',
  giftTypes: [
    { label: 'Cash', value: 'Cash' },
    { label: 'Check', value: 'Check' }
  ]
};

const CONTACT_ID = '003000000000000AAA';

function build() {
  const element = createElement('c-quick-gift-entry', { is: QuickGiftEntry });
  document.body.appendChild(element);
  return element;
}

function pick(element, id) {
  return element.shadowRoot.querySelector(`[data-id="${id}"]`);
}

function change(target, detail) {
  target.dispatchEvent(new CustomEvent('change', { detail }));
}

async function settle() {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
}

async function enterAGift(element) {
  change(pick(element, 'donor-person'), { recordId: CONTACT_ID });
  change(pick(element, 'amount'), { value: '50' });
  change(pick(element, 'gift-type'), { value: 'Check' });
  await settle();
}

describe('c-quick-gift-entry', () => {
  beforeEach(() => {
    getDefaults.mockResolvedValue({ ...DEFAULTS });
    saveGift.mockResolvedValue({
      success: true,
      giftId: '004000000000000AAA',
      giftName: 'G-000123',
      fieldErrors: []
    });
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('starts from the defaults the controller returns', async () => {
    const element = build();
    await settle();

    expect(getDefaults).toHaveBeenCalled();
    expect(pick(element, 'gift-date').value).toBe(DEFAULTS.giftDate);
    expect(pick(element, 'appeal').value).toBe(DEFAULTS.defaultAppealId);
    expect(pick(element, 'fund').value).toBe(DEFAULTS.defaultFundId);
    expect(pick(element, 'gift-type').options).toEqual(DEFAULTS.giftTypes);
  });

  it('searches contacts for the donor, and accounts where people are accounts', async () => {
    const contactOrg = build();
    await settle();
    expect(pick(contactOrg, 'donor-person').objectApiName).toBe('Contact');

    getDefaults.mockResolvedValue({ ...DEFAULTS, hasPersonAccounts: true });
    const personAccountOrg = build();
    await settle();
    expect(pick(personAccountOrg, 'donor-person').objectApiName).toBe('Account');
  });

  it('says the defaults could not be read when the controller fails', async () => {
    getDefaults.mockRejectedValue({ body: { message: 'Settings are unavailable.' } });
    const element = build();
    await settle();

    expect(pick(element, 'form-error').textContent).toContain('Settings are unavailable.');
  });

  it('shows the controller validation messages beside their fields', async () => {
    saveGift.mockResolvedValue({
      success: false,
      fieldErrors: [
        { field: 'donor', message: 'Choose the person or organization who gave this gift.' },
        {
          field: 'amount',
          message:
            'Enter an amount greater than zero. A refund is entered from the original gift, not here.'
        }
      ]
    });
    const element = build();
    await settle();

    pick(element, 'save').click();
    await settle();

    expect(pick(element, 'error-donor').textContent).toContain('Choose the person');
    expect(pick(element, 'error-amount').textContent).toContain('greater than zero');
    expect(pick(element, 'saved')).toBeNull();
  });

  it('saves the gift the person entered and confirms it with a link', async () => {
    const element = build();
    await settle();
    const toast = jest.fn();
    element.addEventListener('lightning__showtoast', toast);

    await enterAGift(element);
    pick(element, 'save').click();
    await settle();

    expect(saveGift).toHaveBeenCalledWith({
      input: {
        donorContactId: CONTACT_ID,
        donorAccountId: null,
        amount: 50,
        giftDate: '2026-09-07',
        giftType: 'Check',
        appealId: DEFAULTS.defaultAppealId,
        fundId: DEFAULTS.defaultFundId,
        paymentReference: null
      }
    });
    expect(pick(element, 'saved')).not.toBeNull();
    expect(pick(element, 'saved-link').href).toContain('/lightning/r/Gift__c/');
    expect(toast).toHaveBeenCalled();
    expect(toast.mock.calls[0][0].detail.messageData[0].label).toBe('G-000123');
    expect(toast.mock.calls[0][0].detail.messageData[0].url).toContain('004000000000000AAA');
  });

  it('clears the donor and the amount after save and new, and keeps the date and fund', async () => {
    const element = build();
    await settle();

    await enterAGift(element);
    pick(element, 'save-and-new').click();
    await settle();

    expect(pick(element, 'amount').value).toBeUndefined();
    expect(pick(element, 'donor-person').value).toBeUndefined();
    expect(pick(element, 'gift-date').value).toBe(DEFAULTS.giftDate);
    expect(pick(element, 'fund').value).toBe(DEFAULTS.defaultFundId);
  });

  it('shows what went wrong when the save itself fails', async () => {
    saveGift.mockRejectedValue({ body: { message: 'Insufficient access on Gift.' } });
    const element = build();
    await settle();

    await enterAGift(element);
    pick(element, 'save').click();
    await settle();

    expect(pick(element, 'form-error').textContent).toContain('Insufficient access on Gift.');
    expect(pick(element, 'saved')).toBeNull();
  });
});
