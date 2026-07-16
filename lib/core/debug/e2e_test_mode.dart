const bool kE2ETestMode = bool.fromEnvironment('E2E_TEST_MODE');

/// Keeps the runtime E2E control channel enabled while exercising the real
/// Firebase/relay registration boundary.
///
/// Ordinary E2E builds deliberately suppress push registration so host and
/// simulator tests do not request provider credentials.  The sims
/// `android.production_fcm` profile opts back into that one production
/// boundary with `PRODUCTION_FCM=true`; the device orchestrator still owns the
/// notification permission and target selection.
const bool kProductionFcmTestMode = bool.fromEnvironment('PRODUCTION_FCM');

bool shouldEnableProductionPushRegistration({
  required bool isDesktop,
  bool e2eTestMode = kE2ETestMode,
  bool productionFcmTestMode = kProductionFcmTestMode,
}) => !isDesktop && (!e2eTestMode || productionFcmTestMode);
const bool kDisableLocalDiscovery = bool.fromEnvironment(
  'DISABLE_LOCAL_DISCOVERY',
);
