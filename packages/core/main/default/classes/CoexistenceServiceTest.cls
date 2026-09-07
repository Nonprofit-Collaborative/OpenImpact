/**
 * Tests for CoexistenceService (feature C-07).
 *
 * Maria's org decides the mode; the package only proposes one. These tests cover the
 * proposal, the confirmation, and the refusal to overwrite a choice already made.
 */
@IsTest
private class CoexistenceServiceTest {
    @IsTest
    static void modeIsNullUntilSomebodyConfirmsOne() {
        System.assertEquals(
            null,
            CoexistenceService.getCurrentMode(),
            'A fresh org has no confirmed coexistence mode.'
        );
    }

    @IsTest
    static void membershipDefaultsToContactMode() {
        System.assertEquals(
            CoexistenceService.MEMBERSHIP_CONTACT,
            CoexistenceService.getMembershipMode(),
            'Contact mode is the default until something changes it.'
        );
    }

    @IsTest
    static void npspOrgGetsNpspCoexistence() {
        OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
        shape.hasNpsp = true;
        OrgShapeDetector.overrideShape = shape;

        Test.startTest();
        String applied = CoexistenceService.applyRecommendedIfUnset();
        Test.stopTest();

        System.assertEquals(CoexistenceService.MODE_NPSP, applied, 'NPSP org, NPSP coexistence.');
        System.assertEquals(
            CoexistenceService.MODE_NPSP,
            CoexistenceService.getCurrentMode(),
            'The recommendation is saved, not only returned.'
        );
        System.assertEquals(
            CoexistenceService.MEMBERSHIP_CONTACT,
            CoexistenceService.getMembershipMode(),
            'NPSP coexistence keeps contact membership.'
        );
    }

    @IsTest
    static void personAccountsOrgGetsJunctionMembershipWithTheMode() {
        OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
        shape.hasPersonAccounts = true;
        OrgShapeDetector.overrideShape = shape;

        Test.startTest();
        String applied = CoexistenceService.applyRecommendedIfUnset();
        Test.stopTest();

        System.assertEquals(
            CoexistenceService.MODE_AGENTFORCE_NONPROFIT,
            applied,
            'A Person Accounts org is an Agentforce Nonprofit org.'
        );
        System.assertEquals(
            CoexistenceService.MEMBERSHIP_JUNCTION,
            CoexistenceService.getMembershipMode(),
            'Person Accounts require junction membership, applied in the same save.'
        );
    }

    @IsTest
    static void aConfirmedModeIsNeverOverwritten() {
        CoexistenceService.setMode(CoexistenceService.MODE_STANDALONE);

        OrgShapeDetector.OrgShape shape = new OrgShapeDetector.OrgShape();
        shape.hasNpsp = true;
        OrgShapeDetector.overrideShape = shape;

        Test.startTest();
        String applied = CoexistenceService.applyRecommendedIfUnset();
        Test.stopTest();

        System.assertEquals(
            CoexistenceService.MODE_STANDALONE,
            applied,
            'Maria chose standalone: detection does not argue with her.'
        );
    }

    @IsTest
    static void setModeAcceptsEveryValidMode() {
        CoexistenceService.setMode(CoexistenceService.MODE_NPSP);
        System.assertEquals(
            CoexistenceService.MODE_NPSP,
            CoexistenceService.getCurrentMode(),
            'NPSP coexistence can be chosen by hand.'
        );

        CoexistenceService.setMode(CoexistenceService.MODE_AGENTFORCE_NONPROFIT);
        System.assertEquals(
            CoexistenceService.MODE_AGENTFORCE_NONPROFIT,
            CoexistenceService.getCurrentMode(),
            'Agentforce Nonprofit coexistence can be chosen by hand.'
        );
        System.assertEquals(
            CoexistenceService.MEMBERSHIP_JUNCTION,
            CoexistenceService.getMembershipMode(),
            'Choosing Agentforce Nonprofit by hand still brings junction membership with it.'
        );
    }

    @IsTest
    static void setModeRejectsAnythingElse() {
        Boolean refused = false;
        try {
            CoexistenceService.setMode('Whatever');
        } catch (CoexistenceService.CoexistenceException e) {
            refused = true;
            System.assert(
                e.getMessage().contains('Whatever'),
                'The message names the value that was refused.'
            );
        }
        System.assert(refused, 'An unknown mode is refused rather than saved.');
    }

    @IsTest
    static void setModeRejectsBlank() {
        Boolean refused = false;
        try {
            CoexistenceService.setMode(null);
        } catch (CoexistenceService.CoexistenceException e) {
            refused = true;
        }
        System.assert(refused, 'An empty mode is refused.');
    }

    @IsTest
    static void junctionMembershipCanBeAppliedOnItsOwn() {
        Test.startTest();
        CoexistenceService.applyJunctionMembership();
        Test.stopTest();

        System.assertEquals(
            CoexistenceService.MEMBERSHIP_JUNCTION,
            CoexistenceService.getMembershipMode(),
            'The membership fix moves household membership to the junction.'
        );
    }
}
