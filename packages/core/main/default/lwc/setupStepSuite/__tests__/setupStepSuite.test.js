import { createElement } from 'lwc';
import SetupStepSuite from 'c/setupStepSuite';

const NONPROFIT_MODULES = [
  { name: 'Giving', present: false, required: true, docsUrl: 'https://example.invalid/guide' },
  { name: 'Programs', present: false, required: false, docsUrl: 'https://example.invalid/guide' },
  {
    name: 'Logic Models',
    present: false,
    required: false,
    docsUrl: 'https://example.invalid/guide'
  },
  { name: 'Volunteers', present: false, required: false, docsUrl: 'https://example.invalid/guide' },
  { name: 'Funders', present: false, required: false, docsUrl: 'https://example.invalid/guide' },
  { name: 'Connect', present: false, required: false, docsUrl: 'https://example.invalid/guide' }
];

const COMMUNITY_MODULES = [
  { name: 'Volunteers', present: false, required: false, docsUrl: 'https://example.invalid/guide' }
];

function suite(overrides = {}) {
  return {
    chosenSuite: null,
    recommendedSuite: 'Community',
    givingPresent: false,
    options: [
      {
        value: 'Nonprofit',
        label: 'Nonprofit Suite',
        description: 'For nonprofits.',
        modules: NONPROFIT_MODULES
      },
      {
        value: 'Community',
        label: 'Community Suite',
        description: 'For any other organization.',
        modules: COMMUNITY_MODULES
      }
    ],
    ...overrides
  };
}

function build(model, canEdit = true) {
  const element = createElement('c-setup-step-suite', { is: SetupStepSuite });
  element.suite = model;
  element.canEdit = canEdit;
  document.body.appendChild(element);
  return element;
}

function radios(element) {
  return Array.from(element.shadowRoot.querySelectorAll('[data-id="suite-option"]'));
}

function listedModules(element) {
  return element.shadowRoot.querySelector('[data-id="suite-modules"]').modules.map((m) => m.name);
}

function select(element, value) {
  const radio = radios(element).find((input) => input.value === value);
  radio.checked = true;
  radio.dispatchEvent(new CustomEvent('change'));
}

function flush() {
  return Promise.resolve();
}

describe('c-setup-step-suite', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('offers both suites, each with its one line description', () => {
    const element = build(suite());

    expect(radios(element).map((input) => input.value)).toEqual(['Nonprofit', 'Community']);
    expect(element.shadowRoot.textContent).toContain('Nonprofit Suite');
    expect(element.shadowRoot.textContent).toContain('For nonprofits.');
    expect(element.shadowRoot.textContent).toContain('Community Suite');
    expect(element.shadowRoot.textContent).toContain('For any other organization.');
  });

  it('preselects the suggested suite while nobody has chosen', () => {
    const element = build(suite({ recommendedSuite: 'Nonprofit', givingPresent: true }));

    const checked = radios(element).filter((input) => input.checked);
    expect(checked.map((input) => input.value)).toEqual(['Nonprofit']);
    expect(listedModules(element)).toEqual([
      'Giving',
      'Programs',
      'Logic Models',
      'Volunteers',
      'Funders',
      'Connect'
    ]);
  });

  it('selects the saved suite over the suggestion', () => {
    const element = build(suite({ chosenSuite: 'Community', recommendedSuite: 'Nonprofit' }));

    const checked = radios(element).filter((input) => input.checked);
    expect(checked.map((input) => input.value)).toEqual(['Community']);
  });

  it('lists only the Community Suite modules, never a module only for nonprofits', () => {
    const element = build(suite());

    expect(listedModules(element)).toEqual(['Volunteers']);
    expect(element.shadowRoot.querySelector('[data-id="needs-giving"]')).toBeNull();
  });

  it('changes the list when another suite is selected, without saving anything', async () => {
    const element = build(suite());
    const chosen = jest.fn();
    element.addEventListener('choose', chosen);

    select(element, 'Nonprofit');
    await flush();

    expect(listedModules(element)).toContain('Giving');
    expect(chosen).not.toHaveBeenCalled();
  });

  it('says plainly that the Nonprofit Suite needs Giving when Giving is not installed', async () => {
    const element = build(suite());

    select(element, 'Nonprofit');
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="needs-giving"]').textContent).toContain(
      'Core_SetupAssistant_SuiteNeedsGivingNotice'
    );
  });

  it('says nothing about Giving when Giving is installed', () => {
    const element = build(suite({ recommendedSuite: 'Nonprofit', givingPresent: true }));

    expect(element.shadowRoot.querySelector('[data-id="needs-giving"]')).toBeNull();
  });

  it('sends the selected suite when Maria chooses it', async () => {
    const element = build(suite());
    const chosen = jest.fn();
    element.addEventListener('choose', chosen);

    select(element, 'Nonprofit');
    await flush();
    element.shadowRoot.querySelector('[data-id="choose-suite"]').click();

    expect(chosen).toHaveBeenCalledTimes(1);
    expect(chosen.mock.calls[0][0].detail).toEqual({ suite: 'Nonprofit' });
  });

  it('lets David read the choice but not make it', () => {
    const element = build(suite(), false);

    expect(radios(element).every((input) => input.disabled)).toBe(true);
    expect(element.shadowRoot.querySelector('[data-id="choose-suite"]')).toBeNull();
  });

  it('draws nothing broken when the model has not arrived', () => {
    const element = build(undefined);

    expect(radios(element)).toHaveLength(0);
    expect(element.shadowRoot.querySelector('[data-id="suite-modules"]')).toBeNull();
  });
});
