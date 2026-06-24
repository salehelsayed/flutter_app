import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/device/upload_wake_lock.dart';
import 'package:flutter_app/core/media/group_media_integrity_policy.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import 'package:flutter_app/core/media/image_processor.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/permissions/mic_permission_gateway.dart';
import 'package:flutter_app/core/media/media_picker.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/core/media/video_process_result.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/conversation/application/upload_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/compose_area.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/date_separator.dart';
import 'package:flutter_app/features/feed/presentation/widgets/swipe_to_quote_bubble.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/attachment_preview_strip.dart';
import 'package:flutter_app/features/conversation/domain/models/message_reaction.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';
import 'package:flutter_app/features/conversation/domain/repositories/reaction_repository.dart';
import 'package:flutter_app/features/conversation/presentation/widgets/message_context_overlay.dart';
import 'package:flutter_app/features/groups/application/group_message_listener.dart';
import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';
import 'package:flutter_app/features/groups/domain/models/group_invite_delivery_attempt.dart';
import 'package:flutter_app/features/groups/domain/models/group_key_info.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_app/features/groups/domain/models/group_member.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
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
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_app/shared/widgets/media/full_screen_image_viewer.dart';
import 'package:flutter_app/shared/widgets/media/media_grid.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/bridge/fake_bridge.dart';
import '../../../core/services/fake_p2p_service.dart';
import '../../../shared/fakes/fake_audio_recorder_service.dart';
import '../../../shared/fakes/fake_just_audio.dart';
import '../../../shared/fakes/fake_mic_permission_gateway.dart';
import '../../../shared/fakes/fake_group_reaction_replay_outbox_repository.dart';
import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/fake_media_picker.dart';
import '../../../shared/fakes/fake_upload_wake_lock_driver.dart';
import '../../../shared/fakes/in_memory_contact_repository.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';
import '../../../shared/fakes/in_memory_group_repository.dart';
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

  @override
  Future<GroupModel?> getGroup(String id) async {
    await Future<void>.delayed(delay);
    return null;
  }
}

class CountingGroupMessageRepository extends InMemoryGroupMessageRepository {
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
    String messageId,
  ) async {
    getAttachmentsForMessageCalls++;
    return super.getAttachmentsForMessage(messageId);
  }

  @override
  Future<Map<String, List<MediaAttachment>>> getAttachmentsForMessages(
    List<String> messageIds,
  ) async {
    getAttachmentsForMessagesCalls++;
    return super.getAttachmentsForMessages(messageIds);
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
      if (quotedMessageId != null) 'quotedMessageId': quotedMessageId,
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
      contactRepo = InMemoryContactRepository();
      bridge = FakeBridge(
        initialResponses: {
          'group:publish': {'ok': true, 'messageId': 'msg-published'},
        },
      );
      identityRepo = FakeIdentityRepository(identity: testIdentity);
      p2pService = FakeP2PService();
      messageStreamController = StreamController<GroupMessage>.broadcast();
      wakeLockDriver = FakeUploadWakeLockDriver();
      UploadWakeLockController.debugReset(driver: wakeLockDriver);
      groupRecoveryGate.resetForTest();
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
    });

    Widget buildWidget({
      GroupModel? group,
      CountingMediaAttachmentRepository? mediaRepo,
      ImageProcessor? imageProcessor,
      FakeAudioRecorderService? audioRecorderService,
      MicPermissionGateway? micPermissionGateway,
      MediaPicker? mediaPicker,
      MediaFileManager? mediaFileManager,
      UploadMediaFn? uploadMediaFn,
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
          uploadMediaFn: uploadMediaFn ?? uploadMedia,
          initialAttachments: initialAttachments,
          initialPendingMedia: initialPendingMedia,
          initialText: initialText,
          initialHighlightedMessageId: initialHighlightedMessageId,
          maxAttachmentBudgetBytes: maxAttachmentBudgetBytes,
          reactionRepo: reactionRepo,
          groupReactionReplayOutboxRepository: reactionReplayOutboxRepo,
          groupConversationTracker: groupConversationTracker,
          inviteDeliveryAttemptRepo: inviteDeliveryAttemptRepo,
        ),
      );
    }

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
        final tempDir = Directory.systemTemp.createTempSync('group_total_over_');
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
              PendingComposerMedia(file: vid('v1'), budgetBytes: 200 * 1024 * 1024),
              PendingComposerMedia(file: vid('v2'), budgetBytes: 200 * 1024 * 1024),
              PendingComposerMedia(file: vid('v3'), budgetBytes: 200 * 1024 * 1024),
            ],
          ),
        );
        await pumpFrames(tester, count: 20);

        // No per-attachment chip — each item is individually within its cap.
        expect(find.byKey(const ValueKey('attachment-invalid-0')), findsNothing);
        expect(find.byKey(const ValueKey('attachment-invalid-1')), findsNothing);
        expect(find.byKey(const ValueKey('attachment-invalid-2')), findsNothing);
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
    test(
      'the 3 redundant media snackbars are dropped from source; the '
      'text-retry snackbar is kept',
      () {
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
      },
    );

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
              PendingComposerMedia(
                file: video,
                budgetBytes: 300 * 1024 * 1024,
              ),
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

    testWidgets(
      'interleaves WhatsApp-style date separators across days',
      (tester) async {
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
      },
    );

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
          await uploadStarted.future.timeout(const Duration(seconds: 30));
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
      'media uploads pre-persist upload_pending rows and start in parallel from durable copies',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        final tempDir = Directory.systemTemp.createTempSync('group-media-');
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final files = [
          File('${tempDir.path}/one.jpg')..writeAsStringSync('one'),
          File('${tempDir.path}/two.jpg')..writeAsStringSync('two'),
          File('${tempDir.path}/three.jpg')..writeAsStringSync('three'),
        ];

        final testMediaFileManager = FakeMediaFileManager();
        final uploadStarts = <DateTime>[];
        final seenBlobIds = <String>[];
        final pendingSeenBeforeUpload = <bool>[];
        final uploadRelease = Completer<void>();
        addTearDown(() {
          if (!uploadRelease.isCompleted) {
            uploadRelease.complete();
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
                  uploadStarts.add(DateTime.now().toUtc());
                  seenBlobIds.add(blobId!);
                  final pending = await mediaAttachmentRepo
                      .getUploadPendingAttachments();
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
                  await uploadRelease.future;
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
        await pumpUntil(tester, () => uploadStarts.length == 3, maxPumps: 40);

        expect(uploadStarts, hasLength(3));
        expect(
          uploadStarts.last.difference(uploadStarts.first).inMilliseconds,
          lessThan(80),
        );
        expect(pendingSeenBeforeUpload.every((seen) => seen), isTrue);
        expect(seenBlobIds.toSet(), hasLength(3));

        uploadRelease.complete();
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
          ..writeAsStringSync('pl005');
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
        final file = File('${tempDir.path}/one.jpg')..writeAsStringSync('one');
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

        final pending = await mediaAttachmentRepo.getUploadPendingAttachments();
        expect(pending, hasLength(1));
        final messageId = pending.single.messageId;
        expect(pending.single.id, receivedBlobId);
        expect(pending.single.downloadStatus, 'upload_pending');
        expect(pending.single.localPath, startsWith('pending_uploads/'));

        final persistedBeforeUpload = await msgRepo.getMessage(messageId);
        expect(persistedBeforeUpload, isNotNull);
        expect(persistedBeforeUpload!.text, 'Durable parent row');
        expect(persistedBeforeUpload.status, 'sending');

        await tester.runAsync(() async {
          uploadGate.complete();
          await sendFuture;
        });
        await pumpFrames(tester, count: 20);

        final persistedAfterSend = await msgRepo.getMessage(messageId);
        expect(persistedAfterSend, isNotNull);
        expect(persistedAfterSend!.status, 'sent');
        expect(
          await mediaAttachmentRepo.getUploadPendingAttachments(),
          isEmpty,
        );
        final savedAttachments = await mediaAttachmentRepo
            .getAttachmentsForMessage(messageId);
        expect(savedAttachments, hasLength(1));
        expect(savedAttachments.single.id, receivedBlobId);
        expect(savedAttachments.single.downloadStatus, 'done');
        expect(deletedDirs, contains(messageId));
      },
    );

    testWidgets(
      'failed media upload clears retryable durable rows and avoids group publish',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        final tempDir = Directory.systemTemp.createTempSync(
          'group-media-fail-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final files = [
          File('${tempDir.path}/one.jpg')..writeAsStringSync('one'),
          File('${tempDir.path}/two.jpg')..writeAsStringSync('two'),
          File('${tempDir.path}/three.jpg')..writeAsStringSync('three'),
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
          await mediaAttachmentRepo.getUploadPendingAttachments(),
          isEmpty,
        );
        final failedMessage = (await msgRepo.getMessagesPage(
          group.id,
        )).singleWhere((message) => message.text == 'Fail media');
        expect(failedMessage.status, 'failed');
        final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
          failedMessage.id,
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
        final file = File('${tempDir.path}/one.jpg')..writeAsStringSync('one');
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
            .getUploadPendingAttachments();
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
            .getUploadPendingAttachments();
        expect(pendingAfterFail, isEmpty);
        final failedAttachments = await mediaAttachmentRepo
            .getAttachmentsForMessage(messageId);
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
              "You can read this group's history, but you are not an active "
              'member.',
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

    testWidgets(
      'voice terminal send keeps failed bubble instead of deleting',
      (tester) async {
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

        // Empty-membership chat group → use case returns groupDissolved on send.
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

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
        await tester.runAsync(() async {
          await stopRecording();
        });
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
      },
    );

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
        final source = File('${tempDir.path}/photo.jpg')
          ..writeAsStringSync('photo');
        final mediaFileManager = TrackingDurableMediaFileManager(tempDir);

        await tester.pumpWidget(
          buildWidget(
            group: missingGroup,
            mediaRepo: mediaAttachmentRepo,
            mediaFileManager: mediaFileManager,
            initialAttachments: [source],
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
                  // Physically relocate the upload to the durable owned location
                  // (media/<groupId>/<blob>), as the real upload path does.
                  final absolute = await mediaFileManager!
                      .localPathForAttachment(
                        contactPeerId: missingGroup.id,
                        blobId: blobId!,
                        mime: mime,
                      );
                  await File(absolute).writeAsString('durable');
                  return MediaAttachment(
                    id: blobId,
                    messageId: '',
                    mime: mime,
                    size: 1,
                    mediaType: MediaAttachment.mediaTypeFromMime(mime),
                    localPath: mediaFileManager.relativePathForAttachment(
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

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final sendMessage = screen.onSend as Future<void> Function(String);
        await tester.runAsync(() async {
          await sendMessage('Durable photo');
        });
        await pumpFrames(tester, count: 20);

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
        );
        expect(attachments, isNotEmpty);
        final localPath = attachments.first.localPath;
        expect(localPath, isNotNull);
        final durableAbsolute = await mediaFileManager.resolveStoredPath(
          localPath!,
        );
        expect(
          File(durableAbsolute).existsSync(),
          isTrue,
          reason: 'durable owned file should exist before Delete',
        );

        // Tap the terminal Delete affordance (reachable while read-only).
        await tester.runAsync(() async {
          await tester.tap(
            find.byKey(
              ValueKey('failed-message-delete-${retained.single.id}'),
            ),
          );
          await Future<void>.delayed(const Duration(milliseconds: 200));
        });
        await pumpFrames(tester, count: 10);

        // RED on HEAD: terminal Delete only drops the rows + pending-upload dir,
        // orphaning the durable media/<groupId>/ file on disk.
        expect(File(durableAbsolute).existsSync(), isFalse);
      },
    );

    testWidgets(
      'ordinary media group-not-found rejection retains the failed media bubble',
      (tester) async {
        final missingGroup = makeChatGroup();
        final tempDir = Directory.systemTemp.createTempSync(
          'group-media-missing-group-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final file = File('${tempDir.path}/one.jpg')..writeAsStringSync('one');
        final mediaFileManager = FakeMediaFileManager();
        final deletedDirs = <String>[];
        mediaFileManager.onDeletePendingUploadDir = deletedDirs.add;

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
                }) async => MediaAttachment(
                  id: 'server-missing-group-media',
                  messageId: '',
                  mime: mime,
                  size: 1,
                  mediaType: MediaAttachment.mediaTypeFromMime(mime),
                  localPath: mediaFileManager?.relativePathForAttachment(
                    contactPeerId: missingGroup.id,
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
                ),
          ),
        );
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final sendMessage = screen.onSend as Future<void> Function(String);
        await tester.runAsync(() async {
          await sendMessage('Missing group media');
        });
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
        await groupRepo.saveGroup(
          widgetGroup.copyWith(myRole: GroupRole.member),
        );

        final tempDir = Directory.systemTemp.createTempSync(
          'group-media-unauthorized-',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final file = File('${tempDir.path}/one.jpg')..writeAsStringSync('one');
        final mediaFileManager = FakeMediaFileManager();
        final deletedDirs = <String>[];
        mediaFileManager.onDeletePendingUploadDir = deletedDirs.add;

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
                }) async => MediaAttachment(
                  id: 'server-unauthorized-media',
                  messageId: '',
                  mime: mime,
                  size: 1,
                  mediaType: MediaAttachment.mediaTypeFromMime(mime),
                  localPath: mediaFileManager?.relativePathForAttachment(
                    contactPeerId: widgetGroup.id,
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
                ),
          ),
        );
        await pumpFrames(tester, count: 20);

        final screen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        final sendMessage = screen.onSend as Future<void> Function(String);
        await tester.runAsync(() async {
          await sendMessage('Unauthorized media');
        });
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
            .getAttachmentsForMessage(savedMessage!.id);
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
        tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

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
        await mediaAttachmentRepo.saveAttachment(pendingImageAttachment);
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
        expect(find.byType(FullScreenImageViewer), findsOneWidget);
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
        await mediaAttachmentRepo.saveAttachment(failedAttachment);
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
            .getAttachmentsForMessage('msg-gird005-failed-recovery');
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
        expect(find.byType(FullScreenImageViewer), findsOneWidget);
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
        await mediaAttachmentRepo.saveAttachment(doneAttachment);
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
            .getAttachmentsForMessage('msg-gird005-done-no-path');
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
        expect(find.byType(FullScreenImageViewer), findsOneWidget);
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
            "You can read this group's history, but you are not an active member.",
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
            "You can read this group's history, but you are not an active member.",
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
        final stuckRow = screen.messages
            .firstWhere((message) => message.text == 'Stale unauthorized');
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
            "You can read this group's history, but you are not an active member.",
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'retained self-removal shows the read-only banner and NO removed snackbar',
      (tester) async {
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
            "You can read this group's history, but you are not an active member.",
          ),
          findsOneWidget,
        );
        // …and the redundant transient toast is NOT shown (the discriminator).
        expect(find.text('You were removed from this group.'), findsNothing);
      },
    );

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
              "You can read this group's history, but you are not an active "
              'member.',
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
              "You can read this group's history, but you are not an active "
              'member.',
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
          "You can read this group's history, but you are not an active member.",
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
          await mediaAttachmentRepo.getUploadPendingAttachments(),
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
          await mediaAttachmentRepo.getUploadPendingAttachments(),
          isEmpty,
        );
        final failedMessage = (await msgRepo.getMessagesPage(
          group.id,
        )).singleWhere((message) => message.text == 'Partial upload');
        expect(failedMessage.status, 'failed');
        final savedAttachments = await mediaAttachmentRepo
            .getAttachmentsForMessage(failedMessage.id);
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

    testWidgets('shows relay upload progress and blocks leaving mid-upload', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);

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

      expect(
        find.text(
          '${formatPendingComposerBudgetBytes(5)} / '
          '${formatPendingComposerBudgetBytes(10)}',
        ),
        findsOneWidget,
      );
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
    });

    testWidgets(
      'cancel on the active upload banner restores composer state and terminalizes durable pending rows',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);

        final tempDir = Directory.systemTemp.createTempSync(
          'group_cancel_upload_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });
        final attachmentA = File('${tempDir.path}/cancel-a.jpg')
          ..writeAsStringSync('0123456789');
        final attachmentB = File('${tempDir.path}/cancel-b.jpg')
          ..writeAsStringSync('abcdefghij');
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
        await pumpUntil(tester, () => uploadStarted.length == 2, maxPumps: 120);
        await pumpFrames(tester, count: 5);

        final cancellingScreen = tester.widget<GroupConversationScreen>(
          find.byType(GroupConversationScreen),
        );
        expect(uploadStarted, hasLength(2));
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
            .getAttachmentsForMessage(failedMessage.id);

        expect(uploadCompleted, hasLength(2));
        expect(failedMessage.status, 'failed');
        expect(storedAttachments, hasLength(2));
        expect(
          storedAttachments.every(
            (attachment) => attachment.downloadStatus == 'upload_failed',
          ),
          isTrue,
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
        await pumpUntilAsync(tester, () async {
          return (await msgRepo.getMessage(
                'msg-voice-upload-pending',
              ))?.status ==
              'sent';
        }, maxPumps: 160);

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
        );
        expect(attachments, hasLength(1));
        expect(attachments.single.id, 'att-voice-upload-pending');
        expect(attachments.single.downloadStatus, 'done');
        expect(attachments.single.durationMs, 4100);
        expect(attachments.single.waveform, [0.1, 0.6, 0.2]);
        expect(
          (await mediaAttachmentRepo.getAttachmentsForMessage(
            'msg-unrelated-pending-image',
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
              .getAttachmentsForMessage('msg-md012-repair');
          return attachments
                  .where((attachment) => attachment.id == 'att-md012-target')
                  .single
                  .downloadStatus ==
              'done';
        }, maxPumps: 80);

        final attachments = await mediaAttachmentRepo.getAttachmentsForMessage(
          'msg-md012-repair',
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
              .getAttachmentsForMessage('msg-md012-fail');
          return attachments.single.downloadStatus ==
              kMediaDownloadStatusIntegrityFailed;
        }, maxPumps: 80);

        final attachment = (await mediaAttachmentRepo.getAttachmentsForMessage(
          'msg-md012-fail',
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
          ),
          isEmpty,
        );
        expect(
          await mediaAttachmentRepo.getAttachmentsForMessage(
            'msg-delete-untouched',
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
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
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
          await uploadStarted.future.timeout(const Duration(seconds: 10));
        });
        await pumpFrames(tester, count: 5);

        expect(mediaFileManager.copyCalls, 1);
        expect(receivedBlobId, isNotNull);
        expect(
          receivedLocalPath,
          startsWith(p.join(tempDir.path, 'pending_uploads')),
        );

        final pending = await mediaAttachmentRepo.getUploadPendingAttachments();
        expect(pending, hasLength(1));
        expect(pending.single.id, receivedBlobId);
        expect(pending.single.downloadStatus, 'upload_pending');
        expect(pending.single.localPath, isNotNull);
        expect(pending.single.localPath, startsWith('pending_uploads/'));

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
      },
    );

    testWidgets(
      'voice upload failure keeps upload_pending retry data and restores the quote',
      (tester) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
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
        await pumpUntil(tester, () => uploadStarted.isCompleted, maxPumps: 240);
        expect(uploadStarted.isCompleted, isTrue);
        await pumpFrames(tester, count: 5);

        expect(mediaFileManager.copyCalls, 1);
        expect(receivedBlobId, isNotNull);
        expect(
          receivedLocalPath,
          startsWith(p.join(tempDir.path, 'pending_uploads')),
        );

        final pendingBeforeFail = await mediaAttachmentRepo
            .getUploadPendingAttachments();
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
            .getUploadPendingAttachments();
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
          await mediaAttachmentRepo.getUploadPendingAttachments(),
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
            .getAttachmentsForMessage(failedRow.id);
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
          await uploadStarted.future.timeout(const Duration(seconds: 10));
        });
        await pumpFrames(tester, count: 5);

        expect(mediaFileManager.copyCalls, 1);
        expect(receivedBlobId, isNotNull);
        expect(
          receivedLocalPath,
          startsWith(p.join(tempDir.path, 'pending_uploads')),
        );

        final pending = await mediaAttachmentRepo.getUploadPendingAttachments();
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
        expect(
          mediaFileManager.deletedPendingUploadDirs,
          contains(savedMessage!.id),
        );
        final savedAttachments = await mediaAttachmentRepo
            .getAttachmentsForMessage(savedMessage.id);
        expect(savedAttachments, hasLength(1));
        expect(savedAttachments.single.id, receivedBlobId);
        expect(savedAttachments.single.downloadStatus, 'done');
        expect(savedAttachments.single.localPath, startsWith('media/'));
        expect(
          await mediaAttachmentRepo.getUploadPendingAttachments(),
          isEmpty,
        );
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
                }) async => MediaAttachment(
                  id: 'uploaded-voice-missing-group',
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
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await tester.runAsync(() async {
          await uploadStarted.future.timeout(const Duration(seconds: 6));
        });
        await pumpFrames(tester, count: 5);

        final inFlightMessage = await msgRepo.getLatestMessage(group.id);
        expect(inFlightMessage, isNotNull);
        final messageId = inFlightMessage!.id;

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();

        await tester.runAsync(() async {
          await stopFuture;
        });
        await pumpFrames(tester, count: 10);

        // 144: even when the screen is gone, a terminal result keeps the row as
        // a durable send_failed bubble (it surfaces on reopen) rather than
        // silently deleting the recording.
        expect(
          mediaFileManager.deletedPendingUploadDirs,
          isNot(contains(messageId)),
        );
        expect(
          await mediaAttachmentRepo.getAttachmentsForMessage(messageId),
          isNotEmpty,
        );
        final persisted = await msgRepo.getMessage(messageId);
        expect(persisted, isNotNull);
        expect(persisted!.status, GroupMessage.statusSendFailed);
      },
    );

    testWidgets('voice upload failure restores the quoted reply target', (
      tester,
    ) async {
      final group = makeChatGroup();
      await groupRepo.saveGroup(group);
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

      testWidgets('recorder auto-stop resets the composer recording state', (
        tester,
      ) async {
        final group = makeChatGroup();
        await groupRepo.saveGroup(group);
        await saveActiveGroupMembers(groupRepo, group);
        await pumpAndStartRecording(tester, group);

        await recorder.triggerAutoStop();
        await pumpFrames(tester, count: 5);

        expect(recorder.isRecording, isFalse);
        expect(visibleScreen(tester).recordingState, VoiceRecordingState.idle);
        expect(recorder.onAutoStopped, isNull);
      });

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
        'group mic denial shows the rationale dialog instead of the snackbar (permanentlyDenied)',
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

          expect(find.byType(AlertDialog), findsOneWidget);
          expect(
            find.byKey(const ValueKey('mic-perm-open-settings')),
            findsOneWidget,
          );
          expect(find.text(l10n.perm_microphone_record), findsNothing);
          expect(recorder.startCallCount, 0);

          await tester.tap(find.byKey(const ValueKey('mic-perm-not-now')));
          // Assert the LIVE rendered composer (internal ValueListenableBuilder),
          // not the stale `recordingState` widget prop.
          for (var i = 0;
              i < 12 && find.byIcon(Icons.mic_rounded).evaluate().isEmpty;
              i++) {
            await tester.pump(const Duration(milliseconds: 50));
          }
          await pending;
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

          expect(find.byType(AlertDialog), findsOneWidget);
          await tester.tap(
            find.byKey(const ValueKey('mic-perm-open-settings')),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          await pending;

          expect(gateway.openAppSettingsCallCount, 1);
          expect(find.byType(AlertDialog), findsNothing);
        },
      );

      // Option A (owner-locked): a first plain `denied` resets to idle WITHOUT
      // forcing the Settings dialog (the OS prompt already showed via
      // request()). Locks the denied-vs-permanentlyDenied axis on the group side.
      testWidgets(
        'group first plain denied resets to idle with no dialog/snackbar',
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

          expect(find.byType(AlertDialog), findsNothing);
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
          reason: 'markAsRead runs once-per-flush against the post-batch state',
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
          reason: 'gate must skip the per-message attachment read on a status '
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
  });
}
