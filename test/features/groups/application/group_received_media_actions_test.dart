import 'dart:io';

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/received_media_egress.dart';
import 'package:flutter_app/core/media/received_media_egress_service.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_app/features/groups/application/group_received_media_actions.dart';
import 'package:flutter_app/features/groups/domain/models/group_message.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_group_message_repository.dart';
import '../../../shared/fakes/in_memory_media_attachment_repository.dart';

const _validContentHash =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';

class _RecordedEgressCall {
  _RecordedEgressCall({
    required this.requestId,
    required this.destination,
    required this.selection,
  });

  final String requestId;
  final MediaEgressDestination destination;
  final List<ReceivedMediaEgressCandidate> selection;
}

/// Recording stand-in: never touches the platform channel.
class _RecordingEgressService extends ReceivedMediaEgressService {
  final List<_RecordedEgressCall> calls = [];

  @override
  Future<MediaEgressResult> perform({
    required String requestId,
    required MediaEgressDestination destination,
    required List<ReceivedMediaEgressCandidate> selection,
  }) async {
    calls.add(
      _RecordedEgressCall(
        requestId: requestId,
        destination: destination,
        selection: selection,
      ),
    );
    return MediaEgressResult(
      requestId: requestId,
      outcome: destination == MediaEgressDestination.share
          ? MediaEgressOutcome.presented
          : MediaEgressOutcome.saved,
      items: [
        for (final candidate in selection)
          MediaEgressItemResult(
            attachmentId: candidate.attachmentId,
            outcome: MediaEgressItemOutcome.saved,
          ),
      ],
    );
  }
}

void main() {
  const groupId = 'group-1';
  const otherGroupId = 'group-2';
  const messageId = 'msg-1';

  late InMemoryGroupMessageRepository messageRepo;
  late InMemoryMediaAttachmentRepository mediaRepo;
  late _RecordingEgressService egress;
  late FakeMediaFileManager fileManager;
  late GroupReceivedMediaActionsController controller;

  GroupMessage message({
    String id = messageId,
    String group = groupId,
    bool isIncoming = true,
  }) {
    return GroupMessage(
      id: id,
      groupId: group,
      senderPeerId: isIncoming ? 'peer-alice' : 'peer-self',
      text: 'caption',
      timestamp: DateTime.utc(2026, 7, 10, 12),
      isIncoming: isIncoming,
      createdAt: DateTime.utc(2026, 7, 10, 12),
    );
  }

  MediaAttachment attachment({
    String id = 'att-1',
    String parent = messageId,
    String mime = 'image/jpeg',
    String mediaType = 'image',
    String downloadStatus = 'done',
    String? localPath,
    String? contentHash = _validContentHash,
  }) {
    return MediaAttachment(
      id: id,
      messageId: parent,
      mime: mime,
      size: 2048,
      mediaType: mediaType,
      localPath: localPath,
      downloadStatus: downloadStatus,
      createdAt: '2026-07-10T12:00:00.000Z',
      contentHash: contentHash,
      encryptionKeyBase64: 'a2V5',
      encryptionNonce: 'bm9uY2U=',
      encryptionScheme: kMediaAttachmentEncryptionSchemeBlobAesGcmV1,
    );
  }

  /// Writes a real file under the fake documents root and returns the stored
  /// RELATIVE path (the canonical shape group rows persist).
  String writeMediaFile(String blobId, {String ext = 'jpg'}) {
    final relative = 'media/$groupId/$blobId.$ext';
    final file = File(p.join(FakeMediaFileManager.testRootPath, relative));
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(List<int>.filled(64, 7));
    return relative;
  }

  setUp(() {
    messageRepo = InMemoryGroupMessageRepository();
    mediaRepo = InMemoryMediaAttachmentRepository();
    egress = _RecordingEgressService();
    fileManager = FakeMediaFileManager();
    controller = GroupReceivedMediaActionsController(
      messageRepository: messageRepo,
      mediaAttachmentRepository: mediaRepo,
      egressService: egress,
      mediaFileManager: fileManager,
    );
  });

  tearDown(() {
    final root = Directory(FakeMediaFileManager.testRootPath);
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  group('GroupReceivedMediaActionsController', () {
    test(
      'GMA-04 egress reloads exact group owner and delegates only currently eligible media',
      () async {
        // --- Eligible current row: exact candidate reaches the service.
        await messageRepo.saveMessage(message());
        final relative = writeMediaFile('att-1');
        await mediaRepo.saveAttachment(
          attachment(localPath: relative),
          owner: MediaOwnerLane.group,
        );

        final saved = await controller.save(
          groupId: groupId,
          messageId: messageId,
          attachmentId: 'att-1',
        );
        expect(saved.performed, isTrue);
        expect(saved.result!.outcome, MediaEgressOutcome.saved);
        expect(egress.calls, hasLength(1));
        expect(egress.calls.single.destination, MediaEgressDestination.photos);
        final savedCandidate = egress.calls.single.selection.single;
        expect(savedCandidate.attachmentId, 'att-1');
        expect(savedCandidate.mime, 'image/jpeg');
        expect(
          savedCandidate.storedPath,
          p.join(FakeMediaFileManager.testRootPath, relative),
          reason: 'candidate path is the resolved CURRENT stored path',
        );

        final shared = await controller.share(
          groupId: groupId,
          messageId: messageId,
          attachmentId: 'att-1',
        );
        expect(shared.performed, isTrue);
        expect(shared.result!.outcome, MediaEgressOutcome.presented);
        expect(egress.calls, hasLength(2));
        expect(egress.calls.last.destination, MediaEgressDestination.share);
        expect(
          egress.calls.first.requestId,
          isNot(egress.calls.last.requestId),
          reason: 'each attempt gets its own request ID',
        );

        // --- Every refusal below makes ZERO additional egress calls.
        final baseline = egress.calls.length;

        Future<void> expectRefused(
          Future<GroupReceivedMediaEgressAttempt> attempt,
          String reason,
        ) async {
          final outcome = await attempt;
          expect(outcome.performed, isFalse, reason: reason);
          expect(outcome.refusalReason, isNotNull, reason: reason);
          expect(egress.calls, hasLength(baseline), reason: reason);
        }

        // Absent parent.
        await expectRefused(
          controller.save(
            groupId: groupId,
            messageId: 'msg-absent',
            attachmentId: 'att-1',
          ),
          'missing parent must refuse',
        );

        // Wrong group: the exact same message ID under another group id.
        await expectRefused(
          controller.save(
            groupId: otherGroupId,
            messageId: messageId,
            attachmentId: 'att-1',
          ),
          'wrong-group parent must refuse',
        );

        // Outgoing parent.
        await messageRepo.saveMessage(
          message(id: 'msg-out', isIncoming: false),
        );
        final outRelative = writeMediaFile('att-out');
        await mediaRepo.saveAttachment(
          attachment(id: 'att-out', parent: 'msg-out', localPath: outRelative),
          owner: MediaOwnerLane.group,
        );
        await expectRefused(
          controller.save(
            groupId: groupId,
            messageId: 'msg-out',
            attachmentId: 'att-out',
          ),
          'outgoing parent must refuse',
        );

        // Direct same-ID collision: the row exists ONLY under the direct
        // lane; the group-scoped reload must not see it.
        await messageRepo.saveMessage(message(id: 'msg-collide'));
        final collideRelative = writeMediaFile('att-collide');
        await mediaRepo.saveAttachment(
          attachment(
            id: 'att-collide',
            parent: 'msg-collide',
            localPath: collideRelative,
          ),
          owner: MediaOwnerLane.direct,
        );
        await expectRefused(
          controller.save(
            groupId: groupId,
            messageId: 'msg-collide',
            attachmentId: 'att-collide',
          ),
          'direct-owned same-ID row must refuse',
        );

        // Pending: not yet displayable.
        await messageRepo.saveMessage(message(id: 'msg-pending'));
        await mediaRepo.saveAttachment(
          attachment(
            id: 'att-pending',
            parent: 'msg-pending',
            downloadStatus: 'pending',
          ),
          owner: MediaOwnerLane.group,
        );
        await expectRefused(
          controller.save(
            groupId: groupId,
            messageId: 'msg-pending',
            attachmentId: 'att-pending',
          ),
          'pending row must refuse',
        );

        // Integrity-failed quarantine.
        await messageRepo.saveMessage(message(id: 'msg-tampered'));
        final tamperRelative = writeMediaFile('att-tampered');
        await mediaRepo.saveAttachment(
          attachment(
            id: 'att-tampered',
            parent: 'msg-tampered',
            downloadStatus: 'integrity_failed',
            localPath: tamperRelative,
          ),
          owner: MediaOwnerLane.group,
        );
        await expectRefused(
          controller.save(
            groupId: groupId,
            messageId: 'msg-tampered',
            attachmentId: 'att-tampered',
          ),
          'integrity-failed row must refuse',
        );

        // Mutated verification metadata on the CURRENT row: even though the
        // viewer may hold a stale eligible snapshot, the reloaded row decides.
        await messageRepo.saveMessage(message(id: 'msg-stale'));
        final staleRelative = writeMediaFile('att-stale');
        await mediaRepo.saveAttachment(
          attachment(
            id: 'att-stale',
            parent: 'msg-stale',
            localPath: staleRelative,
            contentHash: null,
          ),
          owner: MediaOwnerLane.group,
        );
        await expectRefused(
          controller.save(
            groupId: groupId,
            messageId: 'msg-stale',
            attachmentId: 'att-stale',
          ),
          'row without verification metadata must refuse',
        );

        // Missing file: done row whose resolved target is gone.
        await messageRepo.saveMessage(message(id: 'msg-gone'));
        final goneRelative = writeMediaFile('att-gone');
        File(
          p.join(FakeMediaFileManager.testRootPath, goneRelative),
        ).deleteSync();
        await mediaRepo.saveAttachment(
          attachment(id: 'att-gone', parent: 'msg-gone', localPath: goneRelative),
          owner: MediaOwnerLane.group,
        );
        await expectRefused(
          controller.save(
            groupId: groupId,
            messageId: 'msg-gone',
            attachmentId: 'att-gone',
          ),
          'missing file must refuse',
        );

        // Group-lane MIME allowlist (not the broader egress allowlist):
        // video/webm is egress-supported but never a legitimate group row.
        await messageRepo.saveMessage(message(id: 'msg-webm'));
        final webmRelative = writeMediaFile('att-webm', ext: 'webm');
        await mediaRepo.saveAttachment(
          attachment(
            id: 'att-webm',
            parent: 'msg-webm',
            mime: 'video/webm',
            mediaType: 'video',
            localPath: webmRelative,
          ),
          owner: MediaOwnerLane.group,
        );
        await expectRefused(
          controller.save(
            groupId: groupId,
            messageId: 'msg-webm',
            attachmentId: 'att-webm',
          ),
          'group-disallowed mime must refuse',
        );

        // Expired/protected lifecycle restriction (plan-238 seam): the
        // restricted row is otherwise fully eligible.
        final restricted = GroupReceivedMediaActionsController(
          messageRepository: messageRepo,
          mediaAttachmentRepository: mediaRepo,
          egressService: egress,
          mediaFileManager: fileManager,
          isEgressRestricted: (row) => row.id == 'att-1',
        );
        final restrictedAttempt = await restricted.save(
          groupId: groupId,
          messageId: messageId,
          attachmentId: 'att-1',
        );
        expect(restrictedAttempt.performed, isFalse);
        expect(restrictedAttempt.refusalReason, 'lifecycle_restricted');
        expect(egress.calls, hasLength(baseline));

        // The fully-eligible row still works after all the refusals above.
        final again = await controller.save(
          groupId: groupId,
          messageId: messageId,
          attachmentId: 'att-1',
        );
        expect(again.performed, isTrue);
        expect(egress.calls, hasLength(baseline + 1));
      },
    );
  });
}
