/**
 * Jest stub for the lightning/actions module, which sfdx-lwc-jest does not ship a stub for.
 * A quick action screen closes itself by firing this event, and a test asserts it was fired.
 */
export class CloseActionScreenEvent extends CustomEvent {
  constructor() {
    super('lightning__closeactionscreen', { bubbles: true, composed: true });
  }
}
