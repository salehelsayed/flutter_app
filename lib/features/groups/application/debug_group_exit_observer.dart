import 'package:flutter/foundation.dart';

/// Receives one step of a voluntary group exit: `request_leave`,
/// `request_queue` or `request_retry` (the coordinator's status and the exit
/// intent ids), then the durable runner's `notice_prepare`, `notice_attempt`,
/// `rotation_attempt`, `rotation_result` (with `deferred`) and
/// `native_leave`.
typedef GroupExitDebugObserver =
    void Function(String step, String groupId, Map<String, Object?> details);

GroupExitDebugObserver? _observer;

/// Debug-build-only seam for production journeys whose original proof reads
/// the durable exit evidence of a leave (catalog H-01, GM-015). It is only
/// readable and settable in debug builds, so release and profile builds never
/// observe exits.
GroupExitDebugObserver? get debugGroupExitObserver =>
    kDebugMode ? _observer : null;

set debugGroupExitObserver(GroupExitDebugObserver? observer) {
  if (!kDebugMode) {
    throw StateError('group exit observer is debug-only');
  }
  _observer = observer;
}

/// Reports one exit step to the debug observer, if any. An observer never
/// affects the exit.
void notifyGroupExitDebugObserver(
  String step,
  String groupId,
  Map<String, Object?> details,
) {
  final observer = debugGroupExitObserver;
  if (observer == null) return;
  try {
    observer(step, groupId, details);
  } catch (_) {}
}
