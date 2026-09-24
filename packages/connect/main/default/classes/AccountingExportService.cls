/**
 * The accounting export (feature X-04): the gifts in a date range as a CSV file for the
 * bookkeeper's accounting system. Admin guide: `docs/admin-guide/accounting-export.md`;
 * decisions: ADR-0051.
 *
 * - One row per allocation, so a split gift is a row per fund; a gift with no allocation at all
 *   is one row with no fund, so an unfiltered file never leaves money out.
 * - Received, Refunded and Written off gifts, the same statuses the giving totals count
 *   (ADR-0022). A refund or write-off is a negative gift of its own (R-G3), so it is its own
 *   negative row on its own date. Pending gifts have not arrived and In-kind gifts are not money.
 * - The export reads and writes nothing, and stores nothing about having run. Marking gifts
 *   posted belongs to G-20 in Giving.
 * - A range over the row limit is refused rather than cut short: a short file that looks
 *   complete reconciles to nothing.
 *
 * The header is a file format contract, not screen text: it is a constant rather than custom
 * labels so that an import mapping saved once in an accounting system keeps working.
 */
public with sharing class AccountingExportService {
    @TestVisible
    private static Integer maxRows = 10000;
    public static final List<String> HEADER = new List<String>{
        'Date',
        'Gift Number',
        'Original Gift',
        'Donor',
        'Fund',
        'Accounting Code',
        'Payment Method',
        'Reference',
        'Amount'
    };

    private static final Set<String> STATUSES = new Set<String>{
        'Received',
        'Refunded',
        'Written off'
    };
    private static final String TYPE_IN_KIND = 'In-kind';
    private static final String LINE_END = '\r\n';
    private static final Set<String> FORMULA_STARTS = new Set<String>{
        '=',
        '+',
        '-',
        '@',
        '\t',
        '\r'
    };

    /** A refusal the person can act on, in words. */
    public class ExportException extends Exception {
    }

    /** The file and what it holds. */
    public class ExportFile {
        public String csv;
        public Integer rowCount = 0;
        public Integer giftCount = 0;
        public Decimal total = 0;
    }

    /** The payment methods the export can be narrowed to: every active gift type but In-kind. */
    public static List<String> paymentMethods() {
        List<String> methods = new List<String>();
        for (Schema.PicklistEntry entry : Gift__c.Type__c.getDescribe().getPicklistValues()) {
            if (entry.isActive() && entry.getValue() != TYPE_IN_KIND) {
                methods.add(entry.getValue());
            }
        }
        return methods;
    }

    /**
     * The export for a range, narrowed to one fund and one payment method when they are given.
     * An empty range gives an ExportFile with no rows and no file.
     */
    public static ExportFile build(Date fromDate, Date toDate, Id fundId, String paymentMethod) {
        if (fromDate == null || toDate == null) {
            throw new ExportException(Label.Connect_AccountingExport_ErrorDatesRequired);
        }
        if (toDate < fromDate) {
            throw new ExportException(Label.Connect_AccountingExport_ErrorDateOrder);
        }
        if (fundId != null && fundId.getSObjectType() != Fund__c.SObjectType) {
            throw new ExportException(Label.Connect_AccountingExport_ErrorFund);
        }
        Set<String> methods = new Set<String>(paymentMethods());
        if (String.isNotBlank(paymentMethod)) {
            if (!methods.contains(paymentMethod)) {
                throw new ExportException(Label.Connect_AccountingExport_ErrorPaymentMethod);
            }
            methods = new Set<String>{ paymentMethod };
        }

        Builder builder = new Builder();
        AccountingExportSelector.read(fromDate, toDate, fundId, methods, STATUSES, builder);
        if (builder.overLimit) {
            throw new ExportException(Label.Connect_AccountingExport_ErrorTooManyRows);
        }
        return builder.finish();
    }

    /** Collects rows into the file as the selector reads them. */
    private class Builder implements AccountingExportSelector.RowSink {
        private List<String> lines = new List<String>{ String.join(HEADER, ',') };
        private Set<Id> gifts = new Set<Id>();
        private ExportFile result = new ExportFile();
        public Boolean overLimit = false;

        public Boolean allocation(Gift_Allocation__c row) {
            Gift__c gift = row.Gift__r;
            return add(
                row.Gift__c,
                gift,
                row.Fund__r == null ? null : row.Fund__r.Name,
                row.Fund__r == null ? null : row.Fund__r.Accounting_Code__c,
                row.Amount__c
            );
        }

        public Boolean unallocatedGift(Gift__c gift) {
            return add(gift.Id, gift, null, null, gift.Amount__c);
        }

        private Boolean add(Id giftId, Gift__c gift, String fund, String code, Decimal amount) {
            if (result.rowCount >= maxRows) {
                overLimit = true;
                return false;
            }
            Decimal value = amount == null ? 0 : amount.setScale(2);
            lines.add(
                String.join(
                    new List<String>{
                        String.valueOf(gift.Gift_Date__c),
                        text(gift.Name),
                        text(gift.Original_Gift__r == null ? null : gift.Original_Gift__r.Name),
                        text(donorName(gift)),
                        text(fund),
                        text(code),
                        text(gift.Type__c),
                        text(gift.Payment_Reference__c),
                        value.toPlainString()
                    },
                    ','
                )
            );
            result.rowCount++;
            result.total += value;
            gifts.add(giftId);
            return true;
        }

        public ExportFile finish() {
            result.giftCount = gifts.size();
            if (result.rowCount > 0) {
                result.csv = String.join(lines, LINE_END) + LINE_END;
            }
            return result;
        }
    }

    private static String donorName(Gift__c gift) {
        if (gift.Donor_Contact__r != null) {
            return gift.Donor_Contact__r.Name;
        }
        return gift.Donor_Account__r == null ? null : gift.Donor_Account__r.Name;
    }

    /**
     * One text cell. A value a spreadsheet would read as a formula is prefixed with an
     * apostrophe, because donor names and references can arrive from outside (the inbound gift
     * API), and a cell starting with = runs when the file is opened. Then quoted as RFC 4180
     * says when it holds a comma, a quote or a line break.
     */
    @TestVisible
    private static String text(String value) {
        if (String.isEmpty(value)) {
            return '';
        }
        String cell = FORMULA_STARTS.contains(value.left(1)) ? '\'' + value : value;
        if (
            cell.contains(',') ||
            cell.contains('"') ||
            cell.contains('\n') ||
            cell.contains('\r')
        ) {
            cell = '"' + cell.replace('"', '""') + '"';
        }
        return cell;
    }
}
