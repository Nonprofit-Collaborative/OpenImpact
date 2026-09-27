/**
 * What the Gift Transaction mirror tests share (X-07): the person who runs a mirror where the org
 * has Gift Transactions, and one of the org's Status values.
 *
 * Gift Transactions need Nonprofit Cloud's Fundraising User permission, which a user created in a
 * test does not have, and which decides whether the describe shows the object at all. So where the
 * person running the tests sees Gift Transactions, the present branch runs as that person, given
 * the packaged sets a mirror run needs; where they do not, the tests take their absent branch.
 */
@IsTest
public class GiftTransactionMirrorTestData {
    private static final List<String> SETS = new List<String>{
        'Barn_Admin',
        'Giving_Admin',
        'Gift_Transaction_Mirror'
    };

    /** The person running the tests, holding the sets a mirror run and its page need. */
    public static User runner() {
        Id me = UserInfo.getUserId();
        System.runAs(new User(Id = me)) {
            Set<Id> held = new Set<Id>();
            for (PermissionSetAssignment assigned : [
                SELECT PermissionSetId
                FROM PermissionSetAssignment
                WHERE AssigneeId = :me
            ]) {
                held.add(assigned.PermissionSetId);
            }
            List<PermissionSetAssignment> missing = new List<PermissionSetAssignment>();
            for (PermissionSet packaged : [SELECT Id FROM PermissionSet WHERE Name IN :SETS]) {
                if (!held.contains(packaged.Id)) {
                    missing.add(
                        new PermissionSetAssignment(AssigneeId = me, PermissionSetId = packaged.Id)
                    );
                }
            }
            insert missing;
        }
        return new User(Id = me);
    }

    /** An active Status value of the org's Gift Transactions: which one means paid is not asked. */
    public static String anActiveStatus() {
        for (
            Schema.PicklistEntry entry : GiftTransactionMirrorSchema.field(
                    GiftTransactionMirrorSchema.STATUS_FIELD
                )
                .getPicklistValues()
        ) {
            if (entry.isActive()) {
                return entry.getValue();
            }
        }
        return null;
    }
}
