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
jest.mock('@salesforce/apex/ImportController.getRows', () => ({ default: jest.fn() }), {
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
async function chooseFile(element, text = FILE_TEXT) {
  const input = element.shadowRoot.querySelector('[data-id="file"]');
  const file = new File([text], 'donors.csv', { type: 'text/csv' });
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
});
