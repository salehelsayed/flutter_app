import 'package:flutter_app/core/debug/e2e_test_mode.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('production push registration build gate', () {
    test('normal mobile build enables registration', () {
      expect(
        shouldEnableProductionPushRegistration(
          isDesktop: false,
          e2eTestMode: false,
          productionFcmTestMode: false,
        ),
        isTrue,
      );
    });

    test('ordinary E2E build suppresses registration', () {
      expect(
        shouldEnableProductionPushRegistration(
          isDesktop: false,
          e2eTestMode: true,
          productionFcmTestMode: false,
        ),
        isFalse,
      );
    });

    test('production FCM E2E profile enables registration', () {
      expect(
        shouldEnableProductionPushRegistration(
          isDesktop: false,
          e2eTestMode: true,
          productionFcmTestMode: true,
        ),
        isTrue,
      );
    });

    test('desktop never enables mobile push registration', () {
      expect(
        shouldEnableProductionPushRegistration(
          isDesktop: true,
          e2eTestMode: false,
          productionFcmTestMode: true,
        ),
        isFalse,
      );
    });
  });
}
