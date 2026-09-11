import 'package:flutter_app/core/database/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/direct_media_blob_custody.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/debug/android_direct_media_blob_custody_e2e.dart';
import 'package:flutter_app/features/conversation/application/send_voice_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_test/flutter_test.dart';

const _sha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _crossedSha =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

void main() {
  test('TC-347-09 app action accepts one exact nonce-bound resume request', () {
    final request = AndroidDirectMediaBlobCustodyE2ERequest.fromConfig(
      _request(
        role: androidDirectMediaBlobCustodySenderRole,
        phase: androidDirectMediaBlobCustodySenderResumePhase,
        expectedHash: _sha,
      ),
    );

    expect(request.expectedCiphertextSha256, _sha);
    expect(request.fixtureIdentitySha256, _sha);
    expect(
      request.receipt(status: 'complete', success: true),
      containsPair('nonce', 'nonce-1'),
    );
  });

  test('TC-347-09 app action rejects crossed phases and unbound hashes', () {
    for (final mutation in <Map<String, dynamic>>[
      _request(
        role: androidDirectMediaBlobCustodyReceiverRole,
        phase: androidDirectMediaBlobCustodySenderResumePhase,
        expectedHash: _sha,
      ),
      <String, dynamic>{
        ..._request(
          role: androidDirectMediaBlobCustodySenderRole,
          phase: androidDirectMediaBlobCustodySenderResumePhase,
          expectedHash: _sha,
        ),
        'nonce': '../escape',
      },
      _request(
        role: androidDirectMediaBlobCustodySenderRole,
        phase: androidDirectMediaBlobCustodySenderResumePhase,
      ),
      _request(
        role: androidDirectMediaBlobCustodySenderRole,
        phase: androidDirectMediaBlobCustodySenderPreparePhase,
        expectedHash: _sha,
      ),
    ]) {
      expect(
        () => AndroidDirectMediaBlobCustodyE2ERequest.fromConfig(mutation),
        throwsFormatException,
      );
    }
  });

  test('TC-347-09 app action failure receipt exposes only a bounded code', () {
    final receipt = androidDirectMediaBlobCustodyE2EFailureReceipt(
      config: _request(
        role: androidDirectMediaBlobCustodySenderRole,
        phase: androidDirectMediaBlobCustodySenderResumePhase,
        expectedHash: _sha,
      ),
      error: StateError('durable voice render source is absent after restart'),
    );

    expect(receipt, containsPair('errorType', 'StateError'));
    expect(receipt, containsPair('errorCode', 'sender_render_source_absent'));
    expect(receipt.containsKey('error'), isFalse);
    expect(receipt.containsKey('stackTrace'), isFalse);
  });

  test('sender completion preserves every rejected voice disposition', () {
    for (final result in SendVoiceMessageResult.values) {
      for (final returnedMessagePresent in [false, true]) {
        for (final uploadLeaseHeld in [false, true]) {
          if (result == SendVoiceMessageResult.success &&
              returnedMessagePresent) {
            expect(
              () => requireAndroidDirectMediaVoiceSendCompletion(
                result: result,
                returnedMessagePresent: returnedMessagePresent,
                uploadLeaseHeld: uploadLeaseHeld,
              ),
              returnsNormally,
            );
            continue;
          }
          Object? failure;
          try {
            requireAndroidDirectMediaVoiceSendCompletion(
              result: result,
              returnedMessagePresent: returnedMessagePresent,
              uploadLeaseHeld: uploadLeaseHeld,
            );
          } catch (error) {
            failure = error;
          }
          expect(failure, isA<StateError>());
          final receipt = androidDirectMediaBlobCustodyE2EFailureReceipt(
            config: _request(
              role: androidDirectMediaBlobCustodySenderRole,
              phase: androidDirectMediaBlobCustodySenderResumePhase,
              expectedHash: _sha,
            ),
            error: failure!,
          );
          expect(receipt['status'], 'failed');
          expect(receipt['success'], isFalse);
          expect(receipt['errorType'], 'StateError');
          expect(receipt['errorCode'], 'sender_production_send_failed');
          expect(receipt['voiceSendResult'], result.name);
          expect(receipt['voiceSendReturnedMessage'], returnedMessagePresent);
          expect(receipt['voiceSendUploadLeaseHeld'], uploadLeaseHeld);
          expect(receipt.containsKey('error'), isFalse);
          expect(receipt.containsKey('stackTrace'), isFalse);
        }
      }
    }
  });

  test(
    'TC-347-09 sender binding uses durable cleanup authority after DB hydration',
    () {
      final request = AndroidDirectMediaBlobCustodyE2ERequest.fromConfig(
        _request(
          role: androidDirectMediaBlobCustodySenderRole,
          phase: androidDirectMediaBlobCustodySenderResumePhase,
          expectedHash: _sha,
        ),
      );
      final before = _senderRow(
        state: DirectMediaBlobCustodyState.outgoingStored,
      );
      final after = before.copyWith(
        state: DirectMediaBlobCustodyState.outgoingCleanupPending,
        inboxCustodyIncarnationId: '0123456789abcdef0123456789abcdef',
        updatedAt: '2026-08-08T12:00:01.000Z',
      );
      final parent = ConversationMessage(
        id: 'message-1',
        contactPeerId: 'peer-1',
        senderPeerId: 'sender-peer',
        text: '',
        timestamp: '2026-08-08T12:00:00.000Z',
        status: 'inboxed',
        isIncoming: false,
        createdAt: '2026-08-08T12:00:00.000Z',
        transport: 'inbox',
        wireEnvelope: '{"v":2}',
        relayExpiresAt: 1999999999000,
      );
      expect(parent.media, isEmpty);

      final evidence = verifyAndroidDirectMediaBlobCustodySenderBinding(
        request: request,
        senderPeerId: 'sender-peer',
        beforeSend: before,
        authoritativeParent: parent,
        afterSendRows: <DirectMediaBlobCustodyRow>[after],
        retainedV108Owner: false,
      );
      expect(evidence?.ciphertextSha256, _sha);
      expect(evidence?.blobExpiresAtMs, 2000000000000);
      expect(evidence?.envelopeExpiresAtMs, 1999999999000);

      for (final mutation
          in <AndroidDirectMediaBlobCustodySenderBindingEvidence? Function()>[
            () => verifyAndroidDirectMediaBlobCustodySenderBinding(
              request: request,
              senderPeerId: 'sender-peer',
              beforeSend: before,
              authoritativeParent: parent,
              afterSendRows: <DirectMediaBlobCustodyRow>[after],
              retainedV108Owner: true,
            ),
            () => verifyAndroidDirectMediaBlobCustodySenderBinding(
              request: request,
              senderPeerId: 'sender-peer',
              beforeSend: before,
              authoritativeParent: parent,
              afterSendRows: <DirectMediaBlobCustodyRow>[
                after.copyWith(inboxCustodyIncarnationId: null),
              ],
              retainedV108Owner: false,
            ),
            () => verifyAndroidDirectMediaBlobCustodySenderBinding(
              request: request,
              senderPeerId: 'sender-peer',
              beforeSend: before,
              authoritativeParent: parent,
              afterSendRows: <DirectMediaBlobCustodyRow>[
                after.copyWith(
                  state: DirectMediaBlobCustodyState.outgoingStored,
                ),
              ],
              retainedV108Owner: false,
            ),
            () => verifyAndroidDirectMediaBlobCustodySenderBinding(
              request: request,
              senderPeerId: 'sender-peer',
              beforeSend: before,
              authoritativeParent: parent,
              afterSendRows: <DirectMediaBlobCustodyRow>[
                _senderRow(
                  state: DirectMediaBlobCustodyState.outgoingCleanupPending,
                  inboxCustodyIncarnationId: '0123456789abcdef0123456789abcdef',
                  contentHash:
                      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
                ),
              ],
              retainedV108Owner: false,
            ),
            () => verifyAndroidDirectMediaBlobCustodySenderBinding(
              request: request,
              senderPeerId: 'sender-peer',
              beforeSend: before,
              authoritativeParent: parent.copyWith(
                relayExpiresAt: 2000000000001,
              ),
              afterSendRows: <DirectMediaBlobCustodyRow>[after],
              retainedV108Owner: false,
            ),
          ]) {
        expect(mutation(), isNull);
      }
    },
  );

  test(
    'TC-347-09 receiver action accepts its strict owner or bootstrap completion',
    () {
      final request = AndroidDirectMediaBlobCustodyE2ERequest.fromConfig(
        _request(
          role: androidDirectMediaBlobCustodyReceiverRole,
          phase: androidDirectMediaBlobCustodyReceiverArmPhase,
        ),
      );
      final parent = _receiverParent();
      final row = _receiverRow();
      final pending = _receiverAttachment(row: row);

      final direct = verifyAndroidDirectMediaBlobCustodyReceiverAuthority(
        request: request,
        authoritativeParent: parent,
        attachments: <MediaAttachment>[pending],
        custodyRow: row,
        nowMs: 1900000000000,
      );
      expect(
        direct?.authority,
        AndroidDirectMediaBlobCustodyReceiverAuthority.directOwner,
      );
      expect(direct?.requiresDirectOwner, isTrue);
      expect(direct?.strictLifecycleCompletionObserved, isFalse);
      expect(direct?.commitment?.contentHash, _sha);

      final completed = _completedReceiverAttachment(pending);
      final bootstrap = verifyAndroidDirectMediaBlobCustodyReceiverAuthority(
        request: request,
        authoritativeParent: parent,
        attachments: <MediaAttachment>[completed],
        custodyRow: null,
        nowMs: 1900000000000,
      );
      expect(
        bootstrap?.authority,
        AndroidDirectMediaBlobCustodyReceiverAuthority.durableStrictCompletion,
      );
      expect(bootstrap?.requiresDirectOwner, isFalse);
      expect(bootstrap?.strictLifecycleCompletionObserved, isTrue);
      expect(bootstrap?.ciphertextSha256, _sha);
      expect(bootstrap?.commitment, isNull);
    },
  );

  test(
    'TC-347-09 receiver action adopts exact durable source-pinned ACK retry',
    () {
      final request = AndroidDirectMediaBlobCustodyE2ERequest.fromConfig(
        _request(
          role: androidDirectMediaBlobCustodyReceiverRole,
          phase: androidDirectMediaBlobCustodyReceiverArmPhase,
        ),
      );
      final row = _receiverRow(
        state: DirectMediaBlobCustodyState.incomingAckPending,
        custodyRelayPeerId: 'relay-peer',
      );
      final attachment = _completedReceiverAttachment(
        _receiverAttachment(row: row),
      );

      final evidence = verifyAndroidDirectMediaBlobCustodyReceiverAuthority(
        request: request,
        authoritativeParent: _receiverParent(),
        attachments: <MediaAttachment>[attachment],
        custodyRow: row,
        nowMs: 1900000000000,
      );

      expect(
        evidence?.authority,
        AndroidDirectMediaBlobCustodyReceiverAuthority.pendingAckOwner,
      );
      expect(evidence?.requiresDirectOwner, isTrue);
      expect(evidence?.strictLifecycleCompletionObserved, isFalse);
      expect(evidence?.commitment?.contentHash, _sha);
    },
  );

  test(
    'TC-347-09 receiver completion rejects absent and crossed durable authority',
    () {
      final request = AndroidDirectMediaBlobCustodyE2ERequest.fromConfig(
        _request(
          role: androidDirectMediaBlobCustodyReceiverRole,
          phase: androidDirectMediaBlobCustodyReceiverArmPhase,
        ),
      );
      final parent = _receiverParent();
      final row = _receiverRow();
      final pending = _receiverAttachment(row: row);
      final completed = _completedReceiverAttachment(pending);
      final ackPending = _receiverRow(
        state: DirectMediaBlobCustodyState.incomingAckPending,
        custodyRelayPeerId: 'relay-peer',
      );

      for (final mutation
          in <AndroidDirectMediaBlobCustodyReceiverEvidence? Function()>[
            () => verifyAndroidDirectMediaBlobCustodyReceiverAuthority(
              request: request,
              authoritativeParent: null,
              attachments: <MediaAttachment>[completed],
              custodyRow: null,
              nowMs: 1900000000000,
            ),
            () => verifyAndroidDirectMediaBlobCustodyReceiverAuthority(
              request: request,
              authoritativeParent: parent.copyWith(
                senderPeerId: 'crossed-peer',
              ),
              attachments: <MediaAttachment>[completed],
              custodyRow: null,
              nowMs: 1900000000000,
            ),
            () => verifyAndroidDirectMediaBlobCustodyReceiverAuthority(
              request: request,
              authoritativeParent: parent,
              attachments: const <MediaAttachment>[],
              custodyRow: null,
              nowMs: 1900000000000,
            ),
            () => verifyAndroidDirectMediaBlobCustodyReceiverAuthority(
              request: request,
              authoritativeParent: parent,
              attachments: <MediaAttachment>[
                completed.copyWith(
                  clearDirectMediaBlobCustodyFingerprint: true,
                ),
              ],
              custodyRow: null,
              nowMs: 1900000000000,
            ),
            () => verifyAndroidDirectMediaBlobCustodyReceiverAuthority(
              request: request,
              authoritativeParent: parent,
              attachments: <MediaAttachment>[pending],
              custodyRow: null,
              nowMs: 1900000000000,
            ),
            () => verifyAndroidDirectMediaBlobCustodyReceiverAuthority(
              request: request,
              authoritativeParent: parent,
              attachments: <MediaAttachment>[pending],
              custodyRow: _receiverRow(contentHash: _crossedSha),
              nowMs: 1900000000000,
            ),
            () => verifyAndroidDirectMediaBlobCustodyReceiverAuthority(
              request: request,
              authoritativeParent: parent,
              attachments: <MediaAttachment>[completed],
              custodyRow: ackPending,
              nowMs: 2000000000000,
            ),
          ]) {
        expect(mutation(), isNull);
      }
    },
  );

  test('TC-347-09 receiver failures expose bounded codes only', () {
    final receipt = androidDirectMediaBlobCustodyE2EFailureReceipt(
      config: _request(
        role: androidDirectMediaBlobCustodyReceiverRole,
        phase: androidDirectMediaBlobCustodyReceiverArmPhase,
      ),
      error: StateError(
        'receiver did not persist the complete strict authority',
      ),
    );

    expect(
      receipt,
      containsPair('errorCode', 'receiver_authority_not_observed'),
    );
    expect(receipt.containsKey('error'), isFalse);
  });
}

DirectMediaBlobCustodyRow _senderRow({
  required DirectMediaBlobCustodyState state,
  String? inboxCustodyIncarnationId,
  String contentHash = _sha,
}) => DirectMediaBlobCustodyRow(
  attachmentId: 'attachment-1',
  messageId: 'message-1',
  direction: DirectMediaBlobCustodyDirection.outgoing,
  state: state,
  inboxCustodyIncarnationId: inboxCustodyIncarnationId,
  recipientPeerId: 'peer-1',
  ciphertextRelativePath:
      'direct_media_blob_custody_v1/sender-peer/attachment-1.bin',
  contentHash: contentHash,
  ciphertextSize: 36108,
  expiresAtMs: 2000000000000,
  custodyRelayPeerId: 'relay-peer',
  lastAttemptAt: null,
  nextAttemptAt: null,
  createdAt: '2026-08-08T12:00:00.000Z',
  updatedAt: '2026-08-08T12:00:00.000Z',
);

ConversationMessage _receiverParent() => ConversationMessage(
  id: 'message-1',
  contactPeerId: 'peer-1',
  senderPeerId: 'peer-1',
  text: '',
  timestamp: '2026-08-08T12:00:00.000Z',
  status: 'delivered',
  isIncoming: true,
  createdAt: '2026-08-08T12:00:00.000Z',
  transport: 'inbox',
);

DirectMediaBlobCustodyRow _receiverRow({
  DirectMediaBlobCustodyState state =
      DirectMediaBlobCustodyState.incomingCommitted,
  String contentHash = _sha,
  String? custodyRelayPeerId,
}) => DirectMediaBlobCustodyRow(
  attachmentId: 'attachment-1',
  messageId: 'message-1',
  direction: DirectMediaBlobCustodyDirection.incoming,
  state: state,
  inboxCustodyIncarnationId: null,
  recipientPeerId: null,
  ciphertextRelativePath: null,
  contentHash: contentHash,
  ciphertextSize: 36108,
  expiresAtMs: 2000000000000,
  custodyRelayPeerId: custodyRelayPeerId,
  lastAttemptAt: null,
  nextAttemptAt: null,
  createdAt: '2026-08-08T12:00:00.000Z',
  updatedAt: '2026-08-08T12:00:00.000Z',
);

MediaAttachment _receiverAttachment({required DirectMediaBlobCustodyRow row}) {
  final commitment = DirectMediaBlobCustodyCommitment(
    contentHash: row.contentHash,
    ciphertextSize: row.ciphertextSize,
    expiresAtMs: row.expiresAtMs!,
  );
  return MediaAttachment(
    id: 'attachment-1',
    messageId: 'message-1',
    mime: 'audio/mp4',
    size: 32000,
    mediaType: 'audio',
    durationMs: 2000,
    downloadStatus: 'pending',
    createdAt: '2026-08-08T12:00:00.000Z',
    downloadRetryCount: 0,
    contentHash: row.contentHash,
    encryptionKeyBase64: 'a2V5',
    encryptionNonce: 'bm9uY2U=',
    encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
    directMediaBlobCustodyFingerprint:
        computeDirectMediaBlobCommitmentFingerprint(
          attachmentId: 'attachment-1',
          commitment: commitment,
        ),
    ownerLane: MediaOwnerLane.direct,
  );
}

MediaAttachment _completedReceiverAttachment(MediaAttachment attachment) =>
    attachment.copyWith(
      localPath: 'media/peer-1/attachment-1.m4a',
      downloadStatus: 'done',
      downloadRetryCount: 0,
    );

Map<String, dynamic> _request({
  required String role,
  required String phase,
  String? expectedHash,
}) => <String, dynamic>{
  'schema': androidDirectMediaBlobCustodyE2ERequestSchema,
  'transport_action': androidDirectMediaBlobCustodyE2EAction,
  'scenario': androidDirectMediaBlobCustodyE2EScenario,
  'buildProfile': androidDirectMediaBlobCustodyE2EBuildProfile,
  'role': role,
  'phase': phase,
  'stepId': androidDirectMediaBlobCustodyStepId(
    role: role,
    phase: phase,
    runId: 'run-1',
  ),
  'runId': 'run-1',
  'nonce': 'nonce-1',
  'contactPeerId': 'peer-1',
  'messageId': 'message-1',
  'attachmentId': 'attachment-1',
  'fixtureIdentitySha256': _sha,
  'expectedCiphertextSha256': ?expectedHash,
  'timeoutMs': 60000,
};
