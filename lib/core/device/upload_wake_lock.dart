import 'package:flutter/foundation.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

abstract class UploadWakeLockDriver {
  Future<void> enable();

  Future<void> disable();
}

class WakelockPlusUploadWakeLockDriver implements UploadWakeLockDriver {
  @override
  Future<void> enable() => WakelockPlus.enable();

  @override
  Future<void> disable() => WakelockPlus.disable();
}

class UploadWakeLockController {
  UploadWakeLockController._();

  static UploadWakeLockDriver _driver = WakelockPlusUploadWakeLockDriver();
  static int _activeHolds = 0;

  static Future<void> acquire() async {
    _activeHolds += 1;
    if (_activeHolds == 1) {
      await _driver.enable();
    }
  }

  static Future<void> release() async {
    if (_activeHolds == 0) return;
    _activeHolds -= 1;
    if (_activeHolds == 0) {
      await _driver.disable();
    }
  }

  @visibleForTesting
  static int get debugActiveHolds => _activeHolds;

  @visibleForTesting
  static void debugSetDriver(UploadWakeLockDriver driver) {
    _driver = driver;
  }

  @visibleForTesting
  static void debugReset({UploadWakeLockDriver? driver}) {
    _activeHolds = 0;
    if (driver != null) {
      _driver = driver;
    }
  }
}
