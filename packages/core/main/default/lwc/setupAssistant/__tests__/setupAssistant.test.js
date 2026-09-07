import { createElement } from 'lwc';
import SetupAssistant from 'c/setupAssistant';

const STEPS = [
  {
    key: 'coexistence',
    position: 1,
    label: 'Confirm how Open Impact fits your existing org',
    description: 'If your org uses Person Accounts, membership uses the junction model.',
    targetType: 'Settings',
    target: 'General',
    setupPath: null,
    completed: true
  },
  {
    key: 'access',
    position: 4,
    label: 'Give your colleagues access',
    description: 'Pick a person and a role.',
    targetType: 'Setup',
    target: 'Access',
    setupPath: '/lightning/setup/ManageUsers/home',
    completed: false
  }
];

function build(canEdit) {
  const element = createElement('c-setup-assistant', { is: SetupAssistant });
  element.steps = STEPS;
  element.completed = 1;
  element.total = 2;
  element.canEdit = canEdit;
  document.body.appendChild(element);
  return element;
}

describe('c-setup-assistant', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('shows each step with its status and how far Maria has got', () => {
    const element = build(true);

    expect(element.shadowRoot.querySelectorAll('li')).toHaveLength(2);
    expect(element.shadowRoot.textContent).toContain('1 of 2');
    const badges = element.shadowRoot.querySelectorAll('span.slds-badge');
    expect(badges[0].textContent).toContain('Core_SetupAssistant_DoneBadge');
    expect(badges[1].textContent).toContain('Core_SetupAssistant_ToDoBadge');
  });

  it('sends a step to the settings console and a Setup step to Setup', () => {
    const element = build(true);
    const links = element.shadowRoot.querySelectorAll('a');

    expect(links[0].href).toContain('/lightning/n/Nonprofit_Settings?section=General');
    expect(links[1].href).toContain('/lightning/setup/ManageUsers/home');
  });

  it('asks the page to mark a step done, and a done step not done', () => {
    const element = build(true);
    const done = jest.fn();
    const notDone = jest.fn();
    element.addEventListener('stepdone', done);
    element.addEventListener('stepnotdone', notDone);

    const buttons = element.shadowRoot.querySelectorAll('lightning-button');
    buttons[0].click();
    buttons[1].click();

    expect(notDone).toHaveBeenCalled();
    expect(notDone.mock.calls[0][0].detail.key).toBe('coexistence');
    expect(done).toHaveBeenCalled();
    expect(done.mock.calls[0][0].detail.key).toBe('access');
  });

  it('lets David read the checklist without ticking it off', () => {
    const element = build(false);

    expect(element.shadowRoot.querySelectorAll('li')).toHaveLength(2);
    expect(element.shadowRoot.querySelectorAll('lightning-button')).toHaveLength(0);
  });
});
