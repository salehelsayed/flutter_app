import 'package:flutter_app/core/notifications/dropped_push_recovery_bridge.dart';

/// The exact Plan-375 Android consumer version this binary understands. It
/// must equal the native `DroppedPushRecoveryBridge.FIXED_WAKE_CONSUMER_VERSION`
/// source constant; any other value reads as not ready.
const int androidFixedWakeConsumerReadinessVersion = 1;

typedef ReadAndroidOpaqueWakeConsumer =
    Future<AndroidOpaqueWakeConsumerSnapshot?> Function();
typedef ReadCurrentSecureOpaqueBinding = Future<String?> Function();

/// The one live Android reader behind
/// `OpaqueWakePlatformConsumerReadiness.readAndroidConsumer`.
///
/// This is a resolver, not a constructor boolean: the paired capability
/// registration, the completed-outcome producer and the outcome drainer all
/// consult it at use time, so they enable and retire together on the same
/// binding/role epoch. Consumer-ready means Plan-374 recovery work is
/// committed enabled, the fixed branch/readiness version is exact, and the
/// native binding equals the current secure binding. Missing, stale, future,
/// cross-account or failed reads are false. No admission boolean is ever
/// persisted, and `Platform.isAndroid` alone can never qualify.
final class AndroidOpaqueWakeReadiness {
  const AndroidOpaqueWakeReadiness({
    required this.admissionEnabled,
    required this.readConsumerSnapshot,
    required this.readCurrentSecureBinding,
  });

  /// The one default-false build admission
  /// (`kWakeOutcomeCoordinatorAdmissionEnabled`), injected by composition.
  final bool admissionEnabled;
  final ReadAndroidOpaqueWakeConsumer readConsumerSnapshot;
  final ReadCurrentSecureOpaqueBinding readCurrentSecureBinding;

  Future<bool> isConsumerReady() async {
    if (!admissionEnabled) return false;
    try {
      final snapshot = await readConsumerSnapshot();
      if (snapshot == null) return false;
      final secureBinding = (await readCurrentSecureBinding())?.trim();
      final nativeBinding = snapshot.currentBinding?.trim();
      return secureBinding != null &&
          secureBinding.isNotEmpty &&
          nativeBinding == secureBinding &&
          snapshot.recoveryWorkEnabled &&
          !snapshot.authorityMutationInProgress &&
          snapshot.fixedWakeConsumerVersion ==
              androidFixedWakeConsumerReadinessVersion;
    } on Object {
      return false;
    }
  }
}
