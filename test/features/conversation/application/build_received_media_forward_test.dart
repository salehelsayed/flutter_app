import 'dart:io';

import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/features/conversation/application/build_received_media_forward.dart';
import 'package:flutter_app/features/conversation/domain/models/conversation_message.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';
import 'package:flutter_test/flutter_test.dart';

import '../domain/repositories/fake_media_attachment_repository.dart';

class _UnresolvedOwnerRepository extends FakeMediaAttachmentRepository {
  _UnresolvedOwnerRepository(this.row);

  final MediaAttachment row;

  @override
  Future<List<MediaAttachment>> getAttachmentsForMessage(
    String messageId, {
    required MediaOwnerLane owner,
  }) async => [row];
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('received_forward_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  ConversationMessage parent({bool incoming = true, bool deleted = false}) =>
      ConversationMessage(
        id: 'message-1',
        contactPeerId: 'contact-1',
        senderPeerId: incoming ? 'contact-1' : 'self',
        text: 'source caption',
        timestamp: '2026-07-10T10:00:00.000Z',
        status: 'delivered',
        isIncoming: incoming,
        createdAt: '2026-07-10T10:00:00.000Z',
        dedupKey: 'source-secret-key',
        deletedAt: deleted ? '2026-07-10T10:01:00.000Z' : null,
      );

  MediaAttachment attachment({
    required String id,
    required String path,
    String mime = 'image/jpeg',
    String status = 'done',
    MediaOwnerLane? owner = MediaOwnerLane.direct,
  }) => MediaAttachment(
    id: id,
    messageId: 'message-1',
    mime: mime,
    size: 10,
    mediaType: MediaAttachment.mediaTypeFromMime(mime),
    localPath: path,
    downloadStatus: status,
    createdAt: '2026-07-10T10:00:01.000Z',
    ownerLane: owner,
  );

  test(
    'builds direct owned drafts with a fresh operation token per explicit action',
    () async {
      final image = File('${tempDir.path}/one.jpg')..writeAsBytesSync([1]);
      final video = File('${tempDir.path}/two.mp4')..writeAsBytesSync([2]);
      final audio = File('${tempDir.path}/three.m4a')..writeAsBytesSync([3]);
      final repo = FakeMediaAttachmentRepository()
        ..seed([
          attachment(id: 'image', path: image.path),
          attachment(id: 'video', path: video.path, mime: 'video/mp4'),
          attachment(id: 'audio', path: audio.path, mime: 'audio/mp4'),
          attachment(
            id: 'group-collision',
            path: image.path,
            owner: MediaOwnerLane.group,
          ),
        ]);
      final tokens = ['operation-a', 'operation-b'].iterator;
      final builder = BuildReceivedMediaForward(
        mediaAttachmentRepository: repo,
        operationTokenFactory: () {
          tokens.moveNext();
          return tokens.current;
        },
        resolveStoredPath: (path) => path,
        fileExists: (path) => File(path).existsSync(),
      );

      final first = await builder.build(parent: parent());
      final second = await builder.build(
        parent: parent(),
        currentAttachmentId: 'video',
      );

      expect(first.denial, isNull);
      expect(first.draft!.shareIntent.filePaths, [image.path, video.path]);
      expect(first.draft!.shareIntent.text, 'source caption');
      expect(
        first.draft!.shareIntent.forwardProvenance!.operationDedupKey,
        'operation-a',
      );
      expect(second.draft!.shareIntent.filePaths, [video.path]);
      expect(
        second.draft!.shareIntent.forwardProvenance!.operationDedupKey,
        'operation-b',
      );
      expect(
        first.draft!.shareIntent.forwardProvenance!.operationDedupKey,
        isNot(anyOf('message-1', 'contact-1', 'source-secret-key')),
      );
      expect(repo.getAttachmentsForMessageCallCount, 2);
    },
  );

  test(
    'ineligible or unresolved source media fails closed before the picker',
    () async {
      final present = File('${tempDir.path}/present.jpg')
        ..writeAsBytesSync([1]);
      var tokenMintCount = 0;

      Future<ReceivedMediaForwardBuildResult> run({
        bool incoming = true,
        bool deleted = false,
        String status = 'done',
        MediaOwnerLane? owner = MediaOwnerLane.direct,
        String? path,
      }) {
        final row = attachment(
          id: 'candidate',
          path: path ?? present.path,
          status: status,
          owner: owner,
        );
        final repo = owner == null
            ? _UnresolvedOwnerRepository(row)
            : (FakeMediaAttachmentRepository()..seed([row]));
        return BuildReceivedMediaForward(
          mediaAttachmentRepository: repo,
          operationTokenFactory: () {
            tokenMintCount++;
            return 'must-not-mint';
          },
          resolveStoredPath: (stored) => stored,
          fileExists: (stored) => File(stored).existsSync(),
        ).build(
          parent: parent(incoming: incoming, deleted: deleted),
        );
      }

      expect(
        (await run(deleted: true)).denial,
        DirectMediaForwardDenial.parentDeleted,
      );
      expect(
        (await run(incoming: false)).denial,
        DirectMediaForwardDenial.parentNotIncoming,
      );
      expect(
        (await run(status: 'pending')).denial,
        DirectMediaForwardDenial.noEligibleVisualMedia,
      );
      expect(
        (await run(status: 'downloading')).denial,
        DirectMediaForwardDenial.noEligibleVisualMedia,
      );
      expect(
        (await run(status: 'evicted')).denial,
        DirectMediaForwardDenial.noEligibleVisualMedia,
      );
      expect(
        (await run(status: 'integrity_failed')).denial,
        DirectMediaForwardDenial.noEligibleVisualMedia,
      );
      expect(
        (await run(owner: null)).denial,
        DirectMediaForwardDenial.noEligibleVisualMedia,
      );
      expect(
        (await run(path: '${tempDir.path}/missing.jpg')).denial,
        DirectMediaForwardDenial.noEligibleVisualMedia,
      );
      expect(tokenMintCount, 0);
    },
  );
}
