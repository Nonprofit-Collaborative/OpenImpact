/**
 * Templates: the shipped ones are materialized once and never overwritten (R-IT4), the
 * matching rule is always one the picklist accepts, and a mapping that identifies nobody is
 * refused before it can be saved.
 */
@IsTest
private class ImportTemplateServiceTest {
    @TestSetup
    static void setUp() {
        TestDataFactory.defaultSettings();
    }

    @IsTest
    static void materializesEveryShippedTemplateOnce() {
        Test.startTest();
        Integer firstRun = ImportTemplateService.materializeDefaults();
        Integer secondRun = ImportTemplateService.materializeDefaults();
        Test.stopTest();

        Assert.isTrue(firstRun > 0, 'The package ships at least one template.');
        Assert.areEqual(0, secondRun, 'A second run creates nothing: the keys already exist.');
        List<Import_Template__c> templates = [
            SELECT Id, Template_Key__c, Is_Package_Default__c
            FROM Import_Template__c
        ];
        Assert.areEqual(firstRun, templates.size(), 'One record per shipped template.');
        for (Import_Template__c template : templates) {
            Assert.isTrue(template.Is_Package_Default__c, 'Each is marked as a shipped default.');
        }
    }

    @IsTest
    static void neverOverwritesAnEditedTemplate() {
        ImportTemplateService.materializeDefaults();
        Import_Template__c template = [
            SELECT Id, Name, Column_Mapping_JSON__c
            FROM Import_Template__c
            LIMIT 1
        ];
        template.Name = 'Maria renamed this';
        template.Column_Mapping_JSON__c = ImportTestDataFactory.donorMapping();
        update template;

        Test.startTest();
        ImportTemplateService.materializeDefaults();
        Test.stopTest();

        Import_Template__c after = [
            SELECT Name, Column_Mapping_JSON__c
            FROM Import_Template__c
            WHERE Id = :template.Id
        ];
        Assert.areEqual('Maria renamed this', after.Name, 'The administrator edit survives.');
        Assert.areEqual(
            ImportTestDataFactory.donorMapping(),
            after.Column_Mapping_JSON__c,
            'So does the mapping they corrected.'
        );
    }

    @IsTest
    static void listingTemplatesMaterializesTheShippedOnesOnFirstUse() {
        Test.startTest();
        List<Import_Template__c> templates = ImportTemplateService.listActive();
        Test.stopTest();
        Assert.isFalse(
            templates.isEmpty(),
            'An org that has never imported still sees the shipped mappings.'
        );
    }

    @IsTest
    static void savesAMappingBackToItsTemplate() {
        Import_Template__c template = ImportTestDataFactory.template(
            ImportTestDataFactory.donorMapping(),
            ImportTemplateService.RULE_EMAIL
        );
        ImportMapping changed = ImportMapping.parse(ImportTestDataFactory.donorMapping());
        changed.columns.add(new ImportMapping.Column('Phone', 'Contact1.Phone'));

        Test.startTest();
        ImportTemplateService.saveMapping(
            template.Id,
            changed.serialize(),
            ImportTemplateService.RULE_NAME_POSTAL
        );
        Test.stopTest();

        Import_Template__c after = [
            SELECT Column_Mapping_JSON__c, Matching_Rule__c
            FROM Import_Template__c
            WHERE Id = :template.Id
        ];
        Assert.areEqual(
            ImportTemplateService.RULE_NAME_POSTAL,
            after.Matching_Rule__c,
            'The rule the administrator chose is stored.'
        );
        Assert.isTrue(
            after.Column_Mapping_JSON__c.contains('Contact1.Phone'),
            'And so is the column they added.'
        );
    }

    @IsTest
    static void refusesAMappingThatIdentifiesNobody() {
        Import_Template__c template = ImportTestDataFactory.template(
            ImportTestDataFactory.donorMapping(),
            ImportTemplateService.RULE_EMAIL
        );
        ImportMapping useless = new ImportMapping();
        useless.columns.add(new ImportMapping.Column('City', 'Contact1.MailingCity'));

        Test.startTest();
        try {
            ImportTemplateService.saveMapping(
                template.Id,
                useless.serialize(),
                ImportTemplateService.RULE_EMAIL
            );
            Assert.fail('A mapping that identifies nobody must be refused.');
        } catch (ImportException e) {
            Assert.areEqual(
                Label.Core_Import_ErrorMappingIdentifiesNobody,
                e.getMessage(),
                'And refused with the message the admin guide quotes.'
            );
        }
        Test.stopTest();
    }

    @IsTest
    static void refusesToSaveAgainstATemplateThatIsGone() {
        Import_Template__c template = ImportTestDataFactory.template(
            ImportTestDataFactory.donorMapping(),
            ImportTemplateService.RULE_EMAIL
        );
        Id templateId = template.Id;
        delete template;

        Test.startTest();
        try {
            ImportTemplateService.saveMapping(
                templateId,
                ImportTestDataFactory.donorMapping(),
                ImportTemplateService.RULE_EMAIL
            );
            Assert.fail('A deleted template cannot be saved to.');
        } catch (ImportException e) {
            Assert.areEqual(Label.Core_Import_ErrorTemplateGone, e.getMessage(), 'Said plainly.');
        }
        Test.stopTest();
    }

    @IsTest
    static void normalizesTheMatchingRule() {
        Assert.areEqual(
            ImportTemplateService.RULE_EMAIL,
            ImportTemplateService.normalizedRule('email EXACT'),
            'Capitalization and spacing do not matter.'
        );
        Assert.areEqual(
            ImportTemplateService.RULE_EMAIL,
            ImportTemplateService.normalizedRule('something else'),
            'An unrecognized rule falls back to the safe one rather than failing a save.'
        );
        Assert.areEqual(
            ImportTemplateService.RULE_EXTERNAL_ID,
            ImportTemplateService.normalizedRule(ImportTemplateService.RULE_EXTERNAL_ID),
            'A real rule is kept.'
        );
    }

    @IsTest
    static void recordsWhenATemplateWasLastUsed() {
        Import_Template__c template = ImportTestDataFactory.template(
            ImportTestDataFactory.donorMapping(),
            ImportTemplateService.RULE_EMAIL
        );
        Test.startTest();
        ImportTemplateService.recordImport(template.Id, Date.today());
        Test.stopTest();
        Assert.areEqual(
            Date.today(),
            [SELECT Last_Import_Date__c FROM Import_Template__c WHERE Id = :template.Id]
            .Last_Import_Date__c,
            'The Hub can say how long it is since this feed was loaded.'
        );
    }

    @IsTest
    static void personModeFollowsTheOrgShape() {
        Assert.areEqual(
            ImportTemplateService.PERSON_MODE_CONTACTS,
            ImportTemplateService.defaultPersonMode(),
            'A platform-only org stores people as contacts.'
        );
    }
}
