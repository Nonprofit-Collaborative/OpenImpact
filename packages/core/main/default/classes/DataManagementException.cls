/**
 * A refusal from Find or bulk update (C-34, C-35), carrying a sentence the person can act on.
 * Controllers show it as it is and do not log it: it is an answer, not a fault.
 */
@NamespaceAccessible
public with sharing class DataManagementException extends Exception {
}
