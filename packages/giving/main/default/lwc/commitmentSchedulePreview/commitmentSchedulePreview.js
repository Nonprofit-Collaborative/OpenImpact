import { LightningElement, api } from 'lwc';
import getSchedule from '@salesforce/apex/CommitmentController.getSchedule';
import generateNow from '@salesforce/apex/CommitmentController.generateNow';

import TITLE from '@salesforce/label/c.Giving_SchedulePreview_Title';
import EMPTY from '@salesforce/label/c.Giving_SchedulePreview_Empty';
import GENERATE_NOW from '@salesforce/label/c.Giving_SchedulePreview_GenerateNow';
import GENERATED from '@salesforce/label/c.Giving_SchedulePreview_Generated';
import GENERATE_ERROR from '@salesforce/label/c.Giving_SchedulePreview_GenerateError';
import LOAD_ERROR from '@salesforce/label/c.Giving_SchedulePreview_LoadError';
import COLUMN_SEQUENCE from '@salesforce/label/c.Giving_SchedulePreview_ColumnSequence';
import COLUMN_DUE_DATE from '@salesforce/label/c.Giving_SchedulePreview_ColumnDueDate';
import COLUMN_AMOUNT from '@salesforce/label/c.Giving_SchedulePreview_ColumnAmount';
import COLUMN_PAID from '@salesforce/label/c.Giving_SchedulePreview_ColumnPaid';
import COLUMN_STATUS from '@salesforce/label/c.Giving_SchedulePreview_ColumnStatus';

const BADGE_BY_STATUS = {
  Paid: 'slds-theme_success',
  'Partially paid': 'slds-theme_warning',
  Overdue: 'slds-theme_error',
  Skipped: 'slds-theme_shade'
};

/**
 * The payment schedule of a commitment, shown on the commitment record page: what is due,
 * when, what has been paid, and where each payment stands. When a commitment has no
 * schedule yet, it offers to generate one.
 */
export default class CommitmentSchedulePreview extends LightningElement {
  @api recordId;

  installments = [];
  loading = true;
  errorMessage;
  noticeMessage;

  labels = {
    title: TITLE,
    empty: EMPTY,
    generateNow: GENERATE_NOW,
    sequence: COLUMN_SEQUENCE,
    dueDate: COLUMN_DUE_DATE,
    amount: COLUMN_AMOUNT,
    paid: COLUMN_PAID,
    status: COLUMN_STATUS
  };

  connectedCallback() {
    this.load();
  }

  get hasInstallments() {
    return this.installments.length > 0;
  }

  get isEmpty() {
    return !this.loading && !this.errorMessage && this.installments.length === 0;
  }

  async load() {
    this.loading = true;
    this.errorMessage = undefined;
    try {
      const schedule = await getSchedule({ commitmentId: this.recordId });
      this.installments = this.decorate(schedule);
    } catch (error) {
      this.installments = [];
      this.errorMessage = this.messageFrom(error, LOAD_ERROR);
    } finally {
      this.loading = false;
    }
  }

  async handleGenerate() {
    this.loading = true;
    this.errorMessage = undefined;
    this.noticeMessage = undefined;
    try {
      const schedule = await generateNow({ commitmentId: this.recordId });
      this.installments = this.decorate(schedule);
      this.noticeMessage = GENERATED;
    } catch (error) {
      this.errorMessage = this.messageFrom(error, GENERATE_ERROR);
    } finally {
      this.loading = false;
    }
  }

  /** Adds the badge class each status wears, so the template stays free of logic. */
  decorate(schedule) {
    const rows = schedule && schedule.installments ? schedule.installments : [];
    return rows.map((row) => ({
      ...row,
      key: row.recordId || `preview-${row.sequence}`,
      badgeClass: BADGE_BY_STATUS[row.status] || 'slds-theme_default'
    }));
  }

  messageFrom(error, fallback) {
    if (error && error.body && error.body.message) {
      return error.body.message;
    }
    return fallback;
  }
}
