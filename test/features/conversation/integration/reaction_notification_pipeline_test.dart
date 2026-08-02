import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/app_root_notification_open.dart';
import 'package:flutter_app/core/notifications/deterministic_notification_id.dart';
import 'package:flutter_app/core/notifications/flutter_notification_service.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/handle_incoming_reaction_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_payload.dart';
import 'package:flutter_app/features/conversation/presentation/navigation/conversation_route_transition.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_wired.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/unread_orbit_indicator.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/push/application/prepare_notification_route_target_use_case.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_feed_cleared_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';
import '../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '../../contact_request/domain/repositories/fake_contact_request_repository.dart';
import '../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';
import '../domain/repositories/fake_message_repository.dart';
import '../domain/repositories/fake_reaction_repository.dart';

const _actorPeerId = '12D3KooWActor';
const _localPeerId = '12D3KooWRecipient';
const _targetMessageId = 'target-message-1';
const _pluginChannel = MethodChannel(
  'dexterous.com/flutter/local_notifications',
);
const _pathProviderChannel = MethodChannel('plugins.flutter.io/path_provider');

FlutterNotificationService _buildNotificationService() {
  return FlutterNotificationService(
    notificationIdResolver: (conversationKey) async =>
        deterministicConversationNotificationId(conversationKey),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final pluginCalls = <MethodCall>[];

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    AndroidFlutterLocalNotificationsPlugin.registerWith();
    pluginCalls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pluginChannel, (call) async {
          pluginCalls.add(call);
          if (call.method == 'initialize') return true;
          if (call.method == 'getNotificationAppLaunchDetails') {
            return <String, Object?>{'notificationLaunchedApp': false};
          }
          return null;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, (call) async {
          if (call.method == 'getApplicationDocumentsDirectory') {
            return '/tmp/reaction-notification-pipeline';
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pluginChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'live ADD to locally authored target preserves actor body route and stable conversation id through plugin',
    () async {
      final fixture = await _PipelineFixture.create(pluginCalls);

      final (result, change) = await fixture.deliverReaction();
      await _waitForPluginShow(pluginCalls);

      expect(result, HandleReactionResult.success);
      expect(change?.type, ReactionChangeType.upserted);
      final show = pluginCalls.singleWhere((call) => call.method == 'show');
      final args = show.arguments as Map;
      expect(args['title'], 'Sender');
      expect(args['body'], 'Reacted 👍 to your message');
      expect(args['payload'], _actorPeerId);
      expect(args['id'], deterministicConversationNotificationId(_actorPeerId));
      expect(fixture.reactions.reactions, hasLength(1));
    },
  );

  testWidgets('reaction activity never increments unread-message orbit state', (
    tester,
  ) async {
    try {
      _setLargeTestSurface(tester);
      _suppressExpectedWidgetHarnessErrors();

      final zeroUnread = await _MountedPipelineFixture.create(
        pluginCalls,
        genuineUnreadCount: 0,
      );
      await tester.pumpWidget(zeroUnread.buildMountedOrbit());
      await _pumpBoundedFrames(tester, count: 8);
      expect(find.byType(OrbitWired), findsOneWidget);
      expect(find.byType(UnreadOrbitIndicator), findsNothing);

      pluginCalls.clear();
      final (zeroResult, zeroChange) = await zeroUnread.deliverReaction();
      await _pumpBoundedFrames(tester, count: 4);

      expect(zeroResult, HandleReactionResult.success);
      expect(zeroChange?.type, ReactionChangeType.upserted);
      expect(await zeroUnread.messages.getTotalUnreadCount(), 0);
      expect(zeroUnread.messages.count, 1);
      expect(zeroUnread.reactions.reactions, hasLength(1));
      expect(find.byType(UnreadOrbitIndicator), findsNothing);
      expect(pluginCalls.where((call) => call.method == 'show'), hasLength(1));

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      zeroUnread.dispose();

      final twoUnread = await _MountedPipelineFixture.create(
        pluginCalls,
        genuineUnreadCount: 2,
      );
      addTearDown(twoUnread.dispose);
      await tester.pumpWidget(twoUnread.buildMountedOrbit());
      await _pumpBoundedFrames(tester, count: 8);

      expect(await twoUnread.messages.getTotalUnreadCount(), 2);
      expect(find.byType(UnreadOrbitIndicator), findsOneWidget);
      expect(_satelliteCount(), 2);
      expect(
        find.bySemanticsLabel('Open chat with Sender, 2 unread messages'),
        findsOneWidget,
      );

      pluginCalls.clear();
      final (twoResult, twoChange) = await twoUnread.deliverReaction();
      await _pumpBoundedFrames(tester, count: 4);

      expect(twoResult, HandleReactionResult.success);
      expect(twoChange?.type, ReactionChangeType.upserted);
      expect(await twoUnread.messages.getTotalUnreadCount(), 2);
      expect(twoUnread.messages.count, 3);
      expect(twoUnread.reactions.reactions, hasLength(1));
      expect(find.byType(UnreadOrbitIndicator), findsOneWidget);
      expect(_satelliteCount(), 2);
      expect(
        find.bySemanticsLabel('Open chat with Sender, 2 unread messages'),
        findsOneWidget,
      );

      final show = pluginCalls.singleWhere((call) => call.method == 'show');
      final payload = (show.arguments as Map)['payload'] as String;
      await twoUnread.notifications.clearDeliveredNotifications();
      await _pumpBoundedFrames(tester, count: 2);
      expect(
        await twoUnread.messages.getTotalUnreadCount(),
        2,
        reason: 'displaying or dismissing the reaction card cannot mark reads',
      );
      expect(twoUnread.messages.count, 3);
      expect(_satelliteCount(), 2);

      // Exercise the production app-root payload dispatcher and preparation
      // use case. The route callback can only push the real ConversationWired;
      // it has no repository read/mutation shortcut.
      final routeFuture = routeAppRootLocalNotificationTap(
        payload: payload,
        onBeforeOpen: twoUnread.notifications.clearDeliveredNotifications,
        onBeforeRouteTarget: twoUnread.prepareNotificationRoute,
        onRouteTarget: twoUnread.openNotificationRoute,
      );
      await _pumpBoundedFrames(tester, count: 8);

      expect(find.byType(ConversationWired), findsOneWidget);
      expect(twoUnread.p2pService.drainOfflineInboxCallCount, greaterThan(0));
      expect(
        await twoUnread.messages.getTotalUnreadCount(),
        0,
        reason:
            'only the mounted ConversationWired normal read commit may clear '
            'the genuine unread messages',
      );

      twoUnread.navigatorKey.currentState!.pop();
      await _pumpBoundedFrames(tester, count: 8);
      await routeFuture;

      expect(find.byType(OrbitWired), findsOneWidget);
      expect(find.byType(UnreadOrbitIndicator), findsNothing);
      expect(_satelliteCount(), 0);
      expect(
        find.bySemanticsLabel('Open chat with Sender, 2 unread messages'),
        findsNothing,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void _setLargeTestSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(1290, 2796);
  tester.view.devicePixelRatio = 3;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

void _suppressExpectedWidgetHarnessErrors() {
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

Future<void> _pumpBoundedFrames(
  WidgetTester tester, {
  required int count,
}) async {
  for (var index = 0; index < count; index++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _waitForPluginShow(List<MethodCall> calls) async {
  for (var attempt = 0; attempt < 200; attempt++) {
    if (calls.any((call) => call.method == 'show')) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

int _satelliteCount() => find
    .byWidgetPredicate((widget) {
      final key = widget.key;
      return key is ValueKey<String> &&
          key.value.startsWith('unread-satellite-');
    })
    .evaluate()
    .length;

class _MountedPipelineFixture {
  final FakeBridge bridge;
  final FakeIdentityRepository identity;
  final FakeContactRepository contacts;
  final FakeContactRequestRepository contactRequests;
  final InMemoryMessageRepository messages;
  final FakeReactionRepository reactions;
  final FlutterNotificationService notifications;
  final FakeP2PService p2pService;
  final FakeSecureKeyStore secureKeyStore;
  final InMemoryMediaAttachmentRepository mediaAttachments;
  final FakeMediaFileManager mediaFileManager;
  final InMemoryGroupRepository groups;
  final InMemoryGroupMessageRepository groupMessages;
  final InMemoryPostsPrivacySettingsRepository postsPrivacySettings;
  final InMemoryFeedClearedRepository feedCleared;
  final ImageProcessor imageProcessor;
  final ChatMessageListener chatMessageListener;
  final ContactRequestListener contactRequestListener;
  final ActiveConversationTracker conversationTracker;
  final GlobalKey<NavigatorState> navigatorKey;

  var _disposed = false;

  _MountedPipelineFixture({
    required this.bridge,
    required this.identity,
    required this.contacts,
    required this.contactRequests,
    required this.messages,
    required this.reactions,
    required this.notifications,
    required this.p2pService,
    required this.secureKeyStore,
    required this.mediaAttachments,
    required this.mediaFileManager,
    required this.groups,
    required this.groupMessages,
    required this.postsPrivacySettings,
    required this.feedCleared,
    required this.imageProcessor,
    required this.chatMessageListener,
    required this.contactRequestListener,
    required this.conversationTracker,
    required this.navigatorKey,
  });

  static Future<_MountedPipelineFixture> create(
    List<MethodCall> pluginCalls, {
    required int genuineUnreadCount,
  }) async {
    final bridge = FakeBridge(
      initialResponses: {
        'message.decrypt': {
          'ok': true,
          'plaintext': jsonEncode({
            'id': 'reaction-event-1',
            'messageId': _targetMessageId,
            'emoji': '👍',
            'action': 'add',
            'senderPeerId': _actorPeerId,
            'timestamp': '2026-07-12T08:00:00.000Z',
          }),
        },
      },
    );
    final identity = FakeIdentityRepository()
      ..seed(
        IdentityModel(
          peerId: _localPeerId,
          publicKey: 'recipient-public-key',
          privateKey: 'recipient-private-key',
          mnemonic12:
              'one two three four five six seven eight nine ten eleven twelve',
          mlKemPublicKey: 'recipient-ml-kem-public-key',
          username: 'Recipient',
          createdAt: '2026-07-12T07:00:00.000Z',
          updatedAt: '2026-07-12T07:00:00.000Z',
        ),
      );
    final contacts = FakeContactRepository()
      ..seed([
        const ContactModel(
          peerId: _actorPeerId,
          publicKey: 'actor-public-key',
          rendezvous: '/relay',
          username: 'Sender',
          signature: 'signature',
          scannedAt: '2026-07-12T07:00:00.000Z',
          mlKemPublicKey: 'actor-ml-kem-public-key',
        ),
      ]);
    final messages = InMemoryMessageRepository();
    await messages.saveMessage(
      const ConversationMessage(
        id: _targetMessageId,
        contactPeerId: _actorPeerId,
        senderPeerId: _localPeerId,
        text: 'locally authored target',
        timestamp: '2026-07-12T07:30:00.000Z',
        status: 'delivered',
        isIncoming: false,
        createdAt: '2026-07-12T07:30:00.000Z',
      ),
    );
    for (var index = 0; index < genuineUnreadCount; index++) {
      await messages.saveMessage(
        ConversationMessage(
          id: 'unread-$index',
          contactPeerId: _actorPeerId,
          senderPeerId: _actorPeerId,
          text: 'genuine unread $index',
          timestamp: '2026-07-12T07:4$index:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-07-12T07:4$index:00.000Z',
        ),
      );
    }

    final contactRequests = FakeContactRequestRepository();
    final reactions = FakeReactionRepository();
    final p2pService = FakeP2PService();
    final mediaAttachments = InMemoryMediaAttachmentRepository();
    final chatMessageListener = ChatMessageListener(
      chatMessageStream: const Stream<ChatMessage>.empty(),
      messageRepo: messages,
      contactRepo: contacts,
    );
    final contactRequestListener = ContactRequestListener(
      contactRequestStream: const Stream<ChatMessage>.empty(),
      requestRepo: contactRequests,
      contactRepo: contacts,
      bridge: bridge,
      getOwnPeerId: () => _localPeerId,
    );
    final notifications = _buildNotificationService();
    await notifications.initialize();
    pluginCalls.clear();

    return _MountedPipelineFixture(
      bridge: bridge,
      identity: identity,
      contacts: contacts,
      contactRequests: contactRequests,
      messages: messages,
      reactions: reactions,
      notifications: notifications,
      p2pService: p2pService,
      secureKeyStore: FakeSecureKeyStore(),
      mediaAttachments: mediaAttachments,
      mediaFileManager: FakeMediaFileManager(),
      groups: InMemoryGroupRepository(),
      groupMessages: InMemoryGroupMessageRepository(),
      postsPrivacySettings: InMemoryPostsPrivacySettingsRepository(),
      feedCleared: InMemoryFeedClearedRepository(),
      imageProcessor: ImageProcessor(
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
      ),
      chatMessageListener: chatMessageListener,
      contactRequestListener: contactRequestListener,
      conversationTracker: ActiveConversationTracker(),
      navigatorKey: GlobalKey<NavigatorState>(),
    );
  }

  Widget buildMountedOrbit() {
    return MaterialApp(
      navigatorKey: navigatorKey,
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: OrbitWired(
        identityRepo: identity,
        contactRepo: contacts,
        contactRequestRepo: contactRequests,
        contactRequestListener: contactRequestListener,
        messageRepo: messages,
        mediaAttachmentRepo: mediaAttachments,
        chatMessageListener: chatMessageListener,
        bridge: bridge,
        p2pService: p2pService,
        mediaFileManager: mediaFileManager,
        secureKeyStore: secureKeyStore,
        imageProcessor: imageProcessor,
        feedClearedRepository: feedCleared,
        conversationTracker: conversationTracker,
        reactionRepository: reactions,
        groupRepository: groups,
        groupMessageRepository: groupMessages,
        postsPrivacySettingsRepository: postsPrivacySettings,
      ),
    );
  }

  Future<(HandleReactionResult, ReactionChange?)> deliverReaction() {
    final envelope = ReactionPayload.buildEncryptedEnvelope(
      senderPeerId: _actorPeerId,
      eventId: 'reaction-event-1',
      action: ReactionPayload.addAction,
      targetMessageId: _targetMessageId,
      kem: 'kem',
      ciphertext: 'ciphertext',
      nonce: 'nonce',
    );
    return handleIncomingReaction(
      message: ChatMessage(
        from: _actorPeerId,
        to: _localPeerId,
        content: envelope,
        timestamp: '2026-07-12T08:00:00.000Z',
        isIncoming: true,
        transport: 'direct',
      ),
      messageRepo: messages,
      reactionRepo: reactions,
      contactRepo: contacts,
      bridge: bridge,
      ownMlKemSecretKey: 'recipient-secret-key',
      notificationService: notifications,
      conversationTracker: conversationTracker,
      getAppLifecycleState: () => AppLifecycleState.resumed,
    );
  }

  Future<void> prepareNotificationRoute(NotificationRouteTarget target) {
    return prepareNotificationRouteTarget(
      routeTarget: target,
      drainOfflineInbox: p2pService.drainOfflineInbox,
      bridge: bridge,
      groupRepository: groups,
      groupMessageRepository: groupMessages,
      mediaAttachmentRepository: mediaAttachments,
      reactionRepository: reactions,
      groupPendingReactionRepository: null,
      selfPeerId: _localPeerId,
      warmPeer: p2pService.warmPeer,
    );
  }

  Future<void> openNotificationRoute(NotificationRouteTarget target) async {
    expectSync(target.kind, NotificationRouteTargetKind.conversation);
    expectSync(target.peerId, _actorPeerId);
    final contact = await contacts.getContact(target.peerId!);
    expectSync(contact, isNotNull);
    // Mirrors the app-root conversation branch at the only public boundary:
    // navigation mounts production ConversationWired, whose own initial-load
    // path performs markConversationRead and emits the Orbit refresh event.
    await navigatorKey.currentState!.push(
      buildConversationRoute(
        builder: (_) => ConversationWired(
          contact: contact!,
          identityRepo: identity,
          messageRepo: messages,
          chatMessageListener: chatMessageListener,
          p2pService: p2pService,
          bridge: bridge,
          contactRepo: contacts,
          mediaAttachmentRepo: mediaAttachments,
          mediaFileManager: mediaFileManager,
          imageProcessor: imageProcessor,
          conversationTracker: conversationTracker,
          reactionRepo: reactions,
          notificationTappedAt: DateTime.now(),
        ),
      ),
    );
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    contactRequestListener.dispose();
    chatMessageListener.dispose();
    notifications.dispose();
    postsPrivacySettings.dispose();
    p2pService.dispose();
    bridge.dispose();
  }
}

class _PipelineFixture {
  final FakeBridge bridge;
  final FakeContactRepository contacts;
  final FakeMessageRepository messages;
  final FakeReactionRepository reactions;
  final FlutterNotificationService notifications;

  _PipelineFixture({
    required this.bridge,
    required this.contacts,
    required this.messages,
    required this.reactions,
    required this.notifications,
  });

  static Future<_PipelineFixture> create(
    List<MethodCall> pluginCalls, {
    int genuineUnreadCount = 0,
  }) async {
    final bridge = FakeBridge(
      initialResponses: {
        'message.decrypt': {
          'ok': true,
          'plaintext': jsonEncode({
            'id': 'reaction-event-1',
            'messageId': _targetMessageId,
            'emoji': '👍',
            'action': 'add',
            'senderPeerId': _actorPeerId,
            'timestamp': '2026-07-12T08:00:00.000Z',
          }),
        },
      },
    );
    final contacts = FakeContactRepository()
      ..seed([
        const ContactModel(
          peerId: _actorPeerId,
          publicKey: 'actor-public-key',
          rendezvous: '/relay',
          username: 'Sender',
          signature: 'signature',
          scannedAt: '2026-07-12T07:00:00.000Z',
        ),
      ]);
    final seededMessages = <ConversationMessage>[
      const ConversationMessage(
        id: _targetMessageId,
        contactPeerId: _actorPeerId,
        senderPeerId: _localPeerId,
        text: 'locally authored target',
        timestamp: '2026-07-12T07:30:00.000Z',
        status: 'delivered',
        isIncoming: false,
        createdAt: '2026-07-12T07:30:00.000Z',
      ),
      for (var index = 0; index < genuineUnreadCount; index++)
        ConversationMessage(
          id: 'unread-$index',
          contactPeerId: _actorPeerId,
          senderPeerId: _actorPeerId,
          text: 'genuine unread $index',
          timestamp: '2026-07-12T07:4$index:00.000Z',
          status: 'delivered',
          isIncoming: true,
          createdAt: '2026-07-12T07:4$index:00.000Z',
        ),
    ];
    final messages = FakeMessageRepository()..seed(seededMessages);
    final notifications = _buildNotificationService();
    await notifications.initialize();
    // Initialization traffic is not part of the display assertion.
    pluginCalls.removeWhere((call) => call.method != 'show');

    return _PipelineFixture(
      bridge: bridge,
      contacts: contacts,
      messages: messages,
      reactions: FakeReactionRepository(),
      notifications: notifications,
    );
  }

  Future<(HandleReactionResult, ReactionChange?)> deliverReaction() {
    final envelope = ReactionPayload.buildEncryptedEnvelope(
      senderPeerId: _actorPeerId,
      eventId: 'reaction-event-1',
      action: ReactionPayload.addAction,
      targetMessageId: _targetMessageId,
      kem: 'kem',
      ciphertext: 'ciphertext',
      nonce: 'nonce',
    );
    return handleIncomingReaction(
      message: ChatMessage(
        from: _actorPeerId,
        to: _localPeerId,
        content: envelope,
        timestamp: '2026-07-12T08:00:00.000Z',
        isIncoming: true,
        transport: 'direct',
      ),
      messageRepo: messages,
      reactionRepo: reactions,
      contactRepo: contacts,
      bridge: bridge,
      ownMlKemSecretKey: 'recipient-secret-key',
      notificationService: notifications,
      conversationTracker: ActiveConversationTracker(),
      getAppLifecycleState: () => AppLifecycleState.resumed,
    );
  }
}
