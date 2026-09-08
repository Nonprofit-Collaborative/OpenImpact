import { createElement } from 'lwc';
import HubHome from 'c/hubHome';
import getHomeModel from '@salesforce/apex/HubController.getHomeModel';

jest.mock('@salesforce/apex/HubController.getHomeModel', () => ({ default: jest.fn() }), {
  virtual: true
});

function model(overrides) {
  return {
    canEdit: true,
    automationPaused: false,
    newErrorCount: 0,
    stepsCompleted: 1,
    stepsTotal: 2,
    steps: [
      {
        key: 'coexistence',
        position: 1,
        label: 'Confirm how Open Impact fits your existing org',
        description: 'Person Accounts orgs use the junction model.',
        targetType: 'Settings',
        target: 'General',
        setupPath: null,
        completed: true
      },
      {
        key: 'modules',
        position: 6,
        label: 'Choose which modules to turn on',
        description: 'Turn on only what you use.',
        targetType: 'Settings',
        target: 'Modules',
        setupPath: null,
        completed: false
      }
    ],
    ...overrides
  };
}

function build() {
  const element = createElement('c-hub-home', { is: HubHome });
  document.body.appendChild(element);
  return element;
}

function settle() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

describe('c-hub-home', () => {
  beforeEach(() => {
    getHomeModel.mockResolvedValue(model());
  });

  afterEach(() => {
    jest.clearAllMocks();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('welcomes Maria and gives the setup assistant the whole page', async () => {
    const element = build();
    await settle();

    expect(element.shadowRoot.querySelector('h1').textContent).toContain(
      'Core_HubHome_WelcomeHeading'
    );
    expect(element.shadowRoot.querySelector('c-setup-assistant')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="reopen-setup"]')).toBeNull();
  });

  it('counts errors to review and links to the Error Log', async () => {
    getHomeModel.mockResolvedValue(model({ newErrorCount: 3 }));
    const element = build();
    await settle();

    expect(element.shadowRoot.querySelector('[data-id="error-count"]').textContent).toBe('3');
    const link = element.shadowRoot.querySelector('a[href="/lightning/o/Error_Log__c/list"]');
    expect(link).not.toBeNull();
  });

  it('says so while automation is paused', async () => {
    getHomeModel.mockResolvedValue(model({ automationPaused: true }));
    const element = build();
    await settle();

    const banner = element.shadowRoot.querySelector('div[role="status"]');
    expect(banner.textContent).toContain('Core_HubHome_AutomationPausedBanner');
  });

  it('collapses to a tile once every step is done, and reopens on request', async () => {
    getHomeModel.mockResolvedValue(model({ stepsCompleted: 2, stepsTotal: 2 }));
    const element = build();
    await settle();

    expect(element.shadowRoot.querySelector('c-setup-assistant')).toBeNull();
    // The wording is a Custom Label with numbered slots, which jest renders as its API name.
    expect(element.shadowRoot.querySelector('[data-id="setup-progress"]').textContent).toContain(
      'Core_SetupAssistant_ProgressFormat'
    );

    element.shadowRoot.querySelector('[data-id="reopen-setup"]').click();
    await settle();

    expect(element.shadowRoot.querySelector('c-setup-assistant')).not.toBeNull();
  });

  it('follows the assistant progress without reloading the page', async () => {
    getHomeModel.mockResolvedValue(model({ stepsCompleted: 1, stepsTotal: 2 }));
    const element = build();
    await settle();

    element.shadowRoot.querySelector('c-setup-assistant').dispatchEvent(
      new CustomEvent('setupchanged', {
        detail: { stepsCompleted: 2, stepsTotal: 2, isComplete: true }
      })
    );
    await settle();

    expect(element.shadowRoot.querySelector('c-setup-assistant')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="reopen-setup"]')).not.toBeNull();
  });
});
