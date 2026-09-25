/**
 * Finds the Health Check extensions dependent packages installed, or answers that there are
 * none, which is the ordinary case in an org without Giving or Connect (G-20 follow-up,
 * ADR-0053, ADR-0057, amended by feature X-01 for Connect's).
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
    /** Connect's, for its nightly mirror run (X-01). */
    @NamespaceAccessible
    public static final String CONNECT_CLASS_NAME = 'ConnectHealthCheckExtension';

    /** Injected by Core's tests, which have no other package to resolve a real one from. */
    @TestVisible
    private static HealthCheckExtension extensionOverride;

    /** The same, standing in for Connect's. */
    @TestVisible
    private static HealthCheckExtension connectOverride;

    /** Set by Core's tests to see the org as having no extension at all. */
    @TestVisible
    private static Boolean noneForTest = false;

    private static Boolean looked = false;
    private static HealthCheckExtension found;
    private static Boolean connectLooked = false;
    private static HealthCheckExtension connectFound;

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
            found = resolve(CLASS_NAME);
        }
        return found;
    }

    /**
     * Every installed extension, keyed by the name a failure of it is reported under
     * (`giving_extension`, `connect_extension`), so one that throws never hides the other's.
     */
    @NamespaceAccessible
    public static Map<String, HealthCheckExtension> findAll() {
        Map<String, HealthCheckExtension> byKey = new Map<String, HealthCheckExtension>();
        HealthCheckExtension giving = find();
        if (giving != null) {
            byKey.put('giving_extension', giving);
        }
        HealthCheckExtension connect = connectOverride;
        if (connect == null && noneForTest != true) {
            if (!connectLooked) {
                connectLooked = true;
                connectFound = resolve(CONNECT_CLASS_NAME);
            }
            connect = connectFound;
        }
        if (connect != null) {
            byKey.put('connect_extension', connect);
        }
        return byKey;
    }

    private static HealthCheckExtension resolve(String className) {
        String prefix = NamespaceUtil.prefix();
        Type extensionType = Type.forName(
            String.isBlank(prefix) ? null : prefix.removeEnd('__'),
            className
        );
        if (extensionType == null) {
            extensionType = Type.forName(className);
        }
        if (extensionType == null) {
            return null;
        }
        Object candidate;
        try {
            candidate = extensionType.newInstance();
        } catch (Exception cannotBuild) {
            ErrorLogger.log(cannotBuild, 'HealthCheckExtensions.resolve');
            return null;
        }
        if (candidate instanceof HealthCheckExtension) {
            return (HealthCheckExtension) candidate;
        }
        ErrorLogger.log(
            new System.TypeException(className + ' does not implement HealthCheckExtension'),
            'HealthCheckExtensions.resolve'
        );
        return null;
    }
}
