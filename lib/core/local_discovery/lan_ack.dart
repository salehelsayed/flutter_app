import 'dart:async';

import 'package:flutter_app/core/local_discovery/local_discovery_service.dart';

enum LanSendAck { committed, legacyAck, failed }

enum _LanInboundDecisionKind { committed, accepted, rejected }

class LanInboundDecision {
  final _LanInboundDecisionKind _kind;
  final String? reason;

  const LanInboundDecision._(this._kind, {this.reason});

  const LanInboundDecision.committed()
    : this._(_LanInboundDecisionKind.committed);

  const LanInboundDecision.accepted()
    : this._(_LanInboundDecisionKind.accepted);

  factory LanInboundDecision.rejected(String reason) {
    final safeReason = reason.trim().isEmpty ? 'rejected' : reason;
    return LanInboundDecision._(
      _LanInboundDecisionKind.rejected,
      reason: safeReason,
    );
  }

  bool get isCommitted => _kind == _LanInboundDecisionKind.committed;
  bool get isAccepted => _kind == _LanInboundDecisionKind.accepted;
  bool get isRejected => _kind == _LanInboundDecisionKind.rejected;
}

typedef LanInboundChatCommitHandler =
    FutureOr<LanInboundDecision> Function(
      LocalChatMessage message, {
      required String? nonce,
    });
