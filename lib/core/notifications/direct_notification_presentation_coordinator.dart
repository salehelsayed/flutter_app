import 'dart:async';

/// One final notification mutation lane per direct peer.
///
/// Foreground shows, read cancellation, and canonical reconciliation all use
/// this owner. Different peers remain concurrent; operations for one stable OS
/// card cannot overtake each other.
final class DirectNotificationPresentationCoordinator {
  final Map<String, _DirectOperationQueue> _queues =
      <String, _DirectOperationQueue>{};

  Future<T> runForPeer<T>(String peerId, Future<T> Function() operation) async {
    final key = peerId.trim();
    if (key.isEmpty) {
      throw ArgumentError.value(peerId, 'peerId', 'must not be empty');
    }
    final queue = _queues.putIfAbsent(key, _DirectOperationQueue.new);
    final previous = queue.tail;
    final release = Completer<void>();
    queue
      ..tail = release.future
      ..pending += 1;
    await previous;
    try {
      return await operation();
    } finally {
      release.complete();
      queue.pending -= 1;
      if (queue.pending == 0 &&
          identical(queue.tail, release.future) &&
          identical(_queues[key], queue)) {
        _queues.remove(key);
      }
    }
  }

  int get debugActiveKeyCount => _queues.length;
}

final class _DirectOperationQueue {
  Future<void> tail = Future<void>.value();
  int pending = 0;
}
