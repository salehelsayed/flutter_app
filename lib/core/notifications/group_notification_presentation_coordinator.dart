import 'dart:async';

/// Serializes final notification operations per group while allowing unrelated
/// groups to proceed independently.
///
/// Presenters must place their final eligibility/unread check and OS show in
/// the keyed callback. The read projector uses the same callback for its fresh
/// unread recheck and exact cancellation, closing both show/read interleavings.
final class GroupNotificationPresentationCoordinator {
  final Map<String, _GroupOperationQueue> _queues =
      <String, _GroupOperationQueue>{};

  Future<T> runForGroup<T>(
    String groupId,
    Future<T> Function() operation,
  ) async {
    final key = groupId.trim();
    if (key.isEmpty) {
      throw ArgumentError.value(groupId, 'groupId', 'must not be empty');
    }

    final queue = _queues.putIfAbsent(key, _GroupOperationQueue.new);
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

  /// Test-only observability for proving idle-key cleanup.
  int get debugActiveKeyCount => _queues.length;
}

final class _GroupOperationQueue {
  Future<void> tail = Future<void>.value();
  int pending = 0;
}
