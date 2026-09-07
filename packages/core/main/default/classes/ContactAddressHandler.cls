/**
 * Contact trigger handler, registered as "Keep a household together when a person's
 * address changes" in the automation registry and dispatched by TriggerDispatcher on the
 * one Contact trigger, so no other feature's handler is touched by this one.
 *
 * When a person's mailing address is entered or changed, the org's Addresses setting
 * decides what happens: the household moves together, or that person gets an address of
 * their own (canonical model R-AD5).
 */
public with sharing class ContactAddressHandler implements TriggerHandler {
    public void beforeInsert(List<SObject> newRecords) {
        // Nothing to do before insert.
    }

    public void beforeUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
        // Nothing to do before update.
    }

    public void beforeDelete(List<SObject> oldRecords) {
        // Nothing to do before delete: an address record outlives the person who moved.
    }

    public void afterInsert(List<SObject> newRecords) {
        capture((List<Contact>) newRecords);
    }

    public void afterUpdate(List<SObject> newRecords, Map<Id, SObject> oldMap) {
        List<Contact> moved = new List<Contact>();
        for (Contact contact : (List<Contact>) newRecords) {
            Contact old = (Contact) oldMap.get(contact.Id);
            if (old == null || mailingAddressChanged(contact, old)) {
                moved.add(contact);
            }
        }
        capture(moved);
    }

    public void afterDelete(List<SObject> oldRecords) {
        // Nothing to do after delete.
    }

    public void afterUndelete(List<SObject> newRecords) {
        // Nothing to do after undelete: the address records were never removed.
    }

    private void capture(List<Contact> contacts) {
        if (contacts.isEmpty()) {
            return;
        }
        try {
            AddressService.captureFromStandardFields(null, contacts);
        } catch (Exception e) {
            ErrorLogger.log(e, 'ContactAddressHandler.capture');
            for (Contact contact : contacts) {
                contact.addError(Label.Core_Address_PropagationFailed);
            }
        }
    }

    private Boolean mailingAddressChanged(Contact contact, Contact old) {
        return contact.MailingStreet != old.MailingStreet ||
            contact.MailingCity != old.MailingCity ||
            contact.MailingState != old.MailingState ||
            contact.MailingPostalCode != old.MailingPostalCode ||
            contact.MailingCountry != old.MailingCountry;
    }
}
