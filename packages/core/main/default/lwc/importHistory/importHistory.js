import { LightningElement } from 'lwc';
import getRecentBatches from '@salesforce/apex/ImportController.getRecentBatches';
import previewUndo from '@salesforce/apex/ImportController.previewUndo';
import startUndo from '@salesforce/apex/ImportController.startUndo';

import heading from '@salesforce/label/c.Core_Import_HistoryHeading';
import empty from '@salesforce/label/c.Core_Import_HistoryEmpty';
import undoUntil from '@salesforce/label/c.Core_Import_HistoryUndoUntil';
import undoButton from '@salesforce/label/c.Core_Import_UndoButton';
import confirmHeading from '@salesforce/label/c.Core_Import_UndoConfirmHeading';
import confirmPeople from '@salesforce/label/c.Core_Import_UndoConfirmPeople';
import confirmHouseholds from '@salesforce/label/c.Core_Import_UndoConfirmHouseholds';
import confirmOrganizations from '@salesforce/label/c.Core_Import_UndoConfirmOrganizations';
import confirmUpdates from '@salesforce/label/c.Core_Import_UndoConfirmUpdates';
import confirmButton from '@salesforce/label/c.Core_Import_UndoConfirmButton';
import cancelButton from '@salesforce/label/c.Core_Import_UndoCancelButton';
import started from '@salesforce/label/c.Core_Import_UndoStarted';
import loadingAltText from '@salesforce/label/c.Core_Import_LoadingAltText';

const HOW_MANY = 10;

/**
 * Recent imports, and the undo of one of them (canonical model R-IB8).
 *
 * Undo is two steps on purpose: the first asks the server what it would remove and put back
 * and shows those numbers; only the second deletes anything, and it sends back the total that
 * was shown, so the server refuses if the set has changed since. Every refusal is the
 * server's own sentence, shown as it is.
 * See docs/admin-guide/importing.md, section 5.
 */
export default class ImportHistory extends LightningElement {
  batches = [];
  loading = true;
  working = false;
  error;
  notice;
  /** The batch being confirmed, and what its undo would do. */
  confirming;
  preview;

  labels = {
    heading,
    empty,
    undoUntil,
    undoButton,
    confirmButton,
    cancelButton,
    loadingAltText
  };

  connectedCallback() {
    this.load();
  }

  async load() {
    this.loading = true;
    try {
      this.batches = (await getRecentBatches({ howMany: HOW_MANY })) || [];
    } catch (error) {
      this.error = errorText(error);
    } finally {
      this.loading = false;
    }
  }

  get hasBatches() {
    return this.batches.length > 0;
  }

  get rows() {
    return this.batches.map((batch) => ({
      ...batch,
      showDeadline: Boolean(batch.canUndo && batch.undoDeadline)
    }));
  }

  get confirmTitle() {
    return this.confirming ? format(confirmHeading, this.confirming.name) : '';
  }

  get previewCounts() {
    const view = this.preview || {};
    return [
      { key: 'people', label: confirmPeople, value: view.people || 0 },
      { key: 'households', label: confirmHouseholds, value: view.households || 0 },
      { key: 'organizations', label: confirmOrganizations, value: view.organizations || 0 },
      { key: 'updates', label: confirmUpdates, value: view.updates || 0 }
    ];
  }

  get canConfirm() {
    return Boolean(this.preview && this.preview.allowed) && !this.working;
  }

  get cannotConfirm() {
    return !this.canConfirm;
  }

  async handleUndo(event) {
    const batchId = event.target.dataset.id;
    this.error = undefined;
    this.notice = undefined;
    this.working = true;
    try {
      this.confirming = this.batches.find((batch) => batch.id === batchId);
      this.preview = await previewUndo({ batchId });
      if (this.preview && !this.preview.allowed) {
        this.error = this.preview.reason;
      }
    } catch (error) {
      this.error = errorText(error);
    } finally {
      this.working = false;
    }
  }

  handleCancel() {
    this.confirming = undefined;
    this.preview = undefined;
    this.error = undefined;
  }

  async handleConfirm() {
    this.working = true;
    this.error = undefined;
    try {
      await startUndo({ batchId: this.confirming.id, confirmedTotal: this.preview.total });
      this.notice = started;
      this.confirming = undefined;
      this.preview = undefined;
      await this.load();
    } catch (error) {
      this.error = errorText(error);
    } finally {
      this.working = false;
    }
  }
}

function format(template, value) {
  return template.replace('{0}', value);
}

function errorText(error) {
  if (!error) {
    return '';
  }
  if (error.body && error.body.message) {
    return error.body.message;
  }
  return error.message || String(error);
}
