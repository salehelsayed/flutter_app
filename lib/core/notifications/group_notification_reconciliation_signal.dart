import 'dart:async';

final StreamController<String> _groupNotificationReconciliationController =
    StreamController<String>.broadcast(sync: true);

/// Process-local wake signal for durable canonical reconciliation custody.
///
/// SQL owns restart safety. This stream only removes latency after a mutation
/// in the current isolate; a missed/background-isolate signal is recovered by
/// the durable startup/resume drain.
Stream<String> get groupNotificationReconciliationSignals =>
    _groupNotificationReconciliationController.stream;

void emitGroupNotificationReconciliationSignal(String rawGroupId) {
  final groupId = rawGroupId.trim();
  if (groupId.isEmpty) return;
  _groupNotificationReconciliationController.add(groupId);
}
