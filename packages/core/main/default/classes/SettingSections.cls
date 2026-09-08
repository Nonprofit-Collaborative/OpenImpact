/**
 * The section names the Nonprofit Settings console groups by.
 *
 * Every package that ships a Setting Definition row uses one of these exact strings in
 * `Section__c`, and the Setup Assistant points its steps at them, so a step's Open action lands
 * on the section it names. A new section is added here first.
 */
@NamespaceAccessible
public with sharing class SettingSections {
    @NamespaceAccessible
    public static final String GENERAL = 'General';
    @NamespaceAccessible
    public static final String HOUSEHOLDS = 'Households';
    @NamespaceAccessible
    public static final String AUTOMATION = 'Automation';
    @NamespaceAccessible
    public static final String ACCESS = 'Access';
    @NamespaceAccessible
    public static final String HEALTH = 'Health';
    @NamespaceAccessible
    public static final String IMPORTING = 'Import';
    @NamespaceAccessible
    public static final String ORGANIZATION = 'Organization';
    @NamespaceAccessible
    public static final String GIVING = 'Giving';
    @NamespaceAccessible
    public static final String ROLLUPS = 'Rollups';
    @NamespaceAccessible
    public static final String ADDRESSES = 'Addresses';
    @NamespaceAccessible
    public static final String RELATIONSHIPS = 'Relationships';

    /** Every section name a package may use, in the order the console lists them. */
    @NamespaceAccessible
    public static List<String> all() {
        return new List<String>{
            GENERAL,
            ORGANIZATION,
            HOUSEHOLDS,
            RELATIONSHIPS,
            ADDRESSES,
            GIVING,
            ROLLUPS,
            AUTOMATION,
            ACCESS,
            IMPORTING,
            HEALTH
        };
    }

    /** True when the given name is one of the shipped sections, ignoring case and spacing. */
    @NamespaceAccessible
    public static Boolean isKnown(String name) {
        if (String.isBlank(name)) {
            return false;
        }
        for (String section : all()) {
            if (section.equalsIgnoreCase(name.trim())) {
                return true;
            }
        }
        return false;
    }
}
