trigger ContactTrigger on Contact(
    before insert,
    before update,
    after insert,
    after update,
    after delete,
    after undelete
) {
    TriggerDispatcher.run(new ContactTriggerHandler());
}
