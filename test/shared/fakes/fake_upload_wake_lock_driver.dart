import 'package:flutter_app/core/device/upload_wake_lock.dart';

class FakeUploadWakeLockDriver implements UploadWakeLockDriver {
  int enableCalls = 0;
  int disableCalls = 0;

  @override
  Future<void> enable() async {
    enableCalls += 1;
  }

  @override
  Future<void> disable() async {
    disableCalls += 1;
  }
}
