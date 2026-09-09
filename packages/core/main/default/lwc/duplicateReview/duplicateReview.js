import { LightningElement, wire } from 'lwc';
import { refreshApex } from '@salesforce/apex';
// Bare, and correctly so: a custom permission defined in the same package resolves without a
// namespace prefix.
import canManageSettings from '@salesforce/customPermission/Manage_Nonprofit_Settings';
import getView from '@salesforce/apex/DuplicateController.getView';
import startScan from '@salesforce/apex/DuplicateController.startScan';
import dismissSuggestion from '@salesforce/apex/DuplicateController.dismiss';
import previewMerge from '@salesforce/apex/DuplicateController.previewMerge';
import mergeHouseholds from '@salesforce/apex/DuplicateController.mergeHouseholds';

import TITLE from '@salesforce/label/c.Core_Duplicates_Title';
import RULES_HEADING from '@salesforce/label/c.Core_Duplicates_RulesHeading';
import RULE_ACTIVE from '@salesforce/label/c.Core_Duplicates_RuleActive';
import RULE_INACTIVE from '@salesforce/label/c.Core_Duplicates_RuleInactive';
import ACTIVATE_LINK from '@salesforce/label/c.Core_Duplicates_ActivateLink';
import NO_RULES_NOTICE from '@salesforce/label/c.Core_Duplicates_NoRulesNotice';
import SCAN_BUTTON from '@salesforce/label/c.Core_Duplicates_ScanButton';
import SCAN_STARTED from '@salesforce/label/c.Core_Duplicates_ScanStarted';
import SCAN_RUNNING from '@salesforce/label/c.Core_Duplicates_ScanRunning';
import LAST_SCAN from '@salesforce/label/c.Core_Duplicates_LastScan';
import SUGGESTIONS_HEADING from '@salesforce/label/c.Core_Duplicates_SuggestionsHeading';
import EMPTY from '@salesforce/label/c.Core_Duplicates_Empty';
import OPEN_BUTTON from '@salesforce/label/c.Core_Duplicates_OpenButton';
import MERGE_BUTTON from '@salesforce/label/c.Core_Duplicates_MergeButton';
import MERGE_HEADING from '@salesforce/label/c.Core_Duplicates_MergeHeading';
import MERGE_BODY from '@salesforce/label/c.Core_Duplicates_MergeBody';
import MERGE_KEEP_LABEL from '@salesforce/label/c.Core_Duplicates_MergeKeepLabel';
import MERGE_CONFIRM from '@salesforce/label/c.Core_Duplicates_MergeConfirm';
import MERGE_FULL_SCREEN from '@salesforce/label/c.Core_Duplicates_MergeFullScreen';
import MERGE_SUCCESS from '@salesforce/label/c.Core_Duplicates_MergeSuccess';
import PEOPLE_MERGE_NOTICE from '@salesforce/label/c.Core_Duplicates_PeopleMergeNotice';
import DISMISS_BUTTON from '@salesforce/label/c.Core_Duplicates_DismissButton';
import DISMISS_HEADING from '@salesforce/label/c.Core_Duplicates_DismissHeading';
import DISMISS_BODY from '@salesforce/label/c.Core_Duplicates_DismissBody';
import DISMISS_REASON_LABEL from '@salesforce/label/c.Core_Duplicates_DismissReasonLabel';
import DISMISS_SUCCESS from '@salesforce/label/c.Core_Duplicates_DismissSuccess';
import DISMISSED_COUNT from '@salesforce/label/c.Core_Duplicates_DismissedCount';
import READ_ONLY from '@salesforce/label/c.Core_Duplicates_ReadOnlyNotice';
import CANCEL from '@salesforce/label/c.Core_Duplicates_Cancel';
import UNEXPECTED_ERROR from '@salesforce/label/c.Core_Duplicates_ErrorUnexpected';

const SETUP_DUPLICATE_RULES = '/lightning/setup/DuplicateRules/home';

/**
 * The Duplicates panel on the Households page of the Nonprofit Settings console.
 *
 * Everything it lists was found by the platform's own duplicate rules, so the first thing it
 * shows is whether those rules are switched on: a page that says "nothing to review" while
 * nothing is being checked would be worse than no page at all.
 *
 * Two households are merged here, in a dialog, because that is the action this page exists to
 * make quick. Everything richer than choosing which household survives, field by field
 * choices in particular, is the household merge screen the record page already carries, and
 * the dialog links to it rather than growing a second copy of it.
 */
export default class DuplicateReview extends LightningElement {
  labels = {
    title: TITLE,
    rulesHeading: RULES_HEADING,
    activateLink: ACTIVATE_LINK,
    noRulesNotice: NO_RULES_NOTICE,
    scanButton: SCAN_BUTTON,
    scanRunning: SCAN_RUNNING,
    lastScan: LAST_SCAN,
    suggestionsHeading: SUGGESTIONS_HEADING,
    empty: EMPTY,
    open: OPEN_BUTTON,
    merge: MERGE_BUTTON,
    mergeHeading: MERGE_HEADING,
    mergeBody: MERGE_BODY,
    mergeKeepLabel: MERGE_KEEP_LABEL,
    mergeConfirm: MERGE_CONFIRM,
    mergeFullScreen: MERGE_FULL_SCREEN,
    peopleMergeNotice: PEOPLE_MERGE_NOTICE,
    dismiss: DISMISS_BUTTON,
    dismissHeading: DISMISS_HEADING,
    dismissBody: DISMISS_BODY,
    dismissReasonLabel: DISMISS_REASON_LABEL,
    dismissedCount: DISMISSED_COUNT,
    readOnly: READ_ONLY,
    cancel: CANCEL
  };

  setupUrl = SETUP_DUPLICATE_RULES;

  view;
  errorMessage;
  noticeMessage;
  busy = false;
  wiredViewResult;

  dismissing;
  dismissReason = '';

  merging;
  mergePreview;
  keepId;

  @wire(getView)
  wiredView(result) {
    this.wiredViewResult = result;
    if (result.data) {
      this.view = result.data;
      this.errorMessage = undefined;
    } else if (result.error) {
      this.errorMessage = this.messageFrom(result.error);
    }
  }

  // ------------------------------------------------------------------ what is shown

  get rules() {
    if (!this.view || !this.view.rules) {
      return [];
    }
    return this.view.rules.map((rule) => ({
      key: `${rule.objectLabel}-${rule.ruleLabel}`,
      objectLabel: rule.objectLabel,
      ruleLabel: rule.ruleLabel,
      state: rule.active ? RULE_ACTIVE : RULE_INACTIVE
    }));
  }

  get showNoRulesNotice() {
    return !!this.view && this.view.anyRuleActive === false;
  }

  get scanRunning() {
    return !!(this.view && this.view.scanRunning);
  }

  get lastScanFinished() {
    return this.view ? this.view.lastScanFinished : undefined;
  }

  get hasLastScan() {
    return !!this.lastScanFinished;
  }

  get dismissedCount() {
    return this.view ? this.view.dismissedCount : 0;
  }

  /**
   * The suggestions with the two things the markup cannot work out for itself: a link to each
   * record, and whether this pair is two households, which is the only pair this page merges.
   */
  get suggestions() {
    if (!this.view || !this.view.suggestions) {
      return [];
    }
    return this.view.suggestions.map((suggestion) => ({
      setId: suggestion.setId,
      foundAt: suggestion.foundAt,
      ruleLabel: suggestion.ruleLabel,
      canMerge: suggestion.canMerge === true,
      showPeopleNotice: suggestion.canMerge !== true,
      records: suggestion.records.map((record) => ({
        recordId: record.recordId,
        name: record.name,
        detail: record.detail,
        objectLabel: record.objectLabel,
        url: `/lightning/r/${record.recordId}/view`
      }))
    }));
  }

  get hasSuggestions() {
    return this.suggestions.length > 0;
  }

  /**
   * Read from the platform rather than from the payload, so the buttons are disabled before
   * the first round trip finishes rather than flickering. The controller checks it again,
   * which is where the real gate is.
   */
  get canManage() {
    return canManageSettings === true;
  }

  get showReadOnlyNote() {
    return !this.canManage;
  }

  get controlsDisabled() {
    return this.busy || !this.canManage;
  }

  // ------------------------------------------------------------------ the scan

  handleScan() {
    this.runAction(startScan(), SCAN_STARTED);
  }

  // ------------------------------------------------------------------ not a duplicate

  handleDismissClick(event) {
    this.dismissing = event.target.dataset.setId;
    this.dismissReason = '';
  }

  handleReasonChange(event) {
    this.dismissReason = event.target.value;
  }

  handleDismissConfirm() {
    const setId = this.dismissing;
    this.dismissing = undefined;
    this.runAction(
      dismissSuggestion({ duplicateRecordSetId: setId, reason: this.dismissReason }),
      DISMISS_SUCCESS
    );
  }

  // ------------------------------------------------------------------ merge

  async handleMergeClick(event) {
    const setId = event.target.dataset.setId;
    const suggestion = this.suggestions.find((row) => row.setId === setId);
    if (!suggestion) {
      return;
    }
    this.merging = suggestion;
    this.keepId = suggestion.records[0].recordId;
    await this.loadPreview();
  }

  handleKeepChange(event) {
    this.keepId = event.detail.value;
    this.loadPreview();
  }

  async loadPreview() {
    this.busy = true;
    this.errorMessage = undefined;
    try {
      this.mergePreview = await previewMerge({
        survivorId: this.keepId,
        victimId: this.otherId
      });
    } catch (error) {
      this.errorMessage = this.messageFrom(error);
      this.merging = undefined;
    } finally {
      this.busy = false;
    }
  }

  get otherId() {
    if (!this.merging) {
      return undefined;
    }
    const other = this.merging.records.find((record) => record.recordId !== this.keepId);
    return other ? other.recordId : undefined;
  }

  get keepOptions() {
    if (!this.merging) {
      return [];
    }
    return this.merging.records.map((record) => ({
      label: record.name,
      value: record.recordId
    }));
  }

  /** Only the fields the two households disagree about: the rest need no decision. */
  get conflictingFields() {
    if (!this.mergePreview || !this.mergePreview.fields) {
      return [];
    }
    return this.mergePreview.fields
      .filter((field) => field.inConflict)
      .map((field) => ({
        key: field.fieldName,
        label: field.label,
        kept: field.survivorValue,
        dropped: field.victimValue
      }));
  }

  get hasConflictingFields() {
    return this.conflictingFields.length > 0;
  }

  get mergeScreenUrl() {
    return this.keepId ? `/lightning/r/Account/${this.keepId}/view` : undefined;
  }

  handleMergeConfirm() {
    const setId = this.merging ? this.merging.setId : undefined;
    const survivorId = this.keepId;
    const victimId = this.otherId;
    this.merging = undefined;
    this.mergePreview = undefined;
    this.runAction(
      mergeHouseholds({
        duplicateRecordSetId: setId,
        survivorId,
        victimId,
        fieldChoices: {}
      }),
      MERGE_SUCCESS
    );
  }

  handleCancel() {
    this.dismissing = undefined;
    this.merging = undefined;
    this.mergePreview = undefined;
  }

  get showDismissDialog() {
    return !!this.dismissing;
  }

  get showMergeDialog() {
    return !!this.merging;
  }

  // ------------------------------------------------------------------ plumbing

  async runAction(promise, notice) {
    this.busy = true;
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
    try {
      this.view = await promise;
      this.noticeMessage = notice;
      if (this.wiredViewResult) {
        await refreshApex(this.wiredViewResult);
      }
    } catch (error) {
      this.errorMessage = this.messageFrom(error);
    } finally {
      this.busy = false;
    }
  }

  messageFrom(error) {
    const body = error && error.body;
    return (body && body.message) || UNEXPECTED_ERROR;
  }
}
