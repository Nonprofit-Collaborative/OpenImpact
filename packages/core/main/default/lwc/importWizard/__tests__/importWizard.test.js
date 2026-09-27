import { createElement } from 'lwc';
import ImportWizard from 'c/importWizard';
import canImport from '@salesforce/apex/ImportController.canImport';
import getTemplates from '@salesforce/apex/ImportController.getTemplates';
import suggestMapping from '@salesforce/apex/ImportController.suggestMapping';
import saveFile from '@salesforce/apex/ImportController.saveFile';
import createBatch from '@salesforce/apex/ImportController.createBatch';
import stageRows from '@salesforce/apex/ImportController.stageRows';
import startDryRun from '@salesforce/apex/ImportController.startDryRun';
import startCommit from '@salesforce/apex/ImportController.startCommit';
import getBatch from '@salesforce/apex/ImportController.getBatch';
import getRows from '@salesforce/apex/ImportController.getRows';
import saveRecurring from '@salesforce/apex/ImportController.saveRecurring';
import getEntityTargets from '@salesforce/apex/ImportController.getEntityTargets';
import getMatchFields from '@salesforce/apex/ImportController.getMatchFields';
import getSeveralMatchRows from '@salesforce/apex/ImportController.getSeveralMatchRows';
import getLoadableObjects from '@salesforce/apex/ImportController.getLoadableObjects';
import createObjectTemplate from '@salesforce/apex/ImportController.createObjectTemplate';
import getObjectFields from '@salesforce/apex/ImportController.getObjectFields';
import getKeyFields from '@salesforce/apex/ImportController.getKeyFields';

jest.mock('@salesforce/apex/ImportController.canImport', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.getTemplates', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.suggestMapping', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.saveFile', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.createBatch', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.stageRows', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.startDryRun', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.startCommit', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.getBatch', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.saveRecurring', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.getRows', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.getEntityTargets', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.getMatchFields', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.getSeveralMatchRows', () => ({ default: jest.fn() }), {
  virtual: true
});

jest.mock('@salesforce/apex/ImportController.getLoadableObjects', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock(
  '@salesforce/apex/ImportController.createObjectTemplate',
  () => ({ default: jest.fn() }),
  {
    virtual: true
  }
);
jest.mock('@salesforce/apex/ImportController.getObjectFields', () => ({ default: jest.fn() }), {
  virtual: true
});
jest.mock('@salesforce/apex/ImportController.getKeyFields', () => ({ default: jest.fn() }), {
  virtual: true
});

const TEMPLATE = {
  id: 'a01',
  name: 'Generic donor list',
  description: 'A list of people with their contact details.',
  matchingRule: 'Email exact',
  personMode: 'Contacts',
  mapping: '{"version":1,"columns":[]}',
  isPackageDefault: true
};

const DRY_RUN_BATCH = {
  id: 'a02',
  name: 'IB-000001',
  status: 'Dry run complete',
  isDryRun: true,
  isFinished: true,
  rowCount: 2,
  created: 2,
  updated: 0,
  matched: 0,
  rejected: 0,
  runLog: 'Dry run. Nothing was written.'
};

const FILE_TEXT = 'Last Name,Email,Notes\nRamirez,ana@example.org,vip\nOkafor,ben@example.org,';

/** How a template matches rows when nobody changed anything (R-IT8, R-IT9). */
const DEFAULT_MATCHING = {
  saveMatching: true,
  organizationRule: 'Name exact',
  personMatchField: '',
  organizationMatchField: '',
  severalMatches: 'Reject the row',
  fileValues: []
};

/**
 * Lets every pending promise and rerender settle. Several turns, because reading a file goes
 * through FileReader, which resolves on its own task.
 */
async function flush(turns = 5) {
  for (let i = 0; i < turns; i++) {
    await new Promise((resolve) => setTimeout(resolve, 0));
  }
}

function render() {
  const element = createElement('c-import-wizard', { is: ImportWizard });
  document.body.appendChild(element);
  return element;
}

/** Feeds the wizard a file the way the browser's file input does. */
async function chooseFile(element, text = FILE_TEXT, name = 'donors.csv') {
  const input = element.shadowRoot.querySelector('[data-id="file"]');
  const file = new File([text], name, { type: 'text/csv' });
  Object.defineProperty(input, 'files', { value: [file], configurable: true });
  input.dispatchEvent(new CustomEvent('change'));
  await flush();
}

function click(element, id) {
  element.shadowRoot.querySelector(`[data-id="${id}"]`).click();
}

describe('the import wizard', () => {
  beforeEach(() => {
    canImport.mockResolvedValue(true);
    getTemplates.mockResolvedValue([TEMPLATE]);
    suggestMapping.mockResolvedValue(
      JSON.stringify({
        version: 1,
        columns: [
          { source: 'Last Name', target: 'Contact1.LastName' },
          { source: 'Email', target: 'Contact1.Email' },
          { source: 'Notes', target: 'Ignore' }
        ]
      })
    );
    saveFile.mockResolvedValue('069000000000001');
    createBatch.mockResolvedValue(DRY_RUN_BATCH);
    stageRows.mockResolvedValue(2);
    startDryRun.mockResolvedValue(DRY_RUN_BATCH);
    startCommit.mockResolvedValue({ ...DRY_RUN_BATCH, status: 'Complete', isDryRun: false });
    getBatch.mockResolvedValue(DRY_RUN_BATCH);
    getRows.mockResolvedValue([]);
    getEntityTargets.mockResolvedValue([]);
    getMatchFields.mockResolvedValue({
      person: [{ value: 'Donor_Id__c', label: 'Donor ID' }],
      organization: [{ value: 'Org_Id__c', label: 'Organization ID' }]
    });
    getSeveralMatchRows.mockResolvedValue([]);
  });

  afterEach(() => {
    while (document.body.firstChild) {
      document.body.removeChild(document.body.firstChild);
    }
    jest.clearAllMocks();
  });

  it('offers the templates it was given', async () => {
    const element = render();
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="template"]').options).toEqual([
      { label: 'Generic donor list', value: 'a01' }
    ]);
  });

  it('tells a user without the permission who to ask', async () => {
    canImport.mockResolvedValue(false);
    const element = render();
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="read-only"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="template"]')).toBeNull();
  });

  it('saves the recurring mark and its source name before leaving the first step', async () => {
    saveRecurring.mockResolvedValue(undefined);
    const element = render();
    await flush();
    const box = element.shadowRoot.querySelector('[data-id="recurring"]');
    box.checked = true;
    box.dispatchEvent(new CustomEvent('change'));
    await flush();
    const name = element.shadowRoot.querySelector('[data-id="source-name"]');
    name.value = 'Monthly processor export';
    name.dispatchEvent(new CustomEvent('change'));
    click(element, 'next');
    await flush();

    expect(saveRecurring).toHaveBeenCalledWith({
      templateId: 'a01',
      isRecurring: true,
      sourceName: 'Monthly processor export'
    });
    expect(element.shadowRoot.querySelector('[data-id="file"]')).not.toBeNull();
  });

  it('stays on the first step and says why when the recurring mark is refused', async () => {
    saveRecurring.mockRejectedValue({ body: { message: 'Give this file a source name.' } });
    const element = render();
    await flush();
    const box = element.shadowRoot.querySelector('[data-id="recurring"]');
    box.checked = true;
    box.dispatchEvent(new CustomEvent('change'));
    await flush();
    click(element, 'next');
    await flush();

    expect(element.shadowRoot.querySelector('[data-id="template"]')).not.toBeNull();
    expect(element.shadowRoot.textContent).toContain('Give this file a source name.');
  });

  it('does not save anything when the recurring mark is left alone', async () => {
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    expect(saveRecurring).not.toHaveBeenCalled();
  });

  it('shows the chosen template description so the choice can be checked', async () => {
    const element = render();
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="template-help"]').textContent).toContain(
      'A list of people'
    );
  });

  it('shows a row of the column picker for every column in the file', async () => {
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    const rows = element.shadowRoot.querySelectorAll('[data-id="column-row"]');
    expect(rows).toHaveLength(3);
    expect(rows[0].textContent).toContain('Last Name');
  });

  it('shows the first values of each column beside the choice', async () => {
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    const rows = element.shadowRoot.querySelectorAll('[data-id="column-row"]');
    expect(rows[0].textContent).toContain('Ramirez, Okafor');
  });

  it('refuses a file with no rows under its heading', async () => {
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    await chooseFile(element, 'Last Name,Email');
    // Labels are stubbed by their identifier under jest; the wording itself lives in
    // Import.labels-meta.xml and is quoted in the admin guide.
    expect(element.shadowRoot.querySelector('[data-id="message"]').textContent).toBe(
      'c.Core_Import_NoHeaderRow'
    );
    expect(element.shadowRoot.querySelectorAll('[data-id="column-row"]')).toHaveLength(0);
  });

  it('reads a file named .xlsx as a workbook, and says so when it is not one', async () => {
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    await chooseFile(element, 'not really a workbook', 'donors.xlsx');
    expect(element.shadowRoot.querySelector('[data-id="message"]').textContent).toBe(
      'c.Core_Import_XlsxUnreadable'
    );
    expect(element.shadowRoot.querySelectorAll('[data-id="column-row"]')).toHaveLength(0);
  });

  it('explains what the chosen matching rule risks', async () => {
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    click(element, 'next');
    await flush();
    const help = element.shadowRoot.querySelector('[data-id="rule-help"]');
    expect(help.textContent).toBe('c.Core_Import_MatchingEmailHelp');
  });

  it('writes nothing before the dry run', async () => {
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    click(element, 'next');
    await flush();
    expect(createBatch).not.toHaveBeenCalled();
    expect(startDryRun).not.toHaveBeenCalled();
  });

  it('stages the file in pages and then dry runs it', async () => {
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    click(element, 'next');
    await flush();
    click(element, 'dry-run');
    await flush();

    expect(createBatch).toHaveBeenCalledTimes(1);
    expect(stageRows).toHaveBeenCalledTimes(1);
    // The first data row of a file is row two, because row one is the heading.
    expect(stageRows.mock.calls[0][0].firstRowNumber).toBe(2);
    expect(JSON.parse(stageRows.mock.calls[0][0].rowsJson)).toHaveLength(2);
    expect(startDryRun).toHaveBeenCalledWith({ batchId: 'a02' });
    expect(element.shadowRoot.querySelector('[data-id="results"]')).not.toBeNull();
  });

  it('sends the mapping the administrator settled on, not the suggestion alone', async () => {
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    const picker = element.shadowRoot.querySelectorAll('[data-id="column-row"] lightning-combobox');
    picker[2].dispatchEvent(new CustomEvent('change', { detail: { value: 'Contact1.Phone' } }));
    await flush();
    click(element, 'next');
    await flush();
    click(element, 'dry-run');
    await flush();

    const sent = JSON.parse(createBatch.mock.calls[0][0].mappingDocument);
    expect(sent.columns[2]).toEqual({ source: 'Notes', target: 'Contact1.Phone' });
  });

  it('commits only after the dry run has completed', async () => {
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    click(element, 'next');
    await flush();
    click(element, 'dry-run');
    await flush();

    const commit = element.shadowRoot.querySelector('[data-id="commit"]');
    expect(commit.disabled).toBe(false);
    commit.click();
    await flush();
    expect(startCommit).toHaveBeenCalledWith({ batchId: 'a02' });
  });

  it('leaves the commit button disabled while the dry run is still going', async () => {
    startDryRun.mockResolvedValue({ ...DRY_RUN_BATCH, status: 'Dry run', isFinished: false });
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    click(element, 'next');
    await flush();
    click(element, 'dry-run');
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="commit"]').disabled).toBe(true);
  });

  it('reports a server failure in words rather than swallowing it', async () => {
    getTemplates.mockRejectedValue({ body: { message: 'That mapping no longer exists.' } });
    const element = render();
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="message"]').textContent).toBe(
      'That mapping no longer exists.'
    );
  });

  it('goes back to the start without leaving the last run on the screen', async () => {
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    click(element, 'next');
    await flush();
    click(element, 'dry-run');
    await flush();
    element.shadowRoot.querySelector('[data-id="commit"]').click();
    await flush();
    click(element, 'start-over');
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="template"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="results"]')).toBeNull();
  });

  /** Walks to the matching step with the default file. */
  async function toMatchingStep() {
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    click(element, 'next');
    await flush();
    return element;
  }

  function type(element, id, value) {
    const input = element.shadowRoot.querySelector(`[data-id="${id}"]`);
    input.value = value;
    input.dispatchEvent(new CustomEvent('change'));
  }

  it('sends the control totals with the batch, and none when the boxes are empty', async () => {
    let element = await toMatchingStep();
    // No module reads gift amounts here, so only the row count is offered.
    expect(element.shadowRoot.querySelector('[data-id="expected-amount"]')).toBeNull();
    type(element, 'expected-count', '2');
    await flush();
    click(element, 'dry-run');
    await flush();
    expect(JSON.parse(createBatch.mock.calls[0][0].optionsJson)).toEqual({
      expectedCount: 2,
      expectedAmount: null,
      ...DEFAULT_MATCHING
    });

    document.body.removeChild(element);
    createBatch.mockClear();
    element = await toMatchingStep();
    click(element, 'dry-run');
    await flush();
    expect(JSON.parse(createBatch.mock.calls[0][0].optionsJson)).toEqual({
      expectedCount: null,
      expectedAmount: null,
      ...DEFAULT_MATCHING
    });
  });

  it('offers the gift columns an installed module loads, and the amount control total', async () => {
    getEntityTargets.mockResolvedValue([{ value: 'Gift.Amount__c', label: 'Gift: amount' }]);
    suggestMapping.mockResolvedValue(
      JSON.stringify({
        version: 1,
        columns: [
          { source: 'Last Name', target: 'Contact1.LastName' },
          { source: 'Email', target: 'Contact1.Email' },
          { source: 'Notes', target: 'Gift.Amount__c' }
        ]
      })
    );
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    const picker = element.shadowRoot.querySelector('[data-id="column-row"] lightning-combobox');
    const labels = picker.options.map((option) => option.label);
    expect(labels).toContain('Gift: amount');
    expect(labels).not.toContain('Gift: amount (kept with the row, not loaded yet)');
    click(element, 'next');
    await flush();
    type(element, 'expected-amount', '125.50');
    await flush();
    click(element, 'dry-run');
    await flush();
    expect(JSON.parse(createBatch.mock.calls[0][0].optionsJson).expectedAmount).toBe(125.5);
  });

  it('shows how gifts match scheduled payments, from the template, and saves the choice', async () => {
    getEntityTargets.mockResolvedValue([{ value: 'Gift.Amount__c', label: 'Gift: amount' }]);
    getTemplates.mockResolvedValue([
      { ...TEMPLATE, donationMatching: 'Match only', matchDateWindowDays: 3 }
    ]);
    suggestMapping.mockResolvedValue(
      JSON.stringify({
        version: 1,
        columns: [
          { source: 'Last Name', target: 'Contact1.LastName' },
          { source: 'Email', target: 'Contact1.Email' },
          { source: 'Notes', target: 'Gift.Amount__c' }
        ]
      })
    );
    const element = await toMatchingStep();
    const choice = element.shadowRoot.querySelector('[data-id="donation-matching"]');
    expect(choice.value).toBe('Match only');
    expect(element.shadowRoot.querySelector('[data-id="match-window"]').value).toBe('3');
    choice.dispatchEvent(new CustomEvent('change', { detail: { value: 'Never match' } }));
    type(element, 'match-tolerance', '0.50');
    await flush();
    click(element, 'dry-run');
    await flush();
    expect(JSON.parse(createBatch.mock.calls[0][0].optionsJson)).toEqual({
      expectedCount: null,
      expectedAmount: null,
      ...DEFAULT_MATCHING,
      saveDonationMatching: true,
      donationMatching: 'Never match',
      matchDateWindowDays: 3,
      matchAmountTolerance: 0.5
    });
  });

  it('does not offer donation matching where no module loads gifts', async () => {
    const element = await toMatchingStep();
    expect(element.shadowRoot.querySelector('[data-id="donation-matching"]')).toBeNull();
    click(element, 'dry-run');
    await flush();
    expect(
      JSON.parse(createBatch.mock.calls[0][0].optionsJson).saveDonationMatching
    ).toBeUndefined();
  });

  it('will not commit a file that disagrees with its control totals, and can go back', async () => {
    const disagrees = { ...DRY_RUN_BATCH, controlTotalsAgree: false };
    createBatch.mockResolvedValue(disagrees);
    startDryRun.mockResolvedValue(disagrees);
    getBatch.mockResolvedValue(disagrees);
    const element = await toMatchingStep();
    click(element, 'dry-run');
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="commit"]').disabled).toBe(true);
    click(element, 'back');
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="expected-count"]')).not.toBeNull();
    expect(element.shadowRoot.querySelector('[data-id="results"]')).toBeNull();
  });
  it('explains each organization rule and what several matches do, and saves the choices', async () => {
    const element = await toMatchingStep();
    await flush();
    const help = () => element.shadowRoot.querySelector('[data-id="organization-rule-help"]');
    expect(help().textContent).toContain('c.Core_Import_OrganizationNameHelp');
    expect(element.shadowRoot.querySelector('[data-id="organization-field"]')).toBeNull();
    const rule = element.shadowRoot.querySelector('[data-id="organization-rule"]');
    rule.dispatchEvent(new CustomEvent('change', { detail: { value: 'External ID' } }));
    await flush();
    expect(help().textContent).toContain('c.Core_Import_OrganizationExternalIdHelp');
    // The organization External ID rule needs its field before a dry run.
    expect(element.shadowRoot.querySelector('[data-id="dry-run"]').disabled).toBe(true);
    const field = element.shadowRoot.querySelector('[data-id="organization-field"]');
    expect(field.options).toEqual([{ label: 'Organization ID', value: 'Org_Id__c' }]);
    field.dispatchEvent(new CustomEvent('change', { detail: { value: 'Org_Id__c' } }));
    const several = element.shadowRoot.querySelector('[data-id="several"]');
    expect(several.value).toBe('Reject the row');
    several.dispatchEvent(
      new CustomEvent('change', { detail: { value: 'Use the most recently changed' } })
    );
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="several-help"]').textContent).toContain(
      'c.Core_Import_SeveralMostRecentHelp'
    );
    expect(element.shadowRoot.querySelector('[data-id="dry-run"]').disabled).toBe(false);
    click(element, 'dry-run');
    await flush();
    expect(getMatchFields).toHaveBeenCalledWith({ templateId: 'a01' });
    expect(JSON.parse(createBatch.mock.calls[0][0].optionsJson)).toMatchObject({
      saveMatching: true,
      organizationRule: 'External ID',
      organizationMatchField: 'Org_Id__c',
      severalMatches: 'Use the most recently changed'
    });
  });

  it('offers the person match fields only under the External ID rule, the first one first', async () => {
    getTemplates.mockResolvedValue([{ ...TEMPLATE, matchingRule: 'External ID' }]);
    const element = await toMatchingStep();
    await flush();
    const picker = element.shadowRoot.querySelector('[data-id="person-field"]');
    expect(picker.options).toEqual([
      { label: 'c.Core_Import_PersonMatchFieldDefault', value: '' },
      { label: 'Donor ID', value: 'Donor_Id__c' }
    ]);
    picker.dispatchEvent(new CustomEvent('change', { detail: { value: 'Donor_Id__c' } }));
    click(element, 'dry-run');
    await flush();
    expect(JSON.parse(createBatch.mock.calls[0][0].optionsJson).personMatchField).toBe(
      'Donor_Id__c'
    );
  });

  it('keeps the matching choices the template saved', async () => {
    getTemplates.mockResolvedValue([
      {
        ...TEMPLATE,
        organizationRule: 'External ID',
        organizationMatchField: 'Org_Id__c',
        severalMatches: 'Use the most recently changed'
      }
    ]);
    const element = await toMatchingStep();
    await flush();
    expect(element.shadowRoot.querySelector('[data-id="organization-rule"]').value).toBe(
      'External ID'
    );
    expect(element.shadowRoot.querySelector('[data-id="organization-field"]').value).toBe(
      'Org_Id__c'
    );
    expect(element.shadowRoot.querySelector('[data-id="several"]').value).toBe(
      'Use the most recently changed'
    );
  });

  it('sends the values for every row of the file, leaving out an empty one', async () => {
    const element = await toMatchingStep();
    const values = element.shadowRoot.querySelector('[data-id="file-values"]');
    expect(values.options.map((option) => option.value)).not.toContain('Ignore');
    values.dispatchEvent(
      new CustomEvent('change', {
        detail: {
          values: [
            { target: 'Household.Name', value: 'Gala 2026 guests' },
            { target: 'Organization.Phone', value: '  ' }
          ]
        }
      })
    );
    await flush();
    click(element, 'dry-run');
    await flush();
    expect(JSON.parse(createBatch.mock.calls[0][0].optionsJson).fileValues).toEqual([
      { target: 'Household.Name', value: 'Gala 2026 guests' }
    ]);
  });

  it('offers the affiliation columns, which Core loads', async () => {
    const element = render();
    await flush();
    click(element, 'next');
    await flush();
    await chooseFile(element);
    const picker = element.shadowRoot.querySelector('[data-id="column-row"] lightning-combobox');
    const values = picker.options.map((option) => option.value);
    expect(values).toContain('Affiliation.Role__c');
    expect(values).toContain('Affiliation.Is_Primary__c');
  });

  it('lists the rows that matched several records once the dry run finishes', async () => {
    let poll;
    const interval = jest.spyOn(window, 'setInterval').mockImplementation((callback) => {
      poll = callback;
      return 1;
    });
    try {
      getSeveralMatchRows.mockResolvedValue([
        {
          id: 'r1',
          rowNumber: 3,
          status: 'Rejected',
          errorMessage: 'More than one person matches.',
          severalMatches: true
        }
      ]);
      const element = await toMatchingStep();
      click(element, 'dry-run');
      await flush();
      poll();
      await flush();
      expect(getSeveralMatchRows).toHaveBeenCalledWith({ batchId: 'a02', offsetRows: 0 });
      const results = element.shadowRoot.querySelector('[data-id="results"]');
      expect(results.severalRows).toHaveLength(1);
    } finally {
      interval.mockRestore();
    }
  });
  describe('a mapping that loads one object', () => {
    const OBJECT_TEMPLATE = {
      ...TEMPLATE,
      id: 'a09',
      name: 'Affiliations',
      targetObject: 'Affiliation__c',
      targetObjectLabel: 'Affiliation',
      loadOperation: 'Insert',
      lookupNotFound: 'Reject the row'
    };
    const FIELDS = [
      { value: 'Record.Id', label: 'Record Id', isLookup: false, lookupFields: [] },
      {
        value: 'Record.Organization__c',
        label: 'Organization',
        isLookup: true,
        lookupFields: [
          { value: 'Id', label: 'Record Id' },
          { value: 'Name', label: 'Account Name' }
        ]
      },
      { value: 'Record.Role__c', label: 'Role', isLookup: false, lookupFields: [] }
    ];
    const OBJECT_FILE = 'Employer,Role\nRose City,Treasurer\nOak Trust,Chair';

    beforeEach(() => {
      getTemplates.mockResolvedValue([OBJECT_TEMPLATE]);
      getObjectFields.mockResolvedValue(FIELDS);
      getKeyFields.mockResolvedValue([{ value: 'Pair_Key__c', label: 'Pair Key' }]);
      suggestMapping.mockResolvedValue(
        JSON.stringify({
          version: 1,
          columns: [
            { source: 'Employer', target: 'Record.Organization__c', lookupField: 'Name' },
            { source: 'Role', target: 'Record.Role__c' }
          ]
        })
      );
    });

    async function toColumns() {
      const element = render();
      await flush();
      click(element, 'next');
      await flush();
      await chooseFile(element, OBJECT_FILE, 'affiliations.csv');
      return element;
    }

    it("offers the object's own fields and a lookup's Find it by picker", async () => {
      const element = await toColumns();
      expect(getObjectFields).toHaveBeenCalledWith({ templateId: 'a09' });
      const pickers = element.shadowRoot.querySelectorAll(
        '[data-id="column-row"] lightning-combobox'
      );
      expect(pickers[0].options.map((option) => option.value)).toEqual([
        'Ignore',
        'Record.Id',
        'Record.Organization__c',
        'Record.Role__c'
      ]);
      const lookup = element.shadowRoot.querySelector('[data-id="lookup-field"]');
      expect(lookup.value).toBe('Name');
      expect(lookup.options).toEqual([
        { label: 'Record Id', value: 'Id' },
        { label: 'Account Name', value: 'Name' }
      ]);
      expect(element.shadowRoot.querySelectorAll('[data-id="lookup-field"]')).toHaveLength(1);
    });

    it('shows the load choices instead of the people rules and saves them', async () => {
      const element = await toColumns();
      click(element, 'next');
      await flush();
      expect(element.shadowRoot.querySelector('[data-id="rule"]')).toBeNull();
      expect(element.shadowRoot.querySelector('[data-id="organization-rule"]')).toBeNull();
      const options = element.shadowRoot.querySelector('[data-id="load-options"]');
      expect(options.operation).toBe('Insert');
      options.dispatchEvent(
        new CustomEvent('change', {
          detail: { operation: 'Insert', matchField: '', lookupNotFound: 'Leave it empty' }
        })
      );
      await flush();
      click(element, 'dry-run');
      await flush();
      const sent = createBatch.mock.calls[0][0];
      expect(JSON.parse(sent.mappingDocument).columns).toEqual([
        { source: 'Employer', target: 'Record.Organization__c', lookupField: 'Name' },
        { source: 'Role', target: 'Record.Role__c' }
      ]);
      expect(JSON.parse(sent.optionsJson)).toMatchObject({
        saveLoad: true,
        loadOperation: 'Insert',
        loadMatchField: '',
        lookupNotFound: 'Leave it empty'
      });
    });

    it('will not dry run an update without a Record Id column, or an upsert without its field', async () => {
      const element = await toColumns();
      click(element, 'next');
      await flush();
      const options = element.shadowRoot.querySelector('[data-id="load-options"]');
      options.dispatchEvent(
        new CustomEvent('change', {
          detail: {
            operation: 'Update by record Id',
            matchField: '',
            lookupNotFound: 'Reject the row'
          }
        })
      );
      await flush();
      expect(element.shadowRoot.querySelector('[data-id="dry-run"]').disabled).toBe(true);
      options.dispatchEvent(
        new CustomEvent('change', {
          detail: {
            operation: 'Upsert by external ID',
            matchField: 'Pair_Key__c',
            lookupNotFound: 'Reject the row'
          }
        })
      );
      await flush();
      expect(getKeyFields).toHaveBeenCalledWith({ templateId: 'a09' });
      expect(element.shadowRoot.querySelector('[data-id="dry-run"]').disabled).toBe(true);
      options.dispatchEvent(
        new CustomEvent('change', {
          detail: { operation: 'Insert', matchField: '', lookupNotFound: 'Reject the row' }
        })
      );
      await flush();
      expect(element.shadowRoot.querySelector('[data-id="dry-run"]').disabled).toBe(false);
    });

    it('makes a one-object mapping on the first step and chooses it', async () => {
      getTemplates.mockResolvedValue([TEMPLATE]);
      getLoadableObjects.mockResolvedValue([{ value: 'Affiliation__c', label: 'Affiliation' }]);
      createObjectTemplate.mockResolvedValue(OBJECT_TEMPLATE);
      const element = render();
      await flush();
      click(element, 'choose-object');
      await flush();
      const object = element.shadowRoot.querySelector('[data-id="new-object"]');
      expect(object.options).toEqual([{ label: 'Affiliation', value: 'Affiliation__c' }]);
      expect(element.shadowRoot.querySelector('[data-id="create-object-template"]').disabled).toBe(
        true
      );
      object.dispatchEvent(new CustomEvent('change', { detail: { value: 'Affiliation__c' } }));
      const name = element.shadowRoot.querySelector('[data-id="new-template-name"]');
      name.value = 'Board members';
      name.dispatchEvent(new CustomEvent('change'));
      await flush();
      click(element, 'create-object-template');
      await flush();
      expect(createObjectTemplate).toHaveBeenCalledWith({
        name: 'Board members',
        objectName: 'Affiliation__c'
      });
      expect(element.shadowRoot.querySelector('[data-id="template"]').value).toBe('a09');
    });

    it('says why a one-object mapping could not be made', async () => {
      getLoadableObjects.mockResolvedValue([{ value: 'Affiliation__c', label: 'Affiliation' }]);
      createObjectTemplate.mockRejectedValue({ body: { message: 'Give the mapping a name.' } });
      const element = render();
      await flush();
      click(element, 'choose-object');
      await flush();
      element.shadowRoot
        .querySelector('[data-id="new-object"]')
        .dispatchEvent(new CustomEvent('change', { detail: { value: 'Affiliation__c' } }));
      const name = element.shadowRoot.querySelector('[data-id="new-template-name"]');
      name.value = 'x';
      name.dispatchEvent(new CustomEvent('change'));
      await flush();
      click(element, 'create-object-template');
      await flush();
      expect(element.shadowRoot.textContent).toContain('Give the mapping a name.');
    });
  });
});
