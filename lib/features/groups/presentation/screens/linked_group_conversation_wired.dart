import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/database/helpers/protected_group_content_db_helpers.dart';
import 'package:flutter_app/core/media/audio_recorder_service.dart';
import 'package:flutter_app/core/media/group_media_blob_custody.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/group_media_mime_policy.dart';
import 'package:flutter_app/core/media/group_media_size_policy.dart';
import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_picker.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/core/notifications/app_visibility_route_binding.dart';
import 'package:flutter_app/core/notifications/app_visibility_snapshot.dart';
import 'package:flutter_app/features/conversation/presentation/navigation/direct_private_media_route_observer.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/models/audio_recording.dart';
import 'package:flutter_app/features/conversation/domain/repositories/media_attachment_repository.dart';
import 'package:flutter_app/features/groups/application/group_offline_replay_envelope.dart';
import 'package:flutter_app/features/groups/application/linked_group_status_refresh.dart';
import 'package:flutter_app/features/groups/application/prepared_group_media_blob_custody_coordinator.dart';
import 'package:flutter_app/features/groups/application/protected_group_content_receive.dart';
import 'package:flutter_app/features/groups/application/protected_group_media_manifest.dart';
import 'package:flutter_app/features/groups/application/send_group_message_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_app/features/groups/domain/models/group_reaction_payload.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_viewer_item.dart';
import 'package:uuid/uuid.dart';

typedef LoadLinkedProtectedMessages =
    Future<List<GroupMessage>> Function(String groupId);
typedef LoadLinkedCurrentGroup = Future<GroupModel?> Function(String groupId);
typedef LoadLinkedProtectedReactions =
    Future<Map<String, List<MessageReaction>>> Function(
      List<String> messageIds,
    );
typedef LoadLinkedProtectedMedia =
    Future<Map<String, List<MediaAttachment>>> Function(
      List<String> messageIds,
    );
typedef MarkLinkedVisibleMessagesRead =
    Future<void> Function(String groupId, List<String> messageIds);
typedef CanAuthorLinkedProtectedContent = Future<bool> Function(String groupId);
typedef SendLinkedProtectedText =
    Future<bool> Function(String groupId, String text);
typedef ToggleLinkedProtectedReaction =
    Future<bool> Function({
      required String groupId,
      required GroupMessage message,
      required String emoji,
      required bool remove,
    });
typedef RunLinkedGroupMediaAuthorAction = Future<bool> Function(String groupId);
typedef OpenLinkedGroupMedia =
    Future<void> Function(String groupId, String messageId, int index);
typedef RetryLinkedGroupMedia =
    Future<void> Function(String groupId, String messageId);

Map<String, Object?>? _linkedProtectedEventPayload(
  Map<String, Object?> row, {
  required String groupId,
  required String eventType,
}) {
  if (row['group_id'] != groupId || row['event_type'] != eventType) return null;
  final raw = row['canonical_payload'];
  if (raw is! String) return null;
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map
        ? Map<String, Object?>.from(decoded.cast<String, Object?>())
        : null;
  } catch (_) {
    return null;
  }
}

bool hasLinkedProtectedContentTerminalEvidence({
  required String groupId,
  required String payloadType,
  required String contentEventId,
  required Iterable<Map<String, Object?>> terminalRows,
}) {
  for (final row in terminalRows) {
    if (isProtectedGroupContentTerminalRowExact(
      row,
      groupId: groupId,
      payloadType: payloadType,
      contentEventId: contentEventId,
    )) {
      return true;
    }
  }
  return false;
}

bool isExactLinkedProtectedMessageEvidence({
  required String groupId,
  required GroupMessage message,
  required Map<String, Object?>? evidenceRow,
  required Iterable<Map<String, Object?>> terminalRows,
  List<MediaAttachment> media = const <MediaAttachment>[],
}) {
  if (evidenceRow == null ||
      hasLinkedProtectedContentTerminalEvidence(
        groupId: groupId,
        payloadType: groupOfflineReplayPayloadTypeMessage,
        contentEventId: message.id,
        terminalRows: terminalRows,
      )) {
    return false;
  }
  final event = _linkedProtectedEventPayload(
    evidenceRow,
    groupId: groupId,
    eventType: protectedGroupMessageEventType,
  );
  final payload = event?['payload'];
  final timestamp = fixedGroupContentUtc(message.timestamp);
  return event != null &&
      payload is Map &&
      evidenceRow['source_event_id'] ==
          protectedGroupMessageSourceEventId(message.id) &&
      evidenceRow['source_peer_id'] == message.senderPeerId &&
      evidenceRow['source_timestamp'] == timestamp &&
      event['custodyKind'] == groupContentCustodyKind &&
      event['groupId'] == groupId &&
      event['payloadType'] == groupOfflineReplayPayloadTypeMessage &&
      event['contentEventId'] == message.id &&
      event['logicalSenderPeerId'] == message.senderPeerId &&
      event['senderTransportPeerId'] == message.transportPeerId &&
      event['authorityKeyEpoch'] == message.keyGeneration &&
      payload['groupId'] == groupId &&
      payload['messageId'] == message.id &&
      payload['senderId'] == message.senderPeerId &&
      payload['transportPeerId'] == message.transportPeerId &&
      payload['logicalDeliveryId'] == message.logicalDeliveryId &&
      payload['keyEpoch'] == message.keyGeneration &&
      payload['text'] == message.text &&
      payload['timestamp'] == timestamp &&
      _matchesLinkedProtectedMediaEvidence(
        groupId: groupId,
        message: message,
        payload: payload,
        media: media,
      );
}

const int _linkedGroupMediaAesGcmTagBytes = 16;

bool _matchesLinkedProtectedMediaEvidence({
  required String groupId,
  required GroupMessage message,
  required Map payload,
  required List<MediaAttachment> media,
}) {
  final rawManifest = payload['mediaManifest'];
  final rawManifestHash = payload['mediaManifestHash'];
  if (media.isEmpty) {
    return rawManifest == null && rawManifestHash == null;
  }
  if (rawManifest is! String || rawManifestHash is! String) return false;

  try {
    final manifest = ProtectedGroupMediaManifest.decode(rawManifest);
    if (manifest.encode() != rawManifest ||
        manifest.fingerprintSha256 != rawManifestHash ||
        manifest.groupId != groupId ||
        manifest.messageId != message.id ||
        manifest.attachments.length != media.length) {
      return false;
    }
    final byId = <String, MediaAttachment>{
      for (final attachment in media) attachment.id: attachment,
    };
    if (byId.length != media.length) return false;
    final sortedAttachmentIds = manifest.attachments
        .map((attachment) => attachment.attachmentId)
        .toList(growable: false);
    for (final commitment in manifest.attachments) {
      final attachment = byId[commitment.attachmentId];
      if (attachment == null ||
          commitment.ciphertextSize <= _linkedGroupMediaAesGcmTagBytes ||
          attachment.messageId != message.id ||
          attachment.ownerLane != MediaOwnerLane.group ||
          attachment.mime != commitment.mime ||
          attachment.mediaType != commitment.mediaType ||
          attachment.size !=
              commitment.ciphertextSize - _linkedGroupMediaAesGcmTagBytes ||
          attachment.width != commitment.width ||
          attachment.height != commitment.height ||
          attachment.durationMs != commitment.durationMs ||
          !_sameWaveform(attachment.waveform, commitment.waveform) ||
          attachment.contentHash != commitment.ciphertextSha256 ||
          attachment.encryptionKeyBase64 != commitment.encryptionKeyBase64 ||
          attachment.encryptionNonce != commitment.encryptionNonce ||
          attachment.encryptionScheme != commitment.encryptionScheme ||
          attachment.groupMediaBlobCustodyFingerprint !=
              computeGroupMediaBlobCustodyFingerprint(
                groupId: groupId,
                messageId: message.id,
                attachmentId: commitment.attachmentId,
                custodyBlobId: commitment.custodyBlobId,
                contentHash: commitment.ciphertextSha256,
                ciphertextSize: commitment.ciphertextSize,
                recipientPeerIds: commitment.recipientPeerIds,
              ) ||
          commitment.caption !=
              (commitment.attachmentId == sortedAttachmentIds.first &&
                      message.text.isNotEmpty
                  ? message.text
                  : null)) {
        return false;
      }
    }
    return true;
  } on Object {
    return false;
  }
}

bool _sameWaveform(List<double>? local, List<double> committed) {
  final normalizedLocal = local ?? const <double>[];
  if (normalizedLocal.length != committed.length) return false;
  for (var index = 0; index < normalizedLocal.length; index++) {
    if (normalizedLocal[index] != committed[index]) return false;
  }
  return true;
}

bool isExactLinkedProtectedReactionEvidence({
  required String groupId,
  required MessageReaction reaction,
  required Iterable<Map<String, Object?>> evidenceRows,
  required Iterable<Map<String, Object?>> terminalRows,
}) {
  String? winningTransition;
  GroupReactionPayload? winningPayload;
  for (final row in evidenceRows) {
    final event = _linkedProtectedEventPayload(
      row,
      groupId: groupId,
      eventType: protectedGroupReactionEventType,
    );
    final rawPayload = event?['payload'];
    if (event == null || rawPayload is! Map) continue;
    final payload = GroupReactionPayload.fromDecryptedJson(
      jsonEncode(rawPayload),
    );
    final transitionId = payload?.eventId;
    final authoredAt = payload == null
        ? null
        : parseFixedGroupContentUtc(payload.timestamp);
    if (payload == null ||
        transitionId == null ||
        authoredAt == null ||
        row['source_event_id'] !=
            protectedGroupReactionSourceEventId(transitionId) ||
        row['source_peer_id'] != payload.senderPeerId ||
        row['source_timestamp'] != payload.timestamp ||
        event['custodyKind'] != groupContentCustodyKind ||
        event['groupId'] != groupId ||
        event['payloadType'] != groupOfflineReplayPayloadTypeReaction ||
        event['contentEventId'] != transitionId ||
        event['logicalSenderPeerId'] != payload.senderPeerId ||
        buildGroupReactionTransitionId(
              groupId: groupId,
              messageId: payload.messageId,
              logicalActorPeerId: payload.senderPeerId,
              action: payload.action,
              emoji: payload.emoji,
              timestamp: authoredAt,
            ) !=
            transitionId ||
        payload.messageId != reaction.messageId ||
        payload.senderPeerId != reaction.senderPeerId ||
        hasLinkedProtectedContentTerminalEvidence(
          groupId: groupId,
          payloadType: groupOfflineReplayPayloadTypeReaction,
          contentEventId: transitionId,
          terminalRows: terminalRows,
        )) {
      continue;
    }
    if (winningTransition == null ||
        compareGroupReactionTransitionIds(transitionId, winningTransition) >
            0) {
      winningTransition = transitionId;
      winningPayload = payload;
    }
  }
  final winner = winningPayload;
  return winner != null &&
      winner.action == GroupReactionPayload.actionAdd &&
      reaction.removedAt == null &&
      reaction.id == winner.id &&
      reaction.emoji == winner.emoji &&
      reaction.timestamp == winner.timestamp;
}

/// The exact local signing material needed by the linked-only strict producer.
///
/// Keeping this projection primitive prevents the presentation owner from
/// gaining account/profile mutation capabilities through a broad repository.
final class LinkedGroupMediaAuthorIdentity {
  const LinkedGroupMediaAuthorIdentity({
    required this.peerId,
    required this.publicKey,
    required this.privateKey,
    required this.username,
  });

  final String peerId;
  final String publicKey;
  final String privateKey;
  final String username;
}

typedef LoadLinkedGroupMediaAuthorIdentity =
    Future<LinkedGroupMediaAuthorIdentity?> Function();

/// Strict-only producer behind the linked route's four ordinary-media ports.
///
/// It deliberately owns no listener, topic, broad retry service, private-media
/// policy, share/forward entry point, or group mutation callback. Fresh files
/// enter the shared prepared-custody coordinator only after a current strict
/// admission snapshot has been obtained. Explicit retry delegates to the two
/// restricted linked-runtime drains supplied by the composition root.
final class LinkedGroupMediaVoiceActionOwner {
  LinkedGroupMediaVoiceActionOwner({
    required this.bridge,
    required this.groupRepository,
    required this.messageRepository,
    required this.mediaAttachmentRepository,
    required this.preparedCustodyCoordinator,
    required this.loadIdentity,
    required this.retryStrictOutgoing,
    required this.retryStrictIncoming,
    required this.refreshProjection,
    this.inviteDeliveryAttemptRepository,
    MediaPicker? mediaPicker,
    ImageProcessor? imageProcessor,
    AudioRecorderService? audioRecorderService,
    ImageQualityPreference imageQuality = ImageQualityPreference.compressed,
    ImageQualityPreference videoQuality = ImageQualityPreference.compressed,
    String Function()? idFactory,
    DateTime Function()? clock,
  }) : _mediaPicker = mediaPicker ?? SystemMediaPicker(),
       _imageProcessor = imageProcessor ?? ImageProcessor(),
       _audioRecorderService = audioRecorderService,
       _imageQuality = imageQuality,
       _videoQuality = videoQuality,
       _idFactory = idFactory ?? const Uuid().v4,
       _clock = clock ?? DateTime.now;

  final Bridge bridge;
  final GroupRepository groupRepository;
  final GroupMessageRepository messageRepository;
  final MediaAttachmentRepository mediaAttachmentRepository;
  final GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepository;
  final PreparedGroupMediaBlobCustodyCoordinator preparedCustodyCoordinator;
  final LoadLinkedGroupMediaAuthorIdentity loadIdentity;
  final Future<int> Function() retryStrictOutgoing;
  final Future<int> Function() retryStrictIncoming;
  final Future<void> Function() refreshProjection;
  final MediaPicker _mediaPicker;
  final ImageProcessor _imageProcessor;
  final AudioRecorderService? _audioRecorderService;
  final ImageQualityPreference _imageQuality;
  final ImageQualityPreference _videoQuality;
  final String Function() _idFactory;
  final DateTime Function() _clock;

  bool _sendInFlight = false;
  bool _voiceTransitionInFlight = false;
  int _voiceGeneration = 0;
  String? _recordingGroupId;
  StreamSubscription<double>? _amplitudeSubscription;
  final List<double> _waveform = <double>[];

  Future<bool> attachOrdinaryMedia(String groupId) async {
    if (_sendInFlight) return false;
    try {
      final picked = await _mediaPicker.pickMultipleMedia();
      if (picked.isEmpty) return false;
      return _sendSources(
        groupId,
        picked
            .take(10)
            .map(
              (file) => _LinkedGroupMediaInput(
                path: file.path,
                declaredMime: _linkedGroupMimeFromPath(file.path),
              ),
            )
            .toList(growable: false),
      );
    } on Object {
      return false;
    }
  }

  Future<bool> startVoiceRecording(String groupId) async {
    final recorder = _audioRecorderService;
    if (recorder == null ||
        recorder.isRecording ||
        _voiceTransitionInFlight ||
        _recordingGroupId != null ||
        _sendInFlight) {
      return false;
    }
    _voiceTransitionInFlight = true;
    final generation = ++_voiceGeneration;
    try {
      // Recording is itself a media-producing effect, so do the same current
      // strict admission read used by send before asking the native recorder
      // to create a file.
      if (await _loadStrictSession(groupId) == null) return false;
      final permitted =
          await recorder.hasPermission() || await recorder.requestPermission();
      if (!permitted || recorder.isRecording) return false;
      _waveform.clear();
      _recordingGroupId = groupId;
      _amplitudeSubscription = recorder.amplitudeStream.listen((sample) {
        if (!sample.isFinite) return;
        final normalized = sample.clamp(0.0, 1.0).toDouble();
        if (_waveform.length == 50) _waveform.removeAt(0);
        _waveform.add(normalized);
      });
      recorder.onAutoStopped = (recording) {
        unawaited(_handleAutoStopped(groupId, recording));
      };
      try {
        await recorder.start(outputPath: '');
      } on Object {
        await _clearVoiceCapture();
        return false;
      }
      if (generation != _voiceGeneration || _recordingGroupId != groupId) {
        try {
          await recorder.cancel();
        } on Object {
          // The generation mismatch already revoked local ownership.
        }
        await _clearVoiceCapture();
        return false;
      }
      return recorder.isRecording && _recordingGroupId == groupId;
    } finally {
      _voiceTransitionInFlight = false;
    }
  }

  Future<bool> stopVoiceRecording(String groupId) async {
    final recorder = _audioRecorderService;
    if (recorder == null ||
        _recordingGroupId != groupId ||
        _voiceTransitionInFlight) {
      return false;
    }
    _voiceTransitionInFlight = true;
    try {
      final recording = await recorder.stop();
      final waveform = List<double>.unmodifiable(_waveform);
      await _clearVoiceCapture();
      if (recording == null) return false;
      return _sendSources(groupId, <_LinkedGroupMediaInput>[
        _LinkedGroupMediaInput(
          path: recording.filePath,
          declaredMime: recording.mime,
          durationMs: recording.durationMs,
          waveform: waveform,
        ),
      ]);
    } on Object {
      await _clearVoiceCapture();
      return false;
    } finally {
      _voiceTransitionInFlight = false;
    }
  }

  Future<bool> cancelVoiceRecording(String groupId) async {
    final recorder = _audioRecorderService;
    if (recorder == null || _recordingGroupId != groupId) return false;
    _voiceGeneration += 1;
    try {
      await recorder.cancel();
      return true;
    } on Object {
      return false;
    } finally {
      await _clearVoiceCapture();
    }
  }

  Future<bool> retryOrdinaryMedia(String groupId, String messageId) async {
    if (groupId.trim() != groupId ||
        groupId.isEmpty ||
        messageId.trim() != messageId ||
        messageId.isEmpty) {
      return false;
    }
    try {
      final outgoing = await retryStrictOutgoing();
      final incoming = await retryStrictIncoming();
      await refreshProjection();
      return outgoing + incoming > 0;
    } on Object {
      return false;
    }
  }

  Future<void> _handleAutoStopped(
    String groupId,
    AudioRecording? recording,
  ) async {
    if (_recordingGroupId != groupId) return;
    final waveform = List<double>.unmodifiable(_waveform);
    await _clearVoiceCapture();
    if (recording == null) return;
    await _sendSources(groupId, <_LinkedGroupMediaInput>[
      _LinkedGroupMediaInput(
        path: recording.filePath,
        declaredMime: recording.mime,
        durationMs: recording.durationMs,
        waveform: waveform,
      ),
    ]);
  }

  Future<void> _clearVoiceCapture() async {
    _recordingGroupId = null;
    _waveform.clear();
    final recorder = _audioRecorderService;
    if (recorder != null) recorder.onAutoStopped = null;
    final subscription = _amplitudeSubscription;
    _amplitudeSubscription = null;
    try {
      await subscription?.cancel();
    } on Object {
      // A stale recorder stream has no authority after local state is cleared.
    }
  }

  Future<
    ({
      LinkedGroupMediaAuthorIdentity identity,
      StrictGroupContentAuthoringSnapshot snapshot,
    })?
  >
  _loadStrictSession(String groupId) async {
    if (groupId.trim() != groupId || groupId.isEmpty) return null;
    final identity = await loadIdentity();
    if (identity == null) return null;
    final admission = await prepareGroupContentAuthoringAdmission(
      groupRepo: groupRepository,
      groupId: groupId,
      senderPeerId: identity.peerId,
      senderPublicKey: identity.publicKey,
      inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepository,
    );
    final snapshot = admission.snapshot;
    if (admission.kind != GroupContentAuthoringResolutionKind.strict ||
        snapshot == null) {
      return null;
    }
    return (identity: identity, snapshot: snapshot);
  }

  Future<bool> _sendSources(
    String groupId,
    List<_LinkedGroupMediaInput> inputs,
  ) async {
    if (_sendInFlight || inputs.isEmpty || inputs.length > 10) return false;
    _sendInFlight = true;
    var hasDurableAuthority = false;
    try {
      final session = await _loadStrictSession(groupId);
      if (session == null) return false;
      final messageId = _idFactory();
      final timestamp = _clock().toUtc();
      final preparedSources = <PreparedGroupMediaBlobSource>[];
      final attachments = <MediaAttachment>[];

      for (final input in inputs) {
        var path = input.path;
        var mime = input.declaredMime ?? _linkedGroupMimeFromPath(path);
        int? width;
        int? height;
        var durationMs = input.durationMs;
        if (mime != null && mime.startsWith('image/')) {
          path = await _imageProcessor.processImage(
            inputPath: path,
            quality: _imageQuality,
          );
          mime = _linkedGroupMimeFromPath(path) ?? mime;
        } else if (mime != null && mime.startsWith('video/')) {
          final video = await _imageProcessor.processVideo(
            inputPath: path,
            quality: _videoQuality,
          );
          path = video.path;
          width = video.width;
          height = video.height;
          durationMs = video.durationMs;
        }
        if (mime == null) return false;
        final mediaType = GroupMediaMimePolicy.mediaTypeForMime(mime);
        if (mediaType == null ||
            !(await GroupMediaMimePolicy.validateFile(
              path: path,
              mime: mime,
              mediaType: mediaType,
            )).isValid) {
          return false;
        }
        final size = await File(path).length();
        if (!GroupMediaSizePolicy.validateSize(
          sizeBytes: size,
          mime: mime,
        ).isValid) {
          return false;
        }
        final attachment = MediaAttachment(
          id: _idFactory(),
          messageId: messageId,
          mime: mime,
          size: size,
          mediaType: mediaType,
          width: width,
          height: height,
          durationMs: durationMs,
          localPath: path,
          downloadStatus: 'upload_pending',
          createdAt: timestamp.toIso8601String(),
          waveform: input.waveform,
          uploadRetryCount: 0,
          downloadRetryCount: 0,
          ownerLane: MediaOwnerLane.group,
        );
        attachments.add(attachment);
        preparedSources.add(
          PreparedGroupMediaBlobSource(
            attachment: attachment,
            plaintextPath: path,
          ),
        );
      }
      if (!GroupMediaSizePolicy.validateAttachments(attachments).isValid) {
        return false;
      }
      final identity = session.identity;
      final snapshot = session.snapshot;
      final parent = GroupMessage(
        id: messageId,
        groupId: groupId,
        senderPeerId: identity.peerId,
        senderUsername: identity.username,
        text: '',
        timestamp: timestamp,
        status: GroupMessage.statusQueuedOffline,
        isIncoming: false,
        createdAt: timestamp,
      );
      final result = await preparedCustodyCoordinator.prepareAndSend(
        bridge: bridge,
        groupRepository: groupRepository,
        messageRepository: messageRepository,
        mediaAttachmentRepository: mediaAttachmentRepository,
        identityPeerId: identity.peerId,
        senderPublicKey: identity.publicKey,
        senderPrivateKey: identity.privateKey,
        senderUsername: identity.username,
        senderDeviceId: snapshot.senderDeviceId,
        senderTransportPeerId: snapshot.senderTransportPeerId,
        inviteDeliveryAttemptRepository: inviteDeliveryAttemptRepository,
        groupContentAuthoring: snapshot.context,
        parent: parent,
        sources: preparedSources,
      );
      hasDurableAuthority = result.preparation.hasDurableAuthority;
      return result.preparation.isComplete || hasDurableAuthority;
    } on Object {
      return hasDurableAuthority;
    } finally {
      _sendInFlight = false;
      try {
        await refreshProjection();
      } on Object {
        // Durable custody is authoritative; the next fixed point reloads UI.
      }
    }
  }
}

final class _LinkedGroupMediaInput {
  const _LinkedGroupMediaInput({
    required this.path,
    this.declaredMime,
    this.durationMs,
    this.waveform,
  });

  final String path;
  final String? declaredMime;
  final int? durationMs;
  final List<double>? waveform;
}

String? _linkedGroupMimeFromPath(String path) {
  final normalized = path.toLowerCase().split('?').first;
  if (normalized.endsWith('.jpg') || normalized.endsWith('.jpeg')) {
    return 'image/jpeg';
  }
  if (normalized.endsWith('.png')) return 'image/png';
  if (normalized.endsWith('.gif')) return 'image/gif';
  if (normalized.endsWith('.webp')) return 'image/webp';
  if (normalized.endsWith('.heic') || normalized.endsWith('.heif')) {
    return 'image/heic';
  }
  if (normalized.endsWith('.mov')) return 'video/quicktime';
  if (normalized.endsWith('.mp4') || normalized.endsWith('.m4v')) {
    return 'video/mp4';
  }
  if (normalized.endsWith('.m4a')) return 'audio/mp4';
  if (normalized.endsWith('.aac')) return 'audio/aac';
  if (normalized.endsWith('.mp3')) return 'audio/mpeg';
  if (normalized.endsWith('.ogg') || normalized.endsWith('.oga')) {
    return 'audio/ogg';
  }
  return null;
}

/// The deliberately small linked-group route owner.
///
/// Unlike [GroupConversationWired], this capability has no private-media,
/// quote, forward, share, history, settings, info, topic or leave callback.
/// Plan-365 adds only ordinary protected attachment/voice authoring, render,
/// playback and explicit retry ports. The producer must return only
/// event-log-proven protected rows; this owner applies the final shape filter
/// again before rendering.
class LinkedGroupConversationWired extends StatefulWidget {
  const LinkedGroupConversationWired({
    super.key,
    required this.group,
    required this.loadCurrentGroup,
    required this.loadProtectedMessages,
    required this.loadProtectedReactions,
    required this.markVisibleMessagesRead,
    required this.groupConversationTracker,
    required this.isAuthoritySettled,
    required this.canAuthorProtectedContent,
    required this.sendProtectedText,
    required this.toggleProtectedReaction,
    this.loadProtectedMedia,
    this.attachOrdinaryMedia,
    this.startVoiceRecording,
    this.stopVoiceRecording,
    this.cancelVoiceRecording,
    this.openOrdinaryMedia,
    this.retryOrdinaryMedia,
    this.backgroundPreference = BackgroundPreference.defaultBackground,
  });

  final GroupModel group;
  final LoadLinkedCurrentGroup loadCurrentGroup;
  final LoadLinkedProtectedMessages loadProtectedMessages;
  final LoadLinkedProtectedReactions loadProtectedReactions;
  final MarkLinkedVisibleMessagesRead markVisibleMessagesRead;
  final ActiveConversationTracker groupConversationTracker;
  final Future<bool> Function(String groupId) isAuthoritySettled;
  final CanAuthorLinkedProtectedContent canAuthorProtectedContent;
  final SendLinkedProtectedText sendProtectedText;
  final ToggleLinkedProtectedReaction toggleProtectedReaction;
  final LoadLinkedProtectedMedia? loadProtectedMedia;
  final RunLinkedGroupMediaAuthorAction? attachOrdinaryMedia;
  final RunLinkedGroupMediaAuthorAction? startVoiceRecording;
  final RunLinkedGroupMediaAuthorAction? stopVoiceRecording;
  final RunLinkedGroupMediaAuthorAction? cancelVoiceRecording;
  final OpenLinkedGroupMedia? openOrdinaryMedia;
  final RetryLinkedGroupMedia? retryOrdinaryMedia;
  final BackgroundPreference backgroundPreference;

  @override
  State<LinkedGroupConversationWired> createState() =>
      _LinkedGroupConversationWiredState();
}

class _LinkedGroupConversationWiredState
    extends State<LinkedGroupConversationWired>
    with WidgetsBindingObserver {
  StreamSubscription<void>? _authorityRefresh;
  List<GroupMessage> _messages = const [];
  Map<String, List<MessageReaction>> _reactions = const {};
  Map<String, List<MediaAttachment>> _media = const {};
  bool _loading = true;
  bool _settled = false;
  bool _authoringQualified = false;
  bool _sending = false;
  bool _voiceRecording = false;
  bool _voiceTransitionInFlight = false;
  bool _isLifecycleResumed = true;
  int _reloadGeneration = 0;
  late GroupModel _currentGroup;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _isLifecycleResumed = lifecycleState == AppLifecycleState.resumed;
    _currentGroup = widget.group;
    if (_isLifecycleResumed) {
      widget.groupConversationTracker.setActive(_activeConversationKey);
    }
    _authorityRefresh = linkedGroupStatusRefreshes.listen((_) {
      unawaited(_reload());
    });
    unawaited(_reload());
  }

  @override
  void dispose() {
    if (_voiceRecording && widget.cancelVoiceRecording != null) {
      unawaited(widget.cancelVoiceRecording!(widget.group.id));
    }
    widget.groupConversationTracker.clearIfActive(_activeConversationKey);
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_authorityRefresh?.cancel());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isLifecycleResumed = state == AppLifecycleState.resumed;
    if (_isLifecycleResumed) {
      // This assignment is synchronous. The app-root resume owner may begin an
      // async notification-display drain in the same lifecycle broadcast; by
      // its first await the linked route is already visible to suppression.
      widget.groupConversationTracker.setActive(_activeConversationKey);
      // Match the incumbent conversation: a route that remained mounted while
      // backgrounded re-reads its device-local projection on resume. The app
      // root's later post-content refresh remains the authoritative fixed-point
      // pass for rows that arrive during resume recovery.
      unawaited(_reload());
    } else {
      _reloadGeneration++;
      _revokeVoiceCapture();
      widget.groupConversationTracker.clearIfActive(_activeConversationKey);
    }
  }

  @override
  void didUpdateWidget(covariant LinkedGroupConversationWired oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.group.id == widget.group.id &&
        identical(
          oldWidget.groupConversationTracker,
          widget.groupConversationTracker,
        )) {
      return;
    }
    oldWidget.groupConversationTracker.clearIfActive(
      'group:${oldWidget.group.id}',
    );
    _currentGroup = widget.group;
    if (_isLifecycleResumed) {
      widget.groupConversationTracker.setActive(_activeConversationKey);
    }
    unawaited(_reload());
  }

  String get _activeConversationKey => 'group:${widget.group.id}';

  Future<bool> _loadAuthoringQualification() async {
    try {
      return await widget.canAuthorProtectedContent(widget.group.id);
    } catch (_) {
      return false;
    }
  }

  Future<void> _reload() async {
    final generation = ++_reloadGeneration;
    final settled = await widget.isAuthoritySettled(widget.group.id);
    if (!mounted || generation != _reloadGeneration) return;
    if (!settled) {
      _revokeVoiceCapture();
      setState(() {
        _settled = false;
        _authoringQualified = false;
        _loading = false;
        _messages = const [];
        _reactions = const {};
        _media = const {};
      });
      return;
    }
    final currentGroup = await widget.loadCurrentGroup(widget.group.id);
    if (!mounted || generation != _reloadGeneration) return;
    if (currentGroup == null) {
      _revokeVoiceCapture();
      setState(() {
        _settled = false;
        _authoringQualified = false;
        _loading = false;
        _messages = const [];
        _reactions = const {};
        _media = const {};
      });
      return;
    }
    final loaded = await widget.loadProtectedMessages(widget.group.id);
    final loadedMedia =
        await widget.loadProtectedMedia?.call(
          loaded.map((message) => message.id).toList(growable: false),
        ) ??
        const <String, List<MediaAttachment>>{};
    if (!mounted || generation != _reloadGeneration) return;
    final protectedMedia = <String, List<MediaAttachment>>{
      for (final entry in loadedMedia.entries)
        entry.key: entry.value
            .where(
              (attachment) =>
                  attachment.ownerLane == MediaOwnerLane.group &&
                  attachment.groupMediaBlobCustodyFingerprint?.isNotEmpty ==
                      true,
            )
            .toList(growable: false),
    }..removeWhere((_, attachments) => attachments.isEmpty);
    final eligible = loaded
        .where(
          (message) => isEligibleLinkedProtectedGroupMessage(
            currentGroup,
            message,
            media: protectedMedia[message.id] ?? const [],
          ),
        )
        .toList(growable: false);
    final reactions = await widget.loadProtectedReactions(
      eligible.map((message) => message.id).toList(growable: false),
    );
    if (!mounted || generation != _reloadGeneration) return;
    final authoringQualified = await _loadAuthoringQualification();
    if (!mounted || generation != _reloadGeneration) return;
    final stillSettled = await widget.isAuthoritySettled(widget.group.id);
    if (!mounted || generation != _reloadGeneration) return;
    if (!stillSettled) {
      _revokeVoiceCapture();
      setState(() {
        _settled = false;
        _authoringQualified = false;
        _loading = false;
        _messages = const [];
        _reactions = const {};
      });
      return;
    }
    final canRemainComposing =
        authoringQualified &&
        !currentGroup.isDissolved &&
        currentGroup.selfRemovedAt == null &&
        currentGroup.type != GroupType.qa &&
        (currentGroup.type != GroupType.announcement ||
            currentGroup.myRole == GroupRole.admin);
    if (!canRemainComposing) _revokeVoiceCapture();
    setState(() {
      _settled = true;
      _authoringQualified = authoringQualified;
      _loading = false;
      _currentGroup = currentGroup;
      _messages = eligible;
      _reactions = reactions;
      _media = <String, List<MediaAttachment>>{
        for (final message in eligible)
          if (protectedMedia[message.id]?.isNotEmpty == true)
            message.id: protectedMedia[message.id]!,
      };
    });
    // Read state is deliberately device-local. Hand the owner only the exact
    // eligible IDs this narrow surface rendered; a mixed hidden media/private/
    // system row must remain unread and retain its separate custody.
    final unreadVisibleIds = eligible
        .where((message) => message.isIncoming && message.readAt == null)
        .map((message) => message.id)
        .toSet()
        .toList(growable: false);
    if (_isLifecycleResumed &&
        widget.groupConversationTracker.isViewing(_activeConversationKey) &&
        unreadVisibleIds.isNotEmpty) {
      await widget.markVisibleMessagesRead(widget.group.id, unreadVisibleIds);
    }
  }

  bool get _hasActiveAuthority =>
      _settled &&
      !_currentGroup.isDissolved &&
      _currentGroup.selfRemovedAt == null &&
      _currentGroup.type != GroupType.qa;

  // Announcement readers may react to ordinary protected rows, but only an
  // admin may author a new announcement. Keep these capabilities separate so
  // tightening the composer cannot silently remove the reaction surface.
  bool get _canCompose =>
      _hasActiveAuthority &&
      _authoringQualified &&
      (_currentGroup.type != GroupType.announcement ||
          _currentGroup.myRole == GroupRole.admin);

  bool get _canReact => _hasActiveAuthority && _authoringQualified;

  Future<bool> _requalifyAuthoring() async {
    try {
      return await _requalifyAuthoringUnchecked();
    } on Object {
      if (mounted) {
        _revokeVoiceCapture();
        setState(() {
          _settled = false;
          _authoringQualified = false;
          _messages = const [];
          _reactions = const {};
          _media = const {};
        });
      }
      return false;
    }
  }

  Future<bool> _requalifyAuthoringUnchecked() async {
    final settled = await widget.isAuthoritySettled(widget.group.id);
    final currentGroup = settled
        ? await widget.loadCurrentGroup(widget.group.id)
        : null;
    final qualified =
        currentGroup != null && await _loadAuthoringQualification();
    final stillSettled =
        settled &&
        currentGroup != null &&
        await widget.isAuthoritySettled(widget.group.id);
    if (!mounted) return false;
    final finalSettled = settled && stillSettled;
    if (_settled != finalSettled ||
        _authoringQualified != qualified ||
        (currentGroup != null && currentGroup != _currentGroup)) {
      setState(() {
        _settled = finalSettled;
        _authoringQualified = finalSettled && qualified;
        if (currentGroup != null) _currentGroup = currentGroup;
        if (!finalSettled) {
          _messages = const [];
          _reactions = const {};
          _media = const {};
        }
      });
    }
    if ((!finalSettled || !qualified || !_hasActiveAuthority) &&
        _voiceRecording) {
      await _cancelVoiceForRevocation();
    }
    return finalSettled && qualified && _hasActiveAuthority;
  }

  Future<void> _send(String raw) async {
    if (_sending || !_canCompose) return;
    final text = raw.trim();
    if (text.isEmpty || text.startsWith(r'{"__sys":')) return;
    setState(() => _sending = true);
    final stillQualified = await _requalifyAuthoring();
    if (stillQualified && _canCompose) {
      await widget.sendProtectedText(widget.group.id, text);
    }
    if (!mounted) return;
    setState(() => _sending = false);
    await _reload();
  }

  Future<void> _react(String messageId, String emoji, bool remove) async {
    if (!_canReact) return;
    GroupMessage? target;
    for (final message in _messages) {
      if (message.id == messageId) target = message;
    }
    final stillQualified = await _requalifyAuthoring();
    if (target == null || !stillQualified || !_canReact) {
      return;
    }
    await widget.toggleProtectedReaction(
      groupId: widget.group.id,
      message: target,
      emoji: emoji,
      remove: remove,
    );
    await _reload();
  }

  Future<void> _attachMedia() async {
    final action = widget.attachOrdinaryMedia;
    if (action == null) return;
    final stillQualified = await _requalifyAuthoring();
    if (!stillQualified || !_canCompose) return;
    try {
      await action(widget.group.id);
      await _reload();
    } on Object {
      // Capability actions fail closed and expose no broad error surface.
    }
  }

  Future<void> _startVoice() async {
    final action = widget.startVoiceRecording;
    if (action == null || _voiceTransitionInFlight || _voiceRecording) return;
    final stillQualified = await _requalifyAuthoring();
    if (!stillQualified || !_canCompose) return;
    _voiceTransitionInFlight = true;
    try {
      final started = await action(widget.group.id);
      if (!mounted) return;
      setState(() => _voiceRecording = started);
    } on Object {
      if (mounted) setState(() => _voiceRecording = false);
    } finally {
      _voiceTransitionInFlight = false;
    }
  }

  Future<void> _stopVoice() async {
    final action = widget.stopVoiceRecording;
    if (action == null || _voiceTransitionInFlight || !_voiceRecording) return;
    final stillQualified = await _requalifyAuthoring();
    if (!stillQualified || !_canCompose) return;
    _voiceTransitionInFlight = true;
    try {
      await action(widget.group.id);
      if (!mounted) return;
      setState(() => _voiceRecording = false);
    } on Object {
      if (mounted) setState(() => _voiceRecording = false);
    } finally {
      _voiceTransitionInFlight = false;
    }
    await _reload();
  }

  Future<void> _cancelVoice() async {
    if (_voiceTransitionInFlight || !_voiceRecording) return;
    final action = widget.cancelVoiceRecording;
    if (action == null) return;
    final stillQualified = await _requalifyAuthoring();
    if (!stillQualified || !_canCompose) return;
    _voiceTransitionInFlight = true;
    try {
      await action(widget.group.id);
      if (!mounted) return;
      setState(() => _voiceRecording = false);
    } on Object {
      if (mounted) setState(() => _voiceRecording = false);
    } finally {
      _voiceTransitionInFlight = false;
    }
  }

  Future<void> _cancelVoiceForRevocation() async {
    final action = widget.cancelVoiceRecording;
    _voiceRecording = false;
    _voiceTransitionInFlight = false;
    if (action != null) await action(widget.group.id);
  }

  void _revokeVoiceCapture() {
    if (!_voiceRecording && !_voiceTransitionInFlight) return;
    _voiceRecording = false;
    _voiceTransitionInFlight = false;
    final action = widget.cancelVoiceRecording;
    if (action != null) unawaited(action(widget.group.id));
  }

  Future<void> _openMedia(String messageId, int index) async {
    if (!await _requalifyAuthoring()) return;
    final message = _messageById(messageId);
    final visual = (_media[messageId] ?? const <MediaAttachment>[])
        .where(
          (attachment) =>
              attachment.mediaType == 'image' ||
              attachment.mediaType == 'video',
        )
        .toList(growable: false);
    if (message == null ||
        index < 0 ||
        index >= visual.length ||
        !isEligibleLinkedProtectedGroupMessage(
          _currentGroup,
          message,
          media: _media[messageId] ?? const <MediaAttachment>[],
        )) {
      return;
    }
    final action = widget.openOrdinaryMedia;
    if (action != null) {
      try {
        await action(widget.group.id, messageId, index);
      } on Object {
        return;
      }
    } else {
      final displayable = visual
          .where(GroupMediaIntegrityPolicy.canDisplayVerifiedGroupMedia)
          .toList(growable: false);
      final selectedId = visual[index].id;
      final selectedIndex = displayable.indexWhere(
        (attachment) => attachment.id == selectedId,
      );
      if (selectedIndex < 0 || displayable.isEmpty || !mounted) return;
      final visibilityIdentity = AppVisibilityConversationIdentity.tryParse(
        lane: AppVisibilityConversationLane.group,
        value: 'group:${widget.group.id}',
      );
      Widget viewerBuilder(BuildContext _) => FullScreenTypedMediaViewer(
        items: displayable
            .map(
              (attachment) => MediaViewerItem(
                attachmentId: attachment.id,
                messageId: message.id,
                kind: attachment.mediaType == 'video'
                    ? MediaViewerKind.video
                    : attachment.mime == 'image/gif'
                    ? MediaViewerKind.gif
                    : MediaViewerKind.image,
                mime: attachment.mime,
                owner: MediaOwnerLane.group,
                localPath: attachment.localPath == null
                    ? null
                    : MediaFileManager.resolveStoredPathSync(
                        attachment.localPath!,
                      ),
                sizeBytes: attachment.size,
                width: attachment.width,
                height: attachment.height,
                durationMs: attachment.durationMs,
                caption: message.text.isEmpty ? null : message.text,
                timestamp: message.timestamp,
                showMetadataDetails: false,
                canEnterPictureInPicture: false,
                protection: const MediaViewerProtection(
                  isDownloaded: true,
                  isIntegrityVerified: true,
                ),
                capabilities: MediaViewerActionCapabilities.none,
              ),
            )
            .toList(growable: false),
        initialIndex: selectedIndex,
      );
      await Navigator.of(context).push<void>(
        visibilityIdentity == null
            ? MaterialPageRoute<void>(builder: viewerBuilder)
            : AppVisibilityInheritedConversationRoute<void>(
                identity: visibilityIdentity,
                builder: viewerBuilder,
              ),
      );
    }
    await _reload();
  }

  Future<void> _retryMedia(String messageId, {String? attachmentId}) async {
    final action = widget.retryOrdinaryMedia;
    if (action == null || !await _requalifyAuthoring()) return;
    final message = _messageById(messageId);
    final media = _media[messageId] ?? const <MediaAttachment>[];
    if (message == null ||
        media.isEmpty ||
        (attachmentId != null &&
            !media.any((attachment) => attachment.id == attachmentId)) ||
        !isEligibleLinkedProtectedGroupMessage(
          _currentGroup,
          message,
          media: media,
        )) {
      return;
    }
    try {
      await action(widget.group.id, messageId);
      await _reload();
    } on Object {
      // Durable strict retry remains available to the next runtime drain.
    }
  }

  GroupMessage? _messageById(String messageId) {
    for (final message in _messages) {
      if (message.id == messageId) return message;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final child = GroupConversationScreen(
      key: const Key('linked-group-conversation-capability'),
      group: _currentGroup,
      messages: _messages,
      onSend: (text) => unawaited(_send(text)),
      onBack: () => Navigator.of(context).maybePop(),
      canWrite: _canCompose,
      isSending: _sending,
      initialLoadDone: !_loading,
      mediaMap: _media,
      onAttach: _canCompose && widget.attachOrdinaryMedia != null
          ? () => unawaited(_attachMedia())
          : null,
      onRecordStart: _canCompose && widget.startVoiceRecording != null
          ? () => unawaited(_startVoice())
          : null,
      onRecordStop: _canCompose && widget.stopVoiceRecording != null
          ? () => unawaited(_stopVoice())
          : null,
      onRecordCancel: _canCompose && widget.cancelVoiceRecording != null
          ? () => unawaited(_cancelVoice())
          : null,
      isRecording: _voiceRecording,
      onMediaTap:
          !_canReact || (_media.isEmpty && widget.openOrdinaryMedia == null)
          ? null
          : (messageId, index) => unawaited(_openMedia(messageId, index)),
      onRetryFailedMedia:
          !_canReact || _media.isEmpty || widget.retryOrdinaryMedia == null
          ? null
          : (messageId) => unawaited(_retryMedia(messageId)),
      onRetryUnavailableMedia:
          !_canReact || _media.isEmpty || widget.retryOrdinaryMedia == null
          ? null
          : (messageId, attachmentId) =>
                unawaited(_retryMedia(messageId, attachmentId: attachmentId)),
      reactions: _reactions,
      onReactionSelected: _canReact
          ? (messageId, emoji) => unawaited(_react(messageId, emoji, false))
          : null,
      onReactionTap: _canReact
          ? (messageId, emoji) => unawaited(_react(messageId, emoji, true))
          : null,
      readOnlyBannerText: _settled
          ? null
          : 'Waiting for protected group authority to settle.',
      backgroundPreference: widget.backgroundPreference,
    );
    final registry = DirectPrivateMediaRouteObserverScope.maybeRegistryOf(
      context,
    );
    final identity = AppVisibilityConversationIdentity.tryParse(
      lane: AppVisibilityConversationLane.group,
      value: 'group:${widget.group.id}',
    );
    if (registry == null || identity == null) return child;
    return AppVisibilityRouteBinding(
      registry: registry,
      identity: identity,
      observer: DirectPrivateMediaRouteObserverScope.maybeOf(context),
      child: child,
    );
  }
}

bool isEligibleLinkedProtectedGroupMessage(
  GroupModel group,
  GroupMessage message, {
  List<MediaAttachment> media = const <MediaAttachment>[],
}) =>
    message.groupId == group.id &&
    group.type != GroupType.qa &&
    message.media.isEmpty &&
    (message.text.trim().isNotEmpty || media.isNotEmpty) &&
    !message.text.trimLeft().startsWith(r'{"__sys":') &&
    (media.isEmpty ||
        media.every(
          (attachment) =>
              attachment.ownerLane == MediaOwnerLane.group &&
              attachment.groupMediaBlobCustodyFingerprint?.isNotEmpty == true,
        )) &&
    (!message.isForwarded ||
        (media.isNotEmpty &&
            media.every(
              (attachment) =>
                  attachment.mediaType == 'image' ||
                  attachment.mediaType == 'video',
            ))) &&
    message.privateMediaPolicy == const GroupPrivateMediaPolicy.ordinary();
