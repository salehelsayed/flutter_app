import 'dart:async';

import 'package:flutter_app/features/groups/application/group_recovery_gate.dart';

/// Bounded fault setup for a missed-live-message fixture. Owning the existing
/// recovery gate prevents periodic rejoin/drain from erasing the live gap while
/// the production foreground-push handler remains callable. No service is
/// replaced; release restores queued recovery and ordinary periodic sweeps.
final class ProductionGroupRecoveryHold {
  ProductionGroupRecoveryHold({
    required this.gate,
    this.maximumDuration = const Duration(minutes: 3),
    this.acquisitionTimeout = const Duration(seconds: 15),
  });

  final GroupRecoveryGate gate;
  final Duration maximumDuration;
  final Duration acquisitionTimeout;
  Completer<void>? _release;
  Future<void>? _completion;
  Timer? _deadline;
  bool _held = false;
  bool _expired = false;

  bool get isHeld => _held && !_expired;

  Future<void> acquire() async {
    if (_release != null) throw StateError('recovery hold already used');
    final entered = Completer<void>();
    final release = _release = Completer<void>();
    _completion = gate.run(() async {
      if (release.isCompleted) return;
      _held = true;
      _deadline = Timer(maximumDuration, () {
        _expired = true;
        dispose();
      });
      entered.complete();
      try {
        await release.future;
      } finally {
        _held = false;
      }
    });
    try {
      await entered.future.timeout(acquisitionTimeout);
    } catch (_) {
      dispose();
      rethrow;
    }
  }

  void requireHeld() {
    if (!isHeld) throw StateError('fixture recovery hold absent or expired');
  }

  Future<void> release() async {
    requireHeld();
    dispose();
    await _completion;
  }

  void dispose() {
    _deadline?.cancel();
    _held = false;
    final release = _release;
    if (release != null && !release.isCompleted) release.complete();
  }
}
