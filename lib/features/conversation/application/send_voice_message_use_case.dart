import 'dart:io';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';

enum SendVoiceMessageResult {
  success,
  invalidRecording,
  uploadFailed,
  sendFailed,
}

const _maxFileSizeBytes = 100 * 1024 * 1024; // 100 MB

/// Orchestrates sending a voice message:
/// 1. Validate recording
/// 2. Upload via bridge
/// 3. Send via sendChatMessage with audio MediaAttachment
///
/// Returns (result, message) — message is non-null on success.
Future<(SendVoiceMessageResult, ConversationMessage?)> sendVoiceMessage({
  required P2PService p2pService,
  required MessageRepository messageRepo,
  required String targetPeerId,
  required String senderPeerId,
  required String senderUsername,
  required AudioRecording recording,
  required Bridge bridge,
  String? recipientMlKemPublicKey,
  MediaAttachmentRepository? mediaAttachmentRepo,
  MediaFileManager? mediaFileManager,
  String? text,
  String? quotedMessageId,
  List<double>? waveform,
  String? messageId,
  String? timestamp,
  String? blobId,
  // 112 Phase 4 "encrypt once": the composer's LAN leg already streamed
  // this artifact; the relay upload must reuse the same key/ciphertext.
  EncryptedMediaArtifact? preparedArtifact,
}) async {
  final sendStopwatch = Stopwatch()..start();
  void emitVoiceTiming({
    required String outcome,
    Map<String, dynamic> details = const {},
  }) {
    emitFlowEvent(
      layer: 'FL',
      event: 'VOICE_SEND_TIMING',
      details: {
        'elapsedMs': sendStopwatch.elapsedMilliseconds,
        'outcome': outcome,
        'durationMs': recording.durationMs,
        'sizeBytes': recording.sizeBytes,
        ...details,
      },
    );
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'VOICE_SEND_START',
    details: {
      'durationMs': recording.durationMs,
      'sizeBytes': recording.sizeBytes,
    },
  );

  // 1. Validate
  if (recording.sizeBytes <= 0 || recording.sizeBytes > _maxFileSizeBytes) {
    emitFlowEvent(
      layer: 'FL',
      event: 'VOICE_SEND_INVALID',
      details: {'sizeBytes': recording.sizeBytes},
    );
    emitVoiceTiming(outcome: 'invalid_recording');
    return (SendVoiceMessageResult.invalidRecording, null);
  }

  final file = File(recording.filePath);
  if (!file.existsSync()) {
    emitFlowEvent(
      layer: 'FL',
      event: 'VOICE_SEND_FILE_NOT_FOUND',
      details: {'filePath': recording.filePath},
    );
    emitVoiceTiming(outcome: 'file_not_found');
    return (SendVoiceMessageResult.invalidRecording, null);
  }

  if (recipientMlKemPublicKey == null ||
      recipientMlKemPublicKey.trim().isEmpty) {
    emitFlowEvent(
      layer: 'FL',
      event: 'VOICE_SEND_ENCRYPTION_REQUIRED',
      details: {},
    );
    emitVoiceTiming(outcome: 'encryption_required');
    return (SendVoiceMessageResult.sendFailed, null);
  }

  // 2. Upload
  emitFlowEvent(layer: 'FL', event: 'VOICE_UPLOAD_START', details: {});

  final uploadStopwatch = Stopwatch()..start();
  final uploaded = await uploadMedia(
    bridge: bridge,
    localFilePath: recording.filePath,
    mime: recording.mime,
    recipientPeerId: targetPeerId,
    mediaFileManager: mediaFileManager,
    durationMs: recording.durationMs,
    waveform: waveform,
    blobId: blobId,
    // The recorder temp is plaintext residue once the durable copy is the
    // render source. Safe: the voice LAN send is awaited BEFORE this
    // use case runs (conversation_wired voice flow).
    deleteSourceWhenDone: true,
    preparedArtifact: preparedArtifact,
  );
  uploadStopwatch.stop();
  final uploadMs = uploadStopwatch.elapsedMilliseconds;

  if (uploaded == null) {
    // 117 Session 4 (finding #3c): the relay upload failed (e.g. a LAN-only
    // delivery or transient relay outage), but the sender's OWN voice note
    // must remain playable. uploadMedia only makes its durable owned copy on
    // upload success, so on failure the optimistic row still points at the
    // recorder temp — which the OS can evict, flipping the message to
    // pending→failed→"Media unavailable" and triggering a relay download for
    // a blob that was never uploaded. Persist a durable owned copy + a 'done'
    // attachment row here so display resolution finds it locally. (Delivery
    // truthfulness — the message status — is a separate concern handled by the
    // caller.)
    await _persistDurableVoiceCopyOnUploadFailure(
      recording: recording,
      targetPeerId: targetPeerId,
      blobId: blobId,
      messageId: messageId,
      waveform: waveform,
      mediaFileManager: mediaFileManager,
      mediaAttachmentRepo: mediaAttachmentRepo,
    );
    emitFlowEvent(layer: 'FL', event: 'VOICE_UPLOAD_FAILED', details: {});
    emitVoiceTiming(outcome: 'upload_failed', details: {'uploadMs': uploadMs});
    return (SendVoiceMessageResult.uploadFailed, null);
  }

  emitFlowEvent(layer: 'FL', event: 'VOICE_UPLOAD_DONE', details: {});

  // 3. Send via existing sendChatMessage with the uploaded attachment
  final voiceSendStopwatch = Stopwatch()..start();
  final (result, message) = await sendChatMessage(
    p2pService: p2pService,
    messageRepo: messageRepo,
    targetPeerId: targetPeerId,
    text: text ?? '',
    senderPeerId: senderPeerId,
    senderUsername: senderUsername,
    bridge: bridge,
    recipientMlKemPublicKey: recipientMlKemPublicKey,
    quotedMessageId: quotedMessageId,
    mediaAttachments: [uploaded],
    mediaAttachmentRepo: mediaAttachmentRepo,
    messageId: messageId,
    timestamp: timestamp,
    emitTimingEvent: false,
  );

  voiceSendStopwatch.stop();
  final voiceSendMs = voiceSendStopwatch.elapsedMilliseconds;

  if (result == SendChatMessageResult.success) {
    emitFlowEvent(layer: 'FL', event: 'VOICE_SEND_SUCCESS', details: {});
    emitVoiceTiming(
      outcome: 'success',
      details: {'uploadMs': uploadMs, 'sendMs': voiceSendMs},
    );
    return (SendVoiceMessageResult.success, message);
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'VOICE_SEND_FAILED',
    details: {'result': result.name},
  );
  emitVoiceTiming(
    outcome: 'send_failed',
    details: {
      'result': result.name,
      'uploadMs': uploadMs,
      'sendMs': voiceSendMs,
    },
  );
  return (SendVoiceMessageResult.sendFailed, null);
}

/// 117 Session 4: copies the recorder temp into the durable owned media dir
/// (`media/<peer>/<blobId>.<ext>`) and persists a `done` attachment row so the
/// sender's voice note survives a failed relay upload + OS temp eviction.
///
/// Best-effort: requires [blobId] + a [mediaFileManager] + a
/// [mediaAttachmentRepo]; otherwise it degrades to the prior behavior. Never
/// throws into the send path — failures are logged and swallowed.
Future<void> _persistDurableVoiceCopyOnUploadFailure({
  required AudioRecording recording,
  required String targetPeerId,
  String? blobId,
  String? messageId,
  List<double>? waveform,
  MediaFileManager? mediaFileManager,
  MediaAttachmentRepository? mediaAttachmentRepo,
}) async {
  if (blobId == null ||
      mediaFileManager == null ||
      mediaAttachmentRepo == null) {
    return;
  }
  try {
    final source = File(recording.filePath);
    if (!source.existsSync()) return;

    // Copy into the canonical owned media path (the same path uploadMedia
    // would use on success, keyed on the stable blobId).
    final durableAbsolute = await mediaFileManager.localPathForAttachment(
      contactPeerId: targetPeerId,
      blobId: blobId,
      mime: recording.mime,
    );
    if (durableAbsolute != recording.filePath) {
      await source.copy(durableAbsolute);
    }

    // Persist as 'upload_pending' — NOT 'done'. 'done' is the
    // relay-blob-exists signal that retryIncompleteUploads keys on
    // (_resolveAttachmentsForRetry reuses 'done' attachments instead of
    // re-uploading); since the relay upload just FAILED, marking 'done' would
    // make a retry reference a blob that was never uploaded → permanent
    // "Media unavailable" on the recipient. 'upload_pending' keeps the row
    // re-uploadable while the durable local copy (absolute path, so the
    // retry's File(localPath).existsSync() check resolves it, and survives OS
    // temp eviction) keeps the sender's own message off the
    // done→pending→download→unavailable path (upload_pending is never flipped
    // by _resolveAttachmentForDisplay nor recovered by _recoverVisibleMedia).
    await mediaAttachmentRepo.saveAttachment(
      MediaAttachment(
        id: blobId,
        messageId: messageId ?? '',
        mime: recording.mime,
        size: recording.sizeBytes,
        mediaType: 'audio',
        durationMs: recording.durationMs,
        localPath: durableAbsolute,
        downloadStatus: 'upload_pending',
        createdAt: DateTime.now().toUtc().toIso8601String(),
        waveform: waveform,
      ),
    );

    emitFlowEvent(
      layer: 'FL',
      event: 'VOICE_DURABLE_COPY_ON_UPLOAD_FAILURE',
      details: {'blobId': blobId, 'storedPath': durableAbsolute},
    );
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'VOICE_DURABLE_COPY_FAILED',
      details: {'error': e.toString()},
    );
  }
}
