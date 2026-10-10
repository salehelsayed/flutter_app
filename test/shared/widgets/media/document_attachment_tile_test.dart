import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/received_media_egress.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/document_attachment_tile.dart';
import 'package:flutter_test/flutter_test.dart';

MediaAttachment _pdf({
  String id = 'doc-1',
  String status = 'done',
  String? localPath = 'media/peer/doc-1.pdf',
  String mime = 'application/pdf',
  String? fileName = 'Invoice.pdf',
}) {
  return MediaAttachment(
    id: id,
    messageId: 'msg-1',
    mime: mime,
    size: 2 * 1024 * 1024,
    mediaType: 'file',
    localPath: localPath,
    downloadStatus: status,
    createdAt: '2026-10-10T10:00:00.000Z',
    fileName: fileName,
  );
}

Widget _wrap(Widget child) => MaterialApp(
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(body: child),
);

void main() {
  group('DocumentAttachmentTile (414)', () {
    testWidgets('shows name and size; tap on a ready PDF opens it', (
      tester,
    ) async {
      final calls = <(MediaEgressDestination, String)>[];
      await tester.pumpWidget(
        _wrap(
          DocumentAttachmentTile(
            attachment: _pdf(),
            performEgress: (destination, attachment) async {
              calls.add((destination, attachment.id));
              return MediaEgressResult(
                requestId: 'r',
                outcome: MediaEgressOutcome.presented,
                items: const [],
              );
            },
          ),
        ),
      );
      expect(find.text('Invoice.pdf'), findsOneWidget);
      expect(find.text('PDF · 2.0 MB'), findsOneWidget);
      await tester.tap(find.byKey(DocumentAttachmentTile.tileKey('doc-1')));
      await tester.pump();
      expect(calls, [(MediaEgressDestination.open, 'doc-1')]);
    });

    testWidgets('no viewer shows the message', (tester) async {
      await tester.pumpWidget(
        _wrap(
          DocumentAttachmentTile(
            attachment: _pdf(),
            performEgress: (_, _) async => MediaEgressResult(
              requestId: 'r',
              outcome: MediaEgressOutcome.noViewer,
              items: const [],
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(DocumentAttachmentTile.tileKey('doc-1')));
      await tester.pumpAndSettle();
      expect(
        find.text('No app on this phone can open this file.'),
        findsOneWidget,
      );
    });

    testWidgets('menu saves to Files and shares', (tester) async {
      final destinations = <MediaEgressDestination>[];
      await tester.pumpWidget(
        _wrap(
          DocumentAttachmentTile(
            attachment: _pdf(),
            performEgress: (destination, _) async {
              destinations.add(destination);
              return MediaEgressResult(
                requestId: 'r',
                outcome: destination == MediaEgressDestination.files
                    ? MediaEgressOutcome.saved
                    : MediaEgressOutcome.presented,
                items: const [],
              );
            },
          ),
        ),
      );
      await tester.tap(find.byKey(DocumentAttachmentTile.menuKey('doc-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save to Files'));
      await tester.pumpAndSettle();
      expect(find.text('Saved'), findsOneWidget);
      await tester.tap(find.byKey(DocumentAttachmentTile.menuKey('doc-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Share'));
      await tester.pumpAndSettle();
      expect(destinations, [
        MediaEgressDestination.files,
        MediaEgressDestination.share,
      ]);
    });

    testWidgets('a pending download shows progress and cannot be opened', (
      tester,
    ) async {
      var called = false;
      await tester.pumpWidget(
        _wrap(
          DocumentAttachmentTile(
            attachment: _pdf(status: 'pending', localPath: null),
            performEgress: (_, _) async {
              called = true;
              throw StateError('must not run');
            },
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byKey(DocumentAttachmentTile.tileKey('doc-1')));
      await tester.pump();
      expect(called, isFalse);
      expect(find.byKey(DocumentAttachmentTile.menuKey('doc-1')), findsNothing);
    });

    testWidgets('a pending PDF offers Download when a download owner exists', (
      tester,
    ) async {
      var downloads = 0;
      await tester.pumpWidget(
        _wrap(
          DocumentAttachmentTile(
            attachment: _pdf(status: 'pending', localPath: null),
            onRetryUnavailableMedia: () => downloads++,
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.byKey(DocumentAttachmentTile.downloadKey('doc-1')));
      expect(downloads, 1);

      await tester.pumpWidget(
        _wrap(
          DocumentAttachmentTile(
            attachment: _pdf(status: 'downloading', localPath: null),
            onRetryUnavailableMedia: () => downloads++,
          ),
        ),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(
        find.byKey(DocumentAttachmentTile.downloadKey('doc-1')),
        findsNothing,
      );
    });

    testWidgets('a failed download offers retry', (tester) async {
      var retried = 0;
      await tester.pumpWidget(
        _wrap(
          DocumentAttachmentTile(
            attachment: _pdf(status: 'failed'),
            onRetryUnavailableMedia: () => retried++,
          ),
        ),
      );
      await tester.tap(find.byKey(DocumentAttachmentTile.retryKey('doc-1')));
      expect(retried, 1);
    });

    testWidgets('a non-PDF file is shown as unsupported and never opens', (
      tester,
    ) async {
      var called = false;
      await tester.pumpWidget(
        _wrap(
          DocumentAttachmentTile(
            attachment: _pdf(
              mime: 'application/octet-stream',
              fileName: 'notes.docx',
            ),
            performEgress: (_, _) async {
              called = true;
              throw StateError('must not run');
            },
          ),
        ),
      );
      expect(find.text('Unsupported file'), findsOneWidget);
      expect(find.text('notes.docx'), findsOneWidget);
      await tester.tap(find.byKey(DocumentAttachmentTile.tileKey('doc-1')));
      await tester.pump();
      expect(called, isFalse);
      expect(find.byKey(DocumentAttachmentTile.menuKey('doc-1')), findsNothing);
    });
  });
}
