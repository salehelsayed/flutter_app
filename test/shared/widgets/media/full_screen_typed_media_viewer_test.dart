import 'dart:async';

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
    durationMs: durationMs,
    sizeBytes: sizeBytes,
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
        expect(find.byKey(const ValueKey('media_meta_duration')), findsNothing);
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
