/**
 * Account trigger handler, registered as "Keep the address a household or organization
 * was created with" in the automation registry and dispatched by TriggerDispatcher on the
 * one Account trigger.
 *
 * A household or organization created with its billing address already filled in, by
 * staff or by an import, gets that address kept as its first address record, marked
 * default, so the records are the truth from the first save (canonical model R-AD3).
 */
public with sharing class AccountAddressHandler implements TriggerHandler {
    public void beforeInsert(List<SObject> newRecords) {
        // Nothing to do before insert.
    }

    public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
        // Nothing to do before update: the address panel, not the billing fields, is
        // where a household's address is changed once it has an address on file.
    }

    public void beforeDelete(List<SObject> oldRecords) {
        // Nothing to do before delete.
    }

    public void afterInsert(List<SObject> newRecords) {
        List<Account> accounts = (List<Account>) newRecords;
        if (accounts.isEmpty()) {
            return;
        }
        try {
            AddressService.captureFromStandardFields(accounts, null);
        } catch (Exception e) {
            ErrorLogger.log(e, 'AccountAddressHandler.afterInsert');
            for (Account account : accounts) {
                account.addError(Label.Core_Address_PropagationFailed);
            }
        }
    }

    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
        // Nothing to do after update.
    }

    public void afterDelete(List<SObject> oldRecords) {
        // Nothing to do after delete.
    }

    public void afterUndelete(List<SObject> newRecords) {
        // Nothing to do after undelete.
    }
}
