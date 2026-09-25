/**
 * Finds the Health Check extension a dependent package installed, or answers that there is
 * none, which is the ordinary case in an org without Giving (G-20 follow-up, ADR-0053,
 * ADR-NEXT).
 *
 * The class is found by namespace and name, the pattern `ImportEntityProcessors` uses for the
 * same reason (R-IR6): a class name is not an API name, so it takes no `__` prefix. A class
 * that cannot be built, or does not implement the interface, is treated as absent and logged,
 * because a health report must not fail over a module it can do without.
 */
@NamespaceAccessible
public with sharing class HealthCheckExtensions {
    /** The class name a dependent package registers to add findings (G-20 follow-up). */
    @NamespaceAccessible
    public static final String CLASS_NAME = 'GivingHealthCheckExtension';

    /** Injected by Core's tests, which have no other package to resolve a real one from. */
    @TestVisible
    private static HealthCheckExtension extensionOverride;

    /** Set by Core's tests to see the org as having no extension at all. */
    @TestVisible
    private static Boolean noneForTest = false;

    private static Boolean looked = false;
    private static HealthCheckExtension found;

    /** The installed extension, or null. Looked up once per transaction. */
    @NamespaceAccessible
    public static HealthCheckExtension find() {
        if (extensionOverride != null) {
            return extensionOverride;
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

    private static HealthCheckExtension resolve() {
        String prefix = NamespaceUtil.prefix();
        Type extensionType = Type.forName(
            String.isBlank(prefix) ? null : prefix.removeEnd('__'),
            CLASS_NAME
        );
        if (extensionType == null) {
            extensionType = Type.forName(CLASS_NAME);
        }
        if (extensionType == null) {
            return null;
        }
        try {
            Object candidate = extensionType.newInstance();
            return candidate instanceof HealthCheckExtension
                ? (HealthCheckExtension) candidate
                : null;
        } catch (Exception cannotBuild) {
            ErrorLogger.log(cannotBuild, 'HealthCheckExtensions.resolve');
            return null;
        }
    }
}
