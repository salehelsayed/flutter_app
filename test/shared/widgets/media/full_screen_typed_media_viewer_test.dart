import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/app_owned_media_path_authority.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/picture_in_picture_gateway.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_picture_in_picture_controller.dart';
import 'package:flutter_app/shared/widgets/media/media_playback_adapter.dart';
import 'package:flutter_app/shared/widgets/media/media_video_controls.dart';
import 'package:flutter_app/shared/widgets/media/media_viewer_item.dart';

import 'fake_media_playback_adapter.dart';

void main() {
  Widget wrap(Widget child, {Locale? locale}) => MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: child,
  );

  MediaViewerItem imageItem({
    required String attachmentId,
    required String messageId,
    required MediaOwnerLane? owner,
    Set<MediaViewerAction> caps = const <MediaViewerAction>{},
    MediaViewerActionPresentation actionPresentation =
        MediaViewerActionPresentation.standardToolbar,
    MediaViewerProtection protection = const MediaViewerProtection(),
    String? caption,
    String? sender,
    DateTime? timestamp,
    int? width,
    int? height,
    int? sizeBytes,
  }) => MediaViewerItem(
    attachmentId: attachmentId,
    messageId: messageId,
    kind: MediaViewerKind.image,
    mime: 'image/jpeg',
    owner: owner,
    localPath: '/tmp/secret-$attachmentId.jpg',
    caption: caption,
    senderLabel: sender,
    timestamp: timestamp,
    width: width,
    height: height,
    sizeBytes: sizeBytes,
    actionPresentation: actionPresentation,
    capabilities: MediaViewerActionCapabilities(allowed: caps),
    protection: protection,
  );

  MediaViewerItem videoItem({
    required String attachmentId,
    required String messageId,
    required MediaOwnerLane? owner,
    Set<MediaViewerAction> caps = const <MediaViewerAction>{},
    MediaViewerActionPresentation actionPresentation =
        MediaViewerActionPresentation.standardToolbar,
    String? caption,
    String? sender,
    DateTime? timestamp,
    int? durationMs,
    int? sizeBytes,
    bool canEnterPictureInPicture = false,
    MediaViewerProtection protection = const MediaViewerProtection(),
  }) => MediaViewerItem(
    attachmentId: attachmentId,
    messageId: messageId,
    kind: MediaViewerKind.video,
    mime: 'video/mp4',
    owner: owner,
    localPath: '/tmp/secret-$attachmentId.mp4',
    caption: caption,
    senderLabel: sender,
    timestamp: timestamp,
    durationMs: durationMs,
    sizeBytes: sizeBytes,
    actionPresentation: actionPresentation,
    canEnterPictureInPicture: canEnterPictureInPicture,
    protection: protection,
    capabilities: MediaViewerActionCapabilities(allowed: caps),
  );

  testWidgets(
    'actions always target the currently visible typed item and owner',
    (tester) async {
      final dispatched = <({MediaViewerItem item, MediaViewerAction action})>[];

      final itemA = imageItem(
        attachmentId: 'att-A',
        messageId: 'msg-A',
        owner: MediaOwnerLane.direct,
        caps: {MediaViewerAction.forward, MediaViewerAction.delete},
      );
      final itemB = imageItem(
        attachmentId: 'att-B',
        messageId: 'msg-B',
        owner: MediaOwnerLane.group,
        caps: {MediaViewerAction.forward, MediaViewerAction.delete},
      );

      await tester.pumpWidget(
        wrap(
          FullScreenTypedMediaViewer(
            items: [itemA, itemB],
            onAction: (item, action) async {
              dispatched.add((item: item, action: action));
              return MediaViewerActionResult.success;
            },
          ),
        ),
      );
      await tester.pump();

      expect(find.text('1 / 2'), findsOneWidget);
      expect(find.byKey(const ValueKey('media_action_more')), findsNothing);
      expect(
        tester.getCenter(find.byKey(const ValueKey('media_action_delete'))).dy,
        lessThan(tester.getSize(find.byType(Scaffold)).height / 2),
      );

      await tester.tap(find.byKey(const ValueKey('media_action_delete')));
      await tester.pump();

      expect(dispatched, hasLength(1));
      expect(dispatched.single.item.attachmentId, 'att-A');
      expect(dispatched.single.item.messageId, 'msg-A');
      expect(dispatched.single.item.owner, MediaOwnerLane.direct);
      expect(dispatched.single.action, MediaViewerAction.delete);

      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();

      expect(find.text('2 / 2'), findsOneWidget);
      expect(find.byKey(const ValueKey('media_action_more')), findsNothing);
      expect(
        tester.getCenter(find.byKey(const ValueKey('media_action_delete'))).dy,
        lessThan(tester.getSize(find.byType(Scaffold)).height / 2),
      );

      await tester.tap(find.byKey(const ValueKey('media_action_delete')));
      await tester.pump();

      expect(dispatched, hasLength(2));
      expect(dispatched.last.item.attachmentId, 'att-B');
      expect(dispatched.last.item.messageId, 'msg-B');
      expect(dispatched.last.item.owner, MediaOwnerLane.group);
      expect(dispatched.last.action, MediaViewerAction.delete);
    },
  );

  testWidgets(
    'capabilities and ownership fail closed and action outcomes settle once',
    (tester) async {
      final calls = <({MediaViewerItem item, MediaViewerAction action})>[];
      Future<MediaViewerActionResult> record(
        MediaViewerItem item,
        MediaViewerAction action,
      ) async {
        calls.add((item: item, action: action));
        return MediaViewerActionResult.success;
      }

      // Unauthorized capability -> button absent.
      await tester.pumpWidget(
        wrap(
          FullScreenTypedMediaViewer(
            items: [
              imageItem(
                attachmentId: 'no-cap',
                messageId: 'm',
                owner: MediaOwnerLane.direct,
                caps: const {},
              ),
            ],
            onAction: record,
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('media_action_save')), findsNothing);
      expect(find.byKey(const ValueKey('media_action_delete')), findsNothing);

      // Authorized + eligible -> present and enabled.
      await tester.pumpWidget(
        wrap(
          FullScreenTypedMediaViewer(
            items: [
              imageItem(
                attachmentId: 'ok',
                messageId: 'm',
                owner: MediaOwnerLane.direct,
                caps: {MediaViewerAction.save},
              ),
            ],
            onAction: record,
          ),
        ),
      );
      await tester.pump();
      final okButton = tester.widget<IconButton>(
        find.byKey(const ValueKey('media_action_save')),
      );
      expect(okButton.onPressed, isNotNull);

      // Unresolved owner (capability granted) -> present but disabled, no call.
      await tester.pumpWidget(
        wrap(
          FullScreenTypedMediaViewer(
            items: [
              imageItem(
                attachmentId: 'unresolved',
                messageId: 'm',
                owner: null,
                caps: {MediaViewerAction.delete},
              ),
            ],
            onAction: record,
          ),
        ),
      );
      await tester.pump();
      final unresolvedButton = tester.widget<IconButton>(
        find.byKey(const ValueKey('media_action_delete')),
      );
      expect(unresolvedButton.onPressed, isNull);
      await tester.tap(
        find.byKey(const ValueKey('media_action_delete')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(calls, isEmpty);

      // Unavailable (not downloaded) -> disabled, no call.
      await tester.pumpWidget(
        wrap(
          FullScreenTypedMediaViewer(
            items: [
              imageItem(
                attachmentId: 'unavailable',
                messageId: 'm',
                owner: MediaOwnerLane.direct,
                caps: {MediaViewerAction.save},
                protection: const MediaViewerProtection(isDownloaded: false),
              ),
            ],
            onAction: record,
          ),
        ),
      );
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('media_action_save')))
            .onPressed,
        isNull,
      );

      // Protected -> disabled.
      await tester.pumpWidget(
        wrap(
          FullScreenTypedMediaViewer(
            items: [
              imageItem(
                attachmentId: 'protected',
                messageId: 'm',
                owner: MediaOwnerLane.direct,
                caps: {MediaViewerAction.save},
                protection: const MediaViewerProtection(isProtected: true),
              ),
            ],
            onAction: record,
          ),
        ),
      );
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('media_action_save')))
            .onPressed,
        isNull,
      );
      expect(calls, isEmpty);

      // Async cancel/failure settles once and leaves the viewer mounted.
      final pending = Completer<MediaViewerActionResult>();
      var asyncCalls = 0;
      await tester.pumpWidget(
        wrap(
          FullScreenTypedMediaViewer(
            items: [
              imageItem(
                attachmentId: 'async',
                messageId: 'm',
                owner: MediaOwnerLane.direct,
                caps: {MediaViewerAction.save},
              ),
            ],
            onAction: (item, action) {
              asyncCalls++;
              return pending.future;
            },
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byKey(const ValueKey('media_action_save')));
      await tester.pump();
      expect(asyncCalls, 1);
      // In-flight -> button disabled, a second tap cannot double-submit.
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('media_action_save')))
            .onPressed,
        isNull,
      );
      await tester.tap(
        find.byKey(const ValueKey('media_action_save')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(asyncCalls, 1);

      pending.complete(MediaViewerActionResult.failure);
      await tester.pump();

      // The viewer stays mounted and surfaces exactly one truthful result.
      expect(find.byType(FullScreenTypedMediaViewer), findsOneWidget);
      expect(
        find.byKey(const ValueKey('media_action_result_failure')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'compact image layout places overflow forward and delete on safe corners',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const caps = <MediaViewerAction>{
        MediaViewerAction.save,
        MediaViewerAction.share,
        MediaViewerAction.info,
        MediaViewerAction.reply,
        MediaViewerAction.forward,
        MediaViewerAction.delete,
      };
      final items = [
        imageItem(
          attachmentId: 'compact-layout-a',
          messageId: 'compact-layout-message',
          owner: MediaOwnerLane.direct,
          caps: caps,
          actionPresentation: MediaViewerActionPresentation.compactImageOverlay,
        ),
        imageItem(
          attachmentId: 'compact-layout-b',
          messageId: 'compact-layout-message',
          owner: MediaOwnerLane.direct,
          caps: caps,
          actionPresentation: MediaViewerActionPresentation.compactImageOverlay,
        ),
      ];

      for (final locale in const [Locale('en'), Locale('ar')]) {
        await tester.pumpWidget(
          wrap(
            MediaQuery(
              data: const MediaQueryData(
                size: Size(320, 568),
                padding: EdgeInsets.fromLTRB(10, 24, 20, 34),
              ),
              child: FullScreenTypedMediaViewer(
                key: ValueKey('compact-layout-${locale.languageCode}'),
                items: items,
                onAction: (_, _) async => MediaViewerActionResult.success,
              ),
            ),
            locale: locale,
          ),
        );
        await tester.pump();

        final more = find.byKey(const ValueKey('media_action_more'));
        final forward = find.byKey(const ValueKey('media_action_forward'));
        final delete = find.byKey(const ValueKey('media_action_delete'));
        expect(find.byIcon(Icons.arrow_back), findsOneWidget);
        expect(find.text('1 / 2'), findsOneWidget);
        expect(more, findsOneWidget);
        expect(forward, findsOneWidget);
        expect(delete, findsOneWidget);
        for (final action in const ['save', 'share', 'info', 'reply']) {
          expect(find.byKey(ValueKey('media_action_$action')), findsNothing);
        }

        for (final control in [more, forward, delete]) {
          expect(tester.getSize(control), const Size(48, 48));
        }
        for (final action in const ['more', 'forward', 'delete']) {
          expect(
            tester.getSize(
              find.byKey(ValueKey('media_action_${action}_visual')),
            ),
            const Size(36, 36),
          );
        }

        final moreRect = tester.getRect(more);
        final forwardRect = tester.getRect(forward);
        final deleteRect = tester.getRect(delete);
        expect(moreRect.center.dy, lessThan(568 / 2));
        expect(forwardRect.center.dy, greaterThan(568 / 2));
        expect(deleteRect.center.dy, greaterThan(568 / 2));
        expect(forwardRect.bottom, lessThanOrEqualTo(568 - 34));
        expect(deleteRect.bottom, lessThanOrEqualTo(568 - 34));
        if (locale.languageCode == 'ar') {
          expect(forwardRect.center.dx, lessThan(deleteRect.center.dx));
          expect(moreRect.center.dx, lessThan(320 / 2));
        } else {
          expect(forwardRect.center.dx, greaterThan(deleteRect.center.dx));
          expect(moreRect.center.dx, greaterThan(320 / 2));
        }

        await tester.tap(forward);
        await tester.pump();
        await tester.pump();
        final result = find.byKey(
          const ValueKey('media_action_result_success'),
        );
        expect(result, findsOneWidget);
        expect(tester.getRect(result).overlaps(forwardRect), isFalse);
        expect(tester.getRect(result).overlaps(deleteRect), isFalse);
      }
    },
  );

  testWidgets(
    'compact overflow lists localized image actions in order and targets the current item',
    (tester) async {
      const expected = <String, ({String more, List<String> actions})>{
        'en': (
          more: 'More actions',
          actions: ['Save image', 'Share', 'Info', 'Reply'],
        ),
        'de': (
          more: 'Weitere Aktionen',
          actions: ['Bild speichern', 'Teilen', 'Info', 'Antworten'],
        ),
        'ar': (
          more: 'المزيد من الإجراءات',
          actions: ['حفظ الصورة', 'مشاركة', 'معلومات', 'رد'],
        ),
      };
      const caps = <MediaViewerAction>{
        MediaViewerAction.save,
        MediaViewerAction.share,
        MediaViewerAction.info,
        MediaViewerAction.reply,
        MediaViewerAction.forward,
        MediaViewerAction.delete,
      };

      for (final locale in const [Locale('en'), Locale('de'), Locale('ar')]) {
        final dispatched =
            <({MediaViewerItem item, MediaViewerAction action})>[];
        final itemA = imageItem(
          attachmentId: 'compact-menu-a-${locale.languageCode}',
          messageId: 'compact-menu-message',
          owner: MediaOwnerLane.direct,
          caps: caps,
          actionPresentation: MediaViewerActionPresentation.compactImageOverlay,
        );
        final itemB = imageItem(
          attachmentId: 'compact-menu-b-${locale.languageCode}',
          messageId: 'compact-menu-message',
          owner: MediaOwnerLane.direct,
          caps: caps,
          actionPresentation: MediaViewerActionPresentation.compactImageOverlay,
        );
        await tester.pumpWidget(
          wrap(
            FullScreenTypedMediaViewer(
              key: ValueKey('compact-menu-${locale.languageCode}'),
              items: [itemA, itemB],
              onAction: (item, action) async {
                dispatched.add((item: item, action: action));
                return MediaViewerActionResult.success;
              },
            ),
            locale: locale,
          ),
        );
        await tester.pump();
        await tester.fling(
          find.byType(PageView),
          Offset(locale.languageCode == 'ar' ? 400 : -400, 0),
          1000,
        );
        await tester.pumpAndSettle();
        expect(find.text('2 / 2'), findsOneWidget);

        final more = tester.widget<PopupMenuButton<MediaViewerAction>>(
          find.byKey(const ValueKey('media_action_more')),
        );
        expect(more.tooltip, expected[locale.languageCode]!.more);
        await tester.tap(find.byKey(const ValueKey('media_action_more')));
        await tester.pumpAndSettle();

        final actionKeys = const [
          ValueKey('media_action_save'),
          ValueKey('media_action_share'),
          ValueKey('media_action_info'),
          ValueKey('media_action_reply'),
        ];
        const actionIcons = <IconData>[
          Icons.download_rounded,
          Icons.ios_share_rounded,
          Icons.info_outline_rounded,
          Icons.reply_rounded,
        ];
        for (var index = 0; index < actionKeys.length; index++) {
          final item = find.byKey(actionKeys[index]);
          final label = find.descendant(
            of: item,
            matching: find.text(expected[locale.languageCode]!.actions[index]),
          );
          final icon = find.descendant(of: item, matching: find.byType(Icon));
          expect(item, findsOneWidget);
          expect(label, findsOneWidget);
          expect(icon, findsOneWidget);

          final iconWidget = tester.widget<Icon>(icon);
          expect(iconWidget.icon, actionIcons[index]);
          expect(iconWidget.size, 20);
          expect(iconWidget.color, Colors.white);

          final iconRect = tester.getRect(icon);
          final labelRect = tester.getRect(label);
          if (Directionality.of(tester.element(item)) == TextDirection.rtl) {
            expect(iconRect.left - labelRect.right, closeTo(12, 0.01));
          } else {
            expect(labelRect.left - iconRect.right, closeTo(12, 0.01));
          }
          if (index > 0) {
            expect(
              tester.getCenter(item).dy,
              greaterThan(
                tester.getCenter(find.byKey(actionKeys[index - 1])).dy,
              ),
            );
          }
        }
        for (final key in const [
          ValueKey('media_action_forward'),
          ValueKey('media_action_delete'),
        ]) {
          expect(
            find.ancestor(
              of: find.byKey(key),
              matching: find.byType(PopupMenuItem<MediaViewerAction>),
            ),
            findsNothing,
          );
        }

        await tester.tap(find.byKey(const ValueKey('media_action_info')));
        await tester.pump();
        expect(dispatched, hasLength(1));
        expect(dispatched.single.item.attachmentId, itemB.attachmentId);
        expect(dispatched.single.action, MediaViewerAction.info);
      }
    },
  );

  testWidgets(
    'compact actions remain capability gated and single dispatch while pending',
    (tester) async {
      const compact = MediaViewerActionPresentation.compactImageOverlay;
      final calls = <({MediaViewerItem item, MediaViewerAction action})>[];

      await tester.pumpWidget(
        wrap(
          FullScreenTypedMediaViewer(
            key: const ValueKey('compact-subset'),
            items: [
              imageItem(
                attachmentId: 'compact-subset',
                messageId: 'compact-message',
                owner: MediaOwnerLane.direct,
                caps: const {MediaViewerAction.save, MediaViewerAction.forward},
                actionPresentation: compact,
              ),
            ],
            onAction: (item, action) async {
              calls.add((item: item, action: action));
              return MediaViewerActionResult.success;
            },
          ),
        ),
      );
      await tester.pump();
      expect(find.byKey(const ValueKey('media_action_more')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('media_action_forward')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('media_action_delete')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('media_action_more')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('media_action_save')), findsOneWidget);
      expect(find.byKey(const ValueKey('media_action_share')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('media_action_save')));
      await tester.pumpAndSettle();
      expect(calls.single.action, MediaViewerAction.save);

      await tester.pumpWidget(
        wrap(
          FullScreenTypedMediaViewer(
            key: const ValueKey('compact-ownerless'),
            items: [
              imageItem(
                attachmentId: 'compact-ownerless',
                messageId: 'compact-message',
                owner: null,
                caps: const {
                  MediaViewerAction.save,
                  MediaViewerAction.forward,
                  MediaViewerAction.delete,
                },
                actionPresentation: compact,
              ),
            ],
            onAction: (item, action) async {
              calls.add((item: item, action: action));
              return MediaViewerActionResult.success;
            },
          ),
        ),
      );
      await tester.pump();
      expect(
        tester
            .widget<PopupMenuButton<MediaViewerAction>>(
              find.byKey(const ValueKey('media_action_more')),
            )
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('media_action_forward')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('media_action_delete')),
            )
            .onPressed,
        isNull,
      );
      expect(calls, hasLength(1));

      final pending = Completer<MediaViewerActionResult>();
      await tester.pumpWidget(
        wrap(
          FullScreenTypedMediaViewer(
            key: const ValueKey('compact-pending'),
            items: [
              imageItem(
                attachmentId: 'compact-pending',
                messageId: 'compact-message',
                owner: MediaOwnerLane.direct,
                caps: const {
                  MediaViewerAction.save,
                  MediaViewerAction.forward,
                  MediaViewerAction.delete,
                },
                actionPresentation: compact,
              ),
            ],
            onAction: (item, action) {
              calls.add((item: item, action: action));
              return pending.future;
            },
          ),
        ),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('media_action_forward')));
      await tester.pump();
      expect(calls, hasLength(2));
      expect(calls.last.action, MediaViewerAction.forward);
      expect(
        tester
            .widget<PopupMenuButton<MediaViewerAction>>(
              find.byKey(const ValueKey('media_action_more')),
            )
            .enabled,
        isFalse,
      );
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('media_action_delete')),
            )
            .onPressed,
        isNull,
      );
      await tester.tap(
        find.byKey(const ValueKey('media_action_delete')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(calls, hasLength(2));
      pending.complete(MediaViewerActionResult.success);
      await tester.pump();

      await tester.pumpWidget(
        wrap(
          FullScreenTypedMediaViewer(
            key: const ValueKey('compact-private'),
            privacyMinimized: true,
            items: [
              imageItem(
                attachmentId: 'compact-private',
                messageId: 'compact-private-message',
                owner: MediaOwnerLane.direct,
                caps: const {
                  MediaViewerAction.save,
                  MediaViewerAction.share,
                  MediaViewerAction.info,
                  MediaViewerAction.reply,
                  MediaViewerAction.forward,
                  MediaViewerAction.delete,
                },
                actionPresentation: compact,
              ),
            ],
            onAction: (item, action) async {
              calls.add((item: item, action: action));
              return MediaViewerActionResult.success;
            },
          ),
        ),
      );
      await tester.pump();
      for (final action in const [
        'more',
        'save',
        'share',
        'info',
        'reply',
        'forward',
        'delete',
      ]) {
        expect(find.byKey(ValueKey('media_action_$action')), findsNothing);
      }
      expect(calls, hasLength(2));
    },
  );

  testWidgets(
    'compact video overflow lists and dispatches every authorized media action',
    (tester) async {
      final compactVideo = MediaViewerActionPresentation.values.singleWhere(
        (value) => value.name == 'compactVideoOverflow',
      );
      const orderedActions = <MediaViewerAction>[
        MediaViewerAction.save,
        MediaViewerAction.share,
        MediaViewerAction.info,
        MediaViewerAction.reply,
        MediaViewerAction.forward,
        MediaViewerAction.delete,
      ];
      const expectedLabels = <String, List<String>>{
        'en': ['Save', 'Share', 'Info', 'Reply', 'Forward', 'Delete'],
        'de': [
          'Speichern',
          'Teilen',
          'Info',
          'Antworten',
          'Weiterleiten',
          'Löschen',
        ],
        'ar': ['حفظ', 'مشاركة', 'معلومات', 'رد', 'إعادة توجيه', 'حذف'],
      };
      const expectedIcons = <IconData>[
        Icons.download_rounded,
        Icons.ios_share_rounded,
        Icons.info_outline_rounded,
        Icons.reply_rounded,
        Icons.forward_rounded,
        Icons.delete_outline_rounded,
      ];

      for (final locale in const [Locale('en'), Locale('de'), Locale('ar')]) {
        final dispatched =
            <({MediaViewerItem item, MediaViewerAction action})>[];
        final first = videoItem(
          attachmentId: 'compact-video-a-${locale.languageCode}',
          messageId: 'compact-video-message',
          owner: MediaOwnerLane.direct,
          caps: orderedActions.toSet(),
          actionPresentation: compactVideo,
        );
        final second = videoItem(
          attachmentId: 'compact-video-b-${locale.languageCode}',
          messageId: 'compact-video-message',
          owner: MediaOwnerLane.direct,
          caps: orderedActions.toSet(),
          actionPresentation: compactVideo,
        );

        await tester.pumpWidget(
          wrap(
            MediaQuery(
              data: const MediaQueryData(size: Size(320, 568)),
              child: FullScreenTypedMediaViewer(
                key: ValueKey('compact-video-${locale.languageCode}'),
                items: [first, second],
                playbackAdapterFactory: (_) => FakeMediaPlaybackAdapter(),
                onAction: (item, action) async {
                  dispatched.add((item: item, action: action));
                  return MediaViewerActionResult.success;
                },
              ),
            ),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();
        await tester.fling(
          find.byType(PageView),
          Offset(locale.languageCode == 'ar' ? 400 : -400, 0),
          1000,
        );
        await tester.pumpAndSettle();
        expect(find.text('2 / 2'), findsOneWidget);
        expect(find.byKey(const ValueKey('media_action_more')), findsOneWidget);
        for (final action in orderedActions) {
          expect(
            find.byKey(ValueKey('media_action_${action.name}')),
            findsNothing,
            reason: '${action.name} escaped the closed video popup',
          );
        }

        for (
          var selectedIndex = 0;
          selectedIndex < orderedActions.length;
          selectedIndex++
        ) {
          await tester.tap(find.byKey(const ValueKey('media_action_more')));
          await tester.pumpAndSettle();

          for (var rowIndex = 0; rowIndex < orderedActions.length; rowIndex++) {
            final action = orderedActions[rowIndex];
            final row = find.byKey(ValueKey('media_action_${action.name}'));
            final label = find.descendant(
              of: row,
              matching: find.text(
                expectedLabels[locale.languageCode]![rowIndex],
              ),
            );
            final icon = find.descendant(of: row, matching: find.byType(Icon));
            expect(row, findsOneWidget);
            expect(label, findsOneWidget);
            expect(icon, findsOneWidget);
            final iconWidget = tester.widget<Icon>(icon);
            expect(iconWidget.icon, expectedIcons[rowIndex]);
            expect(iconWidget.size, 20);
            expect(iconWidget.color, Colors.white);
            final iconRect = tester.getRect(icon);
            final labelRect = tester.getRect(label);
            if (Directionality.of(tester.element(row)) == TextDirection.rtl) {
              expect(iconRect.left - labelRect.right, closeTo(12, 0.01));
            } else {
              expect(labelRect.left - iconRect.right, closeTo(12, 0.01));
            }
            if (rowIndex > 0) {
              expect(
                tester.getCenter(row).dy,
                greaterThan(
                  tester
                      .getCenter(
                        find.byKey(
                          ValueKey(
                            'media_action_${orderedActions[rowIndex - 1].name}',
                          ),
                        ),
                      )
                      .dy,
                ),
              );
            }
          }
          expect(
            find.byKey(const ValueKey('media_action_picture_in_picture')),
            findsNothing,
          );

          final selected = find.byKey(
            ValueKey('media_action_${orderedActions[selectedIndex].name}'),
          );
          if (selectedIndex == orderedActions.length - 1) {
            await tester.ensureVisible(selected);
            await tester.pump();
          }
          await tester.tap(selected);
          await tester.pumpAndSettle();
        }

        expect(dispatched.map((call) => call.action), orderedActions);
        expect(dispatched.map((call) => call.item.attachmentId).toSet(), {
          second.attachmentId,
        });
        expect(tester.takeException(), isNull);
      }

      final pending = Completer<MediaViewerActionResult>();
      final pendingCalls =
          <({MediaViewerItem item, MediaViewerAction action})>[];
      await tester.pumpWidget(
        wrap(
          FullScreenTypedMediaViewer(
            key: const ValueKey('compact-video-pending'),
            items: [
              videoItem(
                attachmentId: 'compact-video-pending',
                messageId: 'compact-video-pending-message',
                owner: MediaOwnerLane.direct,
                caps: const {MediaViewerAction.save, MediaViewerAction.delete},
                actionPresentation: compactVideo,
              ),
            ],
            playbackAdapterFactory: (_) => FakeMediaPlaybackAdapter(),
            onAction: (item, action) {
              pendingCalls.add((item: item, action: action));
              return pending.future;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('media_action_more')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('media_action_save')), findsOneWidget);
      expect(find.byKey(const ValueKey('media_action_delete')), findsOneWidget);
      for (final action in const [
        MediaViewerAction.share,
        MediaViewerAction.info,
        MediaViewerAction.reply,
        MediaViewerAction.forward,
      ]) {
        expect(
          find.byKey(ValueKey('media_action_${action.name}')),
          findsNothing,
        );
      }
      await tester.tap(find.byKey(const ValueKey('media_action_save')));
      await tester.pump();
      expect(pendingCalls, hasLength(1));
      final more =
          tester.widget(find.byKey(const ValueKey('media_action_more')))
              as dynamic;
      expect(more.enabled, isFalse);
      await tester.tap(
        find.byKey(const ValueKey('media_action_more')),
        warnIfMissed: false,
      );
      await tester.pump();
      expect(pendingCalls, hasLength(1));
      pending.complete(MediaViewerActionResult.success);
      await tester.pumpAndSettle();
    },
  );

  testWidgets(
    'compact video overflow nests conditional PiP and starts exact current owner',
    (tester) async {
      final compactVideo = MediaViewerActionPresentation.values.singleWhere(
        (value) => value.name == 'compactVideoOverflow',
      );
      const caps = <MediaViewerAction>{
        MediaViewerAction.save,
        MediaViewerAction.share,
        MediaViewerAction.info,
        MediaViewerAction.reply,
        MediaViewerAction.forward,
        MediaViewerAction.delete,
      };
      final first = videoItem(
        attachmentId: 'compact-pip-first',
        messageId: 'compact-pip-message',
        owner: MediaOwnerLane.direct,
        caps: caps,
        actionPresentation: compactVideo,
        canEnterPictureInPicture: true,
      );
      final second = videoItem(
        attachmentId: 'compact-pip-second',
        messageId: 'compact-pip-message',
        owner: MediaOwnerLane.direct,
        caps: caps,
        actionPresentation: compactVideo,
        canEnterPictureInPicture: true,
      );
      final adapters = <String, List<FakeMediaPlaybackAdapter>>{};
      final gateway = _ViewerPictureInPictureGateway();
      final resume = RecordingResumeStore();
      final loaded = <MediaViewerItem>[];

      await tester.pumpWidget(
        wrap(
          FullScreenTypedMediaViewer(
            items: [first, second],
            playbackAdapterFactory: (item) {
              final adapter = FakeMediaPlaybackAdapter(
                position: const Duration(milliseconds: 3200),
              )..isPlaying = true;
              adapters.putIfAbsent(item.attachmentId, () => []).add(adapter);
              return adapter;
            },
            resumeStore: resume,
            pictureInPictureControllerFactory:
                ({required reloadCurrent, required restorePlayback}) =>
                    MediaPictureInPictureController(
                      gateway: gateway,
                      pathAuthority: _ViewerPathAuthority(),
                      reloadCurrent: reloadCurrent,
                      resumeStore: resume,
                      restorePlayback: restorePlayback,
                      pollTicks: const Stream<void>.empty(),
                      sessionIdFactory: () => 'compact-video-session',
                    ),
            loadPictureInPictureAuthorization: (item) async {
              loaded.add(item);
              return MediaPictureInPictureAuthorization(
                item: item,
                generation: Object.hash(
                  item.owner,
                  item.messageId,
                  item.attachmentId,
                ),
                policyState: MediaPictureInPicturePolicyState.ordinary,
                isIncoming: true,
                isTransferComplete: true,
                routeActive: true,
              );
            },
            onAction: (_, _) async => MediaViewerActionResult.success,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('media_action_picture_in_picture')),
        findsNothing,
      );

      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
      expect(loaded.last.attachmentId, second.attachmentId);
      final firstDisposeBaseline = adapters[first.attachmentId]!
          .map((adapter) => adapter.disposeCount)
          .fold(0, (sum, count) => sum + count);

      await tester.tap(find.byKey(const ValueKey('media_action_more')));
      await tester.pumpAndSettle();
      const pipKey = ValueKey('media_action_picture_in_picture');
      final pipRow = find.byWidgetPredicate(
        (widget) => widget is PopupMenuItem && widget.key == pipKey,
      );
      final pipButton = find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.key == pipKey,
      );
      expect(pipRow, findsOneWidget);
      expect(pipButton, findsNothing);
      expect(
        find.descendant(of: pipRow, matching: find.text('Picture in Picture')),
        findsOneWidget,
      );
      final pipIcon = find.descendant(of: pipRow, matching: find.byType(Icon));
      expect(pipIcon, findsOneWidget);
      expect(
        tester.widget<Icon>(pipIcon).icon,
        Icons.picture_in_picture_alt_rounded,
      );
      expect(
        tester.getCenter(pipRow).dy,
        lessThan(
          tester
              .getCenter(find.byKey(const ValueKey('media_action_delete')))
              .dy,
        ),
      );
      await tester.tap(pipRow);
      await tester.pumpAndSettle();
      expect(gateway.starts, hasLength(1));
      expect(gateway.starts.single.attachment, second.attachmentId);
      expect(
        adapters[first.attachmentId]!
            .map((adapter) => adapter.disposeCount)
            .fold(0, (sum, count) => sum + count),
        firstDisposeBaseline,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'metadata and action semantics follow current item in LTR and RTL',
    (tester) async {
      final image = imageItem(
        attachmentId: 'att-img',
        messageId: 'm-img',
        owner: MediaOwnerLane.direct,
        caption: 'CaptionImage',
        sender: 'Alice',
        timestamp: DateTime(2026, 7, 10, 14, 30),
        width: 800,
        height: 600,
        sizeBytes: 123456,
      );
      final video = videoItem(
        attachmentId: 'att-vid',
        messageId: 'm-vid',
        owner: MediaOwnerLane.group,
        caption: 'CaptionVideo',
        sender: 'Bob',
        timestamp: DateTime(2026, 7, 11, 9, 5),
        durationMs: 83000,
        sizeBytes: 654321,
      );

      for (final entry in <(Locale, TextDirection)>[
        (const Locale('en'), TextDirection.ltr),
        (const Locale('ar'), TextDirection.rtl),
      ]) {
        final locale = entry.$1;
        final direction = entry.$2;

        await tester.pumpWidget(
          wrap(
            FullScreenTypedMediaViewer(
              key: ValueKey('viewer-${locale.languageCode}'),
              items: [image, video],
              playbackAdapterFactory: (_) => FakeMediaPlaybackAdapter(),
            ),
            locale: locale,
          ),
        );
        await tester.pumpAndSettle();

        // Page 0 (image): every applicable detail is visible.
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('media_meta_sender')))
              .data,
          'Alice',
        );
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('media_meta_timestamp')))
              .data,
          '2026-07-10 14:30',
        );
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('media_meta_mime')))
              .data,
          'image/jpeg',
        );
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('media_meta_size')))
              .data,
          '121 KB',
        );
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('media_meta_dimensions')))
              .data,
          '800 × 600',
        );
        expect(find.byKey(const ValueKey('media_meta_duration')), findsNothing);
        expect(find.text('CaptionImage'), findsOneWidget);
        expect(find.textContaining('secret-att-img'), findsNothing);
        expect(
          Directionality.of(
            tester.element(find.byKey(const ValueKey('media_meta_caption'))),
          ),
          direction,
        );

        // Swipe to page 1 (video); the fake adapter's spinner unmounts on init.
        // PageView reverses with Directionality, so advance right in RTL.
        final flingDx = direction == TextDirection.rtl ? 500.0 : -500.0;
        await tester.fling(find.byType(PageView), Offset(flingDx, 0), 1500);
        await tester.pumpAndSettle();
        expect(find.text('2 / 2'), findsOneWidget);

        // Page 1 (video): every applicable detail follows the current page.
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('media_meta_sender')))
              .data,
          'Bob',
        );
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('media_meta_timestamp')))
              .data,
          '2026-07-11 09:05',
        );
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('media_meta_mime')))
              .data,
          'video/mp4',
        );
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('media_meta_size')))
              .data,
          '639 KB',
        );
        expect(
          tester
              .widget<Text>(find.byKey(const ValueKey('media_meta_duration')))
              .data,
          '1:23',
        );
        expect(
          find.byKey(const ValueKey('media_meta_dimensions')),
          findsNothing,
        );
        expect(find.text('CaptionVideo'), findsOneWidget);
        expect(find.text('CaptionImage'), findsNothing);
        expect(find.textContaining('secret-att-vid'), findsNothing);
      }
    },
  );

  testWidgets(
    'metadata detail visibility follows current item while captions and actions remain',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final actions = <({MediaViewerItem item, MediaViewerAction action})>[];
      const hiddenCaption = 'CAPTION_REMAINS_306';
      final hiddenCaptioned = MediaViewerItem(
        attachmentId: 'hidden-captioned-306',
        messageId: 'message-hidden-captioned-306',
        kind: MediaViewerKind.image,
        mime: 'image/x-hidden-captioned-306',
        owner: MediaOwnerLane.direct,
        localPath: '/tmp/hidden-captioned-306.jpg',
        sizeBytes: 111,
        width: 311,
        height: 211,
        caption: hiddenCaption,
        senderLabel: 'HIDDEN_SENDER_306',
        timestamp: DateTime(2026, 5, 1, 10, 11),
        showMetadataDetails: false,
        capabilities: const MediaViewerActionCapabilities(
          allowed: {MediaViewerAction.share},
        ),
      );
      final visibleVideo = videoItem(
        attachmentId: 'visible-video-306',
        messageId: 'message-visible-video-306',
        owner: MediaOwnerLane.direct,
        caption: 'VISIBLE_VIDEO_CAPTION_306',
        sender: 'VISIBLE_VIDEO_SENDER_306',
        timestamp: DateTime(2026, 5, 2, 12, 13),
        durationMs: 61000,
        sizeBytes: 222,
      );
      final hiddenCaptionless = MediaViewerItem(
        attachmentId: 'hidden-captionless-306',
        messageId: 'message-hidden-captionless-306',
        kind: MediaViewerKind.image,
        mime: 'image/x-hidden-captionless-306',
        owner: MediaOwnerLane.direct,
        localPath: '/tmp/hidden-captionless-306.jpg',
        sizeBytes: 333,
        width: 333,
        height: 233,
        senderLabel: 'HIDDEN_CAPTIONLESS_SENDER_306',
        timestamp: DateTime(2026, 5, 3, 14, 15),
        showMetadataDetails: false,
      );

      await tester.pumpWidget(
        wrap(
          FullScreenTypedMediaViewer(
            items: [hiddenCaptioned, visibleVideo, hiddenCaptionless],
            playbackAdapterFactory: (_) => FakeMediaPlaybackAdapter(),
            onAction: (item, action) async {
              actions.add((item: item, action: action));
              return MediaViewerActionResult.success;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      const detailKeys = <String>[
        'media_meta_sender',
        'media_meta_timestamp',
        'media_meta_mime',
        'media_meta_size',
        'media_meta_dimensions',
        'media_meta_duration',
      ];
      void expectHiddenDetails(List<String> values) {
        for (final key in detailKeys) {
          expect(find.byKey(ValueKey(key)), findsNothing);
        }
        for (final value in values) {
          expect(find.text(value), findsNothing);
          expect(
            find.semantics.byLabel(RegExp(RegExp.escape(value))),
            findsNothing,
          );
        }
      }

      expectHiddenDetails(const [
        'HIDDEN_SENDER_306',
        '2026-05-01 10:11',
        'image/x-hidden-captioned-306',
        '111 B',
        '311 × 211',
      ]);
      expect(find.text(hiddenCaption), findsOneWidget);
      expect(find.semantics.byLabel(RegExp(hiddenCaption)), findsOneWidget);
      expect(
        find.byKey(const ValueKey('media_viewer_metadata_content')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('media_action_share')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('media_action_share')));
      await tester.pump();
      expect(actions, hasLength(1));
      expect(actions.single.item.attachmentId, hiddenCaptioned.attachmentId);
      expect(actions.single.action, MediaViewerAction.share);

      await tester.fling(find.byType(PageView), const Offset(-500, 0), 1500);
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      expect(find.text('VISIBLE_VIDEO_SENDER_306'), findsOneWidget);
      expect(find.text('2026-05-02 12:13'), findsOneWidget);
      expect(find.text('video/mp4'), findsOneWidget);
      expect(find.text('222 B'), findsOneWidget);
      expect(find.text('1:01'), findsOneWidget);
      expect(find.text('VISIBLE_VIDEO_CAPTION_306'), findsOneWidget);
      for (final value in const [
        'VISIBLE_VIDEO_SENDER_306',
        '2026-05-02 12:13',
        'video/mp4',
        '222 B',
        '1:01',
      ]) {
        expect(
          find.semantics.byLabel(RegExp(RegExp.escape(value))),
          findsOneWidget,
        );
      }

      await tester.fling(find.byType(PageView), const Offset(-500, 0), 1500);
      await tester.pumpAndSettle();
      expect(find.text('3 / 3'), findsOneWidget);
      expectHiddenDetails(const [
        'HIDDEN_CAPTIONLESS_SENDER_306',
        '2026-05-03 14:15',
        'image/x-hidden-captionless-306',
        '333 B',
        '333 × 233',
      ]);
      expect(
        find.byKey(const ValueKey('media_viewer_metadata_content')),
        findsNothing,
      );

      await tester.fling(find.byType(PageView), const Offset(500, 0), 1500);
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
      expect(find.text('VISIBLE_VIDEO_SENDER_306'), findsOneWidget);

      await tester.fling(find.byType(PageView), const Offset(500, 0), 1500);
      await tester.pumpAndSettle();
      expect(find.text('1 / 3'), findsOneWidget);
      expectHiddenDetails(const [
        'HIDDEN_SENDER_306',
        '2026-05-01 10:11',
        'image/x-hidden-captioned-306',
        '111 B',
        '311 × 211',
      ]);
      expect(find.text(hiddenCaption), findsOneWidget);
      semantics.dispose();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'protected unowned video keeps PiP absent before platform or authority access',
    (tester) async {
      final item = videoItem(
        attachmentId: 'pip-protected-unowned',
        messageId: 'message-protected-unowned',
        owner: null,
        durationMs: 60_000,
        canEnterPictureInPicture: true,
        protection: const MediaViewerProtection(isProtected: true),
      );
      final gateway = _ViewerPictureInPictureGateway();
      final resume = RecordingResumeStore();
      var authorizationLoads = 0;

      await tester.pumpWidget(
        wrap(
          FullScreenTypedMediaViewer(
            items: [item],
            playbackAdapterFactory: (_) => FakeMediaPlaybackAdapter(),
            resumeStore: resume,
            pictureInPictureControllerFactory:
                ({required reloadCurrent, required restorePlayback}) =>
                    MediaPictureInPictureController(
                      gateway: gateway,
                      pathAuthority: _ViewerPathAuthority(),
                      reloadCurrent: reloadCurrent,
                      resumeStore: resume,
                      restorePlayback: restorePlayback,
                      pollTicks: const Stream<void>.empty(),
                    ),
            loadPictureInPictureAuthorization: (current) async {
              authorizationLoads++;
              return MediaPictureInPictureAuthorization(
                item: current,
                generation: 1,
                policyState: MediaPictureInPicturePolicyState.protected,
                isIncoming: true,
                isTransferComplete: true,
                routeActive: true,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('media_action_picture_in_picture')),
        findsNothing,
      );
      expect(authorizationLoads, 0);
      expect(gateway.capabilityCalls, 0);
      expect(gateway.starts, isEmpty);
    },
  );

  testWidgets(
    'supported Android PiP control targets and restores the exact current video owner',
    (tester) async {
      final direct = videoItem(
        attachmentId: 'pip-direct',
        messageId: 'message-direct',
        owner: MediaOwnerLane.direct,
        durationMs: 60_000,
        canEnterPictureInPicture: true,
      );
      final group = videoItem(
        attachmentId: 'pip-group',
        messageId: 'message-group',
        owner: MediaOwnerLane.group,
        durationMs: 90_000,
        canEnterPictureInPicture: true,
      );
      final adapters = <String, List<FakeMediaPlaybackAdapter>>{};
      final gateway = _ViewerPictureInPictureGateway();
      final resume = RecordingResumeStore();
      final loaded = <MediaViewerItem>[];

      Future<MediaPictureInPictureAuthorization?> authorize(
        MediaViewerItem item,
      ) async {
        loaded.add(item);
        return MediaPictureInPictureAuthorization(
          item: item,
          generation:
              Object.hash(item.owner, item.messageId, item.attachmentId) &
              0x7fffffff,
          policyState: MediaPictureInPicturePolicyState.ordinary,
          isIncoming: true,
          isTransferComplete: true,
          routeActive: true,
        );
      }

      await tester.pumpWidget(
        wrap(
          FullScreenTypedMediaViewer(
            items: [direct, group],
            playbackAdapterFactory: (item) {
              final adapter = FakeMediaPlaybackAdapter(
                duration: Duration(milliseconds: item.durationMs!),
                position: const Duration(milliseconds: 3200),
              )..isPlaying = true;
              adapters.putIfAbsent(item.attachmentId, () => []).add(adapter);
              return adapter;
            },
            resumeStore: resume,
            pictureInPictureControllerFactory:
                ({required reloadCurrent, required restorePlayback}) {
                  return MediaPictureInPictureController(
                    gateway: gateway,
                    pathAuthority: _ViewerPathAuthority(),
                    reloadCurrent: reloadCurrent,
                    resumeStore: resume,
                    restorePlayback: restorePlayback,
                    pollTicks: const Stream<void>.empty(),
                    sessionIdFactory: () => 'viewer-session',
                  );
                },
            loadPictureInPictureAuthorization: authorize,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('media_action_picture_in_picture')),
        findsOneWidget,
      );
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('2 / 2'), findsOneWidget);
      expect(loaded.last.attachmentId, 'pip-group');
      expect(loaded.last.owner, MediaOwnerLane.group);
      final currentAdapter = adapters['pip-group']!.first;
      expect(currentAdapter.initializeCount, 1);
      expect(currentAdapter.isInitialized, isTrue);
      expect(currentAdapter.playCount, greaterThanOrEqualTo(1));
      final directDisposeBaseline = adapters['pip-direct']!
          .map((adapter) => adapter.disposeCount)
          .fold(0, (total, count) => total + count);
      final currentPage = tester
          .widgetList(
            find.byWidgetPredicate(
              (widget) =>
                  widget.runtimeType.toString() == '_TypedVideoPage' &&
                  widget.key.toString().contains('pip-group'),
            ),
          )
          .single;
      final currentPageState = (currentPage.key! as GlobalKey).currentState;
      expect(currentPageState, isNotNull);
      expect((currentPageState as dynamic).canStartPictureInPicture, isTrue);
      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey('media_action_picture_in_picture')),
            )
            .onPressed,
        isNotNull,
      );

      await tester.tap(
        find.byKey(const ValueKey('media_action_picture_in_picture')),
      );
      await tester.pumpAndSettle();
      await tester.pump();

      expect(gateway.starts, hasLength(1));
      expect(
        find.byKey(const ValueKey('media_picture_in_picture_start_failure')),
        findsNothing,
      );
      expect(gateway.starts.single.attachment, 'pip-group');
      expect(adapters['pip-group']!.first.pauseCount, 1);
      expect(adapters['pip-group']!.first.disposeCount, 1);
      expect(
        adapters['pip-direct']!
            .map((adapter) => adapter.disposeCount)
            .fold(0, (total, count) => total + count),
        directDisposeBaseline,
      );

      gateway.emit(
        const PictureInPictureEvent(
          session: 'viewer-session',
          attachment: 'pip-group',
          state: PictureInPictureState.restoring,
          positionMs: 4400,
          durationMs: 90_000,
          reason: PictureInPictureTerminalReason.systemReturn,
        ),
      );
      await tester.pump();
      await tester.pumpAndSettle();

      expect(adapters['pip-group'], hasLength(2));
      expect(adapters['pip-group']!.last.seekTargets, <Duration>[
        const Duration(milliseconds: 4400),
      ]);
      expect(adapters['pip-group']!.last.playCount, 1);
    },
  );

  testWidgets(
    'denied native-rejected and thrown PiP starts announce localized failure',
    (tester) async {
      for (final scenario in const ['denied', 'nativeRejected', 'thrown']) {
        final item = videoItem(
          attachmentId: 'pip-failure-$scenario',
          messageId: 'message-failure-$scenario',
          owner: MediaOwnerLane.direct,
          durationMs: 60_000,
          canEnterPictureInPicture: true,
        );
        final gateway = _ViewerPictureInPictureGateway(
          startOutcome: scenario == 'nativeRejected'
              ? PictureInPictureStartOutcome.platformFailure
              : PictureInPictureStartOutcome.started,
        );
        final resume = RecordingResumeStore();
        var authorizationLoads = 0;

        await tester.pumpWidget(
          wrap(
            FullScreenTypedMediaViewer(
              key: ValueKey('pip-failure-viewer-$scenario'),
              items: [item],
              playbackAdapterFactory: (_) => FakeMediaPlaybackAdapter(),
              resumeStore: resume,
              pictureInPictureControllerFactory:
                  ({required reloadCurrent, required restorePlayback}) {
                    if (scenario == 'thrown') {
                      return _ThrowingPictureInPictureController(
                        gateway: gateway,
                        reloadCurrent: reloadCurrent,
                        resumeStore: resume,
                        restorePlayback: restorePlayback,
                      );
                    }
                    return MediaPictureInPictureController(
                      gateway: gateway,
                      pathAuthority: _ViewerPathAuthority(),
                      reloadCurrent: reloadCurrent,
                      resumeStore: resume,
                      restorePlayback: restorePlayback,
                      pollTicks: const Stream<void>.empty(),
                    );
                  },
              loadPictureInPictureAuthorization: (current) async {
                authorizationLoads++;
                return MediaPictureInPictureAuthorization(
                  item: current,
                  generation: 1,
                  policyState: scenario == 'denied' && authorizationLoads >= 3
                      ? MediaPictureInPicturePolicyState.protected
                      : MediaPictureInPicturePolicyState.ordinary,
                  isIncoming: true,
                  isTransferComplete: true,
                  routeActive: true,
                );
              },
            ),
          ),
        );
        await tester.pumpAndSettle();

        final control = find.byKey(
          const ValueKey('media_action_picture_in_picture'),
        );
        expect(control, findsOneWidget, reason: scenario);
        await tester.tap(control);
        await tester.pumpAndSettle();

        final failure = find.byKey(
          const ValueKey('media_picture_in_picture_start_failure'),
        );
        expect(failure, findsOneWidget, reason: scenario);
        final l10n = AppLocalizations.of(tester.element(failure))!;
        expect(
          find.text(l10n.media_viewer_picture_in_picture_start_failed),
          findsOneWidget,
          reason: scenario,
        );
        expect(
          tester
              .getSemantics(failure)
              .getSemanticsData()
              .flagsCollection
              .isLiveRegion,
          isTrue,
          reason: scenario,
        );
        expect(tester.takeException(), isNull, reason: scenario);

        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
      }
    },
  );

  testWidgets('unsupported PiP stays hidden without visible failure feedback', (
    tester,
  ) async {
    final item = videoItem(
      attachmentId: 'pip-unsupported',
      messageId: 'message-unsupported',
      owner: MediaOwnerLane.direct,
      durationMs: 60_000,
      canEnterPictureInPicture: true,
    );
    final gateway = _ViewerPictureInPictureGateway(
      capabilityResult: const PictureInPictureCapability.androidUnsupported(),
    );
    final resume = RecordingResumeStore();

    await tester.pumpWidget(
      wrap(
        FullScreenTypedMediaViewer(
          items: [item],
          playbackAdapterFactory: (_) => FakeMediaPlaybackAdapter(),
          resumeStore: resume,
          pictureInPictureControllerFactory:
              ({required reloadCurrent, required restorePlayback}) =>
                  MediaPictureInPictureController(
                    gateway: gateway,
                    pathAuthority: _ViewerPathAuthority(),
                    reloadCurrent: reloadCurrent,
                    resumeStore: resume,
                    restorePlayback: restorePlayback,
                    pollTicks: const Stream<void>.empty(),
                  ),
          loadPictureInPictureAuthorization: (current) async =>
              MediaPictureInPictureAuthorization(
                item: current,
                generation: 1,
                policyState: MediaPictureInPicturePolicyState.ordinary,
                isIncoming: true,
                isTransferComplete: true,
                routeActive: true,
              ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('media_action_picture_in_picture')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('media_picture_in_picture_start_failure')),
      findsNothing,
    );
  });

  testWidgets(
    'PiP authorization reload failure hides the control without touching playback',
    (tester) async {
      final item = videoItem(
        attachmentId: 'pip-reload-failure',
        messageId: 'message-reload-failure',
        owner: MediaOwnerLane.direct,
        durationMs: 60_000,
        canEnterPictureInPicture: true,
      );
      final adapter = FakeMediaPlaybackAdapter()..isPlaying = true;
      final gateway = _ViewerPictureInPictureGateway();
      final resume = RecordingResumeStore();
      var authorizationLoads = 0;

      await tester.pumpWidget(
        wrap(
          FullScreenTypedMediaViewer(
            items: [item],
            playbackAdapterFactory: (_) => adapter,
            resumeStore: resume,
            pictureInPictureControllerFactory:
                ({required reloadCurrent, required restorePlayback}) =>
                    MediaPictureInPictureController(
                      gateway: gateway,
                      pathAuthority: _ViewerPathAuthority(),
                      reloadCurrent: reloadCurrent,
                      resumeStore: resume,
                      restorePlayback: restorePlayback,
                      pollTicks: const Stream<void>.empty(),
                    ),
            loadPictureInPictureAuthorization: (current) async {
              authorizationLoads++;
              if (authorizationLoads > 1) {
                throw StateError('route authority unavailable');
              }
              return MediaPictureInPictureAuthorization(
                item: current,
                generation: 1,
                policyState: MediaPictureInPicturePolicyState.ordinary,
                isIncoming: true,
                isTransferComplete: true,
                routeActive: true,
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      final control = find.byKey(
        const ValueKey('media_action_picture_in_picture'),
      );
      expect(control, findsOneWidget);
      expect(tester.widget<IconButton>(control).onPressed, isNotNull);
      await tester.tap(control);
      await tester.pumpAndSettle();

      expect(authorizationLoads, 2);
      expect(control, findsNothing);
      expect(gateway.starts, isEmpty);
      expect(adapter.pauseCount, 0);
      expect(adapter.disposeCount, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'private render lifecycle reports one real first frame or one pre-frame failure',
    (tester) async {
      var firstFrames = 0;
      var failures = 0;
      await tester.pumpWidget(
        wrap(
          FullScreenTypedMediaViewer(
            items: [
              videoItem(
                attachmentId: 'private-video-failure',
                messageId: 'private-message',
                owner: MediaOwnerLane.direct,
              ),
            ],
            privacyMinimized: true,
            playbackAdapterFactory: (_) =>
                FakeMediaPlaybackAdapter(failInitialize: true),
            onFirstRenderedFrame: () async {
              firstFrames++;
              return true;
            },
            onPreFrameFailure: () => failures++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(firstFrames, 0);
      expect(failures, 1, reason: 'the initialization failure settles once');
      expect(find.byKey(const ValueKey('media_meta_mime')), findsNothing);
      expect(find.byKey(const ValueKey('media_meta_caption')), findsNothing);
    },
  );

  testWidgets(
    'private renderer fails closed for a missing path and a throwing first-frame transaction',
    (tester) async {
      var preFrameFailures = 0;
      await tester.pumpWidget(
        wrap(
          FullScreenTypedMediaViewer(
            items: const [
              MediaViewerItem(
                attachmentId: 'missing-private-image',
                messageId: 'missing-private-message',
                kind: MediaViewerKind.image,
                mime: 'image/png',
                owner: MediaOwnerLane.direct,
              ),
            ],
            privacyMinimized: true,
            onFirstRenderedFrame: () async => true,
            onPreFrameFailure: () => preFrameFailures++,
          ),
        ),
      );
      await tester.pump();
      expect(preFrameFailures, 1);

      var postFrameFailures = 0;
      await tester.pumpWidget(
        wrap(
          FullScreenTypedMediaViewer(
            key: const ValueKey('throwing-private-renderer'),
            items: [
              videoItem(
                attachmentId: 'throwing-private-video',
                messageId: 'throwing-private-message',
                owner: MediaOwnerLane.direct,
              ),
            ],
            privacyMinimized: true,
            playbackAdapterFactory: (_) => FakeMediaPlaybackAdapter(),
            onFirstRenderedFrame: () async => throw StateError('db failure'),
            onPreFrameFailure: () => preFrameFailures++,
            onPostFrameFailure: () => postFrameFailures++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(postFrameFailures, 1);
      expect(preFrameFailures, 1);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('iOS private images and GIFs use the protected native surface', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      for (final kind in <MediaViewerKind>[
        MediaViewerKind.image,
        MediaViewerKind.gif,
      ]) {
        await tester.pumpWidget(
          wrap(
            FullScreenTypedMediaViewer(
              key: ValueKey('private-${kind.name}'),
              items: [
                MediaViewerItem(
                  attachmentId: 'private-${kind.name}',
                  messageId: 'private-message-${kind.name}',
                  kind: kind,
                  mime: kind == MediaViewerKind.gif ? 'image/gif' : 'image/png',
                  owner: MediaOwnerLane.direct,
                  localPath: '/tmp/private-${kind.name}',
                ),
              ],
              privacyMinimized: true,
              onFirstRenderedFrame: () async => true,
            ),
          ),
        );
        await tester.pump();

        expect(find.byType(UiKitView), findsOneWidget, reason: kind.name);
        expect(
          find.byKey(
            const ValueKey('ios-capture-protected-image-prereveal-cover'),
          ),
          findsOneWidget,
          reason: kind.name,
        );
        expect(tester.takeException(), isNull, reason: kind.name);
      }
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
    'video initialization reports zero frames until one mounted post-raster surface and then settles once',
    (tester) async {
      final gate = Completer<void>();
      final adapter = FakeMediaPlaybackAdapter(initializeGate: gate);
      var firstFrames = 0;

      await tester.pumpWidget(
        wrap(
          FullScreenTypedMediaViewer(
            items: [
              videoItem(
                attachmentId: 'private-video',
                messageId: 'private-message',
                owner: MediaOwnerLane.direct,
              ),
            ],
            privacyMinimized: true,
            playbackAdapterFactory: (_) => adapter,
            onFirstRenderedFrame: () async {
              firstFrames++;
              return true;
            },
          ),
        ),
      );
      await tester.pump();
      expect(firstFrames, 0, reason: 'initialization has not completed');

      gate.complete();
      await tester.idle();
      expect(firstFrames, 0, reason: 'initialization alone is not a raster');
      await tester.pump();
      expect(firstFrames, 1);
      adapter.notify();
      await tester.pump();
      expect(firstFrames, 1);
    },
  );

  testWidgets(
    'private presentation suppresses metadata resume actions and PiP without changing ordinary pages',
    (tester) async {
      final privateItem = videoItem(
        attachmentId: 'private-video',
        messageId: 'private-message',
        owner: MediaOwnerLane.direct,
        caption: 'SECRET caption',
        sender: 'SECRET sender',
        durationMs: 12_345,
        sizeBytes: 9_999,
      );
      final resume = RecordingResumeStore(defaultStored: 5000);
      await tester.pumpWidget(
        wrap(
          FullScreenTypedMediaViewer(
            items: [privateItem],
            privacyMinimized: true,
            resumeStore: resume,
            playbackAdapterFactory: (_) => FakeMediaPlaybackAdapter(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('SECRET'), findsNothing);
      expect(find.byKey(const ValueKey('media_meta_mime')), findsNothing);
      expect(find.byKey(const ValueKey('media_action_save')), findsNothing);
      expect(resume.reads, isEmpty);
      expect(resume.writes, isEmpty);
      expect(privateItem.canEnterPictureInPicture, isFalse);

      await tester.pumpWidget(
        wrap(
          FullScreenTypedMediaViewer(
            items: [privateItem],
            playbackAdapterFactory: (_) => FakeMediaPlaybackAdapter(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('SECRET caption'), findsOneWidget);
      expect(find.byKey(const ValueKey('media_meta_mime')), findsOneWidget);
    },
  );

  testWidgets(
    'private video hides duration scrubber and surface failure cannot report a frame',
    (tester) async {
      final privateVideo = videoItem(
        attachmentId: 'private-video-controls',
        messageId: 'private-message-controls',
        owner: MediaOwnerLane.direct,
        durationMs: 83_000,
      );
      final playable = FakeMediaPlaybackAdapter(
        duration: const Duration(seconds: 83),
        position: const Duration(seconds: 12),
      );

      await tester.pumpWidget(
        wrap(
          FullScreenTypedMediaViewer(
            items: [privateVideo],
            privacyMinimized: true,
            playbackAdapterFactory: (_) => playable,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MediaVideoControls), findsNothing);
      expect(find.byType(Slider), findsNothing);
      expect(find.textContaining('0:12'), findsNothing);
      expect(find.textContaining('1:23'), findsNothing);

      for (final adapter in <FakeMediaPlaybackAdapter>[
        FakeMediaPlaybackAdapter(throwOnBuildSurface: true),
        FakeMediaPlaybackAdapter(failSurfaceBeforeRaster: true),
      ]) {
        var firstFrames = 0;
        var failures = 0;
        await tester.pumpWidget(
          wrap(
            FullScreenTypedMediaViewer(
              key: ValueKey('surface-failure-${adapter.hashCode}'),
              items: [privateVideo],
              privacyMinimized: true,
              playbackAdapterFactory: (_) => adapter,
              onFirstRenderedFrame: () async {
                firstFrames++;
                return true;
              },
              onPreFrameFailure: () => failures++,
            ),
          ),
        );
        await tester.pump();
        await tester.pump();
        await tester.pump();

        final frameworkFailure = tester.takeException();
        expect(
          frameworkFailure,
          isNull,
          reason: 'surface failures must be contained by the private renderer',
        );
        expect(firstFrames, 0);
        expect(failures, 1);
      }
    },
  );
}

class _ViewerPathAuthority implements AppOwnedMediaPathAuthority {
  @override
  Future<String?> authorize(String? candidatePath) async => candidatePath;
}

class _ViewerPictureInPictureGateway implements PictureInPictureGateway {
  _ViewerPictureInPictureGateway({
    this.capabilityResult = const PictureInPictureCapability.androidSupported(),
    this.startOutcome = PictureInPictureStartOutcome.started,
  });

  final _events = StreamController<PictureInPictureEvent>.broadcast(sync: true);
  final starts = <PictureInPictureRequest>[];
  final PictureInPictureCapability capabilityResult;
  final PictureInPictureStartOutcome startOutcome;
  int capabilityCalls = 0;

  void emit(PictureInPictureEvent event) => _events.add(event);

  @override
  Stream<PictureInPictureEvent> get events => _events.stream;

  @override
  Future<PictureInPictureCapability> capability() async {
    capabilityCalls++;
    return capabilityResult;
  }

  @override
  Future<PictureInPictureStartOutcome> start(
    PictureInPictureRequest request,
  ) async {
    starts.add(request);
    return startOutcome;
  }

  @override
  Future<PictureInPictureCommandResult> activate(
    String session,
    String attachment,
  ) async => const PictureInPictureCommandResult.success();

  @override
  Future<PictureInPictureCommandResult> stop(
    String session,
    String attachment,
  ) async => const PictureInPictureCommandResult.success();

  @override
  Future<void> dispose() async => _events.close();
}

class _ThrowingPictureInPictureController
    extends MediaPictureInPictureController {
  _ThrowingPictureInPictureController({
    required super.gateway,
    required super.reloadCurrent,
    required super.resumeStore,
    required super.restorePlayback,
  }) : super(
         pathAuthority: _ViewerPathAuthority(),
         pollTicks: const Stream<void>.empty(),
       );

  @override
  Future<MediaPictureInPictureStartOutcome> start({
    required MediaPictureInPictureAuthorization authorization,
    required MediaPlaybackAdapter playback,
  }) => Future<MediaPictureInPictureStartOutcome>.error(
    StateError('injected PiP start failure'),
  );
}
