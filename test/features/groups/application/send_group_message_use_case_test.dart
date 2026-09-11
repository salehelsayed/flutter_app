import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/config/direct_linked_devices_flag.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';

import 'package:flutter_app/features/groups/application/add_group_member_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/application/group_membership_timeline_message.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/remove_group_member_use_case.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/application/retry_failed_group_inbox_stores_use_case.dart';
import 'package:flutter_app/features/groups/application/protected_group_authority.dart';
import 'package:flutter_app/features/groups/application/protected_group_content_reconciliation.dart';
import 'package:flutter_app/features/groups/application/protected_group_content_authoring_resolver.dart';
import 'package:flutter_app/features/groups/application/protected_group_media_manifest.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_delivery_attempt.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_membership_limit_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_message_receipt.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';

const _validContentHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

final _uuidV4Pattern = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

Future<List<Map<String, dynamic>>> captureFlowEvents(
  Future<void> Function() action,
) async {
  final printed = <String>[];
  final previousLogging = flowEventLoggingEnabled;
  final originalDebugPrint = debugPrint;
  flowEventLoggingEnabled = true;
  debugPrint = (String? message, {int? wrapWidth}) {
    if (message != null) {
      printed.add(message);
    }
  };
  try {
    await action();
  } finally {
    debugPrint = originalDebugPrint;
    flowEventLoggingEnabled = previousLogging;
  }

  return printed
      .where((line) => line.startsWith('[FLOW] '))
      .map(
        (line) =>
            jsonDecode(line.substring('[FLOW] '.length))
                as Map<String, dynamic>,
      )
      .toList();
}

/// A bridge that delays group:publish by [delay] to test concurrency.
class _SlowPublishBridge extends FakeBridge {
  final Duration delay;
  _SlowPublishBridge({this.delay = const Duration(milliseconds: 200)});

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    if (cmd == 'group:publish') {
      await Future<void>.delayed(delay);
    }

    return super.send(message);
  }
}

/// Sizes the canonical relay envelope with production wire-length crypto.
///
/// Group ciphertext is standard-base64 AES-256-GCM (plaintext plus a 16-byte
/// tag), the nonce is 12 bytes, and an Ed25519 signature is 64 bytes. The
/// payload contents are irrelevant to this frame-boundary proof, but their
/// encoded lengths must not be shortened by the general-purpose fake bridge.
class _RelayFrameSizingBridge extends FakeBridge {
  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    final payload = parsed['payload'] as Map<String, dynamic>?;
    if (cmd == 'group.encrypt') {
      final plaintext = payload!['plaintext']! as String;
      return jsonEncode(<String, Object?>{
        'ok': true,
        'ciphertext': base64Encode(<int>[
          ...utf8.encode(plaintext),
          ...List<int>.filled(16, 0),
        ]),
        'nonce': base64Encode(List<int>.filled(12, 0)),
      });
    }
    if (cmd == 'payload.sign') {
      return jsonEncode(<String, Object?>{
        'ok': true,
        'signature': base64Encode(List<int>.filled(64, 0)),
      });
    }
    return super.send(message);
  }
}

/// A bridge that blocks group:publish until [publishGate] completes.
class _GatedPublishBridge extends FakeBridge {
  final Completer<void> publishGate = Completer<void>();
  final Completer<void> publishStarted = Completer<void>();

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    if (cmd == 'group:publish') {
      if (!publishStarted.isCompleted) {
        publishStarted.complete();
      }
      await publishGate.future;
    }

    return super.send(message);
  }
}

/// A bridge that returns ok: false for group:publish but tracks all commands.
class _FailPublishBridge extends FakeBridge {
  _FailPublishBridge() {
    responses['group:publish'] = {'ok': false, 'errorCode': 'PUBLISH_FAILED'};
  }
}

/// A bridge that throws on group:inboxStore commands.
class _InboxStoreFailBridge extends FakeBridge {
  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    if (cmd == 'group:inboxStore') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);
      throw Exception('Relay inbox store failed');
    }

    return super.send(message);
  }
}

/// A bridge that fails the first N group:inboxStore commands and then succeeds.
class _FailFirstNInboxStoreBridge extends _InboxStoreFailBridge {
  _FailFirstNInboxStoreBridge({required int failCount})
    : _failuresRemaining = failCount;

  int _failuresRemaining;

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    if (cmd == 'group:inboxStore') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);
      if (_failuresRemaining > 0) {
        _failuresRemaining--;
        throw Exception('Relay inbox store failed');
      }
      return jsonEncode({'ok': true});
    }

    return super.send(message);
  }
}

class _SlowPublishInboxStoreFailBridge extends _InboxStoreFailBridge {
  static const _publishDelay = Duration(milliseconds: 20);

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'group:publish') {
      await Future<void>.delayed(_publishDelay);
    }
    return super.send(message);
  }
}

String _opaqueReplayCiphertext(String plaintext) =>
    'sealed:${sha256.convert(utf8.encode(plaintext))}';

/// A bridge that keeps group replay encryption opaque while allowing durable
/// inbox custody to succeed so relay-visible payloads can be inspected.
class _OpaqueReplayBridge extends FakeBridge {
  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    if (cmd == 'group.encrypt') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);

      final payload = parsed['payload'] as Map<String, dynamic>;
      final plaintext = payload['plaintext'] as String? ?? '';
      return jsonEncode({
        'ok': true,
        'ciphertext': _opaqueReplayCiphertext(plaintext),
        'nonce': 'opaque-replay-nonce',
      });
    }

    return super.send(message);
  }
}

/// A bridge that keeps group replay encryption opaque while forcing durable
/// inbox custody to fail so the retry payload remains persisted for inspection.
class _OpaqueReplayInboxStoreFailBridge extends _InboxStoreFailBridge {
  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    if (cmd == 'group.encrypt') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);

      final payload = parsed['payload'] as Map<String, dynamic>;
      final plaintext = payload['plaintext'] as String? ?? '';
      return jsonEncode({
        'ok': true,
        'ciphertext': _opaqueReplayCiphertext(plaintext),
        'nonce': 'opaque-replay-nonce',
      });
    }

    return super.send(message);
  }
}

/// A bridge that returns ok:false on group:inboxStore.
class _InboxStoreOkFalseBridge extends FakeBridge {
  _InboxStoreOkFalseBridge() {
    responses['group:inboxStore'] = {
      'ok': false,
      'errorCode': 'INBOX_STORE_FAILED',
    };
  }
}

class _GatedInboxStoreBridge extends FakeBridge {
  final Completer<void> inboxGate = Completer<void>();

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    if (cmd == 'group:inboxStore') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);
      await inboxGate.future;
      return jsonEncode({'ok': true});
    }

    return super.send(message);
  }
}

class _GatedReplayCryptoBridge extends FakeBridge {
  final Completer<void> cryptoEntered = Completer<void>();
  final Completer<void> releaseCrypto = Completer<void>();

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    if (parsed['cmd'] == 'group.encrypt') {
      if (!cryptoEntered.isCompleted) cryptoEntered.complete();
      await releaseCrypto.future;
    }
    return super.send(message);
  }
}

class _DelayedGroupRepository extends InMemoryGroupRepository {
  static const _latestKeyDelay = Duration(milliseconds: 100);
  static const _membersDelay = Duration(milliseconds: 100);

  @override
  Future<GroupKeyInfo?> getLatestKey(String groupId) async {
    await Future<void>.delayed(_latestKeyDelay);
    return super.getLatestKey(groupId);
  }

  @override
  Future<List<GroupMember>> getMembers(String groupId) async {
    await Future<void>.delayed(_membersDelay);
    return super.getMembers(groupId);
  }
}

class _SaveTrackingGroupMessageRepository
    extends InMemoryGroupMessageRepository {
  final Completer<GroupMessage> firstSave = Completer<GroupMessage>();
  final List<GroupMessage> savedMessages = [];

  @override
  Future<void> saveMessage(GroupMessage message) async {
    savedMessages.add(message);
    if (!firstSave.isCompleted) {
      firstSave.complete(message);
    }
    await super.saveMessage(message);
  }
}

class _OrderedGroupMessageRepository extends InMemoryGroupMessageRepository {
  _OrderedGroupMessageRepository(this.operations);

  final List<String> operations;

  @override
  Future<void> saveMessage(GroupMessage message) async {
    operations.add('message:${message.id}:${message.status}');
    await super.saveMessage(message);
  }
}

class _OrderedMediaAttachmentRepository
    extends InMemoryMediaAttachmentRepository {
  _OrderedMediaAttachmentRepository(this.operations);

  final List<String> operations;

  @override
  Future<void> saveAttachment(
    MediaAttachment attachment, {
    required MediaOwnerLane owner,
  }) async {
    operations.add('attachment:${attachment.id}:${attachment.messageId}');
    await super.saveAttachment(attachment, owner: owner);
  }
}

class _FailingNthMediaAttachmentRepository
    extends InMemoryMediaAttachmentRepository {
  _FailingNthMediaAttachmentRepository(this.failAt);

  final int failAt;
  int _saveCount = 0;

  @override
  Future<void> saveAttachment(
    MediaAttachment attachment, {
    required MediaOwnerLane owner,
  }) async {
    _saveCount++;
    if (_saveCount == failAt) {
      throw StateError('injected attachment persistence failure');
    }
    await super.saveAttachment(attachment, owner: owner);
  }
}

class _MissingDurableMediaAttachmentRepository
    extends InMemoryMediaAttachmentRepository {
  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async => const [];
}

class _ThrowingSaveGroupMessageRepository
    extends InMemoryGroupMessageRepository {
  @override
  Future<void> saveMessage(GroupMessage message) async {
    throw StateError('injected parent persistence failure');
  }
}

class _SilentSaveGroupMessageRepository extends InMemoryGroupMessageRepository {
  Future<void> seedMessage(GroupMessage message) => super.saveMessage(message);

  @override
  Future<void> saveMessage(GroupMessage message) async {}
}

class _StrictContentMessageRepository extends InMemoryGroupMessageRepository
    implements
        GroupInboxStoreRetryPayloadCasRepository,
        GroupMessageStrictContentCompletionRepository,
        GroupMessageStrictLocalTerminalRepository,
        GroupMessageStrictPreparedRepository {
  String? initiallyPersistedRetryPayload;
  final List<Map<String, Object?>> protectedEvidence = [];

  @override
  Future<void> saveMessage(GroupMessage message) async {
    initiallyPersistedRetryPayload ??= message.inboxRetryPayload;
    await super.saveMessage(message);
  }

  @override
  Future<bool> replaceInboxRetryPayloadIfExact(
    GroupMessage expected,
    String replacement,
  ) async {
    final current = await getMessage(expected.id);
    if (current == null ||
        current.inboxRetryPayload != expected.inboxRetryPayload ||
        current.status != expected.status ||
        current.inboxStored != expected.inboxStored) {
      return false;
    }
    await saveMessage(current.copyWith(inboxRetryPayload: replacement));
    return true;
  }

  @override
  Future<bool> completeStrictContentIfExact(
    GroupMessage expected, {
    required String sourcePeerId,
    required String sourceEventId,
    required String sourceTimestamp,
    required Map<String, Object?> eventPayload,
  }) async {
    final current = await getMessage(expected.id);
    if (current == null ||
        current.inboxRetryPayload != expected.inboxRetryPayload ||
        current.status != expected.status ||
        current.inboxStored != expected.inboxStored) {
      return false;
    }
    protectedEvidence.add(<String, Object?>{
      'sourcePeerId': sourcePeerId,
      'sourceEventId': sourceEventId,
      'sourceTimestamp': sourceTimestamp,
      'eventPayload': eventPayload,
    });
    await saveMessage(
      current.copyWith(
        status: 'sent',
        inboxStored: true,
        inboxRetryPayload: null,
        wireEnvelope: null,
      ),
    );
    return true;
  }

  @override
  Future<bool> stageAndCompleteStrictLocalContent(
    GroupMessage message, {
    required String sourcePeerId,
    required String sourceEventId,
    required String sourceTimestamp,
    required Map<String, Object?> eventPayload,
  }) async {
    if (await getMessage(message.id) != null) return false;
    protectedEvidence.add(<String, Object?>{
      'sourcePeerId': sourcePeerId,
      'sourceEventId': sourceEventId,
      'sourceTimestamp': sourceTimestamp,
      'eventPayload': eventPayload,
    });
    await saveMessage(
      message.copyWith(
        status: 'sent',
        inboxStored: true,
        inboxRetryPayload: null,
        wireEnvelope: null,
      ),
    );
    return true;
  }

  @override
  Future<bool> stageStrictContentPrepared(
    GroupMessage message, {
    required String sourcePeerId,
    required String sourceEventId,
    required String sourceTimestamp,
    required Map<String, Object?> preparedEventPayload,
  }) async {
    if (await getMessage(message.id) != null) return false;
    protectedEvidence.add(<String, Object?>{
      'sourcePeerId': sourcePeerId,
      'sourceEventId': sourceEventId,
      'sourceTimestamp': sourceTimestamp,
      'eventPayload': preparedEventPayload,
    });
    await saveMessage(message);
    return true;
  }
}

class _PreparedReadbackFailureRepository extends _StrictContentMessageRepository
    implements GroupMessageStrictPreparedTerminalRepository {
  bool throwNextReadbackAfterPrepared = true;

  @override
  Future<GroupMessage?> getMessage(String id) async {
    if (throwNextReadbackAfterPrepared &&
        protectedEvidence.any(
          (row) =>
              (row['sourceEventId'] as String?)?.startsWith('ppm1:') == true,
        )) {
      throwNextReadbackAfterPrepared = false;
      throw StateError('injected prepared owner readback failure');
    }
    return super.getMessage(id);
  }

  @override
  Future<bool> hasExactStrictContentPrepared(
    GroupMessage expected, {
    required Map<String, Object?> eventPayload,
  }) async {
    final current = await getMessage(expected.id);
    return current != null &&
        current.inboxRetryPayload == expected.inboxRetryPayload &&
        protectedEvidence.any(
          (row) =>
              (row['sourceEventId'] as String?)?.startsWith('ppm1:') == true,
        );
  }

  @override
  Future<bool> terminalizeStrictContentPreparedIfExact(
    GroupMessage expected, {
    required Map<String, Object?> preparedEventPayload,
    required String terminalSourcePeerId,
    required String terminalSourceEventId,
    required String terminalSourceTimestamp,
    required Map<String, Object?> terminalEventPayload,
  }) async => false;
}

class _StrictContentInboxStore implements AckOrExpiryInboxStore {
  _StrictContentInboxStore({this.durableCheck});

  final Future<bool> Function()? durableCheck;
  final List<String> recipients = <String>[];
  bool everyStoreObservedDurableRow = true;

  @override
  Future<InboxStoreOutcome> storeInAckCustodyInboxDetailed(
    String toPeerId,
    String message, {
    required AckCustodyKind custodyKind,
    int? timeoutMs,
  }) async {
    expect(custodyKind, AckCustodyKind.groupContentV1);
    final check = durableCheck;
    if (check != null) {
      everyStoreObservedDurableRow =
          everyStoreObservedDurableRow && await check();
    }
    recipients.add(toPeerId);
    return const InboxStoreOutcome(
      status: InboxStoreStatus.stored,
      storeStatus: 'stored',
      custodyContract: ackOrExpiryInboxCustodyContract,
    );
  }
}

class _StrictMediaContentInboxStore extends _StrictContentInboxStore
    implements GroupContentExpiryBoundedInboxStore {
  @override
  Future<InboxStoreOutcome> storeInGroupContentExpiryBoundedInboxDetailed(
    String toPeerId,
    String message, {
    required int custodyExpiresAtOrBeforeMs,
    int? timeoutMs,
  }) async {
    await storeInAckCustodyInboxDetailed(
      toPeerId,
      message,
      custodyKind: AckCustodyKind.groupContentV1,
    );
    return InboxStoreOutcome(
      status: InboxStoreStatus.stored,
      storeStatus: 'stored',
      custodyContract: ackOrExpiryInboxCustodyContract,
      expiresAtMs: custodyExpiresAtOrBeforeMs,
    );
  }
}

class _DriftingStrictGroupRepository extends InMemoryGroupRepository {
  int memberReads = 0;

  @override
  Future<List<GroupMember>> getMembers(String groupId) async {
    final members = await super.getMembers(groupId);
    memberReads++;
    if (memberReads < 2) return members;
    return members
        .where((member) => member.peerId != 'peer-2')
        .toList(growable: false);
  }
}

class _InMemoryInviteDeliveryAttemptRepository
    implements GroupInviteDeliveryAttemptRepository {
  final Map<String, GroupInviteDeliveryAttempt> _attempts = {};

  String _key(String groupId, String peerId) => '$groupId::$peerId';

  @override
  Future<void> saveAttempt(GroupInviteDeliveryAttempt attempt) async {
    _attempts[_key(attempt.groupId, attempt.peerId)] = attempt;
  }

  @override
  Future<GroupInviteDeliveryAttempt?> getAttempt({
    required String groupId,
    required String peerId,
  }) async => _attempts[_key(groupId, peerId)];

  @override
  Future<List<GroupInviteDeliveryAttempt>> getAttemptsForGroup(
    String groupId,
  ) async => _attempts.values
      .where((attempt) => attempt.groupId == groupId)
      .toList(growable: false);

  @override
  Future<GroupInviteDeliveryStatus> getStatusForMember({
    required String groupId,
    required String peerId,
  }) async =>
      _attempts[_key(groupId, peerId)]?.status ??
      GroupInviteDeliveryStatus.unknown;

  @override
  Future<Map<String, GroupInviteDeliveryStatus>> getStatusesForGroupMembers(
    String groupId,
  ) async => {
    for (final attempt in _attempts.values.where(
      (attempt) => attempt.groupId == groupId,
    ))
      attempt.peerId: attempt.status,
  };

  @override
  Future<void> updateStatus({
    required String groupId,
    required String peerId,
    required GroupInviteDeliveryStatus status,
    DateTime? updatedAt,
  }) async {
    final now = (updatedAt ?? DateTime.now()).toUtc();
    final key = _key(groupId, peerId);
    final existing = _attempts[key];
    _attempts[key] = existing == null
        ? GroupInviteDeliveryAttempt(
            groupId: groupId,
            peerId: peerId,
            status: status,
            attemptedAt: now,
            updatedAt: now,
          )
        : existing.copyWith(status: status, updatedAt: now);
  }

  @override
  Future<void> markJoined({
    required String groupId,
    required String peerId,
    String? username,
    DateTime? joinedAt,
  }) async {
    final now = (joinedAt ?? DateTime.now()).toUtc();
    final key = _key(groupId, peerId);
    final existing = _attempts[key];
    _attempts[key] = existing == null
        ? GroupInviteDeliveryAttempt(
            groupId: groupId,
            peerId: peerId,
            username: username,
            status: GroupInviteDeliveryStatus.joined,
            attemptedAt: now,
            updatedAt: now,
          )
        : existing.copyWith(
            username: username,
            status: GroupInviteDeliveryStatus.joined,
            updatedAt: now,
            clearLastError: true,
          );
  }

  @override
  Future<void> markRevoked({
    required String groupId,
    required String peerId,
    DateTime? revokedAt,
  }) async {
    final now = (revokedAt ?? DateTime.now()).toUtc();
    final key = _key(groupId, peerId);
    final existing = _attempts[key];
    _attempts[key] = existing == null
        ? GroupInviteDeliveryAttempt(
            groupId: groupId,
            peerId: peerId,
            status: GroupInviteDeliveryStatus.revoked,
            attemptedAt: now,
            updatedAt: now,
          )
        : existing.copyWith(
            status: GroupInviteDeliveryStatus.revoked,
            updatedAt: now,
            clearLastError: true,
          );
  }

  @override
  Future<void> markDeclined({
    required String groupId,
    required String peerId,
    DateTime? declinedAt,
  }) async {
    final key = _key(groupId, peerId);
    final existing = _attempts[key];
    if (existing?.status == GroupInviteDeliveryStatus.joined) {
      return;
    }
    final now = (declinedAt ?? DateTime.now()).toUtc();
    _attempts[key] = existing == null
        ? GroupInviteDeliveryAttempt(
            groupId: groupId,
            peerId: peerId,
            status: GroupInviteDeliveryStatus.declined,
            attemptedAt: now,
            updatedAt: now,
          )
        : existing.copyWith(
            status: GroupInviteDeliveryStatus.declined,
            updatedAt: now,
            clearLastError: true,
          );
  }

  @override
  Future<int> deleteAttempt({
    required String groupId,
    required String peerId,
  }) async => _attempts.remove(_key(groupId, peerId)) == null ? 0 : 1;

  @override
  Future<int> deleteAttemptsForGroup(String groupId) async {
    final keys = _attempts.keys
        .where((key) => key.startsWith('$groupId::'))
        .toList(growable: false);
    for (final key in keys) {
      _attempts.remove(key);
    }
    return keys.length;
  }
}

Map<String, dynamic> _lastGroupInboxStorePayload(FakeBridge bridge) {
  final inboxMsg = bridge.sentMessages.lastWhere(
    (m) => (jsonDecode(m) as Map)['cmd'] == 'group:inboxStore',
  );
  return (jsonDecode(inboxMsg) as Map)['payload'] as Map<String, dynamic>;
}

List<String> _groupDispatchCommands(FakeBridge bridge) => bridge.sentMessages
    .map((raw) => (jsonDecode(raw) as Map<String, dynamic>)['cmd'] as String?)
    .whereType<String>()
    .where(
      (command) =>
          command == 'group:sendReliable' ||
          command == 'group:publish' ||
          command == 'group:inboxStore',
    )
    .toList(growable: false);

Map<String, dynamic> _groupSendReliablePayloadForMessage(
  FakeBridge bridge,
  String messageId,
) {
  for (final raw in bridge.sentMessages.reversed) {
    final parsed = jsonDecode(raw) as Map<String, dynamic>;
    if (parsed['cmd'] != 'group:sendReliable') continue;
    final payload = parsed['payload'] as Map<String, dynamic>;
    if (payload['messageId'] == messageId) {
      return payload;
    }
  }
  fail('missing group:sendReliable for $messageId');
}

Map<String, dynamic> _groupInboxStorePayloadForMessage(
  FakeBridge bridge,
  String messageId,
) {
  for (final raw in bridge.sentMessages.reversed) {
    final parsed = jsonDecode(raw) as Map<String, dynamic>;
    if (parsed['cmd'] != 'group:inboxStore') continue;
    final payload = parsed['payload'] as Map<String, dynamic>;
    final envelope =
        jsonDecode(payload['message'] as String) as Map<String, dynamic>;
    if (envelope['messageId'] == messageId) {
      return payload;
    }
  }
  fail('missing group:inboxStore for $messageId');
}

List<String> _recipientPeerIdsFromRetryPayload(String inboxRetryPayload) {
  final retryPayload = jsonDecode(inboxRetryPayload) as Map<String, dynamic>;
  return (retryPayload['recipientPeerIds'] as List<dynamic>? ?? const [])
      .cast<String>();
}

Map<String, dynamic> _decodedGroupInboxReplayPayload(FakeBridge bridge) {
  final inboxPayload = _lastGroupInboxStorePayload(bridge);
  final envelope =
      jsonDecode(inboxPayload['message'] as String) as Map<String, dynamic>;
  final ciphertext = envelope['ciphertext'];
  if (ciphertext is String && envelope['kind'] == 'group_offline_replay') {
    return jsonDecode(ciphertext) as Map<String, dynamic>;
  }
  return envelope;
}

List<String> _groupInboxStoreReplayMessageIds(FakeBridge bridge) {
  return bridge.sentMessages
      .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
      .where((message) => message['cmd'] == 'group:inboxStore')
      .map((message) {
        final payload = (message['payload'] as Map).cast<String, dynamic>();
        final envelope =
            jsonDecode(payload['message'] as String) as Map<String, dynamic>;
        final ciphertext = envelope['ciphertext'];
        if (ciphertext is String &&
            envelope['kind'] == 'group_offline_replay') {
          final replay = jsonDecode(ciphertext) as Map<String, dynamic>;
          return replay['messageId'] as String;
        }
        return envelope['messageId'] as String;
      })
      .toList(growable: false);
}

Map<String, dynamic> _lastGroupOfflineReplayEnvelope(FakeBridge bridge) {
  final inboxPayload = _lastGroupInboxStorePayload(bridge);
  return jsonDecode(inboxPayload['message'] as String) as Map<String, dynamic>;
}

int _bridgeCommandIndex(FakeBridge bridge, String command, {int? keyEpoch}) {
  for (var i = 0; i < bridge.sentMessages.length; i++) {
    final parsed = jsonDecode(bridge.sentMessages[i]) as Map<String, dynamic>;
    if (parsed['cmd'] != command) {
      continue;
    }
    if (keyEpoch == null) {
      return i;
    }
    final payload = parsed['payload'];
    if (payload is Map<String, dynamic> && payload['keyEpoch'] == keyEpoch) {
      return i;
    }
  }
  return -1;
}

Map<String, dynamic> _offlineReplayEnvelopeFromRetryPayload(
  String inboxRetryPayload,
) {
  final retryPayload = jsonDecode(inboxRetryPayload) as Map<String, dynamic>;
  return jsonDecode(retryPayload['message'] as String) as Map<String, dynamic>;
}

void _expectSignedReplayEnvelope(
  Map<String, dynamic> envelope, {
  required String groupId,
  required String payloadType,
  required String senderPeerId,
  required String senderPublicKey,
  required String messageId,
}) {
  expect(envelope['kind'], 'group_offline_replay');
  expect(envelope['groupId'], groupId);
  expect(envelope['payloadType'], payloadType);
  expect(envelope['senderPeerId'], senderPeerId);
  expect(envelope['senderPublicKey'], senderPublicKey);
  expect(envelope['messageId'], messageId);
  expect(envelope['signatureAlgorithm'], 'ed25519');
  expect(envelope['signedPayload'], isA<String>());
  expect(envelope['signature'], isA<String>());
  final signedPayload =
      jsonDecode(envelope['signedPayload'] as String) as Map<String, dynamic>;
  expect(signedPayload['kind'], 'group_offline_replay');
  expect(signedPayload['groupId'], groupId);
  expect(signedPayload['payloadType'], payloadType);
  expect(signedPayload['senderPeerId'], senderPeerId);
  expect(signedPayload['senderSigningPublicKey'], senderPublicKey);
  expect(signedPayload['messageId'], messageId);
  expect(signedPayload['ciphertextHash'], isA<String>());
  expect(signedPayload['nonceHash'], isA<String>());
  expect(signedPayload['plaintextHash'], isA<String>());
}

void _expectNoProtectedFragments(String raw, Iterable<String> fragments) {
  for (final fragment in fragments) {
    expect(raw, isNot(contains(fragment)));
  }
}

void _expectNoForbiddenKeys(
  Object? value,
  Set<String> forbiddenKeys, {
  String path = r'$',
}) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString();
      expect(
        forbiddenKeys,
        isNot(contains(key)),
        reason: 'forbidden key $key found at $path',
      );
      _expectNoForbiddenKeys(entry.value, forbiddenKeys, path: '$path.$key');
    }
    return;
  }
  if (value is Iterable) {
    var index = 0;
    for (final item in value) {
      _expectNoForbiddenKeys(item, forbiddenKeys, path: '$path[$index]');
      index++;
    }
  }
}

Future<void> _saveGroupKey(
  InMemoryGroupRepository groupRepo,
  String groupId, {
  int generation = 1,
}) async {
  await groupRepo.saveKey(
    GroupKeyInfo(
      groupId: groupId,
      keyGeneration: generation,
      encryptedKey: 'test-group-key-$generation',
      createdAt: DateTime.now().toUtc(),
    ),
  );
}

void main() {
  late FakeBridge bridge;
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository msgRepo;

  final testGroup = GroupModel(
    id: 'group-1',
    name: 'Test Group',
    type: GroupType.chat,
    topicName: 'group-topic-1',
    createdAt: DateTime.now().toUtc(),
    createdBy: 'peer-1',
    myRole: GroupRole.admin,
  );

  setUp(() async {
    bridge = FakeBridge();
    groupRepo = InMemoryGroupRepository();
    msgRepo = InMemoryGroupMessageRepository();
    groupRecoveryGate.resetForTest();

    await groupRepo.saveGroup(testGroup);
    await groupRepo.saveMember(
      GroupMember(
        groupId: testGroup.id,
        peerId: 'peer-1',
        username: 'Alice',
        role: MemberRole.admin,
        publicKey: 'pk-1',
        joinedAt: DateTime.now().toUtc(),
      ),
    );
    await _saveGroupKey(groupRepo, testGroup.id);

    bridge.responses['group:publish'] = {'ok': true, 'messageId': 'msg-123'};
  });

  tearDown(() {
    groupRecoveryGate.resetForTest();
    setGroupContentAuthoringResolver(groupRepo, null);
  });

  test('sends message successfully', () async {
    final (result, message) = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'Hello group!',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
    );

    expect(result, SendGroupMessageResult.success);
    expect(message, isNotNull);
    expect(message!.text, 'Hello group!');
    expect(message.isIncoming, false);
    expect(message.status, 'sent');
  });

  test(
    'TC-364-01a protected blob-free group authoring freezes physical custody with zero pubsub',
    () async {
      final strictRepo = _StrictContentMessageRepository();
      final strictStore = _StrictContentInboxStore(
        durableCheck: () async {
          final row = await strictRepo.getMessage('msg-tc364-01a');
          return row?.status == GroupMessage.statusQueuedOffline &&
              row?.inboxRetryPayload != null;
        },
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-1',
          username: 'Alice',
          role: MemberRole.admin,
          publicKey: 'pk-1',
          devices: const <GroupMemberDeviceIdentity>[
            GroupMemberDeviceIdentity(
              deviceId: 'device-current',
              transportPeerId: 'transport-current',
              deviceSigningPublicKey: 'pk-current',
            ),
            GroupMemberDeviceIdentity(
              deviceId: 'device-sibling',
              transportPeerId: 'transport-sibling',
              deviceSigningPublicKey: 'pk-sibling',
            ),
            GroupMemberDeviceIdentity(
              deviceId: 'device-revoked',
              transportPeerId: 'transport-revoked',
              deviceSigningPublicKey: 'pk-revoked',
              status: GroupMemberDeviceStatus.revoked,
            ),
          ],
          joinedAt: DateTime.utc(2026, 8, 1),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-2',
          role: MemberRole.writer,
          publicKey: 'pk-2',
          devices: const <GroupMemberDeviceIdentity>[
            GroupMemberDeviceIdentity(
              deviceId: 'device-remote',
              transportPeerId: 'transport-remote',
              deviceSigningPublicKey: 'pk-remote',
            ),
          ],
          joinedAt: DateTime.utc(2026, 8, 1),
        ),
      );

      final result = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: strictRepo,
        groupId: 'group-1',
        text: 'strict discussion',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-current',
        senderPrivateKey: 'sk-current',
        senderUsername: 'Alice',
        senderDeviceId: 'device-current',
        senderTransportPeerId: 'transport-current',
        messageId: 'msg-tc364-01a',
        timestamp: DateTime.utc(2026, 8, 13, 12, 0, 0, 0, 1),
        groupContentAuthoring: GroupContentAuthoringContext(
          directLinkedDeviceSelector:
              const DirectLinkedDeviceSelector.enabled(),
          multiDeviceSyncEnabled: true,
          authorityVersion: GroupContentAuthorityVersion(
            eventAt: DateTime.utc(2026, 8, 13, 11),
            eventId: 'authority.tc364.01a',
            keyEpoch: 1,
          ),
          inboxStore: strictStore,
        ),
      );

      expect(result.$1, SendGroupMessageResult.success);
      expect(strictStore.recipients, <String>[
        'transport-remote',
        'transport-sibling',
      ]);
      expect(
        bridge.commandLog.where(
          (command) =>
              command == 'group:publish' || command == 'group:sendReliable',
        ),
        isEmpty,
      );
      final frozen = GroupContentRetryPayload.decode(
        strictRepo.initiallyPersistedRetryPayload!,
      );
      expect(frozen.pendingRecipientPeerIds, frozen.fullRecipientPeerIds);
      expect(frozen.fullRecipientPeerIds, strictStore.recipients);
      final strictTerminal = await strictRepo.getMessage('msg-tc364-01a');
      expect(strictTerminal!.status, 'sent');
      expect(
        strictTerminal.wireEnvelope,
        isNull,
        reason: 'terminal strict content cannot be reminted by generic retry',
      );
      expect(strictStore.everyStoreObservedDurableRow, isTrue);
      final strictFinalEvidence = strictRepo.protectedEvidence
          .where(
            (row) =>
                row['sourceEventId'] ==
                localProtectedGroupMessageSourceEventId('msg-tc364-01a'),
          )
          .toList(growable: false);
      expect(strictFinalEvidence, hasLength(1));
      expect(
        strictFinalEvidence.single['sourceEventId'],
        localProtectedGroupMessageSourceEventId('msg-tc364-01a'),
      );

      // A transport claimed by two eligible active devices is ambiguous, not
      // one deduplicated physical recipient. It is excluded while the unique
      // sibling transport remains protected.
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-3',
          username: 'Mallory',
          role: MemberRole.writer,
          publicKey: 'pk-3',
          devices: const <GroupMemberDeviceIdentity>[
            GroupMemberDeviceIdentity(
              deviceId: 'device-collision',
              transportPeerId: 'transport-remote',
              deviceSigningPublicKey: 'pk-collision',
            ),
          ],
          joinedAt: DateTime.utc(2026, 8, 1),
        ),
      );
      final ambiguousRepo = _StrictContentMessageRepository();
      final ambiguousStore = _StrictContentInboxStore();
      final ambiguous = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: ambiguousRepo,
        groupId: 'group-1',
        text: 'exclude ambiguous physical claim',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-current',
        senderPrivateKey: 'sk-current',
        senderUsername: 'Alice',
        senderDeviceId: 'device-current',
        senderTransportPeerId: 'transport-current',
        messageId: 'msg-tc364-ambiguous-transport',
        timestamp: DateTime.utc(2026, 8, 13, 12, 0, 10),
        groupContentAuthoring: GroupContentAuthoringContext(
          directLinkedDeviceSelector:
              const DirectLinkedDeviceSelector.enabled(),
          multiDeviceSyncEnabled: true,
          authorityVersion: GroupContentAuthorityVersion(
            eventAt: DateTime.utc(2026, 8, 13, 11),
            eventId: 'authority.tc364.01a.ambiguous',
            keyEpoch: 1,
          ),
          inboxStore: ambiguousStore,
        ),
      );
      expect(ambiguous.$1, SendGroupMessageResult.success);
      expect(ambiguousStore.recipients, <String>['transport-sibling']);
      expect(
        GroupContentRetryPayload.decode(
          ambiguousRepo.initiallyPersistedRetryPayload!,
        ).fullRecipientPeerIds,
        <String>['transport-sibling'],
      );
      await groupRepo.removeMember('group-1', 'peer-3');

      // The production-shaped choke point resolves strict custody even when
      // the composer did not supply an explicit context.
      final autoRepo = _StrictContentMessageRepository();
      final autoStore = _StrictContentInboxStore();
      setGroupContentAuthoringResolver(
        groupRepo,
        ({
          required groupId,
          required senderPeerId,
          required senderPublicKey,
          senderDeviceId,
          senderTransportPeerId,
        }) async => (
          kind: GroupContentAuthoringResolutionKind.strict,
          context: GroupContentAuthoringContext(
            directLinkedDeviceSelector:
                const DirectLinkedDeviceSelector.enabled(),
            multiDeviceSyncEnabled: true,
            authorityVersion: GroupContentAuthorityVersion(
              eventAt: DateTime.utc(2026, 8, 13, 11),
              eventId: 'authority.tc364.01a.production-primary',
              keyEpoch: 1,
            ),
            inboxStore: autoStore,
          ),
        ),
      );
      final isolatedRuntimeRepo = InMemoryGroupRepository();
      setGroupContentAuthoringResolver(
        isolatedRuntimeRepo,
        ({
          required groupId,
          required senderPeerId,
          required senderPublicKey,
          senderDeviceId,
          senderTransportPeerId,
        }) async => const (
          kind: GroupContentAuthoringResolutionKind.refuse,
          context: null,
        ),
      );
      final currentSender = await groupRepo.getMember('group-1', 'peer-1');
      expect(currentSender, isNotNull);
      final isolatedResolution = await resolveGroupContentAuthoring(
        resolverOwner: groupRepo,
        groupId: 'group-1',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-current',
        senderMember: currentSender!,
      );
      expect(
        isolatedResolution.kind,
        GroupContentAuthoringResolutionKind.strict,
        reason: 'a second runtime cannot replace the first runtime resolver',
      );
      setGroupContentAuthoringResolver(isolatedRuntimeRepo, null);
      final beforeAutoCommands = bridge.commandLog.length;
      final auto = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: autoRepo,
        groupId: 'group-1',
        text: 'production primary strict',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-current',
        senderPrivateKey: 'sk-current',
        senderUsername: 'Alice',
        senderDeviceId: 'device-current',
        senderTransportPeerId: 'transport-current',
        messageId: 'msg-tc364-production-primary',
        timestamp: DateTime.utc(2026, 8, 13, 12, 0, 30),
      );
      expect(auto.$1, SendGroupMessageResult.success);
      expect(autoStore.recipients, <String>[
        'transport-remote',
        'transport-sibling',
      ]);
      expect(
        autoRepo.protectedEvidence.where(
          (row) =>
              row['sourceEventId'] ==
              localProtectedGroupMessageSourceEventId(
                'msg-tc364-production-primary',
              ),
        ),
        hasLength(1),
      );
      expect(
        bridge.commandLog
            .skip(beforeAutoCommands)
            .where(
              (command) =>
                  command == 'group:publish' || command == 'group:sendReliable',
            ),
        isEmpty,
      );

      // Initialized production authority whose installed resolver cannot
      // supply a strict context is all-zero. Resolver absence is reserved for
      // incumbent/test compositions and therefore is not a production-shaped
      // missing-context proof.
      setGroupContentAuthoringResolver(
        groupRepo,
        ({
          required groupId,
          required senderPeerId,
          required senderPublicKey,
          senderDeviceId,
          senderTransportPeerId,
        }) async => const (
          kind: GroupContentAuthoringResolutionKind.refuse,
          context: null,
        ),
      );
      final missingContextBridge = FakeBridge();
      final missingContextRepo = _StrictContentMessageRepository();
      final missingContext = await sendGroupMessage(
        bridge: missingContextBridge,
        groupRepo: groupRepo,
        msgRepo: missingContextRepo,
        groupId: 'group-1',
        text: 'must refuse missing context',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-current',
        senderPrivateKey: 'sk-current',
        senderUsername: 'Alice',
        senderDeviceId: 'device-current',
        senderTransportPeerId: 'transport-current',
        messageId: 'msg-tc364-missing-context',
        timestamp: DateTime.utc(2026, 8, 13, 12, 0, 40),
      );
      expect(missingContext.$1, SendGroupMessageResult.authorityUnavailable);
      expect(missingContext.$2, isNull);
      expect(missingContextBridge.commandLog, isEmpty);
      expect(
        await missingContextRepo.getMessage('msg-tc364-missing-context'),
        isNull,
      );
      setGroupContentAuthoringResolver(groupRepo, null);

      // Announcement admins use the same protected lane and physical ACL.
      await groupRepo.saveGroup(
        testGroup.copyWith(
          type: GroupType.announcement,
          myRole: GroupRole.admin,
        ),
      );
      final announcementRepo = _StrictContentMessageRepository();
      final announcementStore = _StrictContentInboxStore(
        durableCheck: () async =>
            (await announcementRepo.getMessage(
              'msg-tc364-announcement',
            ))?.inboxRetryPayload !=
            null,
      );
      final announcement = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: announcementRepo,
        groupId: 'group-1',
        text: 'strict announcement',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-current',
        senderPrivateKey: 'sk-current',
        senderUsername: 'Alice',
        senderDeviceId: 'device-current',
        senderTransportPeerId: 'transport-current',
        messageId: 'msg-tc364-announcement',
        timestamp: DateTime.utc(2026, 8, 13, 12, 1),
        groupContentAuthoring: GroupContentAuthoringContext(
          directLinkedDeviceSelector:
              const DirectLinkedDeviceSelector.enabled(),
          multiDeviceSyncEnabled: true,
          authorityVersion: GroupContentAuthorityVersion(
            eventAt: DateTime.utc(2026, 8, 13, 11),
            eventId: 'authority.tc364.01a.announcement',
            keyEpoch: 1,
          ),
          inboxStore: announcementStore,
        ),
      );
      expect(announcement.$1, SendGroupMessageResult.success);
      expect(announcementStore.recipients, <String>[
        'transport-remote',
        'transport-sibling',
      ]);
      expect(announcementStore.everyStoreObservedDurableRow, isTrue);

      await groupRepo.saveGroup(
        testGroup.copyWith(type: GroupType.chat, myRole: GroupRole.admin),
      );

      Future<void> expectAllZero({
        required String caseName,
        required GroupContentAuthoringContext context,
        bool forwarded = false,
        DateTime? authoredAt,
        // Machinery refusals are typed authorityUnavailable since Plan 377;
        // genuine role/content-policy refusals keep `unauthorized`.
        SendGroupMessageResult expected =
            SendGroupMessageResult.authorityUnavailable,
      }) async {
        final refusalBridge = FakeBridge();
        final refusalRepo = _StrictContentMessageRepository();
        final result = await sendGroupMessage(
          bridge: refusalBridge,
          groupRepo: groupRepo,
          msgRepo: refusalRepo,
          groupId: 'group-1',
          text: 'refuse $caseName',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-current',
          senderPrivateKey: 'sk-current',
          senderUsername: 'Alice',
          senderDeviceId: 'device-current',
          senderTransportPeerId: 'transport-current',
          messageId: 'msg-tc364-$caseName',
          timestamp: authoredAt ?? DateTime.utc(2026, 8, 13, 12, 2),
          isForwarded: forwarded,
          groupContentAuthoring: context,
        );
        expect(result.$1, expected, reason: caseName);
        expect(
          await refusalRepo.getMessage('msg-tc364-$caseName'),
          isNull,
          reason: caseName,
        );
        expect(refusalBridge.commandLog, isEmpty, reason: caseName);
      }

      final enabledAuthority = GroupContentAuthorityVersion(
        eventAt: DateTime.utc(2026, 8, 13, 11),
        eventId: 'authority.tc364.01a.refusal',
        keyEpoch: 1,
      );
      await expectAllZero(
        caseName: 'selector-off',
        context: GroupContentAuthoringContext(
          directLinkedDeviceSelector:
              const DirectLinkedDeviceSelector.disabled(),
          multiDeviceSyncEnabled: true,
          authorityVersion: enabledAuthority,
          inboxStore: _StrictContentInboxStore(),
        ),
      );
      await expectAllZero(
        caseName: 'missing-credential',
        context: GroupContentAuthoringContext(
          directLinkedDeviceSelector:
              const DirectLinkedDeviceSelector.enabled(),
          multiDeviceSyncEnabled: true,
          authorityVersion: enabledAuthority,
          inboxStore: _StrictContentInboxStore(),
          requireLinkedTransportCredential: true,
        ),
      );
      await expectAllZero(
        caseName: 'ineligible-forward',
        context: GroupContentAuthoringContext(
          directLinkedDeviceSelector:
              const DirectLinkedDeviceSelector.enabled(),
          multiDeviceSyncEnabled: true,
          authorityVersion: enabledAuthority,
          inboxStore: _StrictContentInboxStore(),
        ),
        forwarded: true,
      );
      await expectAllZero(
        caseName: 'older-than-authority',
        context: GroupContentAuthoringContext(
          directLinkedDeviceSelector:
              const DirectLinkedDeviceSelector.enabled(),
          multiDeviceSyncEnabled: true,
          authorityVersion: enabledAuthority,
          inboxStore: _StrictContentInboxStore(),
        ),
        authoredAt: enabledAuthority.eventAt.subtract(
          const Duration(microseconds: 1),
        ),
      );
      await expectAllZero(
        caseName: 'future-skew',
        context: GroupContentAuthoringContext(
          directLinkedDeviceSelector:
              const DirectLinkedDeviceSelector.enabled(),
          multiDeviceSyncEnabled: true,
          authorityVersion: enabledAuthority,
          inboxStore: _StrictContentInboxStore(),
        ),
        authoredAt: DateTime.now().toUtc().add(
          groupContentAuthoringFutureSkew + const Duration(minutes: 1),
        ),
      );

      // Announcement membership and local role must both authorize authoring.
      await groupRepo.saveGroup(
        testGroup.copyWith(
          type: GroupType.announcement,
          myRole: GroupRole.member,
        ),
      );
      await expectAllZero(
        caseName: 'announcement-non-admin',
        // Refused by the early group.myRole announcement gate
        // (send_group_message_use_case.dart:1974) — a genuine role refusal,
        // so it keeps `unauthorized` (TC-377-04 rung C semantics).
        expected: SendGroupMessageResult.unauthorized,
        context: GroupContentAuthoringContext(
          directLinkedDeviceSelector:
              const DirectLinkedDeviceSelector.enabled(),
          multiDeviceSyncEnabled: true,
          authorityVersion: enabledAuthority,
          inboxStore: _StrictContentInboxStore(),
        ),
      );
      await groupRepo.saveGroup(testGroup);

      // Candidate crypto is disposable: a second roster read that loses one
      // physical recipient prevents persistence and all network effects.
      final driftRepo = _DriftingStrictGroupRepository();
      await driftRepo.saveGroup(testGroup);
      for (final member in await groupRepo.getMembers('group-1')) {
        await driftRepo.saveMember(member);
      }
      await _saveGroupKey(driftRepo, 'group-1');
      final driftMessageRepo = _StrictContentMessageRepository();
      final driftStore = _StrictContentInboxStore();
      final driftBridge = FakeBridge();
      final drift = await sendGroupMessage(
        bridge: driftBridge,
        groupRepo: driftRepo,
        msgRepo: driftMessageRepo,
        groupId: 'group-1',
        text: 'discard drifted candidate',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-current',
        senderPrivateKey: 'sk-current',
        senderUsername: 'Alice',
        senderDeviceId: 'device-current',
        senderTransportPeerId: 'transport-current',
        messageId: 'msg-tc364-drift',
        timestamp: DateTime.utc(2026, 8, 13, 12, 3),
        groupContentAuthoring: GroupContentAuthoringContext(
          directLinkedDeviceSelector:
              const DirectLinkedDeviceSelector.enabled(),
          multiDeviceSyncEnabled: true,
          authorityVersion: enabledAuthority,
          inboxStore: driftStore,
        ),
      );
      expect(drift.$1, SendGroupMessageResult.error);
      expect(await driftMessageRepo.getMessage('msg-tc364-drift'), isNull);
      expect(driftStore.recipients, isEmpty);
      expect(
        driftBridge.commandLog.where(
          (command) =>
              command == 'group:publish' ||
              command == 'group:sendReliable' ||
              command == 'group:inboxStore',
        ),
        isEmpty,
      );

      // Bridge crypto is deliberately outside the keyed phase. A concurrent
      // authority mutation must enter, and the stale candidate must be thrown
      // away before either durable owner insertion or protected relay store.
      final gatedRepo = InMemoryGroupRepository();
      await gatedRepo.saveGroup(testGroup);
      for (final member in await groupRepo.getMembers('group-1')) {
        await gatedRepo.saveMember(member);
      }
      await _saveGroupKey(gatedRepo, 'group-1');
      final gatedMessageRepo = _StrictContentMessageRepository();
      final gatedStore = _StrictContentInboxStore();
      final gatedCrypto = _GatedReplayCryptoBridge();
      final gatedSend = sendGroupMessage(
        bridge: gatedCrypto,
        groupRepo: gatedRepo,
        msgRepo: gatedMessageRepo,
        groupId: 'group-1',
        text: 'discard crypto candidate after authority drift',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-current',
        senderPrivateKey: 'sk-current',
        senderUsername: 'Alice',
        senderDeviceId: 'device-current',
        senderTransportPeerId: 'transport-current',
        messageId: 'msg-tc364-crypto-drift',
        timestamp: DateTime.utc(2026, 8, 13, 12, 3, 1),
        groupContentAuthoring: GroupContentAuthoringContext(
          directLinkedDeviceSelector:
              const DirectLinkedDeviceSelector.enabled(),
          multiDeviceSyncEnabled: true,
          authorityVersion: enabledAuthority,
          inboxStore: gatedStore,
        ),
      );
      await gatedCrypto.cryptoEntered.future;
      var mutationEntered = false;
      await runGroupAuthorityPhase(
        groupId: 'group-1',
        action: () async {
          mutationEntered = true;
          await gatedRepo.removeMember('group-1', 'peer-2');
        },
      );
      expect(mutationEntered, isTrue);
      gatedCrypto.releaseCrypto.complete();
      expect((await gatedSend).$1, SendGroupMessageResult.error);
      expect(
        await gatedMessageRepo.getMessage('msg-tc364-crypto-drift'),
        isNull,
      );
      expect(gatedStore.recipients, isEmpty);
      expect(
        gatedCrypto.commandLog.where(
          (command) =>
              command == 'group:publish' ||
              command == 'group:sendReliable' ||
              command == 'group:inboxStore',
        ),
        isEmpty,
      );

      // Once owner+PREPARED commit, a transient repository readback failure
      // cannot roll the owner back and orphan append-only evidence. A later
      // retry/restart pass completes those exact frozen bytes.
      final handoffRepo = _PreparedReadbackFailureRepository();
      final handoffStore = _StrictContentInboxStore();
      final handoffBridge = FakeBridge();
      final handoff = await sendGroupMessage(
        bridge: handoffBridge,
        groupRepo: groupRepo,
        msgRepo: handoffRepo,
        groupId: 'group-1',
        text: 'retain prepared owner after readback failure',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-current',
        senderPrivateKey: 'sk-current',
        senderUsername: 'Alice',
        senderDeviceId: 'device-current',
        senderTransportPeerId: 'transport-current',
        messageId: 'msg-tc364-prepared-handoff',
        timestamp: DateTime.utc(2026, 8, 13, 12, 3, 2),
        groupContentAuthoring: GroupContentAuthoringContext(
          directLinkedDeviceSelector:
              const DirectLinkedDeviceSelector.enabled(),
          multiDeviceSyncEnabled: true,
          authorityVersion: enabledAuthority,
          inboxStore: handoffStore,
        ),
      );
      expect(handoff.$1, SendGroupMessageResult.queuedOffline);
      expect(handoffStore.recipients, isEmpty);
      final handedOff = await handoffRepo.getMessage(
        'msg-tc364-prepared-handoff',
      );
      expect(handedOff, isNotNull);
      expect(handedOff!.inboxRetryPayload, isNotNull);
      expect(
        handoffRepo.protectedEvidence.where(
          (row) =>
              (row['sourceEventId'] as String?)?.startsWith('ppm1:') == true,
        ),
        hasLength(1),
      );
      expect(
        await retryFailedGroupInboxStores(
          bridge: handoffBridge,
          msgRepo: handoffRepo,
          groupRepo: groupRepo,
          groupContentInboxStore: handoffStore,
          classifyStrictContentAuthority:
              ({
                required groupId,
                required observedAuthority,
                required contentAt,
                required contentEventId,
              }) async =>
                  ProtectedGroupContentRetryAuthorityDisposition.eligible,
          strictContentOnly: true,
        ),
        1,
      );
      expect(
        (await handoffRepo.getMessage('msg-tc364-prepared-handoff'))!.status,
        'sent',
      );

      // An active linked installation owns its authoring role even while its
      // member-device projection is empty. Production resolution must run
      // before the ordinary-primary legacy fallback, leaving all network and
      // durable-owner effects at zero.
      final emptyLinkedRepo = InMemoryGroupRepository();
      await emptyLinkedRepo.saveGroup(testGroup);
      await emptyLinkedRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-1',
          username: 'Alice',
          role: MemberRole.admin,
          publicKey: 'account-pk',
          joinedAt: DateTime.utc(2026, 8, 1),
        ),
      );
      await _saveGroupKey(emptyLinkedRepo, 'group-1');
      var linkedInstallationLoads = 0;
      setGroupContentAuthoringResolver(
        emptyLinkedRepo,
        buildProtectedGroupContentAuthoringResolver(
          loadIdentity: () async => (peerId: 'peer-1', publicKey: 'account-pk'),
          loadMember: emptyLinkedRepo.getMember,
          loadInstallationAuthority: (_) async {
            linkedInstallationLoads++;
            return LinkedInstallationAuthoritySnapshot(
              disposition: LinkedInstallationDisposition.active,
              credential: LinkedTransportCredential(
                state: LinkedTransportCredentialState.active,
                accountPeerId: 'peer-1',
                accountPublicKey: 'account-pk',
                deviceId: 'device-linked',
                transportPeerId: 'transport-linked',
                transportPublicKey: 'linked-pk',
                transportPrivateKey: 'linked-sk',
                createdAt: '2026-08-13T10:00:00.000Z',
                activatedAt: '2026-08-13T10:00:01.000Z',
              ),
              failClosedReason: null,
            );
          },
          loadLatestSettledAuthority: (_) async => null,
          readCurrentTransportPeerId: () => 'transport-linked',
          inboxStore: _StrictContentInboxStore(),
          directLinkedDeviceSelector:
              const DirectLinkedDeviceSelector.enabled(),
          multiDeviceSyncEnabled: true,
        ),
      );
      final emptyLinkedBridge = FakeBridge();
      final emptyLinkedMessageRepo = _StrictContentMessageRepository();
      final emptyLinked = await sendGroupMessage(
        bridge: emptyLinkedBridge,
        groupRepo: emptyLinkedRepo,
        msgRepo: emptyLinkedMessageRepo,
        groupId: 'group-1',
        text: 'must not resurrect account transport',
        senderPeerId: 'peer-1',
        senderPublicKey: 'account-pk',
        senderPrivateKey: 'account-sk',
        senderUsername: 'Alice',
        messageId: 'msg-tc364-empty-linked',
        timestamp: DateTime.utc(2026, 8, 13, 12, 3, 3),
      );
      expect(linkedInstallationLoads, 1);
      expect(emptyLinked.$1, SendGroupMessageResult.authorityUnavailable);
      expect(emptyLinked.$2, isNull);
      expect(emptyLinkedBridge.commandLog, isEmpty);
      expect(
        await emptyLinkedMessageRepo.getMessage('msg-tc364-empty-linked'),
        isNull,
      );
      setGroupContentAuthoringResolver(emptyLinkedRepo, null);

      // A genuinely uninitialized ordinary primary keeps the incumbent lane.
      final primaryRepo = InMemoryGroupRepository();
      await primaryRepo.saveGroup(testGroup);
      await primaryRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-1',
          username: 'Alice',
          role: MemberRole.admin,
          publicKey: 'pk-1',
          joinedAt: DateTime.utc(2026, 8, 1),
        ),
      );
      await _saveGroupKey(primaryRepo, 'group-1');
      var primaryInstallationLoads = 0;
      setGroupContentAuthoringResolver(
        primaryRepo,
        buildProtectedGroupContentAuthoringResolver(
          loadIdentity: () async => (peerId: 'peer-1', publicKey: 'pk-1'),
          loadMember: primaryRepo.getMember,
          loadInstallationAuthority: (_) async {
            primaryInstallationLoads++;
            return const LinkedInstallationAuthoritySnapshot(
              disposition: LinkedInstallationDisposition.primary,
              credential: null,
              failClosedReason: null,
            );
          },
          loadLatestSettledAuthority: (_) async => null,
          readCurrentTransportPeerId: () => null,
          inboxStore: _StrictContentInboxStore(),
          directLinkedDeviceSelector:
              const DirectLinkedDeviceSelector.enabled(),
          multiDeviceSyncEnabled: true,
        ),
      );
      final primaryBridge = FakeBridge();
      primaryBridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'msg-tc364-primary',
      };
      final primaryMessageRepo = InMemoryGroupMessageRepository();
      final primary = await sendGroupMessage(
        bridge: primaryBridge,
        groupRepo: primaryRepo,
        msgRepo: primaryMessageRepo,
        groupId: 'group-1',
        text: 'incumbent primary',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'msg-tc364-primary',
        timestamp: DateTime.utc(2026, 8, 13, 12, 4),
      );
      expect(primary.$1, SendGroupMessageResult.success);
      expect(primary.$2, isNotNull);
      expect(primaryInstallationLoads, greaterThanOrEqualTo(2));
      expect(
        primaryBridge.commandLog.where(
          (command) =>
              command == 'group:sendReliable' || command == 'group:publish',
        ),
        isNotEmpty,
      );
      setGroupContentAuthoringResolver(primaryRepo, null);
    },
  );

  test(
    'TC-377-01 self-bound creator device roster stays on the legacy lane with no settled authority',
    () async {
      // The seeded device row is the exact production creator-stamp shape
      // (create_group_with_members_use_case.dart:229-234): deviceId ==
      // transportPeerId == the account peerId, deviceSigningPublicKey == the
      // account identity.publicKey that the send passes as senderPublicKey —
      // which is also what satisfies the live unbound-device guard at
      // send_group_message_use_case.dart:2445.
      final selfBoundRepo = InMemoryGroupRepository();
      await selfBoundRepo.saveGroup(testGroup);
      final selfBoundMember = GroupMember(
        groupId: 'group-1',
        peerId: 'peer-1',
        username: 'Alice',
        role: MemberRole.admin,
        publicKey: 'pk-1',
        mlKemPublicKey: 'mlkem-pk-1',
        devices: const <GroupMemberDeviceIdentity>[
          GroupMemberDeviceIdentity(
            deviceId: 'peer-1',
            transportPeerId: 'peer-1',
            deviceSigningPublicKey: 'pk-1',
            mlKemPublicKey: 'mlkem-pk-1',
          ),
        ],
        joinedAt: DateTime.utc(2026, 8, 16),
      );
      await selfBoundRepo.saveMember(selfBoundMember);
      await _saveGroupKey(selfBoundRepo, 'group-1');
      setGroupContentAuthoringResolver(
        selfBoundRepo,
        buildProtectedGroupContentAuthoringResolver(
          loadIdentity: () async => (peerId: 'peer-1', publicKey: 'pk-1'),
          loadMember: selfBoundRepo.getMember,
          loadInstallationAuthority: (_) async =>
              const LinkedInstallationAuthoritySnapshot(
                disposition: LinkedInstallationDisposition.primary,
                credential: null,
                failClosedReason: null,
              ),
          loadLatestSettledAuthority: (_) async => null,
          readCurrentTransportPeerId: () => null,
          inboxStore: _StrictContentInboxStore(),
          directLinkedDeviceSelector:
              const DirectLinkedDeviceSelector.enabled(),
          multiDeviceSyncEnabled: true,
        ),
      );
      addTearDown(() => setGroupContentAuthoringResolver(selfBoundRepo, null));
      final selfBoundBridge = FakeBridge();
      selfBoundBridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'msg-tc377-01',
      };
      final selfBoundMessageRepo = InMemoryGroupMessageRepository();

      final (result, message) = await sendGroupMessage(
        bridge: selfBoundBridge,
        groupRepo: selfBoundRepo,
        msgRepo: selfBoundMessageRepo,
        groupId: 'group-1',
        text: 'first send of a fresh group',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'msg-tc377-01',
        timestamp: DateTime.utc(2026, 8, 16, 23, 0),
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      expect(
        selfBoundBridge.commandLog.where(
          (command) =>
              command == 'group:publish' || command == 'group:sendReliable',
        ),
        isNotEmpty,
      );

      // Predicate parity: the new getter must stay byte-equivalent to the
      // wave's own authoring gate for every roster shape.
      expect(selfBoundMember.hasInitializedDeviceAuthority, isFalse);
      expect(
        selfBoundMember.hasInitializedDeviceAuthority,
        hasProtectedGroupPhysicalAuthority([selfBoundMember]),
      );
      final partiallyBound = selfBoundMember.copyWith(
        devices: const <GroupMemberDeviceIdentity>[
          GroupMemberDeviceIdentity(
            deviceId: 'peer-1',
            transportPeerId: 'transport-x',
            deviceSigningPublicKey: 'pk-1',
          ),
        ],
      );
      expect(partiallyBound.hasInitializedDeviceAuthority, isTrue);
      expect(
        partiallyBound.hasInitializedDeviceAuthority,
        hasProtectedGroupPhysicalAuthority([partiallyBound]),
      );
      final revokedDistinct = selfBoundMember.copyWith(
        devices: const <GroupMemberDeviceIdentity>[
          GroupMemberDeviceIdentity(
            deviceId: 'device-x',
            transportPeerId: 'transport-x',
            deviceSigningPublicKey: 'pk-x',
            status: GroupMemberDeviceStatus.revoked,
          ),
        ],
      );
      expect(revokedDistinct.hasInitializedDeviceAuthority, isTrue);
      expect(
        revokedDistinct.hasInitializedDeviceAuthority,
        hasProtectedGroupPhysicalAuthority([revokedDistinct]),
      );
    },
  );

  test(
    'TC-377-12 self-bound roster passes media admission while a physically initialized roster still refuses',
    () async {
      final admissionRepo = InMemoryGroupRepository();
      await admissionRepo.saveGroup(testGroup);
      final selfBoundMember = GroupMember(
        groupId: 'group-1',
        peerId: 'peer-1',
        username: 'Alice',
        role: MemberRole.admin,
        publicKey: 'pk-1',
        mlKemPublicKey: 'mlkem-pk-1',
        devices: const <GroupMemberDeviceIdentity>[
          GroupMemberDeviceIdentity(
            deviceId: 'peer-1',
            transportPeerId: 'peer-1',
            deviceSigningPublicKey: 'pk-1',
          ),
        ],
        joinedAt: DateTime.utc(2026, 8, 16),
      );
      await admissionRepo.saveMember(selfBoundMember);
      await _saveGroupKey(admissionRepo, 'group-1');
      setGroupContentAuthoringResolver(
        admissionRepo,
        buildProtectedGroupContentAuthoringResolver(
          loadIdentity: () async => (peerId: 'peer-1', publicKey: 'pk-1'),
          loadMember: admissionRepo.getMember,
          loadInstallationAuthority: (_) async =>
              const LinkedInstallationAuthoritySnapshot(
                disposition: LinkedInstallationDisposition.primary,
                credential: null,
                failClosedReason: null,
              ),
          loadLatestSettledAuthority: (_) async => null,
          readCurrentTransportPeerId: () => null,
          inboxStore: _StrictContentInboxStore(),
          directLinkedDeviceSelector:
              const DirectLinkedDeviceSelector.enabled(),
          multiDeviceSyncEnabled: true,
        ),
      );
      addTearDown(() => setGroupContentAuthoringResolver(admissionRepo, null));

      // Rung A: the production creator shape must resolve legacyUninitialized,
      // unblocking the widget media/voice admission pre-gate
      // (group_conversation_wired.dart:2756 / :5193).
      final selfBoundAdmission = await prepareGroupContentAuthoringAdmission(
        groupRepo: admissionRepo,
        groupId: 'group-1',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
      );
      expect(
        selfBoundAdmission.kind,
        GroupContentAuthoringResolutionKind.legacyUninitialized,
      );

      // Rung B: a genuinely initialized (non-self-bound) roster with no
      // settled proof keeps the Plan-364 fail-closed boundary — the rung
      // ORDER inside the resolver is the contract (devices rung before the
      // ordinary-primary fallback).
      await admissionRepo.saveMember(
        selfBoundMember.copyWith(
          devices: const <GroupMemberDeviceIdentity>[
            GroupMemberDeviceIdentity(
              deviceId: 'device-x',
              transportPeerId: 'transport-x',
              deviceSigningPublicKey: 'pk-1',
            ),
          ],
        ),
      );
      final initializedAdmission = await prepareGroupContentAuthoringAdmission(
        groupRepo: admissionRepo,
        groupId: 'group-1',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
      );
      expect(
        initializedAdmission.kind,
        GroupContentAuthoringResolutionKind.refuse,
      );
    },
  );

  test(
    'TC-377-04 strict-authority refusal is authorityUnavailable with unchanged telemetry reason',
    () async {
      // A genuinely initialized (NON-self-bound) roster: device-x != peer-1.
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-1',
          username: 'Alice',
          role: MemberRole.admin,
          publicKey: 'pk-1',
          devices: const <GroupMemberDeviceIdentity>[
            GroupMemberDeviceIdentity(
              deviceId: 'device-x',
              transportPeerId: 'transport-x',
              deviceSigningPublicKey: 'pk-1',
            ),
          ],
          joinedAt: DateTime.utc(2026, 8, 16),
        ),
      );

      // Rung A: installed resolver refusal → authorityUnavailable while the
      // GROUP_SEND_MSG_TIMING outcome/reason telemetry stays byte-stable.
      setGroupContentAuthoringResolver(
        groupRepo,
        ({
          required groupId,
          required senderPeerId,
          required senderPublicKey,
          senderDeviceId,
          senderTransportPeerId,
        }) async => const (
          kind: GroupContentAuthoringResolutionKind.refuse,
          context: null,
        ),
      );
      final refuseBridge = FakeBridge();
      final refuseRepo = _StrictContentMessageRepository();
      late (SendGroupMessageResult, GroupMessage?) refuseResult;
      final refuseEvents = await captureFlowEvents(() async {
        refuseResult = await sendGroupMessage(
          bridge: refuseBridge,
          groupRepo: groupRepo,
          msgRepo: refuseRepo,
          groupId: 'group-1',
          text: 'refused by authority machinery',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'msg-tc377-04a',
          timestamp: DateTime.utc(2026, 8, 16, 23, 1),
        );
      });
      expect(refuseResult.$1, SendGroupMessageResult.authorityUnavailable);
      expect(refuseResult.$2, isNull);
      expect(refuseBridge.commandLog, isEmpty);
      expect(await refuseRepo.getMessage('msg-tc377-04a'), isNull);
      final refuseTiming = refuseEvents.lastWhere(
        (event) => event['event'] == 'GROUP_SEND_MSG_TIMING',
      );
      expect(
        (refuseTiming['details'] as Map<String, dynamic>)['outcome'],
        'unauthorized',
      );
      expect(
        (refuseTiming['details'] as Map<String, dynamic>)['reason'],
        'strict_group_content_authority_unavailable',
      );
      setGroupContentAuthoringResolver(groupRepo, null);

      // Rung B: a resolver that answers legacyUninitialized for an
      // initialized roster is rejected by the second disjunct at
      // send_group_message_use_case.dart:2358 — the only direct lock on it.
      setGroupContentAuthoringResolver(
        groupRepo,
        ({
          required groupId,
          required senderPeerId,
          required senderPublicKey,
          senderDeviceId,
          senderTransportPeerId,
        }) async => const (
          kind: GroupContentAuthoringResolutionKind.legacyUninitialized,
          context: null,
        ),
      );
      final staleLegacyBridge = FakeBridge();
      final staleLegacyRepo = _StrictContentMessageRepository();
      late (SendGroupMessageResult, GroupMessage?) staleLegacyResult;
      final staleLegacyEvents = await captureFlowEvents(() async {
        staleLegacyResult = await sendGroupMessage(
          bridge: staleLegacyBridge,
          groupRepo: groupRepo,
          msgRepo: staleLegacyRepo,
          groupId: 'group-1',
          text: 'stale legacy resolution for an initialized roster',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'msg-tc377-04b',
          timestamp: DateTime.utc(2026, 8, 16, 23, 2),
        );
      });
      expect(
        staleLegacyResult.$1,
        SendGroupMessageResult.authorityUnavailable,
      );
      expect(staleLegacyResult.$2, isNull);
      expect(staleLegacyBridge.commandLog, isEmpty);
      expect(await staleLegacyRepo.getMessage('msg-tc377-04b'), isNull);
      final staleLegacyTiming = staleLegacyEvents.lastWhere(
        (event) => event['event'] == 'GROUP_SEND_MSG_TIMING',
      );
      expect(
        (staleLegacyTiming['details'] as Map<String, dynamic>)['reason'],
        'strict_group_content_authority_unavailable',
      );
      setGroupContentAuthoringResolver(groupRepo, null);

      // Rung C: the role/content-policy clauses of the not-qualified block
      // keep the genuine `unauthorized` after the :2380 split — announcement
      // group, admin myRole (passes the early role gate), non-admin MEMBER
      // row role, machinery-complete strict context.
      await groupRepo.saveGroup(
        testGroup.copyWith(
          type: GroupType.announcement,
          myRole: GroupRole.admin,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-1',
          username: 'Alice',
          role: MemberRole.writer,
          publicKey: 'pk-1',
          devices: const <GroupMemberDeviceIdentity>[
            GroupMemberDeviceIdentity(
              deviceId: 'device-x',
              transportPeerId: 'transport-x',
              deviceSigningPublicKey: 'pk-1',
            ),
          ],
          joinedAt: DateTime.utc(2026, 8, 16),
        ),
      );
      final policyBridge = FakeBridge();
      final policyRepo = _StrictContentMessageRepository();
      late (SendGroupMessageResult, GroupMessage?) policyResult;
      final policyEvents = await captureFlowEvents(() async {
        policyResult = await sendGroupMessage(
          bridge: policyBridge,
          groupRepo: groupRepo,
          msgRepo: policyRepo,
          groupId: 'group-1',
          text: 'non-admin member posting to announcement',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'msg-tc377-04c',
          timestamp: DateTime.utc(2026, 8, 16, 23, 3),
          groupContentAuthoring: GroupContentAuthoringContext(
            directLinkedDeviceSelector:
                const DirectLinkedDeviceSelector.enabled(),
            multiDeviceSyncEnabled: true,
            authorityVersion: GroupContentAuthorityVersion(
              eventAt: DateTime.utc(2026, 8, 16, 22),
              eventId: 'authority.tc377.04c',
              keyEpoch: 1,
            ),
            inboxStore: _StrictContentInboxStore(),
          ),
        );
      });
      expect(policyResult.$1, SendGroupMessageResult.unauthorized);
      expect(policyResult.$2, isNull);
      expect(policyBridge.commandLog, isEmpty);
      final policyTiming = policyEvents.lastWhere(
        (event) => event['event'] == 'GROUP_SEND_MSG_TIMING',
      );
      expect(
        (policyTiming['details'] as Map<String, dynamic>)['outcome'],
        'unauthorized',
      );
      expect(
        (policyTiming['details'] as Map<String, dynamic>)['reason'],
        'strict_group_content_not_qualified',
      );
      await groupRepo.saveGroup(testGroup);
    },
  );

  test(
    'TC-366-03a strict ordinary quote preserves typed metadata for text media and voice',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-1',
          username: 'Alice',
          role: MemberRole.admin,
          publicKey: 'pk-1',
          devices: const <GroupMemberDeviceIdentity>[
            GroupMemberDeviceIdentity(
              deviceId: 'device-current',
              transportPeerId: 'transport-current',
              deviceSigningPublicKey: 'pk-current',
            ),
            GroupMemberDeviceIdentity(
              deviceId: 'device-sibling',
              transportPeerId: 'transport-sibling',
              deviceSigningPublicKey: 'pk-sibling',
            ),
          ],
          joinedAt: DateTime.utc(2026, 8, 1),
        ),
      );
      final strictRepo = _StrictContentMessageRepository();
      final strictStore = _StrictContentInboxStore();
      final result = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: strictRepo,
        groupId: 'group-1',
        text: 'quoted ordinary text',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-current',
        senderPrivateKey: 'sk-current',
        senderUsername: 'Alice',
        senderDeviceId: 'device-current',
        senderTransportPeerId: 'transport-current',
        messageId: 'msg-tc366-quoted-text',
        quotedMessageId: 'quoted-parent-text',
        timestamp: DateTime.utc(2026, 8, 14, 12),
        groupContentAuthoring: GroupContentAuthoringContext(
          directLinkedDeviceSelector:
              const DirectLinkedDeviceSelector.enabled(),
          multiDeviceSyncEnabled: true,
          authorityVersion: GroupContentAuthorityVersion(
            eventAt: DateTime.utc(2026, 8, 14, 11),
            eventId: 'authority.tc366.03a.text',
            keyEpoch: 1,
          ),
          inboxStore: strictStore,
        ),
      );

      expect(result.$1, SendGroupMessageResult.success);
      expect(result.$2?.quotedMessageId, 'quoted-parent-text');
      expect(
        (await strictRepo.getMessage('msg-tc366-quoted-text'))?.quotedMessageId,
        'quoted-parent-text',
      );
      expect(strictStore.recipients, <String>['transport-sibling']);
      expect(
        bridge.commandLog.where(
          (command) =>
              command == 'group:publish' || command == 'group:sendReliable',
        ),
        isEmpty,
      );
    },
  );

  test(
    'GMF-07 forwarded marker survives reliable fallback wire and replay payloads',
    () async {
      Map<String, dynamic> publishPayloadFor(String messageId) {
        for (final raw in bridge.sentMessages.reversed) {
          final parsed = jsonDecode(raw) as Map<String, dynamic>;
          if (parsed['cmd'] != 'group:publish') continue;
          final payload = parsed['payload'] as Map<String, dynamic>;
          if (payload['messageId'] == messageId) return payload;
        }
        fail('missing group:publish for $messageId');
      }

      Map<String, dynamic> replayPlaintextOf(GroupMessage message) {
        final retryPayload =
            jsonDecode(message.inboxRetryPayload!) as Map<String, dynamic>;
        final envelope =
            jsonDecode(retryPayload['message'] as String)
                as Map<String, dynamic>;
        // FakeBridge group.encrypt is a passthrough: the "ciphertext" IS the
        // replay plaintext, so the encrypted-offline-replay seam is decodable.
        return jsonDecode(envelope['ciphertext'] as String)
            as Map<String, dynamic>;
      }

      // ---- Fallback publish mode, live ok + custody fail: the durable
      // replay payload stays on the SENT row and carries the marker.
      bridge.responses['group:inboxStore'] = {'ok': false};
      final (fwdPubResult, fwdPubMessage) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'forwarded via publish',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'fwd-pub-1',
        isForwarded: true,
      );
      expect(fwdPubResult, SendGroupMessageResult.success);
      expect(fwdPubMessage!.isForwarded, isTrue, reason: 'final row marker');
      expect(
        (await msgRepo.getMessage('fwd-pub-1'))!.isForwarded,
        isTrue,
        reason: 'persisted row marker',
      );
      expect(publishPayloadFor('fwd-pub-1')['isForwarded'], isTrue);
      expect(replayPlaintextOf(fwdPubMessage)['isForwarded'], isTrue);

      // Ordinary control on the same seams: NO marker key anywhere.
      final (_, ordPubMessage) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'ordinary via publish',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'ord-pub-1',
      );
      expect(ordPubMessage!.isForwarded, isFalse);
      expect(
        publishPayloadFor('ord-pub-1').containsKey('isForwarded'),
        isFalse,
        reason: 'ordinary sends must not carry the marker key at all',
      );
      expect(
        replayPlaintextOf(ordPubMessage).containsKey('isForwarded'),
        isFalse,
      );

      // ---- Failed publish: the retained wireEnvelope re-drives the marker.
      bridge.responses['group:publish'] = {
        'ok': false,
        'errorCode': 'PUBLISH_FAILED',
        'errorMessage': 'publish failed',
      };
      final (fwdFailResult, fwdFailMessage) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'forwarded but failed',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'fwd-pub-fail-1',
        isForwarded: true,
      );
      expect(fwdFailResult, SendGroupMessageResult.error);
      expect(fwdFailMessage!.status, 'failed');
      expect(fwdFailMessage.isForwarded, isTrue);
      final failedWire =
          jsonDecode(fwdFailMessage.wireEnvelope!) as Map<String, dynamic>;
      expect(failedWire['isForwarded'], isTrue);
      final (_, ordFailMessage) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'ordinary but failed',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'ord-pub-fail-1',
      );
      expect(
        (jsonDecode(ordFailMessage!.wireEnvelope!) as Map<String, dynamic>)
            .containsKey('isForwarded'),
        isFalse,
      );

      // ---- Reliable mode: the SAME marker rides group:sendReliable.
      bridge.responses['group:publish'] = {'ok': true, 'messageId': 'msg-123'};
      bridge.responses['group:sendReliable'] = {
        'ok': true,
        'messageId': 'fwd-rel-1',
        'publishSucceeded': true,
        'inboxStored': true,
        'expectedRecipientCount': 1,
        'topicPeerCount': 1,
        'connectedTopicPeerCount': 1,
        'recipientPeerIds': <String>['peer-2'],
        'deliveryMode': 'live_and_inbox',
        'envelope': '{"kind":"native-reliable-envelope"}',
      };
      final (fwdRelResult, fwdRelMessage) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'forwarded via reliable',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'fwd-rel-1',
        isForwarded: true,
      );
      expect(fwdRelResult, SendGroupMessageResult.success);
      expect(fwdRelMessage!.isForwarded, isTrue);
      final reliablePayload = _groupSendReliablePayloadForMessage(
        bridge,
        'fwd-rel-1',
      );
      expect(reliablePayload['isForwarded'], isTrue);
      bridge.responses['group:sendReliable'] = {
        'ok': true,
        'messageId': 'ord-rel-1',
        'publishSucceeded': true,
        'inboxStored': true,
        'expectedRecipientCount': 1,
        'topicPeerCount': 1,
        'connectedTopicPeerCount': 1,
        'recipientPeerIds': <String>['peer-2'],
        'deliveryMode': 'live_and_inbox',
        'envelope': '{"kind":"native-reliable-envelope"}',
      };
      final (_, ordRelMessage) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'ordinary via reliable',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'ord-rel-1',
      );
      expect(ordRelMessage!.isForwarded, isFalse);
      expect(
        _groupSendReliablePayloadForMessage(
          bridge,
          'ord-rel-1',
        ).containsKey('isForwarded'),
        isFalse,
      );
    },
  );

  test(
    'OB-002 publish failure emits safe group epoch and message metadata',
    () async {
      const groupId = 'group-ob002-publish-failure';
      const messageId = 'ob002-message-publish-failure';
      await groupRepo.saveGroup(
        GroupModel(
          id: groupId,
          name: 'OB-002 Publish Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/$groupId',
          createdAt: DateTime.utc(2026, 5, 14, 6, 53),
          createdBy: 'peer-1',
          myRole: GroupRole.admin,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'peer-1',
          username: 'Alice',
          role: MemberRole.admin,
          publicKey: 'pk-1',
          joinedAt: DateTime.utc(2026, 5, 14, 6, 53),
        ),
      );
      await _saveGroupKey(groupRepo, groupId, generation: 7);
      bridge.responses['group:publish'] = {
        'ok': false,
        'errorCode': 'PUBLISH_FAILED',
        'errorMessage': 'publish failed',
      };

      final events = await captureFlowEvents(() async {
        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: groupId,
          text: 'diagnostic publish failure',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: messageId,
        );

        expect(result, SendGroupMessageResult.error);
        expect(message, isNotNull);
        expect(message!.status, 'failed');
      });

      final errorEvent = events.singleWhere(
        (event) => event['event'] == 'GROUP_SEND_MSG_USE_CASE_PUBLISH_ERROR',
      );
      final failedEvent = events.singleWhere(
        (event) => event['event'] == 'GROUP_SEND_MSG_USE_CASE_PUBLISH_FAILED',
      );

      for (final event in [errorEvent, failedEvent]) {
        final details = event['details'] as Map<String, dynamic>;
        expect(details['groupId'], groupId.substring(0, 8));
        expect(details['keyEpoch'], 7);
        expect(details['messageId'], messageId.substring(0, 8));
        expect(details['errorCode'], 'PUBLISH_FAILED');

        final encoded = jsonEncode(details);
        expect(encoded, isNot(contains(groupId)));
        expect(encoded, isNot(contains(messageId)));
      }
    },
  );

  test('OB-008 degraded send branches map to one retry owner', () async {
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-2',
        username: 'Bob',
        role: MemberRole.writer,
        publicKey: 'pk-2',
        joinedAt: DateTime.utc(2026, 5, 14, 7, 28),
      ),
    );

    Future<GroupMessage> sendBranch({
      required FakeBridge branchBridge,
      required String messageId,
      required String text,
      required SendGroupMessageResult expectedResult,
    }) async {
      final (result, message) = await sendGroupMessage(
        bridge: branchBridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: text,
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: messageId,
      );

      expect(result, expectedResult);
      expect(message, isNotNull);
      final saved = await msgRepo.getMessage(messageId);
      expect(saved, isNotNull);
      return saved!;
    }

    final pendingInboxBridge = _InboxStoreOkFalseBridge()
      ..responses['group:publish'] = {
        'ok': true,
        'messageId': 'ob008-pending-inbox-owner',
        'topicPeers': 1,
      };
    final pendingInbox = await sendBranch(
      branchBridge: pendingInboxBridge,
      messageId: 'ob008-pending-inbox-owner',
      text: 'OB-008 pending inbox owner',
      expectedResult: SendGroupMessageResult.success,
    );
    expect(pendingInbox.status, 'sent');
    expect(pendingInbox.wireEnvelope, isNull);
    expect(pendingInbox.inboxStored, isFalse);
    expect(pendingInbox.inboxRetryPayload, isNotNull);

    final failedBothBridge = _InboxStoreOkFalseBridge()
      ..responses['group:publish'] = {
        'ok': false,
        'errorCode': 'PUBLISH_FAILED',
      };
    final failedBoth = await sendBranch(
      branchBridge: failedBothBridge,
      messageId: 'ob008-failed-both-owner',
      text: 'OB-008 failed both owner',
      expectedResult: SendGroupMessageResult.error,
    );
    expect(failedBoth.status, 'failed');
    expect(failedBoth.wireEnvelope, isNotNull);
    expect(failedBoth.inboxStored, isFalse);
    expect(failedBoth.inboxRetryPayload, isNotNull);

    final failedPublishInboxOkBridge = FakeBridge()
      ..responses['group:publish'] = {
        'ok': false,
        'errorCode': 'PUBLISH_FAILED',
      };
    final failedPublishInboxOk = await sendBranch(
      branchBridge: failedPublishInboxOkBridge,
      messageId: 'ob008-failed-publish-inbox-ok',
      text: 'OB-008 failed publish inbox ok',
      expectedResult: SendGroupMessageResult.error,
    );
    expect(failedPublishInboxOk.status, 'failed');
    expect(failedPublishInboxOk.inboxStored, isTrue);
    expect(failedPublishInboxOk.inboxRetryPayload, isNull);

    final zeroPeerInboxFailBridge = _InboxStoreOkFalseBridge()
      ..responses['group:publish'] = {
        'ok': true,
        'messageId': 'ob008-zero-peer-inbox-fail',
        'topicPeers': 0,
      };
    final zeroPeerInboxFail = await sendBranch(
      branchBridge: zeroPeerInboxFailBridge,
      messageId: 'ob008-zero-peer-inbox-fail',
      text: 'OB-008 zero peer inbox fail',
      expectedResult: SendGroupMessageResult.error,
    );
    expect(zeroPeerInboxFail.status, 'failed');
    expect(zeroPeerInboxFail.inboxStored, isFalse);
    expect(zeroPeerInboxFail.inboxRetryPayload, isNotNull);

    final timeoutCustodyBridge = FakeBridge()
      ..responses['group:publish'] = {
        'ok': false,
        'errorCode': 'BRIDGE_TIMEOUT',
        'errorMessage': 'publish timed out',
      };
    final timeoutCustody = await sendBranch(
      branchBridge: timeoutCustodyBridge,
      messageId: 'ob008-timeout-durable-custody',
      text: 'OB-008 timeout durable custody',
      expectedResult: SendGroupMessageResult.success,
    );
    expect(timeoutCustody.status, 'sent');
    expect(timeoutCustody.inboxStored, isTrue);
    expect(timeoutCustody.wireEnvelope, isNull);
    expect(timeoutCustody.inboxRetryPayload, isNull);

    final failedMessageOwnerIds = (await msgRepo.getFailedOutgoingMessages())
        .map((row) => row.id)
        .toSet();
    final inboxRetryOwnerIds = (await msgRepo.getMessagesWithFailedInboxStore())
        .map((row) => row.id)
        .toSet();

    expect(inboxRetryOwnerIds, {'ob008-pending-inbox-owner'});
    expect(failedMessageOwnerIds, {
      'ob008-failed-both-owner',
      'ob008-failed-publish-inbox-ok',
      'ob008-zero-peer-inbox-fail',
    });
    expect(failedMessageOwnerIds.intersection(inboxRetryOwnerIds), isEmpty);
    expect(
      failedMessageOwnerIds.contains('ob008-timeout-durable-custody'),
      isFalse,
    );
    expect(
      inboxRetryOwnerIds.contains('ob008-timeout-durable-custody'),
      isFalse,
    );
  });

  test('GM-032 empty active membership disables publish and inbox', () async {
    await groupRepo.removeAllMembers(testGroup.id);

    final (result, message) = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'GM-032 should not leave local device',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
      messageId: 'gm032-empty-membership',
    );

    expect(result, SendGroupMessageResult.groupDissolved);
    expect(message, isNull);
    expect(bridge.commandLog, isNot(contains('group:publish')));
    expect(bridge.commandLog, isNot(contains('group:inboxStore')));
    expect(await msgRepo.getMessageCount('group-1'), 0);
  });

  test(
    'initialized primary strict send resolves registered device distinct from member peer id',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: testGroup.id,
          peerId: 'peer-1',
          username: 'Alice',
          role: MemberRole.admin,
          publicKey: 'pk-1',
          devices: const [
            GroupMemberDeviceIdentity(
              deviceId: 'peer-1-device-a',
              transportPeerId: 'peer-1-device-a',
              deviceSigningPublicKey: 'pk-1',
              mlKemPublicKey: 'mlkem-peer-1-device-a',
              keyPackageId: 'kp-peer-1-device-a',
            ),
          ],
          joinedAt: DateTime.utc(2026, 5, 1, 12),
        ),
      );

      final strictRepo = _StrictContentMessageRepository();
      final strictStore = _StrictContentInboxStore();
      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: strictRepo,
        groupId: 'group-1',
        text: 'Hello from registered device',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'registered-device-send',
        groupContentAuthoring: GroupContentAuthoringContext(
          directLinkedDeviceSelector:
              const DirectLinkedDeviceSelector.enabled(),
          multiDeviceSyncEnabled: true,
          authorityVersion: GroupContentAuthorityVersion(
            eventAt: DateTime.utc(2026, 8, 13, 11),
            eventId: 'authority.registered-device-send',
            keyEpoch: 1,
          ),
          inboxStore: strictStore,
        ),
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      expect(message!.transportPeerId, 'peer-1-device-a');

      expect(strictStore.recipients, isEmpty);
      expect(
        bridge.commandLog.where(
          (command) =>
              command == 'group:publish' || command == 'group:sendReliable',
        ),
        isEmpty,
      );
      final saved = await strictRepo.getMessage('registered-device-send');
      expect(saved, isNotNull);
      expect(
        saved!.wireEnvelope,
        isNull,
        reason: 'terminal strict content must not retain remintable wire bytes',
      );
    },
  );

  test(
    'initialized primary strict send honors requested same-key sibling transport',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: testGroup.id,
          peerId: 'peer-1',
          username: 'Alice',
          role: MemberRole.admin,
          publicKey: 'pk-1',
          devices: const [
            GroupMemberDeviceIdentity(
              deviceId: 'peer-1-device-a',
              transportPeerId: 'peer-1-device-a',
              deviceSigningPublicKey: 'pk-1',
              mlKemPublicKey: 'mlkem-peer-1-device-a',
              keyPackageId: 'kp-peer-1-device-a',
            ),
            GroupMemberDeviceIdentity(
              deviceId: 'peer-1-device-b',
              transportPeerId: 'peer-1-device-b',
              deviceSigningPublicKey: 'pk-1',
              mlKemPublicKey: 'mlkem-peer-1-device-b',
              keyPackageId: 'kp-peer-1-device-b',
            ),
          ],
          joinedAt: DateTime.utc(2026, 5, 1, 12),
        ),
      );

      final strictRepo = _StrictContentMessageRepository();
      final strictStore = _StrictContentInboxStore();
      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: strictRepo,
        groupId: 'group-1',
        text: 'Hello from sibling device',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'same-key-sibling-send',
        senderDeviceId: 'peer-1-device-b',
        senderTransportPeerId: 'peer-1-device-b',
        groupContentAuthoring: GroupContentAuthoringContext(
          directLinkedDeviceSelector:
              const DirectLinkedDeviceSelector.enabled(),
          multiDeviceSyncEnabled: true,
          authorityVersion: GroupContentAuthorityVersion(
            eventAt: DateTime.utc(2026, 8, 13, 11),
            eventId: 'authority.same-key-sibling-send',
            keyEpoch: 1,
          ),
          inboxStore: strictStore,
        ),
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      expect(message!.transportPeerId, 'peer-1-device-b');

      expect(strictStore.recipients, <String>['peer-1-device-a']);
      expect(
        bridge.commandLog.where(
          (command) =>
              command == 'group:publish' || command == 'group:sendReliable',
        ),
        isEmpty,
      );
      final saved = await strictRepo.getMessage('same-key-sibling-send');
      expect(saved, isNotNull);
      expect(
        saved!.wireEnvelope,
        isNull,
        reason: 'terminal strict content must not retain remintable wire bytes',
      );
    },
  );

  test(
    'initialized primary strict send excludes current transport but retains sibling',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: testGroup.id,
          peerId: 'peer-1',
          username: 'Alice',
          role: MemberRole.admin,
          publicKey: 'pk-1',
          devices: const [
            GroupMemberDeviceIdentity(
              deviceId: 'peer-1-device-a',
              transportPeerId: 'peer-1-device-a',
              deviceSigningPublicKey: 'pk-1',
              mlKemPublicKey: 'mlkem-peer-1-device-a',
              keyPackageId: 'kp-peer-1-device-a',
            ),
            GroupMemberDeviceIdentity(
              deviceId: 'peer-1-device-b',
              transportPeerId: 'peer-1-device-b',
              deviceSigningPublicKey: 'pk-1',
              mlKemPublicKey: 'mlkem-peer-1-device-b',
              keyPackageId: 'kp-peer-1-device-b',
            ),
          ],
          joinedAt: DateTime.utc(2026, 5, 1, 12),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: testGroup.id,
          peerId: 'peer-2',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-2',
          joinedAt: DateTime.utc(2026, 5, 1, 12, 1),
        ),
      );
      final strictRepo = _StrictContentMessageRepository();
      final strictStore = _StrictContentInboxStore();
      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: strictRepo,
        groupId: 'group-1',
        text: 'Hello sibling device',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'ordinary-multi-device-send',
        senderDeviceId: 'peer-1-device-a',
        senderTransportPeerId: 'peer-1-device-a',
        groupContentAuthoring: GroupContentAuthoringContext(
          directLinkedDeviceSelector:
              const DirectLinkedDeviceSelector.enabled(),
          multiDeviceSyncEnabled: true,
          authorityVersion: GroupContentAuthorityVersion(
            eventAt: DateTime.utc(2026, 8, 13, 11),
            eventId: 'authority.ordinary-multi-device-send',
            keyEpoch: 1,
          ),
          inboxStore: strictStore,
        ),
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      expect(strictStore.recipients, <String>['peer-1-device-b', 'peer-2']);
      expect(strictStore.recipients, isNot(contains('peer-1-device-a')));
      expect(strictStore.recipients, isNot(contains('peer-1')));
      expect(
        bridge.commandLog.where(
          (command) =>
              command == 'group:publish' || command == 'group:sendReliable',
        ),
        isEmpty,
      );
    },
  );

  test('production send can opt into sender account durable replay', () async {
    bridge.responses['group:sendReliable'] = {
      'ok': true,
      'messageId': 'explicit-sender-durable-replay',
      'publishSucceeded': true,
      'inboxStored': true,
      'expectedRecipientCount': 1,
      'topicPeerCount': 0,
      'recipientPeerIds': <String>['peer-1'],
      'deliveryMode': 'inbox_only',
      'envelope': '{"kind":"native-reliable-envelope"}',
    };

    final (result, message) = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'Hello restored sibling',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
      messageId: 'explicit-sender-durable-replay',
      includeSenderPeerIdInDurableRecipients: true,
    );

    expect(result, SendGroupMessageResult.successNoPeers);
    expect(message, isNotNull);
    final reliablePayload = _groupSendReliablePayloadForMessage(
      bridge,
      'explicit-sender-durable-replay',
    );
    expect(reliablePayload['preserveRecipientPeerIds'], isTrue);
    expect(reliablePayload['recipientPeerIds'], <String>['peer-1']);
  });

  test('emits GROUP_SEND_MSG_TIMING with group and media metadata', () async {
    bridge.responses['group:publish'] = {
      'ok': true,
      'messageId': 'msg-flow-proof',
      'topicPeers': 1,
    };

    final events = await captureFlowEvents(() async {
      await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Hello group!',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );
    });

    final begin = events.firstWhere(
      (event) => event['event'] == 'GROUP_SEND_MSG_USE_CASE_BEGIN',
    );
    expect(begin['details']['groupId'], 'group-1');
    expect(begin['details']['textLength'], 'Hello group!'.length);

    final success = events.firstWhere(
      (event) => event['event'] == 'GROUP_SEND_MSG_USE_CASE_SUCCESS',
    );
    expect(success['details']['messageId'], hasLength(8));
    expect(success['details']['topicPeers'], 1);
    expect(success['details']['inboxOk'], isTrue);
    expect(success['details']['inboxPending'], isFalse);

    final timing = events.lastWhere(
      (event) => event['event'] == 'GROUP_SEND_MSG_TIMING',
    );
    expect(timing['details']['outcome'], 'success');
    expect(timing['details']['groupId'], 'group-1');
    expect(timing['details']['hasMedia'], isFalse);
    expect(timing['details']['elapsedMs'], isA<int>());
  });

  test(
    'group send diagnostics expose fanout evidence without transport identity labels',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: testGroup.id,
          peerId: 'peer-2',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-2',
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      bridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'safe-group-metrics-proof',
        'topicPeers': 1,
      };

      final events = await captureFlowEvents(() async {
        await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Sensitive group body must not become diagnostics',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          senderTransportPeerId: '12D3KooUnsafeGroupTransportPeer',
          messageId: 'safe-group-metrics-proof',
        );
      });

      final success = events.firstWhere(
        (event) => event['event'] == 'GROUP_SEND_MSG_USE_CASE_SUCCESS',
      );
      final details = success['details'] as Map<String, dynamic>;
      expect(details['topicPeers'], 1);
      expect(details['expectedRecipientCount'], 1);
      expect(details['liveFanoutState'], 'full_peers');
      expect(details['inboxStored'], isTrue);
      expect(details['inboxPending'], isFalse);
      expect(details['recipientReceiptClaimed'], isFalse);
      expect(details, isNot(contains('transport')));
      expect(details, isNot(contains('transportPeerId')));
      expect(details, isNot(contains('senderTransportPeerId')));

      _expectNoForbiddenKeys(events, {
        'transport',
        'transportPeerId',
        'senderTransportPeerId',
        'recipientPeerId',
        'recipientPeerIds',
        'senderPeerId',
      });
      _expectNoProtectedFragments(jsonEncode(events), const [
        'Sensitive group body must not become diagnostics',
        '12D3KooUnsafeGroupTransportPeer',
        'textPreview',
      ]);
    },
  );

  test('returns groupNotFound for unknown group', () async {
    final (result, message) = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'nonexistent',
      text: 'Hello',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
    );

    expect(result, SendGroupMessageResult.groupNotFound);
    expect(message, isNull);
  });

  test('returns groupDissolved for a dissolved group', () async {
    await groupRepo.updateGroup(
      testGroup.copyWith(
        isDissolved: true,
        dissolvedAt: DateTime.utc(2026, 4, 5, 12, 0, 0),
        dissolvedBy: 'peer-admin',
      ),
    );

    final (result, message) = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'Too late',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
    );

    expect(result, SendGroupMessageResult.groupDissolved);
    expect(message, isNull);
    expect(bridge.commandLog, isNot(contains('group:publish')));
  });

  test('returns unauthorized for non-admin in announcement group', () async {
    final announcementGroup = GroupModel(
      id: 'group-announce',
      name: 'Announcements',
      type: GroupType.announcement,
      topicName: 'group-topic-announce',
      createdAt: DateTime.now().toUtc(),
      createdBy: 'peer-admin',
      myRole: GroupRole.member,
    );
    await groupRepo.saveGroup(announcementGroup);
    await _saveGroupKey(groupRepo, announcementGroup.id);

    final (result, message) = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-announce',
      text: 'Hello',
      senderPeerId: 'peer-2',
      senderPublicKey: 'pk-2',
      senderPrivateKey: 'sk-2',
      senderUsername: 'Bob',
    );

    expect(result, SendGroupMessageResult.unauthorized);
    expect(message, isNull);
  });

  test(
    'returns error for member when bootstrap key is still missing',
    () async {
      final memberGroup = GroupModel(
        id: 'group-bootstrap-pending',
        name: 'Bootstrap Pending',
        type: GroupType.chat,
        topicName: 'group-topic-bootstrap-pending',
        createdAt: DateTime.now().toUtc(),
        createdBy: 'peer-admin',
        myRole: GroupRole.member,
      );
      await groupRepo.saveGroup(memberGroup);
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-bootstrap-pending',
          peerId: 'peer-member',
          username: 'Member',
          role: MemberRole.writer,
          publicKey: 'pk-member',
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-bootstrap-pending',
        text: 'Too early',
        senderPeerId: 'peer-member',
        senderPublicKey: 'pk-member',
        senderPrivateKey: 'sk-member',
        senderUsername: 'Member',
      );

      expect(result, SendGroupMessageResult.error);
      expect(message, isNull);
      expect(bridge.commandLog, isEmpty);
      expect(msgRepo.count, 0);
    },
  );

  test('allows discussion send while group recovery is in progress', () async {
    groupRecoveryGate.begin();
    try {
      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Recovery blocked',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      expect(message!.text, 'Recovery blocked');
    } finally {
      groupRecoveryGate.end();
    }

    expect(bridge.commandLog, contains('group:publish'));
    expect(bridge.commandLog, contains('group:inboxStore'));
    expect(msgRepo.count, 1);
  });

  test(
    'blocks announcement send while group recovery is in progress',
    () async {
      final announcementGroup = GroupModel(
        id: 'group-announce-admin',
        name: 'Announcements',
        type: GroupType.announcement,
        topicName: 'group-topic-announce-admin',
        createdAt: DateTime.now().toUtc(),
        createdBy: 'peer-admin',
        myRole: GroupRole.admin,
      );
      await groupRepo.saveGroup(announcementGroup);
      await _saveGroupKey(groupRepo, announcementGroup.id);

      groupRecoveryGate.begin();
      try {
        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-announce-admin',
          text: 'Resume blocked',
          senderPeerId: 'peer-admin',
          senderPublicKey: 'pk-admin',
          senderPrivateKey: 'sk-admin',
          senderUsername: 'Admin',
        );

        expect(result, SendGroupMessageResult.error);
        expect(message, isNull);
      } finally {
        groupRecoveryGate.end();
      }

      expect(bridge.commandLog, isEmpty);
      expect(msgRepo.count, 0);
    },
  );

  test('saves message to repo on success', () async {
    await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'Hello group!',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
    );

    expect(msgRepo.count, 1);
    final latest = await msgRepo.getLatestMessage('group-1');
    expect(latest, isNotNull);
    expect(latest!.text, 'Hello group!');
  });

  test(
    'PL-001 outgoing unicode and multiline text is identical in live publish and replay payloads',
    () async {
      const messageId = 'pl001-unicode-multiline';
      const pl001Text =
          'PL-001 emoji 👩‍💻🚀\n'
          'RTL مرحبا שלום 123\n'
          'Combining cafe\u0301 na\u0308ive\n'
          'Tabs\tand symbols ✓';
      final sentAt = DateTime.utc(2026, 5, 13, 20, 30);
      await groupRepo.saveMember(
        GroupMember(
          groupId: testGroup.id,
          peerId: 'peer-2',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-2',
          joinedAt: sentAt,
        ),
      );
      bridge.responses['group:publish'] = {
        'ok': true,
        'messageId': messageId,
        'topicPeers': 1,
      };

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: pl001Text,
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: messageId,
        timestamp: sentAt,
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      expect(message!.id, messageId);
      expect(message.text, pl001Text);
      expect(message.keyGeneration, 1);

      final saved = await msgRepo.getMessage(messageId);
      expect(saved, isNotNull);
      expect(saved!.text, pl001Text);
      expect(saved.status, 'sent');

      final publishRaw = bridge.sentMessages.firstWhere((raw) {
        final parsed = jsonDecode(raw) as Map<String, dynamic>;
        return parsed['cmd'] == 'group:publish';
      });
      final publishPayload =
          (jsonDecode(publishRaw) as Map<String, dynamic>)['payload']
              as Map<String, dynamic>;
      expect(publishPayload['messageId'], messageId);
      expect(publishPayload['text'], pl001Text);

      final inboxPayload = _lastGroupInboxStorePayload(bridge);
      final recipientPeerIds =
          (inboxPayload['recipientPeerIds'] as List<dynamic>).cast<String>();
      expect(recipientPeerIds, contains('peer-2'));

      final replayPayload = _decodedGroupInboxReplayPayload(bridge);
      expect(replayPayload['messageId'], messageId);
      expect(replayPayload['keyEpoch'], 1);
      expect(replayPayload['text'], pl001Text);
      expect(replayPayload['timestamp'], sentAt.toIso8601String());
    },
  );

  test(
    'Scenario 3 C send preserves A and B as durable inbox recipients',
    () async {
      final sentAt = DateTime.utc(2026, 5, 28, 12);
      await groupRepo.saveMember(
        GroupMember(
          groupId: testGroup.id,
          peerId: 'peer-2',
          username: 'Bob',
          role: MemberRole.admin,
          publicKey: 'pk-2',
          joinedAt: sentAt.subtract(const Duration(minutes: 2)),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: testGroup.id,
          peerId: 'peer-3',
          username: 'Charlie',
          role: MemberRole.writer,
          publicKey: 'pk-3',
          joinedAt: sentAt.subtract(const Duration(minutes: 1)),
        ),
      );
      bridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'scenario3-charlie-to-ab',
        'topicPeers': 1,
      };

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: testGroup.id,
        text: 'Scenario 3 from C',
        senderPeerId: 'peer-3',
        senderPublicKey: 'pk-3',
        senderPrivateKey: 'sk-3',
        senderUsername: 'Charlie',
        messageId: 'scenario3-charlie-to-ab',
        timestamp: sentAt,
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);

      final inboxPayload = _lastGroupInboxStorePayload(bridge);
      expect(
        inboxPayload['recipientPeerIds'],
        unorderedEquals(<String>['peer-1', 'peer-2']),
      );
      expect(inboxPayload['preserveRecipientPeerIds'], isTrue);

      final replayPayload = _decodedGroupInboxReplayPayload(bridge);
      expect(replayPayload['senderId'], 'peer-3');
      expect(replayPayload['messageId'], 'scenario3-charlie-to-ab');
    },
  );

  test(
    'propagates quotedMessageId through publish, inbox, and saved message',
    () async {
      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Replying in group',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        quotedMessageId: 'msg-parent-1',
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      expect(message!.quotedMessageId, 'msg-parent-1');

      final publishMsg = bridge.sentMessages.firstWhere(
        (m) => (jsonDecode(m) as Map)['cmd'] == 'group:publish',
      );
      final publishPayload =
          (jsonDecode(publishMsg) as Map)['payload'] as Map<String, dynamic>;
      expect(publishPayload['quotedMessageId'], 'msg-parent-1');

      final innerPayload = _decodedGroupInboxReplayPayload(bridge);
      expect(innerPayload['quotedMessageId'], 'msg-parent-1');

      final saved = await msgRepo.getMessage(message.id);
      expect(saved, isNotNull);
      expect(saved!.quotedMessageId, 'msg-parent-1');
    },
  );

  test(
    'PL-004 quoted message id is preserved in publish inbox and sender row',
    () async {
      final sentAt = DateTime.utc(2026, 5, 13, 20, 45);
      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'PL-004 quoted reply',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'pl004-quoted-reply',
        timestamp: sentAt,
        quotedMessageId: 'pl004-visible-parent',
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      expect(message!.quotedMessageId, 'pl004-visible-parent');
      expect(message.id, 'pl004-quoted-reply');
      expect(message.timestamp, sentAt);

      final publishMsg = bridge.sentMessages.firstWhere(
        (m) => (jsonDecode(m) as Map)['cmd'] == 'group:publish',
      );
      final publishPayload =
          (jsonDecode(publishMsg) as Map)['payload'] as Map<String, dynamic>;
      expect(publishPayload['messageId'], 'pl004-quoted-reply');
      expect(publishPayload['quotedMessageId'], 'pl004-visible-parent');

      final innerPayload = _decodedGroupInboxReplayPayload(bridge);
      expect(innerPayload['messageId'], 'pl004-quoted-reply');
      expect(innerPayload['quotedMessageId'], 'pl004-visible-parent');

      final saved = await msgRepo.getMessage('pl004-quoted-reply');
      expect(saved, isNotNull);
      expect(saved!.quotedMessageId, 'pl004-visible-parent');
    },
  );

  test(
    'strips dangerous bidi controls and preserves safe markers across publish, inbox, save, and encrypted inbox payload',
    () async {
      const rawText = 'Hello\u202E\u200E group\u200F!';
      const sanitizedText = 'Hello\u200E group\u200F!';

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: rawText,
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      expect(message!.text, sanitizedText);

      final saved = await msgRepo.getMessage(message.id);
      expect(saved, isNotNull);
      expect(saved!.text, sanitizedText);

      final publishMsg = bridge.sentMessages.firstWhere(
        (m) => (jsonDecode(m) as Map)['cmd'] == 'group:publish',
      );
      final publishPayload =
          (jsonDecode(publishMsg) as Map)['payload'] as Map<String, dynamic>;
      expect(publishPayload['text'], sanitizedText);
      expect(publishPayload['text'], isNot(contains('\u202E')));

      final inboxPayload = _lastGroupInboxStorePayload(bridge);
      expect(inboxPayload.containsKey('pushTitle'), isFalse);
      expect(inboxPayload.containsKey('pushBody'), isFalse);

      final innerPayload = _decodedGroupInboxReplayPayload(bridge);
      expect(innerPayload['text'], sanitizedText);
    },
  );

  test(
    'UP-003 active member without current key cannot send until key is installed',
    () async {
      const groupId = 'group-up003-current-key';
      final memberGroup = GroupModel(
        id: groupId,
        name: 'UP-003 Current Key',
        type: GroupType.chat,
        topicName: 'group-topic-up003-current-key',
        createdAt: DateTime.now().toUtc(),
        createdBy: 'peer-admin',
        myRole: GroupRole.member,
      );
      await groupRepo.saveGroup(memberGroup);
      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'peer-member',
          username: 'Member',
          role: MemberRole.writer,
          publicKey: 'pk-member',
          joinedAt: DateTime.utc(2026, 5, 13),
        ),
      );

      final (blockedResult, blockedMessage) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: groupId,
        text: 'UP-003 no current key',
        senderPeerId: 'peer-member',
        senderPublicKey: 'pk-member',
        senderPrivateKey: 'sk-member',
        senderUsername: 'Member',
      );

      expect(blockedResult, SendGroupMessageResult.error);
      expect(blockedMessage, isNull);
      expect(bridge.commandLog, isEmpty);

      await _saveGroupKey(groupRepo, groupId, generation: 2);
      final (allowedResult, allowedMessage) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: groupId,
        text: 'UP-003 with current key',
        senderPeerId: 'peer-member',
        senderPublicKey: 'pk-member',
        senderPrivateKey: 'sk-member',
        senderUsername: 'Member',
      );

      expect(allowedResult, SendGroupMessageResult.success);
      expect(allowedMessage, isNotNull);
      expect(allowedMessage!.keyGeneration, 2);
    },
  );

  test(
    'SV-003 pending re-add cannot publish until current config and key are installed',
    () async {
      const missingKeyGroupId = 'group-sv003-missing-key';
      final joinedAt = DateTime.utc(2026, 5, 14, 4);
      final pendingKeyGroup = GroupModel(
        id: missingKeyGroupId,
        name: 'SV-003 Missing Key',
        type: GroupType.chat,
        topicName: 'group-topic-sv003-missing-key',
        createdAt: joinedAt,
        createdBy: 'peer-admin',
        myRole: GroupRole.member,
      );
      await groupRepo.saveGroup(pendingKeyGroup);
      await groupRepo.saveMember(
        GroupMember(
          groupId: missingKeyGroupId,
          peerId: 'peer-charlie',
          username: 'Charlie',
          role: MemberRole.writer,
          publicKey: 'pk-charlie',
          joinedAt: joinedAt,
        ),
      );

      final (missingKeyResult, missingKeyMessage) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: missingKeyGroupId,
        text: 'SV-003 missing key',
        senderPeerId: 'peer-charlie',
        senderPublicKey: 'pk-charlie',
        senderPrivateKey: 'sk-charlie',
        senderUsername: 'Charlie',
        messageId: 'sv003-missing-key',
      );

      expect(missingKeyResult, SendGroupMessageResult.error);
      expect(missingKeyMessage, isNull);
      expect(await msgRepo.getMessage('sv003-missing-key'), isNull);
      expect(bridge.commandLog, isEmpty);

      const groupId = 'group-sv003-current-config-key';
      final group = GroupModel(
        id: groupId,
        name: 'SV-003 Current Config Key',
        type: GroupType.chat,
        topicName: 'group-topic-sv003-current-config-key',
        createdAt: joinedAt,
        createdBy: 'peer-admin',
        myRole: GroupRole.member,
      );
      await groupRepo.saveGroup(group);
      await _saveGroupKey(groupRepo, groupId, generation: 2);

      final (
        missingConfigResult,
        missingConfigMessage,
      ) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: groupId,
        text: 'SV-003 missing config',
        senderPeerId: 'peer-charlie',
        senderPublicKey: 'pk-charlie',
        senderPrivateKey: 'sk-charlie',
        senderUsername: 'Charlie',
        messageId: 'sv003-missing-config',
      );

      expect(missingConfigResult, SendGroupMessageResult.unauthorized);
      expect(missingConfigMessage, isNull);
      expect(await msgRepo.getMessage('sv003-missing-config'), isNull);
      expect(bridge.commandLog, isEmpty);

      await groupRepo.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: 'peer-charlie',
          username: 'Charlie',
          role: MemberRole.writer,
          publicKey: 'pk-charlie',
          joinedAt: joinedAt,
        ),
      );
      bridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'sv003-current-send',
        'topicPeers': 0,
      };

      final (currentResult, currentMessage) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: groupId,
        text: 'SV-003 current config and key',
        senderPeerId: 'peer-charlie',
        senderPublicKey: 'pk-charlie',
        senderPrivateKey: 'sk-charlie',
        senderUsername: 'Charlie',
        messageId: 'sv003-current-send',
      );

      expect(currentResult, SendGroupMessageResult.successNoPeers);
      expect(currentMessage, isNotNull);
      expect(currentMessage!.keyGeneration, 2);
      expect(await msgRepo.getMessage('sv003-current-send'), isNotNull);
      expect(bridge.commandLog, contains('group:publish'));
      expect(bridge.commandLog, contains('group:inboxStore'));
      expect(_lastGroupOfflineReplayEnvelope(bridge)['keyEpoch'], 2);
    },
  );

  test('EK004 stores signed offline replay envelope for group_message', () async {
    final (result, message) = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'Hello group!',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
      messageId: 'msg-ek004-offline-replay',
    );

    expect(result, SendGroupMessageResult.success);
    expect(message, isNotNull);
    // Both operations should run (order is non-deterministic due to parallelism)
    expect(bridge.commandLog, contains('group:publish'));
    expect(bridge.commandLog, contains('group:inboxStore'));

    _expectSignedReplayEnvelope(
      _lastGroupOfflineReplayEnvelope(bridge),
      groupId: 'group-1',
      payloadType: 'group_message',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      messageId: 'msg-ek004-offline-replay',
    );
  });

  test(
    'ST-009 full group churn sends to every active max-size recipient',
    () async {
      final joinedAt = DateTime.utc(2026, 5, 16, 9, 9);
      const bobPeerId = 'peer-st009-bob';
      const charliePeerId = 'peer-st009-charlie';

      Future<void> saveMember({
        required String peerId,
        required String username,
        required DateTime joinedAt,
      }) async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: peerId,
            username: username,
            role: MemberRole.writer,
            publicKey: 'pk-$peerId',
            mlKemPublicKey: 'mlkem-$peerId',
            joinedAt: joinedAt,
          ),
        );
      }

      await saveMember(
        peerId: bobPeerId,
        username: 'Bob',
        joinedAt: joinedAt.add(const Duration(minutes: 1)),
      );
      await saveMember(
        peerId: charliePeerId,
        username: 'Charlie',
        joinedAt: joinedAt.add(const Duration(minutes: 2)),
      );
      for (var index = 0; index < groupMembershipLimit - 3; index++) {
        final peerId = 'peer-st009-synth-${index.toString().padLeft(2, '0')}';
        await saveMember(
          peerId: peerId,
          username: 'Synthetic $index',
          joinedAt: joinedAt.add(Duration(minutes: 3 + index)),
        );
      }

      expect(
        (await groupRepo.getMembers('group-1')).length,
        groupMembershipLimit,
      );

      List<String> recipientPeerIdsForLastInboxStore() {
        final inboxPayload = _lastGroupInboxStorePayload(bridge);
        return (inboxPayload['recipientPeerIds'] as List<dynamic>)
            .cast<String>();
      }

      await groupRepo.removeMember('group-1', charliePeerId);
      expect((await groupRepo.getMembers('group-1')).length, 49);
      bridge.sentMessages.clear();
      bridge.commandLog.clear();

      final (
        removedWindowResult,
        removedWindowMessage,
      ) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'ST-009 removed-window max-size send',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'st009-removed-window-send',
        timestamp: joinedAt.add(const Duration(hours: 1)),
      );

      expect(removedWindowResult, SendGroupMessageResult.success);
      expect(removedWindowMessage, isNotNull);
      final removedWindowRecipients = recipientPeerIdsForLastInboxStore();
      expect(removedWindowRecipients, hasLength(groupMembershipLimit - 2));
      expect(removedWindowRecipients, contains(bobPeerId));
      expect(removedWindowRecipients, isNot(contains(charliePeerId)));
      expect(removedWindowRecipients, isNot(contains('peer-1')));
      expect(
        removedWindowRecipients,
        hasLength(removedWindowRecipients.toSet().length),
      );

      await saveMember(
        peerId: charliePeerId,
        username: 'Charlie',
        joinedAt: joinedAt.add(const Duration(hours: 2)),
      );
      expect(
        (await groupRepo.getMembers('group-1')).length,
        groupMembershipLimit,
      );
      bridge.sentMessages.clear();
      bridge.commandLog.clear();

      final (postReaddResult, postReaddMessage) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'ST-009 post-readd max-size send',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'st009-post-readd-send',
        timestamp: joinedAt.add(const Duration(hours: 3)),
      );

      expect(postReaddResult, SendGroupMessageResult.success);
      expect(postReaddMessage, isNotNull);
      final postReaddRecipients = recipientPeerIdsForLastInboxStore();
      expect(postReaddRecipients, hasLength(groupMembershipLimit - 1));
      expect(postReaddRecipients, contains(bobPeerId));
      expect(postReaddRecipients, contains(charliePeerId));
      expect(postReaddRecipients, isNot(contains('peer-1')));
      expect(
        postReaddRecipients,
        hasLength(postReaddRecipients.toSet().length),
      );
    },
  );

  test('ML-003 B post-add send stores durable replay for offline D', () async {
    final joinedAt = DateTime.utc(2026, 5, 11, 9);
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-2',
        username: 'Bob',
        role: MemberRole.writer,
        publicKey: 'pk-2',
        joinedAt: joinedAt,
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-3',
        username: 'Charlie',
        role: MemberRole.writer,
        publicKey: 'pk-3',
        joinedAt: joinedAt,
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-4',
        username: 'Dana',
        role: MemberRole.writer,
        publicKey: 'pk-4',
        joinedAt: joinedAt.add(const Duration(minutes: 1)),
      ),
    );

    final (result, message) = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'ML-003 Bob post-add while Dana is offline',
      senderPeerId: 'peer-2',
      senderPublicKey: 'pk-2',
      senderPrivateKey: 'sk-2',
      senderUsername: 'Bob',
      messageId: 'ml003-b-post-add',
      timestamp: joinedAt.add(const Duration(minutes: 2)),
    );

    expect(result, SendGroupMessageResult.success);
    expect(message, isNotNull);
    final inboxPayload = _lastGroupInboxStorePayload(bridge);
    expect(
      inboxPayload['recipientPeerIds'],
      unorderedEquals(['peer-1', 'peer-3', 'peer-4']),
    );
    expect(message!.inboxStored, isTrue);
    expect(message.inboxRetryPayload, isNull);
  });

  test(
    'group send loads members and excludes sender from push recipients',
    () async {
      final joinedAt = DateTime.utc(2026, 1, 1);
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-1',
          username: 'Alice',
          role: MemberRole.admin,
          joinedAt: joinedAt,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-2',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-2',
          joinedAt: joinedAt.add(const Duration(seconds: 1)),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-3',
          username: 'Cara',
          role: MemberRole.reader,
          publicKey: 'pk-3',
          joinedAt: joinedAt.add(const Duration(seconds: 2)),
        ),
      );

      await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Hello group!',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );

      final inboxPayload = _lastGroupInboxStorePayload(bridge);
      expect(
        inboxPayload['recipientPeerIds'],
        unorderedEquals(['peer-2', 'peer-3']),
      );
      expect(inboxPayload.containsKey('pushTitle'), isFalse);
      expect(inboxPayload.containsKey('pushBody'), isFalse);
    },
  );

  test(
    'GM-027 pre-existing ghost member is excluded from durable recipients',
    () async {
      final failBridge = _InboxStoreFailBridge();
      failBridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'gm027-valid-send',
        'topicPeers': 2,
      };
      final joinedAt = DateTime.utc(2026, 5, 11, 10);
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-2',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-2',
          mlKemPublicKey: 'mlkem-peer-2',
          joinedAt: joinedAt,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-gm027-ghost',
          username: 'Ghost',
          role: MemberRole.writer,
          joinedAt: joinedAt.add(const Duration(seconds: 1)),
        ),
      );

      final (result, message) = await sendGroupMessage(
        bridge: failBridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'GM-027 valid delivery survives ghost recipient',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'gm027-valid-send',
        timestamp: joinedAt.add(const Duration(minutes: 1)),
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      final inboxPayload = _groupInboxStorePayloadForMessage(
        failBridge,
        'gm027-valid-send',
      );
      expect(inboxPayload['recipientPeerIds'], <String>['peer-2']);
      expect(
        inboxPayload['recipientPeerIds'],
        isNot(contains('peer-gm027-ghost')),
      );
      final saved = await msgRepo.getMessage('gm027-valid-send');
      expect(saved?.inboxRetryPayload, isNotNull);
      expect(
        _recipientPeerIdsFromRetryPayload(saved!.inboxRetryPayload!),
        <String>['peer-2'],
      );
    },
  );

  test(
    'GM-028 pre-existing empty PeerId member is excluded from durable recipients',
    () async {
      final failBridge = _InboxStoreFailBridge();
      failBridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'gm028-valid-send',
        'topicPeers': 2,
      };
      final joinedAt = DateTime.utc(2026, 5, 11, 10, 30);
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-2',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-2',
          mlKemPublicKey: 'mlkem-peer-2',
          joinedAt: joinedAt,
        ),
      );
      await groupRepo.saveMemberBypassingValidationForTest(
        GroupMember(
          groupId: 'group-1',
          peerId: '   ',
          username: 'Blank Peer',
          role: MemberRole.writer,
          publicKey: 'pk-gm028-blank',
          mlKemPublicKey: 'mlkem-gm028-blank',
          devices: const <GroupMemberDeviceIdentity>[
            GroupMemberDeviceIdentity(
              deviceId: 'gm028-blank-device',
              transportPeerId: 'gm028-blank-device',
              deviceSigningPublicKey: 'pk-gm028-blank-device',
              mlKemPublicKey: 'mlkem-gm028-blank-device',
              keyPackageId: 'kp-gm028-blank-device',
              keyPackagePublicMaterial: 'public-kp-gm028-blank-device',
            ),
          ],
          joinedAt: joinedAt.add(const Duration(seconds: 1)),
        ),
      );

      final (result, message) = await sendGroupMessage(
        bridge: failBridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'GM-028 valid delivery survives blank peer recipient',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'gm028-valid-send',
        timestamp: joinedAt.add(const Duration(minutes: 1)),
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      final inboxPayload = _groupInboxStorePayloadForMessage(
        failBridge,
        'gm028-valid-send',
      );
      expect(inboxPayload['recipientPeerIds'], <String>['peer-2']);
      expect(inboxPayload['recipientPeerIds'], isNot(contains('')));
      expect(inboxPayload['recipientPeerIds'], isNot(contains('   ')));
      final saved = await msgRepo.getMessage('gm028-valid-send');
      expect(saved?.inboxRetryPayload, isNotNull);
      expect(
        _recipientPeerIdsFromRetryPayload(saved!.inboxRetryPayload!),
        <String>['peer-2'],
      );
    },
  );

  test(
    'GM-019 removed-window durable recipients exclude re-added member until re-add',
    () async {
      final failBridge = _InboxStoreFailBridge();
      failBridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'gm019',
        'topicPeers': 2,
      };
      final joinedAt = DateTime.utc(2026, 5, 11, 8);
      final removedWindowSentAt = joinedAt.add(const Duration(minutes: 5));
      final readdAt = joinedAt.add(const Duration(minutes: 10));
      await groupRepo.saveGroup(
        testGroup.copyWith(
          createdAt: joinedAt.subtract(const Duration(minutes: 1)),
        ),
      );

      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-1',
          username: 'Alice',
          role: MemberRole.admin,
          joinedAt: joinedAt,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-2',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-2',
          joinedAt: joinedAt.add(const Duration(seconds: 1)),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-3',
          username: 'Charlie',
          role: MemberRole.writer,
          publicKey: 'pk-3',
          joinedAt: readdAt,
        ),
      );

      final (removedResult, removedMessage) = await sendGroupMessage(
        bridge: failBridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'GM-019 removed-window durable',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'gm019-removed-window',
        timestamp: removedWindowSentAt,
      );

      expect(removedResult, SendGroupMessageResult.success);
      expect(removedMessage, isNotNull);
      final removedPayload = _groupInboxStorePayloadForMessage(
        failBridge,
        'gm019-removed-window',
      );
      expect(removedPayload['recipientPeerIds'], <String>['peer-2']);
      final removedSaved = await msgRepo.getMessage('gm019-removed-window');
      expect(removedSaved?.inboxRetryPayload, isNotNull);
      expect(
        _recipientPeerIdsFromRetryPayload(removedSaved!.inboxRetryPayload!),
        <String>['peer-2'],
      );

      final (postReaddResult, postReaddMessage) = await sendGroupMessage(
        bridge: failBridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'GM-019 post-readd durable',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'gm019-post-readd',
        timestamp: readdAt.add(const Duration(seconds: 1)),
      );

      expect(postReaddResult, SendGroupMessageResult.success);
      expect(postReaddMessage, isNotNull);
      final postReaddPayload = _groupInboxStorePayloadForMessage(
        failBridge,
        'gm019-post-readd',
      );
      expect(
        postReaddPayload['recipientPeerIds'],
        unorderedEquals(<String>['peer-2', 'peer-3']),
      );
      expect(
        postReaddPayload['recipientPeerIds'],
        hasLength(
          (postReaddPayload['recipientPeerIds'] as List).toSet().length,
        ),
      );
      final postReaddSaved = await msgRepo.getMessage('gm019-post-readd');
      expect(postReaddSaved?.inboxRetryPayload, isNotNull);
      expect(
        _recipientPeerIdsFromRetryPayload(
          postReaddSaved!.inboxRetryPayload!,
        ).toSet(),
        <String>{'peer-2', 'peer-3'},
      );
    },
  );

  test(
    'GI-004 group inbox recipients follow current remove and re-add entitlement windows',
    () async {
      final joinedAt = DateTime.utc(2026, 5, 13, 8);
      final removedWindowSentAt = joinedAt.add(const Duration(minutes: 6));
      final readdAt = joinedAt.add(const Duration(minutes: 10));
      await groupRepo.saveGroup(
        testGroup.copyWith(
          createdAt: joinedAt.subtract(const Duration(minutes: 1)),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-1',
          username: 'Alice',
          role: MemberRole.admin,
          publicKey: 'pk-1',
          joinedAt: joinedAt,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-2',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-2',
          joinedAt: joinedAt.add(const Duration(seconds: 1)),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-3',
          username: 'Charlie',
          role: MemberRole.writer,
          publicKey: 'pk-3',
          joinedAt: joinedAt.add(const Duration(seconds: 2)),
        ),
      );
      await groupRepo.removeMember('group-1', 'peer-3');

      bridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'gi004-removed-window',
        'topicPeers': 1,
      };
      final (removedResult, removedMessage) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'GI-004 removed-window durable',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'gi004-removed-window',
        timestamp: removedWindowSentAt,
      );

      expect(removedResult, SendGroupMessageResult.success);
      expect(removedMessage, isNotNull);
      final removedPayload = _groupInboxStorePayloadForMessage(
        bridge,
        'gi004-removed-window',
      );
      final removedRecipients = (removedPayload['recipientPeerIds'] as List)
          .cast<String>();
      expect(removedRecipients, <String>['peer-2']);
      expect(removedRecipients, isNot(contains('peer-1')));
      expect(removedRecipients, isNot(contains('peer-3')));

      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-3',
          username: 'Charlie',
          role: MemberRole.writer,
          publicKey: 'pk-3-readded',
          joinedAt: readdAt,
        ),
      );
      bridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'gi004-post-readd',
        'topicPeers': 1,
      };
      final (postReaddResult, postReaddMessage) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'GI-004 post-readd durable',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'gi004-post-readd',
        timestamp: readdAt.add(const Duration(seconds: 1)),
      );

      expect(postReaddResult, SendGroupMessageResult.success);
      expect(postReaddMessage, isNotNull);
      final postReaddPayload = _groupInboxStorePayloadForMessage(
        bridge,
        'gi004-post-readd',
      );
      final postReaddRecipients = (postReaddPayload['recipientPeerIds'] as List)
          .cast<String>();
      expect(
        postReaddRecipients,
        unorderedEquals(<String>['peer-2', 'peer-3']),
      );
      expect(postReaddRecipients, isNot(contains('peer-1')));
      expect(
        postReaddRecipients,
        hasLength(postReaddRecipients.toSet().length),
      );
    },
  );

  test(
    'IR-006 group inbox store targets exact active recipients at send time',
    () async {
      final joinedAt = DateTime.utc(2026, 5, 12, 9);
      const activePeerId = 'peer-2';
      const removedPeerId = 'peer-3';
      const declinedPeerId = 'peer-declined';
      const expiredPeerId = 'peer-expired';
      const neverJoinedPeerId = 'peer-never-joined';
      await groupRepo.saveGroup(
        testGroup.copyWith(
          createdAt: joinedAt.subtract(const Duration(minutes: 1)),
        ),
      );

      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: activePeerId,
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-2',
          joinedAt: joinedAt.add(const Duration(minutes: 1)),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: removedPeerId,
          username: 'Charlie',
          role: MemberRole.writer,
          publicKey: 'pk-3',
          joinedAt: joinedAt.add(const Duration(minutes: 2)),
        ),
      );
      await groupRepo.removeMember('group-1', removedPeerId);

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'IR-006 active recipient only',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'ir006-active-recipient-only',
        timestamp: joinedAt.add(const Duration(minutes: 3)),
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      expect(message!.inboxStored, isTrue);

      final inboxPayload = _lastGroupInboxStorePayload(bridge);
      final recipientPeerIds =
          (inboxPayload['recipientPeerIds'] as List<dynamic>).cast<String>();
      expect(recipientPeerIds, <String>[activePeerId]);
      expect(recipientPeerIds, isNot(contains('peer-1')));
      expect(recipientPeerIds, isNot(contains(removedPeerId)));
      expect(recipientPeerIds, isNot(contains(declinedPeerId)));
      expect(recipientPeerIds, isNot(contains(expiredPeerId)));
      expect(recipientPeerIds, isNot(contains(neverJoinedPeerId)));

      final replay = _decodedGroupInboxReplayPayload(bridge);
      expect(replay['messageId'], 'ir006-active-recipient-only');
      expect(replay['senderId'], 'peer-1');
    },
  );

  test(
    'INV-106 excludes persisted non-joined invite attempts from every ordinary send recipient list',
    () async {
      final joinedAt = DateTime.utc(2026, 6, 4, 8);
      const bobPeerId = 'peer-accepted-bob';
      const charliePeerId = 'peer-invited-charlie';

      await groupRepo.saveGroup(
        testGroup.copyWith(
          createdAt: joinedAt.subtract(const Duration(minutes: 1)),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: bobPeerId,
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-bob-accepted',
          joinedAt: joinedAt,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: charliePeerId,
          username: 'Charlie',
          role: MemberRole.writer,
          publicKey: 'pk-charlie-invited',
          joinedAt: joinedAt,
        ),
      );

      Future<void> expectRecipients({
        required String messageId,
        required GroupInviteDeliveryStatus charlieStatus,
        GroupInviteDeliveryStatus? bobStatus,
      }) async {
        final attemptRepo = _InMemoryInviteDeliveryAttemptRepository();
        final attemptAt = joinedAt.add(const Duration(minutes: 1));
        await attemptRepo.saveAttempt(
          GroupInviteDeliveryAttempt(
            groupId: 'group-1',
            peerId: charliePeerId,
            username: 'Charlie',
            status: charlieStatus,
            attemptedAt: attemptAt,
            updatedAt: attemptAt,
          ),
        );
        if (bobStatus != null) {
          await attemptRepo.saveAttempt(
            GroupInviteDeliveryAttempt(
              groupId: 'group-1',
              peerId: bobPeerId,
              username: 'Bob',
              status: bobStatus,
              attemptedAt: attemptAt,
              updatedAt: attemptAt,
            ),
          );
        }

        final scenarioBridge = _OpaqueReplayInboxStoreFailBridge();
        scenarioBridge.responses['group:publish'] = {
          'ok': true,
          'messageId': messageId,
          'topicPeers': 1,
        };

        final (result, message) = await sendGroupMessage(
          bridge: scenarioBridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'INV-106 accepted recipients only for $messageId',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: messageId,
          timestamp: joinedAt.add(const Duration(minutes: 2)),
          inviteDeliveryAttemptRepo: attemptRepo,
        );

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        expect(message!.inboxRetryPayload, isNotNull);
        expect(
          _recipientPeerIdsFromRetryPayload(message.inboxRetryPayload!),
          <String>[bobPeerId],
          reason: messageId,
        );

        final saved = await msgRepo.getMessage(messageId);
        expect(saved, isNotNull);
        expect(saved!.inboxRetryPayload, isNotNull);
        expect(
          _recipientPeerIdsFromRetryPayload(saved.inboxRetryPayload!),
          <String>[bobPeerId],
          reason: '$messageId saved retry payload',
        );

        final inboxPayload = _lastGroupInboxStorePayload(scenarioBridge);
        expect(
          (inboxPayload['recipientPeerIds'] as List<dynamic>).cast<String>(),
          <String>[bobPeerId],
          reason: '$messageId group:inboxStore',
        );
        expect(
          inboxPayload['recipientPeerIds'],
          isNot(contains(charliePeerId)),
          reason: '$messageId group:inboxStore excludes unaccepted invitee',
        );
        expect(inboxPayload['preserveRecipientPeerIds'], isTrue);

        final reliablePayload = _groupSendReliablePayloadForMessage(
          scenarioBridge,
          messageId,
        );
        expect(
          (reliablePayload['recipientPeerIds'] as List<dynamic>).cast<String>(),
          <String>[bobPeerId],
          reason: '$messageId group:sendReliable',
        );
        expect(
          reliablePayload['recipientPeerIds'],
          isNot(contains(charliePeerId)),
          reason: '$messageId native reliable send excludes unaccepted invitee',
        );
        expect(reliablePayload['preserveRecipientPeerIds'], isTrue);
      }

      for (final status in const [
        GroupInviteDeliveryStatus.sent,
        GroupInviteDeliveryStatus.queued,
        GroupInviteDeliveryStatus.needsResend,
        GroupInviteDeliveryStatus.cannotSend,
      ]) {
        await expectRecipients(
          messageId: 'inv106-${status.toValue()}',
          charlieStatus: status,
        );
      }

      await expectRecipients(
        messageId: 'inv106-joined-control',
        charlieStatus: GroupInviteDeliveryStatus.sent,
        bobStatus: GroupInviteDeliveryStatus.joined,
      );
    },
  );

  test(
    'missing invite-attempt rows are included once joined evidence exists (F7)',
    () async {
      final joinedAt = DateTime.utc(2026, 6, 5, 8);
      const bobPeerId = 'peer-accepted-missing-row-bob';
      const charliePeerId = 'peer-unknown-missing-row-charlie';
      final attemptRepo = _InMemoryInviteDeliveryAttemptRepository();

      await groupRepo.saveGroup(
        testGroup.copyWith(
          createdAt: joinedAt.subtract(const Duration(minutes: 1)),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: bobPeerId,
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-bob-missing-row',
          joinedAt: joinedAt,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: charliePeerId,
          username: 'Charlie',
          role: MemberRole.writer,
          publicKey: 'pk-charlie-missing-row',
          joinedAt: joinedAt.add(const Duration(minutes: 1)),
        ),
      );
      await attemptRepo.markJoined(
        groupId: 'group-1',
        peerId: bobPeerId,
        username: 'Bob',
        joinedAt: joinedAt,
      );

      bridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'inv106-missing-row-leak',
        'topicPeers': 1,
      };

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'INV-106 missing row must fail closed',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'inv106-missing-row-leak',
        timestamp: joinedAt.add(const Duration(minutes: 2)),
        inviteDeliveryAttemptRepo: attemptRepo,
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);

      final inboxPayload = _lastGroupInboxStorePayload(bridge);
      expect(
        (inboxPayload['recipientPeerIds'] as List<dynamic>).cast<String>(),
        unorderedEquals(<String>[bobPeerId, charliePeerId]),
      );

      final reliablePayload = _groupSendReliablePayloadForMessage(
        bridge,
        'inv106-missing-row-leak',
      );
      expect(
        (reliablePayload['recipientPeerIds'] as List<dynamic>).cast<String>(),
        unorderedEquals(<String>[bobPeerId, charliePeerId]),
      );
      expect(reliablePayload['preserveRecipientPeerIds'], isTrue);
    },
  );

  test(
    'later-joined admin with witnessed joins includes unevidenced incumbents',
    () async {
      // F7 repro geometry (plan 318 TC-318-01, the dual-variant killer): the
      // sender is an admin AND holds one joined row, so both legacy tracker
      // arms fire; eve joined before this device existed, so no local invite
      // row and no witnessed join-timeline entry can exist for her.
      final joinedAt = DateTime.utc(2026, 6, 5, 8);
      const frankPeerId = 'peer-witnessed-frank';
      const evePeerId = 'peer-incumbent-eve';
      final attemptRepo = _InMemoryInviteDeliveryAttemptRepository();

      await groupRepo.saveGroup(
        testGroup.copyWith(
          createdAt: joinedAt.subtract(const Duration(minutes: 1)),
          myRole: GroupRole.admin,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: evePeerId,
          username: 'Eve',
          role: MemberRole.writer,
          publicKey: 'pk-eve-incumbent',
          joinedAt: joinedAt,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: frankPeerId,
          username: 'Frank',
          role: MemberRole.writer,
          publicKey: 'pk-frank-witnessed',
          joinedAt: joinedAt.add(const Duration(minutes: 1)),
        ),
      );
      await attemptRepo.markJoined(
        groupId: 'group-1',
        peerId: frankPeerId,
        username: 'Frank',
        joinedAt: joinedAt.add(const Duration(minutes: 1)),
      );

      bridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'f7-admin-witnessed-joins',
        'topicPeers': 2,
      };

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'custody must include every unevidenced incumbent',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Dave',
        messageId: 'f7-admin-witnessed-joins',
        timestamp: joinedAt.add(const Duration(minutes: 2)),
        inviteDeliveryAttemptRepo: attemptRepo,
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);

      final inboxPayload = _lastGroupInboxStorePayload(bridge);
      expect(
        (inboxPayload['recipientPeerIds'] as List<dynamic>).cast<String>(),
        unorderedEquals(<String>[frankPeerId, evePeerId]),
      );

      final reliablePayload = _groupSendReliablePayloadForMessage(
        bridge,
        'f7-admin-witnessed-joins',
      );
      expect(
        (reliablePayload['recipientPeerIds'] as List<dynamic>).cast<String>(),
        unorderedEquals(<String>[frankPeerId, evePeerId]),
      );
      expect(reliablePayload['preserveRecipientPeerIds'], isTrue);
    },
  );

  test('witnessed-join tracker member includes earlier incumbents', () async {
    // F7 widened class (plan 318 TC-318-03): a NON-admin member whose only
    // joined row came from witnessing a later join was still a "tracker"
    // under the legacy predicate and dropped earlier incumbents.
    final joinedAt = DateTime.utc(2026, 6, 5, 8);
    const carolPeerId = 'peer-late-carol';
    const evePeerId = 'peer-earlier-eve';
    final attemptRepo = _InMemoryInviteDeliveryAttemptRepository();

    await groupRepo.saveGroup(
      testGroup.copyWith(
        createdAt: joinedAt.subtract(const Duration(minutes: 1)),
        myRole: GroupRole.member,
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: evePeerId,
        username: 'Eve',
        role: MemberRole.writer,
        publicKey: 'pk-eve-earlier',
        joinedAt: joinedAt,
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: carolPeerId,
        username: 'Carol',
        role: MemberRole.writer,
        publicKey: 'pk-carol-late',
        joinedAt: joinedAt.add(const Duration(minutes: 1)),
      ),
    );
    await attemptRepo.markJoined(
      groupId: 'group-1',
      peerId: carolPeerId,
      username: 'Carol',
      joinedAt: joinedAt.add(const Duration(minutes: 1)),
    );

    bridge.responses['group:publish'] = {
      'ok': true,
      'messageId': 'f7-witness-arm',
      'topicPeers': 2,
    };

    final (result, message) = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'witnessing a join must not shrink custody',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Late Member',
      messageId: 'f7-witness-arm',
      timestamp: joinedAt.add(const Duration(minutes: 2)),
      inviteDeliveryAttemptRepo: attemptRepo,
    );

    expect(result, SendGroupMessageResult.success);
    expect(message, isNotNull);

    final inboxPayload = _lastGroupInboxStorePayload(bridge);
    expect(
      (inboxPayload['recipientPeerIds'] as List<dynamic>).cast<String>(),
      unorderedEquals(<String>[carolPeerId, evePeerId]),
    );
  });

  test(
    'later-joined announcement admin includes unevidenced incumbents',
    () async {
      // Plan 318 TC-318-08: announcements share the send path and every
      // announcement sender is an admin — the headline F7 surface.
      final joinedAt = DateTime.utc(2026, 6, 5, 8);
      const frankPeerId = 'peer-ann-frank';
      const evePeerId = 'peer-ann-eve';
      final attemptRepo = _InMemoryInviteDeliveryAttemptRepository();

      await groupRepo.saveGroup(
        testGroup.copyWith(
          createdAt: joinedAt.subtract(const Duration(minutes: 1)),
          type: GroupType.announcement,
          myRole: GroupRole.admin,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: evePeerId,
          username: 'Eve',
          role: MemberRole.reader,
          publicKey: 'pk-eve-ann',
          joinedAt: joinedAt,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: frankPeerId,
          username: 'Frank',
          role: MemberRole.reader,
          publicKey: 'pk-frank-ann',
          joinedAt: joinedAt.add(const Duration(minutes: 1)),
        ),
      );
      await attemptRepo.markJoined(
        groupId: 'group-1',
        peerId: frankPeerId,
        username: 'Frank',
        joinedAt: joinedAt.add(const Duration(minutes: 1)),
      );

      bridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'f7-announcement',
        'topicPeers': 2,
      };

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'announcement custody must include incumbents',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Dave',
        messageId: 'f7-announcement',
        timestamp: joinedAt.add(const Duration(minutes: 2)),
        inviteDeliveryAttemptRepo: attemptRepo,
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);

      final inboxPayload = _lastGroupInboxStorePayload(bridge);
      expect(
        (inboxPayload['recipientPeerIds'] as List<dynamic>).cast<String>(),
        unorderedEquals(<String>[frankPeerId, evePeerId]),
      );
    },
  );

  test('later-joined admin without invite rows includes incumbents', () async {
    // F7 branch 1 (plan 318 TC-318-02): admin sender, EMPTY invite rows —
    // the legacy admin arm made this device a tracker and its own
    // sys-member_joined timeline entry supplied the joined-evidence that
    // dropped every unevidenced incumbent.
    final joinedAt = DateTime.utc(2026, 6, 5, 8);
    const evePeerId = 'peer-incumbent-no-rows-eve';

    await groupRepo.saveGroup(
      testGroup.copyWith(
        createdAt: joinedAt.subtract(const Duration(minutes: 1)),
        myRole: GroupRole.admin,
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: evePeerId,
        username: 'Eve',
        role: MemberRole.writer,
        publicKey: 'pk-eve-no-rows',
        joinedAt: joinedAt,
      ),
    );
    await msgRepo.saveMessage(
      buildMemberJoinedTimelineMessage(
        groupId: 'group-1',
        joinedPeerId: 'peer-1',
        joinedUsername: 'Dave',
        eventAt: joinedAt.add(const Duration(seconds: 30)),
      ),
    );

    bridge.responses['group:publish'] = {
      'ok': true,
      'messageId': 'f7-admin-no-rows',
      'topicPeers': 1,
    };

    final (result, message) = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'no invite rows must not mean no recipients',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Dave',
      messageId: 'f7-admin-no-rows',
      timestamp: joinedAt.add(const Duration(minutes: 2)),
      inviteDeliveryAttemptRepo: _InMemoryInviteDeliveryAttemptRepository(),
    );

    expect(result, SendGroupMessageResult.success);
    expect(message, isNotNull);

    final inboxPayload = _lastGroupInboxStorePayload(bridge);
    expect(
      (inboxPayload['recipientPeerIds'] as List<dynamic>).cast<String>(),
      <String>[evePeerId],
    );
  });

  test(
    'INV-106 preserves legacy current members when no invite evidence exists',
    () async {
      final joinedAt = DateTime.utc(2026, 6, 5, 9);
      const bobPeerId = 'peer-legacy-bob';
      const charliePeerId = 'peer-legacy-charlie';
      final attemptRepo = _InMemoryInviteDeliveryAttemptRepository();

      await groupRepo.saveGroup(
        testGroup.copyWith(
          createdAt: joinedAt.subtract(const Duration(minutes: 1)),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: bobPeerId,
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-legacy-bob',
          joinedAt: joinedAt,
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: charliePeerId,
          username: 'Charlie',
          role: MemberRole.writer,
          publicKey: 'pk-legacy-charlie',
          joinedAt: joinedAt.add(const Duration(minutes: 1)),
        ),
      );

      bridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'inv106-legacy-no-invite-evidence',
        'topicPeers': 2,
      };

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'INV-106 legacy current members stay eligible',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'inv106-legacy-no-invite-evidence',
        timestamp: joinedAt.add(const Duration(minutes: 2)),
        inviteDeliveryAttemptRepo: attemptRepo,
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);

      final inboxPayload = _lastGroupInboxStorePayload(bridge);
      expect(
        (inboxPayload['recipientPeerIds'] as List<dynamic>).cast<String>(),
        unorderedEquals(<String>[bobPeerId, charliePeerId]),
      );
    },
  );

  test('INV-106 preserves explicit empty accepted recipient lists', () async {
    final joinedAt = DateTime.utc(2026, 6, 4, 8);
    const charliePeerId = 'peer-only-unaccepted-charlie';
    final attemptRepo = _InMemoryInviteDeliveryAttemptRepository();
    final attemptAt = joinedAt.add(const Duration(minutes: 1));

    await groupRepo.saveGroup(
      testGroup.copyWith(
        createdAt: joinedAt.subtract(const Duration(minutes: 1)),
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: charliePeerId,
        username: 'Charlie',
        role: MemberRole.writer,
        publicKey: 'pk-charlie-unaccepted',
        joinedAt: joinedAt,
      ),
    );
    await attemptRepo.saveAttempt(
      GroupInviteDeliveryAttempt(
        groupId: 'group-1',
        peerId: charliePeerId,
        username: 'Charlie',
        status: GroupInviteDeliveryStatus.sent,
        attemptedAt: attemptAt,
        updatedAt: attemptAt,
      ),
    );

    final nativeBridge = FakeBridge();
    nativeBridge.responses['group:sendReliable'] = {
      'ok': true,
      'messageId': 'inv106-empty-native',
      'topicPeerCount': 0,
      'expectedRecipientCount': 0,
      'recipientPeerIds': <String>[],
      'inboxStored': false,
      'publishSucceeded': true,
      'deliveryMode': 'live_only',
      'envelope': '{"kind":"native-reliable-envelope"}',
    };

    final (nativeResult, nativeMessage) = await sendGroupMessage(
      bridge: nativeBridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'INV-106 no accepted remotes native',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
      messageId: 'inv106-empty-native',
      timestamp: joinedAt.add(const Duration(minutes: 2)),
      inviteDeliveryAttemptRepo: attemptRepo,
    );

    expect(nativeResult, SendGroupMessageResult.success);
    expect(nativeMessage, isNotNull);
    final nativeReliablePayload = _groupSendReliablePayloadForMessage(
      nativeBridge,
      'inv106-empty-native',
    );
    expect(nativeReliablePayload.containsKey('recipientPeerIds'), isTrue);
    expect(
      (nativeReliablePayload['recipientPeerIds'] as List<dynamic>)
          .cast<String>(),
      <String>[],
    );
    expect(nativeReliablePayload['preserveRecipientPeerIds'], isTrue);
    expect(
      nativeReliablePayload['recipientPeerIds'],
      isNot(contains(charliePeerId)),
    );
    final nativeRetryPayload =
        jsonDecode(nativeMessage!.inboxRetryPayload!) as Map<String, dynamic>;
    expect(nativeRetryPayload.containsKey('recipientPeerIds'), isTrue);
    expect(
      (nativeRetryPayload['recipientPeerIds'] as List<dynamic>).cast<String>(),
      <String>[],
    );

    final fallbackBridge = FakeBridge();
    fallbackBridge.responses['group:sendReliable'] = {
      'ok': false,
      'errorCode': 'UNKNOWN_COMMAND',
    };
    fallbackBridge.responses['group:publish'] = {
      'ok': true,
      'messageId': 'inv106-empty-fallback',
      'topicPeers': 0,
    };

    final (fallbackResult, fallbackMessage) = await sendGroupMessage(
      bridge: fallbackBridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'INV-106 no accepted remotes fallback',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
      messageId: 'inv106-empty-fallback',
      timestamp: joinedAt.add(const Duration(minutes: 3)),
      inviteDeliveryAttemptRepo: attemptRepo,
    );

    expect(fallbackResult, SendGroupMessageResult.successNoPeers);
    expect(fallbackMessage, isNotNull);
    final fallbackReliablePayload = _groupSendReliablePayloadForMessage(
      fallbackBridge,
      'inv106-empty-fallback',
    );
    expect(fallbackReliablePayload['recipientPeerIds'], <String>[]);
    expect(fallbackReliablePayload['preserveRecipientPeerIds'], isTrue);

    final inboxPayload = _lastGroupInboxStorePayload(fallbackBridge);
    expect(inboxPayload.containsKey('recipientPeerIds'), isTrue);
    expect(
      (inboxPayload['recipientPeerIds'] as List<dynamic>).cast<String>(),
      <String>[],
    );
    expect(inboxPayload['preserveRecipientPeerIds'], isTrue);
    expect(inboxPayload['recipientPeerIds'], isNot(contains(charliePeerId)));
  });

  test(
    'UP-012 post-removal sends exclude removed members from durable notification recipients',
    () async {
      final joinedAt = DateTime.utc(2026, 5, 14, 2);
      const activePeerId = 'peer-bob-up012';
      const removedPeerId = 'peer-charlie-up012';

      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: activePeerId,
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-bob-up012',
          joinedAt: joinedAt.add(const Duration(minutes: 1)),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: removedPeerId,
          username: 'Charlie',
          role: MemberRole.writer,
          publicKey: 'pk-charlie-up012',
          joinedAt: joinedAt.add(const Duration(minutes: 2)),
        ),
      );
      await groupRepo.removeMember('group-1', removedPeerId);

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'UP-012 post-removal notification privacy',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'up012-post-removal',
        timestamp: joinedAt.add(const Duration(minutes: 3)),
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      expect(message!.inboxStored, isTrue);

      final inboxPayload = _lastGroupInboxStorePayload(bridge);
      final recipientPeerIds =
          (inboxPayload['recipientPeerIds'] as List<dynamic>).cast<String>();
      expect(recipientPeerIds, <String>[activePeerId]);
      expect(recipientPeerIds, isNot(contains(removedPeerId)));
      expect(inboxPayload.containsKey('pushTitle'), isFalse);
      expect(inboxPayload.containsKey('pushBody'), isFalse);

      final replay = _decodedGroupInboxReplayPayload(bridge);
      expect(replay['messageId'], 'up012-post-removal');
      expect(replay['text'], 'UP-012 post-removal notification privacy');
    },
  );

  test(
    'GM-020 immediate post-removal durable recipients stay Bob-only for every send',
    () async {
      final failBridge = _InboxStoreFailBridge();
      failBridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'gm020',
        'topicPeers': 2,
      };
      final joinedAt = DateTime.utc(2026, 5, 11, 8);
      final removedAt = joinedAt.add(const Duration(minutes: 5));
      final firstSentAt = removedAt.add(const Duration(seconds: 1));
      final secondSentAt = removedAt.add(const Duration(seconds: 2));

      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-2',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-2',
          joinedAt: joinedAt.add(const Duration(seconds: 1)),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-3',
          username: 'Charlie',
          role: MemberRole.writer,
          publicKey: 'pk-3',
          joinedAt: joinedAt.add(const Duration(seconds: 2)),
        ),
      );
      await groupRepo.removeMember('group-1', 'peer-3');

      for (final proof in <({String id, String text, DateTime timestamp})>[
        (
          id: 'gm020-immediate-post-removal',
          text: 'GM-020 immediate post-removal durable',
          timestamp: firstSentAt,
        ),
        (
          id: 'gm020-repeated-post-removal',
          text: 'GM-020 repeated post-removal durable',
          timestamp: secondSentAt,
        ),
      ]) {
        final (result, message) = await sendGroupMessage(
          bridge: failBridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: proof.text,
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: proof.id,
          timestamp: proof.timestamp,
        );

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);

        final inboxPayload = _groupInboxStorePayloadForMessage(
          failBridge,
          proof.id,
        );
        expect(inboxPayload['recipientPeerIds'], <String>['peer-2']);
        expect(inboxPayload['recipientPeerIds'], isNot(contains('peer-1')));
        expect(inboxPayload['recipientPeerIds'], isNot(contains('peer-3')));
        expect(
          inboxPayload['recipientPeerIds'],
          hasLength((inboxPayload['recipientPeerIds'] as List).toSet().length),
        );

        final saved = await msgRepo.getMessage(proof.id);
        expect(saved?.inboxRetryPayload, isNotNull);
        expect(
          _recipientPeerIdsFromRetryPayload(saved!.inboxRetryPayload!),
          <String>['peer-2'],
        );
      }
    },
  );

  test('text group message does not send plaintext preview fields', () async {
    await groupRepo.saveMember(
      GroupMember(
        groupId: 'group-1',
        peerId: 'peer-2',
        username: 'Bob',
        role: MemberRole.writer,
        joinedAt: DateTime.utc(2026, 1, 2),
      ),
    );

    await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'hello',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Sender',
    );

    final inboxPayload = _lastGroupInboxStorePayload(bridge);
    expect(inboxPayload.containsKey('pushTitle'), isFalse);
    expect(inboxPayload.containsKey('pushBody'), isFalse);
    expect(inboxPayload.containsKey('groupName'), isFalse);

    final replayPayload = _decodedGroupInboxReplayPayload(bridge);
    expect(replayPayload['groupName'], 'Test Group');
  });

  test(
    'media-only group message does not send plaintext media preview fields',
    () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-2',
          username: 'Bob',
          role: MemberRole.writer,
          joinedAt: DateTime.utc(2026, 1, 2),
        ),
      );

      final voiceAttachment = MediaAttachment(
        id: 'att-voice',
        messageId: '',
        mime: 'audio/mp4',
        size: 48000,
        mediaType: 'audio',
        downloadStatus: 'done',
        createdAt: DateTime.now().toUtc().toIso8601String(),
        localPath: '/tmp/voice.m4a',
        durationMs: 3000,
        waveform: [0.1, 0.5, 0.8, 0.3],
        contentHash: _validContentHash,
        encryptionKeyBase64: 'key-att-voice',
        encryptionNonce: 'nonce-att-voice',
        encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      );

      await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: '',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        mediaAttachments: [voiceAttachment],
        mediaAttachmentRepo: InMemoryMediaAttachmentRepository(),
      );

      final inboxPayload = _lastGroupInboxStorePayload(bridge);
      expect(inboxPayload.containsKey('pushTitle'), isFalse);
      expect(inboxPayload.containsKey('pushBody'), isFalse);
    },
  );

  test(
    'empty recipient list does not crash and still stores group inbox',
    () async {
      final (result, _) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Only me here',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );

      expect(result, SendGroupMessageResult.success);
      expect(bridge.commandLog, contains('group:inboxStore'));

      final inboxPayload = _lastGroupInboxStorePayload(bridge);
      expect(inboxPayload['recipientPeerIds'], <String>[]);
      expect(inboxPayload['preserveRecipientPeerIds'], isTrue);
    },
  );

  test(
    'rejects stale send after local membership removal before persistence',
    () async {
      await groupRepo.removeMember('group-1', 'peer-1');
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-2',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-2',
          joinedAt: DateTime.utc(2026, 1, 2),
        ),
      );

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Queued stale send',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );

      expect(result, SendGroupMessageResult.unauthorized);
      expect(message, isNull);
      expect(msgRepo.count, 0);
      expect(bridge.commandLog, isEmpty);
    },
  );

  test('send succeeds even if inbox store throws', () async {
    final failBridge = _InboxStoreFailBridge();
    failBridge.responses['group:publish'] = {
      'ok': true,
      'messageId': 'msg-123',
    };

    final (result, message) = await sendGroupMessage(
      bridge: failBridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'Hello!',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
    );

    // Send should still succeed despite inbox store failure
    expect(result, SendGroupMessageResult.success);
    expect(message, isNotNull);
    expect(failBridge.commandLog, contains('group:publish'));
    expect(failBridge.commandLog, contains('group:inboxStore'));
  });

  test('returns error when publish returns ok: false', () async {
    bridge.responses['group:publish'] = {
      'ok': false,
      'errorCode': 'PUBLISH_FAILED',
    };

    final (result, message) = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'Hello!',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
    );

    expect(result, SendGroupMessageResult.error);
    // Pre-persist contract: error returns the failed message (not null)
    expect(message, isNotNull);
    expect(message!.status, 'failed');
  });

  test(
    'BB-002 group:publish NOT_INITIALIZED does not leave a pending send',
    () async {
      bridge.responses['group:publish'] = {
        'ok': false,
        'errorCode': 'NOT_INITIALIZED',
        'errorMessage': 'native node not initialized',
      };

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Before native init',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'bb002-not-initialized-message',
      );

      expect(result, SendGroupMessageResult.error);
      expect(message, isNotNull);
      expect(message!.status, 'failed');
      expect(bridge.commandLog, contains('group:publish'));

      final saved = await msgRepo.getMessage('bb002-not-initialized-message');
      expect(saved, isNotNull);
      expect(saved!.status, 'failed');

      final page = await msgRepo.getMessagesPage('group-1');
      expect(page.map((message) => message.status), isNot(contains('sending')));
      expect(page.map((message) => message.status), isNot(contains('pending')));
    },
  );

  test('returns error when publish throws exception', () async {
    bridge.throwOnSend = true;

    final (result, message) = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'Hello!',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
    );

    expect(result, SendGroupMessageResult.error);
    // Pre-persist contract: error returns the failed message (not null)
    expect(message, isNotNull);
    expect(message!.status, 'failed');
  });

  test('persists explicit inbox success when publish fails', () async {
    bridge.responses['group:publish'] = {
      'ok': false,
      'errorCode': 'PUBLISH_FAILED',
    };

    final (result, message) = await sendGroupMessage(
      bridge: bridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'Hello!',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
    );

    expect(result, SendGroupMessageResult.error);
    // Pre-persist contract: row exists with 'failed' status + retry payloads
    expect(msgRepo.count, 1);
    final page = await msgRepo.getMessagesPage('group-1');
    expect(page, hasLength(1));
    expect(page.single.id, message!.id);
    final saved = await msgRepo.getMessage(page.single.id);
    expect(saved, isNotNull);
    expect(saved!.status, 'failed');
    expect(saved.wireEnvelope, isNotNull);
    expect(saved.inboxStored, isTrue);
    expect(saved.inboxRetryPayload, isNull);
  });

  test('publish and inbox store run concurrently', () async {
    final slowBridge = _SlowPublishBridge(
      delay: const Duration(milliseconds: 200),
    );
    slowBridge.responses['group:publish'] = {
      'ok': true,
      'messageId': 'msg-123',
    };

    final stopwatch = Stopwatch()..start();
    await sendGroupMessage(
      bridge: slowBridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'Hello!',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
    );
    stopwatch.stop();

    // If sequential: publish(200ms) + inboxStore(~0ms) > 200ms (plus overhead)
    // If parallel: max(publish(200ms), inboxStore(~0ms)) ≈ 200ms
    // Both should be present
    expect(slowBridge.commandLog, contains('group:publish'));
    expect(slowBridge.commandLog, contains('group:inboxStore'));

    // Wall-clock should be under 400ms (sequential would be ~400ms+ with overhead)
    expect(stopwatch.elapsedMilliseconds, lessThan(400));
  });

  test(
    'getGroup stays sequential while latest key and member lookup run in parallel',
    () async {
      final slowGroupRepo = _DelayedGroupRepository();
      await slowGroupRepo.saveGroup(testGroup);
      await _saveGroupKey(slowGroupRepo, testGroup.id);
      await slowGroupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 0,
          encryptedKey: 'encrypted-key',
          createdAt: DateTime.now().toUtc(),
        ),
      );
      await slowGroupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-1',
          username: 'Alice',
          role: MemberRole.admin,
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await slowGroupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-2',
          username: 'Bob',
          role: MemberRole.writer,
          joinedAt: DateTime.now().toUtc(),
        ),
      );

      final stopwatch = Stopwatch()..start();
      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: slowGroupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Parallel reads',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );
      stopwatch.stop();

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      expect(stopwatch.elapsedMilliseconds, lessThan(180));
    },
  );

  test('inbox store runs even when publish fails', () async {
    final failBridge = _FailPublishBridge();

    final (result, _) = await sendGroupMessage(
      bridge: failBridge,
      groupRepo: groupRepo,
      msgRepo: msgRepo,
      groupId: 'group-1',
      text: 'Hello!',
      senderPeerId: 'peer-1',
      senderPublicKey: 'pk-1',
      senderPrivateKey: 'sk-1',
      senderUsername: 'Alice',
    );

    expect(result, SendGroupMessageResult.error);
    // inbox store should still have run despite publish failure
    expect(failBridge.commandLog, contains('group:publish'));
    expect(failBridge.commandLog, contains('group:inboxStore'));
  });

  test(
    'RA-017 repeated Charlie churn keeps durable recipient targeting for Bob and Dana',
    () async {
      final joinedAt = DateTime.utc(2026, 5, 13, 8);
      const alicePeerId = 'peer-1';
      const bobPeerId = 'peer-2';
      const charliePeerId = 'peer-3';
      const danaPeerId = 'peer-4';

      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: bobPeerId,
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-2',
          joinedAt: joinedAt.add(const Duration(minutes: 1)),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: charliePeerId,
          username: 'Charlie',
          role: MemberRole.writer,
          publicKey: 'pk-3',
          joinedAt: joinedAt.add(const Duration(minutes: 2)),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: danaPeerId,
          username: 'Dana',
          role: MemberRole.writer,
          publicKey: 'pk-4',
          joinedAt: joinedAt.add(const Duration(minutes: 3)),
        ),
      );

      Future<void> expectRecipients({
        required int cycle,
        required String phase,
        required String senderPeerId,
        required String senderPublicKey,
        required String senderPrivateKey,
        required String senderUsername,
        required List<String> expectedRecipients,
      }) async {
        bridge.sentMessages.clear();
        bridge.commandLog.clear();
        final messageId = 'ra017-$phase-c$cycle-$senderPeerId';
        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'RA-017 $phase cycle $cycle from $senderUsername',
          senderPeerId: senderPeerId,
          senderPublicKey: senderPublicKey,
          senderPrivateKey: senderPrivateKey,
          senderUsername: senderUsername,
          messageId: messageId,
          timestamp: joinedAt.add(
            Duration(hours: cycle, minutes: phase == 'removed' ? 1 : 2),
          ),
        );

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        expect(message!.inboxStored, isTrue);
        final inboxPayload = _lastGroupInboxStorePayload(bridge);
        expect(
          (inboxPayload['recipientPeerIds'] as List<dynamic>).cast<String>(),
          unorderedEquals(expectedRecipients),
          reason:
              'RA-017 $phase cycle $cycle $senderUsername send must target '
              'the active recipients exactly',
        );
        expect(
          (inboxPayload['recipientPeerIds'] as List<dynamic>).cast<String>(),
          isNot(contains(senderPeerId)),
        );
        final replay = _decodedGroupInboxReplayPayload(bridge);
        expect(replay['messageId'], messageId);
        expect(replay['senderId'], senderPeerId);
      }

      for (var cycle = 1; cycle <= 3; cycle++) {
        await groupRepo.removeMember('group-1', charliePeerId);
        await expectRecipients(
          cycle: cycle,
          phase: 'removed',
          senderPeerId: alicePeerId,
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          expectedRecipients: const [bobPeerId, danaPeerId],
        );
        await expectRecipients(
          cycle: cycle,
          phase: 'removed',
          senderPeerId: bobPeerId,
          senderPublicKey: 'pk-2',
          senderPrivateKey: 'sk-2',
          senderUsername: 'Bob',
          expectedRecipients: const [alicePeerId, danaPeerId],
        );
        await expectRecipients(
          cycle: cycle,
          phase: 'removed',
          senderPeerId: danaPeerId,
          senderPublicKey: 'pk-4',
          senderPrivateKey: 'sk-4',
          senderUsername: 'Dana',
          expectedRecipients: const [alicePeerId, bobPeerId],
        );

        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: charliePeerId,
            username: 'Charlie',
            role: MemberRole.writer,
            publicKey: 'pk-3',
            joinedAt: joinedAt.add(Duration(hours: cycle)),
          ),
        );
        await expectRecipients(
          cycle: cycle,
          phase: 'readd',
          senderPeerId: alicePeerId,
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          expectedRecipients: const [bobPeerId, charliePeerId, danaPeerId],
        );
        await expectRecipients(
          cycle: cycle,
          phase: 'readd',
          senderPeerId: bobPeerId,
          senderPublicKey: 'pk-2',
          senderPrivateKey: 'sk-2',
          senderUsername: 'Bob',
          expectedRecipients: const [alicePeerId, charliePeerId, danaPeerId],
        );
        await expectRecipients(
          cycle: cycle,
          phase: 'readd',
          senderPeerId: danaPeerId,
          senderPublicKey: 'pk-4',
          senderPrivateKey: 'sk-4',
          senderUsername: 'Dana',
          expectedRecipients: const [alicePeerId, bobPeerId, charliePeerId],
        );
      }
    },
  );

  test(
    'RA-018 alternating churn durable recipients match active interval for every sender',
    () async {
      final joinedAt = DateTime.utc(2026, 5, 13, 8);
      const alicePeerId = 'peer-1';
      const bobPeerId = 'peer-2';
      const charliePeerId = 'peer-3';
      const danaPeerId = 'peer-4';
      const publicKeysByPeerId = <String, String>{
        alicePeerId: 'pk-1',
        bobPeerId: 'pk-2',
        charliePeerId: 'pk-3',
        danaPeerId: 'pk-4',
      };
      const privateKeysByPeerId = <String, String>{
        alicePeerId: 'sk-1',
        bobPeerId: 'sk-2',
        charliePeerId: 'sk-3',
        danaPeerId: 'sk-4',
      };
      const usernamesByPeerId = <String, String>{
        alicePeerId: 'Alice',
        bobPeerId: 'Bob',
        charliePeerId: 'Charlie',
        danaPeerId: 'Dana',
      };

      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: bobPeerId,
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-2',
          joinedAt: joinedAt.add(const Duration(minutes: 1)),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: charliePeerId,
          username: 'Charlie',
          role: MemberRole.writer,
          publicKey: 'pk-3',
          joinedAt: joinedAt.add(const Duration(minutes: 2)),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: danaPeerId,
          username: 'Dana',
          role: MemberRole.writer,
          publicKey: 'pk-4',
          joinedAt: joinedAt.add(const Duration(minutes: 3)),
        ),
      );

      Future<void> readdMember({
        required String peerId,
        required int cycle,
        required int operationIndex,
      }) async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: peerId,
            username: usernamesByPeerId[peerId]!,
            role: MemberRole.writer,
            publicKey: publicKeysByPeerId[peerId]!,
            joinedAt: joinedAt.add(
              Duration(hours: cycle, minutes: operationIndex),
            ),
          ),
        );
      }

      Future<void> expectRecipients({
        required int cycle,
        required String operation,
        required String senderPeerId,
        required List<String> expectedRecipients,
      }) async {
        bridge.sentMessages.clear();
        bridge.commandLog.clear();
        final messageId = 'ra018-c$cycle-$operation-$senderPeerId';
        final senderUsername = usernamesByPeerId[senderPeerId]!;
        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'RA-018 cycle $cycle $operation from $senderUsername',
          senderPeerId: senderPeerId,
          senderPublicKey: publicKeysByPeerId[senderPeerId]!,
          senderPrivateKey: privateKeysByPeerId[senderPeerId]!,
          senderUsername: senderUsername,
          messageId: messageId,
          timestamp: joinedAt.add(
            Duration(hours: cycle, minutes: expectedRecipients.length),
          ),
        );

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        expect(message!.inboxStored, isTrue);
        final inboxPayload = _lastGroupInboxStorePayload(bridge);
        final recipientPeerIds =
            (inboxPayload['recipientPeerIds'] as List<dynamic>).cast<String>();
        expect(
          recipientPeerIds,
          unorderedEquals(expectedRecipients),
          reason:
              'RA-018 $operation cycle $cycle $senderUsername send must target '
              'the active interval recipients exactly',
        );
        expect(recipientPeerIds, hasLength(recipientPeerIds.toSet().length));
        expect(recipientPeerIds, isNot(contains(senderPeerId)));
        final replay = _decodedGroupInboxReplayPayload(bridge);
        expect(replay['messageId'], messageId);
        expect(replay['senderId'], senderPeerId);
      }

      for (var cycle = 1; cycle <= 3; cycle++) {
        await groupRepo.removeMember('group-1', charliePeerId);
        await expectRecipients(
          cycle: cycle,
          operation: 'charlie-removed',
          senderPeerId: alicePeerId,
          expectedRecipients: const [bobPeerId, danaPeerId],
        );

        await readdMember(
          peerId: charliePeerId,
          cycle: cycle,
          operationIndex: 2,
        );
        await expectRecipients(
          cycle: cycle,
          operation: 'charlie-readded',
          senderPeerId: bobPeerId,
          expectedRecipients: const [alicePeerId, charliePeerId, danaPeerId],
        );

        await groupRepo.removeMember('group-1', danaPeerId);
        await expectRecipients(
          cycle: cycle,
          operation: 'dana-removed',
          senderPeerId: charliePeerId,
          expectedRecipients: const [alicePeerId, bobPeerId],
        );

        await readdMember(peerId: danaPeerId, cycle: cycle, operationIndex: 4);
        await expectRecipients(
          cycle: cycle,
          operation: 'dana-readded',
          senderPeerId: danaPeerId,
          expectedRecipients: const [alicePeerId, bobPeerId, charliePeerId],
        );
      }
    },
  );

  // ---------------------------------------------------------------------------
  // Media attachment tests
  // ---------------------------------------------------------------------------
  group('media attachments', () {
    late InMemoryMediaAttachmentRepository mediaRepo;

    final testAttachment = MediaAttachment(
      id: 'att-1',
      messageId: '',
      mime: 'image/jpeg',
      size: 12345,
      mediaType: 'image',
      downloadStatus: 'done',
      createdAt: DateTime.now().toUtc().toIso8601String(),
      localPath: '/tmp/photo.jpg',
      contentHash: _validContentHash,
      encryptionKeyBase64: 'key-att-1',
      encryptionNonce: 'nonce-att-1',
      encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
    );

    setUp(() {
      mediaRepo = InMemoryMediaAttachmentRepository();
    });

    test(
      'TC-365-02a raw sender refuses initialized media without exact prepared manifest',
      () async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-1',
            username: 'Alice',
            role: MemberRole.admin,
            publicKey: 'pk-1',
            devices: const <GroupMemberDeviceIdentity>[
              GroupMemberDeviceIdentity(
                deviceId: 'device-current',
                transportPeerId: 'transport-current',
                deviceSigningPublicKey: 'pk-current',
              ),
              GroupMemberDeviceIdentity(
                deviceId: 'device-sibling',
                transportPeerId: 'transport-sibling',
                deviceSigningPublicKey: 'pk-sibling',
              ),
            ],
            joinedAt: DateTime.utc(2026, 8, 1),
          ),
        );

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'strict media',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-current',
          senderPrivateKey: 'sk-current',
          senderUsername: 'Alice',
          senderDeviceId: 'device-current',
          senderTransportPeerId: 'transport-current',
          messageId: 'msg-tc365-missing-manifest',
          mediaAttachments: <MediaAttachment>[testAttachment],
          mediaAttachmentRepo: mediaRepo,
          groupContentAuthoring: GroupContentAuthoringContext(
            directLinkedDeviceSelector:
                const DirectLinkedDeviceSelector.enabled(),
            multiDeviceSyncEnabled: true,
            authorityVersion: GroupContentAuthorityVersion(
              eventAt: DateTime.utc(2026, 8, 13, 11),
              eventId: 'authority.tc365.02a',
              keyEpoch: 1,
            ),
            inboxStore: _StrictContentInboxStore(),
          ),
        );

        expect(result, SendGroupMessageResult.authorityUnavailable);
        expect(message, isNull);
        expect(msgRepo.count, 0);
        expect(mediaRepo.count, 0);
        expect(
          bridge.commandLog.where(
            (command) =>
                command == 'group:publish' ||
                command == 'group:sendReliable' ||
                command == 'p2p:mediaUpload',
          ),
          isEmpty,
        );
      },
    );

    for (final waveformCase
        in <
          ({
            String name,
            List<double>? attachment,
            List<double>? commitment,
            bool accepted,
          })
        >[
          (
            name: 'absent image',
            attachment: null,
            commitment: null,
            accepted: true,
          ),
          (
            name: 'empty image',
            attachment: const <double>[],
            commitment: null,
            accepted: true,
          ),
          (
            name: 'matching voice',
            attachment: const <double>[0.1, 0.5],
            commitment: const <double>[0.1, 0.5],
            accepted: true,
          ),
          (
            name: 'different voice samples',
            attachment: const <double>[0.1, 0.4],
            commitment: const <double>[0.1, 0.5],
            accepted: false,
          ),
          (
            name: 'missing committed voice samples',
            attachment: null,
            commitment: const <double>[0.1, 0.5],
            accepted: false,
          ),
          (
            name: 'uncommitted voice samples',
            attachment: const <double>[0.1, 0.5],
            commitment: null,
            accepted: false,
          ),
        ]) {
      test('strict media waveform boundary: ${waveformCase.name}', () async {
        const messageId = 'strict-media-waveform';
        final isVoice = waveformCase.name.contains('voice');
        final strictRepo = _StrictContentMessageRepository();
        final strictStore = _StrictMediaContentInboxStore();
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-1',
            role: MemberRole.admin,
            publicKey: 'pk-1',
            devices: const <GroupMemberDeviceIdentity>[
              GroupMemberDeviceIdentity(
                deviceId: 'device-current',
                transportPeerId: 'transport-current',
                deviceSigningPublicKey: 'pk-current',
              ),
              GroupMemberDeviceIdentity(
                deviceId: 'device-sibling',
                transportPeerId: 'transport-sibling',
                deviceSigningPublicKey: 'pk-sibling',
              ),
            ],
            joinedAt: DateTime.utc(2026, 8, 1),
          ),
        );
        final attachment = testAttachment.copyWith(
          messageId: messageId,
          ownerLane: MediaOwnerLane.group,
          mime: isVoice ? 'audio/mp4' : 'image/jpeg',
          mediaType: isVoice ? 'audio' : 'image',
          waveform: waveformCase.attachment,
          clearWaveform: waveformCase.attachment == null,
        );
        await mediaRepo.saveAttachment(attachment, owner: MediaOwnerLane.group);
        final manifest = ProtectedGroupMediaManifest(
          groupId: 'group-1',
          messageId: messageId,
          attachments: <ProtectedGroupMediaAttachmentCommitment>[
            ProtectedGroupMediaAttachmentCommitment(
              attachmentId: attachment.id,
              custodyBlobId: 'waveform-test-blob',
              ciphertextSha256: attachment.contentHash!,
              ciphertextSize: attachment.size + 16,
              mime: attachment.mime,
              mediaType: attachment.mediaType,
              encryptionKeyBase64: attachment.encryptionKeyBase64!,
              encryptionNonce: attachment.encryptionNonce!,
              waveform: waveformCase.commitment,
              caption: 'strict media',
              targets: <GroupMediaBlobTargetCommitment>[
                GroupMediaBlobTargetCommitment(
                  recipientPeerId: 'transport-sibling',
                  expiresAtMs: 2000000000000,
                ),
              ],
            ),
          ],
        );
        var durableVerifications = 0;
        late (SendGroupMessageResult, GroupMessage?) result;
        final events = await captureFlowEvents(() async {
          result = await sendGroupMessage(
            bridge: bridge,
            groupRepo: groupRepo,
            msgRepo: strictRepo,
            groupId: 'group-1',
            text: 'strict media',
            senderPeerId: 'peer-1',
            senderPublicKey: 'pk-current',
            senderPrivateKey: 'sk-current',
            senderUsername: 'Alice',
            senderDeviceId: 'device-current',
            senderTransportPeerId: 'transport-current',
            messageId: messageId,
            mediaAttachments: <MediaAttachment>[attachment],
            mediaAttachmentRepo: mediaRepo,
            groupContentAuthoring: GroupContentAuthoringContext(
              directLinkedDeviceSelector:
                  const DirectLinkedDeviceSelector.enabled(),
              multiDeviceSyncEnabled: true,
              authorityVersion: GroupContentAuthorityVersion(
                eventAt: DateTime.utc(2026, 8, 13, 11),
                eventId: 'authority.waveform',
                keyEpoch: 1,
              ),
              inboxStore: strictStore,
            ),
            preparedGroupMediaManifest: PreparedGroupMediaManifestAuthority(
              manifest: manifest,
              verifyDurableAuthority: (candidate) async {
                durableVerifications++;
                expect(candidate.encode(), manifest.encode());
                return true;
              },
            ),
          );
        });
        if (waveformCase.accepted) {
          expect(result.$1, SendGroupMessageResult.success);
          expect(result.$2?.status, 'sent');
          expect(result.$2?.inboxStored, isTrue);
          expect(durableVerifications, 1);
          expect(strictStore.recipients, <String>['transport-sibling']);
          final frozen = GroupContentRetryPayload.decode(
            strictRepo.initiallyPersistedRetryPayload!,
          );
          final envelope = jsonDecode(frozen.message) as Map<String, dynamic>;
          expect(envelope['mediaManifest'], manifest.encode());
          expect(envelope['mediaManifestHash'], manifest.fingerprintSha256);
          expect(
            (await mediaRepo.getAttachmentById(attachment.id))?.waveform,
            waveformCase.attachment,
            reason: 'wire normalization must not rewrite durable metadata',
          );
        } else {
          expect(result.$1, SendGroupMessageResult.authorityUnavailable);
          expect(result.$2, isNull);
          expect(durableVerifications, 0);
          expect(strictRepo.count, 0);
          expect(strictStore.recipients, isEmpty);
          final timing = events.singleWhere(
            (event) => event['event'] == 'GROUP_SEND_MSG_TIMING',
          );
          expect(
            (timing['details'] as Map)['reason'],
            'strict_group_media_manifest_mismatch',
          );
        }
        expect(
          bridge.commandLog.where(
            (command) =>
                command == 'group:publish' || command == 'group:sendReliable',
          ),
          isEmpty,
        );
      });
    }

    test(
      'persists stamped done attachments before the pre-persist row save and publish',
      () async {
        const messageId = 'group-media-order-message';
        final operations = <String>[];
        final orderedMessages = _OrderedGroupMessageRepository(operations);
        final orderedMedia = _OrderedMediaAttachmentRepository(operations);
        final gatedBridge = _GatedPublishBridge()
          ..responses['group:publish'] = {
            'ok': true,
            'messageId': messageId,
            'topicPeers': 1,
          };
        final attachments = [
          testAttachment.copyWith(id: 'order-att-1'),
          testAttachment.copyWith(id: 'order-att-2'),
        ];

        final send = sendGroupMessage(
          bridge: gatedBridge,
          groupRepo: groupRepo,
          msgRepo: orderedMessages,
          groupId: 'group-1',
          text: '',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: messageId,
          mediaAttachments: attachments,
          mediaAttachmentRepo: orderedMedia,
        );

        await gatedBridge.publishStarted.future;
        final firstMessageSave = operations.indexWhere(
          (entry) => entry.startsWith('message:'),
        );
        final attachmentSaves = operations
            .asMap()
            .entries
            .where((entry) => entry.value.startsWith('attachment:'))
            .map((entry) => entry.key)
            .toList();
        expect(attachmentSaves, hasLength(2));
        expect(
          attachmentSaves.every((index) => index < firstMessageSave),
          isTrue,
          reason: 'all stamped media must be durable before the first row save',
        );
        for (final attachment in attachments) {
          final saved = await orderedMedia.getAttachmentById(attachment.id);
          expect(saved, isNotNull);
          expect(saved!.messageId, messageId);
          expect(saved.ownerLane, MediaOwnerLane.group);
          expect(saved.downloadStatus, 'done');
        }

        gatedBridge.publishGate.complete();
        final (result, _) = await send;
        expect(result, SendGroupMessageResult.success);
        expect(orderedMedia.count, 2);
      },
    );

    test(
      'terminal publish failure retains persisted done attachments',
      () async {
        const messageId = 'group-media-terminal-failure';
        final failingBridge = _FailPublishBridge()
          ..responses['group:inboxStore'] = {
            'ok': false,
            'errorCode': 'INBOX_STORE_FAILED',
          };

        final (result, message) = await sendGroupMessage(
          bridge: failingBridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: '',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: messageId,
          mediaAttachments: [testAttachment.copyWith(id: 'failed-media-att')],
          mediaAttachmentRepo: mediaRepo,
        );

        expect(result, SendGroupMessageResult.error);
        expect(message, isNotNull);
        expect(message!.status, 'failed');
        final saved = await mediaRepo.getAttachmentsForMessage(
          messageId,
          owner: MediaOwnerLane.group,
        );
        expect(saved, hasLength(1));
        expect(saved.single.id, 'failed-media-att');
        expect(saved.single.downloadStatus, 'done');
      },
    );

    test(
      'nth attachment persistence failure rolls back new media and never dispatches',
      () async {
        const messageId = 'group-media-nth-persist-failure';
        final messages = InMemoryGroupMessageRepository();
        final failingMedia = _FailingNthMediaAttachmentRepository(2);

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: messages,
          groupId: 'group-1',
          text: '',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: messageId,
          mediaAttachments: [
            testAttachment.copyWith(id: 'nth-persist-1'),
            testAttachment.copyWith(id: 'nth-persist-2'),
          ],
          mediaAttachmentRepo: failingMedia,
        );

        expect(result, SendGroupMessageResult.error);
        expect(message, isNull);
        expect(await messages.getMessage(messageId), isNull);
        expect(await messages.getLocalDeletionGroupId(messageId), isNull);
        expect(
          await failingMedia.getAttachmentsForMessage(
            messageId,
            owner: MediaOwnerLane.group,
          ),
          isEmpty,
        );
        expect(_groupDispatchCommands(bridge), isEmpty);
      },
    );

    test(
      'parent persistence failure rolls back new media and never dispatches',
      () async {
        const messageId = 'group-media-parent-persist-failure';
        final messages = _ThrowingSaveGroupMessageRepository();

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: messages,
          groupId: 'group-1',
          text: '',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: messageId,
          mediaAttachments: [testAttachment.copyWith(id: 'parent-failure-att')],
          mediaAttachmentRepo: mediaRepo,
        );

        expect(result, SendGroupMessageResult.error);
        expect(message, isNull);
        expect(
          await mediaRepo.getAttachmentsForMessage(
            messageId,
            owner: MediaOwnerLane.group,
          ),
          isEmpty,
        );
        expect(_groupDispatchCommands(bridge), isEmpty);
      },
    );

    test(
      'media verification failure removes a new parent and its media before dispatch',
      () async {
        const messageId = 'group-media-verification-failure';
        final messages = InMemoryGroupMessageRepository();
        final unreadableMedia = _MissingDurableMediaAttachmentRepository();

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: messages,
          groupId: 'group-1',
          text: '',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: messageId,
          mediaAttachments: [
            testAttachment.copyWith(id: 'verification-failure-att'),
          ],
          mediaAttachmentRepo: unreadableMedia,
        );

        expect(result, SendGroupMessageResult.error);
        expect(message, isNull);
        expect(await messages.getMessage(messageId), isNull);
        expect(
          await unreadableMedia.getAttachmentById('verification-failure-att'),
          isNull,
        );
        expect(_groupDispatchCommands(bridge), isEmpty);
      },
    );

    test(
      'media without a persistence repository fails before parent save or dispatch',
      () async {
        const messageId = 'group-media-missing-repository';
        final messages = _SaveTrackingGroupMessageRepository();

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: messages,
          groupId: 'group-1',
          text: '',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: messageId,
          mediaAttachments: [
            testAttachment.copyWith(id: 'missing-repository-att'),
          ],
        );

        expect(result, SendGroupMessageResult.error);
        expect(message, isNull);
        expect(await messages.getMessage(messageId), isNull);
        expect(await messages.getLocalDeletionGroupId(messageId), isNull);
        expect(messages.savedMessages, isEmpty);
        expect(_groupDispatchCommands(bridge), isEmpty);
      },
    );

    test(
      'media verification failure restores an existing retry parent before returning',
      () async {
        const messageId = 'group-media-retry-verification-failure';
        final messages = InMemoryGroupMessageRepository();
        final unreadableMedia = _MissingDurableMediaAttachmentRepository();
        final originalTimestamp = DateTime.utc(2026, 7, 10, 13);
        final original = GroupMessage(
          id: messageId,
          groupId: 'group-1',
          senderPeerId: 'peer-1',
          senderUsername: 'Alice',
          text: '',
          timestamp: originalTimestamp,
          lastSendAttemptAt: originalTimestamp,
          status: 'failed',
          isIncoming: false,
          createdAt: originalTimestamp,
          wireEnvelope: '{"original":true}',
          inboxRetryPayload: '{"original":true}',
        );
        await messages.saveMessage(original);

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: messages,
          groupId: 'group-1',
          text: '',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: messageId,
          timestamp: originalTimestamp,
          mediaAttachments: [
            testAttachment.copyWith(id: 'retry-verification-failure-att'),
          ],
          mediaAttachmentRepo: unreadableMedia,
        );

        expect(result, SendGroupMessageResult.error);
        expect(message, same(original));
        final restored = await messages.getMessage(messageId);
        expect(restored?.status, 'failed');
        expect(restored?.lastSendAttemptAt, originalTimestamp);
        expect(restored?.wireEnvelope, '{"original":true}');
        expect(_groupDispatchCommands(bridge), isEmpty);
      },
    );

    test(
      'silently rejected parent persistence rolls back new media and never dispatches',
      () async {
        const messageId = 'group-media-parent-silent-reject';
        final messages = _SilentSaveGroupMessageRepository();

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: messages,
          groupId: 'group-1',
          text: '',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: messageId,
          mediaAttachments: [testAttachment.copyWith(id: 'silent-reject-att')],
          mediaAttachmentRepo: mediaRepo,
        );

        expect(result, SendGroupMessageResult.error);
        expect(message, isNull);
        expect(await messages.getMessage(messageId), isNull);
        expect(
          await mediaRepo.getAttachmentsForMessage(
            messageId,
            owner: MediaOwnerLane.group,
          ),
          isEmpty,
        );
        expect(_groupDispatchCommands(bridge), isEmpty);
      },
    );

    test(
      'silently rejected retry parent persistence never dispatches a stale row',
      () async {
        const messageId = 'group-media-retry-parent-silent-reject';
        final messages = _SilentSaveGroupMessageRepository();
        final originalTimestamp = DateTime.utc(2026, 7, 10, 12);
        await messages.seedMessage(
          GroupMessage(
            id: messageId,
            groupId: 'group-1',
            senderPeerId: 'peer-1',
            senderUsername: 'Alice',
            text: '',
            timestamp: originalTimestamp,
            lastSendAttemptAt: originalTimestamp,
            status: 'failed',
            isIncoming: false,
            createdAt: originalTimestamp,
            wireEnvelope: '{"stale":true}',
            inboxRetryPayload: '{"stale":true}',
          ),
        );

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: messages,
          groupId: 'group-1',
          text: '',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: messageId,
          timestamp: originalTimestamp,
          mediaAttachments: [testAttachment.copyWith(id: 'retry-parent-att')],
          mediaAttachmentRepo: mediaRepo,
        );

        expect(result, SendGroupMessageResult.error);
        expect(message?.status, 'failed');
        expect(
          (await messages.getMessage(messageId))?.wireEnvelope,
          '{"stale":true}',
        );
        expect(_groupDispatchCommands(bridge), isEmpty);
      },
    );

    test('includes media in publish payload', () async {
      final (result, _) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Check this out',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        mediaAttachments: [testAttachment],
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, SendGroupMessageResult.success);

      // Verify bridge received media in publish payload
      final publishMsg = bridge.sentMessages.firstWhere(
        (m) => (jsonDecode(m) as Map)['cmd'] == 'group:publish',
      );
      final payload =
          (jsonDecode(publishMsg) as Map)['payload'] as Map<String, dynamic>;
      expect(payload['media'], isNotNull);
      expect((payload['media'] as List).length, 1);
      final mediaJson =
          (payload['media'] as List).single as Map<String, dynamic>;
      expect(mediaJson['contentHash'], _validContentHash);
      expect(mediaJson['encryptionKeyBase64'], 'key-att-1');
      expect(mediaJson['encryptionNonce'], 'nonce-att-1');
      expect(
        mediaJson['encryptionScheme'],
        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      );
    });

    test('includes media in inbox payload', () async {
      await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Check this out',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        mediaAttachments: [testAttachment],
        mediaAttachmentRepo: mediaRepo,
      );

      // Verify inbox store received media in payload
      final innerPayload = _decodedGroupInboxReplayPayload(bridge);
      expect(innerPayload['media'], isNotNull);
      expect((innerPayload['media'] as List).length, 1);
      final mediaJson =
          (innerPayload['media'] as List).single as Map<String, dynamic>;
      expect(mediaJson['contentHash'], _validContentHash);
      expect(mediaJson['encryptionKeyBase64'], 'key-att-1');
      expect(mediaJson['encryptionNonce'], 'nonce-att-1');
      expect(
        mediaJson['encryptionScheme'],
        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
      );
    });

    test(
      'PL-014 media metadata omits group keys plaintext and private keys from diagnostics and relay replay',
      () async {
        final privacyBridge = _OpaqueReplayBridge();
        privacyBridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'msg-pl014-media-privacy',
          'topicPeers': 1,
        };
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-2',
            username: 'Bob',
            role: MemberRole.writer,
            joinedAt: DateTime.utc(2026, 1, 2),
          ),
        );

        const protectedPlaintext = 'PL014 protected plaintext body alpha';
        const senderPrivateKey = 'pl014-sender-private-key-secret';
        const groupKey = 'test-group-key-1';
        const blobKey = 'pl014-blob-key-for-encrypted-descriptor';
        const blobNonce = 'pl014-blob-nonce-for-encrypted-descriptor';
        const forbiddenMetadataKeys = {
          'groupKey',
          'group_key',
          'plaintext',
          'plainText',
          'secretKey',
          'secret_key',
          'privateKey',
          'senderPrivateKey',
        };
        final protectedFragments = [
          protectedPlaintext,
          senderPrivateKey,
          groupKey,
        ];
        final relayProtectedFragments = [
          ...protectedFragments,
          blobKey,
          blobNonce,
        ];
        final privateAttachment = testAttachment.copyWith(
          id: 'blob-pl014-private',
          encryptionKeyBase64: blobKey,
          encryptionNonce: blobNonce,
        );

        final events = await captureFlowEvents(() async {
          final (result, message) = await sendGroupMessage(
            bridge: privacyBridge,
            groupRepo: groupRepo,
            msgRepo: msgRepo,
            groupId: 'group-1',
            text: protectedPlaintext,
            senderPeerId: 'peer-1',
            senderPublicKey: 'pk-1',
            senderPrivateKey: senderPrivateKey,
            senderUsername: 'Alice',
            messageId: 'msg-pl014-media-privacy',
            mediaAttachments: [privateAttachment],
            mediaAttachmentRepo: mediaRepo,
          );

          expect(result, SendGroupMessageResult.success);
          expect(message, isNotNull);
        });

        final publishRaw = privacyBridge.sentMessages.firstWhere(
          (raw) =>
              (jsonDecode(raw) as Map<String, dynamic>)['cmd'] ==
              'group:publish',
        );
        final publishPayload =
            (jsonDecode(publishRaw) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        final publishMedia = publishPayload['media'] as List<dynamic>;
        expect(publishMedia, hasLength(1));
        _expectNoProtectedFragments(
          jsonEncode(publishMedia),
          protectedFragments,
        );
        _expectNoForbiddenKeys(publishMedia, forbiddenMetadataKeys);

        final inboxStoreCommand = privacyBridge.sentMessages.lastWhere(
          (raw) =>
              (jsonDecode(raw) as Map<String, dynamic>)['cmd'] ==
              'group:inboxStore',
        );
        _expectNoProtectedFragments(inboxStoreCommand, relayProtectedFragments);
        final inboxPayload = _lastGroupInboxStorePayload(privacyBridge);
        expect(inboxPayload.containsKey('pushTitle'), isFalse);
        expect(inboxPayload.containsKey('pushBody'), isFalse);
        final replayEnvelope =
            jsonDecode(inboxPayload['message'] as String)
                as Map<String, dynamic>;
        expect(replayEnvelope['kind'], 'group_offline_replay');
        expect(replayEnvelope['ciphertext'], startsWith('sealed:'));
        expect(replayEnvelope.containsKey('media'), isFalse);
        _expectNoForbiddenKeys(replayEnvelope, forbiddenMetadataKeys);

        final diagnosticsJson = jsonEncode(events);
        _expectNoProtectedFragments(diagnosticsJson, relayProtectedFragments);
        _expectNoForbiddenKeys(events, forbiddenMetadataKeys);
      },
    );

    test('saves attachments to MediaAttachmentRepository', () async {
      await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Check this out',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        mediaAttachments: [testAttachment],
        mediaAttachmentRepo: mediaRepo,
      );

      expect(mediaRepo.count, 1);
      // The saved attachment should have a non-empty messageId
      final saved = (await mediaRepo.getPendingDownloads()).isEmpty;
      // Since testAttachment has downloadStatus: 'done', getPendingDownloads returns empty
      expect(saved, isTrue);
    });

    // 228: the group outgoing path must persist media under the GROUP lane —
    // every saveAttachment call carries MediaOwnerLane.group, never direct.
    test('outgoing media save passes group owner', () async {
      final recordedLanes = <MediaOwnerLane?>[];
      mediaRepo.onSaveAttachment = (att) => recordedLanes.add(att.ownerLane);

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Check this out',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        mediaAttachments: [testAttachment],
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      expect(recordedLanes, isNotEmpty);
      expect(
        recordedLanes.toSet(),
        {MediaOwnerLane.group},
        reason: 'every group outgoing media save must pass the group lane',
      );
      final savedAttachment = await mediaRepo.getAttachmentById('att-1');
      expect(savedAttachment, isNotNull);
      expect(savedAttachment!.ownerLane, MediaOwnerLane.group);
      // Lane-scoped read-back: the direct lane must never see this attachment.
      expect(
        await mediaRepo.getAttachmentsForMessage(
          savedAttachment.messageId,
          owner: MediaOwnerLane.direct,
        ),
        isEmpty,
      );
      expect(
        (await mediaRepo.getAttachmentsForMessage(
          savedAttachment.messageId,
          owner: MediaOwnerLane.group,
        )).single.id,
        'att-1',
      );
    });

    test('includes GIF metadata in publish and inbox payloads', () async {
      final gifAttachment = testAttachment.copyWith(
        id: 'gif-att-1',
        mime: 'image/gif',
        localPath: '/tmp/funny.gif',
      );

      final (result, _) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: '',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        mediaAttachments: [gifAttachment],
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, SendGroupMessageResult.success);

      final publishMsg = bridge.sentMessages.firstWhere(
        (m) => (jsonDecode(m) as Map)['cmd'] == 'group:publish',
      );
      final publishPayload =
          (jsonDecode(publishMsg) as Map)['payload'] as Map<String, dynamic>;
      final publishMedia = publishPayload['media'] as List<dynamic>;
      expect(
        (publishMedia.single as Map<String, dynamic>)['mime'],
        'image/gif',
      );

      final innerPayload = _decodedGroupInboxReplayPayload(bridge);
      final inboxMedia = innerPayload['media'] as List<dynamic>;
      expect((inboxMedia.single as Map<String, dynamic>)['mime'], 'image/gif');
    });

    test(
      'rejects dangerous media MIME before persistence, publish, or inbox store',
      () async {
        final dangerousAttachment = testAttachment.copyWith(
          id: 'bad-att-1',
          mime: 'application/pdf',
          mediaType: 'file',
          localPath: '/tmp/bad.pdf',
        );

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'blocked media',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          mediaAttachments: [dangerousAttachment],
          mediaAttachmentRepo: mediaRepo,
        );

        expect(result, SendGroupMessageResult.error);
        expect(message, isNull);
        expect(msgRepo.count, 0);
        expect(mediaRepo.count, 0);
        expect(bridge.commandLog, isNot(contains('group:publish')));
        expect(bridge.commandLog, isNot(contains('group:inboxStore')));
      },
    );

    test(
      'rejects oversized single media before persistence, publish, or inbox store',
      () async {
        final oversizedAttachment = testAttachment.copyWith(
          id: 'oversized-att-1',
          size: kGroupMediaPerAttachmentLimitBytes + 1,
        );

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'blocked oversized media',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          mediaAttachments: [oversizedAttachment],
          mediaAttachmentRepo: mediaRepo,
        );

        expect(result, SendGroupMessageResult.error);
        expect(message, isNull);
        expect(msgRepo.count, 0);
        expect(mediaRepo.count, 0);
        expect(bridge.commandLog, isNot(contains('group:publish')));
        expect(bridge.commandLog, isNot(contains('group:inboxStore')));
      },
    );

    test(
      'rejects oversized total media list before persistence, publish, or inbox store',
      () async {
        final first = testAttachment.copyWith(
          id: 'total-att-1',
          size: kGroupMediaTotalMessageLimitBytes,
        );
        final second = testAttachment.copyWith(id: 'total-att-2', size: 1);

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'blocked oversized total',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          mediaAttachments: [first, second],
          mediaAttachmentRepo: mediaRepo,
        );

        expect(result, SendGroupMessageResult.error);
        expect(message, isNull);
        expect(msgRepo.count, 0);
        expect(mediaRepo.count, 0);
        expect(bridge.commandLog, isNot(contains('group:publish')));
        expect(bridge.commandLog, isNot(contains('group:inboxStore')));
      },
    );

    test('accepts media at the configured size boundary', () async {
      // testAttachment is image/jpeg, so the per-type SEND cap is the image cap.
      final boundaryAttachment = testAttachment.copyWith(
        id: 'boundary-att-1',
        size: kGroupMediaImageLimitBytes,
      );

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: '',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        mediaAttachments: [boundaryAttachment],
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      expect(bridge.commandLog, contains('group:publish'));
      expect(bridge.commandLog, contains('group:inboxStore'));
      expect(mediaRepo.count, 1);
    });

    test('rejects mediaType mismatch before group publish', () async {
      final mismatchedAttachment = testAttachment.copyWith(
        id: 'bad-att-2',
        mime: 'image/jpeg',
        mediaType: 'video',
      );

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'blocked mismatch',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        mediaAttachments: [mismatchedAttachment],
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, SendGroupMessageResult.error);
      expect(message, isNull);
      expect(msgRepo.count, 0);
      expect(mediaRepo.count, 0);
      expect(bridge.commandLog, isNot(contains('group:publish')));
    });

    test('rejects hashless media before persistence or publish', () async {
      final hashlessAttachment = testAttachment.copyWith(
        id: 'hashless-att',
        clearContentHash: true,
      );

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'blocked hashless',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        mediaAttachments: [hashlessAttachment],
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, SendGroupMessageResult.error);
      expect(message, isNull);
      expect(msgRepo.count, 0);
      expect(mediaRepo.count, 0);
      expect(bridge.commandLog, isNot(contains('group:publish')));
      expect(bridge.commandLog, isNot(contains('group:inboxStore')));
    });

    test('rejects media without encryption metadata before publish', () async {
      final unencryptedAttachment = testAttachment.copyWith(
        id: 'unencrypted-att',
        clearEncryptionKeyBase64: true,
        clearEncryptionNonce: true,
        clearEncryptionScheme: true,
      );

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'blocked unencrypted media',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        mediaAttachments: [unencryptedAttachment],
        mediaAttachmentRepo: mediaRepo,
      );

      expect(result, SendGroupMessageResult.error);
      expect(message, isNull);
      expect(msgRepo.count, 0);
      expect(mediaRepo.count, 0);
      expect(bridge.commandLog, isNot(contains('group:publish')));
      expect(bridge.commandLog, isNot(contains('group:inboxStore')));
    });

    test(
      'removes stale upload_pending placeholders before saving final attachments',
      () async {
        const messageId = 'group-media-stable-id';
        await mediaRepo.saveAttachment(
          MediaAttachment(
            id: 'pending-placeholder',
            messageId: messageId,
            mime: 'image/jpeg',
            size: 0,
            mediaType: 'image',
            localPath: 'pending_uploads/$messageId/pending-placeholder.jpg',
            downloadStatus: 'upload_pending',
            createdAt: DateTime.now().toUtc().toIso8601String(),
            contentHash: _validContentHash,
            encryptionKeyBase64: 'key-fixture',
            encryptionNonce: 'nonce-fixture',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ),
          owner: MediaOwnerLane.group,
        );

        final (result, _) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Check this out',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: messageId,
          mediaAttachments: [
            testAttachment.copyWith(
              id: 'final-attachment',
              messageId: messageId,
            ),
          ],
          mediaAttachmentRepo: mediaRepo,
        );

        expect(result, SendGroupMessageResult.success);

        final savedAttachments = await mediaRepo.getAttachmentsForMessage(
          messageId,
          owner: MediaOwnerLane.group,
        );
        expect(savedAttachments, hasLength(1));
        expect(savedAttachments.single.id, 'final-attachment');
        expect(savedAttachments.single.downloadStatus, 'done');
      },
    );

    test('uses provided messageId when given', () async {
      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Hello!',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'pre-created-id',
      );

      expect(result, SendGroupMessageResult.success);
      expect(message!.id, 'pre-created-id');
      final saved = await msgRepo.getMessage('pre-created-id');
      expect(saved, isNotNull);
    });

    test(
      'DE-003 preserves caller messageId in publish, replay, and retry payloads',
      () async {
        const explicitId = 'de003-explicit-message-id';
        const text = 'DE-003 explicit id proof';
        final proofBridge = _InboxStoreFailBridge()
          ..responses['group:publish'] = {
            'ok': true,
            'messageId': explicitId,
            'topicPeers': 1,
          };

        final (result, message) = await sendGroupMessage(
          bridge: proofBridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: text,
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: explicitId,
          timestamp: DateTime.utc(2026, 5, 12, 3),
        );

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        expect(message!.id, explicitId);
        expect(message.status, 'sent');

        final saved = await msgRepo.getMessage(explicitId);
        expect(saved, isNotNull);
        expect(saved!.id, explicitId);
        expect(saved.text, text);
        expect(saved.inboxRetryPayload, isNotNull);

        final publishRaw = proofBridge.sentMessages.lastWhere(
          (raw) =>
              (jsonDecode(raw) as Map<String, dynamic>)['cmd'] ==
              'group:publish',
        );
        final publishPayload =
            (jsonDecode(publishRaw) as Map<String, dynamic>)['payload']
                as Map<String, dynamic>;
        expect(publishPayload['messageId'], explicitId);

        final inboxStorePayload = _lastGroupInboxStorePayload(proofBridge);
        final replayEnvelope =
            jsonDecode(inboxStorePayload['message'] as String)
                as Map<String, dynamic>;
        expect(replayEnvelope['messageId'], explicitId);

        final retryPayload =
            jsonDecode(saved.inboxRetryPayload!) as Map<String, dynamic>;
        expect(retryPayload['message'], inboxStorePayload['message']);
        final retryEnvelope =
            jsonDecode(retryPayload['message'] as String)
                as Map<String, dynamic>;
        expect(retryEnvelope['messageId'], explicitId);
      },
    );

    test('uses provided timestamp when given', () async {
      final fixedTime = DateTime.utc(2026, 1, 15, 12, 0, 0);

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Hello!',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        timestamp: fixedTime,
      );

      expect(result, SendGroupMessageResult.success);
      expect(message!.timestamp, fixedTime);
    });

    test('generates messageId when not provided', () async {
      final (_, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Hello!',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );

      expect(message!.id, isNotEmpty);
      expect(message.id, isNot('pre-created-id'));
    });

    test(
      'logical delivery id is generated once and carried through send payloads',
      () async {
        bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'logical-send-row',
          'topicPeers': 1,
        };
        const messageId = 'logical-send-row';

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Logical delivery send',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: messageId,
        );

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        expect(message!.logicalDeliveryId, messageId);
        final saved = await msgRepo.getMessage(messageId);
        expect(saved, isNotNull);
        expect(saved!.logicalDeliveryId, messageId);

        final reliablePayload = _groupSendReliablePayloadForMessage(
          bridge,
          messageId,
        );
        expect(reliablePayload['logicalDeliveryId'], messageId);

        final publishPayload = bridge.sentMessages
            .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
            .where((message) => message['cmd'] == 'group:publish')
            .map(
              (message) => (message['payload'] as Map).cast<String, dynamic>(),
            )
            .single;
        expect(publishPayload['messageId'], messageId);
        expect(publishPayload['logicalDeliveryId'], messageId);

        final replayPayload = _decodedGroupInboxReplayPayload(bridge);
        expect(replayPayload['messageId'], messageId);
        expect(replayPayload['logicalDeliveryId'], messageId);
      },
    );

    test('SP003 default message ids are unique UUID v4 values', () async {
      final (firstResult, firstMessage) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'First random id message',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );

      final (secondResult, secondMessage) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Second random id message',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );

      expect(firstResult, SendGroupMessageResult.success);
      expect(secondResult, SendGroupMessageResult.success);
      expect(firstMessage, isNotNull);
      expect(secondMessage, isNotNull);
      expect(_uuidV4Pattern.hasMatch(firstMessage!.id), isTrue);
      expect(_uuidV4Pattern.hasMatch(secondMessage!.id), isTrue);
      expect(firstMessage.id, isNot(secondMessage.id));
      expect(await msgRepo.getMessage(firstMessage.id), isNotNull);
      expect(await msgRepo.getMessage(secondMessage.id), isNotNull);
    });

    test(
      'message id collision from generator uses a fresh id without overwriting trusted row',
      () async {
        const collidingId = 'generated-collision-id';
        const resolvedId = 'generated-resolved-id';
        final trustedTimestamp = DateTime.utc(2026, 4, 5, 10);
        await msgRepo.saveMessage(
          GroupMessage(
            id: collidingId,
            groupId: 'group-1',
            senderPeerId: 'peer-1',
            senderUsername: 'Alice',
            text: 'Trusted original',
            timestamp: trustedTimestamp,
            keyGeneration: 1,
            status: 'sent',
            isIncoming: false,
            createdAt: trustedTimestamp,
          ),
        );

        var factoryCallCount = 0;
        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'New generated collision send',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          timestamp: DateTime.utc(2026, 4, 5, 10, 1),
          messageIdFactory: () {
            factoryCallCount++;
            return factoryCallCount == 1 ? collidingId : resolvedId;
          },
        );

        expect(result, SendGroupMessageResult.success);
        expect(message!.id, resolvedId);

        final trusted = await msgRepo.getMessage(collidingId);
        expect(trusted, isNotNull);
        expect(trusted!.text, 'Trusted original');
        expect(trusted.status, 'sent');

        final resolved = await msgRepo.getMessage(resolvedId);
        expect(resolved, isNotNull);
        expect(resolved!.text, 'New generated collision send');
      },
    );

    test(
      'message id collision from explicit id resolves without overwriting trusted row',
      () async {
        const collidingId = 'explicit-collision-id';
        const resolvedId = 'explicit-resolved-id';
        final trustedTimestamp = DateTime.utc(2026, 4, 5, 11);
        await msgRepo.saveMessage(
          GroupMessage(
            id: collidingId,
            groupId: 'group-1',
            senderPeerId: 'peer-1',
            senderUsername: 'Alice',
            text: 'Already sent',
            timestamp: trustedTimestamp,
            keyGeneration: 1,
            status: 'sent',
            isIncoming: false,
            createdAt: trustedTimestamp,
          ),
        );

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Second send with colliding id',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: collidingId,
          timestamp: DateTime.utc(2026, 4, 5, 11, 1),
          messageIdFactory: () => resolvedId,
        );

        expect(result, SendGroupMessageResult.success);
        expect(message!.id, resolvedId);
        expect((await msgRepo.getMessage(collidingId))!.text, 'Already sent');
        expect(
          (await msgRepo.getMessage(resolvedId))!.text,
          'Second send with colliding id',
        );
      },
    );

    test(
      'message id collision guard still allows failed retry in place',
      () async {
        const retryId = 'retry-same-id';
        final retryTimestamp = DateTime.utc(2026, 4, 5, 12);
        await msgRepo.saveMessage(
          GroupMessage(
            id: retryId,
            groupId: 'group-1',
            senderPeerId: 'peer-1',
            senderUsername: 'Alice',
            text: 'Retry same row',
            timestamp: retryTimestamp,
            keyGeneration: 1,
            status: 'failed',
            isIncoming: false,
            createdAt: retryTimestamp,
            wireEnvelope: '{}',
            inboxRetryPayload: '{}',
          ),
        );

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Retry same row',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: retryId,
          timestamp: retryTimestamp,
          messageIdFactory: () => 'should-not-be-used',
        );

        expect(result, SendGroupMessageResult.success);
        expect(message!.id, retryId);
        final saved = await msgRepo.getMessage(retryId);
        expect(saved, isNotNull);
        expect(saved!.text, 'Retry same row');
        expect(saved.status, anyOf('sent', 'pending'));
      },
    );

    test(
      'message id collision guard treats edited restored failed text as a new message',
      () async {
        const failedId = 'edited-restored-old-id';
        const freshId = 'edited-restored-fresh-id';
        final failedTimestamp = DateTime.utc(2026, 4, 5, 12, 30);
        await msgRepo.saveMessage(
          GroupMessage(
            id: failedId,
            groupId: 'group-1',
            senderPeerId: 'peer-1',
            senderUsername: 'Alice',
            text: 'Original failed text',
            timestamp: failedTimestamp,
            keyGeneration: 1,
            status: 'failed',
            isIncoming: false,
            createdAt: failedTimestamp,
            wireEnvelope: '{}',
            inboxRetryPayload: '{}',
          ),
        );

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Edited failed text',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: failedId,
          timestamp: failedTimestamp,
          messageIdFactory: () => freshId,
        );

        expect(result, SendGroupMessageResult.success);
        expect(message!.id, freshId);

        final oldRow = await msgRepo.getMessage(failedId);
        expect(oldRow, isNotNull);
        expect(oldRow!.text, 'Original failed text');
        expect(oldRow.status, 'failed');

        final freshRow = await msgRepo.getMessage(freshId);
        expect(freshRow, isNotNull);
        expect(freshRow!.text, 'Edited failed text');
        expect(freshRow.status, anyOf('sent', 'pending'));
      },
    );

    test(
      'PL-002 media-only group message accepts empty text and preserves media',
      () async {
        final voiceAttachment = MediaAttachment(
          id: 'att-voice',
          messageId: '',
          mime: 'audio/mp4',
          size: 48000,
          mediaType: 'audio',
          downloadStatus: 'done',
          createdAt: DateTime.now().toUtc().toIso8601String(),
          localPath: '/tmp/voice.m4a',
          durationMs: 3000,
          waveform: [0.1, 0.5, 0.8, 0.3],
          contentHash: _validContentHash,
          encryptionKeyBase64: 'key-att-voice',
          encryptionNonce: 'nonce-att-voice',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );
        const messageId = 'pl002-media-only-empty-text';
        final sentAt = DateTime.utc(2026, 5, 14, 18, 4);

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: '',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: messageId,
          timestamp: sentAt,
          mediaAttachments: [voiceAttachment],
          mediaAttachmentRepo: mediaRepo,
        );

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        expect(message!.id, messageId);
        expect(message.text, '');
        expect(message.status, 'sent');

        final publishMsg = bridge.sentMessages.firstWhere(
          (m) => (jsonDecode(m) as Map)['cmd'] == 'group:publish',
        );
        final payload =
            (jsonDecode(publishMsg) as Map)['payload'] as Map<String, dynamic>;
        expect(payload['messageId'], messageId);
        expect(payload['text'], '');
        expect(payload['media'], isNotNull);
        expect((payload['media'] as List), hasLength(1));
        final publishMedia =
            (payload['media'] as List).single as Map<String, dynamic>;
        expect(publishMedia['id'], voiceAttachment.id);
        expect(publishMedia['mime'], 'audio/mp4');
        expect(publishMedia['mediaType'], 'audio');
        expect(publishMedia['durationMs'], 3000);
        expect(publishMedia['waveform'], [0.1, 0.5, 0.8, 0.3]);

        final replayPayload = _decodedGroupInboxReplayPayload(bridge);
        expect(replayPayload['messageId'], messageId);
        expect(replayPayload['text'], '');
        expect(replayPayload['timestamp'], sentAt.toIso8601String());
        expect(replayPayload['media'], isNotNull);
        final replayMedia =
            (replayPayload['media'] as List).single as Map<String, dynamic>;
        expect(replayMedia['id'], voiceAttachment.id);
        expect(replayMedia['mime'], 'audio/mp4');
        expect(replayMedia['mediaType'], 'audio');

        expect(mediaRepo.count, 1);
        final savedAttachments = await mediaRepo.getAttachmentsForMessage(
          messageId,
          owner: MediaOwnerLane.group,
        );
        expect(savedAttachments, hasLength(1));
      },
    );

    test(
      'PL-012 media schema variants survive live publish and replay payloads',
      () async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-2',
            username: 'Bob',
            role: MemberRole.writer,
            joinedAt: DateTime.utc(2026, 5, 16),
          ),
        );
        const messageId = 'pl012-media-schema-variants';
        final sentAt = DateTime.utc(2026, 5, 16, 3, 4);
        final variants = <MediaAttachment>[
          MediaAttachment(
            id: 'att-pl012-image',
            messageId: '',
            mime: 'image/jpeg',
            size: 4096,
            mediaType: 'image',
            width: 800,
            height: 600,
            downloadStatus: 'done',
            createdAt: sentAt.toIso8601String(),
            localPath: '/tmp/pl012-image.jpg',
            contentHash: _validContentHash,
            encryptionKeyBase64: 'key-pl012-image',
            encryptionNonce: 'nonce-pl012-image',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ),
          MediaAttachment(
            id: 'att-pl012-gif',
            messageId: '',
            mime: 'image/gif',
            size: 2048,
            mediaType: 'image',
            width: 320,
            height: 240,
            downloadStatus: 'done',
            createdAt: sentAt.toIso8601String(),
            localPath: '/tmp/pl012-gif.gif',
            contentHash: _validContentHash,
            encryptionKeyBase64: 'key-pl012-gif',
            encryptionNonce: 'nonce-pl012-gif',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ),
          MediaAttachment(
            id: 'att-pl012-video',
            messageId: '',
            mime: 'video/mp4',
            size: 8192,
            mediaType: 'video',
            width: 1280,
            height: 720,
            durationMs: 12000,
            downloadStatus: 'done',
            createdAt: sentAt.toIso8601String(),
            localPath: '/tmp/pl012-video.mp4',
            contentHash: _validContentHash,
            encryptionKeyBase64: 'key-pl012-video',
            encryptionNonce: 'nonce-pl012-video',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ),
          MediaAttachment(
            id: 'att-pl012-voice',
            messageId: '',
            mime: 'audio/mp4',
            size: 3072,
            mediaType: 'audio',
            durationMs: 3300,
            waveform: const <double>[0.1, 0.4, 0.2],
            downloadStatus: 'done',
            createdAt: sentAt.toIso8601String(),
            localPath: '/tmp/pl012-voice.m4a',
            contentHash: _validContentHash,
            encryptionKeyBase64: 'key-pl012-voice',
            encryptionNonce: 'nonce-pl012-voice',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ),
        ];
        final expectedMedia = variants.map((a) => a.toJson()).toList();

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'PL-012 schema variants',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: messageId,
          timestamp: sentAt,
          mediaAttachments: variants,
          mediaAttachmentRepo: mediaRepo,
        );

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        expect(message!.id, messageId);

        final publishMsg = bridge.sentMessages.firstWhere(
          (m) => (jsonDecode(m) as Map)['cmd'] == 'group:publish',
        );
        final payload =
            (jsonDecode(publishMsg) as Map)['payload'] as Map<String, dynamic>;
        expect(payload['messageId'], messageId);
        expect(payload['text'], 'PL-012 schema variants');
        expect(payload['media'], expectedMedia);

        final replayPayload = _decodedGroupInboxReplayPayload(bridge);
        expect(replayPayload['messageId'], messageId);
        expect(replayPayload['text'], 'PL-012 schema variants');
        expect(replayPayload['timestamp'], sentAt.toIso8601String());
        expect(replayPayload['media'], expectedMedia);

        final savedAttachments = await mediaRepo.getAttachmentsForMessage(
          messageId,
          owner: MediaOwnerLane.group,
        );
        expect(savedAttachments, hasLength(variants.length));
        expect(savedAttachments.map((a) => a.toJson()).toList(), expectedMedia);
        expect(
          savedAttachments.map((a) => a.messageId),
          everyElement(messageId),
        );
      },
    );

    test(
      'ML-017 retained removed history rejects send before bootstrap-key checks',
      () async {
        await groupRepo.removeMember('group-1', 'peer-1');
        await groupRepo.removeAllKeys('group-1');
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-2',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-2',
            joinedAt: DateTime.utc(2026, 1, 2),
          ),
        );

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Removed history should stay read-only',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
        );

        expect(result, SendGroupMessageResult.unauthorized);
        expect(message, isNull);
        expect(msgRepo.count, 0);
        expect(bridge.commandLog, isEmpty);
      },
    );

    test(
      'ML-017 retained removed admin with empty active members is unauthorized',
      () async {
        await groupRepo.removeAllMembers('group-1');
        await groupRepo.removeAllKeys('group-1');

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Removed admin history should stay read-only',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
        );

        expect(result, SendGroupMessageResult.unauthorized);
        expect(message, isNull);
        expect(msgRepo.count, 0);
        expect(bridge.commandLog, isEmpty);
      },
    );

    test(
      'ML-017 missing retained key stops stale local member sends before publish',
      () async {
        await groupRepo.removeAllKeys('group-1');

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Stale member row should not publish without a key',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
        );

        expect(result, SendGroupMessageResult.error);
        expect(message, isNull);
        expect(msgRepo.count, 0);
        expect(bridge.commandLog, isEmpty);
      },
    );

    test(
      'announcement voice-only send accepts empty text and writes exact voice push body',
      () async {
        final announcementGroup = GroupModel(
          id: 'group-announce-voice',
          name: 'Voice Announces',
          type: GroupType.announcement,
          topicName: 'group-topic-announce-voice',
          createdAt: DateTime.now().toUtc(),
          createdBy: 'peer-1',
          myRole: GroupRole.admin,
        );
        await groupRepo.saveGroup(announcementGroup);
        await _saveGroupKey(groupRepo, announcementGroup.id);
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'group-announce-voice',
            keyGeneration: 5,
            encryptedKey: 'voice-key',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        final voiceAttachment = MediaAttachment(
          id: 'att-announce-voice',
          messageId: '',
          mime: 'audio/mp4',
          size: 64000,
          mediaType: 'audio',
          downloadStatus: 'done',
          createdAt: DateTime.now().toUtc().toIso8601String(),
          localPath: '/tmp/announce-voice.m4a',
          durationMs: 1800,
          waveform: [0.2, 0.4, 0.8],
          contentHash: _validContentHash,
          encryptionKeyBase64: 'key-att-announce-voice',
          encryptionNonce: 'nonce-att-announce-voice',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-announce-voice',
          text: '',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          mediaAttachments: [voiceAttachment],
          mediaAttachmentRepo: mediaRepo,
          messageId: 'msg-announce-voice',
        );

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        expect(message!.id, 'msg-announce-voice');
        expect(message.text, '');
        expect(message.keyGeneration, 5);
        expect(message.status, 'sent');

        final inboxPayload = _lastGroupInboxStorePayload(bridge);
        expect(inboxPayload.containsKey('pushTitle'), isFalse);
        expect(inboxPayload.containsKey('pushBody'), isFalse);
        final inboxEnvelope =
            jsonDecode(inboxPayload['message'] as String)
                as Map<String, dynamic>;
        expect(inboxEnvelope['keyEpoch'], 5);
        expect(inboxEnvelope['messageId'], 'msg-announce-voice');
      },
    );

    test('rejects message with empty text and no media', () async {
      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: '',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );

      expect(result, SendGroupMessageResult.error);
      expect(message, isNull);
      // Should not have called bridge at all
      expect(bridge.commandLog, isEmpty);
    });

    test(
      'PL-003 empty text without media is rejected before local ghost row or bridge publish',
      () async {
        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: ' \n\t ',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'pl003-empty-no-media',
        );

        expect(result, SendGroupMessageResult.error);
        expect(message, isNull);
        expect(msgRepo.count, 0);
        expect(await msgRepo.getMessagesPage('group-1'), isEmpty);
        expect(await msgRepo.getMessage('pl003-empty-no-media'), isNull);
        expect(bridge.sentMessages, isEmpty);
        expect(bridge.commandLog, isEmpty);
      },
    );

    test('rejects message with whitespace-only text and no media', () async {
      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: '   ',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );

      expect(result, SendGroupMessageResult.error);
      expect(message, isNull);
    });

    test(
      'topicPeers zero returns successNoPeers when durable inbox store succeeds',
      () async {
        // When the Go pubsub topic has zero peers, publish still returns ok:true
        // because the durable inbox store is the fallback path. The send should
        // return successNoPeers while persisting the row as a successful send.
        bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'msg-zero-peers',
          'topicPeers': 0,
        };

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'No peers online',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
        );

        expect(result, SendGroupMessageResult.successNoPeers);
        expect(message, isNotNull);
        expect(message!.text, 'No peers online');
        expect(message.status, 'sent');
        // Both publish and inbox store should have been called
        expect(bridge.commandLog, contains('group:publish'));
        expect(bridge.commandLog, contains('group:inboxStore'));
      },
    );

    test(
      'announcement admin send returns successNoPeers when live fanout is zero',
      () async {
        // Admin in an announcement group should return successNoPeers when
        // no peers are online (zero live fanout), because the durable
        // inbox store ensures offline readers will catch up.
        final announcementGroup = GroupModel(
          id: 'group-announce-zero',
          name: 'Announces',
          type: GroupType.announcement,
          topicName: 'group-topic-announce-zero',
          createdAt: DateTime.now().toUtc(),
          createdBy: 'peer-1',
          myRole: GroupRole.admin,
        );
        await groupRepo.saveGroup(announcementGroup);
        await _saveGroupKey(groupRepo, announcementGroup.id);

        bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'msg-announce-zero',
          'topicPeers': 0,
        };

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-announce-zero',
          text: 'Announcement to empty room',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
        );

        expect(result, SendGroupMessageResult.successNoPeers);
        expect(message, isNotNull);
        expect(message!.status, 'sent');
      },
    );

    test(
      'announcement admin send after key rotation uses the new epoch and remains authorized',
      () async {
        final announcementGroup = GroupModel(
          id: 'group-announce-rotated',
          name: 'Announces Rotated',
          type: GroupType.announcement,
          topicName: 'group-topic-announce-rotated',
          createdAt: DateTime.now().toUtc(),
          createdBy: 'peer-1',
          myRole: GroupRole.admin,
        );
        await groupRepo.saveGroup(announcementGroup);
        await _saveGroupKey(groupRepo, announcementGroup.id);
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'group-announce-rotated',
            keyGeneration: 1,
            encryptedKey: 'old-key',
            createdAt: DateTime.now().toUtc(),
          ),
        );
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'group-announce-rotated',
            keyGeneration: 2,
            encryptedKey: 'new-key',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'msg-announce-rotated',
          'topicPeers': 1,
        };

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-announce-rotated',
          text: 'Post-rotation announcement',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'msg-announce-rotated',
        );

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        expect(message!.keyGeneration, 2);
        expect(message.status, 'sent');
        expect(bridge.commandLog, contains('group:publish'));
        expect(bridge.commandLog, contains('group:inboxStore'));

        final inboxPayload = _lastGroupInboxStorePayload(bridge);
        final inboxEnvelope =
            jsonDecode(inboxPayload['message'] as String)
                as Map<String, dynamic>;
        expect(inboxEnvelope['keyEpoch'], 2);
        expect(inboxEnvelope['messageId'], 'msg-announce-rotated');
      },
    );

    test(
      'announcement non-admin remains blocked before any network send starts',
      () async {
        // Non-admin in an announcement group must be rejected before
        // any bridge calls are made (no publish, no inbox store).
        final announcementGroup = GroupModel(
          id: 'group-announce-blocked',
          name: 'Announces Blocked',
          type: GroupType.announcement,
          topicName: 'group-topic-announce-blocked',
          createdAt: DateTime.now().toUtc(),
          createdBy: 'peer-admin',
          myRole: GroupRole.member,
        );
        await groupRepo.saveGroup(announcementGroup);
        await _saveGroupKey(groupRepo, announcementGroup.id);

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-announce-blocked',
          text: 'Trying to announce',
          senderPeerId: 'peer-2',
          senderPublicKey: 'pk-2',
          senderPrivateKey: 'sk-2',
          senderUsername: 'Bob',
        );

        expect(result, SendGroupMessageResult.unauthorized);
        expect(message, isNull);
        // No bridge calls should have been made at all
        expect(bridge.commandLog, isEmpty);
      },
    );

    test('text-only message without media — no media in payload', () async {
      await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Hello!',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );

      final publishMsg = bridge.sentMessages.firstWhere(
        (m) => (jsonDecode(m) as Map)['cmd'] == 'group:publish',
      );
      final payload =
          (jsonDecode(publishMsg) as Map)['payload'] as Map<String, dynamic>;
      expect(payload.containsKey('media'), isFalse);
    });
  });

  group('MS-018: key rotation epoch binding', () {
    test(
      'send snapshots current epoch for row and replay envelope before publish completes',
      () async {
        final gatedBridge = _GatedPublishBridge();
        gatedBridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'msg-ms018-snapshot',
          'topicPeers': 1,
        };
        final trackingRepo = _SaveTrackingGroupMessageRepository();
        final fixedTime = DateTime.utc(2026, 4, 29, 10, 0);

        final sendFuture = sendGroupMessage(
          bridge: gatedBridge,
          groupRepo: groupRepo,
          msgRepo: trackingRepo,
          groupId: 'group-1',
          text: 'Created before epoch commit',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'msg-ms018-snapshot',
          timestamp: fixedTime,
        );

        final firstSaved = await trackingRepo.firstSave.future;
        expect(firstSaved.keyGeneration, 1);
        expect(firstSaved.inboxRetryPayload, isNotNull);

        final prePersistEnvelope = _offlineReplayEnvelopeFromRetryPayload(
          firstSaved.inboxRetryPayload!,
        );
        expect(prePersistEnvelope['keyEpoch'], 1);
        expect(prePersistEnvelope['messageId'], 'msg-ms018-snapshot');

        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: 'group-1',
            keyGeneration: 2,
            encryptedKey: 'test-group-key-2',
            createdAt: DateTime.now().toUtc(),
          ),
        );

        gatedBridge.publishGate.complete();
        final (result, message) = await sendFuture;

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        expect(message!.keyGeneration, 1);

        final saved = await trackingRepo.getMessage('msg-ms018-snapshot');
        expect(saved, isNotNull);
        expect(saved!.keyGeneration, 1);

        final storedEnvelope = _lastGroupOfflineReplayEnvelope(gatedBridge);
        expect(storedEnvelope['keyEpoch'], 1);
        expect(storedEnvelope['messageId'], 'msg-ms018-snapshot');
      },
    );

    test(
      'messages before during and after rotation bind to the locally committed epoch',
      () async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-bob',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-bob',
            mlKemPublicKey: 'mlkem-bob',
            joinedAt: DateTime.now().toUtc(),
          ),
        );
        bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': 'test-group-key-2',
          'keyEpoch': 2,
        };
        bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'publish-ok',
          'topicPeers': 1,
        };

        final (beforeResult, beforeMessage) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Before rotation commit',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'msg-ms018-before',
        );
        expect(beforeResult, SendGroupMessageResult.success);
        expect(beforeMessage, isNotNull);
        expect(beforeMessage!.keyGeneration, 1);
        expect(_lastGroupOfflineReplayEnvelope(bridge)['keyEpoch'], 1);

        final distributionStarted = Completer<void>();
        final distributionGate = Completer<bool>();
        final rotationFuture = rotateAndDistributeGroupKey(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: 'group-1',
          selfPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          perRecipientTimeout: const Duration(seconds: 5),
          distributionTimeout: const Duration(seconds: 5),
          sendP2PMessage: (peerId, message) {
            if (!distributionStarted.isCompleted) {
              distributionStarted.complete();
            }
            return distributionGate.future;
          },
        );
        await distributionStarted.future;

        final latestDuringRotation = await groupRepo.getLatestKey('group-1');
        expect(latestDuringRotation, isNotNull);
        expect(latestDuringRotation!.keyGeneration, 1);
        expect(await groupRepo.getKeyByGeneration('group-1', 2), isNull);
        expect(_bridgeCommandIndex(bridge, 'group:updateKey', keyEpoch: 2), -1);

        final (duringResult, duringMessage) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'During rotation distribution',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'msg-ms018-during',
        );
        expect(duringResult, SendGroupMessageResult.success);
        expect(duringMessage, isNotNull);
        expect(duringMessage!.keyGeneration, 1);
        expect(_lastGroupOfflineReplayEnvelope(bridge)['keyEpoch'], 1);

        distributionGate.complete(true);
        final rotatedKey = await rotationFuture;
        expect(rotatedKey.key, isNotNull);
        expect(rotatedKey.key!.keyGeneration, 2);

        final latestAfterRotation = await groupRepo.getLatestKey('group-1');
        expect(latestAfterRotation, isNotNull);
        expect(latestAfterRotation!.keyGeneration, 2);

        final (afterResult, afterMessage) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'After rotation commit',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'msg-ms018-after',
        );
        expect(afterResult, SendGroupMessageResult.success);
        expect(afterMessage, isNotNull);
        expect(afterMessage!.keyGeneration, 2);
        expect(_lastGroupOfflineReplayEnvelope(bridge)['keyEpoch'], 2);

        final beforeSaved = await msgRepo.getMessage('msg-ms018-before');
        final duringSaved = await msgRepo.getMessage('msg-ms018-during');
        final afterSaved = await msgRepo.getMessage('msg-ms018-after');
        expect(beforeSaved!.keyGeneration, 1);
        expect(duringSaved!.keyGeneration, 1);
        expect(afterSaved!.keyGeneration, 2);
      },
    );

    test(
      'installed legacy resolver lets distribution overlap send but fences epoch promotion',
      () async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-bob',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-bob',
            mlKemPublicKey: 'mlkem-bob',
            joinedAt: DateTime.now().toUtc(),
          ),
        );
        setGroupContentAuthoringResolver(
          groupRepo,
          ({
            required String groupId,
            required String senderPeerId,
            required String senderPublicKey,
            String? senderDeviceId,
            String? senderTransportPeerId,
          }) async => const (
            kind: GroupContentAuthoringResolutionKind.legacyUninitialized,
            context: null,
          ),
        );
        addTearDown(() => setGroupContentAuthoringResolver(groupRepo, null));

        final gatedBridge = _GatedPublishBridge();
        gatedBridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': 'test-group-key-2',
          'keyEpoch': 2,
        };
        gatedBridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'resolver-rotation-send',
          'topicPeers': 1,
        };
        final distributionStarted = Completer<void>();
        final distributionGate = Completer<bool>();
        final rotationFuture = rotateAndDistributeGroupKey(
          bridge: gatedBridge,
          groupRepo: groupRepo,
          groupId: 'group-1',
          selfPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          sendP2PMessage: (peerId, message) {
            if (!distributionStarted.isCompleted) {
              distributionStarted.complete();
            }
            return distributionGate.future;
          },
        );
        await distributionStarted.future;

        final sendFuture = sendGroupMessage(
          bridge: gatedBridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Legacy send during distribution',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'resolver-rotation-send',
        );
        await gatedBridge.publishStarted.future;

        distributionGate.complete(true);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(
          _bridgeCommandIndex(gatedBridge, 'group:updateKey', keyEpoch: 2),
          -1,
          reason: 'epoch promotion must wait for the legacy send action',
        );
        expect((await groupRepo.getLatestKey('group-1'))!.keyGeneration, 1);

        gatedBridge.publishGate.complete();
        final (sendResult, sentMessage) = await sendFuture;
        expect(sendResult, SendGroupMessageResult.success);
        expect(sentMessage!.keyGeneration, 1);

        final rotated = await rotationFuture;
        expect(rotated.key, isNotNull);
        expect(rotated.key!.keyGeneration, 2);
        expect((await groupRepo.getLatestKey('group-1'))!.keyGeneration, 2);
      },
    );

    test(
      'ST-006 rotation-boundary sends keep active recipients and valid epochs',
      () async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-bob',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-bob',
            mlKemPublicKey: 'mlkem-bob',
            joinedAt: DateTime.now().toUtc(),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-charlie',
            username: 'Charlie',
            role: MemberRole.writer,
            publicKey: 'pk-charlie',
            mlKemPublicKey: 'mlkem-charlie',
            joinedAt: DateTime.now().toUtc(),
          ),
        );
        await groupRepo.removeMember('group-1', 'peer-charlie');

        bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': 'test-group-key-2',
          'keyEpoch': 2,
        };
        bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'st006-publish-ok',
          'topicPeers': 1,
        };

        final distributionStarted = Completer<void>();
        final distributionGate = Completer<bool>();
        final distributionTargets = <String>[];
        final rotationFuture = rotateAndDistributeGroupKey(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: 'group-1',
          selfPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          perRecipientTimeout: const Duration(seconds: 5),
          distributionTimeout: const Duration(seconds: 5),
          sendP2PMessage: (peerId, message) {
            distributionTargets.add(peerId);
            if (!distributionStarted.isCompleted) {
              distributionStarted.complete();
            }
            return distributionGate.future;
          },
        );
        await distributionStarted.future;

        final (bobDuringResult, bobDuringMessage) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'ST-006 Bob during rotation',
          senderPeerId: 'peer-bob',
          senderPublicKey: 'pk-bob',
          senderPrivateKey: 'sk-bob',
          senderUsername: 'Bob',
          messageId: 'st006-bob-during-rotation',
        );
        expect(bobDuringResult, SendGroupMessageResult.success);
        expect(bobDuringMessage, isNotNull);
        expect(bobDuringMessage!.keyGeneration, 1);

        distributionGate.complete(true);
        final rotatedKey = await rotationFuture;
        expect(rotatedKey.key, isNotNull);
        expect(rotatedKey.key!.keyGeneration, 2);
        expect(distributionTargets, ['peer-bob']);
        expect(distributionTargets, isNot(contains('peer-charlie')));
        expect(
          _bridgeCommandIndex(bridge, 'group:updateKey', keyEpoch: 2),
          isNot(-1),
        );

        final (aliceAfterResult, aliceAfterMessage) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'ST-006 Alice after rotation',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'st006-alice-after-rotation',
        );
        expect(aliceAfterResult, SendGroupMessageResult.success);
        expect(aliceAfterMessage, isNotNull);
        expect(aliceAfterMessage!.keyGeneration, 2);

        Map<String, dynamic> inboxPayloadFor(String messageId) {
          final inboxMessages = bridge.sentMessages
              .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
              .where((message) => message['cmd'] == 'group:inboxStore');
          for (final message in inboxMessages) {
            final payload = (message['payload'] as Map).cast<String, dynamic>();
            final envelope =
                jsonDecode(payload['message'] as String)
                    as Map<String, dynamic>;
            if (envelope['messageId'] == messageId) {
              return payload;
            }
          }
          fail('Missing group:inboxStore payload for $messageId');
        }

        Map<String, dynamic> envelopeFor(String messageId) {
          return jsonDecode(inboxPayloadFor(messageId)['message'] as String)
              as Map<String, dynamic>;
        }

        final bobDuringPayload = inboxPayloadFor('st006-bob-during-rotation');
        final aliceAfterPayload = inboxPayloadFor('st006-alice-after-rotation');
        expect(bobDuringPayload['recipientPeerIds'], ['peer-1']);
        expect(aliceAfterPayload['recipientPeerIds'], ['peer-bob']);
        expect(
          bobDuringPayload['recipientPeerIds'],
          isNot(contains('peer-charlie')),
        );
        expect(
          aliceAfterPayload['recipientPeerIds'],
          isNot(contains('peer-charlie')),
        );
        expect(envelopeFor('st006-bob-during-rotation')['keyEpoch'], 1);
        expect(envelopeFor('st006-alice-after-rotation')['keyEpoch'], 2);

        final bobSaved = await msgRepo.getMessage('st006-bob-during-rotation');
        final aliceSaved = await msgRepo.getMessage(
          'st006-alice-after-rotation',
        );
        expect(bobSaved!.keyGeneration, 1);
        expect(aliceSaved!.keyGeneration, 2);
      },
    );

    test(
      'ST-007 process-death checkpoints resume without ghost members or deaf active recipients',
      () async {
        final checkpointEvidence = <String, Map<String, Object?>>{};

        GroupMember member(String peerId, String username) {
          return GroupMember(
            groupId: 'group-1',
            peerId: peerId,
            username: username,
            role: MemberRole.writer,
            publicKey: 'pk-$peerId',
            mlKemPublicKey: 'mlkem-$peerId',
            joinedAt: DateTime.now().toUtc(),
          );
        }

        List<String> inboxRecipients(String messageId, FakeBridge source) {
          final inboxMessages = source.sentMessages
              .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
              .where((message) => message['cmd'] == 'group:inboxStore');
          for (final message in inboxMessages) {
            final payload = (message['payload'] as Map).cast<String, dynamic>();
            final envelope =
                jsonDecode(payload['message'] as String)
                    as Map<String, dynamic>;
            if (envelope['messageId'] == messageId) {
              return (payload['recipientPeerIds'] as List<dynamic>)
                  .cast<String>()
                  .toList(growable: false);
            }
          }
          fail('Missing group:inboxStore payload for $messageId');
        }

        Future<GroupMessage> sendCheckpointMessage({
          required String checkpoint,
          required FakeBridge sourceBridge,
          required Set<String> expectedRecipients,
        }) async {
          sourceBridge.responses['group:publish'] = {
            'ok': true,
            'messageId': 'st007-$checkpoint',
            'topicPeers': expectedRecipients.length,
          };
          final (result, message) = await sendGroupMessage(
            bridge: sourceBridge,
            groupRepo: groupRepo,
            msgRepo: msgRepo,
            groupId: 'group-1',
            text: 'ST-007 $checkpoint active delivery',
            senderPeerId: 'peer-1',
            senderPublicKey: 'pk-1',
            senderPrivateKey: 'sk-1',
            senderUsername: 'Alice',
            messageId: 'st007-$checkpoint',
          );
          expect(result, SendGroupMessageResult.success);
          expect(message, isNotNull);
          expect(inboxRecipients('st007-$checkpoint', sourceBridge).toSet(), {
            ...expectedRecipients,
          });
          return message!;
        }

        await groupRepo.saveMember(member('peer-bob', 'Bob'));

        final rollbackBridge = FakeBridge();
        rollbackBridge.responses['group:updateConfig'] = {
          'ok': false,
          'errorCode': 'ST007_CONFIG_SYNC_FAILED',
          'errorMessage': 'crash after local db write',
        };
        await expectLater(
          addGroupMember(
            bridge: rollbackBridge,
            groupRepo: groupRepo,
            groupId: 'group-1',
            newMember: member('peer-charlie', 'Charlie'),
            selfPeerId: 'peer-1',
          ),
          throwsA(isA<Exception>()),
        );
        checkpointEvidence['local_db_write'] = <String, Object?>{
          'rolledBackGhostMember':
              await groupRepo.getMember('group-1', 'peer-charlie') == null,
          'activeBobStillPresent':
              await groupRepo.getMember('group-1', 'peer-bob') != null,
        };

        await addGroupMember(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: 'group-1',
          newMember: member('peer-charlie', 'Charlie'),
          selfPeerId: 'peer-1',
        );
        final bridgeUpdateMessage = await sendCheckpointMessage(
          checkpoint: 'bridge_update',
          sourceBridge: bridge,
          expectedRecipients: {'peer-bob', 'peer-charlie'},
        );
        checkpointEvidence['bridge_update'] = <String, Object?>{
          'charliePresentAfterRestart':
              await groupRepo.getMember('group-1', 'peer-charlie') != null,
          'deliveryEpoch': bridgeUpdateMessage.keyGeneration,
        };

        bridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': 'st007-key-generation-draft',
          'keyEpoch': 2,
        };
        final failedDistribution = await rotateAndDistributeGroupKey(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: 'group-1',
          selfPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          sendP2PMessage: (peerId, message) async => peerId == 'peer-bob',
        );
        // R-1 promote-then-defer: a partial fanout no longer ABORTS. The new
        // epoch is generated and promoted locally regardless of distribution so
        // the rotation boundary holds (removed members lose the live key). The
        // member whose every send failed (peer-charlie) is recorded as deferred,
        // not rolled back; peer-bob is delivered. The draft is consumed on
        // promotion, so no pending rotation remains and getLatestKey is epoch 2.
        expect(failedDistribution.rotated, isTrue);
        expect(failedDistribution.key, isNotNull);
        expect(failedDistribution.key!.keyGeneration, 2);
        expect(
          failedDistribution.key!.encryptedKey,
          'st007-key-generation-draft',
        );
        expect(failedDistribution.distributedDeviceCount, 1);
        expect(failedDistribution.deferredPeerIds, ['peer-charlie']);
        expect(failedDistribution.fullyDistributed, isFalse);
        final pendingDraft = await groupRepo.getPendingKeyRotation('group-1');
        expect(pendingDraft, isNull);
        expect((await groupRepo.getLatestKey('group-1'))!.keyGeneration, 2);

        // Resume: a follow-up rotation now converges the deferred member. With
        // the epoch already at 2 and the draft consumed, this generates the next
        // epoch (3) and delivers it to BOTH remaining members (transport up for
        // all), so distribution is full and nobody is deferred.
        final retryBridge = FakeBridge();
        retryBridge.responses['group:generateNextKey'] = {
          'ok': true,
          'groupKey': 'st007-key-generation-redraft',
          'keyEpoch': 3,
        };
        retryBridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'st007-key-rotated',
        };
        final retryRotation = await rotateAndDistributeGroupKey(
          bridge: retryBridge,
          groupRepo: groupRepo,
          groupId: 'group-1',
          selfPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          sendP2PMessage: (peerId, message) async => true,
        );
        expect(retryRotation.rotated, isTrue);
        expect(retryRotation.key, isNotNull);
        expect(retryRotation.key!.keyGeneration, 3);
        expect(retryRotation.key!.encryptedKey, 'st007-key-generation-redraft');
        expect(retryRotation.distributedDeviceCount, 2);
        expect(retryRotation.deferredPeerIds, isEmpty);
        expect(retryRotation.fullyDistributed, isTrue);
        expect((await groupRepo.getLatestKey('group-1'))!.keyGeneration, 3);
        final keyGenerationMessage = await sendCheckpointMessage(
          checkpoint: 'key_generation',
          sourceBridge: retryBridge,
          expectedRecipients: {'peer-bob', 'peer-charlie'},
        );
        checkpointEvidence['key_generation'] = <String, Object?>{
          'convergedAllMembersAfterPartial': retryRotation.fullyDistributed,
          'deliveryEpoch': keyGenerationMessage.keyGeneration,
        };

        await removeGroupMember(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: 'group-1',
          memberPeerId: 'peer-charlie',
          selfPeerId: 'peer-1',
        );
        final removeMessage = await sendCheckpointMessage(
          checkpoint: 'invite_send',
          sourceBridge: bridge,
          expectedRecipients: {'peer-bob'},
        );
        checkpointEvidence['invite_send'] = <String, Object?>{
          'charlieGhostAbsent':
              await groupRepo.getMember('group-1', 'peer-charlie') == null,
          'activeBobReceivedByInboxTarget': inboxRecipients(
            'st007-invite_send',
            bridge,
          ).contains('peer-bob'),
          'removedWindowEpoch': removeMessage.keyGeneration,
        };

        await addGroupMember(
          bridge: bridge,
          groupRepo: groupRepo,
          groupId: 'group-1',
          newMember: member('peer-charlie', 'Charlie'),
          selfPeerId: 'peer-1',
        );
        final inboxRetryBridge = _FailFirstNInboxStoreBridge(failCount: 1);
        inboxRetryBridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'st007-inbox_store',
          'topicPeers': 2,
        };
        final (inboxResult, inboxMessage) = await sendGroupMessage(
          bridge: inboxRetryBridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'ST-007 inbox store retry after restart',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'st007-inbox_store',
        );
        expect(inboxResult, SendGroupMessageResult.success);
        expect(inboxMessage, isNotNull);
        expect(inboxMessage!.inboxRetryPayload, isNotNull);
        final retriedInboxStores = await retryFailedGroupInboxStores(
          bridge: inboxRetryBridge,
          msgRepo: msgRepo,
        );
        final recoveredInboxMessage = await msgRepo.getMessage(
          'st007-inbox_store',
        );
        checkpointEvidence['inbox_store'] = <String, Object?>{
          'retryPromotedPendingRow': retriedInboxStores == 1,
          'inboxStoredAfterRestart': recoveredInboxMessage?.inboxStored == true,
        };

        final ackMessage = await sendCheckpointMessage(
          checkpoint: 'ack',
          sourceBridge: bridge,
          expectedRecipients: {'peer-bob', 'peer-charlie'},
        );
        checkpointEvidence['ack'] = <String, Object?>{
          'finalActiveMembers': (await groupRepo.getMembers(
            'group-1',
          )).map((member) => member.peerId).toSet(),
          'finalDeliveryEpoch': ackMessage.keyGeneration,
        };

        expect(checkpointEvidence.keys.toSet(), {
          'local_db_write',
          'bridge_update',
          'key_generation',
          'invite_send',
          'inbox_store',
          'ack',
        });
        expect(
          checkpointEvidence.values.every(
            (evidence) => evidence.values.every((value) => value != false),
          ),
          isTrue,
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // WU-3: Pre-persist, _tryInboxStore, topicPeers, 4-way result matrix
  // ---------------------------------------------------------------------------
  group('WU-3: pre-persist and send contract', () {
    test(
      'pre-persist: message saved with sending status + wireEnvelope + inboxRetryPayload BEFORE bridge call',
      () async {
        final gatedBridge = _GatedPublishBridge();
        gatedBridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'msg-123',
          'topicPeers': 2,
        };
        final trackingRepo = _SaveTrackingGroupMessageRepository();

        final fixedTime = DateTime.utc(2026, 1, 15, 12, 0, 0);
        var completed = false;
        final attemptWindowStart = DateTime.now().toUtc();

        final sendFuture =
            sendGroupMessage(
              bridge: gatedBridge,
              groupRepo: groupRepo,
              msgRepo: trackingRepo,
              groupId: 'group-1',
              text: 'Pre-persist test',
              senderPeerId: 'peer-1',
              senderPublicKey: 'pk-1',
              senderPrivateKey: 'sk-1',
              senderUsername: 'Alice',
              messageId: 'pre-persist-id',
              timestamp: fixedTime,
            ).then((value) {
              completed = true;
              return value;
            });

        final firstSaved = await trackingRepo.firstSave.future;
        final attemptWindowEnd = DateTime.now().toUtc();
        expect(firstSaved.id, 'pre-persist-id');
        expect(firstSaved.status, 'sending');
        expect(firstSaved.timestamp, fixedTime);
        expect(firstSaved.lastSendAttemptAt, isNotNull);
        expect(
          firstSaved.lastSendAttemptAt!.isBefore(attemptWindowStart),
          isFalse,
        );
        expect(
          firstSaved.lastSendAttemptAt!.isAfter(attemptWindowEnd),
          isFalse,
        );
        expect(firstSaved.wireEnvelope, isNotNull);
        expect(firstSaved.inboxRetryPayload, isNotNull);

        final savedWhilePublishBlocked = await trackingRepo.getMessage(
          'pre-persist-id',
        );
        expect(savedWhilePublishBlocked, isNotNull);
        expect(savedWhilePublishBlocked!.status, 'sending');
        expect(savedWhilePublishBlocked.wireEnvelope, isNotNull);
        expect(savedWhilePublishBlocked.inboxRetryPayload, isNotNull);
        expect(completed, isFalse);

        gatedBridge.publishGate.complete();
        final (result, message) = await sendFuture;

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);

        final saved = await trackingRepo.getMessage('pre-persist-id');
        expect(saved, isNotNull);
        expect(saved!.status, 'sent');
        expect(saved.timestamp, fixedTime);
        expect(saved.lastSendAttemptAt, firstSaved.lastSendAttemptAt);
      },
    );

    test(
      'GFR-001 same-attempt send reuses a matching pending outgoing row',
      () async {
        final originalTimestamp = DateTime.utc(2026, 6, 6, 8);
        await msgRepo.saveMessage(
          GroupMessage(
            id: 'gfr001-pending-send-reuse',
            groupId: 'group-1',
            senderPeerId: 'peer-1',
            senderUsername: 'Alice',
            text: 'GFR-001 pending retry text',
            timestamp: originalTimestamp,
            logicalDeliveryId: 'gfr001-logical-send-reuse',
            keyGeneration: 1,
            status: 'pending',
            isIncoming: false,
            createdAt: originalTimestamp,
            wireEnvelope: jsonEncode({
              'groupId': 'group-1',
              'text': 'GFR-001 pending retry text',
              'senderPeerId': 'peer-1',
              'senderUsername': 'Alice',
              'messageId': 'gfr001-pending-send-reuse',
              'logicalDeliveryId': 'gfr001-logical-send-reuse',
            }),
            inboxStored: false,
            inboxRetryPayload: jsonEncode({
              'groupId': 'group-1',
              'message': jsonEncode({
                'groupId': 'group-1',
                'senderId': 'peer-1',
                'senderUsername': 'Alice',
                'keyEpoch': 1,
                'text': 'GFR-001 pending retry text',
                'timestamp': originalTimestamp.toIso8601String(),
                'messageId': 'gfr001-pending-send-reuse',
                'logicalDeliveryId': 'gfr001-logical-send-reuse',
              }),
              'recipientPeerIds': const <String>[],
            }),
          ),
        );

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'GFR-001 pending retry text',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'gfr001-pending-send-reuse',
          logicalDeliveryId: 'gfr001-logical-send-reuse',
          timestamp: originalTimestamp,
        );

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        expect(message!.id, 'gfr001-pending-send-reuse');
        expect(message.logicalDeliveryId, 'gfr001-logical-send-reuse');
        expect(message.timestamp, originalTimestamp);
        final page = await msgRepo.getMessagesPage('group-1');
        expect(page.map((row) => row.id), ['gfr001-pending-send-reuse']);
        expect(page.single.status, 'sent');
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:publish'),
          hasLength(1),
        );
      },
    );

    test(
      'GFR-001 settled same-text sends with new ids remain distinct',
      () async {
        final firstTimestamp = DateTime.utc(2026, 6, 6, 8, 5);
        final secondTimestamp = firstTimestamp.add(const Duration(minutes: 1));

        final (firstResult, firstMessage) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'GFR-001 intentional repeat',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'gfr001-repeat-original',
          timestamp: firstTimestamp,
        );
        final (secondResult, secondMessage) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'GFR-001 intentional repeat',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'gfr001-repeat-second',
          timestamp: secondTimestamp,
        );

        expect(firstResult, SendGroupMessageResult.success);
        expect(secondResult, SendGroupMessageResult.success);
        expect(firstMessage!.id, 'gfr001-repeat-original');
        expect(secondMessage!.id, 'gfr001-repeat-second');
        final page = await msgRepo.getMessagesPage('group-1');
        expect(page.map((row) => row.id).toSet(), {
          'gfr001-repeat-original',
          'gfr001-repeat-second',
        });
        expect(page.map((row) => row.logicalDeliveryId).toSet(), {
          'gfr001-repeat-original',
          'gfr001-repeat-second',
        });
      },
    );

    test(
      'NW-011 send pre-persist survives lifecycle cancellation window',
      () async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-2',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-2',
            joinedAt: DateTime.utc(2026, 5, 13, 1),
          ),
        );

        final gatedBridge = _GatedPublishBridge();
        gatedBridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'nw011-prepersist-send',
          'topicPeers': 1,
        };
        final trackingRepo = _SaveTrackingGroupMessageRepository();
        final sendFuture = sendGroupMessage(
          bridge: gatedBridge,
          groupRepo: groupRepo,
          msgRepo: trackingRepo,
          groupId: 'group-1',
          text: 'NW-011 pre-persist send',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'nw011-prepersist-send',
          timestamp: DateTime.utc(2026, 5, 13, 1, 1),
        );

        final firstSaved = await trackingRepo.firstSave.future;
        expect(firstSaved.id, 'nw011-prepersist-send');
        expect(firstSaved.status, 'sending');
        expect(firstSaved.wireEnvelope, isNotNull);
        expect(firstSaved.inboxRetryPayload, isNotNull);
        expect(gatedBridge.commandLog, isNot(contains('group:publish')));

        final transitioned = await trackingRepo.transitionSendingToFailed();
        expect(transitioned, 1);
        final failedDuringPause = await trackingRepo.getMessage(
          'nw011-prepersist-send',
        );
        expect(failedDuringPause, isNotNull);
        expect(failedDuringPause!.status, 'failed');
        expect(failedDuringPause.wireEnvelope, firstSaved.wireEnvelope);
        expect(
          failedDuringPause.inboxRetryPayload,
          firstSaved.inboxRetryPayload,
        );

        await gatedBridge.publishStarted.future;

        gatedBridge.publishGate.complete();
        final (result, message) = await sendFuture;
        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        final finalRows = await trackingRepo.getMessagesPage('group-1');
        final finalMatches = finalRows
            .where((row) => row.id == 'nw011-prepersist-send')
            .toList(growable: false);
        expect(finalMatches, hasLength(1));
        expect(finalMatches.single.status, anyOf('sent', 'pending'));

        final retryBridge = _FailFirstNInboxStoreBridge(failCount: 1);
        retryBridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'nw011-pending-inbox-retry',
          'topicPeers': 1,
        };
        final retryRepo = InMemoryGroupMessageRepository();
        final (pendingResult, pendingMessage) = await sendGroupMessage(
          bridge: retryBridge,
          groupRepo: groupRepo,
          msgRepo: retryRepo,
          groupId: 'group-1',
          text: 'NW-011 pending inbox retry',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'nw011-pending-inbox-retry',
          timestamp: DateTime.utc(2026, 5, 13, 1, 2),
        );

        expect(pendingResult, SendGroupMessageResult.success);
        expect(pendingMessage, isNotNull);
        expect(pendingMessage!.status, 'sent');
        expect(pendingMessage.inboxRetryPayload, isNotNull);
        final pendingRows = await retryRepo.getMessagesWithFailedInboxStore();
        expect(pendingRows.map((row) => row.id), ['nw011-pending-inbox-retry']);

        final retried = await retryFailedGroupInboxStores(
          bridge: retryBridge,
          msgRepo: retryRepo,
        );
        expect(retried, 1);
        final recovered = await retryRepo.getMessage(
          'nw011-pending-inbox-retry',
        );
        expect(recovered, isNotNull);
        expect(recovered!.status, 'sent');
        expect(recovered.inboxStored, isTrue);
        expect(recovered.inboxRetryPayload, isNull);
        expect(
          (await retryRepo.getMessagesPage('group-1')).where(
            (row) =>
                !row.isIncoming && row.text == 'NW-011 pending inbox retry',
          ),
          hasLength(1),
        );
      },
    );

    test('pre-persist: unauthorized caller does NOT persist a row', () async {
      final announcementGroup = GroupModel(
        id: 'group-no-persist',
        name: 'Announcements',
        type: GroupType.announcement,
        topicName: 'group-topic-announce',
        createdAt: DateTime.now().toUtc(),
        createdBy: 'peer-admin',
        myRole: GroupRole.member,
      );
      await groupRepo.saveGroup(announcementGroup);
      await _saveGroupKey(groupRepo, announcementGroup.id);

      final (result, _) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-no-persist',
        text: 'Trying to send',
        senderPeerId: 'peer-2',
        senderPublicKey: 'pk-2',
        senderPrivateKey: 'sk-2',
        senderUsername: 'Bob',
      );

      expect(result, SendGroupMessageResult.unauthorized);
      expect(msgRepo.count, 0);
    });

    test('pre-persist: group-not-found does NOT persist a row', () async {
      final (result, _) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'nonexistent-group',
        text: 'No group',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
      );

      expect(result, SendGroupMessageResult.groupNotFound);
      expect(msgRepo.count, 0);
    });
  });

  group('WU-3: 0-peer publish detection and 4-way matrix', () {
    test(
      'DE-006 topicPeers matrix reports fanout without recipient receipt claim',
      () async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-2',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-2',
            joinedAt: DateTime.utc(2026, 5, 11, 8),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-3',
            username: 'Carol',
            role: MemberRole.writer,
            publicKey: 'pk-3',
            joinedAt: DateTime.utc(2026, 5, 11, 8, 1),
          ),
        );

        final cases =
            <
              ({
                int topicPeers,
                SendGroupMessageResult result,
                String fanoutState,
                String messageId,
              })
            >[
              (
                topicPeers: 0,
                result: SendGroupMessageResult.successNoPeers,
                fanoutState: 'zero_peers',
                messageId: 'de006-zero-peers',
              ),
              (
                topicPeers: 1,
                result: SendGroupMessageResult.success,
                fanoutState: 'partial_peers',
                messageId: 'de006-partial-peers',
              ),
              (
                topicPeers: 2,
                result: SendGroupMessageResult.success,
                fanoutState: 'full_peers',
                messageId: 'de006-full-peers',
              ),
            ];

        for (final scenario in cases) {
          bridge.responses['group:publish'] = {
            'ok': true,
            'messageId': scenario.messageId,
            'topicPeers': scenario.topicPeers,
          };

          late SendGroupMessageResult result;
          late GroupMessage? message;
          final events = await captureFlowEvents(() async {
            (result, message) = await sendGroupMessage(
              bridge: bridge,
              groupRepo: groupRepo,
              msgRepo: msgRepo,
              groupId: 'group-1',
              text: 'DE-006 ${scenario.fanoutState}',
              senderPeerId: 'peer-1',
              senderPublicKey: 'pk-1',
              senderPrivateKey: 'sk-1',
              senderUsername: 'Alice',
              messageId: scenario.messageId,
            );
          });

          expect(result, scenario.result);
          expect(message, isNotNull);
          expect(message!.status, isNot('delivered'));
          expect(message!.inboxStored, isTrue);
          expect(message!.inboxRetryPayload, isNull);

          final saved = await msgRepo.getMessage(scenario.messageId);
          expect(saved, isNotNull);
          expect(saved!.status, isNot('delivered'));
          expect(saved.inboxStored, isTrue);
          expect(saved.inboxRetryPayload, isNull);

          expect(
            await msgRepo.getReceiptsForMessage(
              'group-1',
              scenario.messageId,
              receiptType: groupMessageReceiptTypeDelivered,
            ),
            isEmpty,
          );
          expect(
            await msgRepo.getReceiptsForMessage(
              'group-1',
              scenario.messageId,
              receiptType: groupMessageReceiptTypeRead,
            ),
            isEmpty,
          );

          final timing = events.lastWhere(
            (event) => event['event'] == 'GROUP_SEND_MSG_TIMING',
          );
          final details = timing['details'] as Map<String, dynamic>;
          expect(details['topicPeers'], scenario.topicPeers);
          expect(details['expectedRecipientCount'], 2);
          expect(details['liveFanoutState'], scenario.fanoutState);
          expect(details['recipientReceiptClaimed'], isFalse);
          expect(details['inboxStored'], isTrue);
          expect(details['inboxPending'], isFalse);
        }
      },
    );

    test(
      'PGC-010 live publish with topic peers marks sent while inbox retry remains staged',
      () async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-2',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-2',
            joinedAt: DateTime.utc(2026, 5, 11, 8),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-3',
            username: 'Carol',
            role: MemberRole.writer,
            publicKey: 'pk-3',
            joinedAt: DateTime.utc(2026, 5, 11, 8, 1),
          ),
        );
        final failBridge = _SlowPublishInboxStoreFailBridge();
        failBridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'de006-partial-inbox-fail',
          'topicPeers': 1,
        };

        late SendGroupMessageResult result;
        late GroupMessage? message;
        final events = await captureFlowEvents(() async {
          (result, message) = await sendGroupMessage(
            bridge: failBridge,
            groupRepo: groupRepo,
            msgRepo: msgRepo,
            groupId: 'group-1',
            text: 'DE-006 partial inbox failure',
            senderPeerId: 'peer-1',
            senderPublicKey: 'pk-1',
            senderPrivateKey: 'sk-1',
            senderUsername: 'Alice',
            messageId: 'de006-partial-inbox-fail',
          );
        });

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'sent');
        expect(message!.status, isNot('delivered'));
        expect(message!.wireEnvelope, isNull);
        expect(message!.inboxStored, isFalse);
        expect(message!.inboxRetryPayload, isNotNull);
        expect(
          _recipientPeerIdsFromRetryPayload(message!.inboxRetryPayload!),
          unorderedEquals(<String>['peer-2', 'peer-3']),
        );

        final saved = await msgRepo.getMessage('de006-partial-inbox-fail');
        expect(saved, isNotNull);
        expect(saved!.status, 'sent');
        expect(saved.wireEnvelope, isNull);
        expect(saved.inboxStored, isFalse);
        expect(saved.inboxRetryPayload, isNotNull);
        expect(
          _recipientPeerIdsFromRetryPayload(saved.inboxRetryPayload!),
          unorderedEquals(<String>['peer-2', 'peer-3']),
        );
        final inboxRetryRows = await msgRepo.getMessagesWithFailedInboxStore();
        expect(inboxRetryRows.map((row) => row.id), [
          'de006-partial-inbox-fail',
        ]);

        expect(
          await msgRepo.getReceiptsForMessage(
            'group-1',
            'de006-partial-inbox-fail',
            receiptType: groupMessageReceiptTypeDelivered,
          ),
          isEmpty,
        );
        expect(
          await msgRepo.getReceiptsForMessage(
            'group-1',
            'de006-partial-inbox-fail',
            receiptType: groupMessageReceiptTypeRead,
          ),
          isEmpty,
        );

        final timing = events.lastWhere(
          (event) => event['event'] == 'GROUP_SEND_MSG_TIMING',
        );
        final details = timing['details'] as Map<String, dynamic>;
        expect(details['outcome'], 'success');
        expect(details['status'], 'sent');
        expect(details['topicPeers'], 1);
        expect(details['expectedRecipientCount'], 2);
        expect(details['liveFanoutState'], 'partial_peers');
        expect(details['recipientReceiptClaimed'], isFalse);
        expect(details['inboxStored'], isFalse);
        expect(details['inboxPending'], isFalse);
      },
    );

    test(
      'GSR-001 reliable send uses single native command and treats full live fanout as sent',
      () async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-2',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-2',
            joinedAt: DateTime.utc(2026, 5, 11, 8),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-3',
            username: 'Carol',
            role: MemberRole.writer,
            publicKey: 'pk-3',
            joinedAt: DateTime.utc(2026, 5, 11, 8, 1),
          ),
        );
        bridge.responses['group:sendReliable'] = {
          'ok': true,
          'messageId': 'gsr-001-full-live',
          'topicPeerCount': 2,
          'expectedRecipientCount': 2,
          'inboxStored': false,
          'publishSucceeded': true,
          'deliveryMode': 'live_only',
        };

        late SendGroupMessageResult result;
        late GroupMessage? message;
        final events = await captureFlowEvents(() async {
          (result, message) = await sendGroupMessage(
            bridge: bridge,
            groupRepo: groupRepo,
            msgRepo: msgRepo,
            groupId: 'group-1',
            text: 'GSR-001 full live fanout',
            senderPeerId: 'peer-1',
            senderPublicKey: 'pk-1',
            senderPrivateKey: 'sk-1',
            senderUsername: 'Alice',
            messageId: 'gsr-001-full-live',
          );
        });

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'sent');
        expect(message!.inboxStored, isFalse);
        expect(message!.inboxRetryPayload, isNotNull);
        expect(bridge.commandLog, contains('group:sendReliable'));
        expect(bridge.commandLog, isNot(contains('group:publish')));
        expect(bridge.commandLog, isNot(contains('group:inboxStore')));

        final timing = events.lastWhere(
          (event) => event['event'] == 'GROUP_SEND_MSG_TIMING',
        );
        final details = timing['details'] as Map<String, dynamic>;
        expect(details['status'], 'sent');
        expect(details['topicPeers'], 2);
        expect(details['expectedRecipientCount'], 2);
        expect(details['liveFanoutState'], 'full_peers');
        expect(details['inboxStored'], isFalse);
      },
    );

    test(
      'PGC-010 reliable partial live fanout marks sent while custody retry remains staged',
      () async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-2',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-2',
            joinedAt: DateTime.utc(2026, 5, 11, 8),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-3',
            username: 'Carol',
            role: MemberRole.writer,
            publicKey: 'pk-3',
            joinedAt: DateTime.utc(2026, 5, 11, 8, 1),
          ),
        );
        bridge.responses['group:sendReliable'] = {
          'ok': true,
          'messageId': 'pgc010-reliable-partial-live',
          'topicPeerCount': 1,
          'expectedRecipientCount': 2,
          'recipientPeerIds': ['peer-2', 'peer-3'],
          'inboxStored': false,
          'publishSucceeded': true,
          'deliveryMode': 'live_only',
        };

        late SendGroupMessageResult result;
        late GroupMessage? message;
        final events = await captureFlowEvents(() async {
          (result, message) = await sendGroupMessage(
            bridge: bridge,
            groupRepo: groupRepo,
            msgRepo: msgRepo,
            groupId: 'group-1',
            text: 'PGC-010 reliable partial live fanout',
            senderPeerId: 'peer-1',
            senderPublicKey: 'pk-1',
            senderPrivateKey: 'sk-1',
            senderUsername: 'Alice',
            messageId: 'pgc010-reliable-partial-live',
          );
        });

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'sent');
        expect(message!.inboxStored, isFalse);
        expect(message!.inboxRetryPayload, isNotNull);
        expect(message!.wireEnvelope, isNull);
        expect(
          _recipientPeerIdsFromRetryPayload(message!.inboxRetryPayload!),
          unorderedEquals(<String>['peer-2', 'peer-3']),
        );
        expect(bridge.commandLog, contains('group:sendReliable'));
        expect(bridge.commandLog, isNot(contains('group:publish')));
        expect(bridge.commandLog, isNot(contains('group:inboxStore')));

        final saved = await msgRepo.getMessage('pgc010-reliable-partial-live');
        expect(saved, isNotNull);
        expect(saved!.status, 'sent');
        expect(saved.inboxStored, isFalse);
        expect(saved.inboxRetryPayload, isNotNull);
        expect(saved.wireEnvelope, isNull);
        final inboxRetryRows = await msgRepo.getMessagesWithFailedInboxStore();
        expect(inboxRetryRows.map((row) => row.id), [
          'pgc010-reliable-partial-live',
        ]);

        final timing = events.lastWhere(
          (event) => event['event'] == 'GROUP_SEND_MSG_TIMING',
        );
        final details = timing['details'] as Map<String, dynamic>;
        expect(details['status'], 'sent');
        expect(details['topicPeers'], 1);
        expect(details['expectedRecipientCount'], 2);
        expect(details['liveFanoutState'], 'partial_peers');
        expect(details['recipientReceiptClaimed'], isFalse);
        expect(details['inboxStored'], isFalse);
        expect(details['inboxPending'], isFalse);
      },
    );

    test(
      'GIRD-001 reliable send timeout persists in-doubt non-failed outgoing row',
      () async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-2',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-2',
            joinedAt: DateTime.utc(2026, 5, 31, 11),
          ),
        );
        bridge.responses['group:sendReliable'] = {
          'ok': false,
          'errorCode': 'BRIDGE_TIMEOUT',
          'errorMessage': 'Timed out waiting for group:sendReliable response',
        };

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'GIRD-001 reliable timeout',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'gird001-reliable-timeout',
        );

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        expect(message!.id, 'gird001-reliable-timeout');
        expect(message.isIncoming, isFalse);
        expect(message.status, 'pending');
        expect(message.wireEnvelope, isNotNull);
        expect(message.inboxRetryPayload, isNotNull);
        expect(message.inboxStored, isFalse);

        final saved = await msgRepo.getMessage('gird001-reliable-timeout');
        expect(saved, isNotNull);
        expect(saved!.id, 'gird001-reliable-timeout');
        expect(saved.isIncoming, isFalse);
        expect(saved.status, 'pending');
        expect(saved.wireEnvelope, isNotNull);
        expect(saved.inboxRetryPayload, isNotNull);
        expect(saved.inboxStored, isFalse);

        final failedIds = (await msgRepo.getFailedOutgoingMessages())
            .map((row) => row.id)
            .toSet();
        expect(failedIds, isNot(contains('gird001-reliable-timeout')));
      },
    );

    test(
      // 210b: this shape IS the real offline-device geometry (gossipsub publish
      // "succeeds" locally with zero topic peers; relay custody fails). It must
      // surface as the distinct queuedOffline result + durable 'queued_offline'
      // row (clock, offline snackbar) — NOT the overloaded 'pending' in-doubt
      // tick — while keeping the repush payload armed and staying non-failed.
      'GIRD-001/210b reliable publish success with zero peers and no custody '
      'is queued_offline (durably queued, not failed)',
      () async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-2',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-2',
            joinedAt: DateTime.utc(2026, 5, 31, 11),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-3',
            username: 'Carol',
            role: MemberRole.writer,
            publicKey: 'pk-3',
            joinedAt: DateTime.utc(2026, 5, 31, 11, 1),
          ),
        );
        bridge.responses['group:sendReliable'] = {
          'ok': true,
          'messageId': 'gird001-reliable-zero-peers',
          'topicPeerCount': 0,
          'expectedRecipientCount': 2,
          'recipientPeerIds': ['peer-2', 'peer-3'],
          'inboxStored': false,
          'publishSucceeded': true,
          'deliveryMode': 'live_only',
        };

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'GIRD-001 reliable zero peers',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'gird001-reliable-zero-peers',
        );

        expect(result, SendGroupMessageResult.queuedOffline);
        expect(message, isNotNull);
        expect(message!.id, 'gird001-reliable-zero-peers');
        expect(message.isIncoming, isFalse);
        expect(message.status, 'queued_offline');
        expect(message.wireEnvelope, isNull);
        expect(message.inboxRetryPayload, isNotNull);
        expect(message.inboxStored, isFalse);

        final saved = await msgRepo.getMessage('gird001-reliable-zero-peers');
        expect(saved, isNotNull);
        expect(saved!.id, 'gird001-reliable-zero-peers');
        expect(saved.isIncoming, isFalse);
        expect(saved.status, 'queued_offline');
        expect(saved.wireEnvelope, isNull);
        expect(saved.inboxRetryPayload, isNotNull);
        expect(saved.inboxStored, isFalse);

        final failedIds = (await msgRepo.getFailedOutgoingMessages())
            .map((row) => row.id)
            .toSet();
        expect(failedIds, isNot(contains('gird001-reliable-zero-peers')));
      },
    );

    test(
      'GIRD-001 replay-envelope fallback uses native reliable envelope for pending inbox retry',
      () async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-2',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-2',
            joinedAt: DateTime.utc(2026, 5, 31, 11),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-3',
            username: 'Carol',
            role: MemberRole.writer,
            publicKey: 'pk-3',
            joinedAt: DateTime.utc(2026, 5, 31, 11, 1),
          ),
        );

        const messageId = 'gird001-native-envelope-retry';
        const protectedText = 'GIRD001 local replay plaintext secret';
        const senderPrivateKey = 'sk-gird001-native-fallback-secret';
        final nativeEnvelope = jsonEncode({
          'kind': 'group_offline_replay',
          'payloadType': 'group_message',
          'messageId': messageId,
          'ciphertext': 'native-reliable-ciphertext',
          'nonce': 'native-reliable-nonce',
        });
        bridge.responses['group.encrypt'] = {
          'ok': false,
          'errorCode': 'GROUP_ENCRYPT_FAILED',
          'errorMessage': 'local replay envelope failed',
        };
        bridge.responses['group:sendReliable'] = {
          'ok': true,
          'messageId': messageId,
          'topicPeerCount': 0,
          'expectedRecipientCount': 2,
          'recipientPeerIds': ['peer-2', 'peer-3'],
          'inboxStored': false,
          'publishSucceeded': true,
          'deliveryMode': 'live_only',
          'envelope': nativeEnvelope,
        };

        final (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: protectedText,
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: senderPrivateKey,
          senderUsername: 'Alice',
          messageId: messageId,
        );

        // 210b: this zero-peers/no-custody shape is now the queuedOffline lane
        // (the payload-composition substance of this test is unchanged — the
        // queued_offline row is still selected by the repush pass below).
        expect(result, SendGroupMessageResult.queuedOffline);
        expect(message, isNotNull);
        expect(message!.id, messageId);
        expect(message.status, 'queued_offline');
        expect(message.wireEnvelope, isNull);
        expect(message.inboxStored, isFalse);
        expect(message.inboxRetryPayload, isNotNull);

        final saved = await msgRepo.getMessage(messageId);
        expect(saved, isNotNull);
        expect(saved!.status, 'queued_offline');
        expect(saved.wireEnvelope, isNull);
        expect(saved.inboxStored, isFalse);
        expect(saved.inboxRetryPayload, isNotNull);

        final retryRaw = saved.inboxRetryPayload!;
        _expectNoProtectedFragments(retryRaw, [
          protectedText,
          senderPrivateKey,
        ]);
        final retryPayload = jsonDecode(retryRaw) as Map<String, dynamic>;
        expect(retryPayload.keys.toSet(), {
          'groupId',
          'message',
          'recipientPeerIds',
        });
        expect(retryPayload['groupId'], 'group-1');
        expect(retryPayload['message'], nativeEnvelope);
        expect(
          retryPayload['recipientPeerIds'],
          unorderedEquals(['peer-2', 'peer-3']),
        );

        final inboxRetryRows = await msgRepo.getMessagesWithFailedInboxStore();
        expect(inboxRetryRows.map((row) => row.id), [messageId]);
      },
    );

    test(
      'DE-007 zero-peer publish stores durable inbox for all active recipients',
      () async {
        final joinedAt = DateTime.utc(2026, 5, 12, 4);
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-2',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-2',
            joinedAt: joinedAt,
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-3',
            username: 'Charlie',
            role: MemberRole.writer,
            publicKey: 'pk-3',
            joinedAt: joinedAt.add(const Duration(seconds: 1)),
          ),
        );
        bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'de007-zero-peer-durable',
          'topicPeers': 0,
        };

        late SendGroupMessageResult result;
        late GroupMessage? message;
        final events = await captureFlowEvents(() async {
          (result, message) = await sendGroupMessage(
            bridge: bridge,
            groupRepo: groupRepo,
            msgRepo: msgRepo,
            groupId: 'group-1',
            text: 'DE-007 zero-peer durable fallback',
            senderPeerId: 'peer-1',
            senderPublicKey: 'pk-1',
            senderPrivateKey: 'sk-1',
            senderUsername: 'Alice',
            messageId: 'de007-zero-peer-durable',
            timestamp: joinedAt.add(const Duration(minutes: 1)),
          );
        });

        expect(result, SendGroupMessageResult.successNoPeers);
        expect(message, isNotNull);
        expect(message!.status, 'sent');
        expect(message!.wireEnvelope, isNull);
        expect(message!.inboxStored, isTrue);
        expect(message!.inboxRetryPayload, isNull);

        final saved = await msgRepo.getMessage('de007-zero-peer-durable');
        expect(saved, isNotNull);
        expect(saved!.status, 'sent');
        expect(saved.wireEnvelope, isNull);
        expect(saved.inboxStored, isTrue);
        expect(saved.inboxRetryPayload, isNull);

        final inboxPayload = _lastGroupInboxStorePayload(bridge);
        expect(
          inboxPayload['recipientPeerIds'],
          unorderedEquals(['peer-2', 'peer-3']),
        );
        final replay = _decodedGroupInboxReplayPayload(bridge);
        expect(replay['messageId'], 'de007-zero-peer-durable');
        expect(replay['senderId'], 'peer-1');

        final timing = events.lastWhere(
          (event) => event['event'] == 'GROUP_SEND_MSG_TIMING',
        );
        final details = timing['details'] as Map<String, dynamic>;
        expect(details['outcome'], 'success_no_peers');
        expect(details['status'], 'sent');
        expect(details['topicPeers'], 0);
        expect(details['expectedRecipientCount'], 2);
        expect(details['liveFanoutState'], 'zero_peers');
        expect(details['inboxStored'], isTrue);
        expect(details['inboxPending'], isFalse);
        expect(details['recipientReceiptClaimed'], isFalse);
      },
    );

    test(
      'NW-007 topic peer count zero keeps active member recipients and no receipt claims',
      () async {
        final joinedAt = DateTime.utc(2026, 5, 13, 11);
        const bobPeerId = 'peer-nw007-bob';
        const charliePeerId = 'peer-nw007-charlie';
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: bobPeerId,
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-nw007-bob',
            joinedAt: joinedAt.add(const Duration(minutes: 1)),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: charliePeerId,
            username: 'Charlie',
            role: MemberRole.writer,
            publicKey: 'pk-nw007-charlie',
            joinedAt: joinedAt.add(const Duration(minutes: 2)),
          ),
        );
        final membersBefore = (await groupRepo.getMembers(
          'group-1',
        )).map((member) => member.peerId).toSet();
        bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'nw007-zero-topic-peer-membership',
          'topicPeers': 0,
        };

        late SendGroupMessageResult result;
        late GroupMessage? message;
        final events = await captureFlowEvents(() async {
          (result, message) = await sendGroupMessage(
            bridge: bridge,
            groupRepo: groupRepo,
            msgRepo: msgRepo,
            groupId: 'group-1',
            text: 'NW-007 zero topic peers keep members active',
            senderPeerId: 'peer-1',
            senderPublicKey: 'pk-1',
            senderPrivateKey: 'sk-1',
            senderUsername: 'Alice',
            messageId: 'nw007-zero-topic-peer-membership',
            timestamp: joinedAt.add(const Duration(minutes: 3)),
          );
        });

        expect(result, SendGroupMessageResult.successNoPeers);
        expect(message, isNotNull);
        expect(message!.status, 'sent');
        expect(message!.inboxStored, isTrue);
        expect(message!.inboxRetryPayload, isNull);

        final inboxPayload = _lastGroupInboxStorePayload(bridge);
        final recipientPeerIds =
            (inboxPayload['recipientPeerIds'] as List<dynamic>).cast<String>();
        expect(recipientPeerIds, unorderedEquals([bobPeerId, charliePeerId]));
        expect(recipientPeerIds, isNot(contains('peer-1')));

        final replay = _decodedGroupInboxReplayPayload(bridge);
        expect(replay['messageId'], 'nw007-zero-topic-peer-membership');
        expect(replay['senderId'], 'peer-1');

        final timing = events.lastWhere(
          (event) => event['event'] == 'GROUP_SEND_MSG_TIMING',
        );
        final details = timing['details'] as Map<String, dynamic>;
        expect(details['outcome'], 'success_no_peers');
        expect(details['topicPeers'], 0);
        expect(details['expectedRecipientCount'], 2);
        expect(details['liveFanoutState'], 'zero_peers');
        expect(details['inboxStored'], isTrue);
        expect(details['inboxPending'], isFalse);
        expect(details['recipientReceiptClaimed'], isFalse);

        expect(
          await msgRepo.getReceiptsForMessage(
            'group-1',
            'nw007-zero-topic-peer-membership',
            receiptType: groupMessageReceiptTypeDelivered,
          ),
          isEmpty,
        );
        expect(
          await msgRepo.getReceiptsForMessage(
            'group-1',
            'nw007-zero-topic-peer-membership',
            receiptType: groupMessageReceiptTypeRead,
          ),
          isEmpty,
        );
        expect(
          (await groupRepo.getMembers(
            'group-1',
          )).map((member) => member.peerId).toSet(),
          membersBefore,
        );
      },
    );

    test(
      'NW-003 zero-peer removed-window durable send targets Bob but excludes Charlie during partitioned churn',
      () async {
        final joinedAt = DateTime.utc(2026, 5, 13, 8);
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-2',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-2',
            joinedAt: joinedAt,
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-3',
            username: 'Charlie',
            role: MemberRole.writer,
            publicKey: 'pk-3',
            joinedAt: joinedAt.add(const Duration(seconds: 1)),
          ),
        );
        await groupRepo.removeMember('group-1', 'peer-3');
        await _saveGroupKey(groupRepo, 'group-1', generation: 2);
        bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'nw003-removed-window',
          'topicPeers': 0,
        };

        late SendGroupMessageResult result;
        late GroupMessage? message;
        final events = await captureFlowEvents(() async {
          (result, message) = await sendGroupMessage(
            bridge: bridge,
            groupRepo: groupRepo,
            msgRepo: msgRepo,
            groupId: 'group-1',
            text: 'NW-003 removed-window durable fallback',
            senderPeerId: 'peer-1',
            senderPublicKey: 'pk-1',
            senderPrivateKey: 'sk-1',
            senderUsername: 'Alice',
            messageId: 'nw003-removed-window',
            timestamp: joinedAt.add(const Duration(minutes: 1)),
          );
        });

        expect(result, SendGroupMessageResult.successNoPeers);
        expect(message, isNotNull);
        expect(message!.status, 'sent');
        expect(message!.keyGeneration, 2);
        expect(message!.inboxStored, isTrue);
        expect(message!.inboxRetryPayload, isNull);

        final inboxPayload = _lastGroupInboxStorePayload(bridge);
        expect(inboxPayload['recipientPeerIds'], ['peer-2']);
        expect(inboxPayload['recipientPeerIds'], isNot(contains('peer-3')));
        expect(
          bridge.sentMessages.where((raw) => raw.contains('peer-3')),
          isEmpty,
          reason: 'Charlie must not appear in publish or inbox-store claims',
        );

        final replay = _decodedGroupInboxReplayPayload(bridge);
        expect(replay['messageId'], 'nw003-removed-window');
        expect(replay['senderId'], 'peer-1');

        expect(
          await msgRepo.getReceiptsForMessage(
            'group-1',
            'nw003-removed-window',
            receiptType: groupMessageReceiptTypeDelivered,
          ),
          isEmpty,
        );

        final timing = events.lastWhere(
          (event) => event['event'] == 'GROUP_SEND_MSG_TIMING',
        );
        final details = timing['details'] as Map<String, dynamic>;
        expect(details['outcome'], 'success_no_peers');
        expect(details['topicPeers'], 0);
        expect(details['expectedRecipientCount'], 1);
        expect(details['liveFanoutState'], 'zero_peers');
        expect(details['recipientReceiptClaimed'], isFalse);
        expect(details['inboxStored'], isTrue);
      },
    );

    test(
      'NW-012 long offline epoch churn sends only to recipients active in each interval',
      () async {
        final baseAt = DateTime.utc(2026, 5, 13, 9);
        const bobPeerId = 'peer-nw012-bob';
        const charliePeerId = 'peer-nw012-charlie';

        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: bobPeerId,
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-nw012-bob',
            joinedAt: baseAt,
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: charliePeerId,
            username: 'Charlie',
            role: MemberRole.writer,
            publicKey: 'pk-nw012-charlie',
            joinedAt: baseAt.add(const Duration(minutes: 1)),
          ),
        );
        bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'nw012-first-active',
          'topicPeers': 0,
        };

        Future<List<String>> sendAndRecipients({
          required String messageId,
          required String text,
          required DateTime timestamp,
        }) async {
          bridge.sentMessages.clear();
          bridge.commandLog.clear();
          bridge.responses['group:publish'] = {
            'ok': true,
            'messageId': messageId,
            'topicPeers': 0,
          };
          final (result, message) = await sendGroupMessage(
            bridge: bridge,
            groupRepo: groupRepo,
            msgRepo: msgRepo,
            groupId: 'group-1',
            text: text,
            senderPeerId: 'peer-1',
            senderPublicKey: 'pk-1',
            senderPrivateKey: 'sk-1',
            senderUsername: 'Alice',
            messageId: messageId,
            timestamp: timestamp,
          );
          expect(result, SendGroupMessageResult.successNoPeers);
          expect(message, isNotNull);
          expect(message!.inboxStored, isTrue);
          final inboxPayload = _lastGroupInboxStorePayload(bridge);
          return (inboxPayload['recipientPeerIds'] as List<dynamic>)
              .cast<String>();
        }

        final firstRecipients = await sendAndRecipients(
          messageId: 'nw012-first-active',
          text: 'NW-012 first active interval',
          timestamp: baseAt.add(const Duration(minutes: 2)),
        );
        expect(firstRecipients, unorderedEquals([bobPeerId, charliePeerId]));
        expect(firstRecipients.toSet(), hasLength(firstRecipients.length));

        await groupRepo.removeMember('group-1', charliePeerId);
        await _saveGroupKey(groupRepo, 'group-1', generation: 2);
        final removedRecipients = await sendAndRecipients(
          messageId: 'nw012-removed-window',
          text: 'NW-012 removed interval',
          timestamp: baseAt.add(const Duration(minutes: 20)),
        );
        expect(removedRecipients, [bobPeerId]);
        expect(removedRecipients, isNot(contains(charliePeerId)));

        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: charliePeerId,
            username: 'Charlie re-added',
            role: MemberRole.writer,
            publicKey: 'pk-nw012-charlie-readd',
            joinedAt: baseAt.add(const Duration(minutes: 40)),
          ),
        );
        await _saveGroupKey(groupRepo, 'group-1', generation: 4);
        final finalRecipients = await sendAndRecipients(
          messageId: 'nw012-final-active',
          text: 'NW-012 final active interval',
          timestamp: baseAt.add(const Duration(minutes: 42)),
        );
        expect(finalRecipients, unorderedEquals([bobPeerId, charliePeerId]));
        expect(finalRecipients.toSet(), hasLength(finalRecipients.length));
      },
    );

    test(
      'NW-006 disconnected active member remains a durable recipient without delivery receipt claims',
      () async {
        final joinedAt = DateTime.utc(2026, 5, 13, 10);
        const disconnectedPeerId = 'peer-bob-disconnected';
        const onlinePeerId = 'peer-charlie-online';
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: disconnectedPeerId,
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-bob',
            joinedAt: joinedAt.add(const Duration(minutes: 1)),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: onlinePeerId,
            username: 'Charlie',
            role: MemberRole.writer,
            publicKey: 'pk-charlie',
            joinedAt: joinedAt.add(const Duration(minutes: 2)),
          ),
        );
        bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'nw006-disconnect-not-removal',
          'topicPeers': 1,
        };

        late SendGroupMessageResult result;
        late GroupMessage? sent;
        final events = await captureFlowEvents(() async {
          final sendResult = await sendGroupMessage(
            bridge: bridge,
            groupRepo: groupRepo,
            msgRepo: msgRepo,
            groupId: 'group-1',
            text: 'NW-006 Bob is disconnected but still active',
            senderPeerId: 'peer-1',
            senderPublicKey: 'pk-1',
            senderPrivateKey: 'sk-1',
            senderUsername: 'Alice',
            messageId: 'nw006-disconnect-not-removal',
            timestamp: joinedAt.add(const Duration(minutes: 3)),
          );
          result = sendResult.$1;
          sent = sendResult.$2;
        });

        expect(result, SendGroupMessageResult.success);
        expect(sent, isNotNull);
        expect(sent!.status, 'sent');
        expect(sent!.inboxStored, isTrue);

        final inboxPayload = _lastGroupInboxStorePayload(bridge);
        final recipientPeerIds =
            (inboxPayload['recipientPeerIds'] as List<dynamic>).cast<String>();
        expect(recipientPeerIds, contains(disconnectedPeerId));
        expect(recipientPeerIds, contains(onlinePeerId));
        expect(recipientPeerIds, isNot(contains('peer-1')));

        final replay = _decodedGroupInboxReplayPayload(bridge);
        expect(replay['messageId'], 'nw006-disconnect-not-removal');
        expect(replay['senderId'], 'peer-1');

        final successEvent = events.lastWhere(
          (event) => event['event'] == 'GROUP_SEND_MSG_USE_CASE_SUCCESS',
        );
        final details = successEvent['details'] as Map<String, dynamic>;
        expect(details['topicPeers'], 1);
        expect(details['expectedRecipientCount'], 2);
        expect(details['liveFanoutState'], 'partial_peers');
        expect(details['recipientReceiptClaimed'], isFalse);

        expect(
          await msgRepo.getReceiptsForMessage(
            'group-1',
            'nw006-disconnect-not-removal',
            receiptType: groupMessageReceiptTypeDelivered,
          ),
          isEmpty,
        );
        expect(
          await msgRepo.getReceiptsForMessage(
            'group-1',
            'nw006-disconnect-not-removal',
            receiptType: groupMessageReceiptTypeRead,
          ),
          isEmpty,
        );
        expect(
          (await groupRepo.getMembers(
            'group-1',
          )).map((member) => member.peerId),
          containsAll(<String>['peer-1', disconnectedPeerId, onlinePeerId]),
        );
      },
    );

    test(
      'NW-009 relay probe failure keeps active members as durable recipients',
      () async {
        final joinedAt = DateTime.utc(2026, 5, 13, 12);
        const probedPeerId = 'peer-nw009-bob';
        const onlinePeerId = 'peer-nw009-charlie';

        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: probedPeerId,
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-nw009-bob',
            joinedAt: joinedAt.add(const Duration(minutes: 1)),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: onlinePeerId,
            username: 'Charlie',
            role: MemberRole.writer,
            publicKey: 'pk-nw009-charlie',
            joinedAt: joinedAt.add(const Duration(minutes: 2)),
          ),
        );
        final membersBefore = (await groupRepo.getMembers(
          'group-1',
        )).map((member) => member.peerId).toSet();

        bridge.responses['relay:probe'] = {
          'ok': false,
          'errorCode': 'NO_RESERVATION',
          'errorMessage': 'simulated relay probe failure',
        };
        final probeResult = await callP2PRelayProbe(
          bridge,
          peerId: probedPeerId,
        );
        expect(probeResult['ok'], isFalse);
        expect(probeResult['errorCode'], 'NO_RESERVATION');

        bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'nw009-relay-probe-failure',
          'topicPeers': 1,
        };

        late SendGroupMessageResult result;
        late GroupMessage? message;
        final events = await captureFlowEvents(() async {
          (result, message) = await sendGroupMessage(
            bridge: bridge,
            groupRepo: groupRepo,
            msgRepo: msgRepo,
            groupId: 'group-1',
            text: 'NW-009 relay probe failure keeps Bob active',
            senderPeerId: 'peer-1',
            senderPublicKey: 'pk-1',
            senderPrivateKey: 'sk-1',
            senderUsername: 'Alice',
            messageId: 'nw009-relay-probe-failure',
            timestamp: joinedAt.add(const Duration(minutes: 3)),
          );
        });

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'sent');
        expect(message!.inboxStored, isTrue);

        final inboxPayload = _lastGroupInboxStorePayload(bridge);
        final recipientPeerIds =
            (inboxPayload['recipientPeerIds'] as List<dynamic>).cast<String>();
        expect(recipientPeerIds, unorderedEquals([probedPeerId, onlinePeerId]));
        expect(recipientPeerIds, isNot(contains('peer-1')));

        final replay = _decodedGroupInboxReplayPayload(bridge);
        expect(replay['messageId'], 'nw009-relay-probe-failure');
        expect(replay['senderId'], 'peer-1');

        final timing = events.lastWhere(
          (event) => event['event'] == 'GROUP_SEND_MSG_TIMING',
        );
        final details = timing['details'] as Map<String, dynamic>;
        expect(details['outcome'], 'success');
        expect(details['topicPeers'], 1);
        expect(details['expectedRecipientCount'], 2);
        expect(details['liveFanoutState'], 'partial_peers');
        expect(details['recipientReceiptClaimed'], isFalse);

        expect(
          await msgRepo.getReceiptsForMessage(
            'group-1',
            'nw009-relay-probe-failure',
            receiptType: groupMessageReceiptTypeDelivered,
          ),
          isEmpty,
        );
        expect(
          (await groupRepo.getMembers(
            'group-1',
          )).map((member) => member.peerId).toSet(),
          membersBefore,
        );
      },
    );

    test('GP-005 zero topic peers records durable fallback custody', () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-2',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-2',
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      bridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'gp005-zero-peers',
        'topicPeers': 0,
      };

      late SendGroupMessageResult result;
      late GroupMessage? message;
      final events = await captureFlowEvents(() async {
        (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'GP-005 zero peers still durable',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'gp005-zero-peers',
        );
      });

      expect(result, SendGroupMessageResult.successNoPeers);
      expect(message, isNotNull);
      final sentMessage = message!;
      expect(sentMessage.status, 'sent');
      expect(sentMessage.inboxStored, isTrue);
      expect(sentMessage.inboxRetryPayload, isNull);
      expect(sentMessage.wireEnvelope, isNull);
      expect(bridge.commandLog, contains('group:publish'));
      expect(bridge.commandLog, contains('group:inboxStore'));

      final saved = await msgRepo.getMessage('gp005-zero-peers');
      expect(saved, isNotNull);
      expect(saved!.status, 'sent');
      expect(saved.inboxStored, isTrue);
      expect(saved.inboxRetryPayload, isNull);

      final inboxPayload = _groupInboxStorePayloadForMessage(
        bridge,
        'gp005-zero-peers',
      );
      expect(inboxPayload['groupId'], 'group-1');
      expect(inboxPayload['recipientPeerIds'], ['peer-2']);

      final noPeersEvent = events.firstWhere(
        (event) => event['event'] == 'GROUP_SEND_MSG_USE_CASE_SUCCESS_NO_PEERS',
      );
      expect(noPeersEvent['details']['messageId'], 'gp005-ze');

      final timing = events.lastWhere(
        (event) => event['event'] == 'GROUP_SEND_MSG_TIMING',
      );
      expect(timing['details']['outcome'], 'success_no_peers');
      expect(timing['details']['status'], 'sent');
      expect(timing['details']['topicPeers'], 0);
      expect(timing['details']['groupId'], 'group-1');
    });

    test(
      'GP-007 zero topic peers complete without retry staging and use inbox',
      () async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-2',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-2',
            joinedAt: DateTime.now().toUtc(),
          ),
        );
        bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'gp007-zero-peer-bounded',
          'topicPeers': 0,
        };

        late SendGroupMessageResult result;
        late GroupMessage? message;
        final stopwatch = Stopwatch()..start();
        final events = await captureFlowEvents(() async {
          (result, message) = await sendGroupMessage(
            bridge: bridge,
            groupRepo: groupRepo,
            msgRepo: msgRepo,
            groupId: 'group-1',
            text: 'GP-007 zero peers should not hang',
            senderPeerId: 'peer-1',
            senderPublicKey: 'pk-1',
            senderPrivateKey: 'sk-1',
            senderUsername: 'Alice',
            messageId: 'gp007-zero-peer-bounded',
          );
        });
        stopwatch.stop();

        expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
        expect(result, SendGroupMessageResult.successNoPeers);
        expect(message, isNotNull);
        final sentMessage = message!;
        expect(sentMessage.status, 'sent');
        expect(sentMessage.inboxStored, isTrue);
        expect(sentMessage.inboxRetryPayload, isNull);
        expect(sentMessage.wireEnvelope, isNull);
        expect(bridge.commandLog, contains('group:publish'));
        expect(bridge.commandLog, contains('group:inboxStore'));

        final saved = await msgRepo.getMessage('gp007-zero-peer-bounded');
        expect(saved, isNotNull);
        expect(saved!.status, 'sent');
        expect(saved.inboxStored, isTrue);
        expect(saved.inboxRetryPayload, isNull);

        final inboxPayload = _groupInboxStorePayloadForMessage(
          bridge,
          'gp007-zero-peer-bounded',
        );
        expect(inboxPayload['groupId'], 'group-1');
        expect(inboxPayload['recipientPeerIds'], ['peer-2']);

        final noPeersEvent = events.firstWhere(
          (event) =>
              event['event'] == 'GROUP_SEND_MSG_USE_CASE_SUCCESS_NO_PEERS',
        );
        expect(noPeersEvent['details']['messageId'], 'gp007-ze');
        expect(noPeersEvent['details']['topicPeers'], 0);
        expect(noPeersEvent['details']['inboxStored'], isTrue);
        expect(noPeersEvent['details']['inboxPending'], isFalse);

        final timing = events.lastWhere(
          (event) => event['event'] == 'GROUP_SEND_MSG_TIMING',
        );
        expect(timing['details']['outcome'], 'success_no_peers');
        expect(timing['details']['status'], 'sent');
        expect(timing['details']['topicPeers'], 0);
        expect(timing['details']['inboxStored'], isTrue);
        expect(timing['details']['inboxPending'], isFalse);
        expect(timing['details']['elapsedMs'], lessThan(1000));
      },
    );

    test(
      'GO-001 zero topic peers exposes durable fallback sender status',
      () async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-2',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-2',
            joinedAt: DateTime.now().toUtc(),
          ),
        );
        bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'go001-zero-peers',
          'topicPeers': 0,
        };

        late SendGroupMessageResult result;
        late GroupMessage? message;
        final events = await captureFlowEvents(() async {
          (result, message) = await sendGroupMessage(
            bridge: bridge,
            groupRepo: groupRepo,
            msgRepo: msgRepo,
            groupId: 'group-1',
            text: 'GO-001 zero live peers',
            senderPeerId: 'peer-1',
            senderPublicKey: 'pk-1',
            senderPrivateKey: 'sk-1',
            senderUsername: 'Alice',
            messageId: 'go001-zero-peers',
          );
        });

        expect(result, SendGroupMessageResult.successNoPeers);
        expect(message, isNotNull);
        expect(message!.status, 'sent');
        expect(message!.inboxStored, isTrue);
        expect(message!.inboxRetryPayload, isNull);

        final saved = await msgRepo.getMessage('go001-zero-peers');
        expect(saved, isNotNull);
        expect(saved!.status, 'sent');
        expect(saved.inboxStored, isTrue);
        expect(saved.inboxRetryPayload, isNull);

        final inboxPayload = _groupInboxStorePayloadForMessage(
          bridge,
          'go001-zero-peers',
        );
        expect(inboxPayload['recipientPeerIds'], ['peer-2']);

        final noPeersEvent = events.firstWhere(
          (event) =>
              event['event'] == 'GROUP_SEND_MSG_USE_CASE_SUCCESS_NO_PEERS',
        );
        expect(noPeersEvent['details']['messageId'], 'go001-ze');
        expect(noPeersEvent['details']['status'], 'sent');
        expect(noPeersEvent['details']['topicPeers'], 0);
        expect(noPeersEvent['details']['inboxStored'], isTrue);
        expect(noPeersEvent['details']['inboxPending'], isFalse);

        final timing = events.lastWhere(
          (event) => event['event'] == 'GROUP_SEND_MSG_TIMING',
        );
        expect(timing['details']['outcome'], 'success_no_peers');
        expect(timing['details']['status'], 'sent');
        expect(timing['details']['topicPeers'], 0);
        expect(timing['details']['inboxStored'], isTrue);
        expect(timing['details']['inboxPending'], isFalse);
        expect(timing['details']['groupId'], 'group-1');
      },
    );

    test('GP-015 zero live topic peers keep durable fallback', () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-2',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-2',
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      bridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'gp015-host-connected-not-topic',
        'topicPeers': 0,
      };

      late SendGroupMessageResult result;
      late GroupMessage? message;
      final events = await captureFlowEvents(() async {
        (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'GP-015 host connected not topic peer',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'gp015-host-connected-not-topic',
        );
      });

      expect(result, SendGroupMessageResult.successNoPeers);
      expect(message, isNotNull);
      final sentMessage = message!;
      expect(sentMessage.status, 'sent');
      expect(sentMessage.inboxStored, isTrue);
      expect(sentMessage.inboxRetryPayload, isNull);
      expect(sentMessage.wireEnvelope, isNull);
      expect(bridge.commandLog, contains('group:publish'));
      expect(bridge.commandLog, contains('group:inboxStore'));

      final saved = await msgRepo.getMessage('gp015-host-connected-not-topic');
      expect(saved, isNotNull);
      expect(saved!.status, 'sent');
      expect(saved.inboxStored, isTrue);
      expect(saved.inboxRetryPayload, isNull);

      final inboxPayload = _groupInboxStorePayloadForMessage(
        bridge,
        'gp015-host-connected-not-topic',
      );
      expect(inboxPayload['groupId'], 'group-1');
      expect(inboxPayload['recipientPeerIds'], ['peer-2']);

      final noPeersEvent = events.firstWhere(
        (event) => event['event'] == 'GROUP_SEND_MSG_USE_CASE_SUCCESS_NO_PEERS',
      );
      expect(noPeersEvent['details']['messageId'], 'gp015-ho');

      final timing = events.lastWhere(
        (event) => event['event'] == 'GROUP_SEND_MSG_TIMING',
      );
      expect(timing['details']['outcome'], 'success_no_peers');
      expect(timing['details']['status'], 'sent');
      expect(timing['details']['topicPeers'], 0);
      expect(timing['details']['groupId'], 'group-1');
    });

    test('GP-006 partial peers keep durable fallback for recipients', () async {
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-2',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-2',
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: 'group-1',
          peerId: 'peer-3',
          username: 'Carol',
          role: MemberRole.writer,
          publicKey: 'pk-3',
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      bridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'gp006-partial-peers',
        'topicPeers': 1,
      };

      late SendGroupMessageResult result;
      late GroupMessage? message;
      final events = await captureFlowEvents(() async {
        (result, message) = await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'GP-006 partial peers',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'gp006-partial-peers',
        );
      });

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      final sentMessage = message!;
      expect(sentMessage.status, 'sent');
      expect(sentMessage.inboxStored, isTrue);
      expect(sentMessage.inboxRetryPayload, isNull);
      expect(sentMessage.wireEnvelope, isNull);
      expect(bridge.commandLog, contains('group:publish'));
      expect(bridge.commandLog, contains('group:inboxStore'));

      final saved = await msgRepo.getMessage('gp006-partial-peers');
      expect(saved, isNotNull);
      expect(saved!.status, 'sent');
      expect(saved.inboxStored, isTrue);
      expect(saved.inboxRetryPayload, isNull);

      final inboxPayload = _groupInboxStorePayloadForMessage(
        bridge,
        'gp006-partial-peers',
      );
      expect(inboxPayload['groupId'], 'group-1');
      expect(
        inboxPayload['recipientPeerIds'],
        unorderedEquals(['peer-2', 'peer-3']),
      );

      final successEvent = events.firstWhere(
        (event) => event['event'] == 'GROUP_SEND_MSG_USE_CASE_SUCCESS',
      );
      expect(successEvent['details']['topicPeers'], 1);
      expect(successEvent['details']['inboxOk'], isTrue);

      final timing = events.lastWhere(
        (event) => event['event'] == 'GROUP_SEND_MSG_TIMING',
      );
      expect(timing['details']['outcome'], 'success');
      expect(timing['details']['status'], 'sent');
      expect(timing['details']['topicPeers'], 1);
      expect(timing['details']['inboxStored'], isTrue);
      expect(timing['details']['groupId'], 'group-1');
    });

    test(
      'GP-008 latest membership drives durable fallback after remove add',
      () async {
        final joinedAt = DateTime.utc(2026, 5, 12, 8);
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-2',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-2',
            joinedAt: joinedAt.add(const Duration(seconds: 1)),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-3',
            username: 'Charlie',
            role: MemberRole.writer,
            publicKey: 'pk-3',
            joinedAt: joinedAt.add(const Duration(seconds: 2)),
          ),
        );

        await groupRepo.removeMember('group-1', 'peer-3');
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-4',
            username: 'Dana',
            role: MemberRole.writer,
            publicKey: 'pk-4',
            joinedAt: joinedAt.add(const Duration(seconds: 3)),
          ),
        );
        bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'gp008-latest-config',
          'topicPeers': 1,
        };

        late SendGroupMessageResult result;
        late GroupMessage? message;
        final events = await captureFlowEvents(() async {
          (result, message) = await sendGroupMessage(
            bridge: bridge,
            groupRepo: groupRepo,
            msgRepo: msgRepo,
            groupId: 'group-1',
            text: 'GP-008 latest config recipients',
            senderPeerId: 'peer-1',
            senderPublicKey: 'pk-1',
            senderPrivateKey: 'sk-1',
            senderUsername: 'Alice',
            messageId: 'gp008-latest-config',
            timestamp: joinedAt.add(const Duration(minutes: 1)),
          );
        });

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        final sentMessage = message!;
        expect(sentMessage.status, 'sent');
        expect(sentMessage.inboxStored, isTrue);
        expect(sentMessage.inboxRetryPayload, isNull);
        expect(sentMessage.wireEnvelope, isNull);
        expect(bridge.commandLog, contains('group:publish'));
        expect(bridge.commandLog, contains('group:inboxStore'));

        final saved = await msgRepo.getMessage('gp008-latest-config');
        expect(saved, isNotNull);
        expect(saved!.status, 'sent');
        expect(saved.inboxStored, isTrue);
        expect(saved.inboxRetryPayload, isNull);

        final inboxPayload = _groupInboxStorePayloadForMessage(
          bridge,
          'gp008-latest-config',
        );
        expect(inboxPayload['groupId'], 'group-1');
        expect(
          inboxPayload['recipientPeerIds'],
          unorderedEquals(<String>['peer-2', 'peer-4']),
        );
        expect(inboxPayload['recipientPeerIds'], isNot(contains('peer-3')));

        final successEvent = events.firstWhere(
          (event) => event['event'] == 'GROUP_SEND_MSG_USE_CASE_SUCCESS',
        );
        expect(successEvent['details']['topicPeers'], 1);
        expect(successEvent['details']['inboxOk'], isTrue);

        final timing = events.lastWhere(
          (event) => event['event'] == 'GROUP_SEND_MSG_TIMING',
        );
        expect(timing['details']['outcome'], 'success');
        expect(timing['details']['status'], 'sent');
        expect(timing['details']['topicPeers'], 1);
        expect(timing['details']['inboxStored'], isTrue);
        expect(timing['details']['groupId'], 'group-1');
      },
    );

    test('0-peer + inbox OK → successNoPeers, status sent', () async {
      bridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'msg-zero-peers',
        'topicPeers': 0,
      };

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'No peers online',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'msg-zero-peers',
      );

      expect(result, SendGroupMessageResult.successNoPeers);
      expect(message, isNotNull);
      expect(message!.status, 'sent');

      final saved = await msgRepo.getMessage('msg-zero-peers');
      expect(saved, isNotNull);
      expect(saved!.status, 'sent');
      expect(saved.inboxStored, isTrue);
    });

    test('0-peer + inbox fail → error', () async {
      final failBridge = _InboxStoreFailBridge();
      failBridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'msg-zero-fail',
        'topicPeers': 0,
      };

      late SendGroupMessageResult result;
      late GroupMessage? message;
      final events = await captureFlowEvents(() async {
        (result, message) = await sendGroupMessage(
          bridge: failBridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Zero peers, inbox fail',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'msg-zero-fail',
        );
      });

      expect(result, SendGroupMessageResult.error);
      expect(message, isNotNull);
      // The pre-persisted row should exist with 'failed' status
      final saved = await msgRepo.getMessage('msg-zero-fail');
      expect(saved, isNotNull);
      expect(saved!.status, 'failed');

      final inboxStoreFailed = events.firstWhere(
        (event) => event['event'] == 'GROUP_SEND_MSG_INBOX_STORE_FAILED',
      );
      expect(
        inboxStoreFailed['details']['error'],
        contains('Relay inbox store failed'),
      );

      final zeroPeersFailed = events.firstWhere(
        (event) =>
            event['event'] == 'GROUP_SEND_MSG_USE_CASE_ZERO_PEERS_INBOX_FAILED',
      );
      expect(zeroPeersFailed['details']['messageId'], 'msg-zero');

      final timing = events.lastWhere(
        (event) => event['event'] == 'GROUP_SEND_MSG_TIMING',
      );
      expect(timing['details']['outcome'], 'zero_peers_inbox_failed');
      expect(timing['details']['topicPeers'], 0);
      expect(timing['details']['groupId'], 'group-1');
    });

    test(
      'OB-003 zero-peer publish explains durable fallback choices',
      () async {
        final joinedAt = DateTime.now().toUtc();
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-ob003-bob',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-ob003-bob',
            joinedAt: joinedAt,
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-ob003-charlie',
            username: 'Charlie',
            role: MemberRole.writer,
            publicKey: 'pk-ob003-charlie',
            joinedAt: joinedAt.add(const Duration(seconds: 1)),
          ),
        );

        bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'ob003-zero-peer-durable',
          'topicPeers': 0,
        };

        late SendGroupMessageResult durableResult;
        late GroupMessage? durableMessage;
        final durableEvents = await captureFlowEvents(() async {
          (durableResult, durableMessage) = await sendGroupMessage(
            bridge: bridge,
            groupRepo: groupRepo,
            msgRepo: msgRepo,
            groupId: 'group-1',
            text: 'OB-003 zero peers durable fallback',
            senderPeerId: 'peer-1',
            senderPublicKey: 'pk-1',
            senderPrivateKey: 'sk-1',
            senderUsername: 'Alice',
            messageId: 'ob003-zero-peer-durable',
            timestamp: joinedAt.add(const Duration(minutes: 1)),
          );
        });

        expect(durableResult, SendGroupMessageResult.successNoPeers);
        expect(durableMessage, isNotNull);
        expect(durableMessage!.status, 'sent');
        final durableEvent = durableEvents.singleWhere(
          (event) =>
              event['event'] == 'GROUP_SEND_MSG_USE_CASE_SUCCESS_NO_PEERS',
        );
        final durableDetails = durableEvent['details'] as Map<String, dynamic>;
        expect(durableDetails['topicPeers'], 0);
        expect(durableDetails['expectedRecipientCount'], 2);
        expect(durableDetails['liveFanoutState'], 'zero_peers');
        expect(durableDetails['inboxStored'], isTrue);
        expect(durableDetails['inboxPending'], isFalse);
        expect(durableDetails['recipientReceiptClaimed'], isFalse);

        final durableTiming = durableEvents.lastWhere(
          (event) => event['event'] == 'GROUP_SEND_MSG_TIMING',
        );
        final durableTimingDetails =
            durableTiming['details'] as Map<String, dynamic>;
        expect(durableTimingDetails['outcome'], 'success_no_peers');
        expect(durableTimingDetails['status'], 'sent');
        expect(durableTimingDetails['liveFanoutState'], 'zero_peers');

        final failBridge = _InboxStoreFailBridge();
        failBridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'ob003-zero-peer-inbox-failed',
          'topicPeers': 0,
        };

        late SendGroupMessageResult failedResult;
        late GroupMessage? failedMessage;
        final failedEvents = await captureFlowEvents(() async {
          (failedResult, failedMessage) = await sendGroupMessage(
            bridge: failBridge,
            groupRepo: groupRepo,
            msgRepo: msgRepo,
            groupId: 'group-1',
            text: 'OB-003 zero peers inbox failed',
            senderPeerId: 'peer-1',
            senderPublicKey: 'pk-1',
            senderPrivateKey: 'sk-1',
            senderUsername: 'Alice',
            messageId: 'ob003-zero-peer-inbox-failed',
            timestamp: joinedAt.add(const Duration(minutes: 2)),
          );
        });

        expect(failedResult, SendGroupMessageResult.error);
        expect(failedMessage, isNotNull);
        expect(failedMessage!.status, 'failed');
        expect(
          failedEvents.any(
            (event) => event['event'] == 'GROUP_SEND_MSG_INBOX_STORE_FAILED',
          ),
          isTrue,
        );
        final failedEvent = failedEvents.singleWhere(
          (event) =>
              event['event'] ==
              'GROUP_SEND_MSG_USE_CASE_ZERO_PEERS_INBOX_FAILED',
        );
        final failedDetails = failedEvent['details'] as Map<String, dynamic>;
        expect(failedDetails['topicPeers'], 0);
        expect(failedDetails['expectedRecipientCount'], 2);
        expect(failedDetails['liveFanoutState'], 'zero_peers');
        expect(failedDetails['inboxStored'], isFalse);
        expect(failedDetails['inboxPending'], isFalse);
        expect(failedDetails['recipientReceiptClaimed'], isFalse);

        final failedTiming = failedEvents.lastWhere(
          (event) => event['event'] == 'GROUP_SEND_MSG_TIMING',
        );
        final failedTimingDetails =
            failedTiming['details'] as Map<String, dynamic>;
        expect(failedTimingDetails['outcome'], 'zero_peers_inbox_failed');
        expect(failedTimingDetails['liveFanoutState'], 'zero_peers');
      },
    );

    test('peers > 0 + inbox OK → success, both payloads cleared', () async {
      bridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'msg-peers-ok',
        'topicPeers': 3,
      };

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Normal send',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'msg-peers-ok',
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      expect(message!.status, 'sent');
      expect(message.inboxStored, isTrue);

      final saved = await msgRepo.getMessage('msg-peers-ok');
      expect(saved, isNotNull);
      expect(saved!.wireEnvelope, isNull);
      expect(saved.inboxRetryPayload, isNull);
    });

    test(
      'peers > 0 + inbox fail -> success with sent status, wireEnvelope cleared, inboxRetryPayload kept',
      () async {
        final failBridge = _InboxStoreFailBridge();
        failBridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'msg-peers-inbox-fail',
          'topicPeers': 3,
        };

        final (result, message) = await sendGroupMessage(
          bridge: failBridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Inbox fails but peers OK',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'msg-peers-inbox-fail',
        );

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'sent');
        expect(message.inboxStored, isFalse);
        expect(message.inboxRetryPayload, isNotNull);

        final saved = await msgRepo.getMessage('msg-peers-inbox-fail');
        expect(saved, isNotNull);
        expect(saved!.status, 'sent');
        expect(saved.wireEnvelope, isNull);
        expect(saved.inboxRetryPayload, isNotNull);
      },
    );

    test(
      'IR-007 publish success plus inbox failure is sent and inbox retry closes same id',
      () async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-2',
            username: 'Bob',
            role: MemberRole.writer,
            joinedAt: DateTime.utc(2026, 5, 13, 0, 2),
          ),
        );
        final retryBridge = _FailFirstNInboxStoreBridge(failCount: 1);
        retryBridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'ir007-pending-inbox-retry',
          'topicPeers': 1,
        };

        final (result, message) = await sendGroupMessage(
          bridge: retryBridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'IR-007 pending inbox retry',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'ir007-pending-inbox-retry',
        );

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        expect(message!.id, 'ir007-pending-inbox-retry');
        expect(message.status, 'sent');
        expect(message.wireEnvelope, isNull);
        expect(message.inboxStored, isFalse);
        expect(message.inboxRetryPayload, isNotNull);

        final saved = await msgRepo.getMessage('ir007-pending-inbox-retry');
        expect(saved, isNotNull);
        expect(saved!.status, 'sent');
        expect(saved.wireEnvelope, isNull);
        expect(saved.inboxStored, isFalse);
        expect(saved.inboxRetryPayload, isNotNull);
        final persistedRetryEnvelope = _offlineReplayEnvelopeFromRetryPayload(
          saved.inboxRetryPayload!,
        );
        expect(
          persistedRetryEnvelope['messageId'],
          'ir007-pending-inbox-retry',
        );

        final inboxRetryRows = await msgRepo.getMessagesWithFailedInboxStore();
        expect(inboxRetryRows.map((row) => row.id), [
          'ir007-pending-inbox-retry',
        ]);

        final retried = await retryFailedGroupInboxStores(
          bridge: retryBridge,
          msgRepo: msgRepo,
        );

        expect(retried, 1);
        final recovered = await msgRepo.getMessage('ir007-pending-inbox-retry');
        expect(recovered, isNotNull);
        expect(recovered!.id, 'ir007-pending-inbox-retry');
        expect(recovered.status, 'sent');
        expect(recovered.inboxStored, isTrue);
        expect(recovered.inboxRetryPayload, isNull);
        expect(_groupInboxStoreReplayMessageIds(retryBridge), [
          'ir007-pending-inbox-retry',
          'ir007-pending-inbox-retry',
        ]);
        expect(
          retryBridge.commandLog.where((cmd) => cmd == 'group:publish'),
          hasLength(1),
        );
        expect(
          retryBridge.commandLog.where((cmd) => cmd == 'group:inboxStore'),
          hasLength(2),
        );

        final page = await msgRepo.getMessagesPage('group-1');
        expect(
          page.where(
            (row) =>
                !row.isIncoming && row.text == 'IR-007 pending inbox retry',
          ),
          hasLength(1),
        );
      },
    );

    test(
      'IR-007 publish failure plus inbox failure is failed and owned by message retry',
      () async {
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-2',
            username: 'Bob',
            role: MemberRole.writer,
            joinedAt: DateTime.utc(2026, 5, 13, 0, 3),
          ),
        );
        final failBridge = _InboxStoreFailBridge();
        failBridge.responses['group:publish'] = {
          'ok': false,
          'errorCode': 'PUBLISH_FAILED',
        };

        final (result, message) = await sendGroupMessage(
          bridge: failBridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'IR-007 failed message retry',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'ir007-failed-message-retry',
        );

        expect(result, SendGroupMessageResult.error);
        expect(message, isNotNull);
        expect(message!.id, 'ir007-failed-message-retry');
        expect(message.status, 'failed');
        expect(message.wireEnvelope, isNotNull);
        expect(message.inboxStored, isFalse);
        expect(message.inboxRetryPayload, isNotNull);

        final saved = await msgRepo.getMessage('ir007-failed-message-retry');
        expect(saved, isNotNull);
        expect(saved!.status, 'failed');
        expect(saved.wireEnvelope, isNotNull);
        expect(saved.inboxStored, isFalse);
        expect(saved.inboxRetryPayload, isNotNull);
        final inboxOnlyRows = await msgRepo.getMessagesWithFailedInboxStore();
        expect(
          inboxOnlyRows.map((row) => row.id),
          isNot(contains('ir007-failed-message-retry')),
        );
        final failedRows = await msgRepo.getFailedOutgoingMessages();
        expect(failedRows.map((row) => row.id), ['ir007-failed-message-retry']);
        expect(
          failBridge.commandLog.where((cmd) => cmd == 'group:publish'),
          hasLength(1),
        );
        expect(
          failBridge.commandLog.where((cmd) => cmd == 'group:inboxStore'),
          hasLength(1),
        );

        final page = await msgRepo.getMessagesPage('group-1');
        expect(
          page.where(
            (row) =>
                !row.isIncoming && row.text == 'IR-007 failed message retry',
          ),
          hasLength(1),
        );
      },
    );

    test(
      'GI-006 inbox failure leaves message sent with retry payload and no durable mark',
      () async {
        final failBridge = _InboxStoreFailBridge();
        failBridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'gi006-inbox-fail',
          'topicPeers': 2,
        };
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-2',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-2',
            joinedAt: DateTime.utc(2026, 5, 13, 9),
          ),
        );

        late SendGroupMessageResult result;
        late GroupMessage? message;
        final events = await captureFlowEvents(() async {
          (result, message) = await sendGroupMessage(
            bridge: failBridge,
            groupRepo: groupRepo,
            msgRepo: msgRepo,
            groupId: 'group-1',
            text: 'GI-006 inbox fails but retry is staged',
            senderPeerId: 'peer-1',
            senderPublicKey: 'pk-1',
            senderPrivateKey: 'sk-1',
            senderUsername: 'Alice',
            messageId: 'gi006-inbox-fail',
          );
        });

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        final returnedMessage = message!;
        expect(returnedMessage.status, 'sent');
        expect(returnedMessage.inboxStored, isFalse);
        expect(returnedMessage.inboxRetryPayload, isNotNull);
        expect(
          _recipientPeerIdsFromRetryPayload(returnedMessage.inboxRetryPayload!),
          <String>['peer-2'],
        );

        final saved = await msgRepo.getMessage('gi006-inbox-fail');
        expect(saved, isNotNull);
        expect(saved!.status, 'sent');
        expect(saved.wireEnvelope, isNull);
        expect(saved.inboxStored, isFalse);
        expect(saved.inboxRetryPayload, isNotNull);
        expect(
          _recipientPeerIdsFromRetryPayload(saved.inboxRetryPayload!),
          <String>['peer-2'],
        );

        final failureEvent = events.firstWhere(
          (event) => event['event'] == 'GROUP_SEND_MSG_INBOX_STORE_FAILED',
        );
        expect(
          failureEvent['details']['error'],
          contains('Relay inbox store failed'),
        );
      },
    );

    test(
      'GO-002 publish success with inbox failure stays sent and retryable',
      () async {
        final failBridge = _InboxStoreFailBridge();
        failBridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'go002-inbox-fail',
          'topicPeers': 2,
        };
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-2',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-2',
            joinedAt: DateTime.utc(2026, 5, 13, 11),
          ),
        );

        late SendGroupMessageResult result;
        late GroupMessage? message;
        final events = await captureFlowEvents(() async {
          (result, message) = await sendGroupMessage(
            bridge: failBridge,
            groupRepo: groupRepo,
            msgRepo: msgRepo,
            groupId: 'group-1',
            text: 'GO-002 inbox store fails after publish succeeds',
            senderPeerId: 'peer-1',
            senderPublicKey: 'pk-1',
            senderPrivateKey: 'sk-1',
            senderUsername: 'Alice',
            messageId: 'go002-inbox-fail',
          );
        });

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        final returnedMessage = message!;
        expect(returnedMessage.status, 'sent');
        expect(returnedMessage.inboxStored, isFalse);
        expect(returnedMessage.inboxRetryPayload, isNotNull);
        expect(
          _recipientPeerIdsFromRetryPayload(returnedMessage.inboxRetryPayload!),
          <String>['peer-2'],
        );

        final saved = await msgRepo.getMessage('go002-inbox-fail');
        expect(saved, isNotNull);
        expect(saved!.status, 'sent');
        expect(saved.inboxStored, isFalse);
        expect(saved.wireEnvelope, isNull);
        expect(saved.inboxRetryPayload, isNotNull);

        final successEvent = events.firstWhere(
          (event) => event['event'] == 'GROUP_SEND_MSG_USE_CASE_SUCCESS',
        );
        expect(successEvent['details']['topicPeers'], 2);
        expect(successEvent['details']['inboxOk'], isFalse);
        expect(successEvent['details']['inboxPending'], isFalse);

        final timingEvent = events.lastWhere(
          (event) => event['event'] == 'GROUP_SEND_MSG_TIMING',
        );
        expect(timingEvent['details']['outcome'], 'success');
        expect(timingEvent['details']['status'], 'sent');
        expect(timingEvent['details']['inboxStored'], isFalse);
        expect(timingEvent['details']['inboxPending'], isFalse);
      },
    );

    test(
      'GO-008 EK-002 GI-035 sent inbox retry and flow logs omit protected plaintext',
      () async {
        final privacyBridge = _OpaqueReplayInboxStoreFailBridge();
        privacyBridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'msg-ek002-privacy',
          'topicPeers': 2,
        };
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-2',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-2',
            joinedAt: DateTime.utc(2026, 1, 2),
          ),
        );

        const protectedText = 'EK002 secret message body alpha';
        const inviteSecret = 'invite-token-secret-ek002-beta';
        const privateState = 'private-state-secret-ek002-gamma';
        const mediaKey = 'media-key-secret-ek002-delta';
        final protectedFragments = [
          protectedText,
          inviteSecret,
          privateState,
          mediaKey,
        ];
        final mediaAttachment = MediaAttachment(
          id: 'att-ek002-private',
          messageId: '',
          mime: 'image/png',
          size: 1200,
          mediaType: 'image',
          downloadStatus: 'done',
          createdAt: DateTime.utc(2026, 1, 2).toIso8601String(),
          contentHash: _validContentHash,
          encryptionKeyBase64: mediaKey,
          encryptionNonce: 'media-nonce-secret-ek002',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );
        final privacyMediaRepo = InMemoryMediaAttachmentRepository();

        late SendGroupMessageResult result;
        late GroupMessage? message;
        final events = await captureFlowEvents(() async {
          (result, message) = await sendGroupMessage(
            bridge: privacyBridge,
            groupRepo: groupRepo,
            msgRepo: msgRepo,
            groupId: 'group-1',
            text: '$protectedText $inviteSecret $privateState',
            senderPeerId: 'peer-1',
            senderPublicKey: 'pk-1',
            senderPrivateKey: 'sk-1',
            senderUsername: 'Alice',
            messageId: 'msg-ek002-privacy',
            mediaAttachments: [mediaAttachment],
            mediaAttachmentRepo: privacyMediaRepo,
          );
        });

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        final returnedMessage = message!;
        expect(returnedMessage.status, 'sent');
        expect(returnedMessage.inboxRetryPayload, isNotNull);

        final saved = await msgRepo.getMessage('msg-ek002-privacy');
        expect(saved, isNotNull);
        expect(saved!.inboxRetryPayload, isNotNull);

        final retryRaw = saved.inboxRetryPayload!;
        _expectNoProtectedFragments(retryRaw, protectedFragments);
        final retryPayload = jsonDecode(retryRaw) as Map<String, dynamic>;
        expect(retryPayload['recipientPeerIds'], ['peer-2']);

        final retryEnvelope = _offlineReplayEnvelopeFromRetryPayload(retryRaw);
        expect(retryEnvelope['kind'], 'group_offline_replay');
        expect(retryEnvelope['payloadType'], 'group_message');
        expect(retryEnvelope['keyEpoch'], 1);
        expect(retryEnvelope['messageId'], 'msg-ek002-privacy');
        expect(retryEnvelope['ciphertext'], startsWith('sealed:'));
        expect(retryEnvelope['nonce'], 'opaque-replay-nonce');
        expect(retryEnvelope.containsKey('text'), isFalse);
        expect(retryEnvelope.containsKey('media'), isFalse);
        expect(retryEnvelope.containsKey('senderUsername'), isFalse);

        final inboxStoreCommand = privacyBridge.sentMessages.lastWhere(
          (raw) =>
              (jsonDecode(raw) as Map<String, dynamic>)['cmd'] ==
              'group:inboxStore',
        );
        _expectNoProtectedFragments(inboxStoreCommand, protectedFragments);
        final inboxPayload = _lastGroupInboxStorePayload(privacyBridge);
        expect(inboxPayload['message'], retryPayload['message']);
        expect(inboxPayload.containsKey('pushTitle'), isFalse);
        expect(inboxPayload.containsKey('pushBody'), isFalse);
        _expectNoProtectedFragments(jsonEncode(events), [
          ...protectedFragments,
          'media-nonce-secret-ek002',
        ]);
      },
    );

    test(
      'IR-014 group inbox store relay payload omits plaintext and secrets',
      () async {
        final privacyBridge = _OpaqueReplayBridge();
        privacyBridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'msg-ir014-opaque',
          'topicPeers': 1,
        };
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-2',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-2',
            joinedAt: DateTime.utc(2026, 1, 2),
          ),
        );

        const protectedText = 'IR014 private relay body alpha';
        const protectedUsername = 'Alice IR014 Secret Name';
        const inviteSecret = 'invite-token-ir014-beta';
        const memberSecret = 'member-secret-ir014-gamma';
        const groupKey = 'test-group-key-1';
        final protectedFragments = [
          protectedText,
          protectedUsername,
          inviteSecret,
          memberSecret,
          groupKey,
        ];

        final (result, message) = await sendGroupMessage(
          bridge: privacyBridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: '$protectedText $inviteSecret $memberSecret',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: protectedUsername,
          messageId: 'msg-ir014-opaque',
        );

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        final inboxStoreCommand = privacyBridge.sentMessages.lastWhere(
          (raw) =>
              (jsonDecode(raw) as Map<String, dynamic>)['cmd'] ==
              'group:inboxStore',
        );
        _expectNoProtectedFragments(inboxStoreCommand, protectedFragments);

        final inboxPayload = _lastGroupInboxStorePayload(privacyBridge);
        expect(inboxPayload.keys.toSet(), {
          'groupId',
          'message',
          'recipientPeerIds',
          'preserveRecipientPeerIds',
        });
        expect(inboxPayload['groupId'], 'group-1');
        expect(inboxPayload['recipientPeerIds'], ['peer-2']);
        expect(inboxPayload['preserveRecipientPeerIds'], isTrue);
        expect(inboxPayload.containsKey('pushTitle'), isFalse);
        expect(inboxPayload.containsKey('pushBody'), isFalse);

        final replayEnvelope =
            jsonDecode(inboxPayload['message'] as String)
                as Map<String, dynamic>;
        expect(replayEnvelope['kind'], 'group_offline_replay');
        expect(replayEnvelope['payloadType'], 'group_message');
        expect(replayEnvelope['messageId'], 'msg-ir014-opaque');
        expect(replayEnvelope['ciphertext'], startsWith('sealed:'));
        expect(replayEnvelope['nonce'], 'opaque-replay-nonce');
        expect(replayEnvelope.containsKey('text'), isFalse);
        expect(replayEnvelope.containsKey('senderUsername'), isFalse);
        _expectNoProtectedFragments(
          replayEnvelope['signedPayload'] as String,
          protectedFragments,
        );
      },
    );

    test(
      'PGC-010 live publish keeps inbox action and completion in one membership phase',
      () async {
        final gatedBridge = _GatedInboxStoreBridge();
        gatedBridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'msg-peers-bg-inbox',
          'topicPeers': 2,
        };

        final sendFuture = sendGroupMessage(
          bridge: gatedBridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Return before inbox completes',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'msg-peers-bg-inbox',
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        var markerCommitted = false;
        final markerFuture = runGroupMembershipMutationLocked(
          groupId: 'group-1',
          action: () async {
            final current = await groupRepo.getGroup('group-1');
            await groupRepo.updateGroup(
              current!.copyWith(selfRemovedAt: DateTime.utc(2026, 7, 20, 10)),
            );
            markerCommitted = true;
          },
        );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        expect(
          markerCommitted,
          isFalse,
          reason: 'B3 must wait for inbox action plus exact completion',
        );

        final savedBeforeRelease = await msgRepo.getMessage(
          'msg-peers-bg-inbox',
        );
        expect(savedBeforeRelease, isNotNull);
        expect(savedBeforeRelease!.status, 'sending');
        expect(savedBeforeRelease.inboxStored, isFalse);
        expect(savedBeforeRelease.inboxRetryPayload, isNotNull);

        gatedBridge.inboxGate.complete();
        final (result, message) = await sendFuture;
        await markerFuture;

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'sent');
        expect(message.inboxStored, isTrue);
        expect(message.inboxRetryPayload, isNull);
        expect(markerCommitted, isTrue);

        final savedAfterRelease = await msgRepo.getMessage(
          'msg-peers-bg-inbox',
        );
        expect(savedAfterRelease, isNotNull);
        expect(savedAfterRelease!.status, 'sent');
        expect(savedAfterRelease.inboxStored, isTrue);
        expect(savedAfterRelease.inboxRetryPayload, isNull);
      },
    );

    test(
      'PGC-010 B3-first membership phase stops foreground publish before dispatch',
      () async {
        final markerMayFinish = Completer<void>();
        final markerCommitted = Completer<void>();
        final markerFuture = runGroupMembershipMutationLocked(
          groupId: 'group-1',
          action: () async {
            final current = await groupRepo.getGroup('group-1');
            await groupRepo.updateGroup(
              current!.copyWith(
                selfRemovedAt: DateTime.utc(2026, 7, 20, 10, 1),
              ),
            );
            markerCommitted.complete();
            await markerMayFinish.future;
          },
        );
        await markerCommitted.future;

        var sendCompleted = false;
        final sendFuture = sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Must not leave the removed shell',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'msg-b3-first',
        ).whenComplete(() => sendCompleted = true);
        await Future<void>.delayed(const Duration(milliseconds: 10));

        expect(sendCompleted, isFalse, reason: 'send must queue behind B3');
        expect(
          bridge.commandLog.where((command) => command == 'group:publish'),
          isEmpty,
        );

        markerMayFinish.complete();
        await markerFuture;
        final (result, message) = await sendFuture;

        expect(result, SendGroupMessageResult.groupNotFound);
        expect(message, isNull);
        expect(
          bridge.commandLog.where((command) => command == 'group:publish'),
          isEmpty,
        );
        expect(await msgRepo.getMessage('msg-b3-first'), isNull);
      },
    );

    test('missing topicPeers + inbox OK → legacy success stays sent', () async {
      // Old bridge response without topicPeers key
      bridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'msg-legacy',
      };

      final (result, message) = await sendGroupMessage(
        bridge: bridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Legacy bridge',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'msg-legacy',
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      expect(message!.status, 'sent');
      expect(message.inboxStored, isTrue);

      final saved = await msgRepo.getMessage('msg-legacy');
      expect(saved, isNotNull);
      expect(saved!.status, 'sent');
      expect(saved.wireEnvelope, isNull);
      expect(saved.inboxRetryPayload, isNull);
    });

    test(
      'missing topicPeers + inbox fail → legacy success stays pending until inbox retry closes it',
      () async {
        final failBridge = _InboxStoreFailBridge();
        failBridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'msg-legacy-inbox-fail',
        };

        final (result, message) = await sendGroupMessage(
          bridge: failBridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Legacy bridge with inbox failure',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'msg-legacy-inbox-fail',
        );

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'pending');
        expect(message.inboxStored, isFalse);
        expect(message.inboxRetryPayload, isNotNull);

        final saved = await msgRepo.getMessage('msg-legacy-inbox-fail');
        expect(saved, isNotNull);
        expect(saved!.status, 'pending');
        expect(saved.wireEnvelope, isNull);
        expect(saved.inboxRetryPayload, isNotNull);
      },
    );

    test(
      'publish fail + inbox fail → status failed, both payloads retained',
      () async {
        final failBridge = _InboxStoreFailBridge();
        failBridge.responses['group:publish'] = {
          'ok': false,
          'errorCode': 'PUBLISH_FAILED',
        };

        final (result, message) = await sendGroupMessage(
          bridge: failBridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Will fail',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'msg-publish-fail',
        );

        expect(result, SendGroupMessageResult.error);
        // Pre-persisted row should exist with 'failed' status
        final page = await msgRepo.getMessagesPage('group-1');
        expect(page, hasLength(1));
        expect(page.single.id, 'msg-publish-fail');
        final saved = await msgRepo.getMessage(page.single.id);
        expect(saved, isNotNull);
        expect(saved!.status, 'failed');
        expect(saved.wireEnvelope, isNotNull);
        expect(saved.inboxStored, isFalse);
        expect(saved.inboxRetryPayload, isNotNull);
      },
    );

    test(
      'publish fail + inbox OK keeps failed status but persists inbox success explicitly',
      () async {
        final failPublishBridge = _FailPublishBridge();

        final (result, message) = await sendGroupMessage(
          bridge: failPublishBridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Publish fails, inbox stores',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'msg-publish-fail-inbox-ok',
        );

        expect(result, SendGroupMessageResult.error);
        expect(message, isNotNull);
        expect(message!.status, 'failed');
        expect(message.inboxStored, isTrue);
        expect(message.inboxRetryPayload, isNull);

        final saved = await msgRepo.getMessage('msg-publish-fail-inbox-ok');
        expect(saved, isNotNull);
        expect(saved!.status, 'failed');
        expect(saved.wireEnvelope, isNotNull);
        expect(saved.inboxStored, isTrue);
        expect(saved.inboxRetryPayload, isNull);
      },
    );

    test(
      'DE-008 publish timeout with durable inbox custody is visible sent success (publish timeout + inbox OK surfaces durable success instead of failed)',
      () async {
        final timeoutPublishBridge = FakeBridge(
          initialResponses: {
            'group:publish': {'ok': false, 'errorCode': 'BRIDGE_TIMEOUT'},
          },
        );

        final (result, message) = await sendGroupMessage(
          bridge: timeoutPublishBridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Publish timed out, inbox stored',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'msg-publish-timeout-inbox-ok',
        );

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        expect(message!.status, 'sent');
        expect(message.inboxStored, isTrue);
        expect(message.wireEnvelope, isNull);
        expect(message.inboxRetryPayload, isNull);

        final page = await msgRepo.getMessagesPage('group-1');
        expect(page, hasLength(1));
        expect(page.single.id, 'msg-publish-timeout-inbox-ok');
        expect(page.single.isIncoming, isFalse);
        expect(page.single.status, 'sent');

        final saved = await msgRepo.getMessage('msg-publish-timeout-inbox-ok');
        expect(saved, isNotNull);
        expect(saved!.status, 'sent');
        expect(saved.inboxStored, isTrue);
        expect(saved.wireEnvelope, isNull);
        expect(saved.inboxRetryPayload, isNull);
      },
    );

    test(
      'DE-008 publish timeout without durable inbox custody leaves one visible failed retryable row',
      () async {
        final timeoutNoCustodyBridge = _InboxStoreOkFalseBridge();
        timeoutNoCustodyBridge.responses['group:publish'] = {
          'ok': false,
          'errorCode': 'BRIDGE_TIMEOUT',
          'errorMessage': 'publish timed out',
        };

        final (result, message) = await sendGroupMessage(
          bridge: timeoutNoCustodyBridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Publish timed out without custody',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'msg-de008-publish-timeout-no-custody',
        );

        expect(result, SendGroupMessageResult.error);
        expect(message, isNotNull);
        expect(message!.id, 'msg-de008-publish-timeout-no-custody');
        expect(message.status, 'failed');
        expect(message.wireEnvelope, isNotNull);
        expect(message.inboxRetryPayload, isNotNull);
        expect(message.inboxStored, isFalse);
        expect(timeoutNoCustodyBridge.commandLog, contains('group:publish'));
        expect(timeoutNoCustodyBridge.commandLog, contains('group:inboxStore'));

        final page = await msgRepo.getMessagesPage('group-1');
        expect(page, hasLength(1));
        final visible = page.single;
        expect(visible.id, 'msg-de008-publish-timeout-no-custody');
        expect(visible.isIncoming, isFalse);
        expect(visible.status, 'failed');
        expect(visible.wireEnvelope, isNotNull);
        expect(visible.inboxRetryPayload, isNotNull);
        expect(visible.inboxStored, isFalse);

        final failedOutgoing = await msgRepo.getFailedOutgoingMessages();
        expect(failedOutgoing.map((row) => row.id), [
          'msg-de008-publish-timeout-no-custody',
        ]);

        final failedInboxStores = await msgRepo
            .getMessagesWithFailedInboxStore();
        expect(
          failedInboxStores.map((row) => row.id),
          isNot(contains('msg-de008-publish-timeout-no-custody')),
        );
      },
    );

    test(
      'GFR-002 no usable transport persists one retryable row for same attempt',
      () async {
        final sentAt = DateTime.utc(2026, 6, 6, 8, 4);
        const messageId = 'gfr002-no-transport-once';
        const logicalDeliveryId = 'gfr002-logical-no-transport';
        final noTransportBridge = _InboxStoreOkFalseBridge();
        noTransportBridge.responses['group:publish'] = {
          'ok': false,
          'errorCode': 'NO_USABLE_TRANSPORT',
          'errorMessage': 'no usable transport',
        };

        final (failedResult, failedMessage) = await sendGroupMessage(
          bridge: noTransportBridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'GFR-002 queued once',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: messageId,
          logicalDeliveryId: logicalDeliveryId,
          timestamp: sentAt,
        );

        expect(failedResult, SendGroupMessageResult.error);
        expect(failedMessage, isNotNull);
        expect(failedMessage!.id, messageId);
        expect(failedMessage.logicalDeliveryId, logicalDeliveryId);
        expect(failedMessage.status, 'failed');

        final failedRows = await msgRepo.getMessagesPage('group-1');
        expect(failedRows.map((row) => row.id), [messageId]);
        final failedSaved = await msgRepo.getMessage(messageId);
        expect(failedSaved, isNotNull);
        expect(failedSaved!.status, 'failed');
        expect(failedSaved.logicalDeliveryId, logicalDeliveryId);
        expect(failedSaved.wireEnvelope, isNotNull);
        expect(failedSaved.inboxRetryPayload, isNotNull);
        expect(
          (await msgRepo.getFailedOutgoingMessages()).map((row) => row.id),
          [messageId],
        );

        noTransportBridge.responses['group:publish'] = {
          'ok': true,
          'messageId': messageId,
          'topicPeers': 1,
        };
        noTransportBridge.responses['group:inboxStore'] = {'ok': true};

        final (retryResult, retriedMessage) = await sendGroupMessage(
          bridge: noTransportBridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'GFR-002 queued once',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: messageId,
          logicalDeliveryId: logicalDeliveryId,
          timestamp: sentAt,
          messageIdFactory: () => 'gfr002-duplicate-should-not-be-used',
        );

        expect(retryResult, SendGroupMessageResult.success);
        expect(retriedMessage, isNotNull);
        expect(retriedMessage!.id, messageId);
        expect(retriedMessage.logicalDeliveryId, logicalDeliveryId);
        expect(retriedMessage.timestamp, sentAt);

        final finalRows = await msgRepo.getMessagesPage('group-1');
        expect(finalRows.map((row) => row.id), [messageId]);
        expect(finalRows.single.status, 'sent');
        expect(finalRows.single.logicalDeliveryId, logicalDeliveryId);
        expect(
          noTransportBridge.commandLog.where((cmd) => cmd == 'group:publish'),
          hasLength(2),
        );
      },
    );

    test(
      'BB-013 group:publish timeout without durable inbox custody leaves failed retryable state',
      () async {
        final timeoutNoCustodyBridge = _InboxStoreOkFalseBridge();
        timeoutNoCustodyBridge.responses['group:publish'] = {
          'ok': false,
          'errorCode': 'BRIDGE_TIMEOUT',
          'errorMessage': 'publish timed out',
        };

        final (result, message) = await sendGroupMessage(
          bridge: timeoutNoCustodyBridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Publish timed out, inbox did not store',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'msg-bb013-publish-timeout-no-custody',
        );

        expect(result, SendGroupMessageResult.error);
        expect(message, isNotNull);
        expect(message!.status, 'failed');
        expect(message.inboxStored, isFalse);
        expect(message.inboxRetryPayload, isNotNull);
        expect(message.wireEnvelope, isNotNull);
        expect(timeoutNoCustodyBridge.commandLog, contains('group:publish'));
        expect(timeoutNoCustodyBridge.commandLog, contains('group:inboxStore'));

        final saved = await msgRepo.getMessage(
          'msg-bb013-publish-timeout-no-custody',
        );
        expect(saved, isNotNull);
        expect(saved!.status, 'failed');
        expect(saved.inboxStored, isFalse);
        expect(saved.inboxRetryPayload, isNotNull);
        expect(saved.wireEnvelope, isNotNull);
      },
    );

    test(
      'BB-015 native publish failures leave one visible failed retryable row',
      () async {
        final failures = <String, Map<String, String>>{
          'NULL_RESPONSE': {
            'errorCode': 'NULL_RESPONSE',
            'errorMessage': 'Native bridge returned null',
          },
          'MISSING_PLUGIN': {
            'errorCode': 'MISSING_PLUGIN',
            'errorMessage': 'Rebuild the app with the updated native bridge.',
          },
          'PLATFORM_ERROR': {
            'errorCode': 'PLATFORM_ERROR',
            'errorMessage': 'Platform channel error',
          },
          'MALFORMED_RESPONSE': {
            'errorCode': 'MALFORMED_RESPONSE',
            'errorMessage': 'Native bridge returned malformed JSON',
          },
        };

        for (final failure in failures.entries) {
          final failureBridge = _InboxStoreOkFalseBridge();
          failureBridge.responses['group:publish'] = {
            'ok': false,
            ...failure.value,
          };
          final suffix = failure.key.toLowerCase().replaceAll('_', '-');
          final messageId = 'msg-bb015-$suffix';

          final (result, message) = await sendGroupMessage(
            bridge: failureBridge,
            groupRepo: groupRepo,
            msgRepo: msgRepo,
            groupId: 'group-1',
            text: 'BB-015 ${failure.key}',
            senderPeerId: 'peer-1',
            senderPublicKey: 'pk-1',
            senderPrivateKey: 'sk-1',
            senderUsername: 'Alice',
            messageId: messageId,
          );

          expect(result, SendGroupMessageResult.error, reason: failure.key);
          expect(message, isNotNull, reason: failure.key);
          expect(message!.id, messageId, reason: failure.key);
          expect(message.status, 'failed', reason: failure.key);
          expect(message.wireEnvelope, isNotNull, reason: failure.key);
          expect(message.inboxRetryPayload, isNotNull, reason: failure.key);
          expect(message.inboxStored, isFalse, reason: failure.key);
          expect(
            failureBridge.commandLog,
            contains('group:publish'),
            reason: failure.key,
          );
          expect(
            failureBridge.commandLog,
            contains('group:inboxStore'),
            reason: failure.key,
          );

          final saved = await msgRepo.getMessage(messageId);
          expect(saved, isNotNull, reason: failure.key);
          expect(saved!.status, 'failed', reason: failure.key);
          expect(saved.wireEnvelope, isNotNull, reason: failure.key);
          expect(saved.inboxRetryPayload, isNotNull, reason: failure.key);
          expect(saved.inboxStored, isFalse, reason: failure.key);

          final visibleRows = (await msgRepo.getMessagesPage(
            'group-1',
          )).where((row) => row.id == messageId).toList();
          expect(visibleRows, hasLength(1), reason: failure.key);
          expect(
            visibleRows.where(
              (row) => row.status == 'sending' || row.status == 'pending',
            ),
            isEmpty,
            reason: failure.key,
          );

          final failedOutgoing = await msgRepo.getFailedOutgoingMessages();
          expect(
            failedOutgoing.map((row) => row.id),
            contains(messageId),
            reason: failure.key,
          );
        }
      },
    );

    test(
      'GI-007 relay non-OK status leaves message sent with retry payload',
      () async {
        final okFalseBridge = _InboxStoreOkFalseBridge();
        okFalseBridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'gi007-non-ok',
          'topicPeers': 2,
        };
        await groupRepo.saveMember(
          GroupMember(
            groupId: 'group-1',
            peerId: 'peer-2',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-2',
            joinedAt: DateTime.utc(2026, 5, 13, 10),
          ),
        );

        final (result, message) = await sendGroupMessage(
          bridge: okFalseBridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'GI-007 relay returned non-OK',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
          messageId: 'gi007-non-ok',
        );

        expect(result, SendGroupMessageResult.success);
        expect(message, isNotNull);
        final returnedMessage = message!;
        expect(returnedMessage.status, 'sent');
        expect(returnedMessage.inboxStored, isFalse);
        expect(returnedMessage.inboxRetryPayload, isNotNull);
        expect(
          _recipientPeerIdsFromRetryPayload(returnedMessage.inboxRetryPayload!),
          <String>['peer-2'],
        );

        final saved = await msgRepo.getMessage('gi007-non-ok');
        expect(saved, isNotNull);
        expect(saved!.status, 'sent');
        expect(saved.inboxStored, isFalse);
        expect(saved.inboxRetryPayload, isNotNull);
        expect(
          _recipientPeerIdsFromRetryPayload(saved.inboxRetryPayload!),
          <String>['peer-2'],
        );
      },
    );

    test('inbox store ok:false is treated as inbox failure', () async {
      final okFalseBridge = _InboxStoreOkFalseBridge();
      okFalseBridge.responses['group:publish'] = {
        'ok': true,
        'messageId': 'msg-inbox-ok-false',
        'topicPeers': 3,
      };

      final (result, message) = await sendGroupMessage(
        bridge: okFalseBridge,
        groupRepo: groupRepo,
        msgRepo: msgRepo,
        groupId: 'group-1',
        text: 'Inbox bridge says ok false',
        senderPeerId: 'peer-1',
        senderPublicKey: 'pk-1',
        senderPrivateKey: 'sk-1',
        senderUsername: 'Alice',
        messageId: 'msg-inbox-ok-false',
      );

      expect(result, SendGroupMessageResult.success);
      expect(message, isNotNull);
      expect(message!.status, 'sent');
      expect(message.inboxStored, isFalse);
      expect(message.inboxRetryPayload, isNotNull);

      final saved = await msgRepo.getMessage('msg-inbox-ok-false');
      expect(saved, isNotNull);
      expect(saved!.status, 'sent');
      expect(saved.inboxStored, isFalse);
      expect(saved.inboxRetryPayload, isNotNull);
    });

    test(
      'inbox store uses exactly one group:inboxStore call on success',
      () async {
        bridge.responses['group:publish'] = {
          'ok': true,
          'messageId': 'msg-single-inbox',
          'topicPeers': 2,
        };

        await sendGroupMessage(
          bridge: bridge,
          groupRepo: groupRepo,
          msgRepo: msgRepo,
          groupId: 'group-1',
          text: 'Single inbox call',
          senderPeerId: 'peer-1',
          senderPublicKey: 'pk-1',
          senderPrivateKey: 'sk-1',
          senderUsername: 'Alice',
        );

        final inboxCalls = bridge.commandLog
            .where((c) => c == 'group:inboxStore')
            .length;
        expect(inboxCalls, 1);
      },
    );

    test(
      'TC-365-02a maximum supported group media manifest fits the relay frame',
      () async {
        const activePhysicalDevicesPerMember = 2;
        const supportedAttachmentMaximum = 10;
        const base58Alphabet =
            '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';
        final physicalTargetMaximum =
            groupMembershipLimit * activePhysicalDevicesPerMember - 1;
        expect(physicalTargetMaximum, protectedGroupMediaMaxPhysicalRecipients);
        final recipients = List<String>.generate(
          physicalTargetMaximum,
          (index) =>
              '12D3KooW${List<String>.filled(42, '1').join()}'
              '${base58Alphabet[index ~/ base58Alphabet.length]}'
              '${base58Alphabet[index % base58Alphabet.length]}',
        );
        final targets = List<GroupMediaBlobTargetCommitment>.generate(
          recipients.length,
          (index) => GroupMediaBlobTargetCommitment(
            recipientPeerId: recipients[index],
            expiresAtMs: 2000000000000 + index,
          ),
          growable: false,
        );
        final attachments =
            List<
              ProtectedGroupMediaAttachmentCommitment
            >.generate(supportedAttachmentMaximum, (index) {
              final attachmentId =
                  '00000000-0000-4000-8000-${index.toString().padLeft(12, '0')}';
              return ProtectedGroupMediaAttachmentCommitment(
                attachmentId: attachmentId,
                custodyBlobId: deterministicGroupMediaCustodyBlobId(
                  groupId: 'group-1',
                  messageId: '00000000-0000-4000-8000-000000000001',
                  attachmentId: attachmentId,
                ),
                ciphertextSha256: index.toRadixString(16).padLeft(64, '0'),
                ciphertextSize:
                    (kGroupMediaTotalMessageLimitBytes ~/
                        supportedAttachmentMaximum) +
                    16,
                mime: index.isEven ? 'image/jpeg' : 'audio/ogg',
                mediaType: index.isEven ? 'image' : 'audio',
                width: index.isEven ? 7680 : null,
                height: index.isEven ? 4320 : null,
                durationMs: index.isEven ? null : 1000 + index,
                waveform: index.isEven
                    ? const <double>[]
                    : List<double>.filled(50, 0.999999),
                encryptionKeyBase64: base64Encode(List<int>.filled(32, index)),
                encryptionNonce: base64Encode(List<int>.filled(12, index)),
                caption: index == 0 ? 'maximum supported media' : null,
                targets: targets,
              );
            });
        final manifest = ProtectedGroupMediaManifest(
          groupId: 'group-1',
          messageId: '00000000-0000-4000-8000-000000000001',
          attachments: attachments,
        );

        final canonical = manifest.encode();
        final reparsed = ProtectedGroupMediaManifest.decode(canonical);
        expect(reparsed.encode(), canonical);
        expect(reparsed.recipientPeerIds, recipients);
        expect(
          reparsed.contentExpiresAtOrBeforeMsFor(recipients.last),
          2000000000000 + recipients.length - 1,
        );
        expect(recipients, hasLength(physicalTargetMaximum));
        expect(attachments, hasLength(supportedAttachmentMaximum));
        expect(recipients.every((peerId) => peerId.length == 52), isTrue);
        final overflow = jsonDecode(canonical) as Map<String, dynamic>;
        (overflow['recipientPeerIds'] as List).add('zz-over-support-target');
        for (final attachment in overflow['attachments'] as List) {
          ((attachment as Map<String, dynamic>)['expiresAtMs'] as List).add(
            2000000009999,
          );
        }
        expect(
          () => ProtectedGroupMediaManifest.decode(jsonEncode(overflow)),
          throwsFormatException,
          reason: 'oversized physical ACLs fail closed instead of truncating',
        );

        final envelope = await buildGroupOfflineReplayEnvelope(
          bridge: _RelayFrameSizingBridge(),
          groupRepo: groupRepo,
          groupId: 'group-1',
          payloadType: groupOfflineReplayPayloadTypeMessage,
          plaintext: jsonEncode(<String, Object?>{
            'groupId': 'group-1',
            'senderId': 'peer-1',
            'senderDeviceId': 'device-primary',
            'transportPeerId': 'transport-primary',
            'messageId': manifest.messageId,
            'logicalDeliveryId': manifest.messageId,
            'keyEpoch': 1,
            'text': 'maximum supported media',
            'timestamp': '2026-08-14T12:00:00.000000Z',
          }),
          senderPeerId: 'peer-1',
          senderPublicKey: base64Encode(List<int>.filled(32, 1)),
          senderPrivateKey: base64Encode(List<int>.filled(64, 2)),
          senderDeviceId: 'device-primary',
          senderTransportPeerId: 'transport-primary',
          recipientPeerIds: recipients,
          messageId: manifest.messageId,
          contentEventId: manifest.messageId,
          contentAuthorityVersion: GroupContentAuthorityVersion(
            eventAt: DateTime.utc(2026, 8, 14, 11),
            eventId: 'authority-max',
            keyEpoch: 1,
          ),
          mediaManifest: manifest,
        );
        final decodedEnvelope = jsonDecode(envelope) as Map<String, dynamic>;
        expect(jsonEncode(decodedEnvelope), envelope);
        expect(decodedEnvelope['custodyKind'], groupContentCustodyKind);
        expect(decodedEnvelope['mediaManifest'], canonical);
        expect(
          decodedEnvelope['signedPayload'],
          canonicalizeGroupEventLogPayload(
            jsonDecode(decodedEnvelope['signedPayload']! as String)
                as Map<String, dynamic>,
          ),
        );
        final envelopeBytes = utf8.encode(envelope).length;
        expect(
          protectedGroupContentFitsRelayFrame(envelope),
          isTrue,
          reason:
              'full canonical group_content_v1 envelope is $envelopeBytes '
              'bytes for $physicalTargetMaximum physical targets and '
              '$supportedAttachmentMaximum attachments; limit is '
              '$protectedGroupContentMaxFrameBytes bytes',
        );
        expect(
          envelopeBytes,
          lessThanOrEqualTo(protectedGroupContentMaxFrameBytes),
        );
        expect(
          deterministicGroupMediaCustodyBlobId(
            groupId: manifest.groupId,
            messageId: manifest.messageId,
            attachmentId: attachments.first.attachmentId,
          ),
          attachments.first.custodyBlobId,
        );
      },
    );
  });
}
