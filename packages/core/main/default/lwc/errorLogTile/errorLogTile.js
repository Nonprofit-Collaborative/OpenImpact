import { LightningElement, wire } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import getTile from '@salesforce/apex/ErrorLogController.getTile';
import acknowledge from '@salesforce/apex/ErrorLogController.acknowledge';

import TITLE from '@salesforce/label/c.Core_ErrorLogTile_Title';
import NEW_COUNT from '@salesforce/label/c.Core_ErrorLogTile_NewCount';
import EMPTY from '@salesforce/label/c.Core_ErrorLogTile_Empty';
import ACKNOWLEDGE from '@salesforce/label/c.Core_ErrorLogTile_Acknowledge';
import VIEW_ALL from '@salesforce/label/c.Core_ErrorLogTile_ViewAll';
import READ_ONLY from '@salesforce/label/c.Core_ErrorLogTile_ReadOnly';
import ACTION_FAILED from '@salesforce/label/c.Core_ErrorLog_ActionFailed';

const ROW_COUNT = 5;

export default class ErrorLogTile extends NavigationMixin(LightningElement) {
  labels = {
    title: TITLE,
    newCount: NEW_COUNT,
    empty: EMPTY,
    acknowledge: ACKNOWLEDGE,
    viewAll: VIEW_ALL,
    readOnly: READ_ONLY
  };

  tile;
  errorMessage;
  busy = false;

  @wire(getTile, { rowCount: ROW_COUNT })
  wiredTile({ data, error }) {
    if (data) {
      this.tile = data;
      this.errorMessage = undefined;
    } else if (error) {
      this.errorMessage = this.messageFrom(error);
    }
  }

  get newCount() {
    return this.tile ? this.tile.newCount : 0;
  }

  get newCountLabel() {
    return `${this.newCount} ${this.labels.newCount}`;
  }

  get entries() {
    return this.tile && this.tile.recent ? this.tile.recent : [];
  }

  get hasEntries() {
    return this.entries.length > 0;
  }

  get isEmpty() {
    return !!this.tile && !this.hasEntries;
  }

  get canUpdate() {
    return !!(this.tile && this.tile.canUpdate);
  }

  get isReadOnly() {
    return !!this.tile && !this.canUpdate;
  }

  get actionsDisabled() {
    return !this.canUpdate || this.busy;
  }

  get hasError() {
    return !!this.errorMessage;
  }

  handleAcknowledge(event) {
    const errorLogId = event.target.dataset.entry;
    this.busy = true;
    this.errorMessage = undefined;
    return acknowledge({ errorLogId })
      .then((tile) => {
        this.tile = tile;
      })
      .catch((error) => {
        this.errorMessage = this.messageFrom(error);
      })
      .finally(() => {
        this.busy = false;
      });
  }

  handleViewAll() {
    this[NavigationMixin.Navigate]({
      type: 'standard__objectPage',
      attributes: {
        objectApiName: 'Error_Log__c',
        actionName: 'list'
      },
      state: {
        filterName: 'New_Errors'
      }
    });
  }

  messageFrom(error) {
    if (error && error.body && error.body.message) {
      return error.body.message;
    }
    return ACTION_FAILED;
  }
}
