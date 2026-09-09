/**
 * Test data and a stand-in sender for the acknowledgment tests (feature G-12).
 *
 * The sender matters more than the data. Apex tests do not send mail, and
 * `Messaging.SendEmailResult` cannot be constructed, so a test that wanted to prove what the
 * feature recorded after a partial failure could not do it against the platform. It does it
 * against this instead, which is why `AcknowledgmentSender` exists at all (ADR-0029).
 */
@IsTest
public class AcknowledgmentTestData {
    /** A sender that records what it was given and answers however the test told it to. */
    public class RecordingSender implements AcknowledgmentSender {
        public List<Messaging.SingleEmailMessage> received = new List<Messaging.SingleEmailMessage>();
        public Set<Integer> failAt = new Set<Integer>();
        public String failureReason = 'The address bounced.';

        public List<AcknowledgmentSendOutcome> send(List<Messaging.SingleEmailMessage> messages) {
            received.addAll(messages);
            List<AcknowledgmentSendOutcome> outcomes = new List<AcknowledgmentSendOutcome>();
            for (Integer index = 0; index < messages.size(); index++) {
                outcomes.add(
                    failAt.contains(index)
                        ? AcknowledgmentSendOutcome.failed(failureReason)
                        : AcknowledgmentSendOutcome.succeeded()
                );
            }
            return outcomes;
        }
    }

    /** Turns the feature on and grants the send permission for the length of the test. */
    public static void enable() {
        Giving_Settings__c settings = Giving_Settings__c.getOrgDefaults();
        settings.SetupOwnerId = UserInfo.getOrganizationId();
        settings.Acknowledgments_Enabled__c = true;
        upsert settings;
        AcknowledgmentService.sendPermission = true;
    }

    /** A rule, ready to insert. Pass nulls for the criteria this rule does not care about. */
    public static Acknowledgment_Rule__c buildRule(
        String name,
        Integer order,
        String channel,
        String template
    ) {
        return new Acknowledgment_Rule__c(
            Name = name,
            Order__c = order,
            Channel__c = channel,
            Email_Template__c = template,
            Active__c = true,
            First_Gift_Only__c = false
        );
    }

    /** A contact with an email address, in their own household. */
    public static Contact insertDonor(String firstName, String lastName, String email) {
        Account household = new Account(Name = lastName + ' Household');
        insert household;
        Contact person = new Contact(
            FirstName = firstName,
            LastName = lastName,
            AccountId = household.Id,
            Email = email
        );
        insert person;
        return person;
    }
}
