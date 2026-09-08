import { LightningElement, api, wire } from 'lwc';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';
import { refreshApex } from '@salesforce/apex';
import getGiftReceiptState from '@salesforce/apex/ReceiptController.getGiftReceiptState';
import issueReceipt from '@salesforce/apex/ReceiptController.issue';
import voidAndReissue from '@salesforce/apex/ReceiptController.voidAndReissue';

/**
 * Issuing, voiding and reissuing a receipt from the gift's own page.
 *
 * One panel rather than two buttons, because the second thing a person wants after issuing a
 * receipt is to see it, and the thing they want after finding a mistake is to see both documents
 * side by side. A void is never offered without a reason box: a void with no reason is the record
 * an auditor cannot use.
 */
export default class ReceiptActions extends LightningElement {
  @api recordId;

  state;
  wiredState;
  reason = '';
  working = false;
  loadError;

  @wire(getGiftReceiptState, { giftId: '$recordId' })
  handleState(result) {
    this.wiredState = result;
    if (result.data) {
      this.state = result.data;
      this.loadError = undefined;
    } else if (result.error) {
      this.loadError = this.messageOf(result.error);
    }
  }

  get receipts() {
    return this.state ? this.state.receipts : [];
  }

  get hasReceipts() {
    return this.receipts.length > 0;
  }

  get canIssue() {
    return !!this.state && this.state.canIssue && !this.state.alreadyReceipted;
  }

  get canReissue() {
    return !!this.state && this.state.canIssue && this.state.alreadyReceipted;
  }

  get busy() {
    return this.working;
  }

  get issuedReceipt() {
    return this.receipts.find((receipt) => receipt.status === 'Issued');
  }

  handleReasonChange(event) {
    this.reason = event.detail.value;
  }

  async handleIssue() {
    this.working = true;
    try {
      const receipt = await issueReceipt({ giftId: this.recordId });
      this.toast('Success', `Receipt ${receipt.receiptNumber} issued.`, 'success');
      await refreshApex(this.wiredState);
    } catch (error) {
      this.toast('Receipt not issued', this.messageOf(error), 'error');
    } finally {
      this.working = false;
    }
  }

  async handleVoidAndReissue() {
    if (!this.reason || !this.reason.trim()) {
      this.toast(
        'Reason needed',
        'Say why this receipt is being voided. A void needs a reason and a date.',
        'warning'
      );
      return;
    }
    const current = this.issuedReceipt;
    if (!current) {
      return;
    }
    this.working = true;
    try {
      const replacement = await voidAndReissue({
        receiptId: current.id,
        reason: this.reason
      });
      this.toast(
        'Success',
        `Receipt ${current.receiptNumber} voided and reissued as ${replacement.receiptNumber}. The original file is unchanged.`,
        'success'
      );
      this.reason = '';
      await refreshApex(this.wiredState);
    } catch (error) {
      this.toast('Receipt not reissued', this.messageOf(error), 'error');
    } finally {
      this.working = false;
    }
  }

  messageOf(error) {
    if (!error) {
      return 'Something went wrong.';
    }
    if (error.body && error.body.message) {
      return error.body.message;
    }
    return error.message || 'Something went wrong.';
  }

  toast(title, message, variant) {
    this.dispatchEvent(new ShowToastEvent({ title, message, variant }));
  }
}
