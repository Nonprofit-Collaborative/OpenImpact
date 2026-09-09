/**
 * The wording, merged.
 *
 * R-AT2 makes the token set closed and deliberately forgiving: a token the package knows is
 * replaced, a token it does not know is left exactly as it was typed, and a token whose value is
 * empty merges to nothing. A thank you is not a tax document, so a missing organization name
 * produces a letter with a gap in it rather than a refused save. A misspelled token, by contrast,
 * survives into the stored letter, where it is visible to whoever proofreads the first one.
 *
 * The email side of the feature is not merged here and is not merged anywhere: the package stores
 * the developer name of a standard email template and does not send email (R-AT3, R-AK8).
 */
public with sharing class AcknowledgmentTemplateService {
    public static final String TOKEN_DONOR_NAME = '{{DonorName}}';
    public static final String TOKEN_DONOR_FIRST_NAME = '{{DonorFirstName}}';
    public static final String TOKEN_GIFT_AMOUNT = '{{GiftAmount}}';
    public static final String TOKEN_GIFT_DATE = '{{GiftDate}}';
    public static final String TOKEN_GIFT_TYPE = '{{GiftType}}';
    public static final String TOKEN_APPEAL_NAME = '{{AppealName}}';
    public static final String TOKEN_ORGANIZATION_NAME = '{{OrganizationName}}';
    public static final String TOKEN_SIGNER_NAME = '{{SignerName}}';
    public static final String TOKEN_SIGNER_TITLE = '{{SignerTitle}}';

    /** The tokens the admin guide lists, so a test and a screen can read them from one place. */
    public static List<String> supportedTokens() {
        return new List<String>{
            TOKEN_DONOR_NAME,
            TOKEN_DONOR_FIRST_NAME,
            TOKEN_GIFT_AMOUNT,
            TOKEN_GIFT_DATE,
            TOKEN_GIFT_TYPE,
            TOKEN_APPEAL_NAME,
            TOKEN_ORGANIZATION_NAME,
            TOKEN_SIGNER_NAME,
            TOKEN_SIGNER_TITLE
        };
    }

    /**
     * The organization as a letter signs it. These are Core settings the Setup Assistant already
     * fills in for receipts, because letters other than receipts print them too (Section 21A).
     */
    public class OrganizationIdentity {
        public String name;
        public String signerName;
        public String signerTitle;
    }

    public static OrganizationIdentity organizationIdentity() {
        Nonprofit_Settings__c core = Nonprofit_Settings__c.getOrgDefaults();
        OrganizationIdentity identity = new OrganizationIdentity();
        identity.name = core.Organization_Legal_Name__c;
        identity.signerName = core.Receipt_Signer_Name__c;
        identity.signerTitle = core.Receipt_Signer_Title__c;
        return identity;
    }

    /**
     * One letter, for one gift. The gift is expected to have been read with its donor and appeal
     * names (`AcknowledgmentSelector.giftsToAcknowledge`); a gift read without them merges those
     * tokens to nothing rather than failing.
     */
    public static String mergeBody(String body, Gift__c gift, OrganizationIdentity identity) {
        if (String.isBlank(body)) {
            return '';
        }
        OrganizationIdentity org = identity == null ? new OrganizationIdentity() : identity;
        String merged = body;
        merged = merged.replace(TOKEN_DONOR_NAME, donorName(gift));
        merged = merged.replace(TOKEN_DONOR_FIRST_NAME, donorFirstName(gift));
        merged = merged.replace(TOKEN_GIFT_AMOUNT, amount(gift));
        merged = merged.replace(TOKEN_GIFT_DATE, giftDate(gift));
        merged = merged.replace(TOKEN_GIFT_TYPE, blankToEmpty(gift == null ? null : gift.Type__c));
        merged = merged.replace(TOKEN_APPEAL_NAME, appealName(gift));
        merged = merged.replace(TOKEN_ORGANIZATION_NAME, blankToEmpty(org.name));
        merged = merged.replace(TOKEN_SIGNER_NAME, blankToEmpty(org.signerName));
        merged = merged.replace(TOKEN_SIGNER_TITLE, blankToEmpty(org.signerTitle));
        return merged;
    }

    private static String donorName(Gift__c gift) {
        if (gift == null) {
            return '';
        }
        if (gift.Donor_Contact__c != null && gift.Donor_Contact__r != null) {
            return blankToEmpty(gift.Donor_Contact__r.Name);
        }
        if (gift.Donor_Account__c != null && gift.Donor_Account__r != null) {
            return blankToEmpty(gift.Donor_Account__r.Name);
        }
        return '';
    }

    /**
     * A person's first name, and an organization's whole name, because "Dear Riverside Community
     * Trust" is right and "Dear Riverside" is not.
     */
    private static String donorFirstName(Gift__c gift) {
        if (
            gift != null &&
            gift.Donor_Contact__c != null &&
            gift.Donor_Contact__r != null &&
            String.isNotBlank(gift.Donor_Contact__r.FirstName)
        ) {
            return gift.Donor_Contact__r.FirstName;
        }
        return donorName(gift);
    }

    private static String appealName(Gift__c gift) {
        if (gift == null || gift.Appeal__c == null || gift.Appeal__r == null) {
            return '';
        }
        return blankToEmpty(gift.Appeal__r.Name);
    }

    private static String amount(Gift__c gift) {
        return gift == null || gift.Amount__c == null ? '' : gift.Amount__c.format();
    }

    private static String giftDate(Gift__c gift) {
        return gift == null || gift.Gift_Date__c == null ? '' : gift.Gift_Date__c.format();
    }

    private static String blankToEmpty(String value) {
        return value == null ? '' : value;
    }
}
