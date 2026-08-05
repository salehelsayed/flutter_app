import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';

/// Total wall-clock budget for one ordinary outgoing live-delivery leg.
const Duration outgoingLiveBudget = Duration(seconds: 6);

/// Time that a deferred-commit send must leave for the receiver's ACK.
const Duration committedAckReserve = Duration(seconds: 3);

/// Maximum native rendezvous-discovery allocation within a live leg.
const Duration outgoingDiscoverPhaseCap = Duration(seconds: 2);

/// Maximum native explicit-dial allocation within a live leg.
const Duration outgoingDialPhaseCap = Duration(milliseconds: 1500);

/// Allocates native phase budgets from one monotonic outgoing-live T0.
///
/// The elapsed reader is deliberately the only time seam. Production callers
/// bind it to the `elapsed` value of their entry stopwatch; tests can supply a
/// mutable reader without adding a clock parameter to public send APIs.
final class OutgoingLiveDeadline {
  OutgoingLiveDeadline(Duration Function() elapsed) : _elapsed = elapsed;

  final Duration Function() _elapsed;

  /// Time remaining in the original six-second live leg, clamped at zero.
  Duration get remaining {
    final value = outgoingLiveBudget - _elapsed();
    return value.isNegative ? Duration.zero : value;
  }

  /// Returns a serialized native timeout for a capped discover/dial phase.
  ///
  /// The bridge watchdog margin is kept inside the original live leg. A value
  /// that floors below one millisecond is rejected so Go cannot reinterpret a
  /// forwarded zero as a request for its default timeout.
  int? allocatePhaseTimeoutMs(Duration phaseCap) {
    final available = remaining - p2pBridgeWatchdogMargin;
    if (available <= Duration.zero) {
      return null;
    }

    final allocation = available < phaseCap ? available : phaseCap;
    final serializedMs = allocation.inMilliseconds;
    return serializedMs >= 1 ? serializedMs : null;
  }

  /// Returns a serialized timeout only when a committed send retains its ACK
  /// reserve after the bridge-watchdog margin has been deducted.
  int? allocateCommittedSendTimeoutMs() {
    final available = remaining - p2pBridgeWatchdogMargin;
    if (available <= Duration.zero) {
      return null;
    }

    final serializedMs = available.inMilliseconds;
    return serializedMs > committedAckReserve.inMilliseconds
        ? serializedMs
        : null;
  }
}
