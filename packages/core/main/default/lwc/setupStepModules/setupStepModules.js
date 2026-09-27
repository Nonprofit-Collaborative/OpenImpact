import { LightningElement, api } from 'lwc';
import PRESENT from '@salesforce/label/c.Core_SetupAssistant_ModulePresent';
import ABSENT from '@salesforce/label/c.Core_SetupAssistant_ModuleAbsent';
import LEARN_MORE from '@salesforce/label/c.Core_SetupAssistant_ModuleLearnMore';
import MANAGER_NOTICE from '@salesforce/label/c.Core_SetupAssistant_ModuleManagerNotice';
import REQUIRED from '@salesforce/label/c.Core_SetupAssistant_ModuleRequired';
import OPTIONAL from '@salesforce/label/c.Core_SetupAssistant_ModuleOptional';
import HOW_TO_GET from '@salesforce/label/c.Core_SetupAssistant_ModuleHowToGet';
import INSTALL from '@salesforce/label/c.Core_SetupAssistant_ModuleInstallLink';

/**
 * The modules a suite offers (C-30): whether each is installed, whether the suite needs it,
 * where to read what it does, and how to get one that is not installed. A module's installer
 * is data (`Suite_Module__mdt.Install_Url__c`), so the Install link appears once a package
 * version is published; until then the row says how to get it in one sentence. Turning a
 * module on and off with one click is the Module Manager, and the notice says so rather than
 * pretending otherwise.
 */
export default class SetupStepModules extends LightningElement {
  @api modules = [];

  labels = {
    learnMore: LEARN_MORE,
    managerNotice: MANAGER_NOTICE,
    howToGet: HOW_TO_GET,
    install: INSTALL
  };

  get rows() {
    return (this.modules || []).map((module) => {
      const absent = !module.present;
      return {
        ...module,
        status: module.present ? PRESENT : ABSENT,
        statusClass: module.present
          ? 'slds-badge slds-theme_success'
          : 'slds-badge slds-badge_inverse',
        roleText: roleText(module.required),
        showInstallLink: absent && Boolean(module.installUrl),
        showHowToGet: absent && !module.installUrl
      };
    });
  }
}

// A module listed for a suite is required or optional; one listed outside a suite is neither.
function roleText(required) {
  if (required === true) {
    return REQUIRED;
  }
  return required === false ? OPTIONAL : undefined;
}
