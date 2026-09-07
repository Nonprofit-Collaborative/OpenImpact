import { LightningElement } from 'lwc';
import getConsoleModel from '@salesforce/apex/SettingsController.getConsoleModel';
import saveSettings from '@salesforce/apex/SettingsController.saveSettings';
import getRecentChanges from '@salesforce/apex/SettingsController.getRecentChanges';
import TITLE from '@salesforce/label/c.Core_Settings_Title';
import SECTIONS_HEADING from '@salesforce/label/c.Core_Settings_SectionsHeading';
import SAVE_BUTTON from '@salesforce/label/c.Core_Settings_SaveButton';
import DISCARD_BUTTON from '@salesforce/label/c.Core_Settings_DiscardButton';
import SAVED_MESSAGE from '@salesforce/label/c.Core_Settings_SavedMessage';
import SAVE_ERROR from '@salesforce/label/c.Core_Settings_SaveErrorMessage';
import LOAD_ERROR from '@salesforce/label/c.Core_Settings_LoadErrorMessage';
import READ_ONLY_NOTICE from '@salesforce/label/c.Core_Settings_ReadOnlyNotice';
import LEARN_MORE from '@salesforce/label/c.Core_Settings_LearnMoreLink';
import EMPTY_SECTION from '@salesforce/label/c.Core_Settings_EmptySectionMessage';
import RECENT_HEADING from '@salesforce/label/c.Core_Settings_RecentChangesHeading';
import RECENT_EMPTY from '@salesforce/label/c.Core_Settings_RecentChangesEmpty';
import COLUMN_SETTING from '@salesforce/label/c.Core_Settings_ColumnSetting';
import COLUMN_OLD from '@salesforce/label/c.Core_Settings_ColumnOldValue';
import COLUMN_NEW from '@salesforce/label/c.Core_Settings_ColumnNewValue';
import COLUMN_BY from '@salesforce/label/c.Core_Settings_ColumnChangedBy';
import COLUMN_AT from '@salesforce/label/c.Core_Settings_ColumnChangedAt';

const RECENT_LIMIT = 10;

export default class SettingsConsole extends LightningElement {
  labels = {
    title: TITLE,
    sectionsHeading: SECTIONS_HEADING,
    save: SAVE_BUTTON,
    discard: DISCARD_BUTTON,
    saved: SAVED_MESSAGE,
    saveError: SAVE_ERROR,
    loadError: LOAD_ERROR,
    readOnly: READ_ONLY_NOTICE,
    learnMore: LEARN_MORE,
    emptySection: EMPTY_SECTION,
    recentHeading: RECENT_HEADING,
    recentEmpty: RECENT_EMPTY
  };

  columns = [
    { label: COLUMN_SETTING, fieldName: 'settingName', type: 'text' },
    { label: COLUMN_OLD, fieldName: 'oldValue', type: 'text' },
    { label: COLUMN_NEW, fieldName: 'newValue', type: 'text' },
    { label: COLUMN_BY, fieldName: 'changedBy', type: 'text' },
    { label: COLUMN_AT, fieldName: 'changedAt', type: 'date' }
  ];

  sections = [];
  changes = [];
  canEdit = false;
  selectedSection;
  pending = {};
  message;
  messageIsError = false;
  loading = true;
  componentTypes = {};

  connectedCallback() {
    this.load();
  }

  get navigationItems() {
    return this.sections.map((section) => ({
      name: section.name,
      label: section.name
    }));
  }

  get currentSection() {
    return this.sections.find((section) => section.name === this.selectedSection);
  }

  get currentSettings() {
    const section = this.currentSection;
    if (!section) {
      return [];
    }
    return section.settings.map((setting) => this.toRow(setting));
  }

  get sectionIsEmpty() {
    return !this.loading && this.currentSettings.length === 0;
  }

  get hasChangesToShow() {
    return this.changes.length > 0;
  }

  get showReadOnlyNotice() {
    return !this.loading && !this.canEdit;
  }

  get isDirty() {
    return Object.keys(this.pending).length > 0;
  }

  get saveDisabled() {
    return !this.canEdit || !this.isDirty;
  }

  get messageClass() {
    return this.messageIsError
      ? 'slds-text-color_error slds-p-vertical_x-small'
      : 'slds-text-color_success slds-p-vertical_x-small';
  }

  toRow(setting) {
    const pendingValue = this.pending[setting.key];
    const hasPending = pendingValue !== undefined;
    const isCheckbox = setting.dataType === 'Checkbox';
    return {
      ...setting,
      isCheckbox,
      isText: setting.dataType === 'Text',
      isNumber: setting.dataType === 'Number',
      isPicklist: setting.dataType === 'Picklist',
      isDateTime: setting.dataType === 'DateTime',
      isComponent: setting.dataType === 'Component',
      hasHelp: Boolean(setting.helpUrl),
      disabled: !this.canEdit,
      ctor: this.componentTypes[setting.component],
      checked: isCheckbox ? (hasPending ? pendingValue === true : setting.checked) : false,
      value: hasPending ? pendingValue : setting.value
    };
  }

  async load() {
    this.loading = true;
    try {
      const model = await getConsoleModel();
      this.applyModel(model);
      this.message = undefined;
    } catch {
      this.messageIsError = true;
      this.message = this.labels.loadError;
    }
    this.loading = false;
    await this.loadChanges();
  }

  async loadChanges() {
    try {
      this.changes = (await getRecentChanges({ limitCount: RECENT_LIMIT })) || [];
    } catch {
      this.changes = [];
    }
  }

  applyModel(model) {
    this.sections = (model && model.sections) || [];
    this.canEdit = Boolean(model && model.canEdit);
    if (!this.selectedSection && this.sections.length > 0) {
      this.selectedSection = this.sections[0].name;
    }
    this.loadDynamicComponents();
  }

  loadDynamicComponents() {
    this.sections.forEach((section) => {
      section.settings.forEach((setting) => {
        if (setting.component && !this.componentTypes[setting.component]) {
          this.importComponent(setting.component);
        }
      });
    });
  }

  async importComponent(name) {
    try {
      const module = await import(`c/${name}`);
      this.componentTypes = { ...this.componentTypes, [name]: module.default };
    } catch {
      // A section whose component is not in this build is left out rather than
      // breaking the page. The feature that owns it ships it.
      this.componentTypes = { ...this.componentTypes };
    }
  }

  handleSectionSelect(event) {
    this.selectedSection = event.detail.name;
  }

  handleSearchSelect(event) {
    if (event.detail && event.detail.section) {
      this.selectedSection = event.detail.section;
    }
  }

  handleChange(event) {
    const key = event.target.dataset.key;
    const kind = event.target.dataset.kind;
    let value;
    if (kind === 'Checkbox') {
      value = event.target.checked;
    } else if (kind === 'Picklist') {
      value = event.detail.value;
    } else {
      value = event.target.value;
    }
    this.pending = { ...this.pending, [key]: value };
    this.message = undefined;
  }

  handleDiscard() {
    this.pending = {};
    this.message = undefined;
  }

  async handleSave() {
    if (!this.canEdit || !this.isDirty) {
      return;
    }
    const values = { ...this.pending };
    try {
      const model = await saveSettings({ values });
      this.applyModel(model);
      this.pending = {};
      this.messageIsError = false;
      this.message = this.labels.saved;
      await this.loadChanges();
    } catch (error) {
      this.messageIsError = true;
      this.message = this.readError(error) || this.labels.saveError;
    }
  }

  readError(error) {
    if (error && error.body && error.body.message) {
      return error.body.message;
    }
    return undefined;
  }
}
