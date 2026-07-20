@Tags(['device'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/private_media_protection_coordinator.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/group_private_media_lifecycle.dart';
import 'package:flutter_app/features/groups/application/group_private_media_viewer_controller.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_private_media_viewer.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import '../test/shared/fakes/in_memory_media_attachment_repository.dart';

const _groupId = 'platform-private-group';
const _messageId = 'platform-private-message';
const _attachmentId = 'platform-private-attachment';

class _ProofLifecycleRepository
    implements GroupPrivateMediaLifecycleRepository {
  _ProofLifecycleRepository(this.parent);

  GroupMessage parent;

  @override
  Future<bool> anchorOutgoingGroupPrivateMediaCustody(
    String messageId, {
    required int nowMs,
  }) async {
    if (parent.id != messageId || parent.isIncoming) return false;
    parent = parent.copyWith(mediaReceivedAt: nowMs, mediaLastCheckedAt: nowMs);
    return true;
  }

  @override
  Future<bool> advanceGroupPrivateMediaClock(
    String messageId, {
    required int nowMs,
  }) async {
    if (parent.id != messageId) return false;
    parent = parent.copyWith(mediaLastCheckedAt: nowMs);
    return true;
  }

  @override
  Future<bool> completeGroupPrivateMediaCleanup(String messageId) async {
    if (parent.id != messageId || !parent.mediaCleanupPending) return false;
    parent = parent.copyWith(mediaCleanupPending: false);
    return true;
  }

  @override
  Future<bool> consumeGroupPrivateMedia(
    String messageId, {
    required int nowMs,
  }) async {
    if (parent.id != messageId || parent.mediaConsumedAt != null) return false;
    parent = parent.copyWith(
      mediaConsumedAt: nowMs,
      mediaLastCheckedAt: nowMs,
      mediaCleanupPending: true,
    );
    return true;
  }

  @override
  Future<List<GroupMessage>> loadActiveGroupPrivateMediaDisappearing({
    int limit = 100,
  }) async => const [];

  @override
  Future<GroupMessage?> loadGroupPrivateMediaMessage(String messageId) async =>
      parent.id == messageId ? parent : null;

  @override
  Future<List<GroupMessage>> loadGroupPrivateMediaRecoveryCandidates({
    int limit = 100,
  }) async => const [];

  @override
  Future<int?> loadNextGroupPrivateMediaExpiryAtMs() async =>
      parent.mediaExpiresAt;

  @override
  Future<bool> rotateGroupPrivateMediaRecoveryCandidate(
    String messageId, {
    required int nowMs,
  }) async => parent.id == messageId;
}

class _ProofCleanupRepository implements GroupPrivateMediaCleanupRepository {
  _ProofCleanupRepository(this.attachments);

  final InMemoryMediaAttachmentRepository attachments;

  @override
  Future<bool> deleteGroupPrivateMediaEncryptionKeyWithinLock({
    required String messageId,
    required String attachmentId,
  }) async => true;

  @override
  Future<int> deleteGroupPrivateMediaAttachmentWithinLock({
    required String messageId,
    required String attachmentId,
  }) async {
    final current = await attachments.getAttachmentsForMessage(
      messageId,
      owner: MediaOwnerLane.group,
    );
    if (!current.any((item) => item.id == attachmentId)) return 0;
    return attachments.deleteAttachmentsForMessage(
      messageId,
      owner: MediaOwnerLane.group,
    );
  }

  @override
  Future<List<GroupPrivateMediaLifecycleAttachmentMetadata>>
  loadGroupPrivateMediaLifecycleAttachmentMetadata(String messageId) async {
    final current = await attachments.getAttachmentsForMessage(
      messageId,
      owner: MediaOwnerLane.group,
    );
    return current
        .map(
          (item) => GroupPrivateMediaLifecycleAttachmentMetadata(
            id: item.id,
            messageId: item.messageId,
            mime: item.mime,
            size: item.size,
            downloadStatus: item.downloadStatus,
            localPath: item.localPath,
          ),
        )
        .toList(growable: false);
  }
}

Widget _app(Widget home, {required GlobalKey<NavigatorState> navigatorKey}) =>
    MaterialApp(
      navigatorKey: navigatorKey,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: home,
    );

Future<void> _pumpUntilReleased(
  WidgetTester tester,
  GroupPrivateMediaViewerGrant grant,
) async {
  for (var frame = 0; frame < 40 && !grant.protectionReleased; frame++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
  expect(
    grant.protectionReleased,
    isTrue,
    reason: 'the protected owner must release within the bounded route window',
  );
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'GPL-11 protected viewer applies truthful platform capture safeguards',
    (tester) async {
      if (!Platform.isAndroid && !Platform.isIOS) {
        fail('GPL-11 is defined only for available Android/iOS targets');
      }

      final mediaFileManager = MediaFileManager();
      final canonicalRelative = mediaFileManager.relativePathForAttachment(
        contactPeerId: _groupId,
        blobId: _attachmentId,
        mime: 'image/png',
      );
      final canonicalAbsolute = await mediaFileManager.resolveStoredPath(
        canonicalRelative,
      );
      final image = File(canonicalAbsolute);
      await image.parent.create(recursive: true);
      await image.writeAsBytes(
        base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
        ),
        flush: true,
      );
      addTearDown(() async {
        if (await image.exists()) await image.delete();
      });
      final contentHash = await GroupMediaIntegrityPolicy.computeFileSha256Hex(
        image.path,
      );

      final attachments = InMemoryMediaAttachmentRepository();
      await attachments.saveAttachment(
        MediaAttachment(
          id: _attachmentId,
          messageId: _messageId,
          mime: 'image/png',
          size: await image.length(),
          mediaType: 'image',
          localPath: canonicalRelative,
          downloadStatus: 'done',
          createdAt: '2026-07-12T10:00:00.000Z',
          contentHash: contentHash,
          encryptionKeyBase64: 'gpl12-key',
          encryptionNonce: 'gpl12-nonce',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ownerLane: MediaOwnerLane.group,
        ),
        owner: MediaOwnerLane.group,
      );
      final lifecycleRepository = _ProofLifecycleRepository(
        GroupMessage(
          id: _messageId,
          groupId: _groupId,
          senderPeerId: 'secret-sender-peer',
          senderUsername: 'SECRET sender name',
          text: 'SECRET private caption',
          timestamp: DateTime.utc(2026, 7, 12, 10),
          status: 'delivered',
          isIncoming: true,
          privateMediaPolicy: const GroupPrivateMediaPolicy.protected(),
          mediaReceivedAt: 100,
          createdAt: DateTime.utc(2026, 7, 12, 10),
        ),
      );
      final engine = GroupPrivateMediaLifecycleEngine(
        messageRepository: lifecycleRepository,
        mediaAttachmentRepository: attachments,
        cleanupRepository: _ProofCleanupRepository(attachments),
        mediaFileManager: mediaFileManager,
        lifecycleLock: MediaAttachmentLifecycleLock(),
        nowMs: () => 100,
      );
      final coordinator = PrivateMediaProtectionCoordinator.platform();
      final controller = GroupPrivateMediaViewerController(
        lifecycleEngine: engine,
        protectionCoordinator: coordinator,
      );
      addTearDown(controller.dispose);

      final events = <PrivateMediaProtectionEvent>[];
      final eventSubscription = coordinator.events.listen(events.add);
      addTearDown(eventSubscription.cancel);

      final before = await coordinator.debugGetState();
      expect(before['activeOwnerCount'], 0);
      final navigatorKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        _app(
          const Scaffold(body: SizedBox.expand()),
          navigatorKey: navigatorKey,
        ),
      );
      const identity = GroupPrivateMediaViewerIdentity(
        groupId: _groupId,
        messageId: _messageId,
        attachmentId: _attachmentId,
      );

      final normalGrant = await controller.prepare(identity);
      expect(normalGrant, isNotNull);
      final activeNormalGrant = normalGrant!;
      final normalActive = await coordinator.debugGetState();
      expect(normalActive['activeOwnerCount'], 1);
      if (Platform.isAndroid) {
        expect(normalActive['secureApplied'], isTrue);
      }

      final normalRoute = navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => GroupPrivateMediaViewer(
            grant: activeNormalGrant,
            controller: controller,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('group-private-media-viewer')),
        findsOneWidget,
      );
      final typedViewer = tester.widget<FullScreenTypedMediaViewer>(
        find.byType(FullScreenTypedMediaViewer),
      );
      expect(typedViewer.privacyMinimized, isTrue);
      expect(typedViewer.items, hasLength(1));
      expect(typedViewer.items.single.owner, MediaOwnerLane.group);
      expect(typedViewer.items.single.canEnterPictureInPicture, isFalse);
      expect(typedViewer.items.single.protection.isProtected, isTrue);
      expect(typedViewer.items.single.capabilities.allowed, isEmpty);
      final routeContext = tester.element(
        find.byKey(const ValueKey('group-private-media-viewer')),
      );
      final l10n = AppLocalizations.of(routeContext)!;
      expect(
        find.text(l10n.group_private_media_notification_body),
        findsOneWidget,
      );
      expect(
        find.text(l10n.private_media_general_capture_limit),
        findsOneWidget,
      );
      expect(
        find.text(
          Platform.isIOS
              ? l10n.private_media_ios_image_capture_limit
              : l10n.private_media_android_capture_limit,
        ),
        findsOneWidget,
      );
      expect(find.text('SECRET sender name'), findsNothing);
      expect(find.text('SECRET private caption'), findsNothing);

      await tester.tap(find.byIcon(Icons.arrow_back).first);
      await tester.pumpAndSettle();
      await normalRoute.timeout(const Duration(seconds: 5));
      await _pumpUntilReleased(tester, activeNormalGrant);
      final normalRestored = await coordinator.debugGetState();
      expect(normalRestored['activeOwnerCount'], 0);
      if (Platform.isAndroid) {
        expect(normalRestored['secureApplied'], isFalse);
      } else {
        expect(normalRestored['coverVisible'], isFalse);
      }

      final eventGrant = await controller.prepare(identity);
      expect(eventGrant, isNotNull);
      final activeEventGrant = eventGrant!;
      final eventRoute = navigatorKey.currentState!.push<void>(
        MaterialPageRoute<void>(
          builder: (_) => GroupPrivateMediaViewer(
            grant: activeEventGrant,
            controller: controller,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final eventRouteActive = await coordinator.debugGetState();
      expect(eventRouteActive['activeOwnerCount'], 1);
      if (Platform.isAndroid) {
        expect(eventRouteActive['secureApplied'], isTrue);
      }

      // This exercises the app's registered native debug channel and the
      // observable route response. It does not claim that a synthetic event is
      // a physical screen-recorder fixture.
      expect(
        await coordinator.debugInjectEvent(
          Platform.isIOS
              ? PrivateMediaProtectionDebugEvent.captureStarted
              : PrivateMediaProtectionDebugEvent.background,
        ),
        isTrue,
      );
      final eventRouteCovered = await coordinator.debugGetState();
      expect(eventRouteCovered['activeOwnerCount'], 1);
      expect(
        find.byKey(const ValueKey('group-private-media-viewer')),
        findsOneWidget,
      );
      if (Platform.isAndroid) {
        expect(eventRouteCovered['secureApplied'], isTrue);
      } else {
        expect(eventRouteCovered['coverVisible'], isTrue);
        expect(eventRouteCovered['captureActive'], isTrue);
      }

      await _pumpUntilReleased(tester, activeEventGrant);
      await eventRoute.timeout(const Duration(seconds: 5));
      final eventRouteRestored = await coordinator.debugGetState();
      expect(eventRouteRestored['activeOwnerCount'], 0);
      if (Platform.isAndroid) {
        expect(eventRouteRestored['secureApplied'], isFalse);
      } else {
        expect(eventRouteRestored['coverVisible'], isFalse);
        expect(eventRouteRestored['captureActive'], isFalse);
      }
      expect(events, isNotEmpty);
      expect(events, everyElement(isA<PrivateMediaProtectionEvent>()));
      expect(
        <Object?>[normalGrant, eventGrant, controller].join(' '),
        isNot(contains('SECRET')),
      );
    },
  );
}
