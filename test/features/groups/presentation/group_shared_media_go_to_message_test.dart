import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/database/helpers/group_messages_db_helpers.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_library.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/direct_received_media_action_sheet.dart';
import 'package:flutter_app/features/groups/application/group_media_delete_for_me_coordinator.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_intent.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
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
