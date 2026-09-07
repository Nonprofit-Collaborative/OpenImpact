/**
 * Household test data. Kept apart from the shared TestDataFactory so that the household
 * feature can add helpers without touching a file every other feature also edits.
 */
@IsTest
public class HouseholdTestDataFactory {
    public static final String MODE_CONTACT = 'Contact';
    public static final String MODE_JUNCTION = 'Junction';

    /**
     * Org level settings with the shipped defaults, so that a test never depends on what
     * another test left behind.
     */
    public static Nonprofit_Settings__c settings(String membershipMode) {
        Nonprofit_Settings__c record = Nonprofit_Settings__c.getOrgDefaults();
        record.Household_Membership_Mode__c = membershipMode;
        record.Auto_Create_Households__c = true;
        record.Delete_Empty_Households__c = true;
        record.Create_Households_For_Person_Accounts__c = false;
        record.Household_Name_Pattern__c = 'The {LastName} Family';
        record.Formal_Greeting_Pattern__c = '{Salutation} {FirstName} {LastName}';
        record.Informal_Greeting_Pattern__c = '{FirstName}';
        record.Include_Deceased_In_Name__c = false;
        upsert record;
        return record;
    }

    public static Nonprofit_Settings__c save(Nonprofit_Settings__c record) {
        upsert record;
        return record;
    }

    public static Contact newContact(String firstName, String lastName) {
        return new Contact(FirstName = firstName, LastName = lastName, Salutation = 'Ms.');
    }

    public static Contact newContact(String salutation, String firstName, String lastName) {
        return new Contact(Salutation = salutation, FirstName = firstName, LastName = lastName);
    }

    public static Account newHousehold(String name) {
        return new Account(
            Name = name,
            RecordTypeId = HouseholdService.householdRecordTypeId(),
            Custom_Name__c = false,
            Member_Count__c = 0
        );
    }

    public static HouseholdService.Person person(
        String salutation,
        String firstName,
        String lastName,
        String role
    ) {
        HouseholdService.Person result = new HouseholdService.Person();
        result.salutation = salutation;
        result.firstName = firstName;
        result.lastName = lastName;
        result.role = role;
        return result;
    }

    /**
     * Maria Garcia and Wei Lee, the pair the admin guide walkthrough uses.
     */
    public static List<HouseholdService.Person> garciaAndLee() {
        return new List<HouseholdService.Person>{
            person('Ms.', 'Maria', 'Garcia', 'Head'),
            person('Mr.', 'Wei', 'Lee', 'Spouse or Partner')
        };
    }

    /**
     * A couple who share a surname, as David would enter them.
     */
    public static List<HouseholdService.Person> smithCouple() {
        return new List<HouseholdService.Person>{
            person('Mr.', 'John', 'Smith', 'Head'),
            person('Mrs.', 'Jane', 'Smith', 'Spouse or Partner')
        };
    }

    public static List<Contact> manyContacts(Integer howMany, String lastName) {
        List<Contact> result = new List<Contact>();
        for (Integer i = 0; i < howMany; i++) {
            result.add(
                new Contact(FirstName = 'Person' + i, LastName = lastName + i, Salutation = 'Mx.')
            );
        }
        return result;
    }
}
