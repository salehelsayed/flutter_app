import 'dart:io';

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/received_media_egress.dart';
import 'package:flutter_app/core/media/received_media_egress_service.dart';
import 'package:flutter_app/features/conversation/application/received_media_action_controller.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/repositories/fake_media_attachment_repository.dart';

/// Records every native-boundary call; never touches a platform channel.
class _RecordingEgressService extends ReceivedMediaEgressService {
  final calls =
      <({
        String requestId,
        MediaEgressDestination destination,
        List<ReceivedMediaEgressCandidate> selection,
      })>[];

  @override
  Future<MediaEgressResult> perform({
    required String requestId,
    required MediaEgressDestination destination,
    required List<ReceivedMediaEgressCandidate> selection,
  }) async {
    calls.add((
      requestId: requestId,
      destination: destination,
      selection: selection,
    ));
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

/// A repository that (wrongly) returns a non-direct row for a direct-lane
/// query — proves the controller re-verifies the owner instead of trusting
/// the query result.
class _WrongOwnerRepo extends FakeMediaAttachmentRepository {
  _WrongOwnerRepo(this.row);

  final MediaAttachment row;

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async => [row];
}

void main() {
  late Directory tempDir;
  late _RecordingEgressService service;
  late FakeMediaAttachmentRepository repo;
  late Map<String, ConversationMessage> parents;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('received_media_ctrl_');
    service = _RecordingEgressService();
    repo = FakeMediaAttachmentRepository();
    parents = {};
  });

  tearDown(() {
    try {
      tempDir.deleteSync(recursive: true);
    } catch (_) {}
  });

  String writeMediaFile(String name, [List<int> bytes = const [7, 8, 9]]) {
    final path = '${tempDir.path}/$name';
    File(path).writeAsBytesSync(bytes);
    return path;
  }

  ConversationMessage makeParent({
    String id = 'msg-1',
    bool isIncoming = true,
    String? deletedAt,
  }) {
    return ConversationMessage(
      id: id,
      contactPeerId: 'peer-contact',
      senderPeerId: isIncoming ? 'peer-contact' : 'peer-me',
      text: 'hello',
      timestamp: '2026-07-09T10:00:00.000Z',
      status: 'delivered',
      isIncoming: isIncoming,
      createdAt: '2026-07-09T10:00:01.000Z',
      deletedAt: deletedAt,
    );
  }

  MediaAttachment makeRow({
    String id = 'att-1',
    String messageId = 'msg-1',
    String? localPath,
    String mime = 'image/jpeg',
    String mediaType = 'image',
    String downloadStatus = 'done',
    MediaOwnerLane? ownerLane = MediaOwnerLane.direct,
    int size = 3,
  }) {
    return MediaAttachment(
      id: id,
      messageId: messageId,
      mime: mime,
      size: size,
      mediaType: mediaType,
      localPath: localPath,
      downloadStatus: downloadStatus,
      createdAt: '2026-07-09T10:00:02.000Z',
      ownerLane: ownerLane,
    );
  }

  ReceivedMediaActionController buildController({
    FakeMediaAttachmentRepository? repoOverride,
    DirectMediaLaneQualifier? qualifier,
  }) {
    return ReceivedMediaActionController(
      loadParentMessage: (id) async => parents[id],
      mediaAttachmentRepo: repoOverride ?? repo,
      egressService: service,
      qualifier: qualifier ?? defaultDirectMediaLaneQualifier,
      resolveStoredPath: (storedPath) => storedPath,
    );
  }

  const identity = DirectReceivedMediaActionIdentity(
    messageId: 'msg-1',
    attachmentId: 'att-1',
  );

  test(
    'egress reloads current direct row and delegates one qualified candidate',
    () async {
      final qualified = <String>[];
      final pathA = writeMediaFile('current-a.jpg');
      parents['msg-1'] = makeParent();
      repo.seed([makeRow(localPath: pathA)]);

      final controller = buildController(
        qualifier: (parent, current) async {
          qualified.add(current.localPath ?? '');
          return DirectMediaLaneQualification.eligible;
        },
      );

      final photos = await controller.performEgress(
        identity: identity,
        destination: MediaEgressDestination.photos,
      );

      expect(photos.wasDenied, isFalse);
      expect(photos.result, isNotNull);
      expect(service.calls, hasLength(1));
      expect(service.calls.single.destination, MediaEgressDestination.photos);
      expect(service.calls.single.selection, hasLength(1));
      expect(service.calls.single.selection.single.attachmentId, 'att-1');
      expect(service.calls.single.selection.single.storedPath, pathA);
      expect(service.calls.single.selection.single.mime, 'image/jpeg');
      expect(
        isValidMediaEgressRequestId(service.calls.single.requestId),
        isTrue,
      );
      expect(photos.result!.requestId, service.calls.single.requestId);

      // Mutate the CURRENT row underneath a stale caller: the next egress
      // must re-read the row and delegate the new path — a captured
      // path/MIME snapshot would keep sending pathA.
      final pathB = writeMediaFile('current-b.jpg');
      await repo.updateLocalPath('att-1', pathB);

      final files = await controller.performEgress(
        identity: identity,
        destination: MediaEgressDestination.files,
      );

      expect(files.wasDenied, isFalse);
      expect(service.calls, hasLength(2));
      expect(service.calls.last.destination, MediaEgressDestination.files);
      expect(service.calls.last.selection.single.storedPath, pathB);
      // The qualifier ran against the reloaded current row both times.
      expect(qualified, [pathA, pathB]);
      // Distinct dispatches never share a request id.
      expect(
        service.calls.first.requestId,
        isNot(service.calls.last.requestId),
      );

      // The source stays untouched: rows still direct/done, bytes unchanged.
      final rows = await repo.getAttachmentsForMessage(
        'msg-1',
        owner: MediaOwnerLane.direct,
      );
      expect(rows.single.downloadStatus, 'done');
      expect(File(pathA).readAsBytesSync(), [7, 8, 9]);
      expect(File(pathB).readAsBytesSync(), [7, 8, 9]);
    },
  );

  test('current row policy denies every ineligible direct egress state', () async {
    Future<void> expectDenied({
      required DirectMediaEgressDenial expected,
      required String reason,
      ConversationMessage? parent,
      MediaAttachment? row,
      FakeMediaAttachmentRepository? repoOverride,
      DirectMediaLaneQualifier? qualifier,
      DirectReceivedMediaActionIdentity target = identity,
    }) async {
      parents.clear();
      if (parent != null) parents[parent.id] = parent;
      repo.seed(row == null ? const [] : [row]);
      final callsBefore = service.calls.length;

      final controller = buildController(
        repoOverride: repoOverride,
        qualifier: qualifier,
      );
      final outcome = await controller.performEgress(
        identity: target,
        destination: MediaEgressDestination.photos,
      );

      expect(outcome.wasDenied, isTrue, reason: reason);
      expect(outcome.denial, expected, reason: reason);
      expect(outcome.result, isNull, reason: reason);
      expect(
        service.calls.length,
        callsBefore,
        reason: 'egress service must not be called: $reason',
      );
    }

    final present = writeMediaFile('present.jpg');

    // Not-downloaded family: pending / downloading / evicted.
    for (final status in const ['pending', 'downloading', 'evicted']) {
      await expectDenied(
        expected: DirectMediaEgressDenial.notDownloaded,
        reason: 'status $status',
        parent: makeParent(),
        row: makeRow(downloadStatus: status, localPath: present),
      );
    }

    // Missing file: done row whose bytes are gone, and a path-less row.
    await expectDenied(
      expected: DirectMediaEgressDenial.fileMissing,
      reason: 'file deleted underneath a done row',
      parent: makeParent(),
      row: makeRow(localPath: '${tempDir.path}/gone.jpg'),
    );
    await expectDenied(
      expected: DirectMediaEgressDenial.fileMissing,
      reason: 'done row without a stored path',
      parent: makeParent(),
      row: makeRow(localPath: null),
    );

    // Integrity-failed is its own truthful denial, not "missing".
    await expectDenied(
      expected: DirectMediaEgressDenial.integrityFailed,
      reason: 'integrity_failed row',
      parent: makeParent(),
      row: makeRow(downloadStatus: 'integrity_failed', localPath: present),
    );

    // Lane qualifier decisions: expired / protected / no decision at all.
    await expectDenied(
      expected: DirectMediaEgressDenial.expired,
      reason: 'qualifier says expired',
      parent: makeParent(),
      row: makeRow(localPath: present),
      qualifier: (_, _) async => DirectMediaLaneQualification.expired,
    );
    await expectDenied(
      expected: DirectMediaEgressDenial.protected,
      reason: 'qualifier says protected',
      parent: makeParent(),
      row: makeRow(localPath: present),
      qualifier: (_, _) async => DirectMediaLaneQualification.protected,
    );
    await expectDenied(
      expected: DirectMediaEgressDenial.policyUnavailable,
      reason: 'absent policy decision fails closed',
      parent: makeParent(),
      row: makeRow(localPath: present),
      qualifier: (_, _) async => null,
    );

    // Parent states: deleted / outgoing / missing entirely.
    await expectDenied(
      expected: DirectMediaEgressDenial.parentDeleted,
      reason: 'deleted parent',
      parent: makeParent(deletedAt: '2026-07-09T11:00:00.000Z'),
      row: makeRow(localPath: present),
    );
    await expectDenied(
      expected: DirectMediaEgressDenial.parentNotIncoming,
      reason: 'outgoing parent',
      parent: makeParent(isIncoming: false),
      row: makeRow(localPath: present),
    );
    await expectDenied(
      expected: DirectMediaEgressDenial.parentNotFound,
      reason: 'parent row absent',
      row: makeRow(localPath: present),
    );

    // Wrong attachment id under a live parent.
    await expectDenied(
      expected: DirectMediaEgressDenial.attachmentNotCurrent,
      reason: 'attachment id not in the current direct rows',
      parent: makeParent(),
      row: makeRow(localPath: present),
      target: const DirectReceivedMediaActionIdentity(
        messageId: 'msg-1',
        attachmentId: 'att-other',
      ),
    );

    // Wrong/unresolved owner rows returned by a (buggy or legacy) lookup
    // must still fail closed at the controller.
    await expectDenied(
      expected: DirectMediaEgressDenial.wrongOwner,
      reason: 'group-owned row leaked into a direct query',
      parent: makeParent(),
      repoOverride: _WrongOwnerRepo(
        makeRow(localPath: present, ownerLane: MediaOwnerLane.group),
      ),
    );
    await expectDenied(
      expected: DirectMediaEgressDenial.wrongOwner,
      reason: 'unresolved-owner row leaked into a direct query',
      parent: makeParent(),
      repoOverride: _WrongOwnerRepo(
        makeRow(localPath: present, ownerLane: null),
      ),
    );

    expect(service.calls, isEmpty);
  });

  test('external share performs native egress with zero delivery calls', () async {
    final path = writeMediaFile('share.jpg');
    parents['msg-1'] = makeParent();
    repo.seed([makeRow(localPath: path)]);

    final controller = buildController();
    final outcome = await controller.performEgress(
      identity: identity,
      destination: MediaEgressDestination.share,
    );

    // Exactly one perform(requestId, share, [currentCandidate]) call: the
    // native sheet is the ONLY share surface — no ShareTargetPicker, no
    // delivery coordinator, no send/P2P seam even exists on the controller.
    expect(service.calls, hasLength(1));
    expect(service.calls.single.destination, MediaEgressDestination.share);
    expect(service.calls.single.selection, hasLength(1));
    expect(service.calls.single.selection.single.attachmentId, 'att-1');
    expect(service.calls.single.selection.single.storedPath, path);

    // The typed native result passes through untouched.
    expect(outcome.wasDenied, isFalse);
    expect(outcome.result!.outcome, MediaEgressOutcome.presented);
    expect(outcome.result!.requestId, service.calls.single.requestId);
  });
}
