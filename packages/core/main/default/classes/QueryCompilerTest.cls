/**
 * The query compiler against the security review notes in ADR-0047 (amended): names only from
 * describe, every value bound, fixed operators and logic, and the display query never run.
 *
 * The injection cases here are the ones a reviewer would try first. Each asserts either that
 * the document is refused before any query is built, or that the hostile text reaches the
 * query only as a bind value and so matches nothing.
 */
@IsTest
private class QueryCompilerTest {
    private static QueryDocument document(String objectName, List<String> fields) {
        QueryDocument result = new QueryDocument();
        result.objectName = objectName;
        result.fields = fields;
        return result;
    }

    private static QueryDocument.Condition condition(
        String id,
        String field,
        String operator,
        Object value
    ) {
        QueryDocument.Condition result = new QueryDocument.Condition();
        result.id = id;
        result.field = field;
        result.operator = operator;
        result.value = value;
        return result;
    }

    private static String refusal(QueryDocument doc) {
        try {
            QueryCompiler.compile(doc);
        } catch (QueryCompiler.QueryCompilerException refused) {
            return refused.getMessage();
        }
        return null;
    }

    private static void insertQueries(List<String> names) {
        List<Saved_Query__c> queries = new List<Saved_Query__c>();
        for (String name : names) {
            queries.add(
                new Saved_Query__c(Name = name, Object_Name__c = 'Contact', Query_JSON__c = '{}')
            );
        }
        insert queries;
    }

    @IsTest
    static void compilesFieldsWithTheNamesDescribeReturns() {
        QueryDocument doc = document(
            'saved_query__c',
            new List<String>{ 'name', 'OBJECT_NAME__C' }
        );
        QueryCompiler.Compiled compiled = QueryCompiler.compile(doc);
        Assert.areEqual('Saved_Query__c', compiled.objectName);
        QueryCompiler.Query query = compiled.rows(2000);
        Assert.areEqual(
            'SELECT Id, Name, Object_Name__c FROM Saved_Query__c LIMIT :rowLimit',
            query.soql
        );
        Assert.areEqual(2000, query.binds.get('rowLimit'));
        Assert.areEqual(3, compiled.columns().size(), 'the record identifier is always a column');
    }

    @IsTest
    static void followsTwoLookupsAndNoMore() {
        QueryCompiler.ResolvedField field = QueryCompiler.resolvePath(
            Contact.SObjectType,
            'account.owner.name'
        );
        Assert.areEqual('Account.Owner.Name', field.path);
        Assert.areEqual(new List<String>{ 'Account', 'Owner' }, field.relationships);

        String message = refusal(
            document('Contact', new List<String>{ 'Account.Owner.Manager.Name' })
        );
        Assert.isNotNull(message, 'a third lookup is refused');
    }

    @IsTest
    static void refusesAnObjectNameThatIsNotAnObject() {
        for (
            String hostile : new List<String>{
                'Contact WHERE Id != null',
                'Contact;',
                'Contact--',
                'Not_A_Real_Object__c',
                ''
            }
        ) {
            Assert.areEqual(
                Label.Core_Find_ErrorUnknownObject,
                refusal(document(hostile, new List<String>())),
                hostile
            );
        }
    }

    @IsTest
    static void refusesAFieldNameThatIsNotAField() {
        for (
            String hostile : new List<String>{
                'LastName FROM User',
                'LastName) OR (Id != null',
                'LastName, (select Id from contacts)',
                'Account..Name',
                'Account.Nope__c',
                'Id\nFROM User'
            }
        ) {
            Assert.isNotNull(refusal(document('Contact', new List<String>{ hostile })), hostile);
        }
        QueryDocument sorted = document('Contact', new List<String>());
        QueryDocument.SortField sortField = new QueryDocument.SortField();
        sortField.field = 'LastName DESC, Id';
        sorted.orderBy.add(sortField);
        Assert.isNotNull(refusal(sorted), 'a sort field is resolved like any other');
    }

    @IsTest
    static void bindsAHostileValueSoItMatchesNothing() {
        insertQueries(new List<String>{ 'Real' });
        String hostile = 'x\' OR Name != \'';
        QueryDocument doc = document('Saved_Query__c', new List<String>{ 'Name' });
        doc.conditions.add(condition('1', 'Name', 'equals', hostile));

        QueryCompiler.Compiled compiled = QueryCompiler.compile(doc);
        QueryCompiler.Query query = compiled.rows(2000);
        Assert.isFalse(query.soql.contains(hostile), 'the value never enters the query text');
        Assert.areEqual(hostile, query.binds.get('b0'));
        Assert.areEqual(0, QuerySelector.records(query).size());
        Assert.isTrue(
            compiled.display(2000).contains('\\\''),
            'the displayed query escapes the quote'
        );
    }

    @IsTest
    static void refusesAnOperatorItDidNotDefine() {
        QueryDocument doc = document('Saved_Query__c', new List<String>());
        doc.conditions.add(condition('1', 'Name', '= \'x\' OR Id != null', 'x'));
        Assert.isNotNull(refusal(doc));

        QueryDocument onBoolean = document('Saved_Query__c', new List<String>());
        onBoolean.conditions.add(condition('1', 'Is_Shared__c', 'contains', 'true'));
        Assert.isNotNull(refusal(onBoolean), 'a condition must suit the field');
    }

    @IsTest
    static void refusesLogicThatIsNotConditionNumbers() {
        for (
            String hostile : new List<String>{
                '1 OR Id != null',
                '1 AND 3',
                '1 AND 2 OR 1',
                '(1 AND 2',
                '1 2',
                'NOT'
            }
        ) {
            QueryDocument doc = document('Saved_Query__c', new List<String>());
            doc.conditions.add(condition('1', 'Name', 'equals', 'a'));
            doc.conditions.add(condition('2', 'Name', 'equals', 'b'));
            doc.logic = hostile;
            Assert.areEqual(Label.Core_Find_ErrorLogic, refusal(doc), hostile);
        }
        QueryDocument valid = document('Saved_Query__c', new List<String>());
        valid.conditions.add(condition('1', 'Name', 'equals', 'a'));
        valid.conditions.add(condition('2', 'Name', 'equals', 'b'));
        valid.conditions.add(condition('3', 'Is_Shared__c', 'equals', true));
        valid.logic = '(1 or 2) and not 3';
        QueryCompiler.Query query = QueryCompiler.compile(valid).rows(10);
        Assert.isTrue(
            query.soql.contains('( (Name = :b0) OR (Name = :b1) ) AND NOT (Is_Shared__c = :b2)'),
            query.soql
        );
    }

    @IsTest
    static void escapesLikeWildcardsSoWhatWasTypedIsWhatMatches() {
        insertQueries(new List<String>{ '100% done', '100 done' });
        QueryDocument doc = document('Saved_Query__c', new List<String>{ 'Name' });
        doc.conditions.add(condition('1', 'Name', 'contains', '0%'));
        QueryCompiler.Query query = QueryCompiler.compile(doc).rows(10);
        Assert.areEqual('%0\\%%', query.binds.get('b0'));
        List<SObject> found = QuerySelector.records(query);
        Assert.areEqual(1, found.size());
        Assert.areEqual('100% done', found[0].get('Name'));
    }

    @IsTest
    static void typesEveryValueFromDescribe() {
        QueryDocument doc = document('Contact', new List<String>());
        doc.conditions.add(condition('1', 'Birthdate', 'greater than', '1990-01-31'));
        doc.conditions.add(
            condition('2', 'AccountId', 'in', new List<Object>{ '001000000000001' })
        );
        doc.conditions.add(condition('3', 'HasOptedOutOfEmail', 'equals', 'false'));
        QueryCompiler.Query query = QueryCompiler.compile(doc).rows(10);
        Assert.areEqual(Date.newInstance(1990, 1, 31), query.binds.get('b0'));
        Assert.isInstanceOfType(query.binds.get('b1'), List<Id>.class);
        Assert.areEqual(false, query.binds.get('b2'));

        for (
            QueryDocument.Condition bad : new List<QueryDocument.Condition>{
                condition('1', 'Birthdate', 'equals', '1990-02-31'),
                condition('1', 'Birthdate', 'equals', 'yesterday'),
                condition('1', 'AccountId', 'equals', 'not an id'),
                condition('1', 'HasOptedOutOfEmail', 'equals', 'perhaps')
            }
        ) {
            QueryDocument wrong = document('Contact', new List<String>());
            wrong.conditions.add(bad);
            Assert.isNotNull(refusal(wrong), String.valueOf(bad.value));
        }
    }

    @IsTest
    static void bindsARelativePeriodAsTwoDates() {
        QueryCompiler.todayForTest = Date.newInstance(2026, 9, 27);
        QueryDocument doc = document('Contact', new List<String>());
        QueryDocument.Condition thisYear = condition('1', 'Birthdate', 'equals', null);
        thisYear.relative = 'THIS_YEAR';
        doc.conditions.add(thisYear);
        QueryDocument.Condition lastDays = condition('2', 'CreatedDate', 'greater or equal', null);
        lastDays.relative = 'LAST_N_DAYS';
        lastDays.n = 30;
        doc.conditions.add(lastDays);

        QueryCompiler.Compiled compiled = QueryCompiler.compile(doc);
        QueryCompiler.Query query = compiled.rows(10);
        Assert.areEqual(Date.newInstance(2026, 1, 1), query.binds.get('b0'));
        Assert.areEqual(Date.newInstance(2026, 12, 31), query.binds.get('b1'));
        Assert.areEqual(
            Datetime.newInstance(Date.newInstance(2026, 8, 29), Time.newInstance(0, 0, 0, 0)),
            query.binds.get('b2')
        );
        Assert.isTrue(query.soql.contains('(Birthdate >= :b0 AND Birthdate <= :b1)'), query.soql);
        Assert.isTrue(compiled.display(10).contains('Birthdate >= 2026-01-01'));

        QueryDocument.Condition tooLong = condition('1', 'Birthdate', 'equals', null);
        tooLong.relative = 'LAST_N_DAYS';
        tooLong.n = 99999;
        QueryDocument wrong = document('Contact', new List<String>());
        wrong.conditions.add(tooLong);
        Assert.isNotNull(refusal(wrong));

        QueryDocument.Condition onText = condition('1', 'LastName', 'equals', null);
        onText.relative = 'THIS_YEAR';
        QueryDocument notADate = document('Contact', new List<String>());
        notADate.conditions.add(onText);
        Assert.isNotNull(refusal(notADate), 'a period suits only a date');
    }

    @IsTest
    static void refusesAFieldTheUserCannotRead() {
        User limited = TestDataFactory.createUser('Nofls', new List<String>());
        System.runAs(new User(Id = UserInfo.getUserId())) {
            PermissionSet permissionSet = new PermissionSet(
                Name = 'Find_Test_Partial',
                Label = 'Find Test Partial'
            );
            insert permissionSet;
            insert new ObjectPermissions(
                ParentId = permissionSet.Id,
                SobjectType = 'Saved_Query__c',
                PermissionsRead = true
            );
            insert new FieldPermissions(
                ParentId = permissionSet.Id,
                SobjectType = 'Saved_Query__c',
                Field = 'Saved_Query__c.Object_Name__c',
                PermissionsRead = true
            );
            insert new PermissionSetAssignment(
                AssigneeId = limited.Id,
                PermissionSetId = permissionSet.Id
            );
        }
        System.runAs(limited) {
            QueryCompiler.compile(document('Saved_Query__c', new List<String>{ 'Object_Name__c' }));
            String message = refusal(
                document('Saved_Query__c', new List<String>{ 'Query_JSON__c' })
            );
            Assert.isNotNull(message, 'a field without read access is refused before any query');
            Assert.isTrue(message.contains('Query_JSON__c'), message);

            QueryDocument filtered = document('Saved_Query__c', new List<String>());
            filtered.conditions.add(condition('1', 'Query_JSON__c', 'is not null', null));
            Assert.isNotNull(refusal(filtered), 'a filter on it is refused too');
        }
    }

    @IsTest
    static void pagesAnExportInIdOrderAfterTheCursor() {
        QueryDocument doc = document('Saved_Query__c', new List<String>{ 'Name' });
        doc.conditions.add(condition('1', 'Name', 'starts with', 'Q'));
        QueryCompiler.Query query = QueryCompiler.compile(doc)
            .exportPage(Id.valueOf('a00000000000001'), 1000);
        Assert.areEqual(
            'SELECT Id, Name FROM Saved_Query__c WHERE (Name LIKE :b0) AND Id > :afterId ' +
            'ORDER BY Id ASC LIMIT :pageSize',
            query.soql
        );
    }

    @IsTest
    static void refusesACompoundFieldAsAColumn() {
        Assert.isNotNull(refusal(document('Contact', new List<String>{ 'MailingAddress' })));
    }
}
