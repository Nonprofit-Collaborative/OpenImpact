import { LightningElement, track } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import hasManageSettings from '@salesforce/customPermission/Manage_Nonprofit_Settings';
import preview from '@salesforce/apex/HouseholdController.preview';
import recomputeAll from '@salesforce/apex/HouseholdController.recomputeAll';
import saveSettings from '@salesforce/apex/SettingsController.saveSettings';

import TITLE from '@salesforce/label/c.Core_HouseholdNamingSettings_Title';
import NAME_LABEL from '@salesforce/label/c.Core_HouseholdNamingSettings_NameLabel';
import FORMAL_LABEL from '@salesforce/label/c.Core_HouseholdNamingSettings_FormalLabel';
import INFORMAL_LABEL from '@salesforce/label/c.Core_HouseholdNamingSettings_InformalLabel';
import TOKEN_HELP from '@salesforce/label/c.Core_HouseholdNamingSettings_TokenHelp';
import PREVIEW_HEADING from '@salesforce/label/c.Core_HouseholdNamingSettings_PreviewHeading';
import COLUMN_MEMBERS from '@salesforce/label/c.Core_HouseholdNamingSettings_ColumnMembers';
import COLUMN_NAME from '@salesforce/label/c.Core_HouseholdNamingSettings_ColumnName';
import COLUMN_FORMAL from '@salesforce/label/c.Core_HouseholdNamingSettings_ColumnFormal';
import COLUMN_INFORMAL from '@salesforce/label/c.Core_HouseholdNamingSettings_ColumnInformal';
import SAVE from '@salesforce/label/c.Core_HouseholdNamingSettings_Save';
import SAVED from '@salesforce/label/c.Core_HouseholdNamingSettings_Saved';
import RECOMPUTE from '@salesforce/label/c.Core_HouseholdNamingSettings_Recompute';
import RECOMPUTE_CONFIRM from '@salesforce/label/c.Core_HouseholdNamingSettings_RecomputeConfirm';
import RECOMPUTE_STARTED from '@salesforce/label/c.Core_HouseholdNamingSettings_RecomputeStarted';
import READ_ONLY from '@salesforce/label/c.Core_HouseholdNamingSettings_ReadOnly';
import CANCEL from '@salesforce/label/c.Core_HouseholdNamingSettings_Cancel';
import CONFIRM from '@salesforce/label/c.Core_HouseholdNamingSettings_Confirm';

const DEBOUNCE_MILLISECONDS = 300;
const NAME_KEY = 'Household_Name_Pattern__c';
const FORMAL_KEY = 'Formal_Greeting_Pattern__c';
const INFORMAL_KEY = 'Informal_Greeting_Pattern__c';

export default class HouseholdNamingSettings extends LightningElement {
  label = {
    title: TITLE,
    nameLabel: NAME_LABEL,
    formalLabel: FORMAL_LABEL,
    informalLabel: INFORMAL_LABEL,
    tokenHelp: TOKEN_HELP,
    previewHeading: PREVIEW_HEADING,
    columnMembers: COLUMN_MEMBERS,
    columnName: COLUMN_NAME,
    columnFormal: COLUMN_FORMAL,
    columnInformal: COLUMN_INFORMAL,
    save: SAVE,
    recompute: RECOMPUTE,
    recomputeConfirm: RECOMPUTE_CONFIRM,
    readOnly: READ_ONLY,
    cancel: CANCEL,
    confirm: CONFIRM
  };

  namePattern = 'The {LastName} Family';
  formalPattern = '{Salutation} {FirstName} {LastName}';
  informalPattern = '{FirstName}';

  @track samples = [];
  errorMessage;
  isSaving = false;
  isConfirmingRecompute = false;

  debounceTimer;

  get canEdit() {
    return hasManageSettings === true;
  }

  get isReadOnly() {
    return !this.canEdit;
  }

  get hasSamples() {
    return this.samples.length > 0;
  }

  connectedCallback() {
    this.refreshPreview();
  }

  disconnectedCallback() {
    clearTimeout(this.debounceTimer);
  }

  handleNameChange(event) {
    this.namePattern = event.detail.value;
    this.schedulePreview();
  }

  handleFormalChange(event) {
    this.formalPattern = event.detail.value;
    this.schedulePreview();
  }

  handleInformalChange(event) {
    this.informalPattern = event.detail.value;
    this.schedulePreview();
  }

  schedulePreview() {
    clearTimeout(this.debounceTimer);
    // The preview waits for a pause in typing rather than asking on every keystroke.
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.debounceTimer = setTimeout(() => {
      this.refreshPreview();
    }, DEBOUNCE_MILLISECONDS);
  }

  refreshPreview() {
    return preview({
      namePattern: this.namePattern,
      formalPattern: this.formalPattern,
      informalPattern: this.informalPattern
    })
      .then((rows) => {
        this.samples = (rows || []).map((row, index) => ({ ...row, key: `sample-${index}` }));
        this.errorMessage = undefined;
      })
      .catch((error) => {
        this.samples = [];
        this.errorMessage = this.readError(error);
      });
  }

  handleSave() {
    this.isSaving = true;
    const values = {};
    values[NAME_KEY] = this.namePattern;
    values[FORMAL_KEY] = this.formalPattern;
    values[INFORMAL_KEY] = this.informalPattern;
    return saveSettings({ settings: values })
      .then(() => {
        this.errorMessage = undefined;
        this.toast(SAVED, 'success');
      })
      .catch((error) => {
        this.errorMessage = this.readError(error);
      })
      .finally(() => {
        this.isSaving = false;
      });
  }

  handleRecomputeClick() {
    this.isConfirmingRecompute = true;
  }

  handleRecomputeCancel() {
    this.isConfirmingRecompute = false;
  }

  handleRecomputeConfirm() {
    this.isConfirmingRecompute = false;
    return recomputeAll()
      .then(() => {
        this.errorMessage = undefined;
        this.toast(RECOMPUTE_STARTED, 'success');
      })
      .catch((error) => {
        this.errorMessage = this.readError(error);
      });
  }

  toast(message, variant) {
    this.dispatchEvent(new ShowToastEvent({ message, variant }));
  }

  readError(error) {
    if (!error) {
      return undefined;
    }
    if (error.body && error.body.message) {
      return error.body.message;
    }
    return error.message;
  }
}
