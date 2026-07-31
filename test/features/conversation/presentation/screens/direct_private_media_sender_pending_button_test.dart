import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_viewer_controller.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/presentation/navigation/direct_private_media_route_observer.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const cases =
      <
        ({
          String label,
          PrivateMediaPolicy policy,
          DirectPrivateMediaOpenFailureReason failureReason,
          bool expectLocalMissingCopy,
          bool expectMinimalTile,
        })
      >[
        (
          label: 'protected',
          policy: PrivateMediaPolicy.protected(),
          failureReason:
              DirectPrivateMediaOpenFailureReason.senderLocalBytesMissing,
          expectLocalMissingCopy: true,
          expectMinimalTile: false,
        ),
        (
          label: 'view_once',
          policy: PrivateMediaPolicy.viewOnce(),
          failureReason: DirectPrivateMediaOpenFailureReason.authorityLost,
          expectLocalMissingCopy: false,
          expectMinimalTile: true,
        ),
      ];

  for (final testCase in cases) {
    testWidgets(
      'hydrated outgoing ${testCase.label} upload_pending row offers exact one-more-look',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync(
          'sender_pending_button_${testCase.label}_',
        );
        addTearDown(() {
          MediaFileManager.debugResetDocumentsDirCache();
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        MediaFileManager.cacheDocumentsDir(tempDir.path);

        final messageId = 'pending-message-${testCase.label}';
        final attachmentId = 'pending-attachment-${testCase.label}';
        final pendingRelativePath =
            'pending_uploads/$messageId/$attachmentId.jpg';
        File('${tempDir.path}/$pendingRelativePath')
          ..createSync(recursive: true)
          ..writeAsBytesSync(const <int>[1, 2, 3, 4]);
        final attachment = MediaAttachment(
          id: attachmentId,
          messageId: messageId,
          mime: 'image/jpeg',
          size: 4,
          mediaType: 'image',
          localPath: pendingRelativePath,
          downloadStatus: 'upload_pending',
          createdAt: '2026-07-20T10:00:00.000Z',
          ownerLane: MediaOwnerLane.direct,
        );
        final message = ConversationMessage(
          id: messageId,
          contactPeerId: 'contact-1',
          senderPeerId: 'self-peer',
          text: '',
          timestamp: '2026-07-20T10:00:00.000Z',
          status: 'sending',
          isIncoming: false,
          createdAt: '2026-07-20T10:00:00.000Z',
          privateMediaPolicy: testCase.policy,
          privateMediaState: PrivateMediaLifecycleState.available,
          media: [attachment],
        );
        final opened = <DirectPrivateMediaViewerIdentity>[];
        DirectPrivateMediaContinuityState? openedGuardState;
        final observer = RouteObserver<ModalRoute<void>>();

        await tester.pumpWidget(
          MaterialApp(
            navigatorObservers: [observer],
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            builder: (context, child) => DirectPrivateMediaRouteObserverScope(
              observer: observer,
              child: child ?? const SizedBox.shrink(),
            ),
            home: Scaffold(
              body: ConversationScreen(
                contactPeerId: 'contact-1',
                contactUsername: 'Alice',
                connectionDate: 'July 20, 2026',
                ownPeerId: 'self-peer',
                messages: [message],
                onSend: (_) {},
                onBack: () {},
                initialLoadDone: true,
                hasMoreOlderMessages: false,
                onOpenPrivateMediaResult: (identity, guard) async {
                  openedGuardState = guard.state;
                  opened.add(identity);
                  return DirectPrivateMediaOpenResult.failed(
                    testCase.failureReason,
                    canRetry: false,
                  );
                },
              ),
            ),
          ),
        );
        await tester.pump(const Duration(milliseconds: 500));

        final openButton = find.byKey(const ValueKey('private-media-open'));
        final visual = find.byKey(const ValueKey('private-media-card-visual'));
        expect(visual, findsOneWidget);
        expect(
          tester.getSize(visual).height,
          testCase.expectMinimalTile ? 150 : 88,
        );
        expect(
          openButton,
          testCase.expectMinimalTile ? findsNothing : findsOneWidget,
        );
        if (!testCase.expectMinimalTile) {
          expect(tester.widget<FilledButton>(openButton).onPressed, isNotNull);
        }
        expect(find.text('View-once photo'), findsNothing);
        expect(
          find.text('Protected photo'),
          testCase.expectMinimalTile ? findsNothing : findsOneWidget,
        );
        expect(
          find.textContaining('You can reopen it once here after sending.'),
          findsNothing,
        );

        await tester.tap(testCase.expectMinimalTile ? visual : openButton);
        await tester.pump();

        expect(openedGuardState, DirectPrivateMediaContinuityState.valid);
        expect(opened, [
          DirectPrivateMediaViewerIdentity(
            messageId: messageId,
            attachmentId: attachmentId,
          ),
        ]);
        expect(
          find.text("Your sent media can't be reopened on this phone."),
          testCase.expectLocalMissingCopy ? findsOneWidget : findsNothing,
        );
        expect(
          find.text('Private media'),
          testCase.expectLocalMissingCopy ? findsNothing : findsOneWidget,
        );
      },
    );
  }
}
