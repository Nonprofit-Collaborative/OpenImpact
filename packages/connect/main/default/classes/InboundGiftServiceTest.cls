/**
 * The inbound gift API's rules (X-03, ADR-NEXT), tested through the service that the REST
 * endpoint and the Flow action share.
 *
 * The donor is Luis Garcia, who gave online; the funds are the sample data's General Fund (the
 * default) and Building Fund (accounting code 4100). The integration user holds only the two
 * data permission sets the admin guide tells Maria to assign, Nonprofit Staff and Giving Staff,
 * so a passing test proves those sets are enough to record a gift.
 */
@IsTest
private class InboundGiftServiceTest {
    private static final String LUIS_EMAIL = 'luis.garcia.inbound@example.org';
    private static final String BUILDING_CODE = '4100';
    private static final String OWN_DONOR_EMAIL = 'luis.garcia.owned@example.org';

    @TestSetup
    static void setup() {
        insert new Fund__c(Name = 'General Fund', Active__c = true, Is_Default__c = true);
        insert new List<Fund__c>{
            new Fund__c(
                Name = 'Building Fund',
                Active__c = true,
                Accounting_Code__c = BUILDING_CODE
            ),
            new Fund__c(Name = 'Old Roof Fund', Active__c = false, Accounting_Code__c = '4999')
        };
        insert new Appeal__c(Name = 'Spring Appeal');
        insert new Contact(FirstName = 'Luis', LastName = 'Garcia', Email = LUIS_EMAIL);
        insert new Account(Name = 'Riverside Foundation');
    }

    private static User integrationUser() {
        return TestDataFactory.createUser(
            'Integration',
            new List<String>{ 'Nonprofit_Staff', 'Giving_Staff' }
        );
    }

    /**
     * A donor the integration user can see. It finds donors only among what it can see, and on
     * an org whose contacts are private it sees only its own (the admin guide says how to share
     * donors with it), so a test that runs as that user adds the donor as that user.
     */
    private static void addOwnDonor() {
        insert new Contact(FirstName = 'Luis', LastName = 'Garcia', Email = OWN_DONOR_EMAIL);
    }

    private static InboundGift gift(String externalId, Decimal amount) {
        InboundGift request = new InboundGift();
        request.externalId = externalId;
        request.amount = amount;
        request.paymentMethod = 'Card';
        request.donorEmail = LUIS_EMAIL;
        return request;
    }

    private static InboundGiftResult recordOne(InboundGift request) {
        return InboundGiftService.record(new List<InboundGift>{ request })[0];
    }

    private static Id fundNamed(String name) {
        return [SELECT Id FROM Fund__c WHERE Name = :name].Id;
    }

    @IsTest
    static void recordsAGiftFoundByEmailAndDesignatesItToTheNamedFund() {
        InboundGift request = gift('stripe:ch_1', 50);
        request.fundCode = BUILDING_CODE;
        request.paymentReference = ' ch_1 ';
        request.giftDate = Date.newInstance(2026, 9, 20);
        request.donorEmail = OWN_DONOR_EMAIL;
        InboundGiftResult result;
        System.runAs(integrationUser()) {
            addOwnDonor();
            Test.startTest();
            result = recordOne(request);
            Test.stopTest();
        }

        Assert.areEqual(InboundGiftResult.OUTCOME_CREATED, result.outcome, result.message);
        Assert.areEqual(201, InboundGiftResult.httpStatus(result));
        Gift__c recorded = [
            SELECT
                Donor_Contact__c,
                Donor_Account__c,
                Amount__c,
                Gift_Date__c,
                Type__c,
                Status__c,
                External_Id__c,
                Payment_Reference__c,
                (SELECT Fund__c, Amount__c FROM Gift_Allocations__r)
            FROM Gift__c
            WHERE Id = :result.giftId
        ];
        Assert.areEqual(
            [SELECT Id FROM Contact WHERE Email = :OWN_DONOR_EMAIL].Id,
            recorded.Donor_Contact__c
        );
        Assert.isNull(recorded.Donor_Account__c);
        Assert.areEqual(50, recorded.Amount__c);
        Assert.areEqual(Date.newInstance(2026, 9, 20), recorded.Gift_Date__c);
        Assert.areEqual('Card', recorded.Type__c);
        Assert.areEqual('Received', recorded.Status__c);
        Assert.areEqual('stripe:ch_1', recorded.External_Id__c);
        Assert.areEqual('ch_1', recorded.Payment_Reference__c);
        Assert.areEqual(1, recorded.Gift_Allocations__r.size(), 'One allocation, not two.');
        Assert.areEqual(fundNamed('Building Fund'), recorded.Gift_Allocations__r[0].Fund__c);
        Assert.areEqual(50, recorded.Gift_Allocations__r[0].Amount__c);
    }

    @IsTest
    static void aGiftNamingNoFundGoesToTheDefaultFundAndIsDatedToday() {
        InboundGiftResult result = recordOne(gift('stripe:ch_2', 25));

        Gift__c recorded = [
            SELECT Gift_Date__c, (SELECT Fund__c FROM Gift_Allocations__r)
            FROM Gift__c
            WHERE Id = :result.giftId
        ];
        Assert.areEqual(Date.today(), recorded.Gift_Date__c);
        Assert.areEqual(fundNamed('General Fund'), recorded.Gift_Allocations__r[0].Fund__c);
    }

    @IsTest
    static void sendingTheSameGiftAgainRecordsItOnceAndChangesNothing() {
        InboundGiftResult first = recordOne(gift('stripe:ch_3', 40));
        InboundGift again = gift('STRIPE:CH_3', 40);
        again.paymentReference = 'changed';
        InboundGiftResult second = recordOne(again);

        Assert.areEqual(InboundGiftResult.OUTCOME_EXISTING, second.outcome);
        Assert.areEqual(200, InboundGiftResult.httpStatus(second));
        Assert.areEqual(
            first.giftId,
            second.giftId,
            'External Id ignores case, as its index does.'
        );
        Assert.areEqual(1, [SELECT COUNT() FROM Gift__c]);
        Assert.isNull([SELECT Payment_Reference__c FROM Gift__c].Payment_Reference__c);
    }

    @IsTest
    static void theSameExternalIdWithAnotherAmountIsAConflict() {
        InboundGiftResult first = recordOne(gift('stripe:ch_4', 40));
        InboundGiftResult second = recordOne(gift('stripe:ch_4', 45));

        Assert.areEqual(InboundGiftResult.OUTCOME_REJECTED, second.outcome);
        Assert.areEqual(InboundGiftResult.ERROR_CONFLICT, second.errorCode);
        Assert.areEqual(409, InboundGiftResult.httpStatus(second));
        Assert.areEqual(first.giftId, second.giftId);
        Assert.areEqual(40, [SELECT Amount__c FROM Gift__c].Amount__c);
    }

    @IsTest
    static void aRepeatInsideOneCallIsAnsweredFromTheFirst() {
        List<InboundGiftResult> results = InboundGiftService.record(
            new List<InboundGift>{ gift('flow:1', 10), gift('flow:1', 10), gift('flow:1', 11) }
        );

        Assert.areEqual(InboundGiftResult.OUTCOME_CREATED, results[0].outcome);
        Assert.areEqual(InboundGiftResult.OUTCOME_EXISTING, results[1].outcome);
        Assert.areEqual(results[0].giftId, results[1].giftId);
        Assert.areEqual(InboundGiftResult.ERROR_CONFLICT, results[2].errorCode);
        Assert.areEqual(1, [SELECT COUNT() FROM Gift__c]);
    }

    @IsTest
    static void aMalformedGiftIsRefusedWithoutStoppingTheOthers() {
        InboundGift noAmount = gift('v:1', null);
        List<InboundGiftResult> results = InboundGiftService.record(
            new List<InboundGift>{ noAmount, gift('v:2', 10), null }
        );

        Assert.areEqual(InboundGiftResult.ERROR_INVALID_FIELD, results[0].errorCode);
        Assert.areEqual(InboundGiftResult.OUTCOME_CREATED, results[1].outcome, results[1].message);
        Assert.areEqual(InboundGiftResult.ERROR_INVALID_FIELD, results[2].errorCode);
        Assert.areEqual(1, [SELECT COUNT() FROM Gift__c]);
        Assert.areEqual(0, InboundGiftService.record(new List<InboundGift>()).size());
    }

    @IsTest
    static void aDonorNobodyMatchesIsRefusedAndLogged() {
        InboundGift stranger = gift('stripe:ch_5', 10);
        stranger.donorEmail = 'nobody@example.org';
        InboundGift madeUpId = gift('stripe:ch_6', 10);
        madeUpId.donorEmail = null;
        madeUpId.donorId = 'not-an-id';
        InboundGift wrongKind = gift('stripe:ch_7', 10);
        wrongKind.donorEmail = null;
        wrongKind.donorId = fundNamed('General Fund');

        Test.startTest();
        List<InboundGiftResult> results = InboundGiftService.record(
            new List<InboundGift>{ stranger, madeUpId, wrongKind }
        );
        Test.getEventBus().deliver();
        Test.stopTest();

        for (InboundGiftResult result : results) {
            Assert.areEqual(InboundGiftResult.ERROR_DONOR_NOT_FOUND, result.errorCode);
            Assert.areEqual(422, InboundGiftResult.httpStatus(result));
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Gift__c]);
        List<Error_Log__c> logged = [
            SELECT Message__c, Severity__c
            FROM Error_Log__c
            WHERE Context__c = 'InboundGiftService'
        ];
        Assert.areEqual(3, logged.size(), 'Every refusal is logged.');
        Assert.areEqual('Warning', logged[0].Severity__c);
        for (Error_Log__c entry : logged) {
            Assert.isFalse(entry.Message__c.contains('nobody@example.org'), 'No personal data.');
            Assert.isTrue(entry.Message__c.contains('stripe:ch_'), 'The external id is named.');
        }
    }

    @IsTest
    static void anOrganizationIsNamedByItsRecordId() {
        InboundGift grant = gift('daf:GR-1', 2500);
        grant.donorEmail = null;
        grant.donorId = [SELECT Id FROM Account WHERE Name = 'Riverside Foundation'].Id;
        grant.paymentMethod = 'grant';
        grant.appealId = [SELECT Id FROM Appeal__c].Id;
        grant.fundId = fundNamed('Building Fund');

        InboundGiftResult result = recordOne(grant);

        Gift__c recorded = [
            SELECT
                Donor_Account__c,
                Donor_Contact__c,
                Type__c,
                Appeal__c,
                (SELECT Fund__c FROM Gift_Allocations__r)
            FROM Gift__c
            WHERE Id = :result.giftId
        ];
        Assert.areEqual(grant.donorId, recorded.Donor_Account__c);
        Assert.isNull(recorded.Donor_Contact__c);
        Assert.areEqual('Grant', recorded.Type__c, 'The method is matched ignoring case.');
        Assert.areEqual(grant.appealId, recorded.Appeal__c);
        Assert.areEqual(fundNamed('Building Fund'), recorded.Gift_Allocations__r[0].Fund__c);
    }

    @IsTest
    static void unknownOrInactiveFundsAndUnknownAppealsAreRefused() {
        InboundGift unknownCode = gift('f:1', 10);
        unknownCode.fundCode = '9999';
        InboundGift inactiveCode = gift('f:2', 10);
        inactiveCode.fundCode = '4999';
        InboundGift wrongFundId = gift('f:3', 10);
        wrongFundId.fundId = [SELECT Id FROM Appeal__c].Id;
        InboundGift unknownAppeal = gift('f:4', 10);
        unknownAppeal.appealId = fundNamed('General Fund');

        List<InboundGiftResult> results = InboundGiftService.record(
            new List<InboundGift>{ unknownCode, inactiveCode, wrongFundId, unknownAppeal }
        );

        Assert.areEqual(InboundGiftResult.ERROR_FUND_NOT_FOUND, results[0].errorCode);
        Assert.areEqual(InboundGiftResult.ERROR_FUND_NOT_FOUND, results[1].errorCode);
        Assert.areEqual(InboundGiftResult.ERROR_FUND_NOT_FOUND, results[2].errorCode);
        Assert.areEqual(InboundGiftResult.ERROR_APPEAL_NOT_FOUND, results[3].errorCode);
        Assert.areEqual(0, [SELECT COUNT() FROM Gift__c]);
    }

    @IsTest
    static void withNoDefaultFundTheGiftIsNotSavedInThePlatformsWords() {
        update new Fund__c(Id = fundNamed('General Fund'), Is_Default__c = false);

        InboundGiftResult result = recordOne(gift('p:1', 10));

        Assert.areEqual(InboundGiftResult.ERROR_NOT_SAVED, result.errorCode);
        Assert.areEqual(422, InboundGiftResult.httpStatus(result));
        Assert.areEqual(0, [SELECT COUNT() FROM Gift__c]);
    }

    @IsTest
    static void anExternalIdHeldByAGiftTheUserCannotSeeIsAConflict() {
        Contact luis = [SELECT Id FROM Contact WHERE Email = :LUIS_EMAIL];
        insert new Gift__c(
            Donor_Contact__c = luis.Id,
            Amount__c = 10,
            Gift_Date__c = Date.today(),
            Type__c = 'Check',
            Status__c = 'Received',
            External_Id__c = 'dup:1'
        );
        InboundGiftResult result;
        System.runAs(integrationUser()) {
            addOwnDonor();
            InboundGift request = gift('dup:1', 10);
            request.donorEmail = OWN_DONOR_EMAIL;
            result = recordOne(request);
        }

        Assert.areEqual(InboundGiftResult.ERROR_CONFLICT, result.errorCode, result.message);
        Assert.areEqual(1, [SELECT COUNT() FROM Gift__c]);
    }

    @IsTest
    static void twoHundredGiftsInOneCallStayInsideTheLimits() {
        List<InboundGift> requests = new List<InboundGift>();
        for (Integer index = 0; index < 200; index++) {
            InboundGift request = gift('bulk:' + index, 5);
            if (Math.mod(index, 2) == 0) {
                request.fundCode = BUILDING_CODE;
            }
            if (Math.mod(index, 10) == 0) {
                request.donorEmail = 'nobody' + index + '@example.org';
            }
            requests.add(request);
        }

        Test.startTest();
        List<InboundGiftResult> results = InboundGiftService.record(requests);
        Test.stopTest();

        Integer created = 0;
        for (InboundGiftResult result : results) {
            created += result.outcome == InboundGiftResult.OUTCOME_CREATED ? 1 : 0;
        }
        Assert.areEqual(180, created);
        Assert.areEqual(180, [SELECT COUNT() FROM Gift__c]);
        Assert.areEqual(
            80,
            [
                SELECT COUNT()
                FROM Gift_Allocation__c
                WHERE Fund__r.Accounting_Code__c = :BUILDING_CODE
            ]
        );
    }

    @IsTest
    static void aRequestBodyIsReadStrictly() {
        InboundGiftResult misspelled = InboundGiftService.recordBody(
            Blob.valueOf(
                '{"externalId":"b:1","amount":10,"paymentMethod":"Card","donorEmail":"' +
                    LUIS_EMAIL +
                    '","fundcod":"4100"}'
            )
        );
        InboundGiftResult notJson = InboundGiftService.recordBody(Blob.valueOf('amount=10'));
        InboundGiftResult empty = InboundGiftService.recordBody(null);
        InboundGiftResult wellFormed = InboundGiftService.recordBody(
            Blob.valueOf(
                '{"externalId":"b:2","amount":10.5,"paymentMethod":"check","giftDate":"2026-09-01",' +
                    '"donorEmail":"' +
                    LUIS_EMAIL.toUpperCase() +
                    '","fundCode":"4100"}'
            )
        );

        Assert.areEqual(InboundGiftResult.ERROR_INVALID_REQUEST, misspelled.errorCode);
        Assert.areEqual(InboundGiftResult.ERROR_INVALID_REQUEST, notJson.errorCode);
        Assert.areEqual(InboundGiftResult.ERROR_INVALID_REQUEST, empty.errorCode);
        Assert.areEqual(400, InboundGiftResult.httpStatus(empty));
        Assert.areEqual(InboundGiftResult.OUTCOME_CREATED, wellFormed.outcome, wellFormed.message);
        Gift__c recorded = [SELECT Gift_Date__c, Type__c, Amount__c FROM Gift__c];
        Assert.areEqual(Date.newInstance(2026, 9, 1), recorded.Gift_Date__c);
        Assert.areEqual('Check', recorded.Type__c);
        Assert.areEqual(10.5, recorded.Amount__c);
    }

    @IsTest
    static void aPersonStoredAsAnAccountIsCreditedOnTheAccount() {
        List<RecordType> personTypes = [
            SELECT Id
            FROM RecordType
            WHERE SobjectType = 'Account' AND IsPersonType = TRUE AND IsActive = TRUE
            LIMIT 1
        ];
        if (personTypes.isEmpty()) {
            return; // An org without person accounts has no such path to prove.
        }
        SObject person = new Account(RecordTypeId = personTypes[0].Id);
        person.put('LastName', 'Okafor');
        person.put('PersonEmail', 'ada.okafor.inbound@example.org');
        insert person;
        Id personContactId = (Id) Database.query(
                'SELECT PersonContactId FROM Account WHERE Id = \'' + person.Id + '\''
            )[0]
            .get('PersonContactId');

        InboundGift byEmail = gift('pa:1', 10);
        byEmail.donorEmail = 'ada.okafor.inbound@example.org';
        InboundGift byContactId = gift('pa:2', 10);
        byContactId.donorEmail = null;
        byContactId.donorId = personContactId;
        List<InboundGiftResult> results = InboundGiftService.record(
            new List<InboundGift>{ byEmail, byContactId }
        );

        for (Gift__c recorded : [SELECT Donor_Account__c, Donor_Contact__c FROM Gift__c]) {
            Assert.areEqual(person.Id, recorded.Donor_Account__c);
            Assert.isNull(recorded.Donor_Contact__c);
        }
        Assert.areEqual(InboundGiftResult.OUTCOME_CREATED, results[1].outcome, results[1].message);
    }
}
