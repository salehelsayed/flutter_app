import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_thread_summary.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/conversation_header.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/message_context_overlay.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/feed/domain/models/feed_route_changes.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_navigation_bar.dart';
import 'package:flutter_app/features/feed/presentation/widgets/nav_bar_button.dart';
import 'package:flutter_app/features/groups/application/group_config_payload.dart';
import 'package:flutter_app/features/groups/application/group_invite_listener.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_payload.dart';
import 'package:flutter_app/features/groups/domain/models/group_welcome_key_package.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/domain/models/group_thread_summary.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_reaction_details_sheet.dart';
import 'package:flutter_app/features/groups/presentation/widgets/expandable_fab.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/introduction/application/introduction_listener.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_wired.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_close_button.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_search_trigger.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/friends_filter_toggle.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';

import '../../../../core/bridge/fake_bridge.dart';
import '../../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/fake_media_file_manager.dart';
import '../../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../../shared/fakes/in_memory_group_repository.dart';
import '../../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../../shared/fakes/in_memory_message_repository.dart';
import '../../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '../../../../shared/fakes/in_memory_introduction_repository.dart';
import '../../../../shared/fakes/in_memory_pending_group_invite_repository.dart';
import '../../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../../contact_request/domain/repositories/fake_contact_request_repository.dart';
import '../../../conversation/domain/repositories/fake_reaction_repository.dart';
import '../../../identity/domain/repositories/fake_identity_repository.dart';

Text _textFor(WidgetTester tester, String text) {
  final finder = find.byWidgetPredicate(
    (widget) => widget is Text && widget.data == text,
    description: 'Text("$text")',
  );
  expect(finder, findsOneWidget);
  return tester.widget<Text>(finder);
}

IntroductionModel pendingIntroduction({
  required String ownPeerId,
  required String otherPeerId,
  required String createdAt,
  String id = 'orbit-intro',
}) {
  return IntroductionModel(
    id: id,
    introducerId: 'peer-A',
    recipientId: ownPeerId,
    introducedId: otherPeerId,
    createdAt: createdAt,
    introducerUsername: 'Noor',
    recipientUsername: 'Alice',
    introducedUsername: 'Dora',
  );
}

void main() {
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
  late InMemoryPendingGroupInviteRepository pendingInviteRepo;
  late StreamController<GroupMessage> groupMessageStreamController;
  late StreamController<GroupModel> joinedGroupInviteController;
  late StreamController<PendingGroupInvite> pendingInviteController;
  late InMemoryPostsPrivacySettingsRepository postsPrivacySettingsRepository;

  final testIdentity = IdentityModel(
    peerId: 'test-peer-id-12345',
    publicKey: 'test-public-key',
    privateKey: 'test-private-key',
    mnemonic12: 'w1 w2 w3 w4 w5 w6 w7 w8 w9 w10 w11 w12',
    mlKemPublicKey: 'mlkem-test-peer-id-12345',
    username: 'Alice',
    createdAt: DateTime.now().toUtc().toIso8601String(),
    updatedAt: DateTime.now().toUtc().toIso8601String(),
  );

  final testContact = ContactModel(
    peerId: 'contact-peer-id',
    publicKey: 'contact-pk',
    rendezvous: '/dns4/relay/tcp/443',
    username: 'Bob',
    signature: 'sig',
    scannedAt: DateTime.now().toUtc().toIso8601String(),
    mlKemPublicKey: 'mlkem-contact-peer-id',
  );

  String freshPendingIntroductionCreatedAt() => DateTime.now()
      .toUtc()
      .subtract(const Duration(days: 1))
      .toIso8601String();

  setUp(() {
    identityRepo = FakeIdentityRepository();
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
    pendingInviteRepo = InMemoryPendingGroupInviteRepository();
    groupMessageStreamController = StreamController<GroupMessage>.broadcast();
    joinedGroupInviteController = StreamController<GroupModel>.broadcast();
    pendingInviteController = StreamController<PendingGroupInvite>.broadcast();
    postsPrivacySettingsRepository = InMemoryPostsPrivacySettingsRepository();
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

    // Mock path_provider for getApplicationDocumentsDirectory()
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (MethodCall methodCall) async {
            if (methodCall.method == 'getApplicationDocumentsDirectory') {
              return '/tmp/test_docs';
            }
            return null;
          },
        );
  });

  tearDown(() {
    groupMessageStreamController.close();
    joinedGroupInviteController.close();
    pendingInviteController.close();
    postsPrivacySettingsRepository.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  /// Sets the test surface to iPhone 14 Pro Max size to avoid overflow errors.
  void setLargeTestSurface(WidgetTester tester) {
    tester.view.physicalSize = const Size(1290, 2796);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  /// Suppresses RenderFlex overflow errors for complex animated layouts.
  void suppressOverflowErrors() {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.toString().contains('overflowed')) return;
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);
  }

  void suppressNavAssetErrors() {
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) {
      final message = details.exceptionAsString();
      if (message.contains('Unable to load asset') ||
          message.contains('SvgPicture') ||
          message.contains('ImageFilter')) {
        return;
      }
      originalOnError?.call(details);
    };
    addTearDown(() => FlutterError.onError = originalOnError);
  }

  /// Builds an OrbitWired widget with default fakes, wrapped in MaterialApp.
  ///
  /// [contactRequestListener] and [chatMessageListener] can be overridden
  /// for tests that need controllable streams.
  /// [wrapInNavigator] wraps in a Navigator with an underneath route for
  /// testing Navigator.pop() behavior.
  Widget buildOrbitWired({
    ContactRequestListener? contactRequestListener,
    ChatMessageListener? chatMessageListener,
    _FakeGroupMessageListener? groupMessageListener,
    FakeReactionRepository? reactionRepository,
    IntroductionListener? introductionListener,
    InMemoryIntroductionRepository? introductionRepository,
    GroupInviteListener? groupInviteListener,
    FakeContactRepository? contactRepository,
    InMemoryMessageRepository? messageRepository,
    InMemoryGroupRepository? groupRepository,
    InMemoryGroupMessageRepository? groupMessageRepository,
    bool wrapInNavigator = false,
    String? initialFilterTab,
    AppShellController? appShellController,
    ValueNotifier<int>? feedUnreadCountListenable,
    ValueChanged<FeedRouteChanges?>? onEmbeddedExit,
    ValueChanged<bool>? onRowActionOpenChanged,
    VoidCallback? onHeaderBuild,
    VoidCallback? onListBuild,
    List<NavigatorObserver>? navigatorObservers,
  }) {
    final effectiveContactRepo = contactRepository ?? contactRepo;
    final effectiveMessageRepo = messageRepository ?? messageRepo;
    final effectiveGroupRepo = groupRepository ?? groupRepo;
    final effectiveGroupMessageRepo = groupMessageRepository ?? groupMsgRepo;

    final crListener =
        contactRequestListener ??
        ContactRequestListener(
          contactRequestStream: const Stream<ChatMessage>.empty(),
          requestRepo: contactRequestRepo,
          contactRepo: effectiveContactRepo,
          bridge: bridge,
          getOwnPeerId: () => '',
        );

    final cmListener =
        chatMessageListener ??
        ChatMessageListener(
          chatMessageStream: const Stream<ChatMessage>.empty(),
          messageRepo: effectiveMessageRepo,
          contactRepo: effectiveContactRepo,
        );

    final gmListener =
        groupMessageListener ??
        _FakeGroupMessageListener(groupMessageStreamController.stream);

    final orbitWidget = OrbitWired(
      identityRepo: identityRepo,
      contactRepo: effectiveContactRepo,
      contactRequestRepo: contactRequestRepo,
      contactRequestListener: crListener,
      messageRepo: effectiveMessageRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      chatMessageListener: cmListener,
      bridge: bridge,
      p2pService: p2pService,
      mediaFileManager: mediaFileManager,
      secureKeyStore: secureKeyStore,
      imageProcessor: imageProcessor,
      reactionRepository: reactionRepository,
      groupRepository: effectiveGroupRepo,
      groupMessageRepository: effectiveGroupMessageRepo,
      groupMessageListener: gmListener,
      groupInviteListener: groupInviteListener,
      introductionRepository: introductionRepository,
      introductionListener: introductionListener,
      appShellController: appShellController,
      postsPrivacySettingsRepository: postsPrivacySettingsRepository,
      feedUnreadCountListenable: feedUnreadCountListenable,
      onEmbeddedExit: onEmbeddedExit,
      onRowActionOpenChanged: onRowActionOpenChanged,
      initialFilterTab: initialFilterTab,
      debugOnHeaderBuild: onHeaderBuild,
      debugOnListBuild: onListBuild,
    );

    if (wrapInNavigator) {
      return MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorObservers: navigatorObservers ?? const <NavigatorObserver>[],
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(
                    context,
                  ).push(MaterialPageRoute(builder: (_) => orbitWidget));
                },
                child: const Text('Open Orbit'),
              ),
            ),
          ),
        ),
      );
    }

    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      navigatorObservers: navigatorObservers ?? const <NavigatorObserver>[],
      home: orbitWidget,
    );
  }

  Future<void> pumpOrbitFrames(WidgetTester tester, {int count = 3}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  group('OrbitWired', () {
    GroupInviteMembershipFreshnessProof makeInviteFreshnessProof({
      required String inviteId,
      required String groupId,
      required String? recipientPeerId,
      required Map<String, dynamic> groupConfig,
      required DateTime issuedAt,
      String? recipientDeviceId,
      String? recipientTransportPeerId,
      String? recipientMlKemPublicKey,
      String? recipientKeyPackageId,
      String? recipientKeyPackagePublicMaterial,
    }) {
      final stateHash = buildGroupConfigStateHash(
        groupId: groupId,
        groupConfig: groupConfig,
      );
      return GroupInviteMembershipFreshnessProof(
        inviteId: inviteId,
        groupId: groupId,
        recipientPeerId: recipientPeerId,
        recipientDeviceId: recipientDeviceId,
        recipientTransportPeerId: recipientTransportPeerId,
        recipientMlKemPublicKey: recipientMlKemPublicKey,
        recipientKeyPackageId: recipientKeyPackageId,
        recipientKeyPackagePublicMaterial: recipientKeyPackagePublicMaterial,
        inviterPeerId: '12D3KooWAlice',
        inviterPublicKey: 'alicePubKey64',
        keyEpoch: 1,
        groupConfigStateHash: stateHash,
        membershipWatermark: stateHash,
        issuedAt: issuedAt.toUtc(),
        expiresAt: issuedAt.toUtc().add(groupInviteMembershipFreshnessTtl),
        inviterMemberSnapshot: const {
          'peerId': '12D3KooWAlice',
          'username': 'Alice',
          'role': 'admin',
          'publicKey': 'alicePubKey64',
          'mlKemPublicKey': 'aliceMlKem64',
        },
      );
    }

    PendingGroupInvite makePendingInvite({
      String groupId = 'grp-abc123',
      String groupName = 'Book Club',
      DateTime? receivedAt,
      String? recipientDeviceId,
    }) {
      final effectiveReceivedAt = (receivedAt ?? DateTime.now().toUtc())
          .toUtc();
      final createdAt = effectiveReceivedAt.subtract(const Duration(hours: 6));
      final inviteTimestamp = createdAt.add(const Duration(minutes: 5));
      final packageId = recipientDeviceId == null
          ? null
          : defaultGroupWelcomeKeyPackageIdForDevice(recipientDeviceId);
      final packageMaterial = recipientDeviceId == null
          ? null
          : testIdentity.mlKemPublicKey;
      final welcomeKeyPackage =
          recipientDeviceId != null &&
              packageId != null &&
              packageMaterial != null
          ? GroupWelcomeKeyPackage.create(
              packageId: packageId,
              publicMaterial: packageMaterial,
              recipientPeerId: testIdentity.peerId,
              recipientDeviceId: recipientDeviceId,
              recipientTransportPeerId: recipientDeviceId,
              recipientMlKemPublicKey: testIdentity.mlKemPublicKey!,
              inviteId: 'invite-$groupId',
              groupId: groupId,
              keyEpoch: 1,
              issuedAt: inviteTimestamp,
              expiresAt: effectiveReceivedAt.add(pendingGroupInviteTtl),
            )
          : null;
      final Map<String, dynamic> groupConfig = {
        'name': groupName,
        'groupType': 'chat',
        'description': 'Invite description',
        'members': [
          {
            'peerId': '12D3KooWAlice',
            'username': 'Alice',
            'role': 'admin',
            'publicKey': 'alicePubKey64',
            'mlKemPublicKey': 'aliceMlKem64',
          },
          {
            'peerId': testIdentity.peerId,
            'username': testIdentity.username,
            'role': 'writer',
            'publicKey': testIdentity.publicKey,
            'mlKemPublicKey': testIdentity.mlKemPublicKey,
            if (recipientDeviceId != null)
              'devices': [
                {
                  'deviceId': recipientDeviceId,
                  'transportPeerId': recipientDeviceId,
                  'deviceSigningPublicKey': testIdentity.publicKey,
                  'mlKemPublicKey': testIdentity.mlKemPublicKey,
                  'keyPackageId': packageId,
                  'keyPackagePublicMaterial': packageMaterial,
                  'status': 'active',
                },
              ],
          },
        ],
        'createdBy': '12D3KooWAlice',
        'createdAt': createdAt.toIso8601String(),
      };
      final payload = GroupInvitePayload(
        id: 'invite-$groupId',
        groupId: groupId,
        groupKey: 'base64-key',
        keyEpoch: 1,
        groupConfig: groupConfig,
        senderPeerId: '12D3KooWAlice',
        senderUsername: 'Alice',
        timestamp: inviteTimestamp.toIso8601String(),
        recipientPeerId: testIdentity.peerId,
        recipientDeviceId: recipientDeviceId,
        recipientTransportPeerId: recipientDeviceId,
        recipientMlKemPublicKey: recipientDeviceId == null
            ? null
            : testIdentity.mlKemPublicKey,
        recipientKeyPackageId: packageId,
        recipientKeyPackagePublicMaterial: packageMaterial,
        welcomeKeyPackage: welcomeKeyPackage,
        invitePolicy: GroupInvitePolicy(
          expiresAt: effectiveReceivedAt.add(pendingGroupInviteTtl),
          allowedDevices: [recipientDeviceId ?? testIdentity.peerId],
          assignedRole: 'writer',
          canInviteOthers: false,
          joinMaterialKind: GroupInvitePolicy.inlineGroupKeyKind,
          keyEpoch: 1,
          welcomeKeyPackageId: welcomeKeyPackage?.packageId,
          welcomeKeyPackagePublicMaterialHash:
              welcomeKeyPackage?.publicMaterialHash,
          welcomeKeyPackageExpiresAt: welcomeKeyPackage?.expiresAt,
        ),
        membershipFreshnessProof: makeInviteFreshnessProof(
          inviteId: 'invite-$groupId',
          groupId: groupId,
          recipientPeerId: testIdentity.peerId,
          recipientDeviceId: recipientDeviceId,
          recipientTransportPeerId: recipientDeviceId,
          recipientMlKemPublicKey: recipientDeviceId == null
              ? null
              : testIdentity.mlKemPublicKey,
          recipientKeyPackageId: packageId,
          recipientKeyPackagePublicMaterial: packageMaterial,
          groupConfig: groupConfig,
          issuedAt: inviteTimestamp,
        ),
      ).withInviteSignature(signature: 'signed-invite-by-alice');

      return PendingGroupInvite.fromPayload(
        payload,
        receivedAt: effectiveReceivedAt,
      );
    }

    testWidgets('loads and displays identity in orbit header', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);

      await tester.pumpWidget(buildOrbitWired());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // OrbitScreen renders OrbitHeader with the identity's peerId for the avatar.
      // It also renders the localized close-friends chrome in multiple places.
      expect(find.byType(OrbitWired), findsOneWidget);
      expect(find.text('Close Friends'), findsWidgets);
    });

    testWidgets('loads active friends list', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'msg-1',
          contactPeerId: 'contact-peer-id',
          text: 'Hello from Bob',
          senderPeerId: 'contact-peer-id',
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
          status: 'delivered',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );

      await tester.pumpWidget(buildOrbitWired());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // FriendRow renders the current display name
      expect(find.text('Bob'), findsWidgets);
    });

    testWidgets('cold load batches friend thread summaries', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);

      final spyContactRepo = _SpyContactRepository();
      final spyMessageRepo = _SpyMessageRepository();
      spyContactRepo.seed([
        testContact,
        testContact.copyWith(peerId: 'contact-peer-id-2', username: 'Cara'),
      ]);

      await tester.pumpWidget(
        buildOrbitWired(
          contactRepository: spyContactRepo,
          messageRepository: spyMessageRepo,
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(spyContactRepo.getActiveContactsCallCount, 1);
      expect(spyContactRepo.getArchivedContactsCallCount, 1);
      expect(spyMessageRepo.getConversationThreadSummariesCallCount, 1);
      expect(
        spyMessageRepo.getConversationThreadSummaryCallCountByPeerId,
        isEmpty,
      );
      expect(
        spyMessageRepo.getMessageCountForContactCallCountByPeerId,
        isEmpty,
      );
      expect(
        spyMessageRepo.getLatestMessageForContactCallCountByPeerId,
        isEmpty,
      );
      expect(spyMessageRepo.getUnreadCountForContactCallCountByPeerId, isEmpty);
    });

    testWidgets('search trigger button exists', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);

      await tester.pumpWidget(buildOrbitWired());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // OrbitSearchTrigger is the floating search pill at the bottom
      expect(find.byType(OrbitSearchTrigger), findsOneWidget);
      // It contains the search icon
      expect(find.byIcon(Icons.search), findsWidgets);
      // The trigger itself is icon-only; the placeholder lives in the dock.
      expect(
        find.descendant(
          of: find.byType(OrbitSearchTrigger),
          matching: find.byIcon(Icons.search),
        ),
        findsOneWidget,
      );
    });

    testWidgets('filter toggle shows All and Archived tabs', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);
      contactRepo.seed([testContact]);

      await tester.pumpWidget(buildOrbitWired());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // FriendsFilterToggle renders 'All' and 'Archived' labels
      expect(find.byType(FriendsFilterToggle), findsOneWidget);
      expect(find.text('All'), findsOneWidget);
      expect(find.text('Archived'), findsOneWidget);
    });

    testWidgets('friends list header shows QR buttons', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);

      await tester.pumpWidget(buildOrbitWired());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // FriendsListHeader renders 'My QR' and 'Scan' pill buttons
      expect(find.text('My QR'), findsOneWidget);
      expect(find.text('Scan'), findsOneWidget);
    });

    testWidgets('close button pops navigation', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);

      await tester.pumpWidget(buildOrbitWired(wrapInNavigator: true));
      await tester.pump(const Duration(milliseconds: 100));

      // Tap the 'Open Orbit' button to push the orbit route
      await tester.tap(find.text('Open Orbit'));
      // Pump enough frames for the route transition to complete (300ms default)
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // Verify OrbitWired is now on screen
      expect(find.byType(OrbitWired), findsOneWidget);

      // Tap the OrbitCloseButton (top-left X button)
      expect(find.byType(OrbitCloseButton), findsOneWidget);
      await tester.tap(find.byType(OrbitCloseButton));
      // Pump enough frames for the pop transition to complete (300ms default)
      for (int i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }

      // After pop, OrbitWired should no longer be visible
      expect(find.byType(OrbitWired), findsNothing);
      expect(find.text('Open Orbit'), findsOneWidget);
    });

    testWidgets(
      'embedded close button switches the shell back to feed without popping',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        suppressNavAssetErrors();
        identityRepo.seed(testIdentity);

        final feedUnreadCountListenable = ValueNotifier<int>(3);
        addTearDown(feedUnreadCountListenable.dispose);
        final shellController = AppShellController(
          initialTab: AppShellTab.orbit,
        );
        FeedRouteChanges? exitChanges;

        await tester.pumpWidget(
          buildOrbitWired(
            appShellController: shellController,
            feedUnreadCountListenable: feedUnreadCountListenable,
            onEmbeddedExit: (changes) => exitChanges = changes,
          ),
        );
        await pumpOrbitFrames(tester, count: 6);

        await tester.tap(find.byType(OrbitCloseButton));
        await pumpOrbitFrames(tester, count: 4);

        expect(find.byType(OrbitWired), findsOneWidget);
        expect(shellController.activeTab, AppShellTab.feed);
        expect(exitChanges, isNull);
      },
    );

    testWidgets(
      'persistent nav shows independent feed unread and orbit intro badges',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        suppressNavAssetErrors();
        identityRepo.seed(testIdentity);

        final feedUnreadCountListenable = ValueNotifier<int>(7);
        addTearDown(feedUnreadCountListenable.dispose);
        final shellController = AppShellController(initialTab: 'orbit');
        final introRepo = InMemoryIntroductionRepository();
        await introRepo.saveIntroduction(
          pendingIntroduction(
            ownPeerId: testIdentity.peerId,
            otherPeerId: 'intro-peer-id',
            createdAt: freshPendingIntroductionCreatedAt(),
          ),
        );

        await tester.pumpWidget(
          buildOrbitWired(
            appShellController: shellController,
            feedUnreadCountListenable: feedUnreadCountListenable,
            introductionRepository: introRepo,
          ),
        );
        await pumpOrbitFrames(tester, count: 6);

        expect(find.byType(FeedNavigationBar), findsOneWidget);
        final buttons = tester
            .widgetList<NavBarButton>(find.byType(NavBarButton))
            .toList();
        expect(buttons[0].badgeCount, 7);
        expect(buttons[0].isActive, isFalse);
        expect(buttons[1].badgeCount, 1);
        expect(buttons[1].isActive, isTrue);
      },
    );

    testWidgets(
      'persistent nav feed tap pops the route and switches the shell back to feed',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        suppressNavAssetErrors();
        identityRepo.seed(testIdentity);

        final feedUnreadCountListenable = ValueNotifier<int>(2);
        addTearDown(feedUnreadCountListenable.dispose);
        final observer = _RecordingNavigatorObserver();
        final shellController = AppShellController(initialTab: 'orbit');

        await tester.pumpWidget(
          buildOrbitWired(
            wrapInNavigator: true,
            appShellController: shellController,
            feedUnreadCountListenable: feedUnreadCountListenable,
            navigatorObservers: [observer],
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        observer.reset();

        await tester.tap(find.text('Open Orbit'));
        await pumpOrbitFrames(tester, count: 10);

        await tester.tap(find.text('Feed'));
        await pumpOrbitFrames(tester, count: 10);

        expect(find.byType(OrbitWired), findsNothing);
        expect(find.text('Open Orbit'), findsOneWidget);
        expect(shellController.activeTab, 'feed');
        expect(observer.pushCount, 1);
      },
    );

    testWidgets('persistent nav orbit tap is a route-level no-op', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);

      final feedUnreadCountListenable = ValueNotifier<int>(1);
      addTearDown(feedUnreadCountListenable.dispose);
      final observer = _RecordingNavigatorObserver();
      final shellController = AppShellController(initialTab: 'orbit');

      await tester.pumpWidget(
        buildOrbitWired(
          wrapInNavigator: true,
          appShellController: shellController,
          feedUnreadCountListenable: feedUnreadCountListenable,
          navigatorObservers: [observer],
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.text('Open Orbit'));
      await pumpOrbitFrames(tester, count: 10);
      observer.reset();

      await tester.tap(find.text('Orbit'));
      await pumpOrbitFrames(tester, count: 6);

      expect(find.byType(OrbitWired), findsOneWidget);
      expect(find.text('Open Orbit'), findsNothing);
      expect(observer.pushCount, 0);
      expect(shellController.activeTab, 'orbit');
    });

    testWidgets('refreshes only the affected friend on incoming message', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);
      final spyContactRepo = _SpyContactRepository();
      final spyMessageRepo = _SpyMessageRepository();
      spyContactRepo.seed([
        testContact,
        testContact.copyWith(peerId: 'contact-peer-id-2', username: 'Cara'),
      ]);

      final fakeChatListener = _FakeChatMessageListener(
        messageRepo: spyMessageRepo,
        contactRepo: spyContactRepo,
      );

      await tester.pumpWidget(
        buildOrbitWired(
          chatMessageListener: fakeChatListener,
          contactRepository: spyContactRepo,
          messageRepository: spyMessageRepo,
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Initially Bob exists as a friend but has no last activity text
      expect(find.text('Bob'), findsWidgets);

      spyContactRepo.resetTracking();
      spyMessageRepo.resetTracking();

      // Seed a mixed-script message and emit an incoming chat event to
      // trigger a single-friend refresh, not a full Orbit reload.
      await spyMessageRepo.saveMessage(
        ConversationMessage(
          id: 'msg-refresh-1',
          contactPeerId: 'contact-peer-id',
          text: 'مرحبا Hello 123',
          senderPeerId: 'contact-peer-id',
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
          status: 'delivered',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );

      fakeChatListener.emitIncomingMessage(
        ConversationMessage(
          id: 'msg-refresh-1',
          contactPeerId: 'contact-peer-id',
          text: 'مرحبا Hello 123',
          senderPeerId: 'contact-peer-id',
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
          status: 'delivered',
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // After refresh, the FriendRow should show the mixed-script text.
      expect(find.text('مرحبا Hello 123'), findsOneWidget);
      expect(
        _textFor(tester, 'مرحبا Hello 123').textDirection,
        TextDirection.rtl,
      );
      expect(spyContactRepo.getActiveContactsCallCount, 0);
      expect(spyContactRepo.getArchivedContactsCallCount, 0);
      expect(spyContactRepo.getContactCallCountByPeerId, {
        'contact-peer-id': 1,
      });
      expect(spyMessageRepo.getConversationThreadSummaryCallCountByPeerId, {
        'contact-peer-id': 1,
      });
      expect(spyMessageRepo.getConversationThreadSummariesCallCount, 0);
      expect(
        spyMessageRepo.getMessageCountForContactCallCountByPeerId,
        isEmpty,
      );
      expect(
        spyMessageRepo.getLatestMessageForContactCallCountByPeerId,
        isEmpty,
      );
      expect(spyMessageRepo.getUnreadCountForContactCallCountByPeerId, isEmpty);
    });

    testWidgets(
      'archived friend refresh stays in archived results after an incoming message',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        identityRepo.seed(testIdentity);
        final spyContactRepo = _SpyContactRepository();
        final spyMessageRepo = _SpyMessageRepository();
        spyContactRepo.seed([
          testContact.copyWith(
            isArchived: true,
            archivedAt: DateTime.utc(2026, 3, 1).toIso8601String(),
          ),
        ]);

        final fakeChatListener = _FakeChatMessageListener(
          messageRepo: spyMessageRepo,
          contactRepo: spyContactRepo,
        );

        await tester.pumpWidget(
          buildOrbitWired(
            chatMessageListener: fakeChatListener,
            contactRepository: spyContactRepo,
            messageRepository: spyMessageRepo,
            initialFilterTab: 'archived',
          ),
        );
        await pumpOrbitFrames(tester, count: 6);

        expect(find.text('Bob'), findsWidgets);

        spyContactRepo.resetTracking();
        spyMessageRepo.resetTracking();

        await spyMessageRepo.saveMessage(
          ConversationMessage(
            id: 'msg-archived-refresh',
            contactPeerId: 'contact-peer-id',
            text: 'Archived ping',
            senderPeerId: 'contact-peer-id',
            timestamp: DateTime.now().toUtc().toIso8601String(),
            isIncoming: true,
            status: 'delivered',
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );

        fakeChatListener.emitIncomingMessage(
          ConversationMessage(
            id: 'msg-archived-refresh',
            contactPeerId: 'contact-peer-id',
            text: 'Archived ping',
            senderPeerId: 'contact-peer-id',
            timestamp: DateTime.now().toUtc().toIso8601String(),
            isIncoming: true,
            status: 'delivered',
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );

        await pumpOrbitFrames(tester, count: 6);

        expect(find.text('Archived ping'), findsOneWidget);
        expect(spyContactRepo.getActiveContactsCallCount, 0);
        expect(spyContactRepo.getArchivedContactsCallCount, 0);
        expect(spyContactRepo.getContactCallCountByPeerId, {
          'contact-peer-id': 1,
        });
        expect(spyMessageRepo.getConversationThreadSummaryCallCountByPeerId, {
          'contact-peer-id': 1,
        });
        expect(spyMessageRepo.getConversationThreadSummariesCallCount, 0);

        await tester.tap(find.text('All'));
        await pumpOrbitFrames(tester, count: 3);

        expect(find.text('Archived ping'), findsNothing);
        expect(find.text('Bob'), findsNothing);
      },
    );

    testWidgets(
      'incoming mixed Arabic-first message refreshes the row and renders RTL',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        identityRepo.seed(testIdentity);
        final spyContactRepo = _SpyContactRepository();
        final spyMessageRepo = _SpyMessageRepository();
        spyContactRepo.seed([testContact]);

        final fakeChatListener = _FakeChatMessageListener(
          messageRepo: spyMessageRepo,
          contactRepo: spyContactRepo,
        );

        await tester.pumpWidget(
          buildOrbitWired(
            chatMessageListener: fakeChatListener,
            contactRepository: spyContactRepo,
            messageRepository: spyMessageRepo,
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        spyContactRepo.resetTracking();
        spyMessageRepo.resetTracking();

        const mixedText = 'مرحبا Hello 123';
        await spyMessageRepo.saveMessage(
          ConversationMessage(
            id: 'msg-refresh-mixed',
            contactPeerId: 'contact-peer-id',
            text: mixedText,
            senderPeerId: 'contact-peer-id',
            timestamp: DateTime.now().toUtc().toIso8601String(),
            isIncoming: true,
            status: 'delivered',
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );

        fakeChatListener.emitIncomingMessage(
          ConversationMessage(
            id: 'msg-refresh-mixed',
            contactPeerId: 'contact-peer-id',
            text: mixedText,
            senderPeerId: 'contact-peer-id',
            timestamp: DateTime.now().toUtc().toIso8601String(),
            isIncoming: true,
            status: 'delivered',
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );

        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text(mixedText), findsOneWidget);
        expect(_textFor(tester, mixedText).textDirection, TextDirection.rtl);
        expect(spyContactRepo.getContactCallCountByPeerId, {
          'contact-peer-id': 1,
        });
        expect(spyMessageRepo.getConversationThreadSummaryCallCountByPeerId, {
          'contact-peer-id': 1,
        });
      },
    );

    testWidgets(
      'search context is preserved while unrelated friend updates arrive',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        identityRepo.seed(testIdentity);

        final spyContactRepo = _SpyContactRepository();
        final spyMessageRepo = _SpyMessageRepository();
        spyContactRepo.seed([
          testContact,
          testContact.copyWith(peerId: 'contact-peer-id-2', username: 'Cara'),
        ]);

        final fakeChatListener = _FakeChatMessageListener(
          messageRepo: spyMessageRepo,
          contactRepo: spyContactRepo,
        );

        await tester.pumpWidget(
          buildOrbitWired(
            chatMessageListener: fakeChatListener,
            contactRepository: spyContactRepo,
            messageRepository: spyMessageRepo,
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        await tester.tap(find.byType(OrbitSearchTrigger));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        await tester.enterText(find.byType(TextField), 'Bo');
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Bob'), findsWidgets);
        expect(find.text('Cara'), findsNothing);

        await spyMessageRepo.saveMessage(
          ConversationMessage(
            id: 'msg-refresh-cara',
            contactPeerId: 'contact-peer-id-2',
            text: 'Cara says hi',
            senderPeerId: 'contact-peer-id-2',
            timestamp: DateTime.now().toUtc().toIso8601String(),
            isIncoming: true,
            status: 'delivered',
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );

        fakeChatListener.emitIncomingMessage(
          ConversationMessage(
            id: 'msg-refresh-cara',
            contactPeerId: 'contact-peer-id-2',
            text: 'Cara says hi',
            senderPeerId: 'contact-peer-id-2',
            timestamp: DateTime.now().toUtc().toIso8601String(),
            isIncoming: true,
            status: 'delivered',
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );

        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        expect(find.text('Bob'), findsWidgets);
        expect(find.text('Cara'), findsNothing);
        final searchField = tester.widget<TextField>(find.byType(TextField));
        expect(searchField.controller!.text, 'Bo');
      },
    );

    testWidgets(
      'typing search updates the list without rebuilding the header',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        identityRepo.seed(testIdentity);
        contactRepo.seed([
          testContact,
          testContact.copyWith(peerId: 'contact-peer-id-2', username: 'Cara'),
        ]);

        var headerBuildCount = 0;
        var listBuildCount = 0;

        await tester.pumpWidget(
          buildOrbitWired(
            onHeaderBuild: () => headerBuildCount++,
            onListBuild: () => listBuildCount++,
          ),
        );
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        await tester.tap(find.byType(OrbitSearchTrigger));
        await tester.pump(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));

        final headerBuildsBeforeTyping = headerBuildCount;
        final listBuildsBeforeTyping = listBuildCount;

        await tester.enterText(find.byType(TextField), 'Bo');
        await tester.pump(const Duration(milliseconds: 100));

        expect(headerBuildCount, headerBuildsBeforeTyping);
        expect(listBuildCount, greaterThan(listBuildsBeforeTyping));
        expect(find.text('Bob'), findsWidgets);
        expect(find.text('Cara'), findsNothing);
      },
    );

    testWidgets('shows contact request dialog on incoming request', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);

      final fakeRequestListener = _FakeContactRequestListener(
        requestRepo: contactRequestRepo,
        contactRepo: contactRepo,
        bridge: bridge,
      );

      await tester.pumpWidget(
        buildOrbitWired(contactRequestListener: fakeRequestListener),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Emit a contact request
      fakeRequestListener.emitRequest(
        ContactRequestModel(
          peerId: 'requester-peer-id',
          publicKey: 'requester-pk',
          rendezvous: '/dns4/relay',
          username: 'Charlie',
          signature: 'req-sig',
          receivedAt: DateTime.now().toUtc().toIso8601String(),
          status: ContactRequestStatus.pending,
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // The ContactRequestDialog should appear with Charlie's name
      expect(find.text('Charlie'), findsOneWidget);
      expect(find.text('wants to connect with you'), findsOneWidget);
      expect(find.text('Accept'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
    });

    testWidgets('disposes stream subscriptions without errors', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);

      final fakeChatListener = _FakeChatMessageListener(
        messageRepo: messageRepo,
        contactRepo: contactRepo,
      );

      final fakeRequestListener = _FakeContactRequestListener(
        requestRepo: contactRequestRepo,
        contactRepo: contactRepo,
        bridge: bridge,
      );

      await tester.pumpWidget(
        buildOrbitWired(
          chatMessageListener: fakeChatListener,
          contactRequestListener: fakeRequestListener,
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Replace the widget tree with something else to trigger dispose
      await tester.pumpWidget(
        const MaterialApp(home: Scaffold(body: Text('Replaced'))),
      );
      await tester.pump(const Duration(milliseconds: 100));

      // No crash or error means subscriptions and animation controllers
      // were all disposed cleanly
      expect(find.text('Replaced'), findsOneWidget);
    });

    testWidgets('shows ExpandableFab with + icon', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);

      await tester.pumpWidget(buildOrbitWired());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // ExpandableFab is now in OrbitScreen
      expect(find.byType(ExpandableFab), findsOneWidget);
      expect(find.byIcon(Icons.add), findsOneWidget);
    });

    testWidgets('tapping FAB opens menu with New Group and New Announce', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);

      await tester.pumpWidget(buildOrbitWired());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('New Group'), findsOneWidget);
      expect(find.text('New Announce'), findsOneWidget);
    });

    testWidgets('displays group rows when groups exist', (tester) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);

      await groupRepo.saveGroup(
        GroupModel(
          id: 'g-1',
          name: 'Alpha Group',
          type: GroupType.chat,
          topicName: 'topic-g-1',
          createdAt: DateTime.utc(2026, 3, 1),
          createdBy: 'peer-admin',
          myRole: GroupRole.admin,
        ),
      );

      await tester.pumpWidget(buildOrbitWired());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Group name should appear in the list
      expect(find.text('Alpha Group'), findsOneWidget);
    });

    testWidgets('displays structured group rows with latest message preview', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);

      await groupRepo.saveGroup(
        GroupModel(
          id: 'g-1',
          name: 'Alpha Group',
          type: GroupType.chat,
          topicName: 'topic-g-1',
          createdAt: DateTime.utc(2026, 3, 1),
          createdBy: 'peer-admin',
          myRole: GroupRole.admin,
        ),
      );

      await groupMsgRepo.saveMessage(
        GroupMessage(
          id: 'gm-1',
          groupId: 'g-1',
          senderPeerId: 'peer-alice',
          senderUsername: 'Alice',
          text: 'مرحبا Hello 123',
          timestamp: DateTime.utc(2026, 3, 1),
          isIncoming: true,
          createdAt: DateTime.utc(2026, 3, 1),
        ),
      );

      await tester.pumpWidget(buildOrbitWired());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Alpha Group'), findsOneWidget);
      expect(find.text('Alice'), findsOneWidget);
      expect(find.text('مرحبا Hello 123'), findsOneWidget);
      expect(
        _textFor(tester, 'مرحبا Hello 123').textDirection,
        TextDirection.rtl,
      );
    });

    testWidgets('refreshes only the affected group on incoming group message', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);
      final spyContactRepo = _SpyContactRepository();
      final spyMessageRepo = _SpyMessageRepository();
      final spyGroupRepo = _SpyGroupRepository();
      final spyGroupMsgRepo = _SpyGroupMessageRepository();

      await spyGroupRepo.saveGroup(
        GroupModel(
          id: 'g-1',
          name: 'Alpha Group',
          type: GroupType.chat,
          topicName: 'topic-g-1',
          createdAt: DateTime.utc(2026, 3, 1),
          createdBy: 'peer-admin',
          myRole: GroupRole.admin,
        ),
      );

      await tester.pumpWidget(
        buildOrbitWired(
          contactRepository: spyContactRepo,
          messageRepository: spyMessageRepo,
          groupRepository: spyGroupRepo,
          groupMessageRepository: spyGroupMsgRepo,
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Initially group shows with no message preview
      expect(find.text('Alpha Group'), findsOneWidget);
      expect(find.text('Bob'), findsNothing);
      expect(find.text('New group msg'), findsNothing);

      spyContactRepo.resetTracking();
      spyMessageRepo.resetTracking();
      spyGroupRepo.resetTracking();
      spyGroupMsgRepo.resetTracking();

      // Seed a group message and emit on the group message stream
      final newMsg = GroupMessage(
        id: 'gm-new',
        groupId: 'g-1',
        senderPeerId: 'peer-bob',
        senderUsername: 'Bob',
        text: 'New group msg',
        timestamp: DateTime.utc(2026, 3, 2),
        isIncoming: true,
        createdAt: DateTime.utc(2026, 3, 2),
      );
      await spyGroupMsgRepo.saveMessage(newMsg);
      groupMessageStreamController.add(newMsg);

      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Bob'), findsOneWidget);
      expect(find.text('New group msg'), findsOneWidget);
      expect(spyContactRepo.getActiveContactsCallCount, 0);
      expect(spyContactRepo.getArchivedContactsCallCount, 0);
      expect(spyGroupRepo.getActiveGroupsCallCount, 0);
      expect(spyGroupRepo.getAllGroupsCallCount, 0);
      expect(spyGroupRepo.getGroupCallCountById, {'g-1': 1});
      expect(spyGroupMsgRepo.getGroupThreadSummaryCallCountByGroupId, {
        'g-1': 1,
      });
      expect(spyGroupMsgRepo.getGroupThreadSummariesCallCount, 0);
      expect(spyGroupMsgRepo.getLatestMessageCallCountByGroupId, isEmpty);
      expect(spyGroupMsgRepo.getUnreadCountCallCountByGroupId, isEmpty);
    });

    testWidgets('create-group route result refreshes only the affected group', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);

      final spyGroupRepo = _SpyGroupRepository();
      final spyGroupMsgRepo = _SpyGroupMessageRepository();
      await spyGroupRepo.saveGroup(
        GroupModel(
          id: 'g-1',
          name: 'Alpha Group',
          type: GroupType.chat,
          topicName: 'topic-g-1',
          createdAt: DateTime.utc(2026, 3, 1),
          createdBy: 'peer-admin',
          myRole: GroupRole.admin,
        ),
      );

      await tester.pumpWidget(
        buildOrbitWired(
          groupRepository: spyGroupRepo,
          groupMessageRepository: spyGroupMsgRepo,
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      spyGroupRepo.resetTracking();
      spyGroupMsgRepo.resetTracking();

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('New Group'));
      await tester.pump(const Duration(milliseconds: 300));

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop(const FeedRouteChanges(changedGroupIds: {'g-1'}));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      expect(spyGroupRepo.getActiveGroupsCallCount, 0);
      expect(spyGroupRepo.getAllGroupsCallCount, 0);
      expect(spyGroupRepo.getGroupCallCountById, {'g-1': 1});
      expect(spyGroupMsgRepo.getGroupThreadSummariesCallCount, 0);
      expect(spyGroupMsgRepo.getGroupThreadSummaryCallCountByGroupId, {
        'g-1': 1,
      });
    });

    testWidgets('interleaves groups and friends sorted by last activity', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);

      // Add a friend with an older message
      contactRepo.seed([testContact]);
      await messageRepo.saveMessage(
        ConversationMessage(
          id: 'msg-old',
          contactPeerId: 'contact-peer-id',
          text: 'Old message from Bob',
          senderPeerId: 'contact-peer-id',
          timestamp: '2026-01-01T00:00:00.000Z',
          isIncoming: true,
          status: 'delivered',
          createdAt: '2026-01-01T00:00:00.000Z',
        ),
      );

      // Add a group with a newer message
      await groupRepo.saveGroup(
        GroupModel(
          id: 'g-1',
          name: 'Newer Group',
          type: GroupType.chat,
          topicName: 'topic-g-1',
          createdAt: DateTime.utc(2026, 3, 1),
          createdBy: 'peer-admin',
          myRole: GroupRole.admin,
        ),
      );
      await groupMsgRepo.saveMessage(
        GroupMessage(
          id: 'gm-1',
          groupId: 'g-1',
          senderPeerId: 'peer-alice',
          senderUsername: 'Alice',
          text: 'Recent group msg',
          timestamp: DateTime.utc(2026, 3, 1),
          isIncoming: true,
          createdAt: DateTime.utc(2026, 3, 1),
        ),
      );

      await tester.pumpWidget(buildOrbitWired());
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 100));

      // Both should appear
      expect(find.text('Newer Group'), findsOneWidget);
      expect(find.text('Bob'), findsWidgets);
    });

    testWidgets(
      'friend tap pushes conversation route before read marking completes',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        identityRepo.seed(testIdentity);

        final delayedContactRepo = _DelayedSpyContactRepository()
          ..seed([testContact]);
        final delayedMessageRepo = _DelayedSpyMessageRepository()
          ..markConversationAsReadGate = Completer<void>();
        final observer = _RecordingNavigatorObserver();

        await tester.pumpWidget(
          buildOrbitWired(
            contactRepository: delayedContactRepo,
            messageRepository: delayedMessageRepo,
            navigatorObservers: [observer],
          ),
        );
        await pumpOrbitFrames(tester);

        observer.reset();

        await tester.tap(find.text('Bob').first);
        await tester.pump();

        expect(observer.pushCount, 1);
        expect(observer.lastPushedRoute, isNotNull);

        delayedMessageRepo.markConversationAsReadGate!.complete();
        await pumpOrbitFrames(tester);
      },
    );

    testWidgets(
      'late mutual acceptance and later block do not let stale intro reload repopulate Intros',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        identityRepo.seed(testIdentity);

        final introRepo = _SequencedIntroductionRepository();
        final fakeIntroListener = _FakeIntroductionListener(
          introRepo: introRepo,
          contactRepo: contactRepo,
          bridge: bridge,
          messageRepo: messageRepo,
        );
        final fakeChatListener = _FakeChatMessageListener(
          messageRepo: messageRepo,
          contactRepo: contactRepo,
        );

        final pendingIntro = IntroductionModel(
          id: 'intro-late-accept',
          introducerId: 'peer-A',
          recipientId: testIdentity.peerId,
          introducedId: 'intro-peer-id',
          introducerUsername: 'Noor',
          recipientUsername: testIdentity.username,
          introducedUsername: 'Dora',
          recipientStatus: IntroductionStatus.accepted,
          introducedStatus: IntroductionStatus.pending,
          status: IntroductionOverallStatus.pending,
          createdAt: '2026-03-01T12:00:00.000Z',
        );

        introRepo.pendingResultsByCall[1] = [pendingIntro];
        introRepo.pendingResultsByCall[2] = [pendingIntro];
        introRepo.pendingResultsByCall[3] = const <IntroductionModel>[];
        introRepo.pendingResultsByCall[4] = const <IntroductionModel>[];
        introRepo.pendingCallGates[2] = Completer<void>();

        await tester.pumpWidget(
          buildOrbitWired(
            chatMessageListener: fakeChatListener,
            introductionRepository: introRepo,
            introductionListener: fakeIntroListener,
          ),
        );

        await introRepo.waitForPendingCall(2);

        final introducedContact = ContactModel(
          peerId: 'intro-peer-id',
          publicKey: 'intro-pk',
          rendezvous: '/dns4/relay/tcp/443',
          username: 'Dora',
          signature: 'intro-sig',
          scannedAt: '2026-03-02T08:00:00.000Z',
          introducedBy: 'Noor',
          introducedByPeerId: 'peer-A',
        );
        await contactRepo.addContact(introducedContact);

        fakeIntroListener.emitIntroStatusChanged(
          pendingIntro.copyWith(
            introducedStatus: IntroductionStatus.accepted,
            status: IntroductionOverallStatus.mutualAccepted,
          ),
        );

        await pumpOrbitFrames(tester, count: 6);

        expect(find.text('Dora'), findsWidgets);

        await contactRepo.blockContact(introducedContact.peerId);
        fakeChatListener.emitContactUpdate(
          introducedContact.copyWith(
            isBlocked: true,
            blockedAt: '2026-03-02T08:05:00.000Z',
          ),
        );

        await pumpOrbitFrames(tester, count: 4);

        introRepo.pendingCallGates[2]!.complete();
        await pumpOrbitFrames(tester, count: 6);

        await tester.tap(find.text('Intros'));
        await pumpOrbitFrames(tester, count: 3);

        expect(find.text('No introductions yet'), findsOneWidget);
        expect(find.text('Unavailable'), findsNothing);
      },
    );

    testWidgets('startup repairs a stale persisted mutual acceptance row', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      identityRepo.seed(testIdentity);

      final introRepo = InMemoryIntroductionRepository();
      await introRepo.saveIntroduction(
        IntroductionModel(
          id: 'intro-stale-upgrade-row',
          introducerId: 'peer-A',
          recipientId: testIdentity.peerId,
          introducedId: 'intro-peer-id',
          introducerUsername: 'Noor',
          recipientUsername: testIdentity.username,
          introducedUsername: 'Dora',
          recipientStatus: IntroductionStatus.accepted,
          introducedStatus: IntroductionStatus.accepted,
          status: IntroductionOverallStatus.pending,
          createdAt: freshPendingIntroductionCreatedAt(),
        ),
      );

      await contactRepo.addContact(
        ContactModel(
          peerId: 'intro-peer-id',
          publicKey: 'intro-pk',
          rendezvous: '/dns4/relay/tcp/443',
          username: 'Dora',
          signature: 'intro-sig',
          scannedAt: '2026-03-25T12:05:00.000Z',
          introducedBy: 'Noor',
          introducedByPeerId: 'peer-A',
        ),
      );

      await tester.pumpWidget(
        buildOrbitWired(
          introductionRepository: introRepo,
          initialFilterTab: 'intros',
        ),
      );
      await pumpOrbitFrames(tester, count: 6);

      expect(find.text('Waiting for Dora'), findsNothing);
      expect(find.text('No introductions yet'), findsOneWidget);

      final loaded = await introRepo.getIntroduction('intro-stale-upgrade-row');
      expect(loaded, isNotNull);
      expect(loaded!.status, IntroductionOverallStatus.mutualAccepted);
    });

    testWidgets(
      'accepting an intro shows processing immediately and ignores duplicate taps',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        identityRepo.seed(testIdentity);

        final introRepo = _BlockingIntroductionRepository();
        await introRepo.saveIntroduction(
          pendingIntroduction(
            ownPeerId: testIdentity.peerId,
            otherPeerId: 'intro-peer-id',
            createdAt: freshPendingIntroductionCreatedAt(),
          ),
        );
        introRepo.acceptGate = Completer<void>();

        await tester.pumpWidget(
          buildOrbitWired(
            introductionRepository: introRepo,
            initialFilterTab: 'intros',
          ),
        );
        await pumpOrbitFrames(tester, count: 6);

        final acceptFinder = find.byKey(
          const ValueKey('intro-accept-orbit-intro'),
        );

        await tester.tap(acceptFinder);
        await tester.pump();

        expect(find.text('Accepting...'), findsOneWidget);
        expect(introRepo.acceptedUpdates, 1);
        expect(tester.widget<FilledButton>(acceptFinder).onPressed, isNull);
        expect(
          tester
              .widget<OutlinedButton>(
                find.byKey(const ValueKey('intro-pass-orbit-intro')),
              )
              .onPressed,
          isNull,
        );

        await tester.tap(acceptFinder);
        await tester.pump();

        expect(introRepo.acceptedUpdates, 1);

        introRepo.acceptGate!.complete();
        await pumpOrbitFrames(tester, count: 8);
      },
    );

    testWidgets(
      'passing an intro disables both actions immediately and ignores duplicate taps',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        identityRepo.seed(testIdentity);

        final introRepo = _BlockingIntroductionRepository();
        await introRepo.saveIntroduction(
          pendingIntroduction(
            ownPeerId: testIdentity.peerId,
            otherPeerId: 'intro-peer-id',
            createdAt: freshPendingIntroductionCreatedAt(),
          ),
        );
        introRepo.passGate = Completer<void>();

        await tester.pumpWidget(
          buildOrbitWired(
            introductionRepository: introRepo,
            initialFilterTab: 'intros',
          ),
        );
        await pumpOrbitFrames(tester, count: 6);

        final passFinder = find.byKey(const ValueKey('intro-pass-orbit-intro'));

        await tester.tap(passFinder);
        await tester.pump();

        expect(introRepo.passedUpdates, 1);
        expect(tester.widget<OutlinedButton>(passFinder).onPressed, isNull);
        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('intro-accept-orbit-intro')),
              )
              .onPressed,
          isNull,
        );

        await tester.tap(passFinder);
        await tester.pump();

        expect(introRepo.passedUpdates, 1);

        introRepo.passGate!.complete();
        await pumpOrbitFrames(tester, count: 8);
      },
    );

    testWidgets(
      'live intro delete confirmation removes the row, clears the badge, and marks route-return refresh',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        suppressNavAssetErrors();
        identityRepo.seed(testIdentity);

        final introRepo = InMemoryIntroductionRepository();
        await introRepo.saveIntroduction(
          pendingIntroduction(
            ownPeerId: testIdentity.peerId,
            otherPeerId: 'intro-peer-id',
            createdAt: freshPendingIntroductionCreatedAt(),
          ),
        );

        final feedUnreadCountListenable = ValueNotifier<int>(4);
        addTearDown(feedUnreadCountListenable.dispose);
        final shellController = AppShellController(
          initialTab: AppShellTab.orbit,
        );
        FeedRouteChanges? exitChanges;

        await tester.pumpWidget(
          buildOrbitWired(
            introductionRepository: introRepo,
            initialFilterTab: 'intros',
            appShellController: shellController,
            feedUnreadCountListenable: feedUnreadCountListenable,
            onEmbeddedExit: (changes) => exitChanges = changes,
          ),
        );
        await pumpOrbitFrames(tester, count: 6);

        expect(find.text('Dora'), findsOneWidget);
        var buttons = tester
            .widgetList<NavBarButton>(find.byType(NavBarButton))
            .toList();
        expect(buttons[1].badgeCount, 1);

        final center = tester.getCenter(find.text('Dora'));
        await tester.dragFrom(center, const Offset(-140, 0));
        await pumpOrbitFrames(tester, count: 4);

        await tester.tap(find.text('Delete').first);
        await tester.pump();
        expect(find.text('Delete'), findsNWidgets(2));

        await tester.tap(find.text('Delete').last);
        await pumpOrbitFrames(tester, count: 6);

        expect(find.text('Dora'), findsNothing);
        expect(find.text('No introductions yet'), findsOneWidget);

        buttons = tester
            .widgetList<NavBarButton>(find.byType(NavBarButton))
            .toList();
        expect(buttons[1].badgeCount, 0);

        await tester.tap(find.text('Feed'));
        await pumpOrbitFrames(tester, count: 4);

        expect(shellController.activeTab, AppShellTab.feed);
        expect(exitChanges?.refreshPendingIntroductions, isTrue);
      },
    );

    testWidgets('canceling live intro delete keeps the row and badge count', (
      tester,
    ) async {
      setLargeTestSurface(tester);
      suppressOverflowErrors();
      suppressNavAssetErrors();
      identityRepo.seed(testIdentity);

      final introRepo = InMemoryIntroductionRepository();
      await introRepo.saveIntroduction(
        pendingIntroduction(
          ownPeerId: testIdentity.peerId,
          otherPeerId: 'intro-peer-id',
          createdAt: freshPendingIntroductionCreatedAt(),
        ),
      );

      final feedUnreadCountListenable = ValueNotifier<int>(1);
      addTearDown(feedUnreadCountListenable.dispose);
      final shellController = AppShellController(initialTab: AppShellTab.orbit);

      await tester.pumpWidget(
        buildOrbitWired(
          introductionRepository: introRepo,
          initialFilterTab: 'intros',
          appShellController: shellController,
          feedUnreadCountListenable: feedUnreadCountListenable,
        ),
      );
      await pumpOrbitFrames(tester, count: 6);

      final center = tester.getCenter(find.text('Dora'));
      await tester.dragFrom(center, const Offset(-140, 0));
      await pumpOrbitFrames(tester, count: 4);

      await tester.tap(find.text('Delete').first);
      await tester.pump();
      await tester.tap(find.text('Cancel'));
      await pumpOrbitFrames(tester, count: 4);

      expect(find.text('Dora'), findsOneWidget);
      final remaining = await introRepo.countPendingIntroductions(
        testIdentity.peerId,
      );
      expect(remaining, 1);
      final buttons = tester
          .widgetList<NavBarButton>(find.byType(NavBarButton))
          .toList();
      expect(buttons[1].badgeCount, 1);
      expect(shellController.activeTab, AppShellTab.orbit);
    });

    testWidgets(
      'pending group invites are visible from the Intros tab and counted in the Orbit badge',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        identityRepo.seed(testIdentity);

        final invite = makePendingInvite(
          groupId: 'grp-intros',
          groupName: 'My Group - 1',
        );
        await pendingInviteRepo.savePendingInvite(invite);

        final groupInviteListener = _FakeGroupInviteListener(
          joinedStream: joinedGroupInviteController.stream,
          pendingStream: pendingInviteController.stream,
          pendingInviteRepo: pendingInviteRepo,
        );
        final feedUnreadCountListenable = ValueNotifier<int>(0);
        addTearDown(feedUnreadCountListenable.dispose);

        await tester.pumpWidget(
          buildOrbitWired(
            groupInviteListener: groupInviteListener,
            initialFilterTab: 'intros',
            appShellController: AppShellController(
              initialTab: AppShellTab.orbit,
            ),
            feedUnreadCountListenable: feedUnreadCountListenable,
          ),
        );
        await pumpOrbitFrames(tester, count: 6);

        expect(find.text('Pending Group Invites'), findsOneWidget);
        expect(find.text('My Group - 1'), findsOneWidget);
        expect(find.text('Invited by Alice'), findsOneWidget);

        final buttons = tester
            .widgetList<NavBarButton>(find.byType(NavBarButton))
            .toList();
        expect(buttons[1].badgeCount, 1);
      },
    );

    testWidgets(
      'accepting a pending group invite from Intros joins the group',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        identityRepo.seed(testIdentity);
        contactRepo.seed([
          const ContactModel(
            peerId: '12D3KooWAlice',
            publicKey: 'alicePubKey64',
            rendezvous: '/ip4/0.0.0.0',
            username: 'Alice',
            signature: 'sig',
            scannedAt: '2026-01-01T00:00:00Z',
            mlKemPublicKey: 'aliceMlKem64',
          ),
        ]);

        final invite = makePendingInvite(
          groupId: 'grp-accept',
          groupName: 'Writers Room',
        );
        await pendingInviteRepo.savePendingInvite(invite);
        bridge.responses['group:inboxRetrieveCursor'] = {
          'ok': true,
          'messages': <Map<String, dynamic>>[],
          'cursor': '',
        };

        final groupInviteListener = _FakeGroupInviteListener(
          joinedStream: joinedGroupInviteController.stream,
          pendingStream: pendingInviteController.stream,
          pendingInviteRepo: pendingInviteRepo,
        );
        final feedUnreadCountListenable = ValueNotifier<int>(0);
        addTearDown(feedUnreadCountListenable.dispose);

        await tester.pumpWidget(
          buildOrbitWired(
            groupInviteListener: groupInviteListener,
            initialFilterTab: 'intros',
            appShellController: AppShellController(
              initialTab: AppShellTab.orbit,
            ),
            feedUnreadCountListenable: feedUnreadCountListenable,
          ),
        );
        await pumpOrbitFrames(tester, count: 6);

        await tester.tap(
          find.byKey(ValueKey('pending-group-invite-accept-${invite.groupId}')),
        );
        await pumpOrbitFrames(tester, count: 30);

        expect(
          await pendingInviteRepo.getPendingInvite(invite.groupId),
          isNull,
        );
        expect(await groupRepo.getGroup(invite.groupId), isNotNull);
        expect(
          find.byKey(ValueKey('pending-group-invite-${invite.groupId}')),
          findsNothing,
        );
        expect(find.text('Joined Writers Room'), findsOneWidget);

        await tester.tap(find.text('All'));
        await pumpOrbitFrames(tester, count: 4);

        expect(find.text('Writers Room'), findsOneWidget);
      },
    );

    testWidgets(
      'EK011 accepts a key-package-bound pending group invite from Intros',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        identityRepo.seed(testIdentity);
        contactRepo.seed([
          const ContactModel(
            peerId: '12D3KooWAlice',
            publicKey: 'alicePubKey64',
            rendezvous: '/ip4/0.0.0.0',
            username: 'Alice',
            signature: 'sig',
            scannedAt: '2026-01-01T00:00:00Z',
            mlKemPublicKey: 'aliceMlKem64',
          ),
        ]);
        const localDeviceId = 'orbit-local-device-1';
        p2pService.emitState(
          const NodeState(peerId: localDeviceId, isStarted: true),
        );

        final invite = makePendingInvite(
          groupId: 'grp-package-orbit',
          groupName: 'Package Writers',
          recipientDeviceId: localDeviceId,
        );
        await pendingInviteRepo.savePendingInvite(invite);

        final groupInviteListener = _FakeGroupInviteListener(
          joinedStream: joinedGroupInviteController.stream,
          pendingStream: pendingInviteController.stream,
          pendingInviteRepo: pendingInviteRepo,
        );
        final feedUnreadCountListenable = ValueNotifier<int>(0);
        addTearDown(feedUnreadCountListenable.dispose);

        await tester.pumpWidget(
          buildOrbitWired(
            groupInviteListener: groupInviteListener,
            initialFilterTab: 'intros',
            appShellController: AppShellController(
              initialTab: AppShellTab.orbit,
            ),
            feedUnreadCountListenable: feedUnreadCountListenable,
          ),
        );
        await pumpOrbitFrames(tester, count: 6);

        await tester.tap(
          find.byKey(ValueKey('pending-group-invite-accept-${invite.groupId}')),
        );
        await pumpOrbitFrames(tester, count: 30);

        expect(
          await pendingInviteRepo.getPendingInvite(invite.groupId),
          isNull,
        );
        expect(await groupRepo.getGroup(invite.groupId), isNotNull);
        expect(
          find.byKey(ValueKey('pending-group-invite-${invite.groupId}')),
          findsNothing,
        );
        expect(find.text('Joined Package Writers'), findsOneWidget);

        final tombstone = await pendingInviteRepo.getWelcomeKeyPackageTombstone(
          packageId: defaultGroupWelcomeKeyPackageIdForDevice(localDeviceId)!,
          recipientDeviceId: localDeviceId,
          groupId: invite.groupId,
        );
        expect(tombstone, isNotNull);
        expect(tombstone!.inviteId, invite.inviteId);
      },
    );

    testWidgets(
      'pushed conversation route shows loading shell before delayed initial page resolves',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        identityRepo.seed(testIdentity);

        final delayedContactRepo = _DelayedSpyContactRepository()
          ..seed([testContact]);
        final delayedMessageRepo = _DelayedSpyMessageRepository()
          ..markConversationAsReadGate = Completer<void>()
          ..getMessagesPageGate = Completer<void>();
        final observer = _RecordingNavigatorObserver();

        await tester.pumpWidget(
          buildOrbitWired(
            contactRepository: delayedContactRepo,
            messageRepository: delayedMessageRepo,
            navigatorObservers: [observer],
          ),
        );
        await pumpOrbitFrames(tester);

        observer.reset();

        await tester.tap(find.text('Bob').first);
        await tester.pump();
        await pumpOrbitFrames(tester, count: 2);

        expect(observer.pushCount, 1);
        expect(
          find.byKey(const ValueKey('conversation-loading-shell')),
          findsOneWidget,
        );
        expect(find.byType(ConversationHeader), findsOneWidget);
        expect(find.text('Write something...'), findsOneWidget);

        delayedMessageRepo.markConversationAsReadGate!.complete();
        delayedMessageRepo.getMessagesPageGate!.complete();
        await pumpOrbitFrames(tester, count: 6);
      },
    );

    testWidgets(
      'all tab renders active friends before archived hydration completes',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        identityRepo.seed(testIdentity);

        final delayedContactRepo = _DelayedSpyContactRepository()
          ..seed([testContact]);
        delayedContactRepo.archivedContactsGate = Completer<void>();

        await tester.pumpWidget(
          buildOrbitWired(contactRepository: delayedContactRepo),
        );
        await pumpOrbitFrames(tester);

        expect(find.text('Bob'), findsWidgets);

        delayedContactRepo.archivedContactsGate!.complete();
        await pumpOrbitFrames(tester);
      },
    );

    testWidgets(
      'all tab renders active groups before archived hydration completes',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        identityRepo.seed(testIdentity);

        final delayedGroupRepo = _DelayedSpyGroupRepository()
          ..allGroupsGate = Completer<void>();
        await delayedGroupRepo.saveGroup(
          GroupModel(
            id: 'g-active',
            name: 'Alpha Group',
            type: GroupType.chat,
            topicName: 'topic-g-active',
            createdAt: DateTime.utc(2026, 3, 1),
            createdBy: 'peer-admin',
            myRole: GroupRole.admin,
          ),
        );

        await tester.pumpWidget(
          buildOrbitWired(groupRepository: delayedGroupRepo),
        );
        await pumpOrbitFrames(tester);

        expect(find.text('Alpha Group'), findsOneWidget);

        delayedGroupRepo.allGroupsGate!.complete();
        await pumpOrbitFrames(tester);
      },
    );

    testWidgets(
      'orbit entry keeps group long-press actions aligned with the shared conversation surface',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        identityRepo.seed(testIdentity);

        final orbitGroup = GroupModel(
          id: 'g-orbit-actions',
          name: 'Orbit Actions Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/g-orbit-actions',
          createdAt: DateTime.utc(2026, 3, 1),
          createdBy: 'peer-admin',
          myRole: GroupRole.admin,
        );
        await groupRepo.saveGroup(orbitGroup);
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'orbit-msg-1',
            groupId: orbitGroup.id,
            senderPeerId: 'peer-bob',
            senderUsername: 'Bob',
            text: 'Orbit action message',
            timestamp: DateTime.utc(2026, 3, 1, 12),
            createdAt: DateTime.utc(2026, 3, 1, 12),
          ),
        );

        await tester.pumpWidget(
          buildOrbitWired(
            groupRepository: groupRepo,
            groupMessageRepository: groupMsgRepo,
          ),
        );
        await pumpOrbitFrames(tester, count: 6);

        await tester.tap(find.text('Orbit Actions Group'));
        await pumpOrbitFrames(tester, count: 10);

        expect(find.byType(GroupConversationWired), findsOneWidget);
        expect(find.text('Orbit action message'), findsOneWidget);

        await tester.longPress(find.text('Orbit action message'));
        await pumpOrbitFrames(tester, count: 4);

        expect(find.byKey(MessageContextOverlay.overlayKey), findsOneWidget);
        expect(
          find.byKey(MessageContextOverlay.replyActionKey),
          findsOneWidget,
        );
        expect(find.byKey(MessageContextOverlay.copyActionKey), findsOneWidget);
      },
    );

    testWidgets(
      'orbit entry keeps group reaction inspection aligned with the shared conversation surface',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        identityRepo.seed(testIdentity);

        final reactionRepo = FakeReactionRepository();
        final orbitGroup = GroupModel(
          id: 'g-orbit-reactions',
          name: 'Orbit Reactions Group',
          type: GroupType.chat,
          topicName: '/mknoon/group/g-orbit-reactions',
          createdAt: DateTime.utc(2026, 3, 1),
          createdBy: 'peer-admin',
          myRole: GroupRole.admin,
        );
        await groupRepo.saveGroup(orbitGroup);
        await groupRepo.saveMember(
          GroupMember(
            groupId: orbitGroup.id,
            peerId: testIdentity.peerId,
            username: testIdentity.username,
            role: MemberRole.admin,
            joinedAt: DateTime.utc(2026, 3, 1, 10),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: orbitGroup.id,
            peerId: 'peer-bob',
            username: 'Bob',
            role: MemberRole.writer,
            joinedAt: DateTime.utc(2026, 3, 1, 10, 1),
          ),
        );
        await groupMsgRepo.saveMessage(
          GroupMessage(
            id: 'orbit-reaction-msg-1',
            groupId: orbitGroup.id,
            senderPeerId: 'peer-bob',
            senderUsername: 'Bob',
            text: 'Orbit reaction message',
            timestamp: DateTime.utc(2026, 3, 1, 12),
            createdAt: DateTime.utc(2026, 3, 1, 12),
          ),
        );
        await reactionRepo.saveReaction(
          MessageReaction(
            id: 'orbit-rxn-self',
            messageId: 'orbit-reaction-msg-1',
            emoji: '🔥',
            senderPeerId: testIdentity.peerId,
            timestamp: DateTime.utc(2026, 3, 1, 12, 1).toIso8601String(),
            createdAt: DateTime.utc(2026, 3, 1, 12, 1).toIso8601String(),
          ),
        );
        await reactionRepo.saveReaction(
          MessageReaction(
            id: 'orbit-rxn-bob',
            messageId: 'orbit-reaction-msg-1',
            emoji: '🔥',
            senderPeerId: 'peer-bob',
            timestamp: DateTime.utc(2026, 3, 1, 12, 2).toIso8601String(),
            createdAt: DateTime.utc(2026, 3, 1, 12, 2).toIso8601String(),
          ),
        );

        await tester.pumpWidget(
          buildOrbitWired(
            reactionRepository: reactionRepo,
            groupRepository: groupRepo,
            groupMessageRepository: groupMsgRepo,
          ),
        );
        await pumpOrbitFrames(tester, count: 6);

        await tester.tap(find.text('Orbit Reactions Group'));
        await pumpOrbitFrames(tester, count: 10);

        expect(find.byType(GroupConversationWired), findsOneWidget);
        expect(find.text('Orbit reaction message'), findsOneWidget);
        expect(find.textContaining('🔥', skipOffstage: false), findsWidgets);
        await tester.tap(find.textContaining('🔥', skipOffstage: false).last);
        await pumpOrbitFrames(tester, count: 4);

        expect(find.byKey(GroupReactionDetailsSheet.sheetKey), findsOneWidget);
        expect(
          find.byKey(GroupReactionDetailsSheet.rowKey(testIdentity.peerId)),
          findsOneWidget,
        );
        expect(
          find.byKey(GroupReactionDetailsSheet.rowKey('peer-bob')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'archived tab shows loading placeholders before archived data resolves',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        identityRepo.seed(testIdentity);

        final delayedContactRepo = _DelayedSpyContactRepository()
          ..seed([
            testContact.copyWith(
              isArchived: true,
              archivedAt: DateTime.utc(2026, 3, 1).toIso8601String(),
            ),
          ])
          ..archivedContactsGate = Completer<void>();
        final delayedGroupRepo = _DelayedSpyGroupRepository()
          ..allGroupsGate = Completer<void>();

        await tester.pumpWidget(
          buildOrbitWired(
            contactRepository: delayedContactRepo,
            groupRepository: delayedGroupRepo,
            initialFilterTab: 'archived',
          ),
        );
        await pumpOrbitFrames(tester);

        expect(
          find.byKey(const ValueKey('orbit-loading-row-0')),
          findsOneWidget,
        );
        expect(find.text('No archived friends yet'), findsNothing);

        delayedContactRepo.archivedContactsGate!.complete();
        delayedGroupRepo.allGroupsGate!.complete();
        await pumpOrbitFrames(tester);
      },
    );

    testWidgets(
      'archived tab swaps placeholders for archived rows when archived hydration completes',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        identityRepo.seed(testIdentity);

        final delayedContactRepo = _DelayedSpyContactRepository()
          ..seed([
            testContact.copyWith(
              isArchived: true,
              archivedAt: DateTime.utc(2026, 3, 1).toIso8601String(),
            ),
          ])
          ..archivedContactsGate = Completer<void>();

        await tester.pumpWidget(
          buildOrbitWired(
            contactRepository: delayedContactRepo,
            initialFilterTab: 'archived',
          ),
        );
        await pumpOrbitFrames(tester);

        expect(
          find.byKey(const ValueKey('orbit-loading-row-0')),
          findsOneWidget,
        );

        delayedContactRepo.archivedContactsGate!.complete();
        await pumpOrbitFrames(tester, count: 6);

        expect(find.byKey(const ValueKey('orbit-loading-row-0')), findsNothing);
        expect(find.text('Bob'), findsWidgets);
      },
    );

    testWidgets(
      'background archived hydration does not replace visible all-tab rows with placeholders',
      (tester) async {
        setLargeTestSurface(tester);
        suppressOverflowErrors();
        identityRepo.seed(testIdentity);

        final delayedContactRepo = _DelayedSpyContactRepository()
          ..seed([testContact])
          ..archivedContactsGate = Completer<void>();
        final delayedGroupRepo = _DelayedSpyGroupRepository()
          ..allGroupsGate = Completer<void>();

        await tester.pumpWidget(
          buildOrbitWired(
            contactRepository: delayedContactRepo,
            groupRepository: delayedGroupRepo,
          ),
        );
        await pumpOrbitFrames(tester);

        expect(find.text('Bob'), findsWidgets);
        expect(find.byKey(const ValueKey('orbit-loading-row-0')), findsNothing);

        delayedContactRepo.archivedContactsGate!.complete();
        delayedGroupRepo.allGroupsGate!.complete();
        await pumpOrbitFrames(tester);
      },
    );
  });
}

class _FakeGroupInviteListener extends GroupInviteListener {
  final Stream<GroupModel> _joinedStream;
  final Stream<PendingGroupInvite> _pendingStream;

  _FakeGroupInviteListener({
    required Stream<GroupModel> joinedStream,
    required Stream<PendingGroupInvite> pendingStream,
    required InMemoryPendingGroupInviteRepository pendingInviteRepo,
  }) : _joinedStream = joinedStream,
       _pendingStream = pendingStream,
       super(
         groupInviteStream: const Stream.empty(),
         groupRepo: _NoOpGroupRepo(),
         pendingInviteRepo: pendingInviteRepo,
         contactRepo: FakeContactRepository(),
         bridge: FakeBridge(),
         getOwnMlKemSecretKey: () async => null,
       );

  @override
  Stream<GroupModel> get groupJoinedStream => _joinedStream;

  @override
  Stream<PendingGroupInvite> get pendingInviteStream => _pendingStream;
}

class _RecordingNavigatorObserver extends NavigatorObserver {
  Route<dynamic>? lastPushedRoute;
  int pushCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);
    pushCount++;
    lastPushedRoute = route;
  }

  void reset() {
    lastPushedRoute = null;
    pushCount = 0;
  }
}

class _SpyContactRepository extends FakeContactRepository {
  int getActiveContactsCallCount = 0;
  int getArchivedContactsCallCount = 0;
  final Map<String, int> getContactCallCountByPeerId = {};

  @override
  Future<ContactModel?> getContact(String peerId) async {
    getContactCallCountByPeerId.update(
      peerId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    return super.getContact(peerId);
  }

  @override
  Future<List<ContactModel>> getActiveContacts() async {
    getActiveContactsCallCount++;
    return super.getActiveContacts();
  }

  @override
  Future<List<ContactModel>> getArchivedContacts() async {
    getArchivedContactsCallCount++;
    return super.getArchivedContacts();
  }

  void resetTracking() {
    getActiveContactsCallCount = 0;
    getArchivedContactsCallCount = 0;
    getContactCallCountByPeerId.clear();
  }
}

class _SpyMessageRepository extends InMemoryMessageRepository {
  final Map<String, int> getMessageCountForContactCallCountByPeerId = {};
  final Map<String, int> getLatestMessageForContactCallCountByPeerId = {};
  final Map<String, int> getUnreadCountForContactCallCountByPeerId = {};
  int getConversationThreadSummariesCallCount = 0;
  final Map<String, int> getConversationThreadSummaryCallCountByPeerId = {};

  @override
  Future<int> getMessageCountForContact(String contactPeerId) async {
    getMessageCountForContactCallCountByPeerId.update(
      contactPeerId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    return super.getMessageCountForContact(contactPeerId);
  }

  @override
  Future<ConversationMessage?> getLatestMessageForContact(
    String contactPeerId,
  ) async {
    getLatestMessageForContactCallCountByPeerId.update(
      contactPeerId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    return super.getLatestMessageForContact(contactPeerId);
  }

  @override
  Future<int> getUnreadCountForContact(String contactPeerId) async {
    getUnreadCountForContactCallCountByPeerId.update(
      contactPeerId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    return super.getUnreadCountForContact(contactPeerId);
  }

  @override
  Future<ConversationThreadSummary> getConversationThreadSummary(
    String contactPeerId,
  ) {
    getConversationThreadSummaryCallCountByPeerId.update(
      contactPeerId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    return super.getConversationThreadSummary(contactPeerId);
  }

  @override
  Future<Map<String, ConversationThreadSummary>> getConversationThreadSummaries(
    Iterable<String> contactPeerIds,
  ) {
    getConversationThreadSummariesCallCount++;
    return super.getConversationThreadSummaries(contactPeerIds);
  }

  void resetTracking() {
    getMessageCountForContactCallCountByPeerId.clear();
    getLatestMessageForContactCallCountByPeerId.clear();
    getUnreadCountForContactCallCountByPeerId.clear();
    getConversationThreadSummariesCallCount = 0;
    getConversationThreadSummaryCallCountByPeerId.clear();
  }
}

class _SpyGroupRepository extends InMemoryGroupRepository {
  int getActiveGroupsCallCount = 0;
  int getAllGroupsCallCount = 0;
  final Map<String, int> getGroupCallCountById = {};

  @override
  Future<List<GroupModel>> getActiveGroups() async {
    getActiveGroupsCallCount++;
    return super.getActiveGroups();
  }

  @override
  Future<List<GroupModel>> getAllGroups() async {
    getAllGroupsCallCount++;
    return super.getAllGroups();
  }

  @override
  Future<GroupModel?> getGroup(String id) async {
    getGroupCallCountById.update(id, (count) => count + 1, ifAbsent: () => 1);
    return super.getGroup(id);
  }

  void resetTracking() {
    getActiveGroupsCallCount = 0;
    getAllGroupsCallCount = 0;
    getGroupCallCountById.clear();
  }
}

class _SpyGroupMessageRepository extends InMemoryGroupMessageRepository {
  final Map<String, int> getLatestMessageCallCountByGroupId = {};
  final Map<String, int> getUnreadCountCallCountByGroupId = {};
  int getGroupThreadSummariesCallCount = 0;
  final Map<String, int> getGroupThreadSummaryCallCountByGroupId = {};

  @override
  Future<GroupMessage?> getLatestMessage(String groupId) async {
    getLatestMessageCallCountByGroupId.update(
      groupId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    return super.getLatestMessage(groupId);
  }

  @override
  Future<int> getUnreadCount(String groupId) async {
    getUnreadCountCallCountByGroupId.update(
      groupId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    return super.getUnreadCount(groupId);
  }

  @override
  Future<GroupThreadSummary> getGroupThreadSummary(String groupId) {
    getGroupThreadSummaryCallCountByGroupId.update(
      groupId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    return super.getGroupThreadSummary(groupId);
  }

  @override
  Future<Map<String, GroupThreadSummary>> getGroupThreadSummaries(
    Iterable<String> groupIds,
  ) {
    getGroupThreadSummariesCallCount++;
    return super.getGroupThreadSummaries(groupIds);
  }

  void resetTracking() {
    getLatestMessageCallCountByGroupId.clear();
    getUnreadCountCallCountByGroupId.clear();
    getGroupThreadSummariesCallCount = 0;
    getGroupThreadSummaryCallCountByGroupId.clear();
  }
}

class _DelayedSpyContactRepository extends _SpyContactRepository {
  Completer<void>? archivedContactsGate;

  @override
  Future<List<ContactModel>> getArchivedContacts() async {
    final gate = archivedContactsGate;
    if (gate != null) {
      await gate.future;
    }
    return super.getArchivedContacts();
  }
}

class _DelayedSpyMessageRepository extends _SpyMessageRepository {
  Completer<void>? markConversationAsReadGate;
  Completer<void>? getMessagesPageGate;

  @override
  Future<int> markConversationAsRead(String contactPeerId) async {
    final gate = markConversationAsReadGate;
    if (gate != null) {
      await gate.future;
    }
    return super.markConversationAsRead(contactPeerId);
  }

  @override
  Future<List<ConversationMessage>> getMessagesPage(
    String contactPeerId, {
    int limit = 50,
    String? beforeTimestamp,
  }) async {
    final gate = getMessagesPageGate;
    if (gate != null) {
      await gate.future;
    }
    return super.getMessagesPage(
      contactPeerId,
      limit: limit,
      beforeTimestamp: beforeTimestamp,
    );
  }
}

class _DelayedSpyGroupRepository extends _SpyGroupRepository {
  Completer<void>? allGroupsGate;

  @override
  Future<List<GroupModel>> getAllGroups() async {
    final gate = allGroupsGate;
    if (gate != null) {
      await gate.future;
    }
    return super.getAllGroups();
  }
}

class _FakeIntroductionListener extends IntroductionListener {
  final _introReceivedController =
      StreamController<IntroductionModel>.broadcast();
  final _introStatusController =
      StreamController<IntroductionModel>.broadcast();

  _FakeIntroductionListener({
    required super.introRepo,
    required super.contactRepo,
    required super.bridge,
    required super.messageRepo,
  }) : super(
         introductionStream: const Stream<ChatMessage>.empty(),
         getOwnMlKemSecretKey: () async => null,
         getOwnPeerId: () async => null,
       );

  @override
  Stream<IntroductionModel> get introReceivedStream =>
      _introReceivedController.stream;

  @override
  Stream<IntroductionModel> get introStatusChangedStream =>
      _introStatusController.stream;

  @override
  void emitIntroStatusChanged(IntroductionModel intro) =>
      _introStatusController.add(intro);
}

class _SequencedIntroductionRepository extends InMemoryIntroductionRepository {
  final Map<int, Completer<void>> pendingCallGates = {};
  final Map<int, List<IntroductionModel>> pendingResultsByCall = {};
  final Map<int, Completer<void>> _pendingCallWaiters = {};
  int _pendingCallCount = 0;

  @override
  Future<List<IntroductionModel>> getPendingIntroductionsForUser(
    String peerId,
  ) async {
    _pendingCallCount++;
    final callIndex = _pendingCallCount;
    _pendingCallWaiters.remove(callIndex)?.complete();
    final gate = pendingCallGates[callIndex];
    if (gate != null) {
      await gate.future;
    }
    final configured = pendingResultsByCall[callIndex];
    if (configured != null) {
      return List<IntroductionModel>.from(configured);
    }
    return super.getPendingIntroductionsForUser(peerId);
  }

  Future<void> waitForPendingCall(int callIndex) {
    if (_pendingCallCount >= callIndex) {
      return Future.value();
    }
    final waiter = _pendingCallWaiters.putIfAbsent(
      callIndex,
      () => Completer<void>(),
    );
    return waiter.future;
  }
}

class _BlockingIntroductionRepository extends InMemoryIntroductionRepository {
  Completer<void>? acceptGate;
  Completer<void>? passGate;
  int acceptedUpdates = 0;
  int passedUpdates = 0;

  @override
  Future<void> updateRecipientStatus(
    String id,
    IntroductionStatus status,
  ) async {
    await _maybeBlock(status);
    return super.updateRecipientStatus(id, status);
  }

  @override
  Future<void> updateIntroducedStatus(
    String id,
    IntroductionStatus status,
  ) async {
    await _maybeBlock(status);
    return super.updateIntroducedStatus(id, status);
  }

  Future<void> _maybeBlock(IntroductionStatus status) async {
    if (status == IntroductionStatus.accepted) {
      acceptedUpdates++;
      final gate = acceptGate;
      if (gate != null) {
        await gate.future;
      }
      return;
    }

    if (status == IntroductionStatus.passed) {
      passedUpdates++;
      final gate = passGate;
      if (gate != null) {
        await gate.future;
      }
    }
  }
}

/// Fake [ChatMessageListener] with controllable streams for testing.
///
/// Overrides [incomingMessageStream] and [contactUpdatedStream] with
/// broadcast StreamControllers that tests can push events into.
class _FakeChatMessageListener extends ChatMessageListener {
  final StreamController<ConversationMessage> _incomingController =
      StreamController.broadcast();
  final StreamController<ContactModel> _contactUpdateController =
      StreamController.broadcast();

  _FakeChatMessageListener({
    required super.messageRepo,
    required super.contactRepo,
  }) : super(chatMessageStream: const Stream.empty());

  @override
  Stream<ConversationMessage> get incomingMessageStream =>
      _incomingController.stream;

  @override
  Stream<ContactModel> get contactUpdatedStream =>
      _contactUpdateController.stream;

  void emitIncomingMessage(ConversationMessage msg) =>
      _incomingController.add(msg);

  @override
  void emitContactUpdate(ContactModel contact) =>
      _contactUpdateController.add(contact);
}

/// Fake [ContactRequestListener] with a controllable stream for testing.
///
/// Overrides [requestStream] with a broadcast StreamController that tests
/// can push [ContactRequestModel] events into.
class _FakeContactRequestListener extends ContactRequestListener {
  final _controller = StreamController<ContactRequestModel>.broadcast();

  _FakeContactRequestListener({
    required super.requestRepo,
    required super.contactRepo,
    required super.bridge,
  }) : super(
         contactRequestStream: const Stream.empty(),
         getOwnPeerId: () => '',
       );

  @override
  Stream<ContactRequestModel> get requestStream => _controller.stream;

  void emitRequest(ContactRequestModel request) => _controller.add(request);
}

/// Fake [GroupMessageListener] with a controllable stream for testing.
class _FakeGroupMessageListener extends GroupMessageListener {
  final Stream<GroupMessage> _externalStream;

  _FakeGroupMessageListener(this._externalStream)
    : super(groupRepo: _NoOpGroupRepo(), msgRepo: _NoOpMsgRepo());

  @override
  Stream<GroupMessage> get groupMessageStream => _externalStream;
}

class _NoOpGroupRepo implements GroupRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NoOpMsgRepo implements GroupMessageRepository {
  @override
  Future<int> transitionSendingToFailed() async => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
