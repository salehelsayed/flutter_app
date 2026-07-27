import 'dart:io';

import '../scripts/group_multi_party_runtime_config.dart';

/// Applies the entrypoint-level runtime-config policy for the shared harness.
///
/// Generic Android launches opt into a required, atomically staged config.
/// Specialized Android launches use the legacy entrypoint and ignore any stale
/// strict config left in Documents. Non-Android launches preserve the existing
/// optional Documents-file behavior.
Future<Map<String, String>> loadGroupMultiPartyHarnessRuntimeConfigValues({
  required bool isAndroid,
  required bool requireAndroidRuntimeConfig,
  required Future<File> Function() resolveFinalConfigFile,
  Duration timeout = const Duration(minutes: 2),
}) async {
  if (isAndroid && !requireAndroidRuntimeConfig) {
    return const <String, String>{};
  }
  final finalConfigFile = await resolveFinalConfigFile();
  return loadGroupMultiPartyRuntimeConfigValues(
    finalConfigFile: finalConfigFile,
    requireConfig: isAndroid && requireAndroidRuntimeConfig,
    timeout: timeout,
  );
}
