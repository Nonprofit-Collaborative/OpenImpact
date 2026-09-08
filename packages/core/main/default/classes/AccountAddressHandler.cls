/**
 * Account trigger handler, registered as "Keep the address a household or organization
 * was created with" in the automation registry and dispatched by TriggerDispatcher on the
 * one Account trigger.
 *
 * A household or organization created with its billing address already filled in, by
 * staff or by an import, gets that address kept as its first address record, marked
 * default, so the records are the truth from the first save (canonical model R-AD3).
 *
 * Every context method takes no arguments and reads the trigger collections through the
 * accessors on TriggerHandler.
 */
public with sharing class AccountAddressHandler extends TriggerHandler {
    public override void afterInsert() {
        List<Account> accounts = (List<Account>) newRecords();
        if (accounts == null || accounts.isEmpty()) {
            return;
        }
        try {
            AddressService.captureFromStandardFields(accounts, null);
        } catch (Exception thrown) {
            ErrorLogger.log(thrown, 'AccountAddressHandler.afterInsert');
            for (Account account : accounts) {
                account.addError(Label.Core_Address_PropagationFailed);
            }
        }
    }
}
