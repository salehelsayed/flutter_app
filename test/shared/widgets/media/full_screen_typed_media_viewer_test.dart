import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
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
    capabilities: MediaViewerActionCapabilities(allowed: caps),
    protection: protection,
  );

  MediaViewerItem videoItem({
    required String attachmentId,
    required String messageId,
    required MediaOwnerLane? owner,
    Set<MediaViewerAction> caps = const <MediaViewerAction>{},
    String? caption,
    String? sender,
    int? durationMs,
    int? sizeBytes,
  }) => MediaViewerItem(
    attachmentId: attachmentId,
    messageId: messageId,
    kind: MediaViewerKind.video,
    mime: 'video/mp4',
    owner: owner,
    localPath: '/tmp/secret-$attachmentId.mp4',
    caption: caption,
    senderLabel: sender,
    durationMs: durationMs,
    sizeBytes: sizeBytes,
    capabilities: MediaViewerActionCapabilities(allowed: caps),
  );

  testWidgets(
    'actions always target the currently visible typed item and owner',
    (tester) async {
      final dispatched =
          <({MediaViewerItem item, MediaViewerAction action})>[];

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

      await tester.tap(find.byKey(const ValueKey('media_action_delete')));
      await tester.pump();

      expect(dispatched, hasLength(1));
      expect(dispatched.single.item.attachmentId, 'att-A');
      expect(dispatched.single.item.messageId, 'msg-A');
      expect(dispatched.single.item.owner, MediaOwnerLane.direct);
      expect(dispatched.single.action, MediaViewerAction.delete);

      await tester.fling(
        find.byType(PageView),
        const Offset(-400, 0),
        1000,
      );
      await tester.pumpAndSettle();

      expect(find.text('2 / 2'), findsOneWidget);

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
            .widget<IconButton>(
              find.byKey(const ValueKey('media_action_save')),
            )
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
            .widget<IconButton>(
              find.byKey(const ValueKey('media_action_save')),
            )
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
            .widget<IconButton>(
              find.byKey(const ValueKey('media_action_save')),
            )
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

        // Page 0 (image): dimensions present, duration absent, current caption.
        expect(
          find.byKey(const ValueKey('media_meta_dimensions')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('media_meta_duration')),
          findsNothing,
        );
        expect(find.byKey(const ValueKey('media_meta_size')), findsOneWidget);
        expect(find.text('CaptionImage'), findsOneWidget);
        expect(find.text('Alice'), findsOneWidget);
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

        // Page 1 (video): duration present, dimensions absent, new caption.
        expect(
          find.byKey(const ValueKey('media_meta_duration')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('media_meta_dimensions')),
          findsNothing,
        );
        expect(find.text('CaptionVideo'), findsOneWidget);
        expect(find.text('Bob'), findsOneWidget);
        expect(find.text('CaptionImage'), findsNothing);
        expect(find.textContaining('secret-att-vid'), findsNothing);
      }
    },
  );
}
