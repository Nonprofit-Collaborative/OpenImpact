import { LightningElement, api, wire, track } from 'lwc';
import { refreshApex } from '@salesforce/apex';
import { getRecord } from 'lightning/uiRecordApi';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import getMembers from '@salesforce/apex/HouseholdController.getMembers';
import getMembershipMode from '@salesforce/apex/HouseholdController.getMembershipMode';
import moveContact from '@salesforce/apex/HouseholdController.moveContact';

import TITLE from '@salesforce/label/c.Core_HouseholdMembersPanel_Title';
import EMPTY from '@salesforce/label/c.Core_HouseholdMembersPanel_Empty';
import NOT_A_HOUSEHOLD from '@salesforce/label/c.Core_HouseholdMembersPanel_NotAHousehold';
import PRIMARY from '@salesforce/label/c.Core_HouseholdMembersPanel_Primary';
import DECEASED from '@salesforce/label/c.Core_HouseholdMembersPanel_Deceased';
import ADD_MEMBER from '@salesforce/label/c.Core_HouseholdMembersPanel_AddMember';
import ADD_MEMBER_JUNCTION from '@salesforce/label/c.Core_HouseholdMembersPanel_AddMemberJunction';
import MOVE_MEMBER from '@salesforce/label/c.Core_HouseholdMembersPanel_MoveMember';
import MOVE_HELP from '@salesforce/label/c.Core_HouseholdMembersPanel_MoveHelp';
import MOVE_SUCCESS from '@salesforce/label/c.Core_HouseholdMembersPanel_MoveSuccess';
import ADD_SUCCESS from '@salesforce/label/c.Core_HouseholdMembersPanel_AddSuccess';
import SAVE from '@salesforce/label/c.Core_HouseholdMembersPanel_Save';
import CANCEL from '@salesforce/label/c.Core_HouseholdMembersPanel_Cancel';

const RECORD_TYPE_FIELD = 'Account.RecordType.DeveloperName';
const HOUSEHOLD = 'Household';
const JUNCTION = 'Junction';

export default class HouseholdMembersPanel extends LightningElement {
  @api recordId;

  label = {
    title: TITLE,
    empty: EMPTY,
    notAHousehold: NOT_A_HOUSEHOLD,
    primary: PRIMARY,
    deceased: DECEASED,
    addMember: ADD_MEMBER,
    addMemberJunction: ADD_MEMBER_JUNCTION,
    moveMember: MOVE_MEMBER,
    moveHelp: MOVE_HELP,
    save: SAVE,
    cancel: CANCEL
  };

  @track members = [];
  membershipMode;
  recordTypeName;
  errorMessage;
  isAdding = false;
  movingPersonId;
  targetHouseholdId;

  membersResult;

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

  @wire(getMembershipMode)
  wiredMode({ data, error }) {
    if (data) {
      this.membershipMode = data;
    } else if (error) {
      this.errorMessage = this.readError(error);
    }
  }

  @wire(getMembers, { householdId: '$recordId' })
  wiredMembers(result) {
    this.membersResult = result;
    if (result.data) {
      this.members = result.data.map((member) => ({
        ...member,
        badges: this.badgesFor(member)
      }));
      this.errorMessage = undefined;
    } else if (result.error) {
      this.members = [];
      this.errorMessage = this.readError(result.error);
    }
  }

  get isHousehold() {
    return this.recordTypeName === HOUSEHOLD;
  }

  get isJunctionMode() {
    return this.membershipMode === JUNCTION;
  }

  get canAddMember() {
    return this.isHousehold && !this.isJunctionMode;
  }

  get hasMembers() {
    return this.members.length > 0;
  }

  get isMoving() {
    return !!this.movingPersonId;
  }

  badgesFor(member) {
    const badges = [];
    if (member.isPrimary) {
      badges.push({ key: `${member.personId}-primary`, text: PRIMARY });
    }
    if (member.isDeceased) {
      badges.push({ key: `${member.personId}-deceased`, text: DECEASED });
    }
    return badges;
  }

  handleAddClick() {
    this.isAdding = true;
  }

  handleAddCancel() {
    this.isAdding = false;
  }

  handleAddSuccess() {
    this.isAdding = false;
    this.toast(ADD_SUCCESS, 'success');
    return this.refresh();
  }

  handleMoveClick(event) {
    this.movingPersonId = event.target.dataset.personId;
    this.targetHouseholdId = undefined;
  }

  handleMoveCancel() {
    this.movingPersonId = undefined;
    this.targetHouseholdId = undefined;
  }

  handleTargetChange(event) {
    const value = event.detail.value;
    this.targetHouseholdId = Array.isArray(value) ? value[0] : value;
  }

  handleMoveSave() {
    const personId = this.movingPersonId;
    const targetId = this.targetHouseholdId;
    return moveContact({ contactId: personId, targetHouseholdId: targetId })
      .then(() => {
        this.movingPersonId = undefined;
        this.targetHouseholdId = undefined;
        this.errorMessage = undefined;
        this.toast(MOVE_SUCCESS, 'success');
        return this.refresh();
      })
      .catch((error) => {
        this.errorMessage = this.readError(error);
      });
  }

  refresh() {
    return refreshApex(this.membersResult);
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
