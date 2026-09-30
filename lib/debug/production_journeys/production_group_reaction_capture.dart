import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/conversation/domain/models/reaction_change.dart';

/// Bounded observation of one real group reaction operation and its receiver
/// stream. The caller first validates the target against production storage.
/// This observer cannot send a reaction or alter a repository/listener.
final class ProductionGroupReactionCapture {
  ProductionGroupReactionCapture({
    required String groupId,
    required String messageId,
    required String senderPeerId,
    required Stream<ReactionChange> changes,
  }) {
    String digest(String value) =>
        sha256.convert(utf8.encode(value)).toString();
    final groupDigest = digest(groupId);
    final messageDigest = digest(messageId);
    final senderDigest = digest(senderPeerId);
    _lease = installScopedE2EFlowEventSink((event) {
      if (_disposed || event['event'] != 'GROUP_REACTION_SEND_RESULT') return;
      final details = event['details'];
      if (details is! Map ||
          details['groupSha256'] != groupDigest ||
          details['messageSha256'] != messageDigest ||
          details['senderIdentitySha256'] != senderDigest) {
        return;
      }
      _record(_outcomes, {
        'outcome': details['outcome'],
        'reactionId': details['reactionId'],
      });
    });
    _subscription = changes.listen((change) {
      if (_disposed ||
          change.messageId != messageId ||
          change.senderPeerId != senderPeerId) {
        return;
      }
      _record(_changes, {
        'type': change.type.name,
        'messageId': change.messageId,
        'senderPeerId': change.senderPeerId,
        'reactionId': change.reaction?.id,
        'emoji': change.reaction?.emoji,
        'timestamp': change.reaction?.timestamp,
      });
    }, onError: (Object _, StackTrace _) => _streamFailed = true);
    _expiry = Timer(const Duration(minutes: 3), () {
      _expired = true;
      dispose();
    });
  }

  late final E2EFlowEventSinkLease _lease;
  late final StreamSubscription<ReactionChange> _subscription;
  late final Timer _expiry;
  final _outcomes = <Map<String, Object?>>[];
  final _changes = <Map<String, Object?>>[];
  var _disposed = false;
  var _expired = false;
  var _overflow = false;
  var _streamFailed = false;

  void _record(List<Map<String, Object?>> target, Map<String, Object?> value) {
    if (_disposed) return;
    final count = _outcomes.length + _changes.length;
    if (count >= 256) {
      _overflow = true;
      return;
    }
    target.add({...value, 'sequence': count + 1});
  }

  Map<String, Object?> snapshot() {
    if (_disposed || _expired || _overflow || _streamFailed) {
      throw StateError('reaction observation unavailable');
    }
    return {
      'outcomes': jsonDecode(jsonEncode(_outcomes)),
      'changes': jsonDecode(jsonEncode(_changes)),
    };
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _expiry.cancel();
    _lease.release();
    unawaited(_subscription.cancel());
  }
}
