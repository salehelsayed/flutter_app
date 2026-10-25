import 'package:flutter_app/core/utils/thought_lifetime.dart';

typedef _Retraction = ({String retractedBy, DateTime expiresAt});

/// Retractions that reached this phone before the thought they name.
///
/// A thought and its retraction can arrive in one inbox drain, and the
/// retraction's handler is the quicker of the two. Dropping it as unknown
/// would let the slower create store a thought its author already deleted,
/// for the full 24 h. So the retraction is remembered until the thought would
/// have expired anyway, and a create for it from the same author is rejected.
///
/// Memory is enough: both messages reach one `PostListener` in one process,
/// so the record outlives the race it guards. If the process dies between the
/// two, the create's ack was never released and the sender delivers it again,
/// alone; that one crash window is the accepted remainder.
final class EarlyThoughtRetractions {
  EarlyThoughtRetractions({
    DateTime Function()? nowProvider,
    this.capacity = 256,
  }) : _now = nowProvider ?? DateTime.now;

  final DateTime Function() _now;

  /// The oldest retraction leaves once this many are held.
  final int capacity;

  final _byPostId = <String, _Retraction>{};

  void record({
    required String postId,
    required String retractedBy,
    required DateTime postCreatedAt,
  }) {
    _prune();
    final expiresAt = ThoughtLifetime.expiresAt(postCreatedAt);
    if (!expiresAt.isAfter(_now().toUtc())) return;
    _byPostId.remove(postId);
    _byPostId[postId] = (retractedBy: retractedBy, expiresAt: expiresAt);
    while (_byPostId.length > capacity) {
      _byPostId.remove(_byPostId.keys.first);
    }
  }

  /// Whether [authorPeerId] already retracted the thought [postId].
  bool rejects({required String postId, required String authorPeerId}) {
    _prune();
    return _byPostId[postId]?.retractedBy == authorPeerId;
  }

  void _prune() {
    final now = _now().toUtc();
    _byPostId.removeWhere(
      (_, retraction) => !retraction.expiresAt.isAfter(now),
    );
  }
}
