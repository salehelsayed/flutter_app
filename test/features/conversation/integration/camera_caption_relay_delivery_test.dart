// MEDIA-002/014: post-preparation Dart delivery, not an iOS/Android device proof.
// Native FlutterImageCompress is stubbed with a prepared, real large JPEG.
// EncryptedMediaTestBridge uses XOR test crypto, not production Go AES-GCM.
// Native capture/compression, real cryptography, and a live relay circuit remain
// unproven here. Repositories/migrations, files, send/receive/download decisions,
// inbox staging/replay, image decoding and received-media widgets are real.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/media/private_media_protection_coordinator.dart';
import 'package:flutter_app/app/lifecycle/handle_app_resumed.dart';
import 'package:flutter_app/core/services/pending_message_retrier.dart';
import 'package:flutter_app/core/database/helpers/media_attachments_db_helpers.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:flutter_app/core/database/helpers/inbox_staging_db_helpers.dart';
import 'package:flutter_app/core/inbox/inbox_staging_repository_impl.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/core/services/inbox_store_outcome.dart';
import 'package:flutter_app/core/services/p2p_service_impl.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/download_media_use_case.dart';
import 'package:flutter_app/features/conversation/application/recovered_inbox_chat_disposition.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_wired.dart';
import 'package:flutter_app/features/conversation/presentation/screens/conversation_screen.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_grid_cell.dart';
import 'package:flutter_app/shared/widgets/media/media_viewer_item.dart';

import '../../contact_request/presentation/support/contact_request_sql_fixture.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../identity/domain/repositories/fake_identity_repository.dart';
import '../../../shared/fakes/ed25519_contact_request_crypto.dart';
import '../../../shared/fakes/encrypted_media_test_bridge.dart';
import '../../../shared/fakes/fake_mic_permission_gateway.dart';
import '../../../shared/fakes/fake_just_audio.dart';
import '../../../shared/fixtures/media_repository_real_db_fixture.dart';

const _caption = 'Kamera-Foto: Grüße 👋';
final _alice = TestEd25519Identity.fromSeedByte(71);
final _bob = TestEd25519Identity.fromSeedByte(72);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(installFakeJustAudioPlatform);
  late Uint8List cameraJpeg;
  late Uint8List preparedJpeg;
  late Uint8List compressedJpeg;

  setUpAll(() {
    // A real 12 MP JPEG, not a magic prefix or a small thumbnail padded to 4 MB.
    // Deterministic sensor-like luminance noise gives the file real image data.
    final image = img.Image(width: 4032, height: 3024);
    var state = 0x12345678;
    for (final pixel in image) {
      state ^= (state << 13) & 0xffffffff;
      state ^= state >> 17;
      state ^= (state << 5) & 0xffffffff;
      final noise = state & 63;
      pixel.setRgb(48 + noise, 64 + noise, 80 + noise);
    }
    image.exif.imageIfd.orientation = 6;
    cameraJpeg = img.encodeJpg(image, quality: 85);
    // Fixture preparation ONLY: native compression is explicitly not executed.
    final prepared = img.bakeOrientation(image);
    prepared.exif.clear();
    preparedJpeg = img.encodeJpg(prepared, quality: 85);
    compressedJpeg = img.encodeJpg(
      img.copyResize(prepared, width: 1512, height: 2016),
      quality: 85,
    );
    expect(compressedJpeg.length, lessThan(preparedJpeg.length));
    expect(
      cameraJpeg.length,
      inInclusiveRange(3 * 1024 * 1024, 6 * 1024 * 1024),
    );
    expect(img.decodeJpgExif(cameraJpeg)!.imageIfd.orientation, 6);
    expect(img.decodeJpgExif(preparedJpeg)?.imageIfd.orientation, isNot(6));
    final rawInfo = img.JpegDecoder().startDecode(cameraJpeg)!;
    expect((rawInfo.width, rawInfo.height), (4032, 3024));
  });

  for (final offline in [false, true]) {
    testWidgets(
      'Original camera JPEG + caption opens full recipient image over '
      '${offline ? 'offline inbox catch-up' : 'online relay'}',
      (tester) async {
        final h = (await tester.runAsync(
          () => _Journey.open(cameraJpeg, preparedJpeg),
        ))!;
        addTearDown(() => tester.runAsync(h.close));
        final received = await tester.runAsync(
          () => h.deliver(offline: offline),
        );
        await h.expectFullImage(tester, received!);
      },
    );
    testWidgets(
      'MEDIA-002/014 compressed camera JPEG + caption opens full recipient '
      'image once over ${offline ? 'offline inbox catch-up' : 'online relay'}',
      (tester) async {
        final h = (await tester.runAsync(
          () => _Journey.open(cameraJpeg, compressedJpeg),
        ))!;
        addTearDown(() => tester.runAsync(h.close));
        final received = (await tester.runAsync(
          () => h.deliver(
            offline: offline,
            imageQuality: ImageQualityPreference.compressed,
          ),
        ))!;
        await h.expectFullImage(tester, received, width: 1512, height: 2016);
        await tester.runAsync(h.expectSingleCopyAfterReplay);
      },
    );
  }

  for (final quality in ImageQualityPreference.values) {
    testWidgets(
      'MEDIA-003/DC-011 reverse logical sender preserves ${quality.name} '
      'full camera image and caption',
      (tester) async {
        final compressed = quality == ImageQualityPreference.compressed;
        final h = (await tester.runAsync(
          () => _Journey.open(
            cameraJpeg,
            compressed ? compressedJpeg : preparedJpeg,
            reversePeers: true,
          ),
        ))!;
        addTearDown(() => tester.runAsync(h.close));
        final received = (await tester.runAsync(
          () => h.deliver(offline: false, imageQuality: quality),
        ))!;
        await h.expectFullImage(
          tester,
          received,
          width: compressed ? 1512 : 3024,
          height: compressed ? 2016 : 4032,
        );
        await tester.runAsync(h.expectSingleCopyAfterReplay);
      },
    );
  }

  Future<void> expectTransientRecovery(
    WidgetTester tester, {
    bool aggregate = false,
  }) async {
    final h = (await tester.runAsync(
      () => _Journey.open(cameraJpeg, preparedJpeg),
    ))!;
    addTearDown(() => tester.runAsync(h.close));
    if (aggregate) {
      // Go mediaDownloadAcrossRelays reports only the last error: a relay
      // holding the blob can be temporarily unreachable before an empty one
      // answers not-found. This does not establish the store125 incident cause.
      h.receiver.nextDownloadError =
          'all 2 relays failed, last error: download failed: not found';
    } else {
      h.receiver.failMediaDownload = true;
    }
    final failed = (await tester.runAsync(() => h.deliver(offline: false)))!;
    expect(h.sender.relayStore.blobIds, contains(failed.id));
    expect(
      failed.downloadStatus,
      isNot(
        anyOf(
          kMediaDownloadStatusDownloadFailed,
          kMediaDownloadStatusUnavailable,
        ),
      ),
      reason:
          'One temporary transport failure must retain recovery, not terminal unavailability',
    );
    expect(failed.downloadStatus, kMediaDownloadStatusFailed);
    expect(failed.downloadRetryCount, 1);
    expect(
      GroupMediaIntegrityPolicy.isRetryableDownloadFailure(failed),
      isTrue,
    );
    h.receiver.failMediaDownload = false;
    final recovered = await tester.runAsync(
      () => downloadMedia(
        bridge: h.receiver,
        mediaAttachmentRepo: h.bob.repo,
        mediaFileManager: h.files,
        attachment: failed,
        contactPeerId: _alice.peerId,
        owner: MediaOwnerLane.direct,
        messageRepo: h.bob.messageRepo,
      ),
    );
    expect(recovered, isNotNull);
    await h.expectFullImage(tester, recovered!);
    expect(
      h.receiver.commandLog.where((c) => c == 'media:download'),
      hasLength(2),
    );
  }

  testWidgets(
    'two reported QUIC transport failures retry automatically without unavailable UI',
    (tester) async {
      final h = (await tester.runAsync(
        () => _Journey.open(cameraJpeg, preparedJpeg),
      ))!;
      addTearDown(() => tester.runAsync(h.close));
      h.receiver.transportErrors.addAll([
        'download stream: received a stateless reset',
        'download stream: connection closed (remote): code: 0x0: transport error: Application error 0x0 (remote)',
      ]);
      final successGate = (await tester.runAsync(
        () async => Completer<void>(),
      ))!;
      h.receiver.successGate = successGate;
      late Future<MediaAttachment> delivery;
      await tester.runAsync(() async {
        delivery = h.deliver(offline: false);
        await h.firstDownloadFailureCommitted.future.timeout(
          const Duration(seconds: 30),
        );
      });
      addTearDown(
        () => tester.runAsync(() async {
          if (!successGate.isCompleted) successGate.complete();
          await delivery.timeout(const Duration(seconds: 30));
        }),
      );
      final row = (await tester.runAsync(
        () => h.bob.repo.getAttachmentsForMessage(
          h.messageId!,
          owner: MediaOwnerLane.direct,
        ),
      ))!.single;
      expect(
        row.downloadStatus,
        kMediaDownloadStatusPending,
        reason:
            'Transport retry must remain pending, not the unavailable failed state',
      );
      expect(
        row.downloadRetryCount ?? 0,
        0,
        reason:
            'Transport interruption cannot spend the nontransport retry cap',
      );
      expect(
        h.latestPublished!.media.single.downloadStatus,
        kMediaDownloadStatusDownloading,
      );
      await tester.pumpWidget(
        h.wrap(
          MediaGridCell(
            attachment: h.latestPublished!.media.single,
            onRetryUnavailableMedia: () {},
          ),
        ),
      );
      for (final text in [
        "Couldn't load yet. Tap to try again.",
        'No longer available',
        "Couldn't open this file",
      ]) {
        expect(find.text(text), findsNothing);
      }
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final done = (await tester.runAsync(() async {
        successGate.complete();
        return delivery;
      }))!;
      await h.expectFullImage(tester, done);
      expect(h.receiver.downloadAttempts, hasLength(3));
      expect(
        h.receiver.downloadAttempts[1].difference(
          h.receiver.downloadAttempts[0],
        ),
        greaterThanOrEqualTo(const Duration(milliseconds: 500)),
      );
      expect(
        h.receiver.downloadAttempts[2].difference(
          h.receiver.downloadAttempts[1],
        ),
        greaterThanOrEqualTo(const Duration(seconds: 1)),
      );
    },
  );

  testWidgets(
    'transport burst stays retryable without consuming the nontransport cap',
    (tester) async {
      final h = (await tester.runAsync(
        () => _Journey.open(cameraJpeg, preparedJpeg),
      ))!;
      addTearDown(() => tester.runAsync(h.close));
      h.receiver.transportErrors.addAll(
        List.filled(3, 'received a stateless reset'),
      );
      final pending = (await tester.runAsync(() => h.deliver(offline: false)))!;
      expect(pending.downloadStatus, kMediaDownloadStatusRetryWaiting);
      expect(pending.downloadRetryCount ?? 0, 0);
      expect(
        h.receiver.downloadAttempts,
        hasLength(3),
        reason: 'active retry burst is bounded',
      );
      expect(h.sender.relayStore.blobIds, contains(pending.id));
      final recovered = (await tester.runAsync(
        () => downloadMedia(
          bridge: h.receiver,
          mediaAttachmentRepo: h.bob.repo,
          mediaFileManager: h.files,
          attachment: pending,
          contactPeerId: _alice.peerId,
          owner: MediaOwnerLane.direct,
          messageRepo: h.bob.messageRepo,
        ),
      ))!;
      await h.expectFullImage(tester, recovered);
      expect(h.receiver.downloadAttempts, hasLength(4));
    },
  );

  testWidgets('truncated native download and response EOF retry to full image', (
    tester,
  ) async {
    final h = (await tester.runAsync(
      () => _Journey.open(cameraJpeg, preparedJpeg),
    ))!;
    addTearDown(() => tester.runAsync(h.close));
    h.receiver.transportErrors.addAll([
      'all 1 relays failed, last error: download incomplete: wrote 4096/4978763, err=EOF',
      'all 1 relays failed, last error: download request: read response: EOF',
    ]);
    final done = (await tester.runAsync(() => h.deliver(offline: false)))!;
    expect(h.receiver.downloadAttempts, hasLength(3));
    await h.expectFullImage(tester, done);
  });

  testWidgets(
    'closed chat offline burst and reconnecting restore recover on later relay readiness without a tap',
    (tester) async {
      final h = (await tester.runAsync(
        () => _Journey.open(cameraJpeg, preparedJpeg),
      ))!;
      addTearDown(() => tester.runAsync(h.close));
      final done = await tester.runAsync(() async {
        final states = <String>[];
        final publication = h.listener.incomingMessageStream.listen(
          (message) => states.addAll(
            message.media.map((attachment) => attachment.downloadStatus),
          ),
        );
        final p2p = FakeP2PService();
        final restored = StreamController<void>.broadcast();
        final passes = <Future<int>>[];
        final recoveryErrors = <Object>[];
        var recoveryTriggers = 0;
        final retrier = PendingMessageRetrier(
          p2pService: p2p,
          bridge: h.receiver,
          messageRepo: h.bob.messageRepo,
          identityRepo: FakeIdentityRepository(),
          contactRepo: buildWidgetContactRepository(h.bob.db),
          networkRestoredSignal: restored.stream,
          networkRestoredDebounce: const Duration(milliseconds: 20),
          retryDebounce: const Duration(milliseconds: 20),
          periodicRetryInterval: const Duration(hours: 1),
          groupContinuitySweepInterval: const Duration(hours: 1),
          retryFailedMessagesOverride: () async => 0,
          retryUnackedMessagesOverride: () async => 0,
          drainDirectMediaBlobCustodyFn: () async {
            recoveryTriggers++;
            // Match the production primary hook: its existing listener owns
            // the incoming pass without holding the outgoing short flush.
            final pass = h.listener.retryIncompleteMediaDownloads().catchError((
              Object error,
            ) {
              recoveryErrors.add(error);
              return 0;
            });
            passes.add(pass);
            unawaited(pass);
            return 0;
          },
        );
        try {
          h.receiver.preservePartialOnFailure = true;
          // Exact native errors from device attempts 1-3: the multi-address
          // fallback hides dial backoff behind its final connection failure.
          h.receiver.transportErrors.addAll([
            'all 1 relays failed, last error: download request: read response: read length: write udp4 <ip>-><ip>: sendmsg: network is unreachable',
            'all 1 relays failed, last error: connection failed',
            'all 1 relays failed, last error: connection failed',
          ]);
          final offline = await h.deliver(offline: false);
          expect(offline.downloadStatus, kMediaDownloadStatusRetryWaiting);
          expect(offline.downloadRetryCount ?? 0, 0);
          expect(h.receiver.downloadAttempts, hasLength(3));
          expect(
            await File(h.receiver.failedPartPath!).readAsBytes(),
            h.sender.relayStore.ciphertextByBlobId[offline.id]!.take(4096),
          );

          // Attempt 4 mirrors the early OS-restored device attempt while the
          // relay is connecting; two bounded follow-ups still cannot connect.
          h.receiver.transportErrors.addAll(
            List.filled(
              3,
              'all 1 relays failed, last error: connection failed',
            ),
          );
          final earlyRestore = h.listener.incomingMessageStream.firstWhere(
            (message) =>
                message.id == h.messageId &&
                h.receiver.downloadAttempts.length >= 6 &&
                message.media.single.downloadStatus ==
                    kMediaDownloadStatusRetryWaiting,
          );
          retrier.start();
          p2p.emitState(
            const NodeState(isStarted: true, relayState: 'connecting'),
          );
          restored.add(null);
          final retained = await earlyRestore.timeout(
            const Duration(seconds: 30),
          );
          expect(retained.media.single.downloadRetryCount ?? 0, 0);
          expect(h.receiver.downloadAttempts, hasLength(6));
          expect(p2p.currentState.relayState, 'connecting');
          expect(h.sender.relayStore.blobIds, contains(offline.id));

          final received = h.listener.incomingMessageStream.firstWhere(
            (message) =>
                message.id == h.messageId &&
                message.media.single.downloadStatus == kMediaDownloadStatusDone,
          );
          p2p.emitState(
            const NodeState(
              isStarted: true,
              circuitAddresses: ['/p2p-circuit/relay'],
              relayState: 'online',
              sendCapabilityReady: true,
              inboxCapabilityReady: true,
            ),
          );
          final recovered = await received.timeout(const Duration(seconds: 30));
          expect(recoveryTriggers, 2);
          expect(h.receiver.downloadAttempts, hasLength(7));
          expect(recoveryErrors, isEmpty);
          expect(
            states,
            isNot(
              contains(
                anyOf(
                  kMediaDownloadStatusFailed,
                  kMediaDownloadStatusDownloadFailed,
                  kMediaDownloadStatusUnavailable,
                  kMediaDownloadStatusIntegrityFailed,
                ),
              ),
            ),
          );
          return recovered.media.single;
        } finally {
          retrier.dispose();
          await restored.close();
          p2p.dispose();
          await Future.wait(passes).timeout(const Duration(seconds: 30));
          await publication.cancel();
        }
      });
      if (done == null) {
        return;
      }
      await h.expectFullImage(tester, done);
    },
  );

  for (final error in [
    'download failed: not found',
    'download failed: not authorized',
  ]) {
    testWidgets('connected relay $error stays terminal', (tester) async {
      final h = (await tester.runAsync(
        () => _Journey.open(cameraJpeg, preparedJpeg),
      ))!;
      addTearDown(() => tester.runAsync(h.close));
      h.receiver.nextDownloadError = error;
      final failed = (await tester.runAsync(() => h.deliver(offline: false)))!;
      expect(failed.downloadStatus, kMediaDownloadStatusUnavailable);
      expect(h.receiver.downloadAttempts, hasLength(1));
      await tester.pumpWidget(
        h.wrap(
          MediaGridCell(attachment: failed, onRetryUnavailableMedia: () {}),
        ),
      );
      expect(find.text('No longer available'), findsOneWidget);
      expect(find.byTooltip('Retry'), findsNothing);
      expect(
        (await tester.runAsync(
          () => h.bob.messageRepo.getMessage(h.messageId!),
        ))!.text,
        _caption,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  for (final trigger in [
    'foreground',
    'connectivity',
    'open-connectivity',
    'interrupted-connectivity',
  ]) {
    final openChat = trigger == 'open-connectivity';
    testWidgets(
      '${openChat ? 'open' : 'closed'}-chat retained failure recovers on app $trigger',
      (tester) async {
        final h = (await tester.runAsync(
          () => _Journey.open(cameraJpeg, preparedJpeg),
        ))!;
        addTearDown(() => tester.runAsync(h.close));
        h.receiver.failMediaDownload = true;
        final failed = (await tester.runAsync(
          () => h.deliver(offline: false),
        ))!;
        expect(failed.downloadStatus, kMediaDownloadStatusFailed);
        expect(failed.downloadRetryCount, 1);
        await tester.runAsync(() async {
          // Legacy failed rows keep their established cap. A transport-pending
          // row has different authority and remains recoverable beyond that cap.
          await h.bob.db.update(
            'media_attachments',
            {'download_retry_count': 3},
            where: 'id = ?',
            whereArgs: [failed.id],
          );
          expect(await h.listener.retryIncompleteMediaDownloads(), 0);
          expect(h.receiver.downloadAttempts, hasLength(1));
          await h.bob.db.update(
            'media_attachments',
            {
              'download_retry_count':
                  trigger.endsWith('connectivity') &&
                      trigger != 'open-connectivity'
                  ? 0
                  : 1,
              'download_status': trigger == 'interrupted-connectivity'
                  ? 'downloading'
                  : trigger == 'connectivity'
                  ? 'retry_waiting'
                  : 'failed',
            },
            where: 'id = ?',
            whereArgs: [failed.id],
          );
        });
        await tester.pumpWidget(
          h.wrap(
            MediaGridCell(attachment: failed, onRetryUnavailableMedia: () {}),
          ),
        );
        for (final text in [
          "Couldn't load yet. Tap to try again.",
          'No longer available',
          "Couldn't open this file",
        ]) {
          expect(find.text(text), findsNothing);
        }
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        // Remove the media widget entirely: neither recovery trigger can rely on
        // a conversation route, bubble rebuild or user Retry tap.
        await tester.pumpWidget(const SizedBox.shrink());
        final recovered = await tester.runAsync(() async {
          h.receiver.failMediaDownload = false;
          final hydrated = h.listener.incomingMessageStream.firstWhere(
            (m) =>
                m.id == h.messageId &&
                m.media.single.downloadStatus == kMediaDownloadStatusDone,
          );
          final p2p = FakeP2PService();
          try {
            if (openChat) {
              // Native protection events are an explicit host boundary. Ordinary
              // media below never enters a protected viewer or claims OS proof.
              final messenger = tester.binding.defaultBinaryMessenger;
              messenger.setMockMessageHandler(
                kPrivateMediaProtectionEventChannel,
                (_) async =>
                    const StandardMethodCodec().encodeSuccessEnvelope(null),
              );
              addTearDown(
                () => messenger.setMockMessageHandler(
                  kPrivateMediaProtectionEventChannel,
                  null,
                ),
              );
              // Keep initial route load from retrying, then restore the actual
              // retained failure before connectivity changes. Only the restored
              // signal below can initiate this download.
              await h.bob.repo.updateDownloadStatus(
                failed.id,
                kMediaDownloadStatusEvicted,
              );
              final contacts = buildWidgetContactRepository(h.bob.db);
              final contact = (await contacts.getContact(_alice.peerId))!;
              await tester.pumpWidget(
                h.wrap(
                  ConversationWired(
                    contact: contact,
                    identityRepo: FakeIdentityRepository()
                      ..seed(
                        FakeIdentityRepository.makeIdentity(
                          peerId: _bob.peerId,
                        ),
                      ),
                    messageRepo: h.bob.messageRepo,
                    chatMessageListener: h.listener,
                    p2pService: p2p,
                    bridge: h.receiver,
                    contactRepo: contacts,
                    mediaAttachmentRepo: h.bob.repo,
                    mediaFileManager: h.files,
                    micPermissionGateway: FakeMicPermissionGateway(),
                  ),
                ),
              );
              for (
                var i = 0;
                i < 80 && find.text(_caption).evaluate().isEmpty;
                i++
              ) {
                await Future<void>.delayed(const Duration(milliseconds: 25));
                await tester.pump();
              }
              expect(find.text(_caption), findsWidgets);
              expect(h.receiver.downloadAttempts, hasLength(1));
              await h.bob.repo.updateDownloadStatus(
                failed.id,
                kMediaDownloadStatusFailed,
              );
            }
            if (trigger == 'foreground') {
              final result = await handleAppResumed(
                bridge: h.receiver,
                p2pService: p2p,
                drainDirectMediaBlobCustodyFn:
                    h.listener.retryIncompleteMediaDownloads,
              );
              expect(result, isTrue);
            } else {
              final restored = StreamController<void>.broadcast();
              final retrier = PendingMessageRetrier(
                p2pService: p2p,
                bridge: h.receiver,
                messageRepo: h.bob.messageRepo,
                identityRepo: FakeIdentityRepository(),
                contactRepo: buildWidgetContactRepository(h.bob.db),
                networkRestoredSignal: restored.stream,
                networkRestoredDebounce: const Duration(milliseconds: 20),
                drainDirectMediaBlobCustodyFn:
                    h.listener.retryIncompleteMediaDownloads,
                retryUnackedMessagesOverride: () async => 0,
              );
              try {
                retrier.start();
                restored.add(null);
                await hydrated.timeout(const Duration(seconds: 30));
              } finally {
                retrier.dispose();
                await restored.close();
              }
            }
            final hydratedMessage = await hydrated.timeout(
              const Duration(seconds: 30),
            );
            if (openChat) {
              await tester.pump();
              final image = find.byType(Image).first;
              await precacheImage(
                tester.widget<Image>(image).image,
                tester.element(image),
              ).timeout(const Duration(seconds: 20));
              await tester.pump();
              final screen = tester.widget<ConversationScreen>(
                find.byType(ConversationScreen),
              );
              expect(
                screen.messages
                    .singleWhere((m) => m.id == h.messageId)
                    .media
                    .single
                    .downloadStatus,
                kMediaDownloadStatusDone,
              );
              for (final text in [
                "Couldn't load yet. Tap to try again.",
                'No longer available',
                "Couldn't open this file",
              ]) {
                expect(find.text(text), findsNothing);
              }
            }
            return hydratedMessage.media.single;
          } finally {
            p2p.dispose();
          }
        });
        expect(h.receiver.downloadAttempts, hasLength(2));
        await h.expectFullImage(tester, recovered!);
      },
    );
  }

  testWidgets(
    'direct recovery pages past unrelated first-page rows for every media kind',
    (tester) async {
      final h = (await tester.runAsync(
        () => _Journey.open(cameraJpeg, preparedJpeg),
      ))!;
      addTearDown(() => tester.runAsync(h.close));
      h.receiver.failMediaDownload = true;
      final failed = (await tester.runAsync(() => h.deliver(offline: false)))!;
      final recovered = await tester.runAsync(() async {
        for (var i = 0; i < 25; i++) {
          final id = '00000000-0000-0000-0000-${i.toString().padLeft(12, '0')}';
          await h.bob.seedDirectParent(id);
          await h.bob.db.update(
            'messages',
            {'is_incoming': 0},
            where: 'id = ?',
            whereArgs: [id],
          );
          final kind = ['image', 'video', 'audio', 'file'][i % 4];
          await h.bob.repo.saveAttachment(
            MediaAttachment(
              id: 'page-$i',
              messageId: id,
              mime: kind == 'file' ? 'application/pdf' : '$kind/test',
              size: 4096,
              mediaType: kind,
              downloadStatus: kMediaDownloadStatusPending,
              createdAt: '2026-10-20T00:00:00Z',
            ),
            owner: MediaOwnerLane.direct,
          );
        }
        final firstPage = await dbLoadRetryableDirectMediaMessageIds(h.bob.db);
        expect(firstPage, hasLength(25));
        expect(firstPage, isNot(contains(h.messageId)));
        // The first page is real SQL, containing all media kinds but outgoing
        // parents. They must not starve the eligible receive on the next page.
        h.receiver.failMediaDownload = false;
        expect(await h.listener.retryIncompleteMediaDownloads(), 1);
        return (await h.bob.repo.getAttachmentsForMessage(
          h.messageId!,
          owner: MediaOwnerLane.direct,
        )).single;
      });
      expect(h.receiver.downloadAttempts, hasLength(2));
      expect(failed.downloadStatus, kMediaDownloadStatusFailed);
      await h.expectFullImage(tester, recovered!);
    },
  );

  for (final activeOwner in ['arrival', 'recovery']) {
    testWidgets(
      'restore edge during active $activeOwner survives a stale final transport failure',
      (tester) async {
        final h = (await tester.runAsync(
          () => _Journey.open(cameraJpeg, preparedJpeg),
        ))!;
        addTearDown(() => tester.runAsync(h.close));
        final done = await tester.runAsync(() async {
          if (activeOwner == 'recovery') {
            h.receiver.failMediaDownload = true;
            await h.deliver(offline: false);
            h.receiver.failMediaDownload = false;
          }
          final finished = h.listener.incomingMessageStream.firstWhere(
            (m) =>
                m.id == h.messageId &&
                m.media.any(
                  (a) => a.downloadStatus == kMediaDownloadStatusDone,
                ),
          );
          final gate = Completer<void>();
          h.receiver.lastFailureGate = gate;
          h.receiver.transportErrors.addAll(
            List.filled(3, 'received a stateless reset'),
          );
          Future<MediaAttachment>? arrival;
          Future<int>? recovery;
          if (activeOwner == 'arrival') {
            arrival = h.deliver(offline: false);
          } else {
            recovery = h.listener.retryIncompleteMediaDownloads();
          }
          Future<int>? restored;
          try {
            await h.receiver.lastFailureEntered.future.timeout(
              const Duration(seconds: 30),
            );
            // The native third attempt is still held while restoration arrives.
            // For arrival, witness the real SQL page before advancing one event
            // turn; NoIsolate SQLite work completes in the intervening microtasks.
            if (activeOwner == 'arrival') {
              h.recoveryPageLoaded = Completer<void>();
            }
            restored = h.listener.retryIncompleteMediaDownloads();
            if (activeOwner == 'arrival') await h.recoveryPageLoaded!.future;
            await Future<void>.delayed(Duration.zero);
            gate.complete();
            final result = await finished.timeout(const Duration(seconds: 10));
            return result.media.single;
          } finally {
            if (!gate.isCompleted) gate.complete();
            if (arrival != null) {
              await arrival.timeout(const Duration(seconds: 30));
            }
            if (recovery != null) {
              await recovery.timeout(const Duration(seconds: 30));
            }
            if (restored != null) {
              await restored.timeout(const Duration(seconds: 30));
            }
          }
        });
        if (done == null) return; // runAsync already reports its failure.
        expect(
          h.receiver.downloadAttempts,
          hasLength(activeOwner == 'arrival' ? 4 : 5),
        );
        await h.expectFullImage(tester, done);
      },
    );
  }

  group(
    'KNOWN GAP: mixed-relay temporary failure is mistaken for terminal not-found',
    () {
      testWidgets(
        'aggregate relay error preserves retry and eventual full image plus caption',
        (tester) => expectTransientRecovery(tester, aggregate: true),
      );
    },
    skip:
        'KNOWN GAP: download_media_use_case.dart substring-matches not found inside the '
        'multi-relay aggregate, terminalizes a recoverable failure, and removes Retry. '
        'Run with --run-skipped to retain the desired-retry failure.',
  );
}

class _Journey {
  _Journey(
    this.root,
    this.alice,
    this.bob,
    this.sender,
    this.receiver,
    this.files,
  );
  final Directory root;
  final MediaRepositoryRealDbFixture alice;
  final MediaRepositoryRealDbFixture bob;
  final EncryptedMediaTestBridge sender;
  final _ReceiverBridge receiver;
  final MediaFileManager files;
  late final TestEd25519Identity senderIdentity;
  late final TestEd25519Identity receiverIdentity;
  late final ChatMessageListener listener;
  late final P2PServiceImpl service;
  late Uint8List expectedBytes;
  String? messageId;
  String? deliveredWire;
  late Completer<void> firstDownloadFailureCommitted;
  Completer<void>? recoveryPageLoaded;
  ConversationMessage? latestPublished;
  StreamSubscription<ConversationMessage>? _publication;

  static Future<_Journey> open(
    Uint8List camera,
    Uint8List prepared, {
    bool reversePeers = false,
  }) async {
    final root = await Directory.systemTemp.createTemp('camera_caption_relay_');
    // OS directory lookup only; all file work still uses MediaFileManager.
    final previousPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _DocumentsPath(root.path);
    addTearDown(() => PathProviderPlatform.instance = previousPaths);
    final alice = await MediaRepositoryRealDbFixture.create(
      databasePath: '${root.path}/alice.db',
      databaseFactoryOverride: databaseFactoryFfiNoIsolate,
    );
    final firstFailureCommitted = Completer<void>();
    _ReceiverBridge? receiverForFailureBarrier;
    final bob = await MediaRepositoryRealDbFixture.create(
      databasePath: '${root.path}/bob.db',
      databaseFactoryOverride: databaseFactoryFfiNoIsolate,
      dbSaveMediaAttachmentAround: (row, persist) async {
        await persist();
        if (((row['download_retry_count'] as int? ?? 0) > 0 ||
                (row['download_status'] == kMediaDownloadStatusPending &&
                    (receiverForFailureBarrier?.downloadAttempts.isNotEmpty ??
                        false))) &&
            !firstFailureCommitted.isCompleted) {
          firstFailureCommitted.complete();
        }
      },
    );
    final store = RelayMediaStore();
    final sender = EncryptedMediaTestBridge(store, seedSalt: 10);
    final receiver = _ReceiverBridge(store);
    receiverForFailureBarrier = receiver;
    final files = MediaFileManager();
    MediaFileManager.cacheDocumentsDir(root.path);
    final h = _Journey(root, alice, bob, sender, receiver, files)
      ..senderIdentity = reversePeers ? _bob : _alice
      ..receiverIdentity = reversePeers ? _alice : _bob
      ..expectedBytes = prepared
      ..firstDownloadFailureCommitted = firstFailureCommitted;
    final contacts = buildWidgetContactRepository(bob.db);
    await contacts.addContact(
      ContactModel(
        peerId: h.senderIdentity.peerId,
        username: 'Alice',
        publicKey: h.senderIdentity.publicKey,
        rendezvous: 'test-rendezvous',
        signature: 'test-contact-signature',
        scannedAt: DateTime.now().toUtc().toIso8601String(),
        mlKemPublicKey: 'test-mlkem-alice',
      ),
    );
    h.listener = ChatMessageListener(
      loadRetryableMediaMessageIds:
          ({String? afterMessageId, int limit = 25}) async {
            final rows = await dbLoadRetryableDirectMediaMessageIds(
              bob.db,
              afterMessageId: afterMessageId,
              limit: limit,
            );
            final witness = h.recoveryPageLoaded;
            if (witness != null && !witness.isCompleted) witness.complete();
            return rows;
          },
      chatMessageStream: const Stream<ChatMessage>.empty(),
      messageRepo: bob.messageRepo,
      contactRepo: contacts,
      bridge: receiver,
      getOwnMlKemSecretKey: () async => 'test-mlkem-bob-secret',
      mediaAttachmentRepo: bob.repo,
      mediaFileManager: files,
    );
    h._publication = h.listener.incomingMessageStream.listen(
      (message) => h.latestPublished = message,
    );
    h.service = P2PServiceImpl(
      bridge: receiver,
      inboxStagingRepository: _staging(bob.db),
      replayRecoveredInboxChatMessage:
          (message, {String? stagedEntryId}) async =>
              mapChatReplayOutcomeToDisposition(
                await h.listener.processIncomingMessage(
                  message,
                  suppressNotification: true,
                  stagedEntryId: stagedEntryId,
                ),
              ),
    );
    await File('${root.path}/camera.jpg').writeAsBytes(camera, flush: true);
    return h;
  }

  Future<MediaAttachment> deliver({
    required bool offline,
    ImageQualityPreference imageQuality = ImageQualityPreference.original,
  }) async {
    final pending = await preparePendingComposerMedia(
      inputPath: '${root.path}/camera.jpg',
      imageProcessor: ImageProcessor(
        compressFile:
            ({
              required String path,
              required int quality,
              required bool keepExif,
              int minWidth = 1920,
              int minHeight = 1080,
            }) async {
              expect(path, '${root.path}/camera.jpg');
              expect(
                quality,
                imageQuality == ImageQualityPreference.original ? 100 : 85,
                reason:
                    'selected quality reaches the native compressor boundary',
              );
              expect(
                keepExif,
                isFalse,
                reason: 'EXIF stripping stays requested',
              );
              final output = '${root.path}/prepared-camera.jpg';
              await File(output).writeAsBytes(expectedBytes, flush: true);
              return XFile(output);
            },
      ),
      imageQualityPreference: imageQuality,
      videoQualityPreference: ImageQualityPreference.original,
    );
    expect(pending.budgetBytes, expectedBytes.length);
    expect(await pending.file.readAsBytes(), expectedBytes);
    // Published/default-off lane: direct_media_blob_custody_client_flag.dart.
    final uploaded = (await uploadMedia(
      bridge: sender,
      localFilePath: pending.file.path,
      mime: 'image/jpeg',
      recipientPeerId: receiverIdentity.peerId,
      mediaFileManager: files,
    )).attachmentOrNull;
    expect(uploaded, isNotNull);
    expect(uploaded!.blobCustody, isNull);
    expect(uploaded.size, expectedBytes.length);
    expect(
      sender.relayStore.uploadedBytesByBlobId[uploaded.id],
      isNot(equals(expectedBytes)),
    );
    final p2p = FakeP2PService(
      initialState: NodeState(isStarted: true, peerId: senderIdentity.peerId),
    );
    addTearDown(p2p.dispose);
    String? inboxEnvelope;
    final (result, _) = await sendChatMessage(
      p2pService: p2p,
      messageRepo: alice.messageRepo,
      targetPeerId: receiverIdentity.peerId,
      text: _caption,
      senderPeerId: senderIdentity.peerId,
      senderUsername: 'Alice',
      bridge: sender,
      recipientMlKemPublicKey: 'test-mlkem-bob',
      mediaAttachments: [uploaded],
      mediaAttachmentRepo: alice.repo,
      storeInAckCustodyInboxDetailed:
          (peer, wire, {required custodyKind, timeoutMs}) async {
            expect(peer, receiverIdentity.peerId);
            inboxEnvelope = wire;
            return InboxStoreOutcome(
              status: InboxStoreStatus.stored,
              storeStatus: 'stored',
              expiresAtMs: DateTime.now()
                  .add(const Duration(days: 1))
                  .millisecondsSinceEpoch,
              custodyContract: ackOrExpiryInboxCustodyContract,
            );
          },
    );
    expect(result, SendChatMessageResult.success);
    final sent = (await alice.messageRepo.getMessagesForContact(
      receiverIdentity.peerId,
    )).single;
    messageId = sent.id;
    final wire = inboxEnvelope ?? p2p.lastSendMessageContent;
    expect(wire, isNotNull);
    deliveredWire = wire;
    expect(await bob.messageRepo.getMessage(sent.id), isNull);
    // Wait for actual completion, excluding parent persist and active loading
    // emissions. A deferred/terminal failure also completes one bounded burst.
    final hydrated = listener.incomingMessageStream.firstWhere(
      (m) =>
          m.id == sent.id &&
          m.media.isNotEmpty &&
          m.media.every(
            (a) => !{
              kMediaDownloadStatusPending,
              kMediaDownloadStatusDownloading,
            }.contains(a.downloadStatus),
          ),
    );
    if (offline) {
      receiver.pending.add({
        'id': 'camera-inbox-entry',
        'from': senderIdentity.peerId,
        'message': wire,
        'timestamp': DateTime.now().toUtc().toIso8601String(),
      });
      await service.startNodeCore(
        'cHJpdmF0ZWtleXRlc3Q=',
        receiverIdentity.peerId,
      );
      final drained = await service.drainOfflineInboxFully();
      expect(drained.isSuccessful, isTrue);
      expect(receiver.acked, contains('camera-inbox-entry'));
      expect(receiver.pending, isEmpty);
    } else {
      final outcome = await listener.processIncomingMessage(
        ChatMessage(
          from: senderIdentity.peerId,
          to: receiverIdentity.peerId,
          content: wire!,
          timestamp: DateTime.now().toUtc().toIso8601String(),
          isIncoming: true,
          transport: 'relay',
        ),
      );
      expect(outcome.state, ChatMessageProcessState.stored);
      expect(receiver.acked, isEmpty);
    }
    final completed = await hydrated.timeout(const Duration(seconds: 30));
    expect(completed.text, _caption);
    return completed.media.single;
  }

  Future<void> expectSingleCopyAfterReplay() async {
    final downloadsBefore = receiver.downloadAttempts.length;
    await listener.processIncomingMessage(
      ChatMessage(
        from: senderIdentity.peerId,
        to: receiverIdentity.peerId,
        content: deliveredWire!,
        timestamp: DateTime.now().toUtc().toIso8601String(),
        isIncoming: true,
        transport: 'relay',
      ),
    );
    final messages = await bob.messageRepo.getMessagesForContact(
      senderIdentity.peerId,
    );
    expect(messages.map((m) => m.id).toList(), [messageId]);
    expect(messages.single.text, _caption);
    final attachments = await bob.repo.getAttachmentsForMessage(
      messageId!,
      owner: MediaOwnerLane.direct,
    );
    expect(attachments, hasLength(1));
    expect(attachments.single.downloadStatus, kMediaDownloadStatusDone);
    expect(receiver.downloadAttempts.length, downloadsBefore);
  }

  Widget wrap(Widget child) => MaterialApp(
    locale: const Locale('en'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(body: child),
  );

  Future<void> expectFullImage(
    WidgetTester tester,
    MediaAttachment attachment, {
    int width = 3024,
    int height = 4032,
  }) async {
    final persisted = await tester.runAsync(
      () => bob.repo.getAttachmentsForMessage(
        messageId!,
        owner: MediaOwnerLane.direct,
      ),
    );
    expect(persisted!.single.downloadStatus, kMediaDownloadStatusDone);
    expect(attachment.downloadStatus, kMediaDownloadStatusDone);
    expect(
      receiver.commandLog,
      containsAll(['media:download', 'blob:decrypt']),
    );
    final path = await files.resolveStoredPath(persisted.single.localPath!);
    final bytes = await tester.runAsync(() => File(path).readAsBytes());
    expect(sha256.convert(bytes!), sha256.convert(expectedBytes));
    final decoded = img.decodeJpg(bytes)!;
    expect((decoded.width, decoded.height), (width, height));
    final message = await tester.runAsync(
      () => bob.messageRepo.getMessage(messageId!),
    );
    expect(message!.text, _caption);
    var opened = false;
    await _mountDecodedImage(
      tester,
      wrap(
        MediaGridCell(attachment: persisted.single, onTap: () => opened = true),
      ),
    );
    for (final text in [
      "Couldn't load yet. Tap to try again.",
      'No longer available',
      "Couldn't open this file",
    ]) {
      expect(find.text(text), findsNothing);
    }
    await tester.tap(
      find.byKey(ValueKey('media-grid-cell-$messageId-${attachment.id}')),
    );
    expect(
      opened,
      isTrue,
      reason: 'production render gate must permit opening',
    );
    await _mountDecodedImage(
      tester,
      wrap(
        FullScreenTypedMediaViewer(
          items: [
            MediaViewerItem(
              attachmentId: attachment.id,
              messageId: messageId!,
              kind: MediaViewerKind.image,
              mime: attachment.mime,
              owner: MediaOwnerLane.direct,
              localPath: path,
              sizeBytes: bytes.length,
              caption: message.text,
            ),
          ],
        ),
      ),
    );
    expect(find.byKey(const ValueKey('media_meta_caption')), findsOneWidget);
    expect(find.text(_caption), findsOneWidget);
    for (final text in [
      "Couldn't load yet. Tap to try again.",
      'No longer available',
      "Couldn't open this file",
    ]) {
      expect(find.text(text), findsNothing);
    }
    expect(
      tester
          .widgetList<RawImage>(find.byType(RawImage))
          .any((w) => w.image?.width == width && w.image?.height == height),
      isTrue,
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  }

  Future<void> _mountDecodedImage(WidgetTester tester, Widget widget) async {
    // Build and resolve the actual renderer provider in the real async zone.
    // Creating a FileImage stream in the fake zone and awaiting it in runAsync
    // leaves its file/decode callbacks stranded in the fake clock.
    await tester.runAsync(() async {
      await tester.pumpWidget(widget);
      final image = find.byType(Image).first;
      await precacheImage(
        tester.widget<Image>(image).image,
        tester.element(image),
      ).timeout(const Duration(seconds: 20));
    });
    await tester.pumpAndSettle();
  }

  Future<void> close() async {
    await _publication?.cancel();
    listener.dispose();
    service.dispose();
    MediaFileManager.debugResetDocumentsDirCache();
    await alice.dispose();
    await bob.dispose();
    await root.delete(recursive: true);
  }
}

class _DocumentsPath extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  _DocumentsPath(this.path);
  final String path;
  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

class _ReceiverBridge extends EncryptedMediaTestBridge {
  _ReceiverBridge(super.relayStore) : super(seedSalt: 20);
  final pending = <Map<String, dynamic>>[];
  final acked = <String>[];
  String? nextDownloadError;
  final transportErrors = <String>[];
  final downloadAttempts = <DateTime>[];
  bool preservePartialOnFailure = false;
  String? failedPartPath;
  Completer<void>? successGate;
  Completer<void>? lastFailureGate;
  final lastFailureEntered = Completer<void>();
  @override
  Future<String> send(String message) async {
    final request = jsonDecode(message) as Map<String, dynamic>;
    final payload = request['payload'] as Map<String, dynamic>? ?? {};
    if (request['cmd'] == 'media:download') {
      downloadAttempts.add(DateTime.now());
      if (transportErrors.isNotEmpty) {
        final error = transportErrors.removeAt(0);
        commandLog.add('media:download');
        if (preservePartialOnFailure) {
          failedPartPath = payload['outputPath'] as String;
          final partial = File(failedPartPath!);
          await partial.parent.create(recursive: true);
          await partial.writeAsBytes(
            relayStore.ciphertextByBlobId[payload['id']]!.take(4096).toList(),
            flush: true,
          );
        }
        if (transportErrors.isEmpty && lastFailureGate != null) {
          if (!lastFailureEntered.isCompleted) lastFailureEntered.complete();
          await lastFailureGate!.future;
        }
        return jsonEncode({
          'ok': false,
          'errorCode': 'MEDIA_ERROR',
          'errorMessage': error,
        });
      }
      if (nextDownloadError == null) await successGate?.future;
    }
    if (request['cmd'] == 'media:download' && nextDownloadError != null) {
      final error = nextDownloadError;
      nextDownloadError = null;
      commandLog.add('media:download');
      return jsonEncode({
        'ok': false,
        'errorCode': 'MEDIA_ERROR',
        'errorMessage': error,
      });
    }
    switch (request['cmd']) {
      case 'node:start':
        return jsonEncode({
          'ok': true,
          'peerId': _bob.peerId,
          'isStarted': true,
          'listenAddresses': [],
          'circuitAddresses': [],
          'connections': [],
        });
      case 'inbox:retrieve_pending':
        return jsonEncode({
          'ok': true,
          'custodyContract': payload['custodyContract'],
          'messages':
              payload['custodyContract'] == ackOrExpiryInboxCustodyContract
              ? pending
              : [],
          'hasMore': false,
        });
      case 'inbox:ack':
        final ids = (payload['entryIds'] as List<dynamic>).cast<String>();
        acked.addAll(ids);
        pending.removeWhere((row) => ids.contains(row['id']));
        return jsonEncode({
          'ok': true,
          'acked': ids.length,
          'custodyContract': payload['custodyContract'],
        });
      default:
        return super.send(message);
    }
  }
}

InboxStagingRepositoryImpl _staging(Database db) => InboxStagingRepositoryImpl(
  dbInsertInboxStagingEntry: (row) => dbInsertInboxStagingEntry(db, row),
  dbLoadRecoverableInboxStagingEntries: ({limit = 50, entryIds}) =>
      dbLoadRecoverableInboxStagingEntries(
        db,
        limit: limit,
        entryIds: entryIds,
      ),
  dbLoadInboxStagingEntry: (id) => dbLoadInboxStagingEntry(db, id),
  dbDeleteInboxStagingEntry: (id) => dbDeleteInboxStagingEntry(db, id),
  dbMarkInboxStagingEntryRetryable: (id, {required reasonCode, reasonDetail}) =>
      dbMarkInboxStagingEntryRetryable(
        db,
        id,
        reasonCode: reasonCode,
        reasonDetail: reasonDetail,
      ),
  dbMarkInboxStagingEntryRejected: (id, {required reasonCode, reasonDetail}) =>
      dbMarkInboxStagingEntryRejected(
        db,
        id,
        reasonCode: reasonCode,
        reasonDetail: reasonDetail,
      ),
  dbMarkInboxStagingEntryQuarantined:
      (id, {required reasonCode, reasonDetail}) =>
          dbMarkInboxStagingEntryQuarantined(
            db,
            id,
            reasonCode: reasonCode,
            reasonDetail: reasonDetail,
          ),
  dbCountQuarantinedInboxStagingEntries: () =>
      dbCountQuarantinedInboxStagingEntries(db),
);
