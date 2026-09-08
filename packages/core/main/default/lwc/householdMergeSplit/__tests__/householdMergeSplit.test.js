// The test wire adapters below are emitted to on purpose, which is how a wired
// component is driven from a test.
/* eslint-disable @lwc/lwc/no-unexpected-wire-adapter-usages */
import { createElement } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import HouseholdMergeSplit from 'c/householdMergeSplit';
import canEdit from '@salesforce/apex/HouseholdMergeController.canEdit';
import searchHouseholds from '@salesforce/apex/HouseholdMergeController.searchHouseholds';
import getPreview from '@salesforce/apex/HouseholdMergeController.preview';
import mergeHouseholds from '@salesforce/apex/HouseholdMergeController.mergeHouseholds';
import splitHousehold from '@salesforce/apex/HouseholdMergeController.splitHousehold';
import getMembers from '@salesforce/apex/HouseholdController.getMembers';

jest.mock(
  '@salesforce/apex/HouseholdMergeController.canEdit',
  () => {
    const { createApexTestWireAdapter } = jest.requireActual('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/HouseholdController.getMembers',
  () => {
    const { createApexTestWireAdapter } = jest.requireActual('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/HouseholdMergeController.searchHouseholds',
  () => ({ default: jest.fn(() => Promise.resolve([])) }),
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/HouseholdMergeController.preview',
  () => ({ default: jest.fn(() => Promise.resolve({ fields: [], members: [] })) }),
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/HouseholdMergeController.mergeHouseholds',
  () => ({ default: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/HouseholdMergeController.splitHousehold',
  () => ({ default: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

const HOUSEHOLD_ID = '001000000000001AAA';
const OTHER_HOUSEHOLD_ID = '001000000000002AAA';
const TARGET_HOUSEHOLD_ID = '001000000000003AAA';
const MARIA_ID = '003000000000001AAA';
const WEI_ID = '003000000000002AAA';

const SEARCH_RESULTS = [
  { id: OTHER_HOUSEHOLD_ID, name: 'Garcia Household', memberCount: 1, location: 'Oakland, CA' }
];

const PREVIEW = {
  survivorId: HOUSEHOLD_ID,
  survivorName: 'The Garcia Family',
  victimId: OTHER_HOUSEHOLD_ID,
  victimName: 'Garcia Household',
  canEdit: true,
  fields: [
    {
      fieldName: 'Name',
      label: 'Account Name',
      survivorValue: 'The Garcia Family',
      victimValue: 'Garcia Household',
      inConflict: true
    },
    {
      fieldName: 'BillingCity',
      label: 'Billing City',
      survivorValue: 'Oakland',
      victimValue: 'Oakland',
      inConflict: false
    }
  ],
  members: [
    { personId: MARIA_ID, name: 'Maria Garcia', role: 'Head', fromSurvivor: true },
    { personId: WEI_ID, name: 'Wei Lee', role: 'Spouse or Partner', fromSurvivor: false }
  ]
};

const MEMBERS = [
  { personId: MARIA_ID, name: 'Maria Garcia', role: 'Head', isPrimary: true, isDeceased: false },
  {
    personId: WEI_ID,
    name: 'Wei Lee',
    role: 'Spouse or Partner',
    isPrimary: false,
    isDeceased: false
  }
];

function recordOfType(developerName) {
  return {
    fields: {
      RecordType: { value: { fields: { DeveloperName: { value: developerName } } } }
    }
  };
}

function flush() {
  return Promise.resolve();
}

function build() {
  const element = createElement('c-household-merge-split', { is: HouseholdMergeSplit });
  element.recordId = HOUSEHOLD_ID;
  document.body.appendChild(element);
  return element;
}

async function openOn(recordType, editable) {
  const element = build();
  getRecord.emit(recordOfType(recordType));
  canEdit.emit(editable);
  getMembers.emit(MEMBERS);
  await flush();
  return element;
}

describe('c-household-merge-split', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('says so politely on a record that is not a household', async () => {
    const element = await openOn('Organization', true);

    expect(element.shadowRoot.querySelector('.not-a-household')).not.toBeNull();
    expect(element.shadowRoot.querySelector('lightning-tabset')).toBeNull();
  });

  it('shows a read only notice and no actions when the person cannot edit', async () => {
    const element = await openOn('Household', false);

    expect(element.shadowRoot.querySelector('.read-only-notice')).not.toBeNull();
    expect(element.shadowRoot.querySelector('lightning-tabset')).toBeNull();
  });

  it('compares the two households after one is picked from the search', async () => {
    searchHouseholds.mockResolvedValue(SEARCH_RESULTS);
    getPreview.mockResolvedValue(PREVIEW);
    const element = await openOn('Household', true);

    element.shadowRoot.querySelector('.search-button').dispatchEvent(new CustomEvent('click'));
    await flush();
    await flush();

    const results = element.shadowRoot.querySelectorAll('.search-result');
    expect(results.length).toBe(1);

    element.shadowRoot.querySelector('.pick-button').dispatchEvent(new CustomEvent('click'));
    await flush();
    await flush();

    expect(getPreview).toHaveBeenCalledWith({
      survivorId: HOUSEHOLD_ID,
      victimId: OTHER_HOUSEHOLD_ID
    });
    const rows = element.shadowRoot.querySelectorAll('.comparison-row');
    expect(rows.length).toBe(2);
    const choices = element.shadowRoot.querySelectorAll('.field-choice');
    expect(choices.length).toBe(1);
    expect(element.shadowRoot.querySelectorAll('.merge-member').length).toBe(2);
  });

  it('asks for confirmation and then merges with the values chosen', async () => {
    searchHouseholds.mockResolvedValue(SEARCH_RESULTS);
    getPreview.mockResolvedValue(PREVIEW);
    mergeHouseholds.mockResolvedValue(HOUSEHOLD_ID);
    const element = await openOn('Household', true);

    element.shadowRoot.querySelector('.search-button').dispatchEvent(new CustomEvent('click'));
    await flush();
    await flush();
    element.shadowRoot.querySelector('.pick-button').dispatchEvent(new CustomEvent('click'));
    await flush();
    await flush();

    element.shadowRoot
      .querySelector('.field-choice')
      .dispatchEvent(new CustomEvent('change', { detail: { value: 'Victim' } }));
    await flush();

    expect(element.shadowRoot.querySelector('.merge-confirm')).toBeNull();
    element.shadowRoot.querySelector('.merge-button').dispatchEvent(new CustomEvent('click'));
    await flush();

    const confirm = element.shadowRoot.querySelector('.merge-confirm');
    expect(confirm).not.toBeNull();
    expect(confirm.querySelector('.confirm-victim').textContent).toBe('Garcia Household');
    expect(confirm.querySelector('.confirm-survivor').textContent).toBe('The Garcia Family');

    element.shadowRoot
      .querySelector('.merge-confirm-button')
      .dispatchEvent(new CustomEvent('click'));
    await flush();

    expect(mergeHouseholds).toHaveBeenCalledWith({
      survivorId: HOUSEHOLD_ID,
      victimId: OTHER_HOUSEHOLD_ID,
      fieldChoices: { Name: 'Victim' }
    });
  });

  it('shows the message when a merge is refused', async () => {
    searchHouseholds.mockResolvedValue(SEARCH_RESULTS);
    getPreview.mockResolvedValue(PREVIEW);
    mergeHouseholds.mockRejectedValue({
      body: { message: 'Both records must be households.' }
    });
    const element = await openOn('Household', true);

    element.shadowRoot.querySelector('.search-button').dispatchEvent(new CustomEvent('click'));
    await flush();
    await flush();
    element.shadowRoot.querySelector('.pick-button').dispatchEvent(new CustomEvent('click'));
    await flush();
    await flush();
    element.shadowRoot.querySelector('.merge-button').dispatchEvent(new CustomEvent('click'));
    await flush();
    element.shadowRoot
      .querySelector('.merge-confirm-button')
      .dispatchEvent(new CustomEvent('click'));
    await flush();
    await flush();
    await flush();
    await flush();

    expect(element.shadowRoot.querySelector('[role="alert"]').textContent).toContain(
      'Both records must be households.'
    );
  });

  it('splits the people ticked into a new household', async () => {
    splitHousehold.mockResolvedValue(TARGET_HOUSEHOLD_ID);
    const element = await openOn('Household', true);

    const checkboxes = element.shadowRoot.querySelectorAll('.member-checkbox');
    expect(checkboxes.length).toBe(2);
    checkboxes[1].checked = true;
    checkboxes[1].dispatchEvent(new CustomEvent('change'));
    await flush();

    element.shadowRoot.querySelector('.split-button').dispatchEvent(new CustomEvent('click'));
    await flush();
    expect(element.shadowRoot.querySelector('.split-confirm')).not.toBeNull();

    element.shadowRoot
      .querySelector('.split-confirm-button')
      .dispatchEvent(new CustomEvent('click'));
    await flush();

    expect(splitHousehold).toHaveBeenCalledWith({
      householdId: HOUSEHOLD_ID,
      personIds: [WEI_ID],
      targetHouseholdId: null
    });
  });

  it('splits into a household that already exists when one is chosen', async () => {
    splitHousehold.mockResolvedValue(TARGET_HOUSEHOLD_ID);
    searchHouseholds.mockResolvedValue([
      { id: TARGET_HOUSEHOLD_ID, name: 'Lee Household', memberCount: 2, location: 'Oakland, CA' }
    ]);
    const element = await openOn('Household', true);

    const checkboxes = element.shadowRoot.querySelectorAll('.member-checkbox');
    checkboxes[1].checked = true;
    checkboxes[1].dispatchEvent(new CustomEvent('change'));
    await flush();

    element.shadowRoot
      .querySelector('.destination-choice')
      .dispatchEvent(new CustomEvent('change', { detail: { value: 'Existing' } }));
    await flush();

    element.shadowRoot
      .querySelector('.split-search-button')
      .dispatchEvent(new CustomEvent('click'));
    await flush();
    await flush();
    element.shadowRoot.querySelector('.split-pick-button').dispatchEvent(new CustomEvent('click'));
    await flush();

    element.shadowRoot.querySelector('.split-button').dispatchEvent(new CustomEvent('click'));
    await flush();
    element.shadowRoot
      .querySelector('.split-confirm-button')
      .dispatchEvent(new CustomEvent('click'));
    await flush();

    expect(splitHousehold).toHaveBeenCalledWith({
      householdId: HOUSEHOLD_ID,
      personIds: [WEI_ID],
      targetHouseholdId: TARGET_HOUSEHOLD_ID
    });
  });

  it('will not split until somebody is ticked', async () => {
    const element = await openOn('Household', true);

    expect(element.shadowRoot.querySelector('.split-button').disabled).toBe(true);

    const checkboxes = element.shadowRoot.querySelectorAll('.member-checkbox');
    checkboxes[0].checked = true;
    checkboxes[0].dispatchEvent(new CustomEvent('change'));
    await flush();

    expect(element.shadowRoot.querySelector('.split-button').disabled).toBe(false);
  });

  it('will not split into an existing household until one is picked', async () => {
    searchHouseholds.mockResolvedValue([
      { id: TARGET_HOUSEHOLD_ID, name: 'Lee Household', memberCount: 2, location: 'Oakland, CA' }
    ]);
    const element = await openOn('Household', true);

    const checkboxes = element.shadowRoot.querySelectorAll('.member-checkbox');
    checkboxes[1].checked = true;
    checkboxes[1].dispatchEvent(new CustomEvent('change'));
    await flush();
    element.shadowRoot
      .querySelector('.destination-choice')
      .dispatchEvent(new CustomEvent('change', { detail: { value: 'Existing' } }));
    await flush();

    expect(element.shadowRoot.querySelector('.split-button').disabled).toBe(true);

    element.shadowRoot
      .querySelector('.split-search-button')
      .dispatchEvent(new CustomEvent('click'));
    await flush();
    await flush();
    element.shadowRoot.querySelector('.split-pick-button').dispatchEvent(new CustomEvent('click'));
    await flush();

    expect(element.shadowRoot.querySelector('.split-target-name').textContent).toBe(
      'Lee Household'
    );
    expect(element.shadowRoot.querySelector('.split-button').disabled).toBe(false);
  });
});
