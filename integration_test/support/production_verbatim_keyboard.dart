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

/// Keeps one device on the verbatim keyboard across consecutive sends.
///
/// Restoring the device keyboard right after a send, while the composer keeps
/// focus, opens it; a following navigation back then only closes it. A
/// session therefore restores only on [restore]: before a flow that uses the
/// device keyboard (and its hideKeyboard), and when the journey ends.
final class ProductionVerbatimKeyboardSession {
  ProductionVerbatimKeyboardSession(this._adb, this._switches);

  final Future<ProcessResult> Function(List<String> args) _adb;
  final List<Map<String, Object?>> _switches;
  bool? _installed;
  String? _restoreTo;

  Future<T> run<T>(
    String label,
    Future<T> Function(bool verbatim) action, {
    Map<String, Object?> extra = const {},
  }) async {
    _installed ??=
        '${(await _adb(['shell', 'ime', 'list', '-a', '-s'])).stdout}'.contains(
          productionVerbatimIme,
        );
    if (!_installed!) {
      _switches.add({...extra, 'label': label, 'restoreTo': null});
      return action(false);
    }
    if (_restoreTo == null) {
      _restoreTo =
          '${(await _adb(['shell', 'settings', 'get', 'secure', 'default_input_method'])).stdout}'
              .trim();
      await _adb(['shell', 'ime', 'enable', productionVerbatimIme]);
      await _adb(['shell', 'ime', 'set', productionVerbatimIme]);
    }
    _switches.add({...extra, 'label': label, 'restoreTo': _restoreTo});
    return action(true);
  }

  Future<void> restore() async {
    final original = _restoreTo;
    _restoreTo = null;
    if (original != null &&
        original.isNotEmpty &&
        original != productionVerbatimIme) {
      await _adb(['shell', 'ime', 'set', original]);
    }
  }
}
