import { createElement } from 'lwc';
import SetupStepModules from 'c/setupStepModules';

const MODULES = [
  { name: 'Core', present: true, docsUrl: 'https://example.invalid/core' },
  { name: 'Giving', present: false, docsUrl: 'https://example.invalid/giving' }
];

function build() {
  const element = createElement('c-setup-step-modules', { is: SetupStepModules });
  element.modules = MODULES;
  document.body.appendChild(element);
  return element;
}

describe('c-setup-step-modules', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('says which modules are here and which are not', () => {
    const element = build();

    const items = element.shadowRoot.querySelectorAll('li');
    expect(items).toHaveLength(2);
    expect(items[0].textContent).toContain('Core_SetupAssistant_ModulePresent');
    expect(items[1].textContent).toContain('Core_SetupAssistant_ModuleAbsent');
  });

  it('links each module to what it does', () => {
    const element = build();

    const links = element.shadowRoot.querySelectorAll('a');
    expect(links).toHaveLength(2);
    expect(links[1].href).toContain('giving');
  });

  it('says plainly that one click module control comes later', () => {
    const element = build();

    expect(element.shadowRoot.textContent).toContain('Core_SetupAssistant_ModuleManagerNotice');
  });

  it('says whether the suite needs each module', () => {
    const element = createElement('c-setup-step-modules', { is: SetupStepModules });
    element.modules = [
      { name: 'Giving', present: true, required: true, docsUrl: 'https://example.invalid/g' },
      { name: 'Programs', present: false, required: false, docsUrl: 'https://example.invalid/p' }
    ];
    document.body.appendChild(element);

    const roles = element.shadowRoot.querySelectorAll('[data-id="module-role"]');
    expect(roles).toHaveLength(2);
    expect(roles[0].textContent).toContain('Core_SetupAssistant_ModuleRequired');
    expect(roles[1].textContent).toContain('Core_SetupAssistant_ModuleOptional');
  });

  it('says how to get a module that is not installed while no install link is published', () => {
    const element = build();

    const rows = element.shadowRoot.querySelectorAll('[data-id="module-row"]');
    expect(rows[0].querySelector('[data-id="how-to-get"]')).toBeNull();
    expect(rows[1].querySelector('[data-id="how-to-get"]').textContent).toContain(
      'Core_SetupAssistant_ModuleHowToGet'
    );
    expect(element.shadowRoot.querySelector('[data-id="install-link"]')).toBeNull();
  });

  it('offers the install link once a module carries one', () => {
    const element = createElement('c-setup-step-modules', { is: SetupStepModules });
    element.modules = [
      {
        name: 'Volunteers',
        present: false,
        required: false,
        docsUrl: 'https://example.invalid/v',
        installUrl: 'https://example.invalid/install/volunteers'
      },
      {
        name: 'Giving',
        present: true,
        required: true,
        docsUrl: 'https://example.invalid/g',
        installUrl: 'https://example.invalid/install/giving'
      }
    ];
    document.body.appendChild(element);

    const links = element.shadowRoot.querySelectorAll('[data-id="install-link"]');
    expect(links).toHaveLength(1);
    expect(links[0].href).toBe('https://example.invalid/install/volunteers');
    expect(element.shadowRoot.querySelector('[data-id="how-to-get"]')).toBeNull();
  });
});
