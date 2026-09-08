/**
 * Test data for the Giving package's own objects. Core's TestDataFactory builds households,
 * contacts and organizations; this builds the giving records on top of them, so a test reads
 * as a story about David and Maria rather than as a pile of field assignments.
 */
@IsTest
public class GivingTestDataFactory {
    /**
     * A fund. Pass isDefault true for the one that undesignated gifts should go to.
     */
    public static Fund__c buildFund(String name, Boolean isDefault) {
        return new Fund__c(
            Name = name,
            Active__c = true,
            Restricted__c = false,
            Is_Default__c = isDefault
        );
    }

    /**
     * An inserted default fund named "General", which is what most organizations call it and
     * what the admin guide walks David through creating.
     */
    public static Fund__c insertDefaultFund() {
        Fund__c fund = buildFund('General', true);
        insert fund;
        return fund;
    }

    /**
     * An appeal, active, with no goal unless the test sets one.
     */
    public static Appeal__c buildAppeal(String name) {
        return new Appeal__c(Name = name, Active__c = true, Start_Date__c = Date.today());
    }

    /**
     * A gift from a contact, ready to insert.
     */
    public static Gift__c buildGift(Id donorContactId, Decimal amount) {
        return new Gift__c(
            Donor_Contact__c = donorContactId,
            Amount__c = amount,
            Type__c = 'Check',
            Status__c = 'Received',
            Acknowledgment_Status__c = 'To acknowledge'
        );
    }

    /**
     * A gift from an account: an organization, a household giving in its own name, or a person
     * held as an account.
     */
    public static Gift__c buildAccountGift(Id donorAccountId, Decimal amount) {
        return new Gift__c(
            Donor_Account__c = donorAccountId,
            Amount__c = amount,
            Type__c = 'Check',
            Status__c = 'Received',
            Acknowledgment_Status__c = 'To acknowledge'
        );
    }

    /**
     * Many gifts from one donor, for the bulk tests that prove one save of two hundred records
     * stays inside the platform's limits (plan Section 7.2).
     */
    public static List<Gift__c> buildGifts(Id donorContactId, Integer howMany, Decimal amount) {
        List<Gift__c> gifts = new List<Gift__c>();
        for (Integer i = 0; i < howMany; i++) {
            gifts.add(buildGift(donorContactId, amount));
        }
        return gifts;
    }

    /**
     * An allocation of part of a gift to a fund.
     */
    public static Gift_Allocation__c buildAllocation(Id giftId, Id fundId, Decimal amount) {
        return new Gift_Allocation__c(Gift__c = giftId, Fund__c = fundId, Amount__c = amount);
    }

    /**
     * A household account and a contact in it, named for the persona a test is about. Returns
     * the contact, whose AccountId is the household.
     */
    public static Contact insertHouseholdContact(
        String householdName,
        String firstName,
        String lastName
    ) {
        Account household = new Account(Name = householdName);
        insert household;
        Contact person = new Contact(
            FirstName = firstName,
            LastName = lastName,
            AccountId = household.Id
        );
        insert person;
        return person;
    }

    /**
     * An organization account, for the donor path where no household is derived.
     */
    public static Account insertOrganization(String name) {
        Account organization = new Account(Name = name);
        insert organization;
        return organization;
    }
}
