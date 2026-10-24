import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/database/helpers/groups_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_members_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_keys_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/features/groups/application/drain_group_offline_inbox_use_case.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/data/repositories/group_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_message_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../shared/fakes/ed25519_contact_request_crypto.dart';

// Real send/custody decisions, replay verification/receive owner, current-schema
// file databases and repositories. Native relay/crypto/keychain are faked;
// closing and reopening both graphs is not an actual OS process kill.
void main() {
  test('GC-005 accepted text and membership survive both SQL/runtime restarts; '
      'replayed custody keeps one identity', () async {
    sqfliteFfiInit();
    groupRecoveryGate.resetForTest();
    final root = await Directory.systemTemp.createTemp(
      'group_custody_restart_',
    );
    final a = TestEd25519Identity.fromSeedByte(91);
    final b = TestEd25519Identity.fromSeedByte(92);
    final aStore = FakeSecureKeyStore();
    final bStore = FakeSecureKeyStore();
    var left = await _SqlPeer.open('${root.path}/left.db', a.peerId, aStore);
    var right = await _SqlPeer.open('${root.path}/right.db', b.peerId, bStore);
    addTearDown(() async {
      await left.close();
      await right.close();
      await root.delete(recursive: true);
      groupRecoveryGate.resetForTest();
    });
    final joined = DateTime.utc(2026, 10, 1);
    const groupId = 'restart-group';
    for (final peer in [left, right]) {
      await peer.groups.saveGroup(
        GroupModel(
          id: groupId,
          name: 'Restart group',
          type: GroupType.chat,
          topicName: 'restart-topic',
          createdAt: joined,
          createdBy: a.peerId,
          myRole: peer.self == a.peerId ? GroupRole.admin : GroupRole.member,
        ),
      );
      await peer.groups.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: a.peerId,
          username: 'Sender',
          publicKey: a.publicKey,
          role: MemberRole.admin,
          joinedAt: joined,
        ),
      );
      await peer.groups.saveMember(
        GroupMember(
          groupId: groupId,
          peerId: b.peerId,
          username: 'Receiver',
          publicKey: b.publicKey,
          role: MemberRole.writer,
          joinedAt: joined,
        ),
      );
      await peer.groups.saveKey(
        GroupKeyInfo(
          groupId: groupId,
          keyGeneration: 1,
          encryptedKey: 'synthetic-group-key',
          createdAt: joined,
        ),
      );
    }
    final sender = ZeroPeerPublishBridge();
    final (result, sent) = await sendGroupMessage(
      bridge: sender,
      groupRepo: left.groups,
      msgRepo: left.messages,
      groupId: groupId,
      text: 'Accepted before restart 👋',
      senderPeerId: a.peerId,
      senderPublicKey: a.publicKey,
      senderPrivateKey: 'synthetic-private-key',
      senderUsername: 'Sender',
      timestamp: DateTime.utc(2026, 10, 22, 9),
    );
    expect(result, SendGroupMessageResult.successNoPeers);
    expect(sent!.status, 'sent');
    expect(sent.inboxStored, isTrue);
    final stored = sender.sentMessages
        .map((s) => jsonDecode(s) as Map<String, dynamic>)
        .where((m) => m['cmd'] == 'group:inboxStore')
        .single;
    final payload = stored['payload'] as Map<String, dynamic>;
    expect(payload['recipientPeerIds'], contains(b.peerId));
    final wire = payload['message'] as String;
    expect((await right.messages.getMessagesPage(groupId)), isEmpty);

    // Verified accepted custody is the cut: no receiver delivery has occurred.
    // Recreate both DB handles, repositories and listeners; only the remote
    // accepted wire plus native-keychain stand-ins survive outside the graph.
    await left.close();
    await right.close();
    left = await _SqlPeer.open('${root.path}/left.db', a.peerId, aStore);
    right = await _SqlPeer.open('${root.path}/right.db', b.peerId, bStore);
    final retained = await left.messages.getMessage(sent.id);
    expect(retained!.id, sent.id);
    expect(retained.text, sent.text);
    expect(retained.inboxStored, isTrue);
    for (final peer in [left, right]) {
      final members = await peer.groups.getMembers(groupId);
      expect(
        {for (final m in members) m.peerId: m.role},
        {a.peerId: MemberRole.admin, b.peerId: MemberRole.writer},
      );
      expect((await peer.groups.getLatestKey(groupId))!.keyGeneration, 1);
    }
    final decoded = await decodeInboxMessage(
      FakeBridge(),
      right.groups,
      {'message': wire, 'from': a.peerId},
      groupId,
      expectedRecipientPeerId: b.peerId,
    );
    await right.listener.handleReplayEnvelope(decoded, rethrowOnError: true);
    await right.listener.handleReplayEnvelope(decoded, rethrowOnError: true);
    final received = await right.messages.getMessagesPage(groupId);
    expect(received, hasLength(1));
    expect(received.single.id, sent.id);
    expect(received.single.text, sent.text);
    expect(received.single.isIncoming, isTrue);

    // Persist removal across a fresh owner rather than restoring cached roster.
    await left.groups.removeMember(groupId, b.peerId);
    await left.close();
    left = await _SqlPeer.open('${root.path}/left.db', a.peerId, aStore);
    expect((await left.groups.getMembers(groupId)).map((m) => m.peerId), [
      a.peerId,
    ]);
    expect((await left.messages.getMessage(sent.id))!.text, sent.text);
    final rejoined = DateTime.now().toUtc();
    await left.groups.saveMember(
      GroupMember(
        groupId: groupId,
        peerId: b.peerId,
        username: 'Receiver',
        publicKey: b.publicKey,
        role: MemberRole.writer,
        joinedAt: rejoined,
      ),
    );
    await left.close();
    left = await _SqlPeer.open('${root.path}/left.db', a.peerId, aStore);
    final readded = await left.groups.getMember(groupId, b.peerId);
    expect(readded!.joinedAt, rejoined);
    expect(readded.role, MemberRole.writer);
    expect((await left.messages.getMessagesPage(groupId)).map((m) => m.id), [
      sent.id,
    ]);
  }, timeout: const Timeout(Duration(seconds: 30)));
}

class _SqlPeer {
  _SqlPeer(this.db, this.self, FakeSecureKeyStore store) {
    groups = GroupRepositoryImpl(
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
      dbLoadLatestGroupKey: (id) => dbLoadLatestGroupKey(db, id),
      dbLoadGroupKeyByGeneration: (id, epoch) =>
          dbLoadGroupKeyByGeneration(db, id, epoch),
      dbDeleteAllGroupKeys: (id) => dbDeleteAllGroupKeys(db, id),
      groupKeyStore: store,
    );
    messages = GroupMessageRepositoryImpl(
      dbInsertGroupMessage: (row) => dbInsertGroupMessage(db, row),
      dbLoadGroupMessagesPage: (id, {limit = 50, offset = 0}) =>
          dbLoadGroupMessagesPage(db, id, limit: limit, offset: offset),
      dbLoadGroupMessage: (id) => dbLoadGroupMessage(db, id),
      dbLoadGroupMessageByLogicalDeliveryIdFn: (id, sender, logical) =>
          dbLoadGroupMessageByLogicalDeliveryId(db, id, sender, logical),
      dbLoadLatestGroupMessage: (id) => dbLoadLatestGroupMessage(db, id),
      dbLoadLatestRemovalTimestampForSenderFn: (id, sender) =>
          dbLoadLatestGroupRemovalTimestampForSender(db, id, sender),
      dbUpdateGroupMessageStatus: (id, status) =>
          dbUpdateGroupMessageStatus(db, id, status),
      dbCountGroupMessages: (id) => dbCountGroupMessages(db, id),
      dbCountUnreadGroupMessages: (id) => dbCountUnreadGroupMessages(db, id),
      dbCountTotalUnreadGroupMessages: () =>
          dbCountTotalUnreadGroupMessages(db),
      dbMarkGroupMessagesAsRead: (id) => dbMarkGroupMessagesAsRead(db, id),
      dbDeleteGroupMessage: (id) => dbDeleteGroupMessage(db, id),
      dbExistsGroupMessageByContent: (id, sender, text, timestamp) =>
          dbExistsGroupMessageByContent(db, id, sender, text, timestamp),
      dbDeleteGroupMessagesForGroup: (id) =>
          dbDeleteGroupMessagesForGroup(db, id),
      dbLoadGroupThreadSummaries: (ids) => dbLoadGroupThreadSummaries(db, ids),
    );
    listener = GroupMessageListener(
      groupRepo: groups,
      msgRepo: messages,
      bridge: FakeBridge(),
      getSelfPeerId: () async => self,
    );
  }
  final Database db;
  final String self;
  late final GroupRepositoryImpl groups;
  late final GroupMessageRepositoryImpl messages;
  late final GroupMessageListener listener;
  static Future<_SqlPeer> open(
    String path,
    String self,
    FakeSecureKeyStore store,
  ) async {
    final db = await databaseFactoryFfiNoIsolate.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: currentIdentityDatabaseVersion,
        onCreate: runProductionOnCreate,
        onUpgrade: runProductionOnUpgrade,
      ),
    );
    return _SqlPeer(db, self, store);
  }

  Future<void> close() async {
    if (!db.isOpen) return;
    listener.dispose();
    await db.close();
  }
}
