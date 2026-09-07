import { LightningElement, api, wire, track } from 'lwc';
import { NavigationMixin } from 'lightning/navigation';
import { getRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import searchHouseholds from '@salesforce/apex/HouseholdMergeController.searchHouseholds';
import canEdit from '@salesforce/apex/HouseholdMergeController.canEdit';
import getPreview from '@salesforce/apex/HouseholdMergeController.preview';
import mergeHouseholds from '@salesforce/apex/HouseholdMergeController.mergeHouseholds';
import splitHousehold from '@salesforce/apex/HouseholdMergeController.splitHousehold';
import getMembers from '@salesforce/apex/HouseholdController.getMembers';

import TITLE from '@salesforce/label/c.Core_HouseholdMerge_Title';
import TAB_MERGE from '@salesforce/label/c.Core_HouseholdMerge_TabMerge';
import TAB_SPLIT from '@salesforce/label/c.Core_HouseholdMerge_TabSplit';
import SEARCH_LABEL from '@salesforce/label/c.Core_HouseholdMerge_SearchLabel';
import SEARCH_PLACEHOLDER from '@salesforce/label/c.Core_HouseholdMerge_SearchPlaceholder';
import NO_RESULTS from '@salesforce/label/c.Core_HouseholdMerge_NoResults';
import SELECT_OTHER from '@salesforce/label/c.Core_HouseholdMerge_SelectOther';
import COLUMN_FIELD from '@salesforce/label/c.Core_HouseholdMerge_ColumnField';
import COLUMN_THIS from '@salesforce/label/c.Core_HouseholdMerge_ColumnThis';
import COLUMN_OTHER from '@salesforce/label/c.Core_HouseholdMerge_ColumnOther';
import MEMBERS_HEADING from '@salesforce/label/c.Core_HouseholdMerge_MembersHeading';
import KEEP_SURVIVOR from '@salesforce/label/c.Core_HouseholdMerge_KeepSurvivor';
import KEEP_VICTIM from '@salesforce/label/c.Core_HouseholdMerge_KeepVictim';
import MEMBER_FROM_THIS from '@salesforce/label/c.Core_HouseholdMerge_MemberFromThis';
import MEMBER_FROM_OTHER from '@salesforce/label/c.Core_HouseholdMerge_MemberFromOther';
import MERGE_BUTTON from '@salesforce/label/c.Core_HouseholdMerge_MergeButton';
import CONFIRM_HEADING from '@salesforce/label/c.Core_HouseholdMerge_ConfirmHeading';
import CONFIRM_BODY from '@salesforce/label/c.Core_HouseholdMerge_ConfirmBody';
import CONFIRM_BUTTON from '@salesforce/label/c.Core_HouseholdMerge_ConfirmButton';
import CANCEL from '@salesforce/label/c.Core_HouseholdMerge_Cancel';
import MERGE_SUCCESS from '@salesforce/label/c.Core_HouseholdMerge_Success';
import READ_ONLY from '@salesforce/label/c.Core_HouseholdMerge_ReadOnly';
import NOT_A_HOUSEHOLD from '@salesforce/label/c.Core_HouseholdMerge_NotAHousehold';
import SPLIT_HEADING from '@salesforce/label/c.Core_HouseholdMerge_SplitHeading';
import SPLIT_NEW from '@salesforce/label/c.Core_HouseholdMerge_SplitNewHousehold';
import SPLIT_EXISTING from '@salesforce/label/c.Core_HouseholdMerge_SplitExistingHousehold';
import SPLIT_BUTTON from '@salesforce/label/c.Core_HouseholdMerge_SplitButton';
import SPLIT_CONFIRM_BODY from '@salesforce/label/c.Core_HouseholdMerge_SplitConfirmBody';
import SPLIT_SUCCESS from '@salesforce/label/c.Core_HouseholdMerge_SplitSuccess';

const RECORD_TYPE_FIELD = 'Account.RecordType.DeveloperName';
const HOUSEHOLD = 'Household';
const SURVIVOR = 'Survivor';
const VICTIM = 'Victim';
const NEW_HOUSEHOLD = 'New';
const EXISTING_HOUSEHOLD = 'Existing';

export default class HouseholdMergeSplit extends NavigationMixin(LightningElement) {
  @api recordId;

  label = {
    title: TITLE,
    tabMerge: TAB_MERGE,
    tabSplit: TAB_SPLIT,
    searchLabel: SEARCH_LABEL,
    searchPlaceholder: SEARCH_PLACEHOLDER,
    noResults: NO_RESULTS,
    selectOther: SELECT_OTHER,
    columnField: COLUMN_FIELD,
    columnThis: COLUMN_THIS,
    columnOther: COLUMN_OTHER,
    membersHeading: MEMBERS_HEADING,
    mergeButton: MERGE_BUTTON,
    confirmHeading: CONFIRM_HEADING,
    confirmButton: CONFIRM_BUTTON,
    cancel: CANCEL,
    readOnly: READ_ONLY,
    notAHousehold: NOT_A_HOUSEHOLD,
    splitHeading: SPLIT_HEADING,
    splitNew: SPLIT_NEW,
    splitExisting: SPLIT_EXISTING,
    splitButton: SPLIT_BUTTON,
    splitConfirmBody: SPLIT_CONFIRM_BODY
  };

  recordTypeName;
  canEditThis = false;
  errorMessage;
  busy = false;

  @track searchResults = [];
  searchTerm = '';
  searchedOnce = false;
  otherHouseholdId;
  otherHouseholdName;

  @track comparison = [];
  @track mergeMembers = [];
  choices = {};
  confirmingMerge = false;

  @track splitMembers = [];
  splitDestination = NEW_HOUSEHOLD;
  splitTargetId;
  confirmingSplit = false;

  @wire(getRecord, { recordId: '$recordId', fields: [RECORD_TYPE_FIELD] })
  wiredAccount({ data, error }) {
    if (data) {
      const recordType = data.fields.RecordType;
      this.recordTypeName =
        recordType && recordType.value ? recordType.value.fields.DeveloperName.value : undefined;
    } else if (error) {
      this.errorMessage = this.readError(error);
    }
  }

  @wire(canEdit, { householdId: '$recordId' })
  wiredCanEdit({ data, error }) {
    if (data !== undefined) {
      this.canEditThis = data === true;
    } else if (error) {
      this.errorMessage = this.readError(error);
    }
  }

  @wire(getMembers, { householdId: '$recordId' })
  wiredMembers({ data, error }) {
    if (data) {
      this.splitMembers = data.map((member) => ({ ...member, selected: false }));
    } else if (error) {
      this.errorMessage = this.readError(error);
    }
  }

  // ---------------------------------------------------------------- state

  get isHousehold() {
    return this.recordTypeName === HOUSEHOLD;
  }

  get showReadOnlyNotice() {
    return this.isHousehold && !this.canEditThis;
  }

  get isUsable() {
    return this.isHousehold && this.canEditThis;
  }

  get hasSearchResults() {
    return this.searchResults.length > 0;
  }

  get showNoResults() {
    return this.searchedOnce && !this.hasSearchResults && !this.otherHouseholdId;
  }

  get hasComparison() {
    return this.comparison.length > 0;
  }

  get confirmBody() {
    return CONFIRM_BODY.replace('{0}', this.otherHouseholdName || '').replace(
      '{1}',
      this.survivorName || ''
    );
  }

  survivorName;

  get selectedPersonIds() {
    return this.splitMembers.filter((member) => member.selected).map((member) => member.personId);
  }

  get canSplit() {
    if (this.selectedPersonIds.length === 0) {
      return false;
    }
    return this.splitDestination === NEW_HOUSEHOLD ? true : !!this.splitTargetId;
  }

  get isSplittingToExisting() {
    return this.splitDestination === EXISTING_HOUSEHOLD;
  }

  get destinationOptions() {
    return [
      { label: this.label.splitNew, value: NEW_HOUSEHOLD },
      { label: this.label.splitExisting, value: EXISTING_HOUSEHOLD }
    ];
  }

  // ---------------------------------------------------------------- merge

  handleSearchChange(event) {
    this.searchTerm = event.target.value;
  }

  handleSearch() {
    this.searchedOnce = true;
    return searchHouseholds({ term: this.searchTerm, excludeId: this.recordId })
      .then((results) => {
        this.searchResults = results || [];
        this.errorMessage = undefined;
      })
      .catch((error) => {
        this.searchResults = [];
        this.errorMessage = this.readError(error);
      });
  }

  handlePickHousehold(event) {
    const chosenId = event.target.dataset.householdId;
    const chosen = this.searchResults.find((row) => row.id === chosenId);
    this.otherHouseholdId = chosenId;
    this.otherHouseholdName = chosen ? chosen.name : '';
    return this.loadPreview();
  }

  loadPreview() {
    this.busy = true;
    return getPreview({ survivorId: this.recordId, victimId: this.otherHouseholdId })
      .then((preview) => {
        this.survivorName = preview.survivorName;
        this.choices = {};
        this.comparison = preview.fields.map((field) => ({
          ...field,
          options: [
            { label: KEEP_SURVIVOR, value: SURVIVOR },
            { label: KEEP_VICTIM, value: VICTIM }
          ],
          selected: SURVIVOR
        }));
        this.mergeMembers = preview.members.map((member) => ({
          ...member,
          origin: member.fromSurvivor ? MEMBER_FROM_THIS : MEMBER_FROM_OTHER
        }));
        this.errorMessage = undefined;
      })
      .catch((error) => {
        this.comparison = [];
        this.mergeMembers = [];
        this.errorMessage = this.readError(error);
      })
      .finally(() => {
        this.busy = false;
      });
  }

  handleChoiceChange(event) {
    const fieldName = event.target.dataset.fieldName;
    const value = event.detail.value;
    this.choices = { ...this.choices, [fieldName]: value };
    this.comparison = this.comparison.map((field) => {
      return field.fieldName === fieldName ? { ...field, selected: value } : field;
    });
  }

  handleMergeClick() {
    this.confirmingMerge = true;
  }

  handleMergeCancel() {
    this.confirmingMerge = false;
  }

  handleMergeConfirm() {
    this.busy = true;
    return mergeHouseholds({
      survivorId: this.recordId,
      victimId: this.otherHouseholdId,
      fieldChoices: this.choices
    })
      .then((survivorId) => {
        this.confirmingMerge = false;
        this.errorMessage = undefined;
        this.toast(MERGE_SUCCESS, 'success');
        this.goTo(survivorId);
      })
      .catch((error) => {
        this.confirmingMerge = false;
        this.errorMessage = this.readError(error);
      })
      .finally(() => {
        this.busy = false;
      });
  }

  // ---------------------------------------------------------------- split

  handleMemberToggle(event) {
    const personId = event.target.dataset.personId;
    const checked = event.target.checked;
    this.splitMembers = this.splitMembers.map((member) => {
      return member.personId === personId ? { ...member, selected: checked } : member;
    });
  }

  handleDestinationChange(event) {
    this.splitDestination = event.detail.value;
    this.splitTargetId = undefined;
  }

  handleSplitTargetChange(event) {
    const value = event.detail.value;
    this.splitTargetId = Array.isArray(value) ? value[0] : value;
  }

  handleSplitClick() {
    this.confirmingSplit = true;
  }

  handleSplitCancel() {
    this.confirmingSplit = false;
  }

  handleSplitConfirm() {
    this.busy = true;
    return splitHousehold({
      householdId: this.recordId,
      personIds: this.selectedPersonIds,
      targetHouseholdId: this.splitDestination === NEW_HOUSEHOLD ? null : this.splitTargetId
    })
      .then((destinationId) => {
        this.confirmingSplit = false;
        this.errorMessage = undefined;
        this.toast(SPLIT_SUCCESS, 'success');
        this.goTo(destinationId);
      })
      .catch((error) => {
        this.confirmingSplit = false;
        this.errorMessage = this.readError(error);
      })
      .finally(() => {
        this.busy = false;
      });
  }

  // ---------------------------------------------------------------- helpers

  goTo(recordId) {
    this[NavigationMixin.Navigate]({
      type: 'standard__recordPage',
      attributes: { recordId, objectApiName: 'Account', actionName: 'view' }
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
