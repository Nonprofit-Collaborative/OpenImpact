/**
 * Duplicate suggestions: asking the platform what it thinks, and remembering what a person
 * decided about the answer (C-20, canonical model Section 29A).
 *
 * Nothing in this class compares two records. The comparison is the platform's: the matching
 * rules an administrator has activated decide what counts as the same person or the same
 * household, and `Datacloud.FindDuplicatesByIds` runs those rules against records that already
 * exist. That is the whole gap Open Impact fills, because a duplicate rule otherwise only ever
 * runs at the moment somebody saves a record, and the standard job that runs the rules over
 * records already in the org is available only in the two largest editions.
 *
 * The three parts are deliberately separable, so that the part with a decision in it can be
 * tested without an org: `pairsToRecord` is arithmetic on identifiers and knows nothing about
 * the platform, `matchesFor` is the one call into the platform's matching engine, and
 * `recordPairs` writes the platform's own duplicate record sets.
 */
public with sharing class DuplicateService {
    /** How many records one call to the platform's matcher will take. */
    public static final Integer MAX_RECORDS_PER_CALL = 50;

    private static final String SEPARATOR = '-';
    private static final String CONTEXT_MATCH = 'Duplicate scan: asking the platform for matches';
    private static final String CONTEXT_WRITE = 'Duplicate scan: recording a suggestion';

    /** Raised with a message the page shows as it is. */
    public class DuplicateException extends Exception {
    }

    /** Two records the platform says are the same thing. */
    public class Pair {
        public Id left;
        public Id right;
        public String key;
        public String ruleName;

        public Pair(Id left, Id right, String ruleName) {
            Boolean leftFirst = String.valueOf(left).compareTo(String.valueOf(right)) <= 0;
            this.left = leftFirst ? left : right;
            this.right = leftFirst ? right : left;
            this.key = pairKey(left, right);
            this.ruleName = ruleName;
        }
    }

    /**
     * The identifier a pair is remembered by: the two record identifiers in ascending order,
     * so that A with B and B with A are the same pair and are dismissed once.
     */
    public static String pairKey(Id left, Id right) {
        if (left == null || right == null) {
            return null;
        }
        String first = String.valueOf(left);
        String second = String.valueOf(right);
        return first.compareTo(second) <= 0
            ? first + SEPARATOR + second
            : second + SEPARATOR + first;
    }

    /** Every pair that can be made out of the records in one suggestion. */
    public static Set<String> pairKeysAmong(List<Id> recordIds) {
        Set<String> keys = new Set<String>();
        if (recordIds == null) {
            return keys;
        }
        for (Integer i = 0; i < recordIds.size(); i++) {
            for (Integer j = i + 1; j < recordIds.size(); j++) {
                String key = pairKey(recordIds[i], recordIds[j]);
                if (key != null) {
                    keys.add(key);
                }
            }
        }
        return keys;
    }

    /**
     * The pairs worth writing down, out of what the matcher answered.
     *
     * Drops a record matched to itself, folds A with B and B with A into one pair, and passes
     * over anything already known: a pair already sitting in a suggestion, and a pair somebody
     * has already said is not a duplicate (R-DP3, R-DP5). No query and no platform call, so
     * the rule this feature actually owns can be tested on its own.
     */
    public static List<Pair> pairsToRecord(List<Pair> found, Set<String> known) {
        List<Pair> result = new List<Pair>();
        Set<String> seen = known == null ? new Set<String>() : new Set<String>(known);
        if (found == null) {
            return result;
        }
        for (Pair candidate : found) {
            if (
                candidate == null ||
                candidate.left == null ||
                candidate.right == null ||
                candidate.left == candidate.right ||
                seen.contains(candidate.key)
            ) {
                continue;
            }
            seen.add(candidate.key);
            result.add(candidate);
        }
        return result;
    }

    /**
     * What the platform's active duplicate rules say about these records.
     *
     * The one place Open Impact touches the matching engine. A failure here is logged and
     * answered with nothing rather than thrown: the platform raises when an object has no
     * active duplicate rule at all, and a scan that finds nothing is a better outcome for a
     * nightly batch than a scan that dies halfway through its second chunk.
     */
    public static List<Pair> matchesFor(List<Id> recordIds) {
        List<Pair> found = new List<Pair>();
        if (recordIds == null || recordIds.isEmpty()) {
            return found;
        }
        try {
            List<Datacloud.FindDuplicatesResult> results = Datacloud.FindDuplicatesByIds.findDuplicatesByIds(
                recordIds
            );
            for (Integer index = 0; index < results.size(); index++) {
                Id source = index < recordIds.size() ? recordIds[index] : null;
                if (source == null) {
                    continue;
                }
                for (Datacloud.DuplicateResult duplicateResult : results[index]
                    .getDuplicateResults()) {
                    String ruleName = duplicateResult.getDuplicateRule();
                    for (Datacloud.MatchResult matchResult : duplicateResult.getMatchResults()) {
                        for (Datacloud.MatchRecord matched : matchResult.getMatchRecords()) {
                            SObject record = matched.getRecord();
                            if (record != null && record.Id != null) {
                                found.add(new Pair(source, record.Id, ruleName));
                            }
                        }
                    }
                }
            }
        } catch (Exception caught) {
            ErrorLogger.log(caught, CONTEXT_MATCH);
            return new List<Pair>();
        }
        return found;
    }

    /**
     * Writes each pair down as a duplicate record set of two, which is where the platform
     * already puts the duplicates its own rules find, so the standard Duplicate Record Sets
     * tab and any report built on it show the scan's findings alongside them.
     *
     * Answers how many were written. A failure is logged and the run carries on: one pair that
     * cannot be recorded is not a reason to lose the rest of a scan.
     */
    public static Integer recordPairs(List<Pair> pairs, Map<String, DuplicateRule> rulesByName) {
        if (pairs == null || pairs.isEmpty()) {
            return 0;
        }
        List<DuplicateRecordSet> sets = new List<DuplicateRecordSet>();
        for (Pair pair : pairs) {
            DuplicateRule rule = rulesByName == null ? null : rulesByName.get(pair.ruleName);
            sets.add(new DuplicateRecordSet(DuplicateRuleId = rule == null ? null : rule.Id));
        }
        try {
            Database.insert(sets, AccessLevel.USER_MODE);
            List<DuplicateRecordItem> items = new List<DuplicateRecordItem>();
            for (Integer index = 0; index < pairs.size(); index++) {
                items.add(
                    new DuplicateRecordItem(
                        DuplicateRecordSetId = sets[index].Id,
                        RecordId = pairs[index].left
                    )
                );
                items.add(
                    new DuplicateRecordItem(
                        DuplicateRecordSetId = sets[index].Id,
                        RecordId = pairs[index].right
                    )
                );
            }
            Database.insert(items, AccessLevel.USER_MODE);
            return sets.size();
        } catch (Exception caught) {
            ErrorLogger.log(caught, CONTEXT_WRITE);
            return 0;
        }
    }

    /**
     * The pairs the scan should pass over for this set of records, because they are already
     * sitting in a suggestion somebody has yet to look at.
     */
    public static Set<String> pairsAlreadySuggested(Set<Id> recordIds) {
        Set<String> known = new Set<String>();
        if (recordIds == null || recordIds.isEmpty()) {
            return known;
        }
        Set<Id> setIds = new Set<Id>();
        for (DuplicateRecordItem item : DuplicateSelector.itemsForRecords(recordIds)) {
            setIds.add(item.DuplicateRecordSetId);
        }
        Map<Id, List<Id>> recordsBySet = new Map<Id, List<Id>>();
        for (DuplicateRecordItem item : DuplicateSelector.itemsForSets(setIds)) {
            if (!recordsBySet.containsKey(item.DuplicateRecordSetId)) {
                recordsBySet.put(item.DuplicateRecordSetId, new List<Id>());
            }
            recordsBySet.get(item.DuplicateRecordSetId).add(item.RecordId);
        }
        for (List<Id> records : recordsBySet.values()) {
            known.addAll(pairKeysAmong(records));
        }
        return known;
    }

    /**
     * The pairs left after the ones a person has already said are not duplicates are taken
     * out. Asked as one query for a whole chunk, and asked last, so that the only pairs it
     * looks up are the ones the scan would otherwise write (R-DP5).
     */
    public static List<Pair> withoutDismissed(List<Pair> pairs) {
        List<Pair> result = new List<Pair>();
        if (pairs == null || pairs.isEmpty()) {
            return result;
        }
        Set<String> keys = new Set<String>();
        for (Pair pair : pairs) {
            keys.add(pair.key);
        }
        Set<String> dismissed = DuplicateSelector.dismissedKeys(keys);
        for (Pair pair : pairs) {
            if (!dismissed.contains(pair.key)) {
                result.add(pair);
            }
        }
        return result;
    }

    /**
     * Records that the person reviewing has decided these records are not duplicates of each
     * other, and takes the suggestion away.
     *
     * Deleting the suggestion removes the grouping and touches neither record (R-DP5). The
     * dismissal is what keeps the next scan from proposing the same two sisters at the same
     * address for a second time, so it is written first: if the delete fails, the pair is
     * still remembered and the transaction rolls both back together.
     */
    public static Integer dismiss(Id duplicateRecordSetId, String reason) {
        if (duplicateRecordSetId == null) {
            throw new DuplicateException(Label.Core_Duplicates_ErrorNoSuggestion);
        }
        List<DuplicateRecordSet> sets = DuplicateSelector.setsByIds(
            new Set<Id>{ duplicateRecordSetId }
        );
        if (sets.isEmpty()) {
            throw new DuplicateException(Label.Core_Duplicates_ErrorNoSuggestion);
        }
        List<Id> records = new List<Id>();
        for (DuplicateRecordItem item : sets[0].DuplicateRecordItems) {
            records.add(item.RecordId);
        }
        Set<String> keys = pairKeysAmong(records);
        keys.removeAll(DuplicateSelector.dismissedKeys(keys));
        List<Duplicate_Dismissal__c> dismissals = new List<Duplicate_Dismissal__c>();
        for (String key : keys) {
            dismissals.add(
                new Duplicate_Dismissal__c(
                    Pair_Key__c = key,
                    Reason__c = String.isBlank(reason) ? null : reason.trim().left(255)
                )
            );
        }
        if (!dismissals.isEmpty()) {
            Database.insert(dismissals, AccessLevel.USER_MODE);
        }
        Database.delete(new List<DuplicateRecordSet>{ sets[0] }, AccessLevel.USER_MODE);
        return dismissals.size();
    }

    /**
     * Takes a suggestion away without remembering anything, which is what a merge leaves
     * behind: the two records are one record now, so the pair cannot come back.
     */
    public static void closeSet(Id duplicateRecordSetId) {
        if (duplicateRecordSetId == null) {
            return;
        }
        List<DuplicateRecordSet> sets = DuplicateSelector.setsByIds(
            new Set<Id>{ duplicateRecordSetId }
        );
        if (!sets.isEmpty()) {
            Database.delete(new List<DuplicateRecordSet>{ sets[0] }, AccessLevel.USER_MODE);
        }
    }
}
