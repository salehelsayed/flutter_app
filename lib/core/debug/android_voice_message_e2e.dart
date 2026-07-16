import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/conversation/application/download_media_use_case.dart';
import 'package:flutter_app/features/conversation/application/send_voice_message_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:just_audio/just_audio.dart';

import 'android_voice_message_e2e_protocol.dart';

export 'android_voice_message_e2e_protocol.dart';

const String _installedSimsBuildProfile = String.fromEnvironment(
  'SIMS_BUILD_PROFILE_ID',
);

typedef AndroidVoiceMessageProgressWriter =
    Future<void> Function(Map<String, Object?> progress);

Map<String, Object?> androidVoiceMessageE2EFailureReceipt({
  required Map<String, dynamic> config,
  required Object error,
}) {
  final request = AndroidVoiceMessageE2ERequest.fromConfig(config);
  return <String, Object?>{
    'schema': androidVoiceMessageE2EEndpointResultSchema,
    'status': 'failed',
    'success': false,
    'scenario': androidVoiceMessageE2EScenario,
    'buildProfile': androidVoiceMessageE2EBuildProfile,
    'role': request.role,
    'stepId': 'voice-${request.role}-${request.runId}',
    'runId': request.runId,
    'nonce': request.nonce,
    'errorType': error.runtimeType.toString(),
  };
}

/// A strict, nonce-bound request for one endpoint of the two-Android voice
/// campaign. Message and attachment IDs are minted once by the host and shared
/// with both endpoints, so an unrelated voice note can never satisfy the run.
final class AndroidVoiceMessageE2ERequest {
  const AndroidVoiceMessageE2ERequest({
    required this.role,
    required this.runId,
    required this.nonce,
    required this.contactPeerId,
    required this.messageId,
    required this.attachmentId,
    required this.timeout,
  });

  factory AndroidVoiceMessageE2ERequest.fromConfig(
    Map<String, dynamic> config,
  ) {
    if (config['schema'] != androidVoiceMessageE2ERequestSchema ||
        config['transport_action'] != androidVoiceMessageE2EAction ||
        config['scenario'] != androidVoiceMessageE2EScenario) {
      throw const FormatException('voice-message request boundary rejected');
    }
    final role = _requiredToken(config, 'role', maxLength: 16);
    if (role != androidVoiceMessageSenderRole &&
        role != androidVoiceMessageReceiverRole) {
      throw const FormatException('voice-message role rejected');
    }
    final runId = _requiredToken(config, 'runId', maxLength: 80);
    if (config['stepId'] != 'voice-$role-$runId') {
      throw const FormatException('voice-message step binding rejected');
    }
    final timeoutMs = ((config['timeoutMs'] as num?)?.toInt() ?? 120000)
        .clamp(30000, 180000)
        .toInt();
    return AndroidVoiceMessageE2ERequest(
      role: role,
      runId: runId,
      nonce: _requiredToken(config, 'nonce', maxLength: 128),
      contactPeerId: _requiredToken(config, 'contactPeerId', maxLength: 160),
      messageId: _requiredToken(config, 'messageId', maxLength: 160),
      attachmentId: _requiredToken(config, 'attachmentId', maxLength: 160),
      timeout: Duration(milliseconds: timeoutMs),
    );
  }

  final String role;
  final String runId;
  final String nonce;
  final String contactPeerId;
  final String messageId;
  final String attachmentId;
  final Duration timeout;

  bool get isSender => role == androidVoiceMessageSenderRole;
}

/// Runs one side of the real Android voice-message journey inside the normal
/// production app graph. The physical sender uses [audioRecorderService] and
/// the production voice use case. The emulator receiver observes the exact
/// persisted message/attachment, uses the production downloader, then decodes
/// and plays those same bytes through just_audio.
///
/// The caller owns file-based request/result transport. In particular, the
/// receiver's [writeProgress] callback must durably publish the `armed` result
/// before the host starts the sender.
Future<Map<String, Object?>> runAndroidVoiceMessageE2EAction({
  required Map<String, dynamic> config,
  required P2PService p2pService,
  required Bridge bridge,
  required IdentityRepository identityRepo,
  required ContactRepository contactRepo,
  required MessageRepository messageRepo,
  required MediaAttachmentRepository mediaAttachmentRepo,
  required MediaFileManager mediaFileManager,
  required AudioRecorderService audioRecorderService,
  required AndroidVoiceMessageProgressWriter writeProgress,
  Duration recordingDuration = const Duration(seconds: 2),
  bool? isAndroidOverride,
  String? installedProfileOverride,
}) async {
  final request = AndroidVoiceMessageE2ERequest.fromConfig(config);
  if ((installedProfileOverride ?? _installedSimsBuildProfile) !=
      androidVoiceMessageE2EBuildProfile) {
    throw StateError('voice-message E2E requires the attested main-app APK');
  }
  if (!(isAndroidOverride ?? Platform.isAndroid)) {
    throw StateError('voice-message E2E endpoint requires Android');
  }
  await _waitForProductionTransport(p2pService, request.timeout);
  if (request.isSender) {
    return _runSender(
      request: request,
      p2pService: p2pService,
      bridge: bridge,
      identityRepo: identityRepo,
      contactRepo: contactRepo,
      messageRepo: messageRepo,
      mediaAttachmentRepo: mediaAttachmentRepo,
      mediaFileManager: mediaFileManager,
      audioRecorderService: audioRecorderService,
      recordingDuration: recordingDuration,
    );
  }
  return _runReceiver(
    request: request,
    p2pService: p2pService,
    bridge: bridge,
    identityRepo: identityRepo,
    messageRepo: messageRepo,
    mediaAttachmentRepo: mediaAttachmentRepo,
    mediaFileManager: mediaFileManager,
    writeProgress: writeProgress,
  );
}

Future<Map<String, Object?>> _runSender({
  required AndroidVoiceMessageE2ERequest request,
  required P2PService p2pService,
  required Bridge bridge,
  required IdentityRepository identityRepo,
  required ContactRepository contactRepo,
  required MessageRepository messageRepo,
  required MediaAttachmentRepository mediaAttachmentRepo,
  required MediaFileManager mediaFileManager,
  required AudioRecorderService audioRecorderService,
  required Duration recordingDuration,
}) async {
  final identity = await identityRepo.loadIdentity();
  final contact = await contactRepo.getContact(request.contactPeerId);
  if (identity == null ||
      contact == null ||
      contact.mlKemPublicKey == null ||
      contact.mlKemPublicKey!.trim().isEmpty) {
    throw StateError('voice-message sender identity/contact is not ready');
  }
  if (!await audioRecorderService.hasPermission()) {
    throw StateError('RECORD_AUDIO was not pregranted');
  }

  File? recordingFile;
  var recorderDisposed = false;
  try {
    await audioRecorderService.start(outputPath: '');
    await Future<void>.delayed(recordingDuration);
    final recording = await audioRecorderService.stop();
    if (recording == null ||
        recording.durationMs < 1500 ||
        recording.sizeBytes <= 0 ||
        recording.mime != 'audio/mp4') {
      throw StateError('production recorder returned an invalid voice note');
    }
    recordingFile = File(recording.filePath);
    final recordingBytes = await _readM4a(recordingFile);
    if (recordingBytes.length != recording.sizeBytes) {
      throw StateError('recording size disagrees with the native file');
    }
    final recordingSha256 = sha256.convert(recordingBytes).toString();

    final (sendResult, sentMessage) = await sendVoiceMessage(
      p2pService: p2pService,
      messageRepo: messageRepo,
      targetPeerId: contact.peerId,
      senderPeerId: identity.peerId,
      senderUsername: identity.username,
      recording: recording,
      bridge: bridge,
      recipientMlKemPublicKey: contact.mlKemPublicKey,
      mediaAttachmentRepo: mediaAttachmentRepo,
      mediaFileManager: mediaFileManager,
      messageId: request.messageId,
      blobId: request.attachmentId,
    );
    if (sendResult != SendVoiceMessageResult.success || sentMessage == null) {
      throw StateError('production voice send did not succeed');
    }
    _requireExactSentMessage(sentMessage, request);
    if (await recordingFile.exists()) {
      throw StateError('transient recorder file survived durable voice upload');
    }

    return <String, Object?>{
      'schema': androidVoiceMessageE2EEndpointResultSchema,
      'status': 'complete',
      'success': true,
      'scenario': androidVoiceMessageE2EScenario,
      'buildProfile': androidVoiceMessageE2EBuildProfile,
      'role': request.role,
      'stepId': 'voice-${request.role}-${request.runId}',
      'runId': request.runId,
      'nonce': request.nonce,
      'sender': <String, Object?>{
        'permissionPregranted': true,
        'realRecordPlugin': true,
        'mime': recording.mime,
        'recordedSizeBytes': recording.sizeBytes,
        'recordedDurationMs': recording.durationMs,
        'recordedPlaintextSha256': recordingSha256,
        'productionSendVoiceMessage': true,
        'productionGoBridge': true,
        'sendResult': 'success',
        'messageId': sentMessage.id,
        'attachmentId': request.attachmentId,
        'receiverPeerIdSha256': _tokenSha256(contact.peerId),
        'messageStatus': sentMessage.status,
        'messageTransport': sentMessage.transport,
        'temporaryRecordingDeleted': true,
      },
      'transport': <String, Object?>{
        'realRelayMediaUpload': true,
        'senderCustodyAccepted': true,
        'usedFakeNetwork': false,
        'usedHostFileTransfer': false,
      },
    };
  } finally {
    if (audioRecorderService.isRecording) {
      await audioRecorderService.cancel();
    }
    await audioRecorderService.dispose();
    recorderDisposed = true;
    if (recordingFile != null && await recordingFile.exists()) {
      await recordingFile.delete();
    }
    assert(recorderDisposed);
  }
}

/// Coordinates the receiver endpoint with the app's ordinary automatic media
/// downloader. A newly persisted attachment can be claimed by that path at the
/// same instant this explicit E2E action observes it. A null result from one
/// download call is therefore not terminal: reload the exact row and either
/// observe its durable completion or retry the production download with the
/// current persisted state.
///
/// Success still requires the exact nonce-bound attachment row to be marked
/// `done` and its resolved file to exist. This helper never supplies bytes and
/// cannot turn a failed relay download into proof.
Future<({MediaAttachment attachment, String localPath})>
waitForAndroidVoiceMessageDownloadForE2E({
  required String messageId,
  required String attachmentId,
  required Future<List<MediaAttachment>> Function() loadAttachments,
  required Future<MediaAttachment?> Function(MediaAttachment attachment)
  downloadAttachment,
  required Future<String> Function(String storedPath) resolveStoredPath,
  required Future<bool> Function(String absolutePath) fileExists,
  Future<void> Function()? onWaitCycle,
  Duration timeout = const Duration(seconds: 30),
  Duration pollInterval = const Duration(milliseconds: 250),
}) async {
  if (timeout <= Duration.zero) {
    throw ArgumentError.value(timeout, 'timeout', 'must be positive');
  }
  if (pollInterval.isNegative) {
    throw ArgumentError.value(
      pollInterval,
      'pollInterval',
      'must not be negative',
    );
  }

  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final attachments = await loadAttachments();
    final exact = attachments
        .where((candidate) => candidate.id == attachmentId)
        .toList(growable: false);
    if (exact.length > 1) {
      throw StateError('duplicate exact receiver attachment observed');
    }
    if (exact.length == 1) {
      final current = exact.single;
      _requireExactReceiverVoiceAttachment(
        current,
        messageId: messageId,
        attachmentId: attachmentId,
      );
      final currentPath = await _resolveCompletedVoiceAttachment(
        current,
        resolveStoredPath: resolveStoredPath,
        fileExists: fileExists,
      );
      if (currentPath != null) {
        return (attachment: current, localPath: currentPath);
      }

      final downloaded = await downloadAttachment(current);
      if (downloaded != null) {
        _requireExactReceiverVoiceAttachment(
          downloaded,
          messageId: messageId,
          attachmentId: attachmentId,
        );
        final downloadedPath = await _resolveCompletedVoiceAttachment(
          downloaded,
          resolveStoredPath: resolveStoredPath,
          fileExists: fileExists,
        );
        if (downloadedPath != null) {
          return (attachment: downloaded, localPath: downloadedPath);
        }
      }
    }

    await onWaitCycle?.call();
    final remaining = deadline.difference(DateTime.now());
    if (remaining <= Duration.zero) break;
    final delay = pollInterval < remaining ? pollInterval : remaining;
    await Future<void>.delayed(delay);
  }
  throw StateError('production receiver media download timed out');
}

Future<String?> _resolveCompletedVoiceAttachment(
  MediaAttachment attachment, {
  required Future<String> Function(String storedPath) resolveStoredPath,
  required Future<bool> Function(String absolutePath) fileExists,
}) async {
  final storedPath = attachment.localPath;
  if (attachment.downloadStatus != 'done' ||
      storedPath == null ||
      storedPath.isEmpty) {
    return null;
  }
  final absolutePath = await resolveStoredPath(storedPath);
  return await fileExists(absolutePath) ? absolutePath : null;
}

void _requireExactReceiverVoiceAttachment(
  MediaAttachment attachment, {
  required String messageId,
  required String attachmentId,
}) {
  if (attachment.id != attachmentId ||
      attachment.messageId != messageId ||
      attachment.mime != 'audio/mp4' ||
      attachment.mediaType != 'audio' ||
      attachment.size <= 0 ||
      (attachment.durationMs ?? 0) < 1500) {
    throw StateError('receiver attachment is not the exact sent voice media');
  }
}

Future<Map<String, Object?>> _runReceiver({
  required AndroidVoiceMessageE2ERequest request,
  required P2PService p2pService,
  required Bridge bridge,
  required IdentityRepository identityRepo,
  required MessageRepository messageRepo,
  required MediaAttachmentRepository mediaAttachmentRepo,
  required MediaFileManager mediaFileManager,
  required AndroidVoiceMessageProgressWriter writeProgress,
}) async {
  final identity = await identityRepo.loadIdentity();
  if (identity == null) {
    throw StateError('voice-message receiver identity is not ready');
  }
  await writeProgress(<String, Object?>{
    'schema': androidVoiceMessageE2EEndpointResultSchema,
    'status': 'armed',
    'success': true,
    'scenario': androidVoiceMessageE2EScenario,
    'buildProfile': androidVoiceMessageE2EBuildProfile,
    'role': request.role,
    'stepId': 'voice-${request.role}-${request.runId}',
    'runId': request.runId,
    'nonce': request.nonce,
    'messageId': request.messageId,
    'attachmentId': request.attachmentId,
  });

  final deadline = DateTime.now().add(request.timeout);
  ConversationMessage? message;
  MediaAttachment? attachment;
  while (DateTime.now().isBefore(deadline)) {
    await p2pService.drainOfflineInbox();
    final candidate = await messageRepo.getMessage(request.messageId);
    if (candidate != null &&
        candidate.isIncoming &&
        candidate.contactPeerId == request.contactPeerId &&
        !candidate.isDeleted &&
        !candidate.isHidden) {
      final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
        candidate.id,
        owner: MediaOwnerLane.direct,
      );
      final exact = attachments
          .where((item) => item.id == request.attachmentId)
          .toList(growable: false);
      if (exact.length > 1) {
        throw StateError('duplicate exact receiver attachment observed');
      }
      if (exact.length == 1) {
        message = candidate;
        attachment = exact.single;
        break;
      }
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  if (message == null || attachment == null) {
    throw StateError('exact incoming voice message/attachment timed out');
  }
  _requireExactReceiverVoiceAttachment(
    attachment,
    messageId: request.messageId,
    attachmentId: request.attachmentId,
  );

  final remaining = deadline.difference(DateTime.now());
  if (remaining <= Duration.zero) {
    throw StateError('production receiver media download window expired');
  }
  final completion = await waitForAndroidVoiceMessageDownloadForE2E(
    messageId: request.messageId,
    attachmentId: request.attachmentId,
    loadAttachments: () => mediaAttachmentRepo.getAttachmentsForMessage(
      request.messageId,
      owner: MediaOwnerLane.direct,
    ),
    downloadAttachment: (current) => downloadMedia(
      bridge: bridge,
      mediaAttachmentRepo: mediaAttachmentRepo,
      mediaFileManager: mediaFileManager,
      attachment: current,
      contactPeerId: request.contactPeerId,
      owner: MediaOwnerLane.direct,
      messageRepo: messageRepo,
      intent: MediaDownloadIntent.explicitUser,
    ),
    resolveStoredPath: mediaFileManager.resolveStoredPath,
    fileExists: (path) => File(path).exists(),
    onWaitCycle: p2pService.drainOfflineInbox,
    timeout: remaining,
  );
  final downloaded = completion.attachment;
  final localPath = completion.localPath;
  final file = File(localPath);
  final bytes = await _readM4a(file);
  if (bytes.length != downloaded.size) {
    throw StateError('receiver bytes do not match attachment size');
  }
  final digest = sha256.convert(bytes).toString();
  final playback = await playAndroidVoiceMessageFileForE2E(
    file: file,
    timeout: request.timeout,
  );
  if (!await file.exists()) {
    throw StateError('production durable receiver attachment was removed');
  }

  return <String, Object?>{
    'schema': androidVoiceMessageE2EEndpointResultSchema,
    'status': 'complete',
    'success': true,
    'scenario': androidVoiceMessageE2EScenario,
    'buildProfile': androidVoiceMessageE2EBuildProfile,
    'role': request.role,
    'stepId': 'voice-${request.role}-${request.runId}',
    'runId': request.runId,
    'nonce': request.nonce,
    'receiver': <String, Object?>{
      'ownPeerIdSha256': _tokenSha256(identity.peerId),
      'productionIncomingListener': true,
      'productionGoBridge': true,
      'messagePersisted': true,
      'realMediaDownload': true,
      'downloadStatus': 'done',
      'messageId': message.id,
      'attachmentId': downloaded.id,
      'downloadedSizeBytes': bytes.length,
      'downloadedPlaintextSha256': digest,
      ...playback,
      'durableAttachmentRetained': true,
    },
    'transport': <String, Object?>{
      'realMessageDelivery': true,
      'realRelayMediaDownload': downloaded.downloadStatus == 'done',
      'usedFakeNetwork': false,
      'usedHostFileTransfer': false,
    },
  };
}

/// Real native decode/play proof used by the receiver action and the focused
/// Android endpoint test. Success requires a start event, non-zero progress,
/// natural completion, and an explicit stop that leaves the player idle.
Future<Map<String, Object?>> playAndroidVoiceMessageFileForE2E({
  required File file,
  Duration timeout = const Duration(seconds: 30),
}) async {
  await _readM4a(file);
  final player = AudioPlayer();
  try {
    final duration = await player.setFilePath(file.path).timeout(timeout);
    if (duration == null || duration <= Duration.zero) {
      throw StateError('native audio decoder returned no duration');
    }
    final started = player.playerStateStream
        .firstWhere(
          (state) =>
              state.playing &&
              state.processingState != ProcessingState.completed,
        )
        .timeout(timeout);
    final progressed = player.positionStream
        .firstWhere((position) => position > Duration.zero)
        .timeout(timeout);
    final completed = player.processingStateStream
        .firstWhere((state) => state == ProcessingState.completed)
        .timeout(timeout);
    unawaited(player.play());
    await started;
    await progressed;
    await completed;
    await player.stop().timeout(timeout);
    if (player.playing) throw StateError('native player did not stop');
    return <String, Object?>{
      'realAudioPlayerPlugin': true,
      'playbackStarted': true,
      'playbackProgressObserved': true,
      'playbackCompleted': true,
      'playbackStopped': true,
      'playbackDurationMs': duration.inMilliseconds,
    };
  } finally {
    await player.stop();
    await player.dispose();
  }
}

Future<List<int>> _readM4a(File file) async {
  if (!await file.exists()) throw StateError('voice media file is missing');
  final bytes = await file.readAsBytes();
  if (bytes.length < 12 ||
      String.fromCharCodes(bytes.sublist(4, 8)) != 'ftyp') {
    throw StateError('voice media is not an MP4/M4A file');
  }
  return bytes;
}

void _requireExactSentMessage(
  ConversationMessage message,
  AndroidVoiceMessageE2ERequest request,
) {
  final exact = message.media
      .where((attachment) => attachment.id == request.attachmentId)
      .toList(growable: false);
  if (message.id != request.messageId ||
      message.isIncoming ||
      message.contactPeerId != request.contactPeerId ||
      exact.length != 1 ||
      exact.single.mediaType != 'audio' ||
      !const <String>{'delivered', 'inboxed'}.contains(message.status) ||
      !const <String>{'direct', 'relay', 'inbox'}.contains(message.transport)) {
    throw StateError('production send result does not match the run tuple');
  }
}

Future<void> _waitForProductionTransport(
  P2PService p2pService,
  Duration timeout,
) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final state = p2pService.currentState;
    if (state.isStarted &&
        (state.listenAddresses.isNotEmpty ||
            state.circuitAddresses.isNotEmpty ||
            state.relayState == 'online')) {
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 250));
  }
  throw StateError('production transport did not become ready');
}

String _requiredToken(
  Map<String, dynamic> config,
  String key, {
  required int maxLength,
}) {
  final value = config[key];
  if (value is! String ||
      value.isEmpty ||
      value.length > maxLength ||
      !RegExp(r'^[A-Za-z0-9._:-]+$').hasMatch(value)) {
    throw FormatException('voice-message request has invalid $key');
  }
  return value;
}

String _tokenSha256(String value) =>
    sha256.convert(utf8.encode(value)).toString();
