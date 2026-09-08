import { LightningElement } from 'lwc';
import { parseCsv, toRecords, toCsv } from './csv';

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

import cardTitle from '@salesforce/label/c.Core_Import_CardTitle';
import stepTemplate from '@salesforce/label/c.Core_Import_StepTemplate';
import stepUpload from '@salesforce/label/c.Core_Import_StepUpload';
import stepColumns from '@salesforce/label/c.Core_Import_StepColumns';
import stepMatching from '@salesforce/label/c.Core_Import_StepMatching';
import stepPreview from '@salesforce/label/c.Core_Import_StepPreview';
import stepResults from '@salesforce/label/c.Core_Import_StepResults';
import nextButton from '@salesforce/label/c.Core_Import_NextButton';
import backButton from '@salesforce/label/c.Core_Import_BackButton';
import dryRunButton from '@salesforce/label/c.Core_Import_DryRunButton';
import commitButton from '@salesforce/label/c.Core_Import_CommitButton';
import startOverButton from '@salesforce/label/c.Core_Import_StartOverButton';
import downloadExceptionsButton from '@salesforce/label/c.Core_Import_DownloadExceptionsButton';
import uploadLabel from '@salesforce/label/c.Core_Import_UploadLabel';
import uploadHint from '@salesforce/label/c.Core_Import_UploadHint';
import columnHeader from '@salesforce/label/c.Core_Import_ColumnHeader';
import targetHeader from '@salesforce/label/c.Core_Import_TargetHeader';
import sampleHeader from '@salesforce/label/c.Core_Import_SampleHeader';
import doNotLoad from '@salesforce/label/c.Core_Import_DoNotLoad';
import matchingRuleLabel from '@salesforce/label/c.Core_Import_MatchingRuleLabel';
import matchingEmailHelp from '@salesforce/label/c.Core_Import_MatchingEmailHelp';
import matchingNamePostalHelp from '@salesforce/label/c.Core_Import_MatchingNamePostalHelp';
import matchingExternalIdHelp from '@salesforce/label/c.Core_Import_MatchingExternalIdHelp';
import readOnlyMessage from '@salesforce/label/c.Core_Import_ReadOnlyMessage';
import loadingAltText from '@salesforce/label/c.Core_Import_LoadingAltText';
import parsingMessage from '@salesforce/label/c.Core_Import_ParsingMessage';
import noHeaderRow from '@salesforce/label/c.Core_Import_NoHeaderRow';

/** How often the wizard asks how a run is going. */
const POLL_INTERVAL_MS = 3000;
/** How many rows are sent to the server in one request. */
const STAGE_PAGE_SIZE = 500;
/**
 * The largest file kept as a Salesforce File. A bigger file still imports; only the copy of
 * the original is skipped, because sending it would risk the request's heap.
 */
const MAX_STORED_FILE_BYTES = 4000000;
/** How many values of each column the picker shows, so the choice can be checked by eye. */
const SAMPLE_VALUES = 3;

const IGNORE = 'Ignore';

/** What a column can be mapped to. Kept in step with ImportColumnLibrary. */
const TARGETS = [
  { value: 'Contact1.Salutation', label: 'Person: title' },
  { value: 'Contact1.FirstName', label: 'Person: first name' },
  { value: 'Contact1.LastName', label: 'Person: last name' },
  { value: 'Contact1.FullName', label: 'Person: full name in one column' },
  { value: 'Contact1.Email', label: 'Person: email' },
  { value: 'Contact1.Phone', label: 'Person: phone' },
  { value: 'Contact1.Title', label: 'Person: job title' },
  { value: 'Contact1.MailingStreet', label: 'Person: street' },
  { value: 'Contact1.MailingCity', label: 'Person: city' },
  { value: 'Contact1.MailingState', label: 'Person: state or province' },
  { value: 'Contact1.MailingPostalCode', label: 'Person: postal code' },
  { value: 'Contact1.MailingCountry', label: 'Person: country' },
  { value: 'Contact2.FirstName', label: 'Second person: first name' },
  { value: 'Contact2.LastName', label: 'Second person: last name' },
  { value: 'Contact2.FullName', label: 'Second person: full name in one column' },
  { value: 'Contact2.Email', label: 'Second person: email' },
  { value: 'Contact2.Phone', label: 'Second person: phone' },
  { value: 'Household.Name', label: 'Household: name' },
  { value: 'Organization.Name', label: 'Organization: name' },
  { value: 'Organization.Phone', label: 'Organization: phone' },
  { value: 'Organization.Website', label: 'Organization: website' },
  { value: 'Organization.BillingStreet', label: 'Organization: street' },
  { value: 'Organization.BillingCity', label: 'Organization: city' },
  { value: 'Organization.BillingState', label: 'Organization: state or province' },
  { value: 'Organization.BillingPostalCode', label: 'Organization: postal code' },
  { value: 'Organization.BillingCountry', label: 'Organization: country' },
  { value: 'Gift.Amount__c', label: 'Gift: amount (kept with the row, not loaded yet)' },
  { value: 'Gift.Gift_Date__c', label: 'Gift: date (kept with the row, not loaded yet)' },
  { value: 'Gift.Type__c', label: 'Gift: payment method (kept with the row, not loaded yet)' },
  {
    value: 'Gift.Payment_Reference__c',
    label: 'Gift: payment reference (kept with the row, not loaded yet)'
  },
  { value: 'Allocation.Fund', label: 'Gift: fund (kept with the row, not loaded yet)' }
];

const RULES = [
  { value: 'Email exact', help: matchingEmailHelp },
  { value: 'Name plus postal code', help: matchingNamePostalHelp },
  { value: 'External ID', help: matchingExternalIdHelp }
];

/**
 * The import wizard (C-14): choose a mapping, upload a file, check the columns, choose how
 * rows are matched, dry run, commit, and see the result.
 *
 * The file is parsed here rather than on the server and sent up in pages, so a large file
 * never arrives as one request. Nothing is written until the administrator has seen a dry
 * run of the same file with the same mapping, which is the rule the whole screen is built
 * around. See docs/admin-guide/importing.md.
 */
export default class ImportWizard extends LightningElement {
  step = 1;
  loading = true;
  parsing = false;
  permitted = false;
  message;
  templates = [];
  templateId;
  matchingRule = 'Email exact';
  headers = [];
  records = [];
  columns = [];
  batch;
  rejectedRows = [];
  fileName;
  pollTimer;
  storeFileError;

  labels = {
    cardTitle,
    stepTemplate,
    stepUpload,
    stepColumns,
    stepMatching,
    stepPreview,
    stepResults,
    nextButton,
    backButton,
    dryRunButton,
    commitButton,
    startOverButton,
    downloadExceptionsButton,
    uploadLabel,
    uploadHint,
    columnHeader,
    targetHeader,
    sampleHeader,
    matchingRuleLabel,
    readOnlyMessage,
    loadingAltText,
    parsingMessage
  };

  async connectedCallback() {
    try {
      this.permitted = await canImport();
      if (this.permitted) {
        this.templates = await getTemplates();
        if (this.templates.length > 0) {
          this.selectTemplate(this.templates[0].id);
        }
      }
    } catch (error) {
      this.message = this.errorText(error);
    } finally {
      this.loading = false;
    }
  }

  disconnectedCallback() {
    this.stopPolling();
  }

  // ---------------------------------------------------------------------------------------
  // Step one: which mapping
  // ---------------------------------------------------------------------------------------

  get templateOptions() {
    return this.templates.map((template) => ({ label: template.name, value: template.id }));
  }

  get selectedTemplate() {
    return this.templates.find((template) => template.id === this.templateId);
  }

  get templateDescription() {
    return this.selectedTemplate ? this.selectedTemplate.description : '';
  }

  handleTemplateChange(event) {
    this.selectTemplate(event.detail.value);
  }

  selectTemplate(templateId) {
    this.templateId = templateId;
    const template = this.selectedTemplate;
    if (template && template.matchingRule) {
      this.matchingRule = template.matchingRule;
    }
  }

  // ---------------------------------------------------------------------------------------
  // Step two: the file
  // ---------------------------------------------------------------------------------------

  async handleFileChange(event) {
    const file = event.target.files && event.target.files[0];
    if (!file) {
      return;
    }
    this.message = undefined;
    this.parsing = true;
    this.fileName = file.name;
    try {
      const text = await this.readText(file);
      const { headers, records } = toRecords(parseCsv(text));
      if (headers.length === 0 || records.length === 0) {
        this.message = noHeaderRow;
        return;
      }
      this.headers = headers;
      this.records = records;
      await this.buildColumns(file);
      this.step = 3;
    } catch (error) {
      this.message = this.errorText(error);
    } finally {
      this.parsing = false;
    }
  }

  readText(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      reader.onload = () => resolve(reader.result);
      reader.onerror = () => reject(reader.error);
      reader.readAsText(file);
    });
  }

  readBase64(file) {
    return new Promise((resolve, reject) => {
      const reader = new FileReader();
      // A data URL is "data:<type>;base64,<content>"; only the content is sent.
      reader.onload = () => resolve(String(reader.result).split(',')[1]);
      reader.onerror = () => reject(reader.error);
      reader.readAsDataURL(file);
    });
  }

  async buildColumns(file) {
    const suggested = await suggestMapping({ templateId: this.templateId, headers: this.headers });
    const targets = {};
    const parsed = JSON.parse(suggested || '{}');
    (parsed.columns || []).forEach((column) => {
      targets[column.source] = column.target;
    });
    this.columns = this.headers.map((heading) => ({
      key: heading,
      source: heading,
      target: targets[heading] || IGNORE,
      samples: this.records
        .slice(0, SAMPLE_VALUES)
        .map((record) => record[heading])
        .filter((value) => value && value.length > 0)
        .join(', ')
    }));
    this.pendingFile = file;
  }

  // ---------------------------------------------------------------------------------------
  // Step three: the columns
  // ---------------------------------------------------------------------------------------

  get targetOptions() {
    return [{ label: doNotLoad, value: IGNORE }].concat(TARGETS);
  }

  handleTargetChange(event) {
    const source = event.target.dataset.source;
    const target = event.detail.value;
    this.columns = this.columns.map((column) => {
      return column.source === source ? { ...column, target } : column;
    });
  }

  get mappingDocument() {
    return JSON.stringify({
      version: 1,
      columns: this.columns.map((column) => ({ source: column.source, target: column.target })),
      defaults: []
    });
  }

  get mapsSomebody() {
    return this.columns.some((column) =>
      [
        'Contact1.LastName',
        'Contact1.FullName',
        'Contact1.Email',
        'Contact2.LastName',
        'Contact2.FullName',
        'Contact2.Email',
        'Organization.Name'
      ].includes(column.target)
    );
  }

  // ---------------------------------------------------------------------------------------
  // Step four: the matching rule
  // ---------------------------------------------------------------------------------------

  get ruleOptions() {
    return RULES.map((rule) => ({ label: rule.value, value: rule.value }));
  }

  get ruleHelp() {
    const found = RULES.find((rule) => rule.value === this.matchingRule);
    return found ? found.help : '';
  }

  handleRuleChange(event) {
    this.matchingRule = event.detail.value;
  }

  // ---------------------------------------------------------------------------------------
  // Steps five and six: the dry run, the commit, the result
  // ---------------------------------------------------------------------------------------

  async handleDryRun() {
    this.message = undefined;
    this.loading = true;
    try {
      const fileId = await this.storeOriginal();
      this.batch = await createBatch({
        templateId: this.templateId,
        fileId,
        fileName: this.fileName,
        mappingDocument: this.mappingDocument,
        matchingRule: this.matchingRule
      });
      await this.stageAllRows();
      this.batch = await startDryRun({ batchId: this.batch.id });
      this.step = 5;
      this.startPolling();
    } catch (error) {
      this.message = this.errorText(error);
    } finally {
      this.loading = false;
    }
  }

  async storeOriginal() {
    const file = this.pendingFile;
    if (!file || file.size > MAX_STORED_FILE_BYTES) {
      return null;
    }
    try {
      return await saveFile({ fileName: file.name, base64Content: await this.readBase64(file) });
    } catch (storeError) {
      // Keeping a copy of the file is not worth failing an import over: the import goes
      // ahead and the batch simply has no link back to the original.
      this.storeFileError = this.errorText(storeError);
      return null;
    }
  }

  async stageAllRows() {
    for (let start = 0; start < this.records.length; start += STAGE_PAGE_SIZE) {
      const page = this.records.slice(start, start + STAGE_PAGE_SIZE);
      // Sequential on purpose: the row numbers have to arrive in file order.
      // eslint-disable-next-line no-await-in-loop
      await stageRows({
        batchId: this.batch.id,
        rowsJson: JSON.stringify(page),
        firstRowNumber: start + 2
      });
    }
  }

  async handleCommit() {
    this.message = undefined;
    this.loading = true;
    try {
      this.batch = await startCommit({ batchId: this.batch.id });
      this.step = 6;
      this.startPolling();
    } catch (error) {
      this.message = this.errorText(error);
    } finally {
      this.loading = false;
    }
  }

  startPolling() {
    this.stopPolling();
    this.pollTimer = setInterval(() => this.refresh(), POLL_INTERVAL_MS);
  }

  stopPolling() {
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = undefined;
    }
  }

  async refresh() {
    if (!this.batch) {
      return;
    }
    try {
      this.batch = await getBatch({ batchId: this.batch.id });
      if (this.batch && this.batch.isFinished) {
        this.stopPolling();
        this.rejectedRows = await getRows({
          batchId: this.batch.id,
          status: 'Rejected',
          offsetRows: 0
        });
      }
    } catch (error) {
      this.stopPolling();
      this.message = this.errorText(error);
    }
  }

  /**
   * Hands the rejected rows back as a CSV the administrator can fix in a spreadsheet, with
   * the reason on each one so the fix is obvious.
   */
  handleDownloadExceptions() {
    const headers = ['Row'].concat(this.headers).concat(['Reason']);
    const records = this.rejectedRows.map((row) => {
      const values = row.values ? JSON.parse(row.values) : {};
      const record = { Row: row.rowNumber, Reason: row.errorMessage };
      this.headers.forEach((heading) => {
        record[heading] = values[heading] || '';
      });
      return record;
    });
    const text = toCsv(headers, records);
    const link = document.createElement('a');
    link.href = `data:text/csv;charset=utf-8,${encodeURIComponent(text)}`;
    link.download = `${this.batch ? this.batch.name : 'import'}-exceptions.csv`;
    link.click();
  }

  handleStartOver() {
    this.stopPolling();
    this.step = 1;
    this.batch = undefined;
    this.rejectedRows = [];
    this.headers = [];
    this.records = [];
    this.columns = [];
    this.fileName = undefined;
    this.pendingFile = undefined;
    this.message = undefined;
  }

  // ---------------------------------------------------------------------------------------
  // Navigation
  // ---------------------------------------------------------------------------------------

  handleNext() {
    this.message = undefined;
    this.step = Math.min(this.step + 1, 6);
  }

  handleBack() {
    this.message = undefined;
    this.step = Math.max(this.step - 1, 1);
  }

  get isStepTemplate() {
    return this.step === 1;
  }

  get isStepUpload() {
    return this.step === 2;
  }

  get isStepColumns() {
    return this.step === 3;
  }

  get isStepMatching() {
    return this.step === 4;
  }

  get isStepPreview() {
    return this.step === 5;
  }

  get isStepResults() {
    return this.step === 6;
  }

  get showResults() {
    return this.step >= 5;
  }

  get canGoBack() {
    return this.step > 1 && this.step < 5;
  }

  get cannotLeaveTemplateStep() {
    return !this.templateId;
  }

  get showReadOnlyNotice() {
    return !this.loading && !this.permitted;
  }

  get cannotDryRun() {
    return !this.mapsSomebody || this.records.length === 0;
  }

  get cannotCommit() {
    return !this.batch || this.batch.status !== 'Dry run complete';
  }

  get hasMessage() {
    return Boolean(this.message);
  }

  get showWizard() {
    return this.permitted && !this.loading;
  }

  errorText(error) {
    if (!error) {
      return '';
    }
    if (error.body && error.body.message) {
      return error.body.message;
    }
    return error.message || String(error);
  }
}
