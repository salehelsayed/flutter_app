import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_file_path_convention.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_lifecycle_engine.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/media/private_media_protection_coordinator.dart';
import 'package:flutter_app/features/conversation/application/direct_private_media_viewer_controller.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/message_context_overlay.dart';
import 'package:flutter_app/features/feed/presentation/widgets/swipe_to_quote_bubble.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

const _ownPeerId = '12D3KooWOwnThumbBubblePeer';
const _contactPeerId = '12D3KooWContactThumbBubblePeer';
const _tileKey = ValueKey('private-media-thumbnail-tile');
const _noPixelVisualKey = ValueKey('private-media-card-visual');

/// Refcount-faithful protection channel: enter publishes a token, exit
/// removes it, and the protocol envelopes match the native handler exactly.
class _RecordingProtectionChannel {
  final List<String> enters = <String>[];
  final List<String> exits = <String>[];
  final Set<String> _tokens = <String>{};
  final StreamController<Object?> events =
      StreamController<Object?>.broadcast();
  bool failEnter = false;

  PrivateMediaProtectionCoordinator buildCoordinator() =>
      PrivateMediaProtectionCoordinator(
        invokeMethod: _invoke,
        nativeEvents: events.stream,
      );

  Future<Object?> _invoke(String method, Map<String, Object?>? args) async {
    final token = args?['ownerToken'] as String?;
    switch (method) {
      case 'enter':
        enters.add(token!);
        if (failEnter) return const <String, Object?>{'ok': false};
        _tokens.add(token);
        return <String, Object?>{'ok': true, 'protectionActive': true};
      case 'exit':
        exits.add(token!);
        _tokens.remove(token);
        return <String, Object?>{
          'ok': true,
          'protectionActive': _tokens.isNotEmpty,
        };
    }
    throw StateError('unexpected protection method $method');
  }
}

/// Records every lifecycle-engine claim the open-launcher seam could make.
/// Mirrors the real adapter API so a future engine call from the render path
/// cannot dodge the recorder (it would have to go through these methods).
class _RecordingLifecycleLane implements PrivateMediaLifecycleLaneAdapter {
  _RecordingLifecycleLane(this.target);

  PrivateMediaLifecycleTarget target;
  int claimOpenings = 0;
  int consumeOpenings = 0;
  int consumes = 0;

  @override
  Future<PrivateMediaLifecycleTarget?> loadTarget(String messageId) async =>
      target.messageId == messageId ? target : null;

  @override
  Future<bool> claimOpening(
    PrivateMediaOpeningLeaseIdentity identity, {
    required int nowMs,
  }) async {
    claimOpenings++;
    return false;
  }

  @override
  Future<bool> markViewing(
    PrivateMediaOpeningLeaseIdentity identity, {
    required int nowMs,
  }) async => false;

  @override
  Future<bool> rollbackOpening(
    PrivateMediaOpeningLeaseIdentity identity,
  ) async => false;

  @override
  Future<bool> consume(String messageId, {required int nowMs}) async {
    consumes++;
    return false;
  }

  @override
  Future<bool> consumeOpening(
    PrivateMediaOpeningLeaseIdentity identity, {
    required int nowMs,
  }) async {
    consumeOpenings++;
    return false;
  }

  @override
  Future<bool> advanceClock(String messageId, {required int nowMs}) async =>
      true;

  @override
  Future<bool> failClosedCorruptState(
    String messageId, {
    required int nowMs,
  }) async => false;

  @override
  Future<List<PrivateMediaLifecycleTarget>> loadActiveDisappearing({
    int limit = 100,
  }) async => const <PrivateMediaLifecycleTarget>[];

  @override
  Future<List<PrivateMediaLifecycleTarget>> loadRecoveryCandidates({
    int limit = 100,
  }) async => const <PrivateMediaLifecycleTarget>[];

  @override
  Future<bool> rotateRecoveryCandidate(
    String messageId, {
    required int nowMs,
  }) async => true;

  @override
  Future<int?> loadNextExpiryAtMs() async => null;

  @override
  Future<void> cleanupTerminalWithinLock(
    PrivateMediaLifecycleTarget current,
  ) async {}
}

void main() {
  late Directory tempDocs;

  setUp(() {
    tempDocs = Directory.systemTemp.createTempSync('protected_thumb_screen_');
    MediaFileManager.cacheDocumentsDir(tempDocs.path);
  });

  tearDown(() {
    MediaFileManager.debugResetDocumentsDirCache();
    if (tempDocs.existsSync()) {
      tempDocs.deleteSync(recursive: true);
    }
  });

  List<int> jpegBytes() => img.encodeJpg(img.Image(width: 8, height: 8));

  /// Seeds the receiver-side thumbnail exactly where the production writer
  /// puts it: the guarded sibling path from the SAME convention call
  /// (fake-fixture reachability is proven by the receive test).
  String seedThumbFile(String blobId) {
    final relative = MediaFilePathConvention.relativeThumbnailPathForAttachment(
      contactPeerId: _contactPeerId,
      blobId: blobId,
    );
    final absolute = MediaFileManager.resolveStoredPathSync(relative);
    File(absolute)
      ..createSync(recursive: true)
      ..writeAsBytesSync(jpegBytes());
    return absolute;
  }

  String seedOutgoingMediaFile(String name) {
    final file = File(p.join(tempDocs.path, 'outgoing', name));
    file.createSync(recursive: true);
    file.writeAsBytesSync(jpegBytes());
    return file.path;
  }

  MediaAttachment attachment({
    required String id,
    required String messageId,
    String mime = 'image/jpeg',
    String mediaType = 'image',
    String downloadStatus = 'pending',
    String? localPath,
  }) {
    return MediaAttachment(
      id: id,
      messageId: messageId,
      mime: mime,
      size: 42,
      mediaType: mediaType,
      localPath: localPath,
      downloadStatus: downloadStatus,
      createdAt: '2026-07-29T10:00:00.000Z',
      ownerLane: MediaOwnerLane.direct,
    );
  }

  ConversationMessage privateMessage({
    required String id,
    required bool isIncoming,
    required PrivateMediaPolicy policy,
    required PrivateMediaLifecycleState state,
    List<MediaAttachment> media = const [],
    String status = 'delivered',
  }) {
    return ConversationMessage(
      id: id,
      contactPeerId: _contactPeerId,
      senderPeerId: isIncoming ? _contactPeerId : _ownPeerId,
      text: '',
      timestamp: '2026-07-29T10:00:00.000Z',
      status: status,
      isIncoming: isIncoming,
      createdAt: '2026-07-29T10:00:00.000Z',
      privateMediaPolicy: policy,
      privateMediaState: state,
      media: media,
    );
  }

  Future<void> pumpConversation(
    WidgetTester tester, {
    required List<ConversationMessage> messages,
    PrivateMediaProtectionCoordinator? protectionCoordinator,
    ValueChanged<String>? onQuoteReply,
    ValueChanged<String>? onDeleteMessage,
    DirectPrivateMediaResultLauncher? onOpenPrivateMediaResult,
    ConversationMediaViewerBuilder? mediaViewerBuilder,
  }) async {
    tester.view.physicalSize = const Size(900, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: ConversationScreen(
            contactPeerId: _contactPeerId,
            contactUsername: 'Alice',
            connectionDate: 'July 29, 2026',
            ownPeerId: _ownPeerId,
            messages: messages,
            onSend: (_) {},
            onBack: () {},
            initialLoadDone: true,
            hasMoreOlderMessages: false,
            protectionCoordinator: protectionCoordinator,
            onQuoteReply: onQuoteReply,
            onDeleteMessage: onDeleteMessage,
            onOpenPrivateMediaResult: onOpenPrivateMediaResult,
            mediaViewerBuilder: mediaViewerBuilder,
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));
    // Let the Android route-protection enter() settle and rebuild (bounded
    // pumps: the ambient background animates forever, so never pumpAndSettle).
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
  }

  Finder row(String messageId) => find.byKey(ValueKey('msg-$messageId'));
  Finder slot(String messageId) =>
      find.byKey(ValueKey('private-media-slot-$messageId'));
  Finder tileIn(String messageId) =>
      find.descendant(of: slot(messageId), matching: find.byKey(_tileKey));

  testWidgets(
    'incoming protected photo with persisted thumbnail renders the restricted thumbnail tile',
    (tester) async {
      final channel = _RecordingProtectionChannel();
      final message = privateMessage(
        id: 'incoming-protected-photo',
        isIncoming: true,
        policy: const PrivateMediaPolicy.protected(),
        state: PrivateMediaLifecycleState.available,
        media: [
          attachment(
            id: 'thumb-blob-in-1',
            messageId: 'incoming-protected-photo',
          ),
        ],
      );
      final thumbPath = seedThumbFile('thumb-blob-in-1');

      await pumpConversation(
        tester,
        messages: [message],
        protectionCoordinator: channel.buildCoordinator(),
      );

      final tile = tileIn(message.id);
      expect(tile, findsOneWidget);
      final image = find.descendant(of: tile, matching: find.byType(Image));
      expect(image, findsOneWidget);
      var provider = tester.widget<Image>(image).image;
      if (provider is ResizeImage) provider = provider.imageProvider;
      expect(provider, isA<FileImage>());
      expect((provider as FileImage).file.path, thumbPath);
      expect(
        find.descendant(
          of: tile,
          matching: find.byIcon(Icons.lock_outline_rounded),
        ),
        findsOneWidget,
      );
      // The no-pixel open tile must be REPLACED, not augmented.
      expect(
        find.descendant(
          of: slot(message.id),
          matching: find.byKey(_noPixelVisualKey),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: slot(message.id),
          matching: find.byKey(const ValueKey('private-media-open')),
        ),
        findsNothing,
      );
    },
  );

  testWidgets(
    'incoming protected photo without thumbnail keeps the no-pixel open tile',
    (tester) async {
      final channel = _RecordingProtectionChannel();
      final message = privateMessage(
        id: 'incoming-protected-thumbless',
        isIncoming: true,
        policy: const PrivateMediaPolicy.protected(),
        state: PrivateMediaLifecycleState.available,
        media: [
          attachment(
            id: 'thumb-blob-absent-1',
            messageId: 'incoming-protected-thumbless',
          ),
        ],
      );

      await pumpConversation(
        tester,
        messages: [message],
        protectionCoordinator: channel.buildCoordinator(),
      );

      expect(tileIn(message.id), findsNothing);
      expect(
        find.descendant(of: slot(message.id), matching: find.byType(Image)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: slot(message.id),
          matching: find.byKey(_noPixelVisualKey),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'outgoing protected photo renders the thumbnail tile with reopen affordance',
    (tester) async {
      final channel = _RecordingProtectionChannel();
      final localPath = seedOutgoingMediaFile('outgoing-protected.jpg');
      final withBytes = privateMessage(
        id: 'outgoing-protected-photo',
        isIncoming: false,
        policy: const PrivateMediaPolicy.protected(),
        state: PrivateMediaLifecycleState.available,
        status: 'sent',
        media: [
          attachment(
            id: 'thumb-blob-out-1',
            messageId: 'outgoing-protected-photo',
            downloadStatus: 'done',
            localPath: localPath,
          ),
        ],
      );

      final semanticsHandle = tester.ensureSemantics();
      await pumpConversation(
        tester,
        messages: [withBytes],
        protectionCoordinator: channel.buildCoordinator(),
      );

      final tile = tileIn(withBytes.id);
      expect(tile, findsOneWidget);
      final image = find.descendant(of: tile, matching: find.byType(Image));
      expect(image, findsOneWidget);
      var provider = tester.widget<Image>(image).image;
      if (provider is ResizeImage) provider = provider.imageProvider;
      expect((provider as FileImage).file.path, localPath);
      expect(
        find.descendant(
          of: slot(withBytes.id),
          matching: find.byKey(const ValueKey('private-media-outgoing')),
        ),
        findsNothing,
      );
      // Reopen affordance rides the tile's single semantics node.
      final node = tester.getSemantics(find.byKey(_tileKey));
      final data = node.getSemanticsData();
      expect(data.label, contains('Protected photo'));
      // 302: the sender re-opens a protected photo without limit, so the tile
      // announces the anytime promise on the same node that carries the tap.
      expect(data.value, 'You can reopen it here anytime.');
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      semanticsHandle.dispose();

      // Bytes absent -> exact current outgoing card, no tile.
      final withoutBytes = privateMessage(
        id: 'outgoing-protected-missing',
        isIncoming: false,
        policy: const PrivateMediaPolicy.protected(),
        state: PrivateMediaLifecycleState.available,
        status: 'sent',
        media: [
          attachment(
            id: 'thumb-blob-out-2',
            messageId: 'outgoing-protected-missing',
            downloadStatus: 'done',
            localPath: p.join(tempDocs.path, 'outgoing', 'missing.jpg'),
          ),
        ],
      );
      await pumpConversation(
        tester,
        messages: [withoutBytes],
        protectionCoordinator: channel.buildCoordinator(),
      );
      expect(tileIn(withoutBytes.id), findsNothing);
      expect(
        find.descendant(
          of: slot(withoutBytes.id),
          matching: find.byKey(const ValueKey('private-media-outgoing')),
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'thumbnail tap opens the protected flow and never the ordinary viewer',
    (tester) async {
      final channel = _RecordingProtectionChannel();
      var privateOpens = 0;
      var ordinaryBuilds = 0;
      final message = privateMessage(
        id: 'incoming-protected-tap',
        isIncoming: true,
        policy: const PrivateMediaPolicy.protected(),
        state: PrivateMediaLifecycleState.available,
        media: [
          attachment(
            id: 'thumb-blob-tap-1',
            messageId: 'incoming-protected-tap',
          ),
        ],
      );
      seedThumbFile('thumb-blob-tap-1');

      await pumpConversation(
        tester,
        messages: [message],
        protectionCoordinator: channel.buildCoordinator(),
        onOpenPrivateMediaResult: (identity, guard) async {
          expect(identity.messageId, message.id);
          expect(identity.attachmentId, 'thumb-blob-tap-1');
          privateOpens++;
          return const DirectPrivateMediaOpenResult.displayed(
            DirectPrivateMediaSettleResult(
              disposition:
                  DirectPrivateMediaSettleDisposition.rolledBackAvailable,
              exitReason: DirectPrivateMediaExitReason.close,
              firstFrameRecorded: true,
            ),
          );
        },
        mediaViewerBuilder:
            ({
              required String localPath,
              required List<String> allPaths,
              required int initialIndex,
            }) {
              ordinaryBuilds++;
              return const SizedBox.shrink();
            },
      );

      await tester.tap(tileIn(message.id));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      // Two-path discriminator asserted together: the pair proves exclusivity.
      expect(privateOpens, 1);
      expect(ordinaryBuilds, 0);
    },
  );

  testWidgets(
    'thumbnail tile preserves ancestor long press and the restricted menu',
    (tester) async {
      final channel = _RecordingProtectionChannel();
      final message = privateMessage(
        id: 'incoming-protected-menu',
        isIncoming: true,
        policy: const PrivateMediaPolicy.protected(),
        state: PrivateMediaLifecycleState.available,
        media: [
          attachment(
            id: 'thumb-blob-menu-1',
            messageId: 'incoming-protected-menu',
          ),
        ],
      );
      seedThumbFile('thumb-blob-menu-1');

      await pumpConversation(
        tester,
        messages: [message],
        protectionCoordinator: channel.buildCoordinator(),
        onQuoteReply: (_) {},
        onDeleteMessage: (_) {},
      );

      // Swipe-to-quote stays an ancestor of the tile.
      expect(
        find.ancestor(
          of: tileIn(message.id),
          matching: find.byType(SwipeToQuoteBubble),
        ),
        findsWidgets,
      );

      await tester.longPress(tileIn(message.id));
      await tester.pump(const Duration(milliseconds: 500));

      expect(
        find.byKey(MessageContextOverlay.selectedMessageKey),
        findsOneWidget,
      );
      expect(find.byKey(MessageContextOverlay.replyActionKey), findsOneWidget);
      expect(find.byKey(MessageContextOverlay.saveActionKey), findsNothing);
      expect(find.byKey(MessageContextOverlay.shareActionKey), findsNothing);
      expect(find.byKey(MessageContextOverlay.forwardActionKey), findsNothing);
      expect(find.byKey(MessageContextOverlay.copyActionKey), findsNothing);
    },
  );

  testWidgets(
    'thumbnail render claims no opening lease and leaves state available',
    (tester) async {
      final channel = _RecordingProtectionChannel();
      final message = privateMessage(
        id: 'incoming-protected-budget',
        isIncoming: true,
        policy: const PrivateMediaPolicy.protected(),
        state: PrivateMediaLifecycleState.available,
        media: [
          attachment(
            id: 'thumb-blob-budget-1',
            messageId: 'incoming-protected-budget',
          ),
        ],
      );
      seedThumbFile('thumb-blob-budget-1');

      final lane = _RecordingLifecycleLane(
        PrivateMediaLifecycleTarget(
          messageId: message.id,
          scopeId: _contactPeerId,
          mode: PrivateMediaMode.protected,
          state: PrivateMediaLifecycleState.available,
          receivedAtMs: 0,
        ),
      );
      final engine = PrivateMediaLifecycleEngine(
        adapter: lane,
        lifecycleLock: MediaAttachmentLifecycleLock(),
        nowMs: () => 0,
      );

      await pumpConversation(
        tester,
        messages: [message],
        protectionCoordinator: channel.buildCoordinator(),
        // The launcher seam is the only place a render path could reach the
        // engine; if it ever runs, the recorder counts the claim.
        onOpenPrivateMediaResult: (identity, guard) async {
          await engine.openOneShot(identity.messageId);
          return const DirectPrivateMediaOpenResult.failed(
            DirectPrivateMediaOpenFailureReason.prepareFailed,
            canRetry: true,
          );
        },
      );

      expect(tileIn(message.id), findsOneWidget);
      expect(lane.claimOpenings, 0);
      expect(lane.consumeOpenings, 0);
      expect(lane.consumes, 0);
      expect(message.privateMediaState, PrivateMediaLifecycleState.available);
    },
  );

  testWidgets(
    'view once disappearing protected video and unsupported keep their current presentations',
    (tester) async {
      final channel = _RecordingProtectionChannel();
      final viewOnce = privateMessage(
        id: 'adjacent-view-once',
        isIncoming: true,
        policy: const PrivateMediaPolicy.viewOnce(),
        state: PrivateMediaLifecycleState.available,
        media: [
          attachment(id: 'adjacent-vo-blob', messageId: 'adjacent-view-once'),
        ],
      );
      final disappearing = privateMessage(
        id: 'adjacent-disappearing',
        isIncoming: true,
        policy: PrivateMediaPolicy.disappearing(3600),
        state: PrivateMediaLifecycleState.available,
        media: [
          attachment(
            id: 'adjacent-dis-blob',
            messageId: 'adjacent-disappearing',
          ),
        ],
      );
      final protectedVideo = privateMessage(
        id: 'adjacent-protected-video',
        isIncoming: true,
        policy: const PrivateMediaPolicy.protected(),
        state: PrivateMediaLifecycleState.available,
        media: [
          attachment(
            id: 'adjacent-vid-blob',
            messageId: 'adjacent-protected-video',
            mime: 'video/mp4',
            mediaType: 'video',
          ),
        ],
      );
      final unsupported = privateMessage(
        id: 'adjacent-unsupported',
        isIncoming: true,
        policy: const PrivateMediaPolicy.unsupported(sourceVersion: 9),
        state: PrivateMediaLifecycleState.unsupported,
      );
      // A file exists at every adjacent blob's would-be thumbnail path, so a
      // widened (policy.isPrivate / includes-video) branch would wrongly render
      // pixels for these rows.
      seedThumbFile('adjacent-vo-blob');
      seedThumbFile('adjacent-dis-blob');
      seedThumbFile('adjacent-vid-blob');

      await pumpConversation(
        tester,
        messages: [viewOnce, disappearing, protectedVideo, unsupported],
        protectionCoordinator: channel.buildCoordinator(),
      );

      for (final id in [
        'adjacent-view-once',
        'adjacent-disappearing',
        'adjacent-protected-video',
      ]) {
        expect(tileIn(id), findsNothing, reason: id);
        expect(
          find.descendant(of: slot(id), matching: find.byType(Image)),
          findsNothing,
          reason: id,
        );
        expect(
          find.descendant(
            of: slot(id),
            matching: find.byKey(_noPixelVisualKey),
          ),
          findsOneWidget,
          reason: id,
        );
      }
      expect(tileIn('adjacent-unsupported'), findsNothing);
      expect(
        find.descendant(
          of: slot('adjacent-unsupported'),
          matching: find.byKey(const ValueKey('private-media-unsupported')),
        ),
        findsOneWidget,
      );
      // No route protection was requested by any of these rows: the negative
      // fixture in the protection suite pins enters == 0; here the adjacent
      // rows must at minimum never render a tile.
      expect(find.byKey(_tileKey), findsNothing);
      expect(row('adjacent-unsupported'), findsOneWidget);
    },
  );
}
