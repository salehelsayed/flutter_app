import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/constants/media_constants.dart';
import 'package:flutter_app/core/media/media_picker.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/attachment_preview_strip.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/discovered_peer.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/send_message_result.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../shared/fakes/fake_media_picker.dart';
import '../../../contacts/domain/repositories/fake_contact_repository.dart';
import '../../../conversation/domain/repositories/fake_media_attachment_repository.dart';
import '../../../conversation/domain/repositories/fake_message_repository.dart';
import '../../../identity/domain/repositories/fake_identity_repository.dart';

const _tinyJpgBytes = <int>[0xFF, 0xD8, 0xFF, 0xE0];

Future<(SendChatMessageResult, ConversationMessage?)> _unusedSendFn({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required String targetPeerId,
  required String text,
  required String senderPeerId,
  required String senderUsername,
  String? messageId,
  String? timestamp,
  Bridge? bridge,
  String? recipientMlKemPublicKey,
  String? quotedMessageId,
  List<MediaAttachment>? mediaAttachments,
  MediaAttachmentRepository? mediaAttachmentRepo,
}) async {
  return (SendChatMessageResult.success, null);
}

class _NoOpP2PService implements P2PService {
  @override
  NodeState get currentState => const NodeState(isStarted: true, peerId: 'me');

  @override
  void dispose() {}

  @override
  Future<bool> dialPeer(
    String peerId, {
    List<String>? addresses,
    int? timeoutMs,
  }) async => true;

  @override
  Future<DiscoveredPeer?> discoverPeer(String peerId, {int? timeoutMs}) async =>
      null;

  @override
  Stream<ChatMessage> get messageStream => const Stream.empty();

  @override
  Future<void> performImmediateHealthCheck() async {}

  @override
  Future<RelayProbeResult> probeRelay(String peerId) async =>
      RelayProbeResult.error;

  @override
  Future<bool> registerPushToken(String token, String platform) async => true;

  @override
  Future<List<Map<String, dynamic>>> retrieveInbox({int? timeoutMs}) async =>
      const [];

  @override
  Future<bool> sendLocalMedia({
    required String peerId,
    required String filePath,
    required String mime,
    required String mediaId,
    required String fromPeerId,
    int? durationMs,
    List<double>? waveform,
    String? filename,
  }) async => false;

  @override
  Future<bool> sendLocalMessage(
    String peerId,
    String message,
    String fromPeerId, {
    int? timeoutMs,
  }) async => false;

  @override
  Future<bool> sendMessage(String peerId, String message) async => true;

  @override
  Future<SendMessageResult> sendMessageWithReply(
    String peerId,
    String message, {
    int? timeoutMs,
  }) async => const SendMessageResult(sent: true, reply: 'ok');

  @override
  Future<bool> startNode(String privateKeyBase64, String peerId) async => true;

  @override
  Future<bool> startNodeCore(String privateKeyBase64, String peerId) async =>
      true;

  @override
  Stream<NodeState> get stateStream => const Stream.empty();

  @override
  Future<bool> stopNode() async => true;

  @override
  Future<bool> storeInInbox(String toPeerId, String message, {int? timeoutMs}) async => false;

  @override
  Future<void> drainOfflineInbox() async {}

  @override
  Future<void> warmBackground() async {}

  @override
  bool isConnectedToPeer(String peerId) => false;

  @override
  bool isLocalPeer(String peerId) => false;

  @override
  String? get lastRecoveryMethod => null;
}

ContactModel _makeContact() {
  return ContactModel(
    peerId: '12D3KooWContactPeer123',
    publicKey: 'pub',
    rendezvous: '/dns4/relay/tcp/443/p2p/relay',
    username: 'Alice',
    signature: 'sig',
    scannedAt: '2026-02-11T10:00:00.000Z',
  );
}

Future<void> _pumpScreen(
  WidgetTester tester, {
  required IdentityRepository identityRepo,
  required MessageRepository messageRepo,
  required ContactRepository contactRepo,
  required ChatMessageListener chatListener,
  required MediaPicker mediaPicker,
  MediaAttachmentRepository? mediaAttachmentRepo,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: ConversationWired(
        contact: _makeContact(),
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        chatMessageListener: chatListener,
        p2pService: _NoOpP2PService(),
        sendChatMessageFn: _unusedSendFn,
        contactRepo: contactRepo,
        mediaAttachmentRepo: mediaAttachmentRepo,
        mediaPicker: mediaPicker,
        qualityPreference: ImageQualityPreference.compressed,
        videoQualityPreference: ImageQualityPreference.compressed,
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _openGalleryPicker(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.add_rounded));
  await tester.pump(const Duration(milliseconds: 500));
  tester
      .widget<ListTile>(find.widgetWithText(ListTile, 'Media Library'))
      .onTap!();
  await tester.pump();
}

Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 20,
  Duration step = const Duration(milliseconds: 100),
}) async {
  for (var i = 0; i < maxPumps; i++) {
    if (condition()) {
      await tester.pump(const Duration(milliseconds: 200));
      return;
    }
    await tester.pump(step);
  }
  expect(condition(), isTrue);
}

List<String> _pendingPaths(WidgetTester tester) {
  final stripFinder = find.byType(AttachmentPreviewStrip);
  if (stripFinder.evaluate().isEmpty) {
    return const [];
  }
  final strip = tester.widget<AttachmentPreviewStrip>(stripFinder);
  return strip.attachments.map((file) => file.path).toList();
}

void main() {
  group('ConversationWired GIF picker guard', () {
    late FakeIdentityRepository identityRepo;
    late FakeMessageRepository messageRepo;
    late FakeContactRepository contactRepo;
    late ChatMessageListener chatListener;
    late FakeMediaPicker mediaPicker;
    late FakeMediaAttachmentRepository mediaAttachmentRepo;
    late Directory tempDir;

    setUp(() async {
      identityRepo = FakeIdentityRepository()
        ..seed(FakeIdentityRepository.makeIdentity(peerId: 'my-peer-id'));
      messageRepo = FakeMessageRepository();
      contactRepo = FakeContactRepository()..seed([_makeContact()]);
      chatListener = ChatMessageListener(
        chatMessageStream: const Stream.empty(),
        messageRepo: messageRepo,
        contactRepo: contactRepo,
      );
      mediaPicker = FakeMediaPicker();
      mediaAttachmentRepo = FakeMediaAttachmentRepository();
      tempDir = await Directory.systemTemp.createTemp('conv_gif_guard_');
    });

    tearDown(() async {
      chatListener.dispose();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    testWidgets(
      'oversized GIF is rejected before it reaches pending attachments',
      (tester) async {
        final oversizedGif = File('${tempDir.path}/too-big.gif');
        oversizedGif.createSync(recursive: true);
        oversizedGif.openSync(mode: FileMode.write)
          ..truncateSync(kMaxGifFileSize + 1)
          ..closeSync();
        mediaPicker.multipleMediaResult = [XFile(oversizedGif.path)];

        await _pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          chatListener: chatListener,
          mediaPicker: mediaPicker,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        await _openGalleryPicker(tester);
        await tester.pump(const Duration(milliseconds: 500));

        expect(_pendingPaths(tester), isEmpty);
        expect(
          find.text('GIF files larger than 25 MB cannot be added.'),
          findsOneWidget,
        );
      },
    );

    testWidgets('large JPEGs are not rejected by the GIF-only picker guard', (
      tester,
    ) async {
      final largeJpg = File('${tempDir.path}/large-photo.jpg');
      largeJpg.createSync(recursive: true);
      largeJpg.openSync(mode: FileMode.write)
        ..truncateSync(kMaxGifFileSize + 1)
        ..closeSync();
      mediaPicker.multipleMediaResult = [XFile(largeJpg.path)];

      await _pumpScreen(
        tester,
        identityRepo: identityRepo,
        messageRepo: messageRepo,
        contactRepo: contactRepo,
        chatListener: chatListener,
        mediaPicker: mediaPicker,
        mediaAttachmentRepo: mediaAttachmentRepo,
      );

      await _openGalleryPicker(tester);
      await _pumpUntil(tester, () => _pendingPaths(tester).isNotEmpty);

      expect(_pendingPaths(tester), [largeJpg.path]);
      expect(
        find.text('GIF files larger than 25 MB cannot be added.'),
        findsNothing,
      );
    });

    testWidgets(
      'mixed picks keep valid JPEG siblings while skipping oversized GIFs',
      (tester) async {
        final oversizedGif = File('${tempDir.path}/too-big.gif');
        oversizedGif.createSync(recursive: true);
        oversizedGif.openSync(mode: FileMode.write)
          ..truncateSync(kMaxGifFileSize + 1)
          ..closeSync();
        final validJpg = File('${tempDir.path}/ok.jpg')
          ..writeAsBytesSync(_tinyJpgBytes);
        mediaPicker.multipleMediaResult = [
          XFile(oversizedGif.path),
          XFile(validJpg.path),
        ];

        await _pumpScreen(
          tester,
          identityRepo: identityRepo,
          messageRepo: messageRepo,
          contactRepo: contactRepo,
          chatListener: chatListener,
          mediaPicker: mediaPicker,
          mediaAttachmentRepo: mediaAttachmentRepo,
        );

        await _openGalleryPicker(tester);
        await _pumpUntil(tester, () => _pendingPaths(tester).isNotEmpty);

        expect(_pendingPaths(tester), [validJpg.path]);
        expect(
          find.text('GIF files larger than 25 MB cannot be added.'),
          findsOneWidget,
        );
      },
    );
  });
}
