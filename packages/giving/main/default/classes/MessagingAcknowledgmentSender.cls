/**
 * The shipped sender: one `Messaging.sendEmail` call for the whole chunk, not one per message.
 *
 * That is not a micro optimization. Apex allows ten email invocations per transaction, so a chunk
 * that sent one message at a time would stop after ten thank yous. Passing the list and asking
 * for partial success gets the whole chunk out in one invocation and gives back a result per
 * message, which is exactly what R-AK10 needs: the failures are named and the rest still went.
 */
public with sharing class MessagingAcknowledgmentSender implements AcknowledgmentSender {
    public List<AcknowledgmentSendOutcome> send(List<Messaging.SingleEmailMessage> messages) {
        List<AcknowledgmentSendOutcome> outcomes = new List<AcknowledgmentSendOutcome>();
        if (messages == null || messages.isEmpty()) {
            return outcomes;
        }
        List<Messaging.SendEmailResult> results = Messaging.sendEmail(messages, false);
        for (Messaging.SendEmailResult result : results) {
            if (result.isSuccess()) {
                outcomes.add(AcknowledgmentSendOutcome.succeeded());
            } else {
                outcomes.add(AcknowledgmentSendOutcome.failed(firstErrorOf(result)));
            }
        }
        return outcomes;
    }

    /**
     * The first error the platform gave, trimmed to what fits on the record. The rest of the
     * detail is in the Error Log entry the caller writes; this is the sentence a person reads on
     * the acknowledgment itself.
     */
    private static String firstErrorOf(Messaging.SendEmailResult result) {
        List<Messaging.SendEmailError> errors = result.getErrors();
        if (errors == null || errors.isEmpty()) {
            return Label.Giving_Acknowledgment_SendFailedUnknown;
        }
        String message = errors[0].getMessage();
        if (String.isBlank(message)) {
            return Label.Giving_Acknowledgment_SendFailedUnknown;
        }
        return message.length() > 255 ? message.substring(0, 255) : message;
    }
}
