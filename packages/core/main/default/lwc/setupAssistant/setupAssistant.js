import { LightningElement } from 'lwc';
import getState from '@salesforce/apex/SetupAssistantController.getState';
import completeStep from '@salesforce/apex/SetupAssistantController.completeStep';
import skipStep from '@salesforce/apex/SetupAssistantController.skipStep';
import resetSetup from '@salesforce/apex/SetupAssistantController.reset';
import applyCoexistence from '@salesforce/apex/SetupAssistantController.applyCoexistence';
import saveOrganizationIdentity from '@salesforce/apex/SetupAssistantController.saveOrganizationIdentity';
import saveDefaults from '@salesforce/apex/SetupAssistantController.saveDefaults';
import assignAccess from '@salesforce/apex/SetupAssistantController.assignAccess';

import HEADING from '@salesforce/label/c.Core_SetupAssistant_Heading';
import PROGRESS_LABEL from '@salesforce/label/c.Core_SetupAssistant_ProgressLabel';
import STEP_COUNTER from '@salesforce/label/c.Core_SetupAssistant_StepCounterLabel';
import DONE_BADGE from '@salesforce/label/c.Core_SetupAssistant_DoneBadge';
import TODO_BADGE from '@salesforce/label/c.Core_SetupAssistant_ToDoBadge';
import SKIPPED_BADGE from '@salesforce/label/c.Core_SetupAssistant_SkippedBadge';
import NEXT from '@salesforce/label/c.Core_SetupAssistant_NextButton';
import BACK from '@salesforce/label/c.Core_SetupAssistant_BackButton';
import SKIP from '@salesforce/label/c.Core_SetupAssistant_SkipButton';
import FINISH from '@salesforce/label/c.Core_SetupAssistant_FinishButton';
import SAVE from '@salesforce/label/c.Core_SetupAssistant_SaveButton';
import READ_ONLY from '@salesforce/label/c.Core_SetupAssistant_ReadOnlyNotice';
import RULE_SETTING from '@salesforce/label/c.Core_SetupAssistant_RuleSetting';
import RULE_ACTION from '@salesforce/label/c.Core_SetupAssistant_RuleAction';
import LOAD_ERROR from '@salesforce/label/c.Core_SetupAssistant_LoadErrorMessage';
import COMPLETE_HEADING from '@salesforce/label/c.Core_SetupAssistant_CompleteHeading';
import ELAPSED from '@salesforce/label/c.Core_SetupAssistant_ElapsedLabel';
import REOPEN from '@salesforce/label/c.Core_SetupAssistant_ReopenButton';
import GIVING_MISSING from '@salesforce/label/c.Core_SetupAssistant_GivingMissingNotice';
import FUND_LABEL from '@salesforce/label/c.Core_SetupAssistant_FundLabel';
import APPEAL_LABEL from '@salesforce/label/c.Core_SetupAssistant_AppealLabel';
import USER_LABEL from '@salesforce/label/c.Core_SetupAssistant_UserLabel';
import ROLE_LABEL from '@salesforce/label/c.Core_SetupAssistant_RoleLabel';
import GIVE_ACCESS from '@salesforce/label/c.Core_SetupAssistant_GiveAccessButton';
import CREATE_USER from '@salesforce/label/c.Core_SetupAssistant_CreateUserLink';
import LOAD_SAMPLE from '@salesforce/label/c.Core_SetupAssistant_LoadSampleButton';
import IMPORT_BUTTON from '@salesforce/label/c.Core_SetupAssistant_ImportButton';
import IMPORT_MISSING from '@salesforce/label/c.Core_SetupAssistant_ImportMissingNotice';
import VERIFY_MISSING from '@salesforce/label/c.Core_SetupAssistant_VerifyGivingMissing';

const CREATE_USER_URL = '/lightning/setup/ManageUsers/home';
const IMPORT_URL = '/lightning/n/Import';

/**
 * The guided Setup Assistant: one step open at a time, Back and Next, Skip for now, and it
 * opens on the step Maria stopped at. Steps that belong to another feature render that
 * feature's component dynamically, so a step whose module is not installed shows a notice
 * instead of breaking the page.
 */
export default class SetupAssistant extends LightningElement {
  state;
  activeIndex = 0;
  errorMessage;
  reopened = false;
  namingType;
  sampleDataType;
  giftEntryType;
  showSampleData = false;
  chosenUserId;
  chosenRole;
  chosenFundId;
  chosenAppealId;

  labels = {
    heading: HEADING,
    progress: PROGRESS_LABEL,
    stepCounter: STEP_COUNTER,
    next: NEXT,
    back: BACK,
    skip: SKIP,
    finish: FINISH,
    save: SAVE,
    readOnly: READ_ONLY,
    completeHeading: COMPLETE_HEADING,
    elapsed: ELAPSED,
    reopen: REOPEN,
    givingMissing: GIVING_MISSING,
    fund: FUND_LABEL,
    appeal: APPEAL_LABEL,
    user: USER_LABEL,
    role: ROLE_LABEL,
    giveAccess: GIVE_ACCESS,
    createUser: CREATE_USER,
    loadSample: LOAD_SAMPLE,
    importButton: IMPORT_BUTTON,
    importMissing: IMPORT_MISSING,
    verifyMissing: VERIFY_MISSING
  };

  createUserUrl = CREATE_USER_URL;
  importUrl = IMPORT_URL;

  connectedCallback() {
    this.load();
  }

  async load() {
    try {
      this.applyState(await getState(), true);
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage = this.messageFrom(error);
    }
  }

  applyState(state, moveToFirstUnfinished) {
    if (!state) {
      return;
    }
    this.state = state;
    if (moveToFirstUnfinished) {
      this.activeIndex = this.firstUnfinishedIndex(state);
    }
    this.importComponents();
    this.dispatchEvent(
      new CustomEvent('setupchanged', {
        detail: {
          stepsCompleted: state.stepsCompleted,
          stepsTotal: state.stepsTotal,
          isComplete: state.isComplete
        }
      })
    );
  }

  firstUnfinishedIndex(state) {
    const steps = state.steps || [];
    const index = steps.findIndex((step) => !step.completed && !step.skipped);
    return index < 0 ? Math.max(steps.length - 1, 0) : index;
  }

  // Steps that belong to another feature render that feature's component. Each import is
  // written out literally so the compiler can see it, and a build without that component
  // shows the step's notice instead of failing to render.
  async importComponents() {
    if (!this.namingType) {
      this.namingType = await this.tryImport(() => import('c/householdNamingSettings'));
    }
    if (!this.sampleDataType) {
      this.sampleDataType = await this.tryImport(() => import('c/sampleDataManager'));
    }
    if (!this.giftEntryType && this.state && this.state.giving && this.state.giving.isPresent) {
      this.giftEntryType = await this.tryImport(() => import('c/quickGiftEntry'));
    }
  }

  async tryImport(loader) {
    try {
      const module = await loader();
      return module.default;
    } catch {
      return undefined;
    }
  }

  get steps() {
    return (this.state && this.state.steps) || [];
  }

  get canEdit() {
    return Boolean(this.state && this.state.canEdit);
  }

  get isReadOnly() {
    return Boolean(this.state) && !this.state.canEdit;
  }

  get activeStep() {
    return this.steps[this.activeIndex];
  }

  get activeKey() {
    return this.activeStep ? this.activeStep.key : undefined;
  }

  get ruleText() {
    if (!this.activeStep) {
      return '';
    }
    return this.activeStep.completionRule === 'Setting' ? RULE_SETTING : RULE_ACTION;
  }

  get progressText() {
    return this.state ? `${this.state.stepsCompleted} of ${this.state.stepsTotal}` : '';
  }

  get counterText() {
    return this.state ? `${this.activeIndex + 1} / ${this.state.stepsTotal}` : '';
  }

  get showCompletionScreen() {
    return Boolean(this.state && this.state.isComplete && !this.reopened);
  }

  get showPanels() {
    return Boolean(this.state) && !this.showCompletionScreen;
  }

  get isFirstStep() {
    return this.activeIndex === 0;
  }

  get isLastStep() {
    return this.state ? this.activeIndex >= this.state.stepsTotal - 1 : true;
  }

  get forwardLabel() {
    return this.isLastStep ? this.labels.finish : this.labels.next;
  }

  get summaryRows() {
    return this.steps.map((step) => ({
      ...step,
      badge: step.completed ? DONE_BADGE : step.skipped ? SKIPPED_BADGE : TODO_BADGE,
      badgeClass: step.completed ? 'slds-badge slds-theme_success' : 'slds-badge slds-badge_inverse'
    }));
  }

  get elapsedText() {
    return this.state &&
      this.state.elapsedMinutes !== null &&
      this.state.elapsedMinutes !== undefined
      ? String(this.state.elapsedMinutes)
      : '';
  }

  get isCoexistenceStep() {
    return this.activeKey === 'coexistence';
  }

  get isNamingStep() {
    return this.activeKey === 'naming';
  }

  get isDefaultsStep() {
    return this.activeKey === 'funddefaults';
  }

  get isAccessStep() {
    return this.activeKey === 'access';
  }

  get isIdentityStep() {
    return this.activeKey === 'identity';
  }

  get isModulesStep() {
    return this.activeKey === 'modules';
  }

  get isDataStep() {
    return this.activeKey === 'data';
  }

  get isVerifyStep() {
    return this.activeKey === 'verify';
  }

  get givingPresent() {
    return Boolean(this.state && this.state.giving && this.state.giving.isPresent);
  }

  get fundObject() {
    return this.state && this.state.giving ? this.state.giving.fundObject : undefined;
  }

  get appealObject() {
    return this.state && this.state.giving ? this.state.giving.appealObject : undefined;
  }

  get importAvailable() {
    return Boolean(this.state && this.state.importAvailable);
  }

  get roleOptions() {
    return ((this.state && this.state.roles) || []).map((role) => ({
      label: role.replace(/_/g, ' '),
      value: role
    }));
  }

  get identityValues() {
    return (this.state && this.state.identity) || {};
  }

  get modules() {
    return (this.state && this.state.modules) || [];
  }

  get coexistence() {
    return (this.state && this.state.coexistence) || {};
  }

  handleBack() {
    if (this.activeIndex > 0) {
      this.activeIndex -= 1;
    }
  }

  handleForward() {
    if (this.canEdit && this.activeStep && this.activeStep.completionRule === 'Action') {
      this.call(completeStep, { stepKey: this.activeKey }, false);
      this.advance();
      return;
    }
    this.advance();
  }

  handleSkip() {
    if (!this.canEdit) {
      this.advance();
      return;
    }
    this.call(skipStep, { stepKey: this.activeKey }, false);
    this.advance();
  }

  advance() {
    if (!this.isLastStep) {
      this.activeIndex += 1;
    } else {
      this.reopened = false;
    }
  }

  handleReset() {
    this.reopened = true;
    this.call(resetSetup, {}, true);
  }

  handleReopen() {
    this.reopened = true;
    this.activeIndex = 0;
  }

  handleCoexistenceConfirm(event) {
    this.call(applyCoexistence, { mode: event.detail.mode }, false, () => this.advance());
  }

  handleNamingSaved() {
    this.call(completeStep, { stepKey: 'naming' }, false);
  }

  handleIdentitySave(event) {
    this.call(saveOrganizationIdentity, { values: event.detail.values }, false);
  }

  handleFundChange(event) {
    this.chosenFundId = event.detail.recordId;
  }

  handleAppealChange(event) {
    this.chosenAppealId = event.detail.recordId;
  }

  handleDefaultsSave() {
    this.call(
      saveDefaults,
      { fundId: this.chosenFundId, appealId: this.chosenAppealId },
      false,
      () => this.advance()
    );
  }

  handleUserChange(event) {
    this.chosenUserId = event.detail.recordId;
  }

  handleRoleChange(event) {
    this.chosenRole = event.detail.value;
  }

  handleAssignAccess() {
    this.call(assignAccess, { userId: this.chosenUserId, roleDeveloperName: this.chosenRole });
  }

  handleShowSampleData() {
    this.showSampleData = true;
  }

  async call(action, parameters, moveToFirstUnfinished, afterwards) {
    try {
      this.applyState(await action(parameters), Boolean(moveToFirstUnfinished));
      this.errorMessage = undefined;
      if (afterwards) {
        afterwards();
      }
    } catch (error) {
      this.errorMessage = this.messageFrom(error);
    }
  }

  messageFrom(error) {
    return error && error.body && error.body.message ? error.body.message : LOAD_ERROR;
  }
}
