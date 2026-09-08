import { createElement } from 'lwc';
import ReceiptSettings from 'c/receiptSettings';
import getTemplates from '@salesforce/apex/ReceiptController.getTemplates';
import getRuns from '@salesforce/apex/ReceiptController.getRuns';
import getDefaultStatementYear from '@salesforce/apex/ReceiptController.getDefaultStatementYear';
import startStatementRun from '@salesforce/apex/ReceiptController.startStatementRun';

jest.mock(
  '@salesforce/apex/ReceiptController.getTemplates',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ReceiptController.getRuns',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ReceiptController.getDefaultStatementYear',
  () => {
    const { createApexTestWireAdapter } = require('@salesforce/sfdx-lwc-jest');
    return { default: createApexTestWireAdapter(jest.fn()) };
  },
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ReceiptController.saveTemplate',
  () => ({ default: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ReceiptController.activateTemplate',
  () => ({ default: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);
jest.mock(
  '@salesforce/apex/ReceiptController.startStatementRun',
  () => ({ default: jest.fn(() => Promise.resolve({ id: 'a03000000000001' })) }),
  { virtual: true }
);
jest.mock('@salesforce/apex', () => ({ refreshApex: jest.fn(() => Promise.resolve()) }), {
  virtual: true
});

const TEMPLATES = [
  {
    id: 'a04000000000001',
    name: 'Per gift receipt',
    type: 'Per gift',
    body: '<p>{{OrganizationName}}</p>',
    active: true
  },
  {
    id: 'a04000000000002',
    name: 'Consolidated statement',
    type: 'Consolidated statement',
    body: '<p>{{GiftLines}}</p>',
    active: true
  }
];

function build() {
  const element = createElement('c-receipt-settings', { is: ReceiptSettings });
  document.body.appendChild(element);
  return element;
}

function flush() {
  return Promise.resolve();
}

describe('c-receipt-settings', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('loads the first letter into the editor', async () => {
    const element = build();
    getTemplates.emit(TEMPLATES);
    getRuns.emit([]);
    await flush();

    const editor = element.shadowRoot.querySelector('lightning-textarea');
    expect(editor.value).toBe('<p>{{OrganizationName}}</p>');
  });

  it('says the tax wording is not editable here', async () => {
    const element = build();
    getTemplates.emit(TEMPLATES);
    getRuns.emit([]);
    await flush();

    const text = element.shadowRoot.textContent;
    expect(text).toContain('cannot be edited');
  });

  it('starts a run for the year the settings name', async () => {
    const element = build();
    getTemplates.emit(TEMPLATES);
    getRuns.emit([]);
    getDefaultStatementYear.emit(2026);
    await flush();

    const buttons = Array.from(element.shadowRoot.querySelectorAll('lightning-button'));
    const generate = buttons.find((button) => button.label === 'Generate');
    generate.click();
    await flush();

    expect(startStatementRun).toHaveBeenCalledWith({ statementYear: 2026 });
  });
});
