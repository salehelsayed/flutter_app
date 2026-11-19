import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/app/bootstrap/active_identity_reporter_bootstrap.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/private_media_protection_coordinator.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contact_request/application/contact_request_listener.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/conversation/presentation/screens/direct_conversation_route_authority.dart';
import 'package:flutter_app/features/feed/application/app_shell_controller.dart';
import 'package:flutter_app/features/feed/domain/models/app_shell_tab.dart';
import 'package:flutter_app/features/feed/presentation/screens/feed_wired.dart';
import 'package:flutter_app/features/feed/presentation/widgets/letter_card_system.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/posts/application/pending_post_target_store.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

import '../../../../core/secure_storage/fake_secure_key_store.dart';
import '../../../../core/services/fake_p2p_service.dart';
import '../../../../shared/fakes/fake_just_audio.dart';
import '../../../../shared/fakes/fake_media_file_manager.dart';
import '../../../../shared/fakes/in_memory_feed_cleared_repository.dart';
import '../../../../shared/fakes/in_memory_post_repository.dart';
import '../../../../shared/fakes/in_memory_posts_privacy_settings_repository.dart';
import '../../../../shared/fixtures/media_repository_real_db_fixture.dart';
import '../../../contact_request/domain/repositories/fake_contact_request_repository.dart';
import '../../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../../groups/application/b6_daily_activity_test_support.dart';
import '../../../identity/domain/repositories/fake_identity_repository.dart';

const _budget = Duration(seconds: 3);
const _text = 'A fresh weekly direct message';

Future<T> _io<T>(WidgetTester tester, Future<T> Function() action) async =>
    (await tester.runAsync(() => action().timeout(_budget))) as T;

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() ready,
) async {
  final elapsed = Stopwatch()..start();
  while (!ready() && elapsed.elapsed < _budget) {
    await _io(tester, () => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 100)).timeout(_budget);
  }
  expect(ready(), isTrue, reason: 'the original three-second fixture bound');
}

class _DocumentsPath extends PathProviderPlatform {
  _DocumentsPath(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
  @override
  Future<String?> getTemporaryPath() async => path;
  @override
  Future<String?> getApplicationSupportPath() async => path;
}

class _CheckpointBridge extends B6ActivityBridge {
  _CheckpointBridge() {
    final now = DateTime.now().millisecondsSinceEpoch;
    activityAnswer = (request, revision) async {
      if (request['op'] != 'weeklyProjection' && request['op'] != 'markWeekly') {
        return B6ActivityBridge.reply(request, revision);
      }
      // Controlled native protocol response; this fixture does not implement
      // or claim to test Go's Berlin calendar.
      return jsonEncode({
        'ok': true,
        'data': {
          'revision': revision,
          'consentEpoch': request['consentEpoch'],
          if (request['op'] == 'markWeekly') 'accepted': true,
          if (request['op'] == 'weeklyProjection')
            'weekly': {
              'week': '2026-W47',
              'startUnixMillis': now - const Duration(days: 1).inMilliseconds,
              'endUnixMillis': now + const Duration(days: 6).inMilliseconds,
              'kinds': <String>[],
              'acknowledged': <Object>[],
            },
        },
      });
    };
  }

  final sendTaskEnded = Completer<void>();
  int sendTaskBegins = 0;

  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    if (request['cmd'] == 'bg:begin') {
      sendTaskBegins++;
      return 'b15-weekly-ui-send';
    }
    if (request['cmd'] == 'bg:end') {
      expect(request['payload']['taskId'], 'b15-weekly-ui-send');
      if (!sendTaskEnded.isCompleted) sendTaskEnded.complete();
      return 'ok';
    }
    return super.send(message);
  }
}

void main() {
  testWidgets(
    'B15DW-001 real Feed route send persists admitted weekly initial',
    (tester) async {
      installFakeJustAudioPlatform();
      final previousFlowLogging = flowEventLoggingEnabled;
      final previousPathProvider = PathProviderPlatform.instance;
      final messenger = tester.binding.defaultBinaryMessenger;
      flowEventLoggingEnabled = false;
      messenger.setMockMessageHandler(
        kPrivateMediaProtectionEventChannel,
        (_) async => const StandardMethodCodec().encodeSuccessEnvelope(null),
      );
      addTearDown(() {
        flowEventLoggingEnabled = previousFlowLogging;
        PathProviderPlatform.instance = previousPathProvider;
        messenger.setMockMessageHandler(kPrivateMediaProtectionEventChannel, null);
      });

      final directory = await _io(
        tester,
        () => Directory.systemTemp.createTemp('b15-direct-weekly-red-'),
      );
      addTearDown(() => _io(tester, () => directory.delete(recursive: true)));
      PathProviderPlatform.instance = _DocumentsPath(directory.path);
      final fixture = await _io(tester, MediaRepositoryRealDbFixture.create);
      addTearDown(() => _io(tester, fixture.dispose));
      final identity = IdentityModel(
        peerId: 'b15-weekly-own-account',
        publicKey: 'own-public-key',
        privateKey: 'own-private-key',
        mnemonic12: 'one two three four five six seven eight nine ten eleven twelve',
        username: 'Alice',
        createdAt: '2026-11-19T10:00:00.000Z',
        updatedAt: '2026-11-19T10:00:00.000Z',
      );
      final contact = ContactModel(
        peerId: 'b15-weekly-contact-account',
        publicKey: 'contact-public-key',
        rendezvous: '/dns4/relay/tcp/443',
        username: 'Bob',
        signature: 'signature',
        scannedAt: '2026-11-19T10:00:00.000Z',
        mlKemPublicKey: 'contact-ml-kem-public-key',
      );
      await _io(tester, () => fixture.db.insert('contacts', {
        'peer_id': contact.peerId,
        'public_key': contact.publicKey,
        'rendezvous': contact.rendezvous,
        'username': contact.username,
        'signature': contact.signature,
        'scanned_at': contact.scannedAt,
        'ml_kem_public_key': contact.mlKemPublicKey,
      }));

      final bridge = await _io(tester, () async => _CheckpointBridge());
      final prepared = await _io(tester, () async =>
        prepareProductionActiveIdentityReporter(documentsPath: directory.path));
      addTearDown(() => _io(tester, prepared.dispose));
      final reporter = await _io(tester, () => prepared.reporter);
      expect(reporter, isNotNull);
      await _io(tester, () async {
        reporter!.attachBridge(bridge);
        reporter.observeIdentity(
          accountPeerId: identity.peerId,
          rootPrivateKeyBase64: base64Encode(List<int>.filled(64, 17)),
          profileBinding: b6Binding,
        );
        await reporter.observeConsent((enabled: true, consentEpoch: 7));
      });
      final contacts = FakeContactRepository()..seed([contact]);
      final identities = FakeIdentityRepository()..seed(identity);
      final requests = FakeContactRequestRepository()..contactRepository = contacts;
      final listener = await _io(tester, () async => ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: fixture.messageRepo,
        contactRepo: contacts,
      ));
      addTearDown(listener.dispose);
      final requestListener = ContactRequestListener(
        contactRequestStream: const Stream.empty(),
        requestRepo: requests,
        contactRepo: contacts,
        bridge: bridge,
        getOwnPeerId: () => identity.peerId,
      );
      addTearDown(requestListener.dispose);
      final posts = InMemoryPostRepository();
      final privacy = InMemoryPostsPrivacySettingsRepository();
      addTearDown(posts.dispose);
      addTearDown(privacy.dispose);
      final p2p = FakeP2PService(initialState: NodeState.stopped);
      addTearDown(p2p.dispose);
      final shell = AppShellController(initialTab: AppShellTab.feed);
      final pendingPostTarget = PendingPostTargetStore();
      addTearDown(shell.dispose);
      addTearDown(pendingPostTarget.dispose);

      try {
        await tester.pumpWidget(MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: FeedWired(
            directRouteAuthority: DirectConversationRouteAuthority(activityReporter: reporter),
            repository: identities,
            contactRepository: contacts,
            contactRequestRepository: requests,
            contactRequestListener: requestListener,
            messageRepository: fixture.messageRepo,
            postRepository: posts,
            mediaAttachmentRepository: fixture.repo,
            chatMessageListener: listener,
            bridge: bridge,
            p2pService: p2p,
            mediaFileManager: FakeMediaFileManager(),
            secureKeyStore: FakeSecureKeyStore(),
            imageProcessor: ImageProcessor(
              compressFile: ({required path, required quality, required keepExif,
                minWidth = 1920, minHeight = 1080}) async => null,
              compressVideo: ({required path, required compress, onProgress}) async => null,
            ),
            appShellController: shell,
            pendingPostTargetStore: pendingPostTarget,
            postsPrivacySettingsRepository: privacy,
            feedClearedRepository: InMemoryFeedClearedRepository(),
          ),
        )).timeout(_budget);
        await _pumpUntil(tester, () => find.byType(LetterCardSystem).evaluate().isNotEmpty);
        final l10n = AppLocalizations.of(tester.element(find.byType(FeedWired)))!;
        await _io(tester, () => tester.tap(find.text(l10n.feed_tap_to_say_hi)));
        await _pumpUntil(tester, () {
          final screen = find.byType(ConversationScreen);
          if (screen.evaluate().isEmpty) return false;
          return tester.widget<ConversationScreen>(screen).initialLoadDone &&
            ModalRoute.of(tester.element(screen))?.animation?.status ==
                AnimationStatus.completed;
        });
        await tester.pump(const Duration(milliseconds: 100)).timeout(_budget);
        expect(tester.widget<ConversationWired>(find.byType(ConversationWired)).activityReporter,
          same(reporter));
        expect(bridge.marks, isEmpty, reason: 'opening the real route is not communication');
        expect(await _io(tester, () => fixture.db.query('messages')), isEmpty);

        await tester.enterText(find.byType(TextField), _text).timeout(_budget);
        await tester.pump().timeout(_budget);
        final sendArrow = find.descendant(
          of: find.byType(ConversationScreen),
          matching: find.byIcon(Icons.arrow_upward_rounded),
        ).hitTestable();
        await _pumpUntil(tester, () => sendArrow.evaluate().length == 1);
        await _io(tester, () => tester.tap(sendArrow));
        // isSending becomes false before the sender. The owned bg:end is after
        // the awaited real sender and post-send SQL/UI refresh. Text has no
        // media leases, so its remaining outer cleanup is synchronous.
        await _io(tester, () => bridge.sendTaskEnded.future);
        await _io(tester, () => bridge.sendTaskEnded.future);
        await tester.pump().timeout(_budget);
        final screen = tester.widget<ConversationScreen>(find.byType(ConversationScreen));
        expect(screen.isSending, isFalse);
        expect(bridge.sendTaskBegins, 1);
        expect(bridge.marks, hasLength(1), reason: 'the real fresh typed admission completed');
        final rows = await _io(tester, () => fixture.db.query('messages'));
        expect(rows, hasLength(1));
        final messageId = rows.single['id'] as String;
        expect(rows.single['text'], _text);
        expect(rows.single['is_incoming'], 0);
        expect(rows.single['status'], 'failed', reason: 'stopped-node send retains durable custody');
        final custody = await _io(tester, () => fixture.db.query('direct_inbox_custody_outbox'));
        expect(custody, hasLength(1));
        expect(custody.single['message_id'], messageId);
        expect(p2p.sendMessageCallCount, 0);
        expect(p2p.storeInInboxCallCount, 0);
        await _io(tester, reporter!.flush);
        expect(bridge.requests.where((r) => r['op'] == 'markWeekly'), isEmpty,
          reason: 'no incoming or delivery fact has qualified chat');
        expect(tester.takeException(), isNull);

        final checkpoint = File('${directory.path}/active_identity/chat/engagement-chat-witness-v1.json');
        expect(await _io(tester, checkpoint.exists), isTrue,
          reason: 'fresh durable admission must reach the real private weekly chat checkpoint');
        final snapshot = jsonDecode(await _io(tester, checkpoint.readAsString)) as Map<String, dynamic>;
        expect(snapshot['phase'], 'collecting');
        expect(snapshot['scope'], {'profileBinding': b6Binding, 'consentEpoch': 7, 'week': '2026-W47'});
        expect(snapshot['contacts'], [{
          'account': contact.peerId,
          'incomingSeen': false,
          'deliveredOutgoingSeen': false,
          'outgoing': [{'message': messageId, 'generation': messageId}],
        }]);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink()).timeout(_budget);
        await tester.pump().timeout(_budget);
      }
    },
  );
}
