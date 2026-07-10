import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/shared/widgets/media/media_video_resume_controller.dart';
import 'package:flutter_app/shared/widgets/media/media_viewer_item.dart';

import 'fake_media_playback_adapter.dart';

void main() {
  MediaViewerItem videoItem(
    MediaOwnerLane? owner, {
    int? durationMs,
    String id = 'att-vid',
  }) => MediaViewerItem(
    attachmentId: id,
    messageId: 'm',
    kind: MediaViewerKind.video,
    mime: 'video/mp4',
    owner: owner,
    durationMs: durationMs,
    localPath: '/tmp/$id.mp4',
  );

  MediaViewerItem imageItem(MediaOwnerLane owner) => MediaViewerItem(
    attachmentId: 'att-img',
    messageId: 'm',
    kind: MediaViewerKind.image,
    mime: 'image/jpeg',
    owner: owner,
    localPath: '/tmp/att-img.jpg',
  );

  test(
    'owner aware resume restores throttles flushes and resets on completion',
    () async {
      final adapter = FakeMediaPlaybackAdapter(
        duration: const Duration(seconds: 60),
      );
      final store = RecordingResumeStore(defaultStored: 30000);
      var now = DateTime(2026, 1, 1, 12);
      final controller = MediaVideoResumeController(
        item: videoItem(MediaOwnerLane.direct),
        adapter: adapter,
        store: store,
        clock: () => now,
        checkpointInterval: const Duration(seconds: 5),
      );

      // Restore reads once (owner-aware) and seeks exactly once after init.
      await controller.restore();
      expect(store.reads, hasLength(1));
      expect(store.reads.single.owner, MediaOwnerLane.direct);
      expect(store.reads.single.attachmentId, 'att-vid');
      expect(adapter.seekTargets, [const Duration(milliseconds: 30000)]);

      await controller.restore();
      expect(store.reads, hasLength(1), reason: 'restore reads only once');

      // A tick storm within one interval persists at most once.
      adapter.isPlaying = true;
      adapter.position = const Duration(seconds: 31);
      await controller.onTick();
      adapter.position = const Duration(seconds: 32);
      await controller.onTick();
      adapter.position = const Duration(seconds: 33);
      await controller.onTick();
      expect(store.writes.map((w) => w.positionMs), [31000]);

      // Past the interval, the next tick persists again.
      now = now.add(const Duration(seconds: 6));
      adapter.position = const Duration(seconds: 40);
      await controller.onTick();
      expect(store.writes.map((w) => w.positionMs), [31000, 40000]);

      // Flush (pause / exit) persists the current position immediately.
      adapter.position = const Duration(seconds: 45);
      await controller.flush();
      expect(store.writes.map((w) => w.positionMs), [31000, 40000, 45000]);

      // Genuine completion resets to zero exactly once.
      adapter.isCompleted = true;
      await controller.onTick();
      await controller.onTick();
      expect(store.writes.map((w) => w.positionMs), [31000, 40000, 45000, 0]);

      // Every read and write carried the exact attachment and direct owner.
      expect(
        store.writes.every(
          (w) => w.owner == MediaOwnerLane.direct && w.attachmentId == 'att-vid',
        ),
        isTrue,
      );
    },
  );

  test(
    'resume obeys known unknown nonvideo and unresolved contracts',
    () async {
      // Unknown duration: stores a non-negative position, then re-clamps once
      // the duration becomes known.
      final unknownAdapter = FakeMediaPlaybackAdapter(duration: Duration.zero);
      final unknownStore = RecordingResumeStore();
      final unknownController = MediaVideoResumeController(
        item: videoItem(MediaOwnerLane.group),
        adapter: unknownAdapter,
        store: unknownStore,
      );
      unknownAdapter.isPlaying = true;
      unknownAdapter.position = const Duration(seconds: 45);
      await unknownController.onTick();
      expect(unknownStore.writes.map((w) => w.positionMs), [45000]);

      unknownAdapter.duration = const Duration(seconds: 30);
      await unknownController.flush();
      expect(unknownStore.writes.map((w) => w.positionMs), [45000, 30000]);
      expect(unknownStore.writes.last.owner, MediaOwnerLane.group);

      // Known duration clamps immediately (in-bounds stays, overrun clamps down).
      final knownAdapter = FakeMediaPlaybackAdapter(
        duration: const Duration(seconds: 30),
      );
      final knownStore = RecordingResumeStore();
      final knownController = MediaVideoResumeController(
        item: videoItem(MediaOwnerLane.direct),
        adapter: knownAdapter,
        store: knownStore,
      );
      knownAdapter.position = const Duration(seconds: 25);
      await knownController.flush();
      knownAdapter.position = const Duration(seconds: 40);
      await knownController.flush();
      // Negative position clamps to zero.
      knownAdapter.position = const Duration(seconds: -5);
      await knownController.flush();
      expect(knownStore.writes.map((w) => w.positionMs), [25000, 30000, 0]);

      // Non-video item: zero reads and zero writes.
      final imageAdapter = FakeMediaPlaybackAdapter(
        duration: const Duration(seconds: 30),
      );
      final imageStore = RecordingResumeStore(defaultStored: 12000);
      final imageController = MediaVideoResumeController(
        item: imageItem(MediaOwnerLane.direct),
        adapter: imageAdapter,
        store: imageStore,
      );
      await imageController.restore();
      imageAdapter.isPlaying = true;
      imageAdapter.position = const Duration(seconds: 10);
      await imageController.onTick();
      await imageController.flush();
      expect(imageStore.reads, isEmpty);
      expect(imageStore.writes, isEmpty);

      // Ownerless / unresolved video: zero reads and zero writes (fail closed).
      final ownerlessAdapter = FakeMediaPlaybackAdapter(
        duration: const Duration(seconds: 30),
      );
      final ownerlessStore = RecordingResumeStore(defaultStored: 12000);
      final ownerlessController = MediaVideoResumeController(
        item: videoItem(null, id: 'att-legacy'),
        adapter: ownerlessAdapter,
        store: ownerlessStore,
      );
      await ownerlessController.restore();
      ownerlessAdapter.isPlaying = true;
      ownerlessAdapter.position = const Duration(seconds: 10);
      await ownerlessController.onTick();
      await ownerlessController.flush();
      expect(ownerlessStore.reads, isEmpty);
      expect(ownerlessStore.writes, isEmpty);
    },
  );
}
