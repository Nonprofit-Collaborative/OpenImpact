/**
 * Recurring sources: a mapping that loads a file nobody uploaded (R-IT6, feature C-19).
 *
 * The source is a name, and the name is the start of a file name. Somebody, or something,
 * drops the monthly export into the org as a Salesforce File called "Monthly processor export
 * 2026-09.csv", and the mapping whose source is "Monthly processor export" picks it up: no
 * callout, no credentials, no second integration to keep alive, and every way of getting a
 * file into Salesforce is already a way of feeding this.
 *
 * Three things keep an unattended import from being a way to lose an afternoon of data. It
 * does nothing unless an administrator has turned it on. It loads one file per source per
 * run, so a folder somebody emptied into the org cannot become one enormous job. And every
 * batch it makes is an ordinary batch: dry run first, tagged, journaled, and undoable inside
 * the same window, because an import nobody watched is the one most likely to need undoing.
 */
@NamespaceAccessible
public with sharing class ImportRecurringService {
    /** How many rows of a file are staged in one request to the row service. */
    private static final Integer STAGE_PAGE_SIZE = 500;

    /** The largest file the job reads in one transaction, so the heap is never the limit. */
    private static final Integer MAX_FILE_BYTES = 4000000;

    /**
     * How many imports one run may start. The platform holds five batch jobs, and an org with
     * a dozen recurring sources should work through them over successive nights rather than
     * fail the twelfth every night.
     */
    private static final Integer MAX_STARTS_PER_RUN = 2;

    /** What one mapping's turn produced. */
    private class Attempt {
        Boolean started = false;
        String message;
    }

    /**
     * Looks at every active recurring mapping and starts at most one import for each.
     *
     * @return how many imports were started
     */
    @NamespaceAccessible
    public static Integer run() {
        if (!isEnabled()) {
            return 0;
        }
        List<Import_Template__c> templates = ImportTemplateSelector.selectRecurring();
        if (templates.isEmpty()) {
            return 0;
        }
        Set<String> alreadyLoaded = loadedFileIds();
        Integer started = 0;
        List<Import_Template__c> toUpdate = new List<Import_Template__c>();
        for (Import_Template__c template : templates) {
            Attempt attempt = new Attempt();
            if (started >= MAX_STARTS_PER_RUN) {
                attempt.message = Label.Core_Import_RecurringWaitsForNextRun;
            } else {
                try {
                    attempt = loadOne(template, alreadyLoaded);
                } catch (Exception e) {
                    ErrorLogger.log(e, 'ImportRecurringService.run', template.Id);
                    attempt.message = e.getMessage();
                }
            }
            if (attempt.started) {
                started++;
            }
            toUpdate.add(
                new Import_Template__c(
                    Id = template.Id,
                    Recurring_Last_Run__c = Datetime.now(),
                    Recurring_Last_Result__c = attempt.message == null
                        ? null
                        : attempt.message.abbreviate(255)
                )
            );
        }
        if (!toUpdate.isEmpty()) {
            // The run record is the package's own bookkeeping about its own job (ADR-0021),
            // and it is written whether the run found anything or not: a feed that has quietly
            // stopped looks exactly like a feed with nothing new until the run is visible.
            Database.update(toUpdate, false, AccessLevel.SYSTEM_MODE);
        }
        return started;
    }

    /** Whether an administrator has turned recurring sources on. Off is the shipped answer. */
    @NamespaceAccessible
    public static Boolean isEnabled() {
        Object configured = SettingsService.hasKey('Import_Recurring_Enabled__c')
            ? SettingsService.getValue('Import_Recurring_Enabled__c')
            : null;
        return configured == true || 'true'.equalsIgnoreCase(String.valueOf(configured));
    }

    /**
     * Starts the import of the oldest file this source has not loaded yet, and says in one
     * sentence what it did, for the mapping's visible last run.
     */
    private static Attempt loadOne(Import_Template__c template, Set<String> alreadyLoaded) {
        Attempt attempt = new Attempt();
        if (String.isBlank(template.Source_Name__c)) {
            attempt.message = Label.Core_Import_RecurringNoSourceName;
            return attempt;
        }
        List<ContentVersion> files = waiting(template.Source_Name__c, alreadyLoaded);
        if (files.isEmpty()) {
            attempt.message = Label.Core_Import_RecurringNothingNew;
            return attempt;
        }
        ContentVersion file = files[0];
        if (file.ContentSize != null && file.ContentSize > MAX_FILE_BYTES) {
            attempt.message = String.format(
                Label.Core_Import_RecurringFileTooLarge,
                new List<String>{ file.Title }
            );
            return attempt;
        }
        ImportCsvParser.Parsed parsed = ImportCsvParser.parse(file.VersionData.toString());
        if (parsed.rows.isEmpty()) {
            attempt.message = String.format(
                Label.Core_Import_RecurringFileEmpty,
                new List<String>{ file.Title }
            );
            return attempt;
        }
        Import_Batch__c batch = ImportBatchService.create(
            template.Id,
            String.valueOf(file.ContentDocumentId),
            file.Title,
            true
        );
        for (Integer offset = 0; offset < parsed.rows.size(); offset += STAGE_PAGE_SIZE) {
            List<Map<String, Object>> page = new List<Map<String, Object>>();
            for (
                Integer i = offset;
                i < Math.min(offset + STAGE_PAGE_SIZE, parsed.rows.size());
                i++
            ) {
                page.add(parsed.rows[i]);
            }
            ImportBatchService.stageRows(batch.Id, page, offset + 2);
        }
        // The dry run comes first here exactly as it does for a person (R-IB1). The commit
        // follows automatically when it finishes, and only then.
        ImportBatchService.startDryRun(batch.Id);
        alreadyLoaded.add(String.valueOf(file.ContentDocumentId));
        attempt.started = true;
        attempt.message = String.format(
            Label.Core_Import_RecurringStarted,
            new List<String>{ file.Title, String.valueOf(parsed.rows.size()) }
        );
        return attempt;
    }

    /**
     * The files whose name starts with this source name and which no import has loaded,
     * oldest first, so a backlog is worked through in the order it arrived.
     *
     * The identifier of the document, not its name, is what says a file has been loaded, so a
     * file uploaded twice under the same name is still loaded once and a file renamed after
     * loading is not loaded again.
     */
    private static List<ContentVersion> waiting(String sourceName, Set<String> alreadyLoaded) {
        String prefix = sourceName.trim() + '%';
        List<ContentVersion> result = new List<ContentVersion>();
        for (
            ContentVersion file : [
                SELECT Id, Title, ContentDocumentId, ContentSize, VersionData, CreatedDate
                FROM ContentVersion
                WHERE IsLatest = TRUE AND Title LIKE :prefix
                WITH USER_MODE
                ORDER BY CreatedDate ASC
                LIMIT 10
            ]
        ) {
            if (!alreadyLoaded.contains(String.valueOf(file.ContentDocumentId))) {
                result.add(file);
            }
        }
        return result;
    }

    /** The files every import has already loaded, so none of them is loaded twice. */
    private static Set<String> loadedFileIds() {
        Set<String> result = new Set<String>();
        for (
            Import_Batch__c batch : [
                SELECT File_Id__c
                FROM Import_Batch__c
                WHERE File_Id__c != NULL
                WITH SYSTEM_MODE
                ORDER BY CreatedDate DESC
                LIMIT 2000
            ]
        ) {
            result.add(batch.File_Id__c);
        }
        return result;
    }
}
