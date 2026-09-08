/**
 * Which `ReceiptRenderer` this org uses.
 *
 * The setting exists because ADR-0016's first spike is open: nobody has yet confirmed in a real
 * org that `Blob.toPdf()` is not metered as a callout inside a batch. If it is, an org can move to
 * the fallback implementation by changing one value in the Nonprofit Settings console rather than
 * by waiting for a package version. An empty setting, which is the shipped state, means the
 * renderer the package ships.
 *
 * A named class that cannot be constructed is an error with a readable message, not a silent
 * fallback: an administrator who typed a class name and got the default renderer anyway would have
 * no way to tell.
 */
public with sharing class ReceiptRendererFactory {
    /**
     * Set by a test to run the whole feature without producing PDF bytes. Production code never
     * assigns it; ADR-0016 records that PDF bytes cannot be asserted in an Apex test, so the tests
     * assert the composed HTML and the record and file graph instead.
     */
    @TestVisible
    private static ReceiptRenderer overrideRenderer;

    public static ReceiptRenderer get() {
        if (overrideRenderer != null) {
            return overrideRenderer;
        }
        String configured = Giving_Settings__c.getOrgDefaults().Receipt_Renderer__c;
        if (String.isBlank(configured)) {
            return new BlobToPdfReceiptRenderer();
        }
        Type rendererType = Type.forName(configured.trim());
        if (rendererType == null) {
            throw new ReceiptRendererFactoryException(
                String.format(
                    Label.Giving_Receipt_UnknownRenderer,
                    new List<String>{ configured.trim() }
                )
            );
        }
        Object instance = rendererType.newInstance();
        if (!(instance instanceof ReceiptRenderer)) {
            throw new ReceiptRendererFactoryException(
                String.format(
                    Label.Giving_Receipt_UnknownRenderer,
                    new List<String>{ configured.trim() }
                )
            );
        }
        return (ReceiptRenderer) instance;
    }

    public class ReceiptRendererFactoryException extends Exception {
    }
}
