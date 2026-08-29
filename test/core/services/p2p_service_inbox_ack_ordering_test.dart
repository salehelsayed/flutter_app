// ignore_for_file: overridden_fields

import 'dart:async';
import 'dart:convert';

import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/inbox/inbox_staging_entry.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_notification_display_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_reaction_replay_outbox_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/protected_group_content_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/protected_group_reaction_target_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/reactions_db_helpers.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/protected_group_authority_history.dart';
import 'package:flutter_app/features/groups/application/protected_group_content_receive.dart';
import 'package:flutter_app/features/groups/application/protected_group_content_reconciliation.dart';
import 'package:flutter_app/features/groups/application/protected_group_media_manifest.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_reaction_replay_outbox_entry.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/connection_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../core/bridge/fake_bridge.dart' as test_bridge;
import '../../shared/fakes/in_memory_inbox_staging_repository.dart';
import '../../shared/fakes/in_memory_group_repository.dart';

final class _DatabaseReadingGroupRepository extends InMemoryGroupRepository {
  _DatabaseReadingGroupRepository(this.database);

  final Database database;
  int authorityProjectionReads = 0;

  @override
  Future<GroupModel?> getGroup(String id) async {
    authorityProjectionReads++;
    await database.query(
      'groups',
      columns: const <String>['id'],
      where: 'id = ?',
      whereArgs: <Object?>[id],
      limit: 1,
    );
    return super.getGroup(id);
  }

  @override
  Future<GroupKeyInfo?> getLatestKey(String groupId) async {
    authorityProjectionReads++;
    await database.query(
      'group_keys',
      columns: const <String>['key_generation'],
      where: 'group_id = ?',
      whereArgs: <Object?>[groupId],
      orderBy: 'key_generation DESC',
      limit: 1,
    );
    return super.getLatestKey(groupId);
  }
}

class _FakeBridge extends Bridge {
  final Map<String, FutureOr<String> Function(Map<String, dynamic>?)>
  _handlers = {};
  final calledCommands = <String>[];
  final payloadsByCommand = <String, List<Map<String, dynamic>?>>{};
  bool _initialized = false;

  void whenCommand(
    String command,
    FutureOr<String> Function(Map<String, dynamic>?) handler,
  ) {
    _handlers[command] = handler;
  }

  List<Map<String, dynamic>?> payloadsFor(String command) =>
      List.unmodifiable(payloadsByCommand[command] ?? const []);

  @override
  bool get isInitialized => _initialized;

  @override
  Future<void> initialize() async {
    _initialized = true;
  }

  @override
  Future<bool> checkHealth() async => true;

  @override
  Future<void> reinitialize() async {}

  @override
  void dispose() {}

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    final command = request['cmd'] as String;
    final payload = request['payload'] as Map<String, dynamic>?;
    calledCommands.add(command);
    payloadsByCommand.putIfAbsent(command, () => []).add(payload);
    final handler = _handlers[command];
    if (handler != null) {
      return await handler(payload);
    }
    return jsonEncode({
      'ok': false,
      'errorCode': 'UNHANDLED',
      'errorMessage': 'no handler for $command',
    });
  }

  @override
  void Function(ChatMessage)? onMessageReceived;
  @override
  void Function(ConnectionState)? onPeerConnected;
  @override
  void Function(ConnectionState)? onPeerDisconnected;
  @override
  void Function(List<String>, List<String>)? onAddressesUpdated;
  @override
  void Function(Map<String, dynamic>)? onRelayStateChanged;
  @override
  void Function(Map<String, dynamic>)? onGroupMessageReceived;
  @override
  void Function(Map<String, dynamic>)? onGroupReactionReceived;
}

Map<String, dynamic> _pendingInboxRow({
  required String entryId,
  required String from,
  String messageId = 'msg-001',
  String text = 'hello',
  Object? timestamp = '2026-04-01T00:00:00.000Z',
}) {
  return {
    'id': entryId,
    'from': from,
    'message': jsonEncode({
      'type': 'chat_message',
      'version': '1',
      'payload': {
        'id': messageId,
        'text': text,
        'senderPeerId': from,
        'senderUsername': 'Alice',
        'timestamp': '2026-04-01T00:00:00.000Z',
      },
    }),
    'timestamp': timestamp,
  };
}

Map<String, dynamic> _pendingProtectedGroupRow({
  required String entryId,
  String type = 'group_authority_v1',
  bool useSignedContentDiscriminator = false,
  bool includeSignedPayloadWithoutDiscriminator = false,
  String? signedCustodyKindOverride,
  String? outerCustodyKind,
  String? crossedOuterType,
  Map<String, Object?> signedPayloadExtras = const <String, Object?>{},
}) {
  final signedPayload = useSignedContentDiscriminator
      ? canonicalizeGroupEventLogPayload(<String, Object?>{
          'custodyKind': signedCustodyKindOverride ?? type,
          ...signedPayloadExtras,
        })
      : includeSignedPayloadWithoutDiscriminator
      ? canonicalizeGroupEventLogPayload(const <String, Object?>{
          'schemaVersion': 1,
        })
      : null;
  return <String, dynamic>{
    'id': entryId,
    'from': 'physical-sender',
    'message': jsonEncode(<String, dynamic>{
      if (!useSignedContentDiscriminator && outerCustodyKind == null)
        'type': type,
      'type': ?crossedOuterType,
      'custodyKind': ?outerCustodyKind,
      'signedPayload': ?signedPayload,
      'version': '1',
      'id': '15:member_removed10:transition17:physical-linked',
      'senderPeerId': 'physical-sender',
      'recipientPeerId': 'physical-linked',
      'encrypted': <String, dynamic>{
        'kem': 'kem',
        'ciphertext': 'ciphertext',
        'nonce': 'nonce',
      },
    }),
    'timestamp': '2026-04-01T00:00:00.000Z',
  };
}

Future<void> _start(P2PServiceImpl service, _FakeBridge bridge) async {
  bridge.whenCommand(
    'node:start',
    (_) => jsonEncode({
      'ok': true,
      'peerId': 'self-peer',
      'isStarted': true,
      'listenAddresses': [],
      'circuitAddresses': [],
      'connections': [],
    }),
  );
  await service.startNodeCore('cHJpdmF0ZWtleXRlc3Q=', 'self-peer');
  bridge.calledCommands.clear();
}

Future<void> _waitFor(
  bool Function() condition, {
  Duration timeout = const Duration(milliseconds: 500),
  String reason = 'condition',
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('Timed out waiting for $reason');
}

RecoveredInboxReplayOutcome _committed() => (
  disposition: RecoveredInboxChatDisposition.committed,
  reasonCode: 'stored',
  reasonDetail: null,
);

String _requireAckOrExpiryCustodyContract(Map<String, dynamic>? payload) {
  expect(payload?['custodyContract'], ackOrExpiryInboxCustodyContract);
  return payload!['custodyContract'] as String;
}

Future<List<String>> _exerciseProtectedMetadataAckOrdering({
  required String entryId,
  required Map<String, Object?> metadata,
}) async {
  final bridge = _FakeBridge();
  final repo = InMemoryInboxStagingRepository();
  final ordering = <String>[];
  var committed = false;
  bridge.whenCommand('inbox:retrieve_pending', (payload) {
    final custodyContract = _requireAckOrExpiryCustodyContract(payload);
    return jsonEncode(<String, Object?>{
      'ok': true,
      'custodyContract': custodyContract,
      'messages': <Map<String, dynamic>>[
        _pendingProtectedGroupRow(
          entryId: entryId,
          type: groupContentCustodyKind,
          useSignedContentDiscriminator: true,
          signedPayloadExtras: metadata,
        ),
      ],
      'hasMore': false,
    });
  });
  bridge.whenCommand('inbox:ack', (payload) {
    expect(committed, isTrue, reason: 'metadata must commit before exact ACK');
    ordering.add('ack');
    final custodyContract = _requireAckOrExpiryCustodyContract(payload);
    return jsonEncode(<String, Object?>{
      'ok': true,
      'acked': 1,
      'custodyContract': custodyContract,
    });
  });
  final service = P2PServiceImpl(
    bridge: bridge,
    inboxStagingRepository: repo,
    replayRecoveredProtectedGroupEnvelope: (message) async {
      final envelope = jsonDecode(message.content) as Map<String, dynamic>;
      final signed =
          jsonDecode(envelope['signedPayload']! as String)
              as Map<String, dynamic>;
      for (final expected in metadata.entries) {
        expect(signed[expected.key], expected.value);
      }
      ordering.add('commit');
      committed = true;
      return (
        disposition: ProtectedGroupReplayDisposition.applied,
        reasonCode: 'protected_metadata_committed',
        reasonDetail: null,
      );
    },
  );
  await _start(service, bridge);
  await service.drainOfflineInbox();
  expect(repo.entry(entryId), isNull);
  service.dispose();
  return ordering;
}

Future<void> _exerciseProtectedContentAdapterAndReconciliation() async {
  final bridge = test_bridge.FakeBridge();
  final groupRepo = InMemoryGroupRepository();
  final group = GroupModel(
    id: 'group-364',
    name: 'Protected',
    type: GroupType.chat,
    topicName: 'unused-topic',
    createdAt: DateTime.utc(2026, 8, 13, 9),
    createdBy: 'peer-sender',
    myRole: GroupRole.member,
  );
  const senderDevice = GroupMemberDeviceIdentity(
    deviceId: 'device-sender',
    transportPeerId: 'transport-sender',
    deviceSigningPublicKey: 'pk-sender',
  );
  const localDevice = GroupMemberDeviceIdentity(
    deviceId: 'device-local',
    transportPeerId: 'transport-local',
    deviceSigningPublicKey: 'pk-local',
  );
  final sender = GroupMember(
    groupId: group.id,
    peerId: 'peer-sender',
    username: 'Sender',
    role: MemberRole.writer,
    publicKey: 'pk-sender',
    devices: const [senderDevice, localDevice],
    joinedAt: group.createdAt,
  );
  final local = GroupMember(
    groupId: group.id,
    peerId: 'peer-local',
    username: 'Local',
    role: MemberRole.writer,
    publicKey: 'pk-local',
    devices: const [localDevice],
    joinedAt: group.createdAt,
  );
  await groupRepo.saveGroup(group);
  await groupRepo.saveMember(sender);
  await groupRepo.saveMember(local);
  await groupRepo.saveKey(
    GroupKeyInfo(
      groupId: group.id,
      keyGeneration: 7,
      encryptedKey: 'group-key-7',
      createdAt: group.createdAt,
    ),
  );
  final observed = AuthenticatedGroupAuthorityProof(
    eventId: 'authority-observed',
    groupId: group.id,
    eventAt: DateTime.utc(2026, 8, 13, 10),
    keyEpoch: 7,
    control: 'bootstrap_genesis',
    actorAccountPeerId: 'peer-sender',
    actorAccountPublicKey: 'pk-sender',
    senderTransportPeerId: 'transport-sender',
    senderTransportPublicKey: 'pk-sender',
    authorityData: const <String, Object?>{},
    signature: 'fake-signature',
  );
  final authority = ProtectedGroupContentAuthority(
    observed: observed,
    groupType: GroupType.chat,
    members: [sender, local],
    terminalFacts: [observed],
  );
  const eventAt = '2026-08-13T11:00:00.000000Z';
  Future<String> messageEnvelope(
    String id,
    String text, {
    Map<String, Object?> extraPlaintext = const <String, Object?>{},
    List<String> recipientPeerIds = const <String>['transport-local'],
    ProtectedGroupMediaManifest? mediaManifest,
  }) => buildGroupOfflineReplayEnvelope(
    bridge: bridge,
    groupRepo: groupRepo,
    groupId: group.id,
    payloadType: groupOfflineReplayPayloadTypeMessage,
    plaintext: jsonEncode(<String, Object?>{
      'groupId': group.id,
      'senderId': sender.peerId,
      'senderDeviceId': senderDevice.deviceId,
      'transportPeerId': senderDevice.transportPeerId,
      'messageId': id,
      'logicalDeliveryId': id,
      'keyEpoch': 7,
      'text': text,
      'timestamp': eventAt,
      ...extraPlaintext,
    }),
    senderPeerId: sender.peerId,
    senderPublicKey: senderDevice.deviceSigningPublicKey,
    senderPrivateKey: 'sk-sender',
    senderDeviceId: senderDevice.deviceId,
    senderTransportPeerId: senderDevice.transportPeerId,
    recipientPeerIds: recipientPeerIds,
    messageId: id,
    contentEventId: id,
    contentAuthorityVersion: GroupContentAuthorityVersion(
      eventAt: observed.eventAt,
      eventId: observed.eventId,
      keyEpoch: observed.keyEpoch,
    ),
    mediaManifest: mediaManifest,
  );

  final committedPayloads = <String, String>{};
  final committedMessageRows = <String, Map<String, Object?>>{};
  final terminalContentKeys = <String>{};
  Map<String, Object?>? firstEventPayload;
  Map<String, Object?>? firstMessageRow;
  List<Map<String, Object?>>? committedMediaAttachmentRows;
  List<DirectMediaBlobCustodyRow>? committedIncomingMediaCustodyRows;
  Map<String, Object?>? committedMediaEventPayload;
  var terminalCommits = 0;
  var terminalCommitResult = DbProtectedGroupContentCommitResult.applied;
  var reactionCommits = 0;
  var displayBuilds = 0;
  var descriptorTransactionAttempts = 0;
  var targetDisposition =
      ProtectedGroupReactionTargetDisposition.prerequisiteWaiting;
  Future<ProtectedGroupContentApplyOutcome> apply(
    String envelope, {
    String localPeerId = 'peer-local',
    ProtectedGroupContentAuthority? acceptedAuthority,
    Future<bool> Function(String groupId)? hasPendingAuthority,
  }) => handleProtectedGroupContentReplay(
    bridge: bridge,
    groupRepository: groupRepo,
    message: ChatMessage(
      from: senderDevice.transportPeerId,
      to: localDevice.transportPeerId,
      content: envelope,
      timestamp: eventAt,
      isIncoming: true,
    ),
    localLogicalPeerId: localPeerId,
    localTransportPeerId: localDevice.transportPeerId,
    loadAuthority: (_, _) async => acceptedAuthority ?? authority,
    hasPendingAuthority: hasPendingAuthority ?? (String _) async => false,
    hasTerminal:
        ({
          required groupId,
          required payloadType,
          required contentEventId,
        }) async => terminalContentKeys.contains(
          '$groupId|$payloadType|$contentEventId',
        ),
    commitMessage:
        ({
          required groupId,
          required sourcePeerId,
          required sourceEventId,
          required sourceTimestamp,
          required eventPayload,
          required messageRow,
          required mediaAttachmentRows,
          required incomingMediaCustodyRows,
          readyDisplayOutboxRow,
        }) async {
          descriptorTransactionAttempts++;
          final canonical = canonicalizeGroupEventLogPayload(eventPayload);
          final existing = committedPayloads[sourceEventId];
          if (existing != null && existing != canonical) {
            throw GroupEventLogTamperException('conflicting protected id');
          }
          committedPayloads[sourceEventId] = canonical;
          committedMessageRows[sourceEventId] = Map<String, Object?>.from(
            messageRow,
          );
          firstEventPayload ??= Map<String, Object?>.from(eventPayload);
          firstMessageRow ??= Map<String, Object?>.from(messageRow);
          if (mediaAttachmentRows.isNotEmpty) {
            committedMediaEventPayload = Map<String, Object?>.from(
              eventPayload,
            );
            committedMediaAttachmentRows = List<Map<String, Object?>>.from(
              mediaAttachmentRows,
            );
            committedIncomingMediaCustodyRows =
                List<DirectMediaBlobCustodyRow>.from(incomingMediaCustodyRows);
          }
          return existing == null
              ? DbProtectedGroupContentCommitResult.applied
              : DbProtectedGroupContentCommitResult.exactDuplicate;
        },
    commitReaction:
        ({
          required groupId,
          required sourcePeerId,
          required sourceEventId,
          required sourceTimestamp,
          required eventPayload,
          required reactionRow,
          required transitionId,
          required action,
          readyDisplayOutboxRow,
        }) async {
          reactionCommits++;
          return DbProtectedGroupContentCommitResult.applied;
        },
    commitTerminal:
        ({
          required groupId,
          required sourcePeerId,
          required sourceEventId,
          required sourceTimestamp,
          required eventPayload,
        }) async {
          final result = terminalCommitResult;
          if (result == DbProtectedGroupContentCommitResult.applied ||
              result == DbProtectedGroupContentCommitResult.exactDuplicate) {
            terminalCommits++;
            terminalContentKeys.add(
              '$groupId|${eventPayload['payloadType']}|'
              '${eventPayload['contentEventId']}',
            );
          }
          return result;
        },
    resolveReactionTarget: (_, _) async => targetDisposition,
    buildMessageDisplayRow: (_) async {
      displayBuilds++;
      return null;
    },
    nowUtc: () => DateTime.utc(2026, 8, 13, 12),
  );

  final racedAuthorityEnvelope = await messageEnvelope(
    'msg-authority-prepared-race',
    'must wait',
  );
  final authorityPhaseEntered = Completer<void>();
  final releaseAuthorityPhase = Completer<void>();
  final authorityProducer = runGroupAuthorityPhase<void>(
    groupId: group.id,
    action: () async {
      authorityPhaseEntered.complete();
      await releaseAuthorityPhase.future;
    },
  );
  await authorityPhaseEntered.future;
  var pendingAuthorityInsidePhase = false;
  var pendingAuthorityChecks = 0;
  // This models the bootstrap optimization observing no PREPARED fact before
  // the authority producer commits one while holding the keyed phase.
  expect(pendingAuthorityInsidePhase, isFalse);
  final racedApply = apply(
    racedAuthorityEnvelope,
    hasPendingAuthority: (_) async {
      pendingAuthorityChecks++;
      return pendingAuthorityInsidePhase;
    },
  );
  await Future<void>.delayed(Duration.zero);
  pendingAuthorityInsidePhase = true;
  releaseAuthorityPhase.complete();
  await authorityProducer;
  final racedOutcome = await racedApply;
  expect(
    racedOutcome.disposition,
    ProtectedGroupContentApplyDisposition.prerequisiteWaiting,
  );
  expect(racedOutcome.reasonCode, 'authority_reconciliation_pending');
  expect(pendingAuthorityChecks, 1);
  expect(
    committedPayloads,
    isNot(
      contains(
        protectedGroupMessageSourceEventId('msg-authority-prepared-race'),
      ),
    ),
    reason: 'the in-phase PREPARED recheck prevents projection and later ACK',
  );

  final firstEnvelope = await messageEnvelope('msg-collision', 'ordinary');
  expect(
    (await apply(firstEnvelope)).disposition,
    ProtectedGroupContentApplyDisposition.applied,
  );
  expect(
    (await apply(firstEnvelope)).disposition,
    ProtectedGroupContentApplyDisposition.exactDuplicate,
  );
  expect(displayBuilds, 2, reason: 'duplicate display is transaction-deduped');
  expect(
    (await apply(firstEnvelope, localPeerId: sender.peerId)).disposition,
    ProtectedGroupContentApplyDisposition.exactDuplicate,
  );
  expect(
    firstMessageRow?['is_incoming'],
    1,
    reason: 'the non-self projection is incoming; self echo builds no display',
  );
  final quotedEnvelope = await messageEnvelope(
    'msg-protected-quote',
    'ordinary reply',
    extraPlaintext: const <String, Object?>{
      'quotedMessageId': 'missing-local-parent',
    },
  );
  expect(
    (await apply(quotedEnvelope)).disposition,
    ProtectedGroupContentApplyDisposition.applied,
  );
  expect(
    committedMessageRows[protectedGroupMessageSourceEventId(
      'msg-protected-quote',
    )]?['quoted_message_id'],
    'missing-local-parent',
  );
  final privateQuotedEnvelope = await messageEnvelope(
    'msg-private-quote-shape',
    'private quote must terminalize',
    extraPlaintext: const <String, Object?>{
      'quotedMessageId': 'parent-private',
      'mediaPolicyVersion': 1,
      'mediaLifecycle': 'standard',
      'mediaDurationSeconds': null,
      'mediaProtected': true,
    },
  );
  expect(
    (await apply(privateQuotedEnvelope)).disposition,
    ProtectedGroupContentApplyDisposition.terminalReject,
  );

  final mediaManifest = ProtectedGroupMediaManifest(
    groupId: group.id,
    messageId: 'msg-protected-media',
    attachments: <ProtectedGroupMediaAttachmentCommitment>[
      ProtectedGroupMediaAttachmentCommitment(
        attachmentId: 'attachment-a',
        custodyBlobId: 'blob-a',
        ciphertextSha256: List<String>.filled(64, 'a').join(),
        ciphertextSize: 116,
        mime: 'image/jpeg',
        mediaType: 'image',
        width: 12,
        height: 8,
        encryptionKeyBase64: 'a2V5LWE=',
        encryptionNonce: 'bm9uY2UtYQ==',
        caption: 'media caption',
        targets: <GroupMediaBlobTargetCommitment>[
          GroupMediaBlobTargetCommitment(
            recipientPeerId: 'transport-local',
            expiresAtMs: 2000000456000,
          ),
          GroupMediaBlobTargetCommitment(
            recipientPeerId: 'transport-peer-b',
            expiresAtMs: 2000000456100,
          ),
        ],
      ),
      ProtectedGroupMediaAttachmentCommitment(
        attachmentId: 'attachment-b',
        custodyBlobId: 'blob-b',
        ciphertextSha256: List<String>.filled(64, 'b').join(),
        ciphertextSize: 216,
        mime: 'audio/ogg',
        mediaType: 'audio',
        durationMs: 1500,
        waveform: const <double>[0.1, 0.5, 0.2],
        encryptionKeyBase64: 'a2V5LWI=',
        encryptionNonce: 'bm9uY2UtYg==',
        targets: <GroupMediaBlobTargetCommitment>[
          GroupMediaBlobTargetCommitment(
            recipientPeerId: 'transport-local',
            expiresAtMs: 2000000455000,
          ),
          GroupMediaBlobTargetCommitment(
            recipientPeerId: 'transport-peer-b',
            expiresAtMs: 2000000456200,
          ),
        ],
      ),
    ],
  );
  final mediaEnvelope = await messageEnvelope(
    mediaManifest.messageId,
    'media caption',
    recipientPeerIds: const <String>['transport-local', 'transport-peer-b'],
    mediaManifest: mediaManifest,
  );
  final crossedManifestMap =
      jsonDecode(mediaManifest.encode()) as Map<String, dynamic>;
  final crossedAttachment =
      (crossedManifestMap['attachments']! as List).first
          as Map<String, dynamic>;
  final crossedExpiries = List<Object?>.from(
    crossedAttachment['expiresAtMs']! as List,
  );
  expect(crossedExpiries, <Object?>[2000000456000, 2000000456100]);
  crossedAttachment['expiresAtMs'] = <Object?>[
    crossedExpiries[1],
    crossedExpiries[0],
  ];
  final crossedManifest = ProtectedGroupMediaManifest.decode(
    jsonEncode(crossedManifestMap),
  );
  final crossedEnvelopeMap = jsonDecode(mediaEnvelope) as Map<String, dynamic>
    ..['mediaManifest'] = crossedManifest.encode()
    ..['mediaManifestHash'] = crossedManifest.fingerprintSha256;
  final crossedSignedPayload =
      jsonDecode(crossedEnvelopeMap['signedPayload']! as String)
          as Map<String, dynamic>;
  expect(
    crossedSignedPayload['mediaManifestHash'],
    mediaManifest.fingerprintSha256,
    reason: 'the signature retains the original target-to-expiry authority',
  );
  expect(
    crossedEnvelopeMap['mediaManifestHash'],
    isNot(crossedSignedPayload['mediaManifestHash']),
    reason:
        'the visible manifest and its hash were crossed together, leaving '
        'only the signed hash able to reject the target swap',
  );

  final crossedBridge = _FakeBridge();
  final crossedRepo = InMemoryInboxStagingRepository();
  var crossedAckAttempts = 0;
  late ProtectedGroupContentApplyOutcome crossedOutcome;
  crossedBridge.whenCommand('inbox:retrieve_pending', (payload) {
    final custodyContract = _requireAckOrExpiryCustodyContract(payload);
    return jsonEncode(<String, Object?>{
      'ok': true,
      'custodyContract': custodyContract,
      'messages': <Map<String, Object?>>[
        <String, Object?>{
          'id': 'crossed-group-media-target-entry',
          'from': senderDevice.transportPeerId,
          'message': jsonEncode(crossedEnvelopeMap),
          'timestamp': eventAt,
        },
      ],
      'hasMore': false,
    });
  });
  crossedBridge.whenCommand('inbox:ack', (payload) {
    crossedAckAttempts++;
    final custodyContract = _requireAckOrExpiryCustodyContract(payload);
    return jsonEncode(<String, Object?>{
      'ok': true,
      'acked': 1,
      'custodyContract': custodyContract,
    });
  });
  final crossedService = P2PServiceImpl(
    bridge: crossedBridge,
    inboxStagingRepository: crossedRepo,
    replayRecoveredProtectedGroupEnvelope: (message) async {
      crossedOutcome = await apply(message.content);
      return (
        disposition: switch (crossedOutcome.disposition) {
          ProtectedGroupContentApplyDisposition.applied =>
            ProtectedGroupReplayDisposition.applied,
          ProtectedGroupContentApplyDisposition.exactDuplicate =>
            ProtectedGroupReplayDisposition.duplicate,
          ProtectedGroupContentApplyDisposition.terminalReject =>
            ProtectedGroupReplayDisposition.terminalRejected,
          ProtectedGroupContentApplyDisposition.unverifiedReject =>
            ProtectedGroupReplayDisposition.unverifiedRejected,
          ProtectedGroupContentApplyDisposition.prerequisiteWaiting =>
            ProtectedGroupReplayDisposition.prerequisiteWaiting,
          ProtectedGroupContentApplyDisposition.retryableFailure =>
            ProtectedGroupReplayDisposition.retryable,
        },
        reasonCode: crossedOutcome.reasonCode,
        reasonDetail: crossedOutcome.reasonDetail,
      );
    },
  );
  await _start(crossedService, crossedBridge);
  final descriptorAttemptsBeforeCrossedTarget = descriptorTransactionAttempts;
  await crossedService.drainOfflineInbox();
  expect(
    crossedOutcome.disposition,
    ProtectedGroupContentApplyDisposition.unverifiedReject,
  );
  expect(crossedOutcome.reasonCode, 'protected_media_manifest_binding_invalid');
  expect(
    descriptorTransactionAttempts,
    descriptorAttemptsBeforeCrossedTarget,
    reason:
        'crossed target authority is refused before attachment/custody '
        'descriptor commit',
  );
  expect(crossedAckAttempts, 0);
  expect(
    crossedBridge.payloadsFor('inbox:ack'),
    isEmpty,
    reason: 'crossed target authority never enters the content ACK set',
  );
  expect(
    crossedRepo.entry('crossed-group-media-target-entry')?.status,
    'quarantined',
  );
  crossedService.dispose();

  final decodedMediaRetry = GroupContentRetryPayload.decode(
    jsonEncode(<String, Object?>{
      'groupId': group.id,
      'message': mediaEnvelope,
      'custodyContract': ackOrExpiryInboxCustodyContract,
      'custodyKind': groupContentCustodyKind,
      'recipientPeerIds': const <String>['transport-local', 'transport-peer-b'],
    }),
  );
  expect(decodedMediaRetry.mediaManifest?.encode(), mediaManifest.encode());
  expect(decodedMediaRetry.mediaManifestHash, mediaManifest.fingerprintSha256);
  expect(
    decodedMediaRetry.contentExpiresAtOrBeforeMsFor('transport-local'),
    2000000455000,
  );
  expect(
    (await apply(mediaEnvelope)).disposition,
    ProtectedGroupContentApplyDisposition.applied,
  );
  expect(committedMediaAttachmentRows, hasLength(2));
  expect(
    committedMediaAttachmentRows?.map((row) => row['size']),
    <Object?>[100, 200],
    reason: 'attachment size is plaintext; custody retains ciphertext bytes',
  );
  expect(
    committedMediaAttachmentRows?.every(
      (row) => RegExp(
        r'^[0-9a-f]{64}$',
      ).hasMatch(row['group_media_blob_custody_fingerprint']! as String),
    ),
    isTrue,
  );
  expect(committedIncomingMediaCustodyRows, hasLength(2));
  expect(
    committedIncomingMediaCustodyRows?.every(
      (row) =>
          row.ownerLane == MediaBlobCustodyOwnerLane.group &&
          row.direction == DirectMediaBlobCustodyDirection.incoming &&
          row.state == DirectMediaBlobCustodyState.incomingCommitted &&
          row.recipientPeerId == null,
    ),
    isTrue,
  );
  expect(
    committedIncomingMediaCustodyRows?.map((row) => row.expiresAtMs),
    <int>[2000000456000, 2000000455000],
    reason:
        'incoming custody selects the local physical target from each distinct '
        'signed attachment commitment',
  );
  final committedMediaPlaintext =
      committedMediaEventPayload?['payload'] as Map<String, Object?>?;
  expect(committedMediaPlaintext?['mediaManifest'], mediaManifest.encode());
  expect(
    committedMediaPlaintext?['mediaManifestHash'],
    mediaManifest.fingerprintSha256,
  );

  final forwardedManifest = ProtectedGroupMediaManifest(
    groupId: group.id,
    messageId: 'msg-protected-forwarded-media',
    attachments: mediaManifest.attachments
        .where((attachment) => attachment.mediaType == 'image')
        .toList(growable: false),
  );
  final forwardedEnvelope = await messageEnvelope(
    forwardedManifest.messageId,
    'forwarded caption',
    extraPlaintext: const <String, Object?>{'isForwarded': true},
    recipientPeerIds: const <String>['transport-local', 'transport-peer-b'],
    mediaManifest: forwardedManifest,
  );
  expect(
    (await apply(forwardedEnvelope)).disposition,
    ProtectedGroupContentApplyDisposition.applied,
  );
  expect(
    committedMessageRows[protectedGroupMessageSourceEventId(
      forwardedManifest.messageId,
    )]?['is_forwarded'],
    1,
  );
  expect(committedMediaAttachmentRows, hasLength(1));

  final conflict = await messageEnvelope('msg-collision', 'different');
  expect(
    (await apply(conflict)).disposition,
    ProtectedGroupContentApplyDisposition.terminalReject,
  );
  final reserved = await messageEnvelope('msg-system', r'{"__sys":"x"}');
  expect(
    (await apply(reserved)).disposition,
    ProtectedGroupContentApplyDisposition.terminalReject,
  );
  final formerlyReserved = await messageEnvelope('msg-system', 'now ordinary');
  expect(
    (await apply(formerlyReserved)).reasonCode,
    'protected_content_terminal_duplicate',
    reason: 'durably terminalized content identity can never be resurrected',
  );
  expect(
    committedPayloads,
    isNot(contains(protectedGroupMessageSourceEventId('msg-system'))),
  );
  terminalCommitResult =
      DbProtectedGroupContentCommitResult.prerequisiteMissing;
  final deferredTerminal = await messageEnvelope(
    'msg-terminal-prerequisite',
    r'{"__sys":"deferred"}',
  );
  final deferredTerminalOutcome = await apply(deferredTerminal);
  expect(
    deferredTerminalOutcome.disposition,
    ProtectedGroupContentApplyDisposition.prerequisiteWaiting,
    reason: 'a failed terminal commit cannot make relay bytes ACK-eligible',
  );
  expect(
    deferredTerminalOutcome.reasonCode,
    'protected_content_terminal_prerequisite_missing',
  );
  expect(
    terminalContentKeys,
    isNot(
      contains(
        '${group.id}|$groupOfflineReplayPayloadTypeMessage|'
        'msg-terminal-prerequisite',
      ),
    ),
  );
  terminalCommitResult = DbProtectedGroupContentCommitResult.applied;
  for (final excluded in <Map<String, Object?>>[
    const <String, Object?>{'media': <Object?>[]},
    const <String, Object?>{'quotedMessageId': 42},
    const <String, Object?>{'isForwarded': 'yes'},
  ]) {
    final id = 'excluded-shape-${excluded.keys.single}';
    final shaped = await messageEnvelope(
      id,
      'ordinary',
      extraPlaintext: excluded,
    );
    expect(
      (await apply(shaped)).disposition,
      ProtectedGroupContentApplyDisposition.terminalReject,
    );
    expect(
      committedPayloads,
      isNot(contains(protectedGroupMessageSourceEventId(id))),
    );
  }
  expect(terminalCommits, greaterThanOrEqualTo(1));
  final terminalCommitsBeforeUnverified = terminalCommits;
  final signedOnlyOuter = jsonDecode(firstEnvelope) as Map<String, dynamic>
    ..remove('custodyKind');
  expect(
    (await apply(jsonEncode(signedOnlyOuter))).disposition,
    ProtectedGroupContentApplyDisposition.exactDuplicate,
    reason:
        'canonical signed content remains protected when its redundant '
        'unsigned outer marker is absent',
  );
  final crossedOuter = jsonDecode(firstEnvelope) as Map<String, dynamic>
    ..['type'] = 'group_authority_v1';
  expect(
    (await apply(jsonEncode(crossedOuter))).disposition,
    ProtectedGroupContentApplyDisposition.unverifiedReject,
    reason:
        'an unsigned outer authority hint cannot cross a signed content lane',
  );

  final topLevelOnly = jsonDecode(firstEnvelope) as Map<String, dynamic>
    ..remove('signedPayload');
  expect(
    (await apply(jsonEncode(topLevelOnly))).disposition,
    ProtectedGroupContentApplyDisposition.unverifiedReject,
  );
  final missingInner = jsonDecode(firstEnvelope) as Map<String, dynamic>;
  final missingInnerPayload =
      jsonDecode(missingInner['signedPayload']! as String)
            as Map<String, dynamic>
        ..remove('custodyKind');
  missingInner['signedPayload'] = canonicalizeGroupEventLogPayload(
    missingInnerPayload,
  );
  expect(
    (await apply(jsonEncode(missingInner))).disposition,
    ProtectedGroupContentApplyDisposition.unverifiedReject,
  );
  final crossedInner = jsonDecode(firstEnvelope) as Map<String, dynamic>;
  final crossedInnerPayload =
      jsonDecode(crossedInner['signedPayload']! as String)
            as Map<String, dynamic>
        ..['custodyKind'] = 'group_authority_v1';
  crossedInner['signedPayload'] = canonicalizeGroupEventLogPayload(
    crossedInnerPayload,
  );
  expect(
    (await apply(jsonEncode(crossedInner))).disposition,
    ProtectedGroupContentApplyDisposition.unverifiedReject,
  );
  final invalidSignature = jsonDecode(firstEnvelope) as Map<String, dynamic>
    ..['signature'] = 'invalid-signature';
  bridge.responses['payload.verify'] = <String, dynamic>{
    'ok': true,
    'valid': false,
  };
  expect(
    (await apply(jsonEncode(invalidSignature))).disposition,
    ProtectedGroupContentApplyDisposition.unverifiedReject,
  );
  bridge.responses.remove('payload.verify');
  expect(
    terminalCommits,
    terminalCommitsBeforeUnverified,
    reason: 'unverified bytes cannot manufacture durable terminal evidence',
  );
  expect(
    protectedGroupMessageSourceEventId('gr1:collision'),
    isNot(protectedGroupReactionSourceEventId('gr1:collision')),
  );

  final reactionAt = DateTime.utc(2026, 8, 13, 11, 5);
  final transition = buildGroupReactionTransitionId(
    groupId: group.id,
    messageId: 'missing-target',
    logicalActorPeerId: sender.peerId,
    action: 'add',
    emoji: '👍',
    timestamp: reactionAt,
  );
  final reactionEnvelope = await buildGroupOfflineReplayEnvelope(
    bridge: bridge,
    groupRepo: groupRepo,
    groupId: group.id,
    payloadType: groupOfflineReplayPayloadTypeReaction,
    plaintext: jsonEncode(<String, Object?>{
      'id': deterministicGroupReactionStateId(
        groupId: group.id,
        messageId: 'missing-target',
        logicalActorPeerId: sender.peerId,
      ),
      'messageId': 'missing-target',
      'emoji': '👍',
      'action': 'add',
      'senderPeerId': sender.peerId,
      'timestamp': fixedGroupContentUtc(reactionAt),
      'eventId': transition,
    }),
    senderPeerId: sender.peerId,
    senderPublicKey: senderDevice.deviceSigningPublicKey,
    senderPrivateKey: 'sk-sender',
    senderDeviceId: senderDevice.deviceId,
    senderTransportPeerId: senderDevice.transportPeerId,
    recipientPeerIds: const ['transport-local'],
    messageId: transition,
    contentEventId: transition,
    contentAuthorityVersion: GroupContentAuthorityVersion(
      eventAt: observed.eventAt,
      eventId: observed.eventId,
      keyEpoch: observed.keyEpoch,
    ),
    reactionNotificationExtension: GroupReactionNotificationExtensionInput(
      transitionId: transition,
      action: 'add',
      targetMessageId: 'missing-target',
      reactorPeerId: sender.peerId,
      reactorTransportPeerId: senderDevice.transportPeerId,
      notificationRecipientTransportPeerIds: const ['transport-local'],
    ),
  );
  expect(
    (await apply(reactionEnvelope)).disposition,
    ProtectedGroupContentApplyDisposition.prerequisiteWaiting,
  );
  targetDisposition = ProtectedGroupReactionTargetDisposition.terminal;
  expect(
    (await apply(reactionEnvelope)).disposition,
    ProtectedGroupContentApplyDisposition.terminalReject,
  );
  targetDisposition = ProtectedGroupReactionTargetDisposition.available;
  expect(
    (await apply(reactionEnvelope)).reasonCode,
    'protected_content_terminal_duplicate',
  );
  expect(reactionCommits, 0, reason: 'terminal reaction cannot resurrect');

  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
    options: OpenDatabaseOptions(
      version: 1,
      onCreate: (db, _) async {
        await db.execute('''CREATE TABLE group_event_log (
          id TEXT PRIMARY KEY, group_id TEXT NOT NULL, sequence INTEGER NOT NULL,
          event_type TEXT NOT NULL, source_peer_id TEXT NOT NULL,
          source_event_id TEXT NOT NULL, source_timestamp TEXT NOT NULL,
          canonical_payload TEXT NOT NULL, previous_entry_hash TEXT,
          entry_hash TEXT NOT NULL, created_at TEXT NOT NULL,
          UNIQUE(group_id, sequence), UNIQUE(group_id, source_event_id))''');
        await db.execute('''CREATE INDEX idx_group_event_log_event_type
          ON group_event_log(group_id, event_type, source_timestamp)''');
        await db.execute('''CREATE TABLE group_messages (
          id TEXT PRIMARY KEY, group_id TEXT NOT NULL,
          sender_peer_id TEXT NOT NULL, transport_peer_id TEXT,
          sender_username TEXT, text TEXT, timestamp TEXT NOT NULL,
          last_send_attempt_at TEXT, quoted_message_id TEXT,
          logical_delivery_id TEXT, key_generation INTEGER,
          status TEXT, is_incoming INTEGER, is_forwarded INTEGER,
          media_policy_version INTEGER, media_lifecycle TEXT,
          media_duration_seconds INTEGER, media_protected INTEGER,
          media_received_at INTEGER, media_expires_at INTEGER,
          media_last_checked_at INTEGER, media_consumed_at INTEGER,
          media_expired_at INTEGER, media_cleanup_pending INTEGER,
          read_at TEXT, created_at TEXT, wire_envelope TEXT,
          inbox_stored INTEGER, inbox_retry_payload TEXT,
          retry_attempt_count INTEGER NOT NULL DEFAULT 0,
          next_eligible_at INTEGER,
          notification_display_terminal_event_id TEXT)''');
        await db.execute('''CREATE TABLE message_reactions (
          id TEXT PRIMARY KEY, message_id TEXT NOT NULL, emoji TEXT NOT NULL,
          sender_peer_id TEXT NOT NULL, timestamp TEXT NOT NULL,
          created_at TEXT NOT NULL, removed_at TEXT,
          notification_display_terminal_event_id TEXT,
          UNIQUE(message_id, sender_peer_id))''');
        await db.execute('''CREATE TABLE group_reaction_replay_outbox (
          reaction_id TEXT PRIMARY KEY, group_id TEXT NOT NULL,
          message_id TEXT NOT NULL, sender_peer_id TEXT NOT NULL,
          emoji TEXT NOT NULL, action TEXT NOT NULL,
          inbox_retry_payload TEXT NOT NULL,
          delivery_status TEXT NOT NULL, last_error TEXT,
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''');
        await db.execute('''CREATE TABLE group_notification_display_outbox (
          event_id TEXT PRIMARY KEY, event_kind TEXT NOT NULL,
          group_id TEXT NOT NULL, message_id TEXT NOT NULL,
          actor_peer_id TEXT NOT NULL, event_timestamp TEXT NOT NULL,
          reaction_id TEXT, reaction_action TEXT, reaction_tombstone INTEGER,
          readiness TEXT NOT NULL, revision INTEGER NOT NULL,
          retry_count INTEGER NOT NULL, last_error_code TEXT,
          last_attempt_at TEXT, next_attempt_at TEXT,
          created_at TEXT NOT NULL, updated_at TEXT NOT NULL)''');
        await db.execute('''CREATE TABLE groups (
          id TEXT PRIMARY KEY)''');
        await db.execute('''CREATE TABLE group_keys (
          group_id TEXT NOT NULL, key_generation INTEGER NOT NULL,
          encrypted_key TEXT NOT NULL, created_at TEXT NOT NULL,
          PRIMARY KEY (group_id, key_generation))''');
        await db.execute('''CREATE TABLE media_attachments (
          id TEXT PRIMARY KEY, message_id TEXT NOT NULL)''');
      },
    ),
  );
  addTearDown(db.close);
  await db.insert('groups', <String, Object?>{'id': group.id});
  await db.insert('group_keys', <String, Object?>{
    'group_id': group.id,
    'key_generation': 7,
    'encrypted_key': 'group-key-7',
    'created_at': eventAt,
  });
  var realDbNow = DateTime.utc(2026, 8, 13, 12);
  final realDbEnvelope = await messageEnvelope(
    'real-db-duplicate',
    'stable replay',
  );
  Future<ProtectedGroupContentApplyOutcome> applyToRealDb([
    String? replayEnvelope,
  ]) => handleProtectedGroupContentReplay(
    bridge: bridge,
    groupRepository: groupRepo,
    message: ChatMessage(
      from: senderDevice.transportPeerId,
      to: localDevice.transportPeerId,
      content: replayEnvelope ?? realDbEnvelope,
      timestamp: eventAt,
      isIncoming: true,
    ),
    localLogicalPeerId: local.peerId,
    localTransportPeerId: localDevice.transportPeerId,
    loadAuthority: (_, _) async => authority,
    hasPendingAuthority: (String _) async => false,
    hasTerminal:
        ({required groupId, required payloadType, required contentEventId}) =>
            hasProtectedGroupContentTerminalEvidence(
              groupId: groupId,
              payloadType: payloadType,
              contentEventId: contentEventId,
              loadRows:
                  ({
                    required groupId,
                    required eventType,
                    afterSourceTimestamp,
                    afterSourceEventId,
                    throughSourceTimestamp,
                    required limit,
                  }) => dbLoadGroupEventLogTypePage(
                    db,
                    groupId: groupId,
                    eventType: eventType,
                    afterSourceTimestamp: afterSourceTimestamp,
                    afterSourceEventId: afterSourceEventId,
                    throughSourceTimestamp: throughSourceTimestamp,
                    newestFirst: true,
                    limit: limit,
                  ),
            ),
    commitMessage:
        ({
          required groupId,
          required sourcePeerId,
          required sourceEventId,
          required sourceTimestamp,
          required eventPayload,
          required messageRow,
          required mediaAttachmentRows,
          required incomingMediaCustodyRows,
          readyDisplayOutboxRow,
        }) => dbCommitProtectedGroupMessage(
          db,
          groupId: groupId,
          sourcePeerId: sourcePeerId,
          sourceEventId: sourceEventId,
          sourceTimestamp: sourceTimestamp,
          eventPayload: eventPayload,
          messageRow: messageRow,
          mediaAttachmentRows: mediaAttachmentRows,
          incomingMediaCustodyRows: incomingMediaCustodyRows,
          readyDisplayOutboxRow: readyDisplayOutboxRow,
        ),
    commitReaction:
        ({
          required groupId,
          required sourcePeerId,
          required sourceEventId,
          required sourceTimestamp,
          required eventPayload,
          required reactionRow,
          required transitionId,
          required action,
          readyDisplayOutboxRow,
        }) => dbCommitProtectedGroupReaction(
          db,
          groupId: groupId,
          sourcePeerId: sourcePeerId,
          sourceEventId: sourceEventId,
          sourceTimestamp: sourceTimestamp,
          eventPayload: eventPayload,
          reactionRow: reactionRow,
          transitionId: transitionId,
          action: action,
          readyDisplayOutboxRow: readyDisplayOutboxRow,
        ),
    commitTerminal:
        ({
          required groupId,
          required sourcePeerId,
          required sourceEventId,
          required sourceTimestamp,
          required eventPayload,
        }) => dbCommitProtectedGroupContentTerminal(
          db,
          groupId: groupId,
          sourcePeerId: sourcePeerId,
          sourceEventId: sourceEventId,
          sourceTimestamp: sourceTimestamp,
          eventPayload: eventPayload,
        ),
    resolveReactionTarget: (groupId, messageId) =>
        dbClassifyProtectedGroupReactionTarget(
          db,
          groupId: groupId,
          messageId: messageId,
        ),
    nowUtc: () => realDbNow,
  );
  final firstRealDbApply = await applyToRealDb();
  expect(
    firstRealDbApply.disposition,
    ProtectedGroupContentApplyDisposition.applied,
    reason: '${firstRealDbApply.reasonCode}: ${firstRealDbApply.reasonDetail}',
  );
  realDbNow = realDbNow.add(const Duration(seconds: 1));
  expect(
    (await applyToRealDb()).disposition,
    ProtectedGroupContentApplyDisposition.exactDuplicate,
    reason: 'arrival time cannot conflict with immutable signed projection',
  );
  const mediaCollisionId = 'media-collision';
  await db.insert('group_messages', <String, Object?>{
    'id': mediaCollisionId,
    'group_id': group.id,
    'sender_peer_id': sender.peerId,
    'text': 'ordinary',
    'timestamp': eventAt,
    'is_forwarded': 0,
    'media_policy_version': 0,
    'created_at': eventAt,
  });
  await db.insert('media_attachments', <String, Object?>{
    'id': 'attachment-collision',
    'message_id': mediaCollisionId,
  });
  expect(
    (await applyToRealDb(
      await messageEnvelope(mediaCollisionId, 'ordinary'),
    )).disposition,
    ProtectedGroupContentApplyDisposition.prerequisiteWaiting,
  );
  expect(
    await dbLoadGroupEventLogEntryExact(
      db,
      groupId: group.id,
      sourceEventId: protectedGroupMessageSourceEventId(mediaCollisionId),
    ),
    isNull,
    reason: 'blob-free evidence cannot bless a media-bearing ID collision',
  );
  const legacyTargetId = 'legacy-ordinary-target';
  const legacyReactionAt = '2026-08-13T11:06:00.000000Z';
  await db.insert('group_messages', <String, Object?>{
    'id': legacyTargetId,
    'group_id': group.id,
    'sender_peer_id': local.peerId,
    'text': 'pre-364 ordinary',
    'timestamp': eventAt,
    'is_forwarded': 0,
    'media_policy_version': 0,
    'created_at': eventAt,
  });
  final legacyTransition = buildGroupReactionTransitionId(
    groupId: group.id,
    messageId: legacyTargetId,
    logicalActorPeerId: sender.peerId,
    action: 'add',
    emoji: '👍',
    timestamp: DateTime.parse(legacyReactionAt),
  );
  final legacyReactionEnvelope = await buildGroupOfflineReplayEnvelope(
    bridge: bridge,
    groupRepo: groupRepo,
    groupId: group.id,
    payloadType: groupOfflineReplayPayloadTypeReaction,
    plaintext: jsonEncode(<String, Object?>{
      'id': deterministicGroupReactionStateId(
        groupId: group.id,
        messageId: legacyTargetId,
        logicalActorPeerId: sender.peerId,
      ),
      'messageId': legacyTargetId,
      'emoji': '👍',
      'action': 'add',
      'senderPeerId': sender.peerId,
      'timestamp': legacyReactionAt,
      'eventId': legacyTransition,
    }),
    senderPeerId: sender.peerId,
    senderPublicKey: senderDevice.deviceSigningPublicKey,
    senderPrivateKey: 'sk-sender',
    senderDeviceId: senderDevice.deviceId,
    senderTransportPeerId: senderDevice.transportPeerId,
    recipientPeerIds: const ['transport-local'],
    messageId: legacyTransition,
    contentEventId: legacyTransition,
    contentAuthorityVersion: GroupContentAuthorityVersion(
      eventAt: observed.eventAt,
      eventId: observed.eventId,
      keyEpoch: observed.keyEpoch,
    ),
    reactionNotificationExtension: GroupReactionNotificationExtensionInput(
      transitionId: legacyTransition,
      action: 'add',
      targetMessageId: legacyTargetId,
      reactorPeerId: sender.peerId,
      reactorTransportPeerId: senderDevice.transportPeerId,
      notificationRecipientTransportPeerIds: const ['transport-local'],
    ),
  );
  expect(
    (await applyToRealDb(legacyReactionEnvelope)).disposition,
    ProtectedGroupContentApplyDisposition.applied,
    reason: 'eligible pre-protected ordinary targets remain reaction-capable',
  );
  final eventOne = Map<String, Object?>.from(firstEventPayload!);
  final eventTwo = jsonDecode(jsonEncode(eventOne)) as Map<String, dynamic>;
  eventTwo['contentEventId'] = 'msg-second';
  (eventTwo['payload'] as Map<String, dynamic>)['messageId'] = 'msg-second';
  (eventTwo['payload'] as Map<String, dynamic>)['logicalDeliveryId'] =
      'msg-second';
  const eventTwoAt = '2026-08-13T10:40:00.000000Z';
  (eventTwo['payload'] as Map<String, dynamic>)['timestamp'] = eventTwoAt;
  for (final entry in <(String, Map<String, Object?>, String)>[
    ('msg-collision', eventOne, eventAt),
    ('msg-second', Map<String, Object?>.from(eventTwo), eventTwoAt),
  ]) {
    await dbAppendGroupEventLogEntry(
      db,
      groupId: group.id,
      eventType: protectedGroupMessageEventType,
      sourcePeerId: sender.peerId,
      sourceEventId: protectedGroupMessageSourceEventId(entry.$1),
      sourceTimestamp: entry.$3,
      payload: entry.$2,
    );
    await db.insert('group_messages', <String, Object?>{
      'id': entry.$1,
      'group_id': group.id,
      'sender_peer_id': sender.peerId,
      'timestamp': entry.$3,
    });
  }
  const reactionTargetId = 'reaction-target-before-authority';
  const reactionStateId = 'reaction-state-before-authority';
  const priorReactionAt = '2026-08-13T10:20:00.000000Z';
  const invalidReactionAt = '2026-08-13T11:20:00.000000Z';
  final priorTransition = buildGroupReactionTransitionId(
    groupId: group.id,
    messageId: reactionTargetId,
    logicalActorPeerId: sender.peerId,
    action: 'add',
    emoji: '👍',
    timestamp: DateTime.parse(priorReactionAt),
  );
  final invalidTransition = buildGroupReactionTransitionId(
    groupId: group.id,
    messageId: reactionTargetId,
    logicalActorPeerId: sender.peerId,
    action: 'add',
    emoji: '❤️',
    timestamp: DateTime.parse(invalidReactionAt),
  );
  Map<String, Object?> protectedReactionPayload({
    required String transitionId,
    required String emoji,
    required String timestamp,
  }) => <String, Object?>{
    'custodyKind': groupContentCustodyKind,
    'groupId': group.id,
    'payloadType': groupOfflineReplayPayloadTypeReaction,
    'contentEventId': transitionId,
    'authorityEventAt': fixedGroupContentUtc(observed.eventAt),
    'authorityEventId': observed.eventId,
    'authorityKeyEpoch': observed.keyEpoch,
    'logicalSenderPeerId': sender.peerId,
    'senderDeviceId': senderDevice.deviceId,
    'senderTransportPeerId': senderDevice.transportPeerId,
    'senderPublicKey': senderDevice.deviceSigningPublicKey,
    'recipientPeerIds': const <String>['transport-local'],
    'payload': <String, Object?>{
      'id': reactionStateId,
      'messageId': reactionTargetId,
      'emoji': emoji,
      'action': 'add',
      'senderPeerId': sender.peerId,
      'timestamp': timestamp,
      'eventId': transitionId,
    },
  };
  Map<String, Object?> reactionRow({
    required String emoji,
    required String timestamp,
  }) => <String, Object?>{
    'id': reactionStateId,
    'message_id': reactionTargetId,
    'emoji': emoji,
    'sender_peer_id': sender.peerId,
    'timestamp': timestamp,
    'created_at': timestamp,
  };
  Map<String, Object?> displayRow({
    required String transitionId,
    required String timestamp,
  }) => <String, Object?>{
    'event_id': transitionId,
    'event_kind': 'reaction',
    'group_id': group.id,
    'message_id': reactionTargetId,
    'actor_peer_id': sender.peerId,
    'event_timestamp': timestamp,
    'reaction_id': reactionStateId,
    'reaction_action': 'add',
    'reaction_tombstone': 0,
    'readiness': 'ready',
    'revision': 1,
    'retry_count': 0,
    'last_error_code': null,
    'last_attempt_at': null,
    'next_attempt_at': null,
    'created_at': timestamp,
    'updated_at': timestamp,
  };
  await db.insert('group_messages', <String, Object?>{
    'id': reactionTargetId,
    'group_id': group.id,
    'sender_peer_id': local.peerId,
    'text': 'ordinary reaction target',
    'timestamp': '2026-08-13T10:10:00.000000Z',
    'is_forwarded': 0,
    'media_policy_version': 0,
  });
  expect(
    await dbCommitProtectedGroupReaction(
      db,
      groupId: group.id,
      sourcePeerId: sender.peerId,
      sourceEventId: protectedGroupReactionSourceEventId(priorTransition),
      sourceTimestamp: priorReactionAt,
      eventPayload: protectedReactionPayload(
        transitionId: priorTransition,
        emoji: '👍',
        timestamp: priorReactionAt,
      ),
      reactionRow: reactionRow(emoji: '👍', timestamp: priorReactionAt),
      transitionId: priorTransition,
      action: 'add',
      readyDisplayOutboxRow: displayRow(
        transitionId: priorTransition,
        timestamp: priorReactionAt,
      ),
    ),
    DbProtectedGroupContentCommitResult.applied,
  );
  for (var index = 0; index < 201; index++) {
    final noise = protectedReactionPayload(
      transitionId: 'noise-transition-$index',
      emoji: '🫧',
      timestamp: '2026-08-13T10:25:00.000000Z',
    );
    noise['contentEventId'] = 'noise-transition-$index';
    (noise['payload'] as Map<String, Object?>)['messageId'] =
        'noise-target-$index';
    (noise['payload'] as Map<String, Object?>)['eventId'] =
        'noise-transition-$index';
    await dbAppendGroupEventLogEntry(
      db,
      groupId: group.id,
      eventType: protectedGroupReactionEventType,
      sourcePeerId: sender.peerId,
      sourceEventId: 'pr1:noise-transition-$index',
      sourceTimestamp: '2026-08-13T10:25:00.000000Z',
      payload: noise,
    );
  }
  expect(
    await dbCommitProtectedGroupReaction(
      db,
      groupId: group.id,
      sourcePeerId: sender.peerId,
      sourceEventId: protectedGroupReactionSourceEventId(invalidTransition),
      sourceTimestamp: invalidReactionAt,
      eventPayload: protectedReactionPayload(
        transitionId: invalidTransition,
        emoji: '❤️',
        timestamp: invalidReactionAt,
      ),
      reactionRow: reactionRow(emoji: '❤️', timestamp: invalidReactionAt),
      transitionId: invalidTransition,
      action: 'add',
      readyDisplayOutboxRow: displayRow(
        transitionId: invalidTransition,
        timestamp: invalidReactionAt,
      ),
    ),
    DbProtectedGroupContentCommitResult.applied,
  );
  expect(
    await dbCompleteGroupNotificationDisplayOutboxEntryIfExact(
      db,
      eventId: priorTransition,
      expectedRevision: 1,
      expectedEventKind: 'reaction',
      expectedGroupId: group.id,
      expectedMessageId: reactionTargetId,
      expectedActorPeerId: sender.peerId,
      expectedEventTimestamp: priorReactionAt,
      expectedReactionId: reactionStateId,
      expectedReactionAction: 'add',
      expectedReactionTombstone: false,
      completedAt: '2026-08-13T10:30:00.000000Z',
    ),
    isFalse,
    reason:
        'stale A cannot overwrite terminal authority after canonical state advanced to B',
  );
  expect(
    await dbLoadGroupNotificationDisplayOutboxEntry(db, priorTransition),
    isNotNull,
    reason: 'a refused zero-row terminal write retains exact display custody',
  );
  expect(
    await dbRetireGroupNotificationDisplayOutboxEntryIfExact(
      db,
      eventId: priorTransition,
      expectedRevision: 1,
      expectedEventKind: 'reaction',
      expectedGroupId: group.id,
      expectedMessageId: reactionTargetId,
      expectedActorPeerId: sender.peerId,
      expectedEventTimestamp: priorReactionAt,
      expectedReactionId: reactionStateId,
      expectedReactionAction: 'add',
      expectedReactionTombstone: false,
    ),
    isTrue,
    reason: 'the stale coordinator path retires exact custody without outcome',
  );
  expect(
    await dbLoadGroupNotificationDisplayOutboxEntry(db, priorTransition),
    isNull,
  );
  await groupRepo.saveGroup(
    group.copyWith(
      isDissolved: true,
      dissolvedAt: DateTime.utc(2026, 8, 13, 10, 30),
      dissolvedBy: 'peer-sender',
    ),
  );
  final later = AuthenticatedGroupAuthorityProof(
    eventId: 'authority-dissolved',
    groupId: group.id,
    eventAt: DateTime.utc(2026, 8, 13, 10, 30),
    keyEpoch: 7,
    control: 'group_dissolved',
    actorAccountPeerId: sender.peerId,
    actorAccountPublicKey: 'pk-sender',
    senderTransportPeerId: senderDevice.transportPeerId,
    senderTransportPublicKey: 'pk-sender',
    authorityData: const <String, Object?>{},
    signature: 'fake-signature',
  );
  final databaseReadingGroupRepo = _DatabaseReadingGroupRepository(db);
  await databaseReadingGroupRepo.saveGroup(
    group.copyWith(
      isDissolved: true,
      dissolvedAt: later.eventAt,
      dissolvedBy: sender.peerId,
    ),
  );
  await databaseReadingGroupRepo.saveKey(
    GroupKeyInfo(
      groupId: group.id,
      keyGeneration: 7,
      encryptedKey: 'group-key-7',
      createdAt: group.createdAt,
    ),
  );
  Future<bool> validateHistoricalAuthority({
    required String groupId,
    required String payloadType,
    required String contentEventId,
    required DateTime eventAt,
    required GroupContentAuthorityVersion authorityVersion,
    required String logicalSenderPeerId,
    required String senderDeviceId,
    required String senderTransportPeerId,
    required String senderPublicKey,
  }) async => true;
  expect(
    await reconcileProtectedGroupContentForAuthority(
      db: db,
      groupRepository: databaseReadingGroupRepo,
      authority: later,
      validateHistoricalAuthority: validateHistoricalAuthority,
      pageSize: 1,
      stopAfterCommittedPages: 2,
    ).timeout(const Duration(seconds: 2)),
    isFalse,
    reason:
        'a two-page crash leaves timestamp-ordered frontiers even when sequence decreases',
  );
  expect(
    await dbLoadGroupEventLogEntryExact(
      db,
      groupId: group.id,
      sourceEventId: protectedGroupContentReconciliationCompleteSourceEventId(
        later.eventId,
      ),
    ),
    isNull,
  );
  expect(
    await reconcileProtectedGroupContentForAuthority(
      db: db,
      groupRepository: databaseReadingGroupRepo,
      authority: later,
      validateHistoricalAuthority: validateHistoricalAuthority,
      pageSize: 1,
    ).timeout(const Duration(seconds: 2)),
    isTrue,
  );
  expect(databaseReadingGroupRepo.authorityProjectionReads, 4);
  final rows = await db.query('group_messages');
  expect(
    rows.map((row) => row['id']),
    allOf(
      containsAll(<Object?>[
        mediaCollisionId,
        legacyTargetId,
        reactionTargetId,
      ]),
      isNot(contains('msg-collision')),
      isNot(contains('msg-second')),
    ),
  );
  final restoredReaction = (await db.query('message_reactions')).single;
  expect(restoredReaction['emoji'], '👍');
  expect(restoredReaction['removed_at'], isNull);
  expect(
    restoredReaction['notification_display_terminal_event_id'],
    isNull,
    reason:
        'history rollback does not synthesize terminal display authority for stale A',
  );
  final retainedDisplayRows = await db.query(
    'group_notification_display_outbox',
  );
  expect(
    retainedDisplayRows,
    hasLength(1),
    reason:
        'protected cleanup retains only correlation-bound READY custody for the retired canonical reaction',
  );
  expect(
    retainedDisplayRows.single,
    allOf(<Object>[
      containsPair('event_id', invalidTransition),
      containsPair('event_kind', 'reaction'),
      containsPair('group_id', group.id),
      containsPair('message_id', reactionTargetId),
      containsPair('actor_peer_id', sender.peerId),
      containsPair('event_timestamp', invalidReactionAt),
      containsPair('reaction_id', reactionStateId),
      containsPair('reaction_action', 'add'),
      containsPair('reaction_tombstone', 0),
      containsPair('readiness', 'ready'),
      containsPair('revision', 2),
      containsPair('retry_count', 0),
      containsPair('last_error_code', 'state_unavailable'),
      containsPair(
        'last_attempt_at',
        kGroupNotificationDisplayCanonicalRetiredMarker,
      ),
      containsPair('next_attempt_at', null),
    ]),
  );
  expect(
    await dbLoadGroupNotificationDisplayOutboxEntry(db, priorTransition),
    isNull,
    reason: 'the earlier reaction lane remains exactly retired',
  );
  final queryPlan = await db.rawQuery(
    'EXPLAIN QUERY PLAN '
    'SELECT * FROM group_event_log INDEXED BY idx_group_event_log_event_type '
    'WHERE group_id = ? AND event_type IN (?, ?, ?) '
    'AND source_timestamp >= ? AND sequence <= ? '
    'ORDER BY source_timestamp ASC, source_event_id ASC LIMIT ?',
    <Object?>[
      group.id,
      protectedGroupMessageEventType,
      protectedGroupReactionEventType,
      protectedGroupContentPreparedEventType,
      fixedGroupContentUtc(later.eventAt),
      100000,
      1,
    ],
  );
  expect(
    queryPlan.map((row) => row['detail'].toString()),
    anyElement(contains('idx_group_event_log_event_type')),
    reason: 'authority reconciliation must seek the timestamp/type index',
  );
  final complete = await dbLoadGroupEventLogEntryExact(
    db,
    groupId: group.id,
    sourceEventId: protectedGroupContentReconciliationCompleteSourceEventId(
      later.eventId,
    ),
  );
  expect(
    isProtectedGroupContentReconciliationCompleteRow(
      complete,
      authority: later,
    ),
    isTrue,
    reason:
        'retained canonical-retired display custody does not reopen protected reconciliation',
  );
  final afterInitialComplete = await db.query(
    'group_event_log',
    where: 'group_id = ?',
    whereArgs: <Object?>[group.id],
  );
  final lateAfterComplete = Map<String, Object?>.from(eventOne)
    ..['contentEventId'] = 'late-after-complete';
  lateAfterComplete['payload'] = Map<String, Object?>.from(
    lateAfterComplete['payload'] as Map,
  );
  (lateAfterComplete['payload'] as Map<String, Object?>)['messageId'] =
      'late-after-complete';
  (lateAfterComplete['payload'] as Map<String, Object?>)['logicalDeliveryId'] =
      'late-after-complete';
  await dbAppendGroupEventLogEntry(
    db,
    groupId: group.id,
    eventType: protectedGroupMessageEventType,
    sourcePeerId: sender.peerId,
    sourceEventId: protectedGroupMessageSourceEventId('late-after-complete'),
    sourceTimestamp: eventAt,
    payload: lateAfterComplete,
  );
  final lateProjection =
      Map<String, Object?>.from(
          (await dbLoadGroupMessage(db, reactionTargetId))!,
        )
        ..['id'] = 'late-after-complete'
        ..['sender_peer_id'] = sender.peerId
        ..['timestamp'] = eventAt;
  await db.insert('group_messages', lateProjection);
  expect(
    await reconcileProtectedGroupContentForAuthority(
      db: db,
      groupRepository: groupRepo,
      authority: later,
      validateHistoricalAuthority: validateHistoricalAuthority,
      pageSize: 1,
    ),
    isTrue,
    reason:
        'an exact COMPLETE makes duplicate authority reconciliation a no-op',
  );
  expect(
    await db.query(
      'group_event_log',
      where: 'group_id = ?',
      whereArgs: <Object?>[group.id],
    ),
    hasLength(afterInitialComplete.length + 1),
  );
  expect(
    await dbLoadGroupMessage(db, 'late-after-complete'),
    isNotNull,
    reason: 'duplicate COMPLETE never widens its frozen prefix',
  );
  expect(
    await reconcileProtectedGroupContentForAuthority(
      db: db,
      groupRepository: groupRepo,
      authority: AuthenticatedGroupAuthorityProof(
        eventId: 'authority-unrelated-member-change',
        groupId: group.id,
        eventAt: DateTime.utc(2026, 8, 13, 10, 45),
        keyEpoch: 7,
        control: 'member_role_changed',
        actorAccountPeerId: sender.peerId,
        actorAccountPublicKey: 'pk-sender',
        senderTransportPeerId: senderDevice.transportPeerId,
        senderTransportPublicKey: 'pk-sender',
        authorityData: const <String, Object?>{},
        signature: 'fake-signature',
      ),
      validateHistoricalAuthority: validateHistoricalAuthority,
      pageSize: 1,
    ),
    isTrue,
    reason:
        'any intervening authenticated authority invalidates stale-observed content',
  );
  expect(
    await dbLoadGroupMessage(db, 'late-after-complete'),
    isNull,
    reason:
        'reconciliation mirrors authority-first receive even when sender role remains valid',
  );

  final newerPrepared = later;
  final olderPrepared = AuthenticatedGroupAuthorityProof(
    eventId: 'authority-older-unfinished',
    groupId: group.id,
    eventAt: DateTime.utc(2026, 8, 13, 10, 15),
    keyEpoch: 7,
    control: 'member_removed',
    actorAccountPeerId: sender.peerId,
    actorAccountPublicKey: 'pk-sender',
    senderTransportPeerId: senderDevice.transportPeerId,
    senderTransportPublicKey: 'pk-sender',
    authorityData: const <String, Object?>{},
    signature: 'fake-signature',
  );
  var olderAborted = false;
  var newerAbortedConflict = false;
  var newerReconciliationAvailable = true;
  var completedAuthorityRepairs = 0;
  Future<List<AuthenticatedGroupAuthorityProof>> preparedPage({
    String? afterSourceTimestamp,
    String? afterSourceEventId,
    required int limit,
  }) async {
    if (afterSourceEventId == null) return [newerPrepared];
    if (afterSourceEventId ==
        authenticatedGroupAuthoritySourceEventId(
          AuthenticatedGroupAuthorityPhase.prepared,
          newerPrepared.eventId,
        )) {
      return [olderPrepared];
    }
    return const [];
  }

  Future<AuthenticatedGroupAuthorityProof?> exactPhase({
    required AuthenticatedGroupAuthorityPhase phase,
    required String eventId,
  }) async {
    if (eventId == newerPrepared.eventId &&
        phase == AuthenticatedGroupAuthorityPhase.complete) {
      return newerPrepared;
    }
    if (eventId == newerPrepared.eventId &&
        phase == AuthenticatedGroupAuthorityPhase.aborted &&
        newerAbortedConflict) {
      return newerPrepared;
    }
    if (eventId == olderPrepared.eventId &&
        phase == AuthenticatedGroupAuthorityPhase.aborted &&
        olderAborted) {
      return olderPrepared;
    }
    return null;
  }

  Future<Map<String, Object?>?> reconciliationRow(
    String authorityEventId,
  ) async {
    if (authorityEventId != newerPrepared.eventId ||
        !newerReconciliationAvailable) {
      return null;
    }
    return <String, Object?>{
      'group_id': group.id,
      'event_type': protectedGroupContentTerminalEventType,
      'source_peer_id': newerPrepared.actorAccountPeerId,
      'source_event_id':
          protectedGroupContentReconciliationCompleteSourceEventId(
            newerPrepared.eventId,
          ),
      'source_timestamp': fixedGroupContentUtc(newerPrepared.eventAt),
      'canonical_payload': jsonEncode(<String, Object?>{
        'reasonCode': 'authority_reconciliation_complete',
        'groupId': group.id,
        'authorityEventId': newerPrepared.eventId,
        'authorityEventAt': fixedGroupContentUtc(newerPrepared.eventAt),
        'authorityKeyEpoch': newerPrepared.keyEpoch,
        'upperSequence': 0,
        'lastProcessedSequence': 0,
        'lastSourceTimestamp': null,
        'lastSourceEventId': null,
        'complete': true,
      }),
    };
  }

  expect(
    await hasPendingProtectedGroupContentAuthority(
      groupId: group.id,
      loadPreparedPage: preparedPage,
      loadExactPhase: exactPhase,
      loadReconciliationRow: reconciliationRow,
      pageSize: 1,
    ),
    isTrue,
    reason: 'a newer complete transition cannot hide older unfinished work',
  );
  olderAborted = true;
  expect(
    await hasPendingProtectedGroupContentAuthority(
      groupId: group.id,
      loadPreparedPage: preparedPage,
      loadExactPhase: exactPhase,
      loadReconciliationRow: reconciliationRow,
      pageSize: 1,
    ),
    isFalse,
  );
  newerReconciliationAvailable = false;
  expect(
    await hasPendingProtectedGroupContentAuthority(
      groupId: group.id,
      loadPreparedPage: preparedPage,
      loadExactPhase: exactPhase,
      loadReconciliationRow: reconciliationRow,
      repairCompletedAuthority: (completed) async {
        expect(completed.eventId, newerPrepared.eventId);
        completedAuthorityRepairs++;
        newerReconciliationAvailable = true;
        return true;
      },
      pageSize: 1,
    ),
    isFalse,
    reason:
        'upgrade/startup history repairs a COMPLETE authority before exposing content',
  );
  expect(completedAuthorityRepairs, 1);
  newerAbortedConflict = true;
  expect(
    await hasPendingProtectedGroupContentAuthority(
      groupId: group.id,
      loadPreparedPage: preparedPage,
      loadExactPhase: exactPhase,
      loadReconciliationRow: reconciliationRow,
      pageSize: 1,
    ),
    isTrue,
    reason:
        'one authority cannot be authenticated as both COMPLETE and ABORTED',
  );
  newerAbortedConflict = false;

  final retryTransition = AuthenticatedGroupAuthorityProof(
    eventId: 'authority-during-retry',
    groupId: group.id,
    eventAt: DateTime.utc(2026, 8, 13, 10, 50),
    keyEpoch: 7,
    control: 'member_config',
    actorAccountPeerId: sender.peerId,
    actorAccountPublicKey: sender.publicKey!,
    senderTransportPeerId: senderDevice.transportPeerId,
    senderTransportPublicKey: senderDevice.deviceSigningPublicKey,
    authorityData: const <String, Object?>{},
    signature: 'fake-signature',
  );
  var retryTransitionComplete = false;
  var retryTransitionReconciled = false;
  var retryTransitionAborted = false;
  Future<ProtectedGroupContentRetryAuthorityDisposition> classifyRetry(
    DateTime contentAt,
  ) => classifyProtectedGroupContentRetryAuthority(
    groupId: group.id,
    observedAuthority: GroupContentAuthorityVersion(
      eventAt: observed.eventAt,
      eventId: observed.eventId,
      keyEpoch: observed.keyEpoch,
    ),
    contentAt: contentAt,
    contentEventId: 'retry-content',
    loadPreparedPage:
        ({afterSourceTimestamp, afterSourceEventId, required limit}) async =>
            afterSourceEventId == null
            ? <AuthenticatedGroupAuthorityProof>[retryTransition]
            : const <AuthenticatedGroupAuthorityProof>[],
    loadExactPhase: ({required phase, required eventId}) async {
      if (eventId == observed.eventId &&
          phase == AuthenticatedGroupAuthorityPhase.genesis) {
        return observed;
      }
      if (eventId == retryTransition.eventId &&
          phase == AuthenticatedGroupAuthorityPhase.complete &&
          retryTransitionComplete) {
        return retryTransition;
      }
      if (eventId == retryTransition.eventId &&
          phase == AuthenticatedGroupAuthorityPhase.aborted &&
          retryTransitionAborted) {
        return retryTransition;
      }
      return null;
    },
    loadReconciliationRow: (_) async => retryTransitionReconciled
        ? <String, Object?>{
            'group_id': group.id,
            'event_type': protectedGroupContentTerminalEventType,
            'source_peer_id': retryTransition.actorAccountPeerId,
            'source_event_id':
                protectedGroupContentReconciliationCompleteSourceEventId(
                  retryTransition.eventId,
                ),
            'source_timestamp': fixedGroupContentUtc(retryTransition.eventAt),
            'canonical_payload': jsonEncode(<String, Object?>{
              'reasonCode': 'authority_reconciliation_complete',
              'groupId': group.id,
              'authorityEventId': retryTransition.eventId,
              'authorityEventAt': fixedGroupContentUtc(retryTransition.eventAt),
              'authorityKeyEpoch': retryTransition.keyEpoch,
              'upperSequence': 0,
              'lastProcessedSequence': 0,
              'lastSourceTimestamp': null,
              'lastSourceEventId': null,
              'complete': true,
            }),
          }
        : null,
    pageSize: 1,
  );
  expect(
    await classifyRetry(DateTime.utc(2026, 8, 13, 11)),
    ProtectedGroupContentRetryAuthorityDisposition.prerequisiteWaiting,
    reason: 'an unfinished PREPARED pauses retry without terminalizing owner A',
  );
  retryTransitionComplete = true;
  expect(
    await classifyRetry(DateTime.utc(2026, 8, 13, 11)),
    ProtectedGroupContentRetryAuthorityDisposition.prerequisiteWaiting,
    reason: 'COMPLETE is not settled until exact content reconciliation exists',
  );
  retryTransitionReconciled = true;
  expect(
    await classifyRetry(DateTime.utc(2026, 8, 13, 11)),
    ProtectedGroupContentRetryAuthorityDisposition.stale,
    reason: 'only a settled authority between observed A and content is stale',
  );
  expect(
    await classifyRetry(DateTime.utc(2026, 8, 13, 10, 40)),
    ProtectedGroupContentRetryAuthorityDisposition.eligible,
    reason: 'a later settled authority does not invalidate prior valid content',
  );
  retryTransitionAborted = true;
  expect(
    await classifyRetry(DateTime.utc(2026, 8, 13, 11)),
    ProtectedGroupContentRetryAuthorityDisposition.failClosed,
    reason: 'conflicting authenticated terminal phases fail closed',
  );
  retryTransitionAborted = false;
  final newestUnfinished = AuthenticatedGroupAuthorityProof(
    eventId: 'authority-newest-unfinished',
    groupId: group.id,
    eventAt: DateTime.utc(2026, 8, 13, 10, 55),
    keyEpoch: 7,
    control: 'device_announce',
    actorAccountPeerId: sender.peerId,
    actorAccountPublicKey: sender.publicKey!,
    senderTransportPeerId: senderDevice.transportPeerId,
    senderTransportPublicKey: senderDevice.deviceSigningPublicKey,
    authorityData: const <String, Object?>{},
    signature: 'fake-signature',
  );
  expect(
    await classifyProtectedGroupContentRetryAuthority(
      groupId: group.id,
      observedAuthority: GroupContentAuthorityVersion(
        eventAt: observed.eventAt,
        eventId: observed.eventId,
        keyEpoch: observed.keyEpoch,
      ),
      contentAt: DateTime.utc(2026, 8, 13, 11),
      contentEventId: 'retry-content',
      loadPreparedPage:
          ({afterSourceTimestamp, afterSourceEventId, required limit}) async {
            if (afterSourceEventId == null) return [newestUnfinished];
            if (afterSourceEventId ==
                authenticatedGroupAuthoritySourceEventId(
                  AuthenticatedGroupAuthorityPhase.prepared,
                  newestUnfinished.eventId,
                )) {
              return [retryTransition];
            }
            return const <AuthenticatedGroupAuthorityProof>[];
          },
      loadExactPhase: ({required phase, required eventId}) async {
        if (eventId == observed.eventId &&
            phase == AuthenticatedGroupAuthorityPhase.genesis) {
          return observed;
        }
        if (eventId == retryTransition.eventId &&
            phase == AuthenticatedGroupAuthorityPhase.complete) {
          return retryTransition;
        }
        return null;
      },
      loadReconciliationRow: (eventId) async =>
          eventId == retryTransition.eventId
          ? <String, Object?>{
              'group_id': group.id,
              'event_type': protectedGroupContentTerminalEventType,
              'source_peer_id': retryTransition.actorAccountPeerId,
              'source_event_id':
                  protectedGroupContentReconciliationCompleteSourceEventId(
                    retryTransition.eventId,
                  ),
              'source_timestamp': fixedGroupContentUtc(retryTransition.eventAt),
              'canonical_payload': jsonEncode(<String, Object?>{
                'reasonCode': 'authority_reconciliation_complete',
                'groupId': group.id,
                'authorityEventId': retryTransition.eventId,
                'authorityEventAt': fixedGroupContentUtc(
                  retryTransition.eventAt,
                ),
                'authorityKeyEpoch': retryTransition.keyEpoch,
                'upperSequence': 0,
                'lastProcessedSequence': 0,
                'lastSourceTimestamp': null,
                'lastSourceEventId': null,
                'complete': true,
              }),
            }
          : null,
      pageSize: 1,
    ),
    ProtectedGroupContentRetryAuthorityDisposition.stale,
    reason:
        'older settled B outranks newer unfinished C across newest-first pages',
  );

  final epochZeroGroup = group.copyWith(id: 'group-epoch-zero');
  await groupRepo.saveGroup(epochZeroGroup);
  await groupRepo.saveKey(
    GroupKeyInfo(
      groupId: epochZeroGroup.id,
      keyGeneration: 0,
      encryptedKey: 'epoch-zero-key',
      createdAt: epochZeroGroup.createdAt,
    ),
  );
  await db.insert('groups', <String, Object?>{'id': epochZeroGroup.id});
  await db.insert('group_keys', <String, Object?>{
    'group_id': epochZeroGroup.id,
    'key_generation': 0,
    'encrypted_key': 'epoch-zero-key',
    'created_at': eventAt,
  });
  final epochZeroAuthority = AuthenticatedGroupAuthorityProof(
    eventId: 'authority-epoch-zero',
    groupId: epochZeroGroup.id,
    eventAt: DateTime.utc(2026, 8, 13, 13),
    keyEpoch: 0,
    control: 'bootstrap_genesis',
    actorAccountPeerId: sender.peerId,
    actorAccountPublicKey: sender.publicKey!,
    senderTransportPeerId: senderDevice.transportPeerId,
    senderTransportPublicKey: senderDevice.deviceSigningPublicKey,
    authorityData: const <String, Object?>{},
    signature: 'fake-signature',
  );
  expect(
    AuthenticatedGroupAuthorityProof.tryParse(epochZeroAuthority.toMap()),
    isNotNull,
    reason: 'epoch zero is a canonical initial authority version',
  );
  expect(
    await reconcileProtectedGroupContentForAuthority(
      db: db,
      groupRepository: groupRepo,
      authority: epochZeroAuthority,
      validateHistoricalAuthority: validateHistoricalAuthority,
    ),
    isTrue,
  );
  expect(
    await dbLoadGroupEventLogEntryExact(
      db,
      groupId: epochZeroGroup.id,
      sourceEventId: protectedGroupContentReconciliationCompleteSourceEventId(
        epochZeroAuthority.eventId,
      ),
    ),
    isNotNull,
  );

  final upgradedGroup = group.copyWith(id: 'group-upgrade-backfill');
  await groupRepo.saveGroup(upgradedGroup);
  for (final epoch in <int>[7, 8]) {
    await groupRepo.saveKey(
      GroupKeyInfo(
        groupId: upgradedGroup.id,
        keyGeneration: epoch,
        encryptedKey: 'upgrade-key-$epoch',
        createdAt: upgradedGroup.createdAt,
      ),
    );
  }
  await db.insert('groups', <String, Object?>{'id': upgradedGroup.id});
  for (final epoch in <int>[7, 8]) {
    await db.insert('group_keys', <String, Object?>{
      'group_id': upgradedGroup.id,
      'key_generation': epoch,
      'encrypted_key': 'upgrade-key-$epoch',
      'created_at': eventAt,
    });
  }
  final preUpgradeAuthority = AuthenticatedGroupAuthorityProof(
    eventId: 'authority-before-upgrade',
    groupId: upgradedGroup.id,
    eventAt: DateTime.utc(2026, 8, 13, 12, 30),
    keyEpoch: 7,
    control: 'member_role_updated',
    actorAccountPeerId: sender.peerId,
    actorAccountPublicKey: sender.publicKey!,
    senderTransportPeerId: senderDevice.transportPeerId,
    senderTransportPublicKey: senderDevice.deviceSigningPublicKey,
    authorityData: const <String, Object?>{},
    signature: 'fake-signature',
  );
  expect(
    await reconcileProtectedGroupContentForAuthority(
      db: db,
      groupRepository: groupRepo,
      authority: preUpgradeAuthority,
      validateHistoricalAuthority: validateHistoricalAuthority,
    ),
    isFalse,
    reason: 'a live receive transition still requires its exact key projection',
  );
  expect(
    await reconcileProtectedGroupContentForAuthority(
      db: db,
      groupRepository: groupRepo,
      authority: preUpgradeAuthority,
      validateHistoricalAuthority: validateHistoricalAuthority,
      allowDominatingProjection: true,
    ),
    isTrue,
    reason:
        'startup backfill accepts a later authenticated key projection without failing open',
  );

  final chainGroup = GroupModel(
    id: 'group-reaction-chain',
    name: 'Reaction chain',
    type: GroupType.chat,
    topicName: 'unused-topic-chain',
    createdAt: group.createdAt,
    createdBy: sender.peerId,
    myRole: GroupRole.member,
  );
  await groupRepo.saveGroup(chainGroup);
  await groupRepo.saveKey(
    GroupKeyInfo(
      groupId: chainGroup.id,
      keyGeneration: 7,
      encryptedKey: 'chain-key',
      createdAt: chainGroup.createdAt,
    ),
  );
  await db.insert('groups', <String, Object?>{'id': chainGroup.id});
  await db.insert('group_keys', <String, Object?>{
    'group_id': chainGroup.id,
    'key_generation': 7,
    'encrypted_key': 'chain-key',
    'created_at': eventAt,
  });
  const chainTarget = 'chain-target';
  await db.insert('group_messages', <String, Object?>{
    'id': chainTarget,
    'group_id': chainGroup.id,
    'sender_peer_id': local.peerId,
    'text': 'ordinary reaction target',
    'timestamp': '2026-08-13T10:05:00.000000Z',
    'is_forwarded': 0,
    'media_policy_version': 0,
  });
  const chainState = 'chain-reaction-state';
  const chainAAt = '2026-08-13T10:20:00.000000Z';
  const chainBAt = '2026-08-13T10:40:00.000000Z';
  final chainA = buildGroupReactionTransitionId(
    groupId: chainGroup.id,
    messageId: chainTarget,
    logicalActorPeerId: sender.peerId,
    action: 'add',
    emoji: 'A',
    timestamp: DateTime.parse(chainAAt),
  );
  final authorityX = AuthenticatedGroupAuthorityProof(
    eventId: 'chain-authority-x',
    groupId: chainGroup.id,
    eventAt: DateTime.utc(2026, 8, 13, 10, 15),
    keyEpoch: 7,
    control: 'member_metadata_changed',
    actorAccountPeerId: sender.peerId,
    actorAccountPublicKey: sender.publicKey!,
    senderTransportPeerId: senderDevice.transportPeerId,
    senderTransportPublicKey: senderDevice.deviceSigningPublicKey,
    authorityData: const <String, Object?>{},
    signature: 'fake-signature',
  );
  Map<String, Object?> chainPayload({
    required String transition,
    required String emoji,
    required String timestamp,
    required AuthenticatedGroupAuthorityProof observedAuthority,
  }) => <String, Object?>{
    'custodyKind': groupContentCustodyKind,
    'groupId': chainGroup.id,
    'payloadType': groupOfflineReplayPayloadTypeReaction,
    'contentEventId': transition,
    'authorityEventAt': fixedGroupContentUtc(observedAuthority.eventAt),
    'authorityEventId': observedAuthority.eventId,
    'authorityKeyEpoch': observedAuthority.keyEpoch,
    'logicalSenderPeerId': sender.peerId,
    'senderDeviceId': senderDevice.deviceId,
    'senderTransportPeerId': senderDevice.transportPeerId,
    'senderPublicKey': senderDevice.deviceSigningPublicKey,
    'recipientPeerIds': const <String>['transport-local'],
    'payload': <String, Object?>{
      'id': chainState,
      'messageId': chainTarget,
      'emoji': emoji,
      'action': 'add',
      'senderPeerId': sender.peerId,
      'timestamp': timestamp,
      'eventId': transition,
    },
  };
  Map<String, Object?> chainRow(String emoji, String timestamp) =>
      <String, Object?>{
        'id': chainState,
        'message_id': chainTarget,
        'emoji': emoji,
        'sender_peer_id': sender.peerId,
        'timestamp': timestamp,
        'created_at': timestamp,
      };
  expect(
    await dbCommitProtectedGroupReaction(
      db,
      groupId: chainGroup.id,
      sourcePeerId: sender.peerId,
      sourceEventId: protectedGroupReactionSourceEventId(chainA),
      sourceTimestamp: chainAAt,
      eventPayload: chainPayload(
        transition: chainA,
        emoji: 'A',
        timestamp: chainAAt,
        observedAuthority: observed,
      ),
      reactionRow: chainRow('A', chainAAt),
      transitionId: chainA,
      action: 'add',
    ),
    DbProtectedGroupContentCommitResult.applied,
  );
  expect(
    await reconcileProtectedGroupContentForAuthority(
      db: db,
      groupRepository: groupRepo,
      authority: authorityX,
      validateHistoricalAuthority: validateHistoricalAuthority,
      pageSize: 1,
    ),
    isTrue,
  );
  expect(
    await dbLoadActiveOrTombstonedReactionForSender(
      db,
      chainTarget,
      sender.peerId,
    ),
    isNull,
  );
  final chainB = buildGroupReactionTransitionId(
    groupId: chainGroup.id,
    messageId: chainTarget,
    logicalActorPeerId: sender.peerId,
    action: 'add',
    emoji: 'B',
    timestamp: DateTime.parse(chainBAt),
  );
  expect(
    await dbCommitProtectedGroupReaction(
      db,
      groupId: chainGroup.id,
      sourcePeerId: sender.peerId,
      sourceEventId: protectedGroupReactionSourceEventId(chainB),
      sourceTimestamp: chainBAt,
      eventPayload: chainPayload(
        transition: chainB,
        emoji: 'B',
        timestamp: chainBAt,
        observedAuthority: authorityX,
      ),
      reactionRow: chainRow('B', chainBAt),
      transitionId: chainB,
      action: 'add',
    ),
    DbProtectedGroupContentCommitResult.applied,
  );
  final authorityY = AuthenticatedGroupAuthorityProof(
    eventId: 'chain-authority-y',
    groupId: chainGroup.id,
    eventAt: DateTime.utc(2026, 8, 13, 10, 30),
    keyEpoch: 7,
    control: 'group_metadata_changed',
    actorAccountPeerId: sender.peerId,
    actorAccountPublicKey: sender.publicKey!,
    senderTransportPeerId: senderDevice.transportPeerId,
    senderTransportPublicKey: senderDevice.deviceSigningPublicKey,
    authorityData: const <String, Object?>{},
    signature: 'fake-signature',
  );
  expect(
    await reconcileProtectedGroupContentForAuthority(
      db: db,
      groupRepository: groupRepo,
      authority: authorityY,
      validateHistoricalAuthority: validateHistoricalAuthority,
      pageSize: 1,
    ),
    isTrue,
  );
  expect(
    await dbLoadActiveOrTombstonedReactionForSender(
      db,
      chainTarget,
      sender.peerId,
    ),
    isNull,
    reason:
        'second rollback skips the exact terminalized A prefix after restart',
  );

  final preparedGroup = group.copyWith(
    id: 'group-prepared-owner',
    isDissolved: false,
    dissolvedAt: null,
    dissolvedBy: null,
  );
  await groupRepo.saveGroup(preparedGroup);
  await groupRepo.saveKey(
    GroupKeyInfo(
      groupId: preparedGroup.id,
      keyGeneration: 7,
      encryptedKey: 'prepared-key',
      createdAt: preparedGroup.createdAt,
    ),
  );
  await db.insert('groups', <String, Object?>{'id': preparedGroup.id});
  await db.insert('group_keys', <String, Object?>{
    'group_id': preparedGroup.id,
    'key_generation': 7,
    'encrypted_key': 'prepared-key',
    'created_at': eventAt,
  });
  final preparedObserved = AuthenticatedGroupAuthorityProof(
    eventId: 'prepared-observed-authority',
    groupId: preparedGroup.id,
    eventAt: DateTime.utc(2026, 8, 13, 14),
    keyEpoch: 7,
    control: 'member_metadata_changed',
    actorAccountPeerId: sender.peerId,
    actorAccountPublicKey: sender.publicKey!,
    senderTransportPeerId: senderDevice.transportPeerId,
    senderTransportPublicKey: senderDevice.deviceSigningPublicKey,
    authorityData: const <String, Object?>{},
    signature: 'fake-signature',
  );
  const preparedMessageId = 'prepared-local-message';
  const preparedMessageAt = '2026-08-13T14:10:00.000000Z';
  final preparedMessagePlaintext = <String, Object?>{
    'groupId': preparedGroup.id,
    'senderId': sender.peerId,
    'senderDeviceId': senderDevice.deviceId,
    'transportPeerId': senderDevice.transportPeerId,
    'messageId': preparedMessageId,
    'logicalDeliveryId': preparedMessageId,
    'keyEpoch': 7,
    'text': 'prepared message',
    'timestamp': preparedMessageAt,
  };
  final preparedMessageEnvelope = await buildGroupOfflineReplayEnvelope(
    bridge: bridge,
    groupRepo: groupRepo,
    groupId: preparedGroup.id,
    payloadType: groupOfflineReplayPayloadTypeMessage,
    plaintext: jsonEncode(preparedMessagePlaintext),
    senderPeerId: sender.peerId,
    senderPublicKey: senderDevice.deviceSigningPublicKey,
    senderPrivateKey: 'sk-sender',
    senderDeviceId: senderDevice.deviceId,
    senderTransportPeerId: senderDevice.transportPeerId,
    recipientPeerIds: const <String>['transport-local'],
    messageId: preparedMessageId,
    contentEventId: preparedMessageId,
    contentAuthorityVersion: GroupContentAuthorityVersion(
      eventAt: preparedObserved.eventAt,
      eventId: preparedObserved.eventId,
      keyEpoch: preparedObserved.keyEpoch,
    ),
  );
  String preparedRetryPayload(String envelope) => jsonEncode(<String, Object?>{
    'groupId': preparedGroup.id,
    'message': envelope,
    'custodyContract': ackOrExpiryInboxCustodyContract,
    'custodyKind': groupContentCustodyKind,
    'recipientPeerIds': const <String>['transport-local'],
  });
  final preparedMessageRetry = preparedRetryPayload(preparedMessageEnvelope);
  final preparedMessageEvidence = buildLocalProtectedGroupContentEventPayload(
    replayEnvelope: preparedMessageEnvelope,
    payload: preparedMessagePlaintext,
  );
  final preparedMessage = <String, Object?>{
    ...GroupMessage(
      id: preparedMessageId,
      groupId: preparedGroup.id,
      senderPeerId: sender.peerId,
      transportPeerId: senderDevice.transportPeerId,
      text: 'prepared message',
      timestamp: DateTime.parse(preparedMessageAt),
      logicalDeliveryId: preparedMessageId,
      keyGeneration: 7,
      status: GroupMessage.statusQueuedOffline,
      isIncoming: false,
      createdAt: DateTime.parse(preparedMessageAt),
      wireEnvelope: jsonEncode(preparedMessagePlaintext),
      inboxRetryPayload: preparedMessageRetry,
    ).toMap(),
    'retry_attempt_count': 0,
    'next_eligible_at': null,
  };
  expect(
    await dbStagePreparedLocalGroupContentMessage(
      db,
      expected: preparedMessage,
      sourcePeerId: sender.peerId,
      sourceEventId: localPreparedProtectedGroupMessageSourceEventId(
        preparedMessageId,
      ),
      sourceTimestamp: preparedMessageAt,
      preparedEventPayload: buildLocalProtectedGroupContentPreparedEventPayload(
        eventPayload: preparedMessageEvidence,
        ownerKind: 'group_message',
        ownerId: preparedMessageId,
        ownerStatus: GroupMessage.statusQueuedOffline,
        inboxRetryPayload: preparedMessageRetry,
      ),
    ),
    isTrue,
  );

  const preparedTargetId = 'prepared-reaction-target';
  await db.insert('group_messages', <String, Object?>{
    'id': preparedTargetId,
    'group_id': preparedGroup.id,
    'sender_peer_id': local.peerId,
    'text': 'target',
    'timestamp': preparedMessageAt,
    'is_forwarded': 0,
    'media_policy_version': 0,
    'created_at': preparedMessageAt,
  });
  const preparedReactionAt = '2026-08-13T14:11:00.000000Z';
  final preparedTransition = buildGroupReactionTransitionId(
    groupId: preparedGroup.id,
    messageId: preparedTargetId,
    logicalActorPeerId: sender.peerId,
    action: 'add',
    emoji: '🧭',
    timestamp: DateTime.parse(preparedReactionAt),
  );
  final preparedReactionPlaintext = <String, Object?>{
    'id': deterministicGroupReactionStateId(
      groupId: preparedGroup.id,
      messageId: preparedTargetId,
      logicalActorPeerId: sender.peerId,
    ),
    'messageId': preparedTargetId,
    'emoji': '🧭',
    'action': 'add',
    'senderPeerId': sender.peerId,
    'timestamp': preparedReactionAt,
    'eventId': preparedTransition,
  };
  final preparedReactionEnvelope = await buildGroupOfflineReplayEnvelope(
    bridge: bridge,
    groupRepo: groupRepo,
    groupId: preparedGroup.id,
    payloadType: groupOfflineReplayPayloadTypeReaction,
    plaintext: jsonEncode(preparedReactionPlaintext),
    senderPeerId: sender.peerId,
    senderPublicKey: senderDevice.deviceSigningPublicKey,
    senderPrivateKey: 'sk-sender',
    senderDeviceId: senderDevice.deviceId,
    senderTransportPeerId: senderDevice.transportPeerId,
    recipientPeerIds: const <String>['transport-local'],
    messageId: preparedTransition,
    contentEventId: preparedTransition,
    contentAuthorityVersion: GroupContentAuthorityVersion(
      eventAt: preparedObserved.eventAt,
      eventId: preparedObserved.eventId,
      keyEpoch: preparedObserved.keyEpoch,
    ),
    reactionNotificationExtension: GroupReactionNotificationExtensionInput(
      transitionId: preparedTransition,
      action: 'add',
      targetMessageId: preparedTargetId,
      reactorPeerId: sender.peerId,
      reactorTransportPeerId: senderDevice.transportPeerId,
      notificationRecipientTransportPeerIds: const <String>['transport-local'],
    ),
  );
  final preparedReactionRetry = preparedRetryPayload(preparedReactionEnvelope);
  final preparedReactionEvidence = buildLocalProtectedGroupContentEventPayload(
    replayEnvelope: preparedReactionEnvelope,
    payload: preparedReactionPlaintext,
  );
  final preparedReaction = GroupReactionReplayOutboxEntry(
    reactionId: preparedTransition,
    groupId: preparedGroup.id,
    messageId: preparedTargetId,
    senderPeerId: sender.peerId,
    emoji: '🧭',
    action: 'add',
    inboxRetryPayload: preparedReactionRetry,
    deliveryStatus: GroupReactionReplayOutboxStatus.pending,
    createdAt: preparedReactionAt,
    updatedAt: preparedReactionAt,
  ).toMap();
  expect(
    await dbStagePreparedLocalGroupReactionContent(
      db,
      expected: preparedReaction,
      sourcePeerId: sender.peerId,
      sourceEventId: localPreparedProtectedGroupReactionSourceEventId(
        preparedTransition,
      ),
      sourceTimestamp: preparedReactionAt,
      preparedEventPayload: buildLocalProtectedGroupContentPreparedEventPayload(
        eventPayload: preparedReactionEvidence,
        ownerKind: 'group_reaction',
        ownerId: preparedTransition,
        ownerStatus: GroupReactionReplayOutboxStatus.pending,
        inboxRetryPayload: preparedReactionRetry,
      ),
    ),
    isTrue,
  );
  final preparedInvalidatingAuthority = AuthenticatedGroupAuthorityProof(
    eventId: 'prepared-invalidating-authority',
    groupId: preparedGroup.id,
    eventAt: DateTime.utc(2026, 8, 13, 14, 5),
    keyEpoch: 7,
    control: 'group_metadata_changed',
    actorAccountPeerId: sender.peerId,
    actorAccountPublicKey: sender.publicKey!,
    senderTransportPeerId: senderDevice.transportPeerId,
    senderTransportPublicKey: senderDevice.deviceSigningPublicKey,
    authorityData: const <String, Object?>{},
    signature: 'fake-signature',
  );
  var rejectSecondPreparedTerminal = true;
  var preparedTerminalCalls = 0;
  Future<bool> terminalizePrepared({
    required DatabaseExecutor txn,
    required String groupId,
    required String payloadType,
    required String contentEventId,
    required String ownerKind,
    required String ownerId,
    required Map<String, Object?> eventPayload,
    required String terminalSourcePeerId,
    required String terminalSourceEventId,
    required String terminalSourceTimestamp,
    required Map<String, Object?> terminalEventPayload,
  }) async {
    preparedTerminalCalls++;
    if (rejectSecondPreparedTerminal && preparedTerminalCalls == 2) {
      return false;
    }
    final applied = switch ((payloadType, ownerKind)) {
      (groupOfflineReplayPayloadTypeMessage, 'group_message') =>
        await dbTerminalizePreparedLocalGroupContentMessageIfExactInTransaction(
          txn,
          expected: (await txn.query(
            'group_messages',
            where: 'id = ? AND group_id = ?',
            whereArgs: <Object?>[ownerId, groupId],
            limit: 1,
          )).single,
          preparedEventPayload: eventPayload,
          terminalSourcePeerId: terminalSourcePeerId,
          terminalSourceEventId: terminalSourceEventId,
          terminalSourceTimestamp: terminalSourceTimestamp,
          terminalEventPayload: terminalEventPayload,
        ),
      (groupOfflineReplayPayloadTypeReaction, 'group_reaction') =>
        await dbTerminalizePreparedLocalGroupReactionIfExactInTransaction(
          txn,
          expected: (await txn.query(
            'group_reaction_replay_outbox',
            where: 'reaction_id = ? AND group_id = ?',
            whereArgs: <Object?>[ownerId, groupId],
            limit: 1,
          )).single,
          preparedEventPayload: eventPayload,
          terminalSourcePeerId: terminalSourcePeerId,
          terminalSourceEventId: terminalSourceEventId,
          terminalSourceTimestamp: terminalSourceTimestamp,
          terminalEventPayload: terminalEventPayload,
        ),
      _ => false,
    };
    return applied;
  }

  await expectLater(
    reconcileProtectedGroupContentForAuthority(
      db: db,
      groupRepository: groupRepo,
      authority: preparedInvalidatingAuthority,
      validateHistoricalAuthority: validateHistoricalAuthority,
      terminalizePreparedContent: terminalizePrepared,
      pageSize: 200,
    ),
    throwsStateError,
  );
  expect(preparedTerminalCalls, 2);
  expect(
    (await dbLoadGroupMessage(db, preparedMessageId))?['status'],
    GroupMessage.statusQueuedOffline,
    reason: 'later prepared-owner CAS failure rolls back the whole page',
  );
  expect(
    await hasProtectedGroupContentTerminalEvidence(
      groupId: preparedGroup.id,
      payloadType: groupOfflineReplayPayloadTypeMessage,
      contentEventId: preparedMessageId,
      loadRows:
          ({
            required groupId,
            required eventType,
            afterSourceTimestamp,
            afterSourceEventId,
            throughSourceTimestamp,
            required limit,
          }) => dbLoadGroupEventLogTypePage(
            db,
            groupId: groupId,
            eventType: eventType,
            afterSourceTimestamp: afterSourceTimestamp,
            afterSourceEventId: afterSourceEventId,
            throughSourceTimestamp: throughSourceTimestamp,
            newestFirst: true,
            limit: limit,
          ),
    ),
    isFalse,
  );
  rejectSecondPreparedTerminal = false;
  preparedTerminalCalls = 0;
  expect(
    await reconcileProtectedGroupContentForAuthority(
      db: db,
      groupRepository: groupRepo,
      authority: preparedInvalidatingAuthority,
      validateHistoricalAuthority: validateHistoricalAuthority,
      terminalizePreparedContent: terminalizePrepared,
      pageSize: 200,
    ),
    isTrue,
    reason: 'restart commits both prepared owners and the page frontier once',
  );
  expect(preparedTerminalCalls, 2);
  final terminalMessage = await dbLoadGroupMessage(db, preparedMessageId);
  expect(terminalMessage?['status'], GroupMessage.statusSendFailed);
  expect(terminalMessage?['inbox_retry_payload'], isNull);
  expect(
    terminalMessage?['wire_envelope'],
    isNull,
    reason: 'terminal protected custody cannot leak into generic reauthoring',
  );
  await dbResetGroupMessageRetryState(db, preparedMessageId);
  expect(
    (await dbLoadGroupMessage(db, preparedMessageId))?['status'],
    GroupMessage.statusSendFailed,
    reason: 'manual retry cannot re-arm a terminal protected owner',
  );
  expect(
    (await dbLoadRetryableOutgoingGroupMessages(
      db,
    )).where((row) => row['id'] == preparedMessageId),
    isEmpty,
    reason: 'the generic background retrier cannot remint terminal custody',
  );
  final terminalReaction = await dbLoadGroupReactionReplayOutboxEntry(
    db,
    preparedTransition,
  );
  expect(terminalReaction?['delivery_status'], 'stored');
  expect(terminalReaction?['inbox_retry_payload'], isEmpty);
  for (final identity in <(String, String)>[
    (groupOfflineReplayPayloadTypeMessage, preparedMessageId),
    (groupOfflineReplayPayloadTypeReaction, preparedTransition),
  ]) {
    expect(
      await hasProtectedGroupContentTerminalEvidence(
        groupId: preparedGroup.id,
        payloadType: identity.$1,
        contentEventId: identity.$2,
        loadRows:
            ({
              required groupId,
              required eventType,
              afterSourceTimestamp,
              afterSourceEventId,
              throughSourceTimestamp,
              required limit,
            }) => dbLoadGroupEventLogTypePage(
              db,
              groupId: groupId,
              eventType: eventType,
              afterSourceTimestamp: afterSourceTimestamp,
              afterSourceEventId: afterSourceEventId,
              throughSourceTimestamp: throughSourceTimestamp,
              newestFirst: true,
              limit: limit,
            ),
      ),
      isTrue,
    );
  }
  expect(
    await dbLoadGroupEventLogEntryExact(
      db,
      groupId: preparedGroup.id,
      sourceEventId: protectedGroupMessageSourceEventId(preparedMessageId),
    ),
    isNull,
  );
  expect(
    await dbLoadGroupEventLogEntryExact(
      db,
      groupId: preparedGroup.id,
      sourceEventId: protectedGroupReactionSourceEventId(preparedTransition),
    ),
    isNull,
  );

  final runtimeOwnerA = Object();
  final runtimeOwnerB = Object();
  var runtimeAReconciliations = 0;
  var runtimeBReconciliations = 0;
  setReconcileCompletedProtectedGroupAuthority(runtimeOwnerA, (_) async {
    runtimeAReconciliations++;
    return true;
  });
  setReconcileCompletedProtectedGroupAuthority(runtimeOwnerB, (_) async {
    runtimeBReconciliations++;
    return true;
  });
  expect(
    await reconcileCompletedProtectedGroupAuthority(runtimeOwnerA, observed),
    isTrue,
  );
  expect(runtimeAReconciliations, 1);
  expect(runtimeBReconciliations, 0);
  setReconcileCompletedProtectedGroupAuthority(runtimeOwnerA, null);
  expect(
    await reconcileCompletedProtectedGroupAuthority(runtimeOwnerA, observed),
    isFalse,
    reason: 'an unregistered protected producer fails closed',
  );
  expect(
    await reconcileCompletedProtectedGroupAuthority(runtimeOwnerB, observed),
    isTrue,
    reason: 'runtime B remains bound to its own repository/database token',
  );
  expect(runtimeBReconciliations, 1);
  setReconcileCompletedProtectedGroupAuthority(runtimeOwnerB, null);

  final authorityFirst = ProtectedGroupContentAuthority(
    observed: observed,
    groupType: GroupType.chat,
    members: [sender, local],
    terminalFacts: [observed, later],
  );
  expect(
    (await apply(
      await messageEnvelope('msg-authority-first', 'late'),
      acceptedAuthority: authorityFirst,
    )).disposition,
    ProtectedGroupContentApplyDisposition.terminalReject,
    reason: 'authority-first and content-first both leave no projection',
  );
}

void main() {
  tearDown(() {
    debugSetFlowEventSink(null);
  });

  group('replay-before-ack ordering', () {
    test(
      'TC-363-01b protected self bootstrap commits atomically before exact relay ACK',
      () async {
        expect(
          const InboxStoreOutcome(
            status: InboxStoreStatus.stored,
            storeStatus: 'stored',
          ).ackOrExpiryAccepted,
          isFalse,
          reason:
              'a generic or ambiguous store response cannot retire either '
              'bootstrap owner',
        );
        expect(
          const InboxStoreOutcome(
            status: InboxStoreStatus.stored,
            storeStatus: 'stored',
            custodyContract: ackOrExpiryInboxCustodyContract,
          ).ackOrExpiryAccepted,
          isTrue,
        );
        final bridge = _FakeBridge();
        final repo = InMemoryInboxStagingRepository();
        var ackAttempts = 0;
        var replayAttempts = 0;
        var bootstrapAvailable = false;
        bridge.whenCommand('inbox:retrieve_pending', (payload) {
          final custodyContract = _requireAckOrExpiryCustodyContract(payload);
          return jsonEncode(<String, dynamic>{
            'ok': true,
            'custodyContract': custodyContract,
            'messages': <Map<String, dynamic>>[
              _pendingProtectedGroupRow(entryId: 'protected-entry'),
            ],
            'hasMore': false,
          });
        });
        bridge.whenCommand('inbox:ack', (payload) {
          final custodyContract = _requireAckOrExpiryCustodyContract(payload);
          ackAttempts++;
          if (ackAttempts == 1) throw StateError('ack unavailable');
          return jsonEncode(<String, dynamic>{
            'ok': true,
            'acked': 1,
            'custodyContract': custodyContract,
          });
        });
        final service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: repo,
          replayRecoveredProtectedGroupEnvelope: (message) async {
            replayAttempts++;
            if (!bootstrapAvailable) {
              return (
                disposition:
                    ProtectedGroupReplayDisposition.prerequisiteWaiting,
                reasonCode: 'bootstrap_required',
                reasonDetail: null,
              );
            }
            return (
              disposition: ProtectedGroupReplayDisposition.applied,
              reasonCode: 'applied',
              reasonDetail: null,
            );
          },
        );
        await _start(service, bridge);

        for (var drain = 0; drain < 12; drain++) {
          await service.drainOfflineInbox();
        }
        expect(repo.entry('protected-entry')?.attemptCount, 0);
        expect(repo.entry('protected-entry')?.status, 'retryable');
        expect(ackAttempts, 0);

        bootstrapAvailable = true;
        await service.drainOfflineInbox();
        expect(repo.entry('protected-entry'), isNotNull);
        expect(replayAttempts, 13);
        expect(ackAttempts, 1);

        await service.drainOfflineInbox();
        expect(repo.entry('protected-entry'), isNull);
        expect(
          replayAttempts,
          13,
          reason: 'terminal local evidence is ACKed without reapplying it',
        );
        expect(ackAttempts, 2);
        expect(bridge.payloadsFor('inbox:ack').last?['entryIds'], <String>[
          'protected-entry',
        ]);

        service.dispose();
      },
    );

    test(
      'TC-364-03a protected content applies in authenticated authority order before exact ACK',
      () async {
        final bridge = _FakeBridge();
        final repo = InMemoryInboxStagingRepository();
        var prerequisitesReady = false;
        var replayAttempts = 0;
        var ackAttempts = 0;
        bridge.whenCommand('inbox:retrieve_pending', (payload) {
          final custodyContract = _requireAckOrExpiryCustodyContract(payload);
          return jsonEncode(<String, dynamic>{
            'ok': true,
            'custodyContract': custodyContract,
            'messages': <Map<String, dynamic>>[
              _pendingProtectedGroupRow(
                entryId: 'protected-content-entry',
                type: 'group_content_v1',
                useSignedContentDiscriminator: true,
              ),
            ],
            'hasMore': false,
          });
        });
        bridge.whenCommand('inbox:ack', (payload) {
          final custodyContract = _requireAckOrExpiryCustodyContract(payload);
          ackAttempts++;
          if (ackAttempts == 1) {
            throw StateError('relay ACK unavailable after durable apply');
          }
          return jsonEncode(<String, dynamic>{
            'ok': true,
            'acked': 1,
            'custodyContract': custodyContract,
          });
        });
        final service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: repo,
          replayRecoveredProtectedGroupEnvelope: (message) async {
            replayAttempts++;
            final envelope =
                jsonDecode(message.content) as Map<String, dynamic>;
            final signedPayload =
                jsonDecode(envelope['signedPayload']! as String)
                    as Map<String, dynamic>;
            expect(
              signedPayload,
              containsPair('custodyKind', 'group_content_v1'),
            );
            expect(
              envelope,
              isNot(containsPair('custodyKind', 'group_content_v1')),
              reason:
                  'the canonical signed discriminator, not an unsigned outer '
                  'hint, selects the protected content lane',
            );
            if (!prerequisitesReady) {
              return (
                disposition:
                    ProtectedGroupReplayDisposition.prerequisiteWaiting,
                reasonCode: 'authenticated_authority_version_unavailable',
                reasonDetail: null,
              );
            }
            return (
              disposition: ProtectedGroupReplayDisposition.applied,
              reasonCode: 'protected_content_applied',
              reasonDetail: null,
            );
          },
        );
        await _start(service, bridge);

        for (var drain = 0; drain < 12; drain++) {
          await service.drainOfflineInbox();
        }
        expect(replayAttempts, 12);
        expect(repo.entry('protected-content-entry')?.attemptCount, 0);
        expect(ackAttempts, 0, reason: 'a prerequisite row is never ACKable');

        prerequisitesReady = true;
        await service.drainOfflineInbox();
        expect(replayAttempts, 13);
        expect(
          repo.entry('protected-content-entry')?.status,
          'protected_ack_pending',
        );
        expect(ackAttempts, 1);

        await service.drainOfflineInbox();
        expect(repo.entry('protected-content-entry'), isNull);
        expect(replayAttempts, 13, reason: 'durable apply is not repeated');
        expect(ackAttempts, 2);
        expect(bridge.payloadsFor('inbox:ack').last?['entryIds'], <String>[
          'protected-content-entry',
        ]);
        service.dispose();

        final crossedBridge = _FakeBridge();
        final crossedRepo = InMemoryInboxStagingRepository();
        var crossedReplayAttempts = 0;
        crossedBridge.whenCommand('inbox:retrieve_pending', (payload) {
          final custodyContract = _requireAckOrExpiryCustodyContract(payload);
          return jsonEncode(<String, dynamic>{
            'ok': true,
            'custodyContract': custodyContract,
            'messages': <Map<String, dynamic>>[
              _pendingProtectedGroupRow(
                entryId: 'crossed-content-authority-type',
                type: 'group_content_v1',
                useSignedContentDiscriminator: true,
                crossedOuterType: 'group_authority_v1',
              ),
            ],
            'hasMore': false,
          });
        });
        final crossedService = P2PServiceImpl(
          bridge: crossedBridge,
          inboxStagingRepository: crossedRepo,
          replayRecoveredProtectedGroupEnvelope: (_) async {
            crossedReplayAttempts++;
            return (
              disposition: ProtectedGroupReplayDisposition.applied,
              reasonCode: 'must_not_bypass_content_pause',
              reasonDetail: null,
            );
          },
        );
        await _start(crossedService, crossedBridge);
        await crossedService.pauseProtectedGroupContentAdmission();
        await crossedService.drainOfflineInbox();
        expect(crossedReplayAttempts, 0);
        expect(
          crossedRepo.entry('crossed-content-authority-type')?.rejectReasonCode,
          'protected_group_content_admission_paused',
          reason: 'signed content outranks an unsigned authority type hint',
        );
        expect(crossedRepo.entry('crossed-content-authority-type'), isNotNull);
        expect(
          crossedBridge.payloadsFor('inbox:ack'),
          isEmpty,
          reason: 'a paused signed-content row remains in relay custody',
        );
        crossedService.dispose();

        final unverifiedBridge = _FakeBridge();
        final unverifiedRepo = InMemoryInboxStagingRepository();
        final unverifiedRows = <Map<String, dynamic>>[
          _pendingProtectedGroupRow(
            entryId: 'outer-content-only',
            type: 'group_content_v1',
            outerCustodyKind: 'group_content_v1',
          ),
          _pendingProtectedGroupRow(
            entryId: 'missing-signed-content-discriminator',
            type: 'group_content_v1',
            includeSignedPayloadWithoutDiscriminator: true,
            outerCustodyKind: 'group_content_v1',
          ),
          _pendingProtectedGroupRow(
            entryId: 'crossed-signed-content-discriminator',
            type: 'group_content_v1',
            useSignedContentDiscriminator: true,
            signedCustodyKindOverride: 'group_authority_v1',
            outerCustodyKind: 'group_content_v1',
          ),
        ];
        var unverifiedReplayAttempts = 0;
        var unverifiedAckAttempts = 0;
        unverifiedBridge.whenCommand('inbox:retrieve_pending', (payload) {
          final custodyContract = _requireAckOrExpiryCustodyContract(payload);
          return jsonEncode(<String, dynamic>{
            'ok': true,
            'custodyContract': custodyContract,
            'messages': unverifiedRows,
            'hasMore': false,
          });
        });
        unverifiedBridge.whenCommand('inbox:ack', (payload) {
          final custodyContract = _requireAckOrExpiryCustodyContract(payload);
          unverifiedAckAttempts++;
          return jsonEncode(<String, dynamic>{
            'ok': true,
            'acked': (payload?['entryIds'] as List?)?.length ?? 0,
            'custodyContract': custodyContract,
          });
        });
        final unverifiedService = P2PServiceImpl(
          bridge: unverifiedBridge,
          inboxStagingRepository: unverifiedRepo,
          replayRecoveredProtectedGroupEnvelope: (_) async {
            unverifiedReplayAttempts++;
            return (
              disposition: ProtectedGroupReplayDisposition.unverifiedRejected,
              reasonCode: 'protected_content_signed_discriminator_invalid',
              reasonDetail: null,
            );
          },
        );
        await _start(unverifiedService, unverifiedBridge);
        await unverifiedService.drainOfflineInbox();
        expect(unverifiedReplayAttempts, unverifiedRows.length);
        expect(
          unverifiedAckAttempts,
          0,
          reason: 'unverified protected candidates are never ACK-eligible',
        );
        for (final row in unverifiedRows) {
          final entryId = row['id']! as String;
          final staged = unverifiedRepo.entry(entryId);
          expect(
            staged,
            isNotNull,
            reason: '$entryId remains in local custody',
          );
          expect(staged?.status, 'quarantined');
          expect(staged?.envelope, row['message']);
        }
        unverifiedService.dispose();

        await _exerciseProtectedContentAdapterAndReconciliation();
      },
    );

    test(
      'TC-365-03a group media content ACK follows the descriptor transaction',
      () async {
        const expiryCeiling = 2000000456000;
        final bridge = _FakeBridge();
        final repo = InMemoryInboxStagingRepository();
        final commitEntered = Completer<void>();
        final releaseCommit = Completer<void>();
        final ordering = <String>[];
        var descriptorCommitted = false;
        var returnedExpiry = expiryCeiling;
        bridge.whenCommand('inbox:store', (payload) {
          if (payload?['custodyKind'] != 'group_content_v1') {
            return jsonEncode(const <String, Object?>{
              'ok': false,
              'errorCode': 'NOT_GROUP_CONTENT',
            });
          }
          expect(payload?['custodyKind'], 'group_content_v1');
          expect(payload?['custodyContract'], ackOrExpiryInboxCustodyContract);
          expect(payload?['custodyExpiresAtOrBeforeMs'], expiryCeiling);
          return jsonEncode(<String, Object?>{
            'ok': true,
            'storeStatus': 'stored',
            'custodyContract': ackOrExpiryInboxCustodyContract,
            'expiresAtMs': returnedExpiry,
          });
        });
        bridge.whenCommand('inbox:retrieve_pending', (payload) {
          final custodyContract = _requireAckOrExpiryCustodyContract(payload);
          return jsonEncode(<String, Object?>{
            'ok': true,
            'custodyContract': custodyContract,
            'messages': <Map<String, dynamic>>[
              _pendingProtectedGroupRow(
                entryId: 'protected-group-media-entry',
                type: 'group_content_v1',
                useSignedContentDiscriminator: true,
              ),
            ],
            'hasMore': false,
          });
        });
        bridge.whenCommand('inbox:ack', (payload) {
          expect(descriptorCommitted, isTrue);
          ordering.add('content-ack');
          final custodyContract = _requireAckOrExpiryCustodyContract(payload);
          return jsonEncode(<String, Object?>{
            'ok': true,
            'acked': 1,
            'custodyContract': custodyContract,
          });
        });
        final service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: repo,
          replayRecoveredProtectedGroupEnvelope: (_) async {
            ordering.add('descriptor-transaction-entered');
            if (!commitEntered.isCompleted) commitEntered.complete();
            await releaseCommit.future;
            descriptorCommitted = true;
            ordering.add('descriptor-transaction-committed');
            return (
              disposition: ProtectedGroupReplayDisposition.applied,
              reasonCode: 'protected_group_media_committed',
              reasonDetail: null,
            );
          },
        );
        await _start(service, bridge);

        final exactReceipt = await service
            .storeInGroupContentExpiryBoundedInboxDetailed(
              'physical-recipient-b',
              'signed-group-media-content',
              custodyExpiresAtOrBeforeMs: expiryCeiling,
            );
        expect(exactReceipt.ackOrExpiryAccepted, isTrue);
        returnedExpiry = expiryCeiling + 1;
        final crossedReceipt = await service
            .storeInGroupContentExpiryBoundedInboxDetailed(
              'physical-recipient-b',
              'signed-group-media-content',
              custodyExpiresAtOrBeforeMs: expiryCeiling,
            );
        expect(crossedReceipt.ackOrExpiryAccepted, isFalse);
        expect(
          crossedReceipt.errorCode,
          'CUSTODY_EXPIRY_PROOF_MISSING_OR_INVALID',
        );

        final drain = service.drainOfflineInbox();
        await commitEntered.future;
        expect(
          bridge.payloadsFor('inbox:ack'),
          isEmpty,
          reason: 'content ACK cannot race the descriptor/custody transaction',
        );
        releaseCommit.complete();
        await drain;
        expect(ordering, <String>[
          'descriptor-transaction-entered',
          'descriptor-transaction-committed',
          'content-ack',
        ]);
        expect(repo.entry('protected-group-media-entry'), isNull);
        service.dispose();
        await _exerciseProtectedContentAdapterAndReconciliation();
      },
    );

    test(
      'TC-366-03a quoted protected content commits before exact ACK',
      () async {
        expect(
          await _exerciseProtectedMetadataAckOrdering(
            entryId: 'tc366-quoted-content',
            metadata: const <String, Object?>{
              'quotedMessageId': 'quoted-parent-id',
            },
          ),
          <String>['commit', 'ack'],
        );
        await _exerciseProtectedContentAdapterAndReconciliation();
      },
    );

    test(
      'TC-366-03b forwarded protected media commits marker before ACK',
      () async {
        expect(
          await _exerciseProtectedMetadataAckOrdering(
            entryId: 'tc366-forwarded-content',
            metadata: const <String, Object?>{'isForwarded': true},
          ),
          <String>['commit', 'ack'],
        );
        await _exerciseProtectedContentAdapterAndReconciliation();
      },
    );

    test(
      'staged entries replay and reach the render stream even when the inbox ack never completes',
      () async {
        final bridge = _FakeBridge();
        final ack = Completer<void>();
        final replayedEntryIds = <String?>[];
        bridge.whenCommand('inbox:retrieve_pending', (payload) {
          final custodyContract = _requireAckOrExpiryCustodyContract(payload);
          return jsonEncode({
            'ok': true,
            'custodyContract': custodyContract,
            'messages': [
              _pendingInboxRow(entryId: 'entry-never-ack', from: 'remote-peer'),
            ],
            'hasMore': false,
          });
        });
        bridge.whenCommand('inbox:ack', (payload) async {
          final custodyContract = _requireAckOrExpiryCustodyContract(payload);
          await ack.future;
          return jsonEncode({
            'ok': true,
            'acked': 1,
            'custodyContract': custodyContract,
          });
        });

        final service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: InMemoryInboxStagingRepository(),
          replayRecoveredInboxChatMessage:
              (message, {String? stagedEntryId}) async {
                replayedEntryIds.add(stagedEntryId);
                return _committed();
              },
        );
        await _start(service, bridge);

        var drainCompleted = false;
        final drain = service.drainOfflineInbox()
          ..then((_) {
            drainCompleted = true;
          });
        await _waitFor(
          () => bridge.calledCommands.contains('inbox:ack'),
          reason: 'ack attempted',
        );
        await _waitFor(
          () => replayedEntryIds.isNotEmpty,
          reason: 'replay before ack completion',
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));

        expect(replayedEntryIds, ['entry-never-ack']);
        expect(ack.isCompleted, isFalse);
        expect(drainCompleted, isFalse);
        expect(bridge.payloadsFor('inbox:ack').single?['entryIds'], [
          'entry-never-ack',
        ]);

        ack.complete();
        await drain;
        service.dispose();
      },
    );

    test(
      'replay commit precedes ack completion and the ack is still sent exactly once',
      () async {
        final bridge = _FakeBridge();
        final ackGate = Completer<void>();
        final flow = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flow.add);
        bridge.whenCommand('inbox:retrieve_pending', (payload) {
          final custodyContract = _requireAckOrExpiryCustodyContract(payload);
          return jsonEncode({
            'ok': true,
            'custodyContract': custodyContract,
            'messages': [
              _pendingInboxRow(
                entryId: 'entry-delayed-ack',
                from: 'remote-peer',
                messageId: 'msg-delayed-ack',
              ),
            ],
            'hasMore': false,
          });
        });
        bridge.whenCommand('inbox:ack', (payload) async {
          final custodyContract = _requireAckOrExpiryCustodyContract(payload);
          await ackGate.future;
          return jsonEncode({
            'ok': true,
            'acked': 1,
            'custodyContract': custodyContract,
          });
        });

        final service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: InMemoryInboxStagingRepository(),
          replayRecoveredInboxChatMessage:
              (message, {String? stagedEntryId}) async => _committed(),
        );
        await _start(service, bridge);

        final drain = service.drainOfflineInbox();
        await _waitFor(
          () => bridge.calledCommands.contains('inbox:ack'),
          reason: 'ack call entered',
        );
        ackGate.complete();
        await drain;

        final names = flow.map((event) => event['event']).toList();
        final replayIndex = names.indexOf(
          'P2P_SERVICE_INBOX_STAGED_CHAT_COMMITTED',
        );
        final ackIndex = names.indexOf(
          'P2P_SERVICE_INBOX_ACK_AFTER_STAGE_SUCCESS',
        );
        expect(replayIndex, isNonNegative);
        expect(ackIndex, isNonNegative);
        expect(replayIndex, lessThan(ackIndex));
        expect(
          bridge.calledCommands.where((c) => c == 'inbox:ack'),
          hasLength(1),
        );
        expect(bridge.payloadsFor('inbox:ack').single?['entryIds'], [
          'entry-delayed-ack',
        ]);

        service.dispose();
      },
    );

    test(
      'legacy confirmed-visible duplicate staging row is ACKed without replay',
      () async {
        final bridge = _FakeBridge();
        final repo = InMemoryInboxStagingRepository();
        final pending = _pendingInboxRow(
          entryId: 'entry-confirmed-duplicate',
          from: 'remote-peer',
          messageId: 'msg-confirmed-duplicate',
        );
        repo.seed(
          InboxStagingEntry(
            entryId: pending['id']! as String,
            ownerPeerId: 'self-peer',
            senderPeerId: pending['from']! as String,
            messageType: 'chat_message',
            relayTimestamp: pending['timestamp']! as String,
            envelope: pending['message']! as String,
            status: 'rejected',
            stagedAt: '2026-04-01T00:00:01.000Z',
            rejectReasonCode: 'duplicate_confirmed_visible',
          ),
        );
        var replayCount = 0;
        bridge.whenCommand('inbox:retrieve_pending', (payload) {
          final custodyContract = _requireAckOrExpiryCustodyContract(payload);
          return jsonEncode({
            'ok': true,
            'custodyContract': custodyContract,
            'messages': [pending],
            'hasMore': false,
          });
        });
        bridge.whenCommand('inbox:ack', (payload) {
          final custodyContract = _requireAckOrExpiryCustodyContract(payload);
          return jsonEncode({
            'ok': true,
            'acked': 1,
            'custodyContract': custodyContract,
          });
        });

        final service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: repo,
          replayRecoveredInboxChatMessage: (_, {String? stagedEntryId}) async {
            replayCount++;
            return _committed();
          },
        );
        await _start(service, bridge);

        await service.drainOfflineInbox();

        expect(
          replayCount,
          0,
          reason: 'historic durable proof is not replayed',
        );
        expect(bridge.payloadsFor('inbox:ack').single?['entryIds'], [
          'entry-confirmed-duplicate',
        ]);
        expect(repo.entry('entry-confirmed-duplicate'), isNull);
        service.dispose();
      },
    );

    test(
      'legacy confirmed duplicate with different relay bytes is not ACKed',
      () async {
        final bridge = _FakeBridge();
        final repo = InMemoryInboxStagingRepository();
        final pending = _pendingInboxRow(
          entryId: 'entry-colliding-duplicate',
          from: 'remote-peer',
          messageId: 'msg-current-relay-bytes',
        );
        repo.seed(
          InboxStagingEntry(
            entryId: pending['id']! as String,
            ownerPeerId: 'self-peer',
            senderPeerId: pending['from']! as String,
            messageType: 'chat_message',
            relayTimestamp: pending['timestamp']! as String,
            envelope: jsonEncode({'different': 'historic relay bytes'}),
            status: 'rejected',
            stagedAt: '2026-04-01T00:00:01.000Z',
            rejectReasonCode: 'duplicate_confirmed_visible',
          ),
        );
        bridge.whenCommand('inbox:retrieve_pending', (payload) {
          final custodyContract = _requireAckOrExpiryCustodyContract(payload);
          return jsonEncode({
            'ok': true,
            'custodyContract': custodyContract,
            'messages': [pending],
            'hasMore': false,
          });
        });

        final service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: repo,
          replayRecoveredInboxChatMessage: (_, {String? stagedEntryId}) async =>
              _committed(),
        );
        await _start(service, bridge);

        await service.drainOfflineInbox();

        expect(bridge.payloadsFor('inbox:ack'), isEmpty);
        expect(repo.entry('entry-colliding-duplicate'), isNotNull);
        service.dispose();
      },
    );

    test(
      'ack throw after replay is swallowed and replayed count still contributes to drain success',
      () async {
        final bridge = _FakeBridge();
        final flow = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flow.add);
        var replayCount = 0;
        bridge.whenCommand('inbox:retrieve_pending', (payload) {
          final custodyContract = _requireAckOrExpiryCustodyContract(payload);
          return jsonEncode({
            'ok': true,
            'custodyContract': custodyContract,
            'messages': [
              _pendingInboxRow(
                entryId: 'entry-ack-throws',
                from: 'remote-peer',
              ),
            ],
            'hasMore': false,
          });
        });
        bridge.whenCommand('inbox:ack', (payload) {
          _requireAckOrExpiryCustodyContract(payload);
          throw StateError('ack down');
        });

        final service = P2PServiceImpl(
          bridge: bridge,
          inboxStagingRepository: InMemoryInboxStagingRepository(),
          replayRecoveredInboxChatMessage:
              (message, {String? stagedEntryId}) async {
                replayCount++;
                return _committed();
              },
        );
        await _start(service, bridge);

        await service.drainOfflineInbox();

        expect(replayCount, 1);
        expect(
          flow.map((event) => event['event']),
          contains('P2P_SERVICE_INBOX_ACK_AFTER_STAGE_EXCEPTION'),
        );
        expect(
          flow.map((event) => event['event']),
          contains('P2P_SERVICE_INBOX_STAGED_DRAIN_SUCCESS'),
        );

        service.dispose();
      },
    );

    test('migration-gated page stays staged-not-replayed-not-acked', () async {
      final bridge = _FakeBridge();
      final repo = InMemoryInboxStagingRepository();
      final flow = <Map<String, dynamic>>[];
      debugSetFlowEventSink(flow.add);
      var replayCount = 0;
      bridge.whenCommand('inbox:retrieve_pending', (payload) {
        final custodyContract = _requireAckOrExpiryCustodyContract(payload);
        return jsonEncode({
          'ok': true,
          'custodyContract': custodyContract,
          'messages': [
            _pendingInboxRow(entryId: 'entry-gated', from: 'remote-peer'),
          ],
          'hasMore': false,
        });
      });
      bridge.whenCommand('inbox:ack', (payload) {
        final custodyContract = _requireAckOrExpiryCustodyContract(payload);
        return jsonEncode({
          'ok': true,
          'acked': 1,
          'custodyContract': custodyContract,
        });
      });

      final service = P2PServiceImpl(
        bridge: bridge,
        inboxStagingRepository: repo,
        accountMigrationNetworkGate: ({peerId, required operation}) async =>
            operation != 'p2p_inbox_ack_after_stage',
        replayRecoveredInboxChatMessage:
            (message, {String? stagedEntryId}) async {
              replayCount++;
              return _committed();
            },
      );
      await _start(service, bridge);

      await service.drainOfflineInbox();

      expect(repo.entry('entry-gated'), isNotNull);
      expect(replayCount, 0);
      expect(bridge.calledCommands, isNot(contains('inbox:ack')));
      expect(
        flow.map((event) => event['event']),
        contains('P2P_SERVICE_INBOX_ACK_SKIPPED_GATED'),
      );

      service.dispose();
    });
  });
}
