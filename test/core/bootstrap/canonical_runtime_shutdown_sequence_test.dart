import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_app/app/bootstrap/canonical_runtime_shutdown_sequence.dart';
import 'package:flutter_test/flutter_test.dart';

// Beta 2026-09-24 (F3): the native engine-teardown shutdown request quiesced
// Go and closed SQLCipher while the appShutdown terminate was still resolving
// the peer endpoint. The send failed (`CALL_ENDPOINT_RESOLUTION_RESULT
// stage=trusted_roster_load outcome=error`, then `CALL_CONTROL_SIGNAL_SEND_FAILED
// type=terminate`), so the peer never saw the hang-up.

void main() {
  test('runtime shutdown waits for the call shutdown to settle', () async {
    final log = <String>[];
    final callShutdown = Completer<void>();
    final sequence = CanonicalRuntimeShutdownSequence(
      shutdownRuntime: () async {
        log.add('runtime');
        return true;
      },
    );
    sequence.bindCallShutdown(() {
      log.add('calls:start');
      return callShutdown.future.then((_) => log.add('calls:done'));
    });

    final released = sequence.shutdown();
    await Future<void>.delayed(Duration.zero);
    expect(log, <String>['calls:start']);

    callShutdown.complete();
    expect(await released, isTrue);
    expect(log, <String>['calls:start', 'calls:done', 'runtime']);
  });

  test('a hung call shutdown is bounded by the budget', () {
    fakeAsync((async) {
      final log = <String>[];
      final sequence = CanonicalRuntimeShutdownSequence(
        shutdownRuntime: () async {
          log.add('runtime');
          return true;
        },
        callShutdownBudget: const Duration(seconds: 2),
      );
      sequence.bindCallShutdown(() => Completer<void>().future);

      bool? released;
      sequence.shutdown().then((value) => released = value);
      async.elapse(const Duration(milliseconds: 1999));
      expect(log, isEmpty);
      async.elapse(const Duration(milliseconds: 2));
      async.flushMicrotasks();
      expect(log, <String>['runtime']);
      expect(released, isTrue);
    });
  });

  test('a failed call shutdown still releases the runtime', () async {
    var runtimeShutdowns = 0;
    final sequence = CanonicalRuntimeShutdownSequence(
      shutdownRuntime: () async {
        runtimeShutdowns++;
        return false;
      },
    );
    sequence.bindCallShutdown(() async => throw StateError('send failed'));

    expect(await sequence.shutdown(), isFalse);
    expect(runtimeShutdowns, 1);
  });

  test('without a bound call graph the runtime shuts down directly', () async {
    var runtimeShutdowns = 0;
    final sequence = CanonicalRuntimeShutdownSequence(
      shutdownRuntime: () async {
        runtimeShutdowns++;
        return true;
      },
    );

    expect(await sequence.shutdown(), isTrue);
    expect(runtimeShutdowns, 1);
  });
}
