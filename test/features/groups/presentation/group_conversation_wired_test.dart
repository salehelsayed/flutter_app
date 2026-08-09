import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/constants/retry_constants.dart';
import 'package:flutter_app/core/device/upload_wake_lock.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/upload_retry_projection.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/media_upload_in_flight_tracker.dart';
import 'package:flutter_app/core/permissions/mic_permission_gateway.dart';
import 'package:flutter_app/core/media/media_picker.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/core/media/video_process_result.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/chat_message_listener.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/domain/repositories/message_repository.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/date_separator.dart';
import 'package:flutter_app/features/feed/presentation/widgets/swipe_to_quote_bubble.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/attachment_preview_strip.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/letter_card.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/message_context_overlay.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_exit_diagnostic_sink.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_coordinator.dart';
import 'package:flutter_app/features/groups/application/group_exit_intent_sink.dart';
import 'package:flutter_app/features/groups/application/group_exit_policy.dart';
import 'package:flutter_app/features/groups/application/group_media_forward_intent.dart';
import 'package:flutter_app/features/groups/application/group_membership_event_watermark.dart';
import 'package:flutter_app/features/groups/application/group_private_media_availability.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/application/retry_incomplete_group_downloads_use_case.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_delivery_attempt.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_intent.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_diagnostic.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/group_private_media_policy.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_invite_delivery_attempt_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_screen.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_message_repository.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_repository.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_conversation_wired.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_reaction_details_sheet.dart';
import 'package:flutter_app/core/notifications/active_conversation_tracker.dart';
import 'package:flutter_app/features/groups/presentation/screens/group_info_screen.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:flutter_app/features/p2p/domain/models/node_state.dart';
import 'package:flutter_app/features/p2p/domain/models/chat_message.dart';
import 'package:flutter_app/features/settings/application/media_download_policy.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_app/features/settings/domain/models/media_download_preferences.dart';
import 'package:flutter_app/core/media/received_media_egress.dart';
import 'package:flutter_app/core/media/received_media_egress_service.dart';
import 'package:flutter_app/features/groups/application/group_media_delete_for_me_coordinator.dart';
import 'package:flutter_app/features/groups/application/group_received_media_actions.dart';
import 'package:flutter_app/features/groups/presentation/widgets/group_media_info_sheet.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_typed_media_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_grid.dart';
import 'package:flutter_app/shared/widgets/media/media_thumbnail_image.dart';
import 'package:flutter_app/shared/widgets/media/media_viewer_item.dart';
import 'package:flutter_app/features/share/presentation/screens/share_target_picker_wired.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/fake_audio_recorder_service.dart';
import '../../../shared/fakes/fake_just_audio.dart';
import '../../../shared/fakes/fake_mic_permission_gateway.dart';
import '../../../shared/fakes/fake_group_reaction_replay_outbox_repository.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/helpers/legacy_upload_media_fn.dart';
import '../../../shared/fakes/fake_media_picker.dart';
import '../../../shared/fakes/recording_media_auto_download_decider.dart';
import '../../../shared/fakes/fake_upload_wake_lock_driver.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
import '../../../shared/fakes/in_memory_message_repository.dart';
import '../../../shared/fixtures/media_bytes.dart';
import '../../conversation/domain/repositories/fake_reaction_repository.dart';

const _tinyPngBytes = <int>[
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x02,
  0x00,
  0x00,
  0x00,
  0x90,
  0x77,
  0x53,
  0xDE,
  0x00,
  0x00,
  0x00,
  0x0C,
  0x49,
  0x44,
  0x41,
  0x54,
  0x08,
  0xD7,
  0x63,
  0xF8,
  0xCF,
  0xC0,
  0x00,
  0x00,
  0x03,
  0x01,
  0x01,
  0x00,
  0x18,
  0xDD,
  0x8D,
  0xB1,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
];

const _validContentHash =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _md012MediaKey = 'md012-media-key';
const _md012MediaNonce = 'md012-media-nonce';
const _tinyMp4Bytes = <int>[
  0x00,
  0x00,
  0x00,
  0x18,
  0x66,
  0x74,
  0x79,
  0x70,
  0x6d,
  0x70,
  0x34,
  0x32,
  0x00,
  0x00,
  0x00,
  0x00,
];

const _validHeifBytes = <int>[
  0x00,
  0x00,
  0x00,
  0x18,
  0x66,
  0x74,
  0x79,
  0x70,
  0x6d,
  0x69,
  0x66,
  0x31,
  0x00,
  0x00,
  0x00,
  0x00,
  0x6d,
  0x69,
  0x66,
  0x31,
];

List<int> _md012EncryptedBytes(
  List<int> plaintext, {
  String key = _md012MediaKey,
  String nonce = _md012MediaNonce,
}) {
  return [...'cipher:$key:$nonce:'.codeUnits, ...plaintext.reversed];
}

String _md012HashBytes(List<int> bytes) => sha256.convert(bytes).toString();

// --- FakeIdentityRepository ---

class FakeIdentityRepository implements IdentityRepository {
  IdentityModel? identity;
  Completer<IdentityModel?>? loadIdentityCompleter;
  FakeIdentityRepository({this.identity, this.loadIdentityCompleter});

  @override
  Future<IdentityModel?> loadIdentity() async {
    final completer = loadIdentityCompleter;
    if (completer != null) {
      final loadedIdentity = await completer.future;
      identity = loadedIdentity;
      if (identical(loadIdentityCompleter, completer)) {
        loadIdentityCompleter = null;
      }
      return loadedIdentity;
    }
    return identity;
  }

  @override
  Future<void> saveIdentity(IdentityModel identity) async {
    this.identity = identity;
  }
}

// --- Fake listener with externally-controlled stream ---

/// A fake GroupMessageListener whose [groupMessageStream] is controlled
/// by an external StreamController.
class FakeGroupMessageListener extends GroupMessageListener {
  final Stream<GroupMessage> _externalStream;
  final Stream<ReactionChange>? _externalReactionStream;
  final Stream<String>? _externalRemovedStream;

  FakeGroupMessageListener(
    this._externalStream, {
    Stream<ReactionChange>? reactionStream,
    Stream<String>? removedStream,
  }) : _externalReactionStream = reactionStream,
       _externalRemovedStream = removedStream,
       super(groupRepo: _NoOpGroupRepo(), msgRepo: _NoOpMsgRepo());

  @override
  Stream<GroupMessage> get groupMessageStream => _externalStream;

  @override
  Stream<ReactionChange> get groupReactionChangeStream =>
      _externalReactionStream ?? super.groupReactionChangeStream;

  @override
  Stream<String> get groupRemovedStream =>
      _externalRemovedStream ?? super.groupRemovedStream;
}

class _NoOpGroupRepo implements GroupRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

class _NoOpMsgRepo implements GroupMessageRepository {
  @override
  Future<int> transitionSendingToFailed() async => 0;

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}

/// A bridge that gates group:publish behind a [Completer] so tests can
/// verify optimistic display before the network responds.
class _GatedPublishBridge extends FakeBridge {
  final Completer<void> publishGate = Completer<void>();
  int publishAttempts = 0;

  _GatedPublishBridge() {
    responses['group:publish'] = {'ok': true, 'messageId': 'msg-published'};
  }

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    if (cmd == 'group:publish') {
      publishAttempts++;
      await publishGate.future;
    }

    return super.send(message);
  }
}

class _GatedBackgroundTaskBridge extends FakeBridge {
  final Completer<void> beginStarted = Completer<void>();
  final Completer<void> beginGate = Completer<void>();
  int endCalls = 0;

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'bg:begin') {
      if (!beginStarted.isCompleted) beginStarted.complete();
      await beginGate.future;
      return 'test-background-task';
    }
    if (cmd == 'bg:end') {
      endCalls++;
      return jsonEncode({'ok': true});
    }
    return super.send(message);
  }
}

/// 210: gates `group:sendReliable` behind a [Completer] and answers with a
/// connectivity-class failure when released, so an offline optimistic bubble can
/// be asserted on the frame BEFORE the send result handler runs (the "no tick
/// flash" check).
class _GatedReliableFailBridge extends FakeBridge {
  final Completer<void> sendGate = Completer<void>();
  int reliableAttempts = 0;

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd == 'group:sendReliable') {
      reliableAttempts++;
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);
      await sendGate.future;
      return jsonEncode({'ok': false, 'errorCode': 'NETWORK_DOWN'});
    }
    return super.send(message);
  }
}

class _SequentialGroupPublishBridge extends FakeBridge {
  _SequentialGroupPublishBridge(this.publishResponses);

  final List<Map<String, dynamic>> publishResponses;
  int _publishIndex = 0;

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;
    if (cmd != 'group:publish') {
      return super.send(message);
    }

    sendCallCount++;
    lastSentMessage = message;
    sentMessages.add(message);
    lastCommand = cmd;
    commandLog.add(cmd!);

    final response =
        publishResponses[_publishIndex < publishResponses.length
            ? _publishIndex
            : publishResponses.length - 1];
    _publishIndex++;
    return jsonEncode(response);
  }
}

class _DownloadRepairBridge extends FakeBridge {
  _DownloadRepairBridge({
    required this.downloadedBytes,
    // ignore: unused_element_parameter
    this.mime = 'image/png',
    this.downloadGate,
  });

  List<int> downloadedBytes;
  String mime;
  Completer<void>? downloadGate;

  @override
  Future<String> send(String message) async {
    final parsed = jsonDecode(message) as Map<String, dynamic>;
    final cmd = parsed['cmd'] as String?;

    if (cmd == 'media:download') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);

      final payload = parsed['payload'] as Map<String, dynamic>;
      final outputPath = payload['outputPath'] as String;
      await downloadGate?.future;
      final file = File(outputPath);
      file.parent.createSync(recursive: true);
      file.writeAsBytesSync(downloadedBytes, flush: true);
      return jsonEncode({
        'ok': true,
        'id': payload['id'],
        'mime': mime,
        'size': downloadedBytes.length,
      });
    }

    if (cmd == 'blob:decrypt') {
      sendCallCount++;
      lastSentMessage = message;
      sentMessages.add(message);
      lastCommand = cmd;
      commandLog.add(cmd!);

      final payload = parsed['payload'] as Map<String, dynamic>;
      final filePath = payload['filePath'] as String;
      final keyBase64 = payload['keyBase64'] as String;
      final nonce = payload['nonce'] as String;
      final encrypted = File(filePath).readAsBytesSync();
      final prefix = 'cipher:$keyBase64:$nonce:'.codeUnits;
      final hasPrefix =
          encrypted.length >= prefix.length &&
          List.generate(
            prefix.length,
            (index) => encrypted[index] == prefix[index],
          ).every((matches) => matches);
      if (!hasPrefix) {
        return jsonEncode({'ok': false, 'errorMessage': 'decrypt failed'});
      }
      final decryptedPath = '$filePath.dec';
      File(decryptedPath).writeAsBytesSync(
        encrypted.skip(prefix.length).toList().reversed.toList(),
        flush: true,
      );
      return jsonEncode({'ok': true, 'decryptedPath': decryptedPath});
    }

    return super.send(message);
  }
}

class TrackingDurableMediaFileManager extends FakeMediaFileManager {
  TrackingDurableMediaFileManager(this.rootDir);

  final Directory rootDir;
  int copyCalls = 0;
  final List<String> deletedPendingUploadDirs = <String>[];

  @override
  Future<String> copyToDurableStorage({
    required String sourceFilePath,
    required String messageId,
    required String attachmentId,
    required String mime,
  }) async {
    copyCalls++;
    final ext = p.extension(sourceFilePath);
    final dir = Directory(p.join(rootDir.path, 'pending_uploads', messageId));
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }
    final destinationPath = p.join(dir.path, '$attachmentId$ext');
    await File(sourceFilePath).copy(destinationPath);
    return p.join('pending_uploads', messageId, '$attachmentId$ext');
  }

  @override
  Future<String> resolveStoredPath(String storedPath) async {
    if (storedPath.startsWith('pending_uploads/') ||
        storedPath.startsWith('pending_uploads\\') ||
        storedPath.startsWith('media/') ||
        storedPath.startsWith('media\\') ||
        storedPath.startsWith('post_media/') ||
        storedPath.startsWith('post_media\\')) {
      return p.join(rootDir.path, storedPath);
    }
    return storedPath;
  }

  @override
  Future<String> localPathForAttachment({
    required String contactPeerId,
    required String blobId,
    required String mime,
  }) async {
    final relativePath = relativePathForAttachment(
      contactPeerId: contactPeerId,
      blobId: blobId,
      mime: mime,
    );
    final absolutePath = p.join(rootDir.path, relativePath);
    final file = File(absolutePath);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    return absolutePath;
  }

  @override
  Future<void> deletePendingUploadDir(String messageId) async {
    deletedPendingUploadDirs.add(messageId);
    final dir = Directory(p.join(rootDir.path, 'pending_uploads', messageId));
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
  }
}

class _ScopedTrackingDurableMediaFileManager
    extends TrackingDurableMediaFileManager {
  _ScopedTrackingDurableMediaFileManager(super.rootDir);

  final List<String> localPathOwnerPeerIds = <String>[];

  @override
  Future<String> localPathForAttachment({
    required String contactPeerId,
    required String blobId,
    required String mime,
  }) {
    localPathOwnerPeerIds.add(contactPeerId);
    return super.localPathForAttachment(
      contactPeerId: contactPeerId,
      blobId: blobId,
      mime: mime,
    );
  }
}

class ThrowingAfterCopyDurableMediaFileManager
    extends TrackingDurableMediaFileManager {
  ThrowingAfterCopyDurableMediaFileManager(super.rootDir);

  @override
  Future<String> copyToDurableStorage({
    required String sourceFilePath,
    required String messageId,
    required String attachmentId,
    required String mime,
  }) async {
    await super.copyToDurableStorage(
      sourceFilePath: sourceFilePath,
      messageId: messageId,
      attachmentId: attachmentId,
      mime: mime,
    );
    throw StateError('simulated durable copy failure');
  }
}

class _DelayedNotFoundGroupRepository extends InMemoryGroupRepository {
  _DelayedNotFoundGroupRepository(this.delay);

  final Duration delay;
  bool _notFoundArmed = false;

  void armNotFound() {
    _notFoundArmed = true;
  }

  @override
  Future<GroupModel?> getGroup(String id) async {
    if (!_notFoundArmed) {
      return super.getGroup(id);
    }
    await Future<void>.delayed(delay);
    return null;
  }
}

class _GatedMembersGroupRepository extends InMemoryGroupRepository {
  String? _heldGroupId;
  Completer<void>? _membersCaptured;
  Completer<void>? _membersRelease;

  void holdNextMembersLookup(String groupId) {
    if (_heldGroupId != null) {
      throw StateError('a members lookup is already held');
    }
    _heldGroupId = groupId;
    _membersCaptured = Completer<void>();
    _membersRelease = Completer<void>();
  }

  bool get membersLookupCaptured => _membersCaptured?.isCompleted ?? false;

  void releaseMembersLookup() {
    final release = _membersRelease;
    if (release != null && !release.isCompleted) {
      release.complete();
    }
  }

  @override
  Future<List<GroupMember>> getMembers(String groupId) async {
    final members = await super.getMembers(groupId);
    if (_heldGroupId == groupId) {
      _heldGroupId = null;
      _membersCaptured!.complete();
      await _membersRelease!.future;
    }
    return members;
  }
}

class CountingGroupMessageRepository extends InMemoryGroupMessageRepository
    implements GroupManualUploadRetryRearmRepository {
  InMemoryMediaAttachmentRepository? manualRearmMediaRepo;
  int getMessagesPageCalls = 0;
  int getMessageCalls = 0;
  int markAsReadCalls = 0;

  @override
  Future<List<GroupMessage>> getMessagesPage(
    String groupId, {
    int limit = 50,
    int offset = 0,
  }) async {
    getMessagesPageCalls++;
    return super.getMessagesPage(groupId, limit: limit, offset: offset);
  }

  @override
  Future<GroupMessage?> getMessage(String id) async {
    getMessageCalls++;
    return super.getMessage(id);
  }

  @override
  Future<void> markAsRead(String groupId) async {
    markAsReadCalls++;
    return super.markAsRead(groupId);
  }

  @override
  Future<bool> rearmUploadRetryForManualRetry({
    required String messageId,
    required List<ManualUploadRetryAttachmentExpectation> attachments,
  }) async {
    final mediaRepo = manualRearmMediaRepo;
    final parent = await super.getMessage(messageId);
    if (mediaRepo == null ||
        parent == null ||
        parent.isIncoming ||
        parent.status != 'failed') {
      return false;
    }
    final persisted = await mediaRepo.getAttachmentsForMessage(
      messageId,
      owner: MediaOwnerLane.group,
    );
    final unfinished = persisted
        .where((attachment) => attachment.downloadStatus != 'done')
        .toList(growable: false);
    if (unfinished.length != attachments.length) return false;
    for (final expected in attachments) {
      final matches = unfinished.where(
        (attachment) =>
            attachment.id == expected.attachmentId &&
            attachment.localPath == expected.storedLocalPath &&
            attachment.downloadStatus == expected.downloadStatus &&
            (attachment.uploadRetryCount ?? 0) == expected.uploadRetryCount,
      );
      if (matches.length != 1) return false;
    }

    await super.saveMessage(
      parent.copyWith(
        status: 'queued_offline',
        wireEnvelope: null,
        inboxRetryPayload: null,
        inboxStored: false,
        retryAttemptCount: 0,
        nextEligibleAt: null,
      ),
    );
    for (final expected in attachments) {
      if (expected.downloadStatus != 'upload_failed') continue;
      final current = unfinished.singleWhere(
        (attachment) => attachment.id == expected.attachmentId,
      );
      await mediaRepo.saveAttachment(
        current.copyWith(downloadStatus: 'upload_pending', uploadRetryCount: 0),
        owner: MediaOwnerLane.group,
      );
    }
    return true;
  }
}

class _WriteCountingGroupMessageRepository
    extends CountingGroupMessageRepository {
  int saveMessageCalls = 0;

  @override
  Future<void> saveMessage(GroupMessage message) {
    saveMessageCalls++;
    return super.saveMessage(message);
  }
}

class _TerminalProjectionGroupMessageRepository
    extends CountingGroupMessageRepository
    implements GroupUploadRetryProjectionRepository {
  _TerminalProjectionGroupMessageRepository({required this.mediaRepo});

  final CountingMediaAttachmentRepository mediaRepo;
  int projectionCalls = 0;
  UploadMediaFailed? lastFailure;

  @override
  Future<UploadRetryProjectionResult> projectUploadFailure({
    required String messageId,
    required String attachmentId,
    required UploadMediaFailed failure,
  }) async {
    projectionCalls++;
    lastFailure = failure;
    if (failure.disposition != UploadMediaDisposition.terminal) {
      throw StateError('P268 fixture expected one terminal upload failure');
    }

    final parent = await super.getMessage(messageId);
    final attachments = await mediaRepo.getAttachmentsForMessage(
      messageId,
      owner: MediaOwnerLane.group,
    );
    final matching = attachments
        .where((attachment) => attachment.id == attachmentId)
        .toList(growable: false);
    if (parent == null ||
        parent.isIncoming ||
        matching.length != 1 ||
        matching.single.downloadStatus != 'upload_pending') {
      throw StateError('P268 terminal projection fixture lost durable state');
    }

    final attachment = matching.single;
    final projectedRetryCount = attachment.uploadRetryCount ?? 0;
    await mediaRepo.saveAttachment(
      attachment.copyWith(
        downloadStatus: 'upload_failed',
        uploadRetryCount: projectedRetryCount,
        ownerLane: MediaOwnerLane.group,
      ),
      owner: MediaOwnerLane.group,
    );
    await super.saveMessage(parent.copyWith(status: 'failed'));
    return UploadRetryProjectionResult(
      state: UploadRetryProjectionState.terminal,
      uploadRetryCount: projectedRetryCount,
    );
  }
}

class SlowInitialPageGroupMessageRepository
    extends CountingGroupMessageRepository {
  final Completer<void> firstPageGate = Completer<void>();

  @override
  Future<List<GroupMessage>> getMessagesPage(
    String groupId, {
    int limit = 50,
    int offset = 0,
  }) async {
    await firstPageGate.future;
    return super.getMessagesPage(groupId, limit: limit, offset: offset);
  }
}

class StaleReloadGroupMessageRepository extends CountingGroupMessageRepository {
  bool _holdNextPage = false;
  Completer<void>? _pageCaptured;
  Completer<void>? _releasePage;

  void holdNextPage() {
    _holdNextPage = true;
    _pageCaptured = Completer<void>();
    _releasePage = Completer<void>();
  }

  Future<void> get pageCaptured => _pageCaptured!.future;

  void releasePage() => _releasePage!.complete();

  @override
  Future<List<GroupMessage>> getMessagesPage(
    String groupId, {
    int limit = 50,
    int offset = 0,
  }) async {
    final snapshot = await super.getMessagesPage(
      groupId,
      limit: limit,
      offset: offset,
    );
    if (_holdNextPage) {
      _holdNextPage = false;
      _pageCaptured!.complete();
      await _releasePage!.future;
    }
    return snapshot;
  }
}

class FailingInitialPageGroupMessageRepository
    extends CountingGroupMessageRepository {
  bool failNextPage = true;

  @override
  Future<List<GroupMessage>> getMessagesPage(
    String groupId, {
    int limit = 50,
    int offset = 0,
  }) async {
    if (failNextPage) {
      failNextPage = false;
      getMessagesPageCalls++;
      throw StateError('simulated initial page failure');
    }

    return super.getMessagesPage(groupId, limit: limit, offset: offset);
  }
}

class CountingMediaAttachmentRepository
    extends InMemoryMediaAttachmentRepository {
  int getAttachmentsForMessagesCalls = 0;
  int getAttachmentsForMessageCalls = 0;

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async {
    getAttachmentsForMessageCalls++;
    return super.getAttachmentsForMessage(messageId, owner: owner);
  }

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds, {
    required MediaOwnerLane owner,
  }) async {
    getAttachmentsForMessagesCalls++;
    return super.getAttachmentsForMessages(messageIds, owner: owner);
  }
}

class _WriteCountingMediaAttachmentRepository
    extends CountingMediaAttachmentRepository {
  int saveAttachmentCalls = 0;

  @override
  Future<void> saveAttachment(
    MediaAttachment attachment, {
    required MediaOwnerLane owner,
  }) {
    saveAttachmentCalls++;
    return super.saveAttachment(attachment, owner: owner);
  }
}

/// Models the production-schema SQLite round trip for the two NOT NULL retry
/// counters: omitted model values are stored and reloaded as database zero.
/// No other attachment field is normalized by this fixture.
class _SqlDefaultingMediaAttachmentRepository
    extends CountingMediaAttachmentRepository {
  @override
  Future<void> saveAttachment(
    MediaAttachment attachment, {
    required MediaOwnerLane owner,
  }) {
    return super.saveAttachment(
      attachment.copyWith(
        uploadRetryCount: attachment.uploadRetryCount ?? 0,
        downloadRetryCount: attachment.downloadRetryCount ?? 0,
      ),
      owner: owner,
    );
  }
}

bool _sameAttachmentAuthorityWithSqlCounterDefaults(
  MediaAttachment current,
  MediaAttachment expected,
) {
  final currentMap = current.toMap()
    ..remove('upload_retry_count')
    ..remove('download_retry_count');
  final expectedMap = expected.toMap()
    ..remove('upload_retry_count')
    ..remove('download_retry_count');
  return jsonEncode(currentMap) == jsonEncode(expectedMap) &&
      (current.uploadRetryCount ?? 0) == (expected.uploadRetryCount ?? 0) &&
      (current.downloadRetryCount ?? 0) == (expected.downloadRetryCount ?? 0);
}

/// Completion/projection fixture for the foreground group-media leaf. It
/// records the exact CAS arguments, applies the Plan 269 local-vs-upload field
/// ownership matrix on success, and consumes retry budget only while the
/// expected pending attachment still owns authority.
class _CompletionAwareGroupMessageRepository
    extends CountingGroupMessageRepository
    implements
        GroupUploadRetryCompletionRepository,
        GroupUploadRetryProjectionRepository {
  _CompletionAwareGroupMessageRepository({required this.mediaRepo});

  final CountingMediaAttachmentRepository mediaRepo;
  Object? completionError;
  bool completionResult = true;
  Future<void> Function(MediaAttachment expectedAttachment)?
  beforeFalseCompletion;

  int completionCalls = 0;
  int projectionCalls = 0;
  int appliedProjectionCalls = 0;
  final List<MediaAttachment> expectedCompletionAttachments = [];
  final List<MediaAttachment> completedCompletionAttachments = [];
  final List<UploadMediaFailed> projectedFailures = [];
  final Map<String, MediaAttachment> _expectedByAttachmentId = {};

  MediaAttachment? expectedFor(String attachmentId) =>
      _expectedByAttachmentId[attachmentId];

  MediaAttachment? completedFor(String attachmentId) {
    for (final attachment in completedCompletionAttachments) {
      if (attachment.id == attachmentId) return attachment;
    }
    return null;
  }

  @override
  Future<bool> completeUploadRetry({
    required GroupMessage expectedParent,
    required MediaAttachment expectedAttachment,
    required MediaAttachment completedAttachment,
  }) async {
    completionCalls++;
    expectedCompletionAttachments.add(expectedAttachment);
    completedCompletionAttachments.add(completedAttachment);
    _expectedByAttachmentId[expectedAttachment.id] = expectedAttachment;

    final error = completionError;
    if (error != null) throw error;
    if (!completionResult) {
      await beforeFalseCompletion?.call(expectedAttachment);
      return false;
    }

    final currentParent = await getMessage(expectedParent.id);
    final currentAttachment = await mediaRepo.getAttachmentById(
      expectedAttachment.id,
    );
    if (currentParent == null ||
        currentParent.id != expectedParent.id ||
        currentParent.groupId != expectedParent.groupId ||
        currentParent.status != expectedParent.status ||
        currentAttachment == null ||
        !_sameAttachmentAuthorityWithSqlCounterDefaults(
          currentAttachment,
          expectedAttachment,
        )) {
      return false;
    }

    await mediaRepo.saveAttachment(
      MediaAttachment(
        id: currentAttachment.id,
        messageId: currentAttachment.messageId,
        mime: completedAttachment.mime,
        size: completedAttachment.size,
        mediaType: completedAttachment.mediaType,
        width: completedAttachment.width,
        height: completedAttachment.height,
        durationMs: completedAttachment.durationMs,
        localPath: completedAttachment.localPath,
        downloadStatus: completedAttachment.downloadStatus,
        createdAt: currentAttachment.createdAt,
        waveform: completedAttachment.waveform,
        uploadRetryCount: currentAttachment.uploadRetryCount ?? 0,
        downloadRetryCount: currentAttachment.downloadRetryCount ?? 0,
        contentHash: completedAttachment.contentHash,
        thumbnailHash: currentAttachment.thumbnailHash,
        encryptionKeyBase64: completedAttachment.encryptionKeyBase64,
        encryptionNonce: completedAttachment.encryptionNonce,
        encryptionScheme: completedAttachment.encryptionScheme,
        ownerLane: currentAttachment.ownerLane,
        isBookmarked: currentAttachment.isBookmarked,
        lastPlaybackPositionMs: currentAttachment.lastPlaybackPositionMs,
      ),
      owner: MediaOwnerLane.group,
    );
    return true;
  }

  @override
  Future<UploadRetryProjectionResult> projectUploadFailure({
    required String messageId,
    required String attachmentId,
    required UploadMediaFailed failure,
  }) async {
    projectionCalls++;
    projectedFailures.add(failure);
    final expected = _expectedByAttachmentId[attachmentId];
    final current = await mediaRepo.getAttachmentById(attachmentId);
    final parent = await getMessage(messageId);
    if (expected == null ||
        current == null ||
        parent == null ||
        current.downloadStatus != 'upload_pending' ||
        !_sameAttachmentAuthorityWithSqlCounterDefaults(current, expected)) {
      return const UploadRetryProjectionResult.notApplied();
    }

    final nextRetryCount = (current.uploadRetryCount ?? 0) + 1;
    final terminal = nextRetryCount >= kMaxUploadRetries;
    await mediaRepo.saveAttachment(
      current.copyWith(
        downloadStatus: terminal ? 'upload_failed' : 'upload_pending',
        uploadRetryCount: nextRetryCount,
        ownerLane: MediaOwnerLane.group,
      ),
      owner: MediaOwnerLane.group,
    );
    await saveMessage(
      parent.copyWith(status: terminal ? 'failed' : 'queued_offline'),
    );
    appliedProjectionCalls++;
    return UploadRetryProjectionResult(
      state: terminal
          ? UploadRetryProjectionState.terminal
          : UploadRetryProjectionState.retryPending,
      uploadRetryCount: nextRetryCount,
    );
  }
}

class GateNthExactMediaReadRepository
    extends CountingMediaAttachmentRepository {
  int exactReadCalls = 0;
  int? _gateAtCall;
  Completer<void>? _captured;
  Completer<void>? _release;

  void gateAfterExactReads(int additionalReads) {
    if (additionalReads <= 0 || _gateAtCall != null) {
      throw StateError('invalid or already-armed exact-read gate');
    }
    _gateAtCall = exactReadCalls + additionalReads;
    _captured = Completer<void>();
    _release = Completer<void>();
  }

  Future<void> get captured => _captured!.future;
  bool get hasCaptured => _captured?.isCompleted ?? false;

  void release() {
    final completer = _release;
    if (completer == null || completer.isCompleted) return;
    completer.complete();
  }

  @override
  Future<MediaAttachment?> getAttachmentById(String id) async {
    exactReadCalls++;
    if (exactReadCalls == _gateAtCall) {
      _captured!.complete();
      await _release!.future;
      _gateAtCall = null;
    }
    return super.getAttachmentById(id);
  }
}

class KnownClearGroupMessageRepository extends CountingGroupMessageRepository
    implements GroupMessageLocalDeletionAuthority {
  @override
  Future<GroupMessageLocalDeletionState> getGroupMessageLocalDeletionState(
    String messageId,
  ) async => GroupMessageLocalDeletionState.knownClear;
}

/// Deliberately returns a mixed/corrupt result for an owner-scoped group read.
/// The viewer boundary must still qualify each current item instead of
/// laundering every sibling through one parent-wide eligible decision.
class MixedViewerMediaAttachmentRepository
    extends CountingMediaAttachmentRepository {
  MixedViewerMediaAttachmentRepository({
    required this.parentMessageId,
    required this.rows,
  });

  final String parentMessageId;
  final List<MediaAttachment> rows;

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async {
    getAttachmentsForMessageCalls++;
    return messageId == parentMessageId
        ? List<MediaAttachment>.of(rows)
        : const <MediaAttachment>[];
  }

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds, {
    required MediaOwnerLane owner,
  }) async {
    getAttachmentsForMessagesCalls++;
    return messageIds.contains(parentMessageId)
        ? <String, List<MediaAttachment>>{
            parentMessageId: List<MediaAttachment>.of(rows),
          }
        : const <String, List<MediaAttachment>>{};
  }
}

class GateFirstSingleMediaReadRepository
    extends CountingMediaAttachmentRepository {
  final Completer<void> firstReadCaptured = Completer<void>();
  final Completer<void> releaseFirstRead = Completer<void>();
  bool armed = false;
  bool _gated = false;

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async {
    final snapshot = await super.getAttachmentsForMessage(
      messageId,
      owner: owner,
    );
    if (armed && !_gated) {
      _gated = true;
      firstReadCaptured.complete();
      await releaseFirstRead.future;
    }
    return snapshot;
  }
}

class _GateForwardCanonicalValidatorFileManager extends FakeMediaFileManager {
  final Completer<void> captured = Completer<void>();
  final Completer<void> release = Completer<void>();
  bool armed = false;
  bool _gated = false;

  @override
  Future<String> trustedMediaRootPath() async {
    final root = await super.trustedMediaRootPath();
    if (armed && !_gated) {
      _gated = true;
      captured.complete();
      await release.future;
    }
    return root;
  }
}

/// Holds exactly one explicitly armed current-contact read. Plan 247 uses this
/// to prove that the bubble has already left the route before the fresh
/// dispatch decision can show feedback or invoke the direct-route opener.
class GateNextContactReadRepository extends InMemoryContactRepository {
  Completer<void>? _captured;
  Completer<void>? _release;
  bool _gateNext = false;

  void gateNextRead() {
    if (_gateNext) throw StateError('a contact-read gate is already armed');
    _gateNext = true;
    _captured = Completer<void>();
    _release = Completer<void>();
  }

  bool get hasCapturedNextRead => _captured?.isCompleted ?? false;

  void releaseNextRead() {
    final release = _release;
    if (release == null || release.isCompleted) {
      throw StateError('no pending contact-read gate');
    }
    release.complete();
  }

  @override
  Future<ContactModel?> getContact(String peerId) async {
    final current = await super.getContact(peerId);
    if (_gateNext) {
      _gateNext = false;
      _captured!.complete();
      await _release!.future;
    }
    return current;
  }
}

class _InMemoryInviteDeliveryAttemptRepository
    implements GroupInviteDeliveryAttemptRepository {
  final Map<String, GroupInviteDeliveryAttempt> _attempts = {};

  String _key(String groupId, String peerId) => '$groupId::$peerId';

  @override
  Future<void> saveAttempt(GroupInviteDeliveryAttempt attempt) async {
    _attempts[_key(attempt.groupId, attempt.peerId)] = attempt;
  }

  @override
  Future<GroupInviteDeliveryAttempt?> getAttempt({
    required String groupId,
    required String peerId,
  }) async => _attempts[_key(groupId, peerId)];

  @override
  Future<List<GroupInviteDeliveryAttempt>> getAttemptsForGroup(
    String groupId,
  ) async => _attempts.values
      .where((attempt) => attempt.groupId == groupId)
      .toList(growable: false);

  @override
  Future<GroupInviteDeliveryStatus> getStatusForMember({
    required String groupId,
    required String peerId,
  }) async =>
      _attempts[_key(groupId, peerId)]?.status ??
      GroupInviteDeliveryStatus.unknown;

  @override
  Future<Map<String, GroupInviteDeliveryStatus>> getStatusesForGroupMembers(
    String groupId,
  ) async => {
    for (final attempt in _attempts.values.where(
      (attempt) => attempt.groupId == groupId,
    ))
      attempt.peerId: attempt.status,
  };

  @override
  Future<void> updateStatus({
    required String groupId,
    required String peerId,
    required GroupInviteDeliveryStatus status,
    DateTime? updatedAt,
  }) async {
    final now = (updatedAt ?? DateTime.now()).toUtc();
    final key = _key(groupId, peerId);
    final existing = _attempts[key];
    _attempts[key] = existing == null
        ? GroupInviteDeliveryAttempt(
            groupId: groupId,
            peerId: peerId,
            status: status,
            attemptedAt: now,
            updatedAt: now,
          )
        : existing.copyWith(status: status, updatedAt: now);
  }

  @override
  Future<void> markJoined({
    required String groupId,
    required String peerId,
    String? username,
    DateTime? joinedAt,
  }) async {
    final now = (joinedAt ?? DateTime.now()).toUtc();
    final key = _key(groupId, peerId);
    final existing = _attempts[key];
    _attempts[key] = existing == null
        ? GroupInviteDeliveryAttempt(
            groupId: groupId,
            peerId: peerId,
            username: username,
            status: GroupInviteDeliveryStatus.joined,
            attemptedAt: now,
            updatedAt: now,
          )
        : existing.copyWith(
            username: username,
            status: GroupInviteDeliveryStatus.joined,
            updatedAt: now,
            clearLastError: true,
          );
  }

  @override
  Future<void> markRevoked({
    required String groupId,
    required String peerId,
    DateTime? revokedAt,
  }) async {
    final now = (revokedAt ?? DateTime.now()).toUtc();
    final key = _key(groupId, peerId);
    final existing = _attempts[key];
    _attempts[key] = existing == null
        ? GroupInviteDeliveryAttempt(
            groupId: groupId,
            peerId: peerId,
            status: GroupInviteDeliveryStatus.revoked,
            attemptedAt: now,
            updatedAt: now,
          )
        : existing.copyWith(
            status: GroupInviteDeliveryStatus.revoked,
            updatedAt: now,
            clearLastError: true,
          );
  }

  @override
  Future<void> markDeclined({
    required String groupId,
    required String peerId,
    DateTime? declinedAt,
  }) async {
    final now = (declinedAt ?? DateTime.now()).toUtc();
    final key = _key(groupId, peerId);
    final existing = _attempts[key];
    if (existing?.status == GroupInviteDeliveryStatus.joined) {
      return;
    }
    _attempts[key] = existing == null
        ? GroupInviteDeliveryAttempt(
            groupId: groupId,
            peerId: peerId,
            status: GroupInviteDeliveryStatus.declined,
            attemptedAt: now,
            updatedAt: now,
          )
        : existing.copyWith(
            status: GroupInviteDeliveryStatus.declined,
            updatedAt: now,
            clearLastError: true,
          );
  }

  @override
  Future<int> deleteAttempt({
    required String groupId,
    required String peerId,
  }) async => _attempts.remove(_key(groupId, peerId)) == null ? 0 : 1;

  @override
  Future<int> deleteAttemptsForGroup(String groupId) async {
    final keys = _attempts.keys
        .where((key) => key.startsWith('$groupId::'))
        .toList(growable: false);
    for (final key in keys) {
      _attempts.remove(key);
    }
    return keys.length;
  }
}

class ThrowingSaveReactionRepository extends FakeReactionRepository {
  @override
  Future<void> saveReaction(MessageReaction reaction) async {
    throw StateError('simulated reaction save failure');
  }
}

// --- Test data ---

final testIdentity = IdentityModel(
  peerId: 'peer-admin',
  publicKey: 'pk-admin',
  privateKey: 'sk-admin',
  mnemonic12:
      'word1 word2 word3 word4 word5 word6 word7 word8 word9 word10 word11 word12',
  mlKemPublicKey: 'mlkem-pk-admin',
  username: 'Admin',
  createdAt: DateTime.now().toUtc().toIso8601String(),
  updatedAt: DateTime.now().toUtc().toIso8601String(),
);

GroupModel makeChatGroup({GroupRole role = GroupRole.admin}) => GroupModel(
  id: 'group-1',
  name: 'Test Group',
  type: GroupType.chat,
  topicName: 'topic-1',
  description: 'A test group',
  createdAt: DateTime.now().toUtc(),
  createdBy: 'peer-admin',
  myRole: role,
);

GroupModel makeAnnouncementGroup({GroupRole role = GroupRole.admin}) =>
    GroupModel(
      id: 'group-1',
      name: 'Announce Group',
      type: GroupType.announcement,
      topicName: 'topic-1',
      description: 'Announcement',
      createdAt: DateTime.now().toUtc(),
      createdBy: 'peer-admin',
      myRole: role,
    );

Future<void> saveActiveGroupMembers(
  InMemoryGroupRepository groupRepo,
  GroupModel group,
) async {
  await groupRepo.saveMember(
    GroupMember(
      groupId: group.id,
      peerId: testIdentity.peerId,
      username: testIdentity.username,
      role: group.myRole == GroupRole.admin
          ? MemberRole.admin
          : MemberRole.writer,
      publicKey: testIdentity.publicKey,
      mlKemPublicKey: testIdentity.mlKemPublicKey,
      joinedAt: DateTime.utc(2026, 5, 1, 10),
    ),
  );
  await groupRepo.saveMember(
    GroupMember(
      groupId: group.id,
      peerId: 'peer-bob',
      username: 'Bob',
      role: MemberRole.writer,
      publicKey: 'pk-peer-bob',
      mlKemPublicKey: 'mlkem-peer-bob',
      joinedAt: DateTime.utc(2026, 5, 1, 10, 1),
    ),
  );
}

GroupMessage makeMessage({
  required String id,
  required String text,
  String groupId = 'group-1',
  bool isIncoming = true,
  String senderPeerId = 'peer-alice',
  String senderUsername = 'Alice',
  String? quotedMessageId,
  String status = 'sent',
  List<MediaAttachment> media = const [],
  GroupPrivateMediaPolicy privateMediaPolicy =
      const GroupPrivateMediaPolicy.ordinary(),
  String? wireEnvelope,
  String? inboxRetryPayload,
  DateTime? timestamp,
}) => GroupMessage(
  id: id,
  groupId: groupId,
  senderPeerId: senderPeerId,
  senderUsername: senderUsername,
  text: text,
  quotedMessageId: quotedMessageId,
  timestamp: timestamp ?? DateTime.now().toUtc(),
  status: status,
  isIncoming: isIncoming,
  createdAt: timestamp ?? DateTime.now().toUtc(),
  media: media,
  privateMediaPolicy: privateMediaPolicy,
  wireEnvelope: wireEnvelope,
  inboxRetryPayload: inboxRetryPayload,
);

// --- Helpers ---

/// Pump enough frames for async operations to complete.
/// AmbientBackground has an infinite animation, so pumpAndSettle will timeout.
Future<void> pumpFrames(WidgetTester tester, {int count = 10}) async {
  for (var i = 0; i < count; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> pumpUntil(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 40,
}) async {
  var pumps = 0;
  while (!condition() && pumps < maxPumps) {
    await tester.pump(const Duration(milliseconds: 50));
    pumps++;
  }
}

Future<void> pumpUntilAsync(
  WidgetTester tester,
  Future<bool> Function() condition, {
  int maxPumps = 40,
}) async {
  var pumps = 0;
  while (!(await condition()) && pumps < maxPumps) {
    await tester.pump(const Duration(milliseconds: 50));
    pumps++;
  }
}

Future<void> pumpUntilAsyncWorkSettles(
  WidgetTester tester,
  bool Function() condition, {
  int maxPumps = 200,
}) async {
  var pumps = 0;
  while (!condition() && pumps < maxPumps) {
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    });
    await tester.pump(const Duration(milliseconds: 50));
    pumps++;
  }
}

Future<void> pumpUntilFuturesComplete(
  WidgetTester tester,
  Iterable<Future<void>> futures, {
  int maxPumps = 200,
}) async {
  var completed = false;
  Object? completionError;
  StackTrace? completionStack;
  unawaited(
    Future.wait<void>(futures).then(
      (_) => completed = true,
      onError: (Object error, StackTrace stack) {
        completionError = error;
        completionStack = stack;
        completed = true;
      },
    ),
  );
  await pumpUntilAsyncWorkSettles(tester, () => completed, maxPumps: maxPumps);
  if (!completed) {
    throw TimeoutException('async test work did not complete');
  }
  if (completionError != null) {
    Error.throwWithStackTrace(completionError!, completionStack!);
  }
}

class StartedScreenSend {
  const StartedScreenSend(this.future);

  final Future<void> future;
}

Future<StartedScreenSend> startScreenSend(
  WidgetTester tester,
  String text, {
  Duration delay = const Duration(milliseconds: 200),
}) async {
  final screen = tester.widget<GroupConversationScreen>(
    find.byType(GroupConversationScreen),
  );
  final send = screen.onSend as Future<void> Function(String);
  late Future<void> sendFuture;
  await tester.runAsync(() async {
    sendFuture = send(text);
    await Future<void>.delayed(delay);
  });
  await tester.pump();
  return StartedScreenSend(sendFuture);
}

List<Map<String, dynamic>> groupPublishPayloads(FakeBridge bridge) {
  return bridge.sentMessages
      .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
      .where((message) => message['cmd'] == 'group:publish')
      .map(
        (message) => (message['payload'] as Map<String, dynamic>)
            .cast<String, dynamic>(),
      )
      .toList();
}

Map<String, dynamic> groupPublishPayloadForMessage(
  FakeBridge bridge,
  String messageId,
) {
  return groupPublishPayloads(
    bridge,
  ).singleWhere((payload) => payload['messageId'] == messageId);
}

String groupTextRetryPayload({
  required String groupId,
  required String senderPeerId,
  required String senderUsername,
  required String messageId,
  required String text,
  required String timestamp,
  String? quotedMessageId,
}) {
  return jsonEncode({
    'groupId': groupId,
    'message': jsonEncode({
      'groupId': groupId,
      'senderId': senderPeerId,
      'senderUsername': senderUsername,
      'keyEpoch': 0,
      'text': text,
      'timestamp': timestamp,
      'messageId': messageId,
      'quotedMessageId': ?quotedMessageId,
      'media': const <Object>[],
    }),
  });
}

Map<String, dynamic> groupSendReliablePayloadForMessage(
  FakeBridge bridge,
  String messageId,
) {
  for (final raw in bridge.sentMessages.reversed) {
    final parsed = jsonDecode(raw) as Map<String, dynamic>;
    if (parsed['cmd'] != 'group:sendReliable') continue;
    final payload = (parsed['payload'] as Map).cast<String, dynamic>();
    if (payload['messageId'] == messageId) return payload;
  }
  fail('missing group:sendReliable for $messageId');
}

Map<String, dynamic> groupInboxStorePayloadForMessage(
  FakeBridge bridge,
  String messageId,
) {
  for (final raw in bridge.sentMessages.reversed) {
    final parsed = jsonDecode(raw) as Map<String, dynamic>;
    if (parsed['cmd'] != 'group:inboxStore') continue;
    final payload = (parsed['payload'] as Map).cast<String, dynamic>();
    final envelope = jsonDecode(payload['message'] as String) as Map;
    if (envelope['messageId'] == messageId) return payload;
  }
  fail('missing group:inboxStore for $messageId');
}

Map<String, dynamic> groupReplayPlaintextForMessage(
  FakeBridge bridge,
  String messageId,
) {
  final inboxPayload = groupInboxStorePayloadForMessage(bridge, messageId);
  final envelope = jsonDecode(inboxPayload['message'] as String) as Map;
  return (jsonDecode(envelope['ciphertext'] as String) as Map)
      .cast<String, dynamic>();
}

void expectNoGroupPrivateWireKeys(
  Iterable<({String boundary, Map<String, dynamic> payload})> payloads,
) {
  for (final entry in payloads) {
    for (final key in GroupPrivateMediaPolicy.wireKeys) {
      expect(
        entry.payload,
        isNot(contains(key)),
        reason: '${entry.boundary} must omit ordinary policy key $key',
      );
    }
  }
}

Future<bool> commitProtectedIfGroupSelectorExists(WidgetTester tester) async {
  final selector = find.byKey(const ValueKey('group-private-media-selector'));
  if (selector.evaluate().isEmpty) return false;

  await tester.ensureVisible(selector);
  await tester.tap(selector);
  await pumpFrames(tester, count: 6);
  final sheet = find.byKey(const ValueKey('private-media-policy-sheet'));
  expect(sheet, findsOneWidget);
  final sheetScrollable = find.descendant(
    of: sheet,
    matching: find.byType(Scrollable),
  );
  final protectedOption = find.byKey(
    const ValueKey('group-private-media-option-protected'),
  );
  await tester.scrollUntilVisible(
    protectedOption,
    200,
    scrollable: sheetScrollable,
  );
  await tester.pump();
  await tester.tap(protectedOption);
  await tester.pump();
  final commit = find.byKey(const ValueKey('private-media-use-mode'));
  await tester.scrollUntilVisible(commit, 200, scrollable: sheetScrollable);
  await tester.tap(commit);
  await pumpFrames(tester, count: 8);
  return true;
}

MediaAttachment successfulGroupUploadFixture({
  required String blobId,
  required String mime,
  required String localFilePath,
}) {
  return MediaAttachment(
    id: blobId,
    messageId: '',
    mime: mime,
    size: 1,
    mediaType: MediaAttachment.mediaTypeFromMime(mime),
    localPath: localFilePath,
    downloadStatus: 'done',
    contentHash: _validContentHash,
    encryptionKeyBase64: 'key-$blobId',
    encryptionNonce: 'nonce-$blobId',
    encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
    createdAt: DateTime.now().toUtc().toIso8601String(),
  );
}

/// Ceiling for "the upload actually started" waits.
///
/// Upload start is signalled by a `Completer`, so every wait below is already
/// event-driven and this value is a HANG ceiling, not a latency assertion: a
/// passing run completes in milliseconds regardless of the number here. The
/// four voice tests that used a 10s ceiling were the only ones to fail in a
/// batched `host-all` (four suites in parallel), while their 30s siblings
/// passed — the work being awaited is a real file copy plus SQLite writes, so
/// the ceiling was racing host load rather than proving anything. One generous
/// shared constant keeps the proof event-driven and machine-speed independent.
const _uploadStartCeiling = Duration(seconds: 60);

void main() {
  group('GroupConversationWired', () {
    late InMemoryGroupRepository groupRepo;
    late CountingGroupMessageRepository msgRepo;
    late CountingMediaAttachmentRepository mediaAttachmentRepo;
    late InMemoryContactRepository contactRepo;
    late FakeBridge bridge;
    late FakeIdentityRepository identityRepo;
    late FakeP2PService p2pService;
    late StreamController<GroupMessage> messageStreamController;
    late FakeUploadWakeLockDriver wakeLockDriver;

    setUp(() async {
      // Voice bubbles construct an AudioPlayer() in initState; route just_audio
      // to a no-op platform so the host test doesn't hit MissingPluginException
      // on the com.ryanheise.just_audio.methods channel (GMAR-004 reopen).
      installFakeJustAudioPlatform();
      groupRepo = InMemoryGroupRepository();
      msgRepo = CountingGroupMessageRepository();
      mediaAttachmentRepo = CountingMediaAttachmentRepository();
      msgRepo.manualRearmMediaRepo = mediaAttachmentRepo;
      contactRepo = InMemoryContactRepository();
      bridge = FakeBridge(
        initialResponses: {
          'group:publish': {'ok': true, 'messageId': 'msg-published'},
        },
      );
      identityRepo = FakeIdentityRepository(identity: testIdentity);
      // 210 preservation: the ~167 existing sends assume a reachable relay (a
      // tick, no offline affordance). The bare FakeP2PService() is
      // relayReady==false; pin it ONLINE here so ONLY the dedicated offline
      // tests below (which build their own offline FakeP2PService) exercise the
      // new `!relayReady` queued-offline branch.
      p2pService = FakeP2PService(
        initialState: const NodeState(
          isStarted: true,
          peerId: 'me',
          relayState: 'online',
        ),
      );
      messageStreamController = StreamController<GroupMessage>.broadcast();
      wakeLockDriver = FakeUploadWakeLockDriver();
      UploadWakeLockController.debugReset(driver: wakeLockDriver);
      groupRecoveryGate.resetForTest();
      setGroupExitIntentAccessSinks(
        forGroup: (_) async => null,
        all: () async => const <GroupExitIntent>[],
      );
      setGroupExitIntentActionSinks();
      setGroupExitDiagnosticAccessSink();
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: 'group-1',
          keyGeneration: 1,
          encryptedKey: 'test-group-key-1',
          createdAt: DateTime.now().toUtc(),
        ),
      );
    });

    tearDown(() {
      messageStreamController.close();
      UploadWakeLockController.debugReset(driver: FakeUploadWakeLockDriver());
      groupRecoveryGate.resetForTest();
      setGroupExitIntentAccessSinks();
      setGroupExitIntentActionSinks();
      setGroupExitDiagnosticAccessSink();
    });

    Widget buildWidget({
      GroupModel? group,
      CountingMediaAttachmentRepository? mediaRepo,
      ImageProcessor? imageProcessor,
      FakeAudioRecorderService? audioRecorderService,
      MicPermissionGateway? micPermissionGateway,
      MediaPicker? mediaPicker,
      MediaFileManager? mediaFileManager,
      LegacyTestUploadMediaFn? uploadMediaFn,
      List<File>? initialAttachments,
      List<PendingComposerMedia>? initialPendingMedia,
      String? initialText,
      String? initialHighlightedMessageId,
      ImageQualityPreference qualityPreference =
          ImageQualityPreference.compressed,
      ImageQualityPreference videoQualityPreference =
          ImageQualityPreference.compressed,
      int maxAttachmentBudgetBytes = kGeneralMediaAttachmentBudgetBytes,
      ReactionRepository? reactionRepo,
      FakeGroupReactionReplayOutboxRepository? reactionReplayOutboxRepo,
      StreamController<ReactionChange>? reactionStreamController,
      StreamController<String>? removedStreamController,
      ActiveConversationTracker? groupConversationTracker,
      CountingGroupMessageRepository? messageRepo,
      GroupInviteDeliveryAttemptRepository? inviteDeliveryAttemptRepo,
      MediaAutoDownloadDecider? autoDownloadDecider,
      GroupMediaDownloadCoordinator? groupMediaDownloadCoordinator,
      GroupReceivedMediaActionsController? mediaActionsController,
      GroupMediaDeleteForMeCoordinator? mediaDeleteForMeCoordinator,
      Future<void> Function(BuildContext, GroupMediaForwardRequest)?
      groupMediaForwardLauncher,
      MessageRepository? forwardMessageRepository,
      ChatMessageListener? forwardChatMessageListener,
      OpenAnnouncementSenderConversation? openAnnouncementSenderConversation,
      GroupPrivateMediaAvailability privateMediaAvailability =
          productionGroupPrivateMediaAvailability,
    }) {
      final g = group ?? makeChatGroup();
      final effectiveMsgRepo = messageRepo ?? msgRepo;
      return MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: GroupConversationWired(
          group: g,
          groupRepo: groupRepo,
          msgRepo: effectiveMsgRepo,
          groupMessageListener: FakeGroupMessageListener(
            messageStreamController.stream,
            reactionStream: reactionStreamController?.stream,
            removedStream: removedStreamController?.stream,
          ),
          bridge: bridge,
          identityRepo: identityRepo,
          contactRepo: contactRepo,
          p2pService: p2pService,
          mediaAttachmentRepo: mediaRepo,
          mediaFileManager: mediaFileManager,
          imageProcessor: imageProcessor,
          audioRecorderService: audioRecorderService,
          micPermissionGateway:
              micPermissionGateway ?? FakeMicPermissionGateway(),
          mediaPicker: mediaPicker,
          qualityPreference: qualityPreference,
          videoQualityPreference: videoQualityPreference,
          uploadMediaFn: uploadMediaFn == null
              ? uploadMedia
              : adaptLegacyTestUploadMediaFn(uploadMediaFn),
          privateMediaAvailability: privateMediaAvailability,
          initialAttachments: initialAttachments,
          initialPendingMedia: initialPendingMedia,
          initialText: initialText,
          initialHighlightedMessageId: initialHighlightedMessageId,
          maxAttachmentBudgetBytes: maxAttachmentBudgetBytes,
          reactionRepo: reactionRepo,
          groupReactionReplayOutboxRepository: reactionReplayOutboxRepo,
          groupConversationTracker: groupConversationTracker,
          inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
          autoDownloadDecider: autoDownloadDecider,
          groupMediaDownloadCoordinator: groupMediaDownloadCoordinator,
          mediaActionsController: mediaActionsController,
          mediaDeleteForMeCoordinator: mediaDeleteForMeCoordinator,
          groupMediaForwardLauncher: groupMediaForwardLauncher,
          forwardMessageRepository: forwardMessageRepository,
          forwardChatMessageListener: forwardChatMessageListener,
          openAnnouncementSenderConversation:
              openAnnouncementSenderConversation,
        ),
      );
    }

    testWidgets(
      'P269 ordinary and voice empty ACL preflight preserves sources with zero durable or crypto effects',
      (tester) async {
        mediaUploadInFlightTracker.clearAll();
        addTearDown(mediaUploadInFlightTracker.clearAll);
        final flowEvents = <Map<String, dynamic>>[];
        debugSetFlowEventSink(flowEvents.add);
        addTearDown(() => debugSetFlowEventSink(null));

        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        final revokedAt = DateTime.utc(2026, 7, 22, 10);
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: testIdentity.peerId,
            username: testIdentity.username,
            role: MemberRole.admin,
            publicKey: testIdentity.publicKey,
            mlKemPublicKey: testIdentity.mlKemPublicKey,
            devices: <GroupMemberDeviceIdentity>[
              GroupMemberDeviceIdentity(
                deviceId: 'device-admin-revoked',
                transportPeerId: 'transport-admin-revoked',
                deviceSigningPublicKey: 'signing-admin-revoked',
                status: GroupMemberDeviceStatus.revoked,
                revokedAt: revokedAt,
              ),
            ],
            joinedAt: DateTime.utc(2026, 5, 1, 10),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: 'peer-bob',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-peer-bob',
            mlKemPublicKey: 'mlkem-peer-bob',
            devices: <GroupMemberDeviceIdentity>[
              GroupMemberDeviceIdentity(
                deviceId: 'device-bob-revoked',
                transportPeerId: 'transport-bob-revoked',
                deviceSigningPublicKey: 'signing-bob-revoked',
                status: GroupMemberDeviceStatus.revoked,
                revokedAt: revokedAt,
              ),
            ],
            joinedAt: DateTime.utc(2026, 5, 1, 10, 1),
          ),
        );

        final tempDir = Directory.systemTemp.createTempSync(
          'p269-empty-group-media-acl-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });

        final ordinarySource = File(p.join(tempDir.path, 'ordinary.jpg'))
          ..writeAsBytesSync(validJpegFixtureBytes);
        final ordinarySourceBytes = ordinarySource.readAsBytesSync();
        final ordinaryMessageRepo = _WriteCountingGroupMessageRepository();
        final ordinaryMediaRepo = CountingMediaAttachmentRepository();
        var ordinaryAttachmentSaveCalls = 0;
        ordinaryMediaRepo.onSaveAttachment = (_) {
          ordinaryAttachmentSaveCalls++;
        };
        final ordinaryFileManager = TrackingDurableMediaFileManager(tempDir);

        await tester.pumpWidget(
          buildWidget(
            group: group,
            messageRepo: ordinaryMessageRepo,
            mediaRepo: ordinaryMediaRepo,
            mediaFileManager: ordinaryFileManager,
            initialAttachments: <File>[ordinarySource],
          ),
        );
        await pumpFrames(tester, count: 20);

        final ordinarySend = await startScreenSend(tester, '');
        await tester.runAsync(() => ordinarySend.future);
        await pumpFrames(tester, count: 20);

        final ordinarySourceRetained = ordinarySource.existsSync();
        final ordinarySourceUnchanged =
            ordinarySourceRetained &&
            base64Encode(ordinarySource.readAsBytesSync()) ==
                base64Encode(ordinarySourceBytes);
        final ordinaryPendingComposerMedia = tester
            .widget<GroupConversationScreen>(
              find.byType(GroupConversationScreen),
            )
            .composerStateListenable!
            .value
            .pendingAttachments
            .length;
        final ordinaryCryptoOrUploadCommands = bridge.commandLog
            .where(
              const <String>{
                'blob:keygen',
                'blob:encrypt',
                'media:upload',
              }.contains,
            )
            .toList(growable: false);

        await tester.pumpWidget(const SizedBox.shrink());
        await pumpFrames(tester, count: 5);

        bridge = FakeBridge(
          initialResponses: {
            'group:publish': {'ok': true, 'messageId': 'msg-published'},
          },
        );
        final voiceSource = File(p.join(tempDir.path, 'voice.m4a'))
          ..writeAsStringSync('p269 empty ACL voice bytes');
        final voiceSourceBytes = voiceSource.readAsBytesSync();
        final voiceRecorder = FakeAudioRecorderService()
          ..fakeDurationMs = 3200
          ..fakeSizeBytes = voiceSource.lengthSync()
          ..fakeOutputPath = voiceSource.path;
        final voiceMessageRepo = _WriteCountingGroupMessageRepository();
        final voiceMediaRepo = CountingMediaAttachmentRepository();
        var voiceAttachmentSaveCalls = 0;
        voiceMediaRepo.onSaveAttachment = (_) {
          voiceAttachmentSaveCalls++;
        };
        final voiceFileManager = TrackingDurableMediaFileManager(tempDir);

        await tester.pumpWidget(
          buildWidget(
            group: group,
            messageRepo: voiceMessageRepo,
            mediaRepo: voiceMediaRepo,
            mediaFileManager: voiceFileManager,
            audioRecorderService: voiceRecorder,
          ),
        );
        await pumpFrames(tester, count: 20);

        final voiceScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        await (voiceScreen.onRecordStart! as Future<void> Function())();
        await pumpUntil(
          tester,
          () => find.byIcon(Icons.stop_rounded).evaluate().isNotEmpty,
        );
        voiceRecorder.emitAmplitude(0.2);
        voiceRecorder.emitAmplitude(0.6);
        voiceRecorder.emitAmplitude(0.3);
        final recordingScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        await tester.runAsync(
          () => (recordingScreen.onRecordStop! as Future<void> Function())(),
        );
        await pumpFrames(tester, count: 20);

        final voiceSourceRetained = voiceSource.existsSync();
        final voiceSourceUnchanged =
            voiceSourceRetained &&
            base64Encode(voiceSource.readAsBytesSync()) ==
                base64Encode(voiceSourceBytes);
        final voiceCryptoOrUploadCommands = bridge.commandLog
            .where(
              const <String>{
                'blob:keygen',
                'blob:encrypt',
                'media:upload',
              }.contains,
            )
            .toList(growable: false);
        final typedAclFailures = flowEvents
            .where(
              (event) =>
                  event['event'] ==
                  'GROUP_CONV_FL_MEDIA_ACL_PREFLIGHT_REJECTED',
            )
            .map((event) {
              final details = event['details'] as Map<String, dynamic>;
              return <String, Object?>{
                'surface': details['surface'],
                'stage': details['stage'],
                'disposition': details['disposition'],
                'errorCode': details['errorCode'],
              };
            })
            .toList(growable: false);

        expect(
          <String, Object>{
            'ordinary source retained': ordinarySourceRetained,
            'ordinary source unchanged': ordinarySourceUnchanged,
            'ordinary durable copies': ordinaryFileManager.copyCalls,
            'ordinary durable cleanup calls':
                ordinaryFileManager.deletedPendingUploadDirs.length,
            'ordinary parent saves': ordinaryMessageRepo.saveMessageCalls,
            'ordinary attachment saves': ordinaryAttachmentSaveCalls,
            'ordinary pending composer media': ordinaryPendingComposerMedia,
            'ordinary crypto/upload commands': ordinaryCryptoOrUploadCommands,
            'voice source retained': voiceSourceRetained,
            'voice source unchanged': voiceSourceUnchanged,
            'voice durable copies': voiceFileManager.copyCalls,
            'voice durable cleanup calls':
                voiceFileManager.deletedPendingUploadDirs.length,
            'voice parent saves': voiceMessageRepo.saveMessageCalls,
            'voice attachment saves': voiceAttachmentSaveCalls,
            'voice crypto/upload commands': voiceCryptoOrUploadCommands,
            'typed ACL failures': typedAclFailures,
          },
          equals(<String, Object>{
            'ordinary source retained': true,
            'ordinary source unchanged': true,
            'ordinary durable copies': 0,
            'ordinary durable cleanup calls': 0,
            'ordinary parent saves': 0,
            'ordinary attachment saves': 0,
            'ordinary pending composer media': 1,
            'ordinary crypto/upload commands': const <String>[],
            'voice source retained': true,
            'voice source unchanged': true,
            'voice durable copies': 0,
            'voice durable cleanup calls': 0,
            'voice parent saves': 0,
            'voice attachment saves': 0,
            'voice crypto/upload commands': const <String>[],
            'typed ACL failures': const <Map<String, Object?>>[
              <String, Object?>{
                'surface': 'ordinary',
                'stage': 'validation',
                'disposition': 'terminal',
                'errorCode': 'EMPTY_GROUP_MEDIA_ACL',
              },
              <String, Object?>{
                'surface': 'voice',
                'stage': 'validation',
                'disposition': 'terminal',
                'errorCode': 'EMPTY_GROUP_MEDIA_ACL',
              },
            ],
          }),
        );
      },
    );

    testWidgets(
      'P269 ordinary foreground media survives database-defaulted retry counters and reaches exact completion once',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);

        final tempDir = Directory.systemTemp.createTempSync(
          'p269-ordinary-sql-defaults-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final jpeg = File(p.join(tempDir.path, 'ordinary.jpg'))
          ..writeAsBytesSync(validJpegFixtureBytes);
        final video = File(p.join(tempDir.path, 'ordinary.mp4'))
          ..writeAsBytesSync(_tinyMp4Bytes);
        final sqlDefaultMediaRepo = _SqlDefaultingMediaAttachmentRepository();
        final completionRepo = _CompletionAwareGroupMessageRepository(
          mediaRepo: sqlDefaultMediaRepo,
        );
        final fileManager = TrackingDurableMediaFileManager(tempDir);
        final uploadedBlobIds = <String>[];
        final uploadedMimes = <String>[];
        var uploadCalls = 0;

        await tester.pumpWidget(
          buildWidget(
            group: group,
            messageRepo: completionRepo,
            mediaRepo: sqlDefaultMediaRepo,
            mediaFileManager: fileManager,
            initialPendingMedia: <PendingComposerMedia>[
              PendingComposerMedia(
                file: jpeg,
                budgetBytes: jpeg.lengthSync(),
                width: 640,
                height: 480,
              ),
              PendingComposerMedia(
                file: video,
                budgetBytes: video.lengthSync(),
                width: 1280,
                height: 720,
                durationMs: 4200,
              ),
            ],
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                  deleteSourceWhenDone = false,
                  preparedArtifact,
                }) async {
                  uploadCalls++;
                  uploadedBlobIds.add(blobId!);
                  uploadedMimes.add(mime);
                  return MediaAttachment(
                    id: blobId,
                    messageId: '',
                    mime: mime,
                    size: 10000 + uploadCalls,
                    mediaType: MediaAttachment.mediaTypeFromMime(mime),
                    width: width,
                    height: height,
                    durationMs: durationMs,
                    localPath: 'relay-owned/$blobId',
                    downloadStatus: 'done',
                    createdAt: '2099-01-0${uploadCalls}T00:00:00.000Z',
                    contentHash: _validContentHash,
                    thumbnailHash: 'upload-thumbnail-$uploadCalls',
                    encryptionKeyBase64: 'upload-key-$uploadCalls',
                    encryptionNonce: 'upload-nonce-$uploadCalls',
                    encryptionScheme:
                        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        final send = await startScreenSend(tester, 'P269 ordinary media');
        await tester.runAsync(() => send.future);
        await pumpFrames(tester, count: 20);

        expect(uploadCalls, 2);
        expect(uploadedMimes, <String>['image/jpeg', 'video/mp4']);
        expect(uploadedBlobIds.toSet(), hasLength(2));
        expect(completionRepo.completionCalls, 2);
        expect(completionRepo.projectionCalls, 0);
        expect(groupPublishPayloads(bridge), hasLength(1));

        final parents = await completionRepo.getMessagesPage(group.id);
        expect(parents, hasLength(1));
        final parent = parents.length == 1 ? parents.single : null;
        expect(parent?.status, 'sent');
        final rows = parent == null
            ? <MediaAttachment>[]
            : await sqlDefaultMediaRepo.getAttachmentsForMessage(
                parent.id,
                owner: MediaOwnerLane.group,
              );
        expect(rows, hasLength(2));
        for (final row in rows) {
          final expected = completionRepo.expectedFor(row.id);
          final completed = completionRepo.completedFor(row.id);
          expect(expected, isNotNull, reason: 'missing exact-CAS expectation');
          expect(completed, isNotNull, reason: 'missing completion result');
          expect(
            expected?.uploadRetryCount,
            0,
            reason: 'new foreground rows must carry the upload counter',
          );
          expect(
            expected?.downloadRetryCount,
            0,
            reason: 'new foreground rows must carry the download counter',
          );
          expect(row.downloadStatus, 'done');
          expect(row.uploadRetryCount, 0);
          expect(row.downloadRetryCount, 0);
          expect(row.createdAt, expected?.createdAt);
          expect(row.thumbnailHash, expected?.thumbnailHash);
          expect(row.size, completed?.size);
          expect(row.localPath, completed?.localPath);
          expect(row.contentHash, completed?.contentHash);
          expect(row.encryptionKeyBase64, completed?.encryptionKeyBase64);
          expect(row.encryptionNonce, completed?.encryptionNonce);
          expect(row.encryptionScheme, completed?.encryptionScheme);
        }
      },
    );

    testWidgets(
      'P269 voice foreground media survives database-defaulted retry counters and reaches exact completion once',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);

        final tempDir = Directory.systemTemp.createTempSync(
          'p269-voice-sql-defaults-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final voiceSource = File(p.join(tempDir.path, 'voice.m4a'))
          ..writeAsStringSync('p269 voice bytes');
        final recorder = FakeAudioRecorderService()
          ..fakeDurationMs = 3200
          ..fakeSizeBytes = voiceSource.lengthSync()
          ..fakeOutputPath = voiceSource.path;
        final sqlDefaultMediaRepo = _SqlDefaultingMediaAttachmentRepository();
        final completionRepo = _CompletionAwareGroupMessageRepository(
          mediaRepo: sqlDefaultMediaRepo,
        );
        final fileManager = TrackingDurableMediaFileManager(tempDir);
        String? uploadedBlobId;
        String? uploadedMime;
        var uploadCalls = 0;

        await tester.pumpWidget(
          buildWidget(
            group: group,
            messageRepo: completionRepo,
            mediaRepo: sqlDefaultMediaRepo,
            mediaFileManager: fileManager,
            audioRecorderService: recorder,
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                  deleteSourceWhenDone = false,
                  preparedArtifact,
                }) async {
                  uploadCalls++;
                  uploadedBlobId = blobId;
                  uploadedMime = mime;
                  return MediaAttachment(
                    id: blobId!,
                    messageId: '',
                    mime: mime,
                    size: 64000,
                    mediaType: 'audio',
                    localPath: 'relay-owned/$blobId',
                    downloadStatus: 'done',
                    createdAt: '2099-02-01T00:00:00.000Z',
                    contentHash: _validContentHash,
                    thumbnailHash: 'upload-voice-thumbnail',
                    encryptionKeyBase64: 'upload-voice-key',
                    encryptionNonce: 'upload-voice-nonce',
                    encryptionScheme:
                        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        await (screen.onRecordStart! as Future<void> Function())();
        await pumpUntil(
          tester,
          () => find.byIcon(Icons.stop_rounded).evaluate().isNotEmpty,
        );
        recorder.emitAmplitude(0.15);
        recorder.emitAmplitude(0.60);
        recorder.emitAmplitude(0.30);
        final recordingScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        await tester.runAsync(
          () => (recordingScreen.onRecordStop! as Future<void> Function())(),
        );
        await pumpFrames(tester, count: 20);

        expect(uploadCalls, 1);
        expect(uploadedMime, 'audio/mp4');
        expect(uploadedBlobId, isNotNull);
        expect(completionRepo.completionCalls, 1);
        expect(completionRepo.projectionCalls, 0);
        expect(groupPublishPayloads(bridge), hasLength(1));

        final parents = await completionRepo.getMessagesPage(group.id);
        expect(parents, hasLength(1));
        final parent = parents.length == 1 ? parents.single : null;
        expect(parent?.status, 'sent');
        final rows = parent == null
            ? <MediaAttachment>[]
            : await sqlDefaultMediaRepo.getAttachmentsForMessage(
                parent.id,
                owner: MediaOwnerLane.group,
              );
        expect(rows, hasLength(1));
        final row = rows.length == 1 ? rows.single : null;
        final expected = row == null
            ? null
            : completionRepo.expectedFor(row.id);
        final completed = row == null
            ? null
            : completionRepo.completedFor(row.id);
        expect(row?.id, uploadedBlobId);
        expect(expected?.id, uploadedBlobId);
        expect(expected?.uploadRetryCount, 0);
        expect(expected?.downloadRetryCount, 0);
        expect(row?.downloadStatus, 'done');
        expect(row?.uploadRetryCount, 0);
        expect(row?.downloadRetryCount, 0);
        expect(row?.durationMs, 3200);
        expect(row?.durationMs, expected?.durationMs);
        expect(row?.waveform, expected?.waveform);
        expect(row?.waveform, isNotEmpty);
        expect(row?.createdAt, expected?.createdAt);
        expect(row?.thumbnailHash, expected?.thumbnailHash);
        expect(row?.size, completed?.size);
        expect(row?.contentHash, completed?.contentHash);
      },
    );

    testWidgets(
      'P269 foreground completion failure projects bounded only while exact pending authority survives',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);

        final tempDir = Directory.systemTemp.createTempSync(
          'p269-foreground-completion-failure-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final source = File(p.join(tempDir.path, 'completion.jpg'))
          ..writeAsBytesSync(validJpegFixtureBytes);
        final completionMediaRepo = CountingMediaAttachmentRepository();
        final completionRepo = _CompletionAwareGroupMessageRepository(
          mediaRepo: completionMediaRepo,
        )..completionError = StateError('simulated completion persistence');
        final fileManager = TrackingDurableMediaFileManager(tempDir);
        var uploadCalls = 0;

        await tester.pumpWidget(
          buildWidget(
            group: group,
            messageRepo: completionRepo,
            mediaRepo: completionMediaRepo,
            mediaFileManager: fileManager,
            initialAttachments: <File>[source],
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                  deleteSourceWhenDone = false,
                  preparedArtifact,
                }) async {
                  uploadCalls++;
                  return successfulGroupUploadFixture(
                    blobId: blobId!,
                    mime: mime,
                    localFilePath: localFilePath,
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        final send = await startScreenSend(tester, 'completion failure');
        await tester.runAsync(() => send.future);
        await pumpFrames(tester, count: 20);

        expect(uploadCalls, 1);
        expect(completionRepo.completionCalls, 1);
        expect(completionRepo.projectionCalls, 1);
        expect(completionRepo.appliedProjectionCalls, 1);
        expect(completionRepo.projectedFailures, hasLength(1));
        final projectedFailure = completionRepo.projectedFailures.isEmpty
            ? null
            : completionRepo.projectedFailures.single;
        expect(projectedFailure?.stage, UploadMediaStage.consumerBoundary);
        expect(
          projectedFailure?.disposition,
          UploadMediaDisposition.boundedRetryable,
        );
        expect(groupPublishPayloads(bridge), isEmpty);

        final pending = await completionMediaRepo.getUploadPendingAttachments(
          owner: MediaOwnerLane.group,
        );
        expect(pending, hasLength(1));
        final pendingRow = pending.length == 1 ? pending.single : null;
        expect(pendingRow?.uploadRetryCount, 1);
        final durablePath = pendingRow?.localPath == null
            ? null
            : await fileManager.resolveStoredPath(pendingRow!.localPath!);
        expect(durablePath, isNotNull);
        expect(
          durablePath == null ? false : File(durablePath).existsSync(),
          isTrue,
        );
        expect(source.readAsBytesSync(), validJpegFixtureBytes);
      },
    );

    testWidgets(
      'P269 ordinary multi-media foreground lease owns every durable persisted blob ID until settlement',
      (tester) async {
        mediaUploadInFlightTracker.clearAll();
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);

        final tempDir = Directory.systemTemp.createTempSync(
          'p269-ordinary-durable-lease-',
        );
        final first = File(p.join(tempDir.path, 'first.jpg'))
          ..writeAsBytesSync(validJpegFixtureBytes);
        final second = File(p.join(tempDir.path, 'second.png'))
          ..writeAsBytesSync(_tinyPngBytes);
        final leaseMediaRepo = CountingMediaAttachmentRepository();
        final fileManager = TrackingDurableMediaFileManager(tempDir);
        final uploadStarted = <Completer<void>>[
          Completer<void>(),
          Completer<void>(),
        ];
        final uploadGates = <Completer<void>>[
          Completer<void>(),
          Completer<void>(),
        ];
        final observedDurableIds = <String>[];
        final ownedAtFirstVisibility = <bool>[];
        final competitorWon = <bool>[];
        final competitorLeases = <MediaUploadLease>[];
        final uploadedIds = <String>[];
        var uploadCalls = 0;

        leaseMediaRepo.onSaveAttachment = (attachment) {
          if (attachment.downloadStatus != 'upload_pending' ||
              observedDurableIds.contains(attachment.id)) {
            return;
          }
          observedDurableIds.add(attachment.id);
          ownedAtFirstVisibility.add(
            mediaUploadInFlightTracker.isInFlight(attachment.id),
          );
          final competingLease = mediaUploadInFlightTracker.tryClaimAll(
            <String>[attachment.id],
            source: MediaUploadTriggerSource.periodic,
          );
          competitorWon.add(competingLease != null);
          if (competingLease != null) competitorLeases.add(competingLease);
        };
        addTearDown(() {
          for (final gate in uploadGates) {
            if (!gate.isCompleted) gate.complete();
          }
          for (final lease in competitorLeases) {
            mediaUploadInFlightTracker.release(lease);
          }
          mediaUploadInFlightTracker.clearAll();
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: leaseMediaRepo,
            mediaFileManager: fileManager,
            initialAttachments: <File>[first, second],
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                  deleteSourceWhenDone = false,
                  preparedArtifact,
                }) async {
                  final index = uploadCalls++;
                  uploadedIds.add(blobId!);
                  if (!uploadStarted[index].isCompleted) {
                    uploadStarted[index].complete();
                  }
                  await uploadGates[index].future;
                  return successfulGroupUploadFixture(
                    blobId: blobId,
                    mime: mime,
                    localFilePath: localFilePath,
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        final send = await startScreenSend(tester, 'leased media');
        await tester.runAsync(
          () => uploadStarted[0].future.timeout(_uploadStartCeiling),
        );
        uploadGates[0].complete();
        await pumpUntilAsyncWorkSettles(
          tester,
          () => uploadStarted[1].isCompleted,
        );
        expect(uploadStarted[1].isCompleted, isTrue);
        uploadGates[1].complete();
        await tester.runAsync(() => send.future);
        await pumpFrames(tester, count: 20);

        expect(observedDurableIds, hasLength(2));
        expect(observedDurableIds.toSet(), uploadedIds.toSet());
        expect(ownedAtFirstVisibility, <bool>[true, true]);
        expect(competitorWon, <bool>[false, false]);
        expect(groupPublishPayloads(bridge), hasLength(1));

        for (final lease in competitorLeases) {
          mediaUploadInFlightTracker.release(lease);
        }
        competitorLeases.clear();
        expect(mediaUploadInFlightTracker.inFlightCount, 0);
      },
    );

    testWidgets(
      'P269 group composer canonicalizes heif to image heic and uploads and publishes once',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);

        final tempDir = Directory.systemTemp.createTempSync('p269-group-heif-');
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final heif = File(p.join(tempDir.path, 'camera.heif'))
          ..writeAsBytesSync(_validHeifBytes);
        final heifMediaRepo = CountingMediaAttachmentRepository();
        final fileManager = TrackingDurableMediaFileManager(tempDir);
        final uploadedMimes = <String>[];
        var uploadCalls = 0;

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: heifMediaRepo,
            mediaFileManager: fileManager,
            initialAttachments: <File>[heif],
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                  deleteSourceWhenDone = false,
                  preparedArtifact,
                }) async {
                  uploadCalls++;
                  uploadedMimes.add(mime);
                  return successfulGroupUploadFixture(
                    blobId: blobId!,
                    mime: mime,
                    localFilePath: localFilePath,
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        final send = await startScreenSend(tester, 'HEIF media');
        await tester.runAsync(() => send.future);
        await pumpFrames(tester, count: 20);

        expect(uploadCalls, 1);
        expect(uploadedMimes, <String>['image/heic']);
        expect(groupPublishPayloads(bridge), hasLength(1));
        final parents = await msgRepo.getMessagesPage(group.id);
        expect(parents, hasLength(1));
        final parent = parents.length == 1 ? parents.single : null;
        expect(parent?.status, 'sent');
        final rows = parent == null
            ? <MediaAttachment>[]
            : await heifMediaRepo.getAttachmentsForMessage(
                parent.id,
                owner: MediaOwnerLane.group,
              );
        expect(rows, hasLength(1));
        expect(rows.isEmpty ? null : rows.single.mime, 'image/heic');
        expect(rows.isEmpty ? null : rows.single.downloadStatus, 'done');
      },
    );

    testWidgets(
      'PB264-17 queued exit is restart-visible, read-only, and cancel-refreshable',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        await msgRepo.saveMessage(
          GroupMessage(
            id: 'pb264-readable',
            groupId: group.id,
            senderPeerId: 'peer-other',
            senderUsername: 'Other',
            text: 'Still readable while leaving',
            timestamp: DateTime.utc(2026, 7, 21, 10),
            createdAt: DateTime.utc(2026, 7, 21, 10),
            isIncoming: true,
            status: 'delivered',
          ),
        );
        final at = DateTime.utc(2026, 7, 21, 9);
        final queuedIntent = GroupExitIntent(
          groupId: group.id,
          intentId: 'pb264-intent',
          selfPeerId: testIdentity.peerId,
          selfJoinedAt: group.createdAt,
          state: GroupExitIntentState.queued,
          pendingBroadcastId: 'pb264-pending-broadcast',
          createdAt: at,
          updatedAt: at,
        );
        GroupExitIntent? durableIntent = queuedIntent;
        setGroupExitIntentAccessSinks(
          forGroup: (groupId) async =>
              groupId == group.id ? durableIntent : null,
          all: () async => durableIntent == null
              ? const <GroupExitIntent>[]
              : <GroupExitIntent>[durableIntent],
        );

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: FakeMediaFileManager(),
            audioRecorderService: FakeAudioRecorderService(),
            reactionRepo: FakeReactionRepository(),
            reactionReplayOutboxRepo: FakeGroupReactionReplayOutboxRepository(),
          ),
        );
        await pumpFrames(tester, count: 20);

        var screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(find.text('Still readable while leaving'), findsOneWidget);
        expect(screen.onInfo, isNotNull);
        expect(screen.canWrite, isFalse);
        expect(
          screen.readOnlyBannerText,
          'This group is read-only while we finish leaving.',
        );
        expect(screen.onAttach, isNull);
        expect(screen.onRecordStart, isNull);
        expect(screen.onQuoteReply, isNull);
        expect(screen.onReactionSelected, isNull);
        expect(screen.onRetryFailedMessage, isNull);
        expect(screen.onRetryFailedMedia, isNull);
        expect(screen.onRetryUnavailableMedia, isNull);

        durableIntent = null;
        screen.onInfo!();
        await pumpFrames(tester, count: 10);
        expect(find.byType(GroupInfoScreen), findsOneWidget);
        tester.state<NavigatorState>(find.byType(Navigator)).pop();
        await pumpFrames(tester, count: 20);

        screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.canWrite, isTrue, reason: 'Info return reloads absence');

        durableIntent = queuedIntent;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await pumpFrames(tester, count: 20);
        screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(
          screen.canWrite,
          isFalse,
          reason: 'resume reloads durable intent',
        );

        durableIntent = null;
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await pumpFrames(tester, count: 20);
        screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.canWrite, isTrue);
        expect(screen.onAttach, isNotNull);
        expect(screen.onQuoteReply, isNotNull);
        expect(screen.onReactionSelected, isNotNull);
      },
    );

    testWidgets(
      'PB266-10 conversation reaches current coded recovery after remount',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        final at = DateTime.utc(2026, 7, 21, 9, 30);
        final self = await groupRepo.getMember(group.id, testIdentity.peerId);
        final queuedIntent = GroupExitIntent(
          groupId: group.id,
          intentId: 'pb266-conversation-intent',
          selfPeerId: testIdentity.peerId,
          selfJoinedAt: self!.joinedAt,
          state: GroupExitIntentState.queued,
          pendingBroadcastId: 'pb266-conversation-notice',
          createdAt: at,
          updatedAt: at,
        );
        final diagnostic = GroupExitDiagnostic.create(
          occurredAt: at,
          groupId: group.id,
          intentId: queuedIntent.intentId,
          kind: GroupExitDiagnosticKind.voluntary,
          severity: GroupExitDiagnosticSeverity.failure,
          phase: GroupExitDiagnosticPhase.native,
          publicCode: GroupExitDiagnosticPublicCode.ex04,
          reason: GroupExitDiagnosticReason.nodeNotInitialized,
        );
        var exactLookupCalls = 0;
        setGroupExitIntentAccessSinks(
          forGroup: (groupId) async =>
              groupId == group.id ? queuedIntent : null,
          all: () async => [queuedIntent],
        );
        setGroupExitDiagnosticAccessSink(
          loadForAction: ({required groupId, required intentId}) async {
            expect(groupId, group.id);
            expect(intentId, queuedIntent.intentId);
            exactLookupCalls++;
            return [diagnostic];
          },
        );
        setGroupExitIntentActionSinks(
          resolveSnapshot: (groupId) => resolveGroupExitSnapshot(
            groupRepo: groupRepo,
            groupId: groupId,
            selfPeerId: testIdentity.peerId,
            messageRepo: msgRepo,
          ),
          requestLeave: (_) async => GroupExitIntentRequestResult(
            status: GroupExitIntentRequestStatus.queued,
            intent: queuedIntent,
          ),
        );

        for (var mount = 0; mount < 2; mount++) {
          await tester.pumpWidget(buildWidget(group: group));
          await pumpFrames(tester, count: 20);
          await tester.tap(find.byIcon(Icons.info_outline));
          await pumpFrames(tester, count: 20);
          expect(find.byType(GroupInfoScreen), findsOneWidget);

          final leave = find.byKey(const ValueKey('group-leave-button'));
          await tester.scrollUntilVisible(
            leave,
            200,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.tap(leave);
          await pumpFrames(tester, count: 20);

          expect(find.textContaining('EX04'), findsOneWidget);
          expect(find.textContaining(group.id), findsNothing);
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
        }

        expect(exactLookupCalls, greaterThanOrEqualTo(2));
      },
    );

    // ---- 210: group offline-send (queued-offline snackbar + clock, not tick) ----
    group('210 offline queued-offline send', () {
      // relayReady == false: node started but no relayState/circuit → offline.
      FakeP2PService offlineP2pService() => FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'me'),
      );

      // FALLBACK lane only (210b correction): a REAL offline device does NOT
      // produce this error shape — go-mknoon has no NETWORK_DOWN code and its
      // reliable send folds connectivity loss into ok:true publish-without-
      // custody flags (pinned by the 210b group below and GIRD-001). These
      // tests pin the SECONDARY lane: an outright bridge/exception `error`
      // while offline must land in the same queued_offline UX via the
      // `!relayReady` fallback branch (NETWORK_DOWN is NOT a "bridge
      // unavailable" code, so the use case returns `error` rather than falling
      // back to legacy publish).
      FakeBridge offlineFailingBridge() => FakeBridge(
        initialResponses: {
          'group:sendReliable': {'ok': false, 'errorCode': 'NETWORK_DOWN'},
        },
      );

      Future<GroupMessage> queuedRowFor(String text) async {
        final rows = await msgRepo.getMessagesPage('group-1');
        return rows.firstWhere((m) => m.text == text && !m.isIncoming);
      }

      // TC #3: offline text send → wifi-off snackbar + clock, no tick, no error,
      // composer not restored, no Retry, durable row is 'queued_offline'.
      testWidgets(
        'offline text send shows wifi-off snackbar + clock, no tick, no Retry',
        (tester) async {
          final group = makeChatGroup();
          await groupRepo.saveGroup(group);
          await saveActiveGroupMembers(groupRepo, group);
          p2pService = offlineP2pService();
          bridge = offlineFailingBridge();

          await tester.pumpWidget(buildWidget(group: group));
          await pumpFrames(tester);

          await tester.enterText(find.byType(TextField), 'Offline text');
          await pumpFrames(tester);
          await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
          await pumpFrames(tester, count: 20);

          // Informational snackbar — mirrors 1:1 exactly.
          expect(
            find.text("Will send when you're back online"),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: find.byType(SnackBar),
              matching: find.byIcon(Icons.wifi_off_rounded),
            ),
            findsOneWidget,
          );
          expect(
            tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
            Colors.blueGrey[700],
          );

          // Bubble shows a CLOCK, never a tick or an error.
          expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
          expect(find.byIcon(Icons.done_rounded), findsNothing);
          expect(find.byIcon(Icons.error_outline_rounded), findsNothing);

          // Composer NOT restored (the message stays durably queued).
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller?.text ??
                '',
            isEmpty,
          );

          // Durable row is 'queued_offline'; no Retry affordance is offered.
          final queued = await queuedRowFor('Offline text');
          expect(queued.status, 'queued_offline');
          expect(
            find.byKey(ValueKey('failed-message-retry-${queued.id}')),
            findsNothing,
          );
        },
      );

      // TC #4: the optimistic bubble must show the clock on the FIRST post-tap
      // frame (before the gated send resolves) — never a 'sending' tick flash.
      testWidgets(
        'optimistic offline bubble shows a clock immediately (no tick flash)',
        (tester) async {
          final group = makeChatGroup();
          await groupRepo.saveGroup(group);
          await saveActiveGroupMembers(groupRepo, group);
          p2pService = offlineP2pService();
          final gated = _GatedReliableFailBridge();
          bridge = gated;
          addTearDown(() {
            if (!gated.sendGate.isCompleted) gated.sendGate.complete();
          });

          await tester.pumpWidget(buildWidget(group: group));
          await pumpFrames(tester);

          await tester.enterText(find.byType(TextField), 'Optimistic offline');
          await pumpFrames(tester);
          await tester.tap(find.byIcon(Icons.arrow_upward_rounded));

          // The reliable send is gated (unresolved), so the result handler has
          // NOT run: the optimistic status alone is under test here.
          await pumpUntil(
            tester,
            () => find.text('Optimistic offline').evaluate().isNotEmpty,
          );
          await pumpFrames(tester, count: 3);

          expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
          expect(find.byIcon(Icons.done_rounded), findsNothing);

          // Release; it settles to queued_offline (still a clock).
          gated.sendGate.complete();
          await pumpFrames(tester, count: 20);
          expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
          expect(find.byIcon(Icons.done_rounded), findsNothing);
        },
      );

      // TC #5: the voice path (`_onRecordStop`) is a separate send surface — it
      // gets the SAME offline affordance (snackbar + clock).
      testWidgets(
        'voice/audio offline send shows wifi-off snackbar + clock (path parity)',
        (tester) async {
          final tempDir = Directory.systemTemp.createTempSync(
            'group-voice-offline-',
          );
          addTearDown(() {
            if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
          });
          final recorder = FakeAudioRecorderService()..fakeDurationMs = 1500;
          final voiceFile = File(p.join(tempDir.path, 'voice.m4a'))
            ..writeAsStringSync('voice');
          recorder.fakeOutputPath = voiceFile.path;
          final mediaFileManager = TrackingDurableMediaFileManager(tempDir);

          final group = makeChatGroup();
          await groupRepo.saveGroup(group);
          // Members present → the send reaches the connectivity path (NOT the
          // empty-membership groupDissolved terminal branch).
          await saveActiveGroupMembers(groupRepo, group);
          p2pService = offlineP2pService();
          bridge = offlineFailingBridge();

          await tester.pumpWidget(
            buildWidget(
              group: group,
              mediaRepo: mediaAttachmentRepo,
              mediaFileManager: mediaFileManager,
              audioRecorderService: recorder,
            ),
          );
          await pumpFrames(tester, count: 20);

          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          final startRecording =
              screen.onRecordStart! as Future<void> Function();
          await startRecording();
          await pumpUntil(
            tester,
            () =>
                tester
                    .widget<GroupConversationScreen>(
                      find.byType(GroupConversationScreen),
                    )
                    .recordingState ==
                VoiceRecordingState.recording,
          );

          final recordingScreen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          final stopRecording =
              recordingScreen.onRecordStop! as Future<void> Function();
          await tester.runAsync(() async {
            await stopRecording();
          });
          await pumpFrames(tester, count: 20);

          expect(
            find.text("Will send when you're back online"),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: find.byType(SnackBar),
              matching: find.byIcon(Icons.wifi_off_rounded),
            ),
            findsOneWidget,
          );
          expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
          expect(find.byIcon(Icons.done_rounded), findsNothing);
          expect(find.byIcon(Icons.error_outline_rounded), findsNothing);

          final after = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          final voiceRows = after.messages
              .where((m) => !m.isIncoming && m.text.isEmpty)
              .toList();
          expect(voiceRows, hasLength(1));
          expect(voiceRows.single.status, 'queued_offline');
        },
      );

      // TC #6 (guard, GREEN on HEAD): an ONLINE success shows a tick and NO
      // offline snackbar — the branch must not fire when relayReady is true.
      testWidgets('online success shows a tick and NO offline snackbar (guard)', (
        tester,
      ) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        // p2pService stays the setUp ONLINE default; setUp bridge = publish ok.

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester);

        await tester.enterText(find.byType(TextField), 'Online ok');
        await pumpFrames(tester);
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpFrames(tester, count: 20);

        expect(find.text('Online ok'), findsOneWidget);
        expect(find.byIcon(Icons.done_rounded), findsOneWidget);
        expect(find.byIcon(Icons.schedule_rounded), findsNothing);
        expect(find.text("Will send when you're back online"), findsNothing);
      });

      // TC #7 (ordering guard, GREEN on HEAD): a TERMINAL group failure while
      // offline still shows the error glyph + read-only banner and NO offline
      // snackbar — the terminal checks precede the offline branch.
      testWidgets(
        'terminal group failure while offline still shows error + read-only, '
        'no offline snackbar',
        (tester) async {
          final group = makeChatGroup();
          await groupRepo.saveGroup(group);
          // No members → empty-membership chat → use case returns groupDissolved
          // (a terminal result) BEFORE any connectivity-class branch.
          p2pService = offlineP2pService();

          await tester.pumpWidget(buildWidget(group: group));
          await pumpFrames(tester);

          await tester.enterText(find.byType(TextField), 'Terminal offline');
          await pumpFrames(tester);
          await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
          await pumpFrames(tester, count: 20);

          expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
          expect(find.byIcon(Icons.schedule_rounded), findsNothing);
          expect(find.text("Will send when you're back online"), findsNothing);
          expect(
            find.byKey(const ValueKey('group-read-only-banner')),
            findsOneWidget,
          );
        },
      );

      // TC #10: the clock→tick transition. Once the queued message actually
      // sends (connectivity returns, the row settles to 'sent' and the listener
      // streams it), the clock is replaced by a single tick — no error, no
      // duplicate, composer still clear, screen not read-only.
      testWidgets(
        'queued_offline settles to a tick when the message actually sends',
        (tester) async {
          final group = makeChatGroup();
          await groupRepo.saveGroup(group);
          await saveActiveGroupMembers(groupRepo, group);
          p2pService = offlineP2pService();
          bridge = offlineFailingBridge();

          await tester.pumpWidget(buildWidget(group: group));
          await pumpFrames(tester);

          await tester.enterText(find.byType(TextField), 'Reconnect me');
          await pumpFrames(tester);
          await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
          await pumpFrames(tester, count: 20);

          expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
          final queued = await queuedRowFor('Reconnect me');
          expect(queued.status, 'queued_offline');

          // Simulate the re-send completing: the DB row settles to 'sent' and the
          // listener streams the settled row for that id.
          await msgRepo.updateMessageStatus(queued.id, 'sent');
          messageStreamController.add(queued.copyWith(status: 'sent'));
          await pumpFrames(tester, count: 20);

          expect(find.byIcon(Icons.done_rounded), findsOneWidget);
          expect(find.byIcon(Icons.schedule_rounded), findsNothing);
          expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
          expect(find.text('Reconnect me'), findsOneWidget);
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller?.text ??
                '',
            isEmpty,
          );
          final after = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          expect(
            after.messages.where(
              (m) => m.text == 'Reconnect me' && !m.isIncoming,
            ),
            hasLength(1),
          );
        },
      );
    });

    // ---- 210b: the REALISTIC offline contract (publish-without-custody) ----
    // A real offline device does NOT get an error back from group:sendReliable:
    // the gossipsub publish "succeeds" locally with zero topic peers and only
    // the relay-inbox custody fails, so the bridge answers ok:true /
    // publishSucceeded:true / inboxStored:false / topicPeerCount:0 (the shape
    // pinned by GIRD-001 in the use-case suite). The 210 NETWORK_DOWN tests
    // above pin the error-fallback lane only; these pin the PRIMARY lane: the
    // use case must map this shape to queuedOffline + a durable 'queued_offline'
    // row (clock) and the screen must surface the honest snackbar — keyed off
    // the RESULT CONTRACT, not the stale-prone relayReady snapshot.
    group('210b realistic offline send (publish-without-custody)', () {
      FakeP2PService offlineP2pService() => FakeP2PService(
        initialState: const NodeState(isStarted: true, peerId: 'me'),
      );

      // The bridge shape a REAL offline (or relay-unreachable) device produces.
      FakeBridge noCustodyBridge({int topicPeers = 0}) => FakeBridge(
        initialResponses: {
          'group:sendReliable': {
            'ok': true,
            'publishSucceeded': true,
            'inboxStored': false,
            'topicPeerCount': topicPeers,
            'connectedTopicPeerCount': topicPeers,
            'expectedRecipientCount': 2,
            'recipientPeerIds': ['peer-2', 'peer-3'],
            'deliveryMode': 'live_only',
          },
        },
      );

      Future<GroupMessage> rowFor(String text) async {
        final rows = await msgRepo.getMessagesPage('group-1');
        return rows.firstWhere((m) => m.text == text && !m.isIncoming);
      }

      // TC 210b-1: the primary device geometry — offline (relayReady false),
      // realistic no-custody result → clock + wifi-off snackbar + durable
      // queued_offline row with the repush payload armed. RED on HEAD: the
      // ok:true shape returns success/'pending' → a tick and NO snackbar.
      testWidgets(
        'realistic offline text send shows wifi-off snackbar + clock, '
        'row queued_offline with repush payload',
        (tester) async {
          final group = makeChatGroup();
          await groupRepo.saveGroup(group);
          await saveActiveGroupMembers(groupRepo, group);
          p2pService = offlineP2pService();
          bridge = noCustodyBridge();

          await tester.pumpWidget(buildWidget(group: group));
          await pumpFrames(tester);

          await tester.enterText(find.byType(TextField), 'Real offline text');
          await pumpFrames(tester);
          await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
          await pumpFrames(tester, count: 20);

          // Honest offline snackbar — mirrors 1:1 exactly.
          expect(
            find.text("Will send when you're back online"),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: find.byType(SnackBar),
              matching: find.byIcon(Icons.wifi_off_rounded),
            ),
            findsOneWidget,
          );
          expect(
            tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
            Colors.blueGrey[700],
          );

          // Clock, never a tick or an error.
          expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
          expect(find.byIcon(Icons.done_rounded), findsNothing);
          expect(find.byIcon(Icons.error_outline_rounded), findsNothing);

          // Composer stays clear (no Retry resurrection).
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller?.text ??
                '',
            isEmpty,
          );

          // Durable row: queued_offline with the self-heal repush lane armed.
          final queued = await rowFor('Real offline text');
          expect(queued.status, 'queued_offline');
          expect(queued.inboxStored, isFalse);
          expect(queued.inboxRetryPayload, isNotNull);
          expect(
            find.byKey(ValueKey('failed-message-retry-${queued.id}')),
            findsNothing,
          );
        },
      );

      // TC 210b-2: the stale-online window (the 15-30s after losing internet
      // where relayReady still reads TRUE). The lane must STILL queue (the
      // result contract says nothing left the device); only the copy changes —
      // the 192-style "Delivery delayed" names what is actually happening,
      // because a "back online" promise would be dishonest while the phone
      // believes it is online. RED on HEAD: tick + no snackbar.
      testWidgets(
        'stale-online no-custody send still queues with the delayed-retry '
        'snackbar (192 copy) and a clock',
        (tester) async {
          final group = makeChatGroup();
          await groupRepo.saveGroup(group);
          await saveActiveGroupMembers(groupRepo, group);
          // p2pService stays the setUp ONLINE default (relayReady TRUE).
          bridge = noCustodyBridge();

          await tester.pumpWidget(buildWidget(group: group));
          await pumpFrames(tester);

          await tester.enterText(find.byType(TextField), 'Stale online text');
          await pumpFrames(tester);
          await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
          await pumpFrames(tester, count: 20);

          expect(
            find.text('Delivery delayed — retrying automatically'),
            findsOneWidget,
          );
          expect(find.text("Will send when you're back online"), findsNothing);
          expect(
            find.descendant(
              of: find.byType(SnackBar),
              matching: find.byIcon(Icons.schedule_send_rounded),
            ),
            findsOneWidget,
          );
          expect(
            tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor,
            Colors.blueGrey[700],
          );

          expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
          expect(find.byIcon(Icons.done_rounded), findsNothing);

          final queued = await rowFor('Stale online text');
          expect(queued.status, 'queued_offline');
        },
      );

      // TC 210b-3 (guard, GREEN on HEAD and after): live peers WITHOUT custody
      // is the pre-existing in-doubt lane — some recipients may have received
      // the live publish, so it must KEEP its tick and show NO queued snackbar.
      // Locks queuedOffline to the zero-peers-AND-no-custody geometry only.
      testWidgets(
        'live peers without custody keeps the in-doubt tick, no queued '
        'snackbar (guard)',
        (tester) async {
          final group = makeChatGroup();
          await groupRepo.saveGroup(group);
          await saveActiveGroupMembers(groupRepo, group);
          bridge = noCustodyBridge(topicPeers: 2);

          await tester.pumpWidget(buildWidget(group: group));
          await pumpFrames(tester);

          await tester.enterText(find.byType(TextField), 'Live partial text');
          await pumpFrames(tester);
          await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
          await pumpFrames(tester, count: 20);

          expect(find.byIcon(Icons.done_rounded), findsOneWidget);
          expect(find.byIcon(Icons.schedule_rounded), findsNothing);
          expect(find.text("Will send when you're back online"), findsNothing);
          expect(
            find.text('Delivery delayed — retrying automatically'),
            findsNothing,
          );
        },
      );

      // TC 210b-4: voice path parity for the realistic contract.
      testWidgets(
        'realistic offline voice send shows wifi-off snackbar + clock '
        '(path parity)',
        (tester) async {
          final tempDir = Directory.systemTemp.createTempSync(
            'group-voice-nocustody-',
          );
          addTearDown(() {
            if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
          });
          final recorder = FakeAudioRecorderService()..fakeDurationMs = 1500;
          final voiceFile = File(p.join(tempDir.path, 'voice.m4a'))
            ..writeAsStringSync('voice');
          recorder.fakeOutputPath = voiceFile.path;
          final mediaFileManager = TrackingDurableMediaFileManager(tempDir);

          final group = makeChatGroup();
          await groupRepo.saveGroup(group);
          await saveActiveGroupMembers(groupRepo, group);
          p2pService = offlineP2pService();
          bridge = noCustodyBridge();

          await tester.pumpWidget(
            buildWidget(
              group: group,
              mediaRepo: mediaAttachmentRepo,
              mediaFileManager: mediaFileManager,
              audioRecorderService: recorder,
            ),
          );
          await pumpFrames(tester, count: 20);

          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          final startRecording =
              screen.onRecordStart! as Future<void> Function();
          await startRecording();
          await pumpUntil(
            tester,
            () =>
                tester
                    .widget<GroupConversationScreen>(
                      find.byType(GroupConversationScreen),
                    )
                    .recordingState ==
                VoiceRecordingState.recording,
          );

          final recordingScreen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          final stopRecording =
              recordingScreen.onRecordStop! as Future<void> Function();
          await tester.runAsync(() async {
            await stopRecording();
          });
          await pumpFrames(tester, count: 20);

          expect(
            find.text("Will send when you're back online"),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: find.byType(SnackBar),
              matching: find.byIcon(Icons.wifi_off_rounded),
            ),
            findsOneWidget,
          );
          expect(find.byIcon(Icons.schedule_rounded), findsOneWidget);
          expect(find.byIcon(Icons.done_rounded), findsNothing);
          expect(find.byIcon(Icons.error_outline_rounded), findsNothing);

          final after = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          final voiceRows = after.messages
              .where((m) => !m.isIncoming && m.text.isEmpty)
              .toList();
          expect(voiceRows, hasLength(1));
          expect(voiceRows.single.status, 'queued_offline');
        },
      );
    });

    testWidgets('prefills shared text into the group composer', (tester) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

      await tester.pumpWidget(
        buildWidget(group: group, initialText: 'Shared group text'),
      );
      await pumpFrames(tester);

      final textField = tester.widget<TextField>(find.byType(TextField));
      expect(textField.controller?.text, 'Shared group text');
    });

    // 204 TC-204-04 (BUG-1, group): the group attach sheet must expose an
    // explicit Cancel affordance (the sheets are duplicated per surface, so the
    // group needs its own lock). RED on HEAD: no Cancel row => key findsNothing.
    testWidgets('attach sheet shows a Cancel affordance (group)', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester, count: 20);

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump(const Duration(milliseconds: 500));

      // Cancel is additive: the three pickers are still present.
      expect(find.text('Media Library'), findsOneWidget);
      expect(find.text('Take Photo'), findsOneWidget);
      expect(find.text('Record Video'), findsOneWidget);

      final cancel = find.byKey(GroupConversationWired.attachSheetCancelKey);
      expect(cancel, findsOneWidget);
      expect(
        find.descendant(of: cancel, matching: find.text('Cancel')),
        findsOneWidget,
      );
    });

    // 204 TC-204-05 (BUG-1, group): Cancel dismisses the group sheet ONLY — it
    // must not invoke a picker and must not clear already-staged media.
    testWidgets(
      'Cancel closes the group attach sheet without picking and keeps staged media (group)',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        final tempDir = Directory.systemTemp.createTempSync(
          'group_cancel_staged_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final attachment = File('${tempDir.path}/staged.jpg')
          ..writeAsStringSync('image');
        final mediaPicker = FakeMediaPicker();

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaPicker: mediaPicker,
            initialAttachments: [attachment],
          ),
        );
        await pumpFrames(tester, count: 20);

        // Baseline: one attachment is staged, and no pick has happened yet.
        expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
        expect(mediaPicker.pickMultipleMediaCalls, 0);

        // Open the sheet, then Cancel it.
        await tester.tap(find.byIcon(Icons.add_rounded));
        await tester.pump(const Duration(milliseconds: 500));
        expect(find.text('Media Library'), findsOneWidget);

        // Invoke the Cancel tile's onTap directly (the sheet extends below the
        // short test viewport, so a hit-test tap would miss) — mirrors how this
        // file drives the picker tiles.
        tester
            .widget<ListTile>(
              find.byKey(GroupConversationWired.attachSheetCancelKey),
            )
            .onTap!();
        await tester.pump(const Duration(milliseconds: 500));

        // SHEET_DISMISSED: the picker options are gone.
        expect(find.text('Media Library'), findsNothing);
        // NOT PICK_INVOKED: Cancel never triggered a gallery pick.
        expect(mediaPicker.pickMultipleMediaCalls, 0);
        // STAGED_INTACT: the previously staged attachment survives.
        expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
      },
    );

    testWidgets('does not render security status in group chat chrome', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      await groupRepo.saveKey(
        GroupKeyInfo(
          groupId: group.id,
          keyGeneration: 2,
          encryptedKey: 'test-group-key-2',
          createdAt: DateTime.now().toUtc(),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: group.id,
          peerId: 'peer-alice',
          username: 'Alice',
          role: MemberRole.writer,
          publicKey: 'pk-alice',
          mlKemPublicKey: 'mlkem-alice',
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: group.id,
          peerId: 'peer-bob',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-bob-current',
          mlKemPublicKey: 'mlkem-bob-current',
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await contactRepo.addContact(
        ContactModel(
          peerId: 'peer-alice',
          publicKey: 'pk-alice',
          rendezvous: '/ip4/127.0.0.1/tcp/4001',
          username: 'Alice',
          signature: 'sig-alice',
          scannedAt: DateTime.utc(2026, 5, 1).toIso8601String(),
          mlKemPublicKey: 'mlkem-alice',
        ),
      );
      await contactRepo.addContact(
        ContactModel(
          peerId: 'peer-bob',
          publicKey: 'pk-bob-saved',
          rendezvous: '/ip4/127.0.0.1/tcp/4001',
          username: 'Bob',
          signature: 'sig-bob',
          scannedAt: DateTime.utc(2026, 5, 1).toIso8601String(),
          mlKemPublicKey: 'mlkem-bob-saved',
        ),
      );

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester, count: 20);

      expect(
        find.byKey(const ValueKey('group-conversation-security-strip')),
        findsNothing,
      );
      expect(find.text('Encrypted - key epoch 2'), findsNothing);
      expect(find.text('1 member needs verification review'), findsNothing);
      expect(find.textContaining('test-group-key-2'), findsNothing);
    });

    testWidgets('counts own member as verified without saved contact', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      await groupRepo.saveMember(
        GroupMember(
          groupId: group.id,
          peerId: testIdentity.peerId,
          username: testIdentity.username,
          role: MemberRole.admin,
          publicKey: testIdentity.publicKey,
          mlKemPublicKey: testIdentity.mlKemPublicKey,
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: group.id,
          peerId: 'peer-alice',
          username: 'Alice',
          role: MemberRole.writer,
          publicKey: 'pk-alice',
          mlKemPublicKey: 'mlkem-alice',
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await groupRepo.saveMember(
        GroupMember(
          groupId: group.id,
          peerId: 'peer-bob',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-bob',
          mlKemPublicKey: 'mlkem-bob',
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await contactRepo.addContact(
        ContactModel(
          peerId: 'peer-alice',
          publicKey: 'pk-alice',
          rendezvous: '/ip4/127.0.0.1/tcp/4001',
          username: 'Alice',
          signature: 'sig-alice',
          scannedAt: DateTime.utc(2026, 5, 1).toIso8601String(),
          mlKemPublicKey: 'mlkem-alice',
        ),
      );
      await contactRepo.addContact(
        ContactModel(
          peerId: 'peer-bob',
          publicKey: 'pk-bob',
          rendezvous: '/ip4/127.0.0.1/tcp/4002',
          username: 'Bob',
          signature: 'sig-bob',
          scannedAt: DateTime.utc(2026, 5, 1).toIso8601String(),
          mlKemPublicKey: 'mlkem-bob',
        ),
      );

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester, count: 20);

      expect(
        find.byKey(const ValueKey('group-conversation-security-strip')),
        findsNothing,
      );
      expect(find.text('Encrypted - key epoch 1'), findsNothing);
      expect(find.text('All 3 members verified'), findsNothing);
      expect(find.text('2 of 3 members verified'), findsNothing);
      expect(
        find.textContaining('not verified from saved contacts'),
        findsNothing,
      );
    });

    testWidgets(
      'hydrated group initialPendingMedia uses budget bytes instead of file size',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        final tempDir = Directory.systemTemp.createTempSync(
          'group_hydrated_budget_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final smallFile = File('${tempDir.path}/hydrated.jpg')
          ..writeAsStringSync('12');

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            initialPendingMedia: [
              PendingComposerMedia(file: smallFile, budgetBytes: 12),
            ],
            maxAttachmentBudgetBytes: 10,
          ),
        );
        await pumpFrames(tester, count: 20);

        expect(find.text('Media Too Large'), findsOneWidget);
      },
    );

    // 149 TC-04: an oversized group pick marks the chip invalid AT PICK TIME,
    // shows NO snackbar, and disables Send (inert tap, draft preserved).
    testWidgets(
      'oversized group pick marks the chip invalid at pick time, shows no '
      'snackbar, and disables Send',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        final tempDir = Directory.systemTemp.createTempSync('group_oversized_');
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final bigImage = File('${tempDir.path}/big.jpg')
          ..writeAsBytesSync(_tinyPngBytes);

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            initialText: 'hello',
            initialPendingMedia: [
              PendingComposerMedia(
                file: bigImage,
                budgetBytes: 30 * 1024 * 1024, // > 25 MB image cap
              ),
            ],
          ),
        );
        await pumpFrames(tester, count: 20);

        expect(
          find.byKey(const ValueKey('attachment-invalid-0')),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(
            SnackBar,
            'The media is too large even after compression.',
          ),
          findsNothing,
        );
        // Send is inert while invalid present: tapping it does not clear draft.
        expect(find.byIcon(Icons.arrow_upward_rounded), findsOneWidget);
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'hello',
        );
        // Retained, not silently discarded.
        expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
      },
    );

    // 149 TC-07: an oversized GIF group pick marks the chip with the GIF caption
    // (not a snackbar).
    testWidgets(
      'GIF-too-large group pick marks the chip with the GIF caption (not a '
      'snackbar)',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        final tempDir = Directory.systemTemp.createTempSync('group_gif_over_');
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final bigGif = File('${tempDir.path}/big.gif')
          ..writeAsBytesSync(_tinyPngBytes);

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            initialPendingMedia: [
              PendingComposerMedia(
                file: bigGif,
                budgetBytes: 30 * 1024 * 1024, // > 25 MB GIF cap
              ),
            ],
          ),
        );
        await pumpFrames(tester, count: 20);

        expect(find.text('GIF too big'), findsOneWidget);
        expect(
          find.widgetWithText(
            SnackBar,
            'GIF files larger than 25 MB cannot be added.',
          ),
          findsNothing,
        );
      },
    );

    // 149 TC-11 (group): two oversized picks mark BOTH chips (mark-all — the
    // group gate iterates `media` itself, no validateAttachments index loss).
    testWidgets(
      'two oversized group picks mark BOTH chips invalid (multi-invalid)',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        final tempDir = Directory.systemTemp.createTempSync('group_multi_');
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final big1 = File('${tempDir.path}/big1.jpg')
          ..writeAsBytesSync(_tinyPngBytes);
        final big2 = File('${tempDir.path}/big2.jpg')
          ..writeAsBytesSync(_tinyPngBytes);

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            initialPendingMedia: [
              PendingComposerMedia(file: big1, budgetBytes: 30 * 1024 * 1024),
              PendingComposerMedia(file: big2, budgetBytes: 30 * 1024 * 1024),
            ],
          ),
        );
        await pumpFrames(tester, count: 20);

        expect(
          find.byKey(const ValueKey('attachment-invalid-0')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('attachment-invalid-1')),
          findsOneWidget,
        );
      },
    );

    // 149 follow-up: a whole-message TOTAL overflow owns no single index (each
    // attachment is individually valid) → it surfaces as a STRIP-LEVEL note +
    // Send-disabled, not a per-chip border. Without this the user picks several
    // individually-valid videos over the 500 MB group cap, sees no chip, taps an
    // enabled Send, and gets NO feedback (the gate blocks silently).
    testWidgets(
      'group total-size overflow (individually-valid attachments) shows a '
      'strip-level note and disables Send (no per-chip)',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        final tempDir = Directory.systemTemp.createTempSync(
          'group_total_over_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        File vid(String n) =>
            File('${tempDir.path}/$n.mp4')..writeAsBytesSync(_tinyMp4Bytes);

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            initialText: 'hello',
            initialPendingMedia: [
              // Each 200 MB < the 250 MB video cap (individually valid), but the
              // 600 MB total exceeds the 500 MB group message cap.
              PendingComposerMedia(
                file: vid('v1'),
                budgetBytes: 200 * 1024 * 1024,
              ),
              PendingComposerMedia(
                file: vid('v2'),
                budgetBytes: 200 * 1024 * 1024,
              ),
              PendingComposerMedia(
                file: vid('v3'),
                budgetBytes: 200 * 1024 * 1024,
              ),
            ],
          ),
        );
        await pumpFrames(tester, count: 20);

        // No per-attachment chip — each item is individually within its cap.
        expect(
          find.byKey(const ValueKey('attachment-invalid-0')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('attachment-invalid-1')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('attachment-invalid-2')),
          findsNothing,
        );
        // The whole-message overflow surfaces as a strip-level note.
        expect(
          find.byKey(const ValueKey('attachment-total-overflow')),
          findsOneWidget,
        );
        // Send is disabled (no transient snackbar, no silent dead-Send).
        expect(
          tester
              .widget<ComposeArea>(find.byType(ComposeArea))
              .hasInvalidAttachment,
          isTrue,
        );
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await tester.pump(const Duration(milliseconds: 200));
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'hello',
        );
        expect(bridge.commandLog, isNot(contains('group:publish')));
      },
    );

    // 149 TC-08 (source-wiring half): the 3 media-tile-duplicate snackbars are
    // removed from the wired source, while the text-retry snackbar (the SOLE
    // feedback for a failed text-message retry, no inline tile) is KEPT.
    // The behavioral inline-present half is locked by the GIRD-002 test.
    test('the 3 redundant media snackbars are dropped from source; the '
        'text-retry snackbar is kept', () {
      final src = File(
        'lib/features/groups/presentation/screens/'
        'group_conversation_wired.dart',
      ).readAsStringSync();

      // Dropped — the MediaGridCell upload-pending / unavailable placeholders
      // already convey this state inline.
      expect(
        src.contains('.media_still_unavailable'),
        isFalse,
        reason: 'media_still_unavailable snackbar must be dropped (inline)',
      );
      expect(
        src.contains('.failed_media_upload_pending_retry'),
        isFalse,
        reason: 'upload-pending snackbar must be dropped (inline placeholder)',
      );
      expect(
        src.contains('.failed_media_retry_failed'),
        isFalse,
        reason: 'failed-media-retry snackbar must be dropped (inline)',
      );

      // KEPT — a failed TEXT retry renders no MediaGridCell, so this snackbar
      // is the only feedback. Dropping it would lose all feedback.
      expect(
        src.contains('.failed_message_retry_failed'),
        isTrue,
        reason: 'failed_message_retry_failed must stay (text-retry path)',
      );
    });

    testWidgets(
      'oversized gallery attachment compresses under budget and stages the processed file',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        final tempDir = Directory.systemTemp.createTempSync(
          'group_large_attachment_compress_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final oversizedFile = File('${tempDir.path}/oversized.jpg')
          ..writeAsStringSync('123456789012');
        final compressedFile = File('${tempDir.path}/compressed.jpg')
          ..writeAsStringSync('1234');

        final mediaPicker = FakeMediaPicker()
          ..multipleMediaResult = [XFile(oversizedFile.path)];
        final qualityCalls = <int>[];
        final imageProcessor = ImageProcessor(
          compressFile:
              ({
                required path,
                required quality,
                required keepExif,
                minWidth = 1920,
                minHeight = 1080,
              }) async {
                qualityCalls.add(quality);
                if (quality == 100) {
                  return XFile(oversizedFile.path);
                }
                return XFile(compressedFile.path);
              },
          compressVideo:
              ({
                required path,
                required compress,
                void Function(double progress)? onProgress,
              }) async => null,
        );

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            imageProcessor: imageProcessor,
            mediaPicker: mediaPicker,
            qualityPreference: ImageQualityPreference.original,
            maxAttachmentBudgetBytes: 10,
          ),
        );
        await pumpFrames(tester, count: 20);

        await tester.tap(find.byIcon(Icons.add_rounded));
        await tester.pump(const Duration(milliseconds: 500));
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Media Library'))
            .onTap!();
        await pumpUntil(
          tester,
          () => find.text('Media Too Large').evaluate().isNotEmpty,
        );

        expect(find.text('Media Too Large'), findsOneWidget);
        expect(find.textContaining('12 B'), findsOneWidget);
        expect(find.textContaining('10 B limit'), findsOneWidget);

        await tester.tap(find.widgetWithText(FilledButton, 'Compress'));
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen
              .composerStateListenable!
              .value
              .pendingAttachments
              .isNotEmpty;
        });
        await pumpFrames(tester, count: 5);

        expect(qualityCalls, equals([100, 85]));
        expect(find.text('Media Too Large'), findsNothing);
        expect(
          find.text('The media is too large even after compression.'),
          findsNothing,
        );

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(
          screen.composerStateListenable!.value.pendingAttachments,
          hasLength(1),
        );
        expect(
          screen.composerStateListenable!.value.pendingAttachments.single.path,
          compressedFile.path,
        );
        expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
      },
    );

    testWidgets(
      'send rejects an oversized non-GIF attachment pre-upload with a type-aware message',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        final tempDir = Directory.systemTemp.createTempSync(
          'group_send_size_gate_video_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        // A tiny real file with a video extension; the send gate reads the
        // declared budgetBytes (300 MB, over the 250 MB video cap), not the file.
        final video = File('${tempDir.path}/clip.mp4')..writeAsStringSync('x');

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            initialPendingMedia: [
              PendingComposerMedia(file: video, budgetBytes: 300 * 1024 * 1024),
            ],
          ),
        );
        await pumpFrames(tester, count: 15);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(
          screen.composerStateListenable!.value.pendingAttachments,
          hasLength(1),
        );

        final send = screen.onSend as Future<void> Function(String);
        await send('');
        await pumpFrames(tester, count: 10);

        // 149: the rejection is now an inline composer chip (generic "Too large"
        // for a non-GIF), NOT a transient snackbar. INV-SZ-1: nothing published,
        // and the composer keeps the attachment (send aborted).
        expect(
          find.byKey(const ValueKey('attachment-invalid-0')),
          findsOneWidget,
        );
        expect(find.text('Too large'), findsOneWidget);
        expect(
          find.text('The media is too large even after compression.'),
          findsNothing,
        );
        expect(bridge.commandLog, isNot(contains('group:publish')));
        expect(
          tester
              .widget<GroupConversationScreen>(
                find.byType(GroupConversationScreen),
              )
              .composerStateListenable!
              .value
              .pendingAttachments,
          hasLength(1),
        );
      },
    );

    testWidgets(
      'send rejects an oversized GIF on final bytes with the GIF-specific message',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        final tempDir = Directory.systemTemp.createTempSync(
          'group_send_size_gate_gif_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final gif = File('${tempDir.path}/big.gif')..writeAsStringSync('x');

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            initialPendingMedia: [
              PendingComposerMedia(
                file: gif,
                budgetBytes: 26 * 1024 * 1024, // over the 25 MB GIF cap
              ),
            ],
          ),
        );
        await pumpFrames(tester, count: 15);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final send = screen.onSend as Future<void> Function(String);
        await send('');
        await pumpFrames(tester, count: 10);

        // 149: the GIF cap reason now routes to the inline composer chip's
        // GIF-specific caption ("GIF too big"), NOT a transient snackbar
        // (INV-SZ-2: still validated on final budget bytes via the single gate).
        expect(
          find.byKey(const ValueKey('attachment-invalid-0')),
          findsOneWidget,
        );
        expect(find.text('GIF too big'), findsOneWidget);
        expect(
          find.text('GIF files larger than 25 MB cannot be added.'),
          findsNothing,
        );
        expect(bridge.commandLog, isNot(contains('group:publish')));
      },
    );

    testWidgets(
      'oversized gallery attachment that remains over budget after compression leaves no pending state',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        final tempDir = Directory.systemTemp.createTempSync(
          'group_large_attachment_reject_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final oversizedFile = File('${tempDir.path}/oversized.jpg')
          ..writeAsStringSync('123456789012');
        final stillOversizedFile = File('${tempDir.path}/still-oversized.jpg')
          ..writeAsStringSync('12345678901');

        final mediaPicker = FakeMediaPicker()
          ..multipleMediaResult = [XFile(oversizedFile.path)];
        final qualityCalls = <int>[];
        final imageProcessor = ImageProcessor(
          compressFile:
              ({
                required path,
                required quality,
                required keepExif,
                minWidth = 1920,
                minHeight = 1080,
              }) async {
                qualityCalls.add(quality);
                if (quality == 100) {
                  return XFile(oversizedFile.path);
                }
                return XFile(stillOversizedFile.path);
              },
          compressVideo:
              ({
                required path,
                required compress,
                void Function(double progress)? onProgress,
              }) async => null,
        );

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            imageProcessor: imageProcessor,
            mediaPicker: mediaPicker,
            qualityPreference: ImageQualityPreference.original,
            maxAttachmentBudgetBytes: 10,
          ),
        );
        await pumpFrames(tester, count: 20);

        await tester.tap(find.byIcon(Icons.add_rounded));
        await tester.pump(const Duration(milliseconds: 500));
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Media Library'))
            .onTap!();
        await pumpUntil(
          tester,
          () => find.text('Media Too Large').evaluate().isNotEmpty,
        );

        await tester.tap(find.widgetWithText(FilledButton, 'Compress'));
        await pumpFrames(tester, count: 20);

        expect(qualityCalls, equals([100, 85]));
        expect(
          find.text('The media is too large even after compression.'),
          findsOneWidget,
        );
        expect(find.byType(AttachmentPreviewStrip), findsNothing);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(
          screen.composerStateListenable!.value.pendingAttachments,
          isEmpty,
        );
      },
    );

    testWidgets('loads and displays messages on init', (tester) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

      await msgRepo.saveMessage(makeMessage(id: 'msg-1', text: 'Hello'));
      await msgRepo.saveMessage(makeMessage(id: 'msg-2', text: 'World'));
      await msgRepo.saveMessage(makeMessage(id: 'msg-3', text: 'How are you?'));

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester);

      expect(find.text('Hello'), findsOneWidget);
      expect(find.text('World'), findsOneWidget);
      expect(find.text('How are you?'), findsOneWidget);
    });

    testWidgets('interleaves WhatsApp-style date separators across days', (
      tester,
    ) async {
      // Tall surface so the reversed lazy ListView builds every row
      // (the oldest message/separator would otherwise be off-screen).
      tester.view.physicalSize = const Size(1200, 4000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

      final now = DateTime.now();
      // Saved oldest -> newest; the timeline renders ascending regardless.
      await msgRepo.saveMessage(
        makeMessage(
          id: 'm-old',
          text: 'Old day message',
          timestamp: now.subtract(const Duration(days: 5)),
        ),
      );
      await msgRepo.saveMessage(
        makeMessage(
          id: 'm-yest',
          text: 'Yesterday message',
          timestamp: now.subtract(const Duration(days: 1)),
        ),
      );
      await msgRepo.saveMessage(
        makeMessage(id: 'm-today', text: 'Today message', timestamp: now),
      );

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester);

      final separators = tester
          .widgetList<DateSeparator>(find.byType(DateSeparator))
          .toList();
      final labels = separators.map((s) => s.label).toList();

      // Exactly one separator per distinct calendar day.
      expect(separators, hasLength(3));
      expect(labels, contains('Today'));
      expect(labels, contains('Yesterday'));
      // The older day uses the "Wed 9. Jun" weekday + day. month format.
      expect(
        labels.any(
          (l) => RegExp(r'^[A-Za-z]{3} \d{1,2}\. [A-Za-z]{3}$').hasMatch(l),
        ),
        isTrue,
      );

      // Messages still render alongside the separators.
      expect(find.text('Today message'), findsOneWidget);
      expect(find.text('Yesterday message'), findsOneWidget);
      expect(find.text('Old day message'), findsOneWidget);
    });

    testWidgets(
      'renders a single date separator when all messages share a day',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        final now = DateTime.now();
        await msgRepo.saveMessage(
          makeMessage(
            id: 'm-1',
            text: 'First today',
            timestamp: now.subtract(const Duration(minutes: 10)),
          ),
        );
        await msgRepo.saveMessage(
          makeMessage(id: 'm-2', text: 'Second today', timestamp: now),
        );

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester);

        final separators = tester
            .widgetList<DateSeparator>(find.byType(DateSeparator))
            .toList();
        expect(separators, hasLength(1));
        expect(separators.single.label, 'Today');
        expect(find.text('First today'), findsOneWidget);
        expect(find.text('Second today'), findsOneWidget);
      },
    );

    testWidgets(
      'emits one separator per day even when a quoted reply reorders across a '
      'day boundary',
      (tester) async {
        // Tall surface so every reordered row builds.
        tester.view.physicalSize = const Size(1200, 4000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        // Two calendar days. Reply 'r' is stamped on the EARLIER day (dayA)
        // but quotes parent 'p' on the LATER day (dayB); the timeline ordering
        // pulls the reply after its parent, producing a non-monotonic day
        // sequence [A, B, A] in render order.
        final todayMidnight = DateTime(
          DateTime.now().year,
          DateTime.now().month,
          DateTime.now().day,
        );
        final dayA = todayMidnight.subtract(const Duration(days: 5));
        final dayB = dayA.add(const Duration(days: 1));

        await msgRepo.saveMessage(
          makeMessage(
            id: 'l',
            text: 'Leading dayA message',
            timestamp: dayA.add(const Duration(hours: 9)),
          ),
        );
        await msgRepo.saveMessage(
          makeMessage(
            id: 'p',
            text: 'Parent on dayB',
            timestamp: dayB.add(const Duration(hours: 8)),
          ),
        );
        await msgRepo.saveMessage(
          makeMessage(
            id: 'r',
            text: 'Reply stamped on dayA',
            timestamp: dayA.add(const Duration(hours: 23, minutes: 59)),
            quotedMessageId: 'p',
          ),
        );

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester);

        final labels = tester
            .widgetList<DateSeparator>(find.byType(DateSeparator))
            .map((s) => s.label)
            .toList();

        // Two distinct calendar days -> exactly two separators, no duplicates.
        expect(labels.toSet(), hasLength(2));
        expect(
          labels,
          hasLength(labels.toSet().length),
          reason: 'a calendar day must not receive a duplicate separator',
        );
      },
    );

    testWidgets('sending a message calls bridge and refreshes', (tester) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      await saveActiveGroupMembers(groupRepo, group);

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester);
      expect(msgRepo.getMessagesPageCalls, 1);

      // Type a message
      final textField = find.byType(TextField);
      expect(textField, findsOneWidget);
      await tester.enterText(textField, 'Test message');
      await pumpFrames(tester);

      // Tap send button (the arrow_upward_rounded icon inside ComposeArea)
      final sendButton = find.byIcon(Icons.arrow_upward_rounded);
      expect(sendButton, findsOneWidget);
      await tester.tap(sendButton);
      await pumpFrames(tester, count: 20);

      // Verify bridge received group:publish command
      expect(bridge.commandLog, contains('group:publish'));
      expect(msgRepo.getMessagesPageCalls, greaterThanOrEqualTo(1));

      // The sent message should appear in the list
      expect(find.text('Test message'), findsOneWidget);
    });

    testWidgets(
      'blocks a second text send while the first local send is in flight and releases after success',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        final gatedBridge = _GatedPublishBridge();
        bridge = gatedBridge;

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester, count: 20);

        await tester.enterText(find.byType(TextField), 'First send');
        await pumpFrames(tester);
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpUntil(
          tester,
          () => tester
              .widget<GroupConversationScreen>(
                find.byType(GroupConversationScreen),
              )
              .isSending,
        );
        await pumpFrames(tester, count: 5);

        expect(find.text('First send'), findsOneWidget);

        await tester.enterText(find.byType(TextField), 'Second send');
        await pumpFrames(tester);
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpFrames(tester, count: 5);

        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'Second send',
        );
        expect(find.text('Second send'), findsOneWidget);
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:publish').length,
          0,
        );

        gatedBridge.publishGate.complete();
        await pumpFrames(tester, count: 20);

        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:publish').length,
          1,
        );
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpFrames(tester, count: 20);

        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:publish').length,
          2,
        );
      },
    );

    testWidgets(
      'voice send blocks text send while the voice pipeline is active and releases after failure',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);

        final tempDir = Directory.systemTemp.createTempSync(
          'group-voice-send-guard-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final recorder = FakeAudioRecorderService()..fakeDurationMs = 1500;
        final voiceFile = File(p.join(tempDir.path, 'voice.m4a'))
          ..writeAsStringSync('voice');
        recorder.fakeOutputPath = voiceFile.path;
        final mediaFileManager = TrackingDurableMediaFileManager(tempDir);
        final uploadStarted = Completer<void>();
        final uploadGate = Completer<void>();

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            audioRecorderService: recorder,
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                  deleteSourceWhenDone = false,
                  preparedArtifact,
                }) async {
                  if (!uploadStarted.isCompleted) {
                    uploadStarted.complete();
                  }
                  await uploadGate.future;
                  return null;
                },
          ),
        );
        await pumpFrames(tester, count: 20);
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen.mediaMap.containsKey('msg-incoming-no-key') &&
              screen.mediaMap.containsKey('msg-outgoing-no-key');
        });

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final startRecording = screen.onRecordStart! as Future<void> Function();
        await startRecording();
        await pumpUntil(
          tester,
          () =>
              tester
                  .widget<GroupConversationScreen>(
                    find.byType(GroupConversationScreen),
                  )
                  .recordingState ==
              VoiceRecordingState.recording,
        );

        final recordingScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final stopRecording =
            recordingScreen.onRecordStop! as Future<void> Function();
        late Future<void> stopFuture;
        await tester.runAsync(() async {
          stopFuture = stopRecording();
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.runAsync(() async {
          await uploadStarted.future.timeout(_uploadStartCeiling);
        });
        expect(uploadStarted.isCompleted, isTrue);
        await pumpFrames(tester, count: 5);
        await pumpUntil(
          tester,
          () => tester
              .widget<GroupConversationScreen>(
                find.byType(GroupConversationScreen),
              )
              .isSending,
        );
        expect(uploadStarted.isCompleted, isTrue);
        expect(
          tester
              .widget<GroupConversationScreen>(
                find.byType(GroupConversationScreen),
              )
              .isSending,
          isTrue,
        );
        await pumpFrames(tester, count: 5);

        await tester.enterText(find.byType(TextField), 'Blocked text send');
        await pumpFrames(tester);
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpFrames(tester, count: 5);

        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'Blocked text send',
        );
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:publish'),
          isEmpty,
        );

        uploadGate.complete();
        await tester.runAsync(() async {
          await stopFuture;
        });
        await pumpFrames(tester, count: 20);

        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpFrames(tester, count: 20);

        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:publish').length,
          1,
        );
      },
    );

    testWidgets(
      'media uploads pre-persist upload_pending rows before each serialized durable upload',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);

        final tempDir = Directory.systemTemp.createTempSync('group-media-');
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final files = [
          File('${tempDir.path}/one.jpg')
            ..writeAsBytesSync(validJpegFixtureBytes),
          File('${tempDir.path}/two.jpg')
            ..writeAsBytesSync(validJpegFixtureBytes),
          File('${tempDir.path}/three.jpg')
            ..writeAsBytesSync(validJpegFixtureBytes),
        ];

        final testMediaFileManager = FakeMediaFileManager();
        final uploadStarts = <String>[];
        final seenBlobIds = <String>[];
        final pendingSeenBeforeUpload = <bool>[];
        final uploadReleases = List<Completer<void>>.generate(
          files.length,
          (_) => Completer<void>(),
        );
        addTearDown(() {
          for (final release in uploadReleases) {
            if (!release.isCompleted) {
              release.complete();
            }
          }
          mediaAttachmentRepo.onSaveAttachment = null;
        });

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: testMediaFileManager,
            initialAttachments: files,
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                  deleteSourceWhenDone = false,
                  preparedArtifact,
                }) async {
                  final uploadIndex = uploadStarts.length;
                  uploadStarts.add(blobId!);
                  seenBlobIds.add(blobId);
                  final pending = await mediaAttachmentRepo
                      .getUploadPendingAttachments(owner: MediaOwnerLane.group);
                  pendingSeenBeforeUpload.add(pending.isNotEmpty);
                  expect(
                    pending.every(
                      (att) =>
                          att.downloadStatus == 'upload_pending' &&
                          att.size > 0 &&
                          (att.localPath?.startsWith('pending_uploads/') ??
                              false),
                    ),
                    isTrue,
                  );
                  await uploadReleases[uploadIndex].future;
                  return MediaAttachment(
                    id: 'server-assigned-${seenBlobIds.length}',
                    messageId: '',
                    mime: mime,
                    size: 1,
                    mediaType: MediaAttachment.mediaTypeFromMime(mime),
                    localPath: mediaFileManager?.relativePathForAttachment(
                      contactPeerId: group.id,
                      blobId: blobId,
                      mime: mime,
                    ),
                    downloadStatus: 'done',
                    contentHash: _validContentHash,
                    encryptionKeyBase64: 'key-fixture',
                    encryptionNonce: 'nonce-fixture',
                    encryptionScheme:
                        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                    createdAt: DateTime.now().toUtc().toIso8601String(),
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        final sendFuture = await startScreenSend(tester, 'Durable media');
        await pumpUntilAsyncWorkSettles(tester, () => uploadStarts.length == 1);
        expect(uploadStarts, hasLength(1));
        uploadReleases[0].complete();
        await pumpUntilAsyncWorkSettles(tester, () => uploadStarts.length == 2);
        expect(uploadStarts, hasLength(2));
        uploadReleases[1].complete();
        await pumpUntilAsyncWorkSettles(tester, () => uploadStarts.length == 3);
        expect(uploadStarts, hasLength(3));
        expect(pendingSeenBeforeUpload.every((seen) => seen), isTrue);
        expect(seenBlobIds.toSet(), hasLength(3));

        uploadReleases[2].complete();
        await tester.runAsync(() async {
          await sendFuture.future;
        });
        await pumpFrames(tester, count: 5);
      },
    );

    testWidgets(
      'PL-005 ordinary media upload allowedPeers match active membership at upload time',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: testIdentity.peerId,
            username: testIdentity.username,
            role: MemberRole.admin,
            publicKey: testIdentity.publicKey,
            mlKemPublicKey: testIdentity.mlKemPublicKey,
            joinedAt: DateTime.utc(2026, 5, 14, 10),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: 'peer-bob',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-peer-bob',
            mlKemPublicKey: 'mlkem-peer-bob',
            joinedAt: DateTime.utc(2026, 5, 14, 10, 1),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: 'peer-charlie',
            username: 'Charlie',
            role: MemberRole.writer,
            publicKey: 'pk-peer-charlie',
            mlKemPublicKey: 'mlkem-peer-charlie',
            joinedAt: DateTime.utc(2026, 5, 14, 10, 2),
          ),
        );
        await groupRepo.removeMember(group.id, 'peer-charlie');

        final tempDir = Directory.systemTemp.createTempSync(
          'pl005-group-media-acl-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final file = File('${tempDir.path}/pl005.jpg')
          ..writeAsBytesSync(validJpegFixtureBytes);
        final capturedAllowedPeers = <List<String>>[];

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: FakeMediaFileManager(),
            initialAttachments: [file],
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                  deleteSourceWhenDone = false,
                  preparedArtifact,
                }) async {
                  capturedAllowedPeers.add(List<String>.from(allowedPeers!));
                  return MediaAttachment(
                    id: blobId!,
                    messageId: '',
                    mime: mime,
                    size: 1,
                    mediaType: MediaAttachment.mediaTypeFromMime(mime),
                    localPath: localFilePath,
                    downloadStatus: 'done',
                    contentHash: _validContentHash,
                    encryptionKeyBase64: 'key-fixture',
                    encryptionNonce: 'nonce-fixture',
                    encryptionScheme:
                        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                    createdAt: DateTime.now().toUtc().toIso8601String(),
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        final sendFuture = await startScreenSend(tester, 'PL-005 media');
        await tester.runAsync(() async {
          await sendFuture.future;
        });
        await pumpFrames(tester, count: 10);

        expect(capturedAllowedPeers, hasLength(1));
        expect(capturedAllowedPeers.single, [testIdentity.peerId, 'peer-bob']);
        expect(capturedAllowedPeers.single, isNot(contains('peer-charlie')));
        expect(capturedAllowedPeers.single, isNot(contains('peer-dave')));
      },
    );

    testWidgets(
      'P268 production chat and announcement media send ordinary without a private selector',
      (tester) async {
        final tempDir = Directory.systemTemp.createTempSync(
          'p268-group-types-ordinary-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final scenarios = <({String label, GroupModel group})>[
          (label: 'discussion', group: makeChatGroup()),
          (
            label: 'announcement',
            group: makeAnnouncementGroup(role: GroupRole.admin),
          ),
        ];

        for (final scenario in scenarios) {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pump();
          groupRepo = InMemoryGroupRepository();
          msgRepo = CountingGroupMessageRepository();
          mediaAttachmentRepo = CountingMediaAttachmentRepository();
          msgRepo.manualRearmMediaRepo = mediaAttachmentRepo;
          bridge = FakeBridge(
            initialResponses: {
              'group:publish': {'ok': true, 'messageId': 'msg-published'},
            },
          );
          final group = scenario.group;
          await groupRepo.saveGroup(group);
          await groupRepo.saveKey(
            GroupKeyInfo(
              groupId: group.id,
              keyGeneration: 1,
              encryptedKey: 'p268-${scenario.label}-key',
              createdAt: DateTime.utc(2026, 7, 21, 12),
            ),
          );
          await saveActiveGroupMembers(groupRepo, group);
          final file = File('${tempDir.path}/${scenario.label}.jpg')
            ..writeAsBytesSync(validJpegFixtureBytes);
          var uploadCalls = 0;

          await tester.pumpWidget(
            buildWidget(
              group: group,
              mediaRepo: mediaAttachmentRepo,
              mediaFileManager: FakeMediaFileManager(),
              initialPendingMedia: <PendingComposerMedia>[
                PendingComposerMedia(
                  file: file,
                  budgetBytes: file.lengthSync(),
                ),
              ],
              privateMediaAvailability:
                  const GroupPrivateMediaAvailability.enabledForTesting(),
              uploadMediaFn:
                  ({
                    required bridge,
                    required localFilePath,
                    required mime,
                    required recipientPeerId,
                    String? blobId,
                    mediaFileManager,
                    width,
                    height,
                    durationMs,
                    waveform,
                    allowedPeers,
                    deleteSourceWhenDone = false,
                    preparedArtifact,
                  }) async {
                    uploadCalls++;
                    return successfulGroupUploadFixture(
                      blobId: blobId!,
                      mime: mime,
                      localFilePath: localFilePath,
                    );
                  },
            ),
          );
          await pumpFrames(tester, count: 20);

          expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
          expect(find.byType(ComposeArea), findsOneWidget);
          expect(
            find.byKey(const ValueKey('group-private-media-selector')),
            findsNothing,
            reason:
                '${scenario.label} fresh media must expose no private selector',
          );

          final send =
              tester
                      .widget<GroupConversationScreen>(
                        find.byType(GroupConversationScreen),
                      )
                      .onSend
                  as Future<void> Function(String);
          await tester.runAsync(() => send(''));
          await pumpFrames(tester, count: 20);

          final rows = await msgRepo.getMessagesPage(group.id);
          expect(rows, hasLength(1), reason: scenario.label);
          final sent = rows.single;
          expect(uploadCalls, 1, reason: scenario.label);
          expect(sent.status, 'sent', reason: scenario.label);
          expect(sent.privateMediaPolicy.isOrdinary, isTrue);
          final attachments = await mediaAttachmentRepo
              .getAttachmentsForMessage(sent.id, owner: MediaOwnerLane.group);
          expect(attachments, hasLength(1), reason: scenario.label);
          expect(attachments.single.downloadStatus, 'done');
          expectNoGroupPrivateWireKeys([
            (
              boundary: '${scenario.label} reliable',
              payload: groupSendReliablePayloadForMessage(bridge, sent.id),
            ),
            (
              boundary: '${scenario.label} publish',
              payload: groupPublishPayloadForMessage(bridge, sent.id),
            ),
            (
              boundary: '${scenario.label} replay',
              payload: groupReplayPlaintextForMessage(bridge, sent.id),
            ),
          ]);
        }
      },
    );

    test(
      'P268 group composer source has no private authoring API or mutable policy state',
      () {
        final screenSource = File(
          'lib/features/groups/presentation/screens/group_conversation_screen.dart',
        ).readAsStringSync();
        final wiredSource = File(
          'lib/features/groups/presentation/screens/group_conversation_wired.dart',
        ).readAsStringSync();
        final composerControllerSource = File(
          'lib/shared/widgets/conversation/'
          'conversation_composer_controller.dart',
        ).readAsStringSync();
        final screenAuthoringSlice = screenSource.substring(
          screenSource.indexOf('class GroupConversationScreen '),
          screenSource.indexOf('class _GroupConversationLoadingShell '),
        );
        final wiredWidgetSlice = wiredSource.substring(
          wiredSource.indexOf('class GroupConversationWired '),
          wiredSource.indexOf('class _GroupConversationWiredState '),
        );
        final wiredStateSlice = wiredSource.substring(
          wiredSource.indexOf('class _GroupConversationWiredState '),
        );
        final snapshotSlice = composerControllerSource.substring(
          composerControllerSource.indexOf(
            'class ConversationComposerSnapshot ',
          ),
          composerControllerSource.indexOf(
            'class ConversationComposerController ',
          ),
        );

        expect(
          screenSource.contains('private_media_policy_picker_sheet.dart'),
          isFalse,
          reason: 'the group screen must not import the shared private picker',
        );
        for (final forbidden in const <String>[
          'privateMediaComposerEligible',
          'onPrivateMediaPolicyChanged',
          '_GroupPrivateMediaSelector',
          'showPrivateMediaPolicyPickerSheet',
          'PrivateMediaSummaryChip',
          'final GroupPrivateMediaPolicy privateMediaPolicy;',
          'this.privateMediaPolicy = const GroupPrivateMediaPolicy.ordinary(),',
        ]) {
          expect(
            screenAuthoringSlice.contains(forbidden),
            isFalse,
            reason: 'group screen retains private authoring seam $forbidden',
          );
        }
        for (final forbidden in const <String>[
          'final GroupPrivateMediaPolicy privateMediaPolicy;',
          'this.privateMediaPolicy = const GroupPrivateMediaPolicy.ordinary(),',
        ]) {
          expect(
            wiredWidgetSlice.contains(forbidden),
            isFalse,
            reason:
                'wired constructor retains private authoring seam $forbidden',
          );
        }
        for (final forbidden in const <String>[
          'widget.privateMediaPolicy',
          '_privateMediaPolicy',
          '_privateMediaComposerEligible',
          '_onPrivateMediaPolicyChanged',
        ]) {
          expect(
            wiredStateSlice.contains(forbidden),
            isFalse,
            reason: 'wired state retains private authoring seam $forbidden',
          );
        }
        expect(snapshotSlice.contains('privateMediaPolicy'), isFalse);
        expect(snapshotSlice.contains('GroupPrivateMediaPolicy'), isFalse);
      },
    );

    testWidgets(
      'P268 second group attachment cannot inherit a hidden private mode or stall send',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        final tempDir = Directory.systemTemp.createTempSync(
          'p268-second-attachment-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final first = File('${tempDir.path}/first.jpg')
          ..writeAsBytesSync(validJpegFixtureBytes);
        final second = File('${tempDir.path}/second.jpg')
          ..writeAsBytesSync(validJpegFixtureBytes);
        final picker = FakeMediaPicker()
          ..multipleMediaResult = <XFile>[XFile(second.path)];
        var uploadCalls = 0;

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaPicker: picker,
            mediaFileManager: FakeMediaFileManager(),
            initialPendingMedia: <PendingComposerMedia>[
              PendingComposerMedia(
                file: first,
                budgetBytes: first.lengthSync(),
              ),
            ],
            privateMediaAvailability:
                const GroupPrivateMediaAvailability.enabledForTesting(),
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                  deleteSourceWhenDone = false,
                  preparedArtifact,
                }) async {
                  uploadCalls++;
                  return successfulGroupUploadFixture(
                    blobId: blobId!,
                    mime: mime,
                    localFilePath: localFilePath,
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);
        await commitProtectedIfGroupSelectorExists(tester);

        await tester.tap(find.byIcon(Icons.add_rounded));
        await tester.pump(const Duration(milliseconds: 500));
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Media Library'))
            .onTap!();
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen
                  .composerStateListenable
                  ?.value
                  .pendingAttachments
                  .length ==
              2;
        });
        expect(
          find.byKey(const ValueKey('group-private-media-selector')),
          findsNothing,
        );

        final send = await startScreenSend(tester, '');
        await tester.runAsync(() => send.future);
        await pumpFrames(tester, count: 20);
        final sendActivity = (
          uploadCalls: uploadCalls,
          reliableCalls: bridge.commandLog
              .where((command) => command == 'group:sendReliable')
              .length,
          publishCalls: bridge.commandLog
              .where((command) => command == 'group:publish')
              .length,
        );
        expect(
          sendActivity,
          equals((uploadCalls: 2, reliableCalls: 1, publishCalls: 1)),
          reason:
              'a stale hidden private mode currently returns before upload and publication',
        );

        final rows = await msgRepo.getMessagesPage(group.id);
        expect(rows, hasLength(1));
        final sent = rows.single;
        expect(sent.status, 'sent');
        expect(sent.privateMediaPolicy.isOrdinary, isTrue);
        final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
          sent.id,
          owner: MediaOwnerLane.group,
        );
        expect(attachments, hasLength(2));
        expect(
          attachments.every(
            (attachment) => attachment.downloadStatus == 'done',
          ),
          isTrue,
        );
        expectNoGroupPrivateWireKeys([
          (
            boundary: 'second attachment reliable',
            payload: groupSendReliablePayloadForMessage(bridge, sent.id),
          ),
          (
            boundary: 'second attachment publish',
            payload: groupPublishPayloadForMessage(bridge, sent.id),
          ),
          (
            boundary: 'second attachment replay',
            payload: groupReplayPlaintextForMessage(bridge, sent.id),
          ),
        ]);
      },
    );

    testWidgets(
      'P268 projected media failure restores ordinary and resends the same parent',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        final projectionRepo = _TerminalProjectionGroupMessageRepository(
          mediaRepo: mediaAttachmentRepo,
        );
        final tempDir = Directory.systemTemp.createTempSync(
          'p268-projected-resend-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final file = File('${tempDir.path}/one.png')
          ..writeAsBytesSync(_tinyPngBytes);
        final uploadedBlobIds = <String>[];
        var uploadCalls = 0;

        await tester.pumpWidget(
          buildWidget(
            group: group,
            messageRepo: projectionRepo,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: FakeMediaFileManager(),
            initialPendingMedia: <PendingComposerMedia>[
              PendingComposerMedia(file: file, budgetBytes: file.lengthSync()),
            ],
            privateMediaAvailability:
                const GroupPrivateMediaAvailability.enabledForTesting(),
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                  deleteSourceWhenDone = false,
                  preparedArtifact,
                }) async {
                  uploadCalls++;
                  uploadedBlobIds.add(blobId!);
                  if (uploadCalls == 1) return null;
                  return successfulGroupUploadFixture(
                    blobId: blobId,
                    mime: mime,
                    localFilePath: localFilePath,
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);
        final selectedProtectedOnHead =
            await commitProtectedIfGroupSelectorExists(tester);

        final firstSend = await startScreenSend(tester, '');
        await tester.runAsync(() => firstSend.future);
        await pumpFrames(tester, count: 20);
        expect(projectionRepo.projectionCalls, 1);
        expect(
          projectionRepo.lastFailure?.disposition,
          UploadMediaDisposition.terminal,
        );
        final restoredSelector = find.byKey(
          const ValueKey('group-private-media-selector'),
        );
        final restoredPrivateUi =
            selectedProtectedOnHead &&
            restoredSelector.evaluate().isNotEmpty &&
            find
                .descendant(
                  of: restoredSelector,
                  matching: find.text('Protected view'),
                )
                .evaluate()
                .isNotEmpty;
        expect(find.byType(AttachmentPreviewStrip), findsOneWidget);

        final failedRows = await projectionRepo.getMessagesPage(group.id);
        expect(failedRows, hasLength(1));
        final failedParent = failedRows.single;
        expect(failedParent.status, 'failed');
        final originalMessageId = failedParent.id;
        final originalTimestamp = failedParent.timestamp;
        final failedAttachments = await mediaAttachmentRepo
            .getAttachmentsForMessage(
              originalMessageId,
              owner: MediaOwnerLane.group,
            );
        expect(failedAttachments, hasLength(1));
        expect(failedAttachments.single.downloadStatus, 'upload_failed');
        final failedAttachmentId = failedAttachments.single.id;

        final secondSend = await startScreenSend(tester, '');
        await tester.runAsync(() => secondSend.future);
        await pumpFrames(tester, count: 20);

        final finalRows = await projectionRepo.getMessagesPage(group.id);
        final sentRows = finalRows
            .where((message) => message.status == 'sent')
            .toList(growable: false);
        final finalSent = sentRows.length == 1 ? sentRows.single : null;
        final continuationEvidence = (
          restoredPrivateUi: restoredPrivateUi,
          rowCount: finalRows.length,
          sentCount: sentRows.length,
          sentId: finalSent?.id,
          sentTimestamp: finalSent?.timestamp,
          sentOrdinary: finalSent?.privateMediaPolicy.isOrdinary,
        );
        expect(
          continuationEvidence,
          equals((
            restoredPrivateUi: false,
            rowCount: 1,
            sentCount: 1,
            sentId: originalMessageId,
            sentTimestamp: originalTimestamp,
            sentOrdinary: true,
          )),
          reason:
              'projected terminal restoration must clear private state and continue the failed parent',
        );

        expect(uploadedBlobIds, hasLength(2));
        final finalAttachments = await mediaAttachmentRepo
            .getAttachmentsForMessage(
              originalMessageId,
              owner: MediaOwnerLane.group,
            );
        expect(finalAttachments, hasLength(1));
        expect(finalAttachments.single.id, uploadedBlobIds.last);
        expect(finalAttachments.single.downloadStatus, 'done');
        expect(
          await mediaAttachmentRepo.getAttachmentById(failedAttachmentId),
          isNull,
        );
        expectNoGroupPrivateWireKeys([
          (
            boundary: 'projected resend reliable',
            payload: groupSendReliablePayloadForMessage(
              bridge,
              originalMessageId,
            ),
          ),
          (
            boundary: 'projected resend publish',
            payload: groupPublishPayloadForMessage(bridge, originalMessageId),
          ),
          (
            boundary: 'projected resend replay',
            payload: groupReplayPlaintextForMessage(bridge, originalMessageId),
          ),
        ]);
      },
    );

    testWidgets(
      'P268 projected first-of-two media failure restores both and resends the same parent',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        final projectionRepo = _TerminalProjectionGroupMessageRepository(
          mediaRepo: mediaAttachmentRepo,
        );
        final tempDir = Directory.systemTemp.createTempSync(
          'p268-projected-two-resend-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final firstFile = File('${tempDir.path}/one.png')
          ..writeAsBytesSync(_tinyPngBytes);
        final secondFile = File('${tempDir.path}/two.png')
          ..writeAsBytesSync(_tinyPngBytes);
        final uploadedBlobIds = <String>[];
        var uploadCalls = 0;

        await tester.pumpWidget(
          buildWidget(
            group: group,
            messageRepo: projectionRepo,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: FakeMediaFileManager(),
            initialPendingMedia: <PendingComposerMedia>[
              PendingComposerMedia(
                file: firstFile,
                budgetBytes: firstFile.lengthSync(),
              ),
              PendingComposerMedia(
                file: secondFile,
                budgetBytes: secondFile.lengthSync(),
              ),
            ],
            privateMediaAvailability:
                const GroupPrivateMediaAvailability.enabledForTesting(),
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                  deleteSourceWhenDone = false,
                  preparedArtifact,
                }) async {
                  uploadCalls++;
                  uploadedBlobIds.add(blobId!);
                  if (uploadCalls == 1) return null;
                  return successfulGroupUploadFixture(
                    blobId: blobId,
                    mime: mime,
                    localFilePath: localFilePath,
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        final firstSend = await startScreenSend(tester, '');
        await tester.runAsync(() => firstSend.future);
        await pumpFrames(tester, count: 20);
        expect(projectionRepo.projectionCalls, 1);
        expect(
          projectionRepo.lastFailure?.disposition,
          UploadMediaDisposition.terminal,
        );

        final restoredScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final restoredAttachmentCount =
            restoredScreen
                .composerStateListenable
                ?.value
                .pendingAttachments
                .length ??
            0;
        final failedRows = await projectionRepo.getMessagesPage(group.id);
        expect(failedRows, hasLength(1));
        final failedParent = failedRows.single;
        expect(failedParent.status, 'failed');
        expect(failedParent.privateMediaPolicy.isOrdinary, isTrue);
        final originalMessageId = failedParent.id;
        final originalTimestamp = failedParent.timestamp;
        final failedAttachments = await mediaAttachmentRepo
            .getAttachmentsForMessage(
              originalMessageId,
              owner: MediaOwnerLane.group,
            );
        expect(failedAttachments, hasLength(1));
        expect(failedAttachments.single.downloadStatus, 'upload_failed');
        final failedAttachmentId = failedAttachments.single.id;

        final secondSend = await startScreenSend(tester, '');
        await tester.runAsync(() => secondSend.future);
        await pumpFrames(tester, count: 20);

        final finalRows = await projectionRepo.getMessagesPage(group.id);
        final sentRows = finalRows
            .where((message) => message.status == 'sent')
            .toList(growable: false);
        final finalSent = sentRows.length == 1 ? sentRows.single : null;
        final finalAttachments = await mediaAttachmentRepo
            .getAttachmentsForMessage(
              originalMessageId,
              owner: MediaOwnerLane.group,
            );
        final finalAttachmentIds =
            finalAttachments
                .map((attachment) => attachment.id)
                .toList(growable: false)
              ..sort();
        final replacementBlobIds = uploadedBlobIds.length == 3
            ? (uploadedBlobIds.sublist(1)..sort())
            : <String>[];
        final continuationEvidence = (
          restoredAttachmentCount: restoredAttachmentCount,
          uploadCalls: uploadCalls,
          uploadedBlobIdCount: uploadedBlobIds.length,
          rowCount: finalRows.length,
          sentCount: sentRows.length,
          sentId: finalSent?.id,
          sentTimestamp: finalSent?.timestamp,
          sentOrdinary: finalSent?.privateMediaPolicy.isOrdinary,
          finalAttachmentCount: finalAttachments.length,
          allFinalAttachmentsDone: finalAttachments.every(
            (attachment) => attachment.downloadStatus == 'done',
          ),
          replacementIdsMatch:
              finalAttachmentIds.join('|') == replacementBlobIds.join('|'),
          failedAttachmentRemoved:
              await mediaAttachmentRepo.getAttachmentById(failedAttachmentId) ==
              null,
        );
        expect(
          continuationEvidence,
          equals((
            restoredAttachmentCount: 2,
            uploadCalls: 3,
            uploadedBlobIdCount: 3,
            rowCount: 1,
            sentCount: 1,
            sentId: originalMessageId,
            sentTimestamp: originalTimestamp,
            sentOrdinary: true,
            finalAttachmentCount: 2,
            allFinalAttachmentsDone: true,
            replacementIdsMatch: true,
            failedAttachmentRemoved: true,
          )),
          reason:
              'a terminal first-of-two projection must restore the whole draft and continue the exact failed parent',
        );

        expectNoGroupPrivateWireKeys([
          (
            boundary: 'projected two-item resend reliable',
            payload: groupSendReliablePayloadForMessage(
              bridge,
              originalMessageId,
            ),
          ),
          (
            boundary: 'projected two-item resend publish',
            payload: groupPublishPayloadForMessage(bridge, originalMessageId),
          ),
          (
            boundary: 'projected two-item resend replay',
            payload: groupReplayPlaintextForMessage(bridge, originalMessageId),
          ),
        ]);
      },
    );

    testWidgets(
      'ordinary media pre-persists the parent row before upload completes and finalizes after sendGroupMessage',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);

        final tempDir = Directory.systemTemp.createTempSync(
          'group-media-parent-row-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final file = File('${tempDir.path}/one.jpg')
          ..writeAsBytesSync(validJpegFixtureBytes);
        final testMediaFileManager = FakeMediaFileManager();
        final deletedDirs = <String>[];
        testMediaFileManager.onDeletePendingUploadDir = deletedDirs.add;
        final uploadStarted = Completer<void>();
        final uploadGate = Completer<void>();
        String? receivedBlobId;

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: testMediaFileManager,
            initialAttachments: [file],
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                  deleteSourceWhenDone = false,
                  preparedArtifact,
                }) async {
                  receivedBlobId = blobId;
                  if (!uploadStarted.isCompleted) {
                    uploadStarted.complete();
                  }
                  await uploadGate.future;
                  return MediaAttachment(
                    id: 'server-media-parent-row',
                    messageId: '',
                    mime: mime,
                    size: 1,
                    mediaType: MediaAttachment.mediaTypeFromMime(mime),
                    localPath: mediaFileManager?.relativePathForAttachment(
                      contactPeerId: group.id,
                      blobId: blobId!,
                      mime: mime,
                    ),
                    downloadStatus: 'done',
                    contentHash: _validContentHash,
                    encryptionKeyBase64: 'key-fixture',
                    encryptionNonce: 'nonce-fixture',
                    encryptionScheme:
                        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                    createdAt: DateTime.now().toUtc().toIso8601String(),
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final sendMessage = screen.onSend as Future<void> Function(String);
        late Future<void> sendFuture;
        await tester.runAsync(() async {
          sendFuture = sendMessage('Durable parent row');
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await pumpUntil(tester, () => uploadStarted.isCompleted);
        await pumpFrames(tester, count: 5);

        final pending = await mediaAttachmentRepo.getUploadPendingAttachments(
          owner: MediaOwnerLane.group,
        );
        expect(pending, hasLength(1));
        final messageId = pending.single.messageId;
        expect(pending.single.id, receivedBlobId);
        expect(pending.single.downloadStatus, 'upload_pending');
        expect(pending.single.localPath, startsWith('pending_uploads/'));

        final persistedBeforeUpload = await msgRepo.getMessage(messageId);
        expect(persistedBeforeUpload, isNotNull);
        expect(persistedBeforeUpload!.text, 'Durable parent row');
        expect(persistedBeforeUpload.status, 'sending');
        expect(persistedBeforeUpload.privateMediaPolicy.isOrdinary, isTrue);

        await tester.runAsync(() async {
          uploadGate.complete();
          await sendFuture;
        });
        await pumpFrames(tester, count: 20);

        final persistedAfterSend = await msgRepo.getMessage(messageId);
        expect(persistedAfterSend, isNotNull);
        expect(persistedAfterSend!.status, 'sent');
        expect(persistedAfterSend.privateMediaPolicy.isOrdinary, isTrue);
        expect(
          await mediaAttachmentRepo.getUploadPendingAttachments(
            owner: MediaOwnerLane.group,
          ),
          isEmpty,
        );
        final savedAttachments = await mediaAttachmentRepo
            .getAttachmentsForMessage(messageId, owner: MediaOwnerLane.group);
        expect(savedAttachments, hasLength(1));
        expect(savedAttachments.single.id, receivedBlobId);
        expect(savedAttachments.single.downloadStatus, 'done');
        expect(deletedDirs, contains(messageId));
        expectNoGroupPrivateWireKeys([
          (
            boundary: 'ordinary media reliable',
            payload: groupSendReliablePayloadForMessage(bridge, messageId),
          ),
          (
            boundary: 'ordinary media publish',
            payload: groupPublishPayloadForMessage(bridge, messageId),
          ),
          (
            boundary: 'ordinary media replay',
            payload: groupReplayPlaintextForMessage(bridge, messageId),
          ),
        ]);
      },
    );

    test(
      'GPL-11V private viewer controller lifetime is screen-owned and independent of recorder auto-stop',
      () {
        final source = File(
          'lib/features/groups/presentation/screens/group_conversation_wired.dart',
        ).readAsStringSync();
        final autoStop = source.substring(
          source.indexOf('void _onVoiceCaptureAutoStopOutcome('),
          source.indexOf('void _forceCancelActiveRecording('),
        );
        final dispose = source.substring(
          source.indexOf('void dispose() {'),
          source.indexOf('String get _activeGroupConversationKey'),
        );
        expect(autoStop, isNot(contains('_lazyPrivateMediaViewerController')));
        expect(autoStop, isNot(contains('privateController.dispose()')));
        expect(dispose, contains('_lazyPrivateMediaViewerController'));
        expect(dispose, contains('unawaited(privateController.dispose())'));
      },
    );

    testWidgets(
      'P268 ordinary wired upload cannot replace a parent drifted while upload is in flight',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        final tempDir = Directory.systemTemp.createTempSync(
          'group-ordinary-upload-parent-drift-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final file = File('${tempDir.path}/private.png')
          ..writeAsBytesSync(_tinyPngBytes);
        final uploadStarted = Completer<void>();
        final uploadGate = Completer<void>();
        addTearDown(() {
          if (!uploadGate.isCompleted) uploadGate.complete();
        });

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: FakeMediaFileManager(),
            initialAttachments: [file],
            privateMediaAvailability:
                const GroupPrivateMediaAvailability.enabledForTesting(),
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                  deleteSourceWhenDone = false,
                  preparedArtifact,
                }) async {
                  if (!uploadStarted.isCompleted) uploadStarted.complete();
                  await uploadGate.future;
                  return MediaAttachment(
                    id: blobId!,
                    messageId: '',
                    mime: mime,
                    size: 1,
                    mediaType: MediaAttachment.mediaTypeFromMime(mime),
                    localPath: localFilePath,
                    downloadStatus: 'done',
                    contentHash: _validContentHash,
                    encryptionKeyBase64: 'key-fixture',
                    encryptionNonce: 'nonce-fixture',
                    encryptionScheme:
                        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                    createdAt: DateTime.now().toUtc().toIso8601String(),
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final send = screen.onSend as Future<void> Function(String);
        late Future<void> sendFuture;
        await tester.runAsync(() async {
          sendFuture = send('');
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await pumpUntil(tester, () => uploadStarted.isCompleted, maxPumps: 240);
        expect(uploadStarted.isCompleted, isTrue);

        final pending = await mediaAttachmentRepo.getUploadPendingAttachments(
          owner: MediaOwnerLane.group,
        );
        expect(pending, hasLength(1));
        final messageId = pending.single.messageId;
        final durableBeforeDrift = await msgRepo.getMessage(messageId);
        expect(durableBeforeDrift, isNotNull);
        expect(durableBeforeDrift!.privateMediaPolicy.isOrdinary, isTrue);
        await msgRepo.saveMessage(
          durableBeforeDrift.copyWith(senderUsername: 'Drifted sender'),
        );

        await tester.runAsync(() async {
          uploadGate.complete();
          await sendFuture;
        });
        await pumpFrames(tester, count: 10);

        expect(bridge.commandLog, isNot(contains('group:sendReliable')));
        expect(bridge.commandLog, isNot(contains('group:publish')));
        expect(bridge.commandLog, isNot(contains('group:inboxStore')));
        final durableAfterSend = await msgRepo.getMessage(messageId);
        expect(durableAfterSend, isNotNull);
        expect(durableAfterSend!.senderUsername, 'Drifted sender');
        expect(durableAfterSend.privateMediaPolicy.isOrdinary, isTrue);
        final rows = await msgRepo.getMessagesPage(group.id);
        expect(rows, hasLength(1));
        expect(rows.single.id, messageId);
      },
    );

    testWidgets(
      'failed media upload clears retryable durable rows and avoids group publish',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);

        final tempDir = Directory.systemTemp.createTempSync(
          'group-media-fail-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final files = [
          File('${tempDir.path}/one.jpg')
            ..writeAsBytesSync(validJpegFixtureBytes),
          File('${tempDir.path}/two.jpg')
            ..writeAsBytesSync(validJpegFixtureBytes),
          File('${tempDir.path}/three.jpg')
            ..writeAsBytesSync(validJpegFixtureBytes),
        ];

        final testMediaFileManager = FakeMediaFileManager();
        var uploadCount = 0;

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: testMediaFileManager,
            initialAttachments: files,
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                  deleteSourceWhenDone = false,
                  preparedArtifact,
                }) async {
                  uploadCount++;
                  if (uploadCount == 2) return null;
                  return MediaAttachment(
                    id: blobId!,
                    messageId: '',
                    mime: mime,
                    size: 1,
                    mediaType: MediaAttachment.mediaTypeFromMime(mime),
                    localPath: mediaFileManager?.relativePathForAttachment(
                      contactPeerId: group.id,
                      blobId: blobId,
                      mime: mime,
                    ),
                    downloadStatus: 'done',
                    contentHash: _validContentHash,
                    encryptionKeyBase64: 'key-fixture',
                    encryptionNonce: 'nonce-fixture',
                    encryptionScheme:
                        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                    createdAt: DateTime.now().toUtc().toIso8601String(),
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        final sendFuture = await startScreenSend(tester, 'Fail media');
        await tester.runAsync(() async {
          await sendFuture.future;
        });
        await pumpFrames(tester, count: 5);
        expect(bridge.commandLog, isNot(contains('group:publish')));

        expect(
          await mediaAttachmentRepo.getUploadPendingAttachments(
            owner: MediaOwnerLane.group,
          ),
          isEmpty,
        );
        final failedMessage = (await msgRepo.getMessagesPage(
          group.id,
        )).singleWhere((message) => message.text == 'Fail media');
        expect(failedMessage.status, 'failed');
        final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
          failedMessage.id,
          owner: MediaOwnerLane.group,
        );
        expect(attachments, hasLength(3));
        expect(
          attachments.where((att) => att.downloadStatus == 'upload_failed'),
          hasLength(1),
        );
        expect(
          attachments.where((att) => att.downloadStatus == 'done'),
          hasLength(2),
        );
        expect(
          attachments.any((att) => att.downloadStatus == 'upload_pending'),
          isFalse,
        );
      },
    );

    testWidgets(
      'ordinary media upload failure persists failed parent state and restores composer and quote',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-parent-media-upload',
            text: 'Media upload parent',
            groupId: group.id,
            isIncoming: true,
          ),
        );

        final tempDir = Directory.systemTemp.createTempSync(
          'group-media-upload-parent-fail-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final file = File('${tempDir.path}/one.jpg')
          ..writeAsBytesSync(validJpegFixtureBytes);
        final mediaFileManager = FakeMediaFileManager();
        final uploadStarted = Completer<void>();
        final uploadGate = Completer<void>();

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            initialAttachments: [file],
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                  deleteSourceWhenDone = false,
                  preparedArtifact,
                }) async {
                  if (!uploadStarted.isCompleted) {
                    uploadStarted.complete();
                  }
                  await uploadGate.future;
                  return null;
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        screen.onQuoteReply!.call('msg-parent-media-upload');
        await tester.pump();
        expect(find.text('Replying to'), findsOneWidget);

        final sendFuture = await startScreenSend(
          tester,
          'Fail media parent row',
        );
        await pumpUntil(tester, () => uploadStarted.isCompleted);
        await pumpFrames(tester, count: 5);

        final pendingBeforeFail = await mediaAttachmentRepo
            .getUploadPendingAttachments(owner: MediaOwnerLane.group);
        expect(pendingBeforeFail, hasLength(1));
        final messageId = pendingBeforeFail.single.messageId;
        final persistedBeforeFail = await msgRepo.getMessage(messageId);
        expect(persistedBeforeFail, isNotNull);
        expect(persistedBeforeFail!.status, 'sending');
        expect(persistedBeforeFail.quotedMessageId, 'msg-parent-media-upload');

        uploadGate.complete();
        await tester.runAsync(() async {
          await sendFuture.future;
        });
        await pumpFrames(tester, count: 20);

        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'Fail media parent row',
        );
        expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
        expect(find.text('Replying to'), findsOneWidget);
        expect(bridge.commandLog, isNot(contains('group:publish')));

        final persistedAfterFail = await msgRepo.getMessage(messageId);
        expect(persistedAfterFail, isNotNull);
        expect(persistedAfterFail!.status, 'failed');
        expect(persistedAfterFail.quotedMessageId, 'msg-parent-media-upload');

        final pendingAfterFail = await mediaAttachmentRepo
            .getUploadPendingAttachments(owner: MediaOwnerLane.group);
        expect(pendingAfterFail, isEmpty);
        final failedAttachments = await mediaAttachmentRepo
            .getAttachmentsForMessage(messageId, owner: MediaOwnerLane.group);
        expect(failedAttachments, hasLength(1));
        expect(failedAttachments.single.id, pendingBeforeFail.single.id);
        expect(failedAttachments.single.downloadStatus, 'upload_failed');

        final failedScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final failedMessage = failedScreen.messages.singleWhere(
          (message) => message.id == messageId,
        );
        expect(failedMessage.status, 'failed');
        expect(failedMessage.quotedMessageId, 'msg-parent-media-upload');
      },
    );

    testWidgets(
      'dissolved text send keeps a non-retryable failed bubble and flips read-only banner',
      (tester) async {
        // Empty-membership chat group: the row is NOT marked dissolved (so the
        // composer is locally writable) but the use case returns groupDissolved
        // (send_group_message_use_case empty-membership branch).
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester, count: 20);

        await tester.enterText(find.byType(TextField), 'Dissolved send');
        await pumpFrames(tester);
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final retained = screen.messages
            .where((message) => message.text == 'Dissolved send')
            .toList();
        expect(retained, hasLength(1));
        expect(retained.single.status, GroupMessage.statusSendFailed);
        expect(screen.canWrite, isFalse);
        expect(
          find.text("Couldn't send — this group was dissolved"),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('group-read-only-banner')),
            matching: find.text(
              'This group has been dissolved. History stays available, but '
              'new messages are disabled.',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('failed-message-retry-${retained.single.id}')),
          findsNothing,
        );
        expect(
          find.byKey(ValueKey('failed-message-delete-${retained.single.id}')),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(SnackBar, 'This group has been dissolved'),
          findsNothing,
        );
        expect(bridge.commandLog, isNot(contains('group:publish')));
      },
    );

    testWidgets(
      'unauthorized text send keeps failed bubble (removed) and flips read-only banner',
      (tester) async {
        final widgetGroup = makeAnnouncementGroup(role: GroupRole.admin);
        await groupRepo.saveGroup(
          widgetGroup.copyWith(myRole: GroupRole.member),
        );

        await tester.pumpWidget(buildWidget(group: widgetGroup));
        await pumpFrames(tester, count: 20);

        await tester.enterText(
          find.byType(TextField),
          'Unauthorized stale send',
        );
        await pumpFrames(tester);
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final retained = screen.messages
            .where((message) => message.text == 'Unauthorized stale send')
            .toList();
        expect(retained, hasLength(1));
        expect(retained.single.status, GroupMessage.statusSendFailed);
        // Banner-gap RED on HEAD: composer stays writable for unauthorized.
        expect(screen.canWrite, isFalse);
        expect(
          find.text("Couldn't send — you're no longer in this group"),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('group-read-only-banner')),
            matching: find.text(
              'You were removed from this group. You can still read past '
              'messages.',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('failed-message-retry-${retained.single.id}')),
          findsNothing,
        );
        expect(
          find.byKey(ValueKey('failed-message-delete-${retained.single.id}')),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(
            SnackBar,
            'You no longer have permission to send messages in this group.',
          ),
          findsNothing,
        );
        expect(bridge.commandLog, isNot(contains('group:publish')));
      },
    );

    testWidgets(
      'missing-group text send keeps failed bubble (unavailable) and flips read-only banner',
      (tester) async {
        final missingGroup = makeChatGroup();

        await tester.pumpWidget(buildWidget(group: missingGroup));
        await pumpFrames(tester, count: 20);

        await tester.enterText(
          find.byType(TextField),
          'Missing group stale send',
        );
        await pumpFrames(tester);
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final retained = screen.messages
            .where((message) => message.text == 'Missing group stale send')
            .toList();
        expect(retained, hasLength(1));
        expect(retained.single.status, GroupMessage.statusSendFailed);
        expect(screen.canWrite, isFalse);
        expect(
          find.text("Couldn't send — this group is unavailable"),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('group-read-only-banner')),
            matching: find.text('This group is no longer available.'),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey('failed-message-retry-${retained.single.id}')),
          findsNothing,
        );
        expect(
          find.byKey(ValueKey('failed-message-delete-${retained.single.id}')),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(SnackBar, 'This group is no longer available.'),
          findsNothing,
        );
        expect(bridge.commandLog, isNot(contains('group:publish')));
      },
    );

    testWidgets('voice terminal send keeps failed bubble instead of deleting', (
      tester,
    ) async {
      final tempDir = Directory.systemTemp.createTempSync(
        'group-voice-terminal-',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final recorder = FakeAudioRecorderService()..fakeDurationMs = 1500;
      final voiceFile = File(p.join(tempDir.path, 'voice.m4a'))
        ..writeAsStringSync('voice');
      recorder.fakeOutputPath = voiceFile.path;
      final mediaFileManager = TrackingDurableMediaFileManager(tempDir);

      // Start active so the voice upload leaf can complete, then empty the
      // roster in the queued membership phase before final send.
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      await saveActiveGroupMembers(groupRepo, group);
      final uploadStarted = Completer<void>();
      final uploadRelease = Completer<void>();
      addTearDown(() {
        if (!uploadRelease.isCompleted) uploadRelease.complete();
      });

      await tester.pumpWidget(
        buildWidget(
          group: group,
          mediaRepo: mediaAttachmentRepo,
          mediaFileManager: mediaFileManager,
          audioRecorderService: recorder,
          uploadMediaFn:
              ({
                required bridge,
                required localFilePath,
                required mime,
                required recipientPeerId,
                String? blobId,
                mediaFileManager,
                width,
                height,
                durationMs,
                waveform,
                allowedPeers,
                deleteSourceWhenDone = false,
                preparedArtifact,
              }) async {
                if (!uploadStarted.isCompleted) uploadStarted.complete();
                await uploadRelease.future;
                return MediaAttachment(
                  id: blobId!,
                  messageId: '',
                  mime: mime,
                  size: 1,
                  mediaType: MediaAttachment.mediaTypeFromMime(mime),
                  localPath: mediaFileManager?.relativePathForAttachment(
                    contactPeerId: group.id,
                    blobId: blobId,
                    mime: mime,
                  ),
                  downloadStatus: 'done',
                  contentHash: _validContentHash,
                  encryptionKeyBase64: 'key-fixture',
                  encryptionNonce: 'nonce-fixture',
                  encryptionScheme:
                      kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                  durationMs: durationMs,
                  waveform: waveform,
                  createdAt: DateTime.now().toUtc().toIso8601String(),
                );
              },
        ),
      );
      await pumpFrames(tester, count: 20);

      final screen = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      final startRecording = screen.onRecordStart! as Future<void> Function();
      await startRecording();
      await pumpUntil(
        tester,
        () =>
            tester
                .widget<GroupConversationScreen>(
                  find.byType(GroupConversationScreen),
                )
                .recordingState ==
            VoiceRecordingState.recording,
      );

      final recordingScreen = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      final stopRecording =
          recordingScreen.onRecordStop! as Future<void> Function();
      late Future<void> stopFuture;
      await tester.runAsync(() async {
        stopFuture = stopRecording();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.runAsync(() async {
        await uploadStarted.future.timeout(_uploadStartCeiling);
      });
      final emptyRoster = runGroupMembershipMutationLocked<void>(
        groupId: group.id,
        action: () async {
          for (final member in await groupRepo.getMembers(group.id)) {
            await groupRepo.removeMember(group.id, member.peerId);
          }
        },
      );
      uploadRelease.complete();
      await pumpUntilFuturesComplete(tester, [emptyRoster, stopFuture]);
      await pumpFrames(tester, count: 20);

      final after = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      final voiceRows = after.messages
          .where(
            (message) =>
                !message.isIncoming &&
                message.status == GroupMessage.statusSendFailed,
          )
          .toList();
      expect(voiceRows, hasLength(1));
      // The recorded audio attachment is retained (not deleted).
      final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
        voiceRows.single.id,
        owner: MediaOwnerLane.group,
      );
      expect(attachments, isNotEmpty);
      expect(after.canWrite, isFalse);
      expect(
        find.byKey(const ValueKey('group-read-only-banner')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('failed-message-retry-${voiceRows.single.id}')),
        findsNothing,
      );
      expect(
        find.byKey(ValueKey('failed-message-delete-${voiceRows.single.id}')),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(SnackBar, 'This group has been dissolved'),
        findsNothing,
      );
    });

    testWidgets(
      'retry-exhausted send_failed in a writable group shows no terminal reason',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-exhausted',
            text: 'Retry exhausted row',
            groupId: group.id,
            isIncoming: false,
            senderPeerId: testIdentity.peerId,
            senderUsername: testIdentity.username,
            status: GroupMessage.statusSendFailed,
          ),
        );

        await tester.pumpWidget(
          buildWidget(group: group, mediaRepo: mediaAttachmentRepo),
        );
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        // Writable group: the retry-exhausted row keeps the existing send_failed
        // treatment with NO terminal "Couldn't send — group ..." reason.
        expect(screen.canWrite, isTrue);
        expect(find.textContaining("Couldn't send"), findsNothing);
        expect(
          find.byKey(const ValueKey('group-read-only-banner')),
          findsNothing,
        );
        expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
      },
    );

    testWidgets(
      'retry-exhausted send_failed WITH a retry payload still shows Retry in a '
      'writable group (payload-gate non-regression)',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-payload',
            text: 'Retry exhausted but retryable',
            isIncoming: false,
            senderPeerId: testIdentity.peerId,
            senderUsername: testIdentity.username,
            status: GroupMessage.statusSendFailed,
            wireEnvelope: '{"cmd":"group:publish"}',
          ),
        );

        await tester.pumpWidget(
          buildWidget(group: group, mediaRepo: mediaAttachmentRepo),
        );
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.canWrite, isTrue);
        // A payload-bearing retry-exhausted row keeps Retry — the 144 finding-2
        // payload gate only hides Retry for no-payload terminal rows.
        expect(
          find.byKey(const ValueKey('failed-message-retry-msg-payload')),
          findsOneWidget,
        );
        expect(find.textContaining("Couldn't send"), findsNothing);
      },
    );

    // 144 follow-up (finding: reopen durability). A terminal send_failed bubble's
    // per-message reason + Delete (and read-only protection) must survive a fresh
    // mount/reopen, reconstructed from the persisted group + own send_failed row —
    // not just the in-memory latch set during the original send.
    testWidgets(
      '144 reopen reconstructs the terminal reason + Delete + read-only banner '
      'for a dissolved group with a persisted send_failed row',
      (tester) async {
        final group = makeChatGroup().copyWith(isDissolved: true);
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-dead',
            text: 'Stranded in a dissolved group',
            isIncoming: false,
            senderPeerId: testIdentity.peerId,
            senderUsername: testIdentity.username,
            status: GroupMessage.statusSendFailed,
          ),
        );

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.canWrite, isFalse);
        // RED on HEAD: the latch resets to none on a fresh mount, so the
        // per-message reason is null and Delete is not wired.
        expect(
          screen.failedTerminalReasonText,
          "Couldn't send — this group was dissolved",
        );
        expect(
          find.byKey(const ValueKey('failed-message-delete-msg-dead')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('failed-message-retry-msg-dead')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('group-read-only-banner')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '144 reopen with a confirmed-removed membership keeps read-only and '
      'reconstructs the removed reason + Delete',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        // Membership loaded and excludes self (definitively removed).
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: 'peer-bob',
            username: 'Bob',
            role: MemberRole.writer,
            joinedAt: DateTime.utc(2026, 5, 1, 10),
          ),
        );
        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-removed',
            text: 'Sent before removal',
            isIncoming: false,
            senderPeerId: testIdentity.peerId,
            senderUsername: testIdentity.username,
            status: GroupMessage.statusSendFailed,
          ),
        );

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.canWrite, isFalse);
        expect(
          screen.failedTerminalReasonText,
          "Couldn't send — you're no longer in this group",
        );
        expect(
          find.byKey(const ValueKey('failed-message-delete-msg-removed')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '144 reopen with an empty local membership after removal does NOT '
      're-enable the composer (closes the fails-open writable hole)',
      (tester) async {
        // The realistic post-removal local state: the group row is not marked
        // dissolved and the local member list is empty. Today this fails open to
        // writable. With a persisted own send_failed row it must stay read-only.
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-empty',
            text: 'Sent before the group emptied',
            isIncoming: false,
            senderPeerId: testIdentity.peerId,
            senderUsername: testIdentity.username,
            status: GroupMessage.statusSendFailed,
          ),
        );

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        // RED on HEAD: empty members fail open => canWrite stays true and the
        // composer TextField is shown even though the user can never send.
        expect(screen.canWrite, isFalse);
        expect(find.byType(TextField), findsNothing);
        expect(
          find.byKey(const ValueKey('failed-message-delete-msg-empty')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '144 terminal Delete removes the durable owned media file from disk',
      (tester) async {
        // NOT saved to the repo => getGroup null => groupNotFound terminal.
        final missingGroup = makeChatGroup();
        final tempDir = Directory.systemTemp.createTempSync(
          'group-terminal-media-leak-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final mediaFileManager = TrackingDurableMediaFileManager(tempDir);
        const messageId = 'msg-terminal-durable-photo';
        const attachmentId = 'att-terminal-durable-photo';
        const mime = 'image/jpeg';
        final durableAbsolute = await mediaFileManager.localPathForAttachment(
          contactPeerId: missingGroup.id,
          blobId: attachmentId,
          mime: mime,
        );
        File(durableAbsolute).writeAsBytesSync(validJpegFixtureBytes);
        final durableRelative = mediaFileManager.relativePathForAttachment(
          contactPeerId: missingGroup.id,
          blobId: attachmentId,
          mime: mime,
        );
        await msgRepo.saveMessage(
          makeMessage(
            id: messageId,
            text: 'Durable photo',
            groupId: missingGroup.id,
            isIncoming: false,
            senderPeerId: testIdentity.peerId,
            senderUsername: testIdentity.username,
            status: GroupMessage.statusSendFailed,
          ),
        );
        await mediaAttachmentRepo.saveAttachment(
          MediaAttachment(
            id: attachmentId,
            messageId: messageId,
            mime: mime,
            size: validJpegFixtureBytes.length,
            mediaType: 'image',
            localPath: durableRelative,
            downloadStatus: 'done',
            contentHash: _validContentHash,
            encryptionKeyBase64: 'key-fixture',
            encryptionNonce: 'nonce-fixture',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
          owner: MediaOwnerLane.group,
        );

        await tester.pumpWidget(
          buildWidget(
            group: missingGroup,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
          ),
        );
        await pumpFrames(tester, count: 20);
        await pumpUntilAsyncWorkSettles(
          tester,
          () => tester
              .widget<GroupConversationScreen>(
                find.byType(GroupConversationScreen),
              )
              .messages
              .any((message) => message.id == messageId),
        );

        final after = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final retained = after.messages
            .where((message) => message.text == 'Durable photo')
            .toList();
        expect(retained, hasLength(1));
        expect(retained.single.status, GroupMessage.statusSendFailed);

        final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
          retained.single.id,
          owner: MediaOwnerLane.group,
        );
        expect(attachments, isNotEmpty);
        final localPath = attachments.first.localPath;
        expect(localPath, isNotNull);
        expect(
          await mediaFileManager.resolveStoredPath(localPath!),
          durableAbsolute,
        );
        expect(
          File(durableAbsolute).existsSync(),
          isTrue,
          reason: 'durable owned file should exist before Delete',
        );

        // Tap the terminal Delete affordance (reachable while read-only).
        await tester.tap(
          find.byKey(ValueKey('failed-message-delete-${retained.single.id}')),
        );
        await pumpUntil(
          tester,
          () => !File(durableAbsolute).existsSync(),
          maxPumps: 120,
        );

        // RED on HEAD: terminal Delete only drops the rows + pending-upload dir,
        // orphaning the durable media/<groupId>/ file on disk.
        expect(File(durableAbsolute).existsSync(), isFalse);
      },
    );

    testWidgets(
      'ordinary media group-not-found rejection retains the failed media bubble',
      (tester) async {
        final missingGroup = makeChatGroup();
        await groupRepo.saveGroup(missingGroup);
        await saveActiveGroupMembers(groupRepo, missingGroup);
        final tempDir = Directory.systemTemp.createTempSync(
          'group-media-missing-group-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final file = File('${tempDir.path}/one.jpg')
          ..writeAsBytesSync(validJpegFixtureBytes);
        final mediaFileManager = FakeMediaFileManager();
        final deletedDirs = <String>[];
        mediaFileManager.onDeletePendingUploadDir = deletedDirs.add;
        final uploadStarted = Completer<void>();
        final uploadRelease = Completer<void>();
        addTearDown(() {
          if (!uploadRelease.isCompleted) uploadRelease.complete();
        });

        await tester.pumpWidget(
          buildWidget(
            group: missingGroup,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            initialAttachments: [file],
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                  deleteSourceWhenDone = false,
                  preparedArtifact,
                }) async {
                  if (!uploadStarted.isCompleted) uploadStarted.complete();
                  await uploadRelease.future;
                  return MediaAttachment(
                    id: blobId!,
                    messageId: '',
                    mime: mime,
                    size: 1,
                    mediaType: MediaAttachment.mediaTypeFromMime(mime),
                    localPath: mediaFileManager?.relativePathForAttachment(
                      contactPeerId: missingGroup.id,
                      blobId: blobId,
                      mime: mime,
                    ),
                    downloadStatus: 'done',
                    contentHash: _validContentHash,
                    encryptionKeyBase64: 'key-fixture',
                    encryptionNonce: 'nonce-fixture',
                    encryptionScheme:
                        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                    createdAt: DateTime.now().toUtc().toIso8601String(),
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        final sendFuture = await startScreenSend(tester, 'Missing group media');
        await pumpUntilAsyncWorkSettles(
          tester,
          () => uploadStarted.isCompleted,
        );
        expect(uploadStarted.isCompleted, isTrue);
        final deleteGroup = runGroupMembershipMutationLocked<void>(
          groupId: missingGroup.id,
          action: () => groupRepo.deleteGroup(missingGroup.id),
        );
        uploadRelease.complete();
        await pumpUntilFuturesComplete(tester, [
          deleteGroup,
          sendFuture.future,
        ]);
        await pumpFrames(tester, count: 20);

        final after = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final retained = after.messages
            .where((message) => message.text == 'Missing group media')
            .toList();
        expect(retained, hasLength(1));
        expect(retained.single.status, GroupMessage.statusSendFailed);
        // The durable media dir is NOT auto-deleted and the bubble media stays.
        expect(deletedDirs, isEmpty);
        expect(after.mediaMap[retained.single.id], isNotEmpty);
        expect(after.canWrite, isFalse);
        expect(
          find.byKey(ValueKey('failed-message-delete-${retained.single.id}')),
          findsOneWidget,
        );
        expect(bridge.commandLog, isNot(contains('group:publish')));
      },
    );

    testWidgets(
      'ordinary media unauthorized rejection retains the failed media bubble',
      (tester) async {
        final widgetGroup = makeAnnouncementGroup(role: GroupRole.admin);
        await groupRepo.saveGroup(widgetGroup);
        await saveActiveGroupMembers(groupRepo, widgetGroup);

        final tempDir = Directory.systemTemp.createTempSync(
          'group-media-unauthorized-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final file = File('${tempDir.path}/one.jpg')
          ..writeAsBytesSync(validJpegFixtureBytes);
        final mediaFileManager = FakeMediaFileManager();
        final deletedDirs = <String>[];
        mediaFileManager.onDeletePendingUploadDir = deletedDirs.add;
        final uploadStarted = Completer<void>();
        final uploadRelease = Completer<void>();
        addTearDown(() {
          if (!uploadRelease.isCompleted) uploadRelease.complete();
        });

        await tester.pumpWidget(
          buildWidget(
            group: widgetGroup,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            initialAttachments: [file],
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                  deleteSourceWhenDone = false,
                  preparedArtifact,
                }) async {
                  if (!uploadStarted.isCompleted) uploadStarted.complete();
                  await uploadRelease.future;
                  return MediaAttachment(
                    id: blobId!,
                    messageId: '',
                    mime: mime,
                    size: 1,
                    mediaType: MediaAttachment.mediaTypeFromMime(mime),
                    localPath: mediaFileManager?.relativePathForAttachment(
                      contactPeerId: widgetGroup.id,
                      blobId: blobId,
                      mime: mime,
                    ),
                    downloadStatus: 'done',
                    contentHash: _validContentHash,
                    encryptionKeyBase64: 'key-fixture',
                    encryptionNonce: 'nonce-fixture',
                    encryptionScheme:
                        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                    createdAt: DateTime.now().toUtc().toIso8601String(),
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        final sendFuture = await startScreenSend(tester, 'Unauthorized media');
        await pumpUntilAsyncWorkSettles(
          tester,
          () => uploadStarted.isCompleted,
        );
        expect(uploadStarted.isCompleted, isTrue);
        final demoteLocalRole = runGroupMembershipMutationLocked<void>(
          groupId: widgetGroup.id,
          action: () => groupRepo.updateGroup(
            widgetGroup.copyWith(myRole: GroupRole.member),
          ),
        );
        uploadRelease.complete();
        await pumpUntilFuturesComplete(tester, [
          demoteLocalRole,
          sendFuture.future,
        ]);
        await pumpFrames(tester, count: 20);

        final after = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final retained = after.messages
            .where((message) => message.text == 'Unauthorized media')
            .toList();
        expect(retained, hasLength(1));
        expect(retained.single.status, GroupMessage.statusSendFailed);
        expect(deletedDirs, isEmpty);
        expect(after.mediaMap[retained.single.id], isNotEmpty);
        expect(after.canWrite, isFalse);
        expect(
          find.byKey(ValueKey('failed-message-delete-${retained.single.id}')),
          findsOneWidget,
        );
        expect(bridge.commandLog, isNot(contains('group:publish')));
      },
    );

    testWidgets(
      'non-durable media send reuses optimistic attachment IDs when uploader returns different IDs',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);

        final tempDir = Directory.systemTemp.createTempSync(
          'group-media-non-durable-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final file = File('${tempDir.path}/one.jpg')..writeAsStringSync('one');

        String? receivedBlobId;

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            initialAttachments: [file],
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                  deleteSourceWhenDone = false,
                  preparedArtifact,
                }) async {
                  receivedBlobId = blobId;
                  return MediaAttachment(
                    id: 'server-non-durable-image',
                    messageId: '',
                    mime: mime,
                    size: 1,
                    mediaType: MediaAttachment.mediaTypeFromMime(mime),
                    localPath: localFilePath,
                    downloadStatus: 'done',
                    contentHash: _validContentHash,
                    encryptionKeyBase64: 'key-fixture',
                    encryptionNonce: 'nonce-fixture',
                    encryptionScheme:
                        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                    createdAt: DateTime.now().toUtc().toIso8601String(),
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        await tester.enterText(find.byType(TextField), 'Fallback media');
        await pumpFrames(tester);
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpFrames(tester, count: 20);

        expect(receivedBlobId, isNotNull);

        final savedMessage = await msgRepo.getLatestMessage(group.id);
        expect(savedMessage, isNotNull);
        final savedAttachments = await mediaAttachmentRepo
            .getAttachmentsForMessage(
              savedMessage!.id,
              owner: MediaOwnerLane.group,
            );
        expect(savedAttachments, hasLength(1));
        expect(savedAttachments.single.id, receivedBlobId);
        expect(savedAttachments.single.downloadStatus, 'done');
      },
    );

    testWidgets(
      'sending a message with zero topic peers keeps the row sent and does not restore the draft',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        final joinedAt = DateTime.utc(2026, 5, 13, 11);
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: testIdentity.peerId,
            username: testIdentity.username,
            role: MemberRole.admin,
            publicKey: testIdentity.publicKey,
            mlKemPublicKey: testIdentity.mlKemPublicKey,
            joinedAt: joinedAt,
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: 'peer-zero-topic-bob',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-zero-topic-bob',
            mlKemPublicKey: 'mlkem-zero-topic-bob',
            joinedAt: joinedAt.add(const Duration(minutes: 1)),
          ),
        );

        bridge = FakeBridge(
          initialResponses: {
            'group:publish': {
              'ok': true,
              'messageId': 'msg-zero-peers',
              'topicPeers': 0,
            },
          },
        );

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester);

        await tester.enterText(find.byType(TextField), 'No peers online');
        await pumpFrames(tester);
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpFrames(tester, count: 20);

        expect(find.text('No peers online'), findsOneWidget);
        expect(find.byIcon(Icons.schedule_rounded), findsNothing);
        expect(find.byIcon(Icons.error_outline_rounded), findsNothing);

        final messages = await msgRepo.getMessagesPage(group.id);
        final saved = messages.firstWhere(
          (message) => message.text == 'No peers online',
        );
        expect(saved.status, 'sent');
        expect(saved.inboxStored, isTrue);
      },
    );

    testWidgets(
      'NW-007 zero topic peers keep active member UI without transient banners',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        final joinedAt = DateTime.utc(2026, 5, 13, 11);
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: testIdentity.peerId,
            username: testIdentity.username,
            role: MemberRole.admin,
            publicKey: testIdentity.publicKey,
            mlKemPublicKey: testIdentity.mlKemPublicKey,
            joinedAt: joinedAt,
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: 'peer-nw007-bob',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-nw007-bob',
            mlKemPublicKey: 'mlkem-nw007-bob',
            joinedAt: joinedAt.add(const Duration(minutes: 1)),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: 'peer-nw007-charlie',
            username: 'Charlie',
            role: MemberRole.writer,
            publicKey: 'pk-nw007-charlie',
            mlKemPublicKey: 'mlkem-nw007-charlie',
            joinedAt: joinedAt.add(const Duration(minutes: 2)),
          ),
        );
        await contactRepo.addContact(
          ContactModel(
            peerId: 'peer-nw007-bob',
            publicKey: 'pk-nw007-bob',
            rendezvous: '/ip4/127.0.0.1/tcp/4001',
            username: 'Bob',
            signature: 'sig-nw007-bob',
            scannedAt: joinedAt.toIso8601String(),
            mlKemPublicKey: 'mlkem-nw007-bob',
          ),
        );
        await contactRepo.addContact(
          ContactModel(
            peerId: 'peer-nw007-charlie',
            publicKey: 'pk-nw007-charlie',
            rendezvous: '/ip4/127.0.0.1/tcp/4002',
            username: 'Charlie',
            signature: 'sig-nw007-charlie',
            scannedAt: joinedAt.toIso8601String(),
            mlKemPublicKey: 'mlkem-nw007-charlie',
          ),
        );
        final membersBefore = (await groupRepo.getMembers(
          group.id,
        )).map((member) => member.peerId).toSet();
        final removedStreamController = StreamController<String>.broadcast();
        addTearDown(removedStreamController.close);
        groupRecoveryGate.begin();
        addTearDown(groupRecoveryGate.resetForTest);
        bridge = FakeBridge(
          initialResponses: {
            'group:publish': {
              'ok': true,
              'messageId': 'nw007-zero-topic-peer-ui',
              'topicPeers': 0,
            },
          },
        );

        await tester.pumpWidget(
          buildWidget(
            group: group,
            removedStreamController: removedStreamController,
          ),
        );
        await pumpFrames(tester, count: 20);

        expect(find.byType(GroupConversationScreen), findsOneWidget);
        expect(find.text('All 3 members verified'), findsNothing);
        expect(
          find.byKey(const ValueKey('group-conversation-security-strip')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('group-recovery-banner')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('group-read-only-banner')),
          findsNothing,
        );
        expect(find.text('You were removed from this group.'), findsNothing);
        expect(find.byType(TextField), findsOneWidget);

        await tester.enterText(
          find.byType(TextField),
          'NW-007 zero peers keep group active',
        );
        await pumpFrames(tester);
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpFrames(tester, count: 20);

        expect(find.byType(GroupConversationScreen), findsOneWidget);
        expect(
          find.text('NW-007 zero peers keep group active'),
          findsOneWidget,
        );
        expect(find.text('All 3 members verified'), findsNothing);
        expect(
          find.byKey(const ValueKey('group-recovery-banner')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('group-read-only-banner')),
          findsNothing,
        );
        expect(find.text('You were removed from this group.'), findsNothing);
        expect(find.byIcon(Icons.schedule_rounded), findsNothing);
        expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
        expect(
          (await groupRepo.getMembers(
            group.id,
          )).map((member) => member.peerId).toSet(),
          membersBefore,
        );
      },
    );

    testWidgets('swipe-to-reply sends quotedMessageId and clears preview', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      await saveActiveGroupMembers(groupRepo, group);
      await msgRepo.saveMessage(
        makeMessage(
          id: 'msg-parent',
          text: 'Incoming parent',
          groupId: group.id,
          isIncoming: true,
        ),
      );

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester, count: 20);

      expect(find.byType(SwipeToQuoteBubble), findsOneWidget);

      final screen = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      screen.onQuoteReply!.call('msg-parent');
      await tester.pump();

      expect(find.text('Incoming parent'), findsWidgets);

      await tester.enterText(find.byType(TextField), 'Reply to parent');
      await pumpFrames(tester);
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await pumpFrames(tester, count: 20);

      final publishMsg = bridge.sentMessages.firstWhere(
        (m) => (jsonDecode(m) as Map)['cmd'] == 'group:publish',
      );
      final payload =
          (jsonDecode(publishMsg) as Map)['payload'] as Map<String, dynamic>;
      expect(payload['quotedMessageId'], 'msg-parent');

      final savedMessages = await msgRepo.getMessagesPage(group.id);
      final sent = savedMessages.firstWhere((m) => m.text == 'Reply to parent');
      expect(sent.quotedMessageId, 'msg-parent');
      expect(find.text('Incoming parent'), findsWidgets);
    });

    testWidgets(
      'incoming message stream upserts without full message/media reloads',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(
          makeMessage(id: 'msg-initial', text: 'Initial'),
        );

        await tester.pumpWidget(
          buildWidget(group: group, mediaRepo: mediaAttachmentRepo),
        );
        await pumpFrames(tester);

        expect(find.text('Initial'), findsOneWidget);
        expect(msgRepo.getMessagesPageCalls, 1);
        expect(mediaAttachmentRepo.getAttachmentsForMessagesCalls, 1);
        final initialGetMessageCalls = msgRepo.getMessageCalls;
        final initialSingleMessageMediaCalls =
            mediaAttachmentRepo.getAttachmentsForMessageCalls;

        // Add a message to the repo (simulating the listener handler saving it)
        final incomingMsg = makeMessage(
          id: 'msg-incoming',
          text: 'Incoming hello',
          groupId: 'group-1',
        );
        await msgRepo.saveMessage(incomingMsg);

        // Emit on the listener stream with matching groupId
        messageStreamController.add(incomingMsg);
        await pumpFrames(tester, count: 20);

        // The message should now appear
        expect(find.text('Incoming hello'), findsOneWidget);
        expect(msgRepo.getMessagesPageCalls, 1);
        expect(msgRepo.getMessageCalls, greaterThan(initialGetMessageCalls));
        expect(mediaAttachmentRepo.getAttachmentsForMessagesCalls, 1);
        expect(
          mediaAttachmentRepo.getAttachmentsForMessageCalls,
          initialSingleMessageMediaCalls + 1,
        );
      },
    );

    testWidgets(
      'multiple inserted events surface targeted upserts without a full page reload',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester);
        final initialPageLoads = msgRepo.getMessagesPageCalls;
        final initialMarkReadCalls = msgRepo.markAsReadCalls;
        GroupConversationWired.debugReorderInvocationCount = 0;

        for (var i = 0; i < 3; i++) {
          await msgRepo.saveMessage(
            makeMessage(
              id: 'inserted-burst-$i',
              text: 'Inserted burst $i',
              groupId: group.id,
              isIncoming: false,
              senderPeerId: testIdentity.peerId,
              senderUsername: testIdentity.username,
              status: 'sending',
            ),
          );
        }
        await pumpFrames(tester, count: 20);

        for (var i = 0; i < 3; i++) {
          expect(find.text('Inserted burst $i'), findsOneWidget);
        }
        expect(msgRepo.getMessagesPageCalls, initialPageLoads);
        expect(GroupConversationWired.debugReorderInvocationCount, 1);
        expect(msgRepo.markAsReadCalls, initialMarkReadCalls);
      },
    );

    testWidgets(
      'inserted event for an in-flight optimistic media send does not clobber optimistic media',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        final gatedMedia = GateFirstSingleMediaReadRepository();
        await tester.pumpWidget(
          buildWidget(group: group, mediaRepo: gatedMedia),
        );
        await pumpFrames(tester);

        const messageId = 'optimistic-insert-race';
        final durableAttachment = MediaAttachment(
          id: 'optimistic-insert-race-att',
          messageId: messageId,
          mime: 'image/png',
          size: _tinyPngBytes.length,
          mediaType: 'image',
          localPath: 'media/group-1/relative.png',
          downloadStatus: 'done',
          createdAt: '2026-07-11T10:00:00.000Z',
          contentHash:
              'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
          encryptionKeyBase64: 'key-optimistic',
          encryptionNonce: 'nonce-optimistic',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        );
        await gatedMedia.saveAttachment(
          durableAttachment,
          owner: MediaOwnerLane.group,
        );
        gatedMedia.armed = true;
        final row = makeMessage(
          id: messageId,
          text: '',
          groupId: group.id,
          isIncoming: false,
          senderPeerId: testIdentity.peerId,
          senderUsername: testIdentity.username,
          status: 'sending',
        );
        await msgRepo.saveMessage(row);
        await pumpUntil(tester, () => gatedMedia.firstReadCaptured.isCompleted);
        expect(gatedMedia.firstReadCaptured.isCompleted, isTrue);

        final optimisticAttachment = durableAttachment.copyWith(
          localPath: '/tmp/optimistic-absolute.png',
        );
        await gatedMedia.saveAttachment(
          optimisticAttachment,
          owner: MediaOwnerLane.group,
        );
        final optimistic = row.copyWith(media: [optimisticAttachment]);
        await msgRepo.saveMessage(optimistic);
        messageStreamController.add(optimistic);
        await pumpFrames(tester, count: 5);
        gatedMedia.releaseFirstRead.complete();
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(
          screen.mediaMap[messageId]!.single.localPath,
          '/tmp/optimistic-absolute.png',
        );
      },
    );

    testWidgets(
      'terminal status arriving while inserted media hydration is held wins over the sending snapshot',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        final gatedMedia = GateFirstSingleMediaReadRepository();
        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: gatedMedia,
            mediaFileManager: FakeMediaFileManager(),
          ),
        );
        await pumpFrames(tester);

        const messageId = 'inserted-terminal-status-race';
        await gatedMedia.saveAttachment(
          MediaAttachment(
            id: 'inserted-terminal-status-race-att',
            messageId: messageId,
            mime: 'image/png',
            size: _tinyPngBytes.length,
            mediaType: 'image',
            localPath: 'pending_uploads/$messageId/terminal-race.png',
            downloadStatus: 'done',
            createdAt: '2026-07-11T10:00:00.000Z',
            contentHash:
                'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
            encryptionKeyBase64: 'key-terminal-race',
            encryptionNonce: 'nonce-terminal-race',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ),
          owner: MediaOwnerLane.group,
        );
        gatedMedia.armed = true;
        await msgRepo.saveMessage(
          makeMessage(
            id: messageId,
            text: '',
            groupId: group.id,
            isIncoming: false,
            senderPeerId: testIdentity.peerId,
            senderUsername: testIdentity.username,
            status: 'sending',
          ),
        );
        await pumpUntil(tester, () => gatedMedia.firstReadCaptured.isCompleted);
        expect(gatedMedia.firstReadCaptured.isCompleted, isTrue);

        await msgRepo.updateMessageStatus(messageId, 'failed');
        expect((await msgRepo.getMessage(messageId))!.status, 'failed');
        gatedMedia.releaseFirstRead.complete();
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(
          screen.messages
              .singleWhere((message) => message.id == messageId)
              .status,
          'failed',
        );
        expect(screen.mediaMap[messageId], hasLength(1));
        expect(
          find.byKey(const ValueKey('failed-media-retry-$messageId')),
          findsOneWidget,
        );
      },
    );

    testWidgets('an inserted message survives a concurrent stale page load', (
      tester,
    ) async {
      const insertedMessageId = 'inserted-during-stale-load';
      const insertedAttachmentId = 'inserted-during-stale-load-att';
      final temp = Directory.systemTemp.createTempSync(
        'group-inserted-stale-load-',
      );
      addTearDown(() => temp.deleteSync(recursive: true));
      final image = File(p.join(temp.path, 'inserted.png'))
        ..writeAsBytesSync(_tinyPngBytes);
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      final staleRepo = StaleReloadGroupMessageRepository();
      await staleRepo.saveMessage(
        makeMessage(
          id: 'reload-trigger',
          text: 'Reload trigger',
          groupId: group.id,
          isIncoming: false,
          senderPeerId: testIdentity.peerId,
          senderUsername: testIdentity.username,
          status: 'sending',
        ),
      );
      await tester.pumpWidget(
        buildWidget(
          group: group,
          messageRepo: staleRepo,
          mediaRepo: mediaAttachmentRepo,
        ),
      );
      await pumpFrames(tester);

      staleRepo.holdNextPage();
      await staleRepo.transitionSendingToFailed();
      await staleRepo.pageCaptured;
      expect(staleRepo.getMessagesPageCalls, greaterThanOrEqualTo(2));

      await mediaAttachmentRepo.saveAttachment(
        MediaAttachment(
          id: insertedAttachmentId,
          messageId: insertedMessageId,
          mime: 'image/png',
          size: image.lengthSync(),
          mediaType: 'image',
          width: 1,
          height: 1,
          localPath: image.path,
          downloadStatus: 'done',
          createdAt: '2026-07-11T10:00:00.000Z',
          contentHash: _validContentHash,
          encryptionKeyBase64: 'inserted-stale-load-key',
          encryptionNonce: 'inserted-stale-load-nonce',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
        ),
        owner: MediaOwnerLane.group,
      );
      await staleRepo.saveMessage(
        makeMessage(
          id: insertedMessageId,
          text: 'Inserted during stale load',
          groupId: group.id,
          isIncoming: false,
          senderPeerId: testIdentity.peerId,
          senderUsername: testIdentity.username,
          status: 'sending',
        ),
      );
      await pumpUntil(
        tester,
        () => find.text('Inserted during stale load').evaluate().isNotEmpty,
      );
      expect(find.text('Inserted during stale load'), findsOneWidget);

      staleRepo.releasePage();
      await pumpFrames(tester, count: 20);
      expect(find.text('Inserted during stale load'), findsOneWidget);
      final screen = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      expect(screen.mediaMap[insertedMessageId], hasLength(1));
      expect(
        screen.mediaMap[insertedMessageId]!.single.id,
        insertedAttachmentId,
      );
      expect(find.byType(MediaGrid), findsOneWidget);
      expect(find.byType(MediaThumbnailImage), findsOneWidget);
    });

    testWidgets(
      'GFR-003 open conversation applies outgoing local status update in place',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        final failed = makeMessage(
          id: 'local-status-visible',
          text: 'Local status visible',
          groupId: group.id,
          isIncoming: false,
          senderPeerId: testIdentity.peerId,
          senderUsername: testIdentity.username,
          status: 'failed',
        );
        await msgRepo.saveMessage(failed);

        await tester.pumpWidget(buildWidget(group: group));
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen.messages.any(
            (message) =>
                message.id == 'local-status-visible' &&
                message.status == 'failed',
          );
        });
        final initialPageLoads = msgRepo.getMessagesPageCalls;

        await msgRepo.saveMessage(failed.copyWith(status: 'sending'));
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen.messages.any(
            (message) =>
                message.id == 'local-status-visible' &&
                message.status == 'sending',
          );
        });

        await msgRepo.saveMessage(failed.copyWith(status: 'sent'));
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen.messages.any(
            (message) =>
                message.id == 'local-status-visible' &&
                message.status == 'sent',
          );
        });

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(
          screen.messages
              .singleWhere((message) => message.id == 'local-status-visible')
              .status,
          'sent',
        );
        expect(msgRepo.getMessagesPageCalls, initialPageLoads);
      },
    );

    testWidgets('local status event for another group is ignored', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      final visible = makeMessage(
        id: 'local-status-current-group',
        text: 'Current group row',
        groupId: group.id,
        isIncoming: false,
        senderPeerId: testIdentity.peerId,
        senderUsername: testIdentity.username,
        status: 'failed',
      );
      final other = makeMessage(
        id: 'local-status-other-group',
        text: 'Other group row',
        groupId: 'group-other',
        isIncoming: false,
        senderPeerId: testIdentity.peerId,
        senderUsername: testIdentity.username,
        status: 'failed',
      );
      await msgRepo.saveMessage(visible);
      await msgRepo.saveMessage(other);

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester, count: 20);
      final initialPageLoads = msgRepo.getMessagesPageCalls;

      await msgRepo.saveMessage(other.copyWith(status: 'sent'));
      await pumpFrames(tester, count: 20);

      final screen = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      expect(
        screen.messages
            .singleWhere(
              (message) => message.id == 'local-status-current-group',
            )
            .status,
        'failed',
      );
      expect(msgRepo.getMessagesPageCalls, initialPageLoads);
    });

    testWidgets(
      'batch local rows-changed event reloads visible sending row status',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(
          makeMessage(
            id: 'local-status-batch',
            text: 'Batch status row',
            groupId: group.id,
            isIncoming: false,
            senderPeerId: testIdentity.peerId,
            senderUsername: testIdentity.username,
            status: 'sending',
          ),
        );

        await tester.pumpWidget(buildWidget(group: group));
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen.messages.any(
            (message) =>
                message.id == 'local-status-batch' &&
                message.status == 'sending',
          );
        });
        final initialPageLoads = msgRepo.getMessagesPageCalls;

        final transitioned = await msgRepo.transitionSendingToFailed();
        expect(transitioned, 1);
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen.messages.any(
            (message) =>
                message.id == 'local-status-batch' &&
                message.status == 'failed',
          );
        });

        expect(msgRepo.getMessagesPageCalls, greaterThan(initialPageLoads));
      },
    );

    testWidgets('local status stream is cancelled after unmount', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      final failed = makeMessage(
        id: 'local-status-after-unmount',
        text: 'Unmounted status row',
        groupId: group.id,
        isIncoming: false,
        senderPeerId: testIdentity.peerId,
        senderUsername: testIdentity.username,
        status: 'failed',
      );
      await msgRepo.saveMessage(failed);

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester, count: 20);
      await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
      await pumpFrames(tester, count: 5);

      await msgRepo.saveMessage(failed.copyWith(status: 'sent'));
      await pumpFrames(tester, count: 5);

      expect(find.byType(GroupConversationScreen), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      '131: resume re-fetch surfaces an incoming message that landed while '
      'backgrounded (the path a notification tap triggers)',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(
          makeMessage(
            id: 'g131-old',
            text: 'old group message',
            groupId: group.id,
            isIncoming: true,
            senderPeerId: 'peer-bob',
            senderUsername: 'Bob',
          ),
        );

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester, count: 20);
        final loadsAfterInitial = msgRepo.getMessagesPageCalls;
        expect(
          tester
              .widget<GroupConversationScreen>(
                find.byType(GroupConversationScreen),
              )
              .messages
              .any((m) => m.id == 'g131-fresh'),
          isFalse,
          reason: 'fresh message has not arrived yet',
        );

        // A new incoming message lands in the repo (the app-level group drain
        // persisted it) — NOT via the live group stream, so the open screen does
        // not catch it live. Only a re-fetch can surface it.
        await msgRepo.saveMessage(
          makeMessage(
            id: 'g131-fresh',
            text: 'arrived while backgrounded',
            groupId: group.id,
            isIncoming: true,
            senderPeerId: 'peer-bob',
            senderUsername: 'Bob',
          ),
        );

        // Resume — exactly what a notification tap does to a backgrounded app.
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );

        await pumpUntil(
          tester,
          () => tester
              .widget<GroupConversationScreen>(
                find.byType(GroupConversationScreen),
              )
              .messages
              .any((m) => m.id == 'g131-fresh'),
        );
        expect(
          tester
              .widget<GroupConversationScreen>(
                find.byType(GroupConversationScreen),
              )
              .messages
              .any((m) => m.id == 'g131-fresh'),
          isTrue,
        );
        expect(
          msgRepo.getMessagesPageCalls,
          greaterThan(loadsAfterInitial),
          reason: 'resume must re-fetch the page to surface the new message',
        );
      },
    );

    testWidgets(
      'local status subscription switches when message repository changes',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        final originalRepo = msgRepo;
        final replacementRepo = CountingGroupMessageRepository();
        final failed = makeMessage(
          id: 'local-status-repo-switch',
          text: 'Repo switch row',
          groupId: group.id,
          isIncoming: false,
          senderPeerId: testIdentity.peerId,
          senderUsername: testIdentity.username,
          status: 'failed',
        );
        await originalRepo.saveMessage(failed);
        await replacementRepo.saveMessage(failed);

        await tester.pumpWidget(
          buildWidget(group: group, messageRepo: originalRepo),
        );
        await pumpFrames(tester, count: 20);
        await tester.pumpWidget(
          buildWidget(group: group, messageRepo: replacementRepo),
        );
        await pumpFrames(tester, count: 5);

        await originalRepo.saveMessage(failed.copyWith(status: 'sent'));
        await pumpFrames(tester, count: 10);
        var screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(
          screen.messages
              .singleWhere(
                (message) => message.id == 'local-status-repo-switch',
              )
              .status,
          'failed',
        );

        await replacementRepo.saveMessage(failed.copyWith(status: 'sent'));
        await pumpUntil(tester, () {
          final updatedScreen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return updatedScreen.messages.any(
            (message) =>
                message.id == 'local-status-repo-switch' &&
                message.status == 'sent',
          );
        });

        screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(
          screen.messages
              .singleWhere(
                (message) => message.id == 'local-status-repo-switch',
              )
              .status,
          'sent',
        );
      },
    );

    testWidgets(
      'UP-013 route reopen renders message persisted while widget unmounted',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(
          makeMessage(id: 'up013-before-unmount', text: 'Before unmount'),
        );

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester);

        expect(find.text('Before unmount'), findsOneWidget);
        expect(msgRepo.getMessagesPageCalls, 1);

        await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
        await pumpFrames(tester);

        final incomingWhileUnmounted = makeMessage(
          id: 'up013-while-unmounted',
          text: 'Arrived while route was away',
          groupId: group.id,
        );
        await msgRepo.saveMessage(incomingWhileUnmounted);
        messageStreamController.add(incomingWhileUnmounted);
        await pumpFrames(tester, count: 5);

        expect(find.text('Arrived while route was away'), findsNothing);

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester, count: 20);

        expect(find.text('Before unmount'), findsOneWidget);
        expect(find.text('Arrived while route was away'), findsOneWidget);
        expect(
          msgRepo.getMessagesPageCalls,
          greaterThanOrEqualTo(2),
          reason: 'reopened route must hydrate from repository state',
        );
      },
    );

    testWidgets(
      'GMAR-004 reopen hydration preserves video voice pending and failed media without duplicates',
      (tester) async {
        final group = makeChatGroup();
        final timestamp = DateTime.utc(2026, 5, 2, 9);
        final mediaFileManager = FakeMediaFileManager();
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(
          makeMessage(
            id: 'gmar004-complete',
            text: 'verified video and voice',
            timestamp: timestamp,
          ),
        );
        await msgRepo.saveMessage(
          makeMessage(
            id: 'gmar004-pending',
            text: 'pending video remains visible',
            timestamp: timestamp.add(const Duration(seconds: 1)),
          ),
        );
        await msgRepo.saveMessage(
          makeMessage(
            id: 'gmar004-failed',
            text: 'failed voice remains retryable',
            timestamp: timestamp.add(const Duration(seconds: 2)),
          ),
        );
        await mediaAttachmentRepo.saveAttachment(
          const MediaAttachment(
            id: 'gmar004-video-done',
            messageId: 'gmar004-complete',
            mime: 'video/mp4',
            size: 4096,
            mediaType: 'video',
            width: 640,
            height: 360,
            durationMs: 12000,
            localPath: 'pending_uploads/gmar004-complete/gmar004-video.mp4',
            downloadStatus: 'done',
            contentHash: _validContentHash,
            encryptionKeyBase64: 'key-fixture',
            encryptionNonce: 'nonce-fixture',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            createdAt: '2026-05-02T09:00:00.000Z',
          ),
          owner: MediaOwnerLane.group,
        );
        await mediaAttachmentRepo.saveAttachment(
          const MediaAttachment(
            id: 'gmar004-voice-done',
            messageId: 'gmar004-complete',
            mime: 'audio/mp4',
            size: 2048,
            mediaType: 'audio',
            durationMs: 4200,
            localPath: 'pending_uploads/gmar004-complete/gmar004-voice.m4a',
            downloadStatus: 'done',
            waveform: <double>[0.2, 0.6, 0.35, 0.8],
            contentHash: _validContentHash,
            encryptionKeyBase64: 'key-fixture',
            encryptionNonce: 'nonce-fixture',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            createdAt: '2026-05-02T09:00:01.000Z',
          ),
          owner: MediaOwnerLane.group,
        );
        await mediaAttachmentRepo.saveAttachment(
          const MediaAttachment(
            id: 'gmar004-video-pending',
            messageId: 'gmar004-pending',
            mime: 'video/mp4',
            size: 4096,
            mediaType: 'video',
            width: 640,
            height: 360,
            durationMs: 9000,
            downloadStatus: 'pending',
            contentHash: _validContentHash,
            encryptionKeyBase64: 'key-fixture',
            encryptionNonce: 'nonce-fixture',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            createdAt: '2026-05-02T09:00:02.000Z',
          ),
          owner: MediaOwnerLane.group,
        );
        await mediaAttachmentRepo.saveAttachment(
          const MediaAttachment(
            id: 'gmar004-voice-failed',
            messageId: 'gmar004-failed',
            mime: 'audio/mp4',
            size: 2048,
            mediaType: 'audio',
            durationMs: 3000,
            downloadStatus: kMediaDownloadStatusIntegrityFailed,
            waveform: <double>[0.1, 0.4, 0.7],
            contentHash: _validContentHash,
            encryptionKeyBase64: 'key-fixture',
            encryptionNonce: 'nonce-fixture',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            createdAt: '2026-05-02T09:00:03.000Z',
          ),
          owner: MediaOwnerLane.group,
        );

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
          ),
        );
        await tester.pump();
        await tester.pump();
        await pumpUntil(
          tester,
          () => mediaAttachmentRepo.getAttachmentsForMessagesCalls > 0,
        );
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await pumpFrames(tester, count: 20);
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen.messages.length == 3 &&
              screen.mediaMap['gmar004-complete']?.length == 2 &&
              screen.mediaMap['gmar004-pending']?.length == 1 &&
              screen.mediaMap['gmar004-failed']?.length == 1;
        });

        void expectHydratedOnce() {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          expect(
            screen.messages.where(
              (message) => message.id == 'gmar004-complete',
            ),
            hasLength(1),
          );
          expect(
            screen.mediaMap['gmar004-complete']!.map((media) => media.id),
            ['gmar004-video-done', 'gmar004-voice-done'],
          );
          expect(
            screen.mediaMap['gmar004-complete']!
                .map((media) => media.contentHash)
                .toSet(),
            {_validContentHash},
          );
          expect(
            screen.mediaMap['gmar004-complete']!
                .map((media) => media.encryptionScheme)
                .toSet(),
            {kMediaAttachmentEncryptionSchemeBlobAesGcmV1},
          );
          expect(
            screen.mediaMap['gmar004-pending']!.single.downloadStatus,
            isIn([
              kMediaDownloadStatusPending,
              kMediaDownloadStatusDownloading,
              kMediaDownloadStatusFailed,
              kMediaDownloadStatusIntegrityFailed,
            ]),
          );
          expect(
            screen.mediaMap['gmar004-failed']!.single.downloadStatus,
            kMediaDownloadStatusIntegrityFailed,
          );
          expect(screen.onRetryUnavailableMedia, isNotNull);
        }

        expectHydratedOnce();
        // The quarantined (integrity_failed) voice is preserved across reopen
        // but is terminal — INV-DL-3 means no retry affordance (was retryable
        // under the old MD-012 behaviour).
        expect(
          find.byKey(
            const ValueKey(
              'unavailable-media-retry-gmar004-failed-gmar004-voice-failed',
            ),
          ),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('failed-media-retry-gmar004-failed')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('failed-media-delete-gmar004-failed')),
          findsNothing,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
          ),
        );
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await pumpFrames(tester, count: 20);
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen.messages.length == 3 &&
              screen.mediaMap['gmar004-complete']?.length == 2 &&
              screen.mediaMap['gmar004-pending']?.length == 1 &&
              screen.mediaMap['gmar004-failed']?.length == 1;
        });

        expectHydratedOnce();
      },
    );

    testWidgets(
      'incoming group image refreshes on open recipient route after background download without reopen',
      (tester) async {
        final group = makeChatGroup();
        final tempDir = Directory.systemTemp.createTempSync(
          'group-open-route-image-refresh-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final mediaFileManager = TrackingDurableMediaFileManager(tempDir);
        final timestamp = DateTime.utc(2026, 5, 29, 6, 20);
        const messageId = 'group-open-route-image-refresh-message';
        const attachmentId = 'group-open-route-image-refresh-blob';
        final encryptedBytes = _md012EncryptedBytes(_tinyPngBytes);
        final downloadGate = Completer<void>();
        bridge = _DownloadRepairBridge(
          downloadedBytes: encryptedBytes,
          downloadGate: downloadGate,
        );

        await groupRepo.saveGroup(group);
        await messageStreamController.close();
        messageStreamController = StreamController<GroupMessage>.broadcast(
          sync: true,
        );
        final incomingMessage = makeMessage(
          id: messageId,
          text: 'Image on open route',
          groupId: group.id,
          isIncoming: true,
          senderPeerId: 'peer-alice',
          senderUsername: 'Alice',
          status: 'delivered',
          timestamp: timestamp,
        );
        final pendingImageAttachment = MediaAttachment(
          id: attachmentId,
          messageId: messageId,
          mime: 'image/png',
          size: _tinyPngBytes.length,
          mediaType: 'image',
          width: 1,
          height: 1,
          downloadStatus: kMediaDownloadStatusPending,
          contentHash: _md012HashBytes(encryptedBytes),
          encryptionKeyBase64: _md012MediaKey,
          encryptionNonce: _md012MediaNonce,
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          createdAt: timestamp.toIso8601String(),
        );

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
          ),
        );
        await pumpFrames(tester, count: 20);

        int mediaGridBrokenImageCount() => find
            .descendant(
              of: find.byType(MediaGrid),
              matching: find.byIcon(Icons.broken_image_outlined),
            )
            .evaluate()
            .length;

        int mediaGridLoadingCount() => find
            .descendant(
              of: find.byType(MediaGrid),
              matching: find.byType(CircularProgressIndicator),
            )
            .evaluate()
            .length;

        await msgRepo.saveMessage(incomingMessage);
        await mediaAttachmentRepo.saveAttachment(
          pendingImageAttachment,
          owner: MediaOwnerLane.group,
        );
        await tester.runAsync(() async {
          messageStreamController.add(incomingMessage);
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          final media = screen.mediaMap[messageId];
          return media != null &&
              media.single.downloadStatus == kMediaDownloadStatusPending &&
              mediaGridLoadingCount() == 1;
        }, maxPumps: 80);

        final initialScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(initialScreen.messages.map((message) => message.id), [
          messageId,
        ]);
        expect(initialScreen.mediaMap[messageId], hasLength(1));
        expect(find.byType(MediaGrid), findsOneWidget);
        final relativePath = mediaFileManager.relativePathForAttachment(
          contactPeerId: group.id,
          blobId: attachmentId,
          mime: 'image/png',
        );
        final absolutePath = await mediaFileManager.resolveStoredPath(
          relativePath,
        );
        final mediaFile = File(absolutePath);
        mediaFile.parent.createSync(recursive: true);
        mediaFile.writeAsBytesSync(_tinyPngBytes, flush: true);
        await mediaAttachmentRepo.saveAttachment(
          pendingImageAttachment.copyWith(
            localPath: relativePath,
            downloadStatus: kMediaDownloadStatusDone,
          ),
          owner: MediaOwnerLane.group,
        );
        await tester.runAsync(() async {
          messageStreamController.add(incomingMessage);
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();
        // Wait for the background download to surface as Done with the resolved
        // local path; the tile now renders Image.file (showing the 143 decode
        // placeholder until a frame is available).
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          final media = screen.mediaMap[messageId];
          return media != null &&
              media.single.downloadStatus == kMediaDownloadStatusDone &&
              media.single.localPath == absolutePath &&
              mediaGridBrokenImageCount() == 0;
        }, maxPumps: 80);

        final refreshedScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(refreshedScreen.mediaMap[messageId], hasLength(1));
        expect(
          refreshedScreen.mediaMap[messageId]!.single.downloadStatus,
          kMediaDownloadStatusDone,
        );
        expect(
          bridge.commandLog.where((cmd) => cmd == 'media:download').length,
          lessThanOrEqualTo(1),
        );
        expect(find.text('Media unavailable'), findsNothing);
        expect(mediaGridBrokenImageCount(), 0);
        // The refreshed tile renders the resolved local image — the background
        // download reached the tile without a reopen. (143: the tile may still
        // show the sized decode placeholder until the first frame is available,
        // which the fake-async host harness cannot drive; decode-completion is
        // covered by the MediaThumbnailImage widget tests, so we assert the
        // Image is wired in rather than that the spinner has cleared.)
        expect(
          find.descendant(
            of: find.byType(MediaGrid),
            matching: find.byType(Image),
          ),
          findsOneWidget,
        );

        await tester.tap(find.byType(MediaGrid));
        await pumpFrames(tester, count: 4);
        expect(find.byType(FullScreenTypedMediaViewer), findsOneWidget);
        if (!downloadGate.isCompleted) {
          downloadGate.complete();
        }
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
      },
    );

    testWidgets(
      'incoming done media without encryption metadata is quarantined but local outgoing owned media can display',
      (tester) async {
        final group = makeChatGroup();
        final tempDir = Directory.systemTemp.createTempSync(
          'group-display-policy-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final mediaFileManager = TrackingDurableMediaFileManager(tempDir);
        final contentHash = _md012HashBytes(_tinyPngBytes);

        void writeRelativeMedia(String relativePath) {
          final file = File(p.join(tempDir.path, relativePath));
          file.parent.createSync(recursive: true);
          file.writeAsBytesSync(_tinyPngBytes);
        }

        writeRelativeMedia('media/${group.id}/incoming-no-key.jpg');
        writeRelativeMedia('media/${group.id}/outgoing-no-key.jpg');
        await groupRepo.saveGroup(group);
        await messageStreamController.close();
        messageStreamController = StreamController<GroupMessage>.broadcast(
          sync: true,
        );

        final incomingMessage = makeMessage(
          id: 'msg-incoming-no-key',
          text: 'Incoming media',
          groupId: group.id,
          isIncoming: true,
        );
        final outgoingMessage = makeMessage(
          id: 'msg-outgoing-no-key',
          text: 'Outgoing media',
          groupId: group.id,
          isIncoming: false,
          senderPeerId: testIdentity.peerId,
          senderUsername: testIdentity.username,
        );
        await mediaAttachmentRepo.saveAttachment(
          MediaAttachment(
            id: 'incoming-no-key',
            messageId: 'msg-incoming-no-key',
            mime: 'image/png',
            size: _tinyPngBytes.length,
            mediaType: 'image',
            localPath: 'media/${group.id}/incoming-no-key.jpg',
            downloadStatus: kMediaDownloadStatusDone,
            contentHash: contentHash,
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
          owner: MediaOwnerLane.group,
        );
        await mediaAttachmentRepo.saveAttachment(
          MediaAttachment(
            id: 'outgoing-no-key',
            messageId: 'msg-outgoing-no-key',
            mime: 'image/png',
            size: _tinyPngBytes.length,
            mediaType: 'image',
            localPath: 'media/${group.id}/outgoing-no-key.jpg',
            downloadStatus: kMediaDownloadStatusDone,
            contentHash: contentHash,
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
          owner: MediaOwnerLane.group,
        );

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
          ),
        );
        await pumpUntil(tester, () => msgRepo.getMessagesPageCalls > 0);
        await msgRepo.saveMessage(incomingMessage);
        await msgRepo.saveMessage(outgoingMessage);
        await tester.runAsync(() async {
          messageStreamController.add(incomingMessage);
          messageStreamController.add(outgoingMessage);
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen.mediaMap.containsKey('msg-incoming-no-key') &&
              screen.mediaMap.containsKey('msg-outgoing-no-key');
        });

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(msgRepo.getMessagesPageCalls, greaterThan(0));
        expect(
          screen.messages.map((message) => message.id),
          containsAll(['msg-incoming-no-key', 'msg-outgoing-no-key']),
        );
        expect(
          screen.mediaMap.keys,
          containsAll(['msg-incoming-no-key', 'msg-outgoing-no-key']),
        );
        expect(
          screen.mediaMap['msg-incoming-no-key']!.single.downloadStatus,
          kMediaDownloadStatusIntegrityFailed,
        );
        expect(
          screen.mediaMap['msg-incoming-no-key']!.single.localPath,
          isNull,
        );
        expect(
          screen.mediaMap['msg-outgoing-no-key']!.single.downloadStatus,
          kMediaDownloadStatusDone,
        );
        expect(
          screen.mediaMap['msg-outgoing-no-key']!.single.localPath,
          contains('outgoing-no-key.jpg'),
        );
      },
    );

    testWidgets(
      'GIRD-005 active failed group image recovery shows loading before resolving while open',
      (tester) async {
        final group = makeChatGroup();
        final mediaFileManager = FakeMediaFileManager();
        final encryptedBytes = _md012EncryptedBytes(_tinyPngBytes);
        final downloadGate = Completer<void>();
        bridge = _DownloadRepairBridge(
          downloadedBytes: encryptedBytes,
          downloadGate: downloadGate,
        );

        await groupRepo.saveGroup(group);
        await messageStreamController.close();
        messageStreamController = StreamController<GroupMessage>.broadcast(
          sync: true,
        );
        final incomingMessage = makeMessage(
          id: 'msg-gird005-failed-recovery',
          text: 'retry failed image',
          groupId: group.id,
          isIncoming: true,
          status: 'delivered',
        );
        final failedAttachment = MediaAttachment(
          id: 'att-gird005-failed-recovery',
          messageId: 'msg-gird005-failed-recovery',
          mime: 'image/png',
          size: _tinyPngBytes.length,
          mediaType: 'image',
          width: 1,
          height: 1,
          downloadStatus: kMediaDownloadStatusFailed,
          contentHash: _md012HashBytes(encryptedBytes),
          encryptionKeyBase64: _md012MediaKey,
          encryptionNonce: _md012MediaNonce,
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          createdAt: '2026-05-31T10:00:00.000Z',
        );

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
          ),
        );
        await pumpFrames(tester, count: 20);
        await msgRepo.saveMessage(incomingMessage);
        await mediaAttachmentRepo.saveAttachment(
          failedAttachment,
          owner: MediaOwnerLane.group,
        );
        await tester.runAsync(() async {
          messageStreamController.add(incomingMessage);
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen.mediaMap.containsKey('msg-gird005-failed-recovery') &&
              bridge.commandLog
                      .where((cmd) => cmd == 'media:download')
                      .length ==
                  1;
        }, maxPumps: 80);

        int mediaGridBrokenImageCount() => find
            .descendant(
              of: find.byType(MediaGrid),
              matching: find.byIcon(Icons.broken_image_outlined),
            )
            .evaluate()
            .length;

        int mediaGridLoadingCount() => find
            .descendant(
              of: find.byType(MediaGrid),
              matching: find.byType(CircularProgressIndicator),
            )
            .evaluate()
            .length;

        final loadingScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(
          loadingScreen
              .mediaMap['msg-gird005-failed-recovery']!
              .single
              .downloadStatus,
          kMediaDownloadStatusDownloading,
        );
        expect(find.text('Media unavailable'), findsNothing);
        expect(mediaGridBrokenImageCount(), 0);
        expect(mediaGridLoadingCount(), 1);
        expect(
          find.byKey(
            const ValueKey(
              'unavailable-media-retry-msg-gird005-failed-recovery-att-gird005-failed-recovery',
            ),
          ),
          findsNothing,
        );

        final failedRelativePath = mediaFileManager.relativePathForAttachment(
          contactPeerId: group.id,
          blobId: failedAttachment.id,
          mime: failedAttachment.mime,
        );
        final failedAbsolutePath = await mediaFileManager.resolveStoredPath(
          failedRelativePath,
        );
        final failedFile = File(failedAbsolutePath);
        failedFile.parent.createSync(recursive: true);
        failedFile.writeAsBytesSync(_tinyPngBytes, flush: true);
        await mediaAttachmentRepo.saveAttachment(
          failedAttachment.copyWith(
            localPath: failedRelativePath,
            downloadStatus: kMediaDownloadStatusDone,
          ),
          owner: MediaOwnerLane.group,
        );
        await tester.runAsync(() async {
          messageStreamController.add(incomingMessage);
          await Future<void>.delayed(const Duration(milliseconds: 500));
        });
        await tester.pump();
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          final media = screen.mediaMap['msg-gird005-failed-recovery'];
          return media != null &&
              media.single.downloadStatus == kMediaDownloadStatusDone &&
              media.single.localPath != null &&
              mediaGridBrokenImageCount() == 0 &&
              mediaGridLoadingCount() == 0;
        }, maxPumps: 80);

        final resolvedScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final persistedAfterFailedRecovery = await mediaAttachmentRepo
            .getAttachmentsForMessage(
              'msg-gird005-failed-recovery',
              owner: MediaOwnerLane.group,
            );
        expect(
          resolvedScreen
              .mediaMap['msg-gird005-failed-recovery']!
              .single
              .localPath,
          allOf(isNotNull, contains('att-gird005-failed-recovery.png')),
          reason:
              'screen=${resolvedScreen.mediaMap['msg-gird005-failed-recovery']?.map((a) => a.toMap()).toList()}, '
              'persisted=${persistedAfterFailedRecovery.map((a) => a.toMap()).toList()}, '
              'commands=${bridge.commandLog}',
        );
        expect(find.text('Media unavailable'), findsNothing);

        await tester.tap(find.byType(MediaGrid));
        await pumpFrames(tester, count: 4);
        expect(find.byType(FullScreenTypedMediaViewer), findsOneWidget);
        if (!downloadGate.isCompleted) {
          downloadGate.complete();
        }
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
      },
    );

    testWidgets(
      'GIRD-005 done group image without local path stays resolving and recovers',
      (tester) async {
        final group = makeChatGroup();
        final mediaFileManager = FakeMediaFileManager();
        final encryptedBytes = _md012EncryptedBytes(_tinyPngBytes);
        final downloadGate = Completer<void>();
        bridge = _DownloadRepairBridge(
          downloadedBytes: encryptedBytes,
          downloadGate: downloadGate,
        );

        await groupRepo.saveGroup(group);
        await messageStreamController.close();
        messageStreamController = StreamController<GroupMessage>.broadcast(
          sync: true,
        );
        final incomingMessage = makeMessage(
          id: 'msg-gird005-done-no-path',
          text: 'hydrate missing path',
          groupId: group.id,
          isIncoming: true,
          status: 'delivered',
        );
        final doneAttachment = MediaAttachment(
          id: 'att-gird005-done-no-path',
          messageId: 'msg-gird005-done-no-path',
          mime: 'image/png',
          size: _tinyPngBytes.length,
          mediaType: 'image',
          width: 1,
          height: 1,
          downloadStatus: kMediaDownloadStatusDone,
          contentHash: _md012HashBytes(encryptedBytes),
          encryptionKeyBase64: _md012MediaKey,
          encryptionNonce: _md012MediaNonce,
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          createdAt: '2026-05-31T10:05:00.000Z',
        );

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
          ),
        );
        await pumpFrames(tester, count: 20);
        await msgRepo.saveMessage(incomingMessage);
        await mediaAttachmentRepo.saveAttachment(
          doneAttachment,
          owner: MediaOwnerLane.group,
        );
        await tester.runAsync(() async {
          messageStreamController.add(incomingMessage);
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen.mediaMap.containsKey('msg-gird005-done-no-path') &&
              bridge.commandLog
                      .where((cmd) => cmd == 'media:download')
                      .length ==
                  1;
        }, maxPumps: 80);

        int mediaGridBrokenImageCount() => find
            .descendant(
              of: find.byType(MediaGrid),
              matching: find.byIcon(Icons.broken_image_outlined),
            )
            .evaluate()
            .length;

        int mediaGridLoadingCount() => find
            .descendant(
              of: find.byType(MediaGrid),
              matching: find.byType(CircularProgressIndicator),
            )
            .evaluate()
            .length;

        final loadingScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(
          loadingScreen
              .mediaMap['msg-gird005-done-no-path']!
              .single
              .downloadStatus,
          kMediaDownloadStatusDownloading,
        );
        expect(find.text('Media unavailable'), findsNothing);
        expect(mediaGridBrokenImageCount(), 0);
        expect(mediaGridLoadingCount(), 1);
        expect(
          find.byKey(
            const ValueKey(
              'unavailable-media-retry-msg-gird005-done-no-path-att-gird005-done-no-path',
            ),
          ),
          findsNothing,
        );

        final doneRelativePath = mediaFileManager.relativePathForAttachment(
          contactPeerId: group.id,
          blobId: doneAttachment.id,
          mime: doneAttachment.mime,
        );
        final doneAbsolutePath = await mediaFileManager.resolveStoredPath(
          doneRelativePath,
        );
        final doneFile = File(doneAbsolutePath);
        doneFile.parent.createSync(recursive: true);
        doneFile.writeAsBytesSync(_tinyPngBytes, flush: true);
        await mediaAttachmentRepo.saveAttachment(
          doneAttachment.copyWith(
            localPath: doneRelativePath,
            downloadStatus: kMediaDownloadStatusDone,
          ),
          owner: MediaOwnerLane.group,
        );
        await tester.runAsync(() async {
          messageStreamController.add(incomingMessage);
          await Future<void>.delayed(const Duration(milliseconds: 500));
        });
        await tester.pump();
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          final media = screen.mediaMap['msg-gird005-done-no-path'];
          return media != null &&
              media.single.downloadStatus == kMediaDownloadStatusDone &&
              media.single.localPath != null &&
              mediaGridBrokenImageCount() == 0 &&
              mediaGridLoadingCount() == 0;
        }, maxPumps: 80);

        final resolvedScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final persistedAfterDoneRecovery = await mediaAttachmentRepo
            .getAttachmentsForMessage(
              'msg-gird005-done-no-path',
              owner: MediaOwnerLane.group,
            );
        expect(
          resolvedScreen.mediaMap['msg-gird005-done-no-path']!.single.localPath,
          allOf(isNotNull, contains('att-gird005-done-no-path.png')),
          reason:
              'screen=${resolvedScreen.mediaMap['msg-gird005-done-no-path']?.map((a) => a.toMap()).toList()}, '
              'persisted=${persistedAfterDoneRecovery.map((a) => a.toMap()).toList()}, '
              'commands=${bridge.commandLog}',
        );
        expect(find.text('Media unavailable'), findsNothing);

        await tester.tap(find.byType(MediaGrid));
        await pumpFrames(tester, count: 4);
        expect(find.byType(FullScreenTypedMediaViewer), findsOneWidget);
        if (!downloadGate.isCompleted) {
          downloadGate.complete();
        }
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
      },
    );

    testWidgets(
      'MS003 live stream upsert orders equal timestamps by message id',
      (tester) async {
        final group = makeChatGroup();
        final sameTimestamp = DateTime.utc(2026, 4, 30, 12);
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(
          makeMessage(
            id: 'ms003-b',
            text: 'B at same time',
            timestamp: sameTimestamp,
          ),
        );

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester);

        final incoming = makeMessage(
          id: 'ms003-a',
          text: 'A at same time',
          timestamp: sameTimestamp,
        );
        await msgRepo.saveMessage(incoming);
        messageStreamController.add(incoming);
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.messages.map((message) => message.id), [
          'ms003-a',
          'ms003-b',
        ]);
      },
    );

    testWidgets(
      'GP-027 out-of-order live messages keep deterministic order after restart',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester);

        final later = makeMessage(
          id: 'gp027-b-later',
          senderPeerId: 'peer-bob',
          senderUsername: 'Bob',
          text: 'Bob arrives first but happened second',
          timestamp: DateTime.utc(2026, 5, 14, 12, 0, 2),
        );
        await msgRepo.saveMessage(later);
        messageStreamController.add(later);
        await pumpFrames(tester, count: 20);

        final earlier = makeMessage(
          id: 'gp027-a-earlier',
          senderPeerId: 'peer-alice',
          senderUsername: 'Alice',
          text: 'Alice arrives second but happened first',
          timestamp: DateTime.utc(2026, 5, 14, 12, 0, 1),
        );
        await msgRepo.saveMessage(earlier);
        messageStreamController.add(earlier);
        await pumpFrames(tester, count: 20);

        GroupConversationScreen screen() =>
            tester.widget<GroupConversationScreen>(
              find.byType(GroupConversationScreen),
            );

        expect(screen().messages.map((message) => message.id), [
          'gp027-a-earlier',
          'gp027-b-later',
        ]);

        await tester.pumpWidget(const SizedBox.shrink());
        await pumpFrames(tester);
        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester, count: 20);

        expect(screen().messages.map((message) => message.id), [
          'gp027-a-earlier',
          'gp027-b-later',
        ]);
      },
    );

    testWidgets('MS004 live stream upsert keeps quoted parent before reply', (
      tester,
    ) async {
      final group = makeChatGroup();
      final parentTimestamp = DateTime.utc(2026, 4, 30, 12, 0, 1);
      final replyTimestamp = DateTime.utc(2026, 4, 30, 12);
      await groupRepo.saveGroup(group);
      await msgRepo.saveMessage(
        makeMessage(
          id: 'zz-ms004-parent',
          text: 'Parent',
          timestamp: parentTimestamp,
        ),
      );
      await msgRepo.saveMessage(
        makeMessage(
          id: 'mm-ms004-peer',
          text: 'Concurrent peer',
          timestamp: replyTimestamp,
        ),
      );

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester);

      final reply = makeMessage(
        id: 'aa-ms004-reply',
        text: 'Reply',
        timestamp: replyTimestamp,
        quotedMessageId: 'zz-ms004-parent',
      );
      await msgRepo.saveMessage(reply);
      messageStreamController.add(reply);
      await pumpFrames(tester, count: 20);

      final screen = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      expect(screen.messages.map((message) => message.id), [
        'mm-ms004-peer',
        'zz-ms004-parent',
        'aa-ms004-reply',
      ]);
    });

    testWidgets('live removal timeline event from listener appears in UI', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester);

      messageStreamController.add(
        makeMessage(
          id: 'sys-member-removed-1',
          text: 'Admin removed Charlie',
          groupId: 'group-1',
          senderPeerId: 'peer-admin',
          senderUsername: 'Admin',
        ),
      );
      await pumpFrames(tester, count: 20);

      expect(find.text('Admin removed Charlie'), findsOneWidget);
    });

    testWidgets('live re-add timeline event from listener appears in UI', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester);

      messageStreamController.add(
        makeMessage(
          id: 'sys-member-added-1',
          text: 'Admin added Charlie',
          groupId: 'group-1',
          senderPeerId: 'peer-admin',
          senderUsername: 'Admin',
        ),
      );
      await pumpFrames(tester, count: 20);

      expect(find.text('Admin added Charlie'), findsOneWidget);
    });

    testWidgets('shows loading shell until the initial group page resolves', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

      final slowRepo = SlowInitialPageGroupMessageRepository();
      await slowRepo.saveMessage(
        makeMessage(id: 'msg-delayed', text: 'Loaded after delay'),
      );
      msgRepo = slowRepo;

      await tester.pumpWidget(
        buildWidget(group: group, mediaRepo: mediaAttachmentRepo),
      );
      await tester.pump();

      expect(find.byKey(const ValueKey('group-loading-shell')), findsOneWidget);
      expect(find.text('Loaded after delay'), findsNothing);

      slowRepo.firstPageGate.complete();
      await pumpFrames(tester, count: 20);

      expect(find.byKey(const ValueKey('group-loading-shell')), findsNothing);
      expect(find.text('Loaded after delay'), findsOneWidget);
    });

    testWidgets(
      'message load failure shows retryable error instead of empty conversation',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        final failingRepo = FailingInitialPageGroupMessageRepository();
        msgRepo = failingRepo;

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester, count: 20);

        expect(find.byKey(const ValueKey('group-loading-shell')), findsNothing);
        expect(find.text("Couldn't load messages"), findsOneWidget);
        expect(
          find.byKey(const ValueKey('group-conversation-load-retry')),
          findsOneWidget,
        );
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('No messages yet'), findsNothing);

        await failingRepo.saveMessage(
          makeMessage(id: 'msg-recovered', text: 'Recovered on retry'),
        );
        await tester.tap(
          find.byKey(const ValueKey('group-conversation-load-retry')),
        );
        await pumpFrames(tester, count: 20);

        expect(failingRepo.getMessagesPageCalls, 2);
        expect(find.text('Recovered on retry'), findsOneWidget);
        expect(find.text("Couldn't load messages"), findsNothing);
        expect(find.text('No messages yet'), findsNothing);
      },
    );

    testWidgets(
      'IR-018 keeps messages live while restart replay is pending without flashing a banner',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(
          makeMessage(id: 'ir018-stale-local', text: 'Local before replay'),
        );
        groupRecoveryGate.begin();

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester, count: 20);

        expect(
          find.byKey(const ValueKey('group-recovery-banner')),
          findsNothing,
        );
        expect(find.text('Local before replay'), findsOneWidget);

        messageStreamController.add(
          makeMessage(
            id: 'ir018-live-during-recovery',
            text: 'Live during replay recovery',
          ),
        );
        await pumpFrames(tester, count: 20);

        expect(find.text('Live during replay recovery'), findsOneWidget);

        groupRecoveryGate.end();
        await pumpFrames(tester, count: 5);

        expect(
          find.byKey(const ValueKey('group-recovery-banner')),
          findsNothing,
        );
        expect(find.text('Live during replay recovery'), findsOneWidget);
      },
    );

    testWidgets(
      'highlights the targeted message context when opened from a notification anchor',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        final start = DateTime.utc(2026, 2, 1, 10);
        await msgRepo.saveMessage(
          GroupMessage(
            id: 'msg-older',
            groupId: group.id,
            senderPeerId: 'peer-alice',
            senderUsername: 'Alice',
            text: 'Older message',
            timestamp: start,
            createdAt: start,
          ),
        );
        await msgRepo.saveMessage(
          GroupMessage(
            id: 'msg-targeted',
            groupId: group.id,
            senderPeerId: 'peer-bob',
            senderUsername: 'Bob',
            text: 'Tapped notification message',
            timestamp: start.add(const Duration(minutes: 1)),
            createdAt: start.add(const Duration(minutes: 1)),
          ),
        );

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            initialHighlightedMessageId: 'msg-targeted',
          ),
        );
        await pumpFrames(tester, count: 20);

        expect(find.text('Tapped notification message'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('grp-highlight-msg-targeted')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<Stack>(
                find.byKey(const ValueKey('grp-highlight-msg-targeted')),
              )
              .clipBehavior,
          Clip.none,
        );
        expect(
          find.byKey(const ValueKey('grp-highlight-cue-msg-targeted')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('grp-highlight-msg-older')),
          findsNothing,
        );

        await tester.longPress(find.text('Tapped notification message'));
        await pumpFrames(tester);

        expect(find.byKey(MessageContextOverlay.overlayKey), findsOneWidget);
        expect(
          find.byKey(MessageContextOverlay.replyActionKey),
          findsOneWidget,
        );
        expect(find.byKey(MessageContextOverlay.copyActionKey), findsOneWidget);
      },
    );

    testWidgets(
      'scrolls a notification-tapped older message into view, not merely highlights it',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        final start = DateTime.utc(2026, 2, 1, 10);
        for (var index = 0; index < 40; index++) {
          await msgRepo.saveMessage(
            GroupMessage(
              id: 'msg-$index',
              groupId: group.id,
              senderPeerId: 'peer-alice',
              senderUsername: 'Alice',
              text: 'Message $index',
              timestamp: start.add(Duration(minutes: index)),
              createdAt: start.add(Duration(minutes: index)),
            ),
          );
        }

        // The oldest message sits at the far end of the reversed list — well
        // off-screen from the live edge a fresh open lands on.
        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            initialHighlightedMessageId: 'msg-0',
          ),
        );
        await pumpFrames(tester, count: 30);

        final highlight = find.byKey(const ValueKey('grp-highlight-msg-0'));
        expect(
          highlight,
          findsOneWidget,
          reason: 'the tapped row must be built and brought on-screen',
        );

        final listRect = tester.getRect(
          find.byKey(const ValueKey('group-messages')),
        );
        final targetRect = tester.getRect(highlight);
        expect(
          targetRect.overlaps(listRect),
          isTrue,
          reason: 'the tapped row must overlap the visible list viewport',
        );
      },
    );

    testWidgets(
      'notification-anchor entry keeps group reaction inspection aligned with the shared conversation surface',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: testIdentity.peerId,
            username: testIdentity.username,
            role: MemberRole.admin,
            joinedAt: DateTime.utc(2026, 2, 1, 10),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: 'peer-bob',
            username: 'Bob',
            role: MemberRole.writer,
            joinedAt: DateTime.utc(2026, 2, 1, 10, 1),
          ),
        );

        final start = DateTime.utc(2026, 2, 1, 10);
        await msgRepo.saveMessage(
          GroupMessage(
            id: 'msg-anchor-older',
            groupId: group.id,
            senderPeerId: 'peer-alice',
            senderUsername: 'Alice',
            text: 'Older anchor message',
            timestamp: start,
            createdAt: start,
          ),
        );
        await msgRepo.saveMessage(
          GroupMessage(
            id: 'msg-anchor-targeted',
            groupId: group.id,
            senderPeerId: 'peer-bob',
            senderUsername: 'Bob',
            text: 'Targeted anchor reaction message',
            timestamp: start.add(const Duration(minutes: 1)),
            createdAt: start.add(const Duration(minutes: 1)),
          ),
        );

        final reactionRepo = FakeReactionRepository();
        await reactionRepo.saveReaction(
          MessageReaction(
            id: 'rxn-anchor-self',
            messageId: 'msg-anchor-targeted',
            emoji: '🔥',
            senderPeerId: testIdentity.peerId,
            timestamp: start.add(const Duration(minutes: 2)).toIso8601String(),
            createdAt: start.add(const Duration(minutes: 2)).toIso8601String(),
          ),
        );
        await reactionRepo.saveReaction(
          MessageReaction(
            id: 'rxn-anchor-bob',
            messageId: 'msg-anchor-targeted',
            emoji: '🔥',
            senderPeerId: 'peer-bob',
            timestamp: start.add(const Duration(minutes: 3)).toIso8601String(),
            createdAt: start.add(const Duration(minutes: 3)).toIso8601String(),
          ),
        );

        await tester.pumpWidget(
          buildWidget(
            group: group,
            reactionRepo: reactionRepo,
            initialHighlightedMessageId: 'msg-anchor-targeted',
          ),
        );
        await pumpFrames(tester, count: 20);

        expect(
          find.byKey(const ValueKey('grp-highlight-msg-anchor-targeted')),
          findsOneWidget,
        );
        expect(
          tester
              .widget<Stack>(
                find.byKey(const ValueKey('grp-highlight-msg-anchor-targeted')),
              )
              .clipBehavior,
          Clip.none,
        );
        expect(
          find.byKey(const ValueKey('grp-highlight-cue-msg-anchor-targeted')),
          findsOneWidget,
        );
        expect(find.text('🔥 2'), findsOneWidget);

        await tester.tap(find.text('🔥 2'));
        await pumpFrames(tester);

        expect(find.byKey(GroupReactionDetailsSheet.sheetKey), findsOneWidget);
        expect(find.text('You'), findsOneWidget);
        expect(find.text('Bob'), findsWidgets);
        expect(reactionRepo.removeReactionCallCount, 0);
      },
    );

    testWidgets(
      'incoming message preserves scroll offset when reading older messages',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        final start = DateTime.utc(2026, 2, 1, 10);
        for (var index = 0; index < 40; index++) {
          await msgRepo.saveMessage(
            GroupMessage(
              id: 'msg-$index',
              groupId: group.id,
              senderPeerId: 'peer-alice',
              senderUsername: 'Alice',
              text: 'Message $index',
              timestamp: start.add(Duration(minutes: index)),
              createdAt: start.add(Duration(minutes: index)),
            ),
          );
        }

        await tester.pumpWidget(
          buildWidget(group: group, mediaRepo: mediaAttachmentRepo),
        );
        await pumpFrames(tester, count: 20);

        final listFinder = find.byKey(const ValueKey('group-messages'));
        expect(listFinder, findsOneWidget);

        final controller = tester.widget<ListView>(listFinder).controller!;
        expect(controller.hasClients, isTrue);

        controller.jumpTo(240);
        await pumpFrames(tester, count: 4);

        final offsetBefore = controller.offset;
        expect(offsetBefore, greaterThan(32));

        final incoming = GroupMessage(
          id: 'msg-late',
          groupId: group.id,
          senderPeerId: 'peer-bob',
          senderUsername: 'Bob',
          text: 'Newest while reading history',
          timestamp: start.add(const Duration(minutes: 60)),
          createdAt: start.add(const Duration(minutes: 60)),
        );
        await msgRepo.saveMessage(incoming);

        messageStreamController.add(incoming);
        await pumpFrames(tester, count: 20);

        expect(controller.offset, closeTo(offsetBefore, 1.0));
        expect(msgRepo.getMessagesPageCalls, 1);
        expect(mediaAttachmentRepo.getAttachmentsForMessagesCalls, 1);
      },
    );

    testWidgets(
      'own text send snaps back to the live edge even when reading older messages',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);

        final start = DateTime.utc(2026, 2, 1, 10);
        for (var index = 0; index < 40; index++) {
          await msgRepo.saveMessage(
            GroupMessage(
              id: 'msg-$index',
              groupId: group.id,
              senderPeerId: 'peer-alice',
              senderUsername: 'Alice',
              text: 'Message $index',
              timestamp: start.add(Duration(minutes: index)),
              createdAt: start.add(Duration(minutes: index)),
            ),
          );
        }

        await tester.pumpWidget(
          buildWidget(group: group, mediaRepo: mediaAttachmentRepo),
        );
        await pumpFrames(tester, count: 20);

        final controller = tester
            .widget<ListView>(find.byKey(const ValueKey('group-messages')))
            .controller!;
        expect(controller.hasClients, isTrue);

        // Scroll up into history (reverse list: offset 0 == newest/live edge).
        controller.jumpTo(240);
        await pumpFrames(tester, count: 4);
        expect(controller.offset, greaterThan(32));

        // The user acts: an own send must bring them back to their own message
        // at the live edge.
        await tester.enterText(find.byType(TextField), 'My own send');
        await pumpFrames(tester);
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpFrames(tester, count: 20);

        expect(find.text('My own send'), findsOneWidget);
        expect(controller.offset, closeTo(0, 1.0));
      },
    );

    testWidgets(
      'own voice send snaps back to the live edge even when reading older messages',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);

        final start = DateTime.utc(2026, 2, 1, 10);
        for (var index = 0; index < 40; index++) {
          await msgRepo.saveMessage(
            GroupMessage(
              id: 'msg-$index',
              groupId: group.id,
              senderPeerId: 'peer-alice',
              senderUsername: 'Alice',
              text: 'Message $index',
              timestamp: start.add(Duration(minutes: index)),
              createdAt: start.add(Duration(minutes: index)),
            ),
          );
        }

        final tempDir = Directory.systemTemp.createTempSync(
          'group-voice-scroll-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });
        final recorder = FakeAudioRecorderService()..fakeDurationMs = 1500;
        final voiceFile = File(p.join(tempDir.path, 'voice.m4a'))
          ..writeAsStringSync('voice');
        recorder.fakeOutputPath = voiceFile.path;
        final mediaFileManager = TrackingDurableMediaFileManager(tempDir);

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            audioRecorderService: recorder,
            // The optimistic insert (and its scroll) fire before the upload, so
            // a no-op upload keeps the assertion deterministic.
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                  deleteSourceWhenDone = false,
                  preparedArtifact,
                }) async => null,
          ),
        );
        await pumpFrames(tester, count: 20);

        final controller = tester
            .widget<ListView>(find.byKey(const ValueKey('group-messages')))
            .controller!;
        controller.jumpTo(240);
        await pumpFrames(tester, count: 4);
        expect(controller.offset, greaterThan(32));

        final messagesBefore = tester
            .widget<GroupConversationScreen>(
              find.byType(GroupConversationScreen),
            )
            .messages
            .length;

        final startRecording =
            tester
                    .widget<GroupConversationScreen>(
                      find.byType(GroupConversationScreen),
                    )
                    .onRecordStart!
                as Future<void> Function();
        await startRecording();
        await pumpUntil(
          tester,
          () =>
              tester
                  .widget<GroupConversationScreen>(
                    find.byType(GroupConversationScreen),
                  )
                  .recordingState ==
              VoiceRecordingState.recording,
        );

        final stopRecording =
            tester
                    .widget<GroupConversationScreen>(
                      find.byType(GroupConversationScreen),
                    )
                    .onRecordStop!
                as Future<void> Function();
        await tester.runAsync(() async {
          await stopRecording();
        });
        await pumpFrames(tester, count: 20);

        final messagesAfter = tester
            .widget<GroupConversationScreen>(
              find.byType(GroupConversationScreen),
            )
            .messages
            .length;
        expect(
          messagesAfter,
          greaterThan(messagesBefore),
          reason: 'optimistic voice message was inserted',
        );
        expect(controller.offset, closeTo(0, 1.0));
      },
    );

    testWidgets(
      'recording ticks update composer without rebuilding header or message list',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(makeMessage(id: 'msg-rec-1', text: 'Hello'));
        final recorder = FakeAudioRecorderService()..fakeDurationMs = 100;

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: FakeMediaFileManager(),
            audioRecorderService: recorder,
          ),
        );
        await pumpFrames(tester, count: 20);

        final headerFinder = find.byKey(const ValueKey('group-header'));
        final listFinder = find.byKey(const ValueKey('group-messages'));
        final headerElement = tester.element(headerFinder);
        final listElement = tester.element(listFinder);
        final initialPageLoads = msgRepo.getMessagesPageCalls;
        final initialBatchMediaLoads =
            mediaAttachmentRepo.getAttachmentsForMessagesCalls;

        final gesture = await tester.startGesture(
          tester.getCenter(find.byIcon(Icons.mic_rounded)),
        );
        await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
        await tester.pump();

        recorder.emitDuration(const Duration(seconds: 2));
        recorder.emitAmplitude(0.5);
        await tester.pump();

        expect(find.text('Cancel'), findsOneWidget);
        expect(find.text('0:02'), findsOneWidget);
        expect(identical(headerElement, tester.element(headerFinder)), isTrue);
        expect(identical(listElement, tester.element(listFinder)), isTrue);
        expect(msgRepo.getMessagesPageCalls, initialPageLoads);
        expect(
          mediaAttachmentRepo.getAttachmentsForMessagesCalls,
          initialBatchMediaLoads,
        );

        await gesture.up();
        await tester.pump();
      },
    );

    testWidgets(
      'voice record callbacks switch the group composer into and out of recording',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        final recorder = FakeAudioRecorderService()..fakeDurationMs = 100;

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: FakeMediaFileManager(),
            audioRecorderService: recorder,
          ),
        );
        await pumpFrames(tester, count: 20);

        final recordingScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final startRecording =
            recordingScreen.onRecordStart! as Future<void> Function();
        await startRecording();
        await tester.pump();

        expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);

        final stopScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final stopRecording =
            stopScreen.onRecordStop! as Future<void> Function();
        await stopRecording();
        await tester.pump();

        expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      },
    );

    testWidgets('info button navigates to group info', (tester) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester);

      // Tap the info icon
      final infoButton = find.byIcon(Icons.info_outline);
      expect(infoButton, findsOneWidget);
      await tester.tap(infoButton);
      await pumpFrames(tester, count: 20);

      // GroupInfoScreen should appear (inside GroupInfoWired)
      expect(find.byType(GroupInfoScreen), findsOneWidget);
    });

    testWidgets('returning from group info reloads the latest group name', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester, count: 20);

      expect(find.text('Test Group'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.info_outline));
      await pumpFrames(tester, count: 20);

      expect(find.byType(GroupInfoScreen), findsOneWidget);

      await groupRepo.updateGroup(
        group.copyWith(
          name: 'Renamed Group',
          description: 'Updated description',
        ),
      );

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new).first);
      await pumpFrames(tester, count: 20);

      expect(find.byType(GroupInfoScreen), findsNothing);
      expect(find.text('Renamed Group'), findsOneWidget);
    });

    testWidgets('non-admin in announcement group cannot write', (tester) async {
      final group = makeAnnouncementGroup(role: GroupRole.member);
      await groupRepo.saveGroup(group);

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester);

      // The compose area should show the read-only message instead of a text field
      expect(
        find.text('Only admins can send messages in this group'),
        findsOneWidget,
      );

      // TextField should not be present (canWrite=false hides it)
      expect(find.byType(TextField), findsNothing);
      expect(find.byIcon(Icons.add_rounded), findsNothing);
      expect(find.byIcon(Icons.mic_rounded), findsNothing);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);

      final screen = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      expect(screen.onAttach, isNull);
      expect(screen.onRecordStart, isNull);
      expect(screen.onRecordStop, isNull);
      expect(screen.onRecordCancel, isNull);
      expect(screen.onQuoteReply, isNull);
    });

    testWidgets('dissolved groups show read-only copy and no send controls', (
      tester,
    ) async {
      final group = makeChatGroup().copyWith(
        isDissolved: true,
        dissolvedAt: DateTime.utc(2026, 4, 5, 12, 0, 0),
        dissolvedBy: 'peer-admin',
      );
      await groupRepo.saveGroup(group);

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester);

      expect(find.text('Dissolved'), findsOneWidget);
      expect(
        find.text(
          'This group has been dissolved. History stays available, but new messages are disabled.',
        ),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
      expect(find.byIcon(Icons.add_rounded), findsNothing);
      expect(find.byIcon(Icons.mic_rounded), findsNothing);
      expect(find.byIcon(Icons.arrow_upward_rounded), findsNothing);

      final screen = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      expect(screen.onAttach, isNull);
      expect(screen.onRecordStart, isNull);
      expect(screen.onRecordStop, isNull);
      expect(screen.onRecordCancel, isNull);
      expect(screen.onQuoteReply, isNull);
    });

    testWidgets(
      'active groups expose the long-press reaction bar when mutation deps are wired',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(makeMessage(id: 'msg-1', text: 'Hello'));

        await tester.pumpWidget(
          buildWidget(
            group: group,
            reactionRepo: FakeReactionRepository(),
            reactionReplayOutboxRepo: FakeGroupReactionReplayOutboxRepository(),
          ),
        );
        await pumpFrames(tester);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.onReactionSelected, isNotNull);

        await tester.longPress(find.text('Hello'));
        await pumpFrames(tester);

        expect(
          find.byKey(MessageContextOverlay.reactionBarKey),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'announcement readers stay read-only for compose but still keep reaction entry',
      (tester) async {
        final group = makeAnnouncementGroup(role: GroupRole.member);
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(makeMessage(id: 'msg-1', text: 'Hello'));

        await tester.pumpWidget(
          buildWidget(
            group: group,
            reactionRepo: FakeReactionRepository(),
            reactionReplayOutboxRepo: FakeGroupReactionReplayOutboxRepository(),
          ),
        );
        await pumpFrames(tester);

        expect(
          find.text('Only admins can send messages in this group'),
          findsOneWidget,
        );
        expect(find.byType(TextField), findsNothing);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.canWrite, isFalse);
        expect(screen.onQuoteReply, isNull);
        expect(screen.onReactionSelected, isNotNull);

        await tester.longPress(find.text('Hello'));
        await pumpFrames(tester);

        expect(find.byKey(MessageContextOverlay.overlayKey), findsOneWidget);
        expect(
          find.byKey(MessageContextOverlay.reactionBarKey),
          findsOneWidget,
        );
        expect(find.byKey(MessageContextOverlay.replyActionKey), findsNothing);
        expect(find.byKey(MessageContextOverlay.copyActionKey), findsOneWidget);
      },
    );

    testWidgets(
      'UP-003 composer enables only for an active member with current key',
      (tester) async {
        final group = makeChatGroup(role: GroupRole.member);
        await groupRepo.saveGroup(group);

        GroupMember selfMember(DateTime joinedAt) => GroupMember(
          groupId: group.id,
          peerId: testIdentity.peerId,
          username: testIdentity.username,
          role: MemberRole.writer,
          publicKey: testIdentity.publicKey,
          mlKemPublicKey: testIdentity.mlKemPublicKey,
          joinedAt: joinedAt,
        );

        await groupRepo.saveMember(selfMember(DateTime.utc(2026, 5, 13, 10)));
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: 'peer-bob',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-bob',
            joinedAt: DateTime.utc(2026, 5, 13, 10, 1),
          ),
        );
        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester, count: 20);

        expect(find.byType(TextField), findsOneWidget);
        var screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.canWrite, isTrue);
        final staleOnSend = screen.onSend as Future<void> Function(String);

        await groupRepo.removeMember(group.id, testIdentity.peerId);
        await staleOnSend('UP-003 stale removed send');
        await pumpFrames(tester, count: 5);

        expect(bridge.commandLog, isNot(contains('group:publish')));
        expect(
          (await msgRepo.getMessagesPage(
            group.id,
          )).where((message) => message.text == 'UP-003 stale removed send'),
          isEmpty,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await pumpFrames(tester, count: 2);
        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester, count: 20);

        expect(find.byType(TextField), findsNothing);
        expect(
          find.text(
            'You were removed from this group. You can still read past messages.',
          ),
          findsOneWidget,
        );

        await groupRepo.saveMember(selfMember(DateTime.utc(2026, 5, 13, 11)));
        await groupRepo.removeAllKeys(group.id);
        await tester.pumpWidget(const SizedBox.shrink());
        await pumpFrames(tester, count: 2);
        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester, count: 20);

        expect(find.byType(TextField), findsNothing);
        expect(
          find.text('Waiting for the current group key before you can send.'),
          findsOneWidget,
        );

        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: group.id,
            keyGeneration: 2,
            encryptedKey: 'test-group-key-2',
            createdAt: DateTime.utc(2026, 5, 13, 12),
          ),
        );
        await tester.pumpWidget(const SizedBox.shrink());
        await pumpFrames(tester, count: 2);
        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester, count: 20);

        expect(find.byType(TextField), findsOneWidget);
        screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.canWrite, isTrue);
      },
    );

    testWidgets(
      'B5 composer disappears on a LIVE sys-member_removed without re-entry',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester, count: 20);

        expect(find.byType(TextField), findsOneWidget);
        var screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.canWrite, isTrue);

        // Self is removed live. Another member (peer-bob) remains, so the
        // members.isEmpty fail-open does NOT mask the assertion. Keep the key so
        // the composer flips read-only purely because self is no longer active.
        await groupRepo.removeMember(group.id, testIdentity.peerId);
        messageStreamController.add(
          makeMessage(
            id: 'sys-member_removed:group-1:${testIdentity.peerId}:1',
            text: 'You were removed',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
          ),
        );
        await pumpFrames(tester, count: 20);

        expect(find.byType(TextField), findsNothing);
        expect(
          find.text(
            'You were removed from this group. You can still read past messages.',
          ),
          findsOneWidget,
        );
        screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.canWrite, isFalse);
      },
    );

    testWidgets(
      'B5 composer reappears on a LIVE sys-members_added(self) without re-entry',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        // Start as a retained read-only shell: self is NOT a member (removed),
        // but another member remains and the key is present.
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: 'peer-bob',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-peer-bob',
            mlKemPublicKey: 'mlkem-peer-bob',
            joinedAt: DateTime.utc(2026, 5, 1, 10, 1),
          ),
        );

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester, count: 20);

        expect(find.byType(TextField), findsNothing);

        // Self is re-added live (key already present from setUp).
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: testIdentity.peerId,
            username: testIdentity.username,
            role: MemberRole.writer,
            publicKey: testIdentity.publicKey,
            mlKemPublicKey: testIdentity.mlKemPublicKey,
            joinedAt: DateTime.utc(2026, 5, 1, 11),
          ),
        );
        messageStreamController.add(
          makeMessage(
            id: 'sys-members_added:group-1:${testIdentity.peerId}:1',
            text: 'You were added back',
            senderPeerId: 'peer-admin',
            senderUsername: 'Admin',
          ),
        );
        await pumpFrames(tester, count: 20);

        expect(find.byType(TextField), findsOneWidget);
        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.canWrite, isTrue);
      },
    );

    testWidgets(
      'B5 composer reappears after a re-add that lands while backgrounded, '
      'recomputed on resume',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        // Retained read-only shell: self absent, another member present.
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: 'peer-bob',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-peer-bob',
            mlKemPublicKey: 'mlkem-peer-bob',
            joinedAt: DateTime.utc(2026, 5, 1, 10, 1),
          ),
        );

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester, count: 20);
        expect(find.byType(TextField), findsNothing);

        // While backgrounded, a re-add restores membership + the current key
        // with NO sys row on this device's message stream (the key-update
        // path). Only a resume recompute can surface it without re-entry.
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: testIdentity.peerId,
            username: testIdentity.username,
            role: MemberRole.writer,
            publicKey: testIdentity.publicKey,
            mlKemPublicKey: testIdentity.mlKemPublicKey,
            joinedAt: DateTime.utc(2026, 5, 1, 11),
          ),
        );

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await pumpFrames(tester, count: 20);

        expect(find.byType(TextField), findsOneWidget);
        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.canWrite, isTrue);
      },
    );

    testWidgets(
      '144 terminal unauthorized send self-heals read-only on a live re-add (resume)',
      (tester) async {
        // A non-admin chat device with a STALE empty local membership: the send
        // diverges to unauthorized (uc sender_not_member) and latches the
        // composer read-only. Without a reset path this would stay read-only
        // until the user leaves and re-enters the screen.
        final group = makeChatGroup(role: GroupRole.member);
        await groupRepo.saveGroup(group);

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester, count: 20);

        await tester.enterText(find.byType(TextField), 'Stale unauthorized');
        await pumpFrames(tester);
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpFrames(tester, count: 20);

        var screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.canWrite, isFalse);
        expect(screen.failedTerminalReasonText, isNotNull);

        // A real re-add lands (membership restored incl self); a resume
        // recomputes capability and releases the latch IN PLACE.
        await saveActiveGroupMembers(groupRepo, group);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await pumpFrames(tester, count: 20);

        screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.canWrite, isTrue);
        expect(screen.failedTerminalReasonText, isNull);
        expect(find.byType(TextField), findsOneWidget);
        expect(
          find.byKey(const ValueKey('group-read-only-banner')),
          findsNothing,
        );
      },
    );

    testWidgets(
      '144 terminal text send_failed row stays Delete-only (no dead-end Retry) '
      'after a live re-add self-heals the composer',
      (tester) async {
        // A terminal text send persists a send_failed row with NO retry payload
        // (the use case returned terminal before any payload was created). After
        // the F1 self-heal re-enables the composer, that stuck row must NOT offer
        // a Retry that can only fail with missing_retry_payload — and Delete must
        // stay reachable so the user can clear it.
        final group = makeChatGroup(role: GroupRole.member);
        await groupRepo.saveGroup(group);

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester, count: 20);

        await tester.enterText(find.byType(TextField), 'Stale unauthorized');
        await pumpFrames(tester);
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpFrames(tester, count: 20);

        var screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.canWrite, isFalse);
        final stuckRow = screen.messages.firstWhere(
          (message) => message.text == 'Stale unauthorized',
        );
        expect(stuckRow.status, GroupMessage.statusSendFailed);

        // A real re-add + resume releases the read-only latch in place.
        await saveActiveGroupMembers(groupRepo, group);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await pumpFrames(tester, count: 20);

        screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.canWrite, isTrue);

        // RED on HEAD: the writable send_failed text row exposes a Retry that
        // cannot work, and loses Delete (failedTerminalReasonText went null).
        expect(
          find.byKey(ValueKey('failed-message-retry-${stuckRow.id}')),
          findsNothing,
        );
        expect(
          find.byKey(ValueKey('failed-message-delete-${stuckRow.id}')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'B5 self member_removed while viewing keeps the conversation open '
      'read-only in place (no pop) when the group row is retained',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        final removedStreamController = StreamController<String>.broadcast();
        addTearDown(removedStreamController.close);

        await tester.pumpWidget(
          buildWidget(
            group: group,
            removedStreamController: removedStreamController,
          ),
        );
        await pumpFrames(tester, count: 20);

        expect(find.byType(GroupConversationScreen), findsOneWidget);
        expect(find.byType(TextField), findsOneWidget);

        // Removed, but the group row is RETAINED (B3 read-only shell).
        await groupRepo.removeMember(group.id, testIdentity.peerId);
        removedStreamController.add(group.id);
        await pumpFrames(tester, count: 20);

        // Stays on the conversation (not ejected) and the composer flips
        // read-only in place — no re-entry required.
        expect(find.byType(GroupConversationScreen), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        expect(
          find.text(
            'You were removed from this group. You can still read past messages.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('removed member sees removed-banner copy on retained group', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      // A second member survives (saveActiveGroupMembers keeps peer-bob), so
      // members.isEmpty is false after removing self — the active-member gate
      // flips read-only instead of failing open.
      await saveActiveGroupMembers(groupRepo, group);
      final removedStreamController = StreamController<String>.broadcast();
      addTearDown(removedStreamController.close);

      await tester.pumpWidget(
        buildWidget(
          group: group,
          removedStreamController: removedStreamController,
        ),
      );
      await pumpFrames(tester, count: 20);

      expect(find.byType(GroupConversationScreen), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);

      // Passive self-removal with the group row RETAINED (B3 read-only shell).
      await groupRepo.removeMember(group.id, testIdentity.peerId);
      removedStreamController.add(group.id);
      await pumpFrames(tester, count: 20);

      // The durable composer read-only banner IS the single feedback surface…
      expect(find.byType(GroupConversationScreen), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(
        find.byKey(const ValueKey('group-read-only-banner')),
        findsOneWidget,
      );
      expect(
        find.text(
          'You were removed from this group. You can still read past messages.',
        ),
        findsOneWidget,
      );
      // …and the redundant transient toast is NOT shown (the discriminator).
      expect(find.text('You were removed from this group.'), findsNothing);
    });

    testWidgets(
      'dissolve-while-viewing flips the read-only banner with no snackbar',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester, count: 20);

        expect(find.byType(TextField), findsOneWidget);

        // Passive dissolve-while-viewing rides the message stream (no
        // removedStream, no snackbar): the dissolved row reloads via
        // _refreshVisibleGroup and the composer flips to the dissolved banner.
        await groupRepo.updateGroup(
          group.copyWith(
            isDissolved: true,
            dissolvedAt: DateTime.utc(2026, 6, 10, 12),
            dissolvedBy: 'peer-admin',
          ),
        );
        messageStreamController.add(
          makeMessage(
            id: 'sys-group_dissolved:group-1',
            text: 'Group dissolved',
          ),
        );
        await pumpFrames(tester, count: 20);

        expect(find.byType(TextField), findsNothing);
        expect(
          find.byKey(const ValueKey('group-read-only-banner')),
          findsOneWidget,
        );
        expect(
          find.text(
            'This group has been dissolved. History stays available, but new messages are disabled.',
          ),
          findsOneWidget,
        );
        // Dissolve is banner-only — never the removed toast.
        expect(find.text('You were removed from this group.'), findsNothing);
      },
    );

    testWidgets(
      'GCA-006 missing identity keeps composer read-only until late identity load',
      (tester) async {
        final group = makeChatGroup(role: GroupRole.member);
        await groupRepo.saveGroup(group);
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: testIdentity.peerId,
            username: testIdentity.username,
            role: MemberRole.writer,
            publicKey: testIdentity.publicKey,
            mlKemPublicKey: testIdentity.mlKemPublicKey,
            joinedAt: DateTime.utc(2026, 5, 14, 10),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: 'peer-bob',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-bob',
            joinedAt: DateTime.utc(2026, 5, 14, 10, 1),
          ),
        );
        final identityLoad = Completer<IdentityModel?>();
        identityRepo = FakeIdentityRepository(
          loadIdentityCompleter: identityLoad,
        );

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester, count: 5);

        var screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.canWrite, isFalse);
        expect(find.byType(TextField), findsNothing);
        expect(
          find.text('Waiting for your identity before you can send.'),
          findsOneWidget,
        );

        final staleOnSend = screen.onSend as Future<void> Function(String);
        await staleOnSend('GCA-006 missing identity send');
        await pumpFrames(tester, count: 5);

        expect(bridge.commandLog, isNot(contains('group:publish')));
        expect(
          (await msgRepo.getMessagesPage(group.id)).where(
            (message) => message.text == 'GCA-006 missing identity send',
          ),
          isEmpty,
        );

        identityLoad.complete(testIdentity);
        await pumpUntil(tester, () {
          final currentScreen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return currentScreen.canWrite &&
              currentScreen.ownPeerId == testIdentity.peerId;
        });

        screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.canWrite, isTrue);
        expect(find.byType(TextField), findsOneWidget);

        final lateOnSend = screen.onSend as Future<void> Function(String);
        await lateOnSend('GCA-006 late identity send');
        await pumpFrames(tester, count: 20);

        expect(bridge.commandLog, contains('group:publish'));
        final savedMessages = await msgRepo.getMessagesPage(group.id);
        final sentMessage = savedMessages.singleWhere(
          (message) => message.text == 'GCA-006 late identity send',
        );
        expect(sentMessage.senderPeerId, testIdentity.peerId);
        expect(sentMessage.senderUsername, testIdentity.username);
      },
    );

    testWidgets(
      'dissolved groups hide reaction entry even when reaction deps are wired',
      (tester) async {
        final group = makeChatGroup().copyWith(
          isDissolved: true,
          dissolvedAt: DateTime.utc(2026, 4, 5, 12, 0, 0),
          dissolvedBy: 'peer-admin',
        );
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(makeMessage(id: 'msg-1', text: 'Hello'));

        await tester.pumpWidget(
          buildWidget(
            group: group,
            reactionRepo: FakeReactionRepository(),
            reactionReplayOutboxRepo: FakeGroupReactionReplayOutboxRepository(),
          ),
        );
        await pumpFrames(tester);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.onReactionSelected, isNull);

        await tester.longPress(find.text('Hello'));
        await pumpFrames(tester);

        expect(find.byKey(MessageContextOverlay.overlayKey), findsOneWidget);
        expect(find.byKey(MessageContextOverlay.reactionBarKey), findsNothing);
        expect(find.byKey(MessageContextOverlay.copyActionKey), findsOneWidget);
      },
    );

    testWidgets(
      'stale reaction entry restores local state when the group dissolves before publish',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(makeMessage(id: 'msg-1', text: 'Hello'));
        final reactionRepo = FakeReactionRepository();
        final reactionReplayOutboxRepo =
            FakeGroupReactionReplayOutboxRepository();

        await tester.pumpWidget(
          buildWidget(
            group: group,
            reactionRepo: reactionRepo,
            reactionReplayOutboxRepo: reactionReplayOutboxRepo,
          ),
        );
        await pumpFrames(tester);

        await groupRepo.updateGroup(
          group.copyWith(
            isDissolved: true,
            dissolvedAt: DateTime.utc(2026, 4, 22, 12),
            dissolvedBy: 'peer-admin',
          ),
        );

        await tester.longPress(find.text('Hello'));
        await pumpFrames(tester);

        final thumbsUp = find.descendant(
          of: find.byKey(MessageContextOverlay.reactionBarKey),
          matching: find.text('\u{1F44D}'),
        );
        expect(thumbsUp, findsOneWidget);

        await tester.tap(thumbsUp);
        await pumpFrames(tester, count: 20);

        expect(await reactionRepo.getReactionsForMessage('msg-1'), isEmpty);
        // 144 INV-5: terminal feedback is the durable read-only banner, not a
        // transient snackbar.
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('group-read-only-banner')),
            matching: find.text(
              'This group has been dissolved. History stays available, but '
              'new messages are disabled.',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(SnackBar, 'This group has been dissolved'),
          findsNothing,
        );

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.canWrite, isFalse);
        // Lock the dissolved OVERRIDE specifically (not just the refreshed
        // dissolved-group state, which would force canWrite false on its own):
        // the per-message reason is driven ONLY by _terminalSendReadOnly, so
        // deleting the reaction-dissolve override re-reds this.
        expect(
          screen.failedTerminalReasonText,
          "Couldn't send — this group was dissolved",
        );
        expect(screen.onReactionSelected, isNull);
        expect(find.byType(TextField), findsNothing);
        expect(find.text('\u{1F44D}'), findsNothing);
      },
    );

    testWidgets(
      'reaction terminal result reverts reaction and flips read-only banner '
      'without a bubble',
      (tester) async {
        // notMember (no members saved) is the reaction analog of the text-send
        // "unauthorized" terminal result. On HEAD this silently reverts and
        // leaves the composer writable (no banner) — the RED.
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(makeMessage(id: 'msg-1', text: 'Hello'));
        final reactionRepo = FakeReactionRepository();
        final reactionReplayOutboxRepo =
            FakeGroupReactionReplayOutboxRepository();

        await tester.pumpWidget(
          buildWidget(
            group: group,
            reactionRepo: reactionRepo,
            reactionReplayOutboxRepo: reactionReplayOutboxRepo,
          ),
        );
        await pumpFrames(tester);

        await tester.longPress(find.text('Hello'));
        await pumpFrames(tester);

        final thumbsUp = find.descendant(
          of: find.byKey(MessageContextOverlay.reactionBarKey),
          matching: find.text('\u{1F44D}'),
        );
        expect(thumbsUp, findsOneWidget);

        await tester.tap(thumbsUp);
        await pumpFrames(tester, count: 20);

        expect(await reactionRepo.getReactionsForMessage('msg-1'), isEmpty);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        // No fabricated failed-reaction message bubble.
        expect(screen.messages.where((m) => m.id != 'msg-1'), isEmpty);
        // Optimistic emoji reverted.
        expect(find.text('\u{1F44D}'), findsNothing);
        // Banner flips with the removed reason; no dissolved snackbar.
        expect(screen.canWrite, isFalse);
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('group-read-only-banner')),
            matching: find.text(
              'You were removed from this group. You can still read past '
              'messages.',
            ),
          ),
          findsOneWidget,
        );
        expect(
          find.widgetWithText(SnackBar, 'This group has been dissolved'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'reaction REMOVE terminal result flips read-only banner (parity with add)',
      (tester) async {
        // Toggling OFF an existing own reaction in a group we are no longer a
        // member of must flip read-only too (remove-direction parity, INV-3).
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(makeMessage(id: 'msg-1', text: 'Hello'));
        final reactionRepo = FakeReactionRepository();
        final reactionReplayOutboxRepo =
            FakeGroupReactionReplayOutboxRepository();
        // Pre-existing OWN reaction so the next toggle is a REMOVE.
        await reactionRepo.saveReaction(
          MessageReaction(
            id: 'r1',
            messageId: 'msg-1',
            emoji: '\u{1F44D}',
            senderPeerId: testIdentity.peerId,
            timestamp: '2026-01-15T12:00:00.000Z',
            createdAt: '2026-01-15T12:00:00.000Z',
          ),
        );

        await tester.pumpWidget(
          buildWidget(
            group: group,
            reactionRepo: reactionRepo,
            reactionReplayOutboxRepo: reactionReplayOutboxRepo,
          ),
        );
        await pumpUntil(tester, () {
          final s = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return s.onReactionSelected != null &&
              (s.reactions['msg-1'] ?? const []).isNotEmpty;
        });

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        // Toggle the own reaction OFF → removeGroupReaction → notMember.
        screen.onReactionSelected!('msg-1', '\u{1F44D}');
        await pumpFrames(tester, count: 20);

        final after = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(after.canWrite, isFalse);
        expect(
          after.failedTerminalReasonText,
          "Couldn't send — you're no longer in this group",
        );
        expect(
          find.descendant(
            of: find.byKey(const ValueKey('group-read-only-banner')),
            matching: find.text(
              'You were removed from this group. You can still read past '
              'messages.',
            ),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      '144 a terminal reaction result disables further reaction entry '
      '(read-only banner and reactions stay consistent)',
      (tester) async {
        // First reaction latches the composer read-only (notMember terminal).
        // The long-press reaction picker must then be disabled too, so the user
        // cannot keep firing reactions that only revert.
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(makeMessage(id: 'msg-1', text: 'Hello'));
        final reactionRepo = FakeReactionRepository();
        final reactionReplayOutboxRepo =
            FakeGroupReactionReplayOutboxRepository();

        await tester.pumpWidget(
          buildWidget(
            group: group,
            reactionRepo: reactionRepo,
            reactionReplayOutboxRepo: reactionReplayOutboxRepo,
          ),
        );
        await pumpUntil(tester, () {
          final s = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return s.onReactionSelected != null;
        });

        final before = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        // The first reaction is allowed (latch starts at none).
        before.onReactionSelected!('msg-1', '\u{1F44D}');
        await pumpFrames(tester, count: 20);

        final after = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(after.canWrite, isFalse);
        expect(
          after.failedTerminalReasonText,
          "Couldn't send — you're no longer in this group",
        );
        // RED on HEAD: _canMutateReactions ignores the terminal latch, so the
        // reaction entry stays wired even though the banner is read-only.
        expect(after.onReactionSelected, isNull);
      },
    );

    testWidgets(
      'optimistic reaction add rolls back when the target message is gone',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        await msgRepo.saveMessage(makeMessage(id: 'msg-1', text: 'Hello'));
        final reactionRepo = FakeReactionRepository();
        final reactionReplayOutboxRepo =
            FakeGroupReactionReplayOutboxRepository();

        await tester.pumpWidget(
          buildWidget(
            group: group,
            reactionRepo: reactionRepo,
            reactionReplayOutboxRepo: reactionReplayOutboxRepo,
          ),
        );
        await pumpFrames(tester);

        await msgRepo.deleteMessage('msg-1');
        await tester.longPress(find.text('Hello'));
        await pumpFrames(tester);

        final thumbsUp = find.descendant(
          of: find.byKey(MessageContextOverlay.reactionBarKey),
          matching: find.text('\u{1F44D}'),
        );
        await tester.tap(thumbsUp);
        await pumpFrames(tester, count: 20);

        expect(await reactionRepo.getReactionsForMessage('msg-1'), isEmpty);
        expect(find.text('\u{1F44D}'), findsNothing);
      },
    );

    testWidgets(
      'INV-R1 optimistic reaction add is KEPT when publish fails (queuedForRetry)',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        await msgRepo.saveMessage(makeMessage(id: 'msg-1', text: 'Hello'));
        final reactionRepo = FakeReactionRepository();
        final reactionReplayOutboxRepo =
            FakeGroupReactionReplayOutboxRepository();

        // Force the live publish to fail → use case returns queuedForRetry.
        bridge.responses['group:publishReaction'] = {
          'ok': false,
          'errorCode': 'GROUP_ERROR',
        };

        await tester.pumpWidget(
          buildWidget(
            group: group,
            reactionRepo: reactionRepo,
            reactionReplayOutboxRepo: reactionReplayOutboxRepo,
          ),
        );
        await pumpFrames(tester);

        await tester.longPress(find.text('Hello'));
        await pumpFrames(tester);

        final thumbsUp = find.descendant(
          of: find.byKey(MessageContextOverlay.reactionBarKey),
          matching: find.text('\u{1F44D}'),
        );
        await tester.tap(thumbsUp);
        await pumpFrames(tester, count: 20);

        // Emoji is kept (NOT reverted), and the reaction is durably persisted.
        expect(find.text('\u{1F44D}'), findsOneWidget);
        expect(
          await reactionRepo.getReactionsForMessage('msg-1'),
          hasLength(1),
        );
      },
    );

    testWidgets(
      'INV-R1 optimistic reaction remove is KEPT when publish fails (queuedForRetry)',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        await msgRepo.saveMessage(makeMessage(id: 'msg-1', text: 'Hello'));
        final reactionRepo = FakeReactionRepository();
        await reactionRepo.saveReaction(
          MessageReaction(
            id: 'rxn-self',
            messageId: 'msg-1',
            emoji: '\u{1F44D}',
            senderPeerId: testIdentity.peerId,
            timestamp: DateTime.now().toUtc().toIso8601String(),
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );
        final reactionReplayOutboxRepo =
            FakeGroupReactionReplayOutboxRepository();

        bridge.responses['group:publishReaction'] = {
          'ok': false,
          'errorCode': 'GROUP_ERROR',
        };

        await tester.pumpWidget(
          buildWidget(
            group: group,
            reactionRepo: reactionRepo,
            reactionReplayOutboxRepo: reactionReplayOutboxRepo,
          ),
        );
        await pumpFrames(tester);

        await tester.longPress(find.text('Hello'));
        await pumpFrames(tester);

        // Tapping the already-present emoji toggles it off (remove).
        final thumbsUp = find.descendant(
          of: find.byKey(MessageContextOverlay.reactionBarKey),
          matching: find.text('\u{1F44D}'),
        );
        await tester.tap(thumbsUp);
        await pumpFrames(tester, count: 20);

        // Optimistic removal is kept (NOT restored) even though publish failed.
        expect(await reactionRepo.getReactionsForMessage('msg-1'), isEmpty);
      },
    );

    testWidgets('optimistic reaction remove rolls back on non-success result', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      await saveActiveGroupMembers(groupRepo, group);
      await msgRepo.saveMessage(makeMessage(id: 'msg-1', text: 'Hello'));
      final reactionRepo = FakeReactionRepository();
      await reactionRepo.saveReaction(
        MessageReaction(
          id: 'rxn-self',
          messageId: 'msg-1',
          emoji: '\u{1F44D}',
          senderPeerId: testIdentity.peerId,
          timestamp: DateTime.now().toUtc().toIso8601String(),
          createdAt: DateTime.now().toUtc().toIso8601String(),
        ),
      );
      final reactionReplayOutboxRepo =
          FakeGroupReactionReplayOutboxRepository();

      await tester.pumpWidget(
        buildWidget(
          group: group,
          reactionRepo: reactionRepo,
          reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        ),
      );
      await pumpFrames(tester);
      await groupRepo.removeMember(group.id, testIdentity.peerId);

      await tester.longPress(find.text('Hello'));
      await pumpFrames(tester);

      final thumbsUp = find.descendant(
        of: find.byKey(MessageContextOverlay.reactionBarKey),
        matching: find.text('\u{1F44D}'),
      );
      await tester.tap(thumbsUp);
      await pumpFrames(tester, count: 20);

      expect(await reactionRepo.getReactionsForMessage('msg-1'), hasLength(1));
      expect(find.text('\u{1F44D}'), findsOneWidget);
    });

    testWidgets('optimistic reaction add rolls back when persistence throws', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      await saveActiveGroupMembers(groupRepo, group);
      await msgRepo.saveMessage(makeMessage(id: 'msg-1', text: 'Hello'));
      final reactionRepo = ThrowingSaveReactionRepository();
      final reactionReplayOutboxRepo =
          FakeGroupReactionReplayOutboxRepository();

      await tester.pumpWidget(
        buildWidget(
          group: group,
          reactionRepo: reactionRepo,
          reactionReplayOutboxRepo: reactionReplayOutboxRepo,
        ),
      );
      await pumpFrames(tester);

      await tester.longPress(find.text('Hello'));
      await pumpFrames(tester);

      final thumbsUp = find.descendant(
        of: find.byKey(MessageContextOverlay.reactionBarKey),
        matching: find.text('\u{1F44D}'),
      );
      await tester.tap(thumbsUp);
      await pumpFrames(tester, count: 20);

      expect(find.text('\u{1F44D}'), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
      'non-admin in announcement group still has no voice stop/cancel callbacks when durable voice deps are enabled',
      (tester) async {
        final group = makeAnnouncementGroup(role: GroupRole.member);
        await groupRepo.saveGroup(group);

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: FakeMediaFileManager(),
            audioRecorderService: FakeAudioRecorderService(),
          ),
        );
        await pumpFrames(tester);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.onRecordStart, isNull);
        expect(screen.onRecordStop, isNull);
        expect(screen.onRecordCancel, isNull);
      },
    );

    testWidgets(
      'read-only announcement members cannot keep hidden quote state',
      (tester) async {
        final writableGroup = makeAnnouncementGroup(role: GroupRole.admin);
        await groupRepo.saveGroup(writableGroup);
        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-parent',
            text: 'Incoming announcement',
            groupId: writableGroup.id,
            isIncoming: true,
          ),
        );

        await tester.pumpWidget(buildWidget(group: writableGroup));
        await pumpFrames(tester, count: 20);

        var screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.onQuoteReply, isNotNull);

        screen.onQuoteReply!.call('msg-parent');
        await tester.pump();
        expect(find.text('Incoming announcement'), findsWidgets);

        final readOnlyGroup = makeAnnouncementGroup(role: GroupRole.member);
        await groupRepo.saveGroup(readOnlyGroup);

        await tester.pumpWidget(buildWidget(group: readOnlyGroup));
        await pumpFrames(tester, count: 20);

        screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.onQuoteReply, isNull);
        expect(find.byType(SwipeToQuoteBubble), findsNothing);
        expect(find.byType(TextField), findsNothing);

        await tester.pumpWidget(buildWidget(group: writableGroup));
        await pumpFrames(tester, count: 20);

        expect(find.text('Incoming announcement'), findsOneWidget);
        expect(find.text('Replying to'), findsNothing);
      },
    );

    testWidgets(
      'stale writer callbacks cannot bypass read-only announcement mode',
      (tester) async {
        final writableGroup = makeAnnouncementGroup(role: GroupRole.admin);
        await groupRepo.saveGroup(writableGroup);

        final recorder = FakeAudioRecorderService()..fakeDurationMs = 200;
        final mediaFileManager = FakeMediaFileManager();

        await tester.pumpWidget(
          buildWidget(
            group: writableGroup,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            audioRecorderService: recorder,
          ),
        );
        await pumpFrames(tester, count: 20);

        final writableScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final staleOnSend =
            writableScreen.onSend as Future<void> Function(String);
        final staleOnAttach = writableScreen.onAttach!;
        final staleOnRecordStart =
            writableScreen.onRecordStart! as Future<void> Function();
        final staleOnRecordStop =
            writableScreen.onRecordStop! as Future<void> Function();

        await staleOnRecordStart();
        await pumpUntil(
          tester,
          () => find.byIcon(Icons.stop_rounded).evaluate().isNotEmpty,
        );

        final readOnlyGroup = makeAnnouncementGroup(role: GroupRole.member);
        await groupRepo.saveGroup(readOnlyGroup);

        await tester.pumpWidget(
          buildWidget(
            group: readOnlyGroup,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            audioRecorderService: recorder,
          ),
        );
        await pumpFrames(tester, count: 20);

        staleOnAttach();
        await tester.pump(const Duration(milliseconds: 300));
        await staleOnRecordStop();
        await pumpFrames(tester, count: 5);
        await staleOnSend('should-never-send');
        await pumpFrames(tester, count: 20);

        expect(find.text('Media Library'), findsNothing);
        expect(find.byIcon(Icons.stop_rounded), findsNothing);
        expect(recorder.startCallCount, 1);
        expect(recorder.stopCallCount, 0);
        expect(bridge.commandLog, isNot(contains('bg:begin')));
        expect(bridge.commandLog, isNot(contains('group:publish')));
        expect(bridge.commandLog, isNot(contains('group:inboxStore')));

        final savedMessages = await msgRepo.getMessagesPage(readOnlyGroup.id);
        expect(
          savedMessages.where((message) => message.text == 'should-never-send'),
          isEmpty,
        );
      },
    );

    testWidgets('ML-017 retained removed-member history opens read-only', (
      tester,
    ) async {
      final group = makeChatGroup(role: GroupRole.member);
      await groupRepo.saveGroup(group);
      await groupRepo.saveMember(
        GroupMember(
          groupId: group.id,
          peerId: 'peer-bob',
          username: 'Bob',
          role: MemberRole.writer,
          publicKey: 'pk-bob',
          joinedAt: DateTime.now().toUtc(),
        ),
      );
      await msgRepo.saveMessage(
        makeMessage(id: 'ml017-old-history', text: 'ML-017 old history'),
      );

      await tester.pumpWidget(
        buildWidget(
          group: group,
          reactionRepo: FakeReactionRepository(),
          reactionReplayOutboxRepo: FakeGroupReactionReplayOutboxRepository(),
        ),
      );
      await pumpFrames(tester);

      expect(find.text('ML-017 old history'), findsOneWidget);
      expect(
        find.text(
          'You were removed from this group. You can still read past messages.',
        ),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);

      final screen = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      expect(screen.canWrite, isFalse);
      expect(screen.onQuoteReply, isNull);
      expect(screen.onReactionSelected, isNull);
    });

    testWidgets('sets tracker active on init', (tester) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      final tracker = ActiveConversationTracker();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GroupConversationWired(
            group: group,
            groupRepo: groupRepo,
            msgRepo: msgRepo,
            groupMessageListener: FakeGroupMessageListener(
              messageStreamController.stream,
            ),
            bridge: bridge,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            p2pService: p2pService,
            groupConversationTracker: tracker,
          ),
        ),
      );
      await pumpFrames(tester);

      expect(tracker.isViewing('group:${group.id}'), isTrue);
    });

    testWidgets(
      'reused group conversation widget clears stale messages media and reactions when group id changes',
      (tester) async {
        final groupA = makeChatGroup();
        final groupB = makeChatGroup().copyWith(
          id: 'group-2',
          name: 'Second Group',
          topicName: 'topic-2',
        );
        await groupRepo.saveGroup(groupA);
        await groupRepo.saveGroup(groupB);
        await msgRepo.saveMessage(
          makeMessage(id: 'msg-group-a', text: 'Group A only'),
        );
        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-group-b',
            text: 'Group B only',
            groupId: groupB.id,
          ),
        );
        final reactionRepo = FakeReactionRepository();
        await reactionRepo.saveReaction(
          MessageReaction(
            id: 'rxn-group-a',
            messageId: 'msg-group-a',
            emoji: '\u{1F44D}',
            senderPeerId: 'peer-alice',
            timestamp: DateTime.now().toUtc().toIso8601String(),
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );
        await mediaAttachmentRepo.saveAttachment(
          MediaAttachment(
            id: 'media-group-a',
            messageId: 'msg-group-a',
            mime: 'image/png',
            size: 1,
            mediaType: 'image',
            localPath: 'pending_uploads/msg-group-a/media.png',
            downloadStatus: kMediaDownloadStatusDone,
            contentHash: _validContentHash,
            encryptionKeyBase64: 'key-fixture',
            encryptionNonce: 'nonce-fixture',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
          owner: MediaOwnerLane.group,
        );

        await tester.pumpWidget(
          buildWidget(
            group: groupA,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: FakeMediaFileManager(),
            reactionRepo: reactionRepo,
          ),
        );
        await pumpFrames(tester, count: 20);
        expect(find.text('Group A only'), findsOneWidget);
        expect(find.text('\u{1F44D}'), findsOneWidget);

        await tester.pumpWidget(
          buildWidget(
            group: groupB,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: FakeMediaFileManager(),
            reactionRepo: reactionRepo,
          ),
        );
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.messages.map((message) => message.id), ['msg-group-b']);
        expect(screen.mediaMap.containsKey('msg-group-a'), isFalse);
        expect(screen.reactions.containsKey('msg-group-a'), isFalse);
        expect(find.text('Group A only'), findsNothing);
        expect(find.text('Group B only'), findsOneWidget);
        expect(find.text('\u{1F44D}'), findsNothing);
      },
    );

    testWidgets(
      'old-group reaction after retarget is ignored while a new-group reaction applies',
      (tester) async {
        final groupA = makeChatGroup();
        final groupB = makeChatGroup().copyWith(
          id: 'group-2',
          name: 'Second Group',
          topicName: 'topic-2',
        );
        await groupRepo.saveGroup(groupA);
        await groupRepo.saveGroup(groupB);
        await msgRepo.saveMessage(
          makeMessage(id: 'msg-group-a-reaction', text: 'Group A reaction'),
        );
        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-group-b-reaction',
            text: 'Group B reaction',
            groupId: groupB.id,
          ),
        );
        final reactionRepo = FakeReactionRepository();
        final reactionStreamController =
            StreamController<ReactionChange>.broadcast();
        addTearDown(reactionStreamController.close);

        await tester.pumpWidget(
          buildWidget(
            group: groupA,
            reactionRepo: reactionRepo,
            reactionStreamController: reactionStreamController,
          ),
        );
        await pumpFrames(tester, count: 20);
        expect(find.text('Group A reaction'), findsOneWidget);

        await tester.pumpWidget(
          buildWidget(
            group: groupB,
            reactionRepo: reactionRepo,
            reactionStreamController: reactionStreamController,
          ),
        );
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen.group.id == groupB.id &&
              screen.messages.any(
                (message) => message.id == 'msg-group-b-reaction',
              );
        });

        reactionStreamController.add(
          ReactionChange.upsert(
            MessageReaction(
              id: 'rxn-late-group-a',
              messageId: 'msg-group-a-reaction',
              emoji: '\u{1F44D}',
              senderPeerId: 'peer-old',
              timestamp: DateTime.now().toUtc().toIso8601String(),
              createdAt: DateTime.now().toUtc().toIso8601String(),
            ),
          ),
        );
        await pumpFrames(tester);

        var screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.group.id, groupB.id);
        expect(screen.reactions.containsKey('msg-group-a-reaction'), isFalse);
        expect(find.text('\u{1F44D}'), findsNothing);

        reactionStreamController.add(
          ReactionChange.upsert(
            MessageReaction(
              id: 'rxn-current-group-b',
              messageId: 'msg-group-b-reaction',
              emoji: '\u{2764}\u{FE0F}',
              senderPeerId: 'peer-new',
              timestamp: DateTime.now().toUtc().toIso8601String(),
              createdAt: DateTime.now().toUtc().toIso8601String(),
            ),
          ),
        );
        await pumpFrames(tester);

        screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.reactions.containsKey('msg-group-a-reaction'), isFalse);
        expect(
          screen.reactions['msg-group-b-reaction']?.single.emoji,
          '\u{2764}\u{FE0F}',
        );
        expect(find.text('\u{2764}\u{FE0F}'), findsOneWidget);
      },
    );

    testWidgets(
      'in-flight old-group listener hydration cannot mutate a reused conversation widget',
      (tester) async {
        final groupA = makeChatGroup();
        final groupB = makeChatGroup().copyWith(
          id: 'group-2',
          name: 'Second Group',
          topicName: 'topic-2',
        );
        await groupRepo.saveGroup(groupA);
        await groupRepo.saveGroup(groupB);
        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-group-b-stable',
            text: 'Group B stable',
            groupId: groupB.id,
          ),
        );
        final gatedMedia = GateFirstSingleMediaReadRepository();

        await tester.pumpWidget(
          buildWidget(group: groupA, mediaRepo: gatedMedia),
        );
        await pumpFrames(tester, count: 20);

        const oldAttachment = MediaAttachment(
          id: 'old-group-held-media',
          messageId: 'old-group-held-message',
          mime: 'image/png',
          size: 1,
          mediaType: 'image',
          localPath: 'media/group-1/held.png',
          downloadStatus: kMediaDownloadStatusDone,
          contentHash: _validContentHash,
          encryptionKeyBase64: 'key-fixture',
          encryptionNonce: 'nonce-fixture',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          createdAt: '2026-07-11T10:00:00.000Z',
        );
        await gatedMedia.saveAttachment(
          oldAttachment,
          owner: MediaOwnerLane.group,
        );
        final oldMessage = makeMessage(
          id: 'old-group-held-message',
          text: 'Old group held update',
          groupId: groupA.id,
          media: const [oldAttachment],
        );
        await msgRepo.saveMessage(oldMessage);
        gatedMedia.armed = true;
        messageStreamController.add(oldMessage);
        await pumpUntil(tester, () => gatedMedia.firstReadCaptured.isCompleted);
        expect(gatedMedia.firstReadCaptured.isCompleted, isTrue);

        await tester.pumpWidget(
          buildWidget(group: groupB, mediaRepo: gatedMedia),
        );
        await pumpFrames(tester, count: 10);
        gatedMedia.releaseFirstRead.complete();
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.messages.map((message) => message.id), [
          'msg-group-b-stable',
        ]);
        expect(screen.mediaMap.containsKey('old-group-held-message'), isFalse);
        expect(find.text('Old group held update'), findsNothing);
        expect(find.text('Group B stable'), findsOneWidget);
      },
    );

    testWidgets(
      'read marking requires foreground lifecycle and matching active group key',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(
          makeMessage(id: 'msg-unread', text: 'Unread while hidden'),
        );
        final tracker = ActiveConversationTracker();

        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        addTearDown(() {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
        });

        await tester.pumpWidget(
          buildWidget(group: group, groupConversationTracker: tracker),
        );
        await pumpFrames(tester, count: 20);

        expect(msgRepo.markAsReadCalls, 0);
        expect(await msgRepo.getUnreadCount(group.id), 1);

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await pumpFrames(tester, count: 10);
        final callsAfterResume = msgRepo.markAsReadCalls;
        expect(callsAfterResume, greaterThanOrEqualTo(1));

        tracker.setActive('group:other');
        final streamed = makeMessage(
          id: 'msg-active-mismatch',
          text: 'Active mismatch',
          groupId: group.id,
        );
        await msgRepo.saveMessage(streamed);
        messageStreamController.add(streamed);
        await pumpFrames(tester, count: 20);

        expect(msgRepo.markAsReadCalls, callsAfterResume);
      },
    );

    testWidgets('clears tracker on dispose', (tester) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      final tracker = ActiveConversationTracker();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GroupConversationWired(
            group: group,
            groupRepo: groupRepo,
            msgRepo: msgRepo,
            groupMessageListener: FakeGroupMessageListener(
              messageStreamController.stream,
            ),
            bridge: bridge,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            p2pService: p2pService,
            groupConversationTracker: tracker,
          ),
        ),
      );
      await pumpFrames(tester);

      expect(tracker.isViewing('group:${group.id}'), isTrue);

      // Replace the widget to trigger dispose
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await pumpFrames(tester);

      expect(tracker.isViewing('group:${group.id}'), isFalse);
    });

    testWidgets('old group dispose does not clear newer active group key', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      final tracker = ActiveConversationTracker();

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: GroupConversationWired(
            group: group,
            groupRepo: groupRepo,
            msgRepo: msgRepo,
            groupMessageListener: FakeGroupMessageListener(
              messageStreamController.stream,
            ),
            bridge: bridge,
            identityRepo: identityRepo,
            contactRepo: contactRepo,
            p2pService: p2pService,
            groupConversationTracker: tracker,
          ),
        ),
      );
      await pumpFrames(tester);

      tracker.setActive('group:newer-group');

      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await pumpFrames(tester);

      expect(tracker.isViewing('group:newer-group'), isTrue);
    });

    testWidgets(
      'current group removal shows a notice and exits the conversation route',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        final tracker = ActiveConversationTracker();
        final removedStreamController = StreamController<String>.broadcast();
        addTearDown(removedStreamController.close);

        await tester.pumpWidget(
          MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => GroupConversationWired(
                          group: group,
                          groupRepo: groupRepo,
                          msgRepo: msgRepo,
                          groupMessageListener: FakeGroupMessageListener(
                            messageStreamController.stream,
                            removedStream: removedStreamController.stream,
                          ),
                          bridge: bridge,
                          identityRepo: identityRepo,
                          contactRepo: contactRepo,
                          p2pService: p2pService,
                          groupConversationTracker: tracker,
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Group Conversation'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('Open Group Conversation'));
        await pumpFrames(tester, count: 20);

        expect(find.byType(GroupConversationScreen), findsOneWidget);
        expect(tracker.isViewing('group:${group.id}'), isTrue);

        // True hard-delete (group row gone) — the only case that still pops the
        // conversation route. A RETAINED removal stays in place read-only (B5).
        await groupRepo.deleteGroup(group.id);
        removedStreamController.add(group.id);
        await pumpFrames(tester, count: 20);

        expect(find.byType(GroupConversationScreen), findsNothing);
        expect(find.text('Open Group Conversation'), findsOneWidget);
        expect(find.text('You were removed from this group.'), findsOneWidget);
        expect(tracker.isViewing('group:${group.id}'), isFalse);
      },
    );

    testWidgets('old group removal does not clear newer active group key', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      final tracker = ActiveConversationTracker();
      final removedStreamController = StreamController<String>.broadcast();
      addTearDown(removedStreamController.close);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => GroupConversationWired(
                        group: group,
                        groupRepo: groupRepo,
                        msgRepo: msgRepo,
                        groupMessageListener: FakeGroupMessageListener(
                          messageStreamController.stream,
                          removedStream: removedStreamController.stream,
                        ),
                        bridge: bridge,
                        identityRepo: identityRepo,
                        contactRepo: contactRepo,
                        p2pService: p2pService,
                        groupConversationTracker: tracker,
                      ),
                    ),
                  );
                },
                child: const Text('Open Group Conversation'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Group Conversation'));
      await pumpFrames(tester, count: 20);

      expect(find.byType(GroupConversationScreen), findsOneWidget);
      tracker.setActive('group:newer-group');

      removedStreamController.add(group.id);
      await pumpFrames(tester, count: 20);

      // The group row is RETAINED (B5), so the conversation stays in place
      // read-only — it must NOT pop. Crucially, a newer group's active-tracking
      // is left untouched.
      expect(find.byType(GroupConversationScreen), findsOneWidget);
      expect(tracker.isViewing('group:newer-group'), isTrue);
    });

    testWidgets('accepts empty initialAttachments without error', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

      await tester.pumpWidget(
        buildWidget(
          group: group,
          mediaRepo: CountingMediaAttachmentRepository(),
          initialAttachments: [],
        ),
      );
      await pumpFrames(tester);

      expect(find.byType(GroupConversationWired), findsOneWidget);
      // No AttachmentPreviewStrip when list is empty
      expect(find.byType(AttachmentPreviewStrip), findsNothing);
    });

    testWidgets(
      'gallery multi-video batches keep one processing tile with honest batch context',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        final tempDir = Directory.systemTemp.createTempSync(
          'group_gallery_batch_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final firstVideo = File('${tempDir.path}/video-1.mp4')
          ..writeAsBytesSync(_tinyPngBytes);
        final stillImage = File('${tempDir.path}/image-1.jpg')
          ..writeAsBytesSync(_tinyPngBytes);
        final secondVideo = File('${tempDir.path}/video-2.mp4')
          ..writeAsBytesSync(_tinyPngBytes);
        final processedFirstVideo = File('${tempDir.path}/processed-1.mp4')
          ..writeAsBytesSync(_tinyPngBytes);
        final processedImage = File('${tempDir.path}/processed-1.jpg')
          ..writeAsBytesSync(_tinyPngBytes);
        final processedSecondVideo = File('${tempDir.path}/processed-2.mp4')
          ..writeAsBytesSync(_tinyPngBytes);

        final mediaPicker = FakeMediaPicker()
          ..multipleMediaResult = [
            XFile(firstVideo.path),
            XFile(stillImage.path),
            XFile(secondVideo.path),
          ];
        final videoResults = [
          Completer<VideoProcessResult>(),
          Completer<VideoProcessResult>(),
        ];
        final imageResult = Completer<XFile?>();
        var imageCompressionStarted = false;
        final progressCallbacks = <void Function(double)?>[];
        var videoCallCount = 0;
        final imageProcessor = ImageProcessor(
          compressFile:
              ({
                required path,
                required quality,
                required keepExif,
                minWidth = 1920,
                minHeight = 1080,
              }) async {
                if (path == stillImage.path) {
                  imageCompressionStarted = true;
                  return imageResult.future;
                }
                return null;
              },
          compressVideo:
              ({
                required path,
                required compress,
                void Function(double progress)? onProgress,
              }) async {
                progressCallbacks.add(onProgress);
                final result = videoResults[videoCallCount];
                videoCallCount++;
                return result.future;
              },
        );

        tester.view.physicalSize = const Size(800, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            imageProcessor: imageProcessor,
            mediaPicker: mediaPicker,
          ),
        );
        await pumpFrames(tester, count: 20);

        await tester.tap(find.byIcon(Icons.add_rounded));
        await tester.pump(const Duration(milliseconds: 500));
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Media Library'))
            .onTap!();
        await pumpUntil(tester, () => progressCallbacks.length == 1);

        progressCallbacks.single!(35);
        await tester.pump();

        expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
        expect(find.text('Processing (1/2)'), findsOneWidget);
        expect(find.text('35%'), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);

        videoResults[0].complete(
          VideoProcessResult(path: processedFirstVideo.path),
        );
        await pumpUntil(tester, () => imageCompressionStarted);
        await tester.pump();

        expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
        expect(find.text('Processing (1/2)'), findsOneWidget);

        imageResult.complete(XFile(processedImage.path));
        await pumpUntil(tester, () => progressCallbacks.length == 2);

        progressCallbacks.last!(60);
        await tester.pump();

        expect(find.text('Processing (2/2)'), findsOneWidget);
        expect(find.text('60%'), findsOneWidget);

        videoResults[1].complete(
          VideoProcessResult(path: processedSecondVideo.path),
        );
        await tester.pump();
      },
    );

    testWidgets('recorded single video keeps single-item processing copy', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

      final tempDir = Directory.systemTemp.createTempSync(
        'group_camera_video_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final cameraVideo = File('${tempDir.path}/camera-video.mp4')
        ..writeAsBytesSync(_tinyPngBytes);
      final processedVideo = File('${tempDir.path}/camera-video-out.mp4')
        ..writeAsBytesSync(_tinyPngBytes);

      final mediaPicker = FakeMediaPicker()
        ..videoResult = XFile(cameraVideo.path);
      final result = Completer<VideoProcessResult>();
      void Function(double progress)? progressCallback;
      final imageProcessor = ImageProcessor(
        compressFile:
            ({
              required path,
              required quality,
              required keepExif,
              minWidth = 1920,
              minHeight = 1080,
            }) async => null,
        compressVideo:
            ({
              required path,
              required compress,
              void Function(double progress)? onProgress,
            }) async {
              progressCallback = onProgress;
              return result.future;
            },
      );

      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildWidget(
          group: group,
          mediaRepo: mediaAttachmentRepo,
          imageProcessor: imageProcessor,
          mediaPicker: mediaPicker,
        ),
      );
      await pumpFrames(tester, count: 20);

      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pump(const Duration(milliseconds: 500));
      tester
          .widget<ListTile>(find.widgetWithText(ListTile, 'Record Video'))
          .onTap!();
      await tester.pump();

      expect(progressCallback, isNotNull);

      progressCallback!(40);
      await tester.pump();

      expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
      expect(find.text('Processing'), findsOneWidget);
      expect(find.text('Processing (1/1)'), findsNothing);
      expect(find.text('40%'), findsOneWidget);

      result.complete(VideoProcessResult(path: processedVideo.path));
      await tester.pump();
    });

    testWidgets(
      'sent text message appears immediately before bridge responds',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);

        // Use a gated bridge that blocks group:publish until we release it
        final gatedBridge = _GatedPublishBridge();
        bridge = gatedBridge;

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester);

        // Type and send
        await tester.enterText(find.byType(TextField), 'Optimistic hello');
        await pumpFrames(tester);
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        // Pump a few frames — bridge is still gated
        await pumpFrames(tester, count: 5);

        // Message should be visible optimistically
        expect(find.text('Optimistic hello'), findsOneWidget);

        // Status should be 'sending' (single check icon)
        expect(find.byIcon(Icons.done_rounded), findsOneWidget);
        expect(find.byIcon(Icons.done_all_rounded), findsNothing);

        // Release the bridge
        gatedBridge.publishGate.complete();
        await pumpFrames(tester, count: 20);

        // Message still visible, status updated to 'sent'
        expect(find.text('Optimistic hello'), findsOneWidget);
      },
    );

    testWidgets('optimistic message is saved to DB before network ops', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      await saveActiveGroupMembers(groupRepo, group);

      final gatedBridge = _GatedPublishBridge();
      bridge = gatedBridge;

      await tester.pumpWidget(buildWidget(group: group));
      await pumpFrames(tester);

      await tester.enterText(find.byType(TextField), 'DB before net');
      await pumpFrames(tester);
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await pumpFrames(tester, count: 5);

      // Message should be in the DB with status 'sending'
      final messages = await msgRepo.getMessagesPage(group.id);
      expect(messages.length, 1);
      expect(messages.first.text, 'DB before net');
      expect(messages.first.status, 'sending');

      // Bridge hasn't been called for publish yet? Actually it was called
      // but is blocked on the completer. The key point: DB was saved first.

      gatedBridge.publishGate.complete();
      await pumpFrames(tester, count: 20);

      // After publish completes, status should be 'sent'
      final updated = await msgRepo.getMessagesPage(group.id);
      expect(updated.first.status, 'sent');
    });

    testWidgets('GFR-003 failed text recovery clears duplicate composer path', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      await saveActiveGroupMembers(groupRepo, group);

      // Bridge returns failure for publish
      bridge = FakeBridge(
        initialResponses: {
          'group:publish': {'ok': false, 'errorCode': 'PUBLISH_FAILED'},
        },
      );

      await tester.pumpWidget(
        buildWidget(group: group, mediaRepo: mediaAttachmentRepo),
      );
      await pumpFrames(tester);

      await tester.enterText(find.byType(TextField), 'Will fail');
      await pumpFrames(tester);
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await pumpFrames(tester, count: 20);

      final failedRows = (await msgRepo.getMessagesPage(
        group.id,
      )).where((message) => message.text == 'Will fail').toList();
      expect(failedRows, hasLength(1));
      expect(failedRows.single.status, 'failed');

      // Message should still be visible, but the composer should not keep the
      // same text as a second independent Send path.
      expect(find.text('Will fail'), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        isEmpty,
      );
      expect(
        find.byKey(ValueKey('failed-message-retry-${failedRows.single.id}')),
        findsOneWidget,
      );

      // Status should be 'failed' (error icon)
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    testWidgets(
      'GFR-003 quoted failed text does not restore stale duplicate quote draft',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-gfr003-parent',
            text: 'Quoted parent',
            groupId: group.id,
          ),
        );
        bridge = FakeBridge(
          initialResponses: {
            'group:publish': {'ok': false, 'errorCode': 'PUBLISH_FAILED'},
          },
        );

        await tester.pumpWidget(
          buildWidget(group: group, mediaRepo: mediaAttachmentRepo),
        );
        await pumpFrames(tester);

        final initialScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        initialScreen.onQuoteReply!('msg-gfr003-parent');
        await pumpFrames(tester);
        expect(
          tester
              .widget<GroupConversationScreen>(
                find.byType(GroupConversationScreen),
              )
              .activeQuoteText,
          'Quoted parent',
        );

        await tester.enterText(find.byType(TextField), 'Quoted failure');
        await pumpFrames(tester);
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpFrames(tester, count: 20);

        final failedRows = (await msgRepo.getMessagesPage(
          group.id,
        )).where((message) => message.text == 'Quoted failure').toList();
        expect(failedRows, hasLength(1));
        expect(failedRows.single.status, 'failed');
        expect(failedRows.single.quotedMessageId, 'msg-gfr003-parent');
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          isEmpty,
        );
        expect(
          tester
              .widget<GroupConversationScreen>(
                find.byType(GroupConversationScreen),
              )
              .activeQuoteText,
          isNull,
        );
        expect(
          find.byKey(ValueKey('failed-message-retry-${failedRows.single.id}')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'publish timeout with inbox success keeps the message successful in UI',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);

        bridge = FakeBridge(
          initialResponses: {
            'group:publish': {'ok': false, 'errorCode': 'BRIDGE_TIMEOUT'},
          },
        );

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester);

        await tester.enterText(find.byType(TextField), 'Timeout but stored');
        await pumpFrames(tester);
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpFrames(tester, count: 20);

        expect(find.text('Timeout but stored'), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          isEmpty,
        );
        expect(find.byIcon(Icons.error_outline_rounded), findsNothing);

        final saved = (await msgRepo.getMessagesPage(
          group.id,
        )).firstWhere((message) => message.text == 'Timeout but stored');
        expect(saved.status, 'sent');
        expect(saved.inboxStored, isTrue);
      },
    );

    testWidgets('upload failure restores quote draft and attachments', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      await saveActiveGroupMembers(groupRepo, group);
      await msgRepo.saveMessage(
        makeMessage(
          id: 'msg-parent-upload',
          text: 'Upload parent',
          groupId: group.id,
          isIncoming: true,
        ),
      );

      final tempDir = Directory.systemTemp.createTempSync(
        'group_retry_upload_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final attachment = File('${tempDir.path}/retry.png')
        ..writeAsBytesSync(_tinyPngBytes);

      await tester.pumpWidget(
        buildWidget(
          group: group,
          uploadMediaFn:
              ({
                required bridge,
                required localFilePath,
                required mime,
                required recipientPeerId,
                String? blobId,
                mediaFileManager,
                width,
                height,
                durationMs,
                waveform,
                allowedPeers,
                deleteSourceWhenDone = false,
                preparedArtifact,
              }) async => null,
          initialPendingMedia: [
            PendingComposerMedia(
              file: attachment,
              budgetBytes: attachment.lengthSync(),
            ),
          ],
        ),
      );
      await pumpFrames(tester, count: 20);
      expect(
        find.byType(AttachmentPreviewStrip),
        findsOneWidget,
        reason: 'initial attachment preview should be seeded before send',
      );

      final screen = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      screen.onQuoteReply!.call('msg-parent-upload');
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Retry upload');
      await pumpFrames(tester);
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await pumpFrames(tester, count: 30);

      expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
      expect(find.text('Replying to'), findsOneWidget);
      expect(find.text('Upload parent'), findsWidgets);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'Retry upload',
      );
    });

    testWidgets(
      'durable media send rejects spoofed bytes before saving upload rows',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        final tempDir = Directory.systemTemp.createTempSync(
          'group-spoofed-media-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final attachment = File(p.join(tempDir.path, 'spoof.jpg'))
          ..writeAsBytesSync(const <int>[0x25, 0x50, 0x44, 0x46, 0x2d, 0x31]);
        var uploadCalled = false;

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: TrackingDurableMediaFileManager(tempDir),
            initialAttachments: [attachment],
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                  deleteSourceWhenDone = false,
                  preparedArtifact,
                }) async {
                  uploadCalled = true;
                  return null;
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        await tester.enterText(find.byType(TextField), 'Spoofed media');
        await pumpFrames(tester);
        await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
        await pumpFrames(tester, count: 30);

        expect(uploadCalled, isFalse);
        expect(
          await mediaAttachmentRepo.getUploadPendingAttachments(
            owner: MediaOwnerLane.group,
          ),
          isEmpty,
        );
        expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'Spoofed media',
        );
      },
    );

    testWidgets(
      'partial durable upload failure keeps successful uploads and clears retryable restored rows',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        final tempDir = Directory.systemTemp.createTempSync(
          'group-partial-upload-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final attachmentA = File(p.join(tempDir.path, 'partial-a.png'))
          ..writeAsBytesSync(_tinyPngBytes);
        final attachmentB = File(p.join(tempDir.path, 'partial-b.png'))
          ..writeAsBytesSync(_tinyPngBytes);
        final mediaFileManager = TrackingDurableMediaFileManager(tempDir);
        final uploadedBlobIds = <String>[];

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            initialAttachments: [attachmentA, attachmentB],
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                  deleteSourceWhenDone = false,
                  preparedArtifact,
                }) async {
                  uploadedBlobIds.add(blobId ?? 'missing-blob-id');
                  if (uploadedBlobIds.length == 2) {
                    return null;
                  }
                  return MediaAttachment(
                    id: blobId!,
                    messageId: '',
                    mime: mime,
                    size: File(localFilePath).lengthSync(),
                    mediaType: MediaAttachment.mediaTypeFromMime(mime),
                    localPath: mediaFileManager!.relativePathForAttachment(
                      contactPeerId: group.id,
                      blobId: blobId,
                      mime: mime,
                    ),
                    downloadStatus: kMediaDownloadStatusDone,
                    contentHash: _validContentHash,
                    encryptionKeyBase64: 'key-fixture',
                    encryptionNonce: 'nonce-fixture',
                    encryptionScheme:
                        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                    createdAt: DateTime.now().toUtc().toIso8601String(),
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        final sendFuture = await startScreenSend(tester, 'Partial upload');
        await tester.runAsync(() async {
          await sendFuture.future;
        });
        await pumpFrames(tester, count: 5);

        expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
        expect(
          await mediaAttachmentRepo.getUploadPendingAttachments(
            owner: MediaOwnerLane.group,
          ),
          isEmpty,
        );
        final failedMessage = (await msgRepo.getMessagesPage(
          group.id,
        )).singleWhere((message) => message.text == 'Partial upload');
        expect(failedMessage.status, 'failed');
        final savedAttachments = await mediaAttachmentRepo
            .getAttachmentsForMessage(
              failedMessage.id,
              owner: MediaOwnerLane.group,
            );
        expect(
          savedAttachments.where(
            (attachment) => attachment.downloadStatus == 'done',
          ),
          hasLength(1),
        );
        expect(
          savedAttachments.where(
            (attachment) => attachment.downloadStatus == 'upload_failed',
          ),
          hasLength(1),
        );
        expect(
          savedAttachments
              .singleWhere((attachment) => attachment.downloadStatus == 'done')
              .id,
          uploadedBlobIds.first,
        );
      },
    );

    testWidgets(
      'offline banner seeds current state and follows both service edges',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        p2pService = FakeP2PService(initialState: NodeState.stopped);

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester);

        expect(
          find.byKey(const ValueKey('offline-message-banner')),
          findsOneWidget,
        );
        expect(find.text("You're offline"), findsOneWidget);

        p2pService.emitState(
          const NodeState(
            isStarted: true,
            peerId: 'me',
            sendCapabilityReady: true,
            inboxCapabilityReady: true,
          ),
        );
        await tester.pump();
        expect(
          find.byKey(const ValueKey('offline-message-banner')),
          findsNothing,
        );

        p2pService.emitState(NodeState.stopped);
        await tester.pump();
        await tester.pump();
        expect(
          find.byKey(const ValueKey('offline-message-banner')),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'retry progress is message-keyed, attachment-correlated, and cleaned on settle',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        final queuedA = makeMessage(
          id: 'retry-progress-a',
          text: '',
          isIncoming: false,
          senderPeerId: testIdentity.peerId,
          senderUsername: testIdentity.username,
          status: GroupMessage.statusQueuedOffline,
        );
        final queuedB = makeMessage(
          id: 'retry-progress-b',
          text: '',
          isIncoming: false,
          senderPeerId: testIdentity.peerId,
          senderUsername: testIdentity.username,
          status: GroupMessage.statusQueuedOffline,
        );
        await msgRepo.saveMessage(queuedA);
        await msgRepo.saveMessage(queuedB);
        for (final entry in const [
          ('retry-progress-a', 'retry-blob-a'),
          ('retry-progress-b', 'retry-blob-b'),
        ]) {
          await mediaAttachmentRepo.saveAttachment(
            MediaAttachment(
              id: entry.$2,
              messageId: entry.$1,
              mime: 'image/jpeg',
              size: 10,
              mediaType: 'image',
              downloadStatus: 'upload_pending',
              contentHash: _validContentHash,
              createdAt: DateTime.now().toUtc().toIso8601String(),
            ),
            owner: MediaOwnerLane.group,
          );
        }

        await tester.pumpWidget(
          buildWidget(group: group, mediaRepo: mediaAttachmentRepo),
        );
        await pumpFrames(tester, count: 20);
        final initialScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(
          initialScreen.messages
              .where(
                (message) =>
                    message.id == 'retry-progress-a' ||
                    message.id == 'retry-progress-b',
              )
              .map((message) => message.status),
          everyElement(GroupMessage.statusQueuedOffline),
        );
        expect(
          initialScreen.mediaMap['retry-progress-a']?.single.id,
          'retry-blob-a',
        );
        expect(
          initialScreen.mediaMap['retry-progress-b']?.single.id,
          'retry-blob-b',
        );
        expect(
          initialScreen.precomputedDisplayItems
              ?.where(
                (item) =>
                    item.message?.id == 'retry-progress-a' ||
                    item.message?.id == 'retry-progress-b',
              )
              .length,
          2,
        );
        emitMediaUploadProgressEvent({
          'id': 'wrong-blob',
          'sentBytes': 5,
          'totalBytes': 10,
          'toPeerId': group.id,
        });
        await tester.pump();
        var projectedScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(projectedScreen.messageUploadProgress, isEmpty);

        emitMediaUploadProgressEvent({
          'id': 'retry-blob-a',
          'sentBytes': 5,
          'totalBytes': 10,
          'toPeerId': group.id,
        });
        emitMediaUploadProgressEvent({
          'id': 'retry-blob-b',
          'sentBytes': 2,
          'totalBytes': 10,
          'toPeerId': group.id,
        });
        await tester.pump();
        await tester.pump();
        final progressScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(
          progressScreen.messageUploadProgress['retry-progress-a']?.percent,
          50,
        );
        expect(
          progressScreen.messageUploadProgress['retry-progress-b']?.percent,
          20,
        );

        // A regressive event for the same attachment is stale and cannot move
        // the message backward.
        emitMediaUploadProgressEvent({
          'id': 'retry-blob-a',
          'sentBytes': 1,
          'totalBytes': 10,
          'toPeerId': group.id,
        });
        await tester.pump();
        projectedScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(
          projectedScreen.messageUploadProgress['retry-progress-a']?.percent,
          50,
        );

        await msgRepo.saveMessage(queuedA.copyWith(status: 'sent'));
        await pumpFrames(tester);
        projectedScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(
          projectedScreen.messageUploadProgress.containsKey('retry-progress-a'),
          isFalse,
        );
        expect(
          projectedScreen.messageUploadProgress.containsKey('retry-progress-b'),
          isTrue,
        );

        emitMediaUploadProgressEvent({
          'id': 'retry-blob-a',
          'sentBytes': 9,
          'totalBytes': 10,
          'toPeerId': group.id,
        });
        await tester.pump();
        await tester.pump();
        projectedScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(
          projectedScreen.messageUploadProgress.containsKey('retry-progress-a'),
          isFalse,
        );
      },
    );

    testWidgets('shows relay upload progress and blocks leaving mid-upload', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      await saveActiveGroupMembers(groupRepo, group);

      final tempDir = Directory.systemTemp.createTempSync(
        'group_upload_progress_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final attachment = File('${tempDir.path}/progress.jpg')
        ..writeAsStringSync('0123456789');

      final uploadGate = Completer<void>();
      final uploadStarted = Completer<void>();
      String? activeBlobId;

      await tester.pumpWidget(
        buildWidget(
          group: group,
          initialAttachments: [attachment],
          uploadMediaFn:
              ({
                required bridge,
                required localFilePath,
                required mime,
                required recipientPeerId,
                String? blobId,
                mediaFileManager,
                width,
                height,
                durationMs,
                waveform,
                allowedPeers,
                deleteSourceWhenDone = false,
                preparedArtifact,
              }) async {
                activeBlobId = blobId;
                uploadStarted.complete();
                await uploadGate.future;
                return MediaAttachment(
                  id: blobId ?? 'uploaded-group-progress-1',
                  messageId: '',
                  mime: mime,
                  size: File(localFilePath).lengthSync(),
                  mediaType: MediaAttachment.mediaTypeFromMime(mime),
                  localPath: localFilePath,
                  downloadStatus: 'done',
                  contentHash: _validContentHash,
                  encryptionKeyBase64: 'key-fixture',
                  encryptionNonce: 'nonce-fixture',
                  encryptionScheme:
                      kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                  createdAt: DateTime.now().toUtc().toIso8601String(),
                );
              },
        ),
      );
      await pumpFrames(tester, count: 20);

      await tester.enterText(find.byType(TextField), 'Uploading');
      await pumpFrames(tester);
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await uploadStarted.future;
      await tester.pump();

      expect(
        find.byKey(const ValueKey('upload-progress-banner')),
        findsOneWidget,
      );
      expect(wakeLockDriver.enableCalls, 1);
      expect(UploadWakeLockController.debugActiveHolds, 1);

      emitMediaUploadProgressEvent({
        'id': activeBlobId,
        'sentBytes': 5,
        'totalBytes': 10,
        'toPeerId': group.id,
      });
      await tester.pump();

      expect(find.text('50%'), findsOneWidget);
      expect(find.text('Sending automatically…'), findsOneWidget);
      expect(find.text('Uploading photo · 50%'), findsOneWidget);
      expect(
        find.text('Keep the app open until the upload completes'),
        findsOneWidget,
      );

      await tester.tap(find.byIcon(Icons.arrow_back_ios_new));
      await tester.pump();

      expect(find.text('Leave conversation?'), findsOneWidget);
      expect(
        find.text(
          'An upload is in progress. Leaving may interrupt it. Are you sure?',
        ),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('upload-leave-stay')));
      await tester.pump();

      expect(
        find.byKey(const ValueKey('upload-progress-banner')),
        findsOneWidget,
      );
      expect(wakeLockDriver.disableCalls, 0);

      uploadGate.complete();
      await pumpUntil(
        tester,
        () =>
            find
                .byKey(const ValueKey('upload-progress-banner'))
                .evaluate()
                .isEmpty &&
            wakeLockDriver.disableCalls == 1,
      );

      expect(UploadWakeLockController.debugActiveHolds, 0);
      expect(find.text('Sending automatically…'), findsNothing);
    });

    testWidgets(
      'switching groups mid-upload quarantines old progress cancel and composer restore until its wake hold terminates',
      (tester) async {
        final groupA = makeChatGroup();
        final groupB = makeChatGroup().copyWith(
          id: 'group-2',
          name: 'Second Group',
          topicName: 'topic-2',
        );
        await groupRepo.saveGroup(groupA);
        await groupRepo.saveGroup(groupB);
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupB.id,
            keyGeneration: 1,
            encryptedKey: 'test-group-key-2',
            createdAt: DateTime.now().toUtc(),
          ),
        );
        await saveActiveGroupMembers(groupRepo, groupA);
        await saveActiveGroupMembers(groupRepo, groupB);

        final tempDir = Directory.systemTemp.createTempSync(
          'group_upload_scope_switch_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final oldAttachment = File('${tempDir.path}/old.jpg')
          ..writeAsBytesSync(validJpegFixtureBytes);
        final newAttachment = File('${tempDir.path}/new.jpg')
          ..writeAsBytesSync(validJpegFixtureBytes);
        final picker = FakeMediaPicker()
          ..multipleMediaResult = <XFile>[XFile(newAttachment.path)];
        final oldUploadGate = Completer<void>();
        final oldUploadStarted = Completer<void>();
        final newUploadStarted = Completer<void>();
        final uploadRecipients = <String>[];
        String? oldBlobId;
        Future<MediaAttachment?> uploadForScope({
          required Bridge bridge,
          required String localFilePath,
          required String mime,
          required String recipientPeerId,
          MediaFileManager? mediaFileManager,
          int? width,
          int? height,
          int? durationMs,
          List<double>? waveform,
          List<String>? allowedPeers,
          String? blobId,
          bool deleteSourceWhenDone = false,
          EncryptedMediaArtifact? preparedArtifact,
        }) async {
          uploadRecipients.add(recipientPeerId);
          if (recipientPeerId == groupA.id) {
            oldBlobId = blobId;
            if (!oldUploadStarted.isCompleted) oldUploadStarted.complete();
            await oldUploadGate.future;
          } else if (!newUploadStarted.isCompleted) {
            newUploadStarted.complete();
          }
          return successfulGroupUploadFixture(
            blobId: blobId!,
            mime: mime,
            localFilePath: localFilePath,
          );
        }

        final createdAt = DateTime.now().toUtc().toIso8601String();
        const queuedBlobId = 'group-b-progress-blob';
        const queuedMessageId = 'group-b-progress-message';
        final queuedAttachment = MediaAttachment(
          id: queuedBlobId,
          messageId: queuedMessageId,
          mime: 'image/jpeg',
          size: 10,
          mediaType: 'image',
          downloadStatus: 'upload_pending',
          createdAt: createdAt,
        );
        await msgRepo.saveMessage(
          makeMessage(
            id: queuedMessageId,
            groupId: groupB.id,
            text: '',
            status: 'sending',
            isIncoming: false,
            media: <MediaAttachment>[queuedAttachment],
          ),
        );

        await tester.pumpWidget(
          buildWidget(
            group: groupA,
            initialAttachments: <File>[oldAttachment],
            mediaPicker: picker,
            uploadMediaFn: uploadForScope,
          ),
        );
        await pumpFrames(tester, count: 20);
        final oldSend = await startScreenSend(tester, 'Old scope draft');
        await pumpUntil(
          tester,
          () => oldUploadStarted.isCompleted,
          maxPumps: 120,
        );

        final oldScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(oldScreen.onCancelUpload, isNotNull);
        oldScreen.onCancelUpload!.call();
        await tester.pump();
        expect(UploadWakeLockController.debugActiveHolds, 1);
        expect(wakeLockDriver.disableCalls, 0);

        await tester.pumpWidget(
          buildWidget(
            group: groupB,
            mediaPicker: picker,
            uploadMediaFn: uploadForScope,
          ),
        );
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen.group.id == groupB.id &&
              screen.messages.any((message) => message.id == queuedMessageId);
        }, maxPumps: 120);
        await tester.enterText(find.byType(TextField), 'Group B draft');
        await tester.pump();

        emitMediaUploadProgressEvent({
          'id': oldBlobId,
          'sentBytes': 9,
          'totalBytes': 10,
          'toPeerId': groupA.id,
        });
        emitMediaUploadProgressEvent({
          'id': queuedBlobId,
          'sentBytes': 3,
          'totalBytes': 10,
          'toPeerId': groupB.id,
        });
        await pumpFrames(tester);

        var currentScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(currentScreen.group.id, groupB.id);
        expect(currentScreen.uploadProgress, isNull);
        expect(currentScreen.onCancelUpload, isNull);
        expect(
          currentScreen.messageUploadProgress.containsKey(queuedMessageId),
          isTrue,
        );
        expect(
          currentScreen.messageUploadProgress[queuedMessageId]?.sentBytes,
          3,
        );
        expect(
          currentScreen.messageUploadProgress.values.any(
            (progress) => progress.attachmentId == oldBlobId,
          ),
          isFalse,
        );
        expect(UploadWakeLockController.debugActiveHolds, 1);
        expect(wakeLockDriver.disableCalls, 0);

        oldUploadGate.complete();
        await pumpUntilFuturesComplete(tester, <Future<void>>[oldSend.future]);
        await pumpUntil(
          tester,
          () => UploadWakeLockController.debugActiveHolds == 0,
          maxPumps: 120,
        );

        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'Group B draft',
        );
        expect(find.byType(AttachmentPreviewStrip), findsNothing);
        expect(find.text('Upload cancelled.'), findsNothing);
        expect(wakeLockDriver.disableCalls, 1);

        await tester.tap(find.byIcon(Icons.add_rounded));
        await tester.pump(const Duration(milliseconds: 500));
        tester
            .widget<ListTile>(find.widgetWithText(ListTile, 'Media Library'))
            .onTap!();
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen
                  .composerStateListenable
                  ?.value
                  .pendingAttachments
                  .length ==
              1;
        }, maxPumps: 120);

        final newSend = await startScreenSend(tester, 'Group B operation');
        await pumpUntilFuturesComplete(tester, <Future<void>>[newSend.future]);
        await pumpUntil(
          tester,
          () => UploadWakeLockController.debugActiveHolds == 0,
          maxPumps: 120,
        );

        currentScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(newUploadStarted.isCompleted, isTrue);
        expect(
          uploadRecipients,
          containsAllInOrder(<String>[groupA.id, groupB.id]),
        );
        expect(currentScreen.group.id, groupB.id);
        expect(wakeLockDriver.enableCalls, 2);
        expect(wakeLockDriver.disableCalls, 2);
      },
    );

    testWidgets(
      'DTR-15 durable two-leaf upload retarget and ABA unmount never resume the stale lane',
      (tester) async {
        mediaUploadInFlightTracker.clearAll();
        addTearDown(mediaUploadInFlightTracker.clearAll);

        final groupA = makeChatGroup();
        final groupB = makeChatGroup().copyWith(
          id: 'group-2',
          name: 'Second Group',
          topicName: 'topic-2',
        );
        await groupRepo.saveGroup(groupA);
        await groupRepo.saveGroup(groupB);
        await groupRepo.saveKey(
          GroupKeyInfo(
            groupId: groupB.id,
            keyGeneration: 1,
            encryptedKey: 'test-group-key-2',
            createdAt: DateTime.now().toUtc(),
          ),
        );
        await saveActiveGroupMembers(groupRepo, groupA);
        await saveActiveGroupMembers(groupRepo, groupB);

        final tempDir = Directory.systemTemp.createTempSync(
          'dtr15_group_upload_retarget_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final sourceA = File(p.join(tempDir.path, 'leaf-a.jpg'))
          ..writeAsBytesSync(validJpegFixtureBytes);
        final sourceB = File(p.join(tempDir.path, 'leaf-b.jpg'))
          ..writeAsBytesSync(validJpegFixtureBytes);
        final groupARoot = Directory(p.join(tempDir.path, 'group-a'));
        final groupBRoot = Directory(p.join(tempDir.path, 'group-b'));
        final groupAFileManager = _ScopedTrackingDurableMediaFileManager(
          groupARoot,
        );
        final groupBFileManager = _ScopedTrackingDurableMediaFileManager(
          groupBRoot,
        );
        final groupAMediaRepo = _WriteCountingMediaAttachmentRepository();
        final groupBMediaRepo = _WriteCountingMediaAttachmentRepository();
        final firstLeafStarted = Completer<void>();
        final firstLeafRelease = Completer<void>();
        var groupAUploadCalls = 0;
        var groupBUploadCalls = 0;
        final uploadRecipients = <String>[];

        Future<MediaAttachment?> groupAUpload({
          required Bridge bridge,
          required String localFilePath,
          required String mime,
          required String recipientPeerId,
          MediaFileManager? mediaFileManager,
          int? width,
          int? height,
          int? durationMs,
          List<double>? waveform,
          List<String>? allowedPeers,
          String? blobId,
          bool deleteSourceWhenDone = false,
          EncryptedMediaArtifact? preparedArtifact,
        }) async {
          groupAUploadCalls++;
          uploadRecipients.add(recipientPeerId);
          if (!firstLeafStarted.isCompleted) {
            firstLeafStarted.complete();
            await firstLeafRelease.future;
          }
          return successfulGroupUploadFixture(
            blobId: blobId!,
            mime: mime,
            localFilePath: localFilePath,
          );
        }

        Future<MediaAttachment?> groupBUpload({
          required Bridge bridge,
          required String localFilePath,
          required String mime,
          required String recipientPeerId,
          MediaFileManager? mediaFileManager,
          int? width,
          int? height,
          int? durationMs,
          List<double>? waveform,
          List<String>? allowedPeers,
          String? blobId,
          bool deleteSourceWhenDone = false,
          EncryptedMediaArtifact? preparedArtifact,
        }) async {
          groupBUploadCalls++;
          uploadRecipients.add(recipientPeerId);
          return successfulGroupUploadFixture(
            blobId: blobId!,
            mime: mime,
            localFilePath: localFilePath,
          );
        }

        await tester.pumpWidget(
          buildWidget(
            group: groupA,
            mediaRepo: groupAMediaRepo,
            mediaFileManager: groupAFileManager,
            initialAttachments: <File>[sourceA, sourceB],
            uploadMediaFn: groupAUpload,
          ),
        );
        await pumpFrames(tester, count: 20);
        final staleSend = await startScreenSend(tester, 'Two old-group leaves');
        await pumpUntil(
          tester,
          () => firstLeafStarted.isCompleted,
          maxPumps: 120,
        );
        expect(firstLeafStarted.isCompleted, isTrue);
        expect(groupAUploadCalls, 1);

        await tester.pumpWidget(
          buildWidget(
            group: groupB,
            mediaRepo: groupBMediaRepo,
            mediaFileManager: groupBFileManager,
            uploadMediaFn: groupBUpload,
          ),
        );
        await pumpUntil(tester, () {
          return tester
                  .widget<GroupConversationScreen>(
                    find.byType(GroupConversationScreen),
                  )
                  .group
                  .id ==
              groupB.id;
        }, maxPumps: 120);

        await tester.pumpWidget(
          buildWidget(
            group: groupA,
            mediaRepo: groupAMediaRepo,
            mediaFileManager: groupAFileManager,
            uploadMediaFn: groupAUpload,
          ),
        );
        await pumpUntil(tester, () {
          return tester
                  .widget<GroupConversationScreen>(
                    find.byType(GroupConversationScreen),
                  )
                  .group
                  .id ==
              groupA.id;
        }, maxPumps: 120);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        final groupBMediaWritesBeforeRelease =
            groupBMediaRepo.saveAttachmentCalls;
        final groupBStorageLookupsBeforeRelease =
            groupBFileManager.localPathOwnerPeerIds.length;
        final groupBCopiesBeforeRelease = groupBFileManager.copyCalls;
        final publishCallsBeforeRelease = bridge.commandLog
            .where((command) => command == 'group:publish')
            .length;

        firstLeafRelease.complete();
        await pumpUntilFuturesComplete(tester, <Future<void>>[
          staleSend.future,
        ]);
        await pumpUntil(
          tester,
          () => UploadWakeLockController.debugActiveHolds == 0,
          maxPumps: 120,
        );

        expect(
          <String, Object>{
            'group A upload calls': groupAUploadCalls,
            'group B upload calls': groupBUploadCalls,
            'upload recipients': uploadRecipients,
            'group B media writes':
                groupBMediaRepo.saveAttachmentCalls -
                groupBMediaWritesBeforeRelease,
            'group B storage lookups':
                groupBFileManager.localPathOwnerPeerIds.length -
                groupBStorageLookupsBeforeRelease,
            'group B durable copies':
                groupBFileManager.copyCalls - groupBCopiesBeforeRelease,
            'group B pending-dir deletes':
                groupBFileManager.deletedPendingUploadDirs,
            'publish calls':
                bridge.commandLog
                    .where((command) => command == 'group:publish')
                    .length -
                publishCallsBeforeRelease,
          },
          <String, Object>{
            'group A upload calls': 1,
            'group B upload calls': 0,
            'upload recipients': <String>[groupA.id],
            'group B media writes': 0,
            'group B storage lookups': 0,
            'group B durable copies': 0,
            'group B pending-dir deletes': <String>[],
            'publish calls': 0,
          },
        );
      },
    );

    testWidgets(
      'cancel between serialized upload leaves restores composer and preserves the completed leaf',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);

        final tempDir = Directory.systemTemp.createTempSync(
          'group_cancel_upload_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final attachmentA = File('${tempDir.path}/cancel-a.jpg')
          ..writeAsBytesSync(validJpegFixtureBytes);
        final attachmentB = File('${tempDir.path}/cancel-b.jpg')
          ..writeAsBytesSync(validJpegFixtureBytes);
        final testMediaFileManager = FakeMediaFileManager();

        final uploadGate = Completer<void>();
        final uploadStarted = <String>[];
        final uploadCompleted = <String>[];

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: testMediaFileManager,
            initialAttachments: [attachmentA, attachmentB],
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                  deleteSourceWhenDone = false,
                  preparedArtifact,
                }) async {
                  uploadStarted.add(blobId ?? 'missing-blob-id');
                  await uploadGate.future;
                  uploadCompleted.add(blobId ?? 'missing-blob-id');
                  return MediaAttachment(
                    id: blobId ?? 'uploaded-group-cancel',
                    messageId: '',
                    mime: mime,
                    size: 1,
                    mediaType: MediaAttachment.mediaTypeFromMime(mime),
                    localPath: testMediaFileManager.relativePathForAttachment(
                      contactPeerId: group.id,
                      blobId: blobId!,
                      mime: mime,
                    ),
                    downloadStatus: 'done',
                    contentHash: _validContentHash,
                    encryptionKeyBase64: 'key-fixture',
                    encryptionNonce: 'nonce-fixture',
                    encryptionScheme:
                        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                    createdAt: DateTime.now().toUtc().toIso8601String(),
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        final sendFuture = await startScreenSend(tester, 'Cancel upload');
        await pumpUntil(tester, () => uploadStarted.length == 1, maxPumps: 120);
        await pumpFrames(tester, count: 5);

        final cancellingScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(uploadStarted, hasLength(1));
        expect(cancellingScreen.uploadProgress, isNotNull);
        expect(cancellingScreen.onCancelUpload, isNotNull);
        expect(wakeLockDriver.enableCalls, 1);
        expect(UploadWakeLockController.debugActiveHolds, 1);

        cancellingScreen.onCancelUpload!.call();
        await tester.pump();
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:publish'),
          isEmpty,
        );

        uploadGate.complete();
        await tester.runAsync(() async {
          await sendFuture.future;
        });
        await pumpUntil(
          tester,
          () =>
              find
                  .byKey(const ValueKey('upload-progress-banner'))
                  .evaluate()
                  .isEmpty &&
              wakeLockDriver.disableCalls == 1,
        );

        final storedMessages = await msgRepo.getMessagesPage(group.id);
        expect(storedMessages, hasLength(1));
        final failedMessage = storedMessages.single;
        final storedAttachments = await mediaAttachmentRepo
            .getAttachmentsForMessage(
              failedMessage.id,
              owner: MediaOwnerLane.group,
            );

        expect(uploadCompleted, hasLength(1));
        expect(failedMessage.status, 'failed');
        expect(storedAttachments, hasLength(1));
        expect(
          storedAttachments.every(
            (attachment) => attachment.downloadStatus == 'done',
          ),
          isTrue,
        );
        expect(
          await mediaAttachmentRepo.getUploadPendingAttachments(
            owner: MediaOwnerLane.group,
          ),
          isEmpty,
        );
        expect(find.text('Upload cancelled.'), findsOneWidget);
        expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
        expect(find.text('Retry'), findsOneWidget);
        expect(find.text('Delete'), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'Cancel upload',
        );
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:publish'),
          isEmpty,
        );
        expect(UploadWakeLockController.debugActiveHolds, 0);
      },
    );

    testWidgets(
      'serialized group cancellation preserves same id direct pending media',
      (tester) async {
        // 228 TC-228-05B: a DIRECT message can legally share the group
        // message's id. Completing the in-flight group leaf must update ONLY
        // the group lane; the same-ID direct sibling remains upload_pending.
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);

        final tempDir = Directory.systemTemp.createTempSync(
          'group_cancel_collide_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final attachment = File('${tempDir.path}/collide.jpg')
          ..writeAsBytesSync(validJpegFixtureBytes);
        final testMediaFileManager = FakeMediaFileManager();

        final uploadGate = Completer<void>();
        final uploadStarted = <String>[];

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: testMediaFileManager,
            initialAttachments: [attachment],
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                  deleteSourceWhenDone = false,
                  preparedArtifact,
                }) async {
                  uploadStarted.add(blobId ?? 'missing-blob-id');
                  await uploadGate.future;
                  return MediaAttachment(
                    id: blobId ?? 'uploaded-group-collide',
                    messageId: '',
                    mime: mime,
                    size: 1,
                    mediaType: MediaAttachment.mediaTypeFromMime(mime),
                    localPath: testMediaFileManager.relativePathForAttachment(
                      contactPeerId: group.id,
                      blobId: blobId!,
                      mime: mime,
                    ),
                    downloadStatus: 'done',
                    contentHash: _validContentHash,
                    encryptionKeyBase64: 'key-fixture',
                    encryptionNonce: 'nonce-fixture',
                    encryptionScheme:
                        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                    createdAt: DateTime.now().toUtc().toIso8601String(),
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        final sendFuture = await startScreenSend(tester, 'Cancel collide');
        await pumpUntil(tester, () => uploadStarted.length == 1, maxPumps: 120);
        await pumpFrames(tester, count: 5);

        // The durable group row is upload_pending; learn the colliding
        // message id and seed the same-ID DIRECT-lane sibling BEFORE the
        // cancel-driven group terminalization runs.
        final pendingGroup = await mediaAttachmentRepo
            .getUploadPendingAttachments(owner: MediaOwnerLane.group);
        expect(pendingGroup, hasLength(1));
        final collidingMessageId = pendingGroup.single.messageId;
        await mediaAttachmentRepo.saveAttachment(
          MediaAttachment(
            id: 'att-direct-sibling',
            messageId: collidingMessageId,
            mime: 'image/jpeg',
            size: 10,
            mediaType: 'image',
            localPath:
                'pending_uploads/$collidingMessageId/att-direct-sibling.jpg',
            downloadStatus: 'upload_pending',
            createdAt: '2026-01-15T12:02:00.000Z',
          ),
          owner: MediaOwnerLane.direct,
        );

        final cancellingScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(cancellingScreen.onCancelUpload, isNotNull);
        cancellingScreen.onCancelUpload!.call();
        await tester.pump();

        uploadGate.complete();
        await tester.runAsync(() async {
          await sendFuture.future;
        });
        await pumpUntil(
          tester,
          () =>
              find
                  .byKey(const ValueKey('upload-progress-banner'))
                  .evaluate()
                  .isEmpty &&
              wakeLockDriver.disableCalls == 1,
        );

        // The in-flight group leaf completed before cancellation was observed.
        final groupAttachments = await mediaAttachmentRepo
            .getAttachmentsForMessage(
              collidingMessageId,
              owner: MediaOwnerLane.group,
            );
        expect(groupAttachments, hasLength(1));
        expect(groupAttachments.single.downloadStatus, 'done');
        expect(
          await mediaAttachmentRepo.getUploadPendingAttachments(
            owner: MediaOwnerLane.group,
          ),
          isEmpty,
        );
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:publish'),
          isEmpty,
        );

        // ...while the same-ID direct sibling is STILL upload_pending.
        final directSiblings = await mediaAttachmentRepo
            .getAttachmentsForMessage(
              collidingMessageId,
              owner: MediaOwnerLane.direct,
            );
        expect(directSiblings.single.id, 'att-direct-sibling');
        expect(directSiblings.single.downloadStatus, 'upload_pending');
      },
    );

    testWidgets(
      'retry control re-sends the targeted failed outgoing text row',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);

        String retryPayload({
          required String messageId,
          required String text,
          required String timestamp,
        }) {
          return jsonEncode({
            'groupId': group.id,
            'message': jsonEncode({
              'groupId': group.id,
              'senderId': testIdentity.peerId,
              'senderUsername': testIdentity.username,
              'keyEpoch': 0,
              'text': text,
              'timestamp': timestamp,
              'messageId': messageId,
              'media': const <Object>[],
            }),
          });
        }

        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-text-targeted',
            text: 'Retry this text row',
            groupId: group.id,
            isIncoming: false,
            senderPeerId: testIdentity.peerId,
            senderUsername: testIdentity.username,
            status: 'failed',
            inboxRetryPayload: retryPayload(
              messageId: 'msg-text-targeted',
              text: 'Retry this text row',
              timestamp: '2026-01-15T12:00:00.000Z',
            ),
          ),
        );
        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-text-untouched',
            text: 'Leave this text failed',
            groupId: group.id,
            isIncoming: false,
            senderPeerId: testIdentity.peerId,
            senderUsername: testIdentity.username,
            status: 'failed',
            inboxRetryPayload: retryPayload(
              messageId: 'msg-text-untouched',
              text: 'Leave this text failed',
              timestamp: '2026-01-15T12:01:00.000Z',
            ),
          ),
        );

        await tester.pumpWidget(
          buildWidget(group: group, mediaRepo: mediaAttachmentRepo),
        );
        await tester.pump();
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen.ownPeerId == testIdentity.peerId &&
              screen.messages.any(
                (message) =>
                    message.id == 'msg-text-targeted' &&
                    message.status == 'failed',
              );
        });

        final retryScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(retryScreen.ownPeerId, testIdentity.peerId);
        expect(retryScreen.onRetryFailedMessage, isNotNull);
        expect(retryScreen.onRetryFailedMedia, isNull);

        final initialGetMessageCalls = msgRepo.getMessageCalls;
        retryScreen.onRetryFailedMessage!('msg-text-targeted');
        await pumpUntil(
          tester,
          () =>
              bridge.commandLog.where((cmd) => cmd == 'group:publish').length ==
              1,
        );
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen.messages.any(
            (message) =>
                message.id == 'msg-text-targeted' && message.status == 'sent',
          );
        });

        expect((await msgRepo.getMessage('msg-text-targeted'))?.status, 'sent');
        expect(
          (await msgRepo.getMessage('msg-text-untouched'))?.status,
          'failed',
        );
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:publish').length,
          1,
        );
        expect(msgRepo.getMessageCalls, greaterThan(initialGetMessageCalls));

        final refreshedScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final refreshedRow = refreshedScreen.messages.singleWhere(
          (message) => message.id == 'msg-text-targeted',
        );
        expect(refreshedRow.status, 'sent');
        expect(find.text('Could not retry message.'), findsNothing);
      },
    );

    testWidgets(
      'GFR-003 repeated retry taps coalesce while row retry is in flight',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        final gatedBridge = _GatedPublishBridge();
        bridge = gatedBridge;

        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-gfr003-retrying',
            text: 'Retry once',
            groupId: group.id,
            isIncoming: false,
            senderPeerId: testIdentity.peerId,
            senderUsername: testIdentity.username,
            status: 'failed',
            inboxRetryPayload: groupTextRetryPayload(
              groupId: group.id,
              senderPeerId: testIdentity.peerId,
              senderUsername: testIdentity.username,
              messageId: 'msg-gfr003-retrying',
              text: 'Retry once',
              timestamp: '2026-01-15T12:02:00.000Z',
            ),
          ),
        );

        await tester.pumpWidget(
          buildWidget(group: group, mediaRepo: mediaAttachmentRepo),
        );
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen.messages.any(
            (message) =>
                message.id == 'msg-gfr003-retrying' &&
                message.status == 'failed',
          );
        });

        final retryScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        retryScreen.onRetryFailedMessage!('msg-gfr003-retrying');
        retryScreen.onRetryFailedMessage!('msg-gfr003-retrying');
        await pumpUntil(tester, () => gatedBridge.publishAttempts == 1);

        final inFlightScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(
          inFlightScreen.retryingFailedMessageIds,
          contains('msg-gfr003-retrying'),
        );
        expect(gatedBridge.publishAttempts, 1);

        gatedBridge.publishGate.complete();
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen.messages.any(
            (message) =>
                message.id == 'msg-gfr003-retrying' && message.status == 'sent',
          );
        });

        expect(gatedBridge.publishAttempts, 1);
        expect(
          (await msgRepo.getMessage('msg-gfr003-retrying'))?.status,
          'sent',
        );
      },
    );

    testWidgets(
      'retry control preserves accepted-recipient filtering for failed outgoing text row',
      (tester) async {
        final group = makeChatGroup().copyWith(
          createdAt: DateTime.utc(2026, 5, 1, 9),
        );
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: 'peer-charlie',
            username: 'Charlie',
            role: MemberRole.writer,
            publicKey: 'pk-peer-charlie',
            mlKemPublicKey: 'mlkem-peer-charlie',
            joinedAt: DateTime.utc(2026, 5, 1, 10, 2),
          ),
        );

        final inviteAttemptRepo = _InMemoryInviteDeliveryAttemptRepository();
        await inviteAttemptRepo.saveAttempt(
          GroupInviteDeliveryAttempt(
            groupId: group.id,
            peerId: 'peer-charlie',
            username: 'Charlie',
            status: GroupInviteDeliveryStatus.sent,
            attemptedAt: DateTime.utc(2026, 5, 1, 10, 3),
            updatedAt: DateTime.utc(2026, 5, 1, 10, 3),
          ),
        );

        const messageId = 'msg-text-filtered';
        final timestamp = DateTime.utc(2026, 5, 15, 12);
        final retryPayload = jsonEncode({
          'groupId': group.id,
          'message': jsonEncode({
            'groupId': group.id,
            'senderId': testIdentity.peerId,
            'senderUsername': testIdentity.username,
            'keyEpoch': 0,
            'text': 'Retry with filtered recipients',
            'timestamp': timestamp.toIso8601String(),
            'messageId': messageId,
            'media': const <Object>[],
          }),
        });

        await msgRepo.saveMessage(
          makeMessage(
            id: messageId,
            text: 'Retry with filtered recipients',
            groupId: group.id,
            isIncoming: false,
            senderPeerId: testIdentity.peerId,
            senderUsername: testIdentity.username,
            status: 'failed',
            inboxRetryPayload: retryPayload,
            timestamp: timestamp,
          ),
        );

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            inviteDeliveryAttemptRepo: inviteAttemptRepo,
          ),
        );
        await tester.pump();
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen.ownPeerId == testIdentity.peerId &&
              screen.messages.any(
                (message) =>
                    message.id == messageId && message.status == 'failed',
              );
        });

        final retryScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(retryScreen.onRetryFailedMessage, isNotNull);

        retryScreen.onRetryFailedMessage!(messageId);
        await pumpUntil(
          tester,
          () =>
              bridge.commandLog
                  .where((cmd) => cmd == 'group:inboxStore')
                  .length ==
              1,
          maxPumps: 80,
        );
        await pumpUntilAsync(tester, () async {
          return (await msgRepo.getMessage(messageId))?.status == 'sent';
        }, maxPumps: 80);

        final reliablePayload = groupSendReliablePayloadForMessage(
          bridge,
          messageId,
        );
        expect(
          (reliablePayload['recipientPeerIds'] as List<dynamic>).cast<String>(),
          <String>['peer-bob'],
        );
        expect(
          reliablePayload['recipientPeerIds'],
          isNot(contains('peer-charlie')),
        );
        expect(reliablePayload['preserveRecipientPeerIds'], isTrue);

        final inboxPayload = groupInboxStorePayloadForMessage(
          bridge,
          messageId,
        );
        expect(
          (inboxPayload['recipientPeerIds'] as List<dynamic>).cast<String>(),
          <String>['peer-bob'],
        );
        expect(
          inboxPayload['recipientPeerIds'],
          isNot(contains('peer-charlie')),
        );
        expect(inboxPayload['preserveRecipientPeerIds'], isTrue);
        expect(find.text('Could not retry message.'), findsNothing);
      },
    );

    testWidgets(
      'retry control re-sends only the targeted failed outgoing media row',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        final mediaFileManager = FakeMediaFileManager();

        String retryPayload({
          required String messageId,
          required String text,
          required String attachmentId,
          required String timestamp,
        }) {
          return jsonEncode({
            'groupId': group.id,
            'message': jsonEncode({
              'groupId': group.id,
              'senderId': testIdentity.peerId,
              'senderUsername': testIdentity.username,
              'keyEpoch': 0,
              'text': text,
              'timestamp': timestamp,
              'messageId': messageId,
              'media': [
                {'id': attachmentId},
              ],
            }),
          });
        }

        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-targeted',
            text: 'Retry only me',
            groupId: group.id,
            isIncoming: false,
            senderPeerId: testIdentity.peerId,
            senderUsername: testIdentity.username,
            status: 'failed',
            inboxRetryPayload: retryPayload(
              messageId: 'msg-targeted',
              text: 'Retry only me',
              attachmentId: 'att-targeted',
              timestamp: '2026-01-15T12:00:00.000Z',
            ),
          ),
        );
        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-untouched',
            text: 'Leave me failed',
            groupId: group.id,
            isIncoming: false,
            senderPeerId: testIdentity.peerId,
            senderUsername: testIdentity.username,
            status: 'failed',
            inboxRetryPayload: retryPayload(
              messageId: 'msg-untouched',
              text: 'Leave me failed',
              attachmentId: 'att-untouched',
              timestamp: '2026-01-15T12:01:00.000Z',
            ),
          ),
        );
        await mediaAttachmentRepo.saveAttachment(
          const MediaAttachment(
            id: 'att-targeted',
            messageId: 'msg-targeted',
            mime: 'image/jpeg',
            size: 10,
            mediaType: 'image',
            localPath: 'pending_uploads/msg-targeted/att-targeted.jpg',
            downloadStatus: 'done',
            contentHash: _validContentHash,
            encryptionKeyBase64: 'key-fixture',
            encryptionNonce: 'nonce-fixture',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            createdAt: '2026-01-15T12:00:00.000Z',
          ),
          owner: MediaOwnerLane.group,
        );
        await mediaAttachmentRepo.saveAttachment(
          const MediaAttachment(
            id: 'att-untouched',
            messageId: 'msg-untouched',
            mime: 'image/jpeg',
            size: 10,
            mediaType: 'image',
            localPath: 'pending_uploads/msg-untouched/att-untouched.jpg',
            downloadStatus: 'done',
            contentHash: _validContentHash,
            encryptionKeyBase64: 'key-fixture',
            encryptionNonce: 'nonce-fixture',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            createdAt: '2026-01-15T12:01:00.000Z',
          ),
          owner: MediaOwnerLane.group,
        );

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
          ),
        );
        await tester.pump();
        await pumpUntil(
          tester,
          () => mediaAttachmentRepo.getAttachmentsForMessagesCalls > 0,
        );
        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await pumpFrames(tester, count: 20);
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen.ownPeerId == testIdentity.peerId &&
              (screen.mediaMap['msg-targeted']?.isNotEmpty ?? false);
        });

        final retryScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(retryScreen.ownPeerId, testIdentity.peerId);
        expect(retryScreen.onRetryFailedMedia, isNotNull);
        expect(retryScreen.mediaMap['msg-targeted'], isNotEmpty);

        retryScreen.onRetryFailedMedia!('msg-targeted');
        await pumpUntil(
          tester,
          () =>
              bridge.commandLog.where((cmd) => cmd == 'group:publish').length ==
              1,
        );

        expect((await msgRepo.getMessage('msg-targeted'))?.status, 'sent');
        expect((await msgRepo.getMessage('msg-untouched'))?.status, 'failed');
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:publish').length,
          1,
        );
        expect(find.text('Could not retry media message.'), findsNothing);
      },
    );

    testWidgets(
      'failed text row retry reuses the failed group row id after composer clears',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        bridge = _SequentialGroupPublishBridge([
          {'ok': false, 'errorCode': 'PUBLISH_FAILED'},
          {'ok': true, 'messageId': 'retry-published', 'topicPeers': 1},
        ]);

        await tester.pumpWidget(
          buildWidget(group: group, mediaRepo: mediaAttachmentRepo),
        );
        await pumpFrames(tester, count: 20);

        final firstScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final firstSend = firstScreen.onSend as Future<void> Function(String);
        await tester.runAsync(() async {
          await firstSend('Retry same restored text');
        });
        await pumpFrames(tester, count: 20);

        final failedRows = (await msgRepo.getMessagesPage(group.id))
            .where((message) => message.text == 'Retry same restored text')
            .toList();
        expect(failedRows, hasLength(1));
        final failedRow = failedRows.single;
        expect(failedRow.status, 'failed');
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          isEmpty,
        );

        final retryScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(retryScreen.onRetryFailedMessage, isNotNull);
        retryScreen.onRetryFailedMessage!(failedRow.id);
        await pumpUntilAsync(tester, () async {
          return (await msgRepo.getMessage(failedRow.id))?.status == 'sent';
        });

        final storedRows = (await msgRepo.getMessagesPage(group.id))
            .where((message) => message.text == 'Retry same restored text')
            .toList();
        expect(storedRows, hasLength(1));
        final storedRow = storedRows.single;
        expect(storedRow.id, failedRow.id);
        expect(storedRow.timestamp, failedRow.timestamp);
        expect(storedRow.status, 'sent');

        final publishPayloads = groupPublishPayloads(bridge);
        expect(publishPayloads, hasLength(2));
        expect(
          publishPayloads.map((payload) => payload['messageId']).toList(),
          [failedRow.id, failedRow.id],
        );
        expect(
          publishPayloads.map((payload) => payload['timestamp']).toList(),
          [
            failedRow.timestamp.toUtc().toIso8601String(),
            failedRow.timestamp.toUtc().toIso8601String(),
          ],
        );
      },
    );

    testWidgets(
      'manual edited composer send after text failure creates a new group row id',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        bridge = _SequentialGroupPublishBridge([
          {'ok': false, 'errorCode': 'PUBLISH_FAILED'},
          {'ok': true, 'messageId': 'retry-published', 'topicPeers': 1},
        ]);

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester, count: 20);

        final firstScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final firstSend = firstScreen.onSend as Future<void> Function(String);
        await tester.runAsync(() async {
          await firstSend('Retry then edit restored text');
        });
        await pumpFrames(tester, count: 20);

        final failedRows = (await msgRepo.getMessagesPage(group.id))
            .where((message) => message.text == 'Retry then edit restored text')
            .toList();
        expect(failedRows, hasLength(1));
        final failedRow = failedRows.single;
        expect(failedRow.status, 'failed');
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          isEmpty,
        );

        await tester.enterText(find.byType(TextField), 'Edited restored text');
        await tester.pump();

        final retryScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final retrySend = retryScreen.onSend as Future<void> Function(String);
        await tester.runAsync(() async {
          await retrySend('Edited restored text');
        });
        await pumpFrames(tester, count: 20);

        final originalRow = await msgRepo.getMessage(failedRow.id);
        expect(originalRow, isNotNull);
        expect(originalRow!.text, 'Retry then edit restored text');
        expect(originalRow.status, 'failed');

        final editedRows = (await msgRepo.getMessagesPage(
          group.id,
        )).where((message) => message.text == 'Edited restored text').toList();
        expect(editedRows, hasLength(1));
        final editedRow = editedRows.single;
        expect(editedRow.id, isNot(failedRow.id));
        expect(editedRow.status, 'sent');

        final publishPayloads = groupPublishPayloads(bridge);
        expect(publishPayloads, hasLength(2));
        expect(publishPayloads.first['messageId'], failedRow.id);
        expect(publishPayloads.first['text'], 'Retry then edit restored text');
        expect(publishPayloads.last['messageId'], editedRow.id);
        expect(publishPayloads.last['text'], 'Edited restored text');
      },
    );

    testWidgets(
      'GIRD-002 restored media composer continuation reuses the failed group row id',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        bridge = _SequentialGroupPublishBridge([
          {'ok': false, 'errorCode': 'PUBLISH_FAILED'},
          {'ok': true, 'messageId': 'retry-published', 'topicPeers': 1},
        ]);

        final tempDir = Directory.systemTemp.createTempSync(
          'gird002-restored-composer-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final attachment = File('${tempDir.path}/image.png')
          ..writeAsBytesSync(_tinyPngBytes);
        final mediaFileManager = FakeMediaFileManager();

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            initialAttachments: [attachment],
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                  deleteSourceWhenDone = false,
                  preparedArtifact,
                }) async => MediaAttachment(
                  id: blobId!,
                  messageId: '',
                  mime: mime,
                  size: _tinyPngBytes.length,
                  mediaType: MediaAttachment.mediaTypeFromMime(mime),
                  localPath: mediaFileManager?.relativePathForAttachment(
                    contactPeerId: group.id,
                    blobId: blobId,
                    mime: mime,
                  ),
                  downloadStatus: 'done',
                  contentHash: _validContentHash,
                  encryptionKeyBase64: 'key-fixture',
                  encryptionNonce: 'nonce-fixture',
                  encryptionScheme:
                      kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                  createdAt: DateTime.now().toUtc().toIso8601String(),
                ),
          ),
        );
        await pumpFrames(tester, count: 20);

        final firstScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final firstSend = firstScreen.onSend as Future<void> Function(String);
        await tester.runAsync(() async {
          await firstSend('GIRD-002 image retry');
        });
        await pumpFrames(tester, count: 20);

        final failedRows = (await msgRepo.getMessagesPage(
          group.id,
        )).where((message) => message.text == 'GIRD-002 image retry').toList();
        expect(failedRows, hasLength(1));
        final originalMessageId = failedRows.single.id;
        expect(failedRows.single.status, 'failed');
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller?.text,
          'GIRD-002 image retry',
        );

        final retryScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final retrySend = retryScreen.onSend as Future<void> Function(String);
        await tester.runAsync(() async {
          await retrySend('GIRD-002 image retry');
        });
        await pumpFrames(tester, count: 20);

        final storedRows = (await msgRepo.getMessagesPage(
          group.id,
        )).where((message) => message.text == 'GIRD-002 image retry').toList();
        expect(storedRows, hasLength(1));
        expect(storedRows.single.id, originalMessageId);
        expect(storedRows.single.status, 'sent');
        final publishMessageIds = bridge.sentMessages
            .map((raw) => jsonDecode(raw) as Map<String, dynamic>)
            .where((message) => message['cmd'] == 'group:publish')
            .map((message) {
              final payload = message['payload'] as Map<String, dynamic>;
              return payload['messageId'] as String?;
            })
            .toList();
        expect(publishMessageIds, [originalMessageId, originalMessageId]);
      },
    );

    testWidgets(
      'upload-pending failed voice retry uploads and publishes the same row immediately',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        final tempDir = Directory.systemTemp.createTempSync(
          'group-voice-upload-pending-retry-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final mediaFileManager = TrackingDurableMediaFileManager(tempDir);
        final voiceFile = File(
          p.join(
            tempDir.path,
            'pending_uploads',
            'msg-voice-upload-pending',
            'voice.m4a',
          ),
        );
        voiceFile.parent.createSync(recursive: true);
        voiceFile.writeAsBytesSync(_tinyMp4Bytes, flush: true);

        final timestamp = DateTime.utc(2026, 1, 15, 12, 3, 4);
        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-voice-upload-pending',
            text: '',
            groupId: group.id,
            isIncoming: false,
            senderPeerId: testIdentity.peerId,
            senderUsername: testIdentity.username,
            status: 'failed',
            timestamp: timestamp,
          ),
        );
        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-unrelated-pending-image',
            text: 'Still uploading image',
            groupId: group.id,
            isIncoming: false,
            senderPeerId: testIdentity.peerId,
            senderUsername: testIdentity.username,
            status: 'failed',
          ),
        );
        await mediaAttachmentRepo.saveAttachment(
          const MediaAttachment(
            id: 'att-voice-upload-pending',
            messageId: 'msg-voice-upload-pending',
            mime: 'audio/mp4',
            size: 16,
            mediaType: 'audio',
            localPath: 'pending_uploads/msg-voice-upload-pending/voice.m4a',
            downloadStatus: 'upload_pending',
            durationMs: 4100,
            waveform: [0.1, 0.6, 0.2],
            createdAt: '2026-01-15T12:03:04.000Z',
          ),
          owner: MediaOwnerLane.group,
        );
        await mediaAttachmentRepo.saveAttachment(
          const MediaAttachment(
            id: 'att-unrelated-pending-image',
            messageId: 'msg-unrelated-pending-image',
            mime: 'image/jpeg',
            size: 10,
            mediaType: 'image',
            localPath: 'pending_uploads/msg-unrelated-pending-image/image.jpg',
            downloadStatus: 'upload_pending',
            createdAt: '2026-01-15T12:04:00.000Z',
          ),
          owner: MediaOwnerLane.group,
        );

        var uploadCallCount = 0;
        String? uploadBlobId;
        int? uploadDurationMs;
        List<double>? uploadWaveform;
        List<String>? uploadAllowedPeers;

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                  deleteSourceWhenDone = false,
                  preparedArtifact,
                }) async {
                  uploadCallCount++;
                  uploadBlobId = blobId;
                  uploadDurationMs = durationMs;
                  uploadWaveform = List<double>.from(waveform!);
                  uploadAllowedPeers = List<String>.from(allowedPeers!);
                  return MediaAttachment(
                    id: blobId!,
                    messageId: '',
                    mime: mime,
                    size: _tinyMp4Bytes.length,
                    mediaType: MediaAttachment.mediaTypeFromMime(mime),
                    localPath: mediaFileManager?.relativePathForAttachment(
                      contactPeerId: group.id,
                      blobId: blobId,
                      mime: mime,
                    ),
                    downloadStatus: 'done',
                    contentHash: _validContentHash,
                    encryptionKeyBase64: 'key-fixture',
                    encryptionNonce: 'nonce-fixture',
                    encryptionScheme:
                        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                    durationMs: durationMs,
                    waveform: waveform,
                    createdAt: DateTime.now().toUtc().toIso8601String(),
                  );
                },
          ),
        );
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen.ownPeerId == testIdentity.peerId &&
              (screen.mediaMap['msg-voice-upload-pending']?.isNotEmpty ??
                  false);
        });

        final retryScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(retryScreen.onRetryFailedMedia, isNotNull);
        retryScreen.onRetryFailedMedia!('msg-voice-upload-pending');
        // E12 source qualification performs real async file I/O before the
        // manual lease/CAS. Let that work run outside the fake-async widget
        // clock, then render the committed result.
        await tester.runAsync(() async {
          for (var attempt = 0; attempt < 160; attempt++) {
            if ((await msgRepo.getMessage(
                  'msg-voice-upload-pending',
                ))?.status ==
                'sent') {
              return;
            }
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
        });
        await tester.pump();

        expect(uploadCallCount, 1);
        expect(uploadBlobId, 'att-voice-upload-pending');
        expect(uploadDurationMs, 4100);
        expect(uploadWaveform, [0.1, 0.6, 0.2]);
        expect(uploadAllowedPeers, [testIdentity.peerId, 'peer-bob']);
        expect(
          bridge.commandLog.where((cmd) => cmd == 'group:publish'),
          hasLength(1),
        );
        final publishPayloads = groupPublishPayloads(bridge);
        expect(publishPayloads, hasLength(1));
        expect(publishPayloads.single['messageId'], 'msg-voice-upload-pending');
        expect(
          publishPayloads.single['timestamp'],
          timestamp.toUtc().toIso8601String(),
        );

        final saved = await msgRepo.getMessage('msg-voice-upload-pending');
        expect(saved, isNotNull);
        expect(saved!.status, 'sent');
        expect(saved.timestamp, timestamp);
        final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
          'msg-voice-upload-pending',
          owner: MediaOwnerLane.group,
        );
        expect(attachments, hasLength(1));
        expect(attachments.single.id, 'att-voice-upload-pending');
        expect(attachments.single.downloadStatus, 'done');
        expect(attachments.single.durationMs, 4100);
        expect(attachments.single.waveform, [0.1, 0.6, 0.2]);
        expect(
          (await mediaAttachmentRepo.getAttachmentsForMessage(
            'msg-unrelated-pending-image',
            owner: MediaOwnerLane.group,
          )).single.downloadStatus,
          'upload_pending',
        );
        expect(
          find.text('Media upload is still finishing. It will retry soon.'),
          findsNothing,
        );
      },
    );

    testWidgets(
      'GIRD-002 upload-pending failed-card retry shows pending feedback without publishing',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        final mediaFileManager = FakeMediaFileManager();

        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-gird002-upload-pending',
            text: 'Still uploading',
            groupId: group.id,
            isIncoming: false,
            senderPeerId: testIdentity.peerId,
            senderUsername: testIdentity.username,
            status: 'failed',
          ),
        );
        await mediaAttachmentRepo.saveAttachment(
          const MediaAttachment(
            id: 'att-gird002-upload-pending',
            messageId: 'msg-gird002-upload-pending',
            mime: 'image/jpeg',
            size: 10,
            mediaType: 'image',
            localPath:
                'pending_uploads/msg-gird002-upload-pending/att-gird002.jpg',
            downloadStatus: 'upload_pending',
            createdAt: '2026-05-31T12:00:00.000Z',
          ),
          owner: MediaOwnerLane.group,
        );

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
          ),
        );
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen.ownPeerId == testIdentity.peerId &&
              (screen.mediaMap['msg-gird002-upload-pending']?.isNotEmpty ??
                  false);
        });

        final retryScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(retryScreen.onRetryFailedMedia, isNotNull);
        retryScreen.onRetryFailedMedia!('msg-gird002-upload-pending');
        await pumpFrames(tester, count: 10);

        expect(bridge.commandLog, isNot(contains('group:publish')));
        expect(
          (await msgRepo.getMessage('msg-gird002-upload-pending'))?.status,
          'failed',
        );
        expect(
          (await mediaAttachmentRepo.getAttachmentsForMessage(
            'msg-gird002-upload-pending',
            owner: MediaOwnerLane.group,
          )).single.downloadStatus,
          'upload_pending',
        );
        // 149: the upload-pending feedback moved INLINE — the MediaGridCell
        // upload-pending placeholder ("Uploading media") conveys it, so the
        // redundant transient snackbar is dropped.
        expect(
          find.text('Media upload is still finishing. It will retry soon.'),
          findsNothing,
        );
        expect(find.text('Uploading media'), findsOneWidget);
        expect(find.text('Could not retry media message.'), findsNothing);
      },
    );

    testWidgets(
      'GIRD-002 already-open group screen reflects resume retry status and media refresh',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        final mediaFileManager = FakeMediaFileManager();

        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-gird002-refresh',
            text: 'Resume refreshed media',
            groupId: group.id,
            isIncoming: false,
            senderPeerId: testIdentity.peerId,
            senderUsername: testIdentity.username,
            status: 'failed',
          ),
        );
        await mediaAttachmentRepo.saveAttachment(
          const MediaAttachment(
            id: 'att-gird002-refresh',
            messageId: 'msg-gird002-refresh',
            mime: 'image/jpeg',
            size: 10,
            mediaType: 'image',
            localPath: 'pending_uploads/msg-gird002-refresh/att.jpg',
            downloadStatus: 'upload_failed',
            createdAt: '2026-05-31T12:01:00.000Z',
          ),
          owner: MediaOwnerLane.group,
        );

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
          ),
        );
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen.messages.any(
                (message) =>
                    message.id == 'msg-gird002-refresh' &&
                    message.status == 'failed',
              ) &&
              (screen.mediaMap['msg-gird002-refresh']?.single.downloadStatus ==
                  'upload_failed');
        });

        final mediaPath = await mediaFileManager.localPathForAttachment(
          contactPeerId: group.id,
          blobId: 'att-gird002-refresh',
          mime: 'image/jpeg',
        );
        File(mediaPath).writeAsBytesSync(_tinyPngBytes, flush: true);
        final refreshedMessage = (await msgRepo.getMessage(
          'msg-gird002-refresh',
        ))!;
        await msgRepo.saveMessage(refreshedMessage.copyWith(status: 'sent'));
        await mediaAttachmentRepo.saveAttachment(
          MediaAttachment(
            id: 'att-gird002-refresh',
            messageId: 'msg-gird002-refresh',
            mime: 'image/jpeg',
            size: _tinyPngBytes.length,
            mediaType: 'image',
            localPath: mediaFileManager.relativePathForAttachment(
              contactPeerId: group.id,
              blobId: 'att-gird002-refresh',
              mime: 'image/jpeg',
            ),
            downloadStatus: 'done',
            contentHash: _validContentHash,
            encryptionKeyBase64: 'key-fixture',
            encryptionNonce: 'nonce-fixture',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            createdAt: '2026-05-31T12:02:00.000Z',
          ),
          owner: MediaOwnerLane.group,
        );

        await tester.runAsync(() async {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.pump();
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen.messages.any(
                (message) =>
                    message.id == 'msg-gird002-refresh' &&
                    message.status == 'sent',
              ) &&
              (screen.mediaMap['msg-gird002-refresh']?.single.downloadStatus ==
                  'done');
        });

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(
          screen.messages
              .singleWhere((message) => message.id == 'msg-gird002-refresh')
              .status,
          'sent',
        );
        expect(
          screen.mediaMap['msg-gird002-refresh']?.single.downloadStatus,
          'done',
        );
      },
    );

    testWidgets(
      'MD-012 retrying quarantined incoming media downloads only the targeted attachment',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        final mediaFileManager = FakeMediaFileManager();
        final repairedBytes = _md012EncryptedBytes(_tinyPngBytes);
        bridge = _DownloadRepairBridge(downloadedBytes: repairedBytes);

        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-md012-repair',
            text: 'repair incoming media',
            groupId: group.id,
            isIncoming: true,
            senderPeerId: 'peer-alice',
            senderUsername: 'Alice',
            status: 'delivered',
          ),
        );
        await mediaAttachmentRepo.saveAttachment(
          MediaAttachment(
            id: 'att-md012-target',
            messageId: 'msg-md012-repair',
            mime: 'image/png',
            size: _tinyPngBytes.length,
            mediaType: 'image',
            localPath: mediaFileManager.relativePathForAttachment(
              contactPeerId: group.id,
              blobId: 'att-md012-target',
              mime: 'image/png',
            ),
            downloadStatus: kMediaDownloadStatusIntegrityFailed,
            contentHash: _md012HashBytes(repairedBytes),
            encryptionKeyBase64: _md012MediaKey,
            encryptionNonce: _md012MediaNonce,
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            createdAt: '2026-04-29T12:00:00.000Z',
          ),
          owner: MediaOwnerLane.group,
        );
        await mediaAttachmentRepo.saveAttachment(
          const MediaAttachment(
            id: 'att-md012-sibling',
            messageId: 'msg-md012-repair',
            mime: 'image/png',
            size: 1,
            mediaType: 'image',
            downloadStatus: kMediaDownloadStatusIntegrityFailed,
            contentHash:
                'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
            encryptionKeyBase64: 'key-sibling',
            encryptionNonce: 'nonce-sibling',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            createdAt: '2026-04-29T12:00:00.000Z',
          ),
          owner: MediaOwnerLane.group,
        );

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
          ),
        );
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen.onRetryUnavailableMedia != null &&
              (screen.mediaMap['msg-md012-repair']?.length ?? 0) == 2;
        });

        final retryScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(retryScreen.onRetryUnavailableMedia, isNotNull);
        await tester.runAsync(() async {
          final result = Function.apply(retryScreen.onRetryUnavailableMedia!, [
            'msg-md012-repair',
            'att-md012-target',
          ]);
          if (result is Future<void>) await result;
        });
        await tester.pump();
        await pumpUntilAsync(tester, () async {
          final attachments = await mediaAttachmentRepo
              .getAttachmentsForMessage(
                'msg-md012-repair',
                owner: MediaOwnerLane.group,
              );
          return attachments
                  .where((attachment) => attachment.id == 'att-md012-target')
                  .single
                  .downloadStatus ==
              'done';
        }, maxPumps: 80);

        final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
          'msg-md012-repair',
          owner: MediaOwnerLane.group,
        );
        final target = attachments
            .where((attachment) => attachment.id == 'att-md012-target')
            .single;
        final sibling = attachments
            .where((attachment) => attachment.id == 'att-md012-sibling')
            .single;

        expect(target.downloadStatus, 'done');
        expect(target.localPath, isNotNull);
        expect(sibling.downloadStatus, kMediaDownloadStatusIntegrityFailed);
        expect(
          (await msgRepo.getMessage('msg-md012-repair'))?.status,
          'delivered',
        );
        expect(
          bridge.commandLog.where((cmd) => cmd == 'media:download'),
          hasLength(1),
        );
        expect(
          bridge.commandLog.where((cmd) => cmd == 'blob:decrypt'),
          hasLength(1),
        );
        expect(bridge.commandLog, isNot(contains('group:publish')));
        expect(bridge.commandLog, isNot(contains('group:inboxStore')));
      },
    );

    testWidgets(
      'MD-012 failed repair keeps media quarantined and clears unsafe file',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        final mediaFileManager = FakeMediaFileManager();
        final expectedBytes = _md012EncryptedBytes(_tinyPngBytes);
        final tamperedBytes = _md012EncryptedBytes('not a png'.codeUnits);
        bridge = _DownloadRepairBridge(downloadedBytes: tamperedBytes);
        final stalePath = await mediaFileManager.localPathForAttachment(
          contactPeerId: group.id,
          blobId: 'att-md012-fail',
          mime: 'image/png',
        );
        File(stalePath).writeAsBytesSync(<int>[9, 9, 9], flush: true);

        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-md012-fail',
            text: 'still unsafe',
            groupId: group.id,
            isIncoming: true,
            senderPeerId: 'peer-alice',
            senderUsername: 'Alice',
            status: 'delivered',
          ),
        );
        await mediaAttachmentRepo.saveAttachment(
          MediaAttachment(
            id: 'att-md012-fail',
            messageId: 'msg-md012-fail',
            mime: 'image/png',
            size: _tinyPngBytes.length,
            mediaType: 'image',
            localPath: mediaFileManager.relativePathForAttachment(
              contactPeerId: group.id,
              blobId: 'att-md012-fail',
              mime: 'image/png',
            ),
            downloadStatus: kMediaDownloadStatusIntegrityFailed,
            contentHash: _md012HashBytes(expectedBytes),
            encryptionKeyBase64: _md012MediaKey,
            encryptionNonce: _md012MediaNonce,
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            createdAt: '2026-04-29T12:00:00.000Z',
          ),
          owner: MediaOwnerLane.group,
        );

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
          ),
        );
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen.onRetryUnavailableMedia != null &&
              (screen.mediaMap['msg-md012-fail']?.isNotEmpty ?? false);
        });

        final retryScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(retryScreen.onRetryUnavailableMedia, isNotNull);
        await tester.runAsync(() async {
          final result = Function.apply(retryScreen.onRetryUnavailableMedia!, [
            'msg-md012-fail',
            'att-md012-fail',
          ]);
          if (result is Future<void>) await result;
        });
        await tester.pump();
        await pumpUntilAsync(tester, () async {
          if (!bridge.commandLog.contains('media:download')) return false;
          final attachments = await mediaAttachmentRepo
              .getAttachmentsForMessage(
                'msg-md012-fail',
                owner: MediaOwnerLane.group,
              );
          return attachments.single.downloadStatus ==
              kMediaDownloadStatusIntegrityFailed;
        }, maxPumps: 80);

        final attachment = (await mediaAttachmentRepo.getAttachmentsForMessage(
          'msg-md012-fail',
          owner: MediaOwnerLane.group,
        )).single;
        expect(attachment.downloadStatus, kMediaDownloadStatusIntegrityFailed);
        expect(attachment.localPath, isNull);
        expect(File(stalePath).existsSync(), isFalse);
        expect(
          bridge.commandLog.where((cmd) => cmd == 'media:download'),
          hasLength(1),
        );
        expect(bridge.commandLog, isNot(contains('group:publish')));
        expect(bridge.commandLog, isNot(contains('group:inboxStore')));
      },
    );

    testWidgets(
      'delete control removes only the targeted failed media row and owned files',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        final mediaFileManager = FakeMediaFileManager();

        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-delete-target',
            text: '',
            groupId: group.id,
            isIncoming: false,
            senderPeerId: testIdentity.peerId,
            senderUsername: testIdentity.username,
            status: 'failed',
            media: const [
              MediaAttachment(
                id: 'att-delete-target',
                messageId: 'msg-delete-target',
                mime: 'image/jpeg',
                size: 10,
                mediaType: 'image',
                localPath:
                    'pending_uploads/msg-delete-target/att-delete-target.jpg',
                downloadStatus: 'upload_pending',
                createdAt: '2026-01-15T12:02:00.000Z',
              ),
            ],
          ),
        );
        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-delete-untouched',
            text: '',
            groupId: group.id,
            isIncoming: false,
            senderPeerId: testIdentity.peerId,
            senderUsername: testIdentity.username,
            status: 'failed',
            media: const [
              MediaAttachment(
                id: 'att-delete-untouched',
                messageId: 'msg-delete-untouched',
                mime: 'image/jpeg',
                size: 10,
                mediaType: 'image',
                localPath:
                    'pending_uploads/msg-delete-untouched/att-delete-untouched.jpg',
                downloadStatus: 'upload_pending',
                createdAt: '2026-01-15T12:03:00.000Z',
              ),
            ],
          ),
        );
        await mediaAttachmentRepo.saveAttachment(
          const MediaAttachment(
            id: 'att-delete-target',
            messageId: 'msg-delete-target',
            mime: 'image/jpeg',
            size: 10,
            mediaType: 'image',
            localPath:
                'pending_uploads/msg-delete-target/att-delete-target.jpg',
            downloadStatus: 'upload_pending',
            createdAt: '2026-01-15T12:02:00.000Z',
          ),
          owner: MediaOwnerLane.group,
        );
        await mediaAttachmentRepo.saveAttachment(
          const MediaAttachment(
            id: 'att-delete-untouched',
            messageId: 'msg-delete-untouched',
            mime: 'image/jpeg',
            size: 10,
            mediaType: 'image',
            localPath:
                'pending_uploads/msg-delete-untouched/att-delete-untouched.jpg',
            downloadStatus: 'upload_pending',
            createdAt: '2026-01-15T12:03:00.000Z',
          ),
          owner: MediaOwnerLane.group,
        );

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
          ),
        );
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen.ownPeerId == testIdentity.peerId &&
              (screen.mediaMap['msg-delete-target']?.isNotEmpty ?? false);
        });

        final deleteScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(deleteScreen.ownPeerId, testIdentity.peerId);
        expect(deleteScreen.onDeleteFailedMedia, isNotNull);
        expect(deleteScreen.mediaMap['msg-delete-target'], isNotEmpty);

        deleteScreen.onDeleteFailedMedia!('msg-delete-target');
        await tester.pump(const Duration(milliseconds: 300));

        expect(await msgRepo.getMessage('msg-delete-target'), isNull);
        expect(await msgRepo.getMessage('msg-delete-untouched'), isNotNull);
        expect(
          await mediaAttachmentRepo.getAttachmentsForMessage(
            'msg-delete-target',
            owner: MediaOwnerLane.group,
          ),
          isEmpty,
        );
        expect(
          await mediaAttachmentRepo.getAttachmentsForMessage(
            'msg-delete-untouched',
            owner: MediaOwnerLane.group,
          ),
          hasLength(1),
        );
        expect(
          mediaFileManager.deletedFilePaths,
          contains(
            endsWith('pending_uploads/msg-delete-target/att-delete-target.jpg'),
          ),
        );
        expect(
          mediaFileManager.deletedFilePaths,
          isNot(
            contains(
              endsWith(
                'pending_uploads/msg-delete-untouched/att-delete-untouched.jpg',
              ),
            ),
          ),
        );
      },
    );

    testWidgets(
      'failed group media cleanup preserves same id direct and unresolved media',
      (tester) async {
        // 228 TC-228-11W: a DIRECT message can legally share this group
        // message's id. The failed-media delete workflow removes ONLY
        // group-owned rows/files — the same-ID direct sibling row and its
        // file survive. NOTE: the in-memory fake stamps a lane on every
        // save/seed, so it cannot hold a raw owner_lane='unresolved' row;
        // unresolved-row preservation for this workflow is proven at the DB
        // tier (media_attachments_db_helpers_test.dart) — this test covers
        // the direct-sibling half.
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        final mediaFileManager = FakeMediaFileManager();

        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-collide-cleanup',
            text: '',
            groupId: group.id,
            isIncoming: false,
            senderPeerId: testIdentity.peerId,
            senderUsername: testIdentity.username,
            status: 'failed',
            media: const [
              MediaAttachment(
                id: 'att-collide-group',
                messageId: 'msg-collide-cleanup',
                mime: 'image/jpeg',
                size: 10,
                mediaType: 'image',
                localPath:
                    'pending_uploads/msg-collide-cleanup/att-collide-group.jpg',
                downloadStatus: 'upload_pending',
                createdAt: '2026-01-15T12:02:00.000Z',
              ),
            ],
          ),
        );
        await mediaAttachmentRepo.saveAttachment(
          const MediaAttachment(
            id: 'att-collide-group',
            messageId: 'msg-collide-cleanup',
            mime: 'image/jpeg',
            size: 10,
            mediaType: 'image',
            localPath:
                'pending_uploads/msg-collide-cleanup/att-collide-group.jpg',
            downloadStatus: 'upload_pending',
            createdAt: '2026-01-15T12:02:00.000Z',
          ),
          owner: MediaOwnerLane.group,
        );
        // Same-ID sibling in the DIRECT lane with its own file path.
        await mediaAttachmentRepo.saveAttachment(
          const MediaAttachment(
            id: 'att-collide-direct',
            messageId: 'msg-collide-cleanup',
            mime: 'image/jpeg',
            size: 10,
            mediaType: 'image',
            localPath:
                'pending_uploads/msg-collide-cleanup/att-collide-direct.jpg',
            downloadStatus: 'upload_pending',
            createdAt: '2026-01-15T12:03:00.000Z',
          ),
          owner: MediaOwnerLane.direct,
        );

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
          ),
        );
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen.ownPeerId == testIdentity.peerId &&
              (screen.mediaMap['msg-collide-cleanup']?.isNotEmpty ?? false);
        });

        final deleteScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(deleteScreen.onDeleteFailedMedia, isNotNull);

        deleteScreen.onDeleteFailedMedia!('msg-collide-cleanup');
        await tester.pump(const Duration(milliseconds: 300));

        // Group-owned artifacts are removed.
        expect(await msgRepo.getMessage('msg-collide-cleanup'), isNull);
        expect(
          await mediaAttachmentRepo.getAttachmentsForMessage(
            'msg-collide-cleanup',
            owner: MediaOwnerLane.group,
          ),
          isEmpty,
        );
        expect(
          mediaFileManager.deletedFilePaths,
          contains(
            endsWith(
              'pending_uploads/msg-collide-cleanup/att-collide-group.jpg',
            ),
          ),
        );

        // The same-ID direct sibling row and its file survive.
        final directSiblings = await mediaAttachmentRepo
            .getAttachmentsForMessage(
              'msg-collide-cleanup',
              owner: MediaOwnerLane.direct,
            );
        expect(directSiblings.single.id, 'att-collide-direct');
        expect(directSiblings.single.downloadStatus, 'upload_pending');
        expect(
          mediaFileManager.deletedFilePaths,
          isNot(
            contains(
              endsWith(
                'pending_uploads/msg-collide-cleanup/att-collide-direct.jpg',
              ),
            ),
          ),
        );
      },
    );

    testWidgets('publish failure restores quote draft and attachments', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      await saveActiveGroupMembers(groupRepo, group);
      await msgRepo.saveMessage(
        makeMessage(
          id: 'msg-parent-publish',
          text: 'Publish parent',
          groupId: group.id,
          isIncoming: true,
        ),
      );

      bridge = FakeBridge(
        initialResponses: {
          'group:publish': {'ok': false, 'errorCode': 'PUBLISH_FAILED'},
        },
      );

      final tempDir = Directory.systemTemp.createTempSync(
        'group_retry_publish_',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final attachment = File('${tempDir.path}/retry.jpg')
        ..writeAsStringSync('image');

      await tester.pumpWidget(
        buildWidget(
          group: group,
          uploadMediaFn:
              ({
                required bridge,
                required localFilePath,
                required mime,
                required recipientPeerId,
                String? blobId,
                mediaFileManager,
                width,
                height,
                durationMs,
                waveform,
                allowedPeers,
                deleteSourceWhenDone = false,
                preparedArtifact,
              }) async => MediaAttachment(
                id: 'uploaded-group-1',
                messageId: '',
                mime: mime,
                size: 1,
                mediaType: MediaAttachment.mediaTypeFromMime(mime),
                localPath: localFilePath,
                downloadStatus: 'done',
                contentHash: _validContentHash,
                encryptionKeyBase64: 'key-fixture',
                encryptionNonce: 'nonce-fixture',
                encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                createdAt: DateTime.now().toUtc().toIso8601String(),
              ),
          initialAttachments: [attachment],
        ),
      );
      await pumpFrames(tester, count: 20);

      final screen = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      screen.onQuoteReply!.call('msg-parent-publish');
      await tester.pump();

      await tester.enterText(find.byType(TextField), 'Retry publish');
      await pumpFrames(tester);
      await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
      await pumpFrames(tester, count: 20);

      expect(find.byType(AttachmentPreviewStrip), findsOneWidget);
      expect(find.text('Replying to'), findsOneWidget);
      expect(find.text('Publish parent'), findsWidgets);
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller?.text,
        'Retry publish',
      );
    });

    // -----------------------------------------------------------------------
    // Voice message tests
    //
    // NOTE: uploadMedia() uses real File I/O (File.length()) which does not
    // complete inside Flutter's FakeAsync zone. Full upload→publish flow is
    // tested at the use case level in send_group_message_use_case_test.dart.
    // These tests verify the optimistic UI pattern and quote restoration
    // behavior added in _onRecordStop.
    // -----------------------------------------------------------------------

    testWidgets(
      'voice send path stays hidden unless both durable media dependencies exist',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        final recorder = FakeAudioRecorderService();
        final uiGateDir = Directory.systemTemp.createTempSync(
          'group-voice-ui-gate-',
        );
        addTearDown(() {
          if (uiGateDir.existsSync()) {
            uiGateDir.deleteSync(recursive: true);
          }
        });

        await tester.pumpWidget(
          buildWidget(
            group: group,
            audioRecorderService: recorder,
            mediaRepo: mediaAttachmentRepo,
          ),
        );
        await pumpFrames(tester, count: 10);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.onRecordStart, isNull);
        expect(screen.onRecordStop, isNull);
        expect(find.byIcon(Icons.mic_rounded), findsNothing);

        await tester.pumpWidget(
          buildWidget(
            group: group,
            audioRecorderService: recorder,
            mediaFileManager: TrackingDurableMediaFileManager(uiGateDir),
          ),
        );
        await pumpFrames(tester, count: 10);

        final screenWithoutRepo = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screenWithoutRepo.onRecordStart, isNull);
        expect(screenWithoutRepo.onRecordStop, isNull);
        expect(find.byIcon(Icons.mic_rounded), findsNothing);
      },
    );

    testWidgets(
      'voice stop pre-persists a durable pending attachment and threads a stable blob ID',
      (tester) async {
        mediaUploadInFlightTracker.clearAll();
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        final tempDir = Directory.systemTemp.createTempSync(
          'group-voice-durable-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final tempVoice = File(p.join(tempDir.path, 'voice.m4a'))
          ..writeAsStringSync('voice');

        final mediaFileManager = TrackingDurableMediaFileManager(tempDir);
        final recorder = FakeAudioRecorderService()
          ..fakeDurationMs = 3200
          ..fakeSizeBytes = 48000
          ..fakeOutputPath = tempVoice.path;
        final uploadGate = Completer<void>();
        final uploadStarted = Completer<void>();
        String? receivedBlobId;
        String? receivedLocalPath;
        bool? ownedAtFirstDurableVisibility;
        MediaUploadLease? competingLease;
        mediaAttachmentRepo.onSaveAttachment = (attachment) {
          if (attachment.downloadStatus != 'upload_pending' ||
              ownedAtFirstDurableVisibility != null) {
            return;
          }
          ownedAtFirstDurableVisibility = mediaUploadInFlightTracker.isInFlight(
            attachment.id,
          );
          competingLease = mediaUploadInFlightTracker.tryClaimAll(<String>[
            attachment.id,
          ], source: MediaUploadTriggerSource.periodic);
        };
        addTearDown(() {
          final lease = competingLease;
          if (lease != null) mediaUploadInFlightTracker.release(lease);
          mediaUploadInFlightTracker.clearAll();
        });

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            audioRecorderService: recorder,
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                  deleteSourceWhenDone = false,
                  preparedArtifact,
                }) async {
                  receivedBlobId = blobId;
                  receivedLocalPath = localFilePath;
                  if (!uploadStarted.isCompleted) {
                    uploadStarted.complete();
                  }
                  await uploadGate.future;
                  return MediaAttachment(
                    id: 'server-voice-success',
                    messageId: '',
                    mime: mime,
                    size: 1,
                    mediaType: MediaAttachment.mediaTypeFromMime(mime),
                    localPath: mediaFileManager?.relativePathForAttachment(
                      contactPeerId: group.id,
                      blobId: blobId!,
                      mime: mime,
                    ),
                    downloadStatus: 'done',
                    contentHash: _validContentHash,
                    encryptionKeyBase64: 'key-fixture',
                    encryptionNonce: 'nonce-fixture',
                    encryptionScheme:
                        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                    durationMs: durationMs,
                    waveform: waveform,
                    createdAt: DateTime.now().toUtc().toIso8601String(),
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        await (screen.onRecordStart! as Future<void> Function())();
        await pumpUntil(
          tester,
          () => find.byIcon(Icons.stop_rounded).evaluate().isNotEmpty,
        );

        recorder.emitAmplitude(0.15);
        recorder.emitAmplitude(0.55);
        recorder.emitAmplitude(0.25);

        final recordingScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final stopRecording =
            recordingScreen.onRecordStop! as Future<void> Function();
        late Future<void> stopFuture;
        await tester.runAsync(() async {
          stopFuture = stopRecording();
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.runAsync(() async {
          await uploadStarted.future.timeout(_uploadStartCeiling);
        });
        await pumpFrames(tester, count: 5);

        expect(mediaFileManager.copyCalls, 1);
        expect(receivedBlobId, isNotNull);
        expect(
          receivedLocalPath,
          startsWith(p.join(tempDir.path, 'pending_uploads')),
        );

        final pending = await mediaAttachmentRepo.getUploadPendingAttachments(
          owner: MediaOwnerLane.group,
        );
        expect(pending, hasLength(1));
        expect(pending.single.id, receivedBlobId);
        expect(pending.single.downloadStatus, 'upload_pending');
        expect(pending.single.localPath, isNotNull);
        expect(pending.single.localPath, startsWith('pending_uploads/'));
        expect(ownedAtFirstDurableVisibility, isTrue);
        expect(competingLease, isNull);

        final refreshedScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final optimisticMessage = refreshedScreen.messages.singleWhere(
          (message) => message.status == 'sending' && message.text.isEmpty,
        );
        final optimisticAttachment =
            refreshedScreen.mediaMap[optimisticMessage.id]!.single;
        expect(optimisticAttachment.id, receivedBlobId);
        expect(optimisticAttachment.localPath, isNotNull);
        expect(
          optimisticAttachment.localPath,
          startsWith(p.join(tempDir.path, 'pending_uploads')),
        );

        uploadGate.complete();
        await tester.runAsync(() async {
          await stopFuture;
        });
        await pumpFrames(tester, count: 20);
        expect(mediaUploadInFlightTracker.inFlightCount, 0);
      },
    );

    testWidgets(
      'voice upload failure keeps upload_pending retry data and restores the quote',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-parent-voice-upload',
            text: 'Voice upload parent',
            groupId: group.id,
            isIncoming: true,
          ),
        );
        final tempDir = Directory.systemTemp.createTempSync(
          'group-voice-upload-fail-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final tempVoice = File(p.join(tempDir.path, 'voice.m4a'))
          ..writeAsStringSync('voice');

        final mediaFileManager = TrackingDurableMediaFileManager(tempDir);
        final recorder = FakeAudioRecorderService()
          ..fakeDurationMs = 2800
          ..fakeSizeBytes = 44100
          ..fakeOutputPath = tempVoice.path;
        final uploadGate = Completer<void>();
        final uploadStarted = Completer<void>();
        String? receivedBlobId;
        String? receivedLocalPath;

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            audioRecorderService: recorder,
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                  deleteSourceWhenDone = false,
                  preparedArtifact,
                }) async {
                  receivedBlobId = blobId;
                  receivedLocalPath = localFilePath;
                  if (!uploadStarted.isCompleted) {
                    uploadStarted.complete();
                  }
                  await uploadGate.future;
                  return null;
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        screen.onQuoteReply!.call('msg-parent-voice-upload');
        await tester.pump();
        expect(find.text('Replying to'), findsOneWidget);

        await (screen.onRecordStart! as Future<void> Function())();
        await pumpUntil(
          tester,
          () => find.byIcon(Icons.stop_rounded).evaluate().isNotEmpty,
        );
        recorder.emitAmplitude(0.15);
        recorder.emitAmplitude(0.55);

        final recordingScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final stopRecording =
            recordingScreen.onRecordStop! as Future<void> Function();
        late Future<void> stopFuture;
        await tester.runAsync(() async {
          stopFuture = stopRecording();
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.runAsync(() async {
          await uploadStarted.future.timeout(_uploadStartCeiling);
        });
        await pumpFrames(tester, count: 5);

        expect(mediaFileManager.copyCalls, 1);
        expect(receivedBlobId, isNotNull);
        expect(
          receivedLocalPath,
          startsWith(p.join(tempDir.path, 'pending_uploads')),
        );

        final pendingBeforeFail = await mediaAttachmentRepo
            .getUploadPendingAttachments(owner: MediaOwnerLane.group);
        expect(pendingBeforeFail, hasLength(1));
        expect(pendingBeforeFail.single.id, receivedBlobId);
        expect(pendingBeforeFail.single.downloadStatus, 'upload_pending');
        expect(pendingBeforeFail.single.durationMs, 2800);
        expect(pendingBeforeFail.single.waveform, isNotNull);
        expect(pendingBeforeFail.single.waveform, isNotEmpty);

        final refreshedScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final optimisticMessage = refreshedScreen.messages.singleWhere(
          (message) => message.status == 'sending' && message.text.isEmpty,
        );
        final optimisticAttachment =
            refreshedScreen.mediaMap[optimisticMessage.id]!.single;
        expect(optimisticAttachment.id, receivedBlobId);
        expect(
          optimisticAttachment.localPath,
          startsWith(p.join(tempDir.path, 'pending_uploads')),
        );

        uploadGate.complete();
        await tester.runAsync(() async {
          await stopFuture;
        });
        await pumpFrames(tester, count: 20);

        final failedScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final failedMessage = failedScreen.messages.singleWhere(
          (message) => message.status == 'failed' && message.text.isEmpty,
        );
        expect(failedMessage.quotedMessageId, 'msg-parent-voice-upload');
        expect(find.text('Replying to'), findsOneWidget);

        final pendingAfterFail = await mediaAttachmentRepo
            .getUploadPendingAttachments(owner: MediaOwnerLane.group);
        expect(pendingAfterFail, hasLength(1));
        expect(pendingAfterFail.single.id, receivedBlobId);
        expect(pendingAfterFail.single.downloadStatus, 'upload_pending');
      },
    );

    testWidgets(
      'voice durable prep failure leaves no empty failed row or pending upload dir',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-parent-voice-prep',
            text: 'Voice prep parent',
            groupId: group.id,
            isIncoming: true,
          ),
        );
        final tempDir = Directory.systemTemp.createTempSync(
          'group-voice-prep-fail-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final tempVoice = File(p.join(tempDir.path, 'voice.m4a'))
          ..writeAsStringSync('voice');
        final mediaFileManager = ThrowingAfterCopyDurableMediaFileManager(
          tempDir,
        );
        final recorder = FakeAudioRecorderService()
          ..fakeDurationMs = 2800
          ..fakeSizeBytes = 44100
          ..fakeOutputPath = tempVoice.path;

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            audioRecorderService: recorder,
          ),
        );
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        screen.onQuoteReply!.call('msg-parent-voice-prep');
        await tester.pump();
        expect(find.text('Replying to'), findsOneWidget);

        await (screen.onRecordStart! as Future<void> Function())();
        await pumpUntil(
          tester,
          () => find.byIcon(Icons.stop_rounded).evaluate().isNotEmpty,
        );
        final recordingScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        await tester.runAsync(() async {
          await (recordingScreen.onRecordStop! as Future<void> Function())();
        });
        await pumpFrames(tester, count: 20);

        final messages = await msgRepo.getMessagesPage(group.id);
        expect(messages.map((message) => message.id), [
          'msg-parent-voice-prep',
        ]);
        expect(
          await mediaAttachmentRepo.getUploadPendingAttachments(
            owner: MediaOwnerLane.group,
          ),
          isEmpty,
        );
        expect(mediaAttachmentRepo.count, 0);
        expect(mediaFileManager.deletedPendingUploadDirs, hasLength(1));
        final pendingRoot = Directory(p.join(tempDir.path, 'pending_uploads'));
        if (pendingRoot.existsSync()) {
          expect(pendingRoot.listSync(recursive: true), isEmpty);
        }
        final settledScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(settledScreen.isSending, isFalse);
        expect(find.text('Replying to'), findsOneWidget);
        expect(bridge.commandLog, isNot(contains('group:publish')));
      },
    );

    testWidgets(
      'PL-005 voice media upload allowedPeers match active membership at upload time',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: testIdentity.peerId,
            username: testIdentity.username,
            role: MemberRole.admin,
            publicKey: testIdentity.publicKey,
            mlKemPublicKey: testIdentity.mlKemPublicKey,
            joinedAt: DateTime.utc(2026, 5, 14, 10),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: 'peer-bob',
            username: 'Bob',
            role: MemberRole.writer,
            publicKey: 'pk-peer-bob',
            mlKemPublicKey: 'mlkem-peer-bob',
            joinedAt: DateTime.utc(2026, 5, 14, 10, 1),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: 'peer-charlie',
            username: 'Charlie',
            role: MemberRole.writer,
            publicKey: 'pk-peer-charlie',
            mlKemPublicKey: 'mlkem-peer-charlie',
            joinedAt: DateTime.utc(2026, 5, 14, 10, 2),
          ),
        );
        await groupRepo.removeMember(group.id, 'peer-charlie');

        final tempDir = Directory.systemTemp.createTempSync(
          'pl005-group-voice-acl-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final tempVoice = File(p.join(tempDir.path, 'voice.m4a'))
          ..writeAsStringSync('voice');
        final recorder = FakeAudioRecorderService()
          ..fakeDurationMs = 1800
          ..fakeSizeBytes = 32000
          ..fakeOutputPath = tempVoice.path;
        final capturedAllowedPeers = <List<String>>[];

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: TrackingDurableMediaFileManager(tempDir),
            audioRecorderService: recorder,
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                  deleteSourceWhenDone = false,
                  preparedArtifact,
                }) async {
                  capturedAllowedPeers.add(List<String>.from(allowedPeers!));
                  return MediaAttachment(
                    id: blobId!,
                    messageId: '',
                    mime: mime,
                    size: 1,
                    mediaType: MediaAttachment.mediaTypeFromMime(mime),
                    localPath: localFilePath,
                    downloadStatus: 'done',
                    contentHash: _validContentHash,
                    encryptionKeyBase64: 'key-fixture',
                    encryptionNonce: 'nonce-fixture',
                    encryptionScheme:
                        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                    durationMs: durationMs,
                    waveform: waveform,
                    createdAt: DateTime.now().toUtc().toIso8601String(),
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        await (screen.onRecordStart! as Future<void> Function())();
        await pumpUntil(
          tester,
          () => find.byIcon(Icons.stop_rounded).evaluate().isNotEmpty,
        );
        final recordingScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        await tester.runAsync(() async {
          await (recordingScreen.onRecordStop! as Future<void> Function())();
        });
        await pumpFrames(tester, count: 20);

        expect(capturedAllowedPeers, hasLength(1));
        expect(capturedAllowedPeers.single, [testIdentity.peerId, 'peer-bob']);
        expect(capturedAllowedPeers.single, isNot(contains('peer-charlie')));
        expect(capturedAllowedPeers.single, isNot(contains('peer-dave')));
      },
    );

    testWidgets(
      'voice re-record after retryable publish failure reuses the failed row id',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        bridge = _SequentialGroupPublishBridge([
          {'ok': false, 'errorCode': 'PUBLISH_FAILED'},
          {
            'ok': true,
            'messageId': 'voice-rerecord-published',
            'topicPeers': 1,
          },
        ]);
        final tempDir = Directory.systemTemp.createTempSync(
          'group-voice-rerecord-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final firstVoice = File(p.join(tempDir.path, 'voice-first.m4a'))
          ..writeAsStringSync('first voice');
        final secondVoice = File(p.join(tempDir.path, 'voice-second.m4a'))
          ..writeAsStringSync('second voice');
        final mediaFileManager = TrackingDurableMediaFileManager(tempDir);
        final recorder = FakeAudioRecorderService()
          ..fakeDurationMs = 3100
          ..fakeSizeBytes = 46000
          ..fakeOutputPath = firstVoice.path;
        final uploadedBlobIds = <String>[];

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            audioRecorderService: recorder,
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                  deleteSourceWhenDone = false,
                  preparedArtifact,
                }) async {
                  uploadedBlobIds.add(blobId!);
                  return MediaAttachment(
                    id: blobId,
                    messageId: '',
                    mime: mime,
                    size: 1,
                    mediaType: MediaAttachment.mediaTypeFromMime(mime),
                    localPath: mediaFileManager?.relativePathForAttachment(
                      contactPeerId: group.id,
                      blobId: blobId,
                      mime: mime,
                    ),
                    downloadStatus: 'done',
                    contentHash: _validContentHash,
                    encryptionKeyBase64: 'key-fixture',
                    encryptionNonce: 'nonce-fixture',
                    encryptionScheme:
                        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                    durationMs: durationMs,
                    waveform: waveform,
                    createdAt: DateTime.now().toUtc().toIso8601String(),
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        Future<void> recordVoice() async {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          await (screen.onRecordStart! as Future<void> Function())();
          await pumpUntil(
            tester,
            () => find.byIcon(Icons.stop_rounded).evaluate().isNotEmpty,
          );
          final recordingScreen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          await tester.runAsync(() async {
            await (recordingScreen.onRecordStop! as Future<void> Function())();
          });
          await pumpFrames(tester, count: 20);
        }

        await recordVoice();
        final failedRows = (await msgRepo.getMessagesPage(group.id))
            .where((message) => !message.isIncoming && message.text.isEmpty)
            .toList();
        expect(failedRows, hasLength(1));
        final failedRow = failedRows.single;
        expect(failedRow.status, 'failed');
        final failedAttachments = await mediaAttachmentRepo
            .getAttachmentsForMessage(
              failedRow.id,
              owner: MediaOwnerLane.group,
            );
        expect(failedAttachments, hasLength(1));
        expect(failedAttachments.single.downloadStatus, 'done');
        final firstBlobId = failedAttachments.single.id;

        recorder.fakeOutputPath = secondVoice.path;
        await recordVoice();

        final storedRows = (await msgRepo.getMessagesPage(group.id))
            .where((message) => !message.isIncoming && message.text.isEmpty)
            .toList();
        expect(storedRows, hasLength(1));
        final storedRow = storedRows.single;
        expect(storedRow.id, failedRow.id);
        expect(storedRow.timestamp, failedRow.timestamp);
        expect(storedRow.status, 'sent');

        final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
          failedRow.id,
          owner: MediaOwnerLane.group,
        );
        expect(attachments, hasLength(1));
        expect(attachments.single.id, uploadedBlobIds.last);
        expect(attachments.single.id, isNot(firstBlobId));
        expect(attachments.single.downloadStatus, 'done');

        final publishPayloads = groupPublishPayloads(bridge);
        expect(publishPayloads, hasLength(2));
        expect(
          publishPayloads.map((payload) => payload['messageId']).toList(),
          [failedRow.id, failedRow.id],
        );
        expect(
          publishPayloads.map((payload) => payload['timestamp']).toList(),
          [
            failedRow.timestamp.toUtc().toIso8601String(),
            failedRow.timestamp.toUtc().toIso8601String(),
          ],
        );
      },
    );

    testWidgets(
      'successful voice send uses the durable copy, cleans pending uploads, and survives temp deletion',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        final tempDir = Directory.systemTemp.createTempSync(
          'group-voice-success-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final tempVoice = File(p.join(tempDir.path, 'voice.m4a'))
          ..writeAsStringSync('voice');

        final mediaFileManager = TrackingDurableMediaFileManager(tempDir);
        final recorder = FakeAudioRecorderService()
          ..fakeDurationMs = 3100
          ..fakeSizeBytes = 46000
          ..fakeOutputPath = tempVoice.path;
        final uploadGate = Completer<void>();
        final uploadStarted = Completer<void>();
        String? receivedBlobId;
        String? receivedLocalPath;

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            audioRecorderService: recorder,
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                  deleteSourceWhenDone = false,
                  preparedArtifact,
                }) async {
                  receivedBlobId = blobId;
                  receivedLocalPath = localFilePath;
                  if (!uploadStarted.isCompleted) {
                    uploadStarted.complete();
                  }
                  expect(
                    File(tempVoice.path).existsSync(),
                    isFalse,
                    reason:
                        'temp source file should no longer matter after durable copy',
                  );
                  await uploadGate.future;
                  return MediaAttachment(
                    id: blobId!,
                    messageId: '',
                    mime: mime,
                    size: 1,
                    mediaType: MediaAttachment.mediaTypeFromMime(mime),
                    localPath: mediaFileManager?.relativePathForAttachment(
                      contactPeerId: group.id,
                      blobId: blobId,
                      mime: mime,
                    ),
                    downloadStatus: 'done',
                    contentHash: _validContentHash,
                    encryptionKeyBase64: 'key-fixture',
                    encryptionNonce: 'nonce-fixture',
                    encryptionScheme:
                        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                    durationMs: durationMs,
                    waveform: waveform,
                    createdAt: DateTime.now().toUtc().toIso8601String(),
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        await (screen.onRecordStart! as Future<void> Function())();
        await pumpUntil(
          tester,
          () => find.byIcon(Icons.stop_rounded).evaluate().isNotEmpty,
        );
        recorder.emitAmplitude(0.1);
        recorder.emitAmplitude(0.4);
        recorder.emitAmplitude(0.2);

        final recordingScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final stopRecording =
            recordingScreen.onRecordStop! as Future<void> Function();
        late Future<void> stopFuture;
        await tester.runAsync(() async {
          stopFuture = stopRecording();
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.runAsync(() async {
          await uploadStarted.future.timeout(_uploadStartCeiling);
        });
        await pumpFrames(tester, count: 5);

        expect(mediaFileManager.copyCalls, 1);
        expect(receivedBlobId, isNotNull);
        expect(
          receivedLocalPath,
          startsWith(p.join(tempDir.path, 'pending_uploads')),
        );

        final pending = await mediaAttachmentRepo.getUploadPendingAttachments(
          owner: MediaOwnerLane.group,
        );
        expect(pending, hasLength(1));
        expect(pending.single.id, receivedBlobId);
        expect(pending.single.localPath, startsWith('pending_uploads/'));

        final optimisticScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final optimisticMessage = optimisticScreen.messages.singleWhere(
          (message) => message.status == 'sending' && message.text.isEmpty,
        );
        final optimisticAttachment =
            optimisticScreen.mediaMap[optimisticMessage.id]!.single;
        expect(optimisticAttachment.id, receivedBlobId);
        expect(
          optimisticAttachment.localPath,
          startsWith(p.join(tempDir.path, 'pending_uploads')),
        );

        uploadGate.complete();
        await tester.runAsync(() async {
          await stopFuture;
        });
        await pumpFrames(tester, count: 20);

        final savedMessage = await msgRepo.getLatestMessage(group.id);
        expect(savedMessage, isNotNull);
        final messageId = savedMessage!.id;
        expect(savedMessage.privateMediaPolicy.isOrdinary, isTrue);
        expect(mediaFileManager.deletedPendingUploadDirs, contains(messageId));
        final savedAttachments = await mediaAttachmentRepo
            .getAttachmentsForMessage(messageId, owner: MediaOwnerLane.group);
        expect(savedAttachments, hasLength(1));
        expect(savedAttachments.single.id, receivedBlobId);
        expect(savedAttachments.single.downloadStatus, 'done');
        expect(savedAttachments.single.localPath, startsWith('media/'));
        expect(
          await mediaAttachmentRepo.getUploadPendingAttachments(
            owner: MediaOwnerLane.group,
          ),
          isEmpty,
        );
        expectNoGroupPrivateWireKeys([
          (
            boundary: 'voice reliable',
            payload: groupSendReliablePayloadForMessage(bridge, messageId),
          ),
          (
            boundary: 'voice publish',
            payload: groupPublishPayloadForMessage(bridge, messageId),
          ),
          (
            boundary: 'voice replay',
            payload: groupReplayPlaintextForMessage(bridge, messageId),
          ),
        ]);
      },
    );

    testWidgets(
      'voice record stop keeps the optimistic voice row caller-local until upload completes',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        final tempDir = Directory.systemTemp.createTempSync(
          'group-voice-caller-local-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final tempVoice = File(p.join(tempDir.path, 'voice.m4a'))
          ..writeAsStringSync('voice');
        final mediaFileManager = TrackingDurableMediaFileManager(tempDir);
        final recorder = FakeAudioRecorderService()
          ..fakeDurationMs = 3000
          ..fakeSizeBytes = 48000
          ..fakeOutputPath = tempVoice.path;
        final uploadGate = Completer<void>();
        final uploadStarted = Completer<void>();

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            audioRecorderService: recorder,
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                  deleteSourceWhenDone = false,
                  preparedArtifact,
                }) async {
                  if (!uploadStarted.isCompleted) {
                    uploadStarted.complete();
                  }
                  await uploadGate.future;
                  return MediaAttachment(
                    id: 'uploaded-voice-gated',
                    messageId: '',
                    mime: mime,
                    size: 1,
                    mediaType: MediaAttachment.mediaTypeFromMime(mime),
                    localPath: localFilePath,
                    downloadStatus: 'done',
                    contentHash: _validContentHash,
                    encryptionKeyBase64: 'key-fixture',
                    encryptionNonce: 'nonce-fixture',
                    encryptionScheme:
                        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                    durationMs: durationMs,
                    waveform: waveform,
                    createdAt: DateTime.now().toUtc().toIso8601String(),
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        await tester.tap(find.byIcon(Icons.mic_rounded));
        await tester.pump();

        expect(find.byIcon(Icons.stop_rounded), findsOneWidget);

        final recordingScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final stopRecording =
            recordingScreen.onRecordStop! as Future<void> Function();
        late Future<void> stopFuture;
        await tester.runAsync(() async {
          stopFuture = stopRecording();
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.runAsync(() async {
          await uploadStarted.future.timeout(_uploadStartCeiling);
        });
        await pumpUntilAsync(tester, () async {
          final messages = await msgRepo.getMessagesPage(group.id);
          return messages.length == 1 && messages.single.status == 'sending';
        }, maxPumps: 240);
        await pumpFrames(tester, count: 10);

        // The durable parent message row is now persisted before upload so
        // resume-time recovery can resolve it from the attachment row.
        final inFlightMessages = await msgRepo.getMessagesPage(group.id);
        expect(inFlightMessages, hasLength(1));
        expect(inFlightMessages.single.status, 'sending');

        await tester.runAsync(() async {
          uploadGate.complete();
          await stopFuture;
        });
        await pumpFrames(tester, count: 20);

        final messages = await msgRepo.getMessagesPage(group.id);
        expect(messages.length, 1);
        expect(messages.first.status, 'sent');
        expect(messages.first.text, '');
        expect(messages.first.isIncoming, false);
        expect(messages.first.senderPeerId, testIdentity.peerId);
      },
    );

    testWidgets(
      'voice send with zero topic peers still persists the final row as sent',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        final tempDir = Directory.systemTemp.createTempSync(
          'group-voice-zero-peers-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final tempVoice = File(p.join(tempDir.path, 'voice.m4a'))
          ..writeAsStringSync('voice');
        final mediaFileManager = TrackingDurableMediaFileManager(tempDir);

        final recorder = FakeAudioRecorderService()
          ..fakeDurationMs = 3000
          ..fakeSizeBytes = 48000
          ..fakeOutputPath = tempVoice.path;

        bridge = FakeBridge(
          initialResponses: {
            'group:publish': {
              'ok': true,
              'messageId': 'msg-voice-zero-peers',
              'topicPeers': 0,
            },
          },
        );

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            audioRecorderService: recorder,
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                  deleteSourceWhenDone = false,
                  preparedArtifact,
                }) async => MediaAttachment(
                  id: 'uploaded-voice-zero-peers',
                  messageId: '',
                  mime: mime,
                  size: 1,
                  mediaType: MediaAttachment.mediaTypeFromMime(mime),
                  localPath: localFilePath,
                  downloadStatus: 'done',
                  contentHash: _validContentHash,
                  encryptionKeyBase64: 'key-fixture',
                  encryptionNonce: 'nonce-fixture',
                  encryptionScheme:
                      kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                  durationMs: durationMs,
                  waveform: waveform,
                  createdAt: DateTime.now().toUtc().toIso8601String(),
                ),
          ),
        );
        await pumpFrames(tester, count: 20);

        final beforeCount = (await msgRepo.getMessagesPage(group.id)).length;

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final startRecording = screen.onRecordStart! as Future<void> Function();
        await startRecording();
        await pumpUntil(
          tester,
          () => find.byIcon(Icons.stop_rounded).evaluate().isNotEmpty,
        );

        final recordingScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final stopRecording =
            recordingScreen.onRecordStop! as Future<void> Function();
        late Future<void> stopFuture;
        await tester.runAsync(() async {
          stopFuture = stopRecording();
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.runAsync(() async {
          await stopFuture;
        });
        await pumpFrames(tester, count: 20);

        final messages = await msgRepo.getMessagesPage(group.id);
        expect(messages, hasLength(beforeCount + 1));
        final saved = await msgRepo.getLatestMessage(group.id);
        expect(saved, isNotNull);
        expect(saved!.isIncoming, isFalse);
        expect(saved.text, '');
        expect(saved.status, 'sent');
        expect(saved.quotedMessageId, isNull);
        expect(saved.inboxStored, isTrue);
        expect(find.byIcon(Icons.schedule_rounded), findsNothing);
      },
    );

    testWidgets(
      'voice group-not-found rejection retains a durable failed voice row',
      (tester) async {
        final missingGroup = makeChatGroup();
        await groupRepo.saveGroup(missingGroup);
        await saveActiveGroupMembers(groupRepo, missingGroup);
        final tempDir = Directory.systemTemp.createTempSync(
          'group-voice-missing-group-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final tempVoice = File(p.join(tempDir.path, 'voice.m4a'))
          ..writeAsStringSync('voice');
        final mediaFileManager = TrackingDurableMediaFileManager(tempDir);
        final recorder = FakeAudioRecorderService()
          ..fakeDurationMs = 3000
          ..fakeSizeBytes = 48000
          ..fakeOutputPath = tempVoice.path;
        final uploadStarted = Completer<void>();
        final uploadRelease = Completer<void>();
        addTearDown(() {
          if (!uploadRelease.isCompleted) uploadRelease.complete();
        });

        await tester.pumpWidget(
          buildWidget(
            group: missingGroup,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            audioRecorderService: recorder,
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                  deleteSourceWhenDone = false,
                  preparedArtifact,
                }) async {
                  if (!uploadStarted.isCompleted) uploadStarted.complete();
                  await uploadRelease.future;
                  return MediaAttachment(
                    id: blobId!,
                    messageId: '',
                    mime: mime,
                    size: 1,
                    mediaType: MediaAttachment.mediaTypeFromMime(mime),
                    localPath: mediaFileManager?.relativePathForAttachment(
                      contactPeerId: missingGroup.id,
                      blobId: blobId,
                      mime: mime,
                    ),
                    downloadStatus: 'done',
                    contentHash: _validContentHash,
                    encryptionKeyBase64: 'key-fixture',
                    encryptionNonce: 'nonce-fixture',
                    encryptionScheme:
                        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                    durationMs: durationMs,
                    waveform: waveform,
                    createdAt: DateTime.now().toUtc().toIso8601String(),
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final startRecording = screen.onRecordStart! as Future<void> Function();
        await startRecording();
        await pumpUntil(
          tester,
          () => find.byIcon(Icons.stop_rounded).evaluate().isNotEmpty,
        );

        final recordingScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final stopRecording =
            recordingScreen.onRecordStop! as Future<void> Function();
        late Future<void> stopFuture;
        await tester.runAsync(() async {
          stopFuture = stopRecording();
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.runAsync(() async {
          await uploadStarted.future.timeout(_uploadStartCeiling);
        });
        final deleteGroup = runGroupMembershipMutationLocked<void>(
          groupId: missingGroup.id,
          action: () => groupRepo.deleteGroup(missingGroup.id),
        );
        uploadRelease.complete();
        await pumpUntilFuturesComplete(tester, [deleteGroup, stopFuture]);
        await pumpFrames(tester, count: 10);

        // 144: a terminal voice send keeps the recorded row + audio as a
        // durable non-retryable send_failed bubble instead of deleting it.
        final persisted = await msgRepo.getMessagesPage(missingGroup.id);
        final voiceRows = persisted
            .where((message) => !message.isIncoming && message.text.isEmpty)
            .toList();
        expect(voiceRows, hasLength(1));
        expect(voiceRows.single.status, GroupMessage.statusSendFailed);
        expect(
          await mediaAttachmentRepo.getAttachmentsForMessage(
            voiceRows.single.id,
            owner: MediaOwnerLane.group,
          ),
          isNotEmpty,
        );
        expect(bridge.commandLog, isNot(contains('group:publish')));
      },
    );

    testWidgets(
      'voice stop after unmount retains a durable failed row when group lookup resolves to not found',
      (tester) async {
        final group = makeChatGroup();
        final delayedGroupRepo = _DelayedNotFoundGroupRepository(
          const Duration(milliseconds: 500),
        );
        groupRepo = delayedGroupRepo;
        await delayedGroupRepo.saveGroup(group);
        await delayedGroupRepo.saveKey(
          GroupKeyInfo(
            groupId: group.id,
            keyGeneration: 1,
            encryptedKey: 'test-group-key-1',
            createdAt: DateTime.utc(2026, 5, 1, 9),
          ),
        );
        await saveActiveGroupMembers(delayedGroupRepo, group);
        await delayedGroupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: 'peer-ally',
            username: 'Ally',
            role: MemberRole.writer,
            joinedAt: DateTime.now().toUtc(),
          ),
        );

        final tempDir = Directory.systemTemp.createTempSync(
          'group-voice-unmounted-cleanup-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final tempVoice = File(p.join(tempDir.path, 'voice.m4a'))
          ..writeAsStringSync('voice');
        final mediaFileManager = TrackingDurableMediaFileManager(tempDir);
        final recorder = FakeAudioRecorderService()
          ..fakeDurationMs = 3000
          ..fakeSizeBytes = 48000
          ..fakeOutputPath = tempVoice.path;
        final uploadStarted = Completer<void>();
        final uploadRelease = Completer<void>();
        addTearDown(() {
          if (!uploadRelease.isCompleted) uploadRelease.complete();
        });

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            audioRecorderService: recorder,
            uploadMediaFn:
                ({
                  required bridge,
                  required localFilePath,
                  required mime,
                  required recipientPeerId,
                  String? blobId,
                  mediaFileManager,
                  width,
                  height,
                  durationMs,
                  waveform,
                  allowedPeers,
                  deleteSourceWhenDone = false,
                  preparedArtifact,
                }) async {
                  if (!uploadStarted.isCompleted) {
                    uploadStarted.complete();
                  }
                  await uploadRelease.future;
                  return MediaAttachment(
                    id: blobId!,
                    messageId: '',
                    mime: mime,
                    size: 1,
                    mediaType: MediaAttachment.mediaTypeFromMime(mime),
                    localPath: mediaFileManager?.relativePathForAttachment(
                      contactPeerId: group.id,
                      blobId: blobId,
                      mime: mime,
                    ),
                    downloadStatus: 'done',
                    contentHash: _validContentHash,
                    encryptionKeyBase64: 'key-fixture',
                    encryptionNonce: 'nonce-fixture',
                    encryptionScheme:
                        kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                    durationMs: durationMs,
                    waveform: waveform,
                    createdAt: DateTime.now().toUtc().toIso8601String(),
                  );
                },
          ),
        );
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        await (screen.onRecordStart! as Future<void> Function())();
        await pumpUntil(
          tester,
          () => find.byIcon(Icons.stop_rounded).evaluate().isNotEmpty,
        );

        final recordingScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final stopRecording =
            recordingScreen.onRecordStop! as Future<void> Function();
        late Future<void> stopFuture;
        await tester.runAsync(() async {
          stopFuture = stopRecording();
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await tester.runAsync(() async {
          await uploadStarted.future.timeout(_uploadStartCeiling);
        });
        await pumpFrames(tester, count: 5);

        final inFlightMessage = await msgRepo.getLatestMessage(group.id);
        expect(inFlightMessage, isNotNull);
        final messageId = inFlightMessage!.id;

        final armNotFound = runGroupMembershipMutationLocked<void>(
          groupId: group.id,
          action: () async => delayedGroupRepo.armNotFound(),
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        uploadRelease.complete();
        await pumpUntilFuturesComplete(tester, [armNotFound, stopFuture]);
        await pumpFrames(tester, count: 10);

        // 144: even when the screen is gone, a terminal result keeps the row as
        // a durable send_failed bubble (it surfaces on reopen) rather than
        // silently deleting the recording.
        expect(
          mediaFileManager.deletedPendingUploadDirs,
          isNot(contains(messageId)),
        );
        expect(
          await mediaAttachmentRepo.getAttachmentsForMessage(
            messageId,
            owner: MediaOwnerLane.group,
          ),
          isNotEmpty,
        );
        final persisted = await msgRepo.getMessage(messageId);
        expect(persisted, isNotNull);
        expect(persisted!.status, GroupMessage.statusSendFailed);
      },
    );

    testWidgets(
      'voice stop unmounted during background-task begin never updates a disposed composer',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        final tempDir = Directory.systemTemp.createTempSync(
          'group-voice-bg-begin-unmount-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final tempVoice = File(p.join(tempDir.path, 'voice.m4a'))
          ..writeAsStringSync('voice');
        final mediaFileManager = TrackingDurableMediaFileManager(tempDir);
        final recorder = FakeAudioRecorderService()
          ..fakeDurationMs = 3000
          ..fakeSizeBytes = 48000
          ..fakeOutputPath = tempVoice.path;
        final gatedBridge = _GatedBackgroundTaskBridge();
        bridge = gatedBridge;

        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            audioRecorderService: recorder,
          ),
        );
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        await (screen.onRecordStart! as Future<void> Function())();
        await pumpUntil(
          tester,
          () => find.byIcon(Icons.stop_rounded).evaluate().isNotEmpty,
        );

        final recordingScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        late Future<void> stopFuture;
        await tester.runAsync(() async {
          stopFuture =
              (recordingScreen.onRecordStop! as Future<void> Function())();
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await pumpUntil(
          tester,
          () => gatedBridge.beginStarted.isCompleted,
          maxPumps: 240,
        );
        expect(gatedBridge.beginStarted.isCompleted, isTrue);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        gatedBridge.beginGate.complete();
        await tester.runAsync(() async {
          await stopFuture.timeout(const Duration(seconds: 10));
        });

        expect(gatedBridge.endCalls, 1);
      },
    );

    testWidgets('voice upload failure restores the quoted reply target', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      await saveActiveGroupMembers(groupRepo, group);
      await msgRepo.saveMessage(
        makeMessage(
          id: 'msg-parent-voice-upload',
          text: 'Voice upload parent',
          groupId: group.id,
          isIncoming: true,
        ),
      );
      final tempDir = Directory.systemTemp.createTempSync(
        'group-voice-upload-reply-',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final tempVoice = File(p.join(tempDir.path, 'voice.m4a'))
        ..writeAsStringSync('voice');
      final mediaFileManager = TrackingDurableMediaFileManager(tempDir);
      final recorder = FakeAudioRecorderService()
        ..fakeDurationMs = 3000
        ..fakeSizeBytes = 48000
        ..fakeOutputPath = tempVoice.path;

      await tester.pumpWidget(
        buildWidget(
          group: group,
          mediaRepo: mediaAttachmentRepo,
          mediaFileManager: mediaFileManager,
          audioRecorderService: recorder,
          uploadMediaFn:
              ({
                required bridge,
                required localFilePath,
                required mime,
                required recipientPeerId,
                String? blobId,
                mediaFileManager,
                width,
                height,
                durationMs,
                waveform,
                allowedPeers,
                deleteSourceWhenDone = false,
                preparedArtifact,
              }) async => null,
        ),
      );
      await pumpFrames(tester, count: 20);

      final screen = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      screen.onQuoteReply!.call('msg-parent-voice-upload');
      await tester.pump();

      expect(find.text('Replying to'), findsOneWidget);

      final startRecording = screen.onRecordStart! as Future<void> Function();
      await startRecording();
      await pumpUntil(
        tester,
        () => find.byIcon(Icons.stop_rounded).evaluate().isNotEmpty,
      );

      final recordingScreen = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      final stopRecording =
          recordingScreen.onRecordStop! as Future<void> Function();
      late Future<void> stopFuture;
      await tester.runAsync(() async {
        stopFuture = stopRecording();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.runAsync(() async {
        await stopFuture;
      });
      await pumpFrames(tester, count: 10);

      final messages = await msgRepo.getMessagesPage(group.id);
      final failed = messages.firstWhere(
        (message) => message.id != 'msg-parent-voice-upload',
      );
      expect(failed.status, 'failed');
      expect(failed.quotedMessageId, 'msg-parent-voice-upload');
      expect(find.text('Replying to'), findsOneWidget);
      expect(find.text('Voice upload parent'), findsWidgets);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    testWidgets('voice publish failure restores the quoted reply target', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      await saveActiveGroupMembers(groupRepo, group);
      await msgRepo.saveMessage(
        makeMessage(
          id: 'msg-parent-voice-publish',
          text: 'Voice publish parent',
          groupId: group.id,
          isIncoming: true,
        ),
      );
      final tempDir = Directory.systemTemp.createTempSync(
        'group-voice-publish-reply-',
      );
      addTearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });
      final tempVoice = File(p.join(tempDir.path, 'voice.m4a'))
        ..writeAsStringSync('voice');
      final mediaFileManager = TrackingDurableMediaFileManager(tempDir);
      final recorder = FakeAudioRecorderService()
        ..fakeDurationMs = 3000
        ..fakeSizeBytes = 48000
        ..fakeOutputPath = tempVoice.path;
      bridge = FakeBridge(
        initialResponses: {
          'group:publish': {'ok': false, 'errorCode': 'PUBLISH_FAILED'},
        },
      );

      await tester.pumpWidget(
        buildWidget(
          group: group,
          mediaRepo: mediaAttachmentRepo,
          mediaFileManager: mediaFileManager,
          audioRecorderService: recorder,
          uploadMediaFn:
              ({
                required bridge,
                required localFilePath,
                required mime,
                required recipientPeerId,
                String? blobId,
                mediaFileManager,
                width,
                height,
                durationMs,
                waveform,
                allowedPeers,
                deleteSourceWhenDone = false,
                preparedArtifact,
              }) async => MediaAttachment(
                id: 'uploaded-voice-1',
                messageId: '',
                mime: mime,
                size: 1,
                mediaType: MediaAttachment.mediaTypeFromMime(mime),
                localPath: localFilePath,
                downloadStatus: 'done',
                contentHash: _validContentHash,
                encryptionKeyBase64: 'key-fixture',
                encryptionNonce: 'nonce-fixture',
                encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
                durationMs: durationMs,
                waveform: waveform,
                createdAt: DateTime.now().toUtc().toIso8601String(),
              ),
        ),
      );
      await pumpFrames(tester, count: 20);

      final screen = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      screen.onQuoteReply!.call('msg-parent-voice-publish');
      await tester.pump();

      expect(find.text('Replying to'), findsOneWidget);

      final startRecording = screen.onRecordStart! as Future<void> Function();
      await startRecording();
      await pumpUntil(
        tester,
        () => find.byIcon(Icons.stop_rounded).evaluate().isNotEmpty,
      );

      final recordingScreen = tester.widget<GroupConversationScreen>(
        find.byType(GroupConversationScreen),
      );
      final stopRecording =
          recordingScreen.onRecordStop! as Future<void> Function();
      late Future<void> stopFuture;
      await tester.runAsync(() async {
        stopFuture = stopRecording();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await tester.runAsync(() async {
        await stopFuture;
      });
      await pumpFrames(tester, count: 10);

      final messages = await msgRepo.getMessagesPage(group.id);
      final failed = messages.firstWhere(
        (message) => message.id != 'msg-parent-voice-publish',
      );

      expect(failed.status, 'failed');
      expect(failed.quotedMessageId, 'msg-parent-voice-publish');
      expect(find.text('Replying to'), findsOneWidget);
      expect(find.text('Voice publish parent'), findsWidgets);
      expect(find.byIcon(Icons.error_outline_rounded), findsOneWidget);
    });

    // Full upload→publish e2e is tested at the use case level:
    // - send_group_message_use_case_test: 'sends message with empty text and media'
    // - Go bridge_test: TestGroupPublish_MediaOnly_AcceptsEmptyText
    // (The wired-level e2e test is not feasible because uploadMedia's File I/O
    // does not resolve in Flutter's FakeAsync zone.)

    testWidgets('announcement admin sees mic button for voice recording', (
      tester,
    ) async {
      final group = makeAnnouncementGroup(role: GroupRole.admin);
      await groupRepo.saveGroup(group);
      final recorder = FakeAudioRecorderService()
        ..fakeDurationMs = 3000
        ..fakeSizeBytes = 48000;

      await tester.pumpWidget(
        buildWidget(
          group: group,
          mediaRepo: mediaAttachmentRepo,
          mediaFileManager: FakeMediaFileManager(),
          audioRecorderService: recorder,
        ),
      );
      await pumpFrames(tester, count: 20);

      // Mic button should be visible for admin in announcement group
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);

      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pump();

      // Recording overlay should appear
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.byIcon(Icons.stop_rounded), findsOneWidget);
    });

    // -----------------------------------------------------------------------
    // Reaction integration tests
    // -----------------------------------------------------------------------

    testWidgets(
      'loads persisted reactions on init when reactionRepo is provided',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(makeMessage(id: 'msg-1', text: 'Hello'));

        final reactionRepo = FakeReactionRepository();
        await reactionRepo.saveReaction(
          MessageReaction(
            id: 'rxn-1',
            messageId: 'msg-1',
            emoji: '\u{1F44D}',
            senderPeerId: 'peer-alice',
            timestamp: DateTime.now().toUtc().toIso8601String(),
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        );

        await tester.pumpWidget(
          buildWidget(group: group, reactionRepo: reactionRepo),
        );
        await pumpFrames(tester);

        // The reaction emoji should be visible in the UI
        expect(find.text('\u{1F44D}'), findsOneWidget);
      },
    );

    testWidgets(
      'GPL-04E explicitly disabled resume hides durable private reactions while ordinary remains',
      (tester) async {
        tester.view.physicalSize = const Size(1200, 3000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-private-reaction',
            text: 'PRIVATE BODY MUST STAY HIDDEN',
            privateMediaPolicy: const GroupPrivateMediaPolicy.viewOnce(),
            timestamp: DateTime.utc(2026, 7, 12, 10),
          ),
        );
        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-unsupported-reaction',
            text: 'UNSUPPORTED BODY MUST STAY HIDDEN',
            privateMediaPolicy: const GroupPrivateMediaPolicy.unsupported(
              sourceVersion: 9,
            ),
            timestamp: DateTime.utc(2026, 7, 12, 10, 1),
          ),
        );
        await msgRepo.saveMessage(
          makeMessage(
            id: 'msg-ordinary-reaction',
            text: 'ordinary reaction control',
            timestamp: DateTime.utc(2026, 7, 12, 10, 2),
          ),
        );

        final reactionRepo = FakeReactionRepository();
        Future<void> persistReaction({
          required String id,
          required String messageId,
          required String emoji,
          required String senderPeerId,
          required DateTime timestamp,
        }) => reactionRepo.saveReaction(
          MessageReaction(
            id: id,
            messageId: messageId,
            emoji: emoji,
            senderPeerId: senderPeerId,
            timestamp: timestamp.toIso8601String(),
            createdAt: timestamp.toIso8601String(),
          ),
        );

        await persistReaction(
          id: 'rxn-private-durable-1',
          messageId: 'msg-private-reaction',
          emoji: '🔒',
          senderPeerId: 'peer-bob',
          timestamp: DateTime.utc(2026, 7, 12, 10, 3),
        );
        await persistReaction(
          id: 'rxn-unsupported-durable-1',
          messageId: 'msg-unsupported-reaction',
          emoji: '🚫',
          senderPeerId: 'peer-bob',
          timestamp: DateTime.utc(2026, 7, 12, 10, 4),
        );
        await persistReaction(
          id: 'rxn-ordinary-durable-1',
          messageId: 'msg-ordinary-reaction',
          emoji: '👍',
          senderPeerId: 'peer-bob',
          timestamp: DateTime.utc(2026, 7, 12, 10, 5),
        );

        await tester.pumpWidget(
          buildWidget(
            group: group,
            reactionRepo: reactionRepo,
            privateMediaAvailability:
                const GroupPrivateMediaAvailability.disabled(),
          ),
        );
        await pumpUntil(tester, () {
          if (find.byType(GroupConversationScreen).evaluate().isEmpty) {
            return false;
          }
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen.initialLoadDone &&
              screen.reactions['msg-ordinary-reaction']?.length == 1;
        });

        void expectPrivacySafeProjection({required int ordinaryCount}) {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          expect(screen.reactions['msg-private-reaction'], isNull);
          expect(screen.reactions['msg-unsupported-reaction'], isNull);
          expect(
            screen.reactions['msg-ordinary-reaction'],
            hasLength(ordinaryCount),
          );

          final cards = tester
              .widgetList<LetterCard>(find.byType(LetterCard))
              .toList(growable: false);
          final unavailableCards = cards
              .where((card) => card.privateContentSlot != null)
              .toList(growable: false);
          expect(unavailableCards, hasLength(2));
          for (final card in unavailableCards) {
            expect(card.reactions, isEmpty);
            expect(card.onReactionTap, isNull);
          }
          final ordinaryCard = cards.singleWhere(
            (card) => card.text == 'ordinary reaction control',
          );
          expect(ordinaryCard.reactions, hasLength(ordinaryCount));
          expect(ordinaryCard.onReactionTap, isNotNull);

          expect(find.text('🔒'), findsNothing);
          expect(find.text('🔒 2'), findsNothing);
          expect(find.text('🚫'), findsNothing);
          expect(find.text('🚫 2'), findsNothing);
          expect(
            find.text(ordinaryCount == 1 ? '👍' : '👍 $ordinaryCount'),
            findsOneWidget,
          );
        }

        expectPrivacySafeProjection(ordinaryCount: 1);

        await persistReaction(
          id: 'rxn-private-durable-2',
          messageId: 'msg-private-reaction',
          emoji: '🔒',
          senderPeerId: 'peer-alice',
          timestamp: DateTime.utc(2026, 7, 12, 10, 6),
        );
        await persistReaction(
          id: 'rxn-unsupported-durable-2',
          messageId: 'msg-unsupported-reaction',
          emoji: '🚫',
          senderPeerId: 'peer-alice',
          timestamp: DateTime.utc(2026, 7, 12, 10, 7),
        );
        await persistReaction(
          id: 'rxn-ordinary-durable-2',
          messageId: 'msg-ordinary-reaction',
          emoji: '👍',
          senderPeerId: 'peer-alice',
          timestamp: DateTime.utc(2026, 7, 12, 10, 8),
        );

        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await pumpUntil(tester, () {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          return screen.reactions['msg-ordinary-reaction']?.length == 2;
        });

        expectPrivacySafeProjection(ordinaryCount: 2);
      },
    );

    testWidgets(
      'local long-press actions stay available when reactionRepo is null',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await msgRepo.saveMessage(makeMessage(id: 'msg-1', text: 'Hello'));

        await tester.pumpWidget(buildWidget(group: group));
        await pumpFrames(tester);

        // Long-press still opens the context surface, but reactions stay hidden.
        await tester.longPress(find.text('Hello'));
        await pumpFrames(tester);

        expect(find.byKey(MessageContextOverlay.overlayKey), findsOneWidget);
        expect(find.byKey(MessageContextOverlay.reactionBarKey), findsNothing);
        expect(
          find.byKey(MessageContextOverlay.replyActionKey),
          findsOneWidget,
        );
        expect(find.byKey(MessageContextOverlay.copyActionKey), findsOneWidget);
        expect(find.text('\u{1F44D}'), findsNothing);
      },
    );

    testWidgets('incoming reaction change stream updates UI state', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
      await msgRepo.saveMessage(makeMessage(id: 'msg-1', text: 'Hello'));

      final reactionRepo = FakeReactionRepository();
      final reactionStreamController =
          StreamController<ReactionChange>.broadcast();

      await tester.pumpWidget(
        buildWidget(
          group: group,
          reactionRepo: reactionRepo,
          reactionStreamController: reactionStreamController,
        ),
      );
      await pumpFrames(tester);

      // No reactions initially
      expect(find.text('\u{1F44D}'), findsNothing);

      // Emit an incoming reaction change
      reactionStreamController.add(
        ReactionChange.upsert(
          MessageReaction(
            id: 'rxn-incoming',
            messageId: 'msg-1',
            emoji: '\u{1F44D}',
            senderPeerId: 'peer-bob',
            timestamp: DateTime.now().toUtc().toIso8601String(),
            createdAt: DateTime.now().toUtc().toIso8601String(),
          ),
        ),
      );
      await pumpFrames(tester);

      // Reaction should now be visible
      expect(find.text('\u{1F44D}'), findsOneWidget);

      // Clean up
      await reactionStreamController.close();
    });

    testWidgets(
      'group reaction chips open participant inspection without mutating stored reactions',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: testIdentity.peerId,
            username: testIdentity.username,
            role: MemberRole.admin,
            joinedAt: DateTime.utc(2026, 4, 11, 10),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: 'peer-bob',
            username: 'Bob',
            role: MemberRole.writer,
            joinedAt: DateTime.utc(2026, 4, 11, 10, 1),
          ),
        );
        await msgRepo.saveMessage(makeMessage(id: 'msg-1', text: 'Hello'));

        final reactionRepo = FakeReactionRepository();
        await reactionRepo.saveReaction(
          MessageReaction(
            id: 'rxn-self',
            messageId: 'msg-1',
            emoji: '🔥',
            senderPeerId: testIdentity.peerId,
            timestamp: DateTime.utc(2026, 4, 11, 10, 2).toIso8601String(),
            createdAt: DateTime.utc(2026, 4, 11, 10, 2).toIso8601String(),
          ),
        );
        await reactionRepo.saveReaction(
          MessageReaction(
            id: 'rxn-bob',
            messageId: 'msg-1',
            emoji: '🔥',
            senderPeerId: 'peer-bob',
            timestamp: DateTime.utc(2026, 4, 11, 10, 3).toIso8601String(),
            createdAt: DateTime.utc(2026, 4, 11, 10, 3).toIso8601String(),
          ),
        );

        await tester.pumpWidget(
          buildWidget(group: group, reactionRepo: reactionRepo),
        );
        await pumpFrames(tester);

        await tester.tap(find.text('🔥 2'));
        await pumpFrames(tester);

        expect(find.byKey(GroupReactionDetailsSheet.sheetKey), findsOneWidget);
        expect(find.text('You'), findsOneWidget);
        expect(find.text('Bob'), findsOneWidget);
        expect(reactionRepo.removeReactionCallCount, 0);
        expect(
          await reactionRepo.getReactionsForMessage('msg-1'),
          hasLength(2),
        );
      },
    );

    testWidgets(
      'group reaction inspection prefers member and contact usernames before readable peer-id fallback',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: 'peer-charlie',
            username: 'Charlie',
            role: MemberRole.writer,
            joinedAt: DateTime.utc(2026, 4, 11, 10),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: 'peer-ibra',
            role: MemberRole.writer,
            joinedAt: DateTime.utc(2026, 4, 11, 10, 1),
          ),
        );
        await groupRepo.saveMember(
          GroupMember(
            groupId: group.id,
            peerId: 'peer-fallback-1234567890',
            role: MemberRole.writer,
            joinedAt: DateTime.utc(2026, 4, 11, 10, 2),
          ),
        );
        contactRepo.addTestContact(
          ContactModel(
            peerId: 'peer-ibra',
            publicKey: 'pk-peer-ibra',
            rendezvous: 'rv-peer-ibra',
            username: 'Ibra',
            signature: 'sig-peer-ibra',
            scannedAt: DateTime.utc(2026, 4, 11, 10, 3).toIso8601String(),
          ),
        );
        await msgRepo.saveMessage(
          makeMessage(id: 'msg-identity', text: 'Identity target'),
        );

        final reactionRepo = FakeReactionRepository();
        await reactionRepo.saveReaction(
          MessageReaction(
            id: 'rxn-charlie',
            messageId: 'msg-identity',
            emoji: '👍',
            senderPeerId: 'peer-charlie',
            timestamp: DateTime.utc(2026, 4, 11, 10, 2).toIso8601String(),
            createdAt: DateTime.utc(2026, 4, 11, 10, 2).toIso8601String(),
          ),
        );
        await reactionRepo.saveReaction(
          MessageReaction(
            id: 'rxn-ibra',
            messageId: 'msg-identity',
            emoji: '👍',
            senderPeerId: 'peer-ibra',
            timestamp: DateTime.utc(2026, 4, 11, 10, 3).toIso8601String(),
            createdAt: DateTime.utc(2026, 4, 11, 10, 3).toIso8601String(),
          ),
        );
        await reactionRepo.saveReaction(
          MessageReaction(
            id: 'rxn-fallback',
            messageId: 'msg-identity',
            emoji: '👍',
            senderPeerId: 'peer-fallback-1234567890',
            timestamp: DateTime.utc(2026, 4, 11, 10, 4).toIso8601String(),
            createdAt: DateTime.utc(2026, 4, 11, 10, 4).toIso8601String(),
          ),
        );

        await tester.pumpWidget(
          buildWidget(group: group, reactionRepo: reactionRepo),
        );
        await pumpFrames(tester);

        await tester.tap(find.text('👍 3'));
        await pumpFrames(tester);

        expect(find.byKey(GroupReactionDetailsSheet.sheetKey), findsOneWidget);
        expect(find.text('Charlie'), findsOneWidget);
        expect(find.text('Ibra'), findsOneWidget);
        expect(find.text('peer-fallbac...'), findsOneWidget);
      },
    );

    group('recording lifecycle on group state changes', () {
      late Directory tempDir;
      late FakeAudioRecorderService recorder;
      late TrackingDurableMediaFileManager mediaFileManager;

      setUp(() {
        tempDir = Directory.systemTemp.createTempSync(
          'group-record-lifecycle-',
        );
        recorder = FakeAudioRecorderService();
        mediaFileManager = TrackingDurableMediaFileManager(tempDir);
      });

      tearDown(() {
        if (tempDir.existsSync()) {
          tempDir.deleteSync(recursive: true);
        }
      });

      Widget buildRecordingWidget(GroupModel group) => buildWidget(
        group: group,
        mediaRepo: mediaAttachmentRepo,
        mediaFileManager: mediaFileManager,
        audioRecorderService: recorder,
      );

      Future<void> pumpAndStartRecording(
        WidgetTester tester,
        GroupModel group,
      ) async {
        await tester.pumpWidget(buildRecordingWidget(group));
        await pumpFrames(tester, count: 10);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final startRecording = screen.onRecordStart! as Future<void> Function();
        await startRecording();
        await pumpUntil(
          tester,
          () =>
              tester
                  .widget<GroupConversationScreen>(
                    find.byType(GroupConversationScreen),
                  )
                  .recordingState ==
              VoiceRecordingState.recording,
        );
        expect(recorder.isRecording, isTrue);
      }

      GroupConversationScreen visibleScreen(WidgetTester tester) =>
          tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );

      testWidgets('losing write access cancels an active recording', (
        tester,
      ) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        await pumpAndStartRecording(tester, group);

        final dissolved = group.copyWith(
          isDissolved: true,
          dissolvedAt: DateTime.utc(2026, 6, 10, 12),
          dissolvedBy: 'peer-admin',
        );
        await tester.pumpWidget(buildRecordingWidget(dissolved));
        await pumpFrames(tester, count: 10);

        expect(recorder.isRecording, isFalse);
        expect(recorder.cancelCallCount, 1);
        expect(visibleScreen(tester).recordingState, VoiceRecordingState.idle);
      });

      testWidgets('switching to another group cancels an active recording', (
        tester,
      ) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        await pumpAndStartRecording(tester, group);

        final otherGroup = GroupModel(
          id: 'group-2',
          name: 'Other Group',
          type: GroupType.chat,
          topicName: 'topic-2',
          description: 'Another test group',
          createdAt: DateTime.now().toUtc(),
          createdBy: 'peer-admin',
          myRole: GroupRole.admin,
        );
        await groupRepo.saveGroup(otherGroup);
        await saveActiveGroupMembers(groupRepo, otherGroup);
        await tester.pumpWidget(buildRecordingWidget(otherGroup));
        await pumpFrames(tester, count: 10);

        expect(recorder.isRecording, isFalse);
        expect(recorder.cancelCallCount, 1);
        expect(visibleScreen(tester).recordingState, VoiceRecordingState.idle);
      });

      testWidgets(
        'DTR-15 completed voice stop retarget aborts at the gated preflight without crossing lanes',
        (tester) async {
          mediaUploadInFlightTracker.clearAll();
          addTearDown(mediaUploadInFlightTracker.clearAll);

          final gatedGroupRepo = _GatedMembersGroupRepository();
          groupRepo = gatedGroupRepo;
          final groupA = makeChatGroup();
          final groupB = makeChatGroup().copyWith(
            id: 'group-2',
            name: 'Second Group',
            topicName: 'topic-2',
          );
          await groupRepo.saveGroup(groupA);
          await groupRepo.saveGroup(groupB);
          await groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupA.id,
              keyGeneration: 1,
              encryptedKey: 'test-group-key-1',
              createdAt: DateTime.now().toUtc(),
            ),
          );
          await groupRepo.saveKey(
            GroupKeyInfo(
              groupId: groupB.id,
              keyGeneration: 1,
              encryptedKey: 'test-group-key-2',
              createdAt: DateTime.now().toUtc(),
            ),
          );
          await saveActiveGroupMembers(groupRepo, groupA);
          await saveActiveGroupMembers(groupRepo, groupB);

          final groupAMessageRepo = _WriteCountingGroupMessageRepository();
          final groupBMessageRepo = _WriteCountingGroupMessageRepository();
          final groupAMediaRepo = _WriteCountingMediaAttachmentRepository();
          final groupBMediaRepo = _WriteCountingMediaAttachmentRepository();
          final groupAFileManager = _ScopedTrackingDurableMediaFileManager(
            Directory(p.join(tempDir.path, 'group-a')),
          );
          final groupBFileManager = _ScopedTrackingDurableMediaFileManager(
            Directory(p.join(tempDir.path, 'group-b')),
          );
          final capture = File(p.join(tempDir.path, 'retarget-capture.m4a'))
            ..writeAsStringSync('dtr15 voice capture bytes');
          final captureBytes = capture.readAsBytesSync();
          recorder
            ..fakeOutputPath = capture.path
            ..fakeDurationMs = 1500
            ..fakeSizeBytes = capture.lengthSync();
          var groupAUploadCalls = 0;
          var groupBUploadCalls = 0;
          final uploadRecipients = <String>[];

          LegacyTestUploadMediaFn successfulVoiceUpload(
            void Function() recordCall,
          ) =>
              ({
                required bridge,
                required localFilePath,
                required mime,
                required recipientPeerId,
                mediaFileManager,
                width,
                height,
                durationMs,
                waveform,
                allowedPeers,
                blobId,
                deleteSourceWhenDone = false,
                preparedArtifact,
              }) async {
                recordCall();
                uploadRecipients.add(recipientPeerId);
                return successfulGroupUploadFixture(
                  blobId: blobId!,
                  mime: mime,
                  localFilePath: localFilePath,
                );
              };

          await tester.pumpWidget(
            buildWidget(
              group: groupA,
              messageRepo: groupAMessageRepo,
              mediaRepo: groupAMediaRepo,
              mediaFileManager: groupAFileManager,
              audioRecorderService: recorder,
              uploadMediaFn: successfulVoiceUpload(() => groupAUploadCalls++),
            ),
          );
          await pumpFrames(tester, count: 20);
          final groupAScreen = visibleScreen(tester);
          await (groupAScreen.onRecordStart! as Future<void> Function())();
          await pumpUntil(
            tester,
            () =>
                visibleScreen(tester).recordingState ==
                VoiceRecordingState.recording,
            maxPumps: 120,
          );
          expect(recorder.isRecording, isTrue);

          gatedGroupRepo.holdNextMembersLookup(groupA.id);
          final recordStop =
              visibleScreen(tester).onRecordStop! as Future<void> Function();
          final staleStop = recordStop();
          await pumpUntil(
            tester,
            () => gatedGroupRepo.membersLookupCaptured,
            maxPumps: 120,
          );
          expect(gatedGroupRepo.membersLookupCaptured, isTrue);
          expect(recorder.isRecording, isFalse);
          expect(capture.existsSync(), isTrue);

          await tester.pumpWidget(
            buildWidget(
              group: groupB,
              messageRepo: groupBMessageRepo,
              mediaRepo: groupBMediaRepo,
              mediaFileManager: groupBFileManager,
              audioRecorderService: recorder,
              uploadMediaFn: successfulVoiceUpload(() => groupBUploadCalls++),
            ),
          );
          await pumpUntil(tester, () {
            return visibleScreen(tester).group.id == groupB.id;
          }, maxPumps: 120);

          final groupAParentWritesBeforeRelease =
              groupAMessageRepo.saveMessageCalls;
          final groupBParentWritesBeforeRelease =
              groupBMessageRepo.saveMessageCalls;
          final groupAMediaWritesBeforeRelease =
              groupAMediaRepo.saveAttachmentCalls;
          final groupBMediaWritesBeforeRelease =
              groupBMediaRepo.saveAttachmentCalls;
          final groupACopiesBeforeRelease = groupAFileManager.copyCalls;
          final groupBCopiesBeforeRelease = groupBFileManager.copyCalls;
          final sendCommandsBeforeRelease = bridge.commandLog
              .where(
                (command) =>
                    command == 'group:publish' ||
                    command == 'group:sendReliable' ||
                    command == 'group:inboxStore',
              )
              .length;

          gatedGroupRepo.releaseMembersLookup();
          await pumpUntilFuturesComplete(tester, <Future<void>>[staleStop]);

          expect(
            <String, Object>{
              'group A parent writes':
                  groupAMessageRepo.saveMessageCalls -
                  groupAParentWritesBeforeRelease,
              'group B parent writes':
                  groupBMessageRepo.saveMessageCalls -
                  groupBParentWritesBeforeRelease,
              'group A media writes':
                  groupAMediaRepo.saveAttachmentCalls -
                  groupAMediaWritesBeforeRelease,
              'group B media writes':
                  groupBMediaRepo.saveAttachmentCalls -
                  groupBMediaWritesBeforeRelease,
              'group A durable copies':
                  groupAFileManager.copyCalls - groupACopiesBeforeRelease,
              'group B durable copies':
                  groupBFileManager.copyCalls - groupBCopiesBeforeRelease,
              'group A pending-dir deletes':
                  groupAFileManager.deletedPendingUploadDirs,
              'group B pending-dir deletes':
                  groupBFileManager.deletedPendingUploadDirs,
              'group A upload calls': groupAUploadCalls,
              'group B upload calls': groupBUploadCalls,
              'upload recipients': uploadRecipients,
              'group send commands':
                  bridge.commandLog
                      .where(
                        (command) =>
                            command == 'group:publish' ||
                            command == 'group:sendReliable' ||
                            command == 'group:inboxStore',
                      )
                      .length -
                  sendCommandsBeforeRelease,
              'capture retained': capture.existsSync(),
              'capture unchanged':
                  capture.existsSync() &&
                  base64Encode(capture.readAsBytesSync()) ==
                      base64Encode(captureBytes),
            },
            <String, Object>{
              'group A parent writes': 0,
              'group B parent writes': 0,
              'group A media writes': 0,
              'group B media writes': 0,
              'group A durable copies': 0,
              'group B durable copies': 0,
              'group A pending-dir deletes': <String>[],
              'group B pending-dir deletes': <String>[],
              'group A upload calls': 0,
              'group B upload calls': 0,
              'upload recipients': <String>[],
              'group send commands': 0,
              'capture retained': true,
              'capture unchanged': true,
            },
          );
        },
      );

      testWidgets(
        'a dissolve arriving mid-recording cancels the active recording',
        (tester) async {
          final group = makeChatGroup();
          await groupRepo.saveGroup(group);
          await saveActiveGroupMembers(groupRepo, group);
          await pumpAndStartRecording(tester, group);

          await groupRepo.updateGroup(
            group.copyWith(
              isDissolved: true,
              dissolvedAt: DateTime.utc(2026, 6, 10, 12),
              dissolvedBy: 'peer-admin',
            ),
          );
          messageStreamController.add(
            makeMessage(
              id: 'sys-group_dissolved:group-1',
              text: 'Group dissolved',
            ),
          );
          await pumpFrames(tester, count: 20);

          expect(recorder.isRecording, isFalse);
          expect(recorder.cancelCallCount, 1);
          expect(
            visibleScreen(tester).recordingState,
            VoiceRecordingState.idle,
          );
        },
      );

      testWidgets(
        'group recorder auto-stop preserves the capture file sends nothing and exposes no review controls',
        (tester) async {
          final group = makeChatGroup();
          await groupRepo.saveGroup(group);
          await saveActiveGroupMembers(groupRepo, group);
          final capture = File('${tempDir.path}/auto-stop-capture.m4a')
            ..writeAsBytesSync(<int>[1, 2, 3, 4]);
          recorder
            ..fakeOutputPath = capture.path
            ..fakeDurationMs = 300000
            ..fakeSizeBytes = capture.lengthSync();
          await pumpAndStartRecording(tester, group);
          final sendsBeforeAutoStop = bridge.commandLog
              .where(
                (command) =>
                    command == 'group:sendReliable' ||
                    command == 'group:publish',
              )
              .length;
          expect(sendsBeforeAutoStop, 0);

          await recorder.triggerAutoStop();
          await pumpFrames(tester, count: 5);

          final sendsAfterAutoStop = bridge.commandLog
              .where(
                (command) =>
                    command == 'group:sendReliable' ||
                    command == 'group:publish',
              )
              .length;
          expect(recorder.isRecording, isFalse);
          expect(
            visibleScreen(tester).recordingState,
            VoiceRecordingState.idle,
          );
          expect(recorder.onAutoStopped, isNull);
          expect(capture.existsSync(), isTrue);
          expect(sendsAfterAutoStop, sendsBeforeAutoStop);
          expect(await msgRepo.getMessagesPage(group.id), isEmpty);
          expect(find.byKey(const ValueKey('voice-review-send')), findsNothing);
          expect(
            find.byKey(const ValueKey('voice-review-discard')),
            findsNothing,
          );
        },
      );

      testWidgets(
        'losing write access while arming aborts the pending recording',
        (tester) async {
          final group = makeChatGroup();
          await groupRepo.saveGroup(group);
          await saveActiveGroupMembers(groupRepo, group);
          recorder.startGate = Completer<void>();

          await tester.pumpWidget(buildRecordingWidget(group));
          await pumpFrames(tester, count: 10);

          final screen = visibleScreen(tester);
          final startRecording =
              screen.onRecordStart! as Future<void> Function();
          final startFuture = startRecording();
          await pumpUntil(
            tester,
            () =>
                visibleScreen(tester).recordingState ==
                VoiceRecordingState.arming,
          );

          final dissolved = group.copyWith(
            isDissolved: true,
            dissolvedAt: DateTime.utc(2026, 6, 10, 12),
            dissolvedBy: 'peer-admin',
          );
          await tester.pumpWidget(buildRecordingWidget(dissolved));
          await pumpFrames(tester, count: 5);

          recorder.startGate!.complete();
          await pumpFrames(tester, count: 10);
          await startFuture;
          // The abort continuation resets the composer ValueNotifier without
          // rebuilding the wired widget; re-pump so the screen prop reflects
          // the final state.
          await tester.pumpWidget(buildRecordingWidget(dissolved));
          await pumpFrames(tester, count: 2);

          expect(recorder.isRecording, isFalse);
          expect(recorder.cancelCallCount, 1);
          expect(
            visibleScreen(tester).recordingState,
            VoiceRecordingState.idle,
          );
        },
      );

      testWidgets(
        'a displaced recording session is not cancelled by a stale surface',
        (tester) async {
          final group = makeChatGroup();
          await groupRepo.saveGroup(group);
          await saveActiveGroupMembers(groupRepo, group);
          await pumpAndStartRecording(tester, group);

          // Another surface took over the shared recorder (its start()
          // force-stopped this one's session and installed its own handler).
          recorder.onAutoStopped = (_) {};

          final dissolved = group.copyWith(
            isDissolved: true,
            dissolvedAt: DateTime.utc(2026, 6, 10, 12),
            dissolvedBy: 'peer-admin',
          );
          await tester.pumpWidget(buildRecordingWidget(dissolved));
          await pumpFrames(tester, count: 10);

          // Local state resyncs, but the foreign session stays untouched.
          expect(
            visibleScreen(tester).recordingState,
            VoiceRecordingState.idle,
          );
          expect(recorder.cancelCallCount, 0);
          expect(recorder.onAutoStopped, isNotNull);
        },
      );

      testWidgets(
        'membership loss discovered during a send refresh cancels an active '
        'recording',
        (tester) async {
          final group = makeChatGroup();
          await groupRepo.saveGroup(group);
          await saveActiveGroupMembers(groupRepo, group);
          await pumpAndStartRecording(tester, group);

          // The user is removed from the group; local capability flags stay
          // stale until the next refresh.
          await groupRepo.removeMember(group.id, testIdentity.peerId);

          final send =
              visibleScreen(tester).onSend as Future<void> Function(String);
          await send('hello');
          await pumpFrames(tester, count: 10);

          expect(recorder.isRecording, isFalse);
          expect(recorder.cancelCallCount, 1);
          expect(
            visibleScreen(tester).recordingState,
            VoiceRecordingState.idle,
          );
        },
      );
    });

    group('mic permission denied prompt (152)', () {
      Future<GroupConversationScreen> driveGroupRecordStart(
        WidgetTester tester, {
        required FakeAudioRecorderService recorder,
        required FakeMicPermissionGateway gateway,
      }) async {
        // A WRITABLE group (admin) — read-only groups expose
        // onRecordStart == null and never reach the permission path.
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await tester.pumpWidget(
          buildWidget(
            group: group,
            // Durable media support (mediaRepo + mediaFileManager) is what gates
            // the record controls on; without it onRecordStart stays null.
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: FakeMediaFileManager(),
            audioRecorderService: recorder,
            micPermissionGateway: gateway,
          ),
        );
        await pumpFrames(tester, count: 20);
        return tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
      }

      testWidgets(
        'group mic denial shows the rationale sheet instead of the snackbar (permanentlyDenied)',
        (tester) async {
          final l10n = await AppLocalizations.delegate.load(const Locale('en'));
          final recorder = FakeAudioRecorderService()
            ..permissionGranted = false;
          final gateway = FakeMicPermissionGateway()
            ..statusToReturn = MicPermissionStatus.permanentlyDenied;
          final screen = await driveGroupRecordStart(
            tester,
            recorder: recorder,
            gateway: gateway,
          );
          expect(screen.onRecordStart, isNotNull);

          final pending = (screen.onRecordStart! as Future<void> Function())();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byKey(const ValueKey('mic-perm-sheet')), findsOneWidget);
          expect(
            find.byKey(const ValueKey('mic-perm-open-settings')),
            findsOneWidget,
          );
          expect(find.text(l10n.perm_microphone_record), findsNothing);
          expect(recorder.startCallCount, 0);

          await tester.tap(find.byKey(const ValueKey('mic-perm-not-now')));
          // Wait for the sheet route to leave first so its decorative mic
          // cannot satisfy the live composer check.
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          await pending;
          await tester.pump();
          expect(find.byKey(const ValueKey('mic-perm-sheet')), findsNothing);
          expect(find.byIcon(Icons.stop_rounded), findsNothing);
          expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
        },
      );

      testWidgets(
        'group Open Settings tap deep-links via the injected gateway',
        (tester) async {
          final recorder = FakeAudioRecorderService()
            ..permissionGranted = false;
          final gateway = FakeMicPermissionGateway()
            ..statusToReturn = MicPermissionStatus.permanentlyDenied;
          final screen = await driveGroupRecordStart(
            tester,
            recorder: recorder,
            gateway: gateway,
          );

          final pending = (screen.onRecordStart! as Future<void> Function())();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byKey(const ValueKey('mic-perm-sheet')), findsOneWidget);
          await tester.tap(
            find.byKey(const ValueKey('mic-perm-open-settings')),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          await pending;

          expect(gateway.openAppSettingsCallCount, 1);
          expect(find.byKey(const ValueKey('mic-perm-sheet')), findsNothing);
        },
      );

      // Option A (owner-locked): a first plain `denied` resets to idle WITHOUT
      // forcing the Settings dialog (the OS prompt already showed via
      // request()). Locks the denied-vs-permanentlyDenied axis on the group side.
      testWidgets(
        'group first plain denied resets to idle with no sheet/snackbar',
        (tester) async {
          final l10n = await AppLocalizations.delegate.load(const Locale('en'));
          final recorder = FakeAudioRecorderService();
          final gateway = FakeMicPermissionGateway()
            ..statusToReturn = MicPermissionStatus.denied;
          final screen = await driveGroupRecordStart(
            tester,
            recorder: recorder,
            gateway: gateway,
          );

          await (screen.onRecordStart! as Future<void> Function())();
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));

          expect(find.byKey(const ValueKey('mic-perm-sheet')), findsNothing);
          expect(find.text(l10n.perm_microphone_record), findsNothing);
          expect(recorder.startCallCount, 0);
          // Live rendered composer is back to idle (mic shown, not recording).
          expect(find.byIcon(Icons.stop_rounded), findsNothing);
          expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
        },
      );
    });

    // 159 sub-change 3 + 4 + folded media gate — group coalesce, scroll/read
    // side-effect preservation, and the media-resolve gate.
    group('159 group coalesce + media gate', () {
      // TC-159-08 — a burst of M group stream events applies ONE batched reorder
      // and all M messages (including the trailing one) render.
      testWidgets(
        'TC-159-08 group M-event burst → ONE batched reorder, all ids incl trailing',
        (tester) async {
          final group = makeChatGroup();
          await groupRepo.saveGroup(group);
          await msgRepo.saveMessage(makeMessage(id: 'seed', text: 'Seed'));

          await tester.pumpWidget(buildWidget(group: group));
          await pumpFrames(tester);
          expect(find.text('Seed'), findsOneWidget);

          const burst = 8;
          GroupConversationWired.debugReorderInvocationCount = 0;
          for (var i = 0; i < burst; i++) {
            final msg = makeMessage(
              id: 'burst-$i',
              text: 'burst-$i',
              timestamp: DateTime.utc(2026, 2, 9, 15, 40 + i),
            );
            await msgRepo.saveMessage(msg);
            messageStreamController.add(msg);
          }
          await pumpFrames(tester, count: 20);

          expect(
            GroupConversationWired.debugReorderInvocationCount,
            1,
            reason: 'the burst must collapse into ONE batched reorder',
          );
          for (var i = 0; i < burst; i++) {
            expect(find.text('burst-$i'), findsOneWidget);
          }
          // Trailing-edge flush: the last message of the burst is present.
          expect(find.text('burst-${burst - 1}'), findsOneWidget);
        },
      );

      // TC-159-08b — a coalesced group burst preserves a scrolled-up offset (one
      // capture before / one restore after) and marks read once-per-flush.
      testWidgets(
        'TC-159-08b coalesced group burst restores scroll offset once + marks read',
        (tester) async {
          final group = makeChatGroup();
          await groupRepo.saveGroup(group);
          for (var i = 0; i < 30; i++) {
            await msgRepo.saveMessage(
              makeMessage(
                id: 'hist-$i',
                text: 'history message number $i',
                timestamp: DateTime.utc(2026, 2, 9, 10, i),
              ),
            );
          }

          await tester.pumpWidget(buildWidget(group: group));
          await pumpFrames(tester);

          final controller = tester
              .widget<GroupConversationScreen>(
                find.byType(GroupConversationScreen),
              )
              .scrollController!;
          // Scroll up (away from the live edge) so preserve-offset is active.
          controller.jumpTo(120);
          await tester.pump();
          expect(controller.position.pixels, 120);

          final readBefore = msgRepo.markAsReadCalls;

          for (var i = 0; i < 6; i++) {
            final msg = makeMessage(
              id: 'late-$i',
              text: 'late arrival $i',
              timestamp: DateTime.utc(2026, 2, 9, 16, i),
            );
            await msgRepo.saveMessage(msg);
            messageStreamController.add(msg);
          }
          await pumpFrames(tester, count: 20);

          // The scrolled-up offset is preserved across the whole batch (not yanked
          // to the live edge, not drifted by M partial restores).
          expect(controller.position.pixels, 120);
          // markAsRead fired exactly once for the whole batch (not N times).
          expect(
            msgRepo.markAsReadCalls - readBefore,
            1,
            reason:
                'markAsRead runs once-per-flush against the post-batch state',
          );
        },
      );

      // TC-159-11 — the media-resolve gate skips the per-message DB attachment read
      // for an already-shown text/status update, and opens for a new message.
      testWidgets(
        'TC-159-11 media-resolve gate skips DB read on an already-shown status update',
        (tester) async {
          final group = makeChatGroup();
          await groupRepo.saveGroup(group);
          await msgRepo.saveMessage(
            makeMessage(id: 'shown', text: 'Already shown', status: 'sent'),
          );

          await tester.pumpWidget(
            buildWidget(group: group, mediaRepo: mediaAttachmentRepo),
          );
          await pumpFrames(tester);
          expect(find.text('Already shown'), findsOneWidget);

          final resolveBefore =
              mediaAttachmentRepo.getAttachmentsForMessageCalls;

          // A pure status update to the already-shown message (no new attachment).
          final updated = makeMessage(
            id: 'shown',
            text: 'Already shown',
            status: 'delivered',
          );
          await msgRepo.saveMessage(updated);
          messageStreamController.add(updated);
          await pumpFrames(tester, count: 20);

          expect(
            mediaAttachmentRepo.getAttachmentsForMessageCalls,
            resolveBefore,
            reason:
                'gate must skip the per-message attachment read on a status '
                'update to an already-shown message',
          );

          // A NEW message opens the gate (resolve IS called).
          final fresh = makeMessage(
            id: 'fresh',
            text: 'Fresh message',
            timestamp: DateTime.utc(2026, 2, 9, 16, 0),
          );
          await msgRepo.saveMessage(fresh);
          messageStreamController.add(fresh);
          await pumpFrames(tester, count: 20);

          expect(
            mediaAttachmentRepo.getAttachmentsForMessageCalls,
            resolveBefore + 1,
            reason: 'gate must OPEN (resolve once) for a genuinely new message',
          );
          expect(find.text('Fresh message'), findsOneWidget);
        },
      );
    });

    group('229 download policy separates discussion announcement and manual '
        'retry', () {
      MediaAttachment makePolicyAttachment(
        String id,
        String messageId, {
        String status = kMediaDownloadStatusPending,
        String mime = 'image/png',
        String mediaType = 'image',
      }) {
        return MediaAttachment(
          id: id,
          messageId: messageId,
          mime: mime,
          size: 2048,
          mediaType: mediaType,
          downloadStatus: status,
          downloadRetryCount: 0,
          contentHash: _validContentHash,
          encryptionKeyBase64: 'key-fixture',
          encryptionNonce: 'nonce-fixture',
          encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          createdAt: '2026-07-10T09:00:00.000Z',
        );
      }

      int downloadCommandCount() => bridge.commandLog
          .where((command) => command == 'media:download')
          .length;

      testWidgets(
        'P269 automatic route media recovery delegates to shared coordinator while explicit retry stays user owned',
        (tester) async {
          final group = makeChatGroup();
          await groupRepo.saveGroup(group);
          await saveActiveGroupMembers(groupRepo, group);

          const initialMessageId = 'msg-269-route-initial';
          const initialAttachmentId = 'att-269-route-initial';
          await msgRepo.saveMessage(
            makeMessage(id: initialMessageId, text: 'initial route recovery'),
          );
          await mediaAttachmentRepo.saveAttachment(
            makePolicyAttachment(initialAttachmentId, initialMessageId),
            owner: MediaOwnerLane.group,
          );

          final policy = RecordingMediaAutoDownloadDecider();
          final transferredAttachmentIds = <String>[];
          final coordinator = RetryIncompleteGroupDownloadsUseCase(
            loadPage: ({required after, required limit}) async => const [],
            loadCurrentAttachment: mediaAttachmentRepo.getAttachmentById,
            loadCurrentParent: msgRepo.getMessage,
            loadCurrentGroup: groupRepo.getGroup,
            autoDownloadDecider: policy,
            transfer:
                ({required attachment, required parent, required group}) async {
                  transferredAttachmentIds.add(attachment.id);
                  // A non-done status is deliberate: it is visible without a
                  // local-file fixture, so the assertion below proves the
                  // route awaited the shared result and rehydrated its map.
                  final persisted = attachment.copyWith(
                    downloadStatus: kMediaDownloadStatusFailed,
                  );
                  await mediaAttachmentRepo.saveAttachment(
                    persisted,
                    owner: MediaOwnerLane.group,
                  );
                  return persisted;
                },
          );

          await tester.pumpWidget(
            buildWidget(
              group: group,
              mediaRepo: mediaAttachmentRepo,
              mediaFileManager: FakeMediaFileManager(),
              groupMediaDownloadCoordinator: coordinator,
            ),
          );
          await pumpUntil(
            tester,
            () => transferredAttachmentIds.contains(initialAttachmentId),
          );
          await pumpFrames(tester, count: 8);

          var screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          expect(transferredAttachmentIds, [initialAttachmentId]);
          expect(
            screen.mediaMap[initialMessageId]!.single.downloadStatus,
            kMediaDownloadStatusFailed,
            reason: 'the initial visible row is rehydrated after recovery',
          );
          expect(downloadCommandCount(), 0);

          const liveMessageId = 'msg-269-route-live';
          const liveAttachmentId = 'att-269-route-live';
          final liveMessage = makeMessage(
            id: liveMessageId,
            text: 'live route recovery',
          );
          await msgRepo.saveMessage(liveMessage);
          await mediaAttachmentRepo.saveAttachment(
            makePolicyAttachment(liveAttachmentId, liveMessageId),
            owner: MediaOwnerLane.group,
          );
          messageStreamController.add(liveMessage);
          await pumpUntil(
            tester,
            () => transferredAttachmentIds.contains(liveAttachmentId),
          );
          await pumpFrames(tester, count: 8);

          screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          expect(transferredAttachmentIds, [
            initialAttachmentId,
            liveAttachmentId,
          ]);
          expect(
            screen.mediaMap[liveMessageId]!.single.downloadStatus,
            kMediaDownloadStatusFailed,
            reason: 'the live visible row is rehydrated after recovery',
          );
          expect(downloadCommandCount(), 0);

          final coordinatorTransfersBeforeRetry =
              transferredAttachmentIds.length;
          final policyConsultsBeforeRetry = policy.requests.length;
          screen.onRetryUnavailableMedia!(liveMessageId, liveAttachmentId);
          for (var i = 0; i < 40 && downloadCommandCount() < 1; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 25)),
            );
            await tester.pump(const Duration(milliseconds: 25));
          }
          await pumpFrames(tester, count: 4);

          expect(
            transferredAttachmentIds,
            hasLength(coordinatorTransfersBeforeRetry),
            reason: 'explicit retry must stay outside automatic coordination',
          );
          expect(policy.requests, hasLength(policyConsultsBeforeRetry));
          expect(downloadCommandCount(), 1);
        },
      );

      testWidgets(
        'discussion denial makes zero transfers and consults the discussion '
        'lane',
        (tester) async {
          final group = makeChatGroup();
          await groupRepo.saveGroup(group);
          await saveActiveGroupMembers(groupRepo, group);
          await msgRepo.saveMessage(
            makeMessage(id: 'msg-229-disc', text: 'discussion media letter'),
          );
          await mediaAttachmentRepo.saveAttachment(
            makePolicyAttachment('att-229-disc', 'msg-229-disc'),
            owner: MediaOwnerLane.group,
          );

          final denying = RecordingMediaAutoDownloadDecider(allow: false);
          await tester.pumpWidget(
            buildWidget(
              group: group,
              mediaRepo: mediaAttachmentRepo,
              mediaFileManager: FakeMediaFileManager(),
              autoDownloadDecider: denying,
            ),
          );
          await pumpFrames(tester, count: 20);
          await pumpUntil(tester, () => denying.requests.isNotEmpty);

          expect(
            downloadCommandCount(),
            0,
            reason: 'a denied policy decision must run BEFORE any transfer',
          );
          for (final request in denying.requests) {
            expect(request.conversationKind, MediaConversationKind.discussion);
            expect(request.storageOwner, MediaOwnerLane.group);
            expect(request.userInitiated, isFalse);
          }
          // Denial keeps the persisted row untouched (no optimistic
          // downloading flip, no failure downgrade).
          final rows = await mediaAttachmentRepo.getAttachmentsForMessage(
            'msg-229-disc',
            owner: MediaOwnerLane.group,
          );
          expect(rows.single.downloadStatus, kMediaDownloadStatusPending);
        },
      );

      testWidgets(
        'announcement denial consults the announcement lane and an explicit '
        'retry still transfers once with the group owner',
        (tester) async {
          // A read-only announcement member: no compose permission, yet media
          // retry stays reachable.
          final group = makeAnnouncementGroup(role: GroupRole.member);
          await groupRepo.saveGroup(group);
          await saveActiveGroupMembers(groupRepo, group);
          await msgRepo.saveMessage(
            makeMessage(id: 'msg-229-ann', text: 'announcement media letter'),
          );
          await mediaAttachmentRepo.saveAttachment(
            makePolicyAttachment(
              'att-229-ann',
              'msg-229-ann',
              status: kMediaDownloadStatusFailed,
            ),
            owner: MediaOwnerLane.group,
          );

          final denying = RecordingMediaAutoDownloadDecider(allow: false);
          await tester.pumpWidget(
            buildWidget(
              group: group,
              mediaRepo: mediaAttachmentRepo,
              mediaFileManager: FakeMediaFileManager(),
              autoDownloadDecider: denying,
            ),
          );
          await pumpFrames(tester, count: 20);
          await pumpUntil(tester, () => denying.requests.isNotEmpty);

          expect(
            downloadCommandCount(),
            0,
            reason:
                'the retryable-failed row must not auto-recover under a '
                'denied announcement lane',
          );
          for (final request in denying.requests) {
            expect(
              request.conversationKind,
              MediaConversationKind.announcement,
              reason: 'announcement groups decide on their own product lane',
            );
            expect(
              request.storageOwner,
              MediaOwnerLane.group,
              reason: 'announcement is never a third storage owner',
            );
          }
          final consultsBeforeRetry = denying.requests.length;

          // Explicit user retry bypasses the denied auto preference.
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          expect(
            screen.onRetryUnavailableMedia,
            isNotNull,
            reason:
                'read-only announcement members keep the retry '
                'affordance',
          );
          screen.onRetryUnavailableMedia!('msg-229-ann', 'att-229-ann');
          // The retry path does real file I/O before and after the bridge
          // call; give it real-async windows until the transfer lands.
          for (var i = 0; i < 40 && downloadCommandCount() < 1; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 25)),
            );
            await tester.pump(const Duration(milliseconds: 25));
          }
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await pumpFrames(tester, count: 10);

          expect(
            downloadCommandCount(),
            1,
            reason:
                'the explicit retry transfers exactly once despite the '
                'denied auto preference',
          );
          expect(
            denying.requests.length,
            consultsBeforeRetry,
            reason: 'the user-authoritative retry is never policy-gated',
          );
          // The integrity-checked download path stayed engaged: the fake
          // bridge produced no verifiable bytes, so the row settles in a
          // truthful non-done state instead of a phantom success.
          final rows = await mediaAttachmentRepo.getAttachmentsForMessage(
            'msg-229-ann',
            owner: MediaOwnerLane.group,
          );
          expect(rows.single.downloadStatus, isNot(kMediaDownloadStatusDone));
        },
      );

      testWidgets(
        'group backed evicted media retries only after visible action',
        (tester) async {
          final group = makeChatGroup();
          await groupRepo.saveGroup(group);
          await saveActiveGroupMembers(groupRepo, group);
          await msgRepo.saveMessage(
            makeMessage(id: 'msg-229-evict', text: 'evicted media letter'),
          );
          await mediaAttachmentRepo.saveAttachment(
            makePolicyAttachment(
              'att-229-evict',
              'msg-229-evict',
              status: kMediaDownloadStatusEvicted,
            ),
            owner: MediaOwnerLane.group,
          );

          // Fully-permissive policy: evicted still never auto-transfers.
          await tester.pumpWidget(
            buildWidget(
              group: group,
              mediaRepo: mediaAttachmentRepo,
              mediaFileManager: FakeMediaFileManager(),
              autoDownloadDecider: RecordingMediaAutoDownloadDecider(),
            ),
          );
          await pumpFrames(tester, count: 20);

          expect(
            downloadCommandCount(),
            0,
            reason: 'mount must make zero transfers for an evicted row',
          );

          const retryKey = ValueKey(
            'evicted-media-retry-msg-229-evict-att-229-evict',
          );
          expect(find.text('Local copy removed'), findsOneWidget);
          expect(find.byKey(retryKey), findsOneWidget);

          await tester.tap(find.byKey(retryKey));
          for (var i = 0; i < 40 && downloadCommandCount() < 1; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 25)),
            );
            await tester.pump(const Duration(milliseconds: 25));
          }

          expect(
            downloadCommandCount(),
            1,
            reason:
                'one visible action performs exactly one owner-aware '
                'retry',
          );
          // The retry went through the owner-aware group lane (the
          // owner-enforcing repo would throw on a cross-lane write) and the
          // fake bridge produced no verifiable bytes, so the row settles
          // truthfully non-done.
          final rows = await mediaAttachmentRepo.getAttachmentsForMessage(
            'msg-229-evict',
            owner: MediaOwnerLane.group,
          );
          expect(rows.single.downloadStatus, isNot(kMediaDownloadStatusDone));
        },
      );
    });

    // -------------------------------------------------------------------------
    // 235: received-media core actions (typed viewer + injected coordinators)
    // -------------------------------------------------------------------------
    group('235 received media actions', () {
      late FakeMediaFileManager mediaFileManager;

      setUp(() {
        mediaFileManager = FakeMediaFileManager();
      });

      tearDown(() {
        final root = Directory(FakeMediaFileManager.testRootPath);
        if (root.existsSync()) root.deleteSync(recursive: true);
      });

      /// Seeds an incoming persisted message with one DONE, verified image
      /// attachment backed by a real decodable file, and returns the absolute
      /// stored path.
      Future<String> seedIncomingDoneImage({
        required String messageId,
        required String attachmentId,
        String caption = 'photo caption',
        String senderPeerId = 'peer-alice',
        String mime = 'image/png',
        bool isIncoming = true,
        int? size,
        int? width,
        int? height,
        DateTime? timestamp,
      }) async {
        await msgRepo.saveMessage(
          makeMessage(
            id: messageId,
            text: caption,
            isIncoming: isIncoming,
            senderPeerId: senderPeerId,
            timestamp: timestamp,
          ),
        );
        final relativePath = mediaFileManager.relativePathForAttachment(
          contactPeerId: 'group-1',
          blobId: attachmentId,
          mime: mime,
        );
        final absolutePath = await mediaFileManager.resolveStoredPath(
          relativePath,
        );
        final mediaFile = File(absolutePath);
        mediaFile.parent.createSync(recursive: true);
        mediaFile.writeAsBytesSync(_tinyPngBytes, flush: true);
        await mediaAttachmentRepo.saveAttachment(
          MediaAttachment(
            id: attachmentId,
            messageId: messageId,
            mime: mime,
            size: size ?? _tinyPngBytes.length,
            mediaType: 'image',
            width: width,
            height: height,
            localPath: absolutePath,
            downloadStatus: kMediaDownloadStatusDone,
            createdAt: (timestamp ?? DateTime.now()).toUtc().toIso8601String(),
            contentHash: _validContentHash,
            encryptionKeyBase64: 'a2V5',
            encryptionNonce: 'bm9uY2U=',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
          ),
          owner: MediaOwnerLane.group,
        );
        return absolutePath;
      }

      Future<String> seedOrdinaryDoneVideo({
        required String messageId,
        required String attachmentId,
        required bool isIncoming,
        required String caption,
        required String mime,
        required int size,
        required int durationMs,
        required DateTime timestamp,
      }) async {
        await msgRepo.saveMessage(
          makeMessage(
            id: messageId,
            text: caption,
            isIncoming: isIncoming,
            senderPeerId: isIncoming ? 'peer-alice' : 'peer-self',
            timestamp: timestamp,
          ),
        );
        final relativePath = mediaFileManager.relativePathForAttachment(
          contactPeerId: 'group-1',
          blobId: attachmentId,
          mime: mime,
        );
        final absolutePath = await mediaFileManager.resolveStoredPath(
          relativePath,
        );
        final mediaFile = File(absolutePath);
        mediaFile.parent.createSync(recursive: true);
        mediaFile.writeAsBytesSync(const <int>[1, 2, 3], flush: true);
        await mediaAttachmentRepo.saveAttachment(
          MediaAttachment(
            id: attachmentId,
            messageId: messageId,
            mime: mime,
            size: size,
            mediaType: 'video',
            localPath: absolutePath,
            downloadStatus: kMediaDownloadStatusDone,
            createdAt: timestamp.toUtc().toIso8601String(),
            contentHash: _validContentHash,
            encryptionKeyBase64: 'a2V5',
            encryptionNonce: 'bm9uY2U=',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            width: 1920,
            height: 1080,
            durationMs: durationMs,
          ),
          owner: MediaOwnerLane.group,
        );
        return absolutePath;
      }

      // The initial load performs REAL file I/O (path resolve + existence
      // checks), which only completes inside tester.runAsync — fake-async
      // pumps alone would hang it forever.
      Future<void> pumpUntilMediaLoaded(
        WidgetTester tester,
        String messageId, {
        int expectedCount = 1,
      }) async {
        for (var i = 0; i < 40; i++) {
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 25));
          });
          await tester.pump();
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          if ((screen.mediaMap[messageId]?.length ?? 0) >= expectedCount) {
            return;
          }
        }
        fail('media for $messageId did not load');
      }

      Future<void> pumpUntilCanWrite(WidgetTester tester) async {
        for (var i = 0; i < 40; i++) {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          if (screen.canWrite) return;
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 25));
          });
          await tester.pump();
        }
        fail('group write capability did not become available');
      }

      Future<void> showViewerMoreMenu(WidgetTester tester) async {
        final more = find.byKey(const ValueKey('media_action_more'));
        expect(more, findsOneWidget);
        tester.state<PopupMenuButtonState<dynamic>>(more).showButtonMenu();
        await pumpFrames(tester, count: 4);
      }

      Future<void> selectViewerPopupAction(
        WidgetTester tester,
        MediaViewerAction action,
      ) async {
        final row = find.byKey(ValueKey('media_action_${action.name}'));
        expect(row, findsOneWidget);
        Navigator.of(tester.element(row)).pop(action);
        await tester.pump();
      }

      ContactModel plan247SenderContact() => ContactModel(
        peerId: 'peer-bob',
        publicKey: 'pk-peer-bob',
        rendezvous: '/ip4/127.0.0.1/tcp/4001',
        username: 'Bob',
        signature: 'sig-peer-bob',
        scannedAt: DateTime.utc(2026, 7, 11).toIso8601String(),
      );

      Future<(GroupModel, KnownClearGroupMessageRepository)>
      seedPlan247EligibleSource({
        required String messageId,
        required String attachmentId,
      }) async {
        final group = makeAnnouncementGroup(role: GroupRole.member);
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        final currentMessages = KnownClearGroupMessageRepository();
        msgRepo = currentMessages;
        await seedIncomingDoneImage(
          messageId: messageId,
          attachmentId: attachmentId,
          caption: 'eligible announcement visual',
          senderPeerId: 'peer-bob',
        );
        await contactRepo.addContact(plan247SenderContact());
        return (group, currentMessages);
      }

      testWidgets(
        'incoming discussion image uses compact keep-in-chat controls without losing actions',
        (tester) async {
          tester.view.physicalSize = const Size(1200, 4000);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final group = makeChatGroup();
          await groupRepo.saveGroup(group);
          await saveActiveGroupMembers(groupRepo, group);
          const imageMessageId = 'group-compact-image-message-313';
          const imageAttachmentId = 'group-compact-image-attachment-313';
          const gifMessageId = 'group-standard-gif-message-313';
          const gifAttachmentId = 'group-standard-gif-attachment-313';
          await seedIncomingDoneImage(
            messageId: imageMessageId,
            attachmentId: imageAttachmentId,
          );
          await seedIncomingDoneImage(
            messageId: gifMessageId,
            attachmentId: gifAttachmentId,
            mime: 'image/gif',
          );
          final controller = RecordingGroupMediaActionsController(
            messageRepository: msgRepo,
            mediaAttachmentRepository: mediaAttachmentRepo,
          );
          await tester.pumpWidget(
            buildWidget(
              group: group,
              mediaRepo: mediaAttachmentRepo,
              mediaFileManager: mediaFileManager,
              mediaActionsController: controller,
              mediaDeleteForMeCoordinator:
                  RecordingGroupMediaDeleteForMeCoordinator(),
              groupMediaForwardLauncher: (_, _) async {},
            ),
          );
          await pumpUntilMediaLoaded(tester, imageMessageId);
          await pumpUntilMediaLoaded(tester, gifMessageId);
          await pumpUntilCanWrite(tester);

          await tester.tap(
            find.byKey(
              const ValueKey(
                'media-grid-cell-$imageMessageId-$imageAttachmentId',
              ),
            ),
          );
          await pumpFrames(tester, count: 4);
          var viewer = tester.widget<FullScreenTypedMediaViewer>(
            find.byType(FullScreenTypedMediaViewer),
          );
          final imageItem = viewer.items.single;
          expect(imageItem.kind, MediaViewerKind.image);
          expect(
            imageItem.actionPresentation,
            MediaViewerActionPresentation.compactImageOverlay,
          );
          expect(
            imageItem.capabilities.allowed,
            unorderedEquals(const <MediaViewerAction>[
              MediaViewerAction.save,
              MediaViewerAction.share,
              MediaViewerAction.info,
              MediaViewerAction.reply,
              MediaViewerAction.forward,
              MediaViewerAction.delete,
            ]),
          );
          final appBar = find.byType(AppBar);
          expect(
            find.descendant(
              of: appBar,
              matching: find.byKey(const ValueKey('media_action_more')),
            ),
            findsOneWidget,
          );
          for (final action in const <MediaViewerAction>[
            MediaViewerAction.save,
            MediaViewerAction.share,
            MediaViewerAction.info,
            MediaViewerAction.reply,
          ]) {
            expect(
              find.byKey(ValueKey('media_action_${action.name}')),
              findsNothing,
              reason: '${action.name} must stay inside the closed image menu',
            );
          }
          for (final action in const <MediaViewerAction>[
            MediaViewerAction.forward,
            MediaViewerAction.delete,
          ]) {
            final key = ValueKey('media_action_${action.name}');
            expect(find.byKey(key), findsOneWidget);
            expect(
              find.descendant(of: appBar, matching: find.byKey(key)),
              findsNothing,
              reason: '${action.name} must not remain in the top AppBar',
            );
          }

          await showViewerMoreMenu(tester);
          const imageMenuIcons = <MediaViewerAction, IconData>{
            MediaViewerAction.save: Icons.download_rounded,
            MediaViewerAction.share: Icons.ios_share_rounded,
            MediaViewerAction.info: Icons.info_outline_rounded,
            MediaViewerAction.reply: Icons.reply_rounded,
          };
          for (final entry in imageMenuIcons.entries) {
            final row = find.byKey(ValueKey('media_action_${entry.key.name}'));
            expect(row, findsOneWidget);
            expect(
              find.descendant(of: row, matching: find.byIcon(entry.value)),
              findsOneWidget,
              reason: '${entry.key.name} must keep its compact-menu icon',
            );
          }
          await selectViewerPopupAction(tester, MediaViewerAction.save);
          await pumpFrames(tester, count: 4);
          expect(controller.saves, [
            'group-1/$imageMessageId/$imageAttachmentId',
          ]);

          await tester.tap(find.byIcon(Icons.arrow_back));
          await pumpFrames(tester, count: 10);
          await tester.tap(
            find.byKey(
              const ValueKey('media-grid-cell-$gifMessageId-$gifAttachmentId'),
            ),
          );
          await pumpFrames(tester, count: 4);
          viewer = tester.widget<FullScreenTypedMediaViewer>(
            find.byType(FullScreenTypedMediaViewer),
          );
          expect(viewer.items.single.kind, MediaViewerKind.gif);
          expect(
            viewer.items.single.actionPresentation,
            MediaViewerActionPresentation.standardToolbar,
          );
          expect(find.byKey(const ValueKey('media_action_more')), findsNothing);
          expect(
            find.byKey(const ValueKey('media_action_save')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'incoming discussion video uses all-action keep-in-chat overflow without losing actions',
        (tester) async {
          tester.view.physicalSize = const Size(1200, 4000);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final group = makeChatGroup();
          await groupRepo.saveGroup(group);
          await saveActiveGroupMembers(groupRepo, group);
          const incomingMessageId = 'group-compact-video-message-313';
          const incomingAttachmentId = 'group-compact-video-attachment-313';
          const outgoingMessageId = 'group-outgoing-video-message-313';
          const outgoingAttachmentId = 'group-outgoing-video-attachment-313';
          await seedOrdinaryDoneVideo(
            messageId: incomingMessageId,
            attachmentId: incomingAttachmentId,
            isIncoming: true,
            caption: 'incoming compact video',
            mime: 'video/mp4',
            size: 4096,
            durationMs: 12000,
            timestamp: DateTime.utc(2026, 7, 31, 18, 1),
          );
          await seedOrdinaryDoneVideo(
            messageId: outgoingMessageId,
            attachmentId: outgoingAttachmentId,
            isIncoming: false,
            caption: 'outgoing standard video',
            mime: 'video/mp4',
            size: 8192,
            durationMs: 18000,
            timestamp: DateTime.utc(2026, 7, 31, 18, 2),
          );
          await tester.pumpWidget(
            buildWidget(
              group: group,
              mediaRepo: mediaAttachmentRepo,
              mediaFileManager: mediaFileManager,
              mediaActionsController: RecordingGroupMediaActionsController(
                messageRepository: msgRepo,
                mediaAttachmentRepository: mediaAttachmentRepo,
              ),
              mediaDeleteForMeCoordinator:
                  RecordingGroupMediaDeleteForMeCoordinator(),
              groupMediaForwardLauncher: (_, _) async {},
            ),
          );
          await pumpUntilMediaLoaded(tester, incomingMessageId);
          await pumpUntilMediaLoaded(tester, outgoingMessageId);
          await pumpUntilCanWrite(tester);

          await tester.tap(
            find.byKey(
              const ValueKey(
                'media-grid-cell-$incomingMessageId-$incomingAttachmentId',
              ),
            ),
          );
          await pumpFrames(tester, count: 4);
          var viewer = tester.widget<FullScreenTypedMediaViewer>(
            find.byType(FullScreenTypedMediaViewer),
          );
          final incomingItem = viewer.items.single;
          expect(incomingItem.kind, MediaViewerKind.video);
          expect(
            incomingItem.actionPresentation,
            MediaViewerActionPresentation.compactVideoOverflow,
          );
          expect(incomingItem.canEnterPictureInPicture, isTrue);
          const videoActions = <MediaViewerAction>[
            MediaViewerAction.save,
            MediaViewerAction.share,
            MediaViewerAction.info,
            MediaViewerAction.reply,
            MediaViewerAction.forward,
            MediaViewerAction.delete,
          ];
          expect(
            incomingItem.capabilities.allowed,
            unorderedEquals(videoActions),
          );
          expect(
            find.byKey(const ValueKey('media_action_more')),
            findsOneWidget,
          );
          for (final action in videoActions) {
            expect(
              find.byKey(ValueKey('media_action_${action.name}')),
              findsNothing,
              reason: '${action.name} escaped the closed video overflow',
            );
          }

          await showViewerMoreMenu(tester);
          const videoMenuIcons = <MediaViewerAction, IconData>{
            MediaViewerAction.save: Icons.download_rounded,
            MediaViewerAction.share: Icons.ios_share_rounded,
            MediaViewerAction.info: Icons.info_outline_rounded,
            MediaViewerAction.reply: Icons.reply_rounded,
            MediaViewerAction.forward: Icons.forward_rounded,
            MediaViewerAction.delete: Icons.delete_outline_rounded,
          };
          final appBar = find.byType(AppBar);
          for (final action in videoActions) {
            final row = find.byKey(ValueKey('media_action_${action.name}'));
            expect(row, findsOneWidget);
            expect(
              find.descendant(
                of: row,
                matching: find.byIcon(videoMenuIcons[action]!),
              ),
              findsOneWidget,
              reason: '${action.name} must keep its compact-menu icon',
            );
            expect(
              find.descendant(of: appBar, matching: row),
              findsNothing,
              reason: '${action.name} must not remain in the top AppBar',
            );
          }
          await tester.tapAt(const Offset(20, 300));
          await pumpFrames(tester, count: 4);

          await tester.tap(find.byIcon(Icons.arrow_back));
          await pumpFrames(tester, count: 10);
          await tester.tap(
            find.byKey(
              const ValueKey(
                'media-grid-cell-$outgoingMessageId-$outgoingAttachmentId',
              ),
            ),
          );
          await pumpFrames(tester, count: 4);
          viewer = tester.widget<FullScreenTypedMediaViewer>(
            find.byType(FullScreenTypedMediaViewer),
          );
          expect(viewer.items.single.kind, MediaViewerKind.video);
          expect(
            viewer.items.single.actionPresentation,
            MediaViewerActionPresentation.standardToolbar,
          );
          expect(viewer.items.single.canEnterPictureInPicture, isFalse);
          expect(viewer.items.single.capabilities.allowed, isEmpty);
          expect(find.byKey(const ValueKey('media_action_more')), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'ordinary discussion images hide automatic metadata for sender and receiver while Info and GIF remain',
        (tester) async {
          tester.view.physicalSize = const Size(1200, 4000);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final semantics = tester.ensureSemantics();
          final group = makeChatGroup();
          await groupRepo.saveGroup(group);
          await saveActiveGroupMembers(groupRepo, group);

          const incomingMessageId = 'group-image-incoming-message-314';
          const incomingAttachmentId = 'group-image-incoming-attachment-314';
          const outgoingMessageId = 'group-image-outgoing-message-314';
          const outgoingAttachmentId = 'group-image-outgoing-attachment-314';
          const gifMessageId = 'group-image-gif-message-314';
          const gifAttachmentId = 'group-image-gif-attachment-314';
          final incomingTimestamp = DateTime.utc(2026, 7, 31, 10, 11);
          final outgoingTimestamp = DateTime.utc(2026, 7, 31, 12, 13);
          await seedIncomingDoneImage(
            messageId: incomingMessageId,
            attachmentId: incomingAttachmentId,
            caption: 'GROUP_INCOMING_IMAGE_CAPTION_314',
            size: 8192,
            width: 641,
            height: 479,
            timestamp: incomingTimestamp,
          );
          await seedIncomingDoneImage(
            messageId: outgoingMessageId,
            attachmentId: outgoingAttachmentId,
            caption: '',
            senderPeerId: 'peer-self',
            mime: 'image/webp',
            isIncoming: false,
            size: 16384,
            width: 1280,
            height: 720,
            timestamp: outgoingTimestamp,
          );
          await seedIncomingDoneImage(
            messageId: gifMessageId,
            attachmentId: gifAttachmentId,
            caption: 'GROUP_GIF_CAPTION_314',
            mime: 'image/gif',
          );
          await tester.pumpWidget(
            buildWidget(
              group: group,
              mediaRepo: mediaAttachmentRepo,
              mediaFileManager: mediaFileManager,
              mediaActionsController: RecordingGroupMediaActionsController(
                messageRepository: msgRepo,
                mediaAttachmentRepository: mediaAttachmentRepo,
              ),
            ),
          );
          await pumpUntilMediaLoaded(tester, incomingMessageId);
          await pumpUntilMediaLoaded(tester, outgoingMessageId);
          await pumpUntilMediaLoaded(tester, gifMessageId);
          await pumpUntilCanWrite(tester);

          const detailKeys = <String>[
            'media_meta_sender',
            'media_meta_timestamp',
            'media_meta_mime',
            'media_meta_size',
            'media_meta_dimensions',
            'media_meta_duration',
          ];
          void expectHiddenDetails(List<String> values) {
            for (final key in detailKeys) {
              expect(find.byKey(ValueKey(key)), findsNothing);
            }
            for (final value in values) {
              expect(
                find.descendant(
                  of: find.byType(FullScreenTypedMediaViewer),
                  matching: find.text(value),
                ),
                findsNothing,
              );
              expect(
                find.descendant(
                  of: find.byType(FullScreenTypedMediaViewer),
                  matching: find.bySemanticsLabel(RegExp(RegExp.escape(value))),
                ),
                findsNothing,
              );
            }
          }

          Future<MediaViewerItem> open(
            String messageId,
            String attachmentId,
          ) async {
            await tester.tap(
              find.byKey(ValueKey('media-grid-cell-$messageId-$attachmentId')),
            );
            await pumpFrames(tester, count: 4);
            final viewer = tester.widget<FullScreenTypedMediaViewer>(
              find.byType(FullScreenTypedMediaViewer),
            );
            expect(viewer.items, hasLength(1));
            return viewer.items.single;
          }

          var item = await open(incomingMessageId, incomingAttachmentId);
          expect(item.kind, MediaViewerKind.image);
          expect(item.showMetadataDetails, isFalse);
          expect(item.mime, 'image/png');
          expect(item.sizeBytes, 8192);
          expect(item.width, 641);
          expect(item.height, 479);
          expect(item.timestamp, incomingTimestamp);
          expect(item.senderLabel, 'Alice');
          expect(item.caption, 'GROUP_INCOMING_IMAGE_CAPTION_314');
          expect(
            item.actionPresentation,
            MediaViewerActionPresentation.compactImageOverlay,
          );
          expect(
            item.capabilities.allowed,
            unorderedEquals(const <MediaViewerAction>[
              MediaViewerAction.save,
              MediaViewerAction.share,
              MediaViewerAction.info,
              MediaViewerAction.reply,
            ]),
          );
          expectHiddenDetails(const <String>[
            'Alice',
            'image/png',
            '8 KB',
            '641 × 479',
          ]);
          expect(
            tester
                .widget<Text>(find.byKey(const ValueKey('media_meta_caption')))
                .data,
            'GROUP_INCOMING_IMAGE_CAPTION_314',
          );

          final incomingViewer = tester.widget<FullScreenTypedMediaViewer>(
            find.byType(FullScreenTypedMediaViewer),
          );
          final infoFlight = incomingViewer.onAction!(
            item,
            MediaViewerAction.info,
          );
          await pumpFrames(tester, count: 10);
          expect(find.byKey(GroupMediaInfoSheet.sheetKey), findsOneWidget);
          expect(
            tester
                .widget<Text>(
                  find.byKey(const ValueKey('group-media-info-mime')),
                )
                .data,
            'image/png',
          );
          expect(
            tester
                .widget<Text>(
                  find.byKey(const ValueKey('group-media-info-size')),
                )
                .data,
            '8 KB',
          );
          expect(
            tester
                .widget<Text>(
                  find.byKey(const ValueKey('group-media-info-dimensions')),
                )
                .data,
            '641 × 479',
          );
          await tester.tapAt(const Offset(5, 5));
          await pumpFrames(tester, count: 10);
          expect(await infoFlight, MediaViewerActionResult.success);
          await tester.tap(find.byIcon(Icons.arrow_back));
          await pumpFrames(tester, count: 10);

          item = await open(outgoingMessageId, outgoingAttachmentId);
          expect(item.kind, MediaViewerKind.image);
          expect(item.showMetadataDetails, isFalse);
          expect(item.mime, 'image/webp');
          expect(item.sizeBytes, 16384);
          expect(item.width, 1280);
          expect(item.height, 720);
          expect(item.timestamp, outgoingTimestamp);
          expect(item.senderLabel, 'You');
          expect(item.caption, isNull);
          expect(
            item.actionPresentation,
            MediaViewerActionPresentation.standardToolbar,
          );
          expect(item.capabilities.allows(MediaViewerAction.info), isFalse);
          expectHiddenDetails(const <String>[
            'You',
            'image/webp',
            '16 KB',
            '1280 × 720',
          ]);
          expect(
            find.byKey(const ValueKey('media_viewer_metadata_content')),
            findsNothing,
          );
          await tester.tap(find.byIcon(Icons.arrow_back));
          await pumpFrames(tester, count: 10);

          item = await open(gifMessageId, gifAttachmentId);
          expect(item.kind, MediaViewerKind.gif);
          expect(item.showMetadataDetails, isTrue);
          expect(
            tester
                .widget<Text>(find.byKey(const ValueKey('media_meta_mime')))
                .data,
            'image/gif',
          );
          expect(
            tester
                .widget<Text>(find.byKey(const ValueKey('media_meta_caption')))
                .data,
            'GROUP_GIF_CAPTION_314',
          );
          semantics.dispose();
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'ordinary group videos hide automatic metadata for sender and receiver while Info retains it',
        (tester) async {
          tester.view.physicalSize = const Size(1200, 4000);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final semantics = tester.ensureSemantics();
          final group = makeChatGroup();
          await groupRepo.saveGroup(group);
          await saveActiveGroupMembers(groupRepo, group);
          const incomingMessageId = 'group-video-incoming-message-312';
          const incomingAttachmentId = 'group-video-incoming-attachment-312';
          const outgoingMessageId = 'group-video-outgoing-message-312';
          const outgoingAttachmentId = 'group-video-outgoing-attachment-312';
          const gifMessageId = 'group-gif-message-312';
          const gifAttachmentId = 'group-gif-attachment-312';
          final incomingTimestamp = DateTime.utc(2026, 7, 14, 10, 11);
          final outgoingTimestamp = DateTime.utc(2026, 7, 15, 12, 13);
          await seedOrdinaryDoneVideo(
            messageId: incomingMessageId,
            attachmentId: incomingAttachmentId,
            isIncoming: true,
            caption: 'GROUP_INCOMING_VIDEO_CAPTION_312',
            mime: 'video/x-group-incoming-312',
            size: 8192,
            durationMs: 83000,
            timestamp: incomingTimestamp,
          );
          await seedOrdinaryDoneVideo(
            messageId: outgoingMessageId,
            attachmentId: outgoingAttachmentId,
            isIncoming: false,
            caption: '',
            mime: 'video/x-group-outgoing-312',
            size: 16384,
            durationMs: 65000,
            timestamp: outgoingTimestamp,
          );
          await seedIncomingDoneImage(
            messageId: gifMessageId,
            attachmentId: gifAttachmentId,
            caption: 'GROUP_GIF_CAPTION_312',
            mime: 'image/gif',
          );
          await tester.pumpWidget(
            buildWidget(
              group: group,
              mediaRepo: mediaAttachmentRepo,
              mediaFileManager: mediaFileManager,
              mediaActionsController: RecordingGroupMediaActionsController(
                messageRepository: msgRepo,
                mediaAttachmentRepository: mediaAttachmentRepo,
              ),
            ),
          );
          await pumpUntilMediaLoaded(tester, incomingMessageId);
          await pumpUntilMediaLoaded(tester, outgoingMessageId);
          await pumpUntilMediaLoaded(tester, gifMessageId);

          const detailKeys = <String>[
            'media_meta_sender',
            'media_meta_timestamp',
            'media_meta_mime',
            'media_meta_size',
            'media_meta_dimensions',
            'media_meta_duration',
          ];
          void expectHiddenDetails(List<String> values) {
            for (final key in detailKeys) {
              expect(find.byKey(ValueKey(key)), findsNothing);
            }
            for (final value in values) {
              expect(
                find.descendant(
                  of: find.byType(FullScreenTypedMediaViewer),
                  matching: find.text(value),
                ),
                findsNothing,
              );
              expect(
                find.descendant(
                  of: find.byType(FullScreenTypedMediaViewer),
                  matching: find.bySemanticsLabel(RegExp(RegExp.escape(value))),
                ),
                findsNothing,
              );
            }
          }

          Future<MediaViewerItem> open(
            String messageId,
            String attachmentId,
          ) async {
            await tester.tap(
              find.byKey(ValueKey('media-grid-cell-$messageId-$attachmentId')),
            );
            await pumpFrames(tester, count: 4);
            final viewer = tester.widget<FullScreenTypedMediaViewer>(
              find.byType(FullScreenTypedMediaViewer),
            );
            expect(viewer.items, hasLength(1));
            return viewer.items.single;
          }

          var item = await open(incomingMessageId, incomingAttachmentId);
          expect(item.kind, MediaViewerKind.video);
          expect(item.showMetadataDetails, isFalse);
          expect(item.mime, 'video/x-group-incoming-312');
          expect(item.sizeBytes, 8192);
          expect(item.durationMs, 83000);
          expect(item.width, 1920);
          expect(item.height, 1080);
          expect(item.timestamp, incomingTimestamp);
          expect(item.senderLabel, 'Alice');
          expect(item.caption, 'GROUP_INCOMING_VIDEO_CAPTION_312');
          expectHiddenDetails(const <String>[
            'Alice',
            'video/x-group-incoming-312',
            '8 KB',
            '1:23',
          ]);
          expect(
            tester
                .widget<Text>(find.byKey(const ValueKey('media_meta_caption')))
                .data,
            'GROUP_INCOMING_VIDEO_CAPTION_312',
          );
          expect(find.byKey(const ValueKey('media_action_info')), findsNothing);
          await showViewerMoreMenu(tester);
          expect(
            find.byKey(const ValueKey('media_action_info')),
            findsOneWidget,
          );
          await tester.tapAt(const Offset(20, 300));
          await pumpFrames(tester, count: 4);
          final viewer = tester.widget<FullScreenTypedMediaViewer>(
            find.byType(FullScreenTypedMediaViewer),
          );
          final infoFlight = viewer.onAction!(item, MediaViewerAction.info);
          await pumpFrames(tester, count: 10);
          expect(find.byKey(GroupMediaInfoSheet.sheetKey), findsOneWidget);
          expect(
            tester
                .widget<Text>(
                  find.byKey(const ValueKey('group-media-info-mime')),
                )
                .data,
            'video/x-group-incoming-312',
          );
          expect(
            tester
                .widget<Text>(
                  find.byKey(const ValueKey('group-media-info-size')),
                )
                .data,
            '8 KB',
          );
          expect(
            tester
                .widget<Text>(
                  find.byKey(const ValueKey('group-media-info-duration')),
                )
                .data,
            '1:23',
          );
          await tester.tapAt(const Offset(5, 5));
          await pumpFrames(tester, count: 10);
          expect(await infoFlight, MediaViewerActionResult.success);
          await tester.tap(find.byIcon(Icons.arrow_back));
          await pumpFrames(tester, count: 10);

          item = await open(outgoingMessageId, outgoingAttachmentId);
          expect(item.kind, MediaViewerKind.video);
          expect(item.showMetadataDetails, isFalse);
          expect(item.mime, 'video/x-group-outgoing-312');
          expect(item.sizeBytes, 16384);
          expect(item.durationMs, 65000);
          expect(item.timestamp, outgoingTimestamp);
          expect(item.senderLabel, 'You');
          expect(item.caption, isNull);
          expectHiddenDetails(const <String>[
            'You',
            'video/x-group-outgoing-312',
            '16 KB',
            '1:05',
          ]);
          expect(
            find.byKey(const ValueKey('media_viewer_metadata_content')),
            findsNothing,
          );
          expect(find.byKey(const ValueKey('media_action_info')), findsNothing);
          await tester.tap(find.byIcon(Icons.arrow_back));
          await pumpFrames(tester, count: 10);

          item = await open(gifMessageId, gifAttachmentId);
          expect(item.kind, MediaViewerKind.gif);
          expect(item.showMetadataDetails, isTrue);
          expect(
            tester
                .widget<Text>(find.byKey(const ValueKey('media_meta_mime')))
                .data,
            'image/gif',
          );
          expect(
            tester
                .widget<Text>(find.byKey(const ValueKey('media_meta_caption')))
                .data,
            'GROUP_GIF_CAPTION_312',
          );
          semantics.dispose();
          expect(tester.takeException(), isNull);
        },
      );

      testWidgets(
        'GMA-03 viewer selection and reopen preserve exact attachment identity',
        (tester) async {
          tester.view.physicalSize = const Size(1200, 4000);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final group = makeChatGroup();
          await groupRepo.saveGroup(group);
          await saveActiveGroupMembers(groupRepo, group);
          await seedIncomingDoneImage(
            messageId: 'msg-a',
            attachmentId: 'att-a',
          );
          // Second attachment on the SAME parent.
          final relativeB = mediaFileManager.relativePathForAttachment(
            contactPeerId: 'group-1',
            blobId: 'att-b',
            mime: 'image/png',
          );
          final absoluteB = await mediaFileManager.resolveStoredPath(relativeB);
          File(absoluteB)
            ..parent.createSync(recursive: true)
            ..writeAsBytesSync(_tinyPngBytes, flush: true);
          await mediaAttachmentRepo.saveAttachment(
            MediaAttachment(
              id: 'att-b',
              messageId: 'msg-a',
              mime: 'image/png',
              size: _tinyPngBytes.length,
              mediaType: 'image',
              localPath: absoluteB,
              downloadStatus: kMediaDownloadStatusDone,
              createdAt: DateTime.now().toUtc().toIso8601String(),
              contentHash: _validContentHash,
              encryptionKeyBase64: 'a2V5',
              encryptionNonce: 'bm9uY2U=',
              encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            ),
            owner: MediaOwnerLane.group,
          );
          // A DIFFERENT parent with its own attachment.
          await seedIncomingDoneImage(
            messageId: 'msg-b',
            attachmentId: 'att-c',
          );

          final controller = RecordingGroupMediaActionsController(
            messageRepository: msgRepo,
            mediaAttachmentRepository: mediaAttachmentRepo,
          );
          await tester.pumpWidget(
            buildWidget(
              group: group,
              mediaRepo: mediaAttachmentRepo,
              mediaFileManager: mediaFileManager,
              mediaActionsController: controller,
            ),
          );
          await pumpUntilMediaLoaded(tester, 'msg-a', expectedCount: 2);
          await pumpUntilMediaLoaded(tester, 'msg-b');

          // Open the viewer on the SECOND attachment of msg-a.
          await tester.tap(
            find.byKey(const ValueKey('media-grid-cell-msg-a-att-b')),
          );
          await pumpFrames(tester, count: 4);
          expect(find.byType(FullScreenTypedMediaViewer), findsOneWidget);
          var viewer = tester.widget<FullScreenTypedMediaViewer>(
            find.byType(FullScreenTypedMediaViewer),
          );
          expect(
            viewer.items.map((item) => item.attachmentId).toList(),
            ['att-a', 'att-b'],
            reason:
                'viewer pages are ONLY this parent\'s attachments — '
                'no conversation-wide swipe navigation',
          );
          expect(viewer.initialIndex, 1);
          expect(viewer.items[1].messageId, 'msg-a');

          // The dispatched action carries the exact selected item.
          await showViewerMoreMenu(tester);
          await selectViewerPopupAction(tester, MediaViewerAction.save);
          await pumpFrames(tester, count: 10);
          expect(controller.saves, ['group-1/msg-a/att-b']);
          expect(find.byKey(const ValueKey('media_action_save')), findsNothing);

          // Reopen from a fresh mount and a different parent: identity follows
          // the newly selected row rather than the previous viewer item.
          await tester.pumpWidget(const SizedBox.shrink());
          expect(find.byType(FullScreenTypedMediaViewer), findsNothing);
          await tester.pumpWidget(
            buildWidget(
              group: group,
              mediaRepo: mediaAttachmentRepo,
              mediaFileManager: mediaFileManager,
              mediaActionsController: controller,
            ),
          );
          await pumpUntilMediaLoaded(tester, 'msg-b');
          await tester.tap(
            find.byKey(const ValueKey('media-grid-cell-msg-b-att-c')),
          );
          await pumpFrames(tester, count: 4);
          viewer = tester.widget<FullScreenTypedMediaViewer>(
            find.byType(FullScreenTypedMediaViewer),
          );
          expect(viewer.items.map((item) => item.attachmentId).toList(), [
            'att-c',
          ]);
          expect(viewer.initialIndex, 0);
          await showViewerMoreMenu(tester);
          await selectViewerPopupAction(tester, MediaViewerAction.save);
          await pumpFrames(tester, count: 4);
          expect(controller.saves, [
            'group-1/msg-a/att-b',
            'group-1/msg-b/att-c',
          ]);
        },
      );

      testWidgets(
        'GPL-04F injected Forward launcher requalifies after attachment await before picker',
        (tester) async {
          tester.view.physicalSize = const Size(1200, 4000);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final group = makeChatGroup();
          await groupRepo.saveGroup(group);
          await saveActiveGroupMembers(groupRepo, group);
          final gatedMedia = GateFirstSingleMediaReadRepository();
          mediaAttachmentRepo = gatedMedia;
          const messageId = 'gpl-04f-injected-message';
          const attachmentId = 'gpl-04f-injected-attachment';
          await seedIncomingDoneImage(
            messageId: messageId,
            attachmentId: attachmentId,
          );
          var launcherCalls = 0;
          await tester.pumpWidget(
            buildWidget(
              group: group,
              mediaRepo: gatedMedia,
              mediaFileManager: mediaFileManager,
              groupMediaForwardLauncher: (_, _) async {
                launcherCalls++;
              },
            ),
          );
          await pumpUntilMediaLoaded(tester, messageId);
          final cellKey = ValueKey('media-grid-cell-$messageId-$attachmentId');
          await tester.tap(find.byKey(cellKey));
          await pumpFrames(tester, count: 4);
          expect(find.byType(FullScreenTypedMediaViewer), findsOneWidget);
          expect(
            find.byKey(const ValueKey('media_action_forward')),
            findsOneWidget,
          );

          gatedMedia.armed = true;
          final pathResolvesBeforeForward =
              mediaFileManager.resolveStoredPathCount;
          final viewer = tester.widget<FullScreenTypedMediaViewer>(
            find.byType(FullScreenTypedMediaViewer),
          );
          final forwardFlight = viewer.onAction!(
            viewer.items.single,
            MediaViewerAction.forward,
          );
          await tester.pump();
          await tester.runAsync(
            () => gatedMedia.firstReadCaptured.future.timeout(
              const Duration(seconds: 2),
            ),
          );
          await msgRepo.saveMessage(
            makeMessage(
              id: messageId,
              text: 'PRIVATE CAPTION MUST NOT REACH PICKER',
              privateMediaPolicy: const GroupPrivateMediaPolicy.viewOnce(),
            ),
          );
          gatedMedia.releaseFirstRead.complete();
          await pumpFrames(tester, count: 10);

          expect(launcherCalls, 0);
          expect(
            mediaFileManager.resolveStoredPathCount,
            pathResolvesBeforeForward,
          );
          expect(await forwardFlight, MediaViewerActionResult.failure);
          expect(find.byType(FullScreenTypedMediaViewer), findsOneWidget);
        },
      );

      testWidgets(
        'GPL-04P denied canonical preview never opens picker or exposes its file path',
        (tester) async {
          tester.view.physicalSize = const Size(1200, 4000);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final group = makeChatGroup();
          await groupRepo.saveGroup(group);
          await saveActiveGroupMembers(groupRepo, group);
          const messageId = 'gpl-04p-message';
          const attachmentId = 'gpl-04p-attachment';
          await seedIncomingDoneImage(
            messageId: messageId,
            attachmentId: attachmentId,
          );

          final outsideDirectory = Directory.systemTemp.createTempSync(
            'gpl_04p_noncanonical_',
          );
          addTearDown(() {
            if (outsideDirectory.existsSync()) {
              outsideDirectory.deleteSync(recursive: true);
            }
          });
          final outsideFile = File(p.join(outsideDirectory.path, 'source.png'))
            ..writeAsBytesSync(_tinyPngBytes);
          final seededRows = await mediaAttachmentRepo.getAttachmentsForMessage(
            messageId,
            owner: MediaOwnerLane.group,
          );
          await mediaAttachmentRepo.saveAttachment(
            seededRows.single.copyWith(localPath: outsideFile.path),
            owner: MediaOwnerLane.group,
          );

          final directMessages = InMemoryMessageRepository();
          final directListener = ChatMessageListener(
            chatMessageStream: const Stream<ChatMessage>.empty(),
            messageRepo: directMessages,
            contactRepo: contactRepo,
          );
          addTearDown(directListener.dispose);
          await tester.pumpWidget(
            buildWidget(
              group: group,
              mediaRepo: mediaAttachmentRepo,
              mediaFileManager: mediaFileManager,
              imageProcessor: ImageProcessor(),
              forwardMessageRepository: directMessages,
              forwardChatMessageListener: directListener,
            ),
          );
          await pumpUntilMediaLoaded(tester, messageId);
          await tester.tap(
            find.byKey(
              const ValueKey(
                'media-grid-cell-gpl-04p-message-gpl-04p-attachment',
              ),
            ),
          );
          await pumpFrames(tester, count: 4);
          expect(find.byType(FullScreenTypedMediaViewer), findsOneWidget);
          expect(
            find.byKey(const ValueKey('media_action_forward')),
            findsOneWidget,
          );

          final viewer = tester.widget<FullScreenTypedMediaViewer>(
            find.byType(FullScreenTypedMediaViewer),
          );
          final forwardResult = await viewer.onAction!(
            viewer.items.single,
            MediaViewerAction.forward,
          );
          await pumpFrames(tester, count: 10);

          expect(forwardResult, MediaViewerActionResult.failure);
          expect(find.byType(ShareTargetPickerWired), findsNothing);
          expect(find.byType(FullScreenTypedMediaViewer), findsOneWidget);
        },
      );

      testWidgets(
        'GPL-04S final-validator attachment drift keeps picker closed and exposes no path',
        (tester) async {
          tester.view.physicalSize = const Size(1200, 4000);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final group = makeChatGroup();
          await groupRepo.saveGroup(group);
          await saveActiveGroupMembers(groupRepo, group);
          const messageId = 'gpl-04s-message';
          const attachmentId = 'gpl-04s-attachment';
          final gatedFiles = _GateForwardCanonicalValidatorFileManager();
          mediaFileManager = gatedFiles;
          addTearDown(() {
            if (!gatedFiles.release.isCompleted) {
              gatedFiles.release.complete();
            }
          });
          await seedIncomingDoneImage(
            messageId: messageId,
            attachmentId: attachmentId,
          );

          final directMessages = InMemoryMessageRepository();
          final directListener = ChatMessageListener(
            chatMessageStream: const Stream<ChatMessage>.empty(),
            messageRepo: directMessages,
            contactRepo: contactRepo,
          );
          addTearDown(directListener.dispose);
          await tester.pumpWidget(
            buildWidget(
              group: group,
              mediaRepo: mediaAttachmentRepo,
              mediaFileManager: gatedFiles,
              imageProcessor: ImageProcessor(),
              forwardMessageRepository: directMessages,
              forwardChatMessageListener: directListener,
            ),
          );
          await pumpUntilMediaLoaded(tester, messageId);
          await tester.tap(
            find.byKey(
              const ValueKey(
                'media-grid-cell-gpl-04s-message-gpl-04s-attachment',
              ),
            ),
          );
          await pumpFrames(tester, count: 4);
          expect(find.byType(FullScreenTypedMediaViewer), findsOneWidget);
          expect(
            find.byKey(const ValueKey('media_action_forward')),
            findsOneWidget,
          );

          gatedFiles.armed = true;
          final viewer = tester.widget<FullScreenTypedMediaViewer>(
            find.byType(FullScreenTypedMediaViewer),
          );
          unawaited(
            viewer.onAction!(viewer.items.single, MediaViewerAction.forward),
          );
          await tester.pump();
          await tester.runAsync(
            () =>
                gatedFiles.captured.future.timeout(const Duration(seconds: 2)),
          );
          await mediaAttachmentRepo.updateDownloadStatus(
            attachmentId,
            'evicted',
          );
          gatedFiles.release.complete();
          await pumpFrames(tester, count: 10);

          expect(find.byType(ShareTargetPickerWired), findsNothing);
          expect(find.byType(FullScreenTypedMediaViewer), findsOneWidget);
        },
      );

      testWidgets(
        'GPL-04O final parent drift during exact-row await keeps picker closed',
        (tester) async {
          tester.view.physicalSize = const Size(1200, 4000);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final group = makeChatGroup();
          await groupRepo.saveGroup(group);
          await saveActiveGroupMembers(groupRepo, group);
          final exactRowAwait = GateNthExactMediaReadRepository();
          mediaAttachmentRepo = exactRowAwait;
          addTearDown(exactRowAwait.release);
          const messageId = 'gpl-04o-message';
          const attachmentId = 'gpl-04o-attachment';
          await seedIncomingDoneImage(
            messageId: messageId,
            attachmentId: attachmentId,
          );

          final directMessages = InMemoryMessageRepository();
          final directListener = ChatMessageListener(
            chatMessageStream: const Stream<ChatMessage>.empty(),
            messageRepo: directMessages,
            contactRepo: contactRepo,
          );
          addTearDown(directListener.dispose);
          await tester.pumpWidget(
            buildWidget(
              group: group,
              mediaRepo: exactRowAwait,
              mediaFileManager: mediaFileManager,
              imageProcessor: ImageProcessor(),
              forwardMessageRepository: directMessages,
              forwardChatMessageListener: directListener,
            ),
          );
          await pumpUntilMediaLoaded(tester, messageId);
          await tester.tap(
            find.byKey(
              const ValueKey(
                'media-grid-cell-gpl-04o-message-gpl-04o-attachment',
              ),
            ),
          );
          await pumpFrames(tester, count: 4);
          expect(find.byType(FullScreenTypedMediaViewer), findsOneWidget);
          expect(
            find.byKey(const ValueKey('media_action_forward')),
            findsOneWidget,
          );

          exactRowAwait.gateAfterExactReads(2);
          final viewer = tester.widget<FullScreenTypedMediaViewer>(
            find.byType(FullScreenTypedMediaViewer),
          );
          final forwardFlight = viewer.onAction!(
            viewer.items.single,
            MediaViewerAction.forward,
          );
          await tester.pump();
          for (var i = 0; i < 40 && !exactRowAwait.hasCaptured; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 25)),
            );
            await tester.pump();
          }
          expect(
            exactRowAwait.hasCaptured,
            isTrue,
            reason:
                'forward preview made ${exactRowAwait.exactReadCalls} exact reads',
          );
          await msgRepo.saveMessage(
            makeMessage(
              id: messageId,
              text: 'PRIVATE CAPTION MUST NOT REACH PICKER',
              privateMediaPolicy: const GroupPrivateMediaPolicy.viewOnce(),
            ),
          );
          exactRowAwait.release();
          await pumpFrames(tester, count: 10);

          expect(await forwardFlight, MediaViewerActionResult.failure);
          expect(find.byType(ShareTargetPickerWired), findsNothing);
          expect(find.byType(FullScreenTypedMediaViewer), findsOneWidget);
        },
      );

      testWidgets(
        'GPL-09I stale viewer and bubble Info reload parent before metadata exposure',
        (tester) async {
          tester.view.physicalSize = const Size(1200, 4000);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final group = makeChatGroup();
          await groupRepo.saveGroup(group);
          await saveActiveGroupMembers(groupRepo, group);
          const messageId = 'gpl-09i-message';
          const attachmentId = 'gpl-09i-attachment';
          await seedIncomingDoneImage(
            messageId: messageId,
            attachmentId: attachmentId,
            caption: 'ordinary caption',
          );
          await tester.pumpWidget(
            buildWidget(
              group: group,
              mediaRepo: mediaAttachmentRepo,
              mediaFileManager: mediaFileManager,
              mediaActionsController: RecordingGroupMediaActionsController(
                messageRepository: msgRepo,
                mediaAttachmentRepository: mediaAttachmentRepo,
              ),
            ),
          );
          await pumpUntilMediaLoaded(tester, messageId);
          const cellKey = ValueKey(
            'media-grid-cell-gpl-09i-message-gpl-09i-attachment',
          );

          await tester.tap(find.byKey(cellKey));
          await pumpFrames(tester, count: 4);
          expect(find.byType(FullScreenTypedMediaViewer), findsOneWidget);
          await msgRepo.saveMessage(
            makeMessage(
              id: messageId,
              text: 'PRIVATE CAPTION MUST NOT ENTER INFO',
              privateMediaPolicy: const GroupPrivateMediaPolicy.viewOnce(),
            ),
          );
          final viewer = tester.widget<FullScreenTypedMediaViewer>(
            find.byType(FullScreenTypedMediaViewer),
          );
          final infoResult = await viewer.onAction!(
            viewer.items.single,
            MediaViewerAction.info,
          );
          expect(infoResult, MediaViewerActionResult.failure);
          await pumpFrames(tester, count: 10);
          expect(find.byKey(GroupMediaInfoSheet.sheetKey), findsNothing);
          await tester.tap(find.byIcon(Icons.arrow_back));
          await pumpFrames(tester, count: 10);

          await msgRepo.saveMessage(
            makeMessage(id: messageId, text: 'ordinary caption'),
          );
          await tester.longPress(find.byKey(cellKey));
          await pumpFrames(tester, count: 4);
          expect(
            find.byKey(MessageContextOverlay.infoActionKey),
            findsOneWidget,
          );
          await msgRepo.saveMessage(
            makeMessage(
              id: messageId,
              text: 'PRIVATE CAPTION MUST NOT ENTER INFO',
              privateMediaPolicy: const GroupPrivateMediaPolicy.unsupported(
                sourceVersion: 9,
              ),
            ),
          );
          await tester.tap(find.byKey(MessageContextOverlay.infoActionKey));
          await pumpFrames(tester, count: 10);
          expect(find.byKey(GroupMediaInfoSheet.sheetKey), findsNothing);
          expect(find.text('image/png'), findsNothing);
          expect(
            find.text('PRIVATE CAPTION MUST NOT ENTER INFO'),
            findsNothing,
          );
        },
      );

      testWidgets(
        'GPL-09J Info reloads a parent that drifts private during attachment lookup before metadata',
        (tester) async {
          tester.view.physicalSize = const Size(1200, 4000);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final group = makeChatGroup();
          await groupRepo.saveGroup(group);
          await saveActiveGroupMembers(groupRepo, group);
          final gatedMedia = GateFirstSingleMediaReadRepository();
          mediaAttachmentRepo = gatedMedia;
          const messageId = 'gpl-09j-message';
          const attachmentId = 'gpl-09j-attachment';
          await seedIncomingDoneImage(
            messageId: messageId,
            attachmentId: attachmentId,
            caption: 'ordinary caption before awaited drift',
          );
          await tester.pumpWidget(
            buildWidget(
              group: group,
              mediaRepo: gatedMedia,
              mediaFileManager: mediaFileManager,
              mediaActionsController: RecordingGroupMediaActionsController(
                messageRepository: msgRepo,
                mediaAttachmentRepository: gatedMedia,
              ),
            ),
          );
          await pumpUntilMediaLoaded(tester, messageId);
          await tester.tap(
            find.byKey(
              const ValueKey(
                'media-grid-cell-gpl-09j-message-gpl-09j-attachment',
              ),
            ),
          );
          await pumpFrames(tester, count: 4);
          final viewer = tester.widget<FullScreenTypedMediaViewer>(
            find.byType(FullScreenTypedMediaViewer),
          );

          gatedMedia.armed = true;
          final infoFuture = viewer.onAction!(
            viewer.items.single,
            MediaViewerAction.info,
          );
          await tester.runAsync(
            () => gatedMedia.firstReadCaptured.future.timeout(
              const Duration(seconds: 2),
            ),
          );
          await msgRepo.saveMessage(
            makeMessage(
              id: messageId,
              text: 'PRIVATE CAPTION MUST NOT ENTER INFO AFTER AWAIT',
              privateMediaPolicy: const GroupPrivateMediaPolicy.viewOnce(),
            ),
          );
          gatedMedia.releaseFirstRead.complete();
          await pumpFrames(tester, count: 10);

          expect(find.byKey(GroupMediaInfoSheet.sheetKey), findsNothing);
          expect(
            find.text('PRIVATE CAPTION MUST NOT ENTER INFO AFTER AWAIT'),
            findsNothing,
          );
          expect(await infoFuture, MediaViewerActionResult.failure);
        },
      );

      testWidgets('GMA-05 media reply reuses existing group quote flow', (
        tester,
      ) async {
        tester.view.physicalSize = const Size(1200, 4000);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        await seedIncomingDoneImage(
          messageId: 'msg-m',
          attachmentId: 'att-1',
          caption: 'reply to this photo',
        );
        await tester.pumpWidget(
          buildWidget(
            group: group,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            mediaActionsController: RecordingGroupMediaActionsController(
              messageRepository: msgRepo,
              mediaAttachmentRepository: mediaAttachmentRepo,
            ),
          ),
        );
        await pumpUntilMediaLoaded(tester, 'msg-m');

        // Viewer Reply pops the viewer and arms the existing quote composer.
        await tester.tap(
          find.byKey(const ValueKey('media-grid-cell-msg-m-att-1')),
        );
        await pumpFrames(tester, count: 4);
        await showViewerMoreMenu(tester);
        expect(
          find.byKey(const ValueKey('media_action_reply')),
          findsOneWidget,
        );
        await selectViewerPopupAction(tester, MediaViewerAction.reply);
        await pumpFrames(tester, count: 10);
        expect(find.byType(FullScreenTypedMediaViewer), findsNothing);
        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(screen.activeQuoteText, 'reply to this photo');

        // canWrite == false (no current send key): the viewer offers no Reply
        // slot at all. Empty membership is deliberately ambiguous (startup
        // window) and never infers removal, so the missing-key gate is the
        // deterministic read-only lever here.
        final readOnlyGroup = makeChatGroup(role: GroupRole.member);
        groupRepo = InMemoryGroupRepository();
        await groupRepo.saveGroup(readOnlyGroup);
        await saveActiveGroupMembers(groupRepo, readOnlyGroup);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          buildWidget(
            group: readOnlyGroup,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            mediaActionsController: RecordingGroupMediaActionsController(
              messageRepository: msgRepo,
              mediaAttachmentRepository: mediaAttachmentRepo,
            ),
          ),
        );
        await pumpUntilMediaLoaded(tester, 'msg-m');
        // Wait for the security-status load to settle the write gate.
        for (var i = 0; i < 40; i++) {
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          if (!screen.canWrite) break;
          await tester.runAsync(() async {
            await Future<void>.delayed(const Duration(milliseconds: 25));
          });
          await tester.pump();
        }
        expect(
          tester
              .widget<GroupConversationScreen>(
                find.byType(GroupConversationScreen),
              )
              .canWrite,
          isFalse,
          reason: 'self is not an active member -> read-only',
        );
        await tester.tap(
          find.byKey(const ValueKey('media-grid-cell-msg-m-att-1')),
        );
        await pumpFrames(tester, count: 4);
        expect(find.byType(FullScreenTypedMediaViewer), findsOneWidget);
        await showViewerMoreMenu(tester);
        expect(find.byKey(const ValueKey('media_action_reply')), findsNothing);
        expect(find.byKey(const ValueKey('media_action_save')), findsOneWidget);
      });

      testWidgets(
        'GMA-11 wired media actions reach only injected coordinators',
        (tester) async {
          tester.view.physicalSize = const Size(1200, 4000);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final group = makeChatGroup();
          await groupRepo.saveGroup(group);
          await saveActiveGroupMembers(groupRepo, group);
          await seedIncomingDoneImage(
            messageId: 'msg-m',
            attachmentId: 'att-1',
          );
          final controller = RecordingGroupMediaActionsController(
            messageRepository: msgRepo,
            mediaAttachmentRepository: mediaAttachmentRepo,
          );
          final deleteCoordinator = RecordingGroupMediaDeleteForMeCoordinator();
          await tester.pumpWidget(
            buildWidget(
              group: group,
              mediaRepo: mediaAttachmentRepo,
              mediaFileManager: mediaFileManager,
              mediaActionsController: controller,
              mediaDeleteForMeCoordinator: deleteCoordinator,
            ),
          );
          await pumpUntilMediaLoaded(tester, 'msg-m');
          final commandsBefore = bridge.commandLog.length;

          // Bubble long-press → Save reaches ONLY the injected controller.
          await tester.longPress(
            find.byKey(const ValueKey('media-grid-cell-msg-m-att-1')),
          );
          await pumpFrames(tester, count: 4);
          await tester.tap(find.byKey(MessageContextOverlay.saveActionKey));
          await pumpFrames(tester, count: 10);
          expect(controller.saves, ['group-1/msg-m/att-1']);
          expect(controller.egressServiceTouched, isFalse);

          // Viewer Share reaches ONLY the injected controller.
          await tester.tap(
            find.byKey(const ValueKey('media-grid-cell-msg-m-att-1')),
          );
          await pumpFrames(tester, count: 4);
          await showViewerMoreMenu(tester);
          await selectViewerPopupAction(tester, MediaViewerAction.share);
          await pumpFrames(tester, count: 4);
          expect(controller.shares, ['group-1/msg-m/att-1']);
          await tester.tap(find.byIcon(Icons.arrow_back));
          await pumpFrames(tester, count: 10);

          // Delete: cancel is a zero-op.
          await tester.longPress(
            find.byKey(const ValueKey('media-grid-cell-msg-m-att-1')),
          );
          await pumpFrames(tester, count: 4);
          await tester.tap(find.byKey(MessageContextOverlay.deleteActionKey));
          await pumpFrames(tester, count: 10);
          expect(
            find.byKey(const ValueKey('group-media-delete-confirm')),
            findsOneWidget,
          );
          await tester.tap(
            find.byKey(const ValueKey('group-media-delete-cancel')),
          );
          await pumpFrames(tester, count: 10);
          expect(deleteCoordinator.calls, isEmpty);

          // One confirm yields exactly one coordinator operation.
          await tester.longPress(
            find.byKey(const ValueKey('media-grid-cell-msg-m-att-1')),
          );
          await pumpFrames(tester, count: 4);
          await tester.tap(find.byKey(MessageContextOverlay.deleteActionKey));
          await pumpFrames(tester, count: 10);
          await tester.tap(
            find.byKey(const ValueKey('group-media-delete-confirm')),
          );
          await pumpFrames(tester, count: 10);
          expect(deleteCoordinator.calls, ['group-1/msg-m']);

          // No send/publish/batch-delivery seam was touched by any action.
          expect(
            bridge.commandLog
                .skip(commandsBefore)
                .where(
                  (raw) =>
                      raw.contains('group:publish') ||
                      raw.contains('group:sendReliable') ||
                      raw.contains('group:inboxStore'),
                ),
            isEmpty,
          );
        },
      );

      testWidgets(
        'GMA-13 announcement member and admin expose core media actions without reply while qa stays excluded',
        (tester) async {
          tester.view.physicalSize = const Size(1200, 4000);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          Future<void> settleCanWrite(bool expected) async {
            for (var i = 0; i < 40; i++) {
              final screen = tester.widget<GroupConversationScreen>(
                find.byType(GroupConversationScreen),
              );
              if (screen.canWrite == expected) break;
              await tester.runAsync(() async {
                await Future<void>.delayed(const Duration(milliseconds: 25));
              });
              await tester.pump();
            }
            expect(
              tester
                  .widget<GroupConversationScreen>(
                    find.byType(GroupConversationScreen),
                  )
                  .canWrite,
              expected,
            );
          }

          final commandsBefore = bridge.commandLog.length;

          // 239: member (canWrite=false) and admin (canWrite=true) get the SAME
          // received-media actions. The admin case is causal for the overlay
          // change — raw canWrite would leak Reply onto announcement media.
          for (final role in [GroupRole.member, GroupRole.admin]) {
            final group = makeAnnouncementGroup(role: role);
            await groupRepo.saveGroup(group);
            await saveActiveGroupMembers(groupRepo, group);
            final messageId = 'msg-${role.name}';
            final attachmentId = 'att-${role.name}';
            await seedIncomingDoneImage(
              messageId: messageId,
              attachmentId: attachmentId,
            );
            final controller = RecordingGroupMediaActionsController(
              messageRepository: msgRepo,
              mediaAttachmentRepository: mediaAttachmentRepo,
            );
            final deleteCoordinator =
                RecordingGroupMediaDeleteForMeCoordinator();
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pumpWidget(
              buildWidget(
                group: group,
                mediaRepo: mediaAttachmentRepo,
                mediaFileManager: mediaFileManager,
                mediaActionsController: controller,
                mediaDeleteForMeCoordinator: deleteCoordinator,
              ),
            );
            await pumpUntilMediaLoaded(tester, messageId);
            await settleCanWrite(role == GroupRole.admin);
            final cellKey = ValueKey(
              'media-grid-cell-$messageId-$attachmentId',
            );

            // Tile long-press offers exactly the four received-media entries —
            // and never Reply, even for the writable admin.
            await tester.longPress(find.byKey(cellKey));
            await pumpFrames(tester, count: 4);
            expect(
              find.byKey(MessageContextOverlay.saveActionKey),
              findsOneWidget,
              reason: '$role announcement media must offer Save',
            );
            expect(
              find.byKey(MessageContextOverlay.shareActionKey),
              findsOneWidget,
            );
            expect(
              find.byKey(MessageContextOverlay.infoActionKey),
              findsOneWidget,
            );
            expect(
              find.byKey(MessageContextOverlay.deleteActionKey),
              findsOneWidget,
            );
            expect(
              find.byKey(MessageContextOverlay.replyActionKey),
              findsNothing,
              reason: '$role must never see Reply on announcement media',
            );

            // Save reaches ONLY the injected controller with exact identity.
            await tester.tap(find.byKey(MessageContextOverlay.saveActionKey));
            await pumpFrames(tester, count: 10);
            expect(controller.saves, ['group-1/$messageId/$attachmentId']);
            expect(controller.egressServiceTouched, isFalse);

            // Info opens the existing sheet.
            await tester.longPress(find.byKey(cellKey));
            await pumpFrames(tester, count: 4);
            await tester.tap(find.byKey(MessageContextOverlay.infoActionKey));
            await pumpFrames(tester, count: 10);
            expect(find.byKey(GroupMediaInfoSheet.sheetKey), findsOneWidget);
            await tester.tapAt(const Offset(5, 5));
            await pumpFrames(tester, count: 10);

            // Viewer carries the same four actions and never Reply.
            await tester.tap(find.byKey(cellKey));
            await pumpFrames(tester, count: 4);
            expect(find.byType(FullScreenTypedMediaViewer), findsOneWidget);
            final announcementViewer = tester
                .widget<FullScreenTypedMediaViewer>(
                  find.byType(FullScreenTypedMediaViewer),
                );
            expect(announcementViewer.items, hasLength(1));
            expect(announcementViewer.items.single.kind, MediaViewerKind.image);
            expect(announcementViewer.items.single.showMetadataDetails, isTrue);
            expect(
              tester
                  .widget<Text>(find.byKey(const ValueKey('media_meta_mime')))
                  .data,
              'image/png',
            );
            for (final action in [
              MediaViewerAction.save,
              MediaViewerAction.share,
              MediaViewerAction.info,
              MediaViewerAction.delete,
            ]) {
              expect(
                find.byKey(ValueKey('media_action_${action.name}')),
                findsOneWidget,
                reason: '$role announcement viewer must offer ${action.name}',
              );
            }
            for (final action in [
              MediaViewerAction.reply,
              MediaViewerAction.forward,
              MediaViewerAction.bookmark,
            ]) {
              expect(
                find.byKey(ValueKey('media_action_${action.name}')),
                findsNothing,
                reason:
                    '$role announcement viewer must not offer '
                    '${action.name}',
              );
            }
            await tester.tap(find.byKey(const ValueKey('media_action_share')));
            await pumpFrames(tester, count: 4);
            expect(controller.shares, ['group-1/$messageId/$attachmentId']);
            await tester.tap(find.byIcon(Icons.arrow_back));
            await pumpFrames(tester, count: 10);

            // Delete: cancel is a zero-op; one confirm dispatches exactly one
            // existing delete-coordinator operation.
            await tester.longPress(find.byKey(cellKey));
            await pumpFrames(tester, count: 4);
            await tester.tap(find.byKey(MessageContextOverlay.deleteActionKey));
            await pumpFrames(tester, count: 10);
            await tester.tap(
              find.byKey(const ValueKey('group-media-delete-cancel')),
            );
            await pumpFrames(tester, count: 10);
            expect(deleteCoordinator.calls, isEmpty);
            await tester.longPress(find.byKey(cellKey));
            await pumpFrames(tester, count: 4);
            await tester.tap(find.byKey(MessageContextOverlay.deleteActionKey));
            await pumpFrames(tester, count: 10);
            await tester.tap(
              find.byKey(const ValueKey('group-media-delete-confirm')),
            );
            await pumpFrames(tester, count: 10);
            expect(deleteCoordinator.calls, ['group-1/$messageId']);
          }

          // No send/publish/batch-delivery seam was touched by any action.
          expect(
            bridge.commandLog
                .skip(commandsBefore)
                .where(
                  (raw) =>
                      raw.contains('group:publish') ||
                      raw.contains('group:sendReliable') ||
                      raw.contains('group:inboxStore'),
                ),
            isEmpty,
          );

          // QA stays excluded wholesale (plans beyond 242 own its actions).
          final qaGroup = GroupModel(
            id: 'group-1',
            name: 'QA Group',
            type: GroupType.qa,
            topicName: 'topic-1',
            description: 'QA',
            createdAt: DateTime.now().toUtc(),
            createdBy: 'peer-admin',
            myRole: GroupRole.member,
          );
          await groupRepo.saveGroup(qaGroup);
          await saveActiveGroupMembers(groupRepo, qaGroup);
          await seedIncomingDoneImage(
            messageId: 'msg-qa',
            attachmentId: 'att-qa',
          );
          final qaController = RecordingGroupMediaActionsController(
            messageRepository: msgRepo,
            mediaAttachmentRepository: mediaAttachmentRepo,
          );
          final qaDeleteCoordinator =
              RecordingGroupMediaDeleteForMeCoordinator();
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.pumpWidget(
            buildWidget(
              group: qaGroup,
              mediaRepo: mediaAttachmentRepo,
              mediaFileManager: mediaFileManager,
              mediaActionsController: qaController,
              mediaDeleteForMeCoordinator: qaDeleteCoordinator,
            ),
          );
          await pumpUntilMediaLoaded(tester, 'msg-qa');

          // Tile long-press never offers the received-media entries.
          await tester.longPress(
            find.byKey(const ValueKey('media-grid-cell-msg-qa-att-qa')),
          );
          await pumpFrames(tester, count: 4);
          expect(
            find.byKey(MessageContextOverlay.saveActionKey),
            findsNothing,
            reason: 'QA must not offer Save',
          );
          expect(
            find.byKey(MessageContextOverlay.shareActionKey),
            findsNothing,
          );
          expect(find.byKey(MessageContextOverlay.infoActionKey), findsNothing);
          expect(
            find.byKey(MessageContextOverlay.deleteActionKey),
            findsNothing,
          );
          // Dismiss whatever overlay (if any) is open.
          if (tester.any(find.byKey(MessageContextOverlay.backdropKey))) {
            await tester.tapAt(const Offset(5, 5));
            await pumpFrames(tester, count: 10);
          }

          // Viewing stays available, but the viewer carries no action slot.
          await tester.tap(
            find.byKey(const ValueKey('media-grid-cell-msg-qa-att-qa')),
          );
          await pumpFrames(tester, count: 4);
          expect(find.byType(FullScreenTypedMediaViewer), findsOneWidget);
          for (final action in MediaViewerAction.values) {
            expect(
              find.byKey(ValueKey('media_action_${action.name}')),
              findsNothing,
              reason: 'QA viewer must not offer ${action.name}',
            );
          }
          expect(qaController.saves, isEmpty);
          expect(qaController.shares, isEmpty);
          expect(qaDeleteCoordinator.calls, isEmpty);
          await tester.tap(find.byIcon(Icons.arrow_back));
          await pumpFrames(tester, count: 10);
        },
      );

      testWidgets(
        'Plan 247 stale blocked bubble dismisses before unavailable feedback and opens nothing',
        (tester) async {
          tester.view.physicalSize = const Size(1200, 4000);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          const messageId = 'plan-247-stale-blocked';
          const attachmentId = 'plan-247-stale-blocked-attachment';
          final gatedContacts = GateNextContactReadRepository();
          contactRepo = gatedContacts;
          final (group, _) = await seedPlan247EligibleSource(
            messageId: messageId,
            attachmentId: attachmentId,
          );
          var openerCalls = 0;
          await tester.pumpWidget(
            buildWidget(
              group: group,
              messageRepo: msgRepo,
              mediaRepo: mediaAttachmentRepo,
              mediaFileManager: mediaFileManager,
              openAnnouncementSenderConversation: (_) async {
                openerCalls++;
              },
            ),
          );
          await pumpUntilMediaLoaded(tester, messageId);

          final cell = find.byKey(
            const ValueKey('media-grid-cell-$messageId-$attachmentId'),
          );
          await tester.longPress(cell);
          await pumpFrames(tester, count: 10);
          expect(
            find.byKey(MessageContextOverlay.messageSenderActionKey),
            findsOneWidget,
            reason: 'the initial current-parent decision is eligible',
          );

          await gatedContacts.blockContact('peer-bob');
          gatedContacts.gateNextRead();
          await tester.tap(
            find.byKey(MessageContextOverlay.messageSenderActionKey),
          );
          await pumpUntil(tester, () => gatedContacts.hasCapturedNextRead);
          await pumpFrames(tester, count: 8);

          expect(find.byKey(MessageContextOverlay.overlayKey), findsNothing);
          expect(find.text('Message sender is unavailable.'), findsNothing);
          expect(openerCalls, 0);

          gatedContacts.releaseNextRead();
          await pumpFrames(tester, count: 10);
          expect(find.byKey(MessageContextOverlay.overlayKey), findsNothing);
          expect(find.text('Message sender is unavailable.'), findsOneWidget);
          expect(find.text('Couldn’t open the conversation.'), findsNothing);
          expect(openerCalls, 0);
        },
      );

      testWidgets(
        'Plan 247 sender drift after eligible render revalidates the selection-time sender',
        (tester) async {
          tester.view.physicalSize = const Size(1200, 4000);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          const messageId = 'plan-247-stale-sender';
          const attachmentId = 'plan-247-stale-sender-attachment';
          final (group, currentMessages) = await seedPlan247EligibleSource(
            messageId: messageId,
            attachmentId: attachmentId,
          );
          var openerCalls = 0;
          await tester.pumpWidget(
            buildWidget(
              group: group,
              messageRepo: currentMessages,
              mediaRepo: mediaAttachmentRepo,
              mediaFileManager: mediaFileManager,
              openAnnouncementSenderConversation: (_) async {
                openerCalls++;
              },
            ),
          );
          await pumpUntilMediaLoaded(tester, messageId);
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          expect(
            await screen.isMessageSenderEligible!(messageId, 'peer-bob'),
            isTrue,
          );

          await currentMessages.saveMessage(
            makeMessage(
              id: messageId,
              text: 'sender changed after capability render',
              senderPeerId: 'peer-alice',
            ),
          );
          await screen.onMessageSenderTap!(messageId, 'peer-bob');
          await tester.pump();

          expect(find.text('Message sender is unavailable.'), findsOneWidget);
          expect(find.text('Couldn’t open the conversation.'), findsNothing);
          expect(openerCalls, 0);
        },
      );

      testWidgets(
        'Plan 247 throwing opener dismisses before exact open-failure feedback',
        (tester) async {
          tester.view.physicalSize = const Size(1200, 4000);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          const messageId = 'plan-247-opener-failure';
          const attachmentId = 'plan-247-opener-failure-attachment';
          final gatedContacts = GateNextContactReadRepository();
          contactRepo = gatedContacts;
          final (group, _) = await seedPlan247EligibleSource(
            messageId: messageId,
            attachmentId: attachmentId,
          );
          var openerCalls = 0;
          bool? overlayPresentAtOpen;
          await tester.pumpWidget(
            buildWidget(
              group: group,
              messageRepo: msgRepo,
              mediaRepo: mediaAttachmentRepo,
              mediaFileManager: mediaFileManager,
              openAnnouncementSenderConversation: (_) async {
                openerCalls++;
                overlayPresentAtOpen = tester.any(
                  find.byKey(MessageContextOverlay.overlayKey),
                );
                throw StateError('simulated direct-route failure');
              },
            ),
          );
          await pumpUntilMediaLoaded(tester, messageId);

          await tester.longPress(
            find.byKey(
              const ValueKey('media-grid-cell-$messageId-$attachmentId'),
            ),
          );
          await pumpFrames(tester, count: 10);
          expect(
            find.byKey(MessageContextOverlay.messageSenderActionKey),
            findsOneWidget,
          );
          gatedContacts.gateNextRead();
          await tester.tap(
            find.byKey(MessageContextOverlay.messageSenderActionKey),
          );
          await pumpUntil(tester, () => gatedContacts.hasCapturedNextRead);
          await pumpFrames(tester, count: 8);
          expect(find.byKey(MessageContextOverlay.overlayKey), findsNothing);
          expect(find.text('Couldn’t open the conversation.'), findsNothing);

          gatedContacts.releaseNextRead();
          await pumpFrames(tester, count: 10);
          expect(openerCalls, 1);
          expect(overlayPresentAtOpen, isFalse);
          expect(find.byKey(MessageContextOverlay.overlayKey), findsNothing);
          expect(find.text('Couldn’t open the conversation.'), findsOneWidget);
          expect(find.text('Message sender is unavailable.'), findsNothing);
        },
      );

      testWidgets(
        'Plan 247 wired latch coalesces while resolver and opener are pending',
        (tester) async {
          tester.view.physicalSize = const Size(1200, 4000);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          const messageId = 'plan-247-coalesced';
          const attachmentId = 'plan-247-coalesced-attachment';
          final gatedContacts = GateNextContactReadRepository();
          contactRepo = gatedContacts;
          final (group, _) = await seedPlan247EligibleSource(
            messageId: messageId,
            attachmentId: attachmentId,
          );
          final openerGate = Completer<void>();
          var openerCalls = 0;
          await tester.pumpWidget(
            buildWidget(
              group: group,
              messageRepo: msgRepo,
              mediaRepo: mediaAttachmentRepo,
              mediaFileManager: mediaFileManager,
              openAnnouncementSenderConversation: (_) async {
                openerCalls++;
                await openerGate.future;
              },
            ),
          );
          await pumpUntilMediaLoaded(tester, messageId);
          final screen = tester.widget<GroupConversationScreen>(
            find.byType(GroupConversationScreen),
          );
          expect(
            await screen.isMessageSenderEligible!(messageId, 'peer-bob'),
            isTrue,
          );

          gatedContacts.gateNextRead();
          final first = screen.onMessageSenderTap!(messageId, 'peer-bob');
          await pumpUntil(tester, () => gatedContacts.hasCapturedNextRead);
          await screen.onMessageSenderTap!(messageId, 'peer-bob');
          expect(openerCalls, 0, reason: 'the first resolver is still gated');

          gatedContacts.releaseNextRead();
          await pumpUntil(tester, () => openerCalls == 1);
          await screen.onMessageSenderTap!(messageId, 'peer-bob');
          expect(
            openerCalls,
            1,
            reason: 'the same wired latch also covers the awaited opener',
          );

          openerGate.complete();
          await first;
          await tester.pump();
          expect(openerCalls, 1);
          expect(find.text('Message sender is unavailable.'), findsNothing);
          expect(find.text('Couldn’t open the conversation.'), findsNothing);
        },
      );

      testWidgets(
        'Plan 247 mismatched viewer attachments never receive Message sender or open',
        (tester) async {
          tester.view.physicalSize = const Size(1200, 4000);
          tester.view.devicePixelRatio = 1.0;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);

          const parentMessageId = 'announcement-private-reply-parent';
          const validAttachmentId = 'valid-group-current-parent';
          const mismatchedAttachmentIds = <String>[
            'direct-owner-current-page',
            'unresolved-owner-current-page',
            'wrong-parent-current-page',
          ];
          final group = makeAnnouncementGroup(role: GroupRole.member);
          await groupRepo.saveGroup(group);
          await saveActiveGroupMembers(groupRepo, group);

          final currentMessages = KnownClearGroupMessageRepository();
          await currentMessages.saveMessage(
            makeMessage(
              id: parentMessageId,
              text: 'eligible announcement visual',
              senderPeerId: 'peer-bob',
            ),
          );
          await contactRepo.addContact(
            ContactModel(
              peerId: 'peer-bob',
              publicKey: 'pk-peer-bob',
              rendezvous: '/ip4/127.0.0.1/tcp/4001',
              username: 'Bob',
              signature: 'sig-peer-bob',
              scannedAt: DateTime.utc(2026, 7, 11).toIso8601String(),
            ),
          );

          final relativePath = mediaFileManager.relativePathForAttachment(
            contactPeerId: group.id,
            blobId: 'plan-247-mixed-viewer',
            mime: 'image/png',
          );
          final absolutePath = await mediaFileManager.resolveStoredPath(
            relativePath,
          );
          File(absolutePath)
            ..parent.createSync(recursive: true)
            ..writeAsBytesSync(_tinyPngBytes, flush: true);

          MediaAttachment row({
            required String id,
            required String messageId,
            required MediaOwnerLane? owner,
          }) => MediaAttachment(
            id: id,
            messageId: messageId,
            mime: 'image/png',
            size: _tinyPngBytes.length,
            mediaType: 'image',
            localPath: absolutePath,
            downloadStatus: kMediaDownloadStatusDone,
            createdAt: DateTime.utc(2026, 7, 11).toIso8601String(),
            contentHash: _validContentHash,
            encryptionKeyBase64: 'a2V5',
            encryptionNonce: 'bm9uY2U=',
            encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
            ownerLane: owner,
          );

          final mixedMedia = MixedViewerMediaAttachmentRepository(
            parentMessageId: parentMessageId,
            rows: <MediaAttachment>[
              row(
                id: validAttachmentId,
                messageId: parentMessageId,
                owner: MediaOwnerLane.group,
              ),
              row(
                id: mismatchedAttachmentIds[0],
                messageId: parentMessageId,
                owner: MediaOwnerLane.direct,
              ),
              row(
                id: mismatchedAttachmentIds[1],
                messageId: parentMessageId,
                owner: null,
              ),
              row(
                id: mismatchedAttachmentIds[2],
                messageId: 'different-parent',
                owner: MediaOwnerLane.group,
              ),
            ],
          );
          var openerCalls = 0;
          await tester.pumpWidget(
            buildWidget(
              group: group,
              messageRepo: currentMessages,
              mediaRepo: mixedMedia,
              mediaFileManager: mediaFileManager,
              openAnnouncementSenderConversation: (contact) async {
                openerCalls++;
              },
            ),
          );
          await pumpUntilMediaLoaded(tester, parentMessageId, expectedCount: 4);

          final validCell = find.byKey(
            const ValueKey(
              'media-grid-cell-$parentMessageId-$validAttachmentId',
            ),
          );
          await tester.tap(validCell);
          await pumpFrames(tester, count: 8);
          expect(
            find.byKey(const ValueKey('media_action_messageSender')),
            findsOneWidget,
            reason: 'the valid group/current-parent sibling proves eligibility',
          );
          final viewer = tester.widget<FullScreenTypedMediaViewer>(
            find.byType(FullScreenTypedMediaViewer),
          );
          final publishedByAttachment = <String, bool>{
            for (final attachmentId in mismatchedAttachmentIds)
              attachmentId: viewer.items
                  .singleWhere((item) => item.attachmentId == attachmentId)
                  .capabilities
                  .allows(MediaViewerAction.messageSender),
          };

          // Move the real typed viewer from the valid sibling to the direct
          // owner page, then invoke only if production incorrectly published
          // the capability. A fixed build leaves the action absent and opens
          // nothing; HEAD publishes it and reaches the real wired opener.
          await tester.drag(find.byType(PageView), const Offset(-700, 0));
          await pumpFrames(tester, count: 8);
          final currentMismatchAction = find.byKey(
            const ValueKey('media_action_messageSender'),
          );
          if (tester.any(currentMismatchAction)) {
            await tester.tap(currentMismatchAction);
            await pumpFrames(tester, count: 8);
          }

          expect(publishedByAttachment, <String, bool>{
            for (final attachmentId in mismatchedAttachmentIds)
              attachmentId: false,
          });
          expect(openerCalls, 0);
        },
      );
    });
  });
}

/// 235: records Save/Share requests without touching the egress service; the
/// service underneath THROWS so any UI bypass of the injected coordinator is
/// loud.
class RecordingGroupMediaActionsController
    extends GroupReceivedMediaActionsController {
  RecordingGroupMediaActionsController({
    required super.messageRepository,
    required super.mediaAttachmentRepository,
  }) : super(egressService: _ThrowingEgressService());

  final List<String> saves = [];
  final List<String> shares = [];

  bool get egressServiceTouched =>
      (egressService as _ThrowingEgressService).touched;

  @override
  Future<GroupReceivedMediaEgressAttempt> save({
    required String groupId,
    required String messageId,
    required String attachmentId,
  }) async {
    saves.add('$groupId/$messageId/$attachmentId');
    return GroupReceivedMediaEgressAttempt.performed(
      MediaEgressResult(
        requestId: 'recorded-save',
        outcome: MediaEgressOutcome.saved,
        items: const [],
      ),
    );
  }

  @override
  Future<GroupReceivedMediaEgressAttempt> share({
    required String groupId,
    required String messageId,
    required String attachmentId,
  }) async {
    shares.add('$groupId/$messageId/$attachmentId');
    return GroupReceivedMediaEgressAttempt.performed(
      MediaEgressResult(
        requestId: 'recorded-share',
        outcome: MediaEgressOutcome.presented,
        items: const [],
      ),
    );
  }
}

class _ThrowingEgressService extends ReceivedMediaEgressService {
  bool touched = false;

  @override
  Future<MediaEgressResult> perform({
    required String requestId,
    required MediaEgressDestination destination,
    required List<ReceivedMediaEgressCandidate> selection,
  }) async {
    touched = true;
    throw StateError('UI must never reach the egress service directly');
  }
}

class RecordingGroupMediaDeleteForMeCoordinator
    implements GroupMediaDeleteForMeCoordinator {
  final List<String> calls = [];

  @override
  Future<void> deleteForMe({
    required String groupId,
    required String messageId,
  }) async {
    calls.add('$groupId/$messageId');
  }
}
