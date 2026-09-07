import { LightningElement, api } from 'lwc';
import HEADING from '@salesforce/label/c.Core_SetupAssistant_Heading';
import MARK_DONE from '@salesforce/label/c.Core_SetupAssistant_MarkDoneButton';
import MARK_NOT_DONE from '@salesforce/label/c.Core_SetupAssistant_MarkNotDoneButton';
import OPEN_BUTTON from '@salesforce/label/c.Core_SetupAssistant_OpenButton';
import DONE_BADGE from '@salesforce/label/c.Core_SetupAssistant_DoneBadge';
import TODO_BADGE from '@salesforce/label/c.Core_SetupAssistant_ToDoBadge';
import ALL_DONE from '@salesforce/label/c.Core_SetupAssistant_AllDoneMessage';
import PROGRESS_LABEL from '@salesforce/label/c.Core_SetupAssistant_ProgressLabel';

const SETTINGS_PAGE = '/lightning/n/Nonprofit_Settings';

export default class SetupAssistant extends LightningElement {
  @api steps = [];
  @api completed = 0;
  @api total = 0;
  @api canEdit = false;

  labels = {
    heading: HEADING,
    markDone: MARK_DONE,
    markNotDone: MARK_NOT_DONE,
    open: OPEN_BUTTON,
    done: DONE_BADGE,
    todo: TODO_BADGE,
    allDone: ALL_DONE,
    progress: PROGRESS_LABEL
  };

  get rows() {
    return (this.steps || []).map((step) => ({
      ...step,
      badge: step.completed ? this.labels.done : this.labels.todo,
      badgeClass: step.completed
        ? 'slds-badge slds-theme_success'
        : 'slds-badge slds-badge_inverse',
      toggleLabel: step.completed ? this.labels.markNotDone : this.labels.markDone,
      openUrl: this.urlFor(step)
    }));
  }

  get progressText() {
    return `${this.completed} of ${this.total}`;
  }

  get allDone() {
    return this.total > 0 && this.completed === this.total;
  }

  urlFor(step) {
    if (step.setupPath && step.targetType === 'Setup') {
      return step.setupPath;
    }
    return `${SETTINGS_PAGE}?section=${encodeURIComponent(step.target || '')}`;
  }

  handleToggle(event) {
    const key = event.currentTarget.dataset.key;
    const step = (this.steps || []).find((row) => row.key === key);
    const name = step && step.completed ? 'stepnotdone' : 'stepdone';
    this.dispatchEvent(new CustomEvent(name, { detail: { key } }));
  }
}
