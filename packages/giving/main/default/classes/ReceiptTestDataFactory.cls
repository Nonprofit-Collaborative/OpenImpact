/**
 * Test data for the receipting feature.
 *
 * It also holds the fake renderer. ADR-0016 records that PDF bytes cannot be asserted in an Apex
 * test, so the tests assert the composed HTML and the record and file graph, and the fake keeps the
 * HTML where a test can read it instead of turning it into bytes nobody can inspect.
 */
@IsTest
public class ReceiptTestDataFactory {
    /** The renderer a test uses: it keeps what it was asked to render, and returns something. */
    public class RecordingRenderer implements ReceiptRenderer {
        public List<String> renderedHtml = new List<String>();

        public Blob render(String html) {
            renderedHtml.add(html);
            return Blob.valueOf(html);
        }

        public String describe() {
            return 'Recording renderer (test)';
        }

        /** The last document composed, which is what a content assertion reads. */
        public String lastHtml() {
            return renderedHtml.isEmpty() ? '' : renderedHtml[renderedHtml.size() - 1];
        }
    }

    /**
     * Everything a receipt needs before it can be issued: an organization to issue it, a numbering
     * prefix, a letter of each kind, permission to issue, and a renderer that does not need a PDF
     * engine. Returns the renderer so a test can read what was composed.
     */
    public static RecordingRenderer setUpReceipting() {
        Nonprofit_Settings__c core = Nonprofit_Settings__c.getOrgDefaults();
        core.SetupOwnerId = UserInfo.getOrganizationId();
        core.Organization_Legal_Name__c = 'Hope For Homes';
        core.Organization_EIN__c = '12-3456789';
        core.Organization_Address__c = '14 Bridge Street, Springfield';
        core.Receipt_Signer_Name__c = 'Tom Alvarez';
        core.Receipt_Signer_Title__c = 'Executive Director';
        upsert core;

        Giving_Settings__c giving = Giving_Settings__c.getOrgDefaults();
        giving.SetupOwnerId = UserInfo.getOrganizationId();
        giving.Receipt_Number_Prefix__c = 'HFH';
        giving.Receipt_Next_Counter__c = 1;
        giving.Receipt_Place_Of_Issue__c = 'Springfield';
        upsert giving;

        insert new List<Receipt_Template__c>{
            new Receipt_Template__c(
                Name = 'Per gift receipt',
                Type__c = ReceiptNumberSequence.TYPE_PER_GIFT,
                Active__c = true,
                Body__c = perGiftTemplateBody()
            ),
            new Receipt_Template__c(
                Name = 'Consolidated statement',
                Type__c = ReceiptNumberSequence.TYPE_STATEMENT,
                Active__c = true,
                Body__c = statementTemplateBody()
            )
        };

        ReceiptService.issuePermission = true;
        RecordingRenderer renderer = new RecordingRenderer();
        ReceiptRendererFactory.overrideRenderer = renderer;
        return renderer;
    }

    public static String perGiftTemplateBody() {
        return '<p>{{OrganizationName}}</p><p>Receipt {{ReceiptNumber}}</p>' +
            '<p>Dear {{DonorName}}, thank you for your gift of {{Amount}} received on {{GiftDate}}.</p>';
    }

    public static String statementTemplateBody() {
        return '<p>{{OrganizationName}}</p><p>Statement {{ReceiptNumber}} for {{StatementYear}}</p>' +
            '<p>Dear {{DonorName}}, your giving totalled {{Amount}}.</p>{{GiftLines}}';
    }

    /** A cash gift with nothing given in return, which is the ordinary case. */
    public static Gift__c plainCashGift(Id donorContactId, Decimal amount, Date giftDate) {
        Gift__c gift = GivingTestDataFactory.buildGift(donorContactId, amount);
        gift.Type__c = 'Cash';
        gift.Gift_Date__c = giftDate;
        return gift;
    }

    /** A gift where the donor received something, so the receipt owes a disclosure. */
    public static Gift__c quidProQuoGift(
        Id donorContactId,
        Decimal amount,
        Decimal benefitValue,
        String benefitDescription,
        Date giftDate
    ) {
        Gift__c gift = plainCashGift(donorContactId, amount, giftDate);
        gift.Benefit_Description__c = benefitDescription;
        gift.Benefit_Value__c = benefitValue;
        return gift;
    }

    /**
     * A gift of goods, whose receipt describes and never values them. The amount and the fair
     * market value are the same number, which is what R-G12 requires of a real one.
     */
    public static Gift__c inKindGift(Id donorContactId, String description, Date giftDate) {
        return inKindGift(donorContactId, description, 900, giftDate);
    }

    public static Gift__c inKindGift(
        Id donorContactId,
        String description,
        Decimal value,
        Date giftDate
    ) {
        Gift__c gift = GivingTestDataFactory.buildGift(donorContactId, value);
        gift.Type__c = 'In-kind';
        gift.Gift_Date__c = giftDate;
        gift.In_Kind_Description__c = description;
        gift.Fair_Market_Value__c = value;
        return gift;
    }
}
