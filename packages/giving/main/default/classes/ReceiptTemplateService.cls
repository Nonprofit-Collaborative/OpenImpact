/**
 * The letters an administrator writes, and the ones the package ships.
 *
 * ADR-0006 puts structured configuration an administrator manages as a list in a packaged custom
 * object, and package shipped defaults in custom metadata materialized into that object. So the
 * two letters Open Impact ships live in `Receipt_Template_Default__mdt` and are copied into
 * `Receipt_Template__c` records the first time they are needed, or when an administrator asks for
 * defaults to be restored. An upgrade updates the metadata and never touches what Maria wrote.
 */
public with sharing class ReceiptTemplateService {
    public class ReceiptTemplateException extends Exception {
    }

    /**
     * The body the renderer merges for one receipt type, materializing the shipped default the
     * first time a type is used so that an organization that has changed nothing still gets a
     * document rather than an error.
     */
    public static String activeBodyFor(String receiptType) {
        Receipt_Template__c template = ReceiptSelector.activeTemplate(receiptType);
        if (template == null) {
            installDefaults();
            template = ReceiptSelector.activeTemplate(receiptType);
        }
        if (template == null || String.isBlank(template.Body__c)) {
            throw new ReceiptTemplateException(Label.Giving_Receipt_NoActiveTemplate);
        }
        return template.Body__c;
    }

    /**
     * Creates any shipped letter this org does not have, and leaves every letter it does have
     * exactly as it is. Safe to run repeatedly, which is what makes it usable both lazily and as
     * the console's Restore defaults action.
     */
    public static List<Receipt_Template__c> installDefaults() {
        Set<String> typesPresent = new Set<String>();
        for (Receipt_Template__c existing : ReceiptSelector.allTemplates()) {
            typesPresent.add(existing.Type__c);
        }

        List<Receipt_Template__c> created = new List<Receipt_Template__c>();
        for (Receipt_Template_Default__mdt shipped : [
            SELECT Template_Name__c, Receipt_Type__c, Body__c
            FROM Receipt_Template_Default__mdt
            WITH SYSTEM_MODE
        ]) {
            if (typesPresent.contains(shipped.Receipt_Type__c)) {
                continue;
            }
            created.add(
                new Receipt_Template__c(
                    Name = shipped.Template_Name__c,
                    Type__c = shipped.Receipt_Type__c,
                    Body__c = shipped.Body__c,
                    Active__c = true
                )
            );
        }
        if (!created.isEmpty()) {
            Database.insert(created, true, AccessLevel.SYSTEM_MODE);
        }
        return created;
    }

    /**
     * R-RT1: one active letter per type. Activating one deactivates the others of its type in the
     * same save, so there is never a moment where two are active or none is.
     */
    public static void activate(Id templateId) {
        Receipt_Template__c chosen;
        List<Receipt_Template__c> toDeactivate = new List<Receipt_Template__c>();
        for (Receipt_Template__c template : ReceiptSelector.allTemplates()) {
            if (template.Id == templateId) {
                chosen = template;
            }
        }
        if (chosen == null) {
            throw new ReceiptTemplateException(Label.Giving_Receipt_TemplateNotFound);
        }
        for (Receipt_Template__c template : ReceiptSelector.allTemplates()) {
            if (
                template.Id != templateId &&
                template.Type__c == chosen.Type__c &&
                template.Active__c
            ) {
                template.Active__c = false;
                toDeactivate.add(template);
            }
        }
        chosen.Active__c = true;
        toDeactivate.add(chosen);
        Database.update(toDeactivate, true, AccessLevel.USER_MODE);
    }

    /** Saves a body an administrator edited. The letter is theirs; the tax sentences are not. */
    public static void saveBody(Id templateId, String body) {
        if (String.isBlank(body)) {
            throw new ReceiptTemplateException(Label.Giving_Receipt_EmptyTemplate);
        }
        Database.update(
            new List<Receipt_Template__c>{
                new Receipt_Template__c(Id = templateId, Body__c = body)
            },
            true,
            AccessLevel.USER_MODE
        );
    }
}
