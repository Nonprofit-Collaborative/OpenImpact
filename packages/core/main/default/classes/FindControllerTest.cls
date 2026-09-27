/**
 * Find's entry points (C-34): the permission gate, a run, the export paged in Id order up to
 * the export row limit, and sharing. The sharing cases run as two users on a minimal profile
 * holding only BarnCRM Admin, over saved queries, which have private sharing: what one person
 * saved and did not share is never returned to the other, by Find or by the saved query list.
 */
@IsTest
private class FindControllerTest {
    private static String documentFor(String objectName, List<String> fields) {
        return JSON.serialize(
            new Map<String, Object>{ 'version' => 1, 'object' => objectName, 'fields' => fields }
        );
    }

    private static List<Saved_Query__c> insertQueries(Integer howMany, String prefix) {
        List<Saved_Query__c> queries = new List<Saved_Query__c>();
        for (Integer i = 0; i < howMany; i++) {
            queries.add(
                new Saved_Query__c(
                    Name = prefix + String.valueOf(i).leftPad(4, '0'),
                    Object_Name__c = 'Contact',
                    Query_JSON__c = documentFor('Contact', new List<String>{ 'LastName' })
                )
            );
        }
        insert queries;
        return queries;
    }

    @IsTest
    static void refusesEverythingWithoutThePermission() {
        FindController.permissionOverride = false;
        Assert.isFalse(FindController.getContext().canUse);
        try {
            FindController.run(documentFor('Contact', new List<String>()));
            Assert.fail('Find must refuse without Find and Export Records');
        } catch (AuraHandledException refused) {
            Assert.areEqual(Label.Core_Find_ErrorNoPermission, refused.getMessage());
        }
        Assert.areEqual(0, [SELECT COUNT() FROM Error_Log__c], 'a refusal is not a fault');
    }

    @IsTest
    static void runsADocumentAndFlattensItsRowsByPath() {
        FindController.permissionOverride = true;
        insertQueries(3, 'Q');
        FindController.RunResult result = FindController.run(
            documentFor('Saved_Query__c', new List<String>{ 'Name', 'CreatedBy.Name' })
        );
        Assert.areEqual(3, result.rows.size());
        Assert.areEqual(3, result.columns.size());
        Assert.areEqual(UserInfo.getName(), result.rows[0].get('CreatedBy.Name'));
        Assert.isTrue(
            result.soql.startsWith('SELECT Id, Name, CreatedBy.Name FROM Saved_Query__c'),
            result.soql
        );
        Assert.isFalse(result.limitReached);
    }

    @IsTest
    static void previewSaysWhyADocumentDoesNotCompileWithoutThrowing() {
        FindController.permissionOverride = true;
        FindController.Preview preview = FindController.preview(
            documentFor('Contact', new List<String>{ 'NoSuchField__c' })
        );
        Assert.isNull(preview.soql);
        Assert.isTrue(preview.error.contains('NoSuchField__c'), preview.error);
    }

    @IsTest
    static void exportsEveryRecordOnceInIdOrder() {
        FindController.permissionOverride = true;
        QuerySelector.exportPageSize = 100;
        List<Saved_Query__c> inserted = insertQueries(250, 'E');
        String doc = documentFor('Saved_Query__c', new List<String>{ 'Name' });

        Set<Id> seen = new Set<Id>();
        Integer exported = 0;
        String afterId;
        Integer pages = 0;
        while (true) {
            QuerySelector.ExportPage page = FindController.exportPage(doc, afterId, exported);
            pages++;
            for (Map<String, Object> row : page.rows) {
                exported++;
                seen.add((Id) row.get('Id'));
            }
            if (page.done) {
                Assert.isFalse(page.stoppedAtLimit);
                break;
            }
            afterId = page.lastId;
        }
        Assert.areEqual(3, pages);
        Assert.areEqual(250, exported, 'no row is repeated');
        Assert.areEqual(new Map<Id, Saved_Query__c>(inserted).keySet(), seen);
    }

    @IsTest
    static void stopsAtTheExportRowLimitAndSaysSo() {
        FindController.permissionOverride = true;
        Barn_Settings__c settings = TestDataFactory.defaultSettings();
        settings.Export_Row_Limit__c = 120;
        TestDataFactory.saveSettings(settings);
        QuerySelector.exportPageSize = 100;
        insertQueries(200, 'L');
        String doc = documentFor('Saved_Query__c', new List<String>{ 'Name' });

        QuerySelector.ExportPage first = FindController.exportPage(doc, null, 0);
        Assert.areEqual(100, first.rows.size());
        Assert.isFalse(first.done);
        QuerySelector.ExportPage second = FindController.exportPage(doc, first.lastId, 100);
        Assert.areEqual(20, second.rows.size(), 'the second page stops at the limit');
        Assert.isTrue(second.done);
        Assert.isTrue(second.stoppedAtLimit);
        Assert.areEqual(120, second.exportLimit);
    }

    @IsTest
    static void refusesAnExportCursorFromAnotherObject() {
        FindController.permissionOverride = true;
        try {
            FindController.exportPage(
                documentFor('Saved_Query__c', new List<String>()),
                UserInfo.getUserId(),
                0
            );
            Assert.fail('a cursor must be a record of the queried object');
        } catch (AuraHandledException refused) {
            Assert.areEqual(Label.Core_Find_ErrorInvalidDocument, refused.getMessage());
        }
    }

    @IsTest
    static void listsQueryableObjectsAndDescribesTheirLookups() {
        FindController.permissionOverride = true;
        Set<String> names = new Set<String>();
        for (FindController.ObjectOption option : FindController.getObjects()) {
            names.add(option.name);
        }
        Assert.isTrue(names.contains('Contact'));
        Assert.isFalse(names.contains('Barn_Settings__c'), 'a custom setting is not listed');
        Assert.isFalse(names.contains('Setting_Definition__mdt'), 'metadata is not listed');

        FindController.FieldOption account;
        for (FindController.FieldOption field : FindController.describeObject('Contact').fields) {
            if (field.name == 'AccountId') {
                account = field;
            }
        }
        Assert.areEqual('Account', account.relationshipName);
        Assert.areEqual('Account', account.referenceTo);

        List<FindController.PathDescription> described = FindController.describePaths(
            'Contact',
            new List<String>{ 'account.name', 'Nope__c' }
        );
        Assert.areEqual(1, described.size(), 'a path that does not resolve is left out');
        Assert.areEqual('Account.Name', described[0].path);
    }

    @IsTest
    static void neverReturnsAQueryAnotherPersonDidNotShare() {
        User owner = TestDataFactory.createUser('Findown', new List<String>{ 'Barn_Admin' });
        User colleague = TestDataFactory.createUser('Findcol', new List<String>{ 'Barn_Admin' });
        Id sharedId;
        Id privateId;
        System.runAs(owner) {
            FindController.permissionOverride = true;
            sharedId = FindController.saveQuery(
                    null,
                    'Shared list',
                    true,
                    documentFor('Saved_Query__c', new List<String>{ 'Name' })
                )
                .id;
            privateId = FindController.saveQuery(
                    null,
                    'Private list',
                    false,
                    documentFor('Saved_Query__c', new List<String>{ 'Name' })
                )
                .id;
        }
        System.runAs(colleague) {
            FindController.permissionOverride = true;
            SavedQuerySharedReader.permissionOverride = true;
            // Find itself runs in user mode: neither of the owner's records is a row here.
            FindController.RunResult result = FindController.run(
                documentFor('Saved_Query__c', new List<String>{ 'Name' })
            );
            Assert.areEqual(0, result.rows.size());

            Set<String> listed = new Set<String>();
            for (SavedQueryService.SavedQueryView view : FindController.getSavedQueries()) {
                listed.add(view.id);
                Assert.isFalse(view.isOwn);
            }
            Assert.isTrue(listed.contains(sharedId), 'a shared query is listed');
            Assert.isFalse(listed.contains(privateId), 'a private one is not');
            Assert.areEqual('Shared list', FindController.openQuery(sharedId).name);
            try {
                FindController.openQuery(privateId);
                Assert.fail('a private query cannot be opened by somebody else');
            } catch (AuraHandledException refused) {
                Assert.areEqual(Label.Core_Find_ErrorSavedGone, refused.getMessage());
            }
            try {
                FindController.saveQuery(
                    sharedId,
                    'Taken over',
                    false,
                    documentFor('Saved_Query__c', new List<String>())
                );
                Assert.fail('only the owner may change a query');
            } catch (AuraHandledException refused) {
                Assert.areEqual(Label.Core_Find_ErrorNotOwner, refused.getMessage());
            }
            try {
                FindController.deleteQuery(sharedId);
                Assert.fail('only the owner may delete a query');
            } catch (AuraHandledException refused) {
                Assert.areEqual(Label.Core_Find_ErrorNotOwner, refused.getMessage());
            }
            // Saving without an identifier keeps the colleague's own copy.
            Assert.isTrue(
                FindController.saveQuery(
                        null,
                        'My copy',
                        false,
                        FindController.openQuery(sharedId).document
                    )
                    .isOwn
            );
        }
        Assert.areEqual(
            'Shared list',
            [SELECT Name FROM Saved_Query__c WHERE Id = :sharedId].Name,
            'the owner\'s query is unchanged'
        );
    }

    @IsTest
    static void savesOnlyTheDocumentsOwnShape() {
        FindController.permissionOverride = true;
        Map<String, Object> raw = new Map<String, Object>{
            'version' => 1,
            'object' => 'Saved_Query__c',
            'fields' => new List<String>{ 'Name' },
            'soql' => 'SELECT Id FROM User'
        };
        SavedQueryService.SavedQueryView saved = FindController.saveQuery(
            null,
            'Mine',
            false,
            JSON.serialize(raw)
        );
        Assert.isFalse(saved.document.contains('soql'), 'a key outside the document is dropped');
        Assert.areEqual('Saved_Query__c', saved.objectName);
    }

    @IsTest
    static void theSharedListIsEmptyWithoutAToolPermission() {
        SavedQuerySharedReader.permissionOverride = false;
        insert new Saved_Query__c(
            Name = 'Shared',
            Object_Name__c = 'Contact',
            Is_Shared__c = true,
            Query_JSON__c = '{}'
        );
        Assert.isTrue(SavedQuerySharedReader.sharedByOthers().isEmpty());
    }
}
