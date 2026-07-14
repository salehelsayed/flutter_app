import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_app/core/media/app_owned_media_path_authority.dart';
import 'package:flutter_app/core/media/media_owner_lane.dart';
import 'package:flutter_app/core/media/picture_in_picture_gateway.dart';
import 'package:flutter_app/shared/widgets/media/media_picture_in_picture_controller.dart';
import 'package:flutter_app/shared/widgets/media/media_playback_adapter.dart';
import 'package:flutter_app/shared/widgets/media/media_video_resume_controller.dart';
import 'package:flutter_app/shared/widgets/media/media_viewer_item.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'PiP handoff has one playback owner and one normalized durable position',
    () async {
      final order = <String>[];
      final gateway = _FakeGateway(order);
      final playback = _FakePlaybackAdapter(
        order,
        position: const Duration(milliseconds: 3200),
        duration: const Duration(milliseconds: 9000),
        playing: true,
      );
      final store = _ResumeStore(order);
      final restores = <MediaPictureInPictureRestore>[];
      final authorization = _authorization();
      var reloads = 0;
      final controller = MediaPictureInPictureController(
        gateway: gateway,
        pathAuthority: _PathAuthority(order),
        reloadCurrent: () async {
          reloads++;
          return authorization;
        },
        resumeStore: store,
        restorePlayback: (restore) async {
          order.add('restore:${restore.positionMs}:${restore.shouldPlay}');
          restores.add(restore);
        },
        sessionIdFactory: () => 'opaque-session',
        pollTicks: const Stream<void>.empty(),
      );

      expect(
        await controller.start(
          authorization: authorization,
          playback: playback,
        ),
        MediaPictureInPictureStartOutcome.started,
      );
      expect(order, <String>[
        'path',
        'path',
        'capability',
        'write:3200',
        'path',
        'pause',
        'dispose',
        'path',
        'start:3200',
      ]);

      gateway.emit(
        const PictureInPictureEvent(
          session: 'stale-session',
          attachment: 'attachment-1',
          state: PictureInPictureState.active,
          positionMs: 3300,
          durationMs: 9000,
        ),
      );
      gateway.emit(
        const PictureInPictureEvent(
          session: 'opaque-session',
          attachment: 'attachment-1',
          state: PictureInPictureState.nativeReady,
          positionMs: 3200,
          durationMs: 9000,
        ),
      );
      await controller.drain();
      expect(gateway.activateCalls, 1);

      gateway.emit(
        const PictureInPictureEvent(
          session: 'opaque-session',
          attachment: 'attachment-1',
          state: PictureInPictureState.checkpoint,
          positionMs: 4100,
          durationMs: 9000,
        ),
      );
      gateway.emit(
        const PictureInPictureEvent(
          session: 'opaque-session',
          attachment: 'attachment-1',
          state: PictureInPictureState.restoring,
          positionMs: 4500,
          durationMs: 9000,
          reason: PictureInPictureTerminalReason.systemReturn,
        ),
      );
      gateway.emit(
        const PictureInPictureEvent(
          session: 'opaque-session',
          attachment: 'attachment-1',
          state: PictureInPictureState.restoring,
          positionMs: 4700,
          durationMs: 9000,
          reason: PictureInPictureTerminalReason.systemReturn,
        ),
      );
      await controller.drain();

      expect(store.positions, <int>[3200, 4100, 4500]);
      expect(restores, hasLength(1));
      expect(restores.single.positionMs, 4500);
      expect(restores.single.shouldPlay, isTrue);
      expect(playback.pauseCalls, 1);
      expect(playback.disposeCalls, 1);
      expect(reloads, greaterThanOrEqualTo(4));
      expect(
        order.indexOf('dispose'),
        lessThan(order.indexOf('start:3200')),
        reason: 'Flutter owner must be gone before native starts',
      );
      expect(
        order.indexOf('write:4500'),
        lessThan(order.indexOf('restore:4500:true')),
        reason: 'one durable owner checkpoint precedes Flutter recreation',
      );
    },
  );

  testWidgets(
    'drain quiesces after successful handoff without requiring a frame pump',
    (tester) async {
      final order = <String>[];
      final gateway = _FakeGateway(order);
      final authorization = _authorization();
      final controller = MediaPictureInPictureController(
        gateway: gateway,
        pathAuthority: _PathAuthority(order),
        reloadCurrent: () async => authorization,
        resumeStore: _ResumeStore(order),
        restorePlayback: (_) async {},
        sessionIdFactory: () => 'opaque-session',
        pollTicks: const Stream<void>.empty(),
      );

      final start = controller.start(
        authorization: authorization,
        playback: _FakePlaybackAdapter(
          order,
          position: const Duration(milliseconds: 3200),
          duration: const Duration(milliseconds: 9000),
          playing: true,
        ),
      );
      await tester.pump();
      expect(await start, MediaPictureInPictureStartOutcome.started);

      await controller.drain();

      expect(order, contains('start:3200'));
    },
  );

  test(
    'active PiP authorization signal stops native before the polling backstop',
    () async {
      final order = <String>[];
      final gateway = _FakeGateway(order);
      final revocations = StreamController<void>();
      final pollTicks = StreamController<void>();
      final authorization = _authorization();
      var current = authorization;
      final controller = MediaPictureInPictureController(
        gateway: gateway,
        pathAuthority: _PathAuthority(order),
        reloadCurrent: () async => current,
        resumeStore: _ResumeStore(order),
        restorePlayback: (_) async => order.add('restore'),
        authorizationChanges: revocations.stream,
        pollTicks: pollTicks.stream,
        sessionIdFactory: () => 'opaque-session',
      );
      addTearDown(() async {
        await controller.dispose();
        await revocations.close();
        await pollTicks.close();
      });

      expect(
        await controller.start(
          authorization: authorization,
          playback: _FakePlaybackAdapter(
            order,
            position: const Duration(milliseconds: 1000),
            duration: const Duration(milliseconds: 9000),
            playing: true,
          ),
        ),
        MediaPictureInPictureStartOutcome.started,
      );
      current = _authorization(
        policyState: MediaPictureInPicturePolicyState.expired,
      );
      revocations.add(null);
      await controller.drain();

      expect(gateway.stopCalls, 1);
      expect(order, isNot(contains('restore')));
      pollTicks.add(null);
      await controller.drain();
      expect(gateway.stopCalls, 1, reason: 'revocation settles exactly once');
    },
  );

  test(
    'authorization signal and poll bypass a blocked checkpoint backlog',
    () async {
      for (final trigger in <String>['signal', 'poll']) {
        final order = <String>[];
        final gateway = _FakeGateway(order);
        final store = _BlockingResumeStore(order, blockPositionMs: 2000);
        final revocations = StreamController<void>();
        final pollTicks = StreamController<void>();
        final authorization = _authorization();
        var current = authorization;
        final controller = MediaPictureInPictureController(
          gateway: gateway,
          pathAuthority: _PathAuthority(order),
          reloadCurrent: () async => current,
          resumeStore: store,
          restorePlayback: (_) async => order.add('restore'),
          authorizationChanges: revocations.stream,
          pollTicks: pollTicks.stream,
          sessionIdFactory: () => 'opaque-session-$trigger',
        );

        try {
          expect(
            await controller.start(
              authorization: authorization,
              playback: _FakePlaybackAdapter(
                order,
                position: const Duration(milliseconds: 1000),
                duration: const Duration(milliseconds: 9000),
                playing: true,
              ),
            ),
            MediaPictureInPictureStartOutcome.started,
          );
          gateway.emit(
            PictureInPictureEvent(
              session: 'opaque-session-$trigger',
              attachment: 'attachment-1',
              state: PictureInPictureState.checkpoint,
              positionMs: 2000,
              durationMs: 9000,
            ),
          );
          await store.blocked;
          for (var positionMs = 2100; positionMs <= 2900; positionMs += 100) {
            gateway.emit(
              PictureInPictureEvent(
                session: 'opaque-session-$trigger',
                attachment: 'attachment-1',
                state: PictureInPictureState.checkpoint,
                positionMs: positionMs,
                durationMs: 9000,
              ),
            );
          }

          current = _authorization(
            policyState: MediaPictureInPicturePolicyState.expired,
          );
          if (trigger == 'signal') {
            revocations.add(null);
          } else {
            pollTicks.add(null);
          }

          await gateway.stopObserved.future.timeout(const Duration(seconds: 1));
          expect(gateway.stopCalls, 1, reason: trigger);
          expect(
            store.positions,
            <int>[1000, 2000],
            reason: '$trigger must not drain queued checkpoint writes',
          );

          store.release();
          await controller.drain();
          expect(store.positions, <int>[1000, 2000], reason: trigger);
          expect(store.maxConcurrentWrites, 1, reason: trigger);
          expect(order, isNot(contains('restore')), reason: trigger);
        } finally {
          store.release();
          await controller.dispose();
          await revocations.close();
          await pollTicks.close();
        }
      }
    },
  );

  test(
    'authorization change during blocked handoff prevents native exposure',
    () async {
      final order = <String>[];
      final gateway = _FakeGateway(order);
      final store = _BlockingResumeStore(order, blockPositionMs: 1000);
      final revocations = StreamController<void>();
      final authorization = _authorization();
      var current = authorization;
      final playback = _FakePlaybackAdapter(
        order,
        position: const Duration(milliseconds: 1000),
        duration: const Duration(milliseconds: 9000),
        playing: true,
      );
      final controller = MediaPictureInPictureController(
        gateway: gateway,
        pathAuthority: _PathAuthority(order),
        reloadCurrent: () async => current,
        resumeStore: store,
        restorePlayback: (_) async => order.add('restore'),
        authorizationChanges: revocations.stream,
        pollTicks: const Stream<void>.empty(),
        sessionIdFactory: () => 'opaque-session',
      );

      try {
        final start = controller.start(
          authorization: authorization,
          playback: playback,
        );
        await store.blocked;
        current = _authorization(
          policyState: MediaPictureInPicturePolicyState.expired,
        );
        revocations.add(null);
        await Future<void>.delayed(Duration.zero);

        store.release();
        expect(await start, MediaPictureInPictureStartOutcome.denied);
        expect(order, isNot(contains('start:1000')));
        expect(gateway.stopCalls, 0);
        expect(playback.pauseCalls, 0);
        expect(playback.disposeCalls, 0);
      } finally {
        store.release();
        await controller.dispose();
        await revocations.close();
      }
    },
  );

  test(
    'silent authorization change during blocked handoff prevents native exposure',
    () async {
      final order = <String>[];
      final gateway = _FakeGateway(order);
      final store = _BlockingResumeStore(order, blockPositionMs: 1000);
      final authorization = _authorization();
      var current = authorization;
      final playback = _FakePlaybackAdapter(
        order,
        position: const Duration(milliseconds: 1000),
        duration: const Duration(milliseconds: 9000),
        playing: true,
      );
      final controller = MediaPictureInPictureController(
        gateway: gateway,
        pathAuthority: _PathAuthority(order),
        reloadCurrent: () async => current,
        resumeStore: store,
        restorePlayback: (_) async => order.add('restore'),
        pollTicks: const Stream<void>.empty(),
        sessionIdFactory: () => 'opaque-session',
      );

      try {
        final start = controller.start(
          authorization: authorization,
          playback: playback,
        );
        await store.blocked;
        current = _authorization(
          policyState: MediaPictureInPicturePolicyState.expired,
        );

        store.release();
        expect(await start, MediaPictureInPictureStartOutcome.denied);
        expect(order, isNot(contains('start:1000')));
        expect(gateway.stopCalls, 0);
        expect(playback.pauseCalls, 0);
        expect(playback.disposeCalls, 0);
      } finally {
        store.release();
        await controller.dispose();
      }
    },
  );

  test(
    'post-disposal transient exact-current failure restores Flutter once',
    () async {
      for (final failure in <String>['reload', 'path']) {
        final order = <String>[];
        final gateway = _FakeGateway(order);
        final authorization = _authorization();
        final restores = <MediaPictureInPictureRestore>[];
        var reloads = 0;
        var pathCalls = 0;
        final controller = MediaPictureInPictureController(
          gateway: gateway,
          pathAuthority: _PathAuthority(
            order,
            shouldThrow: () {
              pathCalls++;
              return failure == 'path' && pathCalls == 4;
            },
          ),
          reloadCurrent: () async {
            reloads++;
            if (failure == 'reload' && reloads == 3) {
              throw StateError('transient final reload failure');
            }
            return authorization;
          },
          resumeStore: _ResumeStore(order),
          restorePlayback: (restore) async {
            restores.add(restore);
            order.add('restore:${restore.positionMs}:${restore.shouldPlay}');
          },
          pollTicks: const Stream<void>.empty(),
          sessionIdFactory: () => 'opaque-session-$failure',
        );

        try {
          expect(
            await controller.start(
              authorization: authorization,
              playback: _FakePlaybackAdapter(
                order,
                position: const Duration(milliseconds: 1000),
                duration: const Duration(milliseconds: 9000),
                playing: true,
              ),
            ),
            MediaPictureInPictureStartOutcome.denied,
            reason: failure,
          );
          expect(order, isNot(contains('start:1000')), reason: failure);
          expect(restores, hasLength(1), reason: failure);
          expect(restores.single.positionMs, 1000);
          expect(restores.single.shouldPlay, isTrue);
          expect(gateway.stopCalls, 0, reason: failure);
        } finally {
          await controller.dispose();
        }
      }
    },
  );

  test(
    'benign final-fence epoch change restores Flutter without native exposure',
    () async {
      final order = <String>[];
      final gateway = _FakeGateway(order);
      final authorization = _authorization();
      final pollTicks = StreamController<void>();
      final finalReloadEntered = Completer<void>();
      final releaseFinalReload = Completer<void>();
      final restores = <MediaPictureInPictureRestore>[];
      var reloads = 0;
      final controller = MediaPictureInPictureController(
        gateway: gateway,
        pathAuthority: _PathAuthority(order),
        reloadCurrent: () async {
          reloads++;
          if (reloads == 3) {
            finalReloadEntered.complete();
            await releaseFinalReload.future;
          }
          return authorization;
        },
        resumeStore: _ResumeStore(order),
        restorePlayback: (restore) async {
          restores.add(restore);
          order.add('restore:${restore.positionMs}:${restore.shouldPlay}');
        },
        pollTicks: pollTicks.stream,
        sessionIdFactory: () => 'opaque-session',
      );

      try {
        final start = controller.start(
          authorization: authorization,
          playback: _FakePlaybackAdapter(
            order,
            position: const Duration(milliseconds: 1000),
            duration: const Duration(milliseconds: 9000),
            playing: true,
          ),
        );
        await finalReloadEntered.future;
        pollTicks.add(null);
        releaseFinalReload.complete();

        expect(await start, MediaPictureInPictureStartOutcome.denied);
        await controller.drain();
        expect(order, isNot(contains('start:1000')));
        expect(restores, hasLength(1));
        expect(restores.single.positionMs, 1000);
        expect(restores.single.shouldPlay, isTrue);
        expect(gateway.stopCalls, 0);
      } finally {
        if (!releaseFinalReload.isCompleted) releaseFinalReload.complete();
        await controller.dispose();
        await pollTicks.close();
      }
    },
  );

  test(
    'post-disposal true revocation never resurrects Flutter or starts native',
    () async {
      final order = <String>[];
      final gateway = _FakeGateway(order);
      final authorization = _authorization();
      var current = authorization;
      final restores = <MediaPictureInPictureRestore>[];
      final controller = MediaPictureInPictureController(
        gateway: gateway,
        pathAuthority: _PathAuthority(order),
        reloadCurrent: () async => current,
        resumeStore: _ResumeStore(order),
        restorePlayback: (restore) async => restores.add(restore),
        pollTicks: const Stream<void>.empty(),
        sessionIdFactory: () => 'opaque-session',
      );

      try {
        expect(
          await controller.start(
            authorization: authorization,
            playback: _FakePlaybackAdapter(
              order,
              position: const Duration(milliseconds: 1000),
              duration: const Duration(milliseconds: 9000),
              playing: true,
              onDispose: () async {
                current = _authorization(
                  policyState: MediaPictureInPicturePolicyState.expired,
                );
              },
            ),
          ),
          MediaPictureInPictureStartOutcome.denied,
        );
        expect(order, isNot(contains('start:1000')));
        expect(restores, isEmpty);
        expect(gateway.stopCalls, 0);
      } finally {
        await controller.dispose();
      }
    },
  );

  test(
    'route disposal after playback teardown never restores or starts native',
    () async {
      final order = <String>[];
      final gateway = _FakeGateway(order);
      final authorization = _authorization();
      final playbackDisposeEntered = Completer<void>();
      final releasePlaybackDispose = Completer<void>();
      final restores = <MediaPictureInPictureRestore>[];
      final controller = MediaPictureInPictureController(
        gateway: gateway,
        pathAuthority: _PathAuthority(order),
        reloadCurrent: () async => authorization,
        resumeStore: _ResumeStore(order),
        restorePlayback: (restore) async => restores.add(restore),
        pollTicks: const Stream<void>.empty(),
        sessionIdFactory: () => 'opaque-session',
      );
      Future<void>? disposal;

      try {
        final start = controller.start(
          authorization: authorization,
          playback: _FakePlaybackAdapter(
            order,
            position: const Duration(milliseconds: 1000),
            duration: const Duration(milliseconds: 9000),
            playing: true,
            onDispose: () async {
              playbackDisposeEntered.complete();
              await releasePlaybackDispose.future;
            },
          ),
        );
        await playbackDisposeEntered.future;
        disposal = controller.dispose();
        releasePlaybackDispose.complete();

        expect(await start, MediaPictureInPictureStartOutcome.nativeRejected);
        await disposal;
        expect(order, isNot(contains('start:1000')));
        expect(restores, isEmpty);
        expect(gateway.stopCalls, 0);
      } finally {
        if (!releasePlaybackDispose.isCompleted) {
          releasePlaybackDispose.complete();
        }
        await (disposal ?? controller.dispose());
      }
    },
  );

  test(
    'dispose priority-stops before a blocked checkpoint can drain',
    () async {
      final order = <String>[];
      final gateway = _FakeGateway(order);
      final store = _BlockingResumeStore(order, blockPositionMs: 2000);
      final authorization = _authorization();
      final controller = MediaPictureInPictureController(
        gateway: gateway,
        pathAuthority: _PathAuthority(order),
        reloadCurrent: () async => authorization,
        resumeStore: store,
        restorePlayback: (_) async => order.add('restore'),
        pollTicks: const Stream<void>.empty(),
        sessionIdFactory: () => 'opaque-session',
      );
      Future<void>? disposal;

      try {
        await controller.start(
          authorization: authorization,
          playback: _FakePlaybackAdapter(
            order,
            position: const Duration(milliseconds: 1000),
            duration: const Duration(milliseconds: 9000),
            playing: true,
          ),
        );
        gateway.emit(
          const PictureInPictureEvent(
            session: 'opaque-session',
            attachment: 'attachment-1',
            state: PictureInPictureState.checkpoint,
            positionMs: 2000,
            durationMs: 9000,
          ),
        );
        await store.blocked;
        for (final positionMs in <int>[2100, 2200, 2300, 2400]) {
          gateway.emit(
            PictureInPictureEvent(
              session: 'opaque-session',
              attachment: 'attachment-1',
              state: PictureInPictureState.checkpoint,
              positionMs: positionMs,
              durationMs: 9000,
            ),
          );
        }

        disposal = controller.dispose();
        await gateway.stopObserved.future.timeout(const Duration(seconds: 1));
        expect(gateway.stopCalls, 1);
        expect(store.positions, <int>[1000, 2000]);

        store.release();
        await disposal;
        expect(store.positions, <int>[1000, 2000]);
        expect(store.maxConcurrentWrites, 1);
        expect(order, isNot(contains('restore')));
      } finally {
        store.release();
        await (disposal ?? controller.dispose());
      }
    },
  );

  test('dispose during blocked handoff prevents native exposure', () async {
    final order = <String>[];
    final gateway = _FakeGateway(order);
    final store = _BlockingResumeStore(order, blockPositionMs: 1000);
    final authorization = _authorization();
    final playback = _FakePlaybackAdapter(
      order,
      position: const Duration(milliseconds: 1000),
      duration: const Duration(milliseconds: 9000),
      playing: true,
    );
    final controller = MediaPictureInPictureController(
      gateway: gateway,
      pathAuthority: _PathAuthority(order),
      reloadCurrent: () async => authorization,
      resumeStore: store,
      restorePlayback: (_) async => order.add('restore'),
      pollTicks: const Stream<void>.empty(),
      sessionIdFactory: () => 'opaque-session',
    );
    Future<void>? disposal;

    try {
      final start = controller.start(
        authorization: authorization,
        playback: playback,
      );
      await store.blocked;
      disposal = controller.dispose();

      store.release();
      expect(await start, MediaPictureInPictureStartOutcome.nativeRejected);
      await disposal;

      expect(order, isNot(contains('start:1000')));
      expect(gateway.stopCalls, 0);
      expect(playback.pauseCalls, 0);
      expect(playback.disposeCalls, 0);
    } finally {
      store.release();
      await (disposal ?? controller.dispose());
    }
  });

  test(
    'checkpoint backlog retains only the exact latest authorized position',
    () async {
      final order = <String>[];
      final gateway = _FakeGateway(order);
      final store = _BlockingResumeStore(order, blockPositionMs: 2000);
      final authorization = _authorization();
      final controller = MediaPictureInPictureController(
        gateway: gateway,
        pathAuthority: _PathAuthority(order),
        reloadCurrent: () async => authorization,
        resumeStore: store,
        restorePlayback: (_) async => order.add('restore'),
        pollTicks: const Stream<void>.empty(),
        sessionIdFactory: () => 'opaque-session',
      );

      try {
        await controller.start(
          authorization: authorization,
          playback: _FakePlaybackAdapter(
            order,
            position: const Duration(milliseconds: 1000),
            duration: const Duration(milliseconds: 9000),
            playing: true,
          ),
        );
        gateway.emit(
          const PictureInPictureEvent(
            session: 'opaque-session',
            attachment: 'attachment-1',
            state: PictureInPictureState.checkpoint,
            positionMs: 2000,
            durationMs: 9000,
          ),
        );
        await store.blocked;
        for (var positionMs = 2100; positionMs <= 2900; positionMs += 100) {
          gateway.emit(
            PictureInPictureEvent(
              session: 'opaque-session',
              attachment: 'attachment-1',
              state: PictureInPictureState.checkpoint,
              positionMs: positionMs,
              durationMs: 9000,
            ),
          );
        }

        expect(store.positions, <int>[1000, 2000]);
        store.release();
        await controller.drain();

        expect(store.positions, <int>[1000, 2000, 2900]);
        expect(store.maxConcurrentWrites, 1);
      } finally {
        store.release();
        await controller.dispose();
      }
    },
  );

  test(
    'terminal restore supersedes checkpoint backlog and preserves write order',
    () async {
      final order = <String>[];
      final gateway = _FakeGateway(order);
      final store = _BlockingResumeStore(order, blockPositionMs: 2000);
      final restores = <MediaPictureInPictureRestore>[];
      final authorization = _authorization();
      final controller = MediaPictureInPictureController(
        gateway: gateway,
        pathAuthority: _PathAuthority(order),
        reloadCurrent: () async => authorization,
        resumeStore: store,
        restorePlayback: (restore) async {
          restores.add(restore);
          order.add('restore:${restore.positionMs}:${restore.shouldPlay}');
        },
        pollTicks: const Stream<void>.empty(),
        sessionIdFactory: () => 'opaque-session',
      );

      try {
        await controller.start(
          authorization: authorization,
          playback: _FakePlaybackAdapter(
            order,
            position: const Duration(milliseconds: 1000),
            duration: const Duration(milliseconds: 9000),
            playing: true,
          ),
        );
        gateway.emit(
          const PictureInPictureEvent(
            session: 'opaque-session',
            attachment: 'attachment-1',
            state: PictureInPictureState.checkpoint,
            positionMs: 2000,
            durationMs: 9000,
          ),
        );
        await store.blocked;
        for (final positionMs in <int>[2100, 2200, 2300, 2400]) {
          gateway.emit(
            PictureInPictureEvent(
              session: 'opaque-session',
              attachment: 'attachment-1',
              state: PictureInPictureState.checkpoint,
              positionMs: positionMs,
              durationMs: 9000,
            ),
          );
        }
        gateway.emit(
          const PictureInPictureEvent(
            session: 'opaque-session',
            attachment: 'attachment-1',
            state: PictureInPictureState.restoring,
            positionMs: 4500,
            durationMs: 9000,
            reason: PictureInPictureTerminalReason.systemReturn,
          ),
        );
        gateway.emit(
          const PictureInPictureEvent(
            session: 'opaque-session',
            attachment: 'attachment-1',
            state: PictureInPictureState.restoring,
            positionMs: 4700,
            durationMs: 9000,
            reason: PictureInPictureTerminalReason.systemReturn,
          ),
        );

        store.release();
        await controller.drain();

        expect(store.positions, <int>[1000, 2000, 4500]);
        expect(restores, hasLength(1));
        expect(restores.single.positionMs, 4500);
        expect(restores.single.shouldPlay, isTrue);
        expect(store.maxConcurrentWrites, 1);
        expect(
          order.indexOf('write:4500'),
          lessThan(order.indexOf('restore:4500:true')),
        );
      } finally {
        store.release();
        await controller.dispose();
      }
    },
  );

  test(
    'native return persists only after exact current reauthorization',
    () async {
      final order = <String>[];
      final gateway = _FakeGateway(order);
      final store = _ResumeStore(order);
      final restores = <MediaPictureInPictureRestore>[];
      final authorization = _authorization();
      MediaPictureInPictureAuthorization? current = authorization;
      final controller = MediaPictureInPictureController(
        gateway: gateway,
        pathAuthority: _PathAuthority(order),
        reloadCurrent: () async => current,
        resumeStore: store,
        restorePlayback: (restore) async => restores.add(restore),
        sessionIdFactory: () => 'opaque-session',
        pollTicks: const Stream<void>.empty(),
      );
      addTearDown(controller.dispose);
      await controller.start(
        authorization: authorization,
        playback: _FakePlaybackAdapter(
          order,
          position: const Duration(milliseconds: 1000),
          duration: const Duration(milliseconds: 9000),
          playing: false,
        ),
      );
      current = null;
      gateway.emit(
        const PictureInPictureEvent(
          session: 'opaque-session',
          attachment: 'attachment-1',
          state: PictureInPictureState.restoring,
          positionMs: 5000,
          durationMs: 9000,
          reason: PictureInPictureTerminalReason.systemReturn,
        ),
      );
      await controller.drain();

      expect(store.positions, <int>[1000]);
      expect(restores, isEmpty);
    },
  );

  test(
    'activate reject or throw restores Flutter once after the handoff checkpoint',
    () async {
      for (final throws in <bool>[false, true]) {
        final order = <String>[];
        final gateway = _FakeGateway(
          order,
          activateFailure: true,
          throwOnActivate: throws,
          emitFailureOnActivate: !throws,
        );
        final store = _ResumeStore(order);
        final restores = <MediaPictureInPictureRestore>[];
        final authorization = _authorization();
        final controller = MediaPictureInPictureController(
          gateway: gateway,
          pathAuthority: _PathAuthority(order),
          reloadCurrent: () async => authorization,
          resumeStore: store,
          restorePlayback: (restore) async => restores.add(restore),
          sessionIdFactory: () => 'opaque-session',
          pollTicks: const Stream<void>.empty(),
        );

        expect(
          await controller.start(
            authorization: authorization,
            playback: _FakePlaybackAdapter(
              order,
              position: const Duration(milliseconds: 2300),
              duration: const Duration(milliseconds: 9000),
              playing: true,
            ),
          ),
          MediaPictureInPictureStartOutcome.started,
        );
        gateway.emit(
          const PictureInPictureEvent(
            session: 'opaque-session',
            attachment: 'attachment-1',
            state: PictureInPictureState.nativeReady,
            positionMs: 2300,
            durationMs: 9000,
          ),
        );
        await controller.drain();

        expect(store.positions, <int>[2300], reason: 'throws=$throws');
        expect(restores, hasLength(1), reason: 'throws=$throws');
        expect(restores.single.positionMs, 2300);
        expect(restores.single.shouldPlay, isTrue);
        await controller.dispose();
      }
    },
  );

  test(
    'reload and path exceptions revoke authority and stop exactly once',
    () async {
      for (final pathThrows in <bool>[false, true]) {
        final order = <String>[];
        final gateway = _FakeGateway(order);
        final ticks = StreamController<void>();
        final authorization = _authorization();
        var revoked = false;
        final controller = MediaPictureInPictureController(
          gateway: gateway,
          pathAuthority: _PathAuthority(
            order,
            shouldThrow: () => revoked && pathThrows,
          ),
          reloadCurrent: () async {
            if (revoked && !pathThrows) {
              throw StateError('current-row reload failed');
            }
            return authorization;
          },
          resumeStore: _ResumeStore(order),
          restorePlayback: (_) async => order.add('restore'),
          sessionIdFactory: () => 'opaque-session',
          pollTicks: ticks.stream,
        );

        expect(
          await controller.start(
            authorization: authorization,
            playback: _FakePlaybackAdapter(
              order,
              position: const Duration(milliseconds: 1000),
              duration: const Duration(milliseconds: 9000),
              playing: true,
            ),
          ),
          MediaPictureInPictureStartOutcome.started,
        );
        revoked = true;
        ticks.add(null);
        ticks.add(null);
        await controller.drain();

        expect(gateway.stopCalls, 1, reason: 'pathThrows=$pathThrows');
        expect(order, isNot(contains('restore')));
        await controller.dispose();
        await ticks.close();
      }
    },
  );
}

MediaPictureInPictureAuthorization _authorization({
  MediaPictureInPicturePolicyState policyState =
      MediaPictureInPicturePolicyState.ordinary,
}) => MediaPictureInPictureAuthorization(
  item: const MediaViewerItem(
    attachmentId: 'attachment-1',
    messageId: 'message-1',
    kind: MediaViewerKind.video,
    mime: 'video/mp4',
    owner: MediaOwnerLane.direct,
    localPath: '/app/Documents/media/video.mp4',
    durationMs: 9000,
    canEnterPictureInPicture: true,
  ),
  generation: 7,
  policyState: policyState,
  isIncoming: true,
  isTransferComplete: true,
  routeActive: true,
);

class _FakeGateway implements PictureInPictureGateway {
  _FakeGateway(
    this.order, {
    this.activateFailure = false,
    this.throwOnActivate = false,
    this.emitFailureOnActivate = false,
  });

  final List<String> order;
  final bool activateFailure;
  final bool throwOnActivate;
  final bool emitFailureOnActivate;
  final _events = StreamController<PictureInPictureEvent>.broadcast(sync: true);
  int activateCalls = 0;
  int stopCalls = 0;
  final stopObserved = Completer<void>();

  void emit(PictureInPictureEvent event) => _events.add(event);

  @override
  Stream<PictureInPictureEvent> get events => _events.stream;

  @override
  Future<PictureInPictureCapability> capability() async {
    order.add('capability');
    return const PictureInPictureCapability.androidSupported();
  }

  @override
  Future<PictureInPictureStartOutcome> start(
    PictureInPictureRequest request,
  ) async {
    order.add('start:${request.positionMs}');
    return PictureInPictureStartOutcome.started;
  }

  @override
  Future<PictureInPictureCommandResult> activate(
    String session,
    String attachment,
  ) async {
    activateCalls++;
    order.add('activate');
    if (emitFailureOnActivate) {
      emit(
        PictureInPictureEvent(
          session: session,
          attachment: attachment,
          state: PictureInPictureState.failed,
          positionMs: 2300,
          durationMs: 9000,
          reason: PictureInPictureTerminalReason.channelFailure,
        ),
      );
    }
    if (throwOnActivate) throw StateError('activate channel failed');
    return activateFailure
        ? const PictureInPictureCommandResult.rejected(
            PictureInPictureFailureReason.channelFailure,
          )
        : const PictureInPictureCommandResult.success();
  }

  @override
  Future<PictureInPictureCommandResult> stop(
    String session,
    String attachment,
  ) async {
    stopCalls++;
    order.add('stop');
    if (!stopObserved.isCompleted) stopObserved.complete();
    return const PictureInPictureCommandResult.success();
  }

  @override
  Future<void> dispose() => _events.close();
}

class _PathAuthority implements AppOwnedMediaPathAuthority {
  _PathAuthority(this.order, {this.shouldThrow});
  final List<String> order;
  final bool Function()? shouldThrow;

  @override
  Future<String?> authorize(String? candidatePath) async {
    order.add('path');
    if (shouldThrow?.call() ?? false) {
      throw StateError('path authorization failed');
    }
    return candidatePath;
  }
}

class _ResumeStore implements MediaViewerResumeStore {
  _ResumeStore(this.order);
  final List<String> order;
  final positions = <int>[];

  @override
  Future<int?> readResumePosition(MediaViewerItem item) async => null;

  @override
  Future<void> writeResumePosition(MediaViewerItem item, int positionMs) async {
    positions.add(positionMs);
    order.add('write:$positionMs');
  }
}

class _BlockingResumeStore implements MediaViewerResumeStore {
  _BlockingResumeStore(this.order, {required this.blockPositionMs});

  final List<String> order;
  final int blockPositionMs;
  final positions = <int>[];
  final _blocked = Completer<void>();
  final _release = Completer<void>();
  var _didBlock = false;
  var _concurrentWrites = 0;
  var maxConcurrentWrites = 0;

  Future<void> get blocked => _blocked.future;

  void release() {
    if (!_release.isCompleted) _release.complete();
  }

  @override
  Future<int?> readResumePosition(MediaViewerItem item) async => null;

  @override
  Future<void> writeResumePosition(MediaViewerItem item, int positionMs) async {
    _concurrentWrites++;
    if (_concurrentWrites > maxConcurrentWrites) {
      maxConcurrentWrites = _concurrentWrites;
    }
    positions.add(positionMs);
    order.add('write:$positionMs');
    try {
      if (!_didBlock && positionMs == blockPositionMs) {
        _didBlock = true;
        if (!_blocked.isCompleted) _blocked.complete();
        await _release.future;
      }
    } finally {
      _concurrentWrites--;
    }
  }
}

class _FakePlaybackAdapter extends MediaPlaybackAdapter {
  _FakePlaybackAdapter(
    this.order, {
    required this.position,
    required this.duration,
    required bool playing,
    this.onDispose,
  }) : _playing = playing;

  final List<String> order;
  @override
  final Duration position;
  @override
  final Duration duration;
  final Future<void> Function()? onDispose;
  bool _playing;
  int pauseCalls = 0;
  int disposeCalls = 0;

  @override
  double get aspectRatio => 1;
  @override
  Object? get initializationError => null;
  @override
  bool get isCompleted => false;
  @override
  bool get isInitialized => true;
  @override
  bool get isMuted => false;
  @override
  bool get isPlaying => _playing;
  @override
  double get speed => 1;
  @override
  void addListener(void Function() listener) {}
  @override
  Widget buildSurface() => const SizedBox.shrink();
  @override
  Future<void> dispose() async {
    disposeCalls++;
    order.add('dispose');
    await onDispose?.call();
  }

  @override
  Future<void> initialize() async {}
  @override
  Future<void> pause() async {
    pauseCalls++;
    _playing = false;
    order.add('pause');
  }

  @override
  Future<void> play() async => _playing = true;
  @override
  void removeListener(void Function() listener) {}
  @override
  Future<void> seekTo(Duration position) async {}
  @override
  Future<void> setMuted(bool muted) async {}
  @override
  Future<void> setSpeed(double speed) async {}
}
