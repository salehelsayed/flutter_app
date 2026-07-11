import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/received_media_egress.dart';
import 'package:flutter_app/core/media/received_media_egress_gateway.dart';
import 'package:flutter_app/core/media/received_media_egress_service.dart';
import 'package:flutter_app/features/conversation/domain/models/media_library.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/direct_received_media_action_sheet.dart';
import 'package:flutter_app/features/groups/application/group_media_delete_for_me_coordinator.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_intent.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_received_media_actions.dart';
import 'package:flutter_app/features/groups/application/group_shared_media_navigation.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_info_screen.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_shared_media_library_screen.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';
import '../shared_media_test_fakes.dart';

void main() {
  test(
    'GML-10 production nested route consumes bounded anchor result',
    () async {
      final repository = _RecordingAroundRepository();
      repository.scripted = [
        for (var index = 0; index < 51; index++)
          _message('m$index', groupId: 'group-a', minute: index),
      ];

      final first = await loadGroupSharedMediaAnchorWindow(
        repository: repository,
        currentGroupId: 'group-a',
        requestedGroupId: 'group-a',
        messageId: 'm25',
      );
      expect(first, hasLength(51));
      expect(repository.calls.single, ('group-a', 'm25', 25, 25));

      await loadGroupSharedMediaAnchorWindow(
        repository: repository,
        currentGroupId: 'group-a',
        requestedGroupId: 'group-a',
        messageId: 'm30',
      );
      expect(repository.calls.last, ('group-a', 'm30', 25, 25));
      expect(
        repository.calls,
        hasLength(2),
        reason: 'later targets are independent',
      );

      final beforeWrongGroup = repository.calls.length;
      expect(
        await loadGroupSharedMediaAnchorWindow(
          repository: repository,
          currentGroupId: 'group-a',
          requestedGroupId: 'group-b',
          messageId: 'm25',
        ),
        isEmpty,
      );
      expect(repository.calls, hasLength(beforeWrongGroup));

      repository.scripted = [
        _message('foreign', groupId: 'group-b', minute: 1),
      ];
      expect(
        await loadGroupSharedMediaAnchorWindow(
          repository: repository,
          currentGroupId: 'group-a',
          requestedGroupId: 'group-a',
          messageId: 'foreign',
        ),
        isEmpty,
      );

      final compatibilityRepository = InMemoryGroupMessageRepository();
      await compatibilityRepository.saveMessage(
        _message('anchor', groupId: 'group-a', minute: 1),
      );
      await expectLater(
        compatibilityRepository.getMessagesAround(
          'group-a',
          'anchor',
          before: 26,
        ),
        throwsArgumentError,
      );

      final deferred = _DeferredAroundRepository();
      final latestWins = GroupSharedMediaAnchorRequestCoordinator();
      final older = latestWins.load(
        repository: deferred,
        currentGroupId: 'group-a',
        requestedGroupId: 'group-a',
        messageId: 'older',
      );
      final newer = latestWins.load(
        repository: deferred,
        currentGroupId: 'group-a',
        requestedGroupId: 'group-a',
        messageId: 'newer',
      );
      deferred.completers[1].complete([
        _message('newer', groupId: 'group-a', minute: 2),
      ]);
      expect((await newer)!.single.id, 'newer');
      deferred.completers[0].complete([
        _message('older', groupId: 'group-a', minute: 1),
      ]);
      expect(await older, isNull, reason: 'late prior navigation is fenced');

      final fixture = await MediaRepositoryRealDbFixture.create();
      addTearDown(fixture.dispose);
      for (var index = 0; index < 60; index++) {
        await fixture.seedGroupParent(
          'sql-${index.toString().padLeft(2, '0')}',
          groupId: 'group-a',
          timestamp: DateTime.utc(
            2026,
            7,
            10,
          ).add(Duration(minutes: index)).toIso8601String(),
        );
      }
      await fixture.seedGroupParent(
        'sql-foreign',
        groupId: 'group-b',
        timestamp: DateTime.utc(2026, 7, 10, 1).toIso8601String(),
      );
      final sqlWindow = await dbLoadGroupMessagesAround(
        fixture.db,
        'group-a',
        'sql-30',
        before: 25,
        after: 25,
      );
      expect(sqlWindow, hasLength(51));
      expect(sqlWindow.first['id'], 'sql-05');
      expect(sqlWindow[25]['id'], 'sql-30');
      expect(sqlWindow.last['id'], 'sql-55');
      expect(
        await dbLoadGroupMessagesAround(fixture.db, 'group-a', 'sql-foreign'),
        isEmpty,
      );
    },
  );

  testWidgets(
    'AML-08 production library rechecks lifecycle restriction before batch Save and Share',
    (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const pathProviderChannel = MethodChannel(
        'plugins.flutter.io/path_provider',
      );
      final documentsRoot = Directory.systemTemp.createTempSync(
        'aml08-production-wiring-',
      );
      addTearDown(() => documentsRoot.deleteSync(recursive: true));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            pathProviderChannel,
            (_) async => documentsRoot.path,
          );
      const nativeEgressChannel = MethodChannel(receivedMediaEgressChannelName);
      var nativeEgressCalls = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(nativeEgressChannel, (call) async {
            nativeEgressCalls++;
            final request = Map<Object?, Object?>.from(call.arguments as Map);
            final destination = request['destination'];
            final items = (request['items'] as List).cast<Map>();
            return <String, Object?>{
              'requestId': request['requestId'],
              'outcome': destination == 'share' ? 'presented' : 'saved',
              'items': destination == 'share'
                  ? const <Object?>[]
                  : [
                      for (final item in items)
                        <String, Object?>{
                          'attachmentId': item['attachmentId'],
                          'outcome': 'saved',
                        },
                    ],
            };
          });
      addTearDown(() {
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        messenger.setMockMethodCallHandler(pathProviderChannel, null);
        messenger.setMockMethodCallHandler(nativeEgressChannel, null);
      });
      final tinyPng = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );

      Future<void> exercise({required bool save}) async {
        final suffix = save ? 'save' : 'share';
        var lifecycleRestricted = false;
        final group = GroupModel(
          id: 'announcement-$suffix',
          name: 'Lifecycle proof $suffix',
          type: GroupType.announcement,
          topicName: 'lifecycle-proof-$suffix',
          createdAt: DateTime.utc(2026, 7, 11),
          createdBy: 'peer-admin',
          myRole: GroupRole.admin,
        );
        final groups = InMemoryGroupRepository();
        await groups.saveGroup(group);
        final messages = InMemoryGroupMessageRepository();
        final entries = [
          groupMediaEntry(
            'control-$suffix',
            messageId: 'control-message-$suffix',
            mime: 'image/png',
            downloadStatus: 'done',
            localPath: 'media/${group.id}/control-$suffix.png',
          ),
          groupMediaEntry(
            'guarded-$suffix',
            messageId: 'guarded-message-$suffix',
            mime: 'image/png',
            downloadStatus: 'done',
            localPath: 'media/${group.id}/guarded-$suffix.png',
          ),
        ];
        final media = _NestedRouteMediaRepository(
          StrictGroupMediaLibraryRepository(
            expectedGroupId: group.id,
            entries: entries,
          ),
        );
        for (var index = 0; index < entries.length; index++) {
          final entry = entries[index];
          await messages.saveMessage(
            _message(
              entry.attachment.messageId,
              groupId: group.id,
              minute: index + 1,
            ),
          );
          await media.saveAttachment(
            entry.attachment,
            owner: MediaOwnerLane.group,
          );
          File('${documentsRoot.path}/${entry.attachment.localPath}')
            ..parent.createSync(recursive: true)
            ..writeAsBytesSync(tinyPng, flush: true);
        }
        final guardedAttachmentId = entries.last.attachment.id;
        final egress = _RecordingReceivedMediaEgressService();
        final mediaActions = GroupReceivedMediaActionsController(
          messageRepository: messages,
          mediaAttachmentRepository: media,
          egressService: egress,
          isEgressRestricted: (attachment) =>
              lifecycleRestricted && attachment.id == guardedAttachmentId,
          requestIdFactory: () => 'aml08-$suffix',
        );
        final controlDecision = await tester.runAsync(
          () => qualifyCurrentGroupMediaRow(
            groupId: group.id,
            messageId: entries.first.attachment.messageId,
            attachmentId: entries.first.attachment.id,
            messageRepository: messages,
            mediaAttachmentRepository: media,
            mediaFileManager: mediaActions.mediaFileManager,
            isEgressRestricted: mediaActions.isEgressRestricted,
          ),
        );
        expect(controlDecision, isNotNull);
        expect(
          controlDecision!.isQualified,
          isTrue,
          reason: 'eligible control fixture: ${controlDecision.refusalReason}',
        );
        final listener = GroupMessageListener(
          groupRepo: groups,
          msgRepo: messages,
        );

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: GroupConversationWired(
              group: group,
              groupRepo: groups,
              msgRepo: messages,
              groupMessageListener: listener,
              bridge: FakeBridge(),
              identityRepo: _IdentityRepository(
                IdentityModel(
                  peerId: 'peer-admin',
                  publicKey: 'pk-admin',
                  privateKey: 'sk-admin',
                  mnemonic12:
                      'one two three four five six seven eight nine ten eleven twelve',
                  username: 'Admin',
                  createdAt: '2026-07-11T00:00:00.000Z',
                  updatedAt: '2026-07-11T00:00:00.000Z',
                ),
              ),
              contactRepo: InMemoryContactRepository(),
              p2pService: FakeP2PService(
                initialState: const NodeState(
                  isStarted: true,
                  peerId: 'peer-admin',
                  relayState: 'online',
                ),
              ),
              mediaAttachmentRepo: media,
              mediaActionsController: mediaActions,
            ),
          ),
        );
        await _pumpFrames(tester, count: 30);
        await tester.tap(find.byIcon(Icons.info_outline));
        await _pumpFrames(tester, count: 20);
        final libraryEntry = find.byKey(
          const ValueKey('group-shared-media-entry'),
        );
        await tester.ensureVisible(libraryEntry);
        await tester.tap(libraryEntry);
        await _pumpFrames(tester, count: 20);

        Future<void> select(String attachmentId) async {
          await tester.longPress(
            find.byKey(ValueKey('group-shared-media-tile-$attachmentId')),
          );
          await tester.pump();
          expect(
            find.byKey(const ValueKey('group-shared-media-action-save')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('group-shared-media-action-share')),
            findsOneWidget,
          );
        }

        Future<void> performSelectedAction() async {
          if (save) {
            tester
                .widget<TextButton>(
                  find.byKey(const ValueKey('group-shared-media-action-save')),
                )
                .onPressed!();
            await tester.pump();
            final filesAction = tester.widget(
              find.byKey(DirectMediaSaveDestinationSheet.filesActionKey),
            );
            (filesAction as dynamic).onTap();
          } else {
            tester
                .widget<TextButton>(
                  find.byKey(const ValueKey('group-shared-media-action-share')),
                )
                .onPressed!();
          }
          for (var index = 0; index < 10; index++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 20)),
            );
            await tester.pump(const Duration(milliseconds: 20));
          }
        }

        // First prove this production route is actually using the injected
        // controller's egress seam. The pre-fix fresh service fails here.
        await select(entries.first.attachment.id);
        await performSelectedAction();
        expect(egress.calls, hasLength(1));
        expect(
          egress.calls.single.selection.single.attachmentId,
          entries.first.attachment.id,
        );
        expect(nativeEgressCalls, 0);

        // The second row is selected while eligible, then becomes restricted
        // without rebuilding the toolbar. Dispatch must recheck and stop at
        // both the injected egress seam and the native channel.
        await select(guardedAttachmentId);
        final egressCallsBeforeRestriction = egress.calls.length;
        final nativeCallsBeforeRestriction = nativeEgressCalls;
        lifecycleRestricted = true;
        await performSelectedAction();
        expect(egress.calls, hasLength(egressCallsBeforeRestriction));
        expect(nativeEgressCalls, nativeCallsBeforeRestriction);
        expect(
          find.byKey(const ValueKey('group-shared-media-selection-title')),
          findsOneWidget,
          reason: 'a denied row must remain selected for retry or deselection',
        );
        await tester.pumpWidget(const SizedBox.shrink());
        listener.dispose();
      }

      await exercise(save: false);
      await exercise(save: true);
    },
  );

  testWidgets(
    'GML-10R GML-13W nested repeats scroll without local delivery bypass',
    (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const pathProviderChannel = MethodChannel(
        'plugins.flutter.io/path_provider',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            pathProviderChannel,
            (_) async => Directory.systemTemp.path,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(pathProviderChannel, null),
      );

      final group = GroupModel(
        id: 'group-a',
        name: 'Route proof group',
        type: GroupType.chat,
        topicName: 'route-proof-topic',
        createdAt: DateTime.utc(2026, 7, 10),
        createdBy: 'peer-admin',
        myRole: GroupRole.admin,
      );
      final groupRepository = InMemoryGroupRepository();
      await groupRepository.saveGroup(group);
      final messageRepository = _NestedRouteMessageRepository();
      for (var index = 0; index < 60; index++) {
        await messageRepository.saveMessage(
          _message(
            'm${index.toString().padLeft(2, '0')}',
            groupId: group.id,
            minute: index,
          ),
        );
      }
      final libraryEntries = [
        groupMediaEntry(
          'target-02',
          messageId: 'm02',
          downloadStatus: 'done',
          localPath: 'noncanonical/target-02.jpg',
        ),
        groupMediaEntry(
          'target-40',
          messageId: 'm40',
          downloadStatus: 'done',
          localPath: 'noncanonical/target-40.jpg',
        ),
      ];
      final mediaRepository = _NestedRouteMediaRepository(
        StrictGroupMediaLibraryRepository(
          expectedGroupId: group.id,
          entries: libraryEntries,
        ),
      );
      for (final entry in libraryEntries) {
        await mediaRepository.saveAttachment(
          entry.attachment,
          owner: MediaOwnerLane.group,
        );
      }
      final listener = GroupMessageListener(
        groupRepo: groupRepository,
        msgRepo: messageRepository,
      );
      final bridge = FakeBridge();
      final p2pService = FakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'peer-admin',
          relayState: 'online',
        ),
      );
      final deleteCoordinator = _RecordingDeleteCoordinator();
      final forwarded = <GroupMediaForwardRequest>[];
      final identityRepository = _IdentityRepository(
        IdentityModel(
          peerId: 'peer-admin',
          publicKey: 'pk-admin',
          privateKey: 'sk-admin',
          mnemonic12:
              'one two three four five six seven eight nine ten eleven twelve',
          username: 'Admin',
          createdAt: '2026-07-10T00:00:00.000Z',
          updatedAt: '2026-07-10T00:00:00.000Z',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GroupConversationWired(
            group: group,
            groupRepo: groupRepository,
            msgRepo: messageRepository,
            groupMessageListener: listener,
            bridge: bridge,
            identityRepo: identityRepository,
            contactRepo: InMemoryContactRepository(),
            p2pService: p2pService,
            mediaAttachmentRepo: mediaRepository,
            mediaDeleteForMeCoordinator: deleteCoordinator,
            groupMediaForwardLauncher: (_, request) async {
              forwarded.add(request);
            },
          ),
        ),
      );
      await _pumpFrames(tester, count: 30);

      final mountedConversation = tester.element(
        find.byType(GroupConversationWired),
      );
      final initialBridgeSendCalls = bridge.sendCallCount;
      final initialP2pSendCalls = p2pService.sendMessageCallCount;
      final initialP2pReplyCalls = p2pService.sendMessageWithReplyCallCount;
      final initialInboxCalls = p2pService.storeInInboxCallCount;

      void expectNoDeliveryCalls() {
        expect(bridge.sendCallCount, initialBridgeSendCalls);
        expect(p2pService.sendMessageCallCount, initialP2pSendCalls);
        expect(p2pService.sendMessageWithReplyCallCount, initialP2pReplyCalls);
        expect(p2pService.storeInInboxCallCount, initialInboxCalls);
      }

      void pressAction(ValueKey<String> key) {
        tester.widget<TextButton>(find.byKey(key)).onPressed!();
      }

      Future<void> openLibraryAndSelect(List<String> attachmentIds) async {
        await tester.tap(find.byIcon(Icons.info_outline));
        await _pumpFrames(tester, count: 20);
        expect(find.byType(GroupInfoScreen), findsOneWidget);

        final entry = find.byKey(const ValueKey('group-shared-media-entry'));
        await tester.ensureVisible(entry);
        await tester.tap(entry);
        await _pumpFrames(tester, count: 20);
        expect(find.byType(GroupSharedMediaLibraryScreen), findsOneWidget);

        for (final attachmentId in attachmentIds) {
          await tester.longPress(
            find.byKey(ValueKey('group-shared-media-tile-$attachmentId')),
          );
          await tester.pump();
        }
      }

      Future<void> expectConversationTarget(String messageId) async {
        await _pumpFrames(tester, count: 30);

        expect(find.byType(GroupInfoScreen), findsNothing);
        expect(find.byType(GroupSharedMediaLibraryScreen), findsNothing);
        expect(
          identical(
            mountedConversation,
            tester.element(find.byType(GroupConversationWired)),
          ),
          isTrue,
          reason: 'the nested result must return to the same mounted route',
        );
        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.highlightedMessageId, messageId);
        expect(
          screen.messages.any((message) => message.id == messageId),
          isTrue,
        );
        final highlight = find.byKey(ValueKey('grp-highlight-$messageId'));
        expect(
          highlight,
          findsOneWidget,
          reason: 'each route result must rebuild its lazy target row',
        );
        expect(
          tester
              .getRect(highlight)
              .overlaps(
                tester.getRect(find.byKey(const ValueKey('group-messages'))),
              ),
          isTrue,
          reason: 'each repeated target must scroll into the visible viewport',
        );
        expectNoDeliveryCalls();
      }

      Future<void> goTo(String attachmentId, String messageId) async {
        await openLibraryAndSelect([attachmentId]);
        pressAction(const ValueKey('group-shared-media-action-goto'));
        await expectConversationTarget(messageId);
      }

      // Exercise every production-wired local action boundary before taking
      // the real nested Go-to route. Failed local preflight/reconciliation is
      // intentional: it keeps selection active while proving none of these
      // callbacks can bypass into Bridge/P2P/internal delivery.
      await openLibraryAndSelect(['target-02']);
      for (final key in const [
        ValueKey('group-shared-media-action-save'),
        ValueKey('group-shared-media-action-share'),
        ValueKey('group-shared-media-action-delete'),
        ValueKey('group-shared-media-action-evict'),
        ValueKey('group-shared-media-action-forward'),
        ValueKey('group-shared-media-action-goto'),
      ]) {
        expect(find.byKey(key), findsOneWidget);
      }

      pressAction(const ValueKey('group-shared-media-action-share'));
      await _pumpFrames(tester);
      expectNoDeliveryCalls();

      pressAction(const ValueKey('group-shared-media-action-save'));
      await tester.pump();
      final filesAction = tester.widget(
        find.byKey(DirectMediaSaveDestinationSheet.filesActionKey),
      );
      (filesAction as dynamic).onTap();
      await _pumpFrames(tester);
      expectNoDeliveryCalls();

      pressAction(const ValueKey('group-shared-media-action-evict'));
      await _pumpFrames(tester);
      expectNoDeliveryCalls();

      pressAction(const ValueKey('group-shared-media-action-forward'));
      await _pumpFrames(tester);
      expect(forwarded, hasLength(1));
      expect(forwarded.single.groupId, 'group-a');
      expect(forwarded.single.messageId, 'm02');
      expect(forwarded.single.attachmentId, 'target-02');
      expectNoDeliveryCalls();

      pressAction(const ValueKey('group-shared-media-action-delete'));
      await tester.pump();
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('group-shared-media-delete-confirm')),
          )
          .onPressed!();
      await _pumpFrames(tester);
      expect(deleteCoordinator.calls, [('group-a', 'm02')]);
      expectNoDeliveryCalls();

      await tester.longPress(
        find.byKey(const ValueKey('group-shared-media-tile-target-40')),
      );
      await tester.pump();
      expect(
        find.byKey(const ValueKey('group-shared-media-action-forward')),
        findsNothing,
        reason: 'multi-select must not expose internal Forward',
      );
      pressAction(const ValueKey('group-shared-media-action-bookmark'));
      await _pumpFrames(tester);
      expect(
        mediaRepository.library.bookmarkWrites,
        containsAll([('target-02', true), ('target-40', true)]),
      );
      expect(forwarded, hasLength(1));
      expectNoDeliveryCalls();

      await tester.longPress(
        find.byKey(const ValueKey('group-shared-media-tile-target-02')),
      );
      await tester.pump();
      pressAction(const ValueKey('group-shared-media-action-goto'));
      await expectConversationTarget('m02');
      await goTo('target-40', 'm40');
      await goTo('target-02', 'm02');

      expect(messageRepository.aroundCalls, [
        ('group-a', 'm02', 25, 25),
        ('group-a', 'm40', 25, 25),
        ('group-a', 'm02', 25, 25),
      ]);

      await tester.pumpWidget(const SizedBox.shrink());
      listener.dispose();
    },
  );

  testWidgets(
    'AML-05R announcement anchor survives a late resume page in the same State',
    (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const pathProviderChannel = MethodChannel(
        'plugins.flutter.io/path_provider',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            pathProviderChannel,
            (_) async => Directory.systemTemp.path,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(pathProviderChannel, null),
      );
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );

      final group = GroupModel(
        id: 'announcement-a',
        name: 'Route race announcement',
        type: GroupType.announcement,
        topicName: 'route-race-announcement',
        createdAt: DateTime.utc(2026, 7, 10),
        createdBy: 'peer-admin',
        myRole: GroupRole.admin,
      );
      final groupRepository = InMemoryGroupRepository();
      await groupRepository.saveGroup(group);
      final messageRepository = _DeferredRouteRaceMessageRepository();
      for (var index = 0; index < 80; index++) {
        await messageRepository.saveMessage(
          _message(
            'a${index.toString().padLeft(2, '0')}',
            groupId: group.id,
            minute: index,
          ),
        );
      }
      final targetEntry = groupMediaEntry(
        'announcement-target-05',
        messageId: 'a05',
        downloadStatus: 'done',
        localPath: 'noncanonical/announcement-target-05.jpg',
      );
      final mediaRepository = _NestedRouteMediaRepository(
        StrictGroupMediaLibraryRepository(
          expectedGroupId: group.id,
          entries: [targetEntry],
        ),
      );
      await mediaRepository.saveAttachment(
        targetEntry.attachment,
        owner: MediaOwnerLane.group,
      );
      final listener = _ControllableGroupMessageListener(
        groupRepo: groupRepository,
        msgRepo: messageRepository,
      );
      final bridge = FakeBridge();
      final p2pService = FakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'peer-admin',
          relayState: 'online',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GroupConversationWired(
            group: group,
            groupRepo: groupRepository,
            msgRepo: messageRepository,
            groupMessageListener: listener,
            bridge: bridge,
            identityRepo: _IdentityRepository(
              IdentityModel(
                peerId: 'peer-admin',
                publicKey: 'pk-admin',
                privateKey: 'sk-admin',
                mnemonic12:
                    'one two three four five six seven eight nine ten eleven twelve',
                username: 'Admin',
                createdAt: '2026-07-10T00:00:00.000Z',
                updatedAt: '2026-07-10T00:00:00.000Z',
              ),
            ),
            contactRepo: InMemoryContactRepository(),
            p2pService: p2pService,
            mediaAttachmentRepo: mediaRepository,
          ),
        ),
      );
      await _pumpFrames(tester, count: 30);

      final mountedState = tester.state(find.byType(GroupConversationWired));
      final initialBridgeSendCalls = bridge.sendCallCount;
      final initialP2pSendCalls = p2pService.sendMessageCallCount;
      final initialP2pReplyCalls = p2pService.sendMessageWithReplyCallCount;
      final initialInboxCalls = p2pService.storeInInboxCallCount;

      messageRepository.deferNextAnchorWindow();
      await tester.tap(find.byIcon(Icons.info_outline));
      await _pumpFrames(tester, count: 20);
      await tester.tap(find.byKey(const ValueKey('group-shared-media-entry')));
      await _pumpFrames(tester, count: 20);
      await tester.longPress(
        find.byKey(
          const ValueKey('group-shared-media-tile-announcement-target-05'),
        ),
      );
      await tester.pump();
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('group-shared-media-action-goto')),
          )
          .onPressed!();
      await _pumpFrames(tester, count: 20);
      expect(messageRepository.anchorWindowStarted, isTrue);

      messageRepository.deferNextLatestPage();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _pumpFrames(tester, count: 5);
      expect(messageRepository.latestPageStarted, isTrue);

      messageRepository.releaseAnchorWindow();
      await _pumpFrames(tester, count: 30);

      var screen = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      expect(screen.highlightedMessageId, 'a05');
      expect(screen.messages.any((message) => message.id == 'a05'), isTrue);
      expect(find.byKey(const ValueKey('grp-highlight-a05')), findsOneWidget);
      expect(
        identical(
          mountedState,
          tester.state(find.byType(GroupConversationWired)),
        ),
        isTrue,
      );

      // A live message + media mutation after the bounded anchor resolves is
      // newer authority than both captured snapshots.
      final updatedTarget = (await messageRepository.getMessage(
        'a05',
      ))!.copyWith(text: 'a05 live update', status: 'delivered');
      await messageRepository.saveMessage(updatedTarget);
      await mediaRepository.saveAttachment(
        targetEntry.attachment.copyWith(
          downloadStatus: 'integrity_failed',
          clearLocalPath: true,
        ),
        owner: MediaOwnerLane.group,
      );
      listener.emit(updatedTarget);
      await _pumpFrames(tester, count: 20);
      screen = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      expect(
        screen.messages.firstWhere((message) => message.id == 'a05').text,
        'a05 live update',
      );
      expect(screen.mediaMap['a05']!.single.downloadStatus, 'integrity_failed');

      messageRepository.releaseLatestPage();
      await _pumpFrames(tester, count: 30);

      screen = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      expect(screen.highlightedMessageId, 'a05');
      expect(
        screen.messages.any((message) => message.id == 'a05'),
        isTrue,
        reason: 'the bounded anchor window must survive the late latest page',
      );
      expect(
        screen.messages.firstWhere((message) => message.id == 'a05').text,
        'a05 live update',
        reason: 'the late page must not roll back a newer live row',
      );
      expect(
        screen.mediaMap['a05']!.single.downloadStatus,
        'integrity_failed',
        reason: 'the late page must not roll back newer local media state',
      );
      expect(find.byKey(const ValueKey('grp-highlight-a05')), findsOneWidget);
      expect(
        identical(
          mountedState,
          tester.state(find.byType(GroupConversationWired)),
        ),
        isTrue,
      );
      expect(bridge.sendCallCount, initialBridgeSendCalls);
      expect(p2pService.sendMessageCallCount, initialP2pSendCalls);
      expect(p2pService.sendMessageWithReplyCallCount, initialP2pReplyCalls);
      expect(p2pService.storeInInboxCallCount, initialInboxCalls);
      expect(
        messageRepository.aroundCallCount,
        1,
        reason: 'the late page reuses the one bounded anchor answer',
      );

      await tester.pumpWidget(const SizedBox.shrink());
      listener.dispose();
    },
  );

  testWidgets(
    'AML-05D local deletion wins pending anchor and late resume snapshots',
    (tester) async {
      tester.view.physicalSize = const Size(600, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      const pathProviderChannel = MethodChannel(
        'plugins.flutter.io/path_provider',
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            pathProviderChannel,
            (_) async => Directory.systemTemp.path,
          );
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(pathProviderChannel, null),
      );
      addTearDown(
        () => tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        ),
      );

      final group = GroupModel(
        id: 'announcement-delete-race',
        name: 'Delete race announcement',
        type: GroupType.announcement,
        topicName: 'delete-race-announcement',
        createdAt: DateTime.utc(2026, 7, 10),
        createdBy: 'peer-admin',
        myRole: GroupRole.admin,
      );
      final groups = InMemoryGroupRepository();
      await groups.saveGroup(group);
      final messages = _DeferredRouteRaceMessageRepository();
      for (var index = 0; index < 80; index++) {
        await messages.saveMessage(
          _message(
            'd${index.toString().padLeft(2, '0')}',
            groupId: group.id,
            minute: index,
          ),
        );
      }
      final targetEntry = groupMediaEntry(
        'announcement-target-60',
        messageId: 'd60',
        downloadStatus: 'done',
        localPath: 'noncanonical/announcement-target-60.jpg',
      );
      final media = _NestedRouteMediaRepository(
        StrictGroupMediaLibraryRepository(
          expectedGroupId: group.id,
          entries: [targetEntry],
        ),
      );
      await media.saveAttachment(
        targetEntry.attachment,
        owner: MediaOwnerLane.group,
      );
      final listener = _ControllableGroupMessageListener(
        groupRepo: groups,
        msgRepo: messages,
      );
      final bridge = FakeBridge();
      final p2pService = FakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'peer-admin',
          relayState: 'online',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GroupConversationWired(
            group: group,
            groupRepo: groups,
            msgRepo: messages,
            groupMessageListener: listener,
            bridge: bridge,
            identityRepo: _IdentityRepository(
              IdentityModel(
                peerId: 'peer-admin',
                publicKey: 'pk-admin',
                privateKey: 'sk-admin',
                mnemonic12:
                    'one two three four five six seven eight nine ten eleven twelve',
                username: 'Admin',
                createdAt: '2026-07-10T00:00:00.000Z',
                updatedAt: '2026-07-10T00:00:00.000Z',
              ),
            ),
            contactRepo: InMemoryContactRepository(),
            p2pService: p2pService,
            mediaAttachmentRepo: media,
          ),
        ),
      );
      await _pumpFrames(tester, count: 30);
      expect(
        tester
            .widget<GroupConversationScreen>(
              find.byType(GroupConversationScreen),
            )
            .messages
            .any((message) => message.id == 'd60'),
        isTrue,
      );
      final initialBridgeSendCalls = bridge.sendCallCount;
      final initialP2pSendCalls = p2pService.sendMessageCallCount;

      messages.deferNextAnchorWindow();
      await tester.tap(find.byIcon(Icons.info_outline));
      await _pumpFrames(tester, count: 20);
      await tester.tap(find.byKey(const ValueKey('group-shared-media-entry')));
      await _pumpFrames(tester, count: 20);
      final deletionCallback = tester
          .widget<GroupSharedMediaLibraryScreen>(
            find.byType(GroupSharedMediaLibraryScreen),
          )
          .onMessagesDeleted!;
      await tester.longPress(
        find.byKey(
          const ValueKey('group-shared-media-tile-announcement-target-60'),
        ),
      );
      await tester.pump();
      tester
          .widget<TextButton>(
            find.byKey(const ValueKey('group-shared-media-action-goto')),
          )
          .onPressed!();
      await _pumpFrames(tester, count: 20);
      expect(messages.anchorWindowStarted, isTrue);

      messages.deferNextLatestPage();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _pumpFrames(tester, count: 5);
      expect(messages.latestPageStarted, isTrue);

      // This is the production library callback into _removeLocalMessage. It
      // fires while both stale snapshots still contain d60.
      deletionCallback({'d60'});
      await _pumpFrames(tester, count: 5);
      expect(
        tester
            .widget<GroupConversationScreen>(
              find.byType(GroupConversationScreen),
            )
            .messages
            .any((message) => message.id == 'd60'),
        isFalse,
      );

      // A listener may still emit the decoded model when its durable insert
      // was skipped by the local-deletion tombstone. That replay must not
      // transiently resurrect the row while the conversation remains mounted.
      listener.emit(_message('d60', groupId: group.id, minute: 60));
      await _pumpFrames(tester, count: 10);
      expect(
        tester
            .widget<GroupConversationScreen>(
              find.byType(GroupConversationScreen),
            )
            .messages
            .any((message) => message.id == 'd60'),
        isFalse,
      );

      messages.releaseAnchorWindow();
      await _pumpFrames(tester, count: 20);
      expect(
        tester
            .widget<GroupConversationScreen>(
              find.byType(GroupConversationScreen),
            )
            .messages
            .any((message) => message.id == 'd60'),
        isFalse,
      );

      messages.releaseLatestPage();
      await _pumpFrames(tester, count: 30);
      final screen = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      expect(screen.messages.any((message) => message.id == 'd60'), isFalse);
      expect(messages.aroundCallCount, 1);
      expect(bridge.sendCallCount, initialBridgeSendCalls);
      expect(p2pService.sendMessageCallCount, initialP2pSendCalls);

      await tester.pumpWidget(const SizedBox.shrink());
      listener.dispose();
    },
  );
}

class _NestedRouteMessageRepository extends InMemoryGroupMessageRepository
    implements GroupMessageAroundRepository {
  final List<GroupMessage> _seeded = [];
  final List<(String, String, int, int)> aroundCalls = [];

  @override
  Future<void> saveMessage(GroupMessage message) async {
    _seeded.removeWhere((candidate) => candidate.id == message.id);
    _seeded.add(message);
    await super.saveMessage(message);
  }

  @override
  Future<List<GroupMessage>> getMessagesAround(
    String groupId,
    String anchorMessageId, {
    int before = 25,
    int after = 25,
  }) async {
    aroundCalls.add((groupId, anchorMessageId, before, after));
    if (before < 0 || before > 25 || after < 0 || after > 25) {
      throw ArgumentError('before and after must each be 0..25');
    }
    final ordered =
        _seeded.where((message) => message.groupId == groupId).toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final anchorIndex = ordered.indexWhere(
      (message) => message.id == anchorMessageId,
    );
    if (anchorIndex < 0) return const [];
    final start = (anchorIndex - before).clamp(0, ordered.length);
    final end = (anchorIndex + after + 1).clamp(0, ordered.length);
    return ordered.sublist(start, end);
  }
}

class _NestedRouteMediaRepository extends InMemoryMediaAttachmentRepository
    implements
        MediaLibraryRepository,
        MediaLibraryStateRepository,
        MediaDownloadStateRepository {
  _NestedRouteMediaRepository(this.library);

  final StrictGroupMediaLibraryRepository library;

  @override
  Future<MediaLibraryPage> getMediaLibraryPage({
    required MediaLibraryScope scope,
    MediaLibraryFilter filter = const MediaLibraryFilter(),
    int limit = 50,
    String? cursor,
  }) => library.getMediaLibraryPage(
    scope: scope,
    filter: filter,
    limit: limit,
    cursor: cursor,
  );

  @override
  Future<void> setBookmarked(String id, {required bool bookmarked}) =>
      library.setBookmarked(id, bookmarked: bookmarked);

  @override
  Future<void> updatePlaybackPosition(String id, int positionMs) =>
      library.updatePlaybackPosition(id, positionMs);

  @override
  Future<bool> beginMediaDownload(
    String id, {
    required MediaOwnerLane owner,
  }) async => false;

  @override
  Future<bool> commitMediaDownloadLocalPath(
    String id, {
    required MediaOwnerLane owner,
    required String localPath,
  }) async => false;

  @override
  Future<int> claimMediaEvicted(
    String id, {
    required MediaOwnerLane owner,
    required String expectedLocalPath,
  }) async => 0;

  @override
  Future<int> finalizeMediaEvictedPathCleared(
    String id, {
    required MediaOwnerLane owner,
  }) async => 0;
}

class _RecordingDeleteCoordinator implements GroupMediaDeleteForMeCoordinator {
  final List<(String, String)> calls = [];

  @override
  Future<void> deleteForMe({
    required String groupId,
    required String messageId,
  }) async {
    calls.add((groupId, messageId));
  }
}

class _RecordingReceivedMediaEgressService extends ReceivedMediaEgressService {
  final List<
    ({
      MediaEgressDestination destination,
      List<ReceivedMediaEgressCandidate> selection,
    })
  >
  calls = [];

  @override
  Future<MediaEgressResult> perform({
    required String requestId,
    required MediaEgressDestination destination,
    required List<ReceivedMediaEgressCandidate> selection,
  }) async {
    calls.add((destination: destination, selection: List.of(selection)));
    return MediaEgressResult(
      requestId: requestId,
      outcome: destination == MediaEgressDestination.share
          ? MediaEgressOutcome.presented
          : MediaEgressOutcome.saved,
      items: [
        for (final candidate in selection)
          MediaEgressItemResult(
            attachmentId: candidate.attachmentId,
            outcome: MediaEgressItemOutcome.saved,
          ),
      ],
    );
  }
}

class _IdentityRepository implements IdentityRepository {
  _IdentityRepository(this.identity);

  IdentityModel? identity;

  @override
  Future<IdentityModel?> loadIdentity() async => identity;

  @override
  Future<void> saveIdentity(IdentityModel identity) async {
    this.identity = identity;
  }
}

Future<void> _pumpFrames(WidgetTester tester, {int count = 10}) async {
  for (var index = 0; index < count; index++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

class _RecordingAroundRepository extends InMemoryGroupMessageRepository
    implements GroupMessageAroundRepository {
  List<GroupMessage> scripted = const [];
  final List<(String, String, int, int)> calls = [];

  @override
  Future<List<GroupMessage>> getMessagesAround(
    String groupId,
    String anchorMessageId, {
    int before = 25,
    int after = 25,
  }) async {
    calls.add((groupId, anchorMessageId, before, after));
    return scripted;
  }
}

class _DeferredAroundRepository extends InMemoryGroupMessageRepository
    implements GroupMessageAroundRepository {
  final List<Completer<List<GroupMessage>>> completers = [];

  @override
  Future<List<GroupMessage>> getMessagesAround(
    String groupId,
    String anchorMessageId, {
    int before = 25,
    int after = 25,
  }) {
    final completer = Completer<List<GroupMessage>>();
    completers.add(completer);
    return completer.future;
  }
}

class _ControllableGroupMessageListener extends GroupMessageListener {
  _ControllableGroupMessageListener({
    required super.groupRepo,
    required super.msgRepo,
  });

  final StreamController<GroupMessage> _controller =
      StreamController<GroupMessage>.broadcast();

  @override
  Stream<GroupMessage> get groupMessageStream => _controller.stream;

  void emit(GroupMessage message) => _controller.add(message);

  @override
  void dispose() {
    unawaited(_controller.close());
    super.dispose();
  }
}

class _DeferredRouteRaceMessageRepository extends InMemoryGroupMessageRepository
    implements GroupMessageAroundRepository {
  final List<GroupMessage> _seeded = [];
  bool _deferNextAnchorWindow = false;
  bool _deferNextLatestPage = false;
  Completer<void>? _anchorWindowGate;
  Completer<void>? _anchorWindowStarted;
  Completer<void>? _latestPageGate;
  Completer<void>? _latestPageStarted;
  int aroundCallCount = 0;

  bool get anchorWindowStarted => _anchorWindowStarted?.isCompleted ?? false;
  bool get latestPageStarted => _latestPageStarted?.isCompleted ?? false;

  @override
  Future<void> saveMessage(GroupMessage message) async {
    _seeded.removeWhere((candidate) => candidate.id == message.id);
    _seeded.add(message);
    await super.saveMessage(message);
  }

  void deferNextAnchorWindow() {
    _deferNextAnchorWindow = true;
    _anchorWindowGate = Completer<void>();
    _anchorWindowStarted = Completer<void>();
  }

  void releaseAnchorWindow() {
    final gate = _anchorWindowGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  void deferNextLatestPage() {
    _deferNextLatestPage = true;
    _latestPageGate = Completer<void>();
    _latestPageStarted = Completer<void>();
  }

  void releaseLatestPage() {
    final gate = _latestPageGate;
    if (gate != null && !gate.isCompleted) gate.complete();
  }

  @override
  Future<List<GroupMessage>> getMessagesPage(
    String groupId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final page = await super.getMessagesPage(
      groupId,
      limit: limit,
      offset: offset,
    );
    if (!_deferNextLatestPage) return page;
    _deferNextLatestPage = false;
    _latestPageStarted!.complete();
    await _latestPageGate!.future;
    return page;
  }

  @override
  Future<List<GroupMessage>> getMessagesAround(
    String groupId,
    String anchorMessageId, {
    int before = 25,
    int after = 25,
  }) async {
    aroundCallCount++;
    final ordered =
        _seeded.where((message) => message.groupId == groupId).toList()
          ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final anchorIndex = ordered.indexWhere(
      (message) => message.id == anchorMessageId,
    );
    if (anchorIndex < 0) return const [];
    final start = (anchorIndex - before).clamp(0, ordered.length);
    final end = (anchorIndex + after + 1).clamp(0, ordered.length);
    final window = ordered.sublist(start, end);
    if (!_deferNextAnchorWindow) return window;
    _deferNextAnchorWindow = false;
    _anchorWindowStarted!.complete();
    await _anchorWindowGate!.future;
    return window;
  }
}

GroupMessage _message(
  String id, {
  required String groupId,
  required int minute,
}) {
  return GroupMessage(
    id: id,
    groupId: groupId,
    senderPeerId: 'peer',
    text: id,
    timestamp: DateTime.utc(2026, 7, 10).add(Duration(minutes: minute)),
    isIncoming: true,
    createdAt: DateTime.utc(2026, 7, 10).add(Duration(minutes: minute)),
  );
}
