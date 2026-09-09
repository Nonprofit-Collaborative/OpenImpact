import { createElement } from 'lwc';
import HealthCheckPanel from 'c/healthCheckPanel';
import getReport from '@salesforce/apex/HealthCheckController.getReport';
import previewFix from '@salesforce/apex/HealthCheckController.previewFix';
import applyFix from '@salesforce/apex/HealthCheckController.applyFix';

jest.mock('@salesforce/apex/HealthCheckController.getReport', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/HealthCheckController.previewFix', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/HealthCheckController.applyFix', () => ({ default: jest.fn() }), {
  virtual: true
});

const mockNavigate = jest.fn();
jest.mock(
  'lightning/navigation',
  () => {
    const Navigate = Symbol('Navigate');
    const GenerateUrl = Symbol('GenerateUrl');
    const NavigationMixin = (Base) =>
      class extends Base {
        [Navigate](...args) {
          mockNavigate(...args);
        }
        [GenerateUrl]() {
          return Promise.resolve('https://example.com');
        }
      };
    NavigationMixin.Navigate = Navigate;
    NavigationMixin.GenerateUrl = GenerateUrl;
    return { NavigationMixin, CurrentPageReference: null, __esModule: true };
  },
  { virtual: true }
);

/** Maria's org: Person Accounts on, Nonprofit Cloud objects present, no mode confirmed. */
function agentforceReport(overrides = {}) {
  return {
    canManageSettings: true,
    modeNeedsAttention: true,
    currentModeLabel: 'not confirmed yet',
    recommendedModeLabel: 'Agentforce Nonprofit coexistence',
    orgShapeSummary: 'Person Accounts enabled. Agentforce Nonprofit objects detected.',
    orgShape: { hasPersonAccounts: true, hasIndustriesNonprofit: true },
    // Both come from Apex, which computes them from the running namespace. Unmanaged, which
    // is what the scratch orgs are, they look like this.
    settingsTabApiName: 'Nonprofit_Settings',
    sectionStateKey: 'c__section',
    findings: [
      {
        key: 'org_shape',
        title: 'What we found in your org',
        detail: 'Person Accounts enabled.',
        severity: 'Info',
        category: 'OrgShape',
        fixLabel: null,
        fixTarget: null
      },
      {
        key: 'membership_mode_person_accounts',
        title: 'Household membership does not fit Person Accounts',
        detail: 'Person Accounts are enabled.',
        severity: 'Error',
        category: 'OrgShape',
        fixLabel: 'Switch to junction membership',
        fixTarget: 'action:applyJunctionMembership'
      },
      {
        key: 'no_nonprofit_admin',
        title: 'No one is assigned the Nonprofit Admin role',
        detail: 'Nobody has the role.',
        severity: 'Error',
        category: 'Access',
        fixLabel: 'Open the Access page',
        fixTarget: 'Access'
      },
      {
        key: 'error_log_new',
        title: '2 errors nobody has looked at',
        detail: 'The Error Log has 2 new entries.',
        severity: 'Warning',
        category: 'Settings',
        fixLabel: 'Open the Error Log',
        fixTarget: '/lightning/o/Error_Log__c/list'
      }
    ],
    ...overrides
  };
}

/** What Apex answers when the panel asks what a fix would do. */
function preview(fixKey, overrides = {}) {
  return {
    fixKey,
    title: 'Add the rollups this package ships',
    summary: 'Open Impact will create 2 rollup definitions, listed below.',
    items: ['Household Lifetime Giving', 'Household Last Gift Date'],
    moreLabel: null,
    affected: 2,
    nothingToDo: false,
    ...overrides
  };
}

function findFix(element, target) {
  const fixes = element.shadowRoot.querySelectorAll('[data-id="fix"]');
  return Array.from(fixes).find((button) => button.dataset.target === target);
}

function createPanel() {
  const element = createElement('c-health-check-panel', { is: HealthCheckPanel });
  document.body.appendChild(element);
  return element;
}

function clickSectionFix(element) {
  const fixes = element.shadowRoot.querySelectorAll('[data-id="fix"]');
  Array.from(fixes)
    .find((button) => button.dataset.target === 'Access')
    .click();
}

function flush() {
  return Promise.resolve().then(() => Promise.resolve());
}

describe('c-health-check-panel', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
    mockNavigate.mockClear();
  });

  it('shows the org shape card and every finding, grouped', async () => {
    getReport.mockResolvedValue(agentforceReport());
    const element = createPanel();
    await flush();

    const summary = element.shadowRoot.querySelector('[data-id="org-shape-summary"]');
    expect(summary.textContent).toContain('Person Accounts enabled');

    const findings = element.shadowRoot.querySelectorAll('[data-id="finding"]');
    expect(findings.length).toBe(4);

    const groups = element.shadowRoot.querySelectorAll('[data-id="group"]');
    expect(groups.length).toBe(3);
  });

  it('previews the recommended mode rather than applying it, and applies it on confirm', async () => {
    getReport.mockResolvedValue(agentforceReport());
    previewFix.mockResolvedValue(
      preview('applyRecommendedMode', {
        title: 'Use the coexistence mode this org needs',
        summary: 'Open Impact will change the coexistence mode from Standalone.',
        items: [],
        affected: 1
      })
    );
    applyFix.mockResolvedValue({
      result: { fixKey: 'applyRecommendedMode', summary: 'The coexistence mode is now NPSP.' },
      report: agentforceReport({ modeNeedsAttention: false, findings: [] })
    });
    const element = createPanel();
    await flush();

    element.shadowRoot.querySelector('[data-id="use-recommended"]').click();
    await flush();

    expect(previewFix).toHaveBeenCalledWith({ fixKey: 'applyRecommendedMode' });
    expect(applyFix).not.toHaveBeenCalled();
    const panel = element.shadowRoot.querySelector('[data-id="fix-preview"]');
    expect(panel).not.toBeNull();
    expect(
      element.shadowRoot.querySelector('[data-id="fix-preview-summary"]').textContent
    ).toContain('will change the coexistence mode');

    element.shadowRoot.querySelector('[data-id="fix-confirm"]').click();
    await flush();

    expect(applyFix).toHaveBeenCalledWith({ fixKey: 'applyRecommendedMode' });
    expect(element.shadowRoot.querySelector('[data-id="fix-preview"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="fix-result-summary"]').textContent).toBe(
      'The coexistence mode is now NPSP.'
    );
    expect(element.shadowRoot.querySelector('[data-id="use-recommended"]')).toBeNull();
  });

  it('names what a fix would create, and cancelling changes nothing', async () => {
    getReport.mockResolvedValue(agentforceReport());
    previewFix.mockResolvedValue(preview('applyJunctionMembership'));
    const element = createPanel();
    await flush();

    findFix(element, 'action:applyJunctionMembership').click();
    await flush();

    const items = element.shadowRoot.querySelectorAll('[data-id="fix-preview-item"]');
    expect(items.length).toBe(2);
    expect(items[0].textContent).toBe('Household Lifetime Giving');

    element.shadowRoot.querySelector('[data-id="fix-cancel"]').click();
    await flush();

    expect(applyFix).not.toHaveBeenCalled();
    expect(element.shadowRoot.querySelector('[data-id="fix-preview"]')).toBeNull();
  });

  it('says so and applies nothing when a fix has nothing left to do', async () => {
    getReport.mockResolvedValue(agentforceReport());
    previewFix.mockResolvedValue(
      preview('applyJunctionMembership', { items: [], affected: 0, nothingToDo: true })
    );
    const element = createPanel();
    await flush();

    findFix(element, 'action:applyJunctionMembership').click();
    await flush();

    expect(applyFix).not.toHaveBeenCalled();
    expect(element.shadowRoot.querySelector('[data-id="fix-preview"]')).toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="fix-result"]')).not.toBeNull();
    expect(getReport).toHaveBeenCalledTimes(2);
  });

  it('shows the message when a fix is refused', async () => {
    getReport.mockResolvedValue(agentforceReport());
    previewFix.mockRejectedValue({
      body: { message: 'You need the Manage Nonprofit Settings permission.' }
    });
    const element = createPanel();
    await flush();

    findFix(element, 'action:applyJunctionMembership').click();
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="error"]').textContent).toBe(
      'You need the Manage Nonprofit Settings permission.'
    );
    expect(element.shadowRoot.querySelector('[data-id="fix-preview"]')).toBeNull();
  });

  it('navigates to a relative URL fix', async () => {
    getReport.mockResolvedValue(agentforceReport());
    const element = createPanel();
    await flush();

    const fixes = element.shadowRoot.querySelectorAll('[data-id="fix"]');
    const errorLog = Array.from(fixes).find((button) => button.dataset.target.startsWith('/'));
    errorLog.click();
    await flush();

    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__webPage',
      attributes: { url: '/lightning/o/Error_Log__c/list' }
    });
  });

  it('navigates to the settings console when no host handles the section fix', async () => {
    getReport.mockResolvedValue(agentforceReport());
    const element = createPanel();
    const handler = jest.fn();
    element.addEventListener('navigatetosection', handler);
    await flush();

    clickSectionFix(element);
    await flush();

    expect(handler).toHaveBeenCalled();
    expect(handler.mock.calls[0][0].detail.section).toBe('Access');
    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: 'Nonprofit_Settings' },
      state: { c__section: 'Access' }
    });
  });

  it('leaves the section fix to a host that handles it, and does not also navigate', async () => {
    getReport.mockResolvedValue(agentforceReport());
    const element = createPanel();
    const handler = jest.fn((event) => event.preventDefault());
    element.addEventListener('navigatetosection', handler);
    await flush();

    clickSectionFix(element);
    await flush();

    expect(handler).toHaveBeenCalled();
    expect(mockNavigate).not.toHaveBeenCalled();
  });

  it('uses the namespaced tab and state key the report supplies', async () => {
    getReport.mockResolvedValue(
      agentforceReport({
        settingsTabApiName: 'example__Nonprofit_Settings',
        sectionStateKey: 'example__section'
      })
    );
    const element = createPanel();
    await flush();

    clickSectionFix(element);
    await flush();

    expect(mockNavigate).toHaveBeenCalledWith({
      type: 'standard__navItemPage',
      attributes: { apiName: 'example__Nonprofit_Settings' },
      state: { example__section: 'Access' }
    });
  });

  it('is read only without the permission', async () => {
    getReport.mockResolvedValue(agentforceReport({ canManageSettings: false }));
    const element = createPanel();
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="read-only"]')).not.toBeNull();
    expect(element.shadowRoot.querySelectorAll('[data-id="fix"]').length).toBe(0);
    expect(element.shadowRoot.querySelector('[data-id="use-recommended"]')).toBeNull();
  });

  it('re-runs on demand', async () => {
    getReport.mockResolvedValue(agentforceReport());
    const element = createPanel();
    await flush();

    element.shadowRoot.querySelector('[data-id="rerun"]').click();
    await flush();

    expect(getReport).toHaveBeenCalledTimes(2);
  });

  it('shows the message when the report cannot be read', async () => {
    getReport.mockRejectedValue({ body: { message: 'Health Check could not read your org.' } });
    const element = createPanel();
    await flush();

    const error = element.shadowRoot.querySelector('[data-id="error"]');
    expect(error.textContent).toBe('Health Check could not read your org.');
  });
});
