import { LightningElement } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getStatus from '@salesforce/apex/SampleDataController.getStatus';
import loadSampleData from '@salesforce/apex/SampleDataController.loadSampleData';
import removeSampleData from '@salesforce/apex/SampleDataController.removeSampleData';
import canManageSampleData from '@salesforce/apex/SampleDataController.canManageSampleData';

import cardTitle from '@salesforce/label/c.Core_SampleData_CardTitle';
import loadButtonLabel from '@salesforce/label/c.Core_SampleData_LoadButton';
import removeButtonLabel from '@salesforce/label/c.Core_SampleData_RemoveButton';
import loadConfirmTitle from '@salesforce/label/c.Core_SampleData_LoadConfirmTitle';
import loadConfirmBody from '@salesforce/label/c.Core_SampleData_LoadConfirmBody';
import removeConfirmTitle from '@salesforce/label/c.Core_SampleData_RemoveConfirmTitle';
import removeConfirmBody from '@salesforce/label/c.Core_SampleData_RemoveConfirmBody';
import productionWarning from '@salesforce/label/c.Core_SampleData_ProductionWarning';
import statusLoaded from '@salesforce/label/c.Core_SampleData_StatusLoaded';
import statusNotLoaded from '@salesforce/label/c.Core_SampleData_StatusNotLoaded';
import statusLoading from '@salesforce/label/c.Core_SampleData_StatusLoading';
import householdsLabel from '@salesforce/label/c.Core_SampleData_HouseholdsLabel';
import contactsLabel from '@salesforce/label/c.Core_SampleData_ContactsLabel';
import organizationsLabel from '@salesforce/label/c.Core_SampleData_OrganizationsLabel';
import readOnlyMessage from '@salesforce/label/c.Core_SampleData_ReadOnlyMessage';
import loadSuccess from '@salesforce/label/c.Core_SampleData_LoadSuccess';
import removeSuccess from '@salesforce/label/c.Core_SampleData_RemoveSuccess';
import loadError from '@salesforce/label/c.Core_SampleData_LoadError';
import removeError from '@salesforce/label/c.Core_SampleData_RemoveError';
import cancelButtonLabel from '@salesforce/label/c.Core_SampleData_CancelButton';
import confirmButtonLabel from '@salesforce/label/c.Core_SampleData_ConfirmButton';

/** How often the status card polls while a load is running (C-10). */
const POLL_INTERVAL_MS = 3000;

/**
 * Status card for the C-10 sample data loader: shows whether the sample set is loaded,
 * with Load and Remove actions (each behind a confirmation that warns against
 * production orgs), and polls the load's progress while it runs.
 * See docs/admin-guide/sample-data.md.
 */
export default class SampleDataManager extends LightningElement {
  labels = {
    cardTitle,
    loadButtonLabel,
    removeButtonLabel,
    loadConfirmTitle,
    loadConfirmBody,
    removeConfirmTitle,
    removeConfirmBody,
    productionWarning,
    statusLoaded,
    statusNotLoaded,
    statusLoading,
    householdsLabel,
    contactsLabel,
    organizationsLabel,
    readOnlyMessage,
    cancelButtonLabel,
    confirmButtonLabel,
    loadSuccess,
    removeSuccess,
    loadError,
    removeError
  };

  householdCount = 0;
  contactCount = 0;
  organizationCount = 0;
  loaded = false;
  loading = false;
  canManage = false;
  isLoadingStatus = true;
  isBusy = false;
  pendingAction; // 'load', 'remove', or undefined

  pollTimer;

  connectedCallback() {
    this.checkPermission();
    this.refreshStatus();
  }

  disconnectedCallback() {
    this.clearPollTimer();
  }

  async checkPermission() {
    try {
      this.canManage = await canManageSampleData();
    } catch {
      // No permission check available (unauthenticated or unpackaged context):
      // fail closed to the read-only view.
      this.canManage = false;
    }
  }

  async refreshStatus() {
    try {
      const result = await getStatus();
      this.applyStatus(result);
    } catch (error) {
      this.showToast(this.labels.loadError, this.reduceError(error), 'error');
    } finally {
      this.isLoadingStatus = false;
    }
  }

  applyStatus(result) {
    const wasLoading = this.loading;
    this.householdCount = result.householdCount;
    this.contactCount = result.contactCount;
    this.organizationCount = result.organizationCount;
    this.loaded = result.loaded;
    this.loading = result.loading;

    if (this.loading) {
      this.startPolling();
    } else {
      this.clearPollTimer();
      if (wasLoading && this.loaded) {
        this.showToast(this.labels.loadSuccess, '', 'success');
      }
    }
  }

  startPolling() {
    if (this.pollTimer) {
      return;
    }
    // eslint-disable-next-line @lwc/lwc/no-async-operation
    this.pollTimer = setInterval(() => {
      this.refreshStatus();
    }, POLL_INTERVAL_MS);
  }

  clearPollTimer() {
    if (this.pollTimer) {
      clearInterval(this.pollTimer);
      this.pollTimer = undefined;
    }
  }

  get statusLabel() {
    if (this.loading) {
      return this.labels.statusLoading;
    }
    return this.loaded ? this.labels.statusLoaded : this.labels.statusNotLoaded;
  }

  get statusBadgeClass() {
    if (this.loading) {
      return 'slds-theme_warning';
    }
    return this.loaded ? 'slds-theme_success' : '';
  }

  get showConfirm() {
    return this.pendingAction != null;
  }

  get confirmTitle() {
    return this.pendingAction === 'load'
      ? this.labels.loadConfirmTitle
      : this.labels.removeConfirmTitle;
  }

  get confirmBody() {
    return this.pendingAction === 'load'
      ? this.labels.loadConfirmBody
      : this.labels.removeConfirmBody;
  }

  get loadDisabled() {
    return !this.canManage || this.loaded || this.loading || this.isBusy;
  }

  get removeDisabled() {
    return !this.canManage || (!this.loaded && !this.loading) || this.isBusy;
  }

  handleLoadClick() {
    this.pendingAction = 'load';
  }

  handleRemoveClick() {
    this.pendingAction = 'remove';
  }

  handleCancel() {
    this.pendingAction = undefined;
  }

  async handleConfirm() {
    const action = this.pendingAction;
    this.pendingAction = undefined;
    this.isBusy = true;
    try {
      if (action === 'load') {
        await loadSampleData();
      } else {
        await removeSampleData();
        this.showToast(this.labels.removeSuccess, '', 'success');
      }
    } catch (error) {
      const message = action === 'load' ? this.labels.loadError : this.labels.removeError;
      this.showToast(message, this.reduceError(error), 'error');
    } finally {
      this.isBusy = false;
      await this.refreshStatus();
    }
  }

  showToast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }

  reduceError(error) {
    if (error && error.body && error.body.message) {
      return error.body.message;
    }
    return error && error.message ? error.message : '';
  }
}
