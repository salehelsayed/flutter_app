import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_viewer_item.dart';

void main() {
  // Transport imports the shared viewer module must never pull in.
  final forbiddenImport = RegExp(
    r'(p2p|go_mknoon|go-mknoon|gobridge|go_bridge|bridge|/relay|repositor'
    r'|_use_case|/send_|delete_message|/inbox)',
    caseSensitive: false,
  );

  const moduleFiles = <String>[
    'lib/shared/widgets/media/media_viewer_item.dart',
    'lib/shared/widgets/media/media_playback_adapter.dart',
    'lib/shared/widgets/media/media_video_controls.dart',
    'lib/shared/widgets/media/media_video_resume_controller.dart',
    'lib/shared/widgets/media/full_screen_typed_media_viewer.dart',
  ];

  Widget wrap(Widget child) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );

  testWidgets(
    'viewer remains callback-only transport-free and diagnostics are redacted',
    (tester) async {
      // (a) No transport imports anywhere in the typed viewer module.
      for (final path in moduleFiles) {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: '$path is missing');
        final importLines = file
            .readAsStringSync()
            .split('\n')
            .where((line) => line.trimLeft().startsWith('import '));
        for (final line in importLines) {
          expect(
            forbiddenImport.hasMatch(line),
            isFalse,
            reason: '$path imports a forbidden transport dependency:\n$line',
          );
        }
      }

      // (b) Action diagnostics carry redacted IDs/outcomes, never user metadata.
      final events = <Map<String, dynamic>>[];
      debugSetFlowEventSink(events.add);
      addTearDown(() => debugSetFlowEventSink(null));

      const secretPath = '/tmp/SECRET-PATH-XYZ.jpg';
      const secretCaption = 'SECRET-CAPTION-VALUE';
      const secretSender = 'SECRET-SENDER-NAME';

      final item = MediaViewerItem(
        attachmentId: 'ATTACHMENT-1234567890',
        messageId: 'MESSAGE-9999',
        kind: MediaViewerKind.image,
        mime: 'image/jpeg',
        owner: MediaOwnerLane.direct,
        localPath: secretPath,
        caption: secretCaption,
        senderLabel: secretSender,
        capabilities: const MediaViewerActionCapabilities(
          allowed: {MediaViewerAction.save},
        ),
      );

      await tester.pumpWidget(
        wrap(
          FullScreenTypedMediaViewer(
            items: [item],
            onAction: (_, _) async => MediaViewerActionResult.success,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('media_action_save')));
      await tester.pump();
      await tester.pump();

      final actionEvents = events
          .where((e) => e['event'] == 'MEDIA_VIEWER_ACTION')
          .toList();
      expect(actionEvents, isNotEmpty);

      final encoded = jsonEncode(actionEvents);
      expect(encoded.contains('SECRET-PATH-XYZ'), isFalse);
      expect(encoded.contains(secretCaption), isFalse);
      expect(encoded.contains(secretSender), isFalse);
      expect(
        encoded.contains('ATTACHMENT-1234567890'),
        isFalse,
        reason: 'full attachment id must not be logged raw',
      );

      final details = actionEvents.first['details'] as Map<String, dynamic>;
      expect(details['action'], 'save');
      expect(details['outcome'], 'success');
      expect((details['attachmentId'] as String).length, lessThanOrEqualTo(8));

      // The compact popup must enter the same redacted callback/diagnostic
      // boundary; menu-local logging of the item would fail these assertions.
      events.clear();
      final compactItem = MediaViewerItem(
        attachmentId: item.attachmentId,
        messageId: item.messageId,
        kind: item.kind,
        mime: item.mime,
        owner: item.owner,
        localPath: item.localPath,
        caption: item.caption,
        senderLabel: item.senderLabel,
        actionPresentation: MediaViewerActionPresentation.compactImageOverlay,
        capabilities: item.capabilities,
      );
      await tester.pumpWidget(
        wrap(
          FullScreenTypedMediaViewer(
            key: const ValueKey('compact-boundary-viewer'),
            items: [compactItem],
            onAction: (_, _) async => MediaViewerActionResult.success,
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('media_action_more')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('media_action_save')));
      await tester.pump();
      await tester.pump();

      final compactEvents = events
          .where((event) => event['event'] == 'MEDIA_VIEWER_ACTION')
          .toList();
      expect(compactEvents, hasLength(1));
      final compactEncoded = jsonEncode(compactEvents);
      expect(compactEncoded.contains('SECRET-PATH-XYZ'), isFalse);
      expect(compactEncoded.contains(secretCaption), isFalse);
      expect(compactEncoded.contains(secretSender), isFalse);
      expect(compactEncoded.contains('ATTACHMENT-1234567890'), isFalse);
      expect(compactEvents.single['details'], containsPair('action', 'save'));
    },
  );
}
