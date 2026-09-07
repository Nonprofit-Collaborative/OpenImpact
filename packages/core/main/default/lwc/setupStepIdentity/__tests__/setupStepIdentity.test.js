import { createElement } from 'lwc';
import SetupStepIdentity from 'c/setupStepIdentity';

jest.mock('@salesforce/user/Id', () => ({ default: '005000000000001AAA' }), { virtual: true });

function build(values, canEdit = true) {
  const element = createElement('c-setup-step-identity', { is: SetupStepIdentity });
  element.values = values;
  element.canEdit = canEdit;
  document.body.appendChild(element);
  return element;
}

describe('c-setup-step-identity', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('shows what the org has already recorded', () => {
    const element = build({
      Organization_Legal_Name__c: 'Riverside Community Aid',
      Receipt_Signer_Name__c: 'Ana Ruiz'
    });

    const inputs = element.shadowRoot.querySelectorAll('lightning-input');
    expect(inputs).toHaveLength(5);
    expect(inputs[0].value).toBe('Riverside Community Aid');
  });

  it('saves what Maria typed, keyed by setting', () => {
    const element = build({});
    const saved = jest.fn();
    element.addEventListener('save', saved);

    const input = element.shadowRoot.querySelector(
      'lightning-input[data-key="Organization_EIN__c"]'
    );
    input.value = '12-3456789';
    input.dispatchEvent(new CustomEvent('change'));
    element.shadowRoot.querySelector('lightning-button').click();

    expect(saved).toHaveBeenCalled();
    expect(saved.mock.calls[0][0].detail.values.Organization_EIN__c).toBe('12-3456789');
  });

  it('keeps an uploaded logo as a file identifier and saves it at once', () => {
    const element = build({});
    const saved = jest.fn();
    element.addEventListener('save', saved);

    const uploads = element.shadowRoot.querySelectorAll('lightning-file-upload');
    expect(uploads[0].recordId).toBe('005000000000001AAA');
    uploads[0].dispatchEvent(
      new CustomEvent('uploadfinished', { detail: { files: [{ documentId: '069000000000001' }] } })
    );

    expect(saved).toHaveBeenCalled();
    expect(saved.mock.calls[0][0].detail.values.Receipt_Logo_Document_Id__c).toBe(
      '069000000000001'
    );
  });

  it('lets David read the receipt details without changing them', () => {
    const element = build({ Organization_Legal_Name__c: 'Riverside Community Aid' }, false);

    expect(element.shadowRoot.querySelectorAll('lightning-file-upload')).toHaveLength(0);
    expect(element.shadowRoot.querySelector('lightning-button')).toBeNull();
    expect(element.shadowRoot.querySelector('lightning-input').disabled).toBe(true);
  });
});
