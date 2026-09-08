/**
 * Import templates: the ones the package ships, and the ones the administrator edits.
 *
 * Materialization follows the settings strategy in ADR-0006 and R-IT4. A shipped default
 * becomes a real `Import_Template__c` record the first time it is seen, matched by template
 * key, and is never overwritten afterwards, so an administrator's edit survives every
 * upgrade. Person Mode is the one value taken from the org rather than from the shipped row
 * (R-IT3): a Nonprofit Cloud or Agentforce Nonprofit org that stores people as person
 * Accounts gets templates that say so.
 */
@NamespaceAccessible
public with sharing class ImportTemplateService {
    @NamespaceAccessible
    public static final String PERSON_MODE_CONTACTS = 'Contacts';
    @NamespaceAccessible
    public static final String PERSON_MODE_PERSON_ACCOUNTS = 'Person Accounts';

    @NamespaceAccessible
    public static final String RULE_EMAIL = 'Email exact';
    @NamespaceAccessible
    public static final String RULE_NAME_POSTAL = 'Name plus postal code';
    @NamespaceAccessible
    public static final String RULE_EXTERNAL_ID = 'External ID';

    private static final Set<String> RULES = new Set<String>{
        RULE_EMAIL,
        RULE_NAME_POSTAL,
        RULE_EXTERNAL_ID
    };

    /**
     * Creates an `Import_Template__c` for every shipped default this org does not have yet,
     * and returns how many were created. Safe to call repeatedly: it is called on install
     * and whenever the wizard opens with no templates.
     */
    @NamespaceAccessible
    public static Integer materializeDefaults() {
        List<Import_Template_Default__mdt> shipped = ImportTemplateSelector.selectShippedDefaults();
        if (shipped.isEmpty()) {
            return 0;
        }
        Set<String> keys = new Set<String>();
        for (Import_Template_Default__mdt row : shipped) {
            if (String.isNotBlank(row.Template_Key__c)) {
                keys.add(row.Template_Key__c);
            }
        }
        Map<String, Import_Template__c> existing = ImportTemplateSelector.selectByKeys(keys);
        String personMode = defaultPersonMode();
        List<Import_Template__c> toCreate = new List<Import_Template__c>();
        for (Import_Template_Default__mdt row : shipped) {
            if (String.isBlank(row.Template_Key__c) || existing.containsKey(row.Template_Key__c)) {
                continue;
            }
            toCreate.add(
                new Import_Template__c(
                    Name = row.MasterLabel,
                    Description__c = row.Description__c,
                    Template_Key__c = row.Template_Key__c,
                    Column_Mapping_JSON__c = row.Column_Mapping_JSON__c,
                    Default_Values_JSON__c = row.Default_Values_JSON__c,
                    Matching_Rule__c = normalizedRule(row.Matching_Rule__c),
                    Person_Mode__c = personMode,
                    Is_Package_Default__c = true,
                    Is_Recurring__c = false,
                    Active__c = row.Default_Active__c == true
                )
            );
        }
        if (toCreate.isEmpty()) {
            return 0;
        }
        Database.insert(toCreate, AccessLevel.USER_MODE);
        return toCreate.size();
    }

    /**
     * The active templates, materializing the shipped defaults first when the org has none.
     * This is what the wizard asks for when it opens.
     */
    @NamespaceAccessible
    public static List<Import_Template__c> listActive() {
        List<Import_Template__c> templates = ImportTemplateSelector.selectActive();
        if (!templates.isEmpty()) {
            return templates;
        }
        materializeDefaults();
        return ImportTemplateSelector.selectActive();
    }

    /**
     * Saves the mapping the administrator built in the picker back onto its template, so the
     * same file next month needs no work. The mapping is validated before it is stored.
     */
    @NamespaceAccessible
    public static Import_Template__c saveMapping(
        Id templateId,
        String mappingDocument,
        String matchingRule
    ) {
        Import_Template__c template = ImportTemplateSelector.selectById(templateId);
        if (template == null) {
            throw new ImportException(Label.Core_Import_ErrorTemplateGone);
        }
        ImportMapping mapping = ImportMapping.parse(mappingDocument);
        if (!mapping.identifiesSomebody()) {
            throw new ImportException(Label.Core_Import_ErrorMappingIdentifiesNobody);
        }
        template.Column_Mapping_JSON__c = mapping.serialize();
        template.Matching_Rule__c = normalizedRule(matchingRule);
        Database.update(template, AccessLevel.USER_MODE);
        return template;
    }

    /** Records that a template was used, so the Hub can say how stale a recurring feed is. */
    @NamespaceAccessible
    public static void recordImport(Id templateId, Date completedOn) {
        if (templateId == null) {
            return;
        }
        Import_Template__c template = new Import_Template__c(
            Id = templateId,
            Last_Import_Date__c = completedOn == null ? Date.today() : completedOn
        );
        Database.update(template, AccessLevel.SYSTEM_MODE);
    }

    /** The person mode a new template starts in, from the org shape the assistant detected. */
    @NamespaceAccessible
    public static String defaultPersonMode() {
        return HouseholdService.isPersonAccountOrg()
            ? PERSON_MODE_PERSON_ACCOUNTS
            : PERSON_MODE_CONTACTS;
    }

    /** True when this template asks for people to be stored as person Accounts (R-IT3). */
    @NamespaceAccessible
    public static Boolean isPersonAccountMode(Import_Template__c template) {
        return template != null &&
            PERSON_MODE_PERSON_ACCOUNTS.equalsIgnoreCase(template.Person_Mode__c);
    }

    /** A rule name the picklist accepts. Anything unrecognized falls back to the safe rule. */
    @NamespaceAccessible
    public static String normalizedRule(String rule) {
        if (String.isBlank(rule)) {
            return RULE_EMAIL;
        }
        for (String known : RULES) {
            if (known.equalsIgnoreCase(rule.trim())) {
                return known;
            }
        }
        return RULE_EMAIL;
    }
}
