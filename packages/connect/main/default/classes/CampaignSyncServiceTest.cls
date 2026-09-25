/**
 * Campaign sync (X-02, canonical model Section 29B) as Maria and David see it: saving an
 * appeal gives it a Campaign, a change follows it there, and nothing about the Campaign ever
 * refuses the appeal.
 *
 * Campaign is read only through dynamic queries here too, so this class compiles where
 * Campaign does not exist; on such an org every test checks that the sync did nothing and
 * stops (R-CS1).
 */
@IsTest
private class CampaignSyncServiceTest {
    @TestSetup
    static void setup() {
        switchOn(true);
    }

    private static void switchOn(Boolean enabled) {
        Connect_Settings__c settings = Connect_Settings__c.getOrgDefaults();
        settings.Campaign_Sync_Enabled__c = enabled;
        upsert settings;
    }

    /** Maria: an administrator who holds Campaign access and the Marketing User box. */
    private static User maria() {
        User maria = TestDataFactory.createUserOnTheRunningUsersProfile(
            'Maria',
            new List<String>{ 'Giving_Admin', 'Campaign_Sync' }
        );
        System.runAs(new User(Id = UserInfo.getUserId())) {
            update new User(Id = maria.Id, UserPermissionsMarketingUser = true);
        }
        return maria;
    }

    /** Campaigns read back by the name describe gives, so the class compiles without one. */
    private static Map<Id, SObject> campaigns(Set<Id> ids) {
        return new Map<Id, SObject>(
            Database.queryWithBinds(
                'SELECT ' +
                    CampaignSyncSelector.CAMPAIGN_FIELDS +
                    ' FROM ' +
                    CampaignSyncService.campaignType().getDescribe().getName() +
                    ' WHERE Id IN :ids',
                new Map<String, Object>{ 'ids' => ids },
                AccessLevel.SYSTEM_MODE
            )
        );
    }

    private static SObject campaign(String campaignId) {
        return campaigns(new Set<Id>{ Id.valueOf(campaignId) }).get(Id.valueOf(campaignId));
    }

    private static Appeal__c reread(Id appealId) {
        return (Appeal__c) Database.queryWithBinds(
            'SELECT ' + CampaignSyncSelector.APPEAL_FIELDS + ' FROM Appeal__c WHERE Id = :appealId',
            new Map<String, Object>{ 'appealId' => appealId },
            AccessLevel.SYSTEM_MODE
        )[0];
    }

    private static Appeal__c springAppeal() {
        return new Appeal__c(
            Name = 'Spring appeal',
            Description__c = 'The spring letter to every donor.',
            Start_Date__c = Date.newInstance(2026, 3, 2),
            End_Date__c = Date.newInstance(2026, 5, 29),
            Goal__c = 25000,
            Cost__c = 1200,
            Active__c = true
        );
    }

    @IsTest
    static void savingAnAppealGivesItACampaignWithTheSameValues() {
        Appeal__c spring = springAppeal();
        Test.startTest();
        System.runAs(maria()) {
            insert spring;
        }
        Test.stopTest();

        Appeal__c saved = reread(spring.Id);
        if (!CampaignSyncService.isAvailable()) {
            Assert.isNull(saved.Campaign_Id__c, 'Without Campaign the sync does nothing.');
            return;
        }
        Assert.isNotNull(saved.Campaign_Id__c, 'The Campaign is linked in the same save (R-CS3).');
        SObject copy = campaign(saved.Campaign_Id__c);
        Assert.areEqual('Spring appeal', copy.get('Name'), 'Name is copied.');
        Assert.areEqual(saved.Description__c, copy.get('Description'), 'Description is copied.');
        Assert.areEqual(saved.Start_Date__c, copy.get('StartDate'), 'Start Date is copied.');
        Assert.areEqual(saved.End_Date__c, copy.get('EndDate'), 'End Date is copied.');
        Assert.areEqual(25000, (Decimal) copy.get('ExpectedRevenue'), 'Goal is Expected Revenue.');
        Assert.areEqual(1200, (Decimal) copy.get('ActualCost'), 'Cost is Actual Cost.');
        Assert.areEqual(true, copy.get('IsActive'), 'Active is copied.');
        Assert.isNull(copy.get('ParentId'), 'No parent appeal, no parent Campaign.');
    }

    @IsTest
    static void aChangeToTheAppealFollowsItToTheCampaignAndNothingComesBack() {
        User admin = maria();
        Appeal__c spring = springAppeal();
        System.runAs(admin) {
            insert spring;
        }
        if (!CampaignSyncService.isAvailable()) {
            return;
        }
        String link = reread(spring.Id).Campaign_Id__c;

        Test.startTest();
        System.runAs(admin) {
            update new Appeal__c(Id = spring.Id, Name = 'spring appeal', Goal__c = 30000);
            SObject handEdited = CampaignSyncService.campaignType().newSObject(Id.valueOf(link));
            handEdited.put('Description', 'Edited on the Campaign');
            update handEdited;
        }
        Test.stopTest();

        SObject copy = campaign(link);
        Assert.areEqual(
            'spring appeal',
            copy.get('Name'),
            'A change of case alone is still a change.'
        );
        Assert.areEqual(30000, (Decimal) copy.get('ExpectedRevenue'), 'The new goal is copied.');
        Appeal__c appeal = reread(spring.Id);
        Assert.areEqual(
            'The spring letter to every donor.',
            appeal.Description__c,
            'An edit on the Campaign never flows back to the appeal.'
        );
        Assert.areEqual(link, appeal.Campaign_Id__c, 'The link is kept, not replaced.');
    }

    @IsTest
    static void aChildAppealsCampaignSitsUnderItsParentsCampaign() {
        User admin = maria();
        Appeal__c gala = new Appeal__c(Name = 'Capital campaign', Active__c = true);
        System.runAs(admin) {
            insert gala;
        }
        Appeal__c calls = new Appeal__c(
            Name = 'Capital campaign: major donor calls',
            Active__c = true,
            Parent_Appeal__c = gala.Id
        );
        Test.startTest();
        System.runAs(admin) {
            insert calls;
        }
        Test.stopTest();
        if (!CampaignSyncService.isAvailable()) {
            return;
        }
        Assert.areEqual(
            Id.valueOf(reread(gala.Id).Campaign_Id__c),
            campaign(reread(calls.Id).Campaign_Id__c).get('ParentId'),
            'Parent Appeal becomes Parent Campaign (R-CS2).'
        );
    }

    @IsTest
    static void switchedOffNothingIsCopied() {
        switchOn(false);
        Appeal__c spring = springAppeal();
        Test.startTest();
        System.runAs(maria()) {
            insert spring;
        }
        Test.stopTest();
        Assert.isNull(reread(spring.Id).Campaign_Id__c, 'Off at install, and off means off.');
    }

    @IsTest
    static void davidWithoutCampaignAccessStillSavesHisAppeal() {
        User david = TestDataFactory.createUser('David', new List<String>{ 'Giving_Staff' });
        Appeal__c spring = springAppeal();
        CampaignSyncService.Result result;
        Test.startTest();
        System.runAs(david) {
            insert spring;
            result = CampaignSyncService.syncBeforeSave(
                new List<Appeal__c>{ springAppeal() },
                null
            );
        }
        Test.stopTest();
        Assert.isNull(reread(spring.Id).Campaign_Id__c, 'The appeal saves without a Campaign.');
        if (CampaignSyncService.isAvailable()) {
            Assert.areEqual(1, result.skipped, 'It is skipped and logged, not refused (R-CS4).');
        }
    }

    @IsTest
    static void aTypedValueThatIsNotACampaignIsRefused() {
        if (!CampaignSyncService.isAvailable()) {
            return;
        }
        Account notACampaign = new Account(Name = 'Riverside Foundation');
        insert notACampaign;
        Appeal__c spring = springAppeal();
        spring.Campaign_Id__c = notACampaign.Id;
        Test.startTest();
        Database.SaveResult saved;
        System.runAs(maria()) {
            saved = Database.insert(spring, false);
        }
        Test.stopTest();
        Assert.isFalse(saved.isSuccess(), 'An Account identifier is not a Campaign (R-CS8).');
        Assert.areEqual(
            Label.Connect_CampaignSync_InvalidCampaignId,
            saved.getErrors()[0].getMessage(),
            'The refusal says what the field must hold.'
        );
    }

    @IsTest
    static void pastingAnExistingCampaignLinksToItAndWritesTheAppealOntoIt() {
        User admin = maria();
        if (!CampaignSyncService.isAvailable()) {
            return;
        }
        SObject existing = CampaignSyncService.campaignType().newSObject();
        existing.put('Name', 'Spring mailing (old)');
        System.runAs(admin) {
            insert existing;
        }
        Appeal__c spring = springAppeal();
        spring.Campaign_Id__c = String.valueOf(existing.Id).left(15);
        Test.startTest();
        System.runAs(admin) {
            insert spring;
        }
        Test.stopTest();
        Appeal__c saved = reread(spring.Id);
        Assert.areEqual(
            String.valueOf(existing.Id),
            saved.Campaign_Id__c,
            'A 15 character identifier is stored in its 18 character form.'
        );
        Assert.areEqual(
            'Spring appeal',
            campaign(saved.Campaign_Id__c).get('Name'),
            'The appeal is written onto the Campaign it was linked to.'
        );
    }

    @IsTest
    static void aDeletedCampaignIsReportedAndTheAppealStillSaves() {
        User admin = maria();
        Appeal__c spring = springAppeal();
        System.runAs(admin) {
            insert spring;
        }
        if (!CampaignSyncService.isAvailable()) {
            return;
        }
        Appeal__c saved = reread(spring.Id);
        System.runAs(admin) {
            delete CampaignSyncService.campaignType().newSObject(Id.valueOf(saved.Campaign_Id__c));
        }
        Appeal__c edited = saved.clone(true, true, true, true);
        edited.Goal__c = 40000;
        CampaignSyncService.Result result;
        Test.startTest();
        System.runAs(admin) {
            result = CampaignSyncService.syncBeforeSave(
                new List<Appeal__c>{ edited },
                new Map<Id, Appeal__c>{ saved.Id => saved }
            );
            update new Appeal__c(Id = spring.Id, Goal__c = 40000);
        }
        Test.stopTest();
        Assert.areEqual(1, result.failed, 'Reported, not replaced (R-CS7).');
        Assert.areEqual(0, result.created, 'No second Campaign is made for the appeal.');
        Assert.areEqual(40000, reread(spring.Id).Goal__c, 'The appeal saved all the same.');
    }

    @IsTest
    static void twoHundredAppealsInOneSaveEachGetACampaign() {
        List<Appeal__c> appeals = new List<Appeal__c>();
        for (Integer i = 0; i < 200; i++) {
            appeals.add(new Appeal__c(Name = 'Giving day ' + i, Goal__c = i, Active__c = true));
        }
        Test.startTest();
        System.runAs(maria()) {
            insert appeals;
        }
        Test.stopTest();
        if (!CampaignSyncService.isAvailable()) {
            return;
        }
        Integer linked = [
            SELECT COUNT()
            FROM Appeal__c
            WHERE Id IN :appeals AND Campaign_Id__c != NULL
            WITH SYSTEM_MODE
        ];
        Assert.areEqual(200, linked, 'One insert of Campaigns serves the whole save.');
    }

    @IsTest
    static void comparisonsReadAsAPersonWould() {
        Assert.isTrue(CampaignSyncService.same(100, 100.00), 'Amounts compare by value.');
        Assert.isFalse(CampaignSyncService.same('Gala', 'gala'), 'Text compares with case.');
        Assert.isTrue(CampaignSyncService.same(null, null), 'Two empties are the same.');
        Assert.isFalse(CampaignSyncService.same(null, ''), 'Empty and blank text differ.');
    }
}
