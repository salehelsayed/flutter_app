import 'dart:io';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/send_chat_message_use_case.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
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

  // 2. Upload
  emitFlowEvent(layer: 'FL', event: 'VOICE_UPLOAD_START', details: {});

  final uploaded = await uploadMedia(
    bridge: bridge,
    localFilePath: recording.filePath,
    mime: recording.mime,
    recipientPeerId: targetPeerId,
    mediaFileManager: mediaFileManager,
    durationMs: recording.durationMs,
    waveform: waveform,
    blobId: blobId,
  );

  if (uploaded == null) {
    emitFlowEvent(layer: 'FL', event: 'VOICE_UPLOAD_FAILED', details: {});
    emitVoiceTiming(outcome: 'upload_failed');
    return (SendVoiceMessageResult.uploadFailed, null);
  }

  emitFlowEvent(layer: 'FL', event: 'VOICE_UPLOAD_DONE', details: {});

  // 3. Send via existing sendChatMessage with the uploaded attachment
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

  if (result == SendChatMessageResult.success) {
    emitFlowEvent(layer: 'FL', event: 'VOICE_SEND_SUCCESS', details: {});
    emitVoiceTiming(outcome: 'success');
    return (SendVoiceMessageResult.success, message);
  }

  emitFlowEvent(
    layer: 'FL',
    event: 'VOICE_SEND_FAILED',
    details: {'result': result.name},
  );
  emitVoiceTiming(outcome: 'send_failed', details: {'result': result.name});
  return (SendVoiceMessageResult.sendFailed, null);
}
