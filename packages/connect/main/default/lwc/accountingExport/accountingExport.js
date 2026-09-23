import { LightningElement, wire } from 'lwc';
import FUND_OBJECT from '@salesforce/schema/Fund__c';
import LOCALE from '@salesforce/i18n/locale';
import CURRENCY from '@salesforce/i18n/currency';
import getPaymentMethods from '@salesforce/apex/AccountingExportController.getPaymentMethods';
import exportGifts from '@salesforce/apex/AccountingExportController.exportGifts';
import title from '@salesforce/label/c.Connect_AccountingExport_Title';
import intro from '@salesforce/label/c.Connect_AccountingExport_Intro';
import visibility from '@salesforce/label/c.Connect_AccountingExport_Visibility';
import from from '@salesforce/label/c.Connect_AccountingExport_From';
import to from '@salesforce/label/c.Connect_AccountingExport_To';
import fund from '@salesforce/label/c.Connect_AccountingExport_Fund';
import allFunds from '@salesforce/label/c.Connect_AccountingExport_AllFunds';
import paymentMethod from '@salesforce/label/c.Connect_AccountingExport_PaymentMethod';
import allMethods from '@salesforce/label/c.Connect_AccountingExport_AllMethods';
import download from '@salesforce/label/c.Connect_AccountingExport_Download';
import summary from '@salesforce/label/c.Connect_AccountingExport_Summary';
import noGifts from '@salesforce/label/c.Connect_AccountingExport_NoGifts';
import errorDatesRequired from '@salesforce/label/c.Connect_AccountingExport_ErrorDatesRequired';
import errorFailed from '@salesforce/label/c.Connect_AccountingExport_ErrorFailed';

/**
 * The Accounting Export page (feature X-04). The service decides what is in the file and
 * refuses a bad range in words; the page only collects the choices, saves the file and says
 * what it held.
 */
export default class AccountingExport extends LightningElement {
  labels = {
    title,
    intro,
    visibility,
    from,
    to,
    fund,
    allFunds,
    paymentMethod,
    allMethods,
    download
  };

  fromDate;
  toDate;
  fundId;
  paymentMethod = '';
  methods = [];
  working = false;
  error;
  message;

  get fundObjectApiName() {
    return FUND_OBJECT.objectApiName;
  }

  get methodOptions() {
    return [{ label: allMethods, value: '' }].concat(this.methods);
  }

  @wire(getPaymentMethods)
  wiredMethods({ data, error }) {
    if (data) {
      this.methods = data.map((option) => ({ label: option.label, value: option.value }));
    } else if (error) {
      this.error = errorFailed;
    }
  }

  handleFromChange(event) {
    this.fromDate = event.detail.value;
  }

  handleToChange(event) {
    this.toDate = event.detail.value;
  }

  handleFundChange(event) {
    this.fundId = event.detail.recordId || undefined;
  }

  handleMethodChange(event) {
    this.paymentMethod = event.detail.value;
  }

  async handleDownload() {
    this.error = undefined;
    this.message = undefined;
    if (!this.fromDate || !this.toDate) {
      this.error = errorDatesRequired;
      return;
    }
    this.working = true;
    try {
      const view = await exportGifts({
        fromDate: this.fromDate,
        toDate: this.toDate,
        fundId: this.fundId || null,
        paymentMethod: this.paymentMethod || null
      });
      if (!view || !view.rowCount) {
        this.message = noGifts;
        return;
      }
      this.save(view.fileName, view.csv);
      this.message = summary
        .replace('{0}', view.rowCount)
        .replace('{1}', view.giftCount)
        .replace('{2}', this.money(view.total));
    } catch (failure) {
      this.error = (failure && failure.body && failure.body.message) || errorFailed;
    } finally {
      this.working = false;
    }
  }

  money(amount) {
    return new Intl.NumberFormat(LOCALE, { style: 'currency', currency: CURRENCY }).format(
      amount || 0
    );
  }

  /** A Blob, not a data URI: 10,000 rows is over a megabyte, past what browsers take in a URL. */
  save(fileName, csv) {
    const url = URL.createObjectURL(new Blob([csv], { type: 'text/csv;charset=utf-8' }));
    const link = document.createElement('a');
    link.href = url;
    link.download = fileName;
    link.click();
    URL.revokeObjectURL(url);
  }
}
