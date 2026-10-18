import 'dart:io';

/// The installed Appium keyboard types text verbatim and shows no on-screen
/// keyboard. Device keyboards autocapitalize and autocorrect proof texts
/// (observed: `msg5` -> `Msg5`, `relay fallback` -> `relay Fallback`).
const productionVerbatimIme = 'io.appium.settings/.AppiumIME';

/// Runs [action] with the Android device switched to the verbatim keyboard
/// when it is installed, restoring the device's own keyboard afterwards even
/// on failure. [action] receives whether the verbatim keyboard is active (its
/// flow must then not use hideKeyboard). Each switch is recorded in
/// [switches] for the proof.
Future<T> withProductionVerbatimKeyboard<T>(
  Future<ProcessResult> Function(List<String> args) adb,
  String label,
  List<Map<String, Object?>> switches,
  Future<T> Function(bool verbatim) action, {
  Map<String, Object?> extra = const {},
}) async {
  final installed =
      '${(await adb(['shell', 'ime', 'list', '-a', '-s'])).stdout}'.contains(
        productionVerbatimIme,
      );
  if (!installed) {
    switches.add({...extra, 'label': label, 'restoreTo': null});
    return action(false);
  }
  final original =
      '${(await adb(['shell', 'settings', 'get', 'secure', 'default_input_method'])).stdout}'
          .trim();
  await adb(['shell', 'ime', 'enable', productionVerbatimIme]);
  await adb(['shell', 'ime', 'set', productionVerbatimIme]);
  switches.add({...extra, 'label': label, 'restoreTo': original});
  try {
    return await action(true);
  } finally {
    if (original.isNotEmpty && original != productionVerbatimIme) {
      await adb(['shell', 'ime', 'set', original]);
    }
  }
}
