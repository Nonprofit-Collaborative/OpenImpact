import { createElement } from 'lwc';
import ImportFileValues from 'c/importFileValues';

const OPTIONS = [
  { label: 'Household: name', value: 'Household.Name' },
  { label: 'Organization: phone', value: 'Organization.Phone' }
];

function render(values = []) {
  const element = createElement('c-import-file-values', { is: ImportFileValues });
  element.options = OPTIONS;
  element.values = values;
  document.body.appendChild(element);
  return element;
}

async function flush() {
  await Promise.resolve();
  await Promise.resolve();
}

describe('the values for every row of a file', () => {
  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
  });

  it('starts with none and adds one row per click', async () => {
    const element = render();
    const changes = [];
    element.addEventListener('change', (event) => changes.push(event.detail.values));
    expect(element.shadowRoot.querySelectorAll('[data-id="file-value"]')).toHaveLength(0);
    element.shadowRoot.querySelector('[data-id="file-value-add"]').click();
    await flush();
    expect(element.shadowRoot.querySelectorAll('[data-id="file-value"]')).toHaveLength(1);
    expect(changes[0]).toEqual([{ target: undefined, value: '' }]);
  });

  it('offers the targets it was given and reports a chosen target and value', async () => {
    const element = render([{ target: undefined, value: '' }]);
    const changes = [];
    element.addEventListener('change', (event) => changes.push(event.detail.values));
    await flush();
    const target = element.shadowRoot.querySelector('[data-id="file-value-target"]');
    expect(target.options).toEqual(OPTIONS);
    target.dispatchEvent(new CustomEvent('change', { detail: { value: 'Household.Name' } }));
    const value = element.shadowRoot.querySelector('[data-id="file-value-value"]');
    value.value = 'Gala 2026 guests';
    value.dispatchEvent(new CustomEvent('change'));
    await flush();
    expect(changes[changes.length - 1]).toEqual([
      { target: 'Household.Name', value: 'Gala 2026 guests' }
    ]);
  });

  it('removes the row whose button was pressed and keeps the others', async () => {
    const element = render([
      { target: 'Household.Name', value: 'One' },
      { target: 'Organization.Phone', value: 'Two' }
    ]);
    const changes = [];
    element.addEventListener('change', (event) => changes.push(event.detail.values));
    await flush();
    element.shadowRoot.querySelectorAll('[data-id="file-value-remove"]')[0].click();
    await flush();
    expect(changes[0]).toEqual([{ target: 'Organization.Phone', value: 'Two' }]);
    expect(element.shadowRoot.querySelectorAll('[data-id="file-value"]')).toHaveLength(1);
  });

  it('stops adding at fifty values, the most a file may carry', async () => {
    const fifty = Array.from({ length: 50 }, (unused, index) => ({
      target: 'Household.Name',
      value: `Value ${index}`
    }));
    const element = render(fifty);
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="file-value-add"]').disabled).toBe(true);
  });
});
