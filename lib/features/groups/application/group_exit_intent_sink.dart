import 'package:flutter_app/features/groups/application/group_exit_intent_coordinator.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_intent.dart';

typedef RequestGroupExitIntent =
    Future<GroupExitIntentRequestResult> Function(String groupId);
typedef CancelQueuedGroupExitIntent =
    Future<GroupExitIntentCancelResult> Function(String groupId);
typedef LoadGroupExitIntent = Future<GroupExitIntent?> Function(String groupId);
typedef LoadAllGroupExitIntents = Future<List<GroupExitIntent>> Function();
typedef LoadCurrentGroupExitIdentityPeerId = Future<String?> Function();
typedef CanRejoinForExitIntent = Future<bool> Function(String groupId);
typedef ProcessExistingGroupExitIntent = Future<void> Function(String groupId);

enum GroupExitIntentLookupStatus { available, unavailable }

class GroupExitIntentLookupResult {
  const GroupExitIntentLookupResult.available(this.intent)
    : status = GroupExitIntentLookupStatus.available,
      cause = null;

  const GroupExitIntentLookupResult.unavailable([this.cause])
    : status = GroupExitIntentLookupStatus.unavailable,
      intent = null;

  final GroupExitIntentLookupStatus status;
  final GroupExitIntent? intent;
  final Object? cause;

  bool get isAvailable => status == GroupExitIntentLookupStatus.available;
}

class GroupExitIntentListLookupResult {
  const GroupExitIntentListLookupResult.available(this.intents)
    : status = GroupExitIntentLookupStatus.available,
      cause = null;

  const GroupExitIntentListLookupResult.unavailable([this.cause])
    : status = GroupExitIntentLookupStatus.unavailable,
      intents = const <GroupExitIntent>[];

  final GroupExitIntentLookupStatus status;
  final List<GroupExitIntent> intents;
  final Object? cause;

  bool get isAvailable => status == GroupExitIntentLookupStatus.available;
}

RequestGroupExitIntent? _requestLeave;
RequestGroupExitIntent? _queueLeaveWhenSyncCompletes;
RequestGroupExitIntent? _retry;
CancelQueuedGroupExitIntent? _cancelQueued;
LoadGroupExitIntent? _loadForGroup;
LoadAllGroupExitIntents? _loadAll;
CanRejoinForExitIntent? _canRejoin;
ProcessExistingGroupExitIntent? _processExisting;

/// Installs the process-wide presentation triggers backed by the concrete
/// [GroupExitIntentCoordinator]. Omitting any trigger keeps that action
/// fail-closed with a typed `unavailable` result.
void setGroupExitIntentActionSinks({
  RequestGroupExitIntent? requestLeave,
  RequestGroupExitIntent? queueLeaveWhenSyncCompletes,
  RequestGroupExitIntent? retry,
  CancelQueuedGroupExitIntent? cancelQueued,
}) {
  _requestLeave = requestLeave;
  _queueLeaveWhenSyncCompletes = queueLeaveWhenSyncCompletes;
  _retry = retry;
  _cancelQueued = cancelQueued;
}

/// Installs read-only presentation projections backed by the concrete durable
/// repository. An unavailable lookup is never represented as an absent intent.
void setGroupExitIntentAccessSinks({
  LoadGroupExitIntent? forGroup,
  LoadAllGroupExitIntents? all,
}) {
  _loadForGroup = forGroup;
  _loadAll = all;
}

bool get hasGroupExitIntentAccessSink =>
    _loadForGroup != null && _loadAll != null;

/// Installs the runtime continuation hooks used by rejoin recovery. Missing or
/// throwing authorization is fail-closed. Processing is additionally guarded
/// by the durable lookup below, so it never creates an intent when none exists.
void setGroupExitIntentRuntimeSinks({
  CanRejoinForExitIntent? canRejoin,
  ProcessExistingGroupExitIntent? processExisting,
}) {
  _canRejoin = canRejoin;
  _processExisting = processExisting;
}

/// Authorizes topic rejoin only for the account that owns durable exit work.
///
/// Early exit phases may still rejoin long enough to finish their signed
/// notice. A switched or unavailable account must not inherit that authority,
/// and every storage/identity error therefore fails closed.
Future<bool> authorizeGroupRejoinForExitIntent({
  required String groupId,
  required LoadGroupExitIntent loadIntent,
  required LoadCurrentGroupExitIdentityPeerId loadCurrentSelfPeerId,
}) async {
  try {
    final intent = await loadIntent(groupId);
    if (intent == null) return true;
    final currentSelfPeerId = (await loadCurrentSelfPeerId())?.trim();
    return currentSelfPeerId != null &&
        currentSelfPeerId.isNotEmpty &&
        currentSelfPeerId == intent.selfPeerId &&
        !intent.preventsRejoin;
  } catch (_) {
    return false;
  }
}

Future<GroupExitIntentRequestResult> requestGroupExitIntentLeave(
  String groupId,
) => _runRequest(_requestLeave, groupId, action: 'requestLeave');

Future<GroupExitIntentRequestResult> queueGroupExitIntentLeaveWhenSyncCompletes(
  String groupId,
) => _runRequest(
  _queueLeaveWhenSyncCompletes,
  groupId,
  action: 'queueLeaveWhenSyncCompletes',
);

Future<GroupExitIntentRequestResult> retryGroupExitIntentLeave(
  String groupId,
) => _runRequest(_retry, groupId, action: 'retry');

Future<GroupExitIntentCancelResult> cancelQueuedGroupExitIntent(
  String groupId,
) async {
  final action = _cancelQueued;
  if (action == null) {
    return GroupExitIntentCancelResult(
      status: GroupExitIntentCancelStatus.unavailable,
      cause: StateError('Group exit action "cancelQueued" is unavailable.'),
    );
  }
  try {
    return await action(groupId);
  } catch (error) {
    return GroupExitIntentCancelResult(
      status: GroupExitIntentCancelStatus.unavailable,
      cause: error,
    );
  }
}

Future<GroupExitIntentLookupResult> loadGroupExitIntent(String groupId) async {
  final load = _loadForGroup;
  if (load == null) {
    return GroupExitIntentLookupResult.unavailable(
      StateError('Group exit intent lookup is unavailable.'),
    );
  }
  try {
    return GroupExitIntentLookupResult.available(await load(groupId));
  } catch (error) {
    return GroupExitIntentLookupResult.unavailable(error);
  }
}

Future<GroupExitIntentListLookupResult> loadAllGroupExitIntents() async {
  final load = _loadAll;
  if (load == null) {
    return GroupExitIntentListLookupResult.unavailable(
      StateError('Group exit intent list lookup is unavailable.'),
    );
  }
  try {
    return GroupExitIntentListLookupResult.available(
      List<GroupExitIntent>.unmodifiable(await load()),
    );
  } catch (error) {
    return GroupExitIntentListLookupResult.unavailable(error);
  }
}

Future<bool> canRejoinForExitIntent(String groupId) async {
  final authorize = _canRejoin;
  if (authorize == null) return false;
  try {
    return await authorize(groupId);
  } catch (_) {
    return false;
  }
}

Future<void> processExistingGroupExitIntent(String groupId) async {
  final lookup = await loadGroupExitIntent(groupId);
  if (!lookup.isAvailable) {
    throw StateError('Group exit intent lookup is unavailable.');
  }
  if (lookup.intent == null) return;

  final process = _processExisting;
  if (process == null) {
    throw StateError('Group exit intent processing is unavailable.');
  }
  await process(groupId);
}

Future<GroupExitIntentRequestResult> _runRequest(
  RequestGroupExitIntent? trigger,
  String groupId, {
  required String action,
}) async {
  if (trigger == null) {
    return GroupExitIntentRequestResult(
      status: GroupExitIntentRequestStatus.unavailable,
      cause: StateError('Group exit action "$action" is unavailable.'),
    );
  }
  try {
    return await trigger(groupId);
  } catch (error) {
    return GroupExitIntentRequestResult(
      status: GroupExitIntentRequestStatus.unavailable,
      cause: error,
    );
  }
}
