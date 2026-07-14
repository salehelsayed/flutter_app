import 'dart:async';

import 'package:flutter_app/core/media/media_attachment_lifecycle_lock.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MediaAttachmentLifecycleLock', () {
    test('same attachment acquisition is reentrant across awaits', () async {
      final lock = MediaAttachmentLifecycleLock();
      final events = <String>[];

      await lock
          .synchronized('attachment-a', () async {
            events.add('outer-start');
            await Future<void>.delayed(Duration.zero);
            await lock.synchronized('attachment-a', () async {
              events.add('inner');
            });
            events.add('outer-end');
          })
          .timeout(const Duration(seconds: 1));

      expect(events, ['outer-start', 'inner', 'outer-end']);
    });

    test('same attachment contenders remain serialized', () async {
      final lock = MediaAttachmentLifecycleLock();
      final firstEntered = Completer<void>();
      final releaseFirst = Completer<void>();
      var secondEntered = false;

      final first = lock.synchronized('attachment-a', () async {
        firstEntered.complete();
        await releaseFirst.future;
      });
      await firstEntered.future;
      final second = lock.synchronized('attachment-a', () async {
        secondEntered = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(secondEntered, isFalse);

      releaseFirst.complete();
      await Future.wait([first, second]);
      expect(secondEntered, isTrue);
    });

    test('an action error releases exact attachment authority', () async {
      final lock = MediaAttachmentLifecycleLock();

      await expectLater(
        lock.synchronized<void>('attachment-a', () async {
          throw StateError('injected action failure');
        }),
        throwsStateError,
      );

      var entered = false;
      await lock
          .synchronized('attachment-a', () async {
            entered = true;
          })
          .timeout(const Duration(seconds: 1));
      expect(entered, isTrue);
    });

    test('an escaped zone cannot reuse a released reentrant lease', () async {
      final lock = MediaAttachmentLifecycleLock();
      late Zone escapedZone;
      await lock.synchronized('attachment-a', () async {
        escapedZone = Zone.current;
      });

      final holderEntered = Completer<void>();
      final releaseHolder = Completer<void>();
      var escapedEntered = false;
      final holder = lock.synchronized('attachment-a', () async {
        holderEntered.complete();
        await releaseHolder.future;
      });
      await holderEntered.future;
      final escaped = escapedZone.run(
        () => lock.synchronized('attachment-a', () async {
          escapedEntered = true;
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(escapedEntered, isFalse);

      releaseHolder.complete();
      await Future.wait([holder, escaped]);
      expect(escapedEntered, isTrue);
    });

    test(
      'exclusive mutation waits for all attachment holders and bars later work',
      () async {
        final lock = MediaAttachmentLifecycleLock();
        final firstEntered = Completer<void>();
        final releaseFirst = Completer<void>();
        final events = <String>[];

        final first = lock.synchronized('attachment-a', () async {
          events.add('first');
          firstEntered.complete();
          await releaseFirst.future;
        });
        await firstEntered.future;
        final exclusive = lock.synchronizedAll(() async {
          events.add('exclusive');
        });
        final later = lock.synchronized('attachment-b', () async {
          events.add('later');
        });
        await Future<void>.delayed(Duration.zero);
        expect(events, ['first']);

        releaseFirst.complete();
        await Future.wait([first, exclusive, later]);
        expect(events, ['first', 'exclusive', 'later']);
      },
    );

    test('an exclusive action error releases queued shared work', () async {
      final lock = MediaAttachmentLifecycleLock();
      final exclusiveEntered = Completer<void>();
      final releaseExclusive = Completer<void>();
      var readerEntered = false;

      final exclusive = lock.synchronizedAll<void>(() async {
        exclusiveEntered.complete();
        await releaseExclusive.future;
        throw StateError('injected exclusive failure');
      });
      await exclusiveEntered.future;
      final reader = lock.synchronized('attachment-a', () async {
        readerEntered = true;
      });
      await Future<void>.delayed(Duration.zero);
      expect(readerEntered, isFalse);

      releaseExclusive.complete();
      await expectLater(exclusive, throwsStateError);
      await reader.timeout(const Duration(seconds: 1));
      expect(readerEntered, isTrue);
    });

    test(
      'queued reader runs before exclusive writers that arrived later',
      () async {
        final lock = MediaAttachmentLifecycleLock();
        final holderEntered = Completer<void>();
        final releaseHolder = Completer<void>();
        final events = <String>[];

        final holder = lock.synchronized('attachment-a', () async {
          holderEntered.complete();
          await releaseHolder.future;
        });
        await holderEntered.future;
        final firstWriter = lock.synchronizedAll(() async {
          events.add('writer-1');
        });
        final reader = lock.synchronized('attachment-b', () async {
          events.add('reader');
        });
        final laterWriter = lock.synchronizedAll(() async {
          events.add('writer-2');
        });
        await Future<void>.delayed(Duration.zero);
        expect(events, isEmpty);

        releaseHolder.complete();
        await Future.wait([holder, firstWriter, reader, laterWriter]);
        expect(events, ['writer-1', 'reader', 'writer-2']);
      },
    );

    test(
      'multi-attachment locking accepts ascending order and rejects inversion',
      () async {
        final lock = MediaAttachmentLifecycleLock();

        await lock.synchronized('attachment-a', () async {
          await lock.synchronized('attachment-b', () async {});
        });

        await expectLater(
          lock.synchronized('attachment-b', () async {
            await lock.synchronized('attachment-a', () async {});
          }),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('exclusive upgrade fails fast instead of deadlocking', () async {
      final lock = MediaAttachmentLifecycleLock();

      await expectLater(
        lock.synchronized(
          'attachment-a',
          () => lock.synchronizedAll(() async {}),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });
}
