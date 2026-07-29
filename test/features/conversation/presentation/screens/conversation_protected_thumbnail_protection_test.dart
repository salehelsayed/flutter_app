import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/media/private_media_protection_coordinator.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../../shared/fixtures/media_repository_real_db_fixture.dart';

const _ownPeerId = '12D3KooWOwnProtectionPeer';
const _contactPeerId = '12D3KooWContactProtectionPeer';
const _tileKey = ValueKey('private-media-thumbnail-tile');
const _noPixelVisualKey = ValueKey('private-media-card-visual');

/// Refcount-faithful recording channel: enter publishes an owner token whose
/// release is observable, so double-enter and never-exit bugs surface.
class _RecordingProtectionChannel {
  final List<String> enters = <String>[];
  final List<String> exits = <String>[];
  final Set<String> _tokens = <String>{};
  final StreamController<Object?> events = StreamController<Object?>.broadcast();
  bool failEnter = false;

  PrivateMediaProtectionCoordinator buildCoordinator() =>
      PrivateMediaProtectionCoordinator(
        invokeMethod: _invoke,
        nativeEvents: events.stream,
      );

  Future<Object?> _invoke(String method, Map<String, Object?>? args) async {
    final token = args?['ownerToken'] as String?;
    switch (method) {
      case 'enter':
        enters.add(token!);
        if (failEnter) return const <String, Object?>{'ok': false};
        _tokens.add(token);
        return <String, Object?>{'ok': true, 'protectionActive': true};
      case 'exit':
        exits.add(token!);
        _tokens.remove(token);
        return <String, Object?>{
          'ok': true,
          'protectionActive': _tokens.isNotEmpty,
        };
    }
    throw StateError('unexpected protection method $method');
  }
}

class _StaticIdentityRepository implements IdentityRepository {
  _StaticIdentityRepository(this.identity);

  final IdentityModel identity;

  @override
  Future<IdentityModel?> loadIdentity() async => identity;

  @override
  Future<void> saveIdentity(IdentityModel identity) async {}
}

class _MinimalP2PService extends Fake implements P2PService {
  final StreamController<NodeState> _states =
      StreamController<NodeState>.broadcast();

  @override
  NodeState get currentState => const NodeState(isStarted: true);

  @override
  Stream<NodeState> get stateStream => _states.stream;

  @override
  Future<void> warmPeer(String peerId, {bool preferQuic = false}) async {}

  @override
  Future<void> drainOfflineInbox() async {}

  @override
  bool isLocalPeer(String peerId) => false;
}

void main() {
  late Directory tempDocs;

  setUp(() {
    tempDocs = Directory.systemTemp.createTempSync('protected_thumb_protect_');
    MediaFileManager.cacheDocumentsDir(tempDocs.path);
  });

  tearDown(() {
    MediaFileManager.debugResetDocumentsDirCache();
    if (tempDocs.existsSync()) {
      tempDocs.deleteSync(recursive: true);
    }
  });

  void seedThumbFile(String blobId) {
    final relative = MediaFilePathConvention.relativeThumbnailPathForAttachment(
      contactPeerId: _contactPeerId,
      blobId: blobId,
    );
    File(MediaFileManager.resolveStoredPathSync(relative))
      ..createSync(recursive: true)
      ..writeAsBytesSync(img.encodeJpg(img.Image(width: 6, height: 6)));
  }

  MediaAttachment attachment({
    required String id,
    required String messageId,
    String mime = 'image/jpeg',
    String mediaType = 'image',
  }) {
    return MediaAttachment(
      id: id,
      messageId: messageId,
      mime: mime,
      size: 42,
      mediaType: mediaType,
      downloadStatus: 'pending',
      createdAt: '2026-07-29T10:00:00.000Z',
      ownerLane: MediaOwnerLane.direct,
    );
  }

  ConversationMessage privateMessage({
    required String id,
    required PrivateMediaPolicy policy,
    String? blobId,
  }) {
    return ConversationMessage(
      id: id,
      contactPeerId: _contactPeerId,
      senderPeerId: _contactPeerId,
      text: '',
      timestamp: '2026-07-29T10:00:00.000Z',
      status: 'delivered',
      isIncoming: true,
      createdAt: '2026-07-29T10:00:00.000Z',
      privateMediaPolicy: policy,
      privateMediaState: PrivateMediaLifecycleState.available,
      media: [
        if (blobId != null) attachment(id: blobId, messageId: id),
      ],
    );
  }

  Future<void> pumpConversation(
    WidgetTester tester, {
    required List<ConversationMessage> messages,
    required PrivateMediaProtectionCoordinator coordinator,
  }) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ConversationScreen(
            contactPeerId: _contactPeerId,
            contactUsername: 'Alice',
            connectionDate: 'July 29, 2026',
            ownPeerId: _ownPeerId,
            messages: messages,
            onSend: (_) {},
            onBack: () {},
            initialLoadDone: true,
            hasMoreOlderMessages: false,
            protectionCoordinator: coordinator,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    // Bounded pumps: the ambient background animates forever, so never
    // pumpAndSettle a ConversationScreen fixture.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets(
    'conversation with a protected thumbnail enters protection and exits on dispose',
    (tester) async {
      final channel = _RecordingProtectionChannel();
      seedThumbFile('protect-enter-blob');
      final message = privateMessage(
        id: 'protect-enter',
        policy: const PrivateMediaPolicy.protected(),
        blobId: 'protect-enter-blob',
      );

      await pumpConversation(
        tester,
        messages: [message],
        coordinator: channel.buildCoordinator(),
      );

      expect(channel.enters, hasLength(1),
          reason: 'exactly one route owner while a thumbnail is rendered');
      expect(channel.exits, isEmpty);
      expect(find.byKey(_tileKey), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 50));

      expect(channel.enters, hasLength(1));
      expect(channel.exits, hasLength(1),
          reason: 'dispose must release the exact owner');
      expect(channel.exits.single, channel.enters.single);
    },
  );

  testWidgets(
    'a chat with only view-once disappearing and thumbless protected media never enters protection',
    (tester) async {
      final channel = _RecordingProtectionChannel();
      // Files exist for the NON-protected private rows, so wiring keyed on
      // requiresRedaction (or on file presence alone) would wrongly enter.
      seedThumbFile('protect-negative-vo-blob');
      seedThumbFile('protect-negative-dis-blob');
      final messages = [
        privateMessage(
          id: 'protect-negative-vo',
          policy: const PrivateMediaPolicy.viewOnce(),
          blobId: 'protect-negative-vo-blob',
        ),
        privateMessage(
          id: 'protect-negative-dis',
          policy: PrivateMediaPolicy.disappearing(3600),
          blobId: 'protect-negative-dis-blob',
        ),
        privateMessage(
          id: 'protect-negative-thumbless',
          policy: const PrivateMediaPolicy.protected(),
          blobId: 'protect-negative-thumbless-blob',
        ),
      ];

      await pumpConversation(
        tester,
        messages: messages,
        coordinator: channel.buildCoordinator(),
      );

      expect(channel.enters, isEmpty,
          reason: 'no protected THUMBNAIL is rendered, so no owner is taken');
      expect(find.byKey(_tileKey), findsNothing);
    },
  );

  testWidgets(
    'deleting the last protected thumbnail releases the owner without dispose',
    (tester) async {
      final channel = _RecordingProtectionChannel();
      seedThumbFile('protect-release-blob');
      final message = privateMessage(
        id: 'protect-release',
        policy: const PrivateMediaPolicy.protected(),
        blobId: 'protect-release-blob',
      );

      final coordinator = channel.buildCoordinator();
      await pumpConversation(
        tester,
        messages: [message],
        coordinator: coordinator,
      );
      expect(channel.enters, hasLength(1));
      expect(channel.exits, isEmpty);

      // Same route, SAME shared coordinator (as production wires it), new
      // message list without the protected thumbnail row.
      await pumpConversation(
        tester,
        messages: const [],
        coordinator: coordinator,
      );

      expect(find.byType(ConversationScreen), findsOneWidget,
          reason: 'the screen must still be mounted');
      expect(channel.exits, hasLength(1),
          reason: 'the owner is released as soon as no thumbnail remains');
      expect(channel.enters, hasLength(1));
    },
  );

  testWidgets('ios never enters route protection', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      final channel = _RecordingProtectionChannel();
      seedThumbFile('protect-ios-blob');
      final message = privateMessage(
        id: 'protect-ios',
        policy: const PrivateMediaPolicy.protected(),
        blobId: 'protect-ios-blob',
      );

      await pumpConversation(
        tester,
        messages: [message],
        coordinator: channel.buildCoordinator(),
      );

      expect(channel.enters, isEmpty,
          reason: 'a route-level owner would latch protected opens shut on iOS');
      // Pixels still render on iOS — through the per-view protected surface.
      expect(find.byKey(_tileKey), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 50));
      expect(channel.enters, isEmpty);
      expect(channel.exits, isEmpty);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('android enter failure keeps the no-pixel presentations', (
    tester,
  ) async {
    final channel = _RecordingProtectionChannel()..failEnter = true;
    seedThumbFile('protect-fail-blob');
    final message = privateMessage(
      id: 'protect-fail',
      policy: const PrivateMediaPolicy.protected(),
      blobId: 'protect-fail-blob',
    );

    await pumpConversation(
      tester,
      messages: [message],
      coordinator: channel.buildCoordinator(),
    );

    expect(channel.enters, hasLength(1));
    expect(find.byKey(_tileKey), findsNothing,
        reason: 'protected pixels must never render in an unprotected window');
    expect(
      find.descendant(
        of: find.byKey(ValueKey('private-media-slot-${message.id}')),
        matching: find.byKey(_noPixelVisualKey),
      ),
      findsOneWidget,
    );
  });

  testWidgets('wired construction passes the shared protection coordinator', (
    tester,
  ) async {
    // The shared-platform coordinator's event channel must answer the listen
    // handshake in tests.
    final messenger = tester.binding.defaultBinaryMessenger;
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

    // The coordinator rides the Session-05 private-media qualification, so the
    // wired fixture must carry REAL lifecycle-capable repositories (the same
    // production impls) plus a file manager — exactly like a live route.
    final fixture = await tester.runAsync(MediaRepositoryRealDbFixture.create);
    addTearDown(() => fixture!.dispose());

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: ConversationWired(
          contact: ContactModel(
            peerId: _contactPeerId,
            publicKey: 'public-key',
            rendezvous: 'rendezvous',
            username: 'Alice',
            signature: 'signature',
            scannedAt: '2026-07-29T08:00:00.000Z',
          ),
          identityRepo: _StaticIdentityRepository(
            IdentityModel(
              peerId: _ownPeerId,
              publicKey: 'public-key',
              privateKey: 'private-key',
              mnemonic12:
                  'one two three four five six seven eight nine ten eleven twelve',
              username: 'Me',
              createdAt: '2026-07-29T08:00:00.000Z',
              updatedAt: '2026-07-29T08:00:00.000Z',
            ),
          ),
          messageRepo: fixture!.messageRepo,
          chatMessageListener: ChatMessageListener(
            chatMessageStream: const Stream.empty(),
            messageRepo: fixture.messageRepo,
            contactRepo: InMemoryContactRepository(),
          ),
          p2pService: _MinimalP2PService(),
          mediaAttachmentRepo: fixture.repo,
          mediaFileManager: MediaFileManager(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    final screen = tester.widget<ConversationScreen>(
      find.byType(ConversationScreen),
    );
    expect(screen.protectionCoordinator, isNotNull,
        reason: 'the wired layer must hand the screen the shared coordinator');
  });
}
