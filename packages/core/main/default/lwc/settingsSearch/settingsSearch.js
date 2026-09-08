import { LightningElement } from 'lwc';
import search from '@salesforce/apex/SettingsController.search';
import INPUT_LABEL from '@salesforce/label/c.Core_SettingsSearch_InputLabel';
import PLACEHOLDER from '@salesforce/label/c.Core_SettingsSearch_Placeholder';
import RESULTS_HEADING from '@salesforce/label/c.Core_SettingsSearch_ResultsHeading';
import NO_RESULTS from '@salesforce/label/c.Core_SettingsSearch_NoResultsMessage';

const DEBOUNCE_MS = 300;

export default class SettingsSearch extends LightningElement {
  labels = {
    inputLabel: INPUT_LABEL,
    placeholder: PLACEHOLDER,
    resultsHeading: RESULTS_HEADING,
    noResults: NO_RESULTS
  };

  results = [];
  searched = false;
  timer;

  disconnectedCallback() {
    this.clearTimer();
  }

  get hasResults() {
    return this.results.length > 0;
  }

  get showNoResults() {
    return this.searched && this.results.length === 0;
  }

  handleInput(event) {
    const term = event.target.value;
    this.clearTimer();
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.timer = setTimeout(() => {
      this.runSearch(term);
    }, DEBOUNCE_MS);
  }

  async runSearch(term) {
    if (!term || term.trim().length === 0) {
      this.results = [];
      this.searched = false;
      return;
    }
    try {
      const hits = await search({ term });
      this.results = (hits || []).map((hit, index) => ({
        ...hit,
        rowId: `${hit.section}-${hit.key}-${index}`
      }));
    } catch {
      this.results = [];
    }
    this.searched = true;
  }

  handleSelect(event) {
    const section = event.currentTarget.dataset.section;
    const key = event.currentTarget.dataset.key;
    this.dispatchEvent(new CustomEvent('settingselect', { detail: { section, key } }));
  }

  clearTimer() {
    if (this.timer) {
      clearTimeout(this.timer);
      this.timer = undefined;
    }
  }
}
