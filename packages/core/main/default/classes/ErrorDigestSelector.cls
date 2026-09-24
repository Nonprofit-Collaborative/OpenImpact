/**
 * The reads behind the error digest (C-23, R-E5): the users it may go to.
 *
 * Every read runs in user mode. The digest runs as the administrator who scheduled it, so it
 * counts what that person can see, which for a Nonprofit Admin is every entry; it never widens
 * what anybody can read, and the links it sends open only for someone allowed to open them.
 */
public with sharing class ErrorDigestSelector {
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
