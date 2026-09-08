import { createElement } from 'lwc';
import RelationshipPanel from 'c/relationshipPanel';
import getRelationships from '@salesforce/apex/RelationshipController.getRelationships';
import removeRelationship from '@salesforce/apex/RelationshipController.removeRelationship';

jest.mock(
  '@salesforce/apex/RelationshipController.getRelationships',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/RelationshipController.removeRelationship',
  () => ({ default: jest.fn() }),
  { virtual: true }
);

jest.mock('@salesforce/apex', () => ({ refreshApex: jest.fn() }), { virtual: true });

const SPOUSE = {
  id: 'a0200000000000AAAA',
  relationshipNumber: 'RL-000001',
  relatedPersonId: '0031000000000002AA',
  relatedPersonName: 'Luis Garcia',
  relationshipType: 'Spouse',
  reciprocalType: 'Spouse',
  status: 'Current',
  isFormer: false,
  description: null,
  isReciprocalManaged: true,
  hasOtherSide: true
};

const FORMER_COLLEAGUE = {
  id: 'a0200000000000BBBB',
  relationshipNumber: 'RL-000002',
  relatedPersonId: '0031000000000003AA',
  relatedPersonName: 'Jordan Reyes',
  relationshipType: 'Colleague',
  reciprocalType: 'Colleague',
  status: 'Former',
  isFormer: true,
  description: 'Worked together at the food bank',
  isReciprocalManaged: true,
  hasOtherSide: true
};

function build(objectApiName = 'Contact') {
  const element = createElement('c-relationship-panel', { is: RelationshipPanel });
  element.recordId = '0031000000000001AA';
  element.objectApiName = objectApiName;
  document.body.appendChild(element);
  return element;
}

function flush() {
  return Promise.resolve().then(() => Promise.resolve());
}

describe('c-relationship-panel', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows a card for every relationship this person has', async () => {
    const element = build();
    getRelationships.emit([SPOUSE, FORMER_COLLEAGUE]);
    await flush();

    const cards = element.shadowRoot.querySelectorAll('[data-id="relationship-card"]');
    expect(cards.length).toBe(2);
    const names = Array.from(element.shadowRoot.querySelectorAll('[data-id="related-person"]')).map(
      (node) => node.textContent
    );
    expect(names).toEqual(['Luis Garcia', 'Jordan Reyes']);
  });

  it('names the type from this side and badges the ones that have ended', async () => {
    const element = build();
    getRelationships.emit([SPOUSE, FORMER_COLLEAGUE]);
    await flush();

    const types = Array.from(
      element.shadowRoot.querySelectorAll('[data-id="relationship-type"]')
    ).map((node) => node.textContent);
    expect(types).toEqual(['Spouse', 'Colleague']);
    expect(element.shadowRoot.querySelectorAll('[data-id="former-badge"]').length).toBe(1);
  });

  it('says so when the person has no relationships yet', async () => {
    const element = build();
    getRelationships.emit([]);
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="empty"]')).not.toBeNull();
    expect(element.shadowRoot.querySelectorAll('[data-id="relationship-card"]').length).toBe(0);
  });

  it('shows a message when the relationships cannot be read', async () => {
    const element = build();
    getRelationships.error();
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="error"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="empty"]')).toBeNull();
  });

  it('removes a relationship and redraws what is left', async () => {
    removeRelationship.mockResolvedValue([FORMER_COLLEAGUE]);
    const element = build();
    getRelationships.emit([SPOUSE, FORMER_COLLEAGUE]);
    await flush();

    element.shadowRoot.querySelector('.remove-relationship').click();
    await flush();

    expect(removeRelationship).toHaveBeenCalledWith({
      relationshipId: SPOUSE.id,
      personId: '0031000000000001AA'
    });
    expect(element.shadowRoot.querySelectorAll('[data-id="relationship-card"]').length).toBe(1);
  });

  it('shows a message when a relationship cannot be removed', async () => {
    removeRelationship.mockRejectedValue(new Error('no'));
    const element = build();
    getRelationships.emit([SPOUSE]);
    await flush();

    element.shadowRoot.querySelector('.remove-relationship').click();
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="error"]')).not.toBeNull();
  });

  it('fills in the contact lookups on a contact record and the account lookups on an account', async () => {
    const asContact = build('Contact');
    getRelationships.emit([]);
    await flush();
    asContact.shadowRoot.querySelector('[data-id="add-relationship"]').click();
    await flush();

    let fields = Array.from(asContact.shadowRoot.querySelectorAll('lightning-input-field')).map(
      (node) => node.fieldName
    );
    expect(fields[0]).toBe('Contact__c');
    expect(fields[1]).toBe('Related_Contact__c');

    const asAccount = build('Account');
    getRelationships.emit([]);
    await flush();
    asAccount.shadowRoot.querySelector('[data-id="add-relationship"]').click();
    await flush();

    fields = Array.from(asAccount.shadowRoot.querySelectorAll('lightning-input-field')).map(
      (node) => node.fieldName
    );
    expect(fields[0]).toBe('Person_Account__c');
    expect(fields[1]).toBe('Related_Person_Account__c');
  });
});
