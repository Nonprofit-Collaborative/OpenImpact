/**
 * The data management settings (canonical model Section 12, v0.7 keys), read the way the
 * import settings are: an empty value is the shipped default, and a value outside the accepted
 * range is held at its nearest end, because a limit of zero or of a million is not a choice
 * anybody means to make.
 */
@NamespaceAccessible
public with sharing class DataManagementSettings {
    @NamespaceAccessible
    public static final Integer EXPORT_ROW_LIMIT_DEFAULT = 50000;
    @NamespaceAccessible
    public static final Integer EXPORT_ROW_LIMIT_MAX = 100000;
    /**
     * 49,000, not 50,000: a bulk update counts its records in one request before it starts, and
     * a request may read 50,000 rows in all, less what it has already read and a margin, so a
     * count past about 49,500 cannot be made (owner decision, 2026-09-28, R-IB16).
     */
    @NamespaceAccessible
    public static final Integer BULK_UPDATE_MAX_DEFAULT = 49000;
    @NamespaceAccessible
    public static final Integer BULK_UPDATE_MAX_CEILING = 49000;

    /** The most rows one Find export may download (R-Q5). */
    @NamespaceAccessible
    public static Integer exportRowLimit() {
        return read('Export_Row_Limit__c', EXPORT_ROW_LIMIT_DEFAULT, EXPORT_ROW_LIMIT_MAX);
    }

    /** The most records one bulk update may change (R-IB16). */
    @NamespaceAccessible
    public static Integer bulkUpdateMaxRecords() {
        return read('Bulk_Update_Max_Records__c', BULK_UPDATE_MAX_DEFAULT, BULK_UPDATE_MAX_CEILING);
    }

    @TestVisible
    private static Integer read(String key, Integer fallback, Integer ceiling) {
        Object configured = SettingsService.hasKey(key) ? SettingsService.getValue(key) : null;
        if (configured == null || String.isBlank(String.valueOf(configured))) {
            return fallback;
        }
        try {
            Integer value = Decimal.valueOf(String.valueOf(configured)).intValue();
            return value < 1 ? 1 : Math.min(value, ceiling);
        } catch (Exception unreadable) {
            return fallback;
        }
    }
}
