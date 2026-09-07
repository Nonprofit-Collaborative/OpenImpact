/**
 * What the household screens call. Every method validates what it is given and returns a
 * shape the component can render, or an error a person can read.
 */
public with sharing class HouseholdController {
    /**
     * One sample household in the naming preview.
     */
    public class HouseholdPreview {
        @AuraEnabled
        public String members;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String formalGreeting;
        @AuraEnabled
        public String informalGreeting;
    }

    /**
     * One member of a household, as the members panel shows them.
     */
    public class MemberView {
        @AuraEnabled
        public Id personId;
        @AuraEnabled
        public String name;
        @AuraEnabled
        public String role;
        @AuraEnabled
        public String source;
        @AuraEnabled
        public Boolean isPrimary;
        @AuraEnabled
        public Boolean isDeceased;
    }

    /**
     * Five sample households, computed in memory from the patterns being typed. Nothing is
     * read from or written to the org's own households. R-H14.
     */
    @AuraEnabled(cacheable=true)
    public static List<HouseholdPreview> preview(
        String namePattern,
        String formalPattern,
        String informalPattern
    ) {
        try {
            Nonprofit_Settings__c settings = SettingsService.getSettings();
            Boolean includeDeceased =
                settings != null &&
                settings.Include_Deceased_In_Name__c == true;
            List<HouseholdPreview> result = new List<HouseholdPreview>();
            for (List<HouseholdService.Person> members : sampleHouseholds()) {
                HouseholdPreview row = new HouseholdPreview();
                row.members = describe(members);
                row.name = HouseholdNamingService.computeName(
                    members,
                    namePattern,
                    includeDeceased
                );
                row.formalGreeting = HouseholdNamingService.computeFormalGreeting(
                    members,
                    formalPattern,
                    includeDeceased
                );
                row.informalGreeting = HouseholdNamingService.computeInformalGreeting(
                    members,
                    informalPattern
                );
                result.add(row);
            }
            return result;
        } catch (Exception e) {
            throw asUserError(e);
        }
    }

    /**
     * Starts the batch that rewrites every household that is not marked as a custom name,
     * and gives the screen the job id so it can report progress.
     */
    @AuraEnabled
    public static String recomputeAll() {
        try {
            return String.valueOf(Database.executeBatch(new HouseholdNamingBatch(), 200));
        } catch (Exception e) {
            ErrorLogger.log(e, Label.Core_Households_ErrorContextNaming);
            throw asUserError(e);
        }
    }

    @AuraEnabled(cacheable=true)
    public static List<MemberView> getMembers(Id householdId) {
        try {
            if (householdId == null || householdId.getSObjectType() != Account.SObjectType) {
                throw new HouseholdException(Label.Core_Households_ErrorNotAHousehold);
            }
            List<MemberView> result = new List<MemberView>();
            Map<Id, List<HouseholdService.Person>> membersByHousehold = HouseholdService.getMembers(
                new Set<Id>{ householdId }
            );
            List<HouseholdService.Person> members = membersByHousehold.get(householdId);
            if (members == null) {
                return result;
            }
            for (HouseholdService.Person person : members) {
                MemberView row = new MemberView();
                row.personId = person.id;
                row.name = fullName(person);
                row.role = person.role;
                row.source = person.sourceObject;
                row.isPrimary = person.isPrimary == true;
                row.isDeceased = person.isDeceased == true;
                result.add(row);
            }
            return result;
        } catch (Exception e) {
            throw asUserError(e);
        }
    }

    @AuraEnabled
    public static void moveContact(Id contactId, Id targetHouseholdId) {
        try {
            HouseholdService.moveContact(contactId, targetHouseholdId);
        } catch (Exception e) {
            ErrorLogger.log(e, Label.Core_Households_ErrorContextMembership, contactId);
            throw asUserError(e);
        }
    }

    // ------------------------------------------------------------------ helpers

    private static AuraHandledException asUserError(Exception e) {
        AuraHandledException error = new AuraHandledException(e.getMessage());
        error.setMessage(e.getMessage());
        return error;
    }

    private static String fullName(HouseholdService.Person person) {
        String first = String.isNotBlank(person.preferredName)
            ? person.preferredName
            : person.firstName;
        String full =
            (first == null ? '' : first) +
            ' ' +
            (person.lastName == null ? '' : person.lastName);
        return full.trim();
    }

    private static String describe(List<HouseholdService.Person> members) {
        List<String> names = new List<String>();
        for (HouseholdService.Person person : members) {
            names.add(fullName(person));
        }
        return String.join(names, ', ');
    }

    /**
     * The five sample households the preview uses, read from a custom label so that they
     * can be translated. Each household is separated by a vertical bar, each member by a
     * semicolon, and each member reads: title, first name, surname, preferred name, role,
     * and Y when the person has died.
     */
    private static List<List<HouseholdService.Person>> sampleHouseholds() {
        List<List<HouseholdService.Person>> result = new List<List<HouseholdService.Person>>();
        for (String block : Label.Core_HouseholdNaming_SampleHouseholds.split('\\|')) {
            List<HouseholdService.Person> members = new List<HouseholdService.Person>();
            for (String entry : block.split(';')) {
                List<String> parts = entry.split(',', -1);
                if (parts.size() < 6) {
                    continue;
                }
                HouseholdService.Person person = new HouseholdService.Person();
                person.salutation = parts[0].trim();
                person.firstName = parts[1].trim();
                person.lastName = parts[2].trim();
                person.preferredName = parts[3].trim();
                person.role = parts[4].trim();
                person.isDeceased = 'Y'.equalsIgnoreCase(parts[5].trim());
                members.add(person);
            }
            if (!members.isEmpty()) {
                result.add(members);
            }
        }
        return result;
    }
}
