import { createElement } from 'lwc';
import QueryFieldPicker from 'c/queryFieldPicker';
import describeObject from '@salesforce/apex/FindController.describeObject';

jest.mock('@salesforce/apex/FindController.describeObject', () => ({ default: jest.fn() }), {
  virtual: true
});

const CONTACT = {
  name: 'Contact',
  fields: [
    {
      name: 'LastName',
      label: 'Last Name',
      type: 'string',
      filterable: true,
      sortable: true,
      showable: true
    },
    {
      name: 'Description',
      label: 'Description',
      type: 'textarea',
      filterable: false,
      sortable: false,
      showable: true
    },
    {
      name: 'AccountId',
      label: 'Account ID',
      type: 'reference',
      filterable: true,
      sortable: true,
      showable: true,
      relationshipName: 'Account',
      relationshipLabel: 'Account',
      referenceTo: 'Account'
    }
  ]
};
const ACCOUNT = {
  name: 'Account',
  fields: [
    {
      name: 'Name',
      label: 'Account Name',
      type: 'string',
      filterable: true,
      sortable: true,
      showable: true
    },
    {
      name: 'OwnerId',
      label: 'Owner ID',
      type: 'reference',
      filterable: true,
      sortable: true,
      showable: true,
      relationshipName: 'Owner',
      relationshipLabel: 'Owner',
      referenceTo: 'User'
    }
  ]
};
const USER = {
  name: 'User',
  fields: [
    {
      name: 'Name',
      label: 'Full Name',
      type: 'string',
      filterable: true,
      sortable: true,
      showable: true
    },
    {
      name: 'ManagerId',
      label: 'Manager ID',
      type: 'reference',
      filterable: true,
      sortable: true,
      showable: true,
      relationshipName: 'Manager',
      relationshipLabel: 'Manager',
      referenceTo: 'User'
    }
  ]
};

function flush() {
  // eslint-disable-next-line @lwc/lwc/no-async-operation
  return new Promise((resolve) => setTimeout(resolve, 0));
}

async function render(props = {}) {
  const element = createElement('c-query-field-picker', { is: QueryFieldPicker });
  Object.assign(element, { label: 'Field', objectName: 'Contact', ...props });
  document.body.appendChild(element);
  await flush();
  return element;
}

function comboboxes(element) {
  return element.shadowRoot.querySelectorAll('lightning-combobox');
}

function choose(combobox, value) {
  combobox.dispatchEvent(new CustomEvent('change', { detail: { value } }));
}

describe('the query field picker', () => {
  beforeEach(() => {
    describeObject.mockImplementation(({ objectName }) =>
      Promise.resolve({ Contact: CONTACT, Account: ACCOUNT, User: USER }[objectName])
    );
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it("offers the object's fields and its lookups", async () => {
    const element = await render();
    const values = comboboxes(element)[0].options.map((option) => option.value);
    expect(values).toEqual(['LastName', 'Description', 'AccountId', 'rel:AccountId']);
  });

  it('offers only filterable fields to a filter', async () => {
    const element = await render({ filterableOnly: true });
    const values = comboboxes(element)[0].options.map((option) => option.value);
    expect(values).not.toContain('Description');
  });

  it('follows two lookups and no more, and names the path it built', async () => {
    const element = await render();
    const handler = jest.fn();
    element.addEventListener('fieldchange', handler);

    choose(comboboxes(element)[0], 'rel:AccountId');
    await flush();
    choose(comboboxes(element)[1], 'rel:OwnerId');
    await flush();
    const third = comboboxes(element)[2];
    expect(third.options.map((option) => option.value)).toEqual(['Name', 'ManagerId']);

    choose(third, 'Name');
    expect(handler).toHaveBeenCalledTimes(1);
    expect(handler.mock.calls[0][0].detail).toMatchObject({
      path: 'Account.Owner.Name',
      label: 'Account > Owner > Full Name',
      type: 'string'
    });
  });

  it('says what went wrong when the object cannot be described', async () => {
    describeObject.mockRejectedValue({ body: { message: 'You cannot read that kind of record.' } });
    const element = await render();
    expect(element.shadowRoot.querySelector('[data-id="picker-error"]').textContent).toBe(
      'You cannot read that kind of record.'
    );
  });
});
