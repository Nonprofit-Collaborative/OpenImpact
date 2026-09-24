/**
 * The error digest (C-23, canonical model R-E5, ADR-NEXT): one short email to each of the
 * people who look after Open Impact, counting the Error Log entries that arrived since the last
 * digest and are still New.
 *
 * What it may say is the point of the design. It counts entries by source and by severity and
 * links to the newest by record name; it never copies an entry's message, technical detail or
 * record reference, so it carries less about a donor than the Error Log itself. It goes only to
 * active users of the org, each message addressed to the user record, which the platform does
 * not count against the daily limit on email sent to addresses. A run that finds nothing new
 * sends nothing.
 *
 * Each run remembers the end of the window it covered. A run that sent, or found nothing, moves
 * the window on; a run that could not send leaves it where it was, so the next one tries again
 * with nothing lost and nothing counted twice.
 */
public with sharing class ErrorDigestService {
    public static final String FREQUENCY_DAILY = 'Daily';
    public static final String FREQUENCY_WEEKLY = 'Weekly';

    /** How many entries one digest links to by name; the rest are counted. */
    @TestVisible
    private static final Integer ENTRIES_LISTED = 25;

    /**
     * How early a run may be and still count as due. The job runs at 07:00 and the window it
     * covered ended a few seconds after 07:00 the day before, so a run a second short of a full
     * day must not wait another day.
     */
    private static final Integer DUE_TOLERANCE_MINUTES = 60;

    private static final String LOG_CONTEXT = 'Error digest';

    /**
     * Test seam, null in every real transaction: when a test sets it, messages are added here
     * instead of being handed to the platform, so what the digest composed can be read back.
     */
    @TestVisible
    private static List<Messaging.SingleEmailMessage> capturedMessages;

    /** What one run did. */
    public class Outcome {
        public Boolean sent = false;
        public Integer entries = 0;
        public Integer recipients = 0;
        public String summary;
    }

    /** The scheduled run: sends only when the chosen frequency says a digest is due. */
    public static Outcome runScheduled() {
        return run(false);
    }

    /** Send now: ignores the frequency, and still sends nothing when nothing is new. */
    public static Outcome sendNow() {
        return run(true);
    }

    private static Outcome run(Boolean ignoreFrequency) {
        Datetime runAt = System.now();
        Nonprofit_Settings__c settings = SettingsService.getSettings();
        Datetime coveredUntil = settings.Error_Digest_Covered_Until__c;
        Integer periodDays = FREQUENCY_WEEKLY.equals(settings.Error_Digest_Frequency__c) ? 7 : 1;
        Outcome outcome = new Outcome();

        Datetime dueAt = coveredUntil?.addDays(periodDays);
        if (!ignoreFrequency && dueAt != null && dueAt.addMinutes(-DUE_TOLERANCE_MINUTES) > runAt) {
            outcome.summary = String.format(
                System.Label.Core_ErrorDigest_SummaryNotDue,
                new List<Object>{ dueAt.format() }
            );
            return finish(outcome, runAt, coveredUntil);
        }

        Datetime windowStart = coveredUntil == null ? runAt.addDays(-periodDays) : coveredUntil;
        ErrorDigestSelector.Window window = ErrorDigestSelector.newEntries(
            windowStart,
            runAt,
            ENTRIES_LISTED
        );
        outcome.entries = window.total;
        if (window.total == 0) {
            outcome.summary = String.format(
                System.Label.Core_ErrorDigest_SummaryNothingNew,
                new List<Object>{ windowStart.format() }
            );
            return finish(outcome, runAt, runAt);
        }

        List<User> recipients = ErrorDigestRecipients.resolve(settings.Error_Digest_Recipients__c);
        if (recipients.isEmpty()) {
            // Not written to the Error Log: the next run would find that entry, fail to send it,
            // and log again. Health Check already names an org where nobody administers.
            outcome.summary = System.Label.Core_ErrorDigest_SummaryNoRecipients;
            return finish(outcome, runAt, coveredUntil);
        }

        String failure = deliver(compose(window, windowStart, recipients), outcome);
        if (outcome.recipients == 0) {
            outcome.summary = String.format(
                System.Label.Core_ErrorDigest_SummaryNotSent,
                new List<Object>{ failure }
            );
            ErrorLogger.logMessage(outcome.summary, LOG_CONTEXT, ErrorLogger.SEVERITY_ERROR);
            return finish(outcome, runAt, coveredUntil);
        }
        outcome.sent = true;
        outcome.summary = String.format(
            System.Label.Core_ErrorDigest_SummarySent,
            new List<Object>{ String.valueOf(window.total), String.valueOf(outcome.recipients) }
        );
        return finish(outcome, runAt, runAt);
    }

    private static Outcome finish(Outcome outcome, Datetime runAt, Datetime coveredUntil) {
        ErrorDigestWriter.recordRun(runAt, outcome.summary, coveredUntil);
        SettingsService.clearCache();
        return outcome;
    }

    // ------------------------------------------------------------------------------ the message

    @TestVisible
    private static List<Messaging.SingleEmailMessage> compose(
        ErrorDigestSelector.Window window,
        Datetime windowStart,
        List<User> recipients
    ) {
        String subject = String.format(
            System.Label.Core_ErrorDigest_Subject,
            new List<Object>{ String.valueOf(window.total) }
        );
        String body = body(window, windowStart);
        List<Messaging.SingleEmailMessage> messages = new List<Messaging.SingleEmailMessage>();
        for (User recipient : recipients) {
            Messaging.SingleEmailMessage message = new Messaging.SingleEmailMessage();
            // Addressed to the user record: internal users only, and not counted against the
            // org's daily limit on email sent to addresses (ADR-NEXT).
            message.setTargetObjectId(recipient.Id);
            message.setSaveAsActivity(false);
            message.setSenderDisplayName(System.Label.Core_ErrorDigest_SenderName);
            message.setSubject(subject);
            message.setPlainTextBody(body);
            messages.add(message);
        }
        return messages;
    }

    private static String body(ErrorDigestSelector.Window window, Datetime windowStart) {
        String base = URL.getOrgDomainUrl().toExternalForm();
        List<String> lines = new List<String>{
            String.format(
                System.Label.Core_ErrorDigest_Intro,
                new List<Object>{ String.valueOf(window.total), windowStart.format() }
            ),
            ''
        };
        lines.add(System.Label.Core_ErrorDigest_BySource);
        lines.addAll(countLines(window.bySource));
        lines.add('');
        lines.add(System.Label.Core_ErrorDigest_BySeverity);
        lines.addAll(countLines(window.bySeverity));
        lines.add('');
        lines.add(System.Label.Core_ErrorDigest_Newest);
        for (Error_Log__c entry : window.newest) {
            lines.add(
                '  ' +
                    String.join(
                        new List<String>{
                            entry.Name,
                            orNoSource(entry.Context__c),
                            String.valueOf(entry.Severity__c)
                        },
                        ', '
                    ) +
                    ': ' +
                    base +
                    '/' +
                    entry.Id
            );
        }
        Integer unlisted = window.total - window.newest.size();
        if (unlisted > 0) {
            lines.add(
                String.format(
                    System.Label.Core_ErrorDigest_More,
                    new List<Object>{ String.valueOf(unlisted) }
                )
            );
        }
        lines.add('');
        lines.add(
            String.format(
                System.Label.Core_ErrorDigest_ListLink,
                new List<Object>{ base + ErrorLogCountSelector.listViewUrl() }
            )
        );
        lines.add(
            String.format(
                System.Label.Core_ErrorDigest_StillNew,
                new List<Object>{ String.valueOf(ErrorLogCountSelector.countNew()) }
            )
        );
        lines.add('');
        lines.add(System.Label.Core_ErrorDigest_Footer);
        return String.join(lines, '\n');
    }

    private static List<String> countLines(Map<String, Integer> counts) {
        List<String> lines = new List<String>();
        for (String name : counts.keySet()) {
            lines.add('  ' + orNoSource(name) + ': ' + counts.get(name));
        }
        return lines;
    }

    private static String orNoSource(String name) {
        return String.isBlank(name) ? System.Label.Core_ErrorDigest_NoSource : name;
    }

    // ------------------------------------------------------------------------------- sending

    /**
     * Hands the messages to the platform in one call, with partial success so that one refused
     * recipient does not stop the others. Sets how many were delivered on the outcome and
     * returns the first reason one was not, for the run summary.
     */
    private static String deliver(List<Messaging.SingleEmailMessage> messages, Outcome outcome) {
        if (capturedMessages != null) {
            capturedMessages.addAll(messages);
            outcome.recipients = messages.size();
            return null;
        }
        String firstFailure;
        try {
            for (Messaging.SendEmailResult result : Messaging.sendEmail(messages, false)) {
                if (result.isSuccess()) {
                    outcome.recipients++;
                } else if (firstFailure == null && !result.getErrors().isEmpty()) {
                    firstFailure = result.getErrors()[0].getMessage();
                }
            }
        } catch (Exception refused) {
            // An org set to send system email only refuses the whole call.
            firstFailure = refused.getMessage();
        }
        return String.isBlank(firstFailure)
            ? System.Label.Core_ErrorDigest_UnknownFailure
            : firstFailure.left(150);
    }
}
