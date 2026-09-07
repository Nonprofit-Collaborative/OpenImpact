import { createElement } from 'lwc';
import SettingsConsole from 'c/settingsConsole';
import getConsoleModel from '@salesforce/apex/SettingsController.getConsoleModel';
import saveSettings from '@salesforce/apex/SettingsController.saveSettings';
import getRecentChanges from '@salesforce/apex/SettingsController.getRecentChanges';

jest.mock('@salesforce/apex/SettingsController.getConsoleModel', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/SettingsController.saveSettings', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/SettingsController.getRecentChanges', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/SettingsController.search', () => ({ default: jest.fn() }), {
  virtual: true
});

function model(canEdit) {
  return {
    canEdit,
    sections: [
      {
        name: 'Households',
        settings: [
          {
            key: 'Household_Name_Pattern__c',
            label: 'Household name pattern',
            description: 'How a household name is built.',
            dataType: 'Text',
            section: 'Households',
            component: null,
            helpUrl: 'https://example.invalid/docs/household-naming.md',
            value: 'The {LastName} Family',
            checked: false,
            options: []
          },
          {
            key: 'Auto_Create_Households__c',
            label: 'Create households automatically',
            description: 'Whether adding a person creates a household.',
            dataType: 'Checkbox',
            section: 'Households',
            component: null,
            helpUrl: null,
            value: 'true',
            checked: true,
            options: []
          }
        ]
      },
      {
        name: 'General',
        settings: [
          {
            key: 'Coexistence_Mode__c',
            label: 'How Open Impact fits your org',
            description: 'Set after Open Impact looks at your org.',
            dataType: 'Picklist',
            section: 'General',
            component: null,
            helpUrl: null,
            value: 'Standalone',
            checked: false,
            options: [
              { label: 'On its own', value: 'Standalone' },
              { label: 'Alongside Nonprofit Cloud', value: 'AgentforceNonprofit' }
            ]
          }
        ]
      }
    ]
  };
}

function build() {
  const element = createElement('c-settings-console', { is: SettingsConsole });
  document.body.appendChild(element);
  return element;
}

function settle() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-settings-console', () => {
  beforeEach(() => {
    getConsoleModel.mockResolvedValue(model(true));
    saveSettings.mockResolvedValue(model(true));
    getRecentChanges.mockResolvedValue([]);
  });

  afterEach(() => {
    jest.clearAllMocks();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('shows the first section with its controls and help', async () => {
    const element = build();
    await settle();

    const navItems = element.shadowRoot.querySelectorAll('lightning-vertical-navigation-item');
    expect(navItems).toHaveLength(2);

    const inputs = element.shadowRoot.querySelectorAll('lightning-input');
    expect(inputs).toHaveLength(2);
    expect(inputs[0].value).toBe('The {LastName} Family');
    expect(inputs[1].checked).toBe(true);

    const help = element.shadowRoot.querySelector('a[target="_blank"]');
    expect(help).not.toBeNull();
    expect(help.href).toContain('household-naming.md');
  });

  it('sends only the settings Maria changed', async () => {
    const element = build();
    await settle();

    const input = element.shadowRoot.querySelector('lightning-input');
    input.value = 'The {LastName} Household';
    input.dispatchEvent(new CustomEvent('change'));
    await settle();

    const buttons = element.shadowRoot.querySelectorAll('lightning-button');
    buttons[0].click();
    await settle();

    expect(saveSettings).toHaveBeenCalledWith({
      values: { Household_Name_Pattern__c: 'The {LastName} Household' }
    });
    expect(element.shadowRoot.querySelector('p[role="status"]')).not.toBeNull();
  });

  it('throws away unsaved edits when Maria discards them', async () => {
    const element = build();
    await settle();

    const input = element.shadowRoot.querySelector('lightning-input');
    input.value = 'Something else';
    input.dispatchEvent(new CustomEvent('change'));
    await settle();

    const buttons = element.shadowRoot.querySelectorAll('lightning-button');
    buttons[1].click();
    await settle();

    expect(saveSettings).not.toHaveBeenCalled();
    expect(element.shadowRoot.querySelector('lightning-input').value).toBe('The {LastName} Family');
  });

  it('tells David which permission he needs and offers him no Save button', async () => {
    getConsoleModel.mockResolvedValue(model(false));
    const element = build();
    await settle();

    const notice = element.shadowRoot.querySelector('div[role="status"]');
    expect(notice.textContent).toContain('Core_Settings_ReadOnlyNotice');
    expect(element.shadowRoot.querySelectorAll('lightning-button')).toHaveLength(0);
    element.shadowRoot.querySelectorAll('lightning-input').forEach((input) => {
      expect(input.disabled).toBe(true);
    });
  });

  it('opens the section a search result points at', async () => {
    const element = build();
    await settle();

    const search = element.shadowRoot.querySelector('c-settings-search');
    search.dispatchEvent(
      new CustomEvent('settingselect', {
        detail: { section: 'General', key: 'Coexistence_Mode__c' }
      })
    );
    await settle();

    const combobox = element.shadowRoot.querySelector('lightning-combobox');
    expect(combobox).not.toBeNull();
    expect(combobox.value).toBe('Standalone');
  });

  it('says the page could not load rather than showing nothing', async () => {
    getConsoleModel.mockRejectedValue(new Error('no'));
    const element = build();
    await settle();

    const message = element.shadowRoot.querySelector('p[role="status"]');
    expect(message.textContent).toContain('Core_Settings_LoadErrorMessage');
  });
});
