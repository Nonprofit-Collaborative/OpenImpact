import { LightningElement } from 'lwc';
import getHomeModel from '@salesforce/apex/HubController.getHomeModel';
import WELCOME_HEADING from '@salesforce/label/c.Core_HubHome_WelcomeHeading';
import WELCOME_MESSAGE from '@salesforce/label/c.Core_HubHome_WelcomeMessage';
import CHECKLIST_HEADING from '@salesforce/label/c.Core_HubHome_ChecklistHeading';
import PAUSED_BANNER from '@salesforce/label/c.Core_HubHome_AutomationPausedBanner';
import ERROR_TILE_HEADING from '@salesforce/label/c.Core_HubHome_ErrorTileHeading';
import ERROR_TILE_LINK from '@salesforce/label/c.Core_HubHome_ErrorTileLinkLabel';
import QUICK_LINKS_HEADING from '@salesforce/label/c.Core_HubHome_QuickLinksHeading';
import QUICK_LINK_SETTINGS from '@salesforce/label/c.Core_HubHome_QuickLinkSettings';
import QUICK_LINK_HOUSEHOLDS from '@salesforce/label/c.Core_HubHome_QuickLinkHouseholds';
import QUICK_LINK_ORGANIZATIONS from '@salesforce/label/c.Core_HubHome_QuickLinkOrganizations';
import LOAD_ERROR from '@salesforce/label/c.Core_HubHome_LoadErrorMessage';
import SETUP_COMPLETE_HEADING from '@salesforce/label/c.Core_SetupAssistant_CompleteTileHeading';
import REOPEN_SETUP from '@salesforce/label/c.Core_SetupAssistant_ReopenButton';

export default class HubHome extends LightningElement {
  labels = {
    welcomeHeading: WELCOME_HEADING,
    welcomeMessage: WELCOME_MESSAGE,
    checklistHeading: CHECKLIST_HEADING,
    pausedBanner: PAUSED_BANNER,
    errorTileHeading: ERROR_TILE_HEADING,
    errorTileLink: ERROR_TILE_LINK,
    quickLinksHeading: QUICK_LINKS_HEADING,
    loadError: LOAD_ERROR,
    setupCompleteHeading: SETUP_COMPLETE_HEADING,
    reopenSetup: REOPEN_SETUP
  };

  quickLinks = [
    { key: 'settings', label: QUICK_LINK_SETTINGS, url: '/lightning/n/Nonprofit_Settings' },
    { key: 'households', label: QUICK_LINK_HOUSEHOLDS, url: '/lightning/n/Households' },
    {
      key: 'organizations',
      label: QUICK_LINK_ORGANIZATIONS,
      url: '/lightning/n/Organizations'
    }
  ];

  errorLogUrl = '/lightning/o/Error_Log__c/list';

  stepsCompleted = 0;
  stepsTotal = 0;
  automationPaused = false;
  newErrorCount = 0;
  canEdit = false;
  errorMessage;
  setupReopened = false;

  connectedCallback() {
    this.load();
  }

  get hasErrors() {
    return this.newErrorCount > 0;
  }

  /** The assistant is the home page until it is finished, and one click away after that. */
  get showAssistant() {
    return this.setupReopened || !this.setupComplete;
  }

  get setupComplete() {
    return this.stepsTotal > 0 && this.stepsCompleted === this.stepsTotal;
  }

  get setupProgressText() {
    return `${this.stepsCompleted} of ${this.stepsTotal}`;
  }

  async load() {
    try {
      this.applyModel(await getHomeModel());
      this.errorMessage = undefined;
    } catch {
      this.errorMessage = this.labels.loadError;
    }
  }

  applyModel(model) {
    if (!model) {
      return;
    }
    this.stepsCompleted = model.stepsCompleted || 0;
    this.stepsTotal = model.stepsTotal || 0;
    this.automationPaused = Boolean(model.automationPaused);
    this.newErrorCount = model.newErrorCount || 0;
    this.canEdit = Boolean(model.canEdit);
  }

  /** The assistant reports its own progress, so the page collapses without reloading. */
  handleSetupChanged(event) {
    this.stepsCompleted = event.detail.stepsCompleted || 0;
    this.stepsTotal = event.detail.stepsTotal || 0;
    if (!event.detail.isComplete) {
      this.setupReopened = false;
    }
  }

  handleReopenSetup() {
    this.setupReopened = true;
  }
}
