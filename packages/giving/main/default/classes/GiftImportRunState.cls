/**
 * What one gift import run carries from chunk to chunk (R-DM1, R-DM4). Each chunk is its own
 * transaction, so Core's import batch holds this as `ImportEntityProcessors.carriedState`: the
 * scheduled payments earlier chunks matched, and the external IDs of the gifts earlier chunks of
 * a dry run would load (a commit finds those gifts themselves). A dry run then reports what
 * the commit will do.
 *
 * An external ID is kept as a digest of its lowercased value, so the state grows by the same
 * small amount per row however long the identifiers are. The digest is only compared.
 */
public with sharing class GiftImportRunState {
    private static final String CLAIMED_KEY = 'claimedInstallments';
    private static final String SEEN_KEY = 'seenExternalIds';

    /** The scheduled payments earlier chunks matched (R-DM4). */
    public Set<Id> claimedInstallments = new Set<Id>();
    /** The digests of the external IDs earlier chunks loaded (R-DM1). */
    public Set<String> seenExternalIds = new Set<String>();

    /** The state earlier chunks left. A state this class did not write carries nothing. */
    public static GiftImportRunState carried() {
        GiftImportRunState state = new GiftImportRunState();
        String carried = ImportEntityProcessors.carriedState;
        if (String.isBlank(carried)) {
            return state;
        }
        try {
            Map<String, Object> values = (Map<String, Object>) JSON.deserializeUntyped(carried);
            for (Object value : listAt(values, CLAIMED_KEY)) {
                state.claimedInstallments.add(Id.valueOf(String.valueOf(value)));
            }
            for (Object value : listAt(values, SEEN_KEY)) {
                state.seenExternalIds.add(String.valueOf(value));
            }
        } catch (Exception unreadable) {
            return new GiftImportRunState();
        }
        return state;
    }

    private static List<Object> listAt(Map<String, Object> values, String key) {
        Object value = values.get(key);
        return value == null ? new List<Object>() : (List<Object>) value;
    }

    /** Hands this state to the next chunk. */
    public void carry() {
        ImportEntityProcessors.carriedState = JSON.serialize(
            new Map<String, Object>{
                CLAIMED_KEY => new List<Id>(claimedInstallments),
                SEEN_KEY => new List<String>(seenExternalIds)
            }
        );
    }

    /**
     * How an external ID is remembered: one digest for every spelling of its case. Sixteen hex
     * digits (64 bits) keep a file of half a million rows well clear of a collision.
     */
    public static String key(String externalId) {
        return EncodingUtil.convertToHex(
                Crypto.generateDigest('MD5', Blob.valueOf(externalId.toLowerCase()))
            )
            .left(16);
    }
}
