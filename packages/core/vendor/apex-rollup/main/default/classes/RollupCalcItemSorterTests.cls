/**
 * Open Impact patch E, see packages/core/vendor/apex-rollup/VENDOR.md.
 * Every sort call in this class goes through a List<SObject> reference rather than the typed list.
 * RollupCalcItemSorter is a System.Comparator<SObject>; the platform compiler accepts it against a
 * typed SObject list, the offline apex-ls checker does not model that covariance. The list object
 * is the same one either way, so the sort is in place and the assertions are unchanged.
 */
@IsTest
private class RollupCalcItemSorterTests {
  @IsTest
  static void shouldOrderByTwoFields() {
    RollupCalcItemSorter sorter = new RollupCalcItemSorter(
      new List<RollupOrderBy__mdt>{
        new RollupOrderBy__mdt(Ranking__c = 0, FieldName__c = 'Amount__c'),
        new RollupOrderBy__mdt(Ranking__c = 1, FieldName__c = 'CloseDate__c')
      }
    );

    Date severalDaysAgo = System.today().addDays(-2);
    RollupCalcItem__c expectedFirstItem = new RollupCalcItem__c(Amount__c = null, CloseDate__c = severalDaysAgo);
    RollupCalcItem__c expectedSecondItem = new RollupCalcItem__c(Amount__c = 1, CloseDate__c = severalDaysAgo);
    List<RollupCalcItem__c> oppsToSort = new List<RollupCalcItem__c>{
      new RollupCalcItem__c(Amount__c = 1, CloseDate__c = System.today()),
      // this record should essentially be thrown out of sorting since it "loses" on the first ordering,
      // which is on Amount
      new RollupCalcItem__c(Amount__c = 3, CloseDate__c = severalDaysAgo.addDays(-1)),
      expectedSecondItem,
      expectedFirstItem
    };
    ((List<SObject>) oppsToSort).sort(sorter);

    System.assertEquals(expectedFirstItem, oppsToSort[0]);
    System.assertEquals(expectedSecondItem, oppsToSort[1]);
  }

  @IsTest
  static void shouldOrderByMultipleFields() {
    RollupCalcItemSorter sorter = new RollupCalcItemSorter(
      new List<RollupOrderBy__mdt>{
        new RollupOrderBy__mdt(Ranking__c = 0, FieldName__c = 'Amount__c'),
        new RollupOrderBy__mdt(Ranking__c = 1, FieldName__c = 'CloseDate__c'),
        new RollupOrderBy__mdt(Ranking__c = 2, FieldName__c = 'Name')
      }
    );

    Date today = System.today().addDays(-2);
    RollupCalcItem__c expectedFirstItem = new RollupCalcItem__c(Amount__c = 1, CloseDate__c = today, Name = 'b');
    RollupCalcItem__c expectedThirdItem = new RollupCalcItem__c(Amount__c = 2, CloseDate__c = today, Name = 'a');
    RollupCalcItem__c expectedSecondItem = new RollupCalcItem__c(Amount__c = 1, CloseDate__c = today, Name = 'c');
    RollupCalcItem__c expectedFourthItem = new RollupCalcItem__c(Amount__c = 2, CloseDate__c = today.addDays(1), Name = 'a');
    List<RollupCalcItem__c> oppsToSort = new List<RollupCalcItem__c>{ expectedSecondItem, expectedFourthItem, expectedThirdItem, expectedFirstItem };
    ((List<SObject>) oppsToSort).sort(sorter);

    System.assertEquals(expectedFirstItem, oppsToSort[0]);
    System.assertEquals(expectedSecondItem, oppsToSort[1]);
    System.assertEquals(expectedThirdItem, oppsToSort[2]);
    System.assertEquals(expectedFourthItem, oppsToSort[3]);
  }

  @IsTest
  static void shouldOrderNullsLast() {
    RollupCalcItemSorter sorter = new RollupCalcItemSorter(
      new List<RollupOrderBy__mdt>{
        new RollupOrderBy__mdt(Ranking__c = 0, FieldName__c = 'Amount__c', NullSortOrder__c = RollupMetaPicklists.NullSortOrder.NullsLast),
        new RollupOrderBy__mdt(Ranking__c = 1, FieldName__c = 'CloseDate__c')
      }
    );

    Date severalDaysAgo = System.today().addDays(-2);
    RollupCalcItem__c expectedFirstItem = new RollupCalcItem__c(Amount__c = 1, CloseDate__c = System.today());
    RollupCalcItem__c expectedSecondItem = new RollupCalcItem__c(Amount__c = 3, CloseDate__c = severalDaysAgo.addDays(-1));
    List<RollupCalcItem__c> oppsToSort = new List<RollupCalcItem__c>{
      new RollupCalcItem__c(Amount__c = 3, CloseDate__c = severalDaysAgo.addDays(-1)),
      expectedSecondItem,
      expectedFirstItem
    };
    ((List<SObject>) oppsToSort).sort(sorter);

    System.assertEquals(expectedFirstItem, oppsToSort[0]);
    System.assertEquals(expectedSecondItem, oppsToSort[1]);
  }

  @IsTest
  static void shouldOrderDescWhenStipulated() {
    RollupCalcItemSorter sorter = new RollupCalcItemSorter(
      new List<RollupOrderBy__mdt>{
        new RollupOrderBy__mdt(Ranking__c = 0, FieldName__c = 'Amount__c', SortOrder__c = RollupMetaPicklists.SortOrder.Descending),
        new RollupOrderBy__mdt(Ranking__c = 1, FieldName__c = 'CloseDate__c')
      }
    );

    Date today = System.today();
    // validates null sort order plays nice with this
    RollupCalcItem__c expectedFirstItem = new RollupCalcItem__c(Amount__c = null, CloseDate__c = today);
    RollupCalcItem__c expectedSecondItem = new RollupCalcItem__c(Amount__c = 5, CloseDate__c = today);
    RollupCalcItem__c expectedThirdItem = new RollupCalcItem__c(Amount__c = 1, CloseDate__c = today);

    List<RollupCalcItem__c> oppsToSort = new List<RollupCalcItem__c>{ expectedThirdItem, expectedFirstItem, expectedSecondItem };
    ((List<SObject>) oppsToSort).sort(sorter);

    System.assertEquals(expectedFirstItem, oppsToSort[0]);
    System.assertEquals(expectedSecondItem, oppsToSort[1]);
    System.assertEquals(expectedThirdItem, oppsToSort[2]);
  }

  @IsTest
  static void shouldProperlySortPicklists() {
    RollupCalcItemSorter sorter = new RollupCalcItemSorter(new List<RollupOrderBy__mdt>{ new RollupOrderBy__mdt(Ranking__c = 0, FieldName__c = 'Industry') });

    List<Schema.PicklistEntry> picklistEntries = Account.Industry.getDescribe().getPicklistValues();
    List<Account> accs = new List<Account>();

    for (Integer reverseIndex = picklistEntries.size() - 1; reverseIndex >= 0; reverseIndex--) {
      Schema.PicklistEntry entry = picklistEntries[reverseIndex];
      accs.add(new Account(Name = entry.getValue(), Industry = entry.getValue()));
    }
    ((List<SObject>) accs).sort(sorter);

    for (Integer index = 0; index < accs.size(); index++) {
      System.assertEquals(picklistEntries[index].getValue(), accs[index].Industry, 'Account at index: ' + index + ' should have matched');
    }
  }

  @IsTest
  static void shouldSortParentFields() {
    Account acc = new Account(Name = 'Parent');
    insert as system acc;

    RollupCalcItem__c opp = new RollupCalcItem__c(Account__r = acc, Amount__c = 1);
    RollupCalcItem__c second = new RollupCalcItem__c(Account__r = acc, Amount__c = 2);

    RollupCalcItemSorter sorter = new RollupCalcItemSorter(
      new List<RollupOrderBy__mdt>{
        new RollupOrderBy__mdt(Ranking__c = 0, FieldName__c = 'Account__r.Name'),
        new RollupOrderBy__mdt(Ranking__c = 0, FieldName__c = 'Amount__c')
      }
    );

    List<RollupCalcItem__c> opps = new List<RollupCalcItem__c>{ second, opp };
    ((List<SObject>) opps).sort(sorter);

    System.assertEquals(opp, opps[0]);
    System.assertEquals(second, opps[1]);
  }

  @IsTest
  static void shouldNotFailOnBlankFieldNames() {
    RollupCalcItemSorter sorter = new RollupCalcItemSorter(
      new List<RollupOrderBy__mdt>{ new RollupOrderBy__mdt(Ranking__c = 0, FieldName__c = 'Amount__c'), new RollupOrderBy__mdt(Ranking__c = 1, FieldName__c = '') }
    );

    RollupCalcItem__c expectedFirstItem = new RollupCalcItem__c(Amount__c = null);
    RollupCalcItem__c expectedSecondItem = new RollupCalcItem__c(Amount__c = 1);
    List<RollupCalcItem__c> oppsToSort = new List<RollupCalcItem__c>{ new RollupCalcItem__c(Amount__c = 1), new RollupCalcItem__c(Amount__c = 3), expectedSecondItem, expectedFirstItem };
    ((List<SObject>) oppsToSort).sort(sorter);

    System.assert(true, 'Should make it here');
  }

  @IsTest
  static void sortsFieldNames() {
    List<RollupCalcItem__c> itemsToSort = new List<RollupCalcItem__c>{
      new RollupCalcItem__c(StageName__c = 'Two'),
      new RollupCalcItem__c(StageName__c = 'Uno Reverse Card'),
      new RollupCalcItem__c(StageName__c = 'Two'),
      new RollupCalcItem__c(),
      new RollupCalcItem__c(StageName__c = 'Z'),
      new RollupCalcItem__c(StageName__c = 'One'),
      new RollupCalcItem__c(StageName__c = 'One')
    };

    ((List<SObject>) itemsToSort).sort(new RollupCalcItemSorter(new List<String>{ RollupCalcItem__c.Name.toString(), RollupCalcItem__c.StageName__c.toString() }));

    System.assertEquals(null, itemsToSort.get(0).StageName__c);
    System.assertEquals('One', itemsToSort.get(1).StageName__c);
    System.assertEquals('One', itemsToSort.get(2).StageName__c);
    System.assertEquals('Two', itemsToSort.get(3).StageName__c);
    System.assertEquals('Two', itemsToSort.get(4).StageName__c);
    System.assertEquals('Uno Reverse Card', itemsToSort.get(5).StageName__c);
    System.assertEquals('Z', itemsToSort.get(6).StageName__c);
  }
}
