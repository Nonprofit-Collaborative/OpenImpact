/**
 * Finds the entity processor a dependent package installed (R-IR6), or answers that there is
 * none, which is the ordinary case in an org without Giving.
 *
 * The class is found by namespace and name, the pattern `SampleDataModules` uses: a class
 * name is not an API name, so it takes no `__` prefix. A class that cannot be built, or does
 * not implement the interface, is logged and treated as absent, because an import must not
 * fail over a module it can do without.
 */
@NamespaceAccessible
public with sharing class ImportEntityProcessors {
    /** The class name a dependent package registers to resolve the rest of a row (R-IR6). */
    @NamespaceAccessible
    public static final String CLASS_NAME = 'GiftImportProcessor';

    /** Injected by Core's tests, which have no other package to resolve a real one from. */
    @TestVisible
    private static ImportEntityProcessor processorOverride;

    /** Set by Core's tests to see the org as having no processor at all. */
    @TestVisible
    private static Boolean noneForTest = false;

    private static Boolean looked = false;
    private static ImportEntityProcessor found;

    /** The installed processor, or null. Looked up once per transaction. */
    @NamespaceAccessible
    public static ImportEntityProcessor find() {
        if (processorOverride != null) {
            return processorOverride;
        }
        if (noneForTest == true) {
            return null;
        }
        if (!looked) {
            looked = true;
            found = resolve();
        }
        return found;
    }

    private static ImportEntityProcessor resolve() {
        String prefix = NamespaceUtil.prefix();
        Type processorType = Type.forName(
            String.isBlank(prefix) ? null : prefix.removeEnd('__'),
            CLASS_NAME
        );
        if (processorType == null) {
            processorType = Type.forName(CLASS_NAME);
        }
        if (processorType == null) {
            return null;
        }
        try {
            Object candidate = processorType.newInstance();
            return candidate instanceof ImportEntityProcessor
                ? (ImportEntityProcessor) candidate
                : null;
        } catch (Exception cannotBuild) {
            ErrorLogger.log(cannotBuild, 'ImportEntityProcessors.resolve');
            return null;
        }
    }
}
