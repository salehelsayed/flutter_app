import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/app_owned_media_path_authority.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/picture_in_picture_gateway.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/media/received_media_egress.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_viewer_controller.dart';
import 'package:flutter_app/features/conversation/application/private_media_action_eligibility.dart';
import 'package:flutter_app/features/conversation/application/received_media_action_controller.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/direct_received_media_action_sheet.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/message_context_overlay.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_picture_in_picture_controller.dart';
import 'package:flutter_app/shared/widgets/media/media_video_resume_controller.dart';
import 'package:flutter_app/shared/widgets/media/media_viewer_item.dart';

// 231: 1:1 received media core actions — attachment-specific bubble long
// press, message-bounded typed viewer parity, close/reopen identity, Info,
// Reply, and small-viewport localized reachability. Save/Share side effects
// are recorded through the screen's typed callbacks only; the
// controller/service contract is received_media_action_controller_test.dart
// and the wired seam is conversation_wired_test.dart.
void main() {
  const contactPeerId = '12D3KooWTestPeerId1234567890';
  const ownPeerId = '12D3KooWMyPeerId1234567890';

  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('direct_media_actions_');
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  // Sync I/O only: real async dart:io awaited inside testWidgets' FakeAsync
  // zone deadlocks (see conversation_screen_test.dart viewer fixtures).
  String writeMediaFile(String name) {
    final path = '${tempDir.path}/$name';
    File(path).writeAsBytesSync(const [1, 2, 3]);
    return path;
  }

  ConversationMessage makeMessage({
    required String id,
    bool isIncoming = true,
    String text = '',
    List<MediaAttachment> media = const [],
    String? deletedAt,
    String? quotedMessageId,
    PrivateMediaPolicy policy = const PrivateMediaPolicy.ordinary(),
    PrivateMediaLifecycleState state = PrivateMediaLifecycleState.none,
  }) {
    return ConversationMessage(
      id: id,
      contactPeerId: contactPeerId,
      senderPeerId: isIncoming ? contactPeerId : ownPeerId,
      text: text,
      timestamp: '2026-02-09T15:30:00.000Z',
      status: 'delivered',
      isIncoming: isIncoming,
      createdAt: '2026-02-09T15:30:01.000Z',
      media: media,
      deletedAt: deletedAt,
      quotedMessageId: quotedMessageId,
      privateMediaPolicy: policy,
      privateMediaState: state,
    );
  }

  MediaAttachment makeAttachment({
    required String id,
    required String messageId,
    required String localPath,
    String mime = 'image/jpeg',
    String mediaType = 'image',
    MediaOwnerLane? ownerLane = MediaOwnerLane.direct,
    String downloadStatus = 'done',
    int size = 2048,
    int? width,
    int? height,
    int? durationMs,
  }) {
    return MediaAttachment(
      id: id,
      messageId: messageId,
      mime: mime,
      size: size,
      mediaType: mediaType,
      width: width,
      height: height,
      durationMs: durationMs,
      localPath: localPath,
      downloadStatus: downloadStatus,
      createdAt: '2026-02-09T15:30:02.000Z',
      ownerLane: ownerLane,
    );
  }

  Widget buildScreen({
    required List<ConversationMessage> messages,
    Locale locale = const Locale('en'),
    DirectReceivedMediaEgressHandler? onMediaEgress,
    DirectReceivedMediaInfoLoader? onLoadMediaInfo,
    DirectPrivateMediaActionDecisionLoader? onLoadMediaActionDecision,
    ValueChanged<String>? onDeleteMediaMessage,
    ValueChanged<String>? onQuoteReply,
    ValueChanged<String>? onDeleteMessage,
    String? activeQuoteText,
    ConversationMediaViewerBuilder? mediaViewerBuilder,
    DirectPrivateMediaResultLauncher? onOpenPrivateMediaResult,
    MediaPictureInPictureControllerFactory? pictureInPictureControllerFactory,
    MediaPictureInPictureAuthorizationLoader? loadPictureInPictureAuthorization,
    MediaViewerResumeStore? mediaViewerResumeStore,
  }) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: ConversationScreen(
          contactPeerId: contactPeerId,
          contactUsername: 'Alice',
          connectionDate: 'February 9, 2026',
          ownPeerId: ownPeerId,
          messages: messages,
          onSend: (_) {},
          onBack: () {},
          initialLoadDone: true,
          onQuoteReply: onQuoteReply,
          onDeleteMessage: onDeleteMessage,
          onMediaEgress: onMediaEgress,
          onLoadMediaInfo: onLoadMediaInfo,
          onLoadMediaActionDecision: onLoadMediaActionDecision,
          onDeleteMediaMessage: onDeleteMediaMessage,
          activeQuoteText: activeQuoteText,
          mediaViewerBuilder: mediaViewerBuilder,
          onOpenPrivateMediaResult: onOpenPrivateMediaResult,
          pictureInPictureControllerFactory: pictureInPictureControllerFactory,
          loadPictureInPictureAuthorization: loadPictureInPictureAuthorization,
          mediaViewerResumeStore: mediaViewerResumeStore,
        ),
      ),
    );
  }

  // AmbientBackground repeats forever — bounded pumps, never pumpAndSettle.
  Future<void> pumpFrames(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  Finder cell(String messageId, String attachmentId) =>
      find.byKey(ValueKey('media-grid-cell-$messageId-$attachmentId'));

  Future<void> dismissModal(WidgetTester tester) async {
    await tester.tapAt(const Offset(5, 5));
    await pumpFrames(tester);
  }

  Future<void> dismissOverlay(WidgetTester tester) async {
    await tester.tap(find.byKey(MessageContextOverlay.backdropKey));
    await pumpFrames(tester);
  }

  DirectReceivedMediaEgressOutcome performedOutcome(
    MediaEgressDestination destination,
    String attachmentId,
  ) {
    return DirectReceivedMediaEgressOutcome.performed(
      MediaEgressResult(
        requestId: 'req-test',
        outcome: destination == MediaEgressDestination.share
            ? MediaEgressOutcome.presented
            : MediaEgressOutcome.saved,
        items: [
          MediaEgressItemResult(
            attachmentId: attachmentId,
            outcome: MediaEgressItemOutcome.saved,
          ),
        ],
      ),
    );
  }

  DirectReceivedMediaInfo makeInfo({
    required String mime,
    required String mediaType,
    int sizeBytes = 2048,
    int? width,
    int? height,
    int? durationMs,
    String downloadStatus = 'done',
  }) {
    return DirectReceivedMediaInfo(
      isIncoming: true,
      timestamp: '2026-02-09T15:30:00.000Z',
      mime: mime,
      mediaType: mediaType,
      sizeBytes: sizeBytes,
      width: width,
      height: height,
      durationMs: durationMs,
      downloadStatus: downloadStatus,
    );
  }

  // The five core direct-media actions on the bubble surface (the shared
  // message context overlay, targeted at the pressed attachment).
  const bubbleMediaActionKeys = <ValueKey<String>>[
    MessageContextOverlay.saveActionKey,
    MessageContextOverlay.shareActionKey,
    MessageContextOverlay.replyActionKey,
    MessageContextOverlay.infoActionKey,
    MessageContextOverlay.deleteActionKey,
  ];

  // The media entries that distinguish an attachment-targeted overlay from
  // the plain whole-message context overlay.
  const mediaOnlyActionKeys = <ValueKey<String>>[
    MessageContextOverlay.saveActionKey,
    MessageContextOverlay.shareActionKey,
    MessageContextOverlay.infoActionKey,
  ];

  // The same five core actions on the typed viewer surface.
  const viewerActionKeys = <ValueKey<String>>[
    ValueKey('media_action_save'),
    ValueKey('media_action_share'),
    ValueKey('media_action_reply'),
    ValueKey('media_action_info'),
    ValueKey('media_action_delete'),
  ];

  testWidgets(
    'attachment long press exposes direct media actions without replacing row context',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final egressCalls =
          <
            ({
              DirectReceivedMediaActionIdentity identity,
              MediaEgressDestination destination,
            })
          >[];
      final infoCalls = <DirectReceivedMediaActionIdentity>[];
      final deleteMediaCalls = <String>[];

      final eligible = makeMessage(
        id: 'msg-elig',
        text: 'eligible row',
        media: [
          makeAttachment(
            id: 'att-a',
            messageId: 'msg-elig',
            localPath: writeMediaFile('elig-a.jpg'),
          ),
          makeAttachment(
            id: 'att-b',
            messageId: 'msg-elig',
            localPath: writeMediaFile('elig-b.mp4'),
            mime: 'video/mp4',
            mediaType: 'video',
            durationMs: 4000,
          ),
        ],
      );
      final unresolved = makeMessage(
        id: 'msg-unres',
        text: 'unresolved row',
        media: [
          makeAttachment(
            id: 'att-u',
            messageId: 'msg-unres',
            localPath: writeMediaFile('unres.jpg'),
            ownerLane: null,
          ),
        ],
      );
      final outgoing = makeMessage(
        id: 'msg-out',
        isIncoming: false,
        text: 'outgoing row',
        media: [
          makeAttachment(
            id: 'att-o',
            messageId: 'msg-out',
            localPath: writeMediaFile('out.jpg'),
          ),
        ],
      );

      await tester.pumpWidget(
        buildScreen(
          messages: [eligible, unresolved, outgoing],
          onQuoteReply: (_) {},
          onDeleteMessage: (_) {},
          onDeleteMediaMessage: deleteMediaCalls.add,
          onMediaEgress: (identity, destination) async {
            egressCalls.add((identity: identity, destination: destination));
            return performedOutcome(destination, identity.attachmentId);
          },
          onLoadMediaInfo: (identity) async {
            infoCalls.add(identity);
            return makeInfo(mime: 'image/jpeg', mediaType: 'image');
          },
        ),
      );
      await pumpFrames(tester);

      // Eligible cell A: the attachment-targeted overlay exposes each core
      // media action exactly once and no Report action exists (plan 244).
      await tester.longPress(cell('msg-elig', 'att-a'));
      await pumpFrames(tester);
      expect(find.byKey(MessageContextOverlay.overlayKey), findsOneWidget);
      for (final key in bubbleMediaActionKeys) {
        expect(find.byKey(key), findsOneWidget, reason: 'missing $key');
      }
      expect(
        find.byKey(const ValueKey('message-context-report-action')),
        findsNothing,
      );
      expect(find.textContaining('Report'), findsNothing);

      // The overlay action targets EXACTLY the pressed attachment.
      await tester.tap(find.byKey(MessageContextOverlay.infoActionKey));
      await pumpFrames(tester);
      expect(infoCalls, hasLength(1));
      expect(infoCalls.single.messageId, 'msg-elig');
      expect(infoCalls.single.attachmentId, 'att-a');
      await dismissModal(tester);

      // Cell B of the SAME message targets attachment B, never "first".
      await tester.longPress(cell('msg-elig', 'att-b'));
      await pumpFrames(tester);
      await tester.tap(find.byKey(MessageContextOverlay.infoActionKey));
      await pumpFrames(tester);
      expect(infoCalls, hasLength(2));
      expect(infoCalls.last.attachmentId, 'att-b');
      await dismissModal(tester);

      // Non-media row space keeps the existing message context: no media
      // entries appear there.
      await tester.longPress(find.text('eligible row'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(MessageContextOverlay.overlayKey), findsOneWidget);
      for (final key in mediaOnlyActionKeys) {
        expect(find.byKey(key), findsNothing, reason: '$key on row context');
      }
      expect(find.byKey(MessageContextOverlay.replyActionKey), findsOneWidget);
      await dismissOverlay(tester);

      // Unresolved-owner media falls back to the plain message context — no
      // media actions, zero controller callbacks.
      final callsBefore = (egress: egressCalls.length, info: infoCalls.length);
      await tester.longPress(cell('msg-unres', 'att-u'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(MessageContextOverlay.overlayKey), findsOneWidget);
      for (final key in mediaOnlyActionKeys) {
        expect(find.byKey(key), findsNothing, reason: '$key for unresolved');
      }
      await dismissOverlay(tester);

      // Outgoing media keeps the existing message context too.
      await tester.longPress(cell('msg-out', 'att-o'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(MessageContextOverlay.overlayKey), findsOneWidget);
      for (final key in mediaOnlyActionKeys) {
        expect(find.byKey(key), findsNothing, reason: '$key for outgoing');
      }
      await dismissOverlay(tester);

      expect(egressCalls.length, callsBefore.egress);
      expect(infoCalls.length, callsBefore.info);
      expect(deleteMediaCalls, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'same message bubble and viewer parity follows selected attachment',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final egressCalls =
          <
            ({
              DirectReceivedMediaActionIdentity identity,
              MediaEgressDestination destination,
            })
          >[];

      final message = makeMessage(
        id: 'msg-parity',
        text: 'parity row',
        media: [
          makeAttachment(
            id: 'att-a',
            messageId: 'msg-parity',
            localPath: writeMediaFile('parity-a.jpg'),
          ),
          makeAttachment(
            id: 'att-b',
            messageId: 'msg-parity',
            localPath: writeMediaFile('parity-b.mp4'),
            mime: 'video/mp4',
            mediaType: 'video',
            durationMs: 5000,
          ),
        ],
      );

      await tester.pumpWidget(
        buildScreen(
          messages: [message],
          onQuoteReply: (_) {},
          onDeleteMediaMessage: (_) {},
          onLoadMediaInfo: (_) async =>
              makeInfo(mime: 'image/jpeg', mediaType: 'image'),
          onMediaEgress: (identity, destination) async {
            egressCalls.add((identity: identity, destination: destination));
            return performedOutcome(destination, identity.attachmentId);
          },
        ),
      );
      await pumpFrames(tester);

      // Bubble surface: the eligible core action set, then Save routes
      // through the Photos/Files destination chooser carrying the exact
      // pressed attachment.
      await tester.longPress(cell('msg-parity', 'att-a'));
      await pumpFrames(tester);
      for (final key in bubbleMediaActionKeys) {
        expect(find.byKey(key), findsOneWidget, reason: 'bubble missing $key');
      }
      await tester.tap(find.byKey(MessageContextOverlay.saveActionKey));
      await pumpFrames(tester);
      expect(
        find.byKey(DirectMediaSaveDestinationSheet.photosActionKey),
        findsOneWidget,
      );
      expect(
        find.byKey(DirectMediaSaveDestinationSheet.filesActionKey),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(DirectMediaSaveDestinationSheet.photosActionKey),
      );
      await pumpFrames(tester);
      expect(egressCalls, hasLength(1));
      expect(egressCalls.single.identity.messageId, 'msg-parity');
      expect(egressCalls.single.identity.attachmentId, 'att-a');
      expect(egressCalls.single.destination, MediaEgressDestination.photos);

      // Viewer surface: the SAME eligible action set, no forward/bookmark.
      await tester.tap(cell('msg-parity', 'att-a'));
      await pumpFrames(tester);
      final viewer = tester.widget<FullScreenTypedMediaViewer>(
        find.byType(FullScreenTypedMediaViewer),
      );
      expect(viewer.items, hasLength(2));
      for (final item in viewer.items) {
        expect(item.messageId, 'msg-parity');
        expect(item.owner, MediaOwnerLane.direct);
      }
      for (final key in viewerActionKeys) {
        expect(find.byKey(key), findsOneWidget, reason: 'viewer missing $key');
      }
      expect(find.byKey(const ValueKey('media_action_forward')), findsNothing);
      expect(find.byKey(const ValueKey('media_action_bookmark')), findsNothing);

      // Page A action carries attachment A...
      await tester.tap(find.byKey(const ValueKey('media_action_share')));
      await pumpFrames(tester);
      expect(egressCalls, hasLength(2));
      expect(egressCalls.last.identity.attachmentId, 'att-a');
      expect(egressCalls.last.destination, MediaEgressDestination.share);

      // ...and after a swipe the action follows the now-visible attachment B
      // while keeping the same owning message.
      await tester.fling(find.byType(PageView), const Offset(-500, 0), 1500);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('2 / 2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('media_action_share')));
      await pumpFrames(tester);
      expect(egressCalls, hasLength(3));
      expect(egressCalls.last.identity.messageId, 'msg-parity');
      expect(egressCalls.last.identity.attachmentId, 'att-b');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'viewer reopen switches parent identity without cross message navigation',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final egressCalls = <DirectReceivedMediaActionIdentity>[];

      final first = makeMessage(
        id: 'msg-one',
        text: 'first row',
        media: [
          makeAttachment(
            id: 'att-one',
            messageId: 'msg-one',
            localPath: writeMediaFile('one.jpg'),
          ),
        ],
      );
      final second = makeMessage(
        id: 'msg-two',
        text: 'second row',
        media: [
          makeAttachment(
            id: 'att-two',
            messageId: 'msg-two',
            localPath: writeMediaFile('two.jpg'),
          ),
        ],
      );

      await tester.pumpWidget(
        buildScreen(
          messages: [first, second],
          onQuoteReply: (_) {},
          onDeleteMediaMessage: (_) {},
          onLoadMediaInfo: (_) async =>
              makeInfo(mime: 'image/jpeg', mediaType: 'image'),
          onMediaEgress: (identity, destination) async {
            egressCalls.add(identity);
            return performedOutcome(destination, identity.attachmentId);
          },
        ),
      );
      await pumpFrames(tester);

      await tester.tap(cell('msg-one', 'att-one'));
      await pumpFrames(tester);
      var viewer = tester.widget<FullScreenTypedMediaViewer>(
        find.byType(FullScreenTypedMediaViewer),
      );
      // Message-bounded: ONLY the tapped parent's item, no conversation list.
      expect(viewer.items.map((i) => i.attachmentId), ['att-one']);
      await tester.tap(find.byKey(const ValueKey('media_action_share')));
      await pumpFrames(tester);
      expect(egressCalls, hasLength(1));
      expect(egressCalls.single.messageId, 'msg-one');
      expect(egressCalls.single.attachmentId, 'att-one');

      // Close and reopen from a DIFFERENT parent: identity is reconstructed,
      // never cached from the first open.
      await tester.tap(find.byIcon(Icons.arrow_back));
      await pumpFrames(tester);
      expect(find.byType(FullScreenTypedMediaViewer), findsNothing);

      await tester.tap(cell('msg-two', 'att-two'));
      await pumpFrames(tester);
      viewer = tester.widget<FullScreenTypedMediaViewer>(
        find.byType(FullScreenTypedMediaViewer),
      );
      expect(viewer.items.map((i) => i.attachmentId), ['att-two']);
      await tester.tap(find.byKey(const ValueKey('media_action_share')));
      await pumpFrames(tester);
      expect(egressCalls, hasLength(2));
      expect(egressCalls.last.messageId, 'msg-two');
      expect(egressCalls.last.attachmentId, 'att-two');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'info follows selected attachment within one message without transport reads',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final infoCalls = <DirectReceivedMediaActionIdentity>[];
      // Persisted-lookup fake: metadata comes from local rows keyed by the
      // EXACT attachment identity — no transport object exists in this test.
      final infoByAttachment = <String, DirectReceivedMediaInfo>{
        'att-img': makeInfo(
          mime: 'image/jpeg',
          mediaType: 'image',
          sizeBytes: 123456,
          width: 800,
          height: 600,
        ),
        'att-vid': makeInfo(
          mime: 'video/mp4',
          mediaType: 'video',
          sizeBytes: 654321,
          durationMs: 83000,
        ),
      };

      final message = makeMessage(
        id: 'msg-info',
        text: 'info row',
        media: [
          makeAttachment(
            id: 'att-img',
            messageId: 'msg-info',
            localPath: writeMediaFile('info-a.jpg'),
            size: 123456,
            width: 800,
            height: 600,
          ),
          makeAttachment(
            id: 'att-vid',
            messageId: 'msg-info',
            localPath: writeMediaFile('info-b.mp4'),
            mime: 'video/mp4',
            mediaType: 'video',
            size: 654321,
            durationMs: 83000,
          ),
        ],
      );

      await tester.pumpWidget(
        buildScreen(
          messages: [message],
          onQuoteReply: (_) {},
          onDeleteMediaMessage: (_) {},
          onMediaEgress: (identity, destination) async =>
              performedOutcome(destination, identity.attachmentId),
          onLoadMediaInfo: (identity) async {
            infoCalls.add(identity);
            return infoByAttachment[identity.attachmentId];
          },
        ),
      );
      await pumpFrames(tester);

      await tester.tap(cell('msg-info', 'att-img'));
      await pumpFrames(tester);
      await tester.tap(find.byKey(const ValueKey('media_action_info')));
      await pumpFrames(tester);

      expect(infoCalls, hasLength(1));
      expect(infoCalls.single.messageId, 'msg-info');
      expect(infoCalls.single.attachmentId, 'att-img');
      expect(find.byKey(DirectReceivedMediaInfoSheet.sheetKey), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(DirectReceivedMediaInfoSheet.senderValueKey),
          matching: find.text('Alice'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(DirectReceivedMediaInfoSheet.typeValueKey),
          matching: find.text('image/jpeg'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(DirectReceivedMediaInfoSheet.dimensionsValueKey),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(DirectReceivedMediaInfoSheet.dimensionsValueKey),
          matching: find.text('800 × 600'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(DirectReceivedMediaInfoSheet.durationValueKey),
        findsNothing,
      );
      expect(
        find.byKey(DirectReceivedMediaInfoSheet.stateValueKey),
        findsOneWidget,
      );
      // Never leaks key/nonce/raw path material.
      expect(find.textContaining(tempDir.path), findsNothing);

      await dismissModal(tester);

      // Swipe to the video page: Info now reflects attachment B while the
      // owning-message metadata (sender) stays fixed.
      await tester.fling(find.byType(PageView), const Offset(-500, 0), 1500);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('2 / 2'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('media_action_info')));
      await pumpFrames(tester);

      expect(infoCalls, hasLength(2));
      expect(infoCalls.last.attachmentId, 'att-vid');
      expect(
        find.descendant(
          of: find.byKey(DirectReceivedMediaInfoSheet.typeValueKey),
          matching: find.text('video/mp4'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(DirectReceivedMediaInfoSheet.durationValueKey),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(DirectReceivedMediaInfoSheet.durationValueKey),
          matching: find.text('1:23'),
        ),
        findsOneWidget,
      );
      expect(
        find.byKey(DirectReceivedMediaInfoSheet.dimensionsValueKey),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byKey(DirectReceivedMediaInfoSheet.senderValueKey),
          matching: find.text('Alice'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('viewer and bubble reply quote the owning message exactly once', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final quoteCalls = <String>[];

    final message = makeMessage(
      id: 'msg-reply',
      text: 'reply row',
      media: [
        makeAttachment(
          id: 'att-r',
          messageId: 'msg-reply',
          localPath: writeMediaFile('reply.jpg'),
        ),
      ],
    );

    await tester.pumpWidget(
      buildScreen(
        messages: [message],
        onQuoteReply: quoteCalls.add,
        onDeleteMediaMessage: (_) {},
        onLoadMediaInfo: (_) async =>
            makeInfo(mime: 'image/jpeg', mediaType: 'image'),
        onMediaEgress: (identity, destination) async =>
            performedOutcome(destination, identity.attachmentId),
      ),
    );
    await pumpFrames(tester);

    // Bubble reply: exactly one quote callback with the OWNING message id
    // (never the attachment id), and the transient overlay closes.
    await tester.longPress(cell('msg-reply', 'att-r'));
    await pumpFrames(tester);
    await tester.tap(find.byKey(MessageContextOverlay.replyActionKey));
    await pumpFrames(tester);
    expect(quoteCalls, ['msg-reply']);
    expect(find.byKey(MessageContextOverlay.overlayKey), findsNothing);

    // Viewer reply: closes the viewer and quotes the same owning message.
    await tester.tap(cell('msg-reply', 'att-r'));
    await pumpFrames(tester);
    await tester.tap(find.byKey(const ValueKey('media_action_reply')));
    await pumpFrames(tester);
    expect(find.byType(FullScreenTypedMediaViewer), findsNothing);
    expect(quoteCalls, ['msg-reply', 'msg-reply']);

    // The active quote preview renders once the wired layer echoes it back.
    await tester.pumpWidget(
      buildScreen(
        messages: [message],
        onQuoteReply: quoteCalls.add,
        activeQuoteText: 'reply row',
      ),
    );
    await pumpFrames(tester);
    expect(find.text('reply row'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'received protected tile reaches typed private launcher and never enters ordinary viewers',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final attachment = makeAttachment(
        id: 'att-protected-tile',
        messageId: 'msg-protected-tile',
        localPath: writeMediaFile('protected-tile.jpg'),
      );
      final message = makeMessage(
        id: 'msg-protected-tile',
        media: [attachment],
        policy: const PrivateMediaPolicy.protected(),
        state: PrivateMediaLifecycleState.available,
      );
      final opened = <DirectPrivateMediaViewerIdentity>[];
      final guardStates = <DirectPrivateMediaContinuityState>[];
      var ordinaryBuilderCalls = 0;

      await tester.pumpWidget(
        buildScreen(
          messages: [message],
          onOpenPrivateMediaResult: (identity, continuityGuard) async {
            opened.add(identity);
            guardStates.add(continuityGuard.state);
            return const DirectPrivateMediaOpenResult.displayed(
              DirectPrivateMediaSettleResult(
                disposition: DirectPrivateMediaSettleDisposition.noLease,
                exitReason: DirectPrivateMediaExitReason.close,
                firstFrameRecorded: true,
              ),
            );
          },
          mediaViewerBuilder:
              ({required localPath, required allPaths, required initialIndex}) {
                ordinaryBuilderCalls++;
                return const SizedBox.shrink();
              },
        ),
      );
      await pumpFrames(tester);

      final tile = find.byKey(const ValueKey('private-media-card-visual'));
      expect(tile, findsOneWidget);
      await tester.tap(tile);
      await pumpFrames(tester);

      expect(opened, const <DirectPrivateMediaViewerIdentity>[
        DirectPrivateMediaViewerIdentity(
          messageId: 'msg-protected-tile',
          attachmentId: 'att-protected-tile',
        ),
      ]);
      expect(guardStates, const <DirectPrivateMediaContinuityState>[
        DirectPrivateMediaContinuityState.valid,
      ]);
      expect(ordinaryBuilderCalls, 0);
      expect(find.byType(FullScreenTypedMediaViewer), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'received view-once tile reaches typed private launcher and never enters ordinary viewers',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final attachment = makeAttachment(
        id: 'att-view-once-tile',
        messageId: 'msg-view-once-tile',
        localPath: writeMediaFile('view-once-tile.jpg'),
      );
      final message = makeMessage(
        id: 'msg-view-once-tile',
        media: [attachment],
        policy: const PrivateMediaPolicy.viewOnce(),
        state: PrivateMediaLifecycleState.available,
      );
      final opened = <DirectPrivateMediaViewerIdentity>[];
      final guardStates = <DirectPrivateMediaContinuityState>[];
      var ordinaryBuilderCalls = 0;

      await tester.pumpWidget(
        buildScreen(
          messages: [message],
          onOpenPrivateMediaResult: (identity, continuityGuard) async {
            opened.add(identity);
            guardStates.add(continuityGuard.state);
            return const DirectPrivateMediaOpenResult.displayed(
              DirectPrivateMediaSettleResult(
                disposition: DirectPrivateMediaSettleDisposition.noLease,
                exitReason: DirectPrivateMediaExitReason.close,
                firstFrameRecorded: true,
              ),
            );
          },
          mediaViewerBuilder:
              ({required localPath, required allPaths, required initialIndex}) {
                ordinaryBuilderCalls++;
                return const SizedBox.shrink();
              },
        ),
      );
      await pumpFrames(tester);

      final tile = find.byKey(const ValueKey('private-media-card-visual'));
      expect(tile, findsOneWidget);
      await tester.tap(tile);
      await pumpFrames(tester);

      expect(opened, const <DirectPrivateMediaViewerIdentity>[
        DirectPrivateMediaViewerIdentity(
          messageId: 'msg-view-once-tile',
          attachmentId: 'att-view-once-tile',
        ),
      ]);
      expect(guardStates, const <DirectPrivateMediaContinuityState>[
        DirectPrivateMediaContinuityState.valid,
      ]);
      expect(ordinaryBuilderCalls, 0);
      expect(find.byType(FullScreenTypedMediaViewer), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'private terminal and stale parents never enter typed or legacy ordinary viewers',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final availableAttachment = makeAttachment(
        id: 'att-private',
        messageId: 'msg-private',
        localPath: writeMediaFile('private.jpg'),
      );
      final availablePrivate = makeMessage(
        id: 'msg-private',
        text: 'SECRET private caption',
        media: [availableAttachment],
        policy: const PrivateMediaPolicy.protected(),
        state: PrivateMediaLifecycleState.available,
      );
      final terminalPrivate = makeMessage(
        id: 'msg-terminal',
        text: 'SECRET terminal caption',
        media: [
          makeAttachment(
            id: 'att-terminal',
            messageId: 'msg-terminal',
            localPath: writeMediaFile('terminal.jpg'),
          ),
        ],
        policy: const PrivateMediaPolicy.viewOnce(),
        state: PrivateMediaLifecycleState.expired,
      );

      await tester.pumpWidget(
        buildScreen(messages: [availablePrivate, terminalPrivate]),
      );
      await pumpFrames(tester);
      expect(cell('msg-private', 'att-private'), findsNothing);
      expect(cell('msg-terminal', 'att-terminal'), findsNothing);
      expect(
        find.byKey(const ValueKey('private-media-card-visual')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('private-terminal-expired')),
        findsOneWidget,
      );
      expect(find.textContaining('SECRET'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('private-media-card-visual')));
      await pumpFrames(tester);
      expect(find.byType(FullScreenTypedMediaViewer), findsNothing);

      var legacyBuilderCalls = 0;
      await tester.pumpWidget(
        buildScreen(
          messages: [availablePrivate],
          mediaViewerBuilder:
              ({required localPath, required allPaths, required initialIndex}) {
                legacyBuilderCalls++;
                return const SizedBox.shrink();
              },
        ),
      );
      await pumpFrames(tester);
      await tester.tap(find.byKey(const ValueKey('private-media-card-visual')));
      await pumpFrames(tester);
      expect(legacyBuilderCalls, 0);

      final ordinarySnapshotAttachment = makeAttachment(
        id: 'att-stale',
        messageId: 'msg-stale',
        localPath: writeMediaFile('stale.jpg'),
      );
      final ordinarySnapshot = makeMessage(
        id: 'msg-stale',
        text: 'SECRET stale caption',
        media: [ordinarySnapshotAttachment],
      );
      final currentPrivate = makeMessage(
        id: 'msg-stale',
        text: 'SECRET stale caption',
        media: [ordinarySnapshotAttachment],
        policy: PrivateMediaPolicy.disappearing(3600),
        state: PrivateMediaLifecycleState.available,
      );
      var currentDecisionLoads = 0;
      await tester.pumpWidget(
        buildScreen(
          messages: [ordinarySnapshot],
          onLoadMediaActionDecision: (identity) async {
            currentDecisionLoads++;
            return DirectPrivateMediaActionEligibility.evaluate(
              parent: currentPrivate,
              attachment: ordinarySnapshotAttachment,
              expectedMessageId: identity.messageId,
              expectedAttachmentId: identity.attachmentId,
            );
          },
        ),
      );
      await pumpFrames(tester);
      await tester.tap(cell('msg-stale', 'att-stale'));
      await pumpFrames(tester);
      expect(currentDecisionLoads, 1);
      expect(find.byType(FullScreenTypedMediaViewer), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'terminal private quote copy stays exactly generic after attachment cleanup',
    (tester) async {
      final terminalParent = makeMessage(
        id: 'private-quoted-parent',
        text: '',
        media: const [],
        policy: const PrivateMediaPolicy.viewOnce(),
        state: PrivateMediaLifecycleState.consumed,
      );
      final reply = makeMessage(
        id: 'reply-with-private-quote',
        text: 'reply',
        quotedMessageId: terminalParent.id,
      );

      await tester.pumpWidget(buildScreen(messages: [terminalParent, reply]));
      await pumpFrames(tester);

      expect(find.text('Private media'), findsOneWidget);
      expect(find.textContaining('SECRET'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('ordinary outgoing media preserves viewer but denies PiP', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final attachment = makeAttachment(
      id: 'att-outgoing-viewer',
      messageId: 'msg-outgoing-viewer',
      localPath: writeMediaFile('outgoing-viewer.mp4'),
      mime: 'video/mp4',
      mediaType: 'video',
    );
    final outgoing = makeMessage(
      id: 'msg-outgoing-viewer',
      isIncoming: false,
      media: [attachment],
    );
    await tester.pumpWidget(
      buildScreen(
        messages: [outgoing],
        onLoadMediaActionDecision: (identity) async =>
            DirectPrivateMediaActionEligibility.evaluate(
              parent: outgoing,
              attachment: attachment,
              expectedMessageId: identity.messageId,
              expectedAttachmentId: identity.attachmentId,
              requireIncoming: false,
            ),
      ),
    );
    await pumpFrames(tester);

    await tester.tap(cell('msg-outgoing-viewer', 'att-outgoing-viewer'));
    await pumpFrames(tester);
    expect(find.byType(FullScreenTypedMediaViewer), findsOneWidget);
    final viewer = tester.widget<FullScreenTypedMediaViewer>(
      find.byType(FullScreenTypedMediaViewer),
    );
    expect(viewer.items.single.canEnterPictureInPicture, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'direct received-video route forwards exact PiP composition to the typed viewer',
    (tester) async {
      tester.view.physicalSize = const Size(1080, 2160);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final attachment = makeAttachment(
        id: 'att-direct-pip',
        messageId: 'msg-direct-pip',
        localPath: writeMediaFile('direct-pip.mp4'),
        mime: 'video/mp4',
        mediaType: 'video',
        durationMs: 9000,
      );
      final message = makeMessage(id: 'msg-direct-pip', media: [attachment]);
      final gateway = _DirectRoutePictureInPictureGateway();
      final resume = _DirectRouteResumeStore();
      final authorized = <MediaViewerItem>[];

      await tester.pumpWidget(
        buildScreen(
          messages: [message],
          onLoadMediaActionDecision: (identity) async =>
              DirectPrivateMediaActionEligibility.evaluate(
                parent: message,
                attachment: attachment,
                expectedMessageId: identity.messageId,
                expectedAttachmentId: identity.attachmentId,
              ),
          pictureInPictureControllerFactory:
              ({required reloadCurrent, required restorePlayback}) =>
                  MediaPictureInPictureController(
                    gateway: gateway,
                    pathAuthority: _DirectRoutePathAuthority(),
                    reloadCurrent: reloadCurrent,
                    resumeStore: resume,
                    restorePlayback: restorePlayback,
                    pollTicks: const Stream<void>.empty(),
                  ),
          loadPictureInPictureAuthorization: (item) async {
            authorized.add(item);
            return MediaPictureInPictureAuthorization(
              item: item,
              generation: 1,
              policyState: MediaPictureInPicturePolicyState.ordinary,
              isIncoming: true,
              isTransferComplete: true,
              routeActive: true,
            );
          },
          mediaViewerResumeStore: resume,
        ),
      );
      await pumpFrames(tester);
      await tester.tap(cell('msg-direct-pip', 'att-direct-pip'));
      await pumpFrames(tester);

      final viewer = tester.widget<FullScreenTypedMediaViewer>(
        find.byType(FullScreenTypedMediaViewer),
      );
      expect(viewer.items.single.owner, MediaOwnerLane.direct);
      expect(viewer.items.single.messageId, 'msg-direct-pip');
      expect(viewer.items.single.canEnterPictureInPicture, isTrue);
      expect(viewer.pictureInPictureControllerFactory, isNotNull);
      expect(viewer.loadPictureInPictureAuthorization, isNotNull);
      expect(
        find.byKey(const ValueKey('media_action_picture_in_picture')),
        findsOneWidget,
      );
      expect(authorized, isNotEmpty);
      expect(authorized.last.attachmentId, 'att-direct-pip');
      expect(gateway.capabilityCalls, greaterThanOrEqualTo(1));
      expect(gateway.startCalls, 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('private Info exposes only generic lifecycle presentation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final message = makeMessage(
      id: 'msg-private-info',
      media: [
        makeAttachment(
          id: 'att-private-info',
          messageId: 'msg-private-info',
          localPath: writeMediaFile('private-info.jpg'),
        ),
      ],
    );
    await tester.pumpWidget(
      buildScreen(
        messages: [message],
        onLoadMediaInfo: (_) async => DirectReceivedMediaInfo(
          isIncoming: true,
          timestamp: '2026-02-09T15:30:00.000Z',
          mime: 'video/SECRET-mime',
          mediaType: 'video',
          sizeBytes: 987654,
          width: 1920,
          height: 1080,
          durationMs: 83000,
          downloadStatus: 'done',
          privateInfo: const DirectPrivateMediaSafeInfo(
            mode: PrivateMediaMode.viewOnce,
            state: PrivateMediaLifecycleState.consumed,
            terminalAtMs: 1_800_000_000_100,
          ),
        ),
      ),
    );
    await pumpFrames(tester);

    await tester.longPress(cell('msg-private-info', 'att-private-info'));
    await pumpFrames(tester);
    await tester.tap(find.byKey(MessageContextOverlay.infoActionKey));
    await pumpFrames(tester);

    expect(find.text('Private media'), findsOneWidget);
    expect(find.text('consumed'), findsOneWidget);
    expect(find.textContaining('SECRET-mime'), findsNothing);
    expect(find.byKey(DirectReceivedMediaInfoSheet.sizeValueKey), findsNothing);
    expect(
      find.byKey(DirectReceivedMediaInfoSheet.dimensionsValueKey),
      findsNothing,
    );
    expect(
      find.byKey(DirectReceivedMediaInfoSheet.durationValueKey),
      findsNothing,
    );
    expect(find.textContaining('1920'), findsNothing);
    expect(find.textContaining('1:23'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'core media actions stay reachable in German and Arabic small viewports',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final locale in const [Locale('de'), Locale('ar')]) {
        final deleteMediaCalls = <String>[];
        final message = makeMessage(
          id: 'msg-l10n',
          text: 'locale row',
          media: [
            makeAttachment(
              id: 'att-l',
              messageId: 'msg-l10n',
              localPath: writeMediaFile('l10n-${locale.languageCode}.jpg'),
            ),
          ],
        );

        await tester.pumpWidget(
          buildScreen(
            messages: [message],
            locale: locale,
            onQuoteReply: (_) {},
            onDeleteMediaMessage: deleteMediaCalls.add,
            onLoadMediaInfo: (_) async =>
                makeInfo(mime: 'image/jpeg', mediaType: 'image'),
            onMediaEgress: (identity, destination) async =>
                performedOutcome(destination, identity.attachmentId),
          ),
        );
        await pumpFrames(tester);

        await tester.longPress(cell('msg-l10n', 'att-l'));
        await pumpFrames(tester);

        expect(
          find.byKey(MessageContextOverlay.overlayKey),
          findsOneWidget,
          reason: 'overlay missing under $locale',
        );
        for (final key in bubbleMediaActionKeys) {
          expect(
            find.byKey(key),
            findsOneWidget,
            reason: 'missing $key under $locale',
          );
        }
        // Every eligible action is not merely present but reachable: the
        // last (delete) entry can be brought on screen and tapped.
        await tester.ensureVisible(
          find.byKey(MessageContextOverlay.deleteActionKey),
        );
        await tester.pump();
        await tester.tap(find.byKey(MessageContextOverlay.deleteActionKey));
        await pumpFrames(tester);
        // Delete dispatch is post-frame; give it one more frame.
        await tester.pump();
        expect(deleteMediaCalls, [
          'msg-l10n',
        ], reason: 'delete unreachable under $locale');
        expect(
          tester.takeException(),
          isNull,
          reason: 'layout exception under $locale',
        );
      }
    },
  );

  testWidgets(
    'corrupt protected visual renders unsupported guidance and never an open affordance',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final attachment = makeAttachment(
        id: 'att-corrupt-private',
        messageId: 'msg-corrupt-private',
        localPath: writeMediaFile('corrupt-private.jpg'),
        downloadStatus: 'integrity_failed',
      );
      final message = makeMessage(
        id: 'msg-corrupt-private',
        text: 'SECRET corrupt caption',
        media: [attachment],
        policy: const PrivateMediaPolicy.protected(),
        state: PrivateMediaLifecycleState.available,
      );

      await tester.pumpWidget(buildScreen(messages: [message]));
      await pumpFrames(tester);

      expect(
        find.byKey(const ValueKey('private-media-unsupported')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('private-media-open')), findsNothing);
      expect(find.textContaining('SECRET'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

class _DirectRoutePathAuthority implements AppOwnedMediaPathAuthority {
  @override
  Future<String?> authorize(String? candidatePath) async => candidatePath;
}

class _DirectRouteResumeStore implements MediaViewerResumeStore {
  @override
  Future<int?> readResumePosition(MediaViewerItem item) async => null;

  @override
  Future<void> writeResumePosition(
    MediaViewerItem item,
    int positionMs,
  ) async {}
}

class _DirectRoutePictureInPictureGateway implements PictureInPictureGateway {
  int capabilityCalls = 0;
  int startCalls = 0;

  @override
  Stream<PictureInPictureEvent> get events => const Stream.empty();

  @override
  Future<PictureInPictureCapability> capability() async {
    capabilityCalls++;
    return const PictureInPictureCapability.androidSupported();
  }

  @override
  Future<PictureInPictureStartOutcome> start(
    PictureInPictureRequest request,
  ) async {
    startCalls++;
    return PictureInPictureStartOutcome.platformFailure;
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
  Future<void> dispose() async {}
}
