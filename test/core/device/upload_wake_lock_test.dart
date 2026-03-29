import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/core/device/upload_wake_lock.dart';

import '../../shared/fakes/fake_upload_wake_lock_driver.dart';

void main() {
  late FakeUploadWakeLockDriver driver;

  setUp(() {
    driver = FakeUploadWakeLockDriver();
    UploadWakeLockController.debugReset(driver: driver);
  });

  tearDown(() {
    UploadWakeLockController.debugReset(driver: FakeUploadWakeLockDriver());
  });

  test('acquire and release keep the wake lock ref-counted', () async {
    await UploadWakeLockController.acquire();
    await UploadWakeLockController.acquire();

    expect(UploadWakeLockController.debugActiveHolds, 2);
    expect(driver.enableCalls, 1);
    expect(driver.disableCalls, 0);

    await UploadWakeLockController.release();

    expect(UploadWakeLockController.debugActiveHolds, 1);
    expect(driver.enableCalls, 1);
    expect(driver.disableCalls, 0);

    await UploadWakeLockController.release();

    expect(UploadWakeLockController.debugActiveHolds, 0);
    expect(driver.enableCalls, 1);
    expect(driver.disableCalls, 1);
  });

  test('release is a no-op when no uploads are active', () async {
    await UploadWakeLockController.release();

    expect(UploadWakeLockController.debugActiveHolds, 0);
    expect(driver.enableCalls, 0);
    expect(driver.disableCalls, 0);
  });
}
