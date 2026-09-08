import { LightningElement, api } from 'lwc';
import USER_ID from '@salesforce/user/Id';
import LEGAL_NAME from '@salesforce/label/c.Core_SetupAssistant_LegalNameLabel';
import EIN from '@salesforce/label/c.Core_SetupAssistant_EinLabel';
import ADDRESS from '@salesforce/label/c.Core_SetupAssistant_AddressLabel';
import LOGO from '@salesforce/label/c.Core_SetupAssistant_LogoLabel';
import SIGNATURE from '@salesforce/label/c.Core_SetupAssistant_SignatureLabel';
import SIGNER_NAME from '@salesforce/label/c.Core_SetupAssistant_SignerNameLabel';
import SIGNER_TITLE from '@salesforce/label/c.Core_SetupAssistant_SignerTitleLabel';
import UPLOAD_HELP from '@salesforce/label/c.Core_SetupAssistant_UploadHelp';
import EIN_PATTERN_MESSAGE from '@salesforce/label/c.Core_SetupAssistant_EinPatternMessage';
import LOGO_PREVIEW_ALT from '@salesforce/label/c.Core_SetupAssistant_LogoPreviewAlt';
import SIGNATURE_PREVIEW_ALT from '@salesforce/label/c.Core_SetupAssistant_SignaturePreviewAlt';
import SAVE from '@salesforce/label/c.Core_SetupAssistant_SaveButton';

const LOGO_KEY = 'Receipt_Logo_Document_Id__c';
const SIGNATURE_KEY = 'Receipt_Signature_Document_Id__c';
const FILE_URL = '/sfc/servlet.shepherd/document/download/';
// A tax identification number in the United States: two digits, a hyphen, seven digits.
// Left blank elsewhere, which the help text says.
const EIN_PATTERN = '[0-9]{2}-[0-9]{7}';

/**
 * Step five: the name, tax identification number, address, signer, logo, and signature
 * that receipts and letters are printed with.
 *
 * Salesforce attaches every uploaded file to a record, and a logo belongs to no record in
 * particular, so the upload goes on the current user's own record and only the file's
 * identifier is kept in settings. The admin guide records that limitation.
 */
export default class SetupStepIdentity extends LightningElement {
  @api canEdit = false;

  userId = USER_ID;
  draft = {};

  labels = {
    legalName: LEGAL_NAME,
    ein: EIN,
    address: ADDRESS,
    logo: LOGO,
    signature: SIGNATURE,
    signerName: SIGNER_NAME,
    signerTitle: SIGNER_TITLE,
    uploadHelp: UPLOAD_HELP,
    einPattern: EIN_PATTERN_MESSAGE,
    logoAlt: LOGO_PREVIEW_ALT,
    signatureAlt: SIGNATURE_PREVIEW_ALT,
    save: SAVE
  };

  einPattern = EIN_PATTERN;

  @api
  get values() {
    return this.draft;
  }

  set values(value) {
    this.draft = { ...(value || {}) };
  }

  get isReadOnly() {
    return !this.canEdit;
  }

  get acceptedFormats() {
    return ['.png', '.jpg', '.jpeg'];
  }

  // Maria never sees the file's record identifier, only the picture it points at
  // (plan Section 2.3: no setting requires knowing an API name).
  get logoUrl() {
    return this.fileUrl(LOGO_KEY);
  }

  get signatureUrl() {
    return this.fileUrl(SIGNATURE_KEY);
  }

  fileUrl(key) {
    return this.draft[key] ? `${FILE_URL}${this.draft[key]}` : undefined;
  }

  handleFieldChange(event) {
    const key = event.target.dataset.key;
    this.draft = { ...this.draft, [key]: event.target.value };
  }

  handleLogoUploaded(event) {
    this.recordFile(LOGO_KEY, event);
  }

  handleSignatureUploaded(event) {
    this.recordFile(SIGNATURE_KEY, event);
  }

  recordFile(key, event) {
    const files = (event.detail && event.detail.files) || [];
    if (files.length === 0) {
      return;
    }
    this.draft = { ...this.draft, [key]: files[0].documentId };
    this.handleSave();
  }

  handleSave() {
    this.dispatchEvent(new CustomEvent('save', { detail: { values: { ...this.draft } } }));
  }
}
