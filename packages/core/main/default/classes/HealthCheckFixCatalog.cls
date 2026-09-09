/**
 * The six fixes Health Check offers, and nothing else (feature C-21).
 *
 * Each one passes all six conditions in ADR-0029, and the ADR is where a seventh has to be
 * argued before it is written. In particular each of these creates rows that are missing or
 * sets a package owned setting to the one value the finding names. **None of them deletes
 * anything, and none of them may be changed so that it does.**
 *
 * Nothing here is a new write path. Every action calls a service that already existed, was
 * already idempotent, and was already reachable from a page in the settings console:
 * `CoexistenceService`, `RollupService.ensureDefaults`, `AutomationControl.ensureDefaults`,
 * `ImportTemplateService.materializeDefaults` and `AccessService.assignRole`. What C-21 adds
 * is the ability to reach them from the finding that says they are needed, having first said
 * what pressing them will do.
 *
 * Every query is a call to an existing selector (plan Section 9.3). The preview and the apply
 * of an action both read the org: the preview so that the person sees the count before they
 * decide, the apply so that the count is right at the moment it acts.
 */
public with sharing class HealthCheckFixCatalog {
    /** The actions this version offers, in the order the report shows their findings. */
    public static Map<String, HealthCheckFix.Action> byKey() {
        Map<String, HealthCheckFix.Action> actions = new Map<String, HealthCheckFix.Action>();
        for (
            HealthCheckFix.Action action : new List<HealthCheckFix.Action>{
                new RecommendedModeFix(),
                new JunctionMembershipFix(),
                new ShippedRollupsFix(),
                new AutomationSwitchesFix(),
                new ImportTemplatesFix(),
                new AdminRoleFix()
            }
        ) {
            actions.put(action.key(), action);
        }
        return actions;
    }

    /**
     * How many packaged rollups, automation switches and import templates this org is missing.
     * Health Check asks the actions themselves rather than counting again, so the number in the
     * finding and the number in the preview can never disagree.
     */
    public static Integer missingCount(String fixKey) {
        HealthCheckFix.Preview preview = HealthCheckFix.preview(fixKey);
        return preview == null || preview.affected == null ? 0 : preview.affected;
    }

    /**
     * The automations that have a row on the Automation page but no shipped registry entry
     * behind them any more, usually because an upgrade stopped shipping them.
     *
     * There is no fix for this and there will not be one: the only remedy is a delete, and
     * ADR-0029 condition 3 refuses it. The rows are inert, because the dispatcher runs the
     * registry rather than the rows, so reporting them is the whole of the answer.
     */
    public static List<String> unregisteredAutomationNames() {
        Set<String> registered = new Set<String>();
        for (Automation_Registry__mdt entry : AutomationRegistrySelector.selectAll()) {
            if (String.isNotBlank(entry.DeveloperName)) {
                registered.add(entry.DeveloperName.toLowerCase());
            }
        }
        List<String> unregistered = new List<String>();
        for (Automation_Setting__c setting : AutomationSettingSelector.selectAllForFramework()) {
            String name = setting.Automation_Name__c;
            if (String.isNotBlank(name) && !registered.contains(name.toLowerCase())) {
                unregistered.add(String.isBlank(setting.Name) ? name : setting.Name);
            }
        }
        unregistered.sort();
        return unregistered;
    }

    // ------------------------------------------------------------------------ coexistence mode

    /**
     * Set the coexistence mode detection recommends. One setting, one value, already audited by
     * `SettingsService`, and reversible on the General page.
     */
    private class RecommendedModeFix implements HealthCheckFix.Action {
        public String key() {
            return HealthCheckFix.KEY_RECOMMENDED_MODE;
        }

        public Boolean writesSetupData() {
            return false;
        }

        public HealthCheckFix.Preview preview() {
            String current = CoexistenceService.getCurrentMode();
            String recommended = OrgShapeDetector.recommendedCoexistenceMode();
            Boolean needed = String.isNotBlank(recommended) && !recommended.equals(current);
            return new HealthCheckFix.Preview(
                key(),
                System.Label.Core_HealthCheckFix_ModeTitle,
                String.format(
                    System.Label.Core_HealthCheckFix_ModePreview,
                    new List<Object>{
                        HealthCheckService.modeLabel(current),
                        HealthCheckService.modeLabel(recommended)
                    }
                ),
                needed ? 1 : 0
            );
        }

        public HealthCheckFix.Result apply(HealthCheckFix.Preview ignored) {
            String recommended = OrgShapeDetector.recommendedCoexistenceMode();
            CoexistenceService.applyMode(recommended);
            return new HealthCheckFix.Result(
                key(),
                System.Label.Core_HealthCheckFix_ModeTitle,
                String.format(
                    System.Label.Core_HealthCheckFix_ModeResult,
                    new List<Object>{ HealthCheckService.modeLabel(recommended) }
                ),
                1
            );
        }
    }

    /**
     * Move household membership to the junction, which is the only way it works where people
     * are accounts. Existing households are not touched: this decides how the next one is built.
     */
    private class JunctionMembershipFix implements HealthCheckFix.Action {
        public String key() {
            return HealthCheckFix.KEY_JUNCTION_MEMBERSHIP;
        }

        public Boolean writesSetupData() {
            return false;
        }

        public HealthCheckFix.Preview preview() {
            Boolean alreadyJunction = CoexistenceService.MEMBERSHIP_JUNCTION.equals(
                CoexistenceService.getMembershipMode()
            );
            return new HealthCheckFix.Preview(
                key(),
                System.Label.Core_HealthCheckFix_MembershipTitle,
                System.Label.Core_HealthCheckFix_MembershipPreview,
                alreadyJunction ? 0 : 1
            );
        }

        public HealthCheckFix.Result apply(HealthCheckFix.Preview ignored) {
            CoexistenceService.applyJunctionMembership();
            return new HealthCheckFix.Result(
                key(),
                System.Label.Core_HealthCheckFix_MembershipTitle,
                System.Label.Core_HealthCheckFix_MembershipResult,
                1
            );
        }
    }

    // --------------------------------------------------------------------- materialized defaults

    /**
     * Create the packaged rollup definitions this org never materialized (R-R6). A definition
     * that is already here is left exactly as the administrator left it, including one they
     * edited or switched off, because `ensureDefaults` matches on the definition key and only
     * ever inserts.
     */
    private class ShippedRollupsFix implements HealthCheckFix.Action {
        public String key() {
            return HealthCheckFix.KEY_SHIPPED_ROLLUPS;
        }

        public Boolean writesSetupData() {
            return false;
        }

        public HealthCheckFix.Preview preview() {
            List<String> missing = missingNames();
            return new HealthCheckFix.Preview(
                    key(),
                    System.Label.Core_HealthCheckFix_RollupsTitle,
                    String.format(
                        System.Label.Core_HealthCheckFix_RollupsPreview,
                        new List<Object>{ String.valueOf(missing.size()) }
                    ),
                    missing.size()
                )
                .naming(missing);
        }

        public HealthCheckFix.Result apply(HealthCheckFix.Preview ignored) {
            Integer created = RollupService.ensureDefaults();
            return new HealthCheckFix.Result(
                key(),
                System.Label.Core_HealthCheckFix_RollupsTitle,
                String.format(
                    System.Label.Core_HealthCheckFix_RollupsResult,
                    new List<Object>{ String.valueOf(created) }
                ),
                created
            );
        }

        /**
         * The shipped rollups this org has no definition for. A row shipped by a module that is
         * not installed is not missing, it is inapplicable: neither its source nor its target
         * object is here, so `ensureDefaults` skips it and so does this count.
         */
        private List<String> missingNames() {
            Set<String> existing = new Set<String>();
            for (Rollup_Definition__c definition : RollupSelector.selectAll()) {
                if (String.isNotBlank(definition.Definition_Key__c)) {
                    existing.add(definition.Definition_Key__c.toLowerCase());
                }
            }
            List<String> missing = new List<String>();
            for (Rollup_Definition_Default__mdt shipped : RollupSelector.selectShippedDefaults()) {
                String definitionKey = shipped.Definition_Key__c;
                if (
                    String.isBlank(definitionKey) || existing.contains(definitionKey.toLowerCase())
                ) {
                    continue;
                }
                if (
                    SettingsService.typeByName(shipped.Source_Object__c) == null ||
                    SettingsService.typeByName(shipped.Target_Object__c) == null
                ) {
                    continue;
                }
                existing.add(definitionKey.toLowerCase());
                missing.add(
                    String.isBlank(shipped.MasterLabel) ? definitionKey : shipped.MasterLabel
                );
            }
            missing.sort();
            return missing;
        }
    }

    /**
     * Create the Automation Setting rows this org never materialized (R-A2), so that every
     * packaged automation has a switch on the Automation page. Nothing about how automation
     * runs changes: an automation with no row already runs, which is what makes this safe.
     */
    private class AutomationSwitchesFix implements HealthCheckFix.Action {
        public String key() {
            return HealthCheckFix.KEY_AUTOMATION_SWITCHES;
        }

        public Boolean writesSetupData() {
            return false;
        }

        public HealthCheckFix.Preview preview() {
            List<String> missing = missingNames();
            return new HealthCheckFix.Preview(
                    key(),
                    System.Label.Core_HealthCheckFix_AutomationTitle,
                    String.format(
                        System.Label.Core_HealthCheckFix_AutomationPreview,
                        new List<Object>{ String.valueOf(missing.size()) }
                    ),
                    missing.size()
                )
                .naming(missing);
        }

        public HealthCheckFix.Result apply(HealthCheckFix.Preview ignored) {
            Integer created = AutomationControl.ensureDefaults();
            return new HealthCheckFix.Result(
                key(),
                System.Label.Core_HealthCheckFix_AutomationTitle,
                String.format(
                    System.Label.Core_HealthCheckFix_AutomationResult,
                    new List<Object>{ String.valueOf(created) }
                ),
                created
            );
        }

        private List<String> missingNames() {
            Set<String> existing = new Set<String>();
            for (
                Automation_Setting__c setting : AutomationSettingSelector.selectAllForFramework()
            ) {
                if (String.isNotBlank(setting.Automation_Name__c)) {
                    existing.add(setting.Automation_Name__c.toLowerCase());
                }
            }
            List<String> missing = new List<String>();
            for (Automation_Registry__mdt entry : AutomationRegistrySelector.selectAll()) {
                String name = entry.DeveloperName;
                if (String.isBlank(name) || existing.contains(name.toLowerCase())) {
                    continue;
                }
                existing.add(name.toLowerCase());
                missing.add(String.isBlank(entry.MasterLabel) ? name : entry.MasterLabel);
            }
            missing.sort();
            return missing;
        }
    }

    /**
     * Create the packaged import templates this org never materialized (R-IT4). A template the
     * administrator has edited keeps its mapping: materialization matches on the template key
     * and only ever inserts.
     */
    private class ImportTemplatesFix implements HealthCheckFix.Action {
        public String key() {
            return HealthCheckFix.KEY_IMPORT_TEMPLATES;
        }

        public Boolean writesSetupData() {
            return false;
        }

        public HealthCheckFix.Preview preview() {
            List<String> missing = missingNames();
            return new HealthCheckFix.Preview(
                    key(),
                    System.Label.Core_HealthCheckFix_TemplatesTitle,
                    String.format(
                        System.Label.Core_HealthCheckFix_TemplatesPreview,
                        new List<Object>{ String.valueOf(missing.size()) }
                    ),
                    missing.size()
                )
                .naming(missing);
        }

        public HealthCheckFix.Result apply(HealthCheckFix.Preview ignored) {
            Integer created = ImportTemplateService.materializeDefaults();
            return new HealthCheckFix.Result(
                key(),
                System.Label.Core_HealthCheckFix_TemplatesTitle,
                String.format(
                    System.Label.Core_HealthCheckFix_TemplatesResult,
                    new List<Object>{ String.valueOf(created) }
                ),
                created
            );
        }

        private List<String> missingNames() {
            List<Import_Template_Default__mdt> shipped = ImportTemplateSelector.selectShippedDefaults();
            Set<String> keys = new Set<String>();
            for (Import_Template_Default__mdt row : shipped) {
                if (String.isNotBlank(row.Template_Key__c)) {
                    keys.add(row.Template_Key__c);
                }
            }
            Map<String, Import_Template__c> existing = ImportTemplateSelector.selectByKeys(keys);
            List<String> missing = new List<String>();
            for (Import_Template_Default__mdt row : shipped) {
                String templateKey = row.Template_Key__c;
                if (String.isBlank(templateKey) || existing.containsKey(templateKey)) {
                    continue;
                }
                missing.add(String.isBlank(row.MasterLabel) ? templateKey : row.MasterLabel);
            }
            missing.sort();
            return missing;
        }
    }

    // ------------------------------------------------------------------------------- admin role

    /**
     * Finish what the install started. `CorePostInstall` assigns the Nonprofit Admin permission
     * set first and the Nonprofit Admin role second, because the platform refuses to assign a
     * packaged permission set group while it is still calculating it, which is the usual state
     * in the minutes after an install. When the retries run out, the people who installed or
     * were set up in those minutes hold the permission set and not the role: they can use the
     * app, and the Access page shows the role as held by nobody.
     *
     * This gives them the role. Nobody gains access: `Nonprofit_Admin_Group` contains exactly
     * the `Nonprofit_Admin` permission set, which is the one they already hold. ADR-0029 records
     * that this fix has to be re-examined if a second permission set is ever added to that group.
     */
    private class AdminRoleFix implements HealthCheckFix.Action {
        public String key() {
            return HealthCheckFix.KEY_ADMIN_ROLE;
        }

        public Boolean writesSetupData() {
            return true;
        }

        public HealthCheckFix.Preview preview() {
            List<User> waiting = usersWaitingForTheRole();
            List<String> names = new List<String>();
            for (User person : waiting) {
                names.add(person.Name);
            }
            return new HealthCheckFix.Preview(
                    key(),
                    System.Label.Core_HealthCheckFix_AdminRoleTitle,
                    String.format(
                        System.Label.Core_HealthCheckFix_AdminRolePreview,
                        new List<Object>{ String.valueOf(waiting.size()) }
                    ),
                    waiting.size()
                )
                .naming(names);
        }

        public HealthCheckFix.Result apply(HealthCheckFix.Preview ignored) {
            Set<Id> userIds = new Set<Id>();
            for (User person : usersWaitingForTheRole()) {
                userIds.add(person.Id);
            }
            if (!userIds.isEmpty()) {
                AccessService.assignRole(userIds, AccessService.ADMIN_ROLE);
            }
            return new HealthCheckFix.Result(
                key(),
                System.Label.Core_HealthCheckFix_AdminRoleTitle,
                String.format(
                    System.Label.Core_HealthCheckFix_AdminRoleResult,
                    new List<Object>{ String.valueOf(userIds.size()) }
                ),
                userIds.size()
            );
        }

        /**
         * The active people who hold the Nonprofit Admin permission set directly but not the
         * role that contains it.
         */
        private List<User> usersWaitingForTheRole() {
            Set<Id> holdTheSet = UserAccessSelector.getPermissionSetAssigneeIds(
                new Set<String>{ HealthCheckService.PERMISSION_SET_ADMIN }
            );
            if (holdTheSet.isEmpty()) {
                return new List<User>();
            }
            holdTheSet.removeAll(
                UserAccessSelector.getAssignedUserIds(
                    new Set<String>{ HealthCheckService.GROUP_ADMIN }
                )
            );
            if (holdTheSet.isEmpty()) {
                return new List<User>();
            }
            return new UserSelector().selectActiveByIds(holdTheSet);
        }
    }
}
