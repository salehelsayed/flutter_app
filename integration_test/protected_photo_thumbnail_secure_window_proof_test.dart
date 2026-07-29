// Plan 301 TC-14 — protected-thumbnail secure-window device proof (Android).
//
// Runs ON a real Android target (dispatched by run_1to1_device_real.dart's
// `protected-thumbnail-secure-window` scenario, which pairs this in-app run
// with OS-EXTERNAL `adb shell dumpsys window` + `adb exec-out screencap`
// observations during the marker-framed hold windows below).
//
// In-app assertions, in order and WITHOUT ever invoking Open or tapping the
// tile first:
//   (a) the restricted thumbnail tile — keyed on the tile widget key, not
//       generic pixels — is visible for an incoming protected photo whose
//       inline-thumbnail sibling exists;
//   (b) the REAL shared platform protection coordinator reports
//       secureApplied=true while the tile is on screen (the host verifies the
//       same window state externally via dumpsys/screencap in this window);
//   (d) after popping the conversation content, secureApplied returns to
//       false (host re-verifies SECURE absent in the released hold window).
//
// Marker protocol (one line each on stdout):
//   P301_MARKER SECURE_HOLD_START / SECURE_HOLD_END
//   P301_MARKER RELEASED_HOLD_START / RELEASED_HOLD_END
//   P301_RESULT {json}
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';

import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/media/private_media_protection_coordinator.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

const _contactPeerId = '12D3KooWSecureWindowProofContact';
const _blobId = 'secure-window-proof-blob';
const _tileKey = ValueKey('private-media-thumbnail-tile');

Future<void> _holdVisible(
  WidgetTester tester,
  Duration duration,
) async {
  final deadline = DateTime.now().add(duration);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
}

Future<bool> _waitForSecureApplied(
  PrivateMediaProtectionCoordinator coordinator, {
  required bool expected,
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final state = await coordinator.debugGetState();
    if (state['secureApplied'] == expected) return true;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }
  return false;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'protected thumbnail holds the OS secure window while visible and releases on pop',
    (tester) async {
      expect(Platform.isAndroid, isTrue,
          reason: 'the secure-window claim is the Android FLAG_SECURE boundary');

      // Seed the inline-thumbnail sibling exactly where the production
      // receive writer persists it, under the REAL documents directory.
      final docs = await getApplicationDocumentsDirectory();
      MediaFileManager.cacheDocumentsDir(docs.path);
      final relative = MediaFilePathConvention.relativeThumbnailPathForAttachment(
        contactPeerId: _contactPeerId,
        blobId: _blobId,
      );
      final thumbFile = File(MediaFileManager.resolveStoredPathSync(relative));
      thumbFile.parent.createSync(recursive: true);
      final pixels = img.Image(width: 240, height: 240);
      img.fill(pixels, color: img.ColorRgb8(240, 120, 40));
      thumbFile.writeAsBytesSync(img.encodeJpg(pixels, quality: 85));
      addTearDown(() {
        if (thumbFile.existsSync()) thumbFile.deleteSync();
        MediaFileManager.debugResetDocumentsDirCache();
      });

      final message = ConversationMessage(
        id: 'secure-window-proof-message',
        contactPeerId: _contactPeerId,
        senderPeerId: _contactPeerId,
        text: '',
        timestamp: '2026-07-29T10:00:00.000Z',
        status: 'delivered',
        isIncoming: true,
        createdAt: '2026-07-29T10:00:00.000Z',
        privateMediaPolicy: const PrivateMediaPolicy.protected(),
        privateMediaState: PrivateMediaLifecycleState.available,
        media: const [
          MediaAttachment(
            id: _blobId,
            messageId: 'secure-window-proof-message',
            mime: 'image/jpeg',
            size: 42,
            mediaType: 'image',
            downloadStatus: 'pending',
            createdAt: '2026-07-29T10:00:00.000Z',
            ownerLane: MediaOwnerLane.direct,
          ),
        ],
      );

      // The REAL shared platform coordinator — the same native handler and
      // window the production conversation route protects.
      final coordinator = PrivateMediaProtectionCoordinator.sharedPlatform();

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: ConversationScreen(
              contactPeerId: _contactPeerId,
              contactUsername: 'SecureWindowPeer',
              connectionDate: 'July 29, 2026',
              ownPeerId: 'secure-window-own-peer',
              messages: [message],
              onSend: (_) {},
              onBack: () {},
              initialLoadDone: true,
              hasMoreOlderMessages: false,
              protectionCoordinator: coordinator,
            ),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 100));

      // (b) real native FLAG_SECURE while the tile is on screen. Wait for the
      // async route enter() + native application first, then assert the tile:
      // the render gate only shows pixels once the owner is held, so a
      // present tile + secureApplied is the exact coupled claim.
      final secured = await _waitForSecureApplied(coordinator, expected: true);
      await tester.pump(const Duration(milliseconds: 100));

      // (a) the tile is visible, keyed on the widget key, with no Open ever
      // invoked and the no-pixel open tile replaced.
      final tileVisible = find.byKey(_tileKey).evaluate().isNotEmpty;
      expect(tileVisible, isTrue,
          reason: 'the restricted thumbnail tile must render before any Open');
      expect(find.byKey(const ValueKey('private-media-open')), findsNothing);
      expect(secured, isTrue,
          reason: 'native secureApplied must be true while the tile is visible');

      // Host observation window: dumpsys must show symbolic SECURE and
      // screencap must capture a black protected region.
      debugPrint('P301_MARKER SECURE_HOLD_START');
      await _holdVisible(tester, const Duration(seconds: 8));
      debugPrint('P301_MARKER SECURE_HOLD_END');

      // (d) pop the conversation content; the route owner releases and the
      // window flag drops.
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 100));
      final released = await _waitForSecureApplied(
        coordinator,
        expected: false,
        timeout: const Duration(seconds: 10),
      );
      expect(released, isTrue,
          reason: 'secureApplied must clear after the conversation is popped');

      debugPrint('P301_MARKER RELEASED_HOLD_START');
      await _holdVisible(tester, const Duration(seconds: 5));
      debugPrint('P301_MARKER RELEASED_HOLD_END');

      debugPrint(
        'P301_RESULT ${jsonEncode(<String, Object?>{
          'schema': 'mknoon.p301.secure-window-proof.v1',
          'tileVisibleBeforeOpen': tileVisible,
          'secureAppliedWhileVisible': secured,
          'secureReleasedAfterPop': released,
        })}',
      );
    },
  );
}
