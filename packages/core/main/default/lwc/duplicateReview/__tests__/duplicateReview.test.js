import { createElement } from 'lwc';
import DuplicateReview from 'c/duplicateReview';
import getView from '@salesforce/apex/DuplicateController.getView';
import startScan from '@salesforce/apex/DuplicateController.startScan';
import dismissSuggestion from '@salesforce/apex/DuplicateController.dismiss';
import previewMerge from '@salesforce/apex/DuplicateController.previewMerge';
import mergeHouseholds from '@salesforce/apex/DuplicateController.mergeHouseholds';

jest.mock(
  '@salesforce/apex/DuplicateController.getView',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock('@salesforce/apex/DuplicateController.startScan', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock('@salesforce/apex/DuplicateController.dismiss', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock('@salesforce/apex/DuplicateController.previewMerge', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock(
  '@salesforce/apex/DuplicateController.mergeHouseholds',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock('@salesforce/customPermission/Manage_Nonprofit_Settings', () => ({ default: true }), {
  virtual: true
});

const HOUSEHOLD_ONE = '001000000000001AAA';
const HOUSEHOLD_TWO = '001000000000002AAA';
const PERSON_ONE = '003000000000001AAA';
const PERSON_TWO = '003000000000002AAA';

function viewWith(overrides) {
  return Object.assign(
    {
      canManage: true,
      anyRuleActive: true,
      rules: [
        {
          objectLabel: 'Contact',
          ruleLabel: 'Open Impact contact duplicates',
          active: true,
          shippedByOpenImpact: true
        }
      ],
      suggestions: [],
      dismissedCount: 0,
      scanRunning: false,
      lastScanFinished: null
    },
    overrides
  );
}

function householdPair() {
  return {
    setId: '0Rm000000000001AAA',
    foundAt: '2026-09-08T10:00:00.000Z',
    ruleLabel: 'Open Impact household duplicates',
    canMerge: true,
    records: [
      {
        recordId: HOUSEHOLD_ONE,
        name: 'Nguyen Household',
        detail: 'Portland, 97201',
        objectLabel: 'Household',
        isHousehold: true
      },
      {
        recordId: HOUSEHOLD_TWO,
        name: 'Nguyen Household',
        detail: 'Portland, 97201',
        objectLabel: 'Household',
        isHousehold: true
      }
    ]
  };
}

function peoplePair() {
  return {
    setId: '0Rm000000000002AAA',
    foundAt: '2026-09-08T10:00:00.000Z',
    ruleLabel: 'Open Impact contact duplicates',
    canMerge: false,
    records: [
      {
        recordId: PERSON_ONE,
        name: 'Ana Reyes',
        detail: 'ana@example.org',
        objectLabel: 'Person',
        isHousehold: false
      },
      {
        recordId: PERSON_TWO,
        name: 'Ana Reyes',
        detail: 'ana@example.org',
        objectLabel: 'Person',
        isHousehold: false
      }
    ]
  };
}

function build() {
  const element = createElement('c-duplicate-review', { is: DuplicateReview });
  document.body.appendChild(element);
  return element;
}

describe('c-duplicate-review', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('says there is nothing to review when no suggestion has been found', async () => {
    const element = build();
    getView.emit(viewWith({}));
    await Promise.resolve();

    expect(element.shadowRoot.querySelector('[data-id="empty"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="no-rules"]')).toBeNull();
  });

  it('warns when no duplicate rule is switched on, because nothing is being checked', async () => {
    const element = build();
    getView.emit(viewWith({ anyRuleActive: false }));
    await Promise.resolve();

    expect(element.shadowRoot.querySelector('[data-id="no-rules"]')).not.toBeNull();
  });

  it('offers a merge for two households and only an open link for two people', async () => {
    const element = build();
    getView.emit(viewWith({ suggestions: [householdPair(), peoplePair()] }));
    await Promise.resolve();

    const suggestions = element.shadowRoot.querySelectorAll('[data-id="suggestion"]');
    expect(suggestions.length).toBe(2);
    expect(element.shadowRoot.querySelectorAll('[data-id="merge-button"]').length).toBe(1);
    expect(element.shadowRoot.querySelectorAll('[data-id="dismiss-button"]').length).toBe(2);
  });

  it('starts a scan and reports that it is running in the background', async () => {
    startScan.mockResolvedValue(viewWith({ scanRunning: true }));
    const element = build();
    getView.emit(viewWith({}));
    await Promise.resolve();

    element.shadowRoot.querySelector('[data-id="scan-button"]').click();
    await Promise.resolve();
    await Promise.resolve();

    expect(startScan).toHaveBeenCalled();
    expect(element.shadowRoot.querySelector('[data-id="notice"]')).not.toBeNull();
  });

  it('asks for a reason before it remembers that a pair is not a duplicate', async () => {
    dismissSuggestion.mockResolvedValue(viewWith({ dismissedCount: 1 }));
    const element = build();
    getView.emit(viewWith({ suggestions: [peoplePair()] }));
    await Promise.resolve();

    element.shadowRoot.querySelector('[data-id="dismiss-button"]').click();
    await Promise.resolve();
    expect(element.shadowRoot.querySelector('[data-id="dismiss-dialog"]')).not.toBeNull();

    const reason = element.shadowRoot.querySelector('[data-id="dismiss-reason"]');
    reason.value = 'Twin sisters at one address';
    reason.dispatchEvent(new CustomEvent('change', { target: reason }));
    element.shadowRoot.querySelector('[data-id="dismiss-confirm"]').click();
    await Promise.resolve();

    expect(dismissSuggestion).toHaveBeenCalledWith({
      duplicateRecordSetId: '0Rm000000000002AAA',
      reason: 'Twin sisters at one address'
    });
  });

  it('previews the merge, and merges only after the person confirms', async () => {
    previewMerge.mockResolvedValue({
      survivorId: HOUSEHOLD_ONE,
      survivorName: 'Nguyen Household',
      victimId: HOUSEHOLD_TWO,
      victimName: 'Nguyen Household',
      canEdit: true,
      fields: [
        {
          fieldName: 'BillingStreet',
          label: 'Billing Street',
          survivorValue: '1 Oak Street',
          victimValue: '1 Oak St',
          inConflict: true
        },
        {
          fieldName: 'BillingCity',
          label: 'Billing City',
          survivorValue: 'Portland',
          victimValue: 'Portland',
          inConflict: false
        }
      ],
      members: []
    });
    mergeHouseholds.mockResolvedValue(viewWith({ suggestions: [] }));

    const element = build();
    getView.emit(viewWith({ suggestions: [householdPair()] }));
    await Promise.resolve();

    element.shadowRoot.querySelector('[data-id="merge-button"]').click();
    await Promise.resolve();
    await Promise.resolve();

    expect(previewMerge).toHaveBeenCalledWith({
      survivorId: HOUSEHOLD_ONE,
      victimId: HOUSEHOLD_TWO
    });
    expect(element.shadowRoot.querySelector('[data-id="merge-dialog"]')).not.toBeNull();
    expect(mergeHouseholds).not.toHaveBeenCalled();

    const conflicts = element.shadowRoot.querySelectorAll('[data-id="conflict"]');
    expect(conflicts.length).toBe(1);

    element.shadowRoot.querySelector('[data-id="merge-confirm"]').click();
    await Promise.resolve();

    expect(mergeHouseholds).toHaveBeenCalledWith({
      duplicateRecordSetId: '0Rm000000000001AAA',
      survivorId: HOUSEHOLD_ONE,
      victimId: HOUSEHOLD_TWO,
      fieldChoices: {}
    });
  });
});
