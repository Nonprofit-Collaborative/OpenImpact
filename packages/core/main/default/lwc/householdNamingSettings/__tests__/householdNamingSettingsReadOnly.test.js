import { createElement } from 'lwc';
import HouseholdNamingSettings from 'c/householdNamingSettings';
import preview from '@salesforce/apex/HouseholdController.preview';

jest.mock(
  '@salesforce/apex/HouseholdController.preview',
  () => ({ default: jest.fn(() => Promise.resolve([])) }),
  { virtual: true }
);

jest.mock(
  '@salesforce/apex/HouseholdController.recomputeAll',
  () => ({ default: jest.fn(() => Promise.resolve('')) }),
  { virtual: true }
);

jest.mock('@salesforce/customPermission/Manage_Nonprofit_Settings', () => ({ default: false }), {
  virtual: true
});

jest.mock(
  '@salesforce/apex/SettingsController.saveSettings',
  () => ({ default: jest.fn(() => Promise.resolve()) }),
  { virtual: true }
);

function flush() {
  return Promise.resolve();
}

describe('c-household-naming-settings without the settings permission', () => {
  beforeEach(() => {
    preview.mockResolvedValue([]);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('shows the patterns but does not let them be changed', async () => {
    const element = createElement('c-household-naming-settings', {
      is: HouseholdNamingSettings
    });
    document.body.appendChild(element);
    await flush();

    const inputs = element.shadowRoot.querySelectorAll('lightning-input');
    expect(inputs.length).toBe(3);
    inputs.forEach((input) => expect(input.disabled).toBe(true));
    expect(element.shadowRoot.querySelector('.save-button').disabled).toBe(true);
    expect(element.shadowRoot.textContent).toContain('c.Core_HouseholdNamingSettings_ReadOnly');
  });
});
