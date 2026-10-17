import 'dart:async';

/// Go push event names for the default-network handoff (SE-42 D27). The Go
/// node emits `path_changing` once per attempted epoch, then exactly one of
/// `relay_ready` or `relay_failed`. A rename on the Go side lands here only.
abstract final class NetworkPathEvents {
  static const String changing = 'network:path_changing';
  static const String relayReady = 'network:relay_ready';
  static const String relayFailed = 'network:relay_failed';

  /// Emitted by the native watcher (not Go) when Android tears down the
  /// previous default network after its linger.
  static const String previousLost = 'network:previous_path_lost';
  static const Set<String> all = <String>{
    changing,
    relayReady,
    relayFailed,
    previousLost,
  };

  /// Payload keys allowed into Dart. Epoch and owner generation are opaque
  /// counters; everything else the node sends (relay id, address family,
  /// timings) stays in the bridge's flow log, not in this typed source.
  static const String epochKey = 'epoch';
  static const String generationKey = 'ownerGeneration';
}

enum NetworkPathStage {
  changing,
  ready,
  failed,

  /// The previous default network was torn down while this epoch is ready.
  /// A one-shot signal: never stored as the latest outcome.
  previousLost,
}

/// The latest known state of one default-network path epoch.
final class NetworkPathOutcome {
  const NetworkPathOutcome({
    required this.generation,
    required this.epoch,
    required this.stage,
  });

  /// Opaque native runtime owner generation the epoch belongs to.
  final int generation;

  /// Monotonically increasing per owner generation.
  final int epoch;
  final NetworkPathStage stage;

  bool get isReady => stage == NetworkPathStage.ready;

  /// Decodes one bridge event map of the form `{'event': name, ...payload}`.
  /// Returns null for any other event or a payload without integer epoch and
  /// generation.
  static NetworkPathOutcome? fromBridgeEvent(Map<String, dynamic> event) {
    final stage = switch (event['event']) {
      NetworkPathEvents.changing => NetworkPathStage.changing,
      NetworkPathEvents.relayReady => NetworkPathStage.ready,
      NetworkPathEvents.relayFailed => NetworkPathStage.failed,
      NetworkPathEvents.previousLost => NetworkPathStage.previousLost,
      _ => null,
    };
    if (stage == null) return null;
    final epoch = _positiveInt(event[NetworkPathEvents.epochKey]);
    final generation = _int(event[NetworkPathEvents.generationKey]);
    if (epoch == null || generation == null) return null;
    return NetworkPathOutcome(
      generation: generation,
      epoch: epoch,
      stage: stage,
    );
  }

  static int? _int(Object? value) => switch (value) {
    int v => v,
    double v when v == v.truncateToDouble() => v.toInt(),
    _ => null,
  };

  static int? _positiveInt(Object? value) {
    final parsed = _int(value);
    return parsed == null || parsed <= 0 ? null : parsed;
  }

  @override
  bool operator ==(Object other) =>
      other is NetworkPathOutcome &&
      other.generation == generation &&
      other.epoch == epoch &&
      other.stage == stage;

  @override
  int get hashCode => Object.hash(generation, epoch, stage);

  @override
  String toString() =>
      'NetworkPathOutcome(gen=$generation, epoch=$epoch, ${stage.name})';
}

/// Typed default-network path source over the bridge's push events.
///
/// It keeps the latest outcome so a subscriber that arrives after the event
/// still sees it, and it fences stale events: an outcome for an older owner
/// generation or an older epoch, or a second terminal outcome for the same
/// epoch, is dropped. This is separate from the restored-only connectivity
/// signal that feeds inbox drains; a connected Wi-Fi to cellular switch
/// produces an epoch here and nothing there.
final class NetworkPathSource {
  NetworkPathSource({required Stream<Map<String, dynamic>> events}) {
    _subscription = events.listen(
      _onEvent,
      onError: (Object _) {
        // A malformed push cannot break call recovery; the next epoch wins.
      },
    );
  }

  late final StreamSubscription<Map<String, dynamic>> _subscription;
  final StreamController<NetworkPathOutcome> _live =
      StreamController<NetworkPathOutcome>.broadcast(sync: true);
  NetworkPathOutcome? _current;

  NetworkPathOutcome? get current => _current;

  /// Replays [current] to each new listener (it lands in that listener's
  /// first microtask), then delivers live outcomes synchronously, like the
  /// bridge's other broadcast streams.
  Stream<NetworkPathOutcome> get outcomes =>
      Stream<NetworkPathOutcome>.multi((listener) {
        final latest = _current;
        if (latest != null) listener.addSync(latest);
        if (_live.isClosed) {
          listener.closeSync();
          return;
        }
        final live = _live.stream.listen(
          listener.addSync,
          onDone: listener.closeSync,
        );
        listener.onCancel = live.cancel;
      }, isBroadcast: true);

  /// The ready epoch whose previous-network loss was already delivered.
  NetworkPathOutcome? _lossDelivered;

  void _onEvent(Map<String, dynamic> event) {
    final next = NetworkPathOutcome.fromBridgeEvent(event);
    if (next == null) return;
    if (next.stage == NetworkPathStage.previousLost) {
      _onPreviousLost(next);
      return;
    }
    if (!_supersedes(next)) return;
    _current = next;
    if (!_live.isClosed) _live.add(next);
  }

  /// Delivered live once, and only for the current ready epoch of the same
  /// owner. It is not stored, so a later subscriber (a later call) never
  /// replays it.
  void _onPreviousLost(NetworkPathOutcome loss) {
    final current = _current;
    if (current == null ||
        !current.isReady ||
        current.generation != loss.generation ||
        current.epoch != loss.epoch ||
        _lossDelivered == loss) {
      return;
    }
    _lossDelivered = loss;
    if (!_live.isClosed) _live.add(loss);
  }

  bool _supersedes(NetworkPathOutcome next) {
    final current = _current;
    if (current == null) return true;
    if (next.generation != current.generation) {
      return next.generation > current.generation;
    }
    if (next.epoch != current.epoch) return next.epoch > current.epoch;
    // A failed attempt can be retried for the same epoch: the node replays
    // a path it could not finish once its restarted host is up. A ready
    // epoch is final.
    return switch (current.stage) {
      NetworkPathStage.changing => next.stage != NetworkPathStage.changing,
      NetworkPathStage.failed => next.stage == NetworkPathStage.changing,
      _ => false,
    };
  }

  Future<void> dispose() async {
    await _subscription.cancel();
    await _live.close();
  }
}
