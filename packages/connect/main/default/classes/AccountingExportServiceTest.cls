/**
 * The accounting export (X-04, ADR-NEXT) for Jen, the bookkeeper, over one August of gifts.
 *
 * The gifts are written with automation paused, so each one carries exactly the allocations
 * written here: a split gift, a refund, a gift with none at all, and the gifts the file must
 * leave out (Pending, In-kind, and one dated in September).
 */
@IsTest
private class AccountingExportServiceTest {
    private static final Date AUGUST_FIRST = Date.newInstance(2026, 8, 1);
    private static final Date AUGUST_LAST = Date.newInstance(2026, 8, 31);

    @TestSetup
    static void setup() {
        TestDataFactory.pausedSettings(1);
        Fund__c general = new Fund__c(
            Name = 'General Fund',
            Active__c = true,
            Is_Default__c = true,
            Accounting_Code__c = '4000'
        );
        Fund__c building = new Fund__c(
            Name = 'Building Fund',
            Active__c = true,
            Accounting_Code__c = '4100'
        );
        insert new List<Fund__c>{ general, building };
        Contact ana = new Contact(FirstName = 'Ana', LastName = 'Garcia');
        Contact formula = new Contact(LastName = '=SUM(A1)');
        insert new List<Contact>{ ana, formula };
        Account riverside = new Account(Name = 'Riverside Foundation');
        insert riverside;

        Gift__c check = gift(ana.Id, null, 100, 'Check', Date.newInstance(2026, 8, 5));
        check.Payment_Reference__c = '1042, "first"';
        Gift__c split = gift(null, riverside.Id, 300, 'Card', Date.newInstance(2026, 8, 10));
        Gift__c unallocated = gift(formula.Id, null, 50, 'Card', Date.newInstance(2026, 8, 20));
        Gift__c pending = gift(ana.Id, null, 70, 'Check', Date.newInstance(2026, 8, 12));
        pending.Status__c = 'Pending';
        Gift__c goods = gift(ana.Id, null, 0, 'In-kind', Date.newInstance(2026, 8, 15));
        goods.In_Kind_Description__c = 'Two laptops';
        goods.Fair_Market_Value__c = 500;
        Gift__c september = gift(ana.Id, null, 25, 'Check', Date.newInstance(2026, 9, 2));
        insert new List<Gift__c>{ check, split, unallocated, pending, goods, september };
        Gift__c refund = gift(null, riverside.Id, -40, 'Card', Date.newInstance(2026, 8, 25));
        refund.Original_Gift__c = split.Id;
        insert refund;

        insert new List<Gift_Allocation__c>{
            allocation(check.Id, general.Id, 100),
            allocation(split.Id, building.Id, 200),
            allocation(split.Id, general.Id, 100),
            allocation(refund.Id, general.Id, -40),
            allocation(pending.Id, general.Id, 70),
            allocation(september.Id, general.Id, 25)
        };
        Nonprofit_Settings__c running = TestDataFactory.defaultSettings();
        running.Automation_Paused_Until__c = null;
        TestDataFactory.saveSettings(running);
    }

    private static Gift__c gift(Id contactId, Id accountId, Decimal amount, String type, Date day) {
        return new Gift__c(
            Donor_Contact__c = contactId,
            Donor_Account__c = accountId,
            Amount__c = amount,
            Type__c = type,
            Status__c = 'Received',
            Gift_Date__c = day
        );
    }

    private static Gift_Allocation__c allocation(Id giftId, Id fundId, Decimal amount) {
        return new Gift_Allocation__c(Gift__c = giftId, Fund__c = fundId, Amount__c = amount);
    }

    private static List<String> lines(AccountingExportService.ExportFile file) {
        return file.csv.removeEnd('\r\n').split('\r\n');
    }

    @IsTest
    static void theMonthIsOneRowPerFundWithRefundsNegativeAndNothingLeftOut() {
        AccountingExportService.ExportFile file = AccountingExportService.build(
            AUGUST_FIRST,
            AUGUST_LAST,
            null,
            null
        );

        Assert.areEqual(5, file.rowCount, file.csv);
        Assert.areEqual(4, file.giftCount, 'The split gift is two rows and one gift.');
        Assert.areEqual(410, file.total, 'The net: 100 + 300 + 50 - 40.');
        List<String> rows = lines(file);
        Assert.areEqual(
            'Date,Gift Number,Original Gift,Donor,Fund,Accounting Code,Payment Method,Reference,Amount',
            rows[0]
        );
        Assert.isTrue(rows[1].startsWith('2026-08-05,G-'), rows[1]);
        Assert.isTrue(
            rows[1].endsWith(',Ana Garcia,General Fund,4000,Check,"1042, ""first""",100.00'),
            'A reference with a comma and quotes is quoted: ' + rows[1]
        );
        Assert.isTrue(
            rows[2].contains(',Riverside Foundation,Building Fund,4100,Card,,200.00'),
            rows[2]
        );
        Assert.isTrue(
            rows[3].contains(',Riverside Foundation,General Fund,4000,Card,,100.00'),
            rows[3]
        );
        Gift__c split = [SELECT Name FROM Gift__c WHERE Amount__c = 300];
        Assert.isTrue(rows[4].startsWith('2026-08-25,G-'), rows[4]);
        Assert.isTrue(
            rows[4].contains(',' + split.Name + ',Riverside Foundation,General Fund,'),
            rows[4]
        );
        Assert.isTrue(rows[4].endsWith(',-40.00'), 'A refund is its own negative row: ' + rows[4]);
        Assert.isTrue(
            rows[5].endsWith(',\'=SUM(A1),,,Card,,50.00'),
            'A gift with no allocation is still in the file, and a formula is defused: ' + rows[5]
        );
    }

    @IsTest
    static void oneFundAndOneMethodNarrowTheFile() {
        Id building = [SELECT Id FROM Fund__c WHERE Name = 'Building Fund'].Id;
        AccountingExportService.ExportFile byFund = AccountingExportService.build(
            AUGUST_FIRST,
            AUGUST_LAST,
            building,
            null
        );
        AccountingExportService.ExportFile byMethod = AccountingExportService.build(
            AUGUST_FIRST,
            AUGUST_LAST,
            null,
            'Check'
        );

        Assert.areEqual(1, byFund.rowCount);
        Assert.areEqual(200, byFund.total);
        Assert.areEqual(1, byMethod.rowCount, 'The Pending check is not money that arrived.');
        Assert.areEqual(100, byMethod.total);
    }

    @IsTest
    static void anEmptyRangeHasNoFile() {
        AccountingExportService.ExportFile file = AccountingExportService.build(
            Date.newInstance(2030, 1, 1),
            Date.newInstance(2030, 1, 7),
            null,
            null
        );

        Assert.areEqual(0, file.rowCount);
        Assert.isNull(file.csv);
    }

    @IsTest
    static void aBadRequestIsRefusedInWords() {
        Id notAFund = [SELECT Id FROM Contact LIMIT 1].Id;
        Map<String, List<Object>> cases = new Map<String, List<Object>>{
            Label.Connect_AccountingExport_ErrorDatesRequired => new List<Object>{
                null,
                AUGUST_LAST,
                null,
                null
            },
            Label.Connect_AccountingExport_ErrorDateOrder => new List<Object>{
                AUGUST_LAST,
                AUGUST_FIRST,
                null,
                null
            },
            Label.Connect_AccountingExport_ErrorFund => new List<Object>{
                AUGUST_FIRST,
                AUGUST_LAST,
                notAFund,
                null
            },
            Label.Connect_AccountingExport_ErrorPaymentMethod => new List<Object>{
                AUGUST_FIRST,
                AUGUST_LAST,
                null,
                'In-kind'
            }
        };
        for (String expected : cases.keySet()) {
            List<Object> args = cases.get(expected);
            try {
                AccountingExportService.build(
                    (Date) args[0],
                    (Date) args[1],
                    (Id) args[2],
                    (String) args[3]
                );
                Assert.fail('Expected a refusal: ' + expected);
            } catch (AccountingExportService.ExportException refused) {
                Assert.areEqual(expected, refused.getMessage());
            }
        }
    }

    @IsTest
    static void theFileHoldsOnlyTheGiftsThePersonCanSee() {
        User jen = TestDataFactory.createUser(
            'Jen',
            new List<String>{ 'Nonprofit_Read_Only', 'Giving_Read_Only' }
        );
        AccountingExportService.ExportFile file;
        System.runAs(jen) {
            file = AccountingExportService.build(AUGUST_FIRST, AUGUST_LAST, null, null);
        }

        Assert.areEqual(0, file.rowCount, 'Gifts are private, and Jen owns none of these.');
    }

    @IsTest
    static void aCellIsQuotedOnlyWhenItMustBe() {
        Assert.areEqual('', AccountingExportService.text(null));
        Assert.areEqual('Plain', AccountingExportService.text('Plain'));
        Assert.areEqual('"a,b"', AccountingExportService.text('a,b'));
        Assert.areEqual('"line\none"', AccountingExportService.text('line\none'));
        Assert.areEqual('\'+1 555', AccountingExportService.text('+1 555'));
        Assert.areEqual('"\'=1,2"', AccountingExportService.text('=1,2'));
    }

    @IsTest
    static void thePageGetsItsFileAndItsWords() {
        List<AccountingExportController.Option> methods = AccountingExportController.getPaymentMethods();
        AccountingExportController.ExportView view = AccountingExportController.exportGifts(
            AUGUST_FIRST,
            AUGUST_LAST,
            null,
            null
        );
        String refusal;
        try {
            AccountingExportController.exportGifts(AUGUST_LAST, AUGUST_FIRST, null, null);
        } catch (AuraHandledException refused) {
            refusal = refused.getMessage();
        }

        for (AccountingExportController.Option option : methods) {
            Assert.areNotEqual('In-kind', option.value);
        }
        Assert.isFalse(methods.isEmpty());
        Assert.areEqual('accounting-export-2026-08-01-to-2026-08-31.csv', view.fileName);
        Assert.areEqual(5, view.rowCount);
        Assert.areEqual(410, view.total);
        Assert.areEqual(Label.Connect_AccountingExport_ErrorDateOrder, refusal);
    }
}
