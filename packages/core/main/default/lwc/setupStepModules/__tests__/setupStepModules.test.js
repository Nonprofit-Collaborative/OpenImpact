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
});
