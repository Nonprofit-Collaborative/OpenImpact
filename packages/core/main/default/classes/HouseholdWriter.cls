/**
 * The one place package owned household bookkeeping is saved.
 *
 * DOCUMENTED EXCEPTION to the user mode rule (plan Sections 4.13 and 7.2, and the review
 * of C-01). The household name, the two greetings and the member count are computed by
 * the package: no person types them, and no screen offers them for editing. A staff user
 * saving a contact must not need edit access on them, and an org's own profile, an
 * integration user or a data loader user cannot be given that access by a packaged
 * permission set at all. Writing them with the running user's access therefore turns an
 * ordinary contact save into a raw DML error, which is the failure this class exists to
 * prevent, so these writes run in system mode.
 *
 * The exception is kept narrow:
 *
 * - Only these fields are written here, and only on the Household record type.
 * - No value written here comes from user input: every one is computed by
 *   HouseholdNamingService or counted by HouseholdService.
 * - The classes that call this one are `with sharing`, so which records a user can reach
 *   is unchanged. Only field level access on the package's own computed fields is
 *   bypassed.
 * - Deleting an emptied household is NOT done here: that removes a record, so it runs
 *   with the user's own access and is logged rather than thrown when it is refused.
 * - Everything a person types (a contact, a membership row, a move) is saved elsewhere in
 *   user mode.
 */
public with sharing class HouseholdWriter {
    /**
     * Creates households the package is making on the user's behalf and returns the ids
     * in the same order, with null where one could not be created.
     */
    public static List<Id> createHouseholds(List<Account> households) {
        List<Id> result = new List<Id>();
        if (households == null || households.isEmpty()) {
            return result;
        }
        List<Database.SaveResult> saves = Database.insert(
            households,
            false,
            AccessLevel.SYSTEM_MODE
        );
        for (Database.SaveResult save : saves) {
            result.add(save.isSuccess() ? save.getId() : null);
        }
        logFailures(saves, Label.Core_Households_ErrorContextMembership);
        return result;
    }

    /**
     * Saves computed values on existing households: the name, the two greetings, and the
     * member count.
     */
    public static void updateHouseholds(List<Account> households) {
        if (households == null || households.isEmpty()) {
            return;
        }
        List<Database.SaveResult> saves = Database.update(
            households,
            false,
            AccessLevel.SYSTEM_MODE
        );
        logFailures(saves, Label.Core_Households_ErrorContextNaming);
    }

    /**
     * Creates the membership rows the package is making on the user's behalf, for a person
     * the org stores as an account.
     */
    public static void createMemberships(List<Household_Member__c> memberships) {
        if (memberships == null || memberships.isEmpty()) {
            return;
        }
        List<Database.SaveResult> saves = Database.insert(
            memberships,
            false,
            AccessLevel.SYSTEM_MODE
        );
        logFailures(saves, Label.Core_Households_ErrorContextMembership);
    }

    /**
     * Removes households the package created that have been left with no members. This one
     * runs with the user's own access, and a refusal is logged rather than thrown, so that
     * tidying up never fails somebody's save.
     */
    public static void deleteHouseholds(List<Account> households) {
        if (households == null || households.isEmpty()) {
            return;
        }
        try {
            List<Database.DeleteResult> deletes = Database.delete(
                households,
                false,
                AccessLevel.USER_MODE
            );
            for (Database.DeleteResult result : deletes) {
                if (!result.isSuccess()) {
                    log(
                        firstMessage(result.getErrors()),
                        Label.Core_Households_ErrorContextMembership
                    );
                }
            }
        } catch (Exception e) {
            ErrorLogger.log(e, Label.Core_Households_ErrorContextMembership);
        }
    }

    private static void logFailures(List<Database.SaveResult> saves, String context) {
        for (Database.SaveResult save : saves) {
            if (!save.isSuccess()) {
                log(firstMessage(save.getErrors()), context);
            }
        }
    }

    private static String firstMessage(List<Database.Error> errors) {
        return errors == null || errors.isEmpty() ? '' : errors[0].getMessage();
    }

    private static void log(String message, String context) {
        ErrorLogger.log(
            new HouseholdException(Label.Core_Households_ErrorSaveFailed + ' ' + message),
            context
        );
    }
}
