@IsTest
private class RollupEvaluatorTests {
  @IsTest
  static void shouldReturnEqualsCorrectlyForEqualsCriteria() {
    RollupCalcItem__c nameEquals = new RollupCalcItem__c(Name = 'RollupZ');
    RollupCalcItem__c doesNotEqualName = new RollupCalcItem__c(Name = 'RollupZZ');
    String whereClause = 'Name = \'RollupZ\'';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, nameEquals.getSObjectType());

    System.assertEquals(true, eval.matches(nameEquals), 'Name should match RollupZ');
    System.assertNotEquals(true, eval.matches(doesNotEqualName), 'Name should not match RollupZ');
  }

  @IsTest
  static void shouldFilterCalcItemsBasedOnWhereClauseCmdtFieldNotEquals() {
    RollupCalcItem__c nameEquals = new RollupCalcItem__c(Name = 'RollupZ');
    RollupCalcItem__c doesNotEqualName = new RollupCalcItem__c(Name = 'RollupZZ');
    String whereClause = 'Name != \'RollupZZ\'';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, nameEquals.getSObjectType());

    System.assertEquals(true, eval.matches(nameEquals), 'RollupZ should match since it does not equal RollupZZ');
    System.assertNotEquals(true, eval.matches(doesNotEqualName), 'RollupZZ should not match');
  }

  @IsTest
  static void shouldFilterCalcItemsBasedOnWhereClauseCmdtFieldNotEqualsAlternate() {
    RollupCalcItem__c nameEquals = new RollupCalcItem__c(Name = 'RollupZ');
    RollupCalcItem__c doesNotEqualName = new RollupCalcItem__c(Name = 'RollupZZ');
    String whereClause = 'Name <> \'RollupZZ\'';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, nameEquals.getSObjectType());

    System.assertEquals(true, eval.matches(nameEquals), 'RollupZ should match since it does not equal RollupZZ');
    System.assertNotEquals(true, eval.matches(doesNotEqualName), 'RollupZZ should not match');
  }

  @IsTest
  static void shouldFilterCalcItemsBasedOnWhereClauseCmdtFieldEqualsMultiple() {
    RollupCalcItem__c rollupZ = new RollupCalcItem__c(Name = 'RollupZ');
    RollupCalcItem__c rollupZZ = new RollupCalcItem__c(Name = 'RollupZZ');
    String whereClause = 'Name IN (\'RollupZZ\', \'RollupZ\')';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, rollupZ.getSObjectType());

    System.assertEquals(true, eval.matches(rollupZ), 'Should match based on IN');
    System.assertEquals(true, eval.matches(rollupZZ), 'Should match based on IN');
  }

  @IsTest
  static void shouldFilterCalcItemsBasedOnWhereClauseCmdtFieldNotEqualsMultiple() {
    RollupCalcItem__c rollupZ = new RollupCalcItem__c(Name = 'RollupZ');
    RollupCalcItem__c rollupZZ = new RollupCalcItem__c(Name = 'RollupZZ');
    String whereClause = 'Name NOT IN (\'RollupZZ\', \'RollupZ\')';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, rollupZ.getSObjectType());

    System.assertNotEquals(true, eval.matches(rollupZ), 'Should not match based on NOT IN');
    System.assertNotEquals(true, eval.matches(rollupZZ), 'Should not match based on NOT IN');
  }

  @IsTest
  static void shouldFilterCalcItemsForNotEqualsNumbers() {
    RollupCalcItem__c notZero = new RollupCalcItem__c(Amount__c = 10);
    RollupCalcItem__c zero = new RollupCalcItem__c(Amount__c = 0);
    String whereClause = 'Amount__c != 0';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, zero.getSObjectType());

    System.assertEquals(true, eval.matches(notZero), String.valueOf(notZero.Amount__c) + ' should not = 0');
    System.assertNotEquals(true, eval.matches(zero), '0 should  be excluded since opp amount = ' + zero.Amount__c);
  }

  @IsTest
  static void shouldNotFilterCalcItemsBasedOnWhereClauseWithInOrNotIn() {
    Account acc = new Account(Name = 'Something & Something Else');
    Account two = new Account(Name = 'Vertical/Backslash');
    Account doesNotMatch = new Account(Name = 'Something with in the string');
    Account three = new Account(Name = 'basic string');

    String whereClause = 'Name != \'Something with in the string\'';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, acc.getSObjectType());

    System.assertNotEquals(true, eval.matches(doesNotMatch), 'In should not be replaced');
    System.assertEquals(true, eval.matches(acc));
    System.assertEquals(true, eval.matches(two));
    System.assertEquals(true, eval.matches(three));

    whereClause = 'Name != \'Something with not in the string\'';
    eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, acc.getSObjectType());

    System.assertNotEquals(true, eval.matches(new Account(Name = 'Something with not in the string')));
  }

  @IsTest
  static void shouldFilterCalcItemsBasedOnWhereClauseCmdtFieldForParentFields() {
    Account acc = new Account(Name = 'RollupEvaluatorTests');
    RollupCalcItem__c oppOne = new RollupCalcItem__c(Name = acc.Name, Account__r = acc);
    RollupCalcItem__c oppTwo = new RollupCalcItem__c(Name = 'RollupZ', Account__r = new Account(Name = 'Some other name'));
    String whereClause = 'Account.Name != ' + acc.Name;

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertNotEquals(true, eval.matches(oppOne), 'Should not match based on parent field');
    System.assertEquals(true, eval.matches(oppTwo), 'Should match since the name is different than the parent field name');
  }

  @IsTest
  static void shouldFilterCalcItemsBasedOnWhereClauseForLists() {
    List<String> accIds = new List<String>{ '0016g0000000000001', '0016g0000000000002' };
    String whereClause = 'Account__c IN ' + JSON.serialize(accIds).replace('[', '(').replace(']', ')').replaceAll('"', '\'');

    RollupCalcItem__c oppOne = new RollupCalcItem__c(Account__c = accIds[0]);
    RollupCalcItem__c oppTwo = new RollupCalcItem__c(Account__c = accIds[1]);
    RollupCalcItem__c shouldNotMatch = new RollupCalcItem__c(Account__c = '0016g0000000000003');

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());
    System.assertEquals(true, eval.matches(oppOne), 'first account Id is in list');
    System.assertEquals(true, eval.matches(oppTwo), 'second account Id is in list');
    System.assertNotEquals(true, eval.matches(shouldNotMatch), 'third account Id is not in list');
  }

  @IsTest
  static void shouldFilterCalcItemsBasedOnWhereClauseCmdtFieldForOrStatements() {
    Account acc = new Account(Name = 'RollupEvaluatorTests');
    RollupCalcItem__c oppOne = new RollupCalcItem__c(Name = acc.Name, Account__r = acc);
    RollupCalcItem__c oppTwo = new RollupCalcItem__c(Name = 'RollupZ', Account__r = acc);
    RollupCalcItem__c oppThree = new RollupCalcItem__c(Name = 'RollupZZ');
    String whereClause = 'Account.Name != \'' + acc.Name + '\' OR Name = \'' + oppTwo.Name + '\'';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertNotEquals(true, eval.matches(oppOne), 'Should not match based on parent field');
    System.assertEquals(true, eval.matches(oppTwo), 'Should match since the name exactly matches the OR clause');
    System.assertEquals(true, eval.matches(oppThree), 'Should match since the account name does not match');
  }

  @IsTest
  static void shouldFilterCalcItemsBasedOnWhereClauseCmdtFieldForLikeStatements() {
    Account acc = new Account(Name = 'RollupEvaluatorTest');
    RollupCalcItem__c oppOne = new RollupCalcItem__c(Name = 'RollupZZ', Account__r = acc);
    RollupCalcItem__c oppTwo = new RollupCalcItem__c(Name = 'RollupZ', Account__r = acc);

    String whereClause = 'Account.Name LIKE \'%Rollup%\'';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertEquals(true, eval.matches(oppOne), 'Should match based on parent field');
    System.assertEquals(true, eval.matches(oppTwo), 'Should match based on parent field');
  }

  @IsTest
  static void shouldFilterCalcItemsBasedOnWhereClauseCmdtFieldForNotLikeStatements() {
    Account acc = new Account(Name = 'RollupEvaluatorTest');
    RollupCalcItem__c target = new RollupCalcItem__c(Name = 'RollupZZ', Account__r = acc);

    String whereClause = 'NOT Account.Name LIKE \'%Rollup%\'';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, target.getSObjectType());

    System.assertEquals(false, eval.matches(target));
    target.Account__r.Name = 'Rollup';
    System.assertEquals(false, eval.matches(target));
    target.Account__r.Name = 'rollUP';
    System.assertEquals(false, eval.matches(target));
    target.Account__r.Name = 'match';
    System.assertEquals(true, eval.matches(target));
  }

  @IsTest
  static void shouldProperlyDetectWildcardsForLike() {
    RollupCalcItem__c target = new RollupCalcItem__c(Name = 'Something new');

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator('Name LIKE \'thi%\'', RollupCalcItem__c.SObjectType);

    System.assertEquals(false, eval.matches(target));
    System.assertEquals(true, eval.matches(new RollupCalcItem__c(Name = 'thing')));

    eval = new RollupEvaluator.WhereFieldEvaluator('Name LIKE \'%thi%\'', RollupCalcItem__c.SObjectType);
    System.assertEquals(true, eval.matches(target));

    eval = new RollupEvaluator.WhereFieldEvaluator('Name LIKE \'%t%i%\'', RollupCalcItem__c.SObjectType);
    System.assertEquals(true, eval.matches(target));
    target.Name = 'Created From: Parent Initiated Rollup';
    System.assertEquals(true, eval.matches(target));
    target.Name = 'ti';
    System.assertEquals(true, eval.matches(target));
    target.Name = 'it';
    System.assertEquals(false, eval.matches(target));
  }

  @IsTest
  static void shouldProperlyHandleWildcardsAtTheBeginningAndEnd() {
    String likeClauseEndingWithPercentage = 'Name LIKE \'|-2CYTD%\'';
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(likeClauseEndingWithPercentage, ContactPointConsent.SObjectType);
    System.assertEquals(true, eval.matches(new ContactPointConsent(Name = '|-2CYTD-1|-2FYTD')));
    System.assertEquals(true, eval.matches(new ContactPointConsent(Name = '|-2CYTD-2')));
    System.assertEquals(false, eval.matches(new ContactPointConsent(Name = '|-1CYTD-3')));
  }

  @IsTest
  static void shouldFilterCalcItemsThatContainAndOrStringsThatAreNotFilterConditions() {
    RollupCalcItem__c oppOne = new RollupCalcItem__c(Name = 'A or B');
    RollupCalcItem__c oppTwo = new RollupCalcItem__c(Name = 'A and B');

    String whereClause = 'Name = \'A or B\''; // gasp

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertEquals(true, eval.matches(oppOne), 'Where clause should not have been split in the wrong place!');
    System.assertNotEquals(true, eval.matches(oppTwo), 'Where clause should not have been split in the wrong place!');
  }

  @IsTest
  static void shouldWorkForStringsWithSymbolsInThem() {
    RollupCalcItem__c oppOne = new RollupCalcItem__c(Name = '!()eeeek$$$-@');

    String whereClause = 'Name = \'!()eeeek$$$-@\'';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertEquals(true, eval.matches(oppOne), 'Where clause should not have been split in the wrong place!');
  }

  @IsTest
  static void shouldWorkForParanthesisAtEndOfString() {
    RollupCalcItem__c nameWithParanthesis = new RollupCalcItem__c(Name = 'Realized Gain/(Loss)');

    String whereClause = 'Name = \'Realized Gain/(Loss)\'';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, nameWithParanthesis.getSObjectType());

    System.assertEquals(true, eval.matches(nameWithParanthesis), 'Where clause should not have been split in the wrong place!');
  }

  @IsTest
  static void shouldWorkForGreaterThanNumbers() {
    RollupCalcItem__c oppOne = new RollupCalcItem__c();
    RollupCalcItem__c oppTwo = new RollupCalcItem__c(Amount__c = 5);
    RollupCalcItem__c oppThree = new RollupCalcItem__c(Amount__c = 3.01);

    String whereClause = 'Amount__c > 4';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertNotEquals(true, eval.matches(oppOne), 'Should not match due to not having amount!');
    System.assertEquals(true, eval.matches(oppTwo), 'Should match since amount is greater than');
    System.assertNotEquals(true, eval.matches(oppThree), 'Should not match since amount is not greater than');

    eval = new RollupEvaluator.WhereFieldEvaluator('Amount__c >= 4.00', oppOne.getSObjectType());

    System.assertEquals(true, eval.matches(new RollupCalcItem__c(Amount__c = 4.00)), 'Should match since amount equals!');
    System.assertEquals(true, eval.matches(new RollupCalcItem__c(Amount__c = 5.00)), 'Should match since amount greater than!');
  }

  @IsTest
  static void shouldWorkForGreaterThanDates() {
    RollupCalcItem__c oppOne = new RollupCalcItem__c(CloseDate__c = System.today());
    RollupCalcItem__c oppTwo = new RollupCalcItem__c(CloseDate__c = System.today().addDays(-2));

    String whereClause = 'CloseDate__c > ' + getSoqlCompliantDatetime(Datetime.newInstance(oppTwo.CloseDate__c, Time.newInstance(0, 0, 0, 0)));

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertEquals(true, eval.matches(oppOne));
    System.assertEquals(false, eval.matches(oppTwo), 'Second close date should not match since it is not greater: ' + oppTwo.CloseDate__c);
  }

  @IsTest
  static void shouldWorkForGreaterThanDatetimes() {
    Event evOne = new Event(ActivityDateTime = System.now().addSeconds(-1));
    Event evTwo = new Event(ActivityDateTime = System.now().addDays(2));

    String whereClause = 'ActivityDateTime > ' + getSoqlCompliantDatetime(System.now());

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, evOne.getSObjectType());

    System.assertEquals(false, eval.matches(evOne));
    System.assertEquals(true, eval.matches(evTwo));
  }

  @IsTest
  static void shouldWorkForGreaterThanTimes() {
    ContactPointAddress cpa = new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(0, 0, 0, 0));

    String whereClause = 'BestTimeToContactEndTime > ' + cpa.BestTimeToContactEndTime;

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, cpa.getSObjectType());

    System.assertEquals(false, eval.matches(cpa));
    System.assertEquals(true, eval.matches(new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(0, 0, 0, 1))));
  }

  @IsTest
  static void shouldWorkForGreaterThanOrEqualDates() {
    RollupCalcItem__c oppOne = new RollupCalcItem__c(CloseDate__c = System.today());
    RollupCalcItem__c oppTwo = new RollupCalcItem__c(CloseDate__c = System.today().addDays(-2));

    String whereClause = 'CloseDate__c >= ' + getSoqlCompliantDatetime(Datetime.newInstance(oppTwo.CloseDate__c, Time.newInstance(0, 0, 0, 0)));

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertEquals(true, eval.matches(oppOne));
    System.assertEquals(true, eval.matches(oppTwo));
  }

  @IsTest
  static void shouldWorkForGreaterThanOrEqualsTimes() {
    ContactPointAddress cpa = new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(0, 0, 0, 0));

    String whereClause = 'BestTimeToContactEndTime >= ' + cpa.BestTimeToContactEndTime;

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, cpa.getSObjectType());

    System.assertEquals(true, eval.matches(cpa));
    System.assertEquals(true, eval.matches(new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(0, 0, 0, 1))));
  }

  @IsTest
  static void shouldWorkForGreaterThanOrEqualsDatetimes() {
    Event evOne = new Event(ActivityDateTime = System.now());
    Event evTwo = new Event(ActivityDateTime = System.now().addDays(-2));

    String whereClause = 'ActivityDateTime >= ' + getSoqlCompliantDatetime(evOne.ActivityDateTime);

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, evOne.getSObjectType());

    System.assertEquals(true, eval.matches(evOne));
    System.assertEquals(false, eval.matches(evTwo));
  }

  @IsTest
  static void shouldWorkForGreaterThanStrings() {
    RollupCalcItem__c oppOne = new RollupCalcItem__c(Name = 'A');
    RollupCalcItem__c oppTwo = new RollupCalcItem__c(Name = 'B');

    String whereClause = 'Name > ' + oppOne.Name;

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertEquals(false, eval.matches(oppOne));
    System.assertEquals(true, eval.matches(oppTwo));
  }

  @IsTest
  static void shouldWorkForGreaterThanOrEqualStrings() {
    RollupCalcItem__c oppOne = new RollupCalcItem__c(Name = 'A');
    RollupCalcItem__c oppTwo = new RollupCalcItem__c(Name = 'B');

    String whereClause = 'Name >= ' + oppOne.Name;

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertEquals(true, eval.matches(oppOne));
    System.assertEquals(true, eval.matches(oppTwo));
  }

  @IsTest
  static void shouldWorkForLessThanDates() {
    RollupCalcItem__c oppOne = new RollupCalcItem__c(CloseDate__c = System.today());
    RollupCalcItem__c oppTwo = new RollupCalcItem__c(CloseDate__c = System.today().addDays(-2));

    String whereClause = 'CloseDate__c < ' + getSoqlCompliantDatetime(Datetime.newInstance(oppTwo.CloseDate__c, Time.newInstance(0, 0, 0, 0)));

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertEquals(false, eval.matches(oppOne));
    System.assertEquals(false, eval.matches(oppTwo));
  }

  @IsTest
  static void shouldWorkForLessThanTimes() {
    ContactPointAddress cpa = new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(0, 0, 0, 0));

    String whereClause = 'BestTimeToContactEndTime < ' + cpa.BestTimeToContactEndTime;

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, cpa.getSObjectType());

    System.assertEquals(false, eval.matches(cpa));
    System.assertEquals(false, eval.matches(new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(0, 0, 0, 1))));
  }

  @IsTest
  static void shouldWorkForLessThanDatetimes() {
    Event evOne = new Event(ActivityDateTime = System.now());
    Event evTwo = new Event(ActivityDateTime = System.now().addDays(-2));

    String whereClause = 'ActivityDateTime < ' + getSoqlCompliantDatetime(evOne.ActivityDateTime);

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, evOne.getSObjectType());

    System.assertEquals(false, eval.matches(evOne));
    System.assertEquals(true, eval.matches(evTwo));
  }

  @IsTest
  static void shouldWorkForLessThanOrEqualDates() {
    RollupCalcItem__c oppOne = new RollupCalcItem__c(CloseDate__c = System.today());
    RollupCalcItem__c oppTwo = new RollupCalcItem__c(CloseDate__c = System.today().addDays(-2));

    String whereClause = 'CloseDate__c <= ' + getSoqlCompliantDatetime(Datetime.newInstance(oppTwo.CloseDate__c, Time.newInstance(0, 0, 0, 0)));

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertEquals(false, eval.matches(oppOne));
    System.assertEquals(true, eval.matches(oppTwo));
  }

  @IsTest
  static void shouldWorkForLessThanOrEqualTimes() {
    ContactPointAddress cpa = new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(0, 0, 0, 0));

    String whereClause = 'BestTimeToContactEndTime <= ' + cpa.BestTimeToContactEndTime;

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, cpa.getSObjectType());

    System.assertEquals(true, eval.matches(cpa));
    System.assertEquals(false, eval.matches(new ContactPointAddress(BestTimeToContactEndTime = Time.newInstance(0, 0, 0, 1))));
  }

  @IsTest
  static void shouldWorkForLessThanOrEqualsDatetimes() {
    Event evOne = new Event(ActivityDateTime = System.now());
    Event evTwo = new Event(ActivityDateTime = System.now().addDays(-2));

    String whereClause = 'ActivityDateTime <= ' + getSoqlCompliantDatetime(evOne.ActivityDateTime);

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, evOne.getSObjectType());

    System.assertEquals(true, eval.matches(evOne));
    System.assertEquals(true, eval.matches(evTwo));
  }

  @IsTest
  static void shouldWorkForLessThanStrings() {
    RollupCalcItem__c oppOne = new RollupCalcItem__c(Name = 'A');
    RollupCalcItem__c oppTwo = new RollupCalcItem__c(Name = 'B');

    String whereClause = 'Name < ' + oppTwo.Name;

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertEquals(true, eval.matches(oppOne));
    System.assertEquals(false, eval.matches(oppTwo));
  }

  @IsTest
  static void shouldWorkForLessThanOrEqualStrings() {
    RollupCalcItem__c oppOne = new RollupCalcItem__c(Name = 'A');
    RollupCalcItem__c oppTwo = new RollupCalcItem__c(Name = 'A');

    String whereClause = 'Name <= ' + oppTwo.Name;

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertEquals(true, eval.matches(oppOne));
    System.assertEquals(true, eval.matches(oppTwo));
  }

  @IsTest
  static void shouldWorkForLessThanConditions() {
    RollupCalcItem__c oppOne = new RollupCalcItem__c();
    RollupCalcItem__c oppTwo = new RollupCalcItem__c(Amount__c = 5);
    RollupCalcItem__c oppThree = new RollupCalcItem__c(Amount__c = 3.01);

    String whereClause = 'Amount__c < 4';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, oppOne.getSObjectType());

    System.assertNotEquals(true, eval.matches(oppOne), 'Should not match due to not having amount');
    System.assertNotEquals(true, eval.matches(oppTwo), 'Should not match since amount is greater than criteria');
    System.assertEquals(true, eval.matches(oppThree), 'Should match since amount is less than');

    eval = new RollupEvaluator.WhereFieldEvaluator('Amount__c <= 4.00', oppOne.getSObjectType());

    System.assertEquals(true, eval.matches(new RollupCalcItem__c(Amount__c = 4.00)), 'Should match since amount equals!');
    System.assertEquals(true, eval.matches(new RollupCalcItem__c(Amount__c = 3.00)), 'Should match since amount less than!');
  }

  @IsTest
  static void shouldWorkForCurrencyZeros() {
    Account acc = new Account(AnnualRevenue = 0.00);
    String whereClause = 'AnnualRevenue != 0';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, acc.getSObjectType());

    System.assertNotEquals(true, eval.matches(acc));
  }

  @IsTest
  static void shouldWorkForBooleanConditions() {
    User active = new User(IsActive = true);
    User nonActive = new User(IsActive = false);

    String lowerWhere = 'IsActive = true';
    String upperWhere = 'IsActive = TRUE';
    String mixedCase = 'IsActive = True';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(lowerWhere, active.getSObjectType());

    System.assertEquals(true, eval.matches(active));
    System.assertNotEquals(true, eval.matches(nonActive));

    eval = new RollupEvaluator.WhereFieldEvaluator(upperWhere, active.getSObjectType());

    System.assertEquals(true, eval.matches(active), 'Upper TRUE should match');
    System.assertNotEquals(true, eval.matches(nonActive), 'Upper TRUE should not match');

    eval = new RollupEvaluator.WhereFieldEvaluator(mixedCase, active.getSObjectType());

    System.assertEquals(true, eval.matches(active), 'Mixed case True should match');
    System.assertNotEquals(true, eval.matches(nonActive), 'Mixed case True should not match');
  }

  @IsTest
  static void shouldReturnForMultipleOrConditionalsWithQueryKeywordsInString() {
    RollupCalcItem__c oppOne = new RollupCalcItem__c(Category__c = 'Omitted');
    RollupCalcItem__c oppTwo = new RollupCalcItem__c(Category__c = 'Pipeline'); // pipeline has "in" within it; this is a query keyword that should not get replaced
    RollupCalcItem__c oppThree = new RollupCalcItem__c(Category__c = 'Best Guess');
    RollupCalcItem__c oppFour = new RollupCalcItem__c(Category__c = 'Commit');
    RollupCalcItem__c oppFive = new RollupCalcItem__c(Amount__c = 5, Category__c = 'Closed');

    String whereClause = 'Category__c = \'Omitted\' OR Category__c = \'Best Guess\' OR Category__c = \'Pipeline\' OR Amount__c = 5';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, RollupCalcItem__c.SObjectType);

    System.assertEquals(true, eval.matches(oppOne), 'Category__c for opp one should match');
    System.assertEquals(true, eval.matches(oppTwo), 'Category__c for opp two should match');
    System.assertEquals(true, eval.matches(oppThree), 'Category__c for opp three should match');
    System.assertEquals(false, eval.matches(oppFour), 'Category__c for opp four should not match');
    System.assertEquals(true, eval.matches(oppFive), 'Amount for opp five should match');
  }

  @IsTest
  static void shouldReturnCorrectlyWhenQueryKeywordsWithSpacesArePartOfString() {
    // even worse than the above - imagine a Name field "This in That" returning false
    // because we've mistakenly transformed it into "This = that" 🤦‍♂️
    RollupCalcItem__c nameShouldMatch = new RollupCalcItem__c(Name = 'This in That');
    String whereClause = 'Name = \'This in That\'';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, RollupCalcItem__c.SObjectType);
    System.assertEquals(true, eval.matches(nameShouldMatch), 'Name should match');
  }

  @IsTest
  static void shouldCorrectlyIdentifyIncludesForMultiSelectPicklists() {
    // QuickText.Channel is the only multi-select picklist in a vanilla Salesforce org
    QuickText qt = new QuickText(Channel = 'AAA;BBB;CCC');
    QuickText nonMatch = new QuickText(Channel = 'AAA');
    String whereClause = 'Channel INCLUDES (\'AAA;CCC\')';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, QuickText.SObjectType);
    System.assertEquals(true, eval.matches(qt), 'Channel should match');
    System.assertNotEquals(true, eval.matches(nonMatch), 'Does not have full picklist val, should not match');
  }

  @IsTest
  static void shouldReturnFalseForEmptyIncludesList() {
    QuickText qt = new QuickText();

    String whereClause = 'Channel INCLUDES (\'1\')';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, QuickText.SObjectType);
    System.assertEquals(false, eval.matches(qt));
  }

  @IsTest
  static void shouldCorrectlyIdentifyIncludesForMultiSelectPicklistsWithSpaces() {
    // QuickText.Channel is the only multi-select picklist in a vanilla Salesforce org
    QuickText one = new QuickText(Channel = 'AAA;BBB;CCC');
    QuickText two = new QuickText(Channel = 'AAA');
    String whereClause = 'Channel INCLUDES (\'In-Person Meeting\')';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, QuickText.SObjectType);

    System.assertEquals(false, eval.matches(one));
    System.assertEquals(false, eval.matches(two));
  }

  @IsTest
  static void shouldReturnDualEvaluatorWhenCalcItemChangedFieldsAndWhereClauseFilledOut() {
    RollupCalcItem__c opp = new RollupCalcItem__c(Id = '0066g000000000000X', Amount__c = 50, StageName__c = 'Updated Name');
    RollupCalcItem__c oldOpp = opp.clone(true, true);
    oldOpp.StageName__c = 'Old Name';

    RollupCalcItem__c secondOpp = new RollupCalcItem__c(Id = '0066g000000000000Z', StageName__c = 'Same', Amount__c = 25);

    Rollup__mdt rollupMetadata = new Rollup__mdt(
      ChangedFieldsOnCalcItem__c = 'StageName__c',
      CalcItemWhereClause__c = 'Amount__c > 20',
      RollupOperation__c = RollupOperation.SUM.name()
    );

    Rollup.Evaluator eval = RollupEvaluator.getEvaluator(
      null,
      rollupMetadata,
      new Map<Id, SObject>{ oldOpp.Id => oldOpp, secondOpp.Id => new RollupCalcItem__c(Id = secondOpp.Id, StageName__c = secondOpp.StageName__c, Amount__c = 15) },
      RollupCalcItem__c.SObjectType
    );
    System.assertEquals(true, eval.matches(opp), 'Should match since StageName has changed and amount > 20');
    System.assertNotEquals(true, eval.matches(secondOpp), 'Should not match, stage name unchanged even though amount > 20');
  }

  @IsTest
  static void shouldReturnDualEvaluatorWhenCalcItemReparented() {
    RollupCalcItem__c opp = new RollupCalcItem__c(Id = '0066g000000000000X', Account__c = '0016g000000000000X', Amount__c = 50);
    RollupCalcItem__c oldOpp = opp.clone(true, true);
    oldOpp.Account__c = '0013g000000000000Z';

    Rollup__mdt rollupMetadata = new Rollup__mdt(
      LookupFieldOnCalcItem__c = 'Account__c',
      CalcItemWhereClause__c = 'Amount__c > 20',
      RollupOperation__c = RollupOperation.SUM.name()
    );

    Rollup.Evaluator eval = RollupEvaluator.getEvaluator(null, rollupMetadata, new Map<Id, SObject>{ oldOpp.Id => oldOpp }, RollupCalcItem__c.SObjectType);
    System.assertEquals(true, eval.matches(opp), 'Should match since StageName has changed and amount > 20');
  }

  @IsTest
  static void shouldReturnDualEvaluatorWhenEvalIsPassedInAndReparenting() {
    RollupCalcItem__c opp = new RollupCalcItem__c(Id = '0066g000000000000X', Account__c = '0016g000000000000X', Amount__c = 50);
    RollupCalcItem__c oldOpp = opp.clone(true, true);
    oldOpp.Account__c = '0013g000000000000Z';

    Rollup__mdt rollupMetadata = new Rollup__mdt(LookupFieldOnCalcItem__c = 'Account__c', RollupOperation__c = RollupOperation.SUM.name());

    Rollup.Evaluator eval = RollupEvaluator.getEvaluator(
      new RollupEvaluator.AlwaysTrueEvaluator(),
      rollupMetadata,
      new Map<Id, SObject>{ oldOpp.Id => oldOpp },
      RollupCalcItem__c.SObjectType
    );
    System.assertEquals(true, eval.matches(opp), 'Should match since always true eval passed in and reparented');
  }

  @IsTest
  static void shouldReturnChangedFieldEval() {
    RollupCalcItem__c opp = new RollupCalcItem__c(Id = '0066g000000000000X', Amount__c = 50);
    RollupCalcItem__c oldOpp = opp.clone(true, true);
    oldOpp.Amount__c = 25;

    RollupCalcItem__c secondOpp = new RollupCalcItem__c(Id = '0066g000000000000Z', Amount__c = 15);

    Rollup__mdt rollupMetadata = new Rollup__mdt(ChangedFieldsOnCalcItem__c = 'Amount__c', RollupOperation__c = RollupOperation.SUM.name());

    Rollup.Evaluator eval = RollupEvaluator.getEvaluator(
      new RollupEvaluator.AlwaysTrueEvaluator(),
      rollupMetadata,
      // second opp can't be passed by reference since we do a referential equality check in the changed field eval
      new Map<Id, SObject>{ oldOpp.Id => oldOpp, secondOpp.Id => new RollupCalcItem__c(Id = secondOpp.Id, Amount__c = secondOpp.Amount__c, Name = 'Something else') },
      RollupCalcItem__c.SObjectType
    );

    System.assertEquals(true, eval.matches(opp), 'Should match since amount changed');
    System.assertNotEquals(true, eval.matches(secondOpp), 'Should not match amount did not change');
  }

  @IsTest
  static void shouldReturnDualEvaluatorWhenEvalIsPassedAndCalcItemWhereClause() {
    RollupCalcItem__c opp = new RollupCalcItem__c(Id = '0066g000000000000X', Amount__c = 50);
    RollupCalcItem__c oldOpp = opp.clone(true, true);
    oldOpp.StageName__c = 'Old Name';

    RollupCalcItem__c secondOpp = new RollupCalcItem__c(Id = '0066g000000000000Z', Amount__c = 15);

    Rollup__mdt rollupMetadata = new Rollup__mdt(CalcItemWhereClause__c = 'Amount__c > 20', RollupOperation__c = RollupOperation.SUM.name());

    Rollup.Evaluator eval = RollupEvaluator.getEvaluator(
      new RollupEvaluator.AlwaysTrueEvaluator(),
      rollupMetadata,
      new Map<Id, SObject>{ oldOpp.Id => oldOpp, secondOpp.Id => secondOpp },
      RollupCalcItem__c.SObjectType
    );

    System.assertEquals(true, eval.matches(opp), 'Should match since amount is > 20');
    System.assertNotEquals(true, eval.matches(secondOpp), 'Should not match since amount is < 20');
  }

  @IsTest
  static void shouldReturnDoubleDualEvalWhenEvalIsPassedAndCalcItemWhereClauseAndChangedFields() {
    RollupCalcItem__c opp = new RollupCalcItem__c(Id = '0066g000000000000X', Amount__c = 50, StageName__c = 'Updated Name');
    RollupCalcItem__c oldOpp = opp.clone(true, true);
    oldOpp.StageName__c = 'Old Name';

    RollupCalcItem__c secondOpp = new RollupCalcItem__c(Id = '0066g000000000000Z', StageName__c = 'Same', Amount__c = 25);

    Rollup__mdt rollupMetadata = new Rollup__mdt(
      ChangedFieldsOnCalcItem__c = 'StageName__c',
      CalcItemWhereClause__c = 'Amount__c > 20',
      RollupOperation__c = RollupOperation.SUM.name()
    );

    Rollup.Evaluator eval = RollupEvaluator.getEvaluator(
      new RollupEvaluator.AlwaysTrueEvaluator(),
      rollupMetadata,
      new Map<Id, SObject>{
        oldOpp.Id => oldOpp,
        secondOpp.Id => new RollupCalcItem__c(Id = secondOpp.Id, StageName__c = secondOpp.StageName__c, Amount__c = secondOpp.Amount__c, Name = 'Something else')
      },
      RollupCalcItem__c.SObjectType
    );

    System.assertEquals(true, eval.matches(opp), 'Should match since StageName has changed and amount > 20');
    System.assertNotEquals(true, eval.matches(secondOpp), 'Should not match since StageName has not changed');
  }

  @IsTest
  static void shouldNotReturnRelationshipFieldsIfTheyAreNotDirectlyRelated() {
    String queryString = 'User.Id IN (\'0056g000002GeR0AAA\')';
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(queryString, RollupCalcItem__c.SObjectType);

    System.assertEquals(new List<String>(), eval.getQueryFields());
  }

  @IsTest
  static void shouldReturnOwnerParentFieldsWhenNotPolymorphic() {
    String queryString = 'Owner.Name = \'someName\'';
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(queryString, Account.SObjectType);

    System.assertEquals(new List<String>{ 'Owner.Name' }, eval.getQueryFields());
  }

  @IsTest
  static void shouldReturnDateFunctionFields() {
    String queryString = 'HOUR_IN_DAY(CreatedDate) = 15';
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(queryString, Account.SObjectType);
    System.assertEquals(new List<String>{ 'CreatedDate' }, eval.getQueryFields());
  }

  @IsTest
  static void shouldThrowExceptionForImproperlyEnteredWhereClause() {
    Exception ex;
    try {
      RollupEvaluator eval = new RollupEvaluator.WhereFieldEvaluator('= 1', RollupCalcItem__c.SObjectType);
      eval.matches(null);
      Assert.fail('Exception should be thrown above');
    } catch (Exception e) {
      ex = e;
    }

    System.assertEquals(true, ex?.getMessage().contains('Where clause entered incorrectly'));
  }

  @IsTest
  static void shouldFilterRecursiveUpdates() {
    Rollup.Evaluator eval = RollupEvaluator.getEvaluator(
      null,
      new Rollup__mdt(
        RollupOperation__c = RollupOperation.UPDATE_CONCAT_DISTINCT.name(),
        RollupFieldOnCalcItem__c = 'Amount__c',
        LookupFieldOnCalcItem__c = 'Account__c'
      ),
      new Map<Id, SObject>(),
      RollupCalcItem__c.SObjectType
    );
    RollupCalcItem__c opp = new RollupCalcItem__c(Id = '0066g000000000000X', Amount__c = 50, Account__c = '0016g000000000000X');

    System.assertEquals(true, eval.matches(opp), 'Should return true when not recursive!');
    System.assertEquals(true, eval.matches(opp), 'Should return true when not recursive twice!');
    System.assertEquals(true, eval.matches(opp), 'Should return true when not recursive thrice!');

    RollupEvaluator.stubRequestId = 'somethingElse';

    eval = RollupEvaluator.getEvaluator(
      null,
      new Rollup__mdt(
        RollupOperation__c = RollupOperation.UPDATE_CONCAT_DISTINCT.name(),
        RollupFieldOnCalcItem__c = 'Amount__c',
        LookupFieldOnCalcItem__c = 'Account__c'
      ),
      new Map<Id, SObject>(),
      RollupCalcItem__c.SObjectType
    );

    System.assertEquals(false, eval.matches(opp), 'Should not return true when recursive');
  }

  @IsTest
  static void shouldNotFilterRecursiveUpdatesWhenGrandparentRelationshipFieldFilledOut() {
    Rollup.Evaluator eval = RollupEvaluator.getEvaluator(
      null,
      new Rollup__mdt(
        RollupOperation__c = RollupOperation.UPDATE_CONCAT_DISTINCT.name(),
        RollupFieldOnCalcItem__c = 'Amount__c',
        LookupFieldOnCalcItem__c = 'Account__c',
        GrandparentRelationshipFieldPath__c = 'Some.Field.Path'
      ),
      new Map<Id, SObject>(),
      RollupCalcItem__c.SObjectType
    );
    RollupCalcItem__c opp = new RollupCalcItem__c(Id = '0066g000000000000X', Amount__c = 50, Account__c = '0016g000000000000X');

    System.assertEquals(true, eval.matches(opp), 'Should return true when not recursive!');

    eval = RollupEvaluator.getEvaluator(
      null,
      new Rollup__mdt(
        RollupOperation__c = RollupOperation.UPDATE_CONCAT_DISTINCT.name(),
        RollupFieldOnCalcItem__c = 'Amount__c',
        LookupFieldOnCalcItem__c = 'Account__c'
      ),
      new Map<Id, SObject>(),
      RollupCalcItem__c.SObjectType
    );

    System.assertEquals(true, eval.matches(opp), 'Should return true when recursive and grandparent field path filled out');
  }

  @IsTest
  static void shouldNotFilterRecursiveUpdatesWhenRollupToUltimateParentIsTrue() {
    Rollup.Evaluator eval = RollupEvaluator.getEvaluator(
      null,
      new Rollup__mdt(
        RollupOperation__c = RollupOperation.UPDATE_CONCAT_DISTINCT.name(),
        RollupFieldOnCalcItem__c = 'Amount__c',
        LookupFieldOnCalcItem__c = 'Account__c',
        RollupToUltimateParent__c = true
      ),
      new Map<Id, SObject>(),
      RollupCalcItem__c.SObjectType
    );
    RollupCalcItem__c opp = new RollupCalcItem__c(Id = '0066g000000000000X', Amount__c = 50, Account__c = '0016g000000000000X');

    System.assertEquals(true, eval.matches(opp), 'Should return true when not recursive!');

    eval = RollupEvaluator.getEvaluator(
      null,
      new Rollup__mdt(
        RollupOperation__c = RollupOperation.UPDATE_CONCAT_DISTINCT.name(),
        RollupFieldOnCalcItem__c = 'Amount__c',
        LookupFieldOnCalcItem__c = 'Account__c'
      ),
      new Map<Id, SObject>(),
      RollupCalcItem__c.SObjectType
    );

    System.assertEquals(true, eval.matches(opp), 'Should return true when recursive and ultimate parent field true');
  }

  @IsTest
  static void shouldWorkWithTripleEvaluator() {
    RollupCalcItem__c opp = new RollupCalcItem__c(Id = '0066g000000000000X', Amount__c = 50, StageName__c = 'Updated Name', Account__c = '0016g000000000000X');
    RollupCalcItem__c oldOpp = opp.clone(true, true);
    oldOpp.StageName__c = 'Old Name';

    Rollup__mdt rollupMetadata = new Rollup__mdt(
      RollupOperation__c = RollupOperation.UPDATE_CONCAT_DISTINCT.name(),
      ChangedFieldsOnCalcItem__c = 'StageName__c',
      CalcItemWhereClause__c = 'Amount__c > 20',
      RollupFieldOnCalcItem__c = 'Amount__c',
      LookupFieldOnCalcItem__c = 'Account__c'
    );

    Rollup.Evaluator eval = RollupEvaluator.getEvaluator(
      new RollupEvaluator.AlwaysTrueEvaluator(),
      rollupMetadata,
      new Map<Id, SObject>{ oldOpp.Id => oldOpp },
      RollupCalcItem__c.SObjectType
    );

    System.assertEquals(true, eval.matches(opp), 'Should return true when not recursive!');

    RollupEvaluator.stubRequestId = 'somethingElse';
    eval = RollupEvaluator.getEvaluator(null, rollupMetadata, new Map<Id, SObject>{ oldOpp.Id => oldOpp }, RollupCalcItem__c.SObjectType);

    System.assertEquals(false, eval.matches(opp), 'Should not return true when recursive and all other conditions true');
  }

  @IsTest
  static void shouldWorkWithChangedFieldsAndRecursionDetection() {
    RollupCalcItem__c opp = new RollupCalcItem__c(Id = '0066g000000000000X', Amount__c = 50, StageName__c = 'Updated Name', Account__c = '0016g000000000000X');
    RollupCalcItem__c oldOpp = opp.clone(true, true);
    oldOpp.StageName__c = 'Old Name';

    Rollup__mdt rollupMetadata = new Rollup__mdt(
      RollupOperation__c = RollupOperation.UPDATE_CONCAT_DISTINCT.name(),
      ChangedFieldsOnCalcItem__c = 'StageName__c',
      RollupFieldOnCalcItem__c = 'Amount__c',
      LookupFieldOnCalcItem__c = 'Account__c'
    );

    Rollup.Evaluator eval = RollupEvaluator.getEvaluator(
      new RollupEvaluator.AlwaysTrueEvaluator(),
      rollupMetadata,
      new Map<Id, SObject>{ oldOpp.Id => oldOpp },
      RollupCalcItem__c.SObjectType
    );

    System.assertEquals(true, eval.matches(opp), 'Should return true when not recursive!');

    RollupEvaluator.stubRequestId = 'somethingElse';
    eval = RollupEvaluator.getEvaluator(
      new RollupEvaluator.AlwaysTrueEvaluator(),
      rollupMetadata,
      new Map<Id, SObject>{ oldOpp.Id => oldOpp },
      RollupCalcItem__c.SObjectType
    );

    System.assertEquals(false, eval.matches(opp), 'Should not return true when recursive and all other conditions true');
  }

  @IsTest
  static void shouldWorkWithCalcItemWhereClauseAndRecursionDetection() {
    RollupCalcItem__c opp = new RollupCalcItem__c(Id = '0066g000000000000X', Amount__c = 50, Account__c = '0016g000000000000X');
    RollupCalcItem__c nonMatchingOpp = new RollupCalcItem__c(Id = '0066g000000000000Y', Amount__c = 15, Account__c = '0016g000000000000X');

    Rollup__mdt rollupMetadata = new Rollup__mdt(
      RollupOperation__c = RollupOperation.UPDATE_CONCAT_DISTINCT.name(),
      CalcItemWhereClause__c = 'Amount__c > 20',
      RollupFieldOnCalcItem__c = 'Amount__c',
      LookupFieldOnCalcItem__c = 'Account__c'
    );

    Rollup.Evaluator eval = RollupEvaluator.getEvaluator(
      new RollupEvaluator.AlwaysTrueEvaluator(),
      rollupMetadata,
      new Map<Id, SObject>(),
      RollupCalcItem__c.SObjectType
    );

    System.assertEquals(true, eval.matches(opp), 'Should return true when not recursive!');

    RollupEvaluator.stubRequestId = 'somethingElse';
    eval = RollupEvaluator.getEvaluator(new RollupEvaluator.AlwaysTrueEvaluator(), rollupMetadata, new Map<Id, SObject>(), RollupCalcItem__c.SObjectType);

    System.assertEquals(false, eval.matches(opp), 'Should not return true when recursive and all other conditions true');
    System.assertEquals(false, eval.matches(nonMatchingOpp), 'Should not match to begin with based on child object where clause');
  }

  @IsTest
  static void shouldWorkForNotEqualNull() {
    RollupCalcItem__c opp = new RollupCalcItem__c(Account__c = '0016g000000000000X');
    String whereClause = 'Account__c != null';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, RollupCalcItem__c.SObjectType);

    System.assertEquals(true, eval.matches(opp), 'Opp should match since it has account Id');
    System.assertNotEquals(true, eval.matches(new RollupCalcItem__c()), 'Opp should not match since AccountId is null');
  }

  @IsTest
  static void shouldCorrectlyDetectNestedNot() {
    String whereClause = 'TaskSubType != \'Email\' OR (NOT Subject LIKE \'Email\')';

    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, Task.SObjectType);

    System.assertEquals(true, eval.matches(new Task(TaskSubType = 'Call')));
    System.assertEquals(true, eval.matches(new Task(TaskSubType = 'Email', Subject = 'Hello')));
    System.assertEquals(false, eval.matches(new Task(TaskSubType = 'Email', Subject = 'Email')));
    System.assertEquals(true, eval.matches(new Task()));
  }

  @IsTest
  static void shouldDetectNestedNotOrConditions() {
    String whereClause = 'Amount__c = 1 OR (NOT (Amount__c = 0 OR Amount__c = 5))';

    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, RollupCalcItem__c.SObjectType);

    System.assertEquals(false, eval.matches(new RollupCalcItem__c(Amount__c = 0)));
    System.assertEquals(true, eval.matches(new RollupCalcItem__c(Amount__c = 1)));
    System.assertEquals(true, eval.matches(new RollupCalcItem__c(Amount__c = 2)));
    System.assertEquals(true, eval.matches(new RollupCalcItem__c(Amount__c = 3)));
    System.assertEquals(true, eval.matches(new RollupCalcItem__c(Amount__c = 4)));
    System.assertEquals(false, eval.matches(new RollupCalcItem__c(Amount__c = 5)));
  }

  @IsTest
  static void shouldDetectNestedNotAndConditions() {
    String whereClause = 'Amount__c >= 1 AND (NOT(Amount__c = 0 OR Amount__c = 5))';

    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, RollupCalcItem__c.SObjectType);

    System.assertEquals(false, eval.matches(new RollupCalcItem__c(Amount__c = 0)));
    System.assertEquals(true, eval.matches(new RollupCalcItem__c(Amount__c = 1)));
    System.assertEquals(true, eval.matches(new RollupCalcItem__c(Amount__c = 2)));
    System.assertEquals(true, eval.matches(new RollupCalcItem__c(Amount__c = 3)));
    System.assertEquals(true, eval.matches(new RollupCalcItem__c(Amount__c = 4)));
    System.assertEquals(false, eval.matches(new RollupCalcItem__c(Amount__c = 5)));
  }

  @IsTest
  static void shouldDetectNotInProperly() {
    String whereClause = 'Amount__c NOT IN (1, 3)';

    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, RollupCalcItem__c.SObjectType);

    System.assertEquals(true, eval.matches(new RollupCalcItem__c(Amount__c = 0)));
    System.assertEquals(false, eval.matches(new RollupCalcItem__c(Amount__c = 1)));
    System.assertEquals(true, eval.matches(new RollupCalcItem__c(Amount__c = 2)));
    System.assertEquals(false, eval.matches(new RollupCalcItem__c(Amount__c = 3)));
    System.assertEquals(true, eval.matches(new RollupCalcItem__c(Amount__c = 4)));
  }

  @IsTest
  static void shouldNotMangleValuesWithNameInThem() {
    String whereClause = 'Name != \'oneName\'';

    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, ContactPointAddress.SObjectType);

    System.assertEquals(false, eval.matches(new ContactPointAddress(Name = 'oneName')));
  }

  @IsTest
  static void shouldWorkWithCarriageReturnsAndLineBreaks() {
    Rollup.defaultControl = new RollupControl__mdt(IsRollupLoggingEnabled__c = true);
    String whereClause = 'Name = \'someValue\' AND (PreferenceRank = 1 \r\n OR PreferenceRank = 2 \r\n OR PreferenceRank = 3)';

    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, ContactPointAddress.SObjectType);

    System.assertEquals(true, eval.matches(new ContactPointAddress(Name = 'someValue', PreferenceRank = 1)));
    System.assertEquals(false, eval.matches(new ContactPointAddress(Name = 'someValue', PreferenceRank = 0)), 'cpa should not match');
    System.assertEquals(false, eval.matches(new ContactPointAddress(Name = 'someValue', PreferenceRank = 4)), 'preference rank should not match');
    System.assertEquals(true, eval.matches(new ContactPointAddress(Name = 'someValue', PreferenceRank = 3)));
  }

  @IsTest
  static void shouldWorkWithoutDecimalZeroesForNumbers() {
    String whereClause = 'Amount__c = 50000';

    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, RollupCalcItem__c.SObjectType);

    System.assertEquals(true, eval.matches(new RollupCalcItem__c(Amount__c = 50000)));
    System.assertEquals(true, eval.matches(new RollupCalcItem__c(Amount__c = 50000.00)), 'Should work with or without decimal places');
    System.assertEquals(false, eval.matches(new RollupCalcItem__c(Amount__c = 50000.01)));

    eval = new RollupEvaluator.WhereFieldEvaluator('Amount__c = 50.1', RollupCalcItem__c.SObjectType);
    System.assertEquals(true, eval.matches(new RollupCalcItem__c(Amount__c = 50.10)), 'Should detect trailing zero correctly');
  }

  @IsTest
  static void shouldProperlySupportNonPolymorphicOwnerClauses() {
    String whereClause = 'Account__r.Owner.Id != null';
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, RollupCalcItem__c.SObjectType);
    System.assertEquals('Account__r.Owner.Id', eval.getQueryFields()[0]);
  }

  @IsTest
  static void shouldNotPassOwnerInQueryFieldsForPolymorphicField() {
    String whereClause = 'Parent.Owner.Id != null';
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, ContactPointAddress.SObjectType);
    System.assertEquals(0, eval.getQueryFields().size(), 'Should not return polymorphic field');
  }

  @IsTest
  static void shouldProperlyReturnMultipleParentLevelFields() {
    String whereClause = 'Account__r.Name != null AND Account__r.Owner.Id != null';
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, RollupCalcItem__c.SObjectType);
    List<String> queryFields = eval.getQueryFields();
    System.assertEquals(2, queryFields.size(), 'Both fields should have been returned: ' + queryFields);
    System.assertEquals('Account__r.Name', queryFields[0]);
    System.assertEquals('Account__r.Owner.Id', queryFields[1]);
  }

  @IsTest
  static void returnsLowercaseParentLevelFields() {
    String whereClause = 'parent__r.account__r.name = \'some account\'';
    List<String> queryFields = new RollupEvaluator.WhereFieldEvaluator(whereClause, RollupCalcItem__c.SObjectType).getQueryFields();
    System.assertEquals(1, queryFields.size(), queryFields);
    System.assertEquals('parent__r.account__r.name', queryFields[0]);
  }

  @IsTest
  static void supportsNonPolymorphicTypeFields() {
    String whereClause = 'Account__r.Type <> \'Something Else\'';
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, RollupCalcItem__c.SObjectType);
    List<String> queryFields = eval.getQueryFields();
    System.assertEquals(1, queryFields.size(), queryFields);
    System.assertEquals('Account__r.Type', queryFields[0]);
  }

  @IsTest
  static void supportsTypeFieldWhenOnlyPresentOnParent() {
    String whereClause = 'Account.Type != \'Something\'';
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, Contact.SObjectType);
    List<String> queryFields = eval.getQueryFields();
    System.assertEquals(1, queryFields.size(), queryFields);
    System.assertEquals('Account.Type', queryFields[0]);
  }

  @IsTest
  static void gracefullyHandlesFieldNotExistingForDateLiteral() {
    String whereClause = 'SomeFieldThatDoesNotExist = THIS_YEAR';
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, RollupCalcItem__c.SObjectType);

    System.assertEquals(false, eval.matches(new RollupCalcItem__c()));
  }

  @IsTest
  static void shouldProperlyEvaluateDateLiteral() {
    String whereClause = 'CloseDate__c = THIS_YEAR';
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, RollupCalcItem__c.SObjectType);
    System.assertEquals(true, eval.matches(new RollupCalcItem__c(CloseDate__c = System.today())));
    System.assertEquals(false, eval.matches(new RollupCalcItem__c(CloseDate__c = System.today().addYears(-1))));
  }

  @IsTest
  static void shouldProperlyEvaluateDateFunction() {
    String whereClause = 'HOUR_IN_DAY(ReminderDateTime) = 5';
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, Task.SObjectType);
    Time fifthHour = Time.newInstance(5, 0, 0, 0);
    Datetime fifthHourDt = Datetime.newInstanceGmt(System.today(), fifthHour);
    System.assertEquals(true, eval.matches(new Task(ReminderDateTime = fifthHourDt)));
  }

  @IsTest
  static void shouldProperlyEvaluateLiteralDateFunctions() {
    Date comparisonDate = Date.newInstance(2020, 3, 7);
    String whereClause = 'DAY_ONLY(ReminderDateTime) = 2020-03-07';
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, Task.SObjectType);
    System.assertEquals(true, eval.matches(new Task(ReminderDateTime = Datetime.newInstanceGmt(comparisonDate, Time.newInstance(0, 0, 0, 0)))));
  }

  @IsTest
  static void shouldStripAwayRelationshipNameWhenParentClauseAndTypeMatchesParent() {
    String whereClause = 'Account.AnnualRevenue = 5';
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, Account.SObjectType);
    System.assertEquals(true, eval.matches(new Account(AnnualRevenue = 5)));
  }

  @IsTest
  static void shouldNotBlowUpOnRelationshipNameForDifferentParent() {
    String whereClause = 'Asset.AssetLevel = 1';
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, Account.SObjectType);
    System.assertEquals(true, eval.matches(new Account()));
  }

  @IsTest
  static void worksWithNYearsAgo() {
    Id accountId = RollupTestUtils.createId(Account.SObjectType);
    String whereClause =
      'Account__c = \'' +
      accountId +
      '\' AND CloseDate__c <= LAST_YEAR AND CloseDate__c > N_YEARS_AGO:3 AND StageName__c != \'Closed Lost\' AND StageName__c != \'Closed/No Event Fees Only\'';
    RollupCalcItem__c matchingOpp = new RollupCalcItem__c(Account__c = accountId, CloseDate__c = System.today().addYears(-1));
    RollupCalcItem__c stageClosedLostNonMatch = new RollupCalcItem__c(Account__c = accountId, CloseDate__c = System.today().addYears(-2), StageName__c = 'Closed Lost');
    RollupCalcItem__c stageClosedNonMatch = new RollupCalcItem__c(Account__c = accountId, CloseDate__c = System.today().addYears(-2), StageName__c = 'Closed/No Event Fees Only');
    RollupCalcItem__c idNonMatch = new RollupCalcItem__c(CloseDate__c = System.today().addYears(-2));
    RollupCalcItem__c closeDateNonMatch = new RollupCalcItem__c(CloseDate__c = System.today(), Account__c = accountId);

    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, RollupCalcItem__c.SObjectType);

    System.assertEquals(true, eval.matches(matchingOpp));
    System.assertEquals(false, eval.matches(stageClosedLostNonMatch));
    System.assertEquals(false, eval.matches(stageClosedNonMatch));
    System.assertEquals(false, eval.matches(idNonMatch));
    System.assertEquals(false, eval.matches(closeDateNonMatch));
  }

  @IsTest
  static void stringsAreComparedCaseInsensitive() {
    String whereClause = 'StageName__c = \'closed lost\'';
    RollupCalcItem__c opp = new RollupCalcItem__c(StageName__c = 'Closed Lost');

    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, opp.getSObjectType());

    System.assertEquals(true, eval.matches(opp));
  }

  @IsTest
  static void pascalCaseForFieldNamesIsNotRequired() {
    String poorlyCasedFieldName = RollupCalcItem__c.IsClosed__c.toString().toLowerCase();

    RollupCalcItem__c isClosedFalse = (RollupCalcItem__c) JSON.deserialize('{ "IsClosed__c": false }', RollupCalcItem__c.class);
    RollupCalcItem__c target = new RollupCalcItem__c(Parent__r = isClosedFalse);
    System.assertEquals(false, target.Parent__r.IsClosed__c);
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(
      'Parent__r.' + poorlyCasedFieldName + ' = false',
      target.getSObjectType()
    );

    System.assertEquals(true, eval.matches(target));
    System.assertEquals(false, eval.matches(new RollupCalcItem__c()), 'Should properly evaluate for null relationship');
  }

  @IsTest
  static void nestedConditionalsWork() {
    String whereClause = '((IsActive = TRUE) OR (IsActive = FALSE AND FirstName = \'One\') OR (IsActive = FALSE AND FirstName LIKE \'Special%\') OR (FirstName = \'a\' AND AboutMe = \'b\') OR (FirstName = \'b\'))';
    User target = new User(IsActive = false, FirstName = 'One');

    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, target.getSObjectType());

    validateQuery(User.SObjectType, whereClause);
    System.assertEquals(true, eval.matches(target));
    System.assertEquals(true, eval.matches(new User(IsActive = true)));
    System.assertEquals(true, eval.matches(new User(IsActive = false, FirstName = 'SpecialK')));
    System.assertEquals(true, eval.matches(new User(FirstName = 'a', AboutMe = 'b')));
    System.assertEquals(true, eval.matches(new User(FirstName = 'b')));
    System.assertEquals(false, eval.matches(new User(IsActive = false, FirstName = 'c')));
  }

  @IsTest
  static void nestedConditionalsWorkWithSomeMatchingInnerClauses() {
    String whereClause = '(StageName__c = \'one\' AND Source__c IN (\'Web\', \'Phone\') ) OR (Source__c in (\'Web\', \'Phone\') AND StageName__c = \'two\')';

    RollupCalcItem__c target = new RollupCalcItem__c(StageName__c = 'one', Source__c = 'Web');
    RollupCalcItem__c secondMatch = new RollupCalcItem__c(StageName__c = 'two', Source__c = 'Phone');
    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, target.getSObjectType());

    validateQuery(RollupCalcItem__c.SObjectType, whereClause);
    System.assertEquals(true, eval.matches(target));
    System.assertEquals(true, eval.matches(secondMatch));
    System.assertEquals(false, eval.matches(new RollupCalcItem__c(StageName__c = 'three', Source__c = 'Web')));
  }

  @IsTest
  static void nestedConditionalsWorkWithMoreThanOneLevel() {
    RollupCalcItem__c oppOne = new RollupCalcItem__c(StageName__c = 'Not A Match');
    RollupCalcItem__c oppTwo = new RollupCalcItem__c(Amount__c = 5, StageName__c = 'Hi');
    RollupCalcItem__c oppThree = new RollupCalcItem__c(Amount__c = 3.01, StageName__c = 'Hello there');
    RollupCalcItem__c oppFour = new RollupCalcItem__c(StageName__c = 'Hi', Amount__c = 0);
    RollupCalcItem__c oppFive = new RollupCalcItem__c(Id = '0066g000000000000T', Amount__c = 3.99999);

    String whereClause =
      'Amount__c < 4 AND (StageName__c LIKE \'%Hello%\' OR StageName__c = \'Hi\' OR (Id IN (\'' +
      oppFive.Id +
      '\',' +
      '\'0066g000000000000Z\'' +
      ')' +
      ' AND Amount__c = ' +
      oppFive.Amount__c +
      '))';

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, RollupCalcItem__c.SObjectType);

    validateQuery(RollupCalcItem__c.SObjectType, whereClause);
    System.assertNotEquals(true, eval.matches(oppOne), 'Name does not match!');
    System.assertNotEquals(true, eval.matches(oppTwo), 'Amount does not match');
    System.assertEquals(true, eval.matches(oppThree), 'Amount matches and name roughly matches!');
    System.assertEquals(true, eval.matches(oppFour), 'Amount and name match');
    System.assertEquals(true, eval.matches(oppFive), 'Id matches inner nested conditional!');
  }

  @IsTest
  static void nestedConditionalWorksWithInSpaces() {
    String whereClause = 'PrivacyConsentStatus = \'Yes\' and EffectiveTo <= TODAY and Effectivefrom >= TODAY and CaptureSource in ( \'Hi\' , \'Hello\' , \'Hola\') and (Name = \'excellent\' or Name = \'stellar\')';

    ContactPointConsent match1 = new ContactPointConsent(
      PrivacyConsentStatus = 'Yes',
      EffectiveTo = System.now().addDays(-1),
      EffectiveFrom = System.now(),
      CaptureSource = 'Hi',
      Name = 'Excellent'
    );
    ContactPointConsent match2 = new ContactPointConsent(
      PrivacyConsentStatus = 'Yes',
      EffectiveTo = System.now().addDays(-1),
      EffectiveFrom = System.now(),
      CaptureSource = 'hello',
      Name = 'stellar'
    );
    ContactPointConsent match3 = new ContactPointConsent(
      PrivacyConsentStatus = 'Yes',
      EffectiveTo = System.now().addDays(-1),
      EffectiveFrom = System.now(),
      CaptureSource = 'Hola',
      Name = 'stellar'
    );
    ContactPointConsent nonMatch1 = new ContactPointConsent(
      PrivacyConsentStatus = 'nonmatch',
      EffectiveTo = System.now().addDays(2),
      EffectiveFrom = System.now().addDays(-1),
      CaptureSource = 'Hi',
      Name = 'stellar'
    );
    ContactPointConsent nonMatch2 = new ContactPointConsent(
      PrivacyConsentStatus = 'Yes',
      EffectiveTo = System.now(),
      EffectiveFrom = System.now().addDays(-1),
      CaptureSource = 'nonmatch',
      Name = 'stellar'
    );
    ContactPointConsent nonMatch3 = new ContactPointConsent(
      PrivacyConsentStatus = 'Yes',
      EffectiveTo = System.now(),
      EffectiveFrom = System.now().addDays(-1),
      CaptureSource = 'hi',
      Name = 'nonmatch'
    );

    Rollup.Evaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, ContactPointConsent.SObjectType);

    System.assertEquals(true, eval.matches(match1));
    System.assertEquals(true, eval.matches(match2));
    System.assertEquals(true, eval.matches(match3));
    System.assertEquals(false, eval.matches(nonMatch1));
    System.assertEquals(false, eval.matches(nonMatch2));
    System.assertEquals(false, eval.matches(nonMatch3));
  }

  @IsTest
  static void stripsExtraParantheticalStructures() {
    String whereClause = '(Name IN (\'0-Current\', \'1-30 Days\', \'31-60 Days\')) AND Name IN (\'0-Current\', \'1-30 Days\', \'31-60 Days\')';

    RollupEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, ContactPointConsent.SObjectType);

    System.assertEquals(true, eval.matches(new ContactPointConsent(Name = '0-Current')));
  }

  @IsTest
  static void whereClauseThatEndsWithColonDelimitedDateLiteralShouldWorkSpaces() {
    String whereClause = 'ActivityDate >= TODAY AND ActivityDate <= NEXT_N_DAYS: 30';

    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, Task.SObjectType);

    System.assertEquals(true, eval.matches(new Task(ActivityDate = System.today())));
    System.assertEquals(true, eval.matches(new Task(ActivityDate = System.today().addDays(30))));
    System.assertEquals(false, eval.matches(new Task(ActivityDate = System.today().addDays(31))));
  }

  @IsTest
  static void whereClauseThatEndsWithColonDelimitedDateLiteralShouldWorkNoSpaces() {
    String whereClause = 'ActivityDate >= TODAY AND ActivityDate <= NEXT_N_DAYS:30';

    RollupEvaluator.WhereFieldEvaluator eval = new RollupEvaluator.WhereFieldEvaluator(whereClause, Task.SObjectType);

    System.assertEquals(true, eval.matches(new Task(ActivityDate = System.today())));
    System.assertEquals(true, eval.matches(new Task(ActivityDate = System.today().addDays(30))));
    System.assertEquals(false, eval.matches(new Task(ActivityDate = System.today().addDays(31))));
  }

  private static String getSoqlCompliantDatetime(Datetime dt) {
    return dt.format('yyyy-MM-dd\'T\'HH:mm:ssZ');
  }

  private static void validateQuery(Schema.SObjectType target, String whereClause) {
    // sanity check - is the where clause valid?
    Database.query('SELECT Id FROM ' + target + ' WHERE ' + whereClause);
  }
}
