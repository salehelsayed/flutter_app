import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/services/share_intent_model.dart';
import 'package:flutter_app/core/services/share_intent_service.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contact_request/domain/models/contact_request_model.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/home/presentation/screens/first_time_experience_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/presentation/screens/identity_choice_wired.dart';
import 'package:flutter_app/features/identity/presentation/startup_router.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/features/share/application/share_batch_delivery_coordinator.dart';
import 'package:flutter_app/features/share/application/share_target_selection.dart';
import 'package:flutter_app/features/share/presentation/screens/share_target_picker_wired.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';
import '../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '../../contact_request/domain/repositories/fake_contact_request_repository.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';

void main() {
  late FakeBridge bridge;
  late InMemoryContactRepository contactRepository;
  late FakeContactRequestRepository contactRequestRepository;
  late InMemoryMessageRepository messageRepository;
  late InMemoryMediaAttachmentRepository mediaAttachmentRepository;
  late InMemoryPostRepository postRepository;
  late InMemoryPostsPrivacySettingsRepository postsPrivacySettingsRepository;
  late FakeIdentityRepository identityRepository;
  late FakeP2PService p2pService;
  late FakeMediaFileManager mediaFileManager;
  late FakeSecureKeyStore secureKeyStore;
  late ChatMessageListener chatMessageListener;
  late InMemoryGroupRepository groupRepository;
  late InMemoryGroupMessageRepository groupMessageRepository;
  late GroupMessageListener groupMessageListener;
  late ImageProcessor imageProcessor;
  late AppShellController appShellController;
  late PendingPostTargetStore pendingPostTargetStore;

  final identityWithContacts = IdentityModel(
    peerId: 'my-peer-id-12345',
    publicKey: 'my-public-key',
    privateKey: 'my-private-key',
    mnemonic12:
        'one two three four five six seven eight nine ten eleven twelve',
    mlKemPublicKey: 'mlkem-public',
    mlKemSecretKey: 'mlkem-secret',
    username: 'Me',
    createdAt: '2026-03-09T08:00:00.000Z',
    updatedAt: '2026-03-09T08:00:00.000Z',
  );

  setUp(() {
    bridge = FakeBridge();
    bridge.responses['payload.sign'] = {'ok': true, 'signature': 'test-sig'};
    bridge.responses['payload.verify'] = {'ok': true, 'valid': true};
    bridge.responses['contactrequest.encrypt'] = {
      'ok': true,
      'ephemeralPublicKey': 'ephemeral-pk',
      'ciphertext': 'ciphertext',
      'nonce': 'nonce',
    };
    bridge.responses['identity.generate'] = {
      'ok': true,
      'identity': {
        'peerId': 'generated-peer-id',
        'publicKey': 'generated-public-key',
        'privateKey': 'generated-private-key',
        'mnemonic12':
            'alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu',
        'createdAt': '2026-03-09T08:00:00.000Z',
        'updatedAt': '2026-03-09T08:00:00.000Z',
      },
    };
    bridge.responses['mlkem.keygen'] = {
      'ok': true,
      'publicKey': 'generated-mlkem-public',
      'secretKey': 'generated-mlkem-secret',
    };

    contactRepository = InMemoryContactRepository();
    contactRequestRepository = FakeContactRequestRepository();
    messageRepository = InMemoryMessageRepository();
    mediaAttachmentRepository = InMemoryMediaAttachmentRepository();
    postRepository = InMemoryPostRepository();
    postsPrivacySettingsRepository = InMemoryPostsPrivacySettingsRepository();
    identityRepository = FakeIdentityRepository();
    p2pService = FakeP2PService();
    mediaFileManager = FakeMediaFileManager();
    secureKeyStore = FakeSecureKeyStore();
    groupRepository = InMemoryGroupRepository();
    groupMessageRepository = InMemoryGroupMessageRepository();
    groupMessageListener = GroupMessageListener(
      groupRepo: groupRepository,
      msgRepo: groupMessageRepository,
    );
    appShellController = AppShellController();
    pendingPostTargetStore = PendingPostTargetStore();
    chatMessageListener = ChatMessageListener(
      chatMessageStream: const Stream<ChatMessage>.empty(),
      messageRepo: messageRepository,
      contactRepo: contactRepository,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => null,
    );
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

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (methodCall) async {
            if (methodCall.method == 'getApplicationDocumentsDirectory') {
              return '/tmp/test_docs';
            }
            return null;
          },
        );
  });

  tearDown(() {
    postsPrivacySettingsRepository.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          null,
        );
  });

  Future<void> pumpFrames(WidgetTester tester, {int count = 12}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Widget buildSharePickerApp({
    required ShareIntent shareIntent,
    ShareBatchDeliveryCoordinator? batchShareCoordinator,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ShareTargetPickerWired(
        shareIntent: shareIntent,
        identityRepo: identityRepository,
        contactRepository: contactRepository,
        messageRepository: messageRepository,
        mediaAttachmentRepository: mediaAttachmentRepository,
        chatMessageListener: chatMessageListener,
        bridge: bridge,
        p2pService: p2pService,
        mediaFileManager: mediaFileManager,
        imageProcessor: imageProcessor,
        groupRepository: groupRepository,
        groupMessageRepository: groupMessageRepository,
        groupMessageListener: groupMessageListener,
        batchShareCoordinator: batchShareCoordinator,
      ),
    );
  }

  StartupRouter buildStartupRouter({
    required ContactRequestListener contactRequestListener,
    ShareIntentService? shareIntentService,
    Future<void> Function()? ensureRuntimeServicesReady,
  }) {
    return StartupRouter(
      repository: identityRepository,
      contactRepository: contactRepository,
      contactRequestRepository: contactRequestRepository,
      contactRequestListener: contactRequestListener,
      messageRepository: messageRepository,
      postRepository: postRepository,
      mediaAttachmentRepository: mediaAttachmentRepository,
      chatMessageListener: chatMessageListener,
      bridge: bridge,
      p2pService: p2pService,
      mediaFileManager: mediaFileManager,
      secureKeyStore: secureKeyStore,
      imageProcessor: imageProcessor,
      shareIntentService: shareIntentService,
      ensureRuntimeServicesReady: ensureRuntimeServicesReady,
      groupRepository: groupRepository,
      groupMessageRepository: groupMessageRepository,
      groupMessageListener: groupMessageListener,
      appShellController: appShellController,
      pendingPostTargetStore: pendingPostTargetStore,
      postsPrivacySettingsRepository: postsPrivacySettingsRepository,
    );
  }

  testWidgets(
    '6a: share text can target multiple selected recipients from the picker',
    (tester) async {
      identityRepository.seed(identityWithContacts);
      contactRepository.addTestContact(_makeContact('peer-alice', 'Alice'));
      await groupRepository.saveGroup(
        _makeGroup('group-chat', 'Writers', GroupType.chat, GroupRole.admin),
      );
      final coordinator = _RecordingBatchCoordinator.failAll();

      await tester.pumpWidget(
        buildSharePickerApp(
          shareIntent: const ShareIntent(
            type: ShareIntentType.text,
            text: 'share this',
          ),
          batchShareCoordinator: coordinator,
        ),
      );
      await pumpFrames(tester);

      await tester.tap(find.byKey(const ValueKey('share-contact-peer-alice')));
      await tester.tap(find.byKey(const ValueKey('share-group-group-chat')));
      await tester.pump();
      await tester.tap(find.text('Send'));
      await pumpFrames(tester);

      expect(coordinator.deliverCallCount, 1);
      expect(coordinator.lastShareIntent?.text, 'share this');
      expect(coordinator.lastTargets.map((target) => target.key).toList(), [
        ShareTargetSelection.contact(_makeContact('peer-alice', 'Alice')).key,
        ShareTargetSelection.group(
          _makeGroup('group-chat', 'Writers', GroupType.chat, GroupRole.admin),
        ).key,
      ]);
    },
  );

  testWidgets(
    '6b: share image keeps file payload when send is confirmed from the picker',
    (tester) async {
      identityRepository.seed(identityWithContacts);
      contactRepository.addTestContact(_makeContact('peer-alice', 'Alice'));
      final coordinator = _RecordingBatchCoordinator.failAll();
      final tempDir = Directory.systemTemp.createTempSync('share_smoke_image_');
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final sharedFile = File('${tempDir.path}/shared.jpg')
        ..writeAsStringSync('image');

      await tester.pumpWidget(
        buildSharePickerApp(
          shareIntent: ShareIntent(
            type: ShareIntentType.files,
            filePaths: [sharedFile.path],
          ),
          batchShareCoordinator: coordinator,
        ),
      );
      await pumpFrames(tester);

      await tester.tap(find.byKey(const ValueKey('share-contact-peer-alice')));
      await tester.pump();
      await tester.tap(find.text('Send'));
      await pumpFrames(tester);

      expect(coordinator.deliverCallCount, 1);
      expect(coordinator.lastShareIntent?.filePaths, [sharedFile.path]);
    },
  );

  testWidgets('6e: share URL keeps URL text in the picker delivery request', (
    tester,
  ) async {
    identityRepository.seed(identityWithContacts);
    contactRepository.addTestContact(_makeContact('peer-alice', 'Alice'));
    final coordinator = _RecordingBatchCoordinator.failAll();

    await tester.pumpWidget(
      buildSharePickerApp(
        shareIntent: const ShareIntent(
          type: ShareIntentType.text,
          text: 'https://mknoon.app/post/123',
        ),
        batchShareCoordinator: coordinator,
      ),
    );
    await pumpFrames(tester);

    await tester.tap(find.byKey(const ValueKey('share-contact-peer-alice')));
    await tester.pump();
    await tester.tap(find.text('Send'));
    await pumpFrames(tester);

    expect(coordinator.lastShareIntent?.text, 'https://mknoon.app/post/123');
  });

  testWidgets('6f: share multiple images preserves all file paths', (
    tester,
  ) async {
    identityRepository.seed(identityWithContacts);
    contactRepository.addTestContact(_makeContact('peer-alice', 'Alice'));
    final coordinator = _RecordingBatchCoordinator.failAll();
    final tempDir = Directory.systemTemp.createTempSync('share_smoke_multi_');
    addTearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });
    final first = File('${tempDir.path}/one.jpg')..writeAsStringSync('one');
    final second = File('${tempDir.path}/two.jpg')..writeAsStringSync('two');

    await tester.pumpWidget(
      buildSharePickerApp(
        shareIntent: ShareIntent(
          type: ShareIntentType.files,
          filePaths: [first.path, second.path],
        ),
        batchShareCoordinator: coordinator,
      ),
    );
    await pumpFrames(tester);

    await tester.tap(find.byKey(const ValueKey('share-contact-peer-alice')));
    await tester.pump();
    await tester.tap(find.text('Send'));
    await pumpFrames(tester);

    expect(coordinator.lastShareIntent?.filePaths, [first.path, second.path]);
  });

  testWidgets(
    '6g: cold start with identity and contacts opens the picker directly',
    (tester) async {
      identityRepository.seed(identityWithContacts);
      contactRepository.addTestContact(_makeContact('peer-alice', 'Alice'));
      final shareIntentService = ShareIntentService(resetShareIntent: () {});
      await shareIntentService.bufferIntent(
        const ShareIntent(type: ShareIntentType.text, text: 'cold start'),
      );
      final requestListener = ContactRequestListener(
        contactRequestStream: const Stream<ChatMessage>.empty(),
        requestRepo: contactRequestRepository,
        contactRepo: contactRepository,
        bridge: bridge,
        getOwnPeerId: () => identityWithContacts.peerId,
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: buildStartupRouter(
            contactRequestListener: requestListener,
            shareIntentService: shareIntentService,
          ),
        ),
      );
      await pumpFrames(tester, count: 20);

      expect(find.text('Share with...'), findsOneWidget);
      expect(find.text('cold start'), findsOneWidget);
    },
  );

  testWidgets(
    '6g1: cold start share opens picker without waiting for deferred runtime startup',
    (tester) async {
      identityRepository.seed(
        IdentityModel(
          peerId: identityWithContacts.peerId,
          publicKey: identityWithContacts.publicKey,
          privateKey: identityWithContacts.privateKey,
          mnemonic12: identityWithContacts.mnemonic12,
          mlKemPublicKey: null,
          mlKemSecretKey: null,
          username: identityWithContacts.username,
          createdAt: identityWithContacts.createdAt,
          updatedAt: identityWithContacts.updatedAt,
        ),
      );
      contactRepository.addTestContact(_makeContact('peer-alice', 'Alice'));
      final runtimeReady = Completer<void>();
      final shareIntentService = ShareIntentService(resetShareIntent: () {});
      await shareIntentService.bufferIntent(
        const ShareIntent(type: ShareIntentType.text, text: 'direct share'),
      );
      final requestListener = ContactRequestListener(
        contactRequestStream: const Stream<ChatMessage>.empty(),
        requestRepo: contactRequestRepository,
        contactRepo: contactRepository,
        bridge: bridge,
        getOwnPeerId: () => identityWithContacts.peerId,
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: buildStartupRouter(
            contactRequestListener: requestListener,
            shareIntentService: shareIntentService,
            ensureRuntimeServicesReady: () => runtimeReady.future,
          ),
        ),
      );
      await pumpFrames(tester, count: 20);

      expect(find.text('Share with...'), findsOneWidget);
      expect(find.text('direct share'), findsOneWidget);
    },
  );

  testWidgets(
    '6g2: cold start with needsIdentity shows picker only after onboarding and first contact',
    (tester) async {
      final requestController =
          StreamController<ContactRequestModel>.broadcast();
      addTearDown(requestController.close);
      final requestListener = _FakeContactRequestListener(
        requestStream: requestController.stream,
      );
      final shareIntentService = ShareIntentService(resetShareIntent: () {});
      await shareIntentService.bufferIntent(
        const ShareIntent(type: ShareIntentType.text, text: 'after onboarding'),
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: buildStartupRouter(
            contactRequestListener: requestListener,
            shareIntentService: shareIntentService,
          ),
        ),
      );
      await pumpFrames(tester, count: 20);

      expect(find.byType(IdentityChoiceWired), findsOneWidget);
      expect(find.text('Share with...'), findsNothing);

      await tester.tap(find.text("I'm new here"));
      await pumpFrames(tester, count: 30);

      expect(find.byType(FirstTimeExperienceWired), findsOneWidget);
      expect(find.text('Share with...'), findsNothing);

      final request = ContactRequestModel(
        peerId: 'peer-generated-friend',
        publicKey: 'friend-pub',
        rendezvous: '/p2p-circuit/relay',
        username: 'Charlie',
        signature: 'friend-sig',
        receivedAt: DateTime.now().toUtc().toIso8601String(),
      );
      contactRequestRepository.seed([request]);
      requestController.add(request);
      await pumpFrames(tester);

      await tester.tap(find.text('Accept'));
      await pumpFrames(tester, count: 30);

      expect(find.text('Share with...'), findsOneWidget);
      expect(find.text('after onboarding'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
    },
  );

  testWidgets(
    '6g3: cold start with identity and no contacts shows picker only after first contact',
    (tester) async {
      identityRepository.seed(identityWithContacts);
      final requestController =
          StreamController<ContactRequestModel>.broadcast();
      addTearDown(requestController.close);
      final requestListener = _FakeContactRequestListener(
        requestStream: requestController.stream,
      );
      final shareIntentService = ShareIntentService(resetShareIntent: () {});
      await shareIntentService.bufferIntent(
        const ShareIntent(
          type: ShareIntentType.text,
          text: 'after first contact',
        ),
      );

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: buildStartupRouter(
            contactRequestListener: requestListener,
            shareIntentService: shareIntentService,
          ),
        ),
      );
      await pumpFrames(tester, count: 20);

      expect(find.byType(FirstTimeExperienceWired), findsOneWidget);
      expect(find.text('Share with...'), findsNothing);

      final request = ContactRequestModel(
        peerId: 'peer-new-friend',
        publicKey: 'friend-pub',
        rendezvous: '/p2p-circuit/relay',
        username: 'Dana',
        signature: 'friend-sig',
        receivedAt: DateTime.now().toUtc().toIso8601String(),
      );
      contactRequestRepository.seed([request]);
      requestController.add(request);
      await pumpFrames(tester);

      await tester.tap(find.text('Accept'));
      await pumpFrames(tester, count: 30);

      expect(find.text('Share with...'), findsOneWidget);
      expect(find.text('after first contact'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
    },
  );

  testWidgets('6h: share when no targets exist shows empty state', (
    tester,
  ) async {
    identityRepository.seed(identityWithContacts);

    await tester.pumpWidget(
      buildSharePickerApp(
        shareIntent: const ShareIntent(
          type: ShareIntentType.text,
          text: 'lonely share',
        ),
      ),
    );
    await pumpFrames(tester);

    expect(find.text('No contacts or groups yet'), findsOneWidget);
  });

  testWidgets(
    '6i: announcement group where user is not admin is excluded from picker',
    (tester) async {
      identityRepository.seed(identityWithContacts);
      await groupRepository.saveGroup(
        _makeGroup(
          'announce-member',
          'Announcements',
          GroupType.announcement,
          GroupRole.member,
        ),
      );
      await groupRepository.saveGroup(
        _makeGroup(
          'announce-admin',
          'Admin Announcements',
          GroupType.announcement,
          GroupRole.admin,
        ),
      );

      await tester.pumpWidget(
        buildSharePickerApp(
          shareIntent: const ShareIntent(
            type: ShareIntentType.text,
            text: 'group filter',
          ),
        ),
      );
      await pumpFrames(tester);

      expect(find.text('Announcements'), findsNothing);
      expect(find.text('Admin Announcements'), findsOneWidget);
    },
  );
}

ContactModel _makeContact(String peerId, String username) {
  return ContactModel(
    peerId: peerId,
    publicKey: 'pk-$peerId',
    rendezvous: '/dns4/relay/tcp/443',
    username: username,
    signature: 'sig-$peerId',
    scannedAt: '2026-03-09T08:00:00.000Z',
  );
}

GroupModel _makeGroup(String id, String name, GroupType type, GroupRole role) {
  return GroupModel(
    id: id,
    name: name,
    type: type,
    topicName: 'topic-$id',
    createdAt: DateTime.parse('2026-03-09T08:00:00.000Z'),
    createdBy: 'me',
    myRole: role,
  );
}

class _RecordingBatchCoordinator implements ShareBatchDeliveryCoordinator {
  final ShareBatchDeliveryResult Function(List<ShareTargetSelection>) _builder;
  int deliverCallCount = 0;
  ShareIntent? lastShareIntent;
  List<ShareTargetSelection> lastTargets = const [];

  _RecordingBatchCoordinator({required ShareBatchDeliveryResult result})
    : _builder = ((_) => result);

  _RecordingBatchCoordinator.failAll()
    : _builder = ((targets) {
        return ShareBatchDeliveryResult(
          results: targets
              .map(
                (target) => ShareBatchTargetResult(
                  target: target,
                  status: ShareBatchTargetStatus.failed,
                  detail: 'Share failed.',
                ),
              )
              .toList(growable: false),
        );
      });

  @override
  Future<ShareBatchDeliveryResult> deliver({
    required ShareIntent shareIntent,
    required List<ShareTargetSelection> targets,
  }) async {
    deliverCallCount++;
    lastShareIntent = shareIntent;
    lastTargets = List<ShareTargetSelection>.from(targets);
    return _builder(targets);
  }
}

class _FakeContactRequestListener extends ContactRequestListener {
  final Stream<ContactRequestModel> _overrideStream;

  _FakeContactRequestListener({
    required Stream<ContactRequestModel> requestStream,
  }) : _overrideStream = requestStream,
       super(
         contactRequestStream: const Stream<ChatMessage>.empty(),
         requestRepo: FakeContactRequestRepository(),
         contactRepo: InMemoryContactRepository(),
         bridge: FakeBridge(),
         getOwnPeerId: () => '',
       );

  @override
  Stream<ContactRequestModel> get requestStream => _overrideStream;
}
