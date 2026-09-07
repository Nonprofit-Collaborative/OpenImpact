/**
 * All SOQL against Address__c. Feature code never queries the object directly
 * (plan Section 7.2: every query lives in a Selector).
 */
public with sharing class AddressSelector {
    /**
     * Every address belonging to any of the given owners, whether the owner is a
     * household or organization account, a contact, or a person account. Ordered so the
     * address in use comes first and the newest address comes next, which is the order
     * the address panel shows and the order the delete promotion relies on.
     */
    public static List<Address__c> selectByOwnerIds(Set<Id> ownerIds) {
        if (ownerIds == null || ownerIds.isEmpty()) {
            return new List<Address__c>();
        }
        return [
            SELECT
                Id,
                Name,
                Account__c,
                Contact__c,
                Person_Account__c,
                Type__c,
                Street__c,
                City__c,
                State__c,
                Postal_Code__c,
                Country__c,
                Seasonal_Start_Month__c,
                Seasonal_Start_Day__c,
                Seasonal_End_Month__c,
                Seasonal_End_Day__c,
                Is_Default__c,
                Verification_Status__c,
                Latest_Verified_Date__c,
                CreatedDate
            FROM Address__c
            WHERE
                Account__c IN :ownerIds
                OR Contact__c IN :ownerIds
                OR Person_Account__c IN :ownerIds
            WITH USER_MODE
            ORDER BY Is_Default__c DESC, CreatedDate DESC
            LIMIT 10000
        ];
    }

    /**
     * The addresses currently marked default for the given owners, leaving out any
     * address in excludeAddressIds. Used to keep one default per owner.
     */
    public static List<Address__c> selectDefaultsByOwnerIds(
        Set<Id> ownerIds,
        Set<Id> excludeAddressIds
    ) {
        if (ownerIds == null || ownerIds.isEmpty()) {
            return new List<Address__c>();
        }
        Set<Id> skip = excludeAddressIds == null ? new Set<Id>() : excludeAddressIds;
        return [
            SELECT
                Id,
                Name,
                Account__c,
                Contact__c,
                Person_Account__c,
                Type__c,
                Street__c,
                City__c,
                State__c,
                Postal_Code__c,
                Country__c,
                Seasonal_Start_Month__c,
                Seasonal_Start_Day__c,
                Seasonal_End_Month__c,
                Seasonal_End_Day__c,
                Is_Default__c,
                CreatedDate
            FROM Address__c
            WHERE
                Is_Default__c = TRUE
                AND Id NOT IN :skip
                AND (Account__c IN :ownerIds
                OR Contact__c IN :ownerIds
                OR Person_Account__c IN :ownerIds)
            WITH USER_MODE
            ORDER BY CreatedDate DESC
            LIMIT 10000
        ];
    }

    /** The given addresses, with every field the service and the panel read. */
    public static List<Address__c> selectByIds(Set<Id> addressIds) {
        if (addressIds == null || addressIds.isEmpty()) {
            return new List<Address__c>();
        }
        return [
            SELECT
                Id,
                Name,
                Account__c,
                Contact__c,
                Person_Account__c,
                Type__c,
                Street__c,
                City__c,
                State__c,
                Postal_Code__c,
                Country__c,
                Seasonal_Start_Month__c,
                Seasonal_Start_Day__c,
                Seasonal_End_Month__c,
                Seasonal_End_Day__c,
                Is_Default__c,
                Verification_Status__c,
                Latest_Verified_Date__c,
                CreatedDate
            FROM Address__c
            WHERE Id IN :addressIds
            WITH USER_MODE
            LIMIT 10000
        ];
    }

    /** The owners that already have at least one address on file. */
    public static Set<Id> selectOwnerIdsWithAddresses(Set<Id> ownerIds) {
        Set<Id> found = new Set<Id>();
        for (Address__c address : selectByOwnerIds(ownerIds)) {
            if (address.Account__c != null) {
                found.add(address.Account__c);
            }
            if (address.Contact__c != null) {
                found.add(address.Contact__c);
            }
            if (address.Person_Account__c != null) {
                found.add(address.Person_Account__c);
            }
        }
        return found;
    }
}
