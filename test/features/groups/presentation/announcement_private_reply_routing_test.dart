import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/message_context_overlay.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_viewer_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'message and viewer open the current eligible sender exactly once',
    (tester) async {
      var messageCalls = 0;
      await _pumpOverlay(tester, onMessageSenderTap: () => messageCalls += 1);

      await tester.tap(
        find.byKey(MessageContextOverlay.messageSenderActionKey),
      );
      await tester.tap(
        find.byKey(MessageContextOverlay.messageSenderActionKey),
      );
      await tester.pump();
      expect(messageCalls, 1);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();

      final dispatched = <(String, MediaViewerAction)>[];
      await _pumpViewer(
        tester,
        items: <MediaViewerItem>[_item('attachment-a')],
        onAction: (item, action) async {
          dispatched.add((item.attachmentId, action));
          return MediaViewerActionResult.success;
        },
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('media_action_messageSender')),
      );
      await tester.pump();
      expect(dispatched, <(String, MediaViewerAction)>[
        ('attachment-a', MediaViewerAction.messageSender),
      ]);
    },
  );

  testWidgets(
    'viewer swipe dispatches the exact current attachment and never the initial page',
    (tester) async {
      final dispatched = <String>[];
      await _pumpViewer(
        tester,
        items: <MediaViewerItem>[_item('attachment-a'), _item('attachment-b')],
        onAction: (item, action) async {
          dispatched.add(item.attachmentId);
          return MediaViewerActionResult.success;
        },
      );

      await tester.drag(find.byType(PageView), const Offset(-500, 0));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('media_action_messageSender')),
      );
      await tester.pump();
      expect(dispatched, <String>['attachment-b']);
    },
  );

  testWidgets(
    'stale menu state dismisses and shows only unavailable feedback',
    (tester) async {
      await _pumpOverlay(
        tester,
        onMessageSenderTap: () {
          Navigator.of(
            tester.element(find.byKey(MessageContextOverlay.overlayKey)),
          ).pop();
        },
      );
      await tester.tap(
        find.byKey(MessageContextOverlay.messageSenderActionKey),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(MessageContextOverlay.overlayKey), findsNothing);

      final source = _groupWiredSource();
      expect(source, contains('announcement_private_reply_unavailable'));
      expect(source, contains('_resolveAnnouncementPrivateReply'));
      expect(
        RegExp(
          r'AnnouncementPrivateReplyRequest\([\s\S]*?senderPeerId:',
        ).hasMatch(source),
        isTrue,
        reason: 'dispatch must preserve the selected two-field request',
      );
    },
  );

  test('route failure dismisses and shows only open-failure feedback', () {
    final source = _groupWiredSource();
    expect(source, contains('announcement_private_reply_open_failed'));
    expect(source, contains('openAnnouncementSenderConversation'));
    expect(source, contains('catch'));
  });

  test('double taps coalesce while resolution or opener is pending', () {
    final source = _groupWiredSource();
    expect(source, contains('_announcementPrivateReplyDispatchInFlight'));
    expect(
      RegExp(
        r'if \(_announcementPrivateReplyDispatchInFlight\)[\s\S]*?return',
      ).hasMatch(source),
      isTrue,
    );
    expect(source, contains('finally'));
  });

  testWidgets('private reply copy is localized accessible and RTL safe', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    const cases = <(Locale, String, String, String)>[
      (
        Locale('en'),
        'Message sender',
        'Message sender is unavailable.',
        'Couldn’t open the conversation.',
      ),
      (
        Locale('de'),
        'Absender anschreiben',
        'Der Absender kann nicht angeschrieben werden.',
        'Die Unterhaltung konnte nicht geöffnet werden.',
      ),
      (
        Locale('ar'),
        'مراسلة المرسل',
        'مراسلة المرسل غير متاحة.',
        'تعذّر فتح المحادثة.',
      ),
    ];

    for (final entry in cases) {
      final (locale, action, unavailable, failed) = entry;
      final l10n = await AppLocalizations.delegate.load(locale);
      expect(l10n.announcement_private_reply_action, action);
      expect(l10n.announcement_private_reply_unavailable, unavailable);
      expect(l10n.announcement_private_reply_open_failed, failed);

      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await _pumpOverlay(
        tester,
        locale: locale,
        showReplyAction: true,
        showEditAction: true,
        onMessageSenderTap: () {},
      );
      expect(find.text(action), findsOneWidget);
      expect(tester.takeException(), isNull);
      final replyAction = find.byKey(MessageContextOverlay.replyActionKey);
      final messageSenderAction = find.byKey(
        MessageContextOverlay.messageSenderActionKey,
      );
      final editAction = find.byKey(MessageContextOverlay.editActionKey);
      expect(
        find.descendant(
          of: messageSenderAction,
          matching: find.byIcon(Icons.chat_bubble_outline_rounded),
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(replyAction).dy,
        lessThan(tester.getTopLeft(messageSenderAction).dy),
      );
      expect(
        tester.getTopLeft(messageSenderAction).dy,
        lessThan(tester.getTopLeft(editAction).dy),
      );
      final messageSenderInkWell = find.descendant(
        of: messageSenderAction,
        matching: find.byType(InkWell),
      );
      expect(tester.getSemantics(messageSenderInkWell).label, action);
      expect(tester.widget<InkWell>(messageSenderInkWell).onTap, isNotNull);
      final direction = Directionality.of(tester.element(messageSenderAction));
      expect(
        direction,
        locale.languageCode == 'ar' ? TextDirection.rtl : TextDirection.ltr,
      );

      final viewerCalls = <MediaViewerAction>[];
      await _pumpViewer(
        tester,
        locale: locale,
        items: <MediaViewerItem>[
          _item(
            'localized-action',
            capabilities: const <MediaViewerAction>{
              MediaViewerAction.reply,
              MediaViewerAction.messageSender,
              MediaViewerAction.save,
            },
          ),
        ],
        onAction: (item, viewerAction) async {
          viewerCalls.add(viewerAction);
          return MediaViewerActionResult.success;
        },
      );
      final viewerReply = find.byKey(
        const ValueKey<String>('media_action_reply'),
      );
      final viewerMessageSender = find.byKey(
        const ValueKey<String>('media_action_messageSender'),
      );
      final viewerSave = find.byKey(
        const ValueKey<String>('media_action_save'),
      );
      expect(tester.widget<IconButton>(viewerMessageSender).tooltip, action);
      expect(find.bySemanticsLabel(action), findsOneWidget);
      expect(
        find.descendant(
          of: viewerMessageSender,
          matching: find.byIcon(Icons.chat_bubble_outline_rounded),
        ),
        findsOneWidget,
      );
      final replyX = tester.getCenter(viewerReply).dx;
      final messageSenderX = tester.getCenter(viewerMessageSender).dx;
      final saveX = tester.getCenter(viewerSave).dx;
      if (locale.languageCode == 'ar') {
        expect(replyX, greaterThan(messageSenderX));
        expect(messageSenderX, greaterThan(saveX));
      } else {
        expect(replyX, lessThan(messageSenderX));
        expect(messageSenderX, lessThan(saveX));
      }
      expect(viewerCalls, isEmpty);
      expect(tester.takeException(), isNull);
    }
    semantics.dispose();
  });

  testWidgets(
    'discussion Reply reactions and private viewer protection stay unchanged',
    (tester) async {
      final dispatches = <MediaViewerAction>[];
      await _pumpViewer(
        tester,
        privacyMinimized: true,
        items: <MediaViewerItem>[_item('protected-message-sender')],
        onAction: (item, action) async {
          dispatches.add(action);
          return MediaViewerActionResult.success;
        },
      );
      expect(
        find.byKey(const ValueKey<String>('media_action_messageSender')),
        findsNothing,
      );
      expect(find.byIcon(Icons.chat_bubble_outline_rounded), findsNothing);
      await tester.tapAt(const Offset(300, 28));
      await tester.pump();
      expect(dispatches, isEmpty);

      final viewer = File(
        'lib/shared/widgets/media/full_screen_typed_media_viewer.dart',
      ).readAsStringSync();
      final group = _groupWiredSource();
      expect(viewer, contains('widget.privacyMinimized'));
      expect(viewer, contains('const <Widget>[]'));
      expect(group, contains('case MediaViewerAction.reply:'));
      expect(group, contains('MediaViewerAction.messageSender'));

      for (final path in <String>[
        'lib/features/conversation/presentation/screens/conversation_screen.dart',
        'lib/features/conversation/presentation/screens/direct_shared_media_library_screen.dart',
        'lib/features/groups/presentation/screens/group_shared_media_library_screen.dart',
      ]) {
        final source = File(path).readAsStringSync();
        expect(
          RegExp(r'MediaViewerAction\.messageSender').allMatches(source),
          hasLength(1),
          reason:
              '$path must handle the announcement-only enum solely in its '
              'fail-closed dispatch adapter and never authorize it',
        );
        expect(
          RegExp(
            r'case MediaViewerAction\.messageSender:[\s\S]{0,500}?'
            r'return MediaViewerActionResult\.failure;',
          ).hasMatch(source),
          isTrue,
          reason: '$path must reject a forged Message sender dispatch',
        );
      }
    },
  );
}

Future<void> _pumpOverlay(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  bool showReplyAction = false,
  bool showEditAction = false,
  required VoidCallback onMessageSenderTap,
}) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () {
                showDialog<void>(
                  context: context,
                  useSafeArea: false,
                  barrierColor: Colors.transparent,
                  builder: (_) => MessageContextOverlay(
                    anchorRect: const Rect.fromLTWH(20, 80, 220, 80),
                    selectedMessage: const SizedBox(width: 220, height: 80),
                    showReactionBar: false,
                    showReplyAction: showReplyAction,
                    showMessageSenderAction: true,
                    showEditAction: showEditAction,
                    onMessageSenderTap: onMessageSenderTap,
                    onReplyTap: () {},
                    onEditTap: () {},
                    onDismiss: () => Navigator.of(context).pop(),
                  ),
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

Future<void> _pumpViewer(
  WidgetTester tester, {
  Locale locale = const Locale('en'),
  required List<MediaViewerItem> items,
  required MediaViewerActionCallback onAction,
  bool privacyMinimized = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: FullScreenTypedMediaViewer(
        items: items,
        onAction: onAction,
        privacyMinimized: privacyMinimized,
      ),
    ),
  );
  await tester.pump();
}

MediaViewerItem _item(
  String id, {
  Set<MediaViewerAction> capabilities = const <MediaViewerAction>{
    MediaViewerAction.messageSender,
  },
}) => MediaViewerItem(
  attachmentId: id,
  messageId: 'announcement-parent',
  kind: MediaViewerKind.image,
  mime: 'image/jpeg',
  owner: MediaOwnerLane.group,
  capabilities: MediaViewerActionCapabilities(allowed: capabilities),
);

String _groupWiredSource() => File(
  'lib/features/groups/presentation/screens/group_conversation_wired.dart',
).readAsStringSync();
