/**
 * The data management settings read as the console documents them: empty is the shipped
 * default, and a value outside the accepted range is held at its nearest end.
 */
@IsTest
private class DataManagementSettingsTest {
    @IsTest
    static void anEmptyExportLimitIsTheShippedDefault() {
        Barn_Settings__c settings = TestDataFactory.defaultSettings();
        settings.Export_Row_Limit__c = null;
        TestDataFactory.saveSettings(settings);
        Assert.areEqual(50000, DataManagementSettings.exportRowLimit());
    }

    @IsTest
    static void anExportLimitOutsideTheRangeIsHeldAtItsEnd() {
        Barn_Settings__c settings = TestDataFactory.defaultSettings();
        settings.Export_Row_Limit__c = 900000;
        TestDataFactory.saveSettings(settings);
        Assert.areEqual(100000, DataManagementSettings.exportRowLimit());

        settings.Export_Row_Limit__c = 0;
        TestDataFactory.saveSettings(settings);
        Assert.areEqual(1, DataManagementSettings.exportRowLimit());

        settings.Export_Row_Limit__c = 250;
        TestDataFactory.saveSettings(settings);
        Assert.areEqual(250, DataManagementSettings.exportRowLimit());
    }

    @IsTest
    static void theBulkUpdateMaximumDefaultsAndIsHeldAtFortyEightThousand() {
        Barn_Settings__c settings = TestDataFactory.defaultSettings();
        settings.Bulk_Update_Max_Records__c = null;
        TestDataFactory.saveSettings(settings);
        Assert.areEqual(48000, DataManagementSettings.bulkUpdateMaxRecords());

        settings.Bulk_Update_Max_Records__c = 250000;
        TestDataFactory.saveSettings(settings);
        Assert.areEqual(48000, DataManagementSettings.bulkUpdateMaxRecords());

        settings.Bulk_Update_Max_Records__c = 10;
        TestDataFactory.saveSettings(settings);
        Assert.areEqual(10, DataManagementSettings.bulkUpdateMaxRecords());
    }
}
