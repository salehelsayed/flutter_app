import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/posts/application/post_expiry_scheduler.dart';
import 'package:flutter_app/features/posts/application/sweep_expired_posts_use_case.dart';
import 'package:flutter_app/features/posts/domain/models/post_audience.dart';
import 'package:flutter_app/features/posts/domain/models/post_model.dart';

import '../../../shared/fakes/fake_media_file_manager.dart';
import '../../../shared/fakes/in_memory_post_repository.dart';

void main() {
  test(
    'an external resume sweep deleting first still cancels its notification',
    () {
      fakeAsync((clock) {
        final created = DateTime.utc(2026, 10, 20, 9);
        var now = created;
        final posts = InMemoryPostRepository();
        final files = FakeMediaFileManager();
        final cancelled = <String>[];
        final scheduler = PostExpiryScheduler(
          postChanges: posts.postChanges,
          nowProvider: () => now,
          onPostChanged: (id) async {
            if (await posts.getPost(id) == null) cancelled.add(id);
          },
          loadNextExpiry: () async => await posts.getPost('thought') == null
              ? null
              : created.add(const Duration(hours: 24)),
          sweep: () async {
            await sweepExpiredPosts(
              postRepo: posts,
              mediaFileManager: files,
              nowProvider: () => now,
            );
          },
        );
        posts.savePost(_thought(created));
        clock.flushMicrotasks();
        scheduler.start();
        clock.flushMicrotasks();
        now = created.add(const Duration(hours: 24));
        // The app-root's existing sweep wins before the scheduler timer fires.
        sweepExpiredPosts(
          postRepo: posts,
          mediaFileManager: files,
          nowProvider: () => now,
        );
        clock.flushMicrotasks();
        expect(files.deletedPostIds, ['thought']);
        expect(cancelled, ['thought']);
        scheduler.dispose();
        posts.dispose();
      });
    },
  );

  test(
    'failed notification cancellation stays queued for the next attempt',
    () {
      fakeAsync((clock) {
        final changes = StreamController<String>.broadcast();
        var attempts = 0;
        final cancelled = <String>[];
        final scheduler = PostExpiryScheduler(
          postChanges: changes.stream,
          loadNextExpiry: () async => null,
          sweep: () async {},
          onPostChanged: (id) async {
            attempts++;
            if (attempts == 1) {
              throw StateError('synthetic native cancellation failure');
            }
            cancelled.add(id);
          },
        );
        scheduler.start();
        clock.flushMicrotasks();
        changes.add('thought');
        clock.flushMicrotasks();
        expect(attempts, 1);
        expect(cancelled, isEmpty);
        clock.elapse(const Duration(minutes: 1));
        clock.flushMicrotasks();
        expect(attempts, 2);
        expect(cancelled, ['thought']);
        scheduler.dispose();
        changes.close();
      });
    },
  );

  test(
    'foreground expiry removes thought and media without resume and cancels its card',
    () {
      fakeAsync((clock) {
        final created = DateTime.utc(2026, 10, 20, 9);
        final expiry = created.add(const Duration(hours: 24));
        final posts = InMemoryPostRepository();
        final files = FakeMediaFileManager();
        final cancelled = <String>[];
        DateTime now() => created.add(clock.elapsed);
        DateTime? nextExpiry;
        final scheduler = PostExpiryScheduler(
          postChanges: posts.postChanges,
          nowProvider: now,
          onPostChanged: (id) async {
            if (await posts.getPost(id) == null) cancelled.add(id);
          },
          loadNextExpiry: () async => nextExpiry,
          sweep: () async {
            final ids = await sweepExpiredPosts(
              postRepo: posts,
              mediaFileManager: files,
              nowProvider: now,
            );
            if (ids.isNotEmpty) nextExpiry = null;
          },
        );
        scheduler.start();
        clock.flushMicrotasks();
        nextExpiry = expiry;
        posts.savePost(
          PostModel(
            id: 'thought',
            eventId: 'evt-thought',
            senderPeerId: 'friend',
            authorPeerId: 'friend',
            authorUsername: 'Friend',
            text: 'Gone at the deadline',
            audience: PostAudience.allFriends(),
            createdAt: created.toIso8601String(),
            visibleAt: created.toIso8601String(),
            expiresAt: expiry.toIso8601String(),
            keepAvailable: true,
          ),
        );
        clock.flushMicrotasks();
        clock.elapse(
          const Duration(hours: 24) - const Duration(milliseconds: 1),
        );
        expect(files.deletedPostIds, isEmpty);
        clock.elapse(const Duration(milliseconds: 1));
        clock.flushMicrotasks();
        expect(files.deletedPostIds, ['thought']);
        expect(cancelled, ['thought']);
        expect(nextExpiry, isNull);
        scheduler.dispose();
        posts.dispose();
      });
    },
  );

  test('background stops the deadline timer and resume catches up', () {
    fakeAsync((clock) {
      final start = DateTime.utc(2026, 10, 20);
      final changes = StreamController<String>.broadcast();
      var sweeps = 0;
      DateTime? next = start.add(const Duration(hours: 1));
      final scheduler = PostExpiryScheduler(
        postChanges: changes.stream,
        nowProvider: () => start.add(clock.elapsed),
        loadNextExpiry: () async => next,
        sweep: () async {
          sweeps++;
          if (clock.elapsed >= const Duration(hours: 1)) next = null;
        },
      );
      scheduler.start();
      clock.flushMicrotasks();
      expect(sweeps, 1);
      scheduler.setForeground(false);
      clock.elapse(const Duration(hours: 2));
      expect(sweeps, 1);
      scheduler.setForeground(true);
      clock.flushMicrotasks();
      expect(sweeps, 2);
      scheduler.dispose();
      changes.close();
    });
  });

  test(
    'changes during a sweep serialize and disposal prevents later DB reads',
    () {
      fakeAsync((clock) {
        final changes = StreamController<String>.broadcast();
        final pending = Completer<void>();
        var reads = 0;
        var sweeps = 0;
        final scheduler = PostExpiryScheduler(
          postChanges: changes.stream,
          loadNextExpiry: () async {
            reads++;
            return null;
          },
          sweep: () async {
            sweeps++;
            await pending.future;
          },
        );
        scheduler.start();
        changes.add('during-sweep');
        clock.flushMicrotasks();
        expect(sweeps, 1);
        scheduler.dispose();
        pending.complete();
        clock.flushMicrotasks();
        expect(reads, 0);
        changes.close();
      });
    },
  );
}

PostModel _thought(DateTime created) => PostModel(
  id: 'thought',
  eventId: 'evt-thought',
  senderPeerId: 'friend',
  authorPeerId: 'friend',
  authorUsername: 'Friend',
  text: 'Private thought',
  audience: PostAudience.allFriends(),
  createdAt: created.toIso8601String(),
  visibleAt: created.toIso8601String(),
  expiresAt: created.add(const Duration(hours: 24)).toIso8601String(),
);
