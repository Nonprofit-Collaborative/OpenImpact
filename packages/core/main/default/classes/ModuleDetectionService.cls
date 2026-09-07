/**
 * Which Open Impact packages are in this org, and what their objects are called.
 *
 * Core never references another package's schema statically (ADR-0009, plan Section 4.2):
 * every name below is a describe probe held as a string, and every caller has to cope with
 * the answer "not installed". A module is present when its probe object exists, or when it
 * has shipped Setting Definition rows naming itself (ADR-0017), which is how a module that
 * Core knows nothing else about announces itself to the settings console.
 */
public with sharing class ModuleDetectionService {
    // detection-only: Giving package is optional
    private static final String GIVING_FUND_OBJECT = 'Fund__c';
    // detection-only: Giving package is optional
    private static final String GIVING_APPEAL_OBJECT = 'Appeal__c';
    // detection-only: the Import framework (C-14) ships later in Core
    private static final String IMPORT_BATCH_OBJECT = 'Import_Batch__c';

    private static final String MODULE_CORE = 'Core';
    private static final String MODULE_GIVING = 'Giving';

    private static final String DOCS_BASE = 'https://github.com/Nonprofit-Collaborative/OpenImpact/blob/main/docs/product-plan.md';

    /** One row of the module list the Setup Assistant shows in step six. */
    public class ModuleInfo {
        @AuraEnabled
        public String name;
        @AuraEnabled
        public Boolean present;
        @AuraEnabled
        public String docsUrl;
    }

    /** True when the Giving package is installed, decided by describe, never by a compile time reference. */
    public static Boolean isGivingPresent() {
        return objectExists(GIVING_FUND_OBJECT) && objectExists(GIVING_APPEAL_OBJECT);
    }

    /** The fund object's API name, or null when Giving is not installed. */
    public static String fundObjectName() {
        return objectExists(GIVING_FUND_OBJECT) ? GIVING_FUND_OBJECT : null;
    }

    /** The appeal object's API name, or null when Giving is not installed. */
    public static String appealObjectName() {
        return objectExists(GIVING_APPEAL_OBJECT) ? GIVING_APPEAL_OBJECT : null;
    }

    /** True when the Import framework's staging object is in this org, so the Import tab is worth linking to. */
    public static Boolean isImportPresent() {
        return objectExists(IMPORT_BATCH_OBJECT);
    }

    /** The six Open Impact packages, each saying whether it is in this org. */
    public static List<ModuleInfo> getModules() {
        Set<String> announced = announcedModules();
        List<ModuleInfo> modules = new List<ModuleInfo>();
        modules.add(module(MODULE_CORE, true, '#51-core-package'));
        modules.add(
            module(
                MODULE_GIVING,
                isGivingPresent() || announced.contains(MODULE_GIVING.toLowerCase()),
                '#52-giving-package'
            )
        );
        modules.add(
            module('Volunteers', announced.contains('volunteers'), '#53-volunteers-package')
        );
        modules.add(module('Programs', announced.contains('programs'), '#54-programs-package'));
        modules.add(module('Funders', announced.contains('funders'), '#55-funders-package'));
        modules.add(module('Connect', announced.contains('connect'), '#56-connect-package'));
        return modules;
    }

    /** The modules that have shipped settings console rows naming themselves. */
    private static Set<String> announcedModules() {
        Set<String> names = new Set<String>();
        try {
            for (Setting_Definition__mdt definition : SettingDefinitionSelector.getAll()) {
                if (String.isNotBlank(definition.Module__c)) {
                    names.add(definition.Module__c.trim().toLowerCase());
                }
            }
        } catch (Exception e) {
            ErrorLogger.log(e, 'Open Impact module detection');
        }
        return names;
    }

    private static ModuleInfo module(String name, Boolean present, String anchor) {
        ModuleInfo info = new ModuleInfo();
        info.name = name;
        info.present = present;
        info.docsUrl = DOCS_BASE + anchor;
        return info;
    }

    private static Boolean objectExists(String objectName) {
        return Schema.getGlobalDescribe().containsKey(objectName.toLowerCase());
    }
}
