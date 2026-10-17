import 'dart:async';

import 'package:flutter_app/core/services/network_path_source.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _push(
  String event, {
  required int epoch,
  int generation = 3,
  Map<String, dynamic> extra = const <String, dynamic>{},
}) => <String, dynamic>{
  'event': event,
  'epoch': epoch,
  'ownerGeneration': generation,
  ...extra,
};

NetworkPathOutcome _outcome(
  NetworkPathStage stage, {
  required int epoch,
  int generation = 3,
}) => NetworkPathOutcome(generation: generation, epoch: epoch, stage: stage);

Future<void> _flush() => Future<void>.delayed(Duration.zero);

void main() {
  late StreamController<Map<String, dynamic>> pushes;
  late NetworkPathSource source;

  setUp(() {
    pushes = StreamController<Map<String, dynamic>>.broadcast(sync: true);
    source = NetworkPathSource(events: pushes.stream);
  });

  tearDown(() async {
    await source.dispose();
    await pushes.close();
  });

  test('a previous-network loss for the ready epoch is delivered once and '
      'never replayed', () async {
    final seen = <NetworkPathOutcome>[];
    final subscription = source.outcomes.listen(seen.add);
    addTearDown(subscription.cancel);
    pushes.add(_push(NetworkPathEvents.changing, epoch: 7));
    pushes.add(_push(NetworkPathEvents.relayReady, epoch: 7));
    pushes.add(_push(NetworkPathEvents.previousLost, epoch: 7));
    pushes.add(_push(NetworkPathEvents.previousLost, epoch: 7));

    expect(seen, <NetworkPathOutcome>[
      _outcome(NetworkPathStage.changing, epoch: 7),
      _outcome(NetworkPathStage.ready, epoch: 7),
      _outcome(NetworkPathStage.previousLost, epoch: 7),
    ]);
    expect(source.current, _outcome(NetworkPathStage.ready, epoch: 7));

    final late = <NetworkPathOutcome>[];
    final lateSubscription = source.outcomes.listen(late.add);
    addTearDown(lateSubscription.cancel);
    await _flush();
    expect(late, <NetworkPathOutcome>[
      _outcome(NetworkPathStage.ready, epoch: 7),
    ]);
  });

  test('a previous-network loss without a matching ready epoch is dropped', () {
    final seen = <NetworkPathOutcome>[];
    final subscription = source.outcomes.listen(seen.add);
    addTearDown(subscription.cancel);

    pushes.add(_push(NetworkPathEvents.previousLost, epoch: 7));
    pushes.add(_push(NetworkPathEvents.changing, epoch: 7));
    pushes.add(_push(NetworkPathEvents.previousLost, epoch: 7));
    pushes.add(_push(NetworkPathEvents.relayReady, epoch: 7));
    pushes.add(_push(NetworkPathEvents.previousLost, epoch: 6));
    pushes.add(_push(NetworkPathEvents.previousLost, epoch: 7, generation: 2));

    expect(seen, <NetworkPathOutcome>[
      _outcome(NetworkPathStage.changing, epoch: 7),
      _outcome(NetworkPathStage.ready, epoch: 7),
    ]);
  });

  test('a new attempt after a failed one (node restart replay) is delivered, '
      'a repeat after ready is not', () {
    final seen = <NetworkPathOutcome>[];
    final subscription = source.outcomes.listen(seen.add);
    addTearDown(subscription.cancel);

    pushes.add(_push(NetworkPathEvents.changing, epoch: 7));
    pushes.add(_push(NetworkPathEvents.relayFailed, epoch: 7));
    pushes.add(_push(NetworkPathEvents.changing, epoch: 7));
    pushes.add(_push(NetworkPathEvents.relayReady, epoch: 7));
    pushes.add(_push(NetworkPathEvents.changing, epoch: 7));
    pushes.add(_push(NetworkPathEvents.relayFailed, epoch: 7));

    expect(seen, <NetworkPathOutcome>[
      _outcome(NetworkPathStage.changing, epoch: 7),
      _outcome(NetworkPathStage.failed, epoch: 7),
      _outcome(NetworkPathStage.changing, epoch: 7),
      _outcome(NetworkPathStage.ready, epoch: 7),
    ]);
    expect(source.current, _outcome(NetworkPathStage.ready, epoch: 7));
  });

  test('a late subscriber sees the latest outcome before live ones', () async {
    pushes.add(_push(NetworkPathEvents.changing, epoch: 7));
    pushes.add(_push(NetworkPathEvents.relayReady, epoch: 7));
    expect(source.current, _outcome(NetworkPathStage.ready, epoch: 7));

    final seen = <NetworkPathOutcome>[];
    final subscription = source.outcomes.listen(seen.add);
    addTearDown(subscription.cancel);
    await _flush();
    pushes.add(_push(NetworkPathEvents.changing, epoch: 8));

    expect(seen, <NetworkPathOutcome>[
      _outcome(NetworkPathStage.ready, epoch: 7),
      _outcome(NetworkPathStage.changing, epoch: 8),
    ]);
  });

  test(
    'a stale epoch or a second terminal outcome cannot change readiness',
    () {
      final seen = <NetworkPathOutcome>[];
      final subscription = source.outcomes.listen(seen.add);
      addTearDown(subscription.cancel);

      pushes.add(_push(NetworkPathEvents.changing, epoch: 7));
      pushes.add(_push(NetworkPathEvents.changing, epoch: 8));
      pushes.add(_push(NetworkPathEvents.relayReady, epoch: 7));
      pushes.add(_push(NetworkPathEvents.relayFailed, epoch: 8));
      pushes.add(_push(NetworkPathEvents.relayReady, epoch: 8));
      // The node replays an epoch it could not finish once its restarted
      // host is up, opening with a fresh path_changing: that is a new
      // attempt, not a repeat.
      pushes.add(_push(NetworkPathEvents.changing, epoch: 8));

      expect(seen, <NetworkPathOutcome>[
        _outcome(NetworkPathStage.changing, epoch: 7),
        _outcome(NetworkPathStage.changing, epoch: 8),
        _outcome(NetworkPathStage.failed, epoch: 8),
        _outcome(NetworkPathStage.changing, epoch: 8),
      ]);
      expect(source.current, _outcome(NetworkPathStage.changing, epoch: 8));
    },
  );

  test('a newer owner generation restarts the epoch order', () {
    final seen = <NetworkPathOutcome>[];
    final subscription = source.outcomes.listen(seen.add);
    addTearDown(subscription.cancel);

    pushes.add(_push(NetworkPathEvents.relayReady, epoch: 9, generation: 3));
    pushes.add(_push(NetworkPathEvents.changing, epoch: 1, generation: 4));
    pushes.add(_push(NetworkPathEvents.relayReady, epoch: 9, generation: 3));

    expect(seen, <NetworkPathOutcome>[
      _outcome(NetworkPathStage.ready, epoch: 9),
      _outcome(NetworkPathStage.changing, epoch: 1, generation: 4),
    ]);
  });

  test('unrelated or malformed pushes are dropped', () {
    final seen = <NetworkPathOutcome>[];
    final subscription = source.outcomes.listen(seen.add);
    addTearDown(subscription.cancel);

    pushes.add(<String, dynamic>{'event': 'relay:state', 'epoch': 1});
    pushes.add(<String, dynamic>{
      'event': NetworkPathEvents.relayReady,
      'ownerGeneration': 3,
    });
    pushes.add(<String, dynamic>{
      'event': NetworkPathEvents.relayReady,
      'epoch': 0,
      'ownerGeneration': 3,
    });
    pushes.add(<String, dynamic>{
      'event': NetworkPathEvents.relayReady,
      'epoch': 'seven',
      'ownerGeneration': 3,
    });
    pushes.add(_push(NetworkPathEvents.relayReady, epoch: 7));

    expect(seen, <NetworkPathOutcome>[
      _outcome(NetworkPathStage.ready, epoch: 7),
    ]);
  });

  test('dispose ends delivery and closes subscribers', () async {
    final seen = <NetworkPathOutcome>[];
    var done = false;
    final subscription = source.outcomes.listen(
      seen.add,
      onDone: () => done = true,
    );
    addTearDown(subscription.cancel);
    pushes.add(_push(NetworkPathEvents.changing, epoch: 7));
    await source.dispose();
    pushes.add(_push(NetworkPathEvents.relayReady, epoch: 7));
    await _flush();

    expect(seen, <NetworkPathOutcome>[
      _outcome(NetworkPathStage.changing, epoch: 7),
    ]);
    expect(done, isTrue);
    expect(source.current, _outcome(NetworkPathStage.changing, epoch: 7));
  });
}
