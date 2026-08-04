import 'package:flutter_app/app/bootstrap/application_bootstrap.dart';
import 'package:flutter_app/app/bootstrap/production_application_bootstrap.dart';
import 'package:flutter_app/core/debug/android_canonical_runtime_h0_probe.dart';
import 'package:flutter_app/core/notifications/headless_canonical_recovery_entrypoint.dart';

export 'package:flutter_app/app/application_root.dart'
    show MyApp, openIntroNotificationOrbitRoute;
export 'package:flutter_app/app/bootstrap/production_application_bootstrap.dart'
    show keychainMirrorBackfill;

void main() async {
  await runApplicationBootstrap(
    bootstrapFactory: ProductionApplicationBootstrap.new,
    host: const FlutterApplicationHost(),
  );
}

/// Debug receiver entrypoint. It creates no widget tree or application root.
@pragma('vm:entry-point')
Future<void> androidCanonicalRuntimeH0ProbeMain(List<String> arguments) =>
    runAndroidCanonicalRuntimeH0Probe(arguments);

/// Dormant and fail-closed until the non-UI production recovery composition is
/// extracted and passes its real SQLCipher/device gates. Production binding
/// publication keeps recovery work disabled.
@pragma('vm:entry-point')
Future<void> androidHeadlessCanonicalRecoveryMain(List<String> arguments) =>
    runAndroidHeadlessCanonicalRecovery(
      arguments,
      runRecovery: runUnavailableHeadlessCanonicalRecovery,
      emergencyShutdown: cleanupUnavailableHeadlessCanonicalRecovery,
    );
