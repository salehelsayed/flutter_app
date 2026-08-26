import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'private iOS provider adapter passes its no-network black-box suite',
    () {
      final pythonCacheDirectory = Directory.systemTemp.createTempSync(
        'ios-notification-provider-python-cache-',
      );
      addTearDown(() {
        if (pythonCacheDirectory.existsSync()) {
          pythonCacheDirectory.deleteSync(recursive: true);
        }
      });
      final result = Process.runSync(
        'python3',
        const <String>[
          '-m',
          'unittest',
          'scripts.test.ios_notification_provider_adapter_test',
        ],
        environment: {'PYTHONPYCACHEPREFIX': pythonCacheDirectory.path},
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    },
  );

  test('adapter keeps secrets and development endpoint bound to handoff', () {
    final source = File(
      'integration_test/scripts/ios_notification_provider_adapter.py',
    ).readAsStringSync();
    expect(source, contains('https://api.sandbox.push.apple.com'));
    expect(source, contains('APNS_DELIVERY_WINDOW_SECONDS = 120'));
    expect(source, isNot(contains('apns-expiration: 0')));
    expect(source, contains('apns_host_for_manifest(staging)'));
    expect(
      source,
      contains('choices=("probe", "setup", "retry", "cleanup", "rollback")'),
    );
    expect(source, contains('[str(security), "cms", "-D", "-i"'));
    expect(source, contains('f"--extract-certificates={prefix}"'));
    expect(source, contains('signingCertificateSha256'));
    expect(source, contains('DeveloperCertificates'));
    expect(source, contains('len(token_bytes) != 32'));
    expect(source, contains('len(mlkem_public_bytes) != 1184'));
    expect(source, contains('embedded.mobileprovision'));
    expect(source, contains('relayFixtureDriverSha256'));
    expect(source, contains('payloadProducerSha256'));
    expect(source, contains('stagingManifestSha256'));
    expect(source, contains('cleanup-sender'));
    expect(source, isNot(contains('shell=True')));
    expect(source, isNot(contains('SIMS_IOS_APNS_DEVICE_TOKEN_PATH')));
    expect(source, contains('SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_PATH'));
    expect(source, contains('SIMS_IOS_NOTIFICATION_RECEIVER_HANDOFF_NONCE'));
    expect(source, contains('start_new_session=True'));
    expect(source, contains('apnsPayloadSha256'));
    expect(
      source,
      contains('mknoon.sims.ios-payload-fast-path-provider-receipt.v2'),
    );
    expect(
      source,
      contains('mknoon.sims.ios-payload-fast-path-provider-retry-receipt.v1'),
    );
    expect(source, contains('apns-collapse-id: '));
    expect(source, contains('apns-unique-id:'));
    expect(
      source,
      contains('mknoon.sims.ios-apns-unique-id-private-provenance.v1'),
    );
    expect(source, contains('_remove_apns_unique_id_provenance'));
    expect(source, contains('"providerMessageIdSha256": _sha256_text('));
    expect(source, contains('"gcm.message_id"'));
    expect(source, contains('"content-available"'));
    expect(source, contains('"payloadBytesIdentical": True'));
    expect(source, contains('"collapseIdentityReused": True'));
    expect(source, contains('"providerIdsDistinct":'));
    expect(source, contains('"firstProviderReceiptSha256": first_receipt_sha'));
    expect(source, contains('action="rollback"'));
    expect(source, contains('SIMS_CHILD_BUILDS_FORBIDDEN'));
    expect(source, contains('SIMS_MANUAL_ACTIONS_FORBIDDEN'));
  });
}
