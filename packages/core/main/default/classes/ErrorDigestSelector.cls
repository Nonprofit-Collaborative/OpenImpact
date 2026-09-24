/**
 * The reads behind the error digest (C-23, R-E5): the new Error Log entries in a window, and
 * the users it may go to.
 *
 * Every read runs in user mode. The digest runs as the administrator who scheduled it, so it
 * counts what that person can see, which for a Nonprofit Admin is every entry; it never widens
 * what anybody can read, and the links it sends open only for someone allowed to open them.
 */
public with sharing class ErrorDigestSelector {
    /** The most distinct sources or severities one digest lists. */
    private static final Integer GROUP_LIMIT = 50;

    /** What arrived in one window, counted rather than copied. */
    public class Window {
        public Integer total = 0;
        public Map<String, Integer> bySource = new Map<String, Integer>();
        public Map<String, Integer> bySeverity = new Map<String, Integer>();
        public List<Error_Log__c> newest = new List<Error_Log__c>();
    }

    /**
     * The entries created after `after` and up to `upTo` that are still New, grouped by source
     * and severity, with the newest few by record name. Only the fields the digest may carry are
     * read: never the message, the technical detail or the record reference.
     */
    public static Window newEntries(Datetime after, Datetime upTo, Integer listed) {
        Window window = new Window();
        String statusNew = ErrorLogger.STATUS_NEW;
        for (AggregateResult row : [
            SELECT Context__c source, COUNT(Id) entries
            FROM Error_Log__c
            WHERE CreatedDate > :after AND CreatedDate <= :upTo AND Status__c = :statusNew
            WITH USER_MODE
            GROUP BY Context__c
            ORDER BY COUNT(Id) DESC
            LIMIT :GROUP_LIMIT
        ]) {
            Integer entries = (Integer) row.get('entries');
            window.bySource.put((String) row.get('source'), entries);
            window.total += entries;
        }
        if (window.total == 0) {
            return window;
        }
        for (AggregateResult row : [
            SELECT Severity__c severity, COUNT(Id) entries
            FROM Error_Log__c
            WHERE CreatedDate > :after AND CreatedDate <= :upTo AND Status__c = :statusNew
            WITH USER_MODE
            GROUP BY Severity__c
            ORDER BY COUNT(Id) DESC
            LIMIT :GROUP_LIMIT
        ]) {
            window.bySeverity.put((String) row.get('severity'), (Integer) row.get('entries'));
        }
        window.newest = [
            SELECT Id, Name, Context__c, Severity__c, CreatedDate
            FROM Error_Log__c
            WHERE CreatedDate > :after AND CreatedDate <= :upTo AND Status__c = :statusNew
            WITH USER_MODE
            ORDER BY CreatedDate DESC, Name DESC
            LIMIT :listed
        ];
        return window;
    }

    /** The active internal users among the given Ids, in the order given. */
    public static List<User> activeUsers(List<Id> userIds, Integer maximum) {
        if (userIds == null || userIds.isEmpty()) {
            return new List<User>();
        }
        Map<Id, User> found = new Map<Id, User>(
            [
                SELECT Id, Name, Email
                FROM User
                WHERE Id IN :userIds AND IsActive = TRUE AND UserType = 'Standard'
                WITH USER_MODE
            ]
        );
        List<User> ordered = new List<User>();
        for (Id userId : userIds) {
            if (found.containsKey(userId) && ordered.size() < maximum) {
                ordered.add(found.get(userId));
            }
        }
        return ordered;
    }

    /**
     * The active internal users with the given email addresses, one per address (the first by
     * name when two users share one), keyed by the address in lower case.
     */
    public static Map<String, User> activeUsersByEmail(Set<String> addresses) {
        Map<String, User> byAddress = new Map<String, User>();
        if (addresses == null || addresses.isEmpty()) {
            return byAddress;
        }
        for (User person : [
            SELECT Id, Name, Email
            FROM User
            WHERE Email IN :addresses AND IsActive = TRUE AND UserType = 'Standard'
            WITH USER_MODE
            ORDER BY Name
            LIMIT 1000
        ]) {
            String key = person.Email.toLowerCase();
            if (!byAddress.containsKey(key)) {
                byAddress.put(key, person);
            }
        }
        return byAddress;
    }
}
