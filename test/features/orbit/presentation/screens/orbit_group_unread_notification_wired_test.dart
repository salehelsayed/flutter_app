import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/app_root_notification_open.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_sink.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_intent.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_avatar.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_wired.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';

import '../../../../core/bridge/fake_bridge.dart';
import '../../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/fake_media_file_manager.dart';
import '../../../../shared/fakes/in_memory_feed_cleared_repository.dart';
import '../../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../../shared/fakes/in_memory_group_repository.dart';
import '../../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../../shared/fakes/in_memory_message_repository.dart';
import '../../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../../contact_request/domain/repositories/fake_contact_request_repository.dart';
import '../../../identity/domain/repositories/fake_identity_repository.dart';

void main() {
  setUp(() {
    setGroupExitIntentAccessSinks(
      forGroup: (_) async => null,
      all: () async => const <GroupExitIntent>[],
    );
  });
  tearDown(setGroupExitIntentAccessSinks);

  late FakeIdentityRepository identityRepo;
  late FakeContactRepository contactRepo;
  late FakeContactRequestRepository contactRequestRepo;
  late FakeBridge bridge;
  late FakeP2PService p2pService;
  late FakeSecureKeyStore secureKeyStore;
  late InMemoryMessageRepository messageRepo;
  late InMemoryMediaAttachmentRepository mediaAttachmentRepo;
  late FakeMediaFileManager mediaFileManager;
  late ImageProcessor imageProcessor;
  late InMemoryGroupRepository groupRepo;
  late InMemoryGroupMessageRepository groupMsgRepo;
  late GroupMessageListener groupMessageListener;
  late ActiveConversationTracker groupConversationTracker;
  late List<Map<String, dynamic>> flowEvents;

  final identity = IdentityModel(
    peerId: 'peer-self',
    publicKey: 'self-public-key',
    privateKey: 'self-private-key',
    mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
    username: 'Alice',
    createdAt: DateTime.utc(2026, 7, 12).toIso8601String(),
    updatedAt: DateTime.utc(2026, 7, 12).toIso8601String(),
  );

  setUp(() {
    identityRepo = FakeIdentityRepository()..seed(identity);
    contactRepo = FakeContactRepository();
    contactRequestRepo = FakeContactRequestRepository();
    bridge = FakeBridge();
    p2pService = FakeP2PService();
    secureKeyStore = FakeSecureKeyStore();
    messageRepo = InMemoryMessageRepository();
    mediaAttachmentRepo = InMemoryMediaAttachmentRepository();
    mediaFileManager = FakeMediaFileManager();
    groupRepo = InMemoryGroupRepository();
    groupMsgRepo = InMemoryGroupMessageRepository();
    groupMessageListener = GroupMessageListener(
      groupRepo: groupRepo,
      msgRepo: groupMsgRepo,
      bridge: bridge,
      getSelfPeerId: () async => identity.peerId,
    );
    groupConversationTracker = ActiveConversationTracker();
    flowEvents = <Map<String, dynamic>>[];
    debugSetFlowEventSink(flowEvents.add);
    imageProcessor = ImageProcessor(
      compressFile:
          ({
            required path,
            required quality,
            required keepExif,
            minWidth = 1920,
            minHeight = 1080,
          }) async => null,
      compressVideo: ({required path, required compress, onProgress}) async =>
          null,
    );
  });

  tearDown(() {
    groupMessageListener.dispose();
    debugSetFlowEventSink(null);
  });

  void setLargeTestSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  void suppressRenderingNoise() {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.contains('overflowed') ||
          message.contains('Unable to load asset') ||
          message.contains('SvgPicture') ||
          message.contains('ImageFilter')) {
        return;
      }
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);
  }

  Widget buildOrbit({
    AppShellController? shellController,
    GlobalKey<NavigatorState>? navigatorKey,
  }) {
    final requestListener = ContactRequestListener(
      contactRequestStream: const Stream<ChatMessage>.empty(),
      requestRepo: contactRequestRepo,
      contactRepo: contactRepo,
      bridge: bridge,
      getOwnPeerId: () => identity.peerId,
    );
    final chatListener = ChatMessageListener(
      chatMessageStream: const Stream<ChatMessage>.empty(),
      messageRepo: messageRepo,
      contactRepo: contactRepo,
    );

    return MaterialApp(
      navigatorKey: navigatorKey,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: OrbitWired(
        identityRepo: identityRepo,
        contactRepo: contactRepo,
        contactRequestRepo: contactRequestRepo,
        contactRequestListener: requestListener,
        messageRepo: messageRepo,
        mediaAttachmentRepo: mediaAttachmentRepo,
        chatMessageListener: chatListener,
        bridge: bridge,
        p2pService: p2pService,
        mediaFileManager: mediaFileManager,
        secureKeyStore: secureKeyStore,
        imageProcessor: imageProcessor,
        feedClearedRepository: InMemoryFeedClearedRepository(),
        groupRepository: groupRepo,
        groupMessageRepository: groupMsgRepo,
        groupMessageListener: groupMessageListener,
        groupConversationTracker: groupConversationTracker,
        appShellController: shellController,
      ),
    );
  }

  Future<void> seedUnreadGroup({
    required String id,
    required String name,
    required GroupType type,
  }) async {
    final timestamp = DateTime.utc(2026, 7, 12, 10, id.hashCode.abs() % 50);
    await groupRepo.saveGroup(
      GroupModel(
        id: id,
        name: name,
        type: type,
        topicName: 'topic-$id',
        createdAt: timestamp.subtract(const Duration(days: 1)),
        createdBy: 'peer-admin',
        myRole: type == GroupType.announcement
            ? GroupRole.member
            : GroupRole.admin,
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: id,
        peerId: identity.peerId,
        username: identity.username,
        role: type == GroupType.announcement
            ? MemberRole.reader
            : MemberRole.admin,
        joinedAt: timestamp.subtract(const Duration(days: 1)),
      ),
    );
    await groupRepo.saveMember(
      GroupMember(
        groupId: id,
        peerId: 'peer-admin',
        username: 'Admin',
        role: MemberRole.admin,
        joinedAt: timestamp.subtract(const Duration(days: 1)),
      ),
    );
    await groupMsgRepo.saveMessage(
      GroupMessage(
        id: 'message-$id',
        groupId: id,
        senderPeerId: 'peer-admin',
        senderUsername: 'Admin',
        text: 'Unread $name message',
        timestamp: timestamp,
        isIncoming: true,
        createdAt: timestamp,
      ),
    );
  }

  Future<void> pumpOrbitFrames(WidgetTester tester, {int count = 6}) async {
    for (var index = 0; index < count; index++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  String groupSemanticsLabel(WidgetTester tester, String groupId) {
    final finder = find.byWidgetPredicate(
      (widget) => widget is GroupAvatar && widget.groupId == groupId,
      description: 'GroupAvatar($groupId)',
    );
    expect(finder, findsOneWidget);
    return tester.getSemantics(finder).label;
  }

  testWidgets('notification-routed read clears chat and announcement nodes', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final navigatorKey = GlobalKey<NavigatorState>();
    setLargeTestSurface(tester);
    suppressRenderingNoise();
    await seedUnreadGroup(
      id: 'chat-group',
      name: 'Discussion Group',
      type: GroupType.chat,
    );
    await seedUnreadGroup(
      id: 'announcement-group',
      name: 'Announcement Group',
      type: GroupType.announcement,
    );

    await tester.pumpWidget(buildOrbit(navigatorKey: navigatorKey));
    await pumpOrbitFrames(tester);

    expect(
      groupSemanticsLabel(tester, 'chat-group'),
      contains('1 unread message'),
    );
    expect(
      groupSemanticsLabel(tester, 'announcement-group'),
      contains('1 unread message'),
    );

    Future<void> openFromNotification({
      required String groupId,
      required String messageId,
    }) async {
      await routeAppRootLocalNotificationTap(
        payload: NotificationRouteTarget.group(
          groupId,
          messageId: messageId,
        ).toPayload(),
        onBeforeRouteTarget: (target) async {
          expect(target.kind, NotificationRouteTargetKind.group);
          expect(target.groupId, groupId);
          expect(target.messageId, messageId);
        },
        onRouteTarget: (target) async {
          final group = await groupRepo.getGroup(target.groupId!);
          expect(group, isNotNull);
          navigatorKey.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => GroupConversationWired(
                group: group!,
                groupRepo: groupRepo,
                msgRepo: groupMsgRepo,
                groupMessageListener: groupMessageListener,
                bridge: bridge,
                identityRepo: identityRepo,
                contactRepo: contactRepo,
                p2pService: p2pService,
                mediaAttachmentRepo: mediaAttachmentRepo,
                mediaFileManager: mediaFileManager,
                imageProcessor: imageProcessor,
                groupConversationTracker: groupConversationTracker,
                initialHighlightedMessageId: target.messageId,
              ),
            ),
          );
        },
      );
      await pumpOrbitFrames(tester, count: 12);
      expect(find.byType(GroupConversationWired), findsOneWidget);
      for (var attempt = 0; attempt < 20; attempt++) {
        if (await groupMsgRepo.getUnreadCount(groupId) == 0) break;
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(await groupMsgRepo.getUnreadCount(groupId), 0);
      navigatorKey.currentState!.pop();
      await pumpOrbitFrames(tester, count: 10);
      expect(find.byType(GroupConversationWired), findsNothing);
    }

    await openFromNotification(
      groupId: 'chat-group',
      messageId: 'message-chat-group',
    );

    expect(
      groupSemanticsLabel(tester, 'chat-group'),
      isNot(contains('unread message')),
    );
    expect(
      groupSemanticsLabel(tester, 'announcement-group'),
      contains('1 unread message'),
    );

    await openFromNotification(
      groupId: 'announcement-group',
      messageId: 'message-announcement-group',
    );

    expect(
      groupSemanticsLabel(tester, 'announcement-group'),
      isNot(contains('unread message')),
    );
    expect(
      flowEvents
          .where((event) => event['event'] == 'ORBIT_FL_GROUP_READ_REFRESH')
          .map((event) => event['details'])
          .whereType<Map<String, Object?>>()
          .map((details) => details['groupId']),
      containsAll(<String>['chat-group', 'announcement-group']),
    );
    semantics.dispose();
  });

  testWidgets('inactive group read replays on the next Orbit entry', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    setLargeTestSurface(tester);
    suppressRenderingNoise();
    await seedUnreadGroup(
      id: 'chat-group',
      name: 'Discussion Group',
      type: GroupType.chat,
    );
    final shellController = AppShellController(initialTab: AppShellTab.feed);
    addTearDown(shellController.dispose);

    await tester.pumpWidget(buildOrbit(shellController: shellController));
    await pumpOrbitFrames(tester);
    expect(
      groupSemanticsLabel(tester, 'chat-group'),
      contains('1 unread message'),
    );

    await groupMsgRepo.markAsRead('chat-group');
    await pumpOrbitFrames(tester);
    expect(
      groupSemanticsLabel(tester, 'chat-group'),
      contains('1 unread message'),
    );

    shellController.switchTo(AppShellTab.orbit);
    await pumpOrbitFrames(tester);
    expect(
      groupSemanticsLabel(tester, 'chat-group'),
      isNot(contains('unread message')),
    );
    semantics.dispose();
  });
}
