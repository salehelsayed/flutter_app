import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/database/helpers/pending_group_broadcasts_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/self_removed_group_shell_db_helpers.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/create_group_with_members_use_case.dart';
import 'package:flutter_app/features/groups/application/handle_incoming_group_invite_use_case.dart';
import 'package:flutter_app/features/groups/application/rotate_and_distribute_group_key_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_welcome_key_package.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import 'package:flutter_app/app/bootstrap/production_canonical_group_replay_composition.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/groups_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_members_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_keys_db_helpers.dart';
import 'package:flutter_app/core/database/db_write_transaction.dart';
import 'package:flutter_app/core/database/helpers/direct_media_blob_custody_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/group_media_blob_custody.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/protected_group_media_manifest.dart';
import 'package:flutter_app/features/groups/application/retry_incomplete_group_downloads_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/settings/application/media_download_policy.dart';
import 'package:flutter_app/features/settings/domain/models/media_download_preferences.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/groups/application/group_key_update_listener.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_key_update_signature.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/protected_group_authority.dart';
import 'package:flutter_app/features/groups/application/protected_group_authority_history.dart';
import 'package:flutter_app/features/groups/application/protected_group_content_receive.dart';
import 'package:flutter_app/features/groups/application/signed_group_transition_audit.dart';
import 'package:flutter_app/features/groups/data/repositories/group_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../bridge/fake_bridge.dart';
import '../secure_storage/fake_secure_key_store.dart';
import '../services/fake_p2p_service.dart';
import '../../shared/fakes/in_memory_contact_repository.dart';

// Real schema/repository/key listener/history/reconciliation; encryption and
// signing use the explicit host fake. This does not certify native cryptography
// or an installed transport. No authenticated history is inserted by the test.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'protected group runtime transport ordinary-primary distinct transport applies authenticated key authority through production SQLite composition',
    () async {
      final f = await _Fixture.create();
      final message = await f.authorityMessage();
      expect(f.identity.peerId, isNot(_receiver.transportPeerId));
      expect((await f.groups.getLatestKey(_groupId))!.keyGeneration, 1);
      expect(await f.db.query('group_event_log'), isEmpty);

      final result = await f.composition.replay(message);
      expect(
        result.disposition,
        ProtectedGroupReplayDisposition.applied,
        reason: result.reasonCode,
      );
      final key = (await f.groups.getLatestKey(_groupId))!;
      expect(key.keyGeneration, 2);
      expect(key.encryptedKey, 'rotated-key');
      final prepared = await f.proof(AuthenticatedGroupAuthorityPhase.prepared);
      final complete = await f.proof(AuthenticatedGroupAuthorityPhase.complete);
      expect(prepared, isNotNull);
      expect(complete, isNotNull);
      expect(
        sameAuthenticatedGroupAuthorityProof(prepared!, complete!),
        isTrue,
      );
      expect(complete.eventId, _eventId);
      expect(complete.keyEpoch, 2);
      expect(complete.actorAccountPeerId, _senderAccount);
      final reconciliation = await dbLoadGroupEventLogEntryExact(
        f.db,
        groupId: _groupId,
        sourceEventId: protectedGroupContentReconciliationCompleteSourceEventId(
          _eventId,
        ),
      );
      expect(
        isProtectedGroupContentReconciliationCompleteRow(
          reconciliation,
          authority: complete,
        ),
        isTrue,
      );
      expect(await f.support.hasUnfinishedContentAuthority(_groupId), isFalse);
      expect(f.pendingRepairCalls, 1);
      final durableBeforeDuplicate = await f.db.query(
        'group_event_log',
        orderBy: 'id',
      );
      final duplicate = await f.composition.replay(message);
      expect(duplicate.disposition, ProtectedGroupReplayDisposition.duplicate);
      expect(
        await f.db.query('group_event_log', orderBy: 'id'),
        durableBeforeDuplicate,
      );
      expect(
        (await f.groups.getLatestKey(_groupId))!.encryptedKey,
        'rotated-key',
      );
      expect(f.pendingRepairCalls, 1);
    },
  );

  test(
    'protected group runtime transport rejected cryptographic proof cannot mutate real key or authority history',
    () async {
      final f = await _Fixture.create();
      final message = await f.authorityMessage();
      f.bridge.responses['payload.verify'] = {'ok': true, 'valid': false};
      final result = await f.composition.replay(message);
      expect(
        result.disposition,
        ProtectedGroupReplayDisposition.terminalRejected,
      );
      expect((await f.groups.getLatestKey(_groupId))!.keyGeneration, 1);
      expect(await f.db.query('group_event_log'), isEmpty);
      expect(f.pendingRepairCalls, 0);
    },
  );
  test(
    'protected group runtime transport strict media commits before automatic dispatch without awaiting transfer and duplicate cannot dispatch twice',
    () async {
      final f = await _Fixture.create();
      await f.applyAuthority();
      final content = await f.mediaMessage('media-applied');
      expect(await f.messageRows.getMessage('media-applied'), isNull);
      expect(await f.db.query('media_attachments'), isEmpty);
      expect(f.operations, isEmpty);

      // Publication must finish while the real retry owner's fake network
      // boundary is held. The listener owns that work until stop completes.
      final result = await f.composition
          .replay(content)
          .timeout(const Duration(seconds: 2));
      expect(
        result.disposition,
        ProtectedGroupReplayDisposition.applied,
        reason: result.reasonCode,
      );
      final started = await Future.any<bool>([
        f.transferStarted.future.then((_) => true),
        Future<bool>.delayed(const Duration(seconds: 2), () => false),
      ]);
      expect(
        started,
        isTrue,
        reason:
            'newly committed protected media must trigger its automatic retry owner',
      );
      expect(f.media.readOwners, [MediaOwnerLane.group]);
      expect(f.operations, [
        'begin',
        'strict-transfer:media-applied-attachment',
      ]);
      expect(f.transferGate.isCompleted, isFalse);
      final durable = await f.mediaSnapshot('media-applied');
      final eventRows = await f.db.query('group_event_log', orderBy: 'id');

      final duplicate = await f.composition.replay(content);
      expect(duplicate.disposition, ProtectedGroupReplayDisposition.duplicate);
      expect(await f.mediaSnapshot('media-applied'), durable);
      expect(await f.db.query('group_event_log', orderBy: 'id'), eventRows);
      expect(f.media.readOwners, [MediaOwnerLane.group]);
      expect(f.operations, [
        'begin',
        'strict-transfer:media-applied-attachment',
      ]);

      var stopped = false;
      final stopping = f.messages.stop().then((_) => stopped = true);
      await Future<void>.delayed(Duration.zero);
      expect(
        stopped,
        isFalse,
        reason: 'stop must retain the in-flight transfer',
      );
      f.transferGate.complete();
      await stopping.timeout(const Duration(seconds: 2));
      expect(f.operations, [
        'begin',
        'strict-transfer:media-applied-attachment',
        'end:sql-media-lease',
      ]);
      // The fake network returns no completed download; no READY/local claim
      // or custody acknowledgement is manufactured by this dispatch test.
      expect(await f.mediaSnapshot('media-applied'), durable);
    },
  );

  test(
    'protected group runtime transport actual creation invite rotation and media need no metadata workaround',
    () async {
      final f = await _CreatedGroupFixture.create();
      await f.createAndAcceptInvite();
      final keyAuthority = await f.rotate();
      final content = await f.sender.mediaMessage(
        'created-media',
        authorityOverride: keyAuthority,
      );
      final applied = await f.receiver.composition.replay(content);
      expect(
        applied.disposition,
        ProtectedGroupReplayDisposition.applied,
        reason: applied.reasonCode,
      );
      await f.receiver.transferStarted.future.timeout(
        const Duration(seconds: 2),
      );
      await f.receiver.expectCommittedMedia('created-media');
      expect(f.receiver.operations, [
        'begin',
        'strict-transfer:created-media-attachment',
      ]);
      final membership = f.requests.singleWhere(
        (r) => r.control == ProtectedGroupAuthorityControl.memberAdd,
      );
      expect(
        membership.frozenRecipients.map((d) => d.transportPeerId).toSet(),
        {_sender.transportPeerId, _receiver.transportPeerId},
      );
      final memberProof = (await f.receiver.proof(
        AuthenticatedGroupAuthorityPhase.complete,
        eventId: membership.transitionId,
      ))!;
      expect(
        await f.receiver.support.loadContentAuthority(
          _groupId,
          GroupContentAuthorityVersion(
            eventAt: keyAuthority.eventAt,
            eventId: keyAuthority.eventId,
            keyEpoch: keyAuthority.keyEpoch,
          ),
        ),
        isNotNull,
      );
      expect(
        memberProof.control,
        ProtectedGroupAuthorityControl.memberAdd.wireValue,
      );
      final history = await f.receiver.db.query('group_event_log');
      expect(
        history.where((r) => r['event_type'] == 'group_metadata_updated'),
        isEmpty,
      );
      final beforeDuplicate = await f.receiver.mediaSnapshot('created-media');
      final duplicate = await f.receiver.composition.replay(content);
      expect(duplicate.disposition, ProtectedGroupReplayDisposition.duplicate);
      expect(await f.receiver.mediaSnapshot('created-media'), beforeDuplicate);
      expect(f.receiver.operations, [
        'begin',
        'strict-transfer:created-media-attachment',
      ]);
    },
  );

  test(
    'protected group runtime transport older completed membership after key rotation preserves the live epoch gate',
    () async {
      final f = await _CreatedGroupFixture.create();
      await f.createAndAcceptInvite();
      final membership = f.requests.singleWhere(
        (r) => r.control == ProtectedGroupAuthorityControl.memberAdd,
      );
      final memberMessage = f.delivered.single;
      final keyAuthority = await f.rotate();
      final groupBefore = (await f.receiver.groups.getGroup(_groupId))!.toMap();
      final eventsBefore = await f.receiver.db.query(
        'group_event_log',
        orderBy: 'id',
      );
      final result = await f.receiver.composition.replay(memberMessage);
      expect(
        result.disposition,
        ProtectedGroupReplayDisposition.retryable,
        reason:
            'ordinary live reconciliation does not adopt an older key epoch',
      );
      expect(
        (await f.receiver.groups.getLatestKey(_groupId))!.keyGeneration,
        keyAuthority.keyEpoch,
      );
      expect(
        (await f.receiver.groups.getGroup(_groupId))!.toMap(),
        groupBefore,
      );
      expect(
        await f.receiver.db.query('group_event_log', orderBy: 'id'),
        eventsBefore,
      );
      final originalComplete = (await f.receiver.proof(
        AuthenticatedGroupAuthorityPhase.complete,
        eventId: membership.transitionId,
      ))!;
      expect(originalComplete.keyEpoch, 1);
      expect(keyAuthority.keyEpoch, 2);
    },
  );

  test(
    'protected group runtime transport actual legacy creation and invite preserve the ordinary uninitialized path',
    () async {
      final f = await _CreatedGroupFixture.create(legacy: true);
      await f.createAndAcceptInvite();
      expect(f.requests, isEmpty);
      expect(f.delivered, isEmpty);
      expect(
        (await f.sender.groups.getMembers(
          _groupId,
        )).every((m) => m.devices.isEmpty),
        isTrue,
      );
      expect(
        (await f.receiver.groups.getMembers(
          _groupId,
        )).every((m) => m.devices.isEmpty),
        isTrue,
      );
      expect(
        (await f.sender.db.query(
          'group_event_log',
        )).map((r) => r['event_type']),
        ['group_created'],
      );
      expect(
        f.sender.bridge.commandLog.where((cmd) => cmd == 'group:publish'),
        hasLength(1),
      );
    },
  );

  test(
    'protected group runtime transport rejected strict media does not commit or schedule automatic recovery',
    () async {
      final f = await _Fixture.create();
      await f.applyAuthority();
      final validContent = await f.mediaMessage('media-rejected');
      final rejectedEnvelope =
          jsonDecode(validContent.content) as Map<String, dynamic>
            ..['signature'] = 'reject-content-signature';
      final content = ChatMessage(
        from: validContent.from,
        to: validContent.to,
        content: jsonEncode(rejectedEnvelope),
        timestamp: validContent.timestamp,
        isIncoming: true,
      );
      final messagesBefore = await f.db.query('group_messages', orderBy: 'id');
      final eventsBefore = await f.db.query('group_event_log', orderBy: 'id');
      final result = await f.composition.replay(content);
      expect(
        result.disposition,
        ProtectedGroupReplayDisposition.unverifiedRejected,
      );
      await f.messages.stop();
      expect(await f.db.query('group_messages', orderBy: 'id'), messagesBefore);
      expect(await f.db.query('media_attachments'), isEmpty);
      expect(await f.custody('media-rejected'), isEmpty);
      expect(await f.db.query('group_event_log', orderBy: 'id'), eventsBefore);
      expect(f.media.readOwners, isEmpty);
      expect(f.operations, isEmpty);
      expect(f.transferStarted.isCompleted, isFalse);
    },
  );
}

const _ciphertextHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _groupId = 'composition-application-group';
const _eventId = 'composition-key-authority-2';
const _senderAccount = 'sender-account';
const _receiverAccount = 'receiver-account';
final _eventAt = DateTime.utc(2026, 9, 18, 12);
const _sender = GroupMemberDeviceIdentity(
  deviceId: 'sender-device',
  transportPeerId: 'sender-transport',
  deviceSigningPublicKey: 'sender-public',
  mlKemPublicKey: 'sender-kem',
);
const _receiver = GroupMemberDeviceIdentity(
  deviceId: 'receiver-device',
  transportPeerId: 'receiver-transport',
  deviceSigningPublicKey: 'receiver-public',
  mlKemPublicKey: 'receiver-kem',
);

// Only the read surface used by the actual listener/retry owner is adapted.
// Every read uses the real database helpers; unimplemented APIs throw.
class _ContentRejectBridge extends PassthroughCryptoBridge {
  @override
  Future<String> send(String message) async {
    final command = jsonDecode(message) as Map<String, dynamic>;
    if (command['cmd'] == 'payload.verify' &&
        (command['payload'] as Map)['signature'] ==
            'reject-content-signature') {
      return jsonEncode({'ok': true, 'valid': false});
    }
    return super.send(message);
  }
}

class _SqlMessages extends GroupMessageRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
  _SqlMessages(this.db);
  final Database db;

  @override
  Future<void> saveMessage(GroupMessage message) async {
    expect(await dbInsertGroupMessage(db, message.toMap()), isTrue);
  }

  @override
  Future<List<GroupMessage>> getMessagesPage(
    String groupId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final rows = await dbLoadGroupMessagesPage(
      db,
      groupId,
      limit: limit,
      offset: offset,
    );
    return rows
        .map((row) => GroupMessage.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  @override
  Future<GroupMessage?> getMessage(String id) async {
    final row = await dbLoadGroupMessage(db, id);
    return row == null
        ? null
        : GroupMessage.fromMap(Map<String, dynamic>.from(row));
  }
}

class _SqlMedia extends Fake
    implements MediaAttachmentRepository, MediaAttachmentByIdLookup {
  _SqlMedia(this.fixture);
  final _Fixture fixture;
  final readOwners = <MediaOwnerLane>[];

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async {
    expect(isInsideDbWriteTransaction(), isFalse);
    readOwners.add(owner);
    await fixture.expectCommittedMedia(messageId);
    final rows = await dbLoadMediaForMessage(
      fixture.db,
      messageId,
      ownerLane: owner.dbValue,
    );
    return rows
        .map((row) => MediaAttachment.fromMap(Map<String, dynamic>.from(row)))
        .toList();
  }

  @override
  Future<MediaAttachment?> getAttachmentById(String id) async {
    final row = await dbLoadMediaById(fixture.db, id);
    return row == null
        ? null
        : MediaAttachment.fromMap(Map<String, dynamic>.from(row));
  }
}

class _AllowDownloads implements MediaAutoDownloadDecider {
  @override
  Future<bool> shouldAutoDownload({
    required MediaConversationKind conversationKind,
    required MediaOwnerLane? storageOwner,
    required String mediaType,
    required String downloadStatus,
    bool userInitiated = false,
    bool isProtected = false,
  }) async => true;
}

class _Fixture {
  _Fixture(
    this.db,
    this.groups, {
    IdentityModel? localIdentity,
    String? transportPeerId,
  }) : identity = localIdentity ?? _receiverIdentity,
       localTransportPeerId = transportPeerId ?? _receiver.transportPeerId;
  final Database db;
  final GroupRepositoryImpl groups;
  final bridge = _ContentRejectBridge();
  static final _receiverIdentity = IdentityModel(
    peerId: _receiverAccount,
    publicKey: _receiver.deviceSigningPublicKey,
    privateKey: 'receiver-private',
    mnemonic12: 'host-test-only',
    mlKemPublicKey: _receiver.mlKemPublicKey,
    mlKemSecretKey: 'receiver-secret',
    createdAt: '2026-09-18T00:00:00Z',
    updatedAt: '2026-09-18T00:00:00Z',
  );
  final IdentityModel identity;
  final String localTransportPeerId;
  int pendingRepairCalls = 0;
  final operations = <String>[];
  final transferStarted = Completer<void>();
  final transferGate = Completer<void>();
  late final media = _SqlMedia(this);
  late final messageRows = _SqlMessages(db);
  late final retryOwner = RetryIncompleteGroupDownloadsUseCase(
    loadPage: ({required after, required limit}) async => throw StateError(
      'protected publication must use targeted recovery, not a sweep',
    ),
    loadCurrentAttachment: media.getAttachmentById,
    loadCurrentParent: messageRows.getMessage,
    loadCurrentGroup: groups.getGroup,
    autoDownloadDecider: _AllowDownloads(),
    transfer: ({required attachment, required parent, required group}) async =>
        throw StateError('strict custody cannot use legacy transfer'),
    strictTransfer:
        ({required attachment, required parent, required group}) async {
          expect(isInsideDbWriteTransaction(), isFalse);
          await expectCommittedMedia(parent.id);
          expect(group.id, _groupId);
          expect(attachment.messageId, parent.id);
          expect(attachment.ownerLane, MediaOwnerLane.group);
          expect(attachment.groupMediaBlobCustodyFingerprint, isNotNull);
          operations.add('strict-transfer:${attachment.id}');
          transferStarted.complete();
          await transferGate.future;
          return null; // Explicit network boundary: no download/ACK proof claimed.
        },
  );
  late final messages = GroupMessageListener(
    groupRepo: groups,
    msgRepo: messageRows,
    bridge: bridge,
    appendGroupEventLogEntry: append,
    mediaAttachmentRepo: media,
    getSelfPeerId: () async => identity.peerId,
    groupMediaDownloadCoordinator: retryOwner,
    getAppLifecycleState: () => AppLifecycleState.paused,
    beginGroupMediaReceiveCriticalTask: () async {
      operations.add('begin');
      return 'sql-media-lease';
    },
    endGroupMediaReceiveCriticalTask: (id) async => operations.add('end:$id'),
  );
  late final support = ProductionCanonicalProtectedGroupAuthoritySupport(
    database: db,
    bridge: bridge,
    groupRepository: groups,
  );
  late final keys = GroupKeyUpdateListener(
    groupKeyUpdateStream: const Stream<ChatMessage>.empty(),
    groupRepo: groups,
    bridge: bridge,
    getOwnMlKemSecretKey: () async => identity.mlKemSecretKey,
    getOwnPeerId: () async => identity.peerId,
    getOwnDeviceId: () async => _receiver.deviceId,
    appendGroupEventLogEntry: append,
  );
  late final composition = ProductionCanonicalProtectedGroupReplayComposition(
    database: db,
    bridge: bridge,
    groupRepository: groups,
    groupMessageListener: messages,
    groupKeyUpdateListener: keys,
    authoritySupport: support,
    loadIdentity: () async => identity,
    loadLinkedAuthority: (_) async => const LinkedInstallationAuthoritySnapshot(
      disposition: LinkedInstallationDisposition.primary,
      credential: null,
      failClosedReason: null,
    ),
    readCurrentTransportPeerId: () => localTransportPeerId,
    applySystemAuthorityReplay: (control, replayData, authority) =>
        applyProductionCanonicalProtectedSystemAuthorityReplay(
          control: control,
          replayData: replayData,
          authority: authority,
          groupRepository: groups,
          groupMessageListener: messages,
        ),
    retryPendingKeyRepairs: (_) async => pendingRepairCalls++,
  );

  static Future<_Fixture> create({
    bool seedGroup = true,
    IdentityModel? localIdentity,
    String? transportPeerId,
  }) async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        singleInstance: false,
        version: currentIdentityDatabaseVersion,
        onCreate: runProductionOnCreate,
      ),
    );
    final groups = GroupRepositoryImpl(
      dbInsertGroup: (row) => dbInsertGroup(db, row),
      dbLoadAllGroups: () => dbLoadAllGroups(db),
      dbLoadGroup: (id) => dbLoadGroup(db, id),
      dbUpdateGroup: (row) => dbUpdateGroup(db, row),
      dbDeleteGroup: (id) => dbDeleteGroup(db, id),
      dbLoadActiveGroups: () => dbLoadActiveGroups(db),
      dbArchiveGroup: (id) => dbArchiveGroup(db, id),
      dbUnarchiveGroup: (id) => dbUnarchiveGroup(db, id),
      dbAdvanceGroupMembershipWatermark:
          ({required groupId, required eventAt, required eventId}) =>
              dbAdvanceGroupMembershipWatermark(
                db,
                groupId: groupId,
                eventAt: eventAt,
                eventId: eventId,
              ),
      dbLoadSelfRemovedGroupFreshnessFloorFn: (id) =>
          dbLoadLatestSelfRemovedGroupFreshnessFloor(db, id),
      dbInsertGroupMember: (row) => dbInsertGroupMember(db, row),
      dbLoadAllGroupMembers: (id) => dbLoadAllGroupMembers(db, id),
      dbLoadGroupMember: (id, peer) => dbLoadGroupMember(db, id, peer),
      dbUpdateGroupMemberRole: (id, peer, role) =>
          dbUpdateGroupMemberRole(db, id, peer, role),
      dbDeleteGroupMember: (id, peer) => dbDeleteGroupMember(db, id, peer),
      dbDeleteAllGroupMembers: (id) => dbDeleteAllGroupMembers(db, id),
      dbInsertGroupKey: (row) => dbInsertGroupKey(db, row),
      dbCommitProtectedGroupKeyAuthority:
          ({
            required keyRow,
            required authorityCompleteSourcePeerId,
            required authorityCompleteSourceEventId,
            required authorityCompleteSourceTimestamp,
            required authorityCompletePayload,
          }) => dbCommitGroupKeyWithAuthorityComplete(
            db,
            keyRow: keyRow,
            authorityCompleteSourcePeerId: authorityCompleteSourcePeerId,
            authorityCompleteSourceEventId: authorityCompleteSourceEventId,
            authorityCompleteSourceTimestamp: authorityCompleteSourceTimestamp,
            authorityCompletePayload: authorityCompletePayload,
          ),
      dbLoadLatestGroupKey: (id) => dbLoadLatestGroupKey(db, id),
      dbLoadGroupKeyByGeneration: (id, epoch) =>
          dbLoadGroupKeyByGeneration(db, id, epoch),
      dbDeleteAllGroupKeys: (id) => dbDeleteAllGroupKeys(db, id),
      dbUpsertPendingGroupKeyRotation: (row) =>
          dbUpsertPendingGroupKeyRotation(db, row),
      dbLoadPendingGroupKeyRotation: (id) =>
          dbLoadPendingGroupKeyRotation(db, id),
      dbDeletePendingGroupKeyRotation: (id, epoch) =>
          dbDeletePendingGroupKeyRotation(db, id, epoch),
      groupKeyStore: FakeSecureKeyStore(),
    );

    final f = _Fixture(
      db,
      groups,
      localIdentity: localIdentity,
      transportPeerId: transportPeerId,
    );
    addTearDown(() async {
      if (!f.transferGate.isCompleted) f.transferGate.complete();
      await f.messages.stop();
      f.messages.dispose();
      f.keys.dispose();
      await db.close();
    });
    if (!seedGroup) return f;
    final joinedAt = _eventAt.subtract(const Duration(days: 1));
    await groups.saveGroup(
      GroupModel(
        id: _groupId,
        name: 'Composition fixture',
        type: GroupType.chat,
        topicName: 'composition-topic',
        createdAt: joinedAt,
        createdBy: _senderAccount,
        myRole: GroupRole.member,
      ),
    );
    for (final (account, device, role) in [
      (_senderAccount, _sender, MemberRole.admin),
      (_receiverAccount, _receiver, MemberRole.writer),
    ]) {
      await groups.saveMember(
        GroupMember(
          groupId: _groupId,
          peerId: account,
          username: account,
          role: role,
          publicKey: device.deviceSigningPublicKey,
          mlKemPublicKey: device.mlKemPublicKey,
          devices: [device],
          joinedAt: joinedAt,
        ),
      );
    }
    await groups.saveKey(
      GroupKeyInfo(
        groupId: _groupId,
        keyGeneration: 1,
        encryptedKey: 'original-key',
        createdAt: joinedAt,
      ),
    );
    return f;
  }

  Future<Map<String, Object?>> append({
    required String groupId,
    required String eventType,
    required String sourcePeerId,
    required String sourceEventId,
    required String sourceTimestamp,
    required Map<String, Object?> payload,
    DateTime? createdAt,
  }) => dbAppendGroupEventLogEntry(
    db,
    groupId: groupId,
    eventType: eventType,
    sourcePeerId: sourcePeerId,
    sourceEventId: sourceEventId,
    sourceTimestamp: sourceTimestamp,
    payload: payload,
    createdAt: createdAt,
  );

  Future<AuthenticatedGroupAuthorityProof?> proof(
    AuthenticatedGroupAuthorityPhase phase, {
    String eventId = _eventId,
  }) => loadAuthenticatedGroupAuthorityProofFromEventLog(
    loadRow: ({required groupId, required sourceEventId}) =>
        dbLoadGroupEventLogEntryExact(
          db,
          groupId: groupId,
          sourceEventId: sourceEventId,
        ),
    groupId: _groupId,
    phase: phase,
    eventId: eventId,
    verify: ({required publicKey, required data, required signature}) =>
        callVerifyPayload(
          bridge: bridge,
          publicKey: publicKey,
          data: data,
          signature: signature,
        ),
  );

  Future<ChatMessage> metadataMessage() async {
    const eventId = 'composition-metadata-snapshot';
    final at = _eventAt.subtract(const Duration(seconds: 1));
    final group = (await groups.getGroup(_groupId))!;
    final config = buildGroupConfigPayload(
      group.copyWith(lastMetadataEventAt: at),
      await groups.getMembers(_groupId),
    );
    final actorPayload = canonicalizeGroupEventLogPayload({
      'schemaVersion': 1,
      'eventType': 'group_metadata_updated',
      'groupId': _groupId,
      'updatedAt': at.toIso8601String(),
      'actor': {
        'peerId': _senderAccount,
        'username': _senderAccount,
        'publicKey': _sender.deviceSigningPublicKey,
      },
      'groupConfigVersion': config[groupConfigVersionField],
      'groupConfigStateHash': config[groupConfigStateHashField],
      'groupConfig': config,
    });
    final actorSigned = await callSignPayload(
      bridge: bridge,
      dataToSign: actorPayload,
      privateKey: 'sender-private',
    );
    final system = await signGroupSystemTransitionPayload(
      bridge: bridge,
      groupRepo: groups,
      groupId: _groupId,
      transitionType: 'group_metadata_updated',
      sourceEventId: eventId,
      eventAt: at,
      actorPeerId: _senderAccount,
      actorUsername: _senderAccount,
      actorSigningPublicKey: _sender.deviceSigningPublicKey,
      actorPrivateKey: 'sender-private',
      actorDeviceId: _sender.deviceId,
      actorTransportPeerId: _sender.transportPeerId,
      systemPayload: {
        '__sys': 'group_metadata_updated',
        'updatedAt': at.toIso8601String(),
        'groupConfig': config,
        'actorEvent': {
          'signedPayload': actorPayload,
          'signature': actorSigned['signature'],
          'signatureAlgorithm': 'ed25519',
        },
      },
    );
    final preparation = await buildProtectedGroupAuthorityRows(
      groupId: _groupId,
      transitionId: eventId,
      control: ProtectedGroupAuthorityControl.memberConfig,
      replayData: {
        'groupId': _groupId,
        'senderId': _senderAccount,
        'senderUsername': _senderAccount,
        'senderDeviceId': _sender.deviceId,
        'transportPeerId': _sender.transportPeerId,
        'keyEpoch': 1,
        'messageId': eventId,
        'text': jsonEncode(system),
        'timestamp': at.toIso8601String(),
      },
      keyEpoch: 1,
      actorAccountPeerId: _senderAccount,
      actorAccountPublicKey: _sender.deviceSigningPublicKey,
      actorAccountPrivateKey: 'sender-private',
      senderDevice: _sender,
      frozenRecipients: [_sender, _receiver],
      callSign: (data, key) =>
          callSignPayload(bridge: bridge, dataToSign: data, privateKey: key),
      callEncrypt: ({required recipientMlKemPublicKey, required plaintext}) =>
          callEncryptMessage(
            bridge: bridge,
            recipientMlKemPublicKey: recipientMlKemPublicKey,
            plaintext: plaintext,
          ),
      now: () => at,
    );
    return ChatMessage(
      from: _sender.transportPeerId,
      to: _receiver.transportPeerId,
      content: preparation.rows.single.sysText,
      timestamp: at.toIso8601String(),
      isIncoming: true,
    );
  }

  Future<void> applyAuthority() async {
    // A key-only proof contains no roster. Establish the signed historical
    // snapshot through the real system replay owner, never by seeding history.
    final snapshot = await composition.replay(await metadataMessage());
    expect(
      snapshot.disposition,
      ProtectedGroupReplayDisposition.applied,
      reason: snapshot.reasonCode,
    );
    final result = await composition.replay(await authorityMessage());
    expect(
      result.disposition,
      ProtectedGroupReplayDisposition.applied,
      reason: result.reasonCode,
    );
  }

  Future<List<DirectMediaBlobCustodyRow>> custody(String messageId) =>
      dbLoadGroupMediaBlobCustodyForMessage(
        db,
        groupId: _groupId,
        messageId: messageId,
      );

  Future<Map<String, Object?>> mediaSnapshot(String messageId) async => {
    'parent': await dbLoadGroupMessage(db, messageId),
    'attachments': await dbLoadMediaForMessage(
      db,
      messageId,
      ownerLane: MediaOwnerLane.group.dbValue,
    ),
    'custody': (await custody(messageId)).map((row) => row.toMap()).toList(),
  };

  Future<void> expectCommittedMedia(String messageId) async {
    final parent = await messageRows.getMessage(messageId);
    expect(parent, isNotNull);
    expect(parent!.groupId, _groupId);
    expect(parent.senderPeerId, _senderAccount);
    expect(parent.isIncoming, isTrue);
    final attachment = await media.getAttachmentById('$messageId-attachment');
    expect(attachment, isNotNull);
    expect(attachment!.downloadStatus, 'pending');
    expect(attachment.localPath, isNull);
    expect(attachment.ownerLane, MediaOwnerLane.group);
    expect(attachment.contentHash, _ciphertextHash);
    final row = (await custody(messageId)).single;
    expect(row.ownerLane, MediaBlobCustodyOwnerLane.group);
    expect(row.groupId, _groupId);
    expect(row.messageId, messageId);
    expect(row.attachmentId, attachment.id);
    expect(row.custodyBlobId, '$messageId-blob');
    expect(row.contentHash, _ciphertextHash);
    expect(row.ciphertextSize, 80);
    expect(row.direction, DirectMediaBlobCustodyDirection.incoming);
    expect(row.state, DirectMediaBlobCustodyState.incomingCommitted);
    expect(
      attachment.groupMediaBlobCustodyFingerprint,
      computeGroupMediaBlobCustodyFingerprint(
        groupId: _groupId,
        messageId: messageId,
        attachmentId: attachment.id,
        custodyBlobId: row.custodyBlobId,
        contentHash: row.contentHash,
        ciphertextSize: row.ciphertextSize,
        recipientPeerIds: [_receiver.transportPeerId],
      ),
    );
  }

  Future<ChatMessage> mediaMessage(
    String messageId, {
    AuthenticatedGroupAuthorityProof? authorityOverride,
  }) async {
    final authority =
        authorityOverride ??
        (await proof(AuthenticatedGroupAuthorityPhase.complete))!;
    final senderDevice = (await groups.getMember(
      _groupId,
      _senderAccount,
    ))!.devices.single;
    final timestamp = fixedGroupContentUtc(
      (authorityOverride?.eventAt ?? _eventAt).add(const Duration(seconds: 1)),
    );
    final manifest = ProtectedGroupMediaManifest(
      groupId: _groupId,
      messageId: messageId,
      attachments: [
        ProtectedGroupMediaAttachmentCommitment(
          attachmentId: '$messageId-attachment',
          custodyBlobId: '$messageId-blob',
          ciphertextSha256: _ciphertextHash,
          ciphertextSize: 80,
          mime: 'image/jpeg',
          mediaType: 'image',
          encryptionKeyBase64: base64Encode(List<int>.filled(32, 7)),
          encryptionNonce: base64Encode(List<int>.filled(12, 8)),
          targets: [
            GroupMediaBlobTargetCommitment(
              recipientPeerId: _receiver.transportPeerId,
              expiresAtMs: 2000000000000,
            ),
          ],
        ),
      ],
    );
    final envelope = await buildGroupOfflineReplayEnvelope(
      bridge: bridge,
      groupRepo: groups,
      groupId: _groupId,
      payloadType: groupOfflineReplayPayloadTypeMessage,
      plaintext: jsonEncode({
        'groupId': _groupId,
        'senderId': _senderAccount,
        'senderDeviceId': senderDevice.deviceId,
        'transportPeerId': senderDevice.transportPeerId,
        'messageId': messageId,
        'logicalDeliveryId': messageId,
        'keyEpoch': 2,
        'text': 'Protected media dispatch',
        'timestamp': timestamp,
      }),
      senderPeerId: _senderAccount,
      senderPublicKey: senderDevice.deviceSigningPublicKey,
      senderPrivateKey: 'sender-private',
      senderDeviceId: senderDevice.deviceId,
      senderTransportPeerId: senderDevice.transportPeerId,
      recipientPeerIds: [_receiver.transportPeerId],
      messageId: messageId,
      contentEventId: messageId,
      contentAuthorityVersion: GroupContentAuthorityVersion(
        eventAt: authority.eventAt,
        eventId: authority.eventId,
        keyEpoch: authority.keyEpoch,
      ),
      mediaManifest: manifest,
    );
    return ChatMessage(
      from: senderDevice.transportPeerId,
      to: _receiver.transportPeerId,
      content: envelope,
      timestamp: timestamp,
      isIncoming: true,
    );
  }

  Future<ChatMessage> authorityMessage() async {
    final canonical = canonicalGroupKeyUpdateSignedPayload(
      groupId: _groupId,
      sourcePeerId: _senderAccount,
      sourceDeviceId: _sender.deviceId,
      sourceTransportPeerId: _sender.transportPeerId,
      recipientPeerId: _receiverAccount,
      recipientDeviceId: _receiver.deviceId,
      recipientTransportPeerId: _receiver.transportPeerId,
      keyGeneration: 2,
      encryptedKey: 'rotated-key',
    );
    final audit = await signGroupTransitionAudit(
      bridge: bridge,
      groupRepo: groups,
      groupId: _groupId,
      transitionType: 'group_key_update',
      sourceEventId: _eventId,
      eventAt: _eventAt,
      actorPeerId: _senderAccount,
      actorUsername: _senderAccount,
      actorSigningPublicKey: _sender.deviceSigningPublicKey,
      actorPrivateKey: 'sender-private',
      actorDeviceId: _sender.deviceId,
      actorTransportPeerId: _sender.transportPeerId,
      transitionSubject: buildGroupKeyUpdateTransitionSubject(
        groupId: _groupId,
        sourcePeerId: _senderAccount,
        sourceDeviceId: _sender.deviceId,
        sourceTransportPeerId: _sender.transportPeerId,
        recipientPeerId: _receiverAccount,
        recipientDeviceId: _receiver.deviceId,
        recipientTransportPeerId: _receiver.transportPeerId,
        keyGeneration: 2,
        encryptedKey: 'rotated-key',
      ),
    );
    final signed = await callSignPayload(
      bridge: bridge,
      dataToSign: canonical,
      privateKey: 'sender-private',
    );
    final encrypted = await callEncryptMessage(
      bridge: bridge,
      recipientMlKemPublicKey: _receiver.mlKemPublicKey!,
      plaintext: jsonEncode({
        'groupId': _groupId,
        'sourceEventId': _eventId,
        'eventAt': _eventAt.toIso8601String(),
        'sourcePeerId': _senderAccount,
        'sourceDeviceId': _sender.deviceId,
        'sourceTransportPeerId': _sender.transportPeerId,
        'recipientPeerId': _receiverAccount,
        'recipientDeviceId': _receiver.deviceId,
        'recipientTransportPeerId': _receiver.transportPeerId,
        'keyGeneration': 2,
        'encryptedKey': 'rotated-key',
        'signatureAlgorithm': groupKeyUpdateSignatureAlgorithm,
        'signedPayload': canonical,
        'signature': signed['signature'],
        signedGroupTransitionAuditField: audit,
      }),
    );
    final keyEnvelope = jsonEncode({
      'type': 'group_key_update',
      'version': '2',
      'encrypted': {
        for (final k in ['kem', 'ciphertext', 'nonce']) k: encrypted[k],
      },
    });
    final prepared = await buildProtectedGroupAuthorityRows(
      groupId: _groupId,
      transitionId: _eventId,
      control: ProtectedGroupAuthorityControl.groupKeyUpdate,
      replayData: {
        'groupId': _groupId,
        'keyGeneration': 2,
        'encryptedKey': 'rotated-key',
        'from': _sender.transportPeerId,
        'to': _receiver.transportPeerId,
        'content': keyEnvelope,
        'timestamp': _eventAt.toIso8601String(),
      },
      keyEpoch: 2,
      actorAccountPeerId: _senderAccount,
      actorAccountPublicKey: _sender.deviceSigningPublicKey,
      actorAccountPrivateKey: 'sender-private',
      senderDevice: _sender,
      frozenRecipients: [_sender, _receiver],
      callSign: (data, key) =>
          callSignPayload(bridge: bridge, dataToSign: data, privateKey: key),
      callEncrypt: ({required recipientMlKemPublicKey, required plaintext}) =>
          callEncryptMessage(
            bridge: bridge,
            recipientMlKemPublicKey: recipientMlKemPublicKey,
            plaintext: plaintext,
          ),
      now: () => _eventAt,
    );
    expect(prepared.hasAuthenticatedAuthority, isTrue);
    expect(prepared.rows, hasLength(1));
    return ChatMessage(
      from: _sender.transportPeerId,
      to: _receiver.transportPeerId,
      content: prepared.rows.single.sysText,
      timestamp: _eventAt.toIso8601String(),
      isIncoming: true,
    );
  }
}

// Two real databases with generated production create/invite/authority frames.
// Crypto and delivery custody remain explicit host boundaries: accepted frames
// are queued byte-for-byte, then replayed through the actual receiver owner.
class _CreatedGroupFixture {
  _CreatedGroupFixture(this.sender, this.receiver, this.p2p, this.legacy);
  final _Fixture sender;
  final _Fixture receiver;
  final FakeP2PService p2p;
  final bool legacy;
  final requests = <ProtectedGroupAuthorityPrepareRequest>[];
  final delivered = <ChatMessage>[];
  final preparations = <ProtectedGroupAuthorityPreparation>[];
  int drained = 0;

  static Future<_CreatedGroupFixture> create({bool legacy = false}) async {
    final identity = IdentityModel(
      peerId: _senderAccount,
      publicKey: _sender.deviceSigningPublicKey,
      privateKey: 'sender-private',
      mnemonic12: 'explicit-host-crypto-fixture',
      mlKemPublicKey: _sender.mlKemPublicKey,
      mlKemSecretKey: 'sender-secret',
      username: _senderAccount,
      createdAt: '2026-09-18T00:00:00Z',
      updatedAt: '2026-09-18T00:00:00Z',
    );
    final sender = await _Fixture.create(
      seedGroup: false,
      localIdentity: identity,
      transportPeerId: legacy ? _senderAccount : _sender.transportPeerId,
    );
    final receiver = await _Fixture.create(
      seedGroup: false,
      transportPeerId: legacy ? _receiverAccount : _receiver.transportPeerId,
    );
    final p2p = FakeP2PService(
      initialState: NodeState(
        peerId: sender.localTransportPeerId,
        isStarted: true,
      ),
    );
    final f = _CreatedGroupFixture(sender, receiver, p2p, legacy);
    addTearDown(() {
      setProtectedGroupAuthorityAdapter();
      setReconcileCompletedProtectedGroupAuthority(sender.groups, null);
      p2p.dispose();
    });
    sender.bridge.responses['group:create'] = {
      'ok': true,
      'groupId': _groupId,
      'topicName': 'composition-topic',
      'groupKey': 'original-key',
      'keyEpoch': 1,
    };
    sender.bridge.responses['group:generateNextKey'] = {
      'ok': true,
      'groupKey': 'rotated-key',
      'keyEpoch': 2,
    };
    setReconcileCompletedProtectedGroupAuthority(
      sender.groups,
      sender.support.reconcileCompletedContentAuthority,
    );
    setProtectedGroupAuthorityAdapter(
      prepare: f.prepare,
      activate: f.activate,
      cancel: (_) async =>
          throw StateError('positive fixture may not abort authority'),
    );
    return f;
  }

  Future<ProtectedGroupAuthorityPreparation?> prepare(
    ProtectedGroupAuthorityPrepareRequest request,
  ) async {
    requests.add(request);
    final keyEpoch =
        request.control == ProtectedGroupAuthorityControl.groupKeyUpdate
        ? request.replayData['keyGeneration'] as int
        : (await sender.groups.getLatestKey(request.groupId))!.keyGeneration;
    final preparation = await buildProtectedGroupAuthorityRows(
      groupId: request.groupId,
      transitionId: request.transitionId,
      control: request.control,
      replayData: request.replayData,
      keyEpoch: keyEpoch,
      actorAccountPeerId: request.actorAccountPeerId,
      actorAccountPublicKey: request.actorAccountPublicKey,
      actorAccountPrivateKey: request.actorAccountPrivateKey,
      senderDevice: request.senderDevice,
      frozenRecipients: request.frozenRecipients,
      deliveryRecipients: request.deliveryRecipients,
      deliveryReplayDataByTransportPeerId:
          request.deliveryReplayDataByTransportPeerId,
      sharedAuthorityProof: request.sharedAuthorityProof,
      callSign: (data, key) => callSignPayload(
        bridge: sender.bridge,
        dataToSign: data,
        privateKey: key,
      ),
      callEncrypt: ({required recipientMlKemPublicKey, required plaintext}) =>
          callEncryptMessage(
            bridge: sender.bridge,
            recipientMlKemPublicKey: recipientMlKemPublicKey,
            plaintext: plaintext,
          ),
    );
    expect(preparation.hasAuthenticatedAuthority, isTrue);
    final proof = preparation.authorityProof!;
    expect(
      await dbInsertPendingGroupBroadcastsWithAuthorityPreparedAtomically(
        sender.db,
        groupId: request.groupId,
        rows: preparation.rows.map((row) => row.toMap()).toList(),
        authorityPreparedSourcePeerId: proof.actorAccountPeerId,
        authorityPreparedSourceEventId:
            authenticatedGroupAuthoritySourceEventId(
              AuthenticatedGroupAuthorityPhase.prepared,
              proof.eventId,
            ),
        authorityPreparedSourceTimestamp: fixedGroupAuthorityUtc(proof.eventAt),
        authorityPreparedPayload: authenticatedGroupAuthorityFactPayload(proof),
      ),
      isTrue,
    );
    preparations.add(preparation);
    return preparation;
  }

  Future<AuthenticatedGroupAuthorityProof?> loadProof({
    required String groupId,
    required AuthenticatedGroupAuthorityPhase phase,
    required String eventId,
  }) => sender.proof(phase, eventId: eventId);

  Future<void> appendProof({
    required AuthenticatedGroupAuthorityPhase phase,
    required AuthenticatedGroupAuthorityProof proof,
  }) async {
    await sender.append(
      groupId: proof.groupId,
      eventType: phase.eventType,
      sourcePeerId: proof.actorAccountPeerId,
      sourceEventId: authenticatedGroupAuthoritySourceEventId(
        phase,
        proof.eventId,
      ),
      sourceTimestamp: fixedGroupAuthorityUtc(proof.eventAt),
      payload: authenticatedGroupAuthorityFactPayload(proof),
    );
  }

  Future<bool> activate(
    ProtectedGroupAuthorityPreparation preparation, {
    required bool requireAllCustody,
  }) async {
    final proof = preparation.authorityProof!;
    if (preparation.control == ProtectedGroupAuthorityControl.memberAdd) {
      final completed = await recoverLocalPreparedProtectedSystemAuthority(
        proof: proof,
        groupRepository: sender.groups,
        verifyAuthorityProof:
            ({required publicKey, required data, required signature}) =>
                callVerifyPayload(
                  bridge: sender.bridge,
                  publicKey: publicKey,
                  data: data,
                  signature: signature,
                ),
        loadAuthorityProof: loadProof,
        appendAuthorityProof: appendProof,
        applyReplay: (control, data, authority) =>
            applyProductionCanonicalProtectedSystemAuthorityReplay(
              control: control,
              replayData: data,
              authority: authority,
              groupRepository: sender.groups,
              groupMessageListener: sender.messages,
            ),
      );
      expect(
        completed,
        isTrue,
        reason:
            'real local listener must complete the actual signed membership projection',
      );
    }
    final complete = await sender.proof(
      AuthenticatedGroupAuthorityPhase.complete,
      eventId: proof.eventId,
    );
    expect(
      complete,
      isNotNull,
      reason: 'delivery follows durable canonical completion',
    );
    expect(sameAuthenticatedGroupAuthorityProof(complete!, proof), isTrue);
    expect(
      await sender.support.reconcileCompletedContentAuthority(complete),
      isTrue,
    );
    for (final row in preparation.rows) {
      expect(row.recipientPeerIds, [_receiver.transportPeerId]);
      // The only network fake: authenticated inbox custody accepts these exact
      // generated bytes. No receiver key/history/media row is written here.
      delivered.add(
        ChatMessage(
          from: sender.localTransportPeerId,
          to: row.recipientPeerIds.single,
          content: row.sysText,
          timestamp: proof.eventAt.toIso8601String(),
          isIncoming: true,
        ),
      );
      await dbDeletePendingGroupBroadcast(sender.db, row.id);
    }
    return true;
  }

  Future<void> createAndAcceptInvite() async {
    final now = DateTime.now().toUtc().toIso8601String();
    final contact = ContactModel(
      peerId: _receiverAccount,
      publicKey: _receiver.deviceSigningPublicKey,
      rendezvous: '/dns4/fixture/tcp/4001/p2p/fixture',
      username: _receiverAccount,
      signature: 'explicit-host-contact',
      scannedAt: now,
      mlKemPublicKey: _receiver.mlKemPublicKey,
    );
    final result = await createGroupWithMembers(
      bridge: sender.bridge,
      groupRepo: sender.groups,
      p2pService: p2p,
      identity: sender.identity,
      selectedContacts: [contact],
      selectedContactDeviceBindings: legacy
          ? const {}
          : {
              _receiverAccount: _receiver.copyWith(
                keyPackageId: defaultGroupWelcomeKeyPackageIdForDevice(
                  _receiver.deviceId,
                ),
                keyPackagePublicMaterial: _receiver.mlKemPublicKey,
              ),
            },
      type: GroupType.chat,
      name: 'Created group authority application',
      appendGroupEventLogEntry: sender.append,
    );
    expect(result.group.id, _groupId);
    expect(result.membersAdded, 1);
    expect(result.invitesSent, 1);
    expect(result.membershipSyncRolledBack, isFalse);
    final invite = p2p.sentMessageLog.singleWhere(
      (entry) =>
          GroupInvitePayload.parseEncryptedEnvelope(entry.content) != null,
    );
    final contacts = InMemoryContactRepository()
      ..addTestContact(
        ContactModel(
          peerId: _senderAccount,
          publicKey: _sender.deviceSigningPublicKey,
          rendezvous: '/dns4/fixture/tcp/4001/p2p/fixture',
          username: _senderAccount,
          signature: 'explicit-host-contact',
          scannedAt: now,
          mlKemPublicKey: _sender.mlKemPublicKey,
        ),
      );
    expect(await receiver.groups.getGroup(_groupId), isNull);
    final accepted = await handleIncomingGroupInvite(
      message: ChatMessage(
        from: sender.localTransportPeerId,
        to: receiver.localTransportPeerId,
        content: invite.content,
        timestamp: now,
        isIncoming: true,
      ),
      groupRepo: receiver.groups,
      contactRepo: contacts,
      bridge: receiver.bridge,
      ownPeerId: receiver.identity.peerId,
      ownMlKemSecretKey: receiver.identity.mlKemSecretKey,
      ownDeviceId: legacy ? null : _receiver.deviceId,
      ownTransportPeerId: legacy ? null : _receiver.transportPeerId,
      ownMlKemPublicKey: _receiver.mlKemPublicKey,
      ownKeyPackageId: legacy
          ? null
          : defaultGroupWelcomeKeyPackageIdForDevice(_receiver.deviceId),
      ownKeyPackagePublicMaterial: legacy ? null : _receiver.mlKemPublicKey,
    );
    expect(accepted.$1, HandleGroupInviteResult.success);
    expect(accepted.$2, _groupId);
    expect((await receiver.groups.getLatestKey(_groupId))!.keyGeneration, 1);
    expect(
      await receiver.db.query('group_event_log'),
      isEmpty,
      reason: 'the ordinary invite is not fabricated authenticated history',
    );
    if (!legacy) {
      final membership = requests.singleWhere(
        (r) => r.control == ProtectedGroupAuthorityControl.memberAdd,
      );
      final invitedGroup = (await receiver.groups.getGroup(_groupId))!;
      expect(
        invitedGroup.lastMembershipEventAt,
        DateTime.parse(membership.replayData['timestamp'] as String),
        reason:
            'ordinary signed invitation carries the exact membership instant',
      );
      expect(
        invitedGroup.lastMembershipEventId,
        membership.replayData['messageId'],
        reason: 'signed invitation preserves the committed membership version',
      );
    }
    await drain(
      expected: legacy
          ? ProtectedGroupReplayDisposition.applied
          : ProtectedGroupReplayDisposition.duplicate,
    );
  }

  Future<void> drain({
    ProtectedGroupReplayDisposition expected =
        ProtectedGroupReplayDisposition.applied,
  }) async {
    while (drained < delivered.length) {
      final result = await receiver.composition.replay(delivered[drained++]);
      expect(result.disposition, expected, reason: result.reasonCode);
    }
  }

  Future<AuthenticatedGroupAuthorityProof> rotate() async {
    final outcome = await rotateAndDistributeGroupKey(
      bridge: sender.bridge,
      groupRepo: sender.groups,
      groupId: _groupId,
      selfPeerId: sender.identity.peerId,
      senderPublicKey: sender.identity.publicKey,
      senderPrivateKey: sender.identity.privateKey,
      senderUsername: sender.identity.username,
      sourceDeviceId: sender.localTransportPeerId,
      sendP2PMessage: p2p.sendMessage,
      storeP2PMessageInInbox: (peer, text) => p2p.storeInInbox(peer, text),
    );
    expect(outcome.rotated, isTrue);
    expect(outcome.fullyDistributed, isTrue);
    expect(outcome.distributedDeviceCount, 1);
    await drain();
    final preparation = preparations.singleWhere(
      (p) => p.control == ProtectedGroupAuthorityControl.groupKeyUpdate,
    );
    final proof = (await receiver.proof(
      AuthenticatedGroupAuthorityPhase.complete,
      eventId: preparation.authorityProof!.eventId,
    ))!;
    expect(proof.keyEpoch, 2);
    expect((await receiver.groups.getLatestKey(_groupId))!.keyGeneration, 2);
    final reconciliation = await dbLoadGroupEventLogEntryExact(
      receiver.db,
      groupId: _groupId,
      sourceEventId: protectedGroupContentReconciliationCompleteSourceEventId(
        proof.eventId,
      ),
    );
    expect(
      isProtectedGroupContentReconciliationCompleteRow(
        reconciliation,
        authority: proof,
      ),
      isTrue,
    );
    return proof;
  }
}
