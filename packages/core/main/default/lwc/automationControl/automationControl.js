import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import canManageSettings from '@salesforce/customPermission/Manage_Nonprofit_Settings';
import getPage from '@salesforce/apex/AutomationControlController.getPage';
import pauseAll from '@salesforce/apex/AutomationControlController.pauseAll';
import resumeAll from '@salesforce/apex/AutomationControlController.resumeAll';
import setEnabled from '@salesforce/apex/AutomationControlController.setEnabled';

import TITLE from '@salesforce/label/c.Core_AutomationControl_Title';
import INTRO from '@salesforce/label/c.Core_AutomationControl_Intro';
import PAUSE_BUTTON from '@salesforce/label/c.Core_AutomationControl_PauseButton';
import RESUME_BUTTON from '@salesforce/label/c.Core_AutomationControl_ResumeButton';
import PAUSE_LENGTH from '@salesforce/label/c.Core_AutomationControl_PauseLength';
import PAUSED_BANNER from '@salesforce/label/c.Core_AutomationControl_PausedBanner';
import READ_ONLY from '@salesforce/label/c.Core_AutomationControl_ReadOnly';
import EMPTY from '@salesforce/label/c.Core_AutomationControl_Empty';
import RUNS_ON from '@salesforce/label/c.Core_AutomationControl_RunsOn';
import ONE_HOUR from '@salesforce/label/c.Core_AutomationControl_OneHour';
import TWO_HOURS from '@salesforce/label/c.Core_AutomationControl_TwoHours';
import FOUR_HOURS from '@salesforce/label/c.Core_AutomationControl_FourHours';
import EIGHT_HOURS from '@salesforce/label/c.Core_AutomationControl_EightHours';
import TWENTY_FOUR_HOURS from '@salesforce/label/c.Core_AutomationControl_TwentyFourHours';
import ERROR_PREFIX from '@salesforce/label/c.Core_AutomationControl_ErrorPrefix';
import PAUSED_PREFIX from '@salesforce/label/c.Core_AutomationControl_PausedPrefix';
import UNEXPECTED_ERROR from '@salesforce/label/c.Core_Automation_UnexpectedError';

const HOUR_OPTIONS = [
  { label: ONE_HOUR, value: '1' },
  { label: TWO_HOURS, value: '2' },
  { label: FOUR_HOURS, value: '4' },
  { label: EIGHT_HOURS, value: '8' },
  { label: TWENTY_FOUR_HOURS, value: '24' }
];

const DEFAULT_HOURS = '2';

export default class AutomationControl extends LightningElement {
  labels = {
    title: TITLE,
    intro: INTRO,
    pauseButton: PAUSE_BUTTON,
    resumeButton: RESUME_BUTTON,
    pauseLength: PAUSE_LENGTH,
    pausedBanner: PAUSED_BANNER,
    readOnly: READ_ONLY,
    empty: EMPTY,
    runsOn: RUNS_ON,
    errorPrefix: ERROR_PREFIX,
    pausedPrefix: PAUSED_PREFIX
  };

  page;
  errorMessage;
  selectedHours = DEFAULT_HOURS;
  busy = false;
  wiredPageResult;

  @wire(getPage)
  wiredPage(result) {
    // The whole result is kept so that an action can refresh the cached wire rather than leaving
    // the page showing what the server said before the action.
    this.wiredPageResult = result;
    if (result.data) {
      this.page = result.data;
      this.errorMessage = undefined;
    } else if (result.error) {
      this.errorMessage = this.messageFrom(result.error);
    }
  }

  get hourOptions() {
    return HOUR_OPTIONS;
  }

  get canManage() {
    return canManageSettings === true;
  }

  get isReadOnly() {
    return !this.canManage;
  }

  get isPaused() {
    return !!(this.page && this.page.paused);
  }

  get pausedUntil() {
    return this.page ? this.page.pausedUntil : undefined;
  }

  get automations() {
    return this.page && this.page.automations ? this.page.automations : [];
  }

  get hasAutomations() {
    return this.automations.length > 0;
  }

  get isEmpty() {
    return !!this.page && !this.hasAutomations;
  }

  get controlsDisabled() {
    return this.isReadOnly || this.busy;
  }

  get hasError() {
    return !!this.errorMessage;
  }

  handleHoursChange(event) {
    this.selectedHours = event.detail.value;
  }

  handlePause() {
    this.runAction(pauseAll({ hours: parseInt(this.selectedHours, 10) }));
  }

  handleResume() {
    this.runAction(resumeAll());
  }

  handleToggle(event) {
    const automationName = event.target.dataset.automation;
    const enabled = event.target.checked;
    this.runAction(setEnabled({ automationName, enabled }));
  }

  runAction(promise) {
    this.busy = true;
    this.errorMessage = undefined;
    return promise
      .then((page) => {
        this.page = page;
      })
      .catch((error) => {
        this.errorMessage = this.messageFrom(error);
        // A refused switch must not leave a toggle showing a change the server did not make, so
        // the list is rebuilt from what the server last said.
        this.page = this.page ? { ...this.page } : this.page;
      })
      .finally(() => {
        this.busy = false;
        this.refreshPage();
      });
  }

  refreshPage() {
    if (this.wiredPageResult) {
      return refreshApex(this.wiredPageResult);
    }
    return Promise.resolve();
  }

  messageFrom(error) {
    if (error && error.body && error.body.message) {
      return error.body.message;
    }
    return UNEXPECTED_ERROR;
  }
}
