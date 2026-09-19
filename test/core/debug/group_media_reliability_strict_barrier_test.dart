import 'dart:io';

import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/debug/group_media_reliability_e2e.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final mutation in [
    'none',
    'changed_custody',
    'changed_fingerprint',
    'changed_content_hash',
    'wrong_attachment',
    'local_ready',
    'missing_loader',
    'same_process',
  ]) {
    test(
      'strict JPEG barrier reopens actual committed custody: $mutation',
      () async {
        final dir = await Directory.systemTemp.createTemp('strict-barrier-');
        addTearDown(() => dir.delete(recursive: true));
        final first = GroupMediaReliabilityE2EController(
          enabled: true,
          stateDirectory: dir,
          currentProcessId: 101,
        );
        await first.arm(
          const GroupMediaReliabilityBarrierRequest(
            runId: 'run',
            groupId: 'group',
            jpegMessageId: 'message-jpeg',
            jpegAttachmentId: 'blob-jpeg',
            mediaMessageIds: {
              'jpeg': 'message-jpeg',
              'mp4': 'message-mp4',
              'voice': 'message-voice',
            },
            mediaAttachmentIds: {
              'jpeg': 'blob-jpeg',
              'mp4': 'blob-mp4',
              'voice': 'blob-voice',
            },
          ),
        );
        final attachment = _attachment();
        final custody = _custody();
        await first.onAutomaticDownloadAttemptStarted(attachment: attachment);
        final held = first.onStrictVerifiedCiphertext(
          attachment: attachment,
          custody: custody,
          loadCurrentAttachment: (_) async => attachment,
        );
        final reached = await first.waitForBarrierReached();
        expect(reached.priorStatus, 'pending');
        expect(reached.attempt, 1);
        expect(first.holdsAutomaticRecovery, isTrue);
        final fresh = GroupMediaReliabilityE2EController(
          enabled: true,
          stateDirectory: dir,
          currentProcessId: mutation == 'same_process' ? 101 : 202,
        );
        final result = fresh.releaseRecoveryAfterPriorStatus(
          loadCurrentAttachment: (_) async => mutation == 'wrong_attachment'
              ? attachment.copyWith(id: 'other')
              : mutation == 'changed_content_hash'
              ? attachment.copyWith(contentHash: 'b' * 64)
              : mutation == 'local_ready'
              ? attachment.copyWith(localPath: 'media/ready')
              : mutation == 'changed_fingerprint'
              ? attachment.copyWith(groupMediaBlobCustodyFingerprint: 'b' * 64)
              : attachment,
          loadStrictCustody: mutation == 'missing_loader'
              ? null
              : ({required groupId, required messageId}) async => [
                  mutation == 'changed_custody'
                      ? _custody(contentHash: 'b' * 64)
                      : custody,
                ],
        );
        if (mutation == 'none') {
          final proof = await result;
          expect(proof.strictCustody!['state'], 'incoming_committed');
          expect(proof.strictCustody!['ack_source_present'], false);
          expect(fresh.holdsAutomaticRecovery, isFalse);
          await fresh.onAutomaticDownloadAttemptStarted(attachment: attachment);
          await fresh.onStrictVerifiedCiphertext(
            attachment: attachment,
            custody: custody,
            loadCurrentAttachment: (_) async => attachment,
          );
          expect((await fresh.loadAttemptCounts())['jpeg'], 2);
        } else {
          await expectLater(result, throwsStateError);
          expect(fresh.holdsAutomaticRecovery, isTrue);
        }
        first.releaseFirstBarrierForTest();
        await held;
      },
    );
  }
}

MediaAttachment _attachment() => MediaAttachment(
  id: 'blob-jpeg',
  messageId: 'message-jpeg',
  mime: 'image/jpeg',
  mediaType: 'image',
  size: 32,
  createdAt: '2026-09-18T00:00:00Z',
  downloadStatus: 'pending',
  ownerLane: MediaOwnerLane.group,
  groupMediaBlobCustodyFingerprint: 'a' * 64,
  contentHash: 'a' * 64,
  encryptionKeyBase64: 'key',
  encryptionNonce: 'nonce',
  encryptionScheme: 'blob_aes_256_gcm_v1',
);
DirectMediaBlobCustodyRow _custody({String? contentHash}) =>
    DirectMediaBlobCustodyRow(
      attachmentId: 'blob-jpeg',
      messageId: 'message-jpeg',
      ownerLane: MediaBlobCustodyOwnerLane.group,
      groupId: 'group',
      custodyBlobId: 'gmb1_fixture',
      direction: DirectMediaBlobCustodyDirection.incoming,
      state: DirectMediaBlobCustodyState.incomingCommitted,
      inboxCustodyIncarnationId: null,
      recipientPeerId: null,
      ciphertextRelativePath: null,
      custodyKind: 'group_media_blob_v1',
      custodyContract: 'ack_or_expiry_v1',
      contentHash: contentHash ?? 'a' * 64,
      ciphertextSize: 48,
      expiresAtMs: 1900000000000,
      custodyRelayPeerId: null,
      lastAttemptAt: null,
      nextAttemptAt: null,
      createdAt: '2026-09-18T00:00:00Z',
      updatedAt: '2026-09-18T00:00:00Z',
    );
