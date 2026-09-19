import 'package:flutter_app/core/database/helpers/group_message_local_deletions_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_media_key_snapshot.dart';
import 'package:flutter_app/features/groups/data/repositories/group_message_repository_impl.dart';
import '../../shared/fixtures/media_repository_real_db_fixture.dart';
import 'dart:async';
import 'package:flutter_app/features/groups/application/protected_group_content_receive.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/app/bootstrap/production_canonical_group_replay_composition.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/database/helpers/group_event_log_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/groups_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_members_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_keys_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/pending_group_broadcasts_db_helpers.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/groups/application/protected_group_authority.dart';
import 'package:flutter_app/features/groups/application/protected_group_authority_history.dart';
import 'package:flutter_app/features/groups/application/protected_group_content_authoring_resolver.dart';
import 'package:flutter_app/features/groups/data/repositories/group_repository_impl.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';
import '../secure_storage/fake_secure_key_store.dart';
import '../../shared/fakes/in_memory_contact_repository.dart';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/features/groups/application/protected_group_media_manifest.dart';
import 'package:flutter_app/core/debug/group_media_reliability_e2e.dart';
import 'package:flutter_app/core/debug/group_media_reliability_authority_target.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/config/direct_linked_devices_flag.dart';
import 'package:flutter_app/core/debug/group_media_reliability_e2e_main_actions.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import '../bridge/fake_bridge.dart';
import '../services/fake_p2p_service.dart';
import '../../shared/fakes/fake_media_file_manager.dart';
import '../../shared/fakes/in_memory_group_repository.dart';
import '../../shared/fakes/in_memory_group_message_repository.dart';
import '../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../features/identity/domain/repositories/fake_identity_repository.dart';

class _Media extends FakeMediaFileManager {
  @override
  Future<String> copyToDurableStorage({
    required String sourceFilePath,
    required String messageId,
    required String attachmentId,
    required String mime,
  }) async {
    final relative = await super.copyToDurableStorage(
      sourceFilePath: sourceFilePath,
      messageId: messageId,
      attachmentId: attachmentId,
      mime: mime,
    );
    await File(sourceFilePath).copy(await resolveStoredPath(relative));
    return relative;
  }
}

class _Recorder extends Fake implements AudioRecorderService {
  @override
  bool get isRecording => false;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  _registerCanonicalAuthorityTests();
  _registerRealSqlMp4PreparationTests();
  for (final resolution in [
    'strict',
    'refused',
    'upload_error',
    'publication_error',
    'legacy',
  ]) {
    test('P269 sender canonical custody $resolution', () async {
      final dir = await Directory.systemTemp.createTemp('p269-diagnosis-');
      addTearDown(() => dir.delete(recursive: true));
      final identity = FakeIdentityRepository.makeIdentity(
        peerId: 'account-author',
        mlKemPublicKey: 'kem-author',
      );
      final groups = InMemoryGroupRepository();
      final at = DateTime.utc(2026, 9, 1);
      await groups.saveGroup(
        GroupModel(
          id: 'group-proof',
          name: 'fixture',
          type: GroupType.chat,
          topicName: 'topic-proof',
          createdAt: at,
          createdBy: identity.peerId,
          myRole: GroupRole.admin,
        ),
      );
      await groups.saveKey(
        GroupKeyInfo(
          groupId: 'group-proof',
          keyGeneration: 1,
          encryptedKey: 'key',
          createdAt: at,
        ),
      );
      for (final author in [true, false]) {
        final account = author ? identity.peerId : 'account-receiver';
        final transport = resolution == 'legacy'
            ? account
            : author
            ? 'transport-author'
            : 'transport-receiver';
        await groups.saveMember(
          GroupMember(
            groupId: 'group-proof',
            peerId: account,
            username: 'fixture',
            role: author ? MemberRole.admin : MemberRole.writer,
            publicKey: author ? identity.publicKey : 'pk-receiver',
            joinedAt: at,
            devices: resolution == 'legacy'
                ? []
                : [
                    GroupMemberDeviceIdentity(
                      deviceId: transport,
                      transportPeerId: transport,
                      deviceSigningPublicKey: author
                          ? identity.publicKey
                          : 'pk-receiver',
                    ),
                  ],
          ),
        );
      }
      setGroupContentAuthoringResolver(
        groups,
        ({
          required groupId,
          required senderPeerId,
          required senderPublicKey,
          senderDeviceId,
          senderTransportPeerId,
        }) async => resolution == 'legacy'
            ? (
                kind: GroupContentAuthoringResolutionKind.legacyUninitialized,
                context: null,
              )
            : resolution == 'refused'
            ? (kind: GroupContentAuthoringResolutionKind.refuse, context: null)
            : (
                kind: GroupContentAuthoringResolutionKind.strict,
                context: GroupContentAuthoringContext(
                  directLinkedDeviceSelector:
                      const DirectLinkedDeviceSelector.enabled(),
                  multiDeviceSyncEnabled: true,
                  authorityVersion: GroupContentAuthorityVersion(
                    eventAt: at,
                    eventId: 'authority-event',
                    keyEpoch: 1,
                  ),
                  inboxStore: _Inbox(fail: resolution == 'publication_error'),
                ),
              ),
      );
      addTearDown(() => setGroupContentAuthoringResolver(groups, null));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => dir.path,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              null,
            ),
      );
      final bridge = _StrictBridge(fail: resolution == 'upload_error');
      final media = _StrictGroupBlobRepository();
      final messages = _StrictContentMessageRepository(
        onCompleted: () async {
          // Canonical strict completion retires custody; the raw staged
          // attachment projection remains upload_pending in real SQLite.
          media.rows.clear();
        },
      );
      Object? failure;
      Map<String, Object?>? proof;
      try {
        proof = await sendGroupKilledIncomingJpegReliabilityFixture(
          runId: 'diagnosis-strict',
          groupId: 'group-proof',
          messageId: 'message-jpeg-strict',
          attachmentId: 'blob-jpeg-strict',
          receiverAccountPeerId: 'account-receiver',
          receiverTransportPeerId: resolution == 'legacy'
              ? 'account-receiver'
              : 'transport-receiver',
          fixtureDirectory: dir,
          bridge: bridge,
          p2pService: FakeP2PService(
            initialState: NodeState(
              isStarted: true,
              peerId: resolution == 'legacy'
                  ? 'account-author'
                  : 'transport-author',
            ),
          ),
          identityRepository: FakeIdentityRepository()..seed(identity),
          groupRepository: groups,
          groupConfigBuilder: (_, _) => <String, dynamic>{},
          groupMessageRepository: messages,
          mediaAttachmentRepository: media,
          mediaFileManager: _Media(),
          audioRecorderService: _Recorder(),
          authorityMode: resolution == 'legacy'
              ? GroupMediaReliabilityAuthorityMode.accountBoundLegacy
              : GroupMediaReliabilityAuthorityMode.distinctAccountAndTransport,
        );
      } catch (error) {
        failure = error;
      }
      if (resolution == 'refused' ||
          resolution == 'upload_error' ||
          resolution == 'publication_error') {
        expect(failure, isA<GroupMediaReliabilitySenderFailure>());
        final typed = failure! as GroupMediaReliabilitySenderFailure;
        expect(
          typed.stage,
          resolution == 'refused'
              ? 'authority_admission'
              : resolution == 'upload_error'
              ? 'strict_preparation'
              : 'strict_publication',
        );
        expect(bridge.legacyUploads, 0);
        if (resolution == 'refused') {
          expect(bridge.strictUploads, 0);
          expect(media.stageCalls, 0);
        }
        expect(proof, isNull);
        return;
      }
      if (resolution == 'legacy') {
        expect(failure, isNull);
        expect(bridge.strictUploads, 0);
        expect(bridge.legacyUploads, 1);
        expect(proof!['strictMediaCustody'], isNull);
        expect(proof['publicationsPerMessage'], {'jpeg': 1});
        return;
      }
      expect(
        failure,
        isNull,
        reason: 'initialized authority must use its canonical producer',
      );
      expect(proof!['publicationsPerMessage'], {'jpeg': 1});
      expect(bridge.strictUploads, 1);
      expect(bridge.legacyUploads, 0);
      expect(
        bridge.commandLog.where(
          (c) => c == 'group:publish' || c == 'group:sendReliable',
        ),
        isEmpty,
      );
      expect(messages.protectedEvidence, hasLength(2));
      expect(media.rows, isEmpty);
      expect(proof['strictMediaCustody'], isNotNull);
    });
  }
}

class _StrictContentMessageRepository extends InMemoryGroupMessageRepository
    implements
        GroupInboxStoreRetryPayloadCasRepository,
        GroupMessageStrictContentCompletionRepository,
        GroupMessageStrictLocalTerminalRepository,
        GroupMessageStrictPreparedRepository {
  _StrictContentMessageRepository({this.onCompleted});
  final Future<void> Function()? onCompleted;
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
    await onCompleted?.call();
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

final class _StrictGroupBlobRepository extends InMemoryMediaAttachmentRepository
    implements
        GroupMediaBlobCustodyRepository,
        GroupMediaBlobArtifactReferenceInventoryRepository {
  final List<DirectMediaBlobCustodyRow> rows = <DirectMediaBlobCustodyRow>[];
  bool stageCompleted = false;
  int stageCalls = 0;

  @override
  bool get supportsGroupMediaBlobCustody => true;

  @override
  Future<T> runGroupMediaBlobCustodyLifecycle<T>(Future<T> Function() action) =>
      action();

  @override
  Future<GroupMediaBlobCustodyStageOutcome>
  stageFreshOutgoingGroupMediaBlobGeneration({
    required GroupMessage parent,
    required List<MediaAttachment> attachments,
    required List<DirectMediaBlobCustodyRow> custodyRows,
    required Map<String, String> custodyBlobIdsByAttachmentId,
  }) async {
    stageCalls++;
    if (rows.isNotEmpty) return GroupMediaBlobCustodyStageOutcome.refused;
    expect(
      custodyBlobIdsByAttachmentId.keys.toSet(),
      attachments.map((attachment) => attachment.id).toSet(),
    );
    for (final attachment in attachments) {
      await saveAttachment(attachment, owner: MediaOwnerLane.group);
    }
    rows.addAll(custodyRows);
    stageCompleted = true;
    return GroupMediaBlobCustodyStageOutcome.applied;
  }

  @override
  Future<List<DirectMediaBlobCustodyRow>> loadGroupMediaBlobCustodyForMessage({
    required String groupId,
    required String messageId,
  }) async => rows
      .where((row) => row.groupId == groupId && row.messageId == messageId)
      .toList(growable: false);

  @override
  Future<List<DirectMediaBlobCustodyRow>> loadGroupMediaBlobCustodyByStates(
    Set<DirectMediaBlobCustodyState> states, {
    int limit = 50,
  }) async => rows
      .where((row) => states.contains(row.state))
      .take(limit)
      .toList(growable: false);

  @override
  Future<DirectMediaBlobCustodyRow?> loadGroupMediaBlobCustodyForTarget({
    required String groupId,
    required String attachmentId,
    required String custodyBlobId,
    required DirectMediaBlobCustodyDirection direction,
    String? recipientPeerId,
  }) async {
    for (final row in rows) {
      if (row.groupId == groupId &&
          row.attachmentId == attachmentId &&
          row.custodyBlobId == custodyBlobId &&
          row.direction == direction &&
          row.recipientPeerId == recipientPeerId) {
        return row;
      }
    }
    return null;
  }

  @override
  Future<bool> transitionGroupMediaBlobCustodyIfExact({
    required DirectMediaBlobCustodyRow expected,
    required DirectMediaBlobCustodyRow next,
  }) async {
    final index = rows.indexWhere(
      (row) => row.exactDatabaseProjectionMatches(expected),
    );
    if (index < 0 || !expected.canTransitionTo(next)) return false;
    rows[index] = next;
    return true;
  }

  @override
  Future<bool> deleteGroupMediaBlobCleanupPendingIfExact(
    DirectMediaBlobCustodyRow expected,
  ) async {
    final index = rows.indexWhere(
      (row) => row.exactDatabaseProjectionMatches(expected),
    );
    if (index < 0 ||
        expected.state != DirectMediaBlobCustodyState.outgoingCleanupPending) {
      return false;
    }
    rows.removeAt(index);
    return true;
  }

  @override
  Future<Set<String>> loadGroupMediaBlobArtifactRelativePaths() async =>
      rows.map((row) => row.ciphertextRelativePath).whereType<String>().toSet();

  @override
  Future<bool> commitIncomingGroupMediaBlobLocalPath({
    required MediaAttachment expectedAttachment,
    required DirectMediaBlobCustodyRow expectedCustody,
    required String localPath,
    required String sourceRelayPeerId,
    required String updatedAt,
    required int nowMs,
  }) async => false;

  @override
  Future<bool> terminalizeIncomingGroupMediaBlobForLocalDeletion({
    required MediaAttachment expectedAttachment,
    required DirectMediaBlobCustodyRow expectedCustody,
    required String sourceRelayPeerId,
    required String updatedAt,
  }) async => false;

  @override
  Future<bool> deleteIncomingGroupMediaBlobAckPendingIfExact(
    DirectMediaBlobCustodyRow expected,
  ) async => false;

  @override
  Future<bool> deleteIncomingGroupMediaBlobIfExpired({
    required DirectMediaBlobCustodyRow expected,
    required int nowMs,
  }) async => false;

  @override
  Future<int> countOtherGroupMediaBlobCustodyRowsReferencingArtifact(
    DirectMediaBlobCustodyRow expected,
  ) async => rows
      .where(
        (row) =>
            !row.exactDatabaseProjectionMatches(expected) &&
            row.ciphertextRelativePath == expected.ciphertextRelativePath,
      )
      .length;
}

class _Inbox
    implements AckOrExpiryInboxStore, GroupContentExpiryBoundedInboxStore {
  _Inbox({this.fail = false});
  final bool fail;
  @override
  Future<InboxStoreOutcome> storeInAckCustodyInboxDetailed(
    String toPeerId,
    String message, {
    required AckCustodyKind custodyKind,
    int? timeoutMs,
  }) async => const InboxStoreOutcome(
    status: InboxStoreStatus.stored,
    storeStatus: 'stored',
    custodyContract: ackOrExpiryInboxCustodyContract,
  );
  @override
  Future<InboxStoreOutcome> storeInGroupContentExpiryBoundedInboxDetailed(
    String toPeerId,
    String message, {
    required int custodyExpiresAtOrBeforeMs,
    int? timeoutMs,
  }) async => fail
      ? const InboxStoreOutcome(status: InboxStoreStatus.failed)
      : InboxStoreOutcome(
          status: InboxStoreStatus.stored,
          storeStatus: 'stored',
          custodyContract: ackOrExpiryInboxCustodyContract,
          expiresAtMs: custodyExpiresAtOrBeforeMs,
        );
}

class _StrictBridge extends FakeBridge {
  _StrictBridge({this.fail = false});
  final bool fail;
  int strictUploads = 0, legacyUploads = 0;
  @override
  Future<String> send(String message) async {
    final decoded = jsonDecode(message) as Map<String, dynamic>;
    if (decoded['cmd'] == 'media:upload') {
      final p = decoded['payload'] as Map<String, dynamic>;
      if (p['custodyKind'] == groupMediaBlobCustodyKind) {
        strictUploads++;
        if (fail) return jsonEncode({'ok': false, 'error': 'fixture_failed'});
        return jsonEncode({
          'ok': true,
          'id': p['id'],
          'storeStatus': 'stored',
          'custodyKind': groupMediaBlobCustodyKind,
          'custodyContract': groupMediaBlobCustodyContract,
          'contentHash': p['contentHash'],
          'size': File(p['filePath'] as String).lengthSync(),
          'mime': groupMediaBlobTransportMime,
          'expiresAtMs': DateTime.now()
              .add(const Duration(days: 1))
              .millisecondsSinceEpoch,
          'custodyRelayPeerId': 'relay-fixture',
        });
      }
      legacyUploads++;
    }
    return super.send(message);
  }
}

// Real SQL owns the key, PREPARED/COMPLETE facts, pending delivery and
// reconciliation. Only the cryptographic engine and remote transport are fakes.
class _CanonicalAuthorityFixture {
  _CanonicalAuthorityFixture(this.db, this.groups);

  final Database db;
  final GroupRepositoryImpl groups;
  final bridge = PassthroughCryptoBridge();
  final identity = FakeIdentityRepository.makeIdentity(
    peerId: 'creator-account',
    mlKemPublicKey: 'creator-kem',
  );
  late final identities = FakeIdentityRepository()..seed(identity);
  final p2p = FakeP2PService(
    initialState: const NodeState(isStarted: true, peerId: 'creator-transport'),
  );
  late final support = ProductionCanonicalProtectedGroupAuthoritySupport(
    database: db,
    bridge: bridge,
    groupRepository: groups,
  );
  int completeCommitsObservedBeforeDelivery = 0;
  Future<void> Function()? beforeSettledRead;

  static Future<_CanonicalAuthorityFixture> create({Database? database}) async {
    sqfliteFfiInit();
    final db =
        database ??
        await databaseFactoryFfi.openDatabase(
          inMemoryDatabasePath,
          options: OpenDatabaseOptions(
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
    final fixture = _CanonicalAuthorityFixture(db, groups);
    addTearDown(() async {
      setProtectedGroupAuthorityAdapter();
      setReconcileCompletedProtectedGroupAuthority(groups, null);
      setGroupContentAuthoringResolver(groups, null);
      if (database == null) await db.close();
    });
    await fixture.initialize();
    return fixture;
  }

  Future<bool> verify({
    required String publicKey,
    required String data,
    required String signature,
  }) => callVerifyPayload(
    bridge: bridge,
    publicKey: publicKey,
    data: data,
    signature: signature,
  );

  Future<AuthenticatedGroupAuthorityProof?> exactComplete(String eventId) =>
      loadAuthenticatedGroupAuthorityProofFromEventLog(
        loadRow: ({required groupId, required sourceEventId}) =>
            dbLoadGroupEventLogEntryExact(
              db,
              groupId: groupId,
              sourceEventId: sourceEventId,
            ),
        groupId: 'fixture-group',
        phase: AuthenticatedGroupAuthorityPhase.complete,
        eventId: eventId,
        verify: verify,
      );

  Future<AuthenticatedGroupAuthorityProof?> settled(String groupId) async {
    await beforeSettledRead?.call();
    if (await support.hasUnfinishedContentAuthority(groupId)) return null;
    final rows = await loadAuthenticatedGroupAuthorityProofPage(
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
      groupId: groupId,
      phase: AuthenticatedGroupAuthorityPhase.complete,
      verify: verify,
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final proof = rows.single;
    final reconciliation = await dbLoadGroupEventLogEntryExact(
      db,
      groupId: groupId,
      sourceEventId: protectedGroupContentReconciliationCompleteSourceEventId(
        proof.eventId,
      ),
    );
    if (!isProtectedGroupContentReconciliationCompleteRow(
      reconciliation,
      authority: proof,
    )) {
      return null;
    }
    return (await groups.getLatestKey(groupId))?.keyGeneration == proof.keyEpoch
        ? proof
        : null;
  }

  Future<void> initialize() async {
    bridge.responses['group:create'] = {
      'ok': true,
      'groupId': 'fixture-group',
      'topicName': 'fixture-topic',
      'groupKey': 'fixture-key',
      'keyEpoch': 1,
    };
    bridge.responses['group:generateNextKey'] = {
      'ok': true,
      'groupKey': 'rotated-key',
      'keyEpoch': 2,
    };
    final contacts = InMemoryContactRepository()
      ..addTestContact(
        ContactModel(
          peerId: 'receiver-account',
          publicKey: 'receiver-pk',
          rendezvous: '/dns4/fixture/tcp/4001/p2p/fixture',
          username: 'receiver',
          signature: 'fixture',
          scannedAt: DateTime.now().toUtc().toIso8601String(),
          mlKemPublicKey: 'receiver-kem',
        ),
      );
    await setupGroupMediaReliabilitySender(
      receiverAccountPeerId: 'receiver-account',
      receiverTransportPeerId: 'receiver-transport',
      bridge: bridge,
      p2pService: p2p,
      identityRepository: identities,
      contactRepository: contacts,
      groupRepository: groups,
      appendGroupEventLogEntry:
          ({
            required groupId,
            required eventType,
            required payload,
            required sourcePeerId,
            required sourceEventId,
            required sourceTimestamp,
            createdAt,
          }) => dbAppendGroupEventLogEntry(
            db,
            groupId: groupId,
            eventType: eventType,
            payload: payload,
            sourcePeerId: sourcePeerId,
            sourceEventId: sourceEventId,
            sourceTimestamp: sourceTimestamp,
            createdAt: createdAt,
          ),
    );
    expect((await db.query('group_event_log')).map((r) => r['event_type']), [
      'group_created',
    ]);
    setGroupContentAuthoringResolver(
      groups,
      buildProtectedGroupContentAuthoringResolver(
        loadIdentity: () async =>
            (peerId: identity.peerId, publicKey: identity.publicKey),
        loadMember: groups.getMember,
        loadInstallationAuthority: (_) async =>
            const LinkedInstallationAuthoritySnapshot(
              disposition: LinkedInstallationDisposition.primary,
              credential: null,
              failClosedReason: null,
            ),
        loadLatestSettledAuthority: settled,
        readCurrentTransportPeerId: () => p2p.currentState.peerId,
        inboxStore: _Inbox(),
        directLinkedDeviceSelector: const DirectLinkedDeviceSelector.enabled(),
        multiDeviceSyncEnabled: true,
      ),
    );
    setReconcileCompletedProtectedGroupAuthority(
      groups,
      support.reconcileCompletedContentAuthority,
    );
    setProtectedGroupAuthorityAdapter(
      prepare: (request) async {
        final preparation = await buildProtectedGroupAuthorityRows(
          groupId: request.groupId,
          transitionId: request.transitionId,
          control: request.control,
          replayData: request.replayData,
          keyEpoch: request.replayData['keyGeneration'] as int,
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
            bridge: bridge,
            dataToSign: data,
            privateKey: key,
          ),
          callEncrypt:
              ({required recipientMlKemPublicKey, required plaintext}) =>
                  callEncryptMessage(
                    bridge: bridge,
                    recipientMlKemPublicKey: recipientMlKemPublicKey,
                    plaintext: plaintext,
                  ),
          now: () => DateTime.parse(request.replayData['timestamp'] as String),
        );
        final proof = preparation.authorityProof!;
        final inserted =
            await dbInsertPendingGroupBroadcastsWithAuthorityPreparedAtomically(
              db,
              groupId: request.groupId,
              rows: preparation.rows.map((r) => r.toMap()).toList(),
              authorityPreparedSourcePeerId: proof.actorAccountPeerId,
              authorityPreparedSourceEventId:
                  authenticatedGroupAuthoritySourceEventId(
                    AuthenticatedGroupAuthorityPhase.prepared,
                    proof.eventId,
                  ),
              authorityPreparedSourceTimestamp: fixedGroupAuthorityUtc(
                proof.eventAt,
              ),
              authorityPreparedPayload: authenticatedGroupAuthorityFactPayload(
                proof,
              ),
            );
        return inserted ? preparation : null;
      },
      activate: (preparation, {required requireAllCustody}) async {
        final persisted = await exactComplete(
          preparation.authorityProof!.eventId,
        );
        if (persisted == null ||
            !sameAuthenticatedGroupAuthorityProof(
              persisted,
              preparation.authorityProof!,
            )) {
          return false;
        }
        completeCommitsObservedBeforeDelivery++;
        for (final row in preparation.rows) {
          if (!await p2p.sendMessage(
            row.recipientPeerIds.single,
            row.sysText,
          )) {
            return false;
          }
          await dbDeletePendingGroupBroadcast(db, row.id);
        }
        return (await db.query('pending_group_broadcasts')).isEmpty;
      },
      cancel: (_) async => false,
    );
  }

  Future<Map<String, Object?>> observe() => probeGroupMediaReliabilityAuthority(
    groupId: 'fixture-group',
    p2pService: p2p,
    identityRepository: identities,
    groupRepository: groups,
  );

  Future<Map<String, Object?>> refresh() =>
      refreshGroupMediaReliabilitySenderAuthority(
        groupId: 'fixture-group',
        receiverAccountPeerId: 'receiver-account',
        receiverTransportPeerId: 'receiver-transport',
        bridge: bridge,
        p2pService: p2p,
        identityRepository: identities,
        groupRepository: groups,
      );
}

void _registerCanonicalAuthorityTests() {
  test(
    'P269 receiver readiness waits past an old strict SQL authority for the exact creator target',
    () async {
      final f = await _CanonicalAuthorityFixture.create();
      final initial = await f.refresh();
      Future<Map<String, List<Map<String, Object?>>>> snapshot() async => {
        for (final table in ['group_keys', 'group_event_log'])
          table: await f.db.query(table),
      };
      Future<void> restore(Map<String, List<Map<String, Object?>>> rows) =>
          f.db.transaction((txn) async {
            for (final table in rows.keys) {
              await txn.delete(table);
              for (final row in rows[table]!) {
                await txn.insert(table, row);
              }
            }
          });
      final oldRows = await snapshot();
      f.bridge.responses['group:generateNextKey'] = {
        'ok': true,
        'groupKey': 'third-fixture-key',
        'keyEpoch': 3,
      };
      final rotated = await f.refresh();
      final fresh = rotated['after']! as Map<String, Object?>;
      final freshRows = await snapshot();
      await restore(oldRows);
      final old = await f.observe();
      expect(old['admission'], 'strict');
      expect(old['keyEpoch'], initial['currentEpoch']);
      expect(old['keyEpoch'], 2);

      final secondRead = Completer<void>();
      final release = Completer<void>();
      var reads = 0;
      f.beforeSettledRead = () async {
        if (++reads == 2) {
          secondRead.complete();
          await release.future;
        }
      };
      final target = GroupMediaReliabilityAuthorityTarget.fromObservation(
        fresh,
      );
      final pending = probeGroupMediaReliabilityAuthority(
        groupId: 'fixture-group',
        p2pService: f.p2p,
        identityRepository: f.identities,
        groupRepository: f.groups,
        requireSettled: true,
        expectedAuthority: target,
        settleTimeout: const Duration(seconds: 3),
      );
      try {
        expect(
          await Future.any([
            secondRead.future.then((_) => 'waiting'),
            pending.then((_) => 'premature_ready'),
          ]),
          'waiting',
          reason: 'A valid old epoch must not satisfy the new creator target.',
        );
        await restore(freshRows);
        release.complete();
        final observed = await pending;
        expect(observed['keyEpoch'], 3);
        expect(target.matchesObservation(observed), isTrue);
      } finally {
        if (!release.isCompleted) release.complete();
        f.beforeSettledRead = null;
      }
    },
  );

  test(
    'P269 canonical refresh uses SQLite COMPLETE and real reconciliation before strict admission',
    () async {
      final f = await _CanonicalAuthorityFixture.create();
      final before = await f.observe();
      expect(before['admission'], 'refuse');
      expect(before['keyEpoch'], 1);
      expect(before['authoritySha256'], isNull);
      final result = await f.refresh();
      expect(result['previousEpoch'], 1);
      expect(result['currentEpoch'], 2);
      expect(result['distributedDeviceCount'], 1);
      expect(result['deferredPeerCount'], 0);
      final after = result['after']! as Map<String, Object?>;
      expect(after['admission'], 'strict');
      expect(after['authoritySha256'], matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(after['memberRolesSha256'], before['memberRolesSha256']);
      expect(f.completeCommitsObservedBeforeDelivery, 1);
      expect(await f.db.query('pending_group_broadcasts'), isEmpty);
      final proof = (await f.settled('fixture-group'))!;
      final completeRows = await f.db.query(
        'group_event_log',
        where: 'event_type = ?',
        whereArgs: [AuthenticatedGroupAuthorityPhase.complete.eventType],
      );
      expect(completeRows, hasLength(1));
      final marker = protectedGroupContentReconciliationCompleteSourceEventId(
        proof.eventId,
      );
      // Fault injection removes only the real reconciliation marker. COMPLETE
      // alone must never confer authoring permission, even at the current epoch.
      expect(
        await f.db.delete(
          'group_event_log',
          where: 'group_id = ? AND source_event_id = ?',
          whereArgs: ['fixture-group', marker],
        ),
        1,
      );
      // Production admission attempts real reconciliation repair. Hold that
      // durable write unavailable rather than assuming a missing marker stays
      // absent while the real repair adapter is installed.
      await f.db.execute('''CREATE TRIGGER reject_test_reconciliation
        BEFORE INSERT ON group_event_log
        WHEN NEW.source_event_id = '${marker.replaceAll("'", "''")}'
        BEGIN SELECT RAISE(ABORT, 'test reconciliation unavailable'); END''');
      await expectLater(f.observe(), throwsA(isA<DatabaseException>()));
      expect(
        await f.db.query(
          'group_event_log',
          where: 'source_event_id = ?',
          whereArgs: [marker],
        ),
        isEmpty,
      );
      await f.db.execute('DROP TRIGGER reject_test_reconciliation');
      expect(await f.support.reconcileCompletedContentAuthority(proof), isTrue);
      expect((await f.observe())['admission'], 'strict');
    },
  );

  for (final (field, replacement) in <(String, Object)>[
    ('keyEpoch', 3),
    ('authoritySha256', 'c' * 64),
    ('authorityEventAt', '2026-01-01T00:00:00.000Z'),
    ('memberRolesSha256', 'd' * 64),
  ]) {
    test('P269 readiness retains its deadline for mismatched $field', () async {
      final f = await _CanonicalAuthorityFixture.create();
      final refreshed = await f.refresh();
      final target = GroupMediaReliabilityAuthorityTarget.fromObservation({
        ...refreshed['after']! as Map<String, Object?>,
        field: replacement,
      });
      await expectLater(
        probeGroupMediaReliabilityAuthority(
          groupId: 'fixture-group',
          p2pService: f.p2p,
          identityRepository: f.identities,
          groupRepository: f.groups,
          requireSettled: true,
          expectedAuthority: target,
          settleTimeout: const Duration(milliseconds: 100),
        ),
        throwsA(
          isA<GroupMediaReliabilitySenderFailure>().having(
            (failure) => failure.stage,
            'stage',
            'authority_settlement',
          ),
        ),
      );
      expect((await f.observe())['admission'], 'strict');
    });
  }

  test(
    'P269 authority probe rejects successful SQL admission after its original bound',
    () async {
      final f = await _CanonicalAuthorityFixture.create();
      await f.refresh();
      final entered = Completer<void>();
      final release = Completer<void>();
      f.beforeSettledRead = () async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
      };
      final pending = probeGroupMediaReliabilityAuthority(
        groupId: 'fixture-group',
        p2pService: f.p2p,
        identityRepository: f.identities,
        groupRepository: f.groups,
        requireSettled: true,
        settleTimeout: const Duration(milliseconds: 100),
      );
      final assertion = expectLater(
        pending,
        throwsA(
          isA<GroupMediaReliabilitySenderFailure>().having(
            (e) => e.stage,
            'stage',
            'authority_settlement',
          ),
        ),
      );
      await entered.future;
      await Future<void>.delayed(const Duration(milliseconds: 150));
      release.complete();
      await assertion;
      f.beforeSettledRead = null;
      expect(
        (await f.observe())['admission'],
        'strict',
        reason:
            'Only the late observation failed; real durable authority remains valid.',
      );
    },
  );

  test(
    'P269 canonical refresh rejects identity cutover during its final authority read',
    () async {
      final f = await _CanonicalAuthorityFixture.create();
      final entered = Completer<void>();
      final release = Completer<void>();
      f.beforeSettledRead = () async {
        if (!entered.isCompleted) entered.complete();
        await release.future;
      };
      final pending = f.refresh();
      final assertion = expectLater(
        pending,
        throwsA(
          isA<GroupMediaReliabilitySenderFailure>().having(
            (e) => e.stage,
            'stage',
            'authority_rotation',
          ),
        ),
      );
      await entered.future;
      f.identities.seed(
        FakeIdentityRepository.makeIdentity(
          peerId: 'replacement-account',
          mlKemPublicKey: 'replacement-kem',
        ),
      );
      release.complete();
      await assertion;
      expect(f.bridge.commandLog, isNot(contains('group:generateNextKey')));
      expect((await f.groups.getLatestKey('fixture-group'))!.keyGeneration, 1);
      expect(await f.db.query('pending_group_broadcasts'), isEmpty);
    },
  );

  test(
    'P269 canonical refresh cannot turn an atomic COMPLETE rollback into strict admission',
    () async {
      final f = await _CanonicalAuthorityFixture.create();
      await f.db.execute('''CREATE TRIGGER reject_test_authority_complete
      BEFORE INSERT ON group_event_log
      WHEN NEW.event_type = '${AuthenticatedGroupAuthorityPhase.complete.eventType}'
      BEGIN SELECT RAISE(ABORT, 'test atomic COMPLETE failure'); END''');
      await expectLater(f.refresh(), throwsA(isA<DatabaseException>()));
      expect((await f.groups.getLatestKey('fixture-group'))!.keyGeneration, 1);
      expect(
        await f.db.query(
          'group_event_log',
          where: 'event_type = ?',
          whereArgs: [AuthenticatedGroupAuthorityPhase.complete.eventType],
        ),
        isEmpty,
      );
      expect((await f.observe())['admission'], 'refuse');
      expect(f.completeCommitsObservedBeforeDelivery, 0);
      expect(
        await f.db.query('pending_group_broadcasts'),
        hasLength(1),
        reason: 'The real prepared owner remains for recovery after rollback.',
      );
    },
  );
}

GroupMessageRepositoryImpl _realSqlGroupMessages(
  MediaRepositoryRealDbFixture fixture,
) {
  final db = fixture.db;
  final keyAccess = GroupMediaKeyAccess(
    secureKeyStore: fixture.secureKeyStore,
    lifecycleLock: fixture.repo.lifecycleLock,
  );
  return GroupMessageRepositoryImpl(
    dbInsertGroupMessage: (row) => dbInsertGroupMessage(db, row),
    dbLoadGroupMessagesPage: (groupId, {limit = 50, offset = 0}) =>
        dbLoadGroupMessagesPage(db, groupId, limit: limit, offset: offset),
    dbLoadGroupMessage: (id) => dbLoadGroupMessage(db, id),
    dbLoadGroupMessageLocalDeletionFn: (id) =>
        dbLoadGroupMessageLocalDeletion(db, id),
    dbLoadLatestGroupMessage: (groupId) =>
        dbLoadLatestGroupMessage(db, groupId),
    dbUpdateGroupMessageStatus: (id, status) =>
        dbUpdateGroupMessageStatus(db, id, status),
    dbCountGroupMessages: (groupId) => dbCountGroupMessages(db, groupId),
    dbCountUnreadGroupMessages: (groupId) =>
        dbCountUnreadGroupMessages(db, groupId),
    dbCountTotalUnreadGroupMessages: () => dbCountTotalUnreadGroupMessages(db),
    dbMarkGroupMessagesAsRead: (groupId) =>
        dbMarkGroupMessagesAsRead(db, groupId),
    dbDeleteGroupMessage: (id) => dbDeleteGroupMessage(db, id),
    dbExistsGroupMessageByContent: (groupId, senderPeerId, text, timestamp) =>
        dbExistsGroupMessageByContent(
          db,
          groupId,
          senderPeerId,
          text,
          timestamp,
        ),
    dbDeleteGroupMessagesForGroup: (groupId) =>
        dbDeleteGroupMessagesForGroup(db, groupId),
    dbLoadGroupThreadSummaries: (groupIds) =>
        dbLoadGroupThreadSummaries(db, groupIds),
    dbCompleteGroupContentInboxStoreRetryIfExactFn:
        ({
          required expected,
          required sourcePeerId,
          required sourceEventId,
          required sourceTimestamp,
          required eventPayload,
        }) => dbCompleteGroupContentInboxStoreRetryIfExact(
          db,
          expected: expected,
          sourcePeerId: sourcePeerId,
          sourceEventId: sourceEventId,
          sourceTimestamp: sourceTimestamp,
          eventPayload: eventPayload,
          mediaKeyAccess: keyAccess,
        ),
    dbStageAndCompleteLocalGroupContentMessageFn:
        ({
          required expected,
          required sourcePeerId,
          required sourceEventId,
          required sourceTimestamp,
          required eventPayload,
        }) => dbStageAndCompleteLocalGroupContentMessage(
          db,
          expected: expected,
          sourcePeerId: sourcePeerId,
          sourceEventId: sourceEventId,
          sourceTimestamp: sourceTimestamp,
          eventPayload: eventPayload,
          mediaKeyAccess: keyAccess,
        ),
    dbStagePreparedLocalGroupContentMessageFn:
        ({
          required expected,
          required sourcePeerId,
          required sourceEventId,
          required sourceTimestamp,
          required preparedEventPayload,
        }) => dbStagePreparedLocalGroupContentMessage(
          db,
          expected: expected,
          sourcePeerId: sourcePeerId,
          sourceEventId: sourceEventId,
          sourceTimestamp: sourceTimestamp,
          preparedEventPayload: preparedEventPayload,
          mediaKeyAccess: keyAccess,
        ),
    dbTerminalizePreparedLocalGroupContentMessageIfExactFn:
        ({
          required expected,
          required preparedEventPayload,
          required terminalSourcePeerId,
          required terminalSourceEventId,
          required terminalSourceTimestamp,
          required terminalEventPayload,
        }) => dbTerminalizePreparedLocalGroupContentMessageIfExact(
          db,
          expected: expected,
          preparedEventPayload: preparedEventPayload,
          terminalSourcePeerId: terminalSourcePeerId,
          terminalSourceEventId: terminalSourceEventId,
          terminalSourceTimestamp: terminalSourceTimestamp,
          terminalEventPayload: terminalEventPayload,
          mediaKeyAccess: keyAccess,
        ),
    dbHasExactPreparedLocalGroupContentMessageFn:
        ({required expected, required eventPayload}) =>
            dbHasExactPreparedLocalGroupContentMessage(
              db,
              expected: expected,
              eventPayload: eventPayload,
              mediaKeyAccess: keyAccess,
            ),
  );
}

// Deliberate later boundary: the actual three-kind entry reaches voice only
// after the MP4 has completed preparation and canonical publication.
class _StopBeforeVoiceRecorder extends _Recorder {
  bool permissionObserved = false;
  @override
  Future<bool> hasPermission() async {
    permissionObserved = true;
    return false;
  }
}

// Crypto remains an explicit fake; the real coordinator, production database,
// repository secure-key projection and custody CAS all execute unchanged.
class _SqlPreparationBridge extends PassthroughCryptoBridge {
  _SqlPreparationBridge({
    required this.rejectUpload,
    required this.beforeUpload,
    this.uploadErrorCode,
  });
  final String? uploadErrorCode;
  final bool rejectUpload;
  final Future<void> Function() beforeUpload;
  int uploads = 0;
  final List<Map<String, dynamic>> uploadRequests = [];
  @override
  Future<String> send(String message) async {
    final decoded = jsonDecode(message) as Map<String, dynamic>;
    if (decoded['cmd'] == 'blob:encrypt') {
      final payload = decoded['payload'] as Map<String, dynamic>;
      final source = File(payload['filePath'] as String);
      final encrypted = File('${source.path}.enc');
      // Model the real AES-GCM frame length, while keeping crypto explicitly
      // fake. Real SQL independently requires ciphertext = plaintext + tag.
      await encrypted.writeAsBytes([
        ...await source.readAsBytes(),
        ...List<int>.filled(16, 0x5a),
      ], flush: true);
      return jsonEncode({
        'ok': true,
        'encryptedPath': encrypted.path,
        'nonce': 'fixture-sql-blob-nonce',
      });
    }
    if (decoded['cmd'] != 'media:upload') {
      return super.send(message);
    }
    final payload = decoded['payload'] as Map<String, dynamic>;
    uploads++;
    uploadRequests.add(Map<String, dynamic>.from(payload));
    await beforeUpload();
    if (rejectUpload) {
      return jsonEncode({
        'ok': false,
        'error': 'fixture_rejected',
        'errorCode': uploadErrorCode,
      });
    }
    return jsonEncode({
      'ok': true,
      'id': payload['id'],
      'storeStatus': 'stored',
      'custodyKind': groupMediaBlobCustodyKind,
      'custodyContract': groupMediaBlobCustodyContract,
      'contentHash': payload['contentHash'],
      'size': File(payload['filePath'] as String).lengthSync(),
      'mime': groupMediaBlobTransportMime,
      'expiresAtMs': DateTime.now()
          .add(const Duration(days: 1))
          .millisecondsSinceEpoch,
      'custodyRelayPeerId': 'relay-fixture',
    });
  }
}

void _registerRealSqlMp4PreparationTests() {
  for (final fixture in [
    (suffix: 'complete', rejectUpload: false, uploadErrorCode: null),
    (
      suffix: 'retained',
      rejectUpload: true,
      uploadErrorCode: 'MEDIA_CUSTODY_ADMISSION_DISABLED',
    ),
    (
      suffix: 'private-code-omitted',
      rejectUpload: true,
      uploadErrorCode: 'unknown-private-transport-credential',
    ),
  ]) {
    final rejectUpload = fixture.rejectUpload;
    test('P269 real SQLite MP4 preparation ${fixture.suffix}', () async {
      final media = await MediaRepositoryRealDbFixture.create();
      addTearDown(media.dispose);
      final authority = await _CanonicalAuthorityFixture.create(
        database: media.db,
      );
      await authority.refresh();
      expect((await authority.observe())['admission'], 'strict');
      expect(
        authority.identity.peerId,
        isNot(authority.p2p.currentState.peerId),
      );
      final messages = _realSqlGroupMessages(media);
      final documents = await Directory.systemTemp.createTemp('p269-sql-mp4-');
      addTearDown(() => documents.delete(recursive: true));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'),
            (_) async => documents.path,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              const MethodChannel('plugins.flutter.io/path_provider'),
              null,
            ),
      );
      final suffix = fixture.suffix;
      final messageIds = {
        for (final kind in ['mp4', 'voice', 'jpeg'])
          kind: 'sql-$suffix-$kind-message',
      };
      final attachmentIds = {
        for (final kind in ['mp4', 'voice', 'jpeg'])
          kind: 'sql-$suffix-$kind-attachment',
      };
      final custody = media.repo as GroupMediaBlobCustodyRepository;
      var stagedBeforeUpload = false;
      final bridge = _SqlPreparationBridge(
        rejectUpload: rejectUpload,
        uploadErrorCode: fixture.uploadErrorCode,
        beforeUpload: () async {
          final rows = await custody.loadGroupMediaBlobCustodyForMessage(
            groupId: 'fixture-group',
            messageId: messageIds['mp4']!,
          );
          expect(rows, hasLength(1));
          expect(
            rows.single.state,
            DirectMediaBlobCustodyState.outgoingPrepared,
          );
          expect(rows.single.recipientPeerId, 'receiver-transport');
          final attachment = await media.repo.getAttachmentById(
            attachmentIds['mp4']!,
          );
          expect(attachment?.ownerLane, MediaOwnerLane.group);
          expect(attachment?.mime, 'video/mp4');
          expect(attachment?.encryptionKeyBase64, isNotEmpty);
          expect(await messages.getMessage(messageIds['mp4']!), isNotNull);
          stagedBeforeUpload = true;
        },
      );
      final recorder = _StopBeforeVoiceRecorder();
      GroupMediaReliabilitySenderFailure? failure;
      try {
        await sendGroupMediaReliabilityFixtures(
          runId: 'sql-mp4-$suffix',
          groupId: 'fixture-group',
          messageIds: messageIds,
          attachmentIds: attachmentIds,
          receiverAccountPeerId: 'receiver-account',
          receiverTransportPeerId: 'receiver-transport',
          fixtureDirectory: Directory('${documents.path}/fixtures'),
          bridge: bridge,
          p2pService: authority.p2p,
          identityRepository: authority.identities,
          groupRepository: authority.groups,
          groupConfigBuilder: (_, _) => <String, dynamic>{},
          groupMessageRepository: messages,
          mediaAttachmentRepository: media.repo,
          mediaFileManager: _Media(),
          audioRecorderService: recorder,
        );
      } on GroupMediaReliabilitySenderFailure catch (error) {
        failure = error;
      }
      expect(
        failure,
        isNotNull,
        reason:
            'The control intentionally stops at upload failure or the later voice permission boundary.',
      );
      expect(
        stagedBeforeUpload,
        isTrue,
        reason:
            'Actual SQLite custody and attachment must exist before the remote upload request.',
      );
      expect(bridge.uploads, 1);
      expect(
        bridge.uploadRequests.single['custodyKind'],
        groupMediaBlobCustodyKind,
      );
      expect(bridge.uploadRequests.single['mime'], groupMediaBlobTransportMime);
      final rows = await custody.loadGroupMediaBlobCustodyForMessage(
        groupId: 'fixture-group',
        messageId: messageIds['mp4']!,
      );
      final parent = await messages.getMessage(messageIds['mp4']!);
      final attachment = await media.repo.getAttachmentById(
        attachmentIds['mp4']!,
      );
      expect(rows, hasLength(1));
      expect(attachment, isNotNull);
      expect(attachment!.messageId, messageIds['mp4']);
      expect(attachment.ownerLane, MediaOwnerLane.group);
      expect(attachment.mime, 'video/mp4');
      expect(
        attachment.contentHash,
        bridge.uploadRequests.single['contentHash'],
      );
      expect(rows.single.contentHash, attachment.contentHash);
      expect(rows.single.ciphertextSize, attachment.size + 16);
      expect(await messages.getMessage(messageIds['voice']!), isNull);
      expect(await messages.getMessage(messageIds['jpeg']!), isNull);
      if (rejectUpload) {
        expect(failure!.stage, 'strict_preparation');
        expect(failure.kind, 'mp4');
        expect(failure.preparationState, 'retained');
        expect(failure.preparationHasDurableAuthority, isTrue);
        expect(failure.preparationUploadResponseOk, isFalse);
        expect(
          failure.preparationUploadErrorCode,
          fixture.suffix == 'retained'
              ? 'MEDIA_CUSTODY_ADMISSION_DISABLED'
              : isNull,
        );
        expect(recorder.permissionObserved, isFalse);
        expect(rows.single.state, DirectMediaBlobCustodyState.outgoingPrepared);
        expect(parent?.status, GroupMessage.statusQueuedOffline);
        expect(parent?.wireEnvelope, isNull);
        expect(attachment.downloadStatus, 'upload_pending');
        expect(parent?.inboxRetryPayload, isNull);
        expect(
          await media.db.query(
            'group_event_log',
            where: 'event_type = ?',
            whereArgs: ['protected_message'],
          ),
          isEmpty,
        );
      } else {
        expect(
          failure!.stage,
          'fixture_material',
          reason: jsonEncode({
            'parentStatus': parent?.status,
            'inboxStored': parent?.inboxStored,
            'attachmentStatus': attachment.downloadStatus,
            'custodyState': rows.single.state.name,
            'hasFingerprint':
                attachment.groupMediaBlobCustodyFingerprint != null,
          }),
        );
        expect(failure.kind, 'voice');
        expect(failure.preparationState, isNull);
        expect(failure.preparationHasDurableAuthority, isNull);
        expect(failure.preparationUploadResponseOk, isNull);
        expect(failure.preparationUploadErrorCode, isNull);
        expect(recorder.permissionObserved, isTrue);
        expect(parent?.status, 'sent');
        expect(parent?.inboxStored, isTrue);
        expect(parent?.wireEnvelope, isNull);
        expect(parent?.inboxRetryPayload, isNull);
        // The strict producer's SQL transaction owns custody completion;
        // this raw presentation field remains its original staged value.
        expect(attachment.downloadStatus, 'upload_pending');
        expect(attachment.groupMediaBlobCustodyFingerprint, isNotEmpty);
        expect(rows.single.attachmentId, attachmentIds['mp4']);
        expect(rows.single.recipientPeerId, 'receiver-transport');
        expect(
          rows.single.state,
          DirectMediaBlobCustodyState.outgoingCleanupPending,
        );
        for (final type in [
          'protected_content_prepared',
          'protected_message',
        ]) {
          expect(
            await media.db.query(
              'group_event_log',
              where: 'group_id = ? AND event_type = ?',
              whereArgs: ['fixture-group', type],
            ),
            hasLength(1),
          );
        }
      }
    });
  }
}
