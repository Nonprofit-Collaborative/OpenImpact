import { LightningElement, api } from 'lwc';

import heading from '@salesforce/label/c.Core_Import_FileValuesHeading';
import help from '@salesforce/label/c.Core_Import_FileValuesHelp';
import targetLabel from '@salesforce/label/c.Core_Import_FileValueTargetLabel';
import valueLabel from '@salesforce/label/c.Core_Import_FileValueLabel';
import addButton from '@salesforce/label/c.Core_Import_FileValueAddButton';
import removeButton from '@salesforce/label/c.Core_Import_FileValueRemoveButton';

/** The most values one file may be given, kept in step with ImportMapping.MAX_FILE_VALUES. */
const MAX_VALUES = 50;

/**
 * The values given for every row of one file (canonical model R-IB14), such as the appeal every
 * gift in it answers. Each is a target from the same list as the column picker and a value. A
 * row's own value wins over these; they belong to this file only and are not saved with the
 * mapping. Presentational: the wizard owns the list and hears every change through a `change`
 * event whose detail is `{ values: [{ target, value }] }`.
 * See docs/admin-guide/importing.md, section 4B.
 */
export default class ImportFileValues extends LightningElement {
  /** What a value can be for: `{ label, value }`, the column picker's targets. */
  @api options = [];

  /** The values so far, as `{ target, value }`. */
  @api
  get values() {
    return this.rows.map((row) => ({ target: row.target, value: row.value }));
  }
  set values(given) {
    this.rows = (given || []).map((row, index) => ({
      key: `value-${index}`,
      target: row.target,
      value: row.value
    }));
    this.nextKey = this.rows.length;
  }

  rows = [];
  nextKey = 0;

  labels = { heading, help, targetLabel, valueLabel, addButton, removeButton };

  get hasRows() {
    return this.rows.length > 0;
  }

  get cannotAdd() {
    return this.rows.length >= MAX_VALUES;
  }

  handleAdd() {
    this.rows = this.rows.concat([{ key: `value-${this.nextKey}`, target: undefined, value: '' }]);
    this.nextKey += 1;
    this.announce();
  }

  handleRemove(event) {
    const key = event.target.dataset.key;
    this.rows = this.rows.filter((row) => row.key !== key);
    this.announce();
  }

  handleTargetChange(event) {
    this.update(event.target.dataset.key, { target: event.detail.value });
  }

  handleValueChange(event) {
    this.update(event.target.dataset.key, { value: event.target.value });
  }

  update(key, change) {
    this.rows = this.rows.map((row) => (row.key === key ? { ...row, ...change } : row));
    this.announce();
  }

  announce() {
    this.dispatchEvent(new CustomEvent('change', { detail: { values: this.values } }));
  }
}
