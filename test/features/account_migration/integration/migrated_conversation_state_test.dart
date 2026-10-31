import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/database/helpers/group_keys_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_members_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/database/helpers/groups_db_helpers.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/account_migration/domain/models/account_migration_authority_state.dart';
import 'package:flutter_app/features/account_migration/application/migration_secure_storage_registry.dart';
import 'package:flutter_app/features/conversation/application/retry_failed_messages_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/groups/application/retry_failed_group_messages_use_case.dart';
import 'package:flutter_app/features/groups/data/repositories/group_message_repository_impl.dart';
import 'package:flutter_app/features/groups/data/repositories/group_repository_impl.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/in_memory_inbox_staging_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';
import '../../contact_request/presentation/support/contact_request_sql_fixture.dart';
import '../../contact_request/support/contact_repair_harness.dart';
import '../migration_durable_fixture.dart';

GroupRepositoryImpl _groups(Database db, DurableMigrationKeyStore keys) =>
    GroupRepositoryImpl(
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
      dbLoadGroupKeyByGeneration: (id, generation) =>
          dbLoadGroupKeyByGeneration(db, id, generation),
      dbDeleteAllGroupKeys: (id) => dbDeleteAllGroupKeys(db, id),
      groupKeyStore: keys,
    );

GroupMessageRepositoryImpl _messages(Database db) => GroupMessageRepositoryImpl(
  dbInsertGroupMessage: (row) => dbInsertGroupMessage(db, row),
  dbLoadGroupMessagesPage: (id, {limit = 50, offset = 0}) =>
      dbLoadGroupMessagesPage(db, id, limit: limit, offset: offset),
  dbLoadGroupMessage: (id) => dbLoadGroupMessage(db, id),
  dbLoadLatestGroupMessage: (id) => dbLoadLatestGroupMessage(db, id),
  dbUpdateGroupMessageStatus: (id, status) =>
      dbUpdateGroupMessageStatus(db, id, status),
  dbCountGroupMessages: (id) => dbCountGroupMessages(db, id),
  dbCountUnreadGroupMessages: (id) => dbCountUnreadGroupMessages(db, id),
  dbCountTotalUnreadGroupMessages: () => dbCountTotalUnreadGroupMessages(db),
  dbMarkGroupMessagesAsRead: (id) => dbMarkGroupMessagesAsRead(db, id),
  dbDeleteGroupMessage: (id) => dbDeleteGroupMessage(db, id),
  dbExistsGroupMessageByContent: (id, peer, text, timestamp) =>
      dbExistsGroupMessageByContent(db, id, peer, text, timestamp),
  dbDeleteGroupMessagesForGroup: (id) => dbDeleteGroupMessagesForGroup(db, id),
  dbLoadGroupThreadSummaries: (ids) => dbLoadGroupThreadSummaries(db, ids),
  dbLoadFailedOutgoingGroupMessagesFn: () =>
      dbLoadFailedOutgoingGroupMessages(db),
  dbLoadRetryableOutgoingGroupMessagesFn: () =>
      dbLoadRetryableOutgoingGroupMessages(db),
  dbUpdateGroupMessageWireEnvelopeFn: (id, envelope) =>
      dbUpdateGroupMessageWireEnvelope(db, id, envelope),
  dbUpdateGroupMessageInboxRetryPayloadFn: (id, payload) =>
      dbUpdateGroupMessageInboxRetryPayload(db, id, payload),
  dbUpdateGroupMessageInboxStoredFn: (id, {required stored}) =>
      dbUpdateGroupMessageInboxStored(db, id, stored: stored),
);

Widget _localized(Widget screen) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: screen),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  testWidgets(
    'DC-019 TRANSFER-012 imported direct/group history and read state '
    'survive disk reopen; pending work retries only on the active target',
    (tester) async {
      late Directory directory;
      late Database source;
      late Database target;
      late DurableMigrationKeyStore sourceKeys;
      late DurableMigrationKeyStore targetKeys;
      late List<ConversationMessage> directHistory;
      late List<GroupMessage> groupHistory;
      late GroupModel group;
      final bridge = FakeBridge(
        initialResponses: {
          'message.encrypt': {
            'ok': true,
            'kem': 'fixture-kem',
            'ciphertext': 'fixture-ciphertext',
            'nonce': 'fixture-nonce',
          },
          'group:publish': {
            'ok': true,
            'messageId': 'group-pending',
            'topicPeers': 1,
          },
        },
      );
      final transport = FakeP2PService(
        initialState: NodeState(isStarted: true, peerId: migrationOwner.peerId),
        discoverPeerResult: DiscoveredPeer(
          id: migrationPeer.peerId,
          addresses: const ['/ip4/127.0.0.1/tcp/4001'],
        ),
      );
      addTearDown(() async {
        await tester.runAsync(() async {
          transport.dispose();
          if (source.isOpen) await source.close();
          if (target.isOpen) await target.close();
          await sourceKeys.close();
          await targetKeys.close();
          await directory.delete(recursive: true);
        });
      });
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp(
          'migrated-conversation-',
        );
        source = await openMigrationProductionDatabase(
          '${directory.path}/source.db',
        );
        target = await openMigrationProductionDatabase(
          '${directory.path}/target.db',
        );
        sourceKeys = await DurableMigrationKeyStore.open(
          '${directory.path}/source-keys.db',
        );
        targetKeys = await DurableMigrationKeyStore.open(
          '${directory.path}/target-keys.db',
        );
        await seedMigrationAccount(
          source,
          sourceKeys,
          documentsRootPath: '${directory.path}/source-documents',
        );
        await targetKeys.write(
          MigrationSecureStorageRegistry.dbEncryptionKey,
          'target-active-db-key',
        );
        await sourceKeys.authority.saveAuthority(
          AccountMigrationAuthorityRecord(
            state: AccountMigrationAuthorityState.active,
            accountPeerId: migrationOwner.peerId,
          ),
        );
        await targetKeys.authority.saveAuthority(
          AccountMigrationAuthorityRecord(
            state: AccountMigrationAuthorityState.migrationImportStaging,
            accountPeerId: migrationOwner.peerId,
          ),
        );
        await roundtripMigrationBundle(
          directory: directory,
          source: source,
          target: target,
          sourceKeys: sourceKeys,
          targetKeys: targetKeys,
          sessionId: 'conversation',
        );
        await source.close();
        await target.close();
        source = await openMigrationProductionDatabase(
          '${directory.path}/source.db',
        );
        target = await openMigrationProductionDatabase(
          '${directory.path}/target.db',
        );
        sourceKeys = await sourceKeys.reopen();
        targetKeys = await targetKeys.reopen();
        final direct = buildWidgetMessageRepository(target);
        final groups = _messages(target);
        directHistory = await direct.getMessagesForContact(
          migrationPeer.peerId,
        );
        groupHistory = await groups.getMessagesPage(migrationGroupId);
        group = (await _groups(target, targetKeys).getGroup(migrationGroupId))!;
        expect(directHistory.map((message) => message.id).toSet(), {
          'direct-unread',
          'direct-pending',
        });
        expect(groupHistory.map((message) => message.id).toSet(), {
          'group-unread',
          'group-pending',
        });
        expect(await direct.getUnreadCountForContact(migrationPeer.peerId), 1);
        expect(await groups.getUnreadCount(migrationGroupId), 1);
      });

      await tester.pumpWidget(
        _localized(
          ConversationScreen(
            contactPeerId: migrationPeer.peerId,
            contactUsername: 'Imported peer',
            connectionDate: 'October 2026',
            ownPeerId: migrationOwner.peerId,
            messages: directHistory,
            onSend: (_) {},
            onBack: () {},
            initialLoadDone: true,
            hasMoreOlderMessages: false,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Imported direct history'), findsOneWidget);
      expect(find.text('Pending direct retry'), findsOneWidget);
      await tester.pumpWidget(
        _localized(
          GroupConversationScreen(
            group: group,
            messages: groupHistory,
            ownPeerId: migrationOwner.peerId,
            onSend: (_) {},
            onBack: () {},
            initialLoadDone: true,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Imported group history'), findsOneWidget);
      expect(find.text('Pending group retry'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());

      await tester.runAsync(() async {
        await buildWidgetMessageRepository(
          target,
        ).markConversationAsRead(migrationPeer.peerId);
        await _messages(target).markAsRead(migrationGroupId);
        await target.close();
        // Retry needs the production atomic staging and settlement callbacks.
        final retryFixture = await MediaRepositoryRealDbFixture.create(
          databasePath: '${directory.path}/target.db',
        );
        target = retryFixture.db;
        final direct = retryFixture.messageRepo;
        final groups = _messages(target);
        final groupRepo = _groups(target, targetKeys);
        final identity = buildWidgetIdentityRepository(target, targetKeys);
        expect((await identity.loadIdentity())!.peerId, migrationOwner.peerId);
        expect(
          (await groupRepo.getLatestKey(migrationGroupId))!.keyGeneration,
          7,
        );
        expect(await direct.getUnreadCountForContact(migrationPeer.peerId), 0);
        expect(await groups.getUnreadCount(migrationGroupId), 0);
        expect((await direct.getMessage('direct-unread'))!.readAt, isNotNull);
        expect((await groups.getMessage('group-unread'))!.readAt, isNotNull);
        expect(
          await targetKeys.networkGate.allowsAccountNetworkSideEffects(
            peerId: migrationOwner.peerId,
            operation: 'pending_retry',
          ),
          isTrue,
        );
        expect(
          await retryFailedMessages(
            messageRepo: direct,
            identityRepo: identity,
            contactRepo: databaseContactRepository(target),
            p2pService: transport,
            bridge: bridge,
            retryDirectInboxCustody: false,
          ),
          1,
        );
        // There are no group attachments in this account. Only that empty read
        // uses a fixture; parent rows, roster, keys, retry selection and mutations
        // all use the imported production database.
        expect(
          await target.query(
            'media_attachments',
            where: 'owner_lane = ?',
            whereArgs: ['group'],
          ),
          isEmpty,
        );
        expect(
          await retryFailedGroupMessages(
            groupMsgRepo: groups,
            groupRepo: groupRepo,
            identityRepo: identity,
            bridge: bridge,
            mediaAttachmentRepo: InMemoryMediaAttachmentRepository(),
          ),
          1,
        );
        final directSendCount = transport.sendMessageWithReplyCallCount;
        final groupPublishCount = bridge.commandLog
            .where((cmd) => cmd == 'group:publish')
            .length;
        expect(directSendCount, 1);
        expect(groupPublishCount, 1);
        final published = bridge.sentMessages
            .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
            .singleWhere((command) => command['cmd'] == 'group:publish');
        expect((published['payload'] as Map)['groupId'], migrationGroupId);

        // A retired source retains the old retry rows, but the actual P2P service
        // consults its reopened durable authority before start, send or replay.
        final retiredBridge = FakeBridge();
        final retiredService = P2PServiceImpl(
          bridge: retiredBridge,
          inboxStagingRepository: InMemoryInboxStagingRepository(),
          accountMigrationNetworkGate:
              sourceKeys.networkGate.allowsAccountNetworkSideEffects,
        );
        try {
          expect(
            await retiredService.startNodeCore(
              'fixture-key',
              migrationOwner.peerId,
            ),
            isFalse,
          );
          expect(
            await retiredService.sendMessage(migrationPeer.peerId, 'old retry'),
            isFalse,
          );
          await retiredService.drainOfflineInbox();
          expect(retiredBridge.sentMessages, isEmpty);
        } finally {
          retiredService.dispose();
        }
        expect(
          (await sourceKeys.authority.loadAuthority())!.state,
          AccountMigrationAuthorityState.migratedOut,
        );
        expect(
          (await buildWidgetMessageRepository(
            source,
          ).getMessage('direct-pending'))!.status,
          'failed',
        );
        expect(
          (await _messages(source).getMessage('group-pending'))!.status,
          'failed',
        );
        expect(
          await buildWidgetMessageRepository(
            source,
          ).getUnreadCountForContact(migrationPeer.peerId),
          1,
        );
        await target.close();
        target = await openMigrationProductionDatabase(
          '${directory.path}/target.db',
        );
        final reopenedIdentity = buildWidgetIdentityRepository(
          target,
          targetKeys,
        );
        expect(
          (await buildWidgetMessageRepository(
            target,
          ).getMessage('direct-pending'))!.status,
          isNot('failed'),
        );
        expect(
          (await _messages(target).getMessage('group-pending'))!.status,
          isNot('failed'),
        );
        expect(
          await retryFailedMessages(
            messageRepo: buildWidgetMessageRepository(target),
            identityRepo: reopenedIdentity,
            contactRepo: databaseContactRepository(target),
            p2pService: transport,
            bridge: bridge,
            retryDirectInboxCustody: false,
          ),
          0,
        );
        expect(
          await retryFailedGroupMessages(
            groupMsgRepo: _messages(target),
            groupRepo: _groups(target, targetKeys),
            identityRepo: reopenedIdentity,
            bridge: bridge,
            mediaAttachmentRepo: InMemoryMediaAttachmentRepository(),
          ),
          0,
        );
        expect(transport.sendMessageWithReplyCallCount, directSendCount);
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:publish'),
          hasLength(groupPublishCount),
        );
      });
    },
  );
}
