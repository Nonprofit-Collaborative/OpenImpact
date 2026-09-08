import { createElement } from 'lwc';
import HubHome from 'c/hubHome';
import getHomeModel from '@salesforce/apex/HubController.getHomeModel';
import markStepDone from '@salesforce/apex/HubController.markStepDone';
import markStepNotDone from '@salesforce/apex/HubController.markStepNotDone';

jest.mock('@salesforce/apex/HubController.getHomeModel', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/HubController.markStepDone', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/HubController.markStepNotDone', () => ({ default: jest.fn() }), {
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
    markStepDone.mockResolvedValue(model({ stepsCompleted: 2 }));
    markStepNotDone.mockResolvedValue(model({ stepsCompleted: 0 }));
  });

  afterEach(() => {
    jest.clearAllMocks();
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('welcomes Maria and hands the checklist to the setup assistant', async () => {
    const element = build();
    await settle();

    expect(element.shadowRoot.querySelector('h1').textContent).toContain(
      'Core_HubHome_WelcomeHeading'
    );
    const assistant = element.shadowRoot.querySelector('c-setup-assistant');
    expect(assistant.steps).toHaveLength(2);
    expect(assistant.total).toBe(2);
    expect(assistant.canEdit).toBe(true);
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

  it('records a step Maria marks done', async () => {
    const element = build();
    await settle();

    const assistant = element.shadowRoot.querySelector('c-setup-assistant');
    assistant.dispatchEvent(new CustomEvent('stepdone', { detail: { key: 'modules' } }));
    await settle();

    expect(markStepDone).toHaveBeenCalledWith({ stepKey: 'modules' });
    expect(element.shadowRoot.querySelector('c-setup-assistant').completed).toBe(2);
  });

  it('puts a step back on the list', async () => {
    const element = build();
    await settle();

    const assistant = element.shadowRoot.querySelector('c-setup-assistant');
    assistant.dispatchEvent(new CustomEvent('stepnotdone', { detail: { key: 'coexistence' } }));
    await settle();

    expect(markStepNotDone).toHaveBeenCalledWith({ stepKey: 'coexistence' });
    expect(element.shadowRoot.querySelector('c-setup-assistant').completed).toBe(0);
  });

  it('shows the message from the server when a step cannot be recorded', async () => {
    markStepDone.mockRejectedValue({ body: { message: 'You need the permission.' } });
    const element = build();
    await settle();

    element.shadowRoot
      .querySelector('c-setup-assistant')
      .dispatchEvent(new CustomEvent('stepdone', { detail: { key: 'modules' } }));
    await settle();

    expect(element.shadowRoot.querySelector('p[role="alert"]').textContent).toContain(
      'You need the permission.'
    );
  });
});
