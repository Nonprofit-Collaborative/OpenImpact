import { LightningElement, api } from 'lwc';
import describeObject from '@salesforce/apex/FindController.describeObject';

import placeholder from '@salesforce/label/c.Core_Find_PickerPlaceholder';
import fieldOn from '@salesforce/label/c.Core_Find_PickerFieldOn';
import relationshipOption from '@salesforce/label/c.Core_Find_PickerRelationship';

const RELATIONSHIP_PREFIX = 'rel:';
/** A path follows at most two lookups (canonical model R-Q1). */
const MAX_DEPTH = 2;

/**
 * Picks one field of an object, or of a record it looks up, up to two lookups away, and says
 * which one with a `fieldchange` event carrying { path, label, type, picklistValues }.
 *
 * Every name it offers comes from the server's describe of the running user's access; the server
 * checks the path again when the query is compiled, so this is a convenience, not a guard.
 * See docs/admin-guide/find.md, section 3.
 */
export default class QueryFieldPicker extends LightningElement {
  @api label;
  /** Offer only fields a filter may use. */
  @api filterableOnly = false;
  /** Offer only fields a sort may use. */
  @api sortableOnly = false;
  /** Offer only fields that can be a column. */
  @api showableOnly = false;

  levels = [];
  error;
  _objectName;

  @api
  get objectName() {
    return this._objectName;
  }

  set objectName(value) {
    if (value !== this._objectName) {
      this._objectName = value;
      this.levels = [];
      if (value) {
        this.loadLevel(0, value, []);
      }
    }
  }

  /** Clears the choice, keeping the first list. */
  @api
  reset() {
    this.levels = this.levels.slice(0, 1).map((level) => ({ ...level, value: undefined }));
  }

  get placeholder() {
    return placeholder;
  }

  async loadLevel(index, objectName, trail) {
    try {
      const description = await describeObject({ objectName });
      const level = {
        key: `${index}-${objectName}`,
        index,
        trail,
        label: index === 0 ? this.label : fieldOn.replace('{0}', trail[trail.length - 1].label),
        options: this.optionsFor(description, index),
        fields: description.fields,
        value: undefined
      };
      this.levels = [...this.levels.slice(0, index), level];
      this.error = undefined;
    } catch (error) {
      this.error = (error && error.body && error.body.message) || String(error);
    }
  }

  optionsFor(description, index) {
    const options = [];
    for (const field of description.fields || []) {
      if (this.offers(field)) {
        options.push({ label: field.label, value: field.name });
      }
      if (field.relationshipName && index < MAX_DEPTH) {
        options.push({
          label: relationshipOption.replace('{0}', field.relationshipLabel),
          value: RELATIONSHIP_PREFIX + field.name
        });
      }
    }
    return options;
  }

  offers(field) {
    if (this.filterableOnly && !field.filterable) {
      return false;
    }
    if (this.sortableOnly && !field.sortable) {
      return false;
    }
    if (this.showableOnly && !field.showable) {
      return false;
    }
    return true;
  }

  handleChange(event) {
    const index = Number(event.target.dataset.index);
    const value = event.detail.value;
    const level = this.levels[index];
    this.levels = this.levels
      .slice(0, index + 1)
      .map((entry, i) => (i === index ? { ...entry, value } : entry));
    if (value.startsWith(RELATIONSHIP_PREFIX)) {
      const field = level.fields.find((f) => f.name === value.slice(RELATIONSHIP_PREFIX.length));
      const trail = [
        ...level.trail,
        { relationshipName: field.relationshipName, label: field.relationshipLabel }
      ];
      this.loadLevel(index + 1, field.referenceTo, trail);
      return;
    }
    const field = level.fields.find((f) => f.name === value);
    const path = [...level.trail.map((step) => step.relationshipName), field.name].join('.');
    const label = [...level.trail.map((step) => step.label), field.label].join(' > ');
    this.dispatchEvent(
      new CustomEvent('fieldchange', {
        detail: { path, label, type: field.type, picklistValues: field.picklistValues || [] }
      })
    );
  }
}
