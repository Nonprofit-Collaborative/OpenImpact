/**
 * Tests for CustomPermissionSelector (feature C-11, ADR-0024).
 *
 * The permission the finding exists for, `Override_Receipt_Lock`, ships in the Giving package
 * and a custom permission cannot be created with DML, so the selector is exercised two ways:
 * against a name no package ships, which is exactly the shape of a Platform-only org, and
 * against a permission Core does ship, granted to a user the test creates, which is the only
 * way to prove the four queries actually find a holder and name them.
 */
@IsTest
private class CustomPermissionSelectorTest {
    /** A developer name deliberately belonging to no package in this repository. */
    private static final String ABSENT_PERMISSION = 'No_Package_Ships_This_Permission';

    @IsTest
    static void aPermissionNoPackageShipsIsHeldByNobody() {
        Test.startTest();
        CustomPermissionSelector.Holders holders = CustomPermissionSelector.holders(
            ABSENT_PERMISSION
        );
        Test.stopTest();

        System.assertEquals(
            true,
            holders.readable,
            'The setup objects were readable, so the answer stands: this is a real "nobody", ' +
            'not a question that could not be asked.'
        );
        System.assertEquals(
            0,
            holders.total,
            'A custom permission that is not in the org is held by nobody. This is the ' +
                'Platform-only org shape: Giving is not installed, the permission does not ' +
                'exist, and Core answers rather than failing.'
        );
        System.assertEquals(
            0,
            holders.names.size(),
            'With no holders there are no names to print.'
        );
    }

    @IsTest
    static void theReceiptLockOverrideIsGrantedToNobodyByThePackage() {
        List<CustomPermission> shipped = [
            SELECT Id, NamespaceName
            FROM CustomPermission
            WHERE DeveloperName = :HealthCheckService.OVERRIDE_RECEIPT_LOCK
        ];

        CustomPermissionSelector.Holders holders = CustomPermissionSelector.holders(
            HealthCheckService.OVERRIDE_RECEIPT_LOCK
        );

        System.assertEquals(
            0,
            holders.total,
            shipped.isEmpty()
                ? 'Giving is not deployed in this org, so the override permission does not ' +
                  'exist and nobody can be holding it.'
                : 'ADR-0024: the package ships Override Receipt Lock on no permission set and ' +
                  'in no permission set group, so a freshly deployed org has no holders.'
        );
        System.assertEquals(
            true,
            holders.readable,
            'Either way the question was answerable, which is what lets Health Check say ' +
            'nothing rather than say nothing is wrong.'
        );
    }

    @IsTest
    static void aPersonHoldingAPermissionIsFoundAndNamed() {
        User maria = HealthCheckTestHelper.mariaWithManageSettings();
        String mariaName = [SELECT Name FROM User WHERE Id = :maria.Id].Name;

        Test.startTest();
        CustomPermissionSelector.Holders holders = CustomPermissionSelector.holders(
            HealthCheckService.MANAGE_SETTINGS
        );
        Test.stopTest();

        System.assert(
            holders.total >= 1,
            'Maria was given the permission through a permission set, so the selector has to ' +
            'find at least one holder.'
        );
        System.assert(
            new Set<String>(holders.names).contains(mariaName),
            'The finding names people, so the selector has to return the holder by name, not ' +
                'just count one. Expected ' +
                mariaName +
                ' among ' +
                String.join(holders.names, ', ')
        );
    }

    @IsTest
    static void aBlankPermissionNameAsksNothing() {
        CustomPermissionSelector.Holders holders = CustomPermissionSelector.holders(null);

        System.assertEquals(
            0,
            holders.total,
            'A missing name is not a question, so it does not become a finding.'
        );
        System.assertEquals(
            true,
            holders.readable,
            'Nothing failed: there was simply nothing to ask.'
        );
    }
}
