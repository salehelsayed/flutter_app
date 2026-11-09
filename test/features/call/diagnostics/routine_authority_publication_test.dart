import 'package:fake_async/fake_async.dart';
import 'package:flutter_app/features/call/diagnostics/routine_authority_publication.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> event(
  String id, {
  String outcome = 'started',
  String stage = 'authority',
  String action = 'publish',
  String? trace,
  int at = 100,
}) => {
  'eventId': id,
  'source': 'flutter',
  'stage': stage,
  'action': action,
  'outcome': outcome,
  'reason': outcome == 'failed' ? 'transport_failed' : 'none',
  'operationId': 'reused-operation',
  'occurredAtMs': at,
  'elapsedMs': at,
  'values': <String, Object?>{},
  if (trace != null) 'traceId': trace,
};

void observe(
  RoutineAuthorityPublicationCoalescer sampler,
  Map<String, Object?> observation,
  Object publication, {
  String state = 'unchanged-capability',
  bool routine = true,
  bool activeCall = false,
  int consent = 1,
}) => sampler.add(
  observation,
  streamKey: 'private-endpoint-stream',
  stateKey: state,
  publication: publication,
  routine: routine,
  activeCall: activeCall,
  consentEpoch: consent,
);

void main() {
  test('coalesces successful refreshes to first start and final ok in 60s', () {
    fakeAsync((clock) {
      final output = <Map<String, Object?>>[];
      final sampler = RoutineAuthorityPublicationCoalescer(
        monotonicNow: () => clock.elapsed,
        emit: output.add,
      );
      final first = Object(), second = Object();
      final firstStart = event('first-start');
      final finalOk = event('second-ok', outcome: 'ok', at: 300);
      observe(sampler, firstStart, first);
      observe(sampler, event('first-ok', outcome: 'ok'), first);
      clock.elapse(const Duration(seconds: 10));
      observe(sampler, event('second-start'), second);
      observe(sampler, finalOk, second);

      expect(output, [firstStart]);
      clock.elapse(const Duration(seconds: 49));
      expect(output, [firstStart]);
      clock.elapse(const Duration(seconds: 1));
      expect(output, [
        firstStart,
        {
          ...finalOk,
          'values': {'count': 2},
        },
      ]);
      expect(finalOk['values'], isEmpty);
      sampler.close();
    });
  });

  test('changed semantic state starts a fresh observation window', () {
    fakeAsync((clock) {
      final output = <Map<String, Object?>>[];
      final sampler = RoutineAuthorityPublicationCoalescer(
        monotonicNow: () => clock.elapsed,
        emit: output.add,
      );
      final first = Object(), changed = Object();
      observe(sampler, event('old-start'), first);
      observe(sampler, event('old-ok', outcome: 'ok'), first);
      observe(
        sampler,
        event('changed-start'),
        changed,
        state: 'new-device-key',
      );
      expect(output.map((e) => e['eventId']), [
        'old-start',
        'old-ok',
        'changed-start',
      ]);
      observe(
        sampler,
        event('changed-ok', outcome: 'ok'),
        changed,
        state: 'new-device-key',
      );
      clock.elapse(const Duration(seconds: 60));
      expect(output.last['eventId'], 'changed-ok');
      expect(output.last['values'], {'count': 1});
      sampler.close();
    });
  });

  test('active-call and trace-bound observations pass through unchanged', () {
    fakeAsync((clock) {
      final output = <Map<String, Object?>>[];
      final sampler = RoutineAuthorityPublicationCoalescer(
        monotonicNow: () => clock.elapsed,
        emit: output.add,
      );
      final active = Object(), traced = Object();
      final observations = [
        event('active-start'),
        event('active-ok', outcome: 'ok'),
        event('trace-start', trace: 'active-call'),
        event('trace-ok', outcome: 'ok', trace: 'active-call'),
      ];
      observe(sampler, observations[0], active, activeCall: true);
      observe(sampler, observations[1], active, activeCall: true);
      observe(sampler, observations[2], traced);
      observe(sampler, observations[3], traced);
      clock.elapse(const Duration(seconds: 60));
      expect(output, observations);
      sampler.close();
    });
  });

  test('interleaved failure retains its own start and exact failure', () {
    fakeAsync((clock) {
      final output = <Map<String, Object?>>[];
      final sampler = RoutineAuthorityPublicationCoalescer(
        monotonicNow: () => clock.elapsed,
        emit: output.add,
      );
      final successful = Object(), failing = Object();
      observe(sampler, event('successful-start'), successful);
      observe(sampler, event('successful-ok', outcome: 'ok'), successful);
      final failureStart = event('failure-start');
      final failure = event('failure', outcome: 'failed');
      observe(sampler, failureStart, failing);
      observe(sampler, failure, failing);
      expect(output, containsAllInOrder([failureStart, failure]));
      expect(output.where((e) => e['eventId'] == 'failure'), [failure]);
      clock.elapse(const Duration(seconds: 60));
      expect(output.where((e) => e['eventId'] == 'failure'), [failure]);
      sampler.close();
    });
  });

  test('reused operation IDs never associate a failure with another start', () {
    fakeAsync((clock) {
      final output = <Map<String, Object?>>[];
      final sampler = RoutineAuthorityPublicationCoalescer(
        monotonicNow: () => clock.elapsed,
        emit: output.add,
      );
      final first = Object(), second = Object();
      final firstStart = event('first-start');
      final secondStart = event('second-start');
      final secondFailure = event('second-failure', outcome: 'failed');
      observe(sampler, firstStart, first);
      observe(sampler, secondStart, second);
      observe(sampler, secondFailure, second);
      observe(sampler, event('first-ok', outcome: 'ok'), first);
      expect(output, containsAllInOrder([secondStart, secondFailure]));
      expect(output.where((e) => e['eventId'] == 'first-start'), [firstStart]);
      expect(output.where((e) => e['eventId'] == 'second-start'), [
        secondStart,
      ]);
      clock.elapse(const Duration(seconds: 60));
      expect(output.where((e) => e['outcome'] == 'failed'), [secondFailure]);
      sampler.close();
    });
  });

  test(
    'consent reset discards pending routine data and preserves new failures',
    () {
      fakeAsync((clock) {
        final output = <Map<String, Object?>>[];
        final sampler = RoutineAuthorityPublicationCoalescer(
          monotonicNow: () => clock.elapsed,
          emit: output.add,
        );
        final old = Object();
        observe(sampler, event('old-start'), old);
        observe(sampler, event('old-ok', outcome: 'ok'), old);
        sampler.reset();
        output
            .clear(); // Existing consent clear erases the retained archive too.
        clock.elapse(const Duration(seconds: 60));
        expect(output, isEmpty);
        final current = Object();
        final failure = event('current-failure', outcome: 'failed');
        observe(sampler, event('current-start'), current, consent: 2);
        observe(sampler, failure, current, consent: 2);
        expect(output, contains(failure));
        sampler.close();
      });
    },
  );

  test('wall-clock rollback cannot extend the monotonic 60-second window', () {
    fakeAsync((clock) {
      final output = <Map<String, Object?>>[];
      final sampler = RoutineAuthorityPublicationCoalescer(
        monotonicNow: () => clock.elapsed,
        emit: output.add,
      );
      final first = Object(), second = Object();
      observe(sampler, event('start-before-clock-change', at: 100000), first);
      observe(sampler, event('ok-before-clock-change', outcome: 'ok'), first);
      clock.elapse(const Duration(seconds: 30));
      observe(sampler, event('start-after-clock-change', at: 1), second);
      observe(
        sampler,
        event('ok-after-clock-change', outcome: 'ok', at: 2),
        second,
      );
      clock.elapse(const Duration(seconds: 30));
      expect(output.map((e) => e['eventId']), [
        'start-before-clock-change',
        'ok-after-clock-change',
      ]);
      expect(output.last['occurredAtMs'], 2);
      sampler.close();
    });
  });

  test('unknown origins, media, terminals and timeouts are never sampled', () {
    fakeAsync((clock) {
      final output = <Map<String, Object?>>[];
      final sampler = RoutineAuthorityPublicationCoalescer(
        monotonicNow: () => clock.elapsed,
        emit: output.add,
      );
      final observations = [
        event('unknown-start'),
        event('unknown-ok', outcome: 'ok'),
        event('media', stage: 'media', action: 'snapshot', outcome: 'ok'),
        event(
          'terminal',
          stage: 'terminal',
          action: 'finish',
          outcome: 'completed',
        ),
        event('timeout', outcome: 'timeout'),
      ];
      for (var index = 0; index < observations.length; index++) {
        observe(sampler, observations[index], Object(), routine: index >= 2);
      }
      clock.elapse(const Duration(seconds: 60));
      expect(output, observations);
      sampler.close();
    });
  });
}
