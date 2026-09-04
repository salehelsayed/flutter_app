import 'package:flutter/widgets.dart';
import 'package:flutter_app/app/bootstrap/application_bootstrap.dart';
import 'package:flutter_app/app/bootstrap/production_application_bootstrap.dart';
import 'package:flutter_app/app/bootstrap/production_headless_call_admission.dart';
import 'package:flutter_app/app/bootstrap/production_headless_canonical_recovery.dart';
import 'package:flutter_app/core/debug/android_canonical_runtime_h0_probe.dart';
import 'package:flutter_app/core/debug/android_headless_recovery_374_fixture.dart';
import 'package:flutter_app/core/notifications/headless_canonical_recovery_entrypoint.dart';
import 'package:flutter_app/debug/debug_e2e_composition_root.dart';

export 'package:flutter_app/app/application_root.dart'
    show MyApp, openIntroNotificationOrbitRoute;
export 'package:flutter_app/app/bootstrap/production_application_bootstrap.dart'
    show keychainMirrorBackfill;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await DebugE2ECompositionRoot.acknowledgeGroupReactionNotificationIosDartMainEntryIfConfigured();
  await runApplicationBootstrap(
    bootstrapFactory: ProductionApplicationBootstrap.new,
    host: const FlutterApplicationHost(),
  );
}

/// Debug receiver entrypoint. It creates no widget tree or application root.
@pragma('vm:entry-point')
Future<void> androidCanonicalRuntimeH0ProbeMain(List<String> arguments) =>
    runAndroidCanonicalRuntimeH0Probe(arguments);

/// Debug-only Plan-374 seed/inspection entrypoint. WorkManager still enters
/// [androidHeadlessCanonicalRecoveryMain] for the measured recovery run.
@pragma('vm:entry-point')
Future<void> androidHeadlessRecovery374FixtureMain(List<String> arguments) =>
    runAndroidHeadlessRecovery374Fixture(arguments);

/// Dedicated production headless recovery entrypoint. The invoked graph owns
/// no widget tree, Activity, foreground bootstrap, or Firebase listener.
@pragma('vm:entry-point')
Future<void> androidHeadlessCanonicalRecoveryMain(List<String> arguments) =>
    runAndroidHeadlessCanonicalRecovery(
      arguments,
      runRecovery: runProductionHeadlessCanonicalRecovery,
      emergencyShutdown: cleanupProductionHeadlessCanonicalRecovery,
    );

/// Dedicated admission-only Android call wake entrypoint. It authenticates
/// one exact mailbox handle and tears down SQLCipher/Go ownership before
/// native code may ask Telecom to present the call.
@pragma('vm:entry-point')
Future<void> androidHeadlessCallAdmissionMain(List<String> arguments) =>
    runProductionAndroidHeadlessCallAdmission(arguments);
