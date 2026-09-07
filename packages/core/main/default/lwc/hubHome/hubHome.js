import { LightningElement } from 'lwc';
import getHomeModel from '@salesforce/apex/HubController.getHomeModel';
import markStepDone from '@salesforce/apex/HubController.markStepDone';
import markStepNotDone from '@salesforce/apex/HubController.markStepNotDone';
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

export default class HubHome extends LightningElement {
  labels = {
    welcomeHeading: WELCOME_HEADING,
    welcomeMessage: WELCOME_MESSAGE,
    checklistHeading: CHECKLIST_HEADING,
    pausedBanner: PAUSED_BANNER,
    errorTileHeading: ERROR_TILE_HEADING,
    errorTileLink: ERROR_TILE_LINK,
    quickLinksHeading: QUICK_LINKS_HEADING,
    loadError: LOAD_ERROR
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

  steps = [];
  stepsCompleted = 0;
  stepsTotal = 0;
  automationPaused = false;
  newErrorCount = 0;
  canEdit = false;
  errorMessage;

  connectedCallback() {
    this.load();
  }

  get hasErrors() {
    return this.newErrorCount > 0;
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
    this.steps = model.steps || [];
    this.stepsCompleted = model.stepsCompleted || 0;
    this.stepsTotal = model.stepsTotal || 0;
    this.automationPaused = Boolean(model.automationPaused);
    this.newErrorCount = model.newErrorCount || 0;
    this.canEdit = Boolean(model.canEdit);
  }

  handleStepDone(event) {
    this.updateStep(markStepDone, event.detail.key);
  }

  handleStepNotDone(event) {
    this.updateStep(markStepNotDone, event.detail.key);
  }

  async updateStep(action, stepKey) {
    try {
      this.applyModel(await action({ stepKey }));
      this.errorMessage = undefined;
    } catch (error) {
      this.errorMessage =
        error && error.body && error.body.message ? error.body.message : this.labels.loadError;
    }
  }
}
