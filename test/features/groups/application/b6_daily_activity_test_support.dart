import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/diagnostics/active_identity_reporter.dart';
import 'package:flutter_app/core/config/direct_linked_devices_flag.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';

const b6Budget = Duration(seconds: 2);
const b6Binding =
    'v1:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const b6OtherBinding =
    'v1:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

typedef B6CapturedActivity = ({
  ActiveIdentityReporter? reporter,
  ActiveIdentityReporterCapture? capture,
});

Future<T> b6Bound<T>(Future<T> future) => future.timeout(b6Budget);

/// Exercise the existing producer on the pre-hook RED revision too. Only a
/// synchronous missing named argument falls back; async producer failures are
/// deliberately outside the catch and are never converted into admission.
Future<T> b6Invoke<T>(
  Function producer,
  Map<Symbol, dynamic> arguments, {
  required ActiveIdentityReporter reporter,
  B6CapturedActivity? capturedActivity,
  bool? preassignedMessageIdIsFresh,
}) {
  Object? result;
  try {
    result = Function.apply(producer, const [], {
      ...arguments,
      #activityReporter: reporter,
      #capturedActivity: capturedActivity,
      if (preassignedMessageIdIsFresh != null)
        #preassignedMessageIdIsFresh: preassignedMessageIdIsFresh,
    });
  } on NoSuchMethodError {
    result = Function.apply(producer, const [], arguments);
  }
  return b6Bound(result as Future<T>);
}

class B6ActivityBridge extends FakeBridge {
  final requests = <Map<String, dynamic>>[];
  final markStarted = Completer<void>();
  Future<String> Function(Map<String, dynamic>, int)? activityAnswer;
  void Function()? onMark;
  int _revision = 0;

  @override
  bool get isInitialized => true;

  List<Map<String, dynamic>> get marks =>
      requests.where((request) => request['op'] == 'mark').toList();

  static String reply(Map<String, dynamic> request, int revision) =>
      jsonEncode({
        'ok': true,
        'data': {
          'revision': revision,
          'consentEpoch': request['consentEpoch'],
          if (request['op'] == 'configure')
            'configured':
                request['enabled'] == true && request['profileBinding'] != '',
          if (request['op'] == 'mark') 'accepted': true,
          if (request['op'] == 'flush') 'queued': true,
        },
      });

  @override
  Future<String> send(String message) async {
    final envelope = jsonDecode(message) as Map<String, dynamic>;
    if (envelope['cmd'] != 'active_identity_reporter_v1') {
      return super.send(message);
    }
    final request = Map<String, dynamic>.from(envelope['payload'] as Map);
    requests.add(request);
    final revision = request['op'] == 'configure'
        ? ++_revision
        : request['revision'] as int;
    if (request['op'] == 'mark') {
      onMark?.call();
      if (!markStarted.isCompleted) markStarted.complete();
    }
    final answer = activityAnswer;
    if (answer != null) return answer(request, revision);
    return reply(request, revision);
  }
}

Future<ActiveIdentityReporter> b6Reporter(B6ActivityBridge bridge) async {
  final reporter = ActiveIdentityReporter(
    statePath: '/unused/b6-public-fixture.json',
  );
  reporter.attachBridge(bridge);
  reporter.observeIdentity(
    accountPeerId: 'peer-1',
    rootPrivateKeyBase64: base64Encode(List<int>.filled(64, 17)),
    profileBinding: b6Binding,
  );
  await b6Bound(reporter.observeConsent((enabled: true, consentEpoch: 7)));
  return reporter;
}

class B6FirstReadGroupRepository extends InMemoryGroupRepository {
  final entered = Completer<void>();
  final release = Completer<void>();
  bool armed = false;

  @override
  Future<GroupModel?> getGroup(String id) async {
    if (armed) {
      armed = false;
      entered.complete();
      await b6Bound(release.future);
    }
    return super.getGroup(id);
  }
}

Future<GroupContentAuthoringContext> b6StrictContext(
  GroupRepository repository,
  AckOrExpiryInboxStore store, {
  bool remote = true,
}) async {
  for (final peer in ['peer-1', if (remote) 'peer-2']) {
    await b6Bound(
      repository.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: peer,
          role: peer == 'peer-1' ? MemberRole.admin : MemberRole.writer,
          publicKey: peer == 'peer-1' ? 'pk-1' : 'pk-2',
          devices: [
            GroupMemberDeviceIdentity(
              deviceId: peer == 'peer-1' ? 'b6-current' : 'b6-remote',
              transportPeerId: peer == 'peer-1' ? 'b6-current' : 'b6-remote',
              deviceSigningPublicKey: peer == 'peer-1'
                  ? 'b6-current-pk'
                  : 'b6-remote-pk',
            ),
          ],
          joinedAt: DateTime.utc(2026, 8, 1),
        ),
      ),
    );
  }
  await b6Bound(
    repository.saveKey(
      GroupKeyInfo(
        groupId: 'group-1',
        keyGeneration: 1,
        encryptedKey: 'b6-public-group-key',
        createdAt: DateTime.now().toUtc(),
      ),
    ),
  );
  return GroupContentAuthoringContext(
    directLinkedDeviceSelector: const DirectLinkedDeviceSelector.enabled(),
    multiDeviceSyncEnabled: true,
    authorityVersion: GroupContentAuthorityVersion(
      eventAt: DateTime.utc(2026, 8, 1),
      eventId: 'b6-public-authority',
      keyEpoch: 1,
    ),
    inboxStore: store,
  );
}
