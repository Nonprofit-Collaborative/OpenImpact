/**
 * The class Core finds by name (registered in its catalog row) to add Mirror for Giving's steps
 * to the one nightly run (ADR-0166 nightly-job-dispatcher): the nightly run of the Opportunity
 * mirror and of the Gift Transaction mirror (X-07). Each step is in tonight's run only while that
 * mirror's direction is chosen and its object exists, and its page switches it on and off.
 *
 * `@NamespaceAccessible` for the reason `MirrorGivingHealthCheckExtension` is: Core resolves it
 * with `Type.forName` under ADR-0017.
 */
@NamespaceAccessible
public with sharing class MirrorGivingNightlyJobProvider implements NightlyStepProvider {
	@NamespaceAccessible
	public MirrorGivingNightlyJobProvider() {
		return;
	}

	public List<NightlyStep> nightlySteps() {
		return new List<NightlyStep>{
			OpportunityMirrorSchedulable.step(),
			GiftTransactionMirrorSchedulable.step()
		};
	}
}
