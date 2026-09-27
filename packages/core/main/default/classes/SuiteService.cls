/**
 * Which suite the organization is setting up, and which modules that suite offers (C-30,
 * ADR-0046 as amended 2026-09-27).
 *
 * BarnCRM is one app sold as two suites built from the same packages: the Nonprofit Suite
 * (Core with Giving and the nonprofit modules) and the Community Suite (Core with the modules
 * that fit any organization). The choice is the Core setting `Suite__c`, empty until an
 * administrator makes it. An empty setting is never read as a choice: the Setup Assistant
 * preselects a suite from what is installed, and nothing else changes until someone saves.
 *
 * The choice decides which modules the Setup Assistant lists and offers, and nothing more. It
 * installs, removes, hides and switches off nothing, so a module that is installed keeps its
 * steps, settings and automation whichever suite is chosen.
 *
 * Which modules a suite lists is data, `Suite_Module__mdt`, so a new module (Events) or an
 * install link, once a package version exists, arrives as a row or a value without a code
 * change. A module with no row for a suite is never listed for it.
 */
public with sharing class SuiteService {
    public static final String NONPROFIT = 'Nonprofit';
    public static final String COMMUNITY = 'Community';

    /** The Core setting that holds the choice. */
    public static final String SETTING_KEY = 'Suite__c';

    /** Only an installer on a secure address is ever offered as a link. */
    private static final String SECURE_SCHEME = 'https://';

    /** Rows used instead of the shipped ones: custom metadata cannot be created in a test. */
    @TestVisible
    private static List<Suite_Module__mdt> stubbedRows;

    /** Raised when a suite is not one of the two. */
    public class SuiteException extends Exception {
    }

    /** What the suite step shows: what was chosen, what is suggested, and each suite's modules. */
    public class SuiteModel {
        /** The saved choice, or null when nobody has chosen. */
        @AuraEnabled
        public String chosenSuite;
        /** The suite preselected while nobody has chosen: Nonprofit with Giving, else Community. */
        @AuraEnabled
        public String recommendedSuite;
        @AuraEnabled
        public Boolean givingPresent;
        @AuraEnabled
        public List<SuiteOption> options;
    }

    /** One suite, as the step offers it. */
    public class SuiteOption {
        @AuraEnabled
        public String value;
        @AuraEnabled
        public String label;
        @AuraEnabled
        public String description;
        /** The modules this suite lists, in order, each saying whether it is installed. */
        @AuraEnabled
        public List<ModuleDetectionService.ModuleInfo> modules;
    }

    /** The two suites, in the order the step offers them. */
    public static List<String> suites() {
        return new List<String>{ NONPROFIT, COMMUNITY };
    }

    /** The suite the organization chose, or null when nobody has chosen. */
    public static String chosenSuite() {
        String value = SettingsService.asText(SettingsService.getValue(SETTING_KEY)).trim();
        return suites().contains(value) ? value : null;
    }

    /**
     * Saves the choice as an ordinary, audited setting through its Setting Definition row, as
     * the console would, so the console and the assistant can never disagree about it.
     */
    public static void choose(String suite) {
        String chosen = suite == null ? '' : suite.trim();
        if (!suites().contains(chosen)) {
            throw new SuiteException(System.Label.Core_SetupAssistant_UnknownSuiteError);
        }
        SettingsService.saveValues(new Map<String, Object>{ SETTING_KEY => chosen });
    }

    /** Everything the suite step needs to draw itself. */
    public static SuiteModel model() {
        SuiteModel model = new SuiteModel();
        model.givingPresent = ModuleDetectionService.isGivingPresent();
        model.recommendedSuite = model.givingPresent ? NONPROFIT : COMMUNITY;
        model.chosenSuite = chosenSuite();
        model.options = new List<SuiteOption>{
            option(
                NONPROFIT,
                System.Label.Core_SetupAssistant_SuiteNonprofitLabel,
                System.Label.Core_SetupAssistant_SuiteNonprofitDescription
            ),
            option(
                COMMUNITY,
                System.Label.Core_SetupAssistant_SuiteCommunityLabel,
                System.Label.Core_SetupAssistant_SuiteCommunityDescription
            )
        };
        return model;
    }

    /**
     * The modules a suite lists, in its order, each saying whether it is installed, whether the
     * suite needs it, where to read about it, and its installer once one is published.
     */
    public static List<ModuleDetectionService.ModuleInfo> modulesFor(String suite) {
        List<ModuleDetectionService.ModuleInfo> modules = new List<ModuleDetectionService.ModuleInfo>();
        if (String.isBlank(suite)) {
            return modules;
        }
        for (Suite_Module__mdt row : rowsFor(suite)) {
            ModuleDetectionService.ModuleInfo info = new ModuleDetectionService.ModuleInfo();
            info.name = row.Module__c.trim();
            info.present = ModuleDetectionService.isPresent(info.name);
            info.required = row.Required__c == true;
            info.installUrl = secureOrNull(row.Install_Url__c);
            info.docsUrl = String.isBlank(row.Help_Path__c)
                ? null
                : SettingsController.HELP_BASE + row.Help_Path__c.trim();
            modules.add(info);
        }
        return modules;
    }

    private static SuiteOption option(String value, String label, String description) {
        SuiteOption option = new SuiteOption();
        option.value = value;
        option.label = label;
        option.description = description;
        option.modules = modulesFor(value);
        return option;
    }

    /** The rows naming this suite and a module, sorted by their order (a stable insertion sort). */
    private static List<Suite_Module__mdt> rowsFor(String suite) {
        List<Suite_Module__mdt> sorted = new List<Suite_Module__mdt>();
        for (Suite_Module__mdt row : rows()) {
            if (
                row == null ||
                String.isBlank(row.Module__c) ||
                String.isBlank(row.Suite__c) ||
                !suite.equalsIgnoreCase(row.Suite__c.trim())
            ) {
                continue;
            }
            Integer at = sorted.size();
            while (at > 0 && orderOf(sorted[at - 1]) > orderOf(row)) {
                at--;
            }
            if (at == sorted.size()) {
                sorted.add(row);
            } else {
                sorted.add(at, row);
            }
        }
        return sorted;
    }

    private static Decimal orderOf(Suite_Module__mdt row) {
        return row.Sort_Order__c == null ? 1000 : row.Sort_Order__c;
    }

    /**
     * The shipped rows, read as shipped: they are package data holding nothing about the org,
     * like the Setting Definition rows, and `getAll` costs no query.
     */
    private static List<Suite_Module__mdt> rows() {
        if (stubbedRows != null) {
            return stubbedRows;
        }
        return Suite_Module__mdt.getAll().values();
    }

    /** An installer address on https, or null, so a row can never offer another kind of link. */
    private static String secureOrNull(String url) {
        String trimmed = url == null ? '' : url.trim();
        return trimmed.toLowerCase().startsWith(SECURE_SCHEME) ? trimmed : null;
    }
}
