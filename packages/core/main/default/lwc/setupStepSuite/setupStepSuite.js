import { LightningElement, api } from 'lwc';
import CHOOSER_LABEL from '@salesforce/label/c.Core_SetupAssistant_SuiteChooserLabel';
import CHOOSE_BUTTON from '@salesforce/label/c.Core_SetupAssistant_SuiteChooseButton';
import MODULES_HEADING from '@salesforce/label/c.Core_SetupAssistant_SuiteModulesHeading';
import NEEDS_GIVING from '@salesforce/label/c.Core_SetupAssistant_SuiteNeedsGivingNotice';

const NONPROFIT = 'Nonprofit';

/**
 * The first step (C-30, ADR-0046): Nonprofit Suite or Community Suite, each with one line
 * saying who it is for, and the modules the selected suite offers with their state. The
 * suite the organization saved is selected; while nobody has chosen, the one Apex suggests
 * from what is installed. Changing the selection only changes the list below it: nothing is
 * saved until Choose and continue.
 */
export default class SetupStepSuite extends LightningElement {
  @api canEdit = false;

  selected;

  labels = {
    chooser: CHOOSER_LABEL,
    choose: CHOOSE_BUTTON,
    modulesHeading: MODULES_HEADING,
    needsGiving: NEEDS_GIVING
  };

  _suite = {};

  @api
  get suite() {
    return this._suite;
  }

  set suite(value) {
    this._suite = value || {};
    this.selected = this._suite.chosenSuite || this._suite.recommendedSuite;
  }

  get isReadOnly() {
    return !this.canEdit;
  }

  get options() {
    return (this._suite.options || []).map((option) => ({
      ...option,
      inputId: `suite-${option.value}`,
      descriptionId: `suite-${option.value}-description`,
      checked: option.value === this.selected
    }));
  }

  get selectedOption() {
    return (this._suite.options || []).find((option) => option.value === this.selected);
  }

  get selectedModules() {
    const option = this.selectedOption;
    return (option && option.modules) || [];
  }

  get hasModules() {
    return this.selectedModules.length > 0;
  }

  // Choosing the Nonprofit Suite without Giving is allowed: the step says so plainly and setup
  // carries on with the steps every organization answers.
  get showNeedsGiving() {
    return this.selected === NONPROFIT && this._suite.givingPresent === false;
  }

  get chooseDisabled() {
    return !this.selected;
  }

  handleSelect(event) {
    this.selected = event.target.value;
  }

  handleChoose() {
    if (!this.selected) {
      return;
    }
    this.dispatchEvent(new CustomEvent('choose', { detail: { suite: this.selected } }));
  }
}
