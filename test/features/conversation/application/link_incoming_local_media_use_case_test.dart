import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/application/link_incoming_local_media_use_case.dart';
import 'package:flutter_app/features/conversation/domain/models/media_attachment.dart';

import '../../../shared/fakes/in_memory_media_attachment_repository.dart';

/// NET-REL-01 P3 — production-seam coverage for the inbound local-WiFi media
/// link callback that previously lived inline in `main.dart` (untested).
///
/// Mutation resistance (each behavior has a control that goes RED if deleted):
/// - Delete the `if (!stillPending) return` dedupe guard → the "not pending"
///   and "already done (relay-CDN won)" tests proceed to persist+link, so
///   `persistCallCount` jumps 0→1 and the outcome flips to `linked` → RED.
/// - Delete the persist+updateLocalPath → the happy test's `localPath` stays
///   null, outcome is not `linked`, and the ATTACHMENT_LINKED event is absent
///   → RED.
/// - Delete the `persistedPath == null` guard → the persist-failed test calls
///   `updateLocalPath(id, null)` → type error → RED.
void main() {
  late List<Map<String, dynamic>> events;

  setUp(() {
    events = <Map<String, dynamic>>[];
    debugSetFlowEventSink((payload) => events.add(payload));
  });

  tearDown(() {
    debugSetFlowEventSink(null);
  });

  List<String> eventNames() =>
      events.map((e) => e['event'] as String).toList();

  Map<String, dynamic>? detailsFor(String event) {
    for (final e in events) {
      if (e['event'] == event) return e['details'] as Map<String, dynamic>;
    }
    return null;
  }

  MediaAttachment pendingAttachment({
    String id = 'media-1',
    String messageId = 'msg-1',
    String downloadStatus = 'pending',
  }) {
    return MediaAttachment(
      id: id,
      messageId: messageId,
      mime: 'image/jpeg',
      size: 256,
      mediaType: 'image',
      downloadStatus: downloadStatus,
      createdAt: '2026-05-30T00:00:00.000Z',
    );
  }

  LocalMediaReady mediaReady({String id = 'media-1', String from = 'peer-A'}) {
    return LocalMediaReady(
      id: id,
      from: from,
      to: 'peer-self',
      mime: 'image/jpeg',
      size: 256,
      localPath: '/tmp/incoming/$id',
      sha256: 'abc123',
    );
  }

  test(
    'happy: pending attachment → persists, repoints local path, links',
    () async {
      final repo = InMemoryMediaAttachmentRepository();
      await repo.saveAttachment(pendingAttachment());

      var persistCallCount = 0;
      String? persistMediaId;
      String? persistFrom;

      final outcome = await linkIncomingLocalMedia(
        media: mediaReady(),
        mediaAttachmentRepo: repo,
        persistMedia: (mediaId, fromPeerId) async {
          persistCallCount++;
          persistMediaId = mediaId;
          persistFrom = fromPeerId;
          return '/persistent/media-1';
        },
      );

      expect(outcome, LinkLocalMediaOutcome.linked);
      // persist was called exactly once with the wire id + sender peer.
      expect(persistCallCount, 1);
      expect(persistMediaId, 'media-1');
      expect(persistFrom, 'peer-A');
      // the attachment row was repointed and marked done (no longer pending).
      final stored = (await repo.getAttachmentsForMessage('msg-1')).single;
      expect(stored.localPath, '/persistent/media-1');
      expect(stored.downloadStatus, 'done');
      expect(await repo.getPendingDownloads(), isEmpty);
      // exactly the linked event fired, carrying the persisted path.
      expect(eventNames(), contains('LOCAL_MEDIA_RECEIVE_ATTACHMENT_LINKED'));
      expect(
        detailsFor('LOCAL_MEDIA_RECEIVE_ATTACHMENT_LINKED'),
        {'id': 'media-1', 'path': '/persistent/media-1'},
      );
      expect(
        eventNames(),
        isNot(contains('LOCAL_MEDIA_RECEIVE_SKIP_NOT_PENDING')),
      );
    },
  );

  test(
    'dedupe: unknown (never-pending) media → skips without persisting',
    () async {
      // Repo has NO matching attachment row at all.
      final repo = InMemoryMediaAttachmentRepository();

      var persistCallCount = 0;
      final outcome = await linkIncomingLocalMedia(
        media: mediaReady(),
        mediaAttachmentRepo: repo,
        persistMedia: (mediaId, fromPeerId) async {
          persistCallCount++;
          return '/persistent/media-1';
        },
      );

      expect(outcome, LinkLocalMediaOutcome.skippedNotPending);
      expect(persistCallCount, 0, reason: 'must not persist when not pending');
      expect(eventNames(), ['LOCAL_MEDIA_RECEIVE_SKIP_NOT_PENDING']);
      expect(detailsFor('LOCAL_MEDIA_RECEIVE_SKIP_NOT_PENDING'), {
        'id': 'media-1',
      });
    },
  );

  test(
    'dedupe vs relay-CDN: attachment already done → skips (does not clobber)',
    () async {
      // The relay-CDN fallback already completed this attachment ('done'),
      // so it is no longer in the pending set.
      final repo = InMemoryMediaAttachmentRepository();
      await repo.saveAttachment(pendingAttachment(downloadStatus: 'done'));

      var persistCallCount = 0;
      final outcome = await linkIncomingLocalMedia(
        media: mediaReady(),
        mediaAttachmentRepo: repo,
        persistMedia: (mediaId, fromPeerId) async {
          persistCallCount++;
          return '/persistent/media-1';
        },
      );

      expect(outcome, LinkLocalMediaOutcome.skippedNotPending);
      expect(persistCallCount, 0, reason: 'must not clobber a done attachment');
      // the relay-completed row is untouched.
      final stored = (await repo.getAttachmentsForMessage('msg-1')).single;
      expect(stored.downloadStatus, 'done');
      expect(eventNames(), ['LOCAL_MEDIA_RECEIVE_SKIP_NOT_PENDING']);
    },
  );

  test(
    'persist failure: returns null → does not update local path',
    () async {
      final repo = InMemoryMediaAttachmentRepository();
      await repo.saveAttachment(pendingAttachment());

      final outcome = await linkIncomingLocalMedia(
        media: mediaReady(),
        mediaAttachmentRepo: repo,
        persistMedia: (mediaId, fromPeerId) async => null,
      );

      expect(outcome, LinkLocalMediaOutcome.persistFailed);
      // attachment stays pending with no local path (no clobber on failure).
      final stored = (await repo.getAttachmentsForMessage('msg-1')).single;
      expect(stored.localPath, isNull);
      expect(stored.downloadStatus, 'pending');
      expect(await repo.getPendingDownloads(), hasLength(1));
      expect(eventNames(), ['LOCAL_MEDIA_RECEIVE_PERSIST_FAILED']);
    },
  );

  test('error path: persist throws → swallowed, reports error', () async {
    final repo = InMemoryMediaAttachmentRepository();
    await repo.saveAttachment(pendingAttachment());

    final outcome = await linkIncomingLocalMedia(
      media: mediaReady(),
      mediaAttachmentRepo: repo,
      persistMedia: (mediaId, fromPeerId) async =>
          throw StateError('disk full'),
    );

    expect(outcome, LinkLocalMediaOutcome.error);
    // attachment untouched; the incoming pipeline did not crash.
    final stored = (await repo.getAttachmentsForMessage('msg-1')).single;
    expect(stored.localPath, isNull);
    expect(stored.downloadStatus, 'pending');
    expect(eventNames(), ['LOCAL_MEDIA_RECEIVE_ERROR']);
    expect(detailsFor('LOCAL_MEDIA_RECEIVE_ERROR')?['id'], 'media-1');
  });
}
