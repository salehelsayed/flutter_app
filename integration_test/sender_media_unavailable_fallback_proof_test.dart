// Sim/device proof for the sender "Media unavailable" fix (Test-Flight-Improv
// 128, rounds 3-5). The device repro: an own-sent 1:1/group image whose
// in-memory attachment still carries the DELETED optimistic `pending_uploads`
// ABSOLUTE path (the send-result/reload swap to the durable copy is unreliable),
// while the durable owned copy DOES exist at `media/<id>/<blob>.<ext>`. The
// render gate (MediaGridCell) must fall back to that owned copy and render the
// thumbnail — never the "Media unavailable" / broken-image placeholder.
//
// This proof drives the REAL screens (`ConversationScreen` and
// `GroupConversationScreen`), so it exercises the `ownedMediaPeerId` wiring
// threaded ConversationScreen/GroupConversationScreen -> LetterCard -> MediaGrid
// -> MediaGridCell end-to-end on a simulator, not just MediaGridCell in
// isolation. Run on a sim/device:
//   flutter test integration_test/sender_media_unavailable_fallback_proof_test.dart
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/media_grid.dart';
import 'package:flutter_app/shared/widgets/media/media_grid_cell.dart';
import 'package:flutter_app/shared/widgets/media/media_thumbnail_image.dart';

// A real, decodable 1x1 PNG so the durable owned copy decodes (a corrupt file
// would itself trip the thumbnail decode-error fallback -> "Media unavailable").
const _validPngBytes = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, //
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, //
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, //
  0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, //
  0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, //
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, //
  0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, //
  0x42, 0x60, 0x82, //
];

const _validContentHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Future<void> _pumpFrames(WidgetTester tester, {int count = 10}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// Seeds the round-5 device residue under [root] and returns the (deleted)
/// stale `pending_uploads` absolute path the displayed attachment carries.
String _seedResidue({
  required Directory root,
  required String dirId,
  required String blobId,
  required String messageId,
}) {
  // The durable owned copy EXISTS at media/<dirId>/<blob>.jpg (what the upload
  // actually committed and what the render gate must fall back to).
  final ownedCopy = File(p.join(root.path, 'media', dirId, '$blobId.jpg'))
    ..createSync(recursive: true)
    ..writeAsBytesSync(_validPngBytes);
  assert(ownedCopy.existsSync());
  // The displayed attachment still points at the DELETED optimistic pending
  // path (never created here on purpose) — the exact on-device residue.
  final stalePending = p.join(
    root.path,
    'pending_uploads',
    messageId,
    '$blobId.jpg',
  );
  assert(!File(stalePending).existsSync());
  return stalePending;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  group('Sender "Media unavailable" owned-copy fallback (sim proof)', () {
    late Directory root;

    setUp(() {
      MediaGridCell.debugResetUnavailableDiagnostics();
      root = Directory.systemTemp.createTempSync('sender_media_fallback_proof_');
      // Mirrors main.dart's seed of the sync render-boundary resolver.
      MediaFileManager.cacheDocumentsDir(root.path);
    });

    tearDown(() {
      MediaFileManager.debugResetDocumentsDirCache();
      if (root.existsSync()) {
        root.deleteSync(recursive: true);
      }
    });

    testWidgets(
      '1:1 own-sent image with a stale display path renders from the durable '
      'owned copy (media/<contactPeerId>)',
      (tester) async {
        const contactPeerId = '12D3KooWProofContact';
        const blob = '5984e08d-1a2b-4c3d-8e9f-0a1b2c3d4e5f';
        const messageId = 'one-to-one-proof-msg';
        final stalePending = _seedResidue(
          root: root,
          dirId: contactPeerId,
          blobId: blob,
          messageId: messageId,
        );

        final message = ConversationMessage(
          id: messageId,
          contactPeerId: contactPeerId,
          senderPeerId: 'me-peer',
          text: 'photo',
          timestamp: DateTime.now().toUtc().toIso8601String(),
          status: 'sent',
          isIncoming: false,
          createdAt: DateTime.now().toUtc().toIso8601String(),
          media: [
            MediaAttachment(
              id: blob,
              messageId: messageId,
              mime: 'image/jpeg',
              size: _validPngBytes.length,
              mediaType: 'image',
              localPath: stalePending, // stale, deleted
              downloadStatus: 'done',
              createdAt: DateTime.now().toUtc().toIso8601String(),
            ),
          ],
        );

        // ConversationScreen does not embed its own Scaffold/Material (unlike
        // GroupConversationScreen) — its TextField compose area needs a Material
        // ancestor, so wrap it like the production navigator route does.
        Widget app() => MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ConversationScreen(
              contactPeerId: contactPeerId,
              contactUsername: 'Proof Contact',
              connectionDate: '2026-01-01',
              ownPeerId: 'me-peer',
              messages: [message],
              initialLoadDone: true,
              onSend: (_) {},
              onBack: () {},
            ),
          ),
        );

        await tester.pumpWidget(app());
        await _pumpFrames(tester);

        expect(find.byType(MediaGrid), findsOneWidget);
        expect(find.byType(MediaThumbnailImage), findsOneWidget);
        expect(find.text('Media unavailable'), findsNothing);
        expect(find.byIcon(Icons.broken_image_outlined), findsNothing);

        // Reopen to mirror the device flow (close -> reopen the thread): the
        // durable fallback must keep rendering, not just on first build.
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pumpWidget(app());
        await _pumpFrames(tester);

        expect(find.byType(MediaThumbnailImage), findsOneWidget);
        expect(find.text('Media unavailable'), findsNothing);
        expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
      },
    );

    testWidgets(
      'group own-sent image with a stale display path renders from the durable '
      'owned copy (media/<groupId>), verification still enforced',
      (tester) async {
        const groupId = 'proof-group-1';
        const blob = '6a1c0bb2-7d8e-4f90-a1b2-c3d4e5f60718';
        const messageId = 'group-proof-msg';
        final stalePending = _seedResidue(
          root: root,
          dirId: groupId,
          blobId: blob,
          messageId: messageId,
        );

        final group = GroupModel(
          id: groupId,
          name: 'Proof Group',
          type: GroupType.chat,
          topicName: 'topic-proof',
          createdAt: DateTime.now().toUtc(),
          createdBy: 'me-peer',
          myRole: GroupRole.member,
        );
        final message = GroupMessage(
          id: messageId,
          groupId: groupId,
          senderPeerId: 'me-peer',
          senderUsername: 'You',
          text: 'group photo',
          timestamp: DateTime.now().toUtc(),
          createdAt: DateTime.now().toUtc(),
          status: 'sent',
          isIncoming: false,
          media: [
            MediaAttachment(
              id: blob,
              messageId: messageId,
              mime: 'image/jpeg',
              size: _validPngBytes.length,
              mediaType: 'image',
              localPath: stalePending, // stale, deleted
              downloadStatus: 'done',
              // Group rendering requires verified content-hash + encryption
              // metadata; the fallback only supplies the file path and never
              // bypasses this gate.
              contentHash: _validContentHash,
              encryptionKeyBase64: 'proof-key',
              encryptionNonce: 'proof-nonce',
              encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
              createdAt: DateTime.now().toUtc().toIso8601String(),
            ),
          ],
        );

        Widget app() => MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GroupConversationScreen(
            group: group,
            messages: [message],
            ownPeerId: 'me-peer',
            initialLoadDone: true,
            onSend: (_) {},
            onBack: () {},
          ),
        );

        await tester.pumpWidget(app());
        await _pumpFrames(tester);

        expect(find.byType(MediaGrid), findsOneWidget);
        expect(find.byType(MediaThumbnailImage), findsOneWidget);
        expect(find.text('Media unavailable'), findsNothing);
        expect(find.byIcon(Icons.broken_image_outlined), findsNothing);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pumpWidget(app());
        await _pumpFrames(tester);

        expect(find.byType(MediaThumbnailImage), findsOneWidget);
        expect(find.text('Media unavailable'), findsNothing);
        expect(find.byIcon(Icons.broken_image_outlined), findsNothing);
      },
    );
  });
}
