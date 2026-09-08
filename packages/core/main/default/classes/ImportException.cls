/**
 * Raised when an import cannot proceed: a mapping that identifies nobody, a template that
 * asks for something this org cannot do, or a batch asked to commit before it has been
 * dry run. The message is written for an administrator, because it is shown to one.
 */
@NamespaceAccessible
public with sharing class ImportException extends Exception {
}
