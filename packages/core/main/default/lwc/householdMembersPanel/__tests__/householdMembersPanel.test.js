// The test wire adapters below are emitted to on purpose, which is how a wired
// component is driven from a test.
/* eslint-disable @lwc/lwc/no-unexpected-wire-adapter-usages */
import { createElement } from 'lwc';
import { getRecord } from 'lightning/uiRecordApi';
import { getObjectInfo } from 'lightning/uiObjectInfoApi';
import HouseholdMembersPanel from 'c/householdMembersPanel';
import getMembers from '@salesforce/apex/HouseholdController.getMembers';
import getMembershipMode from '@salesforce/apex/HouseholdController.getMembershipMode';
import moveContact from '@salesforce/apex/HouseholdController.moveContact';

jest.mock(
  '@salesforce/apex/HouseholdController.getMembers',
  () => {
    const { createApexTestWireAdapter } = jest.requireActual('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/HouseholdController.getMembershipMode',
  () => {
    const { createApexTestWireAdapter } = jest.requireActual('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/HouseholdController.moveContact',
  () => ({ default: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

const HOUSEHOLD_ID = '001000000000001AAA';
const OTHER_HOUSEHOLD_ID = '001000000000002AAA';
const PERSON_ID = '003000000000001AAA';
const PERSON_ACCOUNT_ID = '001000000000009AAA';
const HOUSEHOLD_RECORD_TYPE_ID = '012000000000001AAA';

const ACCOUNT_INFO = {
  recordTypeInfos: {
    [HOUSEHOLD_RECORD_TYPE_ID]: {
      recordTypeId: HOUSEHOLD_RECORD_TYPE_ID,
      developerName: 'Household',
      name: 'Household'
    },
    '012000000000002AAA': {
      recordTypeId: '012000000000002AAA',
      developerName: 'Organization',
      name: 'Organization'
    }
  }
};

const MEMBERS = [
  {
    personId: PERSON_ID,
    name: 'John Smith',
    role: 'Head',
    source: 'Contact',
    isPrimary: true,
    isDeceased: false
  },
  {
    personId: '003000000000002AAA',
    name: 'Jane Smith',
    role: 'Spouse or Partner',
    source: 'Contact',
    isPrimary: false,
    isDeceased: true
  }
];

function recordOfType(developerName) {
  return {
    fields: {
      RecordType: { value: { fields: { DeveloperName: { value: developerName } } } }
    }
  };
}

// Lets every promise the component started settle, including the settings load that the
// first preview waits for.
function flush() {
  return Promise.resolve()
    .then(() => {})
    .then(() => {})
    .then(() => {})
    .then(() => {})
    .then(() => {});
}

function build() {
  const element = createElement('c-household-members-panel', { is: HouseholdMembersPanel });
  element.recordId = HOUSEHOLD_ID;
  document.body.appendChild(element);
  return element;
}

describe('c-household-members-panel', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('lists the members with their role and their badges', async () => {
    const element = build();
    getRecord.emit(recordOfType('Household'));
    getMembershipMode.emit('Contact');
    getMembers.emit(MEMBERS);
    await flush();

    const rows = element.shadowRoot.querySelectorAll('.member-row');
    expect(rows.length).toBe(2);
    expect(rows[0].textContent).toContain('John Smith');
    expect(rows[0].textContent).toContain('Head');

    const badges = element.shadowRoot.querySelectorAll('lightning-badge');
    const labels = Array.from(badges).map((badge) => badge.label);
    expect(labels).toContain('c.Core_HouseholdMembersPanel_Primary');
    expect(labels).toContain('c.Core_HouseholdMembersPanel_Deceased');
  });

  it('says so politely on a record that is not a household', async () => {
    const element = build();
    getRecord.emit(recordOfType('Organization'));
    getMembershipMode.emit('Contact');
    getMembers.emit([]);
    await flush();

    expect(element.shadowRoot.querySelector('.not-a-household')).not.toBeNull();
    expect(element.shadowRoot.querySelector('.member-list')).toBeNull();
  });

  it('offers to add a member only where a person belongs to one household', async () => {
    const element = build();
    getRecord.emit(recordOfType('Household'));
    getMembershipMode.emit('Contact');
    getMembers.emit(MEMBERS);
    await flush();

    expect(element.shadowRoot.querySelector('.add-button')).not.toBeNull();
    expect(element.shadowRoot.querySelector('.junction-message')).toBeNull();
  });

  it('points to the related list instead of adding in the flexible membership mode', async () => {
    const element = build();
    getRecord.emit(recordOfType('Household'));
    getMembershipMode.emit('Junction');
    getMembers.emit(MEMBERS);
    await flush();

    expect(element.shadowRoot.querySelector('.add-button')).toBeNull();
    expect(element.shadowRoot.querySelector('.junction-message')).not.toBeNull();
  });

  it('moves a person to the household that was chosen', async () => {
    moveContact.mockResolvedValue();
    const element = build();
    getRecord.emit(recordOfType('Household'));
    getObjectInfo.emit(ACCOUNT_INFO);
    getMembershipMode.emit('Contact');
    getMembers.emit(MEMBERS);
    await flush();

    element.shadowRoot.querySelectorAll('.move-button')[0].dispatchEvent(new CustomEvent('click'));
    await flush();

    const picker = element.shadowRoot.querySelector('.move-target');
    picker.dispatchEvent(new CustomEvent('change', { detail: { recordId: OTHER_HOUSEHOLD_ID } }));
    element.shadowRoot.querySelector('.move-save-button').dispatchEvent(new CustomEvent('click'));
    await flush();

    expect(moveContact).toHaveBeenCalledWith({
      contactId: PERSON_ID,
      targetHouseholdId: OTHER_HOUSEHOLD_ID
    });
  });

  it('offers households to move to and not organizations', async () => {
    const element = build();
    getRecord.emit(recordOfType('Household'));
    getObjectInfo.emit(ACCOUNT_INFO);
    getMembershipMode.emit('Contact');
    getMembers.emit(MEMBERS);
    await flush();

    element.shadowRoot.querySelectorAll('.move-button')[0].dispatchEvent(new CustomEvent('click'));
    await flush();

    const picker = element.shadowRoot.querySelector('.move-target');
    expect(picker.objectApiName).toBe('Account');
    expect(picker.filter).toEqual({
      criteria: [{ fieldPath: 'RecordTypeId', operator: 'eq', value: HOUSEHOLD_RECORD_TYPE_ID }]
    });
  });

  it('moves a person the org stores as an account', async () => {
    moveContact.mockResolvedValue();
    const element = build();
    getRecord.emit(recordOfType('Household'));
    getObjectInfo.emit(ACCOUNT_INFO);
    getMembershipMode.emit('Junction');
    getMembers.emit([
      {
        personId: PERSON_ACCOUNT_ID,
        name: 'Maria Garcia',
        role: 'Head',
        source: 'Account',
        isPrimary: true,
        isDeceased: false
      }
    ]);
    await flush();

    element.shadowRoot.querySelectorAll('.move-button')[0].dispatchEvent(new CustomEvent('click'));
    await flush();

    const picker = element.shadowRoot.querySelector('.move-target');
    picker.dispatchEvent(new CustomEvent('change', { detail: { recordId: OTHER_HOUSEHOLD_ID } }));
    element.shadowRoot.querySelector('.move-save-button').dispatchEvent(new CustomEvent('click'));
    await flush();

    expect(moveContact).toHaveBeenCalledWith({
      contactId: PERSON_ACCOUNT_ID,
      targetHouseholdId: OTHER_HOUSEHOLD_ID
    });
  });

  it('shows what went wrong when a move is refused', async () => {
    moveContact.mockRejectedValue({ body: { message: 'That account is not a household.' } });
    const element = build();
    getRecord.emit(recordOfType('Household'));
    getObjectInfo.emit(ACCOUNT_INFO);
    getMembershipMode.emit('Contact');
    getMembers.emit(MEMBERS);
    await flush();

    element.shadowRoot.querySelectorAll('.move-button')[0].dispatchEvent(new CustomEvent('click'));
    await flush();
    element.shadowRoot.querySelector('.move-save-button').dispatchEvent(new CustomEvent('click'));
    await flush();

    const alert = element.shadowRoot.querySelector('[role="alert"]');
    expect(alert).not.toBeNull();
    expect(alert.textContent).toContain('That account is not a household.');
  });
});
