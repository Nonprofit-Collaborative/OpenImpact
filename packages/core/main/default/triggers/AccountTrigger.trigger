trigger AccountTrigger on Account(
    before insert,
    before update,
    after insert,
    after update,
    after delete,
    after undelete
) {
    TriggerDispatcher.run('Account');
}
