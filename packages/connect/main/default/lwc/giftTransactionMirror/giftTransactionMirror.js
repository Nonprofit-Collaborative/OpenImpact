import { LightningElement } from 'lwc';
import LOCALE from '@salesforce/i18n/locale';
import CURRENCY from '@salesforce/i18n/currency';
import TIME_ZONE from '@salesforce/i18n/timeZone';
import getStatus from '@salesforce/apex/GiftTransactionMirrorController.getStatus';
import runNow from '@salesforce/apex/GiftTransactionMirrorController.runNow';
import schedule from '@salesforce/apex/GiftTransactionMirrorController.schedule';
import stop from '@salesforce/apex/GiftTransactionMirrorController.stop';
import compare from '@salesforce/apex/GiftTransactionMirrorController.compare';
import copyRangeAgain from '@salesforce/apex/GiftTransactionMirrorController.copyRangeAgain';
import title from '@salesforce/label/c.Connect_GiftTransactionMirror_Title';
import intro from '@salesforce/label/c.Connect_GiftTransactionMirror_Intro';
import unavailable from '@salesforce/label/c.Connect_GiftTransactionMirror_Unavailable';
import switchedOff from '@salesforce/label/c.Connect_GiftTransactionMirror_SwitchedOff';
import directionGifts from '@salesforce/label/c.Connect_GiftTransactionMirror_DirectionGifts';
import directionGiftTransactions from '@salesforce/label/c.Connect_GiftTransactionMirror_DirectionGiftTransactions';
import noManagePermission from '@salesforce/label/c.Connect_GiftTransactionMirror_NoManagePermission';
import noAccess from '@salesforce/label/c.Connect_GiftTransactionMirror_NoAccess';
import runNowLabel from '@salesforce/label/c.Connect_GiftTransactionMirror_RunNow';
import scheduleNightly from '@salesforce/label/c.Connect_GiftTransactionMirror_ScheduleNightly';
import stopSchedule from '@salesforce/label/c.Connect_GiftTransactionMirror_StopSchedule';
import nextRun from '@salesforce/label/c.Connect_GiftTransactionMirror_NextRun';
import notScheduled from '@salesforce/label/c.Connect_GiftTransactionMirror_NotScheduled';
import running from '@salesforce/label/c.Connect_GiftTransactionMirror_RunningNow';
import started from '@salesforce/label/c.Connect_GiftTransactionMirror_Started';
import reconciliationTitle from '@salesforce/label/c.Connect_GiftTransactionMirror_ReconciliationTitle';
import reconciliationIntro from '@salesforce/label/c.Connect_GiftTransactionMirror_ReconciliationIntro';
import fromDate from '@salesforce/label/c.Connect_GiftTransactionMirror_FromDate';
import toDate from '@salesforce/label/c.Connect_GiftTransactionMirror_ToDate';
import compareLabel from '@salesforce/label/c.Connect_GiftTransactionMirror_Compare';
import copyAgain from '@salesforce/label/c.Connect_GiftTransactionMirror_CopyAgain';
import giftSide from '@salesforce/label/c.Connect_GiftTransactionMirror_GiftSide';
import giftTransactionSide from '@salesforce/label/c.Connect_GiftTransactionMirror_GiftTransactionSide';
import noDifferences from '@salesforce/label/c.Connect_GiftTransactionMirror_NoDifferences';
import differenceCount from '@salesforce/label/c.Connect_GiftTransactionMirror_DifferenceCount';
import differenceCountAll from '@salesforce/label/c.Connect_GiftTransactionMirror_DifferenceCountAll';
import columnGift from '@salesforce/label/c.Connect_GiftTransactionMirror_ColumnGift';
import columnGiftAmount from '@salesforce/label/c.Connect_GiftTransactionMirror_ColumnGiftAmount';
import columnGiftDate from '@salesforce/label/c.Connect_GiftTransactionMirror_ColumnGiftDate';
import columnGiftTransaction from '@salesforce/label/c.Connect_GiftTransactionMirror_ColumnGiftTransaction';
import columnGiftTransactionAmount from '@salesforce/label/c.Connect_GiftTransactionMirror_ColumnGiftTransactionAmount';
import columnTransactionDate from '@salesforce/label/c.Connect_GiftTransactionMirror_ColumnTransactionDate';
import columnDifference from '@salesforce/label/c.Connect_GiftTransactionMirror_ColumnDifference';
import errorFailed from '@salesforce/label/c.Connect_GiftTransactionMirror_ErrorFailed';
import lastRun from '@salesforce/label/c.Connect_GiftTransactionMirror_LastRun';
import noLastRun from '@salesforce/label/c.Connect_GiftTransactionMirror_NoLastRun';
import loading from '@salesforce/label/c.Connect_GiftTransactionMirror_Loading';

const GIFTS_TO_GIFT_TRANSACTIONS = 'GiftsToGiftTransactions';
const OFF = 'Off';
/** How often the page asks whether a run it shows as running has finished. */
const POLL_MS = 10000;

function fill(template, ...values) {
  return values.reduce((text, value, index) => text.replace(`{${index}}`, value), template);
}

function isoDate(date) {
  const month = String(date.getMonth() + 1).padStart(2, '0');
  const day = String(date.getDate()).padStart(2, '0');
  return `${date.getFullYear()}-${month}-${day}`;
}

/**
 * The Gift Transaction mirror page (feature X-07). The controller decides what the org and the
 * person allow, and what is still missing, and refuses in words; the page shows the direction,
 * the run and schedule buttons, and the reconciliation of a date range.
 */
export default class GiftTransactionMirror extends LightningElement {
  labels = {
    loading,
    title,
    intro,
    unavailable,
    switchedOff,
    noManagePermission,
    noAccess,
    runNow: runNowLabel,
    scheduleNightly,
    stopSchedule,
    reconciliationTitle,
    reconciliationIntro,
    fromDate,
    toDate,
    compare: compareLabel,
    copyAgain
  };

  columns = [
    {
      label: columnGift,
      fieldName: 'giftUrl',
      type: 'url',
      typeAttributes: { label: { fieldName: 'giftName' } }
    },
    {
      label: columnGiftAmount,
      fieldName: 'giftAmount',
      type: 'currency',
      typeAttributes: { currencyCode: CURRENCY }
    },
    { label: columnGiftDate, fieldName: 'giftDate', type: 'date-local' },
    {
      label: columnGiftTransaction,
      fieldName: 'giftTransactionUrl',
      type: 'url',
      typeAttributes: { label: { fieldName: 'giftTransactionLabel' } }
    },
    {
      label: columnGiftTransactionAmount,
      fieldName: 'giftTransactionAmount',
      type: 'currency',
      typeAttributes: { currencyCode: CURRENCY }
    },
    { label: columnTransactionDate, fieldName: 'transactionDate', type: 'date-local' },
    { label: columnDifference, fieldName: 'reason', wrapText: true }
  ];

  status;
  comparison;
  working = false;
  justStarted = false;
  error;
  fromDate = isoDate(new Date(new Date().getFullYear(), 0, 1));
  toDate = isoDate(new Date());
  /** The range last compared, which Copy again copies whatever the date fields say now. */
  compared;
  pollTimer;

  connectedCallback() {
    this.load();
  }

  disconnectedCallback() {
    clearTimeout(this.pollTimer);
  }

  async load() {
    this.error = undefined;
    try {
      this.show(await getStatus());
    } catch (failure) {
      this.error = this.messageOf(failure);
    }
  }

  /** Shows a status, and while a run is going asks again until it has finished. */
  show(status) {
    this.status = status;
    clearTimeout(this.pollTimer);
    if (status && status.running) {
      // eslint-disable-next-line @lwc/lwc/no-async-operation
      this.pollTimer = setTimeout(() => this.refresh(), POLL_MS);
    } else {
      this.justStarted = false;
    }
  }

  async refresh() {
    try {
      this.show(await getStatus());
    } catch (failure) {
      this.error = this.messageOf(failure);
    }
  }

  get loaded() {
    return Boolean(this.status);
  }

  get spinnerShown() {
    return this.working || (!this.loaded && !this.error);
  }

  money(amount) {
    return new Intl.NumberFormat(LOCALE, { style: 'currency', currency: CURRENCY }).format(
      amount || 0
    );
  }

  /** A date the server sends as yyyy-mm-dd, in the viewer's locale, on that same day. */
  day(value) {
    return new Intl.DateTimeFormat(LOCALE, { dateStyle: 'medium', timeZone: 'UTC' }).format(
      new Date(`${value}T00:00:00Z`)
    );
  }

  moment(value) {
    return new Intl.DateTimeFormat(LOCALE, {
      dateStyle: 'medium',
      timeStyle: 'short',
      timeZone: TIME_ZONE
    }).format(new Date(value));
  }

  get available() {
    return this.loaded && this.status.available;
  }

  get unavailableShown() {
    return this.loaded && !this.status.available;
  }

  get offShown() {
    return this.available && this.status.direction === OFF;
  }

  get onShown() {
    return this.available && this.status.direction !== OFF;
  }

  /** The paid status or the start date is missing or unknown, so nothing is mirrored yet. */
  get notReadyShown() {
    return this.onShown && Boolean(this.status.notReady);
  }

  get directionText() {
    const template =
      this.status.direction === GIFTS_TO_GIFT_TRANSACTIONS
        ? directionGifts
        : directionGiftTransactions;
    return fill(template, this.day(this.status.startDate), this.status.paidStatus);
  }

  get scheduled() {
    return Boolean(this.status && this.status.nextRunAt);
  }

  get scheduleText() {
    return this.scheduled ? fill(nextRun, this.moment(this.status.nextRunAt)) : notScheduled;
  }

  get lastRunText() {
    return this.status.lastRunAt
      ? fill(lastRun, this.moment(this.status.lastRunAt), this.status.lastSummary || '')
      : noLastRun;
  }

  get noManageShown() {
    return this.onShown && !this.status.canManage;
  }

  get noAccessShown() {
    return this.onShown && this.status.canManage && !this.status.canRun;
  }

  get runningShown() {
    return this.onShown && this.status.running;
  }

  get runningText() {
    return this.justStarted ? started : running;
  }

  get manageDisabled() {
    return this.working || !this.status.canManage;
  }

  get scheduleDisabled() {
    return this.manageDisabled || !this.status.canRun || this.notReadyShown;
  }

  get runDisabled() {
    return this.scheduleDisabled || !this.onShown || this.status.running;
  }

  get copyAgainShown() {
    return (
      this.onShown && this.status.direction === GIFTS_TO_GIFT_TRANSACTIONS && this.hasDifferences
    );
  }

  get hasDifferences() {
    return Boolean(this.comparison && this.comparison.differenceCount > 0);
  }

  get giftSideText() {
    return fill(giftSide, this.comparison.giftCount, this.money(this.comparison.giftTotal));
  }

  get giftTransactionSideText() {
    return fill(
      giftTransactionSide,
      this.comparison.giftTransactionCount,
      this.money(this.comparison.giftTransactionTotal)
    );
  }

  get differenceText() {
    if (!this.hasDifferences) {
      return noDifferences;
    }
    const { differenceCount: count, differences } = this.comparison;
    return count > differences.length
      ? fill(differenceCount, count, differences.length)
      : fill(differenceCountAll, count);
  }

  get rows() {
    return this.comparison.differences.map((row) => ({
      ...row,
      giftUrl: row.giftId ? `/${row.giftId}` : undefined,
      giftTransactionUrl: row.giftTransactionId ? `/${row.giftTransactionId}` : undefined,
      giftTransactionLabel: row.giftTransactionName || row.giftTransactionId
    }));
  }

  handleFrom(event) {
    this.fromDate = event.target.value;
  }

  handleTo(event) {
    this.toDate = event.target.value;
  }

  handleRunNow() {
    this.act(() => runNow(), true);
  }

  handleSchedule() {
    this.act(() => schedule(), false);
  }

  handleStop() {
    this.act(() => stop(), false);
  }

  handleCopyAgain() {
    this.act(() => copyRangeAgain({ ...this.compared }), true);
  }

  async handleCompare() {
    this.error = undefined;
    this.working = true;
    const range = { fromDate: this.fromDate, toDate: this.toDate };
    try {
      this.comparison = await compare(range);
      this.compared = range;
    } catch (failure) {
      this.comparison = undefined;
      this.compared = undefined;
      this.error = this.messageOf(failure);
    } finally {
      this.working = false;
    }
  }

  async act(call, starts) {
    this.error = undefined;
    this.working = true;
    try {
      const status = await call();
      this.justStarted = starts;
      this.show(status);
    } catch (failure) {
      this.error = this.messageOf(failure);
    } finally {
      this.working = false;
    }
  }

  messageOf(failure) {
    return (failure && failure.body && failure.body.message) || errorFailed;
  }
}
