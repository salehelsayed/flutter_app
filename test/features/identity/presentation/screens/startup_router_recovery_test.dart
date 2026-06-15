import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/config/startup_config.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_transfer_flow.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_authority_repository_impl.dart';
import 'package:flutter_app/features/account_migration/domain/models/account_migration_authority_state.dart';
import 'package:flutter_app/features/account_migration/presentation/screens/account_migration_blocked_screen.dart';
import 'package:flutter_app/features/account_migration/presentation/screens/account_migration_journey_wired.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_wired.dart';
import 'package:flutter_app/features/home/presentation/screens/first_time_experience_wired.dart';
import 'package:flutter_app/features/identity/presentation/screens/identity_choice_wired.dart';
import 'package:flutter_app/features/identity/presentation/startup_router.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../../core/bridge/fake_bridge.dart';
import '../../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/fake_media_file_manager.dart';
import '../../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../../shared/fakes/in_memory_message_repository.dart';
import '../../../../shared/fakes/in_memory_post_repository.dart';
import '../../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '../../../contact_request/domain/repositories/fake_contact_request_repository.dart';
import '../../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../../identity/domain/repositories/fake_identity_repository.dart';

const _storedMnemonic =
    'abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon abandon about';

void main() {
  late bool previousDeferredStartupMode;
  late FakeIdentityRepository identityRepository;
  late FakeContactRepository contactRepository;
  late FakeContactRequestRepository contactRequestRepository;
  late ContactRequestListener contactRequestListener;
  late InMemoryMessageRepository messageRepository;
  late InMemoryPostRepository postRepository;
  late InMemoryMediaAttachmentRepository mediaAttachmentRepository;
  late ChatMessageListener chatMessageListener;
  late FakeBridge bridge;
  late FakeP2PService p2pService;
  late FakeMediaFileManager mediaFileManager;
  late FakeSecureKeyStore secureKeyStore;
  late ImageProcessor imageProcessor;
  late AppShellController appShellController;
  late PendingPostTargetStore pendingPostTargetStore;
  late InMemoryPostsPrivacySettingsRepository postsPrivacySettingsRepository;

  setUp(() {
    previousDeferredStartupMode = StartupConfig.deferredStartupMode;
    StartupConfig.deferredStartupMode = true;

    identityRepository = FakeIdentityRepository();
    contactRepository = FakeContactRepository();
    contactRequestRepository = FakeContactRequestRepository();
    messageRepository = InMemoryMessageRepository();
    postRepository = InMemoryPostRepository();
    mediaAttachmentRepository = InMemoryMediaAttachmentRepository();
    bridge = FakeBridge(
      initialResponses: {
        'identity.restore': {
          'ok': true,
          'identity': {
            'peerId': '12D3KooWRecovered',
            'publicKey': 'restored-public-key',
            'privateKey': 'restored-private-key',
            'mnemonic12': _storedMnemonic,
            'createdAt': '2026-03-24T08:00:00.000Z',
            'updatedAt': '2026-03-24T08:00:00.000Z',
          },
        },
        'mlkem.keygen': {
          'ok': true,
          'publicKey': 'generated-mlkem-public',
          'secretKey': 'generated-mlkem-secret',
        },
        'payload.sign': {'ok': true, 'signature': 'test-signature'},
      },
    );
    p2pService = FakeP2PService();
    mediaFileManager = FakeMediaFileManager();
    secureKeyStore = FakeSecureKeyStore();
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
    appShellController = AppShellController();
    pendingPostTargetStore = PendingPostTargetStore();
    postsPrivacySettingsRepository = InMemoryPostsPrivacySettingsRepository();

    contactRequestListener = ContactRequestListener(
      contactRequestStream: const Stream<ChatMessage>.empty(),
      requestRepo: contactRequestRepository,
      contactRepo: contactRepository,
      bridge: bridge,
      getOwnPeerId: () => '12D3KooWRecovered',
    );

    chatMessageListener = ChatMessageListener(
      chatMessageStream: const Stream<ChatMessage>.empty(),
      messageRepo: messageRepository,
      contactRepo: contactRepository,
      bridge: bridge,
      getOwnMlKemSecretKey: () async => 'generated-mlkem-secret',
    );
  });

  tearDown(() {
    StartupConfig.deferredStartupMode = previousDeferredStartupMode;
    postsPrivacySettingsRepository.dispose();
  });

  Future<void> pumpFrames(WidgetTester tester, {int count = 20}) async {
    for (var i = 0; i < count; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Widget buildRouterApp({
    AccountMigrationReceiverStartFn? accountMigrationStartReceiver,
    AccountMigrationReceiverEvents? accountMigrationReceiverEvents,
    Future<void> Function()? onAccountMigrationReceiverActivated,
  }) {
    return MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: StartupRouter(
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
        appShellController: appShellController,
        pendingPostTargetStore: pendingPostTargetStore,
        postsPrivacySettingsRepository: postsPrivacySettingsRepository,
        accountMigrationStartReceiver: accountMigrationStartReceiver,
        accountMigrationReceiverEvents: accountMigrationReceiverEvents,
        onAccountMigrationReceiverActivated:
            onAccountMigrationReceiverActivated,
      ),
    );
  }

  Future<void> saveAuthority(
    AccountMigrationAuthorityState state, {
    String? accountPeerId,
  }) {
    return SecureKeyStoreAccountMigrationAuthorityRepository(
      secureKeyStore: secureKeyStore,
    ).saveAuthority(
      AccountMigrationAuthorityRecord(
        state: state,
        accountPeerId: accountPeerId,
      ),
    );
  }

  testWidgets(
    'needsIdentity ignores surviving secure-store mnemonic and stays on onboarding',
    (tester) async {
      await secureKeyStore.write('identity_mnemonic12', _storedMnemonic);

      await tester.pumpWidget(buildRouterApp());
      await pumpFrames(tester);

      expect(find.byType(IdentityChoiceWired), findsOneWidget);
      expect(find.byType(FirstTimeExperienceWired), findsNothing);
      expect(identityRepository.saveIdentityCallCount, 0);
      expect(bridge.commandLog, isNot(contains('identity.restore')));
      expect(bridge.commandLog, isNot(contains('mlkem.keygen')));
      expect(p2pService.startNodeCallCount, 0);
    },
  );

  testWidgets('needsIdentity without surviving mnemonic stays on onboarding', (
    tester,
  ) async {
    await tester.pumpWidget(buildRouterApp());
    await pumpFrames(tester);

    expect(find.byType(IdentityChoiceWired), findsOneWidget);
    expect(find.byType(FirstTimeExperienceWired), findsNothing);
    expect(identityRepository.saveIdentityCallCount, 0);
    expect(bridge.commandLog, isNot(contains('identity.restore')));
    expect(p2pService.startNodeCallCount, 0);
  });

  testWidgets(
    'import staging authority blocks onboarding and P2P before identity exists',
    (tester) async {
      await saveAuthority(
        AccountMigrationAuthorityState.migrationImportStaging,
      );

      await tester.pumpWidget(buildRouterApp());
      await pumpFrames(tester);

      expect(find.byType(AccountMigrationBlockedScreen), findsOneWidget);
      expect(find.byType(IdentityChoiceWired), findsNothing);
      expect(find.byType(FirstTimeExperienceWired), findsNothing);
      expect(find.byType(FeedWired), findsNothing);
      expect(identityRepository.saveIdentityCallCount, 0);
      expect(bridge.commandLog, isNot(contains('mlkem.keygen')));
      expect(p2pService.startNodeCallCount, 0);
    },
  );

  testWidgets(
    'migrated-out identity routes to blocked screen without normal UI or P2P',
    (tester) async {
      const peerId = '12D3KooWMigratedOut';
      identityRepository.seed(
        FakeIdentityRepository.makeIdentity(peerId: peerId),
      );
      contactRepository.seed([
        ContactModel(
          peerId: 'peer-existing',
          publicKey: 'pk-existing',
          rendezvous: '/dns4/rendezvous.example.com/tcp/4001/p2p/peer-existing',
          username: 'Existing',
          signature: 'sig-existing',
          scannedAt: '2026-04-03T12:00:00.000Z',
        ),
      ]);
      await saveAuthority(
        AccountMigrationAuthorityState.migratedOut,
        accountPeerId: peerId,
      );

      await tester.pumpWidget(buildRouterApp());
      await pumpFrames(tester);

      expect(find.byType(AccountMigrationBlockedScreen), findsOneWidget);
      expect(find.byType(FeedWired), findsNothing);
      expect(find.byType(FirstTimeExperienceWired), findsNothing);
      expect(find.byType(IdentityChoiceWired), findsNothing);
      expect(bridge.commandLog, isNot(contains('mlkem.keygen')));
      expect(p2pService.startNodeCallCount, 0);
    },
  );

  testWidgets(
    'active authority preserves returning-user startup and starts P2P',
    (tester) async {
      const peerId = '12D3KooWActive';
      identityRepository.seed(
        FakeIdentityRepository.makeIdentity(
          peerId: peerId,
          mlKemPublicKey: 'existing-mlkem-public',
          mlKemSecretKey: 'existing-mlkem-secret',
        ),
      );
      contactRepository.seed([
        ContactModel(
          peerId: 'peer-existing',
          publicKey: 'pk-existing',
          rendezvous: '/dns4/rendezvous.example.com/tcp/4001/p2p/peer-existing',
          username: 'Existing',
          signature: 'sig-existing',
          scannedAt: '2026-04-03T12:00:00.000Z',
        ),
      ]);
      await saveAuthority(
        AccountMigrationAuthorityState.active,
        accountPeerId: peerId,
      );

      await tester.pumpWidget(buildRouterApp());
      await pumpFrames(tester);

      expect(find.byType(AccountMigrationBlockedScreen), findsNothing);
      expect(p2pService.startNodeCallCount, 1);
    },
  );

  testWidgets(
    'active authority repairs identity when ML-KEM secret is missing',
    (tester) async {
      const peerId = '12D3KooWActiveMissingMlKemSecret';
      identityRepository.seed(
        FakeIdentityRepository.makeIdentity(
          peerId: peerId,
          mlKemPublicKey: 'existing-mlkem-public',
        ),
      );
      await saveAuthority(
        AccountMigrationAuthorityState.active,
        accountPeerId: peerId,
      );

      await tester.pumpWidget(buildRouterApp());
      await pumpFrames(tester);

      expect(bridge.commandLog, contains('mlkem.keygen'));
      expect(identityRepository.saveIdentityCallCount, 1);
      expect(
        identityRepository.lastSavedIdentity?.mlKemPublicKey,
        'generated-mlkem-public',
      );
      expect(
        identityRepository.lastSavedIdentity?.mlKemSecretKey,
        'generated-mlkem-secret',
      );
      expect(p2pService.startNodeCallCount, 1);
    },
  );

  testWidgets(
    'new-phone migration activation reruns startup and routes imported account',
    (tester) async {
      final receiverEvents =
          StreamController<AccountMigrationReceiverEvent>.broadcast();
      String? receiverSessionId;
      var activationCallbackCalled = false;
      addTearDown(receiverEvents.close);

      await tester.pumpWidget(
        buildRouterApp(
          accountMigrationStartReceiver: (output) async {
            receiverSessionId = output.payload.sessionId;
            return const AccountMigrationReceiverStartResult.started();
          },
          accountMigrationReceiverEvents: receiverEvents.stream,
          onAccountMigrationReceiverActivated: () async {
            activationCallbackCalled = true;
            identityRepository.seed(
              FakeIdentityRepository.makeIdentity(
                peerId: '12D3KooWImported',
                mlKemPublicKey: 'imported-mlkem-public',
                mlKemSecretKey: 'imported-mlkem-secret',
              ),
            );
            contactRepository.seed([
              ContactModel(
                peerId: 'peer-imported',
                publicKey: 'pk-imported',
                rendezvous:
                    '/dns4/rendezvous.example.com/tcp/4001/p2p/peer-imported',
                username: 'Imported',
                signature: 'sig-imported',
                scannedAt: '2026-04-03T12:00:00.000Z',
              ),
            ]);
            await saveAuthority(
              AccountMigrationAuthorityState.active,
              accountPeerId: '12D3KooWImported',
            );
          },
        ),
      );
      await pumpFrames(tester);

      await tester.tap(find.text('Move from old phone'));
      await pumpFrames(tester);

      expect(find.byType(AccountMigrationJourneyWired), findsOneWidget);
      expect(receiverSessionId, isNotNull);

      receiverEvents.add(
        AccountMigrationReceiverEvent.activated(sessionId: receiverSessionId!),
      );
      await pumpFrames(tester);

      expect(activationCallbackCalled, isTrue);
      expect(find.byType(FeedWired), findsOneWidget);
      expect(find.byType(AccountMigrationJourneyWired), findsNothing);
      expect(find.byType(IdentityChoiceWired), findsNothing);
      expect(p2pService.startNodeCallCount, 1);
    },
  );
}
