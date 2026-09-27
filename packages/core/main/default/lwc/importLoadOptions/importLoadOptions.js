import { LightningElement, api } from 'lwc';

import operationLabel from '@salesforce/label/c.Core_Import_LoadOperationLabel';
import insertOption from '@salesforce/label/c.Core_Import_OperationInsert';
import updateOption from '@salesforce/label/c.Core_Import_OperationUpdate';
import upsertOption from '@salesforce/label/c.Core_Import_OperationUpsert';
import insertHelp from '@salesforce/label/c.Core_Import_LoadInsertHelp';
import updateHelp from '@salesforce/label/c.Core_Import_LoadUpdateHelp';
import upsertHelp from '@salesforce/label/c.Core_Import_LoadUpsertHelp';
import matchFieldLabel from '@salesforce/label/c.Core_Import_LoadMatchFieldLabel';
import notFoundLabel from '@salesforce/label/c.Core_Import_LookupNotFoundLabel';
import rejectOption from '@salesforce/label/c.Core_Import_LookupRejectOption';
import leaveEmptyOption from '@salesforce/label/c.Core_Import_LookupLeaveEmptyOption';
import rejectHelp from '@salesforce/label/c.Core_Import_LookupRejectHelp';
import leaveEmptyHelp from '@salesforce/label/c.Core_Import_LookupLeaveEmptyHelp';

export const INSERT = 'Insert';
export const UPDATE = 'Update by record Id';
export const UPSERT = 'Upsert by external ID';
export const LOOKUP_REJECT = 'Reject the row';
export const LOOKUP_LEAVE_EMPTY = 'Leave it empty';

/**
 * What a mapping that loads one object does with each row (canonical model R-IT10, R-IT11):
 * insert, update by record Id, or upsert by an external ID field, with the sentence each choice
 * risks, the field an upsert matches on, and what a row does when a lookup finds no record.
 * Presentational: the wizard owns the values and hears every change through a `change` event
 * whose detail is `{ operation, matchField, lookupNotFound }`.
 * See docs/admin-guide/importing.md, section 6A.
 */
export default class ImportLoadOptions extends LightningElement {
  @api operation = INSERT;
  @api matchField = '';
  @api lookupNotFound = LOOKUP_REJECT;
  /** The object's external ID fields an upsert can match on: `{ label, value }`. */
  @api keyFields = [];

  labels = { operationLabel, matchFieldLabel, notFoundLabel };

  get operationOptions() {
    return [
      { label: insertOption, value: INSERT },
      { label: updateOption, value: UPDATE },
      { label: upsertOption, value: UPSERT }
    ];
  }

  get operationHelp() {
    if (this.operation === UPDATE) {
      return updateHelp;
    }
    return this.operation === UPSERT ? upsertHelp : insertHelp;
  }

  get isUpsert() {
    return this.operation === UPSERT;
  }

  get keyFieldOptions() {
    return (this.keyFields || []).map((field) => ({ label: field.label, value: field.value }));
  }

  get notFoundOptions() {
    return [
      { label: rejectOption, value: LOOKUP_REJECT },
      { label: leaveEmptyOption, value: LOOKUP_LEAVE_EMPTY }
    ];
  }

  get notFoundHelp() {
    return this.lookupNotFound === LOOKUP_LEAVE_EMPTY ? leaveEmptyHelp : rejectHelp;
  }

  handleOperationChange(event) {
    this.announce({ operation: event.detail.value });
  }

  handleMatchFieldChange(event) {
    this.announce({ matchField: event.detail.value });
  }

  handleNotFoundChange(event) {
    this.announce({ lookupNotFound: event.detail.value });
  }

  announce(change) {
    const detail = {
      operation: this.operation,
      matchField: this.matchField,
      lookupNotFound: this.lookupNotFound,
      ...change
    };
    this.dispatchEvent(new CustomEvent('change', { detail }));
  }
}
