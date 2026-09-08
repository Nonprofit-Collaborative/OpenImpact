/**
 * The records the soft credit, tribute, and matching gift tests need.
 *
 * The Garcia family is the household these features are documented with, so it is the household
 * they are tested with: Ana Garcia gives, Luis Garcia is recognized, and Riverbend Manufacturing
 * is the employer that matches.
 *
 * This is deliberately a small local factory rather than an addition to the Giving package's
 * shared factory: it builds only what recognition needs, and it does not have to be kept in step
 * with a feature it does not test.
 */
@IsTest
public class RecognitionTestData {
    public static final String HOUSEHOLD_RECORD_TYPE = 'Household';
    public static final String ORGANIZATION_RECORD_TYPE = 'Organization';

    /**
     * Writes the giving setting that decides whether household members are credited
     * automatically.
     */
    public static void setAutomaticHouseholdCredits(Boolean enabled) {
        Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
        settings.SetupOwnerId = UserInfo.getOrganizationId();
        settings.Automatic_Household_Soft_Credits__c = enabled;
        upsert settings;
    }

    /**
     * Switches the org to junction membership, the mode a Person Account org runs in.
     */
    public static void useJunctionMembership() {
        Nonprofit_Settings__c settings = Nonprofit_Settings__c.getOrgDefaults();
        settings.SetupOwnerId = UserInfo.getOrganizationId();
        settings.Household_Membership_Mode__c = 'Junction';
        upsert settings;
    }

    public static Account household(String name) {
        Account record = new Account(Name = name);
        Id recordTypeId = recordTypeId(HOUSEHOLD_RECORD_TYPE);
        if (recordTypeId != null) {
            record.RecordTypeId = recordTypeId;
        }
        insert record;
        return record;
    }

    public static Account organization(String name) {
        Account record = new Account(Name = name);
        Id recordTypeId = recordTypeId(ORGANIZATION_RECORD_TYPE);
        if (recordTypeId != null) {
            record.RecordTypeId = recordTypeId;
        }
        insert record;
        return record;
    }

    public static Contact person(String firstName, String lastName, Id householdId) {
        Contact record = new Contact(FirstName = firstName, LastName = lastName);
        if (householdId != null) {
            record.AccountId = householdId;
        }
        insert record;
        return record;
    }

    public static Household_Member__c membership(Id householdId, Id contactId, String role) {
        Household_Member__c member = new Household_Member__c(
            Account__c = householdId,
            Contact__c = contactId,
            Role__c = role
        );
        insert member;
        return member;
    }

    public static Gift__c newGift(Id donorContactId, Id donorAccountId, Decimal amount) {
        Gift__c gift = new Gift__c(
            Donor_Contact__c = donorContactId,
            Donor_Account__c = donorAccountId,
            Amount__c = amount,
            Gift_Date__c = Date.today(),
            Type__c = 'Check',
            Status__c = 'Received'
        );
        return gift;
    }

    public static Gift__c gift(Id donorContactId, Id donorAccountId, Decimal amount) {
        Gift__c gift = newGift(donorContactId, donorAccountId, amount);
        insert gift;
        return gift;
    }

    public static Soft_Credit__c manualCredit(
        Id giftId,
        Id contactId,
        String role,
        Decimal amount
    ) {
        Soft_Credit__c credit = new Soft_Credit__c(
            Gift__c = giftId,
            Contact__c = contactId,
            Role__c = role,
            Amount__c = amount,
            Is_Automatic__c = false
        );
        insert credit;
        return credit;
    }

    public static Tribute__c tribute(Id giftId, String tributeType, String honoreeName) {
        return new Tribute__c(
            Gift__c = giftId,
            Type__c = tributeType,
            Honoree_Name__c = honoreeName
        );
    }

    public static List<Soft_Credit__c> creditsFor(Id giftId) {
        return [
            SELECT Id, Contact__c, Account__c, Role__c, Amount__c, Percent__c, Is_Automatic__c
            FROM Soft_Credit__c
            WHERE Gift__c = :giftId
            ORDER BY Name
        ];
    }

    private static Id recordTypeId(String developerName) {
        Schema.RecordTypeInfo info = Schema.SObjectType.Account.getRecordTypeInfosByDeveloperName()
            .get(developerName);
        return info == null || !info.isAvailable() ? null : info.getRecordTypeId();
    }
}
