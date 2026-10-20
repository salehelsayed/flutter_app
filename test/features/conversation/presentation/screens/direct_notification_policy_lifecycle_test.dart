import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/helpers/direct_notification_read_projection_db_helpers.dart';
import 'package:flutter_app/core/media/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/media/private_media_protection_coordinator.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/app_visibility_authority.dart';
import 'package:flutter_app/core/notifications/app_visibility_route_binding.dart';
import 'package:flutter_app/core/notifications/app_visibility_snapshot.dart';
import 'package:flutter_app/core/notifications/conversation_notification_content_kind.dart';
import 'package:flutter_app/core/notifications/direct_notification_presentation_coordinator.dart';
import 'package:flutter_app/core/notifications/direct_notification_read_projector.dart';
import 'package:flutter_app/core/notifications/flutter_notification_service.dart';
import 'package:flutter_app/core/notifications/notification_route_dispatch.dart';
import 'package:flutter_app/core/notifications/notification_route_target.dart';
import 'package:flutter_app/core/notifications/notification_tone_tracker.dart';
import 'package:flutter_app/core/notifications/recent_remote_notification_gate.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/data/repositories/contact_repository_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/presentation/navigation/direct_private_media_route_observer.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/identity/data/repositories/identity_repository_impl.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/ed25519_contact_request_crypto.dart';
import '../../../../shared/fakes/fake_media_file_manager.dart';
import '../../../../shared/fixtures/media_repository_real_db_fixture.dart';
import '../../../contact_request/presentation/support/contact_request_sql_fixture.dart';

const _notificationChannel = MethodChannel(
  'dexterous.com/flutter/local_notifications',
);

void main() {
  testWidgets(
    'DC-023 exact route, unread, card generation and duplicate state survive screen and SQL reopen',
    (tester) async {
      final h = await _open(tester);
      await h.receive(tester, h.bob, 'dc-bob-1', 'Bob first');
      await h.receive(tester, h.cara, 'dc-cara-1', 'Cara first');
      await h.receive(
        tester,
        h.bob,
        'dc-bob-1',
        'Bob first',
        expected: ChatMessageProcessState.duplicate,
      );
      expect(h.native.shows, hasLength(2));
      expect(h.native.cards.keys.toSet(), {2001, 2002});
      expect(
        await tester.runAsync(
          () => h.fixture.messageRepo.getUnreadCountForContact(h.bob.peerId),
        ),
        1,
      );
      expect(
        await tester.runAsync(
          () => h.fixture.messageRepo.getUnreadCountForContact(h.cara.peerId),
        ),
        1,
      );
      await h.remoteOpen(tester, h.bob.peerId);
      expect(
        tester
            .widget<ConversationWired>(find.byType(ConversationWired))
            .contact
            .peerId,
        h.bob.peerId,
      );
      expect(find.text('Bob'), findsWidgets);
      expect(
        await tester.runAsync(
          () => h.fixture.messageRepo.getUnreadCountForContact(h.bob.peerId),
        ),
        0,
      );
      expect(
        await tester.runAsync(
          () => h.fixture.messageRepo.getUnreadCountForContact(h.cara.peerId),
        ),
        1,
      );
      expect(h.native.cards.keys.toSet(), {2002});
      expect(h.tracker.isViewing(h.bob.peerId), isTrue);
      await h.receive(tester, h.bob, 'dc-bob-2', 'Bob while viewed');
      expect(h.native.shows, hasLength(2));
      expect(
        await tester.runAsync(
          () => h.fixture.messageRepo.getUnreadCountForContact(h.bob.peerId),
        ),
        0,
      );
      await h.receive(tester, h.cara, 'dc-cara-2', 'Cara second');
      expect(h.native.shows, hasLength(3));
      expect(h.native.cards.keys.toSet(), {2002});
      expect(
        await tester.runAsync(
          () => h.fixture.messageRepo.getUnreadCountForContact(h.cara.peerId),
        ),
        2,
      );
      await tester.runAsync(() async {
        h.navigator.currentState!.pop();
      });
      await _frames(tester);
      await tester.runAsync(h.routes.settle);
      expect(h.tracker.activePeerId, isNull);
      await h.receive(tester, h.bob, 'dc-bob-3', 'Bob after leaving');
      expect(h.native.cards.keys.toSet(), {2001, 2002});
      expect(h.native.shows, hasLength(4));
      await h.localOpen(tester, 2001);
      expect(
        tester
            .widget<ConversationWired>(find.byType(ConversationWired))
            .contact
            .peerId,
        h.bob.peerId,
      );
      expect(
        await tester.runAsync(
          () => h.fixture.messageRepo.getUnreadCountForContact(h.bob.peerId),
        ),
        0,
      );
      expect(h.native.cards.keys.toSet(), {2002});
      await tester.runAsync(() => tester.pumpWidget(const SizedBox.shrink()));
      await _frames(tester);
      await tester.runAsync(() async {
        h.chat.dispose();
        h.fixture = await h.fixture.reopen();
        h.bindRepositories();
        await h.gate.clear();
      });
      await h.mount(tester);
      await h.receive(
        tester,
        h.bob,
        'dc-bob-1',
        'Bob first',
        expected: ChatMessageProcessState.duplicate,
      );
      expect(
        await tester.runAsync(
          () => h.fixture.messageRepo.getUnreadCountForContact(h.bob.peerId),
        ),
        0,
      );
      expect(
        await tester.runAsync(
          () => h.fixture.messageRepo.getUnreadCountForContact(h.cara.peerId),
        ),
        2,
      );
      expect(h.native.cards.keys.toSet(), {2002});
      expect(h.native.shows, hasLength(4));
    },
    timeout: const Timeout(Duration(seconds: 60)),
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'DC-023 forced-silent recovery cannot bypass a blocked Messages channel',
    (tester) async {
      final h = await _open(tester);
      h.native.primaryBlocked = true;
      await h.receive(
        tester,
        h.bob,
        'dc-muted-1',
        'Stored while channel blocked',
        forceSilent: true,
      );
      expect(
        await tester.runAsync(
          () => h.fixture.messageRepo.getUnreadCountForContact(h.bob.peerId),
        ),
        1,
      );
      expect(h.native.shows, hasLength(1));
      expect(
        (h.native.shows.single['platformSpecifics'] as Map)['channelId'],
        'mknoon_messages',
      );
      // The OS blocking itself is outside this test; the real Dart policy must not route around it.
    },
    timeout: const Timeout(Duration(seconds: 60)),
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'DC-023 encrypted private media persists but notification preview is generic',
    (tester) async {
      final h = await _open(tester);
      const hash =
          'dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd';
      final inner = <String, Object?>{
        'id': 'dc-private-1',
        'text': '',
        'senderPeerId': h.bob.peerId,
        'senderUsername': 'Bob',
        'timestamp': '2026-10-20T08:00:00.000Z',
        'dedupKey': 'dc-private-1',
        'privateMedia': {'version': 1, 'mode': 'protected'},
        'media': [
          <String, Object?>{
            'id': 'dc-private-blob-1',
            'mime': 'image/jpeg',
            'size': 13,
            'mediaType': 'image',
            'contentHash': hash,
            'encryptionKeyBase64': 'key-fixture-private',
            'encryptionNonce': 'nonce-fixture-private',
            'encryptionScheme': kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            'blobCustody': DirectMediaBlobCustodyCommitment(
              contentHash: hash,
              ciphertextSize: 41,
              expiresAtMs: DateTime.now().millisecondsSinceEpoch + 3600000,
            ).toJson(),
          },
        ],
      };
      await tester.runAsync(
        () => h.chat.processIncomingMessage(
          ChatMessage(
            from: h.bob.peerId,
            to: h.local.peerId,
            isIncoming: true,
            timestamp: '2026-10-20T08:00:00.000Z',
            content: jsonEncode({
              'type': 'chat_message',
              'version': '2',
              'id': 'dc-private-1',
              'senderPeerId': h.bob.peerId,
              'encrypted': {
                'kem': 'native-kem',
                'ciphertext': 'native-ciphertext',
                'nonce': 'native-nonce',
              },
            }),
            // Existing authenticated native predecrypt-prefetch boundary; admission, SQL and notification code remain real.
            predecryptedText: jsonEncode(inner),
          ),
        ),
      );
      await _frames(tester);
      final stored = await tester.runAsync(
        () => h.fixture.messageRepo.getMessage('dc-private-1'),
      );
      expect(stored?.privateMediaPolicy.mode, PrivateMediaMode.protected);
      expect(stored?.privateMediaState, PrivateMediaLifecycleState.available);
      expect(
        await tester.runAsync(
          () => h.fixture.messageRepo.getUnreadCountForContact(h.bob.peerId),
        ),
        1,
      );
      expect(h.native.shows, hasLength(1));
      expect(h.native.shows.single['body'], 'Private media');
      final encoded = jsonEncode(h.native.shows.single);
      expect(encoded, isNot(contains('key-fixture-private')));
      expect(encoded, isNot(contains(hash)));
      expect(encoded, isNot(contains('native-ciphertext')));
    },
    timeout: const Timeout(Duration(seconds: 60)),
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}

// Keep widget callbacks in the repositories' real async zone while advancing
// animation frames with the binding's virtual clock. Read barriers below join SQL.
Future<void> _frames(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.runAsync(() => tester.pump(const Duration(milliseconds: 100)));
  }
}

Future<_Notifications> _open(WidgetTester tester) async {
  final previousFlow = flowEventLoggingEnabled;
  flowEventLoggingEnabled = false;
  addTearDown(() {
    flowEventLoggingEnabled = previousFlow;
  });
  AndroidFlutterLocalNotificationsPlugin.registerWith();
  final previousLifecycle = tester.binding.lifecycleState;
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  addTearDown(() {
    if (previousLifecycle != null) {
      tester.binding.handleAppLifecycleStateChanged(previousLifecycle);
    }
  });
  tester.view.physicalSize = const Size(1440, 2960);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final dir = (await tester.runAsync(
    () => Directory.systemTemp.createTemp('astra-dc023-'),
  ))!;
  addTearDown(() => dir.delete(recursive: true));
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(
    const MethodChannel('plugins.flutter.io/path_provider'),
    (_) async => dir.path,
  );
  addTearDown(
    () => messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      null,
    ),
  );
  final h = (await tester.runAsync(() async => _Notifications(dir)))!;
  messenger.setMockMessageHandler(
    kPrivateMediaProtectionEventChannel,
    (_) async => const StandardMethodCodec().encodeSuccessEnvelope(null),
  );
  addTearDown(
    () => messenger.setMockMessageHandler(
      kPrivateMediaProtectionEventChannel,
      null,
    ),
  );
  messenger.setMockMethodCallHandler(_notificationChannel, h.native.handle);
  addTearDown(
    () => messenger.setMockMethodCallHandler(_notificationChannel, null),
  );
  addTearDown(() => h.close(tester));
  await tester.runAsync(h.initialize);
  await h.mount(tester);
  return h;
}

class _Notifications {
  _Notifications(this.directory) {
    authority = AppVisibilityAuthority(platformBridge: visibility);
    routes = AppVisibilityRouteRegistry(authority: authority);
    notifications = FlutterNotificationService(
      requestApplePermissions: false,
      notificationIdResolver: (key) async => idFor(key),
      notificationIdLookup: (key) async => idFor(key),
      notificationContentRegistryResolver: () async => content,
      notificationGenerationFactory: () =>
          'fixture-generation-${(++generation).toString().padLeft(8, '0')}',
    );
    readProjector = DirectNotificationReadProjector(
      coordinator: DirectNotificationPresentationCoordinator(),
      cancellation: notifications,
      commitRead: (peerId, metadata) =>
          dbMarkDirectConversationReadAndAcknowledge(
            fixture.db,
            peerId: peerId,
            metadata: metadata,
          ),
    );
    notifications.onNotificationTap = (payload) {
      unawaited(
        routeNotificationPayload(payload: payload, onRouteTarget: route),
      );
    };
  }
  final Directory directory;
  final local = TestEd25519Identity.fromSeedByte(0x61);
  final bob = TestEd25519Identity.fromSeedByte(0x62);
  final cara = TestEd25519Identity.fromSeedByte(0x63);
  final native = _NativeNotifications();
  final content = _ContentStorage();
  final visibility = _NativeVisibility();
  final observer = AppVisibilityRouteObserver();
  final tracker = ActiveConversationTracker();
  final navigator = GlobalKey<NavigatorState>();
  final network = FakeP2PService();
  late final AppVisibilityAuthority authority;
  late final AppVisibilityRouteRegistry routes;
  late final FlutterNotificationService notifications;
  late final DirectNotificationReadProjector readProjector;
  MediaRepositoryRealDbFixture? _fixture;
  MediaRepositoryRealDbFixture get fixture => _fixture!;
  set fixture(MediaRepositoryRealDbFixture value) => _fixture = value;
  late ContactRepositoryImpl contacts;
  late IdentityRepositoryImpl identities;
  ChatMessageListener? _chat;
  ChatMessageListener get chat => _chat!;
  late final gate = RecentRemoteNotificationGate(
    filePath: '${directory.path}/remote-gate.json',
  );
  var generation = 0;
  Completer<void>? routed;
  Completer<void>? readCommitted;
  String? expectedReadPeer;

  int idFor(String key) {
    if (key == bob.peerId) return 2001;
    if (key == cara.peerId) return 2002;
    throw StateError('unexpected conversation identity');
  }

  Future<void> initialize() async {
    fixture = await MediaRepositoryRealDbFixture.create(
      databasePath: '${directory.path}/messages.db',
      databaseFactoryOverride: databaseFactoryFfiNoIsolate,
      projectConversationRead: (peer) async {
        final count = await readProjector.markConversationRead(peer);
        if (readCommitted case final pending?
            when peer == expectedReadPeer && !pending.isCompleted) {
          pending.complete();
        }
        return count;
      },
    );
    bindRepositories();
    await identities.saveIdentity(
      testIdentityModel(
        local,
        username: 'Alice',
        mlKemPublicKey: 'fixture-local-mlkem',
      ),
    );
    for (final item in [(bob, 'Bob'), (cara, 'Cara')]) {
      await contacts.addContact(
        ContactModel(
          peerId: item.$1.peerId,
          publicKey: item.$1.publicKey,
          rendezvous: '/dns4/fixture.invalid/tcp/443',
          username: item.$2,
          signature: 'fixture-contact',
          scannedAt: '2026-01-01T00:00:00.000Z',
        ),
      );
    }
    await notifications.initialize();
    expect(await authority.synchronize(), isTrue);
  }

  void bindRepositories() {
    contacts = buildWidgetContactRepository(fixture.db);
    identities = buildWidgetIdentityRepository(
      fixture.db,
      fixture.secureKeyStore,
    );
    _chat = ChatMessageListener(
      chatMessageStream: const Stream<ChatMessage>.empty(),
      messageRepo: fixture.messageRepo,
      contactRepo: contacts,
      mediaAttachmentRepo: fixture.repo,
      notificationService: notifications,
      appVisibility: authority,
      remoteNotificationGate: gate,
      notificationToneTracker: NotificationToneTracker(),
      backgroundNotificationDuplicateGuardDelay: Duration.zero,
      durableNotificationCoordinatorResolver: () =>
          Future.error(UnsupportedError('native durable coordinator boundary')),
      downloadProfilePictureFn:
          ({
            required bridge,
            required contactRepo,
            required ownerPeerId,
            required avatarVersion,
          }) async => null,
    );
  }

  Future<void> receive(
    WidgetTester tester,
    TestEd25519Identity sender,
    String id,
    String text, {
    bool forceSilent = false,
    ChatMessageProcessState expected = ChatMessageProcessState.stored,
  }) async {
    final outcome = await tester.runAsync(
      () => chat.processIncomingMessage(
        ChatMessage(
          from: sender.peerId,
          to: local.peerId,
          content: jsonEncode({
            'type': 'chat_message',
            'version': '1',
            'payload': {
              'id': id,
              'text': text,
              'senderPeerId': sender.peerId,
              'senderUsername': sender.peerId == bob.peerId ? 'Bob' : 'Cara',
              'timestamp': '2026-10-20T08:00:00.000Z',
            },
          }),
          timestamp: '2026-10-20T08:00:00.000Z',
          isIncoming: true,
        ),
        forceSilentNotification: forceSilent,
      ),
    );
    expect(outcome?.state, expected, reason: outcome?.reasonDetail);
    if (expected == ChatMessageProcessState.duplicate) {
      expect(outcome?.duplicatePriorPersisted, isTrue);
    }
    await _frames(tester);
  }

  Future<void> mount(WidgetTester tester) async {
    await tester.runAsync(
      () => tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigator,
          navigatorObservers: [observer],
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => DirectPrivateMediaRouteObserverScope(
            observer: observer,
            appVisibilityRouteRegistry: routes,
            child: child!,
          ),
          home: const Scaffold(body: Text('Inbox')),
        ),
      ),
    );
    await _frames(tester);
  }

  Future<void> route(NotificationRouteTarget target) async {
    expect(target.kind, NotificationRouteTargetKind.conversation);
    final contact = await contacts.getContact(target.peerId!);
    expect(contact, isNotNull);
    unawaited(
      navigator.currentState!.push<void>(
        MaterialPageRoute(
          builder: (_) => ConversationWired(
            contact: contact!,
            identityRepo: identities,
            messageRepo: fixture.messageRepo,
            chatMessageListener: chat,
            p2pService: network,
            contactRepo: contacts,
            mediaAttachmentRepo: fixture.repo,
            mediaFileManager: FakeMediaFileManager(),
            conversationTracker: tracker,
          ),
        ),
      ),
    );
    final pending = routed;
    routed = null;
    if (pending != null && !pending.isCompleted) pending.complete();
  }

  Future<void> remoteOpen(WidgetTester tester, String peer) async {
    await tester.runAsync(() async {
      readCommitted = Completer<void>();
      expectedReadPeer = peer;
    });
    await tester.runAsync(
      () => routeRemoteNotificationOpen(
        data: {'type': 'new_message', 'sender_id': peer},
        onRouteTarget: route,
        onMissingRouteTarget: () async => fail('missing direct target'),
      ),
    );
    await _frames(tester);
    await tester.runAsync(routes.settle);
    await tester.runAsync(() => readCommitted!.future);
  }

  Future<void> localOpen(WidgetTester tester, int id) async {
    final payload = native.cards[id]!['payload'] as String;
    await tester.runAsync(() async {
      routed = Completer<void>();
      readCommitted = Completer<void>();
      expectedReadPeer = NotificationRouteTarget.fromPayload(
        decodeConversationNotificationPayload(payload)?.routePayload ?? payload,
      )!.peerId;
      final completion = routed!.future;
      await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .handlePlatformMessage(
            _notificationChannel.name,
            const StandardMethodCodec().encodeMethodCall(
              MethodCall('didReceiveNotificationResponse', {
                'notificationId': id,
                'actionId': null,
                'input': null,
                'notificationResponseType':
                    NotificationResponseType.selectedNotification.index,
                'payload': payload,
              }),
            ),
            (_) {},
          );
      await completion;
    });
    await _frames(tester);
    await tester.runAsync(routes.settle);
    await tester.runAsync(() => readCommitted!.future);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.runAsync(() => tester.pumpWidget(const SizedBox.shrink()));
    await _frames(tester);
    routes.dispose();
    await tester.runAsync(() => tester.pump());
    await tester.runAsync(routes.settle);
    await tester.runAsync(() async {
      _chat?.dispose();
      authority.dispose();
      notifications.onNotificationTap = null;
      network.dispose();
      await _fixture?.dispose();
      await gate.clear();
    });
  }
}

// Registry storage and native API responses only; duplicate/read/privacy decisions above stay in production code.
class _ContentStorage implements ConversationNotificationContentRegistry {
  final entries =
      <({String peer, int id}), ConversationNotificationContentMetadata>{};
  @override
  Future<ConversationNotificationContentReplacementResult> replaceContent({
    required String conversationKey,
    required int notificationId,
    required ConversationNotificationContentMetadata metadata,
    required Future<void> Function() replace,
  }) async {
    await replace();
    entries[(peer: conversationKey, id: notificationId)] = metadata;
    return ConversationNotificationContentReplacementResult.shownAndRecorded;
  }

  @override
  Future<ConversationNotificationContentMetadata?> lookupContentMetadata({
    required String conversationKey,
    required int notificationId,
  }) async => entries[(peer: conversationKey, id: notificationId)];
  @override
  Future<bool> cancelContentIfGeneration({
    required String conversationKey,
    required int notificationId,
    required String generation,
    required Future<void> Function() cancel,
  }) async {
    final key = (peer: conversationKey, id: notificationId);
    if (entries[key]?.generation != generation) return false;
    await cancel();
    entries.remove(key);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnsupportedError(
    'unexercised storage boundary ${invocation.memberName}',
  );
}

class _NativeNotifications {
  final shows = <Map<dynamic, dynamic>>[];
  final cards = <int, Map<dynamic, dynamic>>{};
  bool primaryBlocked = false;
  Future<Object?> handle(MethodCall call) async {
    switch (call.method) {
      case 'initialize':
        return true;
      case 'getNotificationAppLaunchDetails':
        return {'notificationLaunchedApp': false};
      case 'getNotificationChannels':
        return primaryBlocked
            ? [
                _channel('mknoon_messages', 0),
                _channel('mknoon_messages_silent', 2),
              ]
            : null;
      case 'getActiveNotifications':
        return [];
      case 'show':
        final args = Map<dynamic, dynamic>.from(call.arguments as Map);
        shows.add(args);
        cards[args['id'] as int] = args;
        return null;
      case 'cancel':
        final args = call.arguments;
        cards.remove(args is int ? args : (args as Map)['id']);
        return null;
      default:
        return null;
    }
  }

  Map<String, Object?> _channel(String id, int importance) => {
    'id': id,
    'name': id,
    'description': null,
    'groupId': null,
    'showBadge': true,
    'importance': importance,
    'playSound': true,
    'soundSource': null,
    'enableLights': false,
    'enableVibration': true,
    'vibrationPattern': null,
    'ledColor': 0,
    'audioAttributesUsage': 5,
  };
}

class _NativeVisibility implements AppVisibilityPlatformBridge {
  AppVisibilitySnapshotV1 snapshot = const AppVisibilitySnapshotV1(
    schemaVersion: appVisibilitySnapshotSchemaVersion,
    revision: 1,
    lifecycleGeneration: 1,
    lifecycle: AppVisibilityLifecycle.foregroundActive,
    visibleConversationDigest: null,
    updatedMonotonicMs: 1000,
    bootSession: 'test:boot-1',
  );
  @override
  Future<AppVisibilityPlatformRead?> readSnapshot() async =>
      AppVisibilityPlatformRead(
        snapshot: snapshot,
        currentMonotonicMs: 1000,
        currentBootSession: 'test:boot-1',
      );
  @override
  Future<AppVisibilityPlatformWrite?> publishVisibleConversation({
    required String? visibleConversationDigest,
    required int lifecycleGeneration,
  }) async {
    final current = lifecycleGeneration == snapshot.lifecycleGeneration;
    if (current) {
      snapshot = AppVisibilitySnapshotV1(
        schemaVersion: appVisibilitySnapshotSchemaVersion,
        revision: snapshot.revision + 1,
        lifecycleGeneration: lifecycleGeneration,
        lifecycle: AppVisibilityLifecycle.foregroundActive,
        visibleConversationDigest: visibleConversationDigest,
        updatedMonotonicMs: 1000,
        bootSession: 'test:boot-1',
      );
    }
    return AppVisibilityPlatformWrite(
      committed: current,
      snapshot: snapshot,
      currentMonotonicMs: 1000,
      currentBootSession: 'test:boot-1',
    );
  }
}
