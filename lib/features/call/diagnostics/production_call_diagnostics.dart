import 'dart:io';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/bridge/bridge.dart';
import 'call_diagnostics.dart';

/// Diagnostics startup is bounded and cannot prevent normal app startup.
Future<void> initializeProductionCallDiagnostics({
  required Bridge bridge,
  required Future<bool> Function() networkAllowed,
}) async {
  try {
    final root = await getApplicationSupportDirectory().timeout(
      const Duration(seconds: 1),
    );
    String build = 'unknown';
    try {
      final info = await PackageInfo.fromPlatform().timeout(
        const Duration(milliseconds: 300),
      );
      build = '${info.version}+${info.buildNumber}';
    } catch (_) {
      // A missing metadata plugin is unrelated to calling capability.
    }
    const sourceBuild = String.fromEnvironment('CALL_DIAGNOSTICS_BUILD');
    if (RegExp(r'^[0-9a-f]{8,40}$').hasMatch(sourceBuild)) {
      build = '$build-$sourceBuild';
    }
    await CallDiagnostics.instance
        .initialize(
          directory: Directory('${root.path}/call_diagnostics'),
          bridge: bridge,
          build: build,
          networkAllowed: networkAllowed,
        )
        .timeout(const Duration(seconds: 2));
  } catch (_) {
    // The dedicated status surface reports storage availability when initialized.
    // Never forward plugin errors or paths to general application logs.
  }
}
