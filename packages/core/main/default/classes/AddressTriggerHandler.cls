/**
 * Address__c trigger handler, registered as "Copy the default address to the standard
 * address fields" in the automation registry and dispatched by TriggerDispatcher, so an
 * administrator can switch it off from Nonprofit Settings without touching Setup.
 *
 * After insert and after update it copies the default address into the standard address
 * fields. After delete it promotes the most recently created remaining address for that
 * owner: deleting the default is allowed rather than blocked, because refusing the delete
 * would leave a household holding an address it does not use and no way out of the app.
 */
public with sharing class AddressTriggerHandler implements TriggerHandler {
    public void beforeInsert(List<SObject> newRecords) {
        // Nothing to do before insert: an address has no id to propagate from yet.
    }

    public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
        // Nothing to do before update.
    }

    public void beforeDelete(List<SObject> oldRecords) {
        // Nothing to do before delete: the promotion runs after the row is gone.
    }

    public void afterInsert(List<SObject> newRecords) {
        sync((List<Address__c>) newRecords);
    }

    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
        sync(changedAddresses((List<Address__c>) newRecords, oldMap));
    }

    public void afterDelete(List<SObject> oldRecords) {
        List<Address__c> deleted = (List<Address__c>) oldRecords;
        try {
            AddressService.promoteDefaultAfterDelete(deleted);
        } catch (Exception e) {
            report(e, deleted, 'AddressTriggerHandler.afterDelete');
        }
    }

    public void afterUndelete(List<SObject> newRecords) {
        sync((List<Address__c>) newRecords);
    }

    private void sync(List<Address__c> addresses) {
        if (addresses.isEmpty()) {
            return;
        }
        try {
            AddressService.syncDefaultToStandardFields(addresses);
        } catch (Exception e) {
            report(e, addresses, 'AddressTriggerHandler.sync');
        }
    }

    /**
     * Only the addresses whose default flag or address text actually moved. Saving an
     * address without changing where it points should not rewrite every household
     * member's mailing address.
     */
    private List<Address__c> changedAddresses(
        List<Address__c> newRecords,
        Map<Id, SObject> oldMap
    ) {
        List<Address__c> changed = new List<Address__c>();
        for (Address__c address : newRecords) {
            Address__c old = (Address__c) oldMap.get(address.Id);
            if (old == null) {
                changed.add(address);
                continue;
            }
            Boolean moved =
                address.Is_Default__c != old.Is_Default__c ||
                address.Street__c != old.Street__c ||
                address.City__c != old.City__c ||
                address.State__c != old.State__c ||
                address.Postal_Code__c != old.Postal_Code__c ||
                address.Country__c != old.Country__c ||
                address.Account__c != old.Account__c ||
                address.Contact__c != old.Contact__c ||
                address.Person_Account__c != old.Person_Account__c;
            if (moved) {
                changed.add(address);
            }
        }
        return changed;
    }

    private void report(Exception e, List<Address__c> records, String context) {
        ErrorLogger.log(e, context);
        for (Address__c address : records) {
            address.addError(Label.Core_Address_PropagationFailed);
        }
    }
}
