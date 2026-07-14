import 'dart:async';
import 'dart:collection';

/// 235: one app-isolate async mutex per attachment ID.
///
/// Serializes the operations that touch one attachment's row + secure key +
/// canonical file across features: the guarded incoming group save, the
/// download commit, and the deletion-journal cleanup saga. The database CAS /
/// journal anti-join stays the correctness authority; this lock orders the
/// surrounding FILE and SECURE-KEY I/O so a cleanup can never interleave with
/// a promotion or key write on the same attachment.
///
/// Same-ID acquisition is reentrant in the current async [Zone], which lets a
/// lifecycle saga call a repository method that defensively acquires the lock
/// again. The zone lease is revoked when its critical section returns, so a
/// delayed callback cannot reuse stale authority. Callers must await work they
/// start inside a critical section rather than intentionally detaching it.
class MediaAttachmentLifecycleLock {
  final Map<String, Future<void>> _tails = <String, Future<void>>{};
  final Object _zoneKey = Object();
  final Queue<_MediaAttachmentBarrierWaiter> _waiting =
      Queue<_MediaAttachmentBarrierWaiter>();
  var _activeShared = 0;
  var _exclusiveActive = false;

  _MediaAttachmentLockContext get _context {
    final inherited = Zone.current[_zoneKey] as _MediaAttachmentLockContext?;
    return inherited != null && inherited.isActive
        ? inherited
        : const _MediaAttachmentLockContext();
  }

  Future<T> synchronized<T>(
    String attachmentId,
    Future<T> Function() action,
  ) async {
    if (attachmentId.isEmpty) {
      throw ArgumentError.value(
        attachmentId,
        'attachmentId',
        'must not be empty',
      );
    }
    final inherited = _context;
    if (inherited.exclusive || inherited.attachmentIds.contains(attachmentId)) {
      return action();
    }
    if (inherited.attachmentIds.isNotEmpty &&
        attachmentId.compareTo(inherited.attachmentIds.last) < 0) {
      throw StateError(
        'attachment lifecycle locks must be acquired in ascending ID order: '
        '${inherited.attachmentIds.last} before $attachmentId would invert it',
      );
    }

    final ownsShared = inherited.attachmentIds.isEmpty;
    if (ownsShared) await _acquireShared();
    final previous = _tails[attachmentId] ?? Future<void>.value();
    final gate = Completer<void>();
    _tails[attachmentId] = gate.future;
    // A failed predecessor must not poison the queue.
    await previous.catchError((_) {});
    final lease = _MediaAttachmentLockLease();
    try {
      final attachmentIds = List<String>.of(inherited.attachmentIds)
        ..add(attachmentId);
      return await runZoned(
        action,
        zoneValues: {
          _zoneKey: _MediaAttachmentLockContext(
            attachmentIds: attachmentIds,
            lease: lease,
          ),
        },
      );
    } finally {
      lease.isActive = false;
      gate.complete();
      if (identical(_tails[attachmentId], gate.future)) {
        _tails.remove(attachmentId);
      }
      if (ownsShared) _releaseShared();
    }
  }

  /// Runs a mutation that cannot identify every affected attachment before
  /// its database write (for example contact-wide deletion).
  ///
  /// Exclusive work waits for every active per-attachment lifecycle section
  /// and prevents later sections from starting until it finishes. Upgrading an
  /// already-held attachment lock is rejected instead of deadlocking; callers
  /// with known IDs must acquire those IDs in ascending order instead.
  Future<T> synchronizedAll<T>(Future<T> Function() action) async {
    final inherited = _context;
    if (inherited.exclusive) return action();
    if (inherited.attachmentIds.isNotEmpty) {
      throw StateError(
        'cannot upgrade an attachment lifecycle lock to exclusive authority',
      );
    }
    await _acquireExclusive();
    final lease = _MediaAttachmentLockLease();
    try {
      return await runZoned(
        action,
        zoneValues: {
          _zoneKey: _MediaAttachmentLockContext(exclusive: true, lease: lease),
        },
      );
    } finally {
      lease.isActive = false;
      _releaseExclusive();
    }
  }

  Future<void> _acquireShared() {
    final waiter = Completer<void>();
    _waiting.add(
      _MediaAttachmentBarrierWaiter(
        kind: _MediaAttachmentBarrierKind.shared,
        completer: waiter,
      ),
    );
    _drainBarrierQueue();
    return waiter.future;
  }

  void _releaseShared() {
    _activeShared--;
    if (_activeShared < 0) {
      throw StateError('attachment lifecycle shared-lock underflow');
    }
    _drainBarrierQueue();
  }

  Future<void> _acquireExclusive() {
    final waiter = Completer<void>();
    _waiting.add(
      _MediaAttachmentBarrierWaiter(
        kind: _MediaAttachmentBarrierKind.exclusive,
        completer: waiter,
      ),
    );
    _drainBarrierQueue();
    return waiter.future;
  }

  void _releaseExclusive() {
    if (!_exclusiveActive) {
      throw StateError('attachment lifecycle exclusive-lock underflow');
    }
    _exclusiveActive = false;
    _drainBarrierQueue();
  }

  void _drainBarrierQueue() {
    if (_exclusiveActive || _waiting.isEmpty) return;

    // Active shared work may admit only shared requests that were already at
    // the head. Once an exclusive request is queued, every later request stays
    // behind it, preventing reader or writer starvation in either direction.
    if (_activeShared > 0) {
      while (_waiting.isNotEmpty &&
          _waiting.first.kind == _MediaAttachmentBarrierKind.shared) {
        _activeShared++;
        _waiting.removeFirst().completer.complete();
      }
      return;
    }

    if (_waiting.first.kind == _MediaAttachmentBarrierKind.exclusive) {
      _exclusiveActive = true;
      _waiting.removeFirst().completer.complete();
      return;
    }

    // A consecutive reader cohort ahead of the next writer starts together.
    while (_waiting.isNotEmpty &&
        _waiting.first.kind == _MediaAttachmentBarrierKind.shared) {
      _activeShared++;
      _waiting.removeFirst().completer.complete();
    }
  }
}

enum _MediaAttachmentBarrierKind { shared, exclusive }

class _MediaAttachmentBarrierWaiter {
  const _MediaAttachmentBarrierWaiter({
    required this.kind,
    required this.completer,
  });

  final _MediaAttachmentBarrierKind kind;
  final Completer<void> completer;
}

class _MediaAttachmentLockContext {
  const _MediaAttachmentLockContext({
    this.attachmentIds = const <String>[],
    this.exclusive = false,
    this.lease,
  });

  final List<String> attachmentIds;
  final bool exclusive;
  final _MediaAttachmentLockLease? lease;

  bool get isActive => lease?.isActive ?? false;
}

class _MediaAttachmentLockLease {
  var isActive = true;
}

/// App-isolate instance shared by save/download/cleanup (mirrors
/// [mediaUploadInFlightTracker]'s house style).
final MediaAttachmentLifecycleLock mediaAttachmentLifecycleLock =
    MediaAttachmentLifecycleLock();
