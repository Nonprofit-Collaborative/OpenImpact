/**
 * The one seam between the acknowledgment feature and the platform's email service.
 *
 * It exists for the same reason `ReceiptRenderer` exists: so that everything above it can be
 * tested for what it composed and what it recorded, without any of those tests depending on
 * whether an org can send mail. There is one shipped implementation,
 * `MessagingAcknowledgmentSender`.
 */
public interface AcknowledgmentSender {
    /**
     * Sends the messages and reports one outcome per message, in the same order.
     *
     * The contract is deliberately all-of-them-or-as-many-as-possible rather than all or nothing:
     * one address that bounces must not stop the other ninety nine thank yous going out
     * (R-AK10).
     */
    List<AcknowledgmentSendOutcome> send(List<Messaging.SingleEmailMessage> messages);
}
