import 'group_multi_party_device_real_harness.dart' as harness;

Future<void> main() {
  return harness.runGroupMultiPartyDeviceRealHarness(
    requireAndroidRuntimeConfig: true,
  );
}
