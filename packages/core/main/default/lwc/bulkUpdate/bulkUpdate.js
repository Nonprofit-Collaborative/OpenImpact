import { LightningElement } from 'lwc';
import getContext from '@salesforce/apex/BulkUpdateController.getContext';
import getSavedQueries from '@salesforce/apex/BulkUpdateController.getSavedQueries';
import openQuery from '@salesforce/apex/BulkUpdateController.openQuery';
import describeQuery from '@salesforce/apex/BulkUpdateController.describeQuery';
import previewUpdate from '@salesforce/apex/BulkUpdateController.preview';
import startUpdate from '@salesforce/apex/BulkUpdateController.start';
import getRecentJobs from '@salesforce/apex/BulkUpdateController.getRecentJobs';
import previewUndo from '@salesforce/apex/BulkUpdateController.previewUndo';
import startUndo from '@salesforce/apex/BulkUpdateController.startUndo';
import { HANDOFF_KEY } from 'c/findCsv';

import noPermission from '@salesforce/label/c.Core_BulkUpdate_ErrorNoPermission';
import heading from '@salesforce/label/c.Core_BulkUpdate_Heading';
import chooseHeading from '@salesforce/label/c.Core_BulkUpdate_ChooseHeading';
import noQuery from '@salesforce/label/c.Core_BulkUpdate_NoQuery';
import objectLine from '@salesforce/label/c.Core_BulkUpdate_ObjectLine';
import changesHeading from '@salesforce/label/c.Core_BulkUpdate_ChangesHeading';
import addChange from '@salesforce/label/c.Core_BulkUpdate_AddChange';
import actionLabel from '@salesforce/label/c.Core_BulkUpdate_ActionLabel';
import actionSet from '@salesforce/label/c.Core_BulkUpdate_ActionSet';
import actionClear from '@salesforce/label/c.Core_BulkUpdate_ActionClear';
import actionCopy from '@salesforce/label/c.Core_BulkUpdate_ActionCopy';
import newValue from '@salesforce/label/c.Core_BulkUpdate_NewValueLabel';
import copyFrom from '@salesforce/label/c.Core_BulkUpdate_CopyFromLabel';
import previewButton from '@salesforce/label/c.Core_BulkUpdate_PreviewButton';
import previewCount from '@salesforce/label/c.Core_BulkUpdate_PreviewCount';
import recordLabel from '@salesforce/label/c.Core_BulkUpdate_RecordLabel';
import beforeLabel from '@salesforce/label/c.Core_BulkUpdate_BeforeLabel';
import afterLabel from '@salesforce/label/c.Core_BulkUpdate_AfterLabel';
import confirmLabel from '@salesforce/label/c.Core_BulkUpdate_ConfirmLabel';
import updateButton from '@salesforce/label/c.Core_BulkUpdate_UpdateButton';
import started from '@salesforce/label/c.Core_BulkUpdate_Started';
import recentHeading from '@salesforce/label/c.Core_BulkUpdate_RecentHeading';
import recentEmpty from '@salesforce/label/c.Core_BulkUpdate_RecentEmpty';
import jobSummary from '@salesforce/label/c.Core_BulkUpdate_JobSummary';
import refreshButton from '@salesforce/label/c.Core_BulkUpdate_RefreshButton';
import undoConfirmHeading from '@salesforce/label/c.Core_BulkUpdate_UndoConfirmHeading';
import undoConfirmCount from '@salesforce/label/c.Core_BulkUpdate_UndoConfirmCount';
import undoConfirmButton from '@salesforce/label/c.Core_BulkUpdate_UndoConfirmButton';
import undoStarted from '@salesforce/label/c.Core_BulkUpdate_UndoStarted';
import undoButton from '@salesforce/label/c.Core_Import_UndoButton';
import undoUntil from '@salesforce/label/c.Core_Import_HistoryUndoUntil';
import openSaved from '@salesforce/label/c.Core_Find_OpenSavedLabel';
import sharedBy from '@salesforce/label/c.Core_Find_SharedBy';
import queryLabel from '@salesforce/label/c.Core_Find_QueryLabel';
import fieldLabel from '@salesforce/label/c.Core_Find_FieldLabel';
import cancel from '@salesforce/label/c.Core_Find_CancelButton';
import remove from '@salesforce/label/c.Core_Find_RemoveButton';
import yes from '@salesforce/label/c.Core_Find_Yes';
import no from '@salesforce/label/c.Core_Find_No';
import loadingAltText from '@salesforce/label/c.Core_Find_LoadingAltText';

const NUMBER_TYPES = ['integer', 'long', 'double', 'currency', 'percent'];

/**
 * Bulk update (C-35): up to five changes to every record a Find query returns, previewed,
 * confirmed by typing the count, run in the background, and undone. See
 * docs/admin-guide/bulk-update.md.
 *
 * The page sends the query document and the changes; the server checks both as the person,
 * counts again before it starts, and refuses when more records match than were confirmed.
 */
export default class BulkUpdate extends LightningElement {
  labels = {
    noPermission,
    heading,
    chooseHeading,
    noQuery,
    changesHeading,
    addChange,
    actionLabel,
    newValue,
    copyFrom,
    previewButton,
    recordLabel,
    beforeLabel,
    afterLabel,
    confirmLabel,
    recentHeading,
    recentEmpty,
    refreshButton,
    undoButton,
    undoUntil,
    undoConfirmButton,
    openSaved,
    queryLabel,
    fieldLabel,
    cancel,
    remove,
    loadingAltText
  };

  context;
  loading = true;
  working = false;
  error;
  notice;

  savedQueries = [];
  savedId;
  documentJson;
  query;
  changes = [];
  preview;
  confirmText = '';

  jobs = [];
  undoing;
  undoPreview;
  nextKey = 1;

  async connectedCallback() {
    try {
      this.context = await getContext();
      if (!this.canUse) {
        return;
      }
      const handed = takeHandoff();
      const [saved] = await Promise.all([getSavedQueries(), this.loadJobs()]);
      this.savedQueries = saved || [];
      if (handed) {
        await this.loadDocument(handed);
      }
    } catch (error) {
      this.error = errorText(error);
    } finally {
      this.loading = false;
    }
  }

  get canUse() {
    return Boolean(this.context && this.context.canUse);
  }

  get cannotUse() {
    return !this.loading && !this.canUse;
  }

  get hasQuery() {
    return Boolean(this.query);
  }

  get objectLine() {
    return this.query ? objectLine.replace('{0}', this.query.objectLabel) : '';
  }

  get savedOptions() {
    return this.savedQueries.map((query) => ({
      label: query.isOwn
        ? query.name
        : sharedBy.replace('{0}', query.name).replace('{1}', query.ownerName || ''),
      value: query.id
    }));
  }

  get targetOptions() {
    return ((this.query && this.query.targets) || []).map((t) => ({
      label: t.label,
      value: t.name
    }));
  }

  get changeRows() {
    return this.changes.map((change) => {
      const target = this.targetFor(change.field);
      const type = target ? target.type : undefined;
      const isSet = change.action === 'set';
      const picklist = target && target.picklistValues && target.picklistValues.length > 0;
      return {
        ...change,
        hasField: Boolean(target),
        actionOptions: [
          { label: actionSet, value: 'set' },
          ...(target && target.nillable ? [{ label: actionClear, value: 'clear' }] : []),
          ...(target && target.sources.length > 0 ? [{ label: actionCopy, value: 'copy' }] : [])
        ],
        isBoolean: isSet && type === 'boolean',
        isPicklist: isSet && type === 'picklist' && picklist,
        isInput: isSet && type !== 'boolean' && !(type === 'picklist' && picklist),
        inputType: inputType(type),
        isCopy: change.action === 'copy',
        sourceOptions: target ? target.sources : [],
        picklistValues: target ? target.picklistValues : [],
        booleanOptions: [
          { label: yes, value: 'true' },
          { label: no, value: 'false' }
        ]
      };
    });
  }

  get cannotAddChange() {
    return (
      !this.hasQuery || this.changes.length >= ((this.context && this.context.maxChanges) || 5)
    );
  }

  get cannotPreview() {
    return !this.hasQuery || this.working || !this.changes.some((c) => c.field);
  }

  get previewCount() {
    return this.preview ? previewCount.replace('{0}', this.preview.count) : '';
  }

  get sampleRows() {
    if (!this.preview) {
      return [];
    }
    const rows = [];
    for (const record of this.preview.sample || []) {
      for (const change of record.changes) {
        rows.push({
          key: `${record.id}-${change.field}`,
          name: record.name,
          label: change.label,
          before: shown(change.before),
          after: shown(change.after)
        });
      }
    }
    return rows;
  }

  get updateLabel() {
    return this.preview ? updateButton.replace('{0}', this.preview.count) : '';
  }

  get cannotStart() {
    return (
      !this.preview ||
      this.working ||
      String(this.confirmText).trim() !== String(this.preview.count)
    );
  }

  get hasJobs() {
    return this.jobs.length > 0;
  }

  get jobRows() {
    return this.jobs.map((job) => ({
      ...job,
      summary: jobSummary
        .replace('{0}', job.matched)
        .replace('{1}', job.updated)
        .replace('{2}', job.unchanged)
        .replace('{3}', job.failed),
      showDeadline: Boolean(job.canUndo && job.undoDeadline)
    }));
  }

  get undoTitle() {
    return this.undoing ? undoConfirmHeading.replace('{0}', this.undoing.name) : '';
  }

  get undoCount() {
    return this.undoPreview ? undoConfirmCount.replace('{0}', this.undoPreview.updates || 0) : '';
  }

  get cannotConfirmUndo() {
    return !(this.undoPreview && this.undoPreview.allowed) || this.working;
  }

  targetFor(name) {
    return name && this.query ? this.query.targets.find((t) => t.name === name) : undefined;
  }

  // ---------------------------------------------------------------------------------------

  async handleOpenSaved(event) {
    this.error = undefined;
    this.savedId = event.detail.value;
    try {
      const saved = await openQuery({ queryId: this.savedId });
      await this.loadDocument(saved.document);
    } catch (error) {
      this.error = errorText(error);
    }
  }

  async loadDocument(documentJson) {
    this.documentJson = documentJson;
    this.preview = undefined;
    this.confirmText = '';
    try {
      this.query = await describeQuery({ documentJson });
      this.changes = [this.newChange()];
    } catch (error) {
      this.query = undefined;
      this.error = errorText(error);
    }
  }

  newChange() {
    const key = this.nextKey;
    this.nextKey += 1;
    return { key, field: undefined, action: 'set', value: '', source: undefined };
  }

  handleAddChange() {
    this.changes = [...this.changes, this.newChange()];
    this.invalidate();
  }

  handleRemoveChange(event) {
    const key = event.currentTarget.dataset.key;
    this.changes = this.changes.filter((c) => String(c.key) !== key);
    this.invalidate();
  }

  handleChangeEdit(event) {
    const key = event.currentTarget.dataset.key;
    const part = event.currentTarget.dataset.part;
    const value = event.detail.value;
    this.changes = this.changes.map((change) => {
      if (String(change.key) !== key) {
        return change;
      }
      if (part === 'field') {
        return { ...change, field: value, action: 'set', value: '', source: undefined };
      }
      return { ...change, [part]: value };
    });
    this.invalidate();
  }

  handleConfirmText(event) {
    this.confirmText = event.detail.value;
  }

  invalidate() {
    this.preview = undefined;
    this.confirmText = '';
  }

  changesJson() {
    return JSON.stringify(
      this.changes
        .filter((c) => c.field)
        .map((c) => {
          const entry = { field: c.field, action: c.action };
          if (c.action === 'set') {
            entry.value = c.value;
          }
          if (c.action === 'copy') {
            entry.source = c.source;
          }
          return entry;
        })
    );
  }

  async handlePreview() {
    this.working = true;
    this.error = undefined;
    this.notice = undefined;
    try {
      this.preview = await previewUpdate({
        documentJson: this.documentJson,
        changesJson: this.changesJson()
      });
      this.confirmText = '';
    } catch (error) {
      this.preview = undefined;
      this.error = errorText(error);
    } finally {
      this.working = false;
    }
  }

  async handleStart() {
    this.working = true;
    this.error = undefined;
    try {
      const job = await startUpdate({
        documentJson: this.documentJson,
        changesJson: this.changesJson(),
        confirmedCount: this.preview.count
      });
      this.notice = started.replace('{0}', job.name || '');
      this.invalidate();
      await this.loadJobs();
    } catch (error) {
      this.error = errorText(error);
    } finally {
      this.working = false;
    }
  }

  async loadJobs() {
    this.jobs = (await getRecentJobs()) || [];
  }

  async handleRefresh() {
    try {
      await this.loadJobs();
    } catch (error) {
      this.error = errorText(error);
    }
  }

  async handleUndo(event) {
    const jobId = event.target.dataset.id;
    this.error = undefined;
    this.notice = undefined;
    this.working = true;
    try {
      this.undoing = this.jobs.find((job) => job.id === jobId);
      this.undoPreview = await previewUndo({ jobId });
      if (this.undoPreview && !this.undoPreview.allowed) {
        this.error = this.undoPreview.reason;
      }
    } catch (error) {
      this.error = errorText(error);
    } finally {
      this.working = false;
    }
  }

  handleUndoCancel() {
    this.undoing = undefined;
    this.undoPreview = undefined;
    this.error = undefined;
  }

  async handleUndoConfirm() {
    this.working = true;
    this.error = undefined;
    try {
      await startUndo({ jobId: this.undoing.id, confirmedTotal: this.undoPreview.total });
      this.notice = undoStarted;
      this.undoing = undefined;
      this.undoPreview = undefined;
      await this.loadJobs();
    } catch (error) {
      this.error = errorText(error);
    } finally {
      this.working = false;
    }
  }
}

/** The query Find handed over, read once and removed, or undefined. */
function takeHandoff() {
  try {
    const handed = window.sessionStorage.getItem(HANDOFF_KEY);
    window.sessionStorage.removeItem(HANDOFF_KEY);
    return handed || undefined;
  } catch {
    return undefined;
  }
}

function inputType(type) {
  if (NUMBER_TYPES.includes(type)) {
    return 'number';
  }
  if (type === 'date') {
    return 'date';
  }
  if (type === 'datetime') {
    return 'datetime';
  }
  return 'text';
}

function shown(value) {
  return value === null || value === undefined ? '' : String(value);
}

function errorText(error) {
  if (error && error.body && error.body.message) {
    return error.body.message;
  }
  return error && error.message ? error.message : String(error);
}
