import { createElement } from 'lwc';
import SetupStepFields from 'c/setupStepFields';

jest.mock('@salesforce/user/Id', () => ({ default: '005000000000001AAA' }), { virtual: true });

const mockNavigate = jest.fn();
jest.mock(
  'lightning/navigation',
  () => {
    const Navigate = Symbol('Navigate');
    const NavigationMixin = (Base) =>
      class extends Base {
        [Navigate](...args) {
          mockNavigate(...args);
        }
      };
    NavigationMixin.Navigate = Navigate;
    return { NavigationMixin, __esModule: true };
  },
  { virtual: true }
);

// The organization step as it arrives with Giving installed: Core's two fields and the
// receipt fields Giving adds (ADR-NEXT, C-29).
const IDENTITY_FIELDS = [
  { fieldType: 'Text', key: 'Organization_Legal_Name__c', label: 'Legal name', maxLength: 255 },
  {
    fieldType: 'Text',
    key: 'Organization_EIN__c',
    label: 'Tax identification number',
    maxLength: 20,
    pattern: '[0-9]{2}-[0-9]{7}',
    patternMessage: 'Enter it as 12-3456789.'
  },
  {
    fieldType: 'Text',
    key: 'Organization_Address__c',
    label: 'Address',
    maxLength: 255,
    fullWidth: true
  },
  {
    fieldType: 'File',
    key: 'Receipt_Logo_Document_Id__c',
    label: 'Logo',
    previewAlt: 'Your logo'
  }
];

function build(fields, canEdit = true) {
  const element = createElement('c-setup-step-fields', { is: SetupStepFields });
  element.fields = fields;
  element.canEdit = canEdit;
  document.body.appendChild(element);
  return element;
}

function withValues(values) {
  return IDENTITY_FIELDS.map((field) => ({ ...field, value: values[field.key] }));
}

describe('c-setup-step-fields', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('shows what the org has already recorded', () => {
    const element = build(withValues({ Organization_Legal_Name__c: 'Riverside Community Aid' }));

    const inputs = element.shadowRoot.querySelectorAll('lightning-input');
    expect(inputs).toHaveLength(3);
    expect(inputs[0].value).toBe('Riverside Community Aid');
    expect(inputs[0].label).toBe('Legal name');
  });

  it('saves every field the step declares, keyed by setting', () => {
    const element = build(withValues({}));
    const saved = jest.fn();
    element.addEventListener('save', saved);

    const input = element.shadowRoot.querySelector(
      'lightning-input[data-key="Organization_EIN__c"]'
    );
    input.value = '12-3456789';
    input.dispatchEvent(new CustomEvent('change'));
    element.shadowRoot.querySelector('[data-id="save-fields"]').click();

    expect(saved.mock.calls[0][0].detail.values).toEqual({
      Organization_Legal_Name__c: null,
      Organization_EIN__c: '12-3456789',
      Organization_Address__c: null,
      Receipt_Logo_Document_Id__c: null
    });
  });

  it('applies the limits and wording the field declares', () => {
    const element = build(withValues({}));

    const ein = element.shadowRoot.querySelector('lightning-input[data-key="Organization_EIN__c"]');
    expect(ein.pattern).toBe('[0-9]{2}-[0-9]{7}');
    expect(ein.maxLength).toBe(20);
    expect(ein.messageWhenPatternMismatch).toBe('Enter it as 12-3456789.');
  });

  it('shows an uploaded file rather than its record identifier', () => {
    const element = build(withValues({ Receipt_Logo_Document_Id__c: '069000000000001' }));

    const preview = element.shadowRoot.querySelector('[data-id="file-preview"]');
    expect(preview.src).toContain('/sfc/servlet.shepherd/document/download/069000000000001');
    expect(preview.alt).toBe('Your logo');
    expect(element.shadowRoot.textContent).not.toContain('069000000000001');
  });

  it('keeps an uploaded file as its identifier and saves it at once', () => {
    const element = build(withValues({}));
    const saved = jest.fn();
    element.addEventListener('save', saved);

    const upload = element.shadowRoot.querySelector('lightning-file-upload');
    expect(upload.recordId).toBe('005000000000001AAA');
    upload.dispatchEvent(
      new CustomEvent('uploadfinished', { detail: { files: [{ documentId: '069000000000001' }] } })
    );

    expect(saved.mock.calls[0][0].detail.values.Receipt_Logo_Document_Id__c).toBe(
      '069000000000001'
    );
  });

  it('saves a chosen record by its identifier', () => {
    const element = build([
      { fieldType: 'Record', key: 'Default_Fund__c', label: 'Fund', objectApiName: 'Fund__c' }
    ]);
    const saved = jest.fn();
    element.addEventListener('save', saved);

    const picker = element.shadowRoot.querySelector('lightning-record-picker');
    expect(picker.objectApiName).toBe('Fund__c');
    picker.dispatchEvent(new CustomEvent('change', { detail: { recordId: 'a01000000000001' } }));
    element.shadowRoot.querySelector('[data-id="save-fields"]').click();

    expect(saved.mock.calls[0][0].detail.values).toEqual({ Default_Fund__c: 'a01000000000001' });
  });

  it('opens the tab a navigation field names, with no save button', () => {
    const element = build([
      { fieldType: 'Navigate', label: 'Enter your first gift', navigationTarget: 'Gift_Entry' }
    ]);

    expect(element.shadowRoot.querySelector('[data-id="save-fields"]')).toBeNull();
    element.shadowRoot.querySelector('[data-id="navigate"]').click();

    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: 'Gift_Entry' }
    });
  });

  it('lets David read the answers without changing them', () => {
    const element = build(
      withValues({ Organization_Legal_Name__c: 'Riverside Community Aid' }),
      false
    );

    expect(element.shadowRoot.querySelectorAll('lightning-file-upload')).toHaveLength(0);
    expect(element.shadowRoot.querySelector('[data-id="save-fields"]')).toBeNull();
    expect(element.shadowRoot.querySelector('lightning-input').disabled).toBe(true);
  });
});
