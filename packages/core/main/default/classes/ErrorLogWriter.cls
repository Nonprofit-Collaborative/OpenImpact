/**
 * Writes Error Log records. The only class in the package that does.
 *
 * DOCUMENTED EXCEPTION to the "with sharing, user mode" rule (plan Section 4.13). This class is
 * `without sharing` and its insert runs in system mode, for one reason: a failure must be
 * recorded even when the running user has no create access on the Error Log object. The failures
 * that matter most are the ones a person hits because something is missing from their access, and
 * those are exactly the ones a user mode insert would drop on the floor. Nothing is read here and
 * nothing is returned to the caller, so no record data can leak through this class.
 *
 * No user input reaches this class unescaped: callers pass a message from a Custom Label or an
 * exception's own message, and the record is written with ordinary typed DML. There is no dynamic
 * SOQL and no dynamic DML anywhere in this file.
 *
 * It never throws (rule R-E2). A failure to log is swallowed rather than masking the original
 * failure, which the caller is usually in the middle of reporting to the user.
 */
public without sharing class ErrorLogWriter {
    public static void write(List<Error_Log__c> entries) {
        if (entries == null || entries.isEmpty()) {
            return;
        }
        try {
            Database.insert(entries, false, AccessLevel.SYSTEM_MODE);
        } catch (Exception failedToLog) {
            System.debug(
                LoggingLevel.ERROR,
                'Open Impact could not write an Error Log record: ' + failedToLog.getMessage()
            );
        }
    }
}
