import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/sims/device_binding.dart';
import '../../../tool/sims/live_device_resolver.dart';
import '../../../tool/sims/manifest.dart';
import '../../../tool/sims/planner.dart';
import '../../../tool/sims/verdict.dart';

void main() {
  test(
    'inventory digest ignores discovery detail but retains source status',
    () {
      final targets = <SimsLiveDeviceTarget>[
        SimsLiveDeviceTarget(
          name: 'Pixel USB',
          platform: SimsLiveDevicePlatform.android,
          kind: SimsLiveDeviceKind.physical,
          availability: SimsLiveDeviceAvailability.connected,
          runtimeId: 'pixel-usb',
          launchId: null,
          sources: const <SimsDeviceDiscoverySource>{
            SimsDeviceDiscoverySource.flutterDevices,
            SimsDeviceDiscoverySource.adb,
          },
        ),
      ];
      final first = _inventory(targets, detail: '10 row(s) discovered');
      final changedDetail = _inventory(targets, detail: '11 row(s) discovered');
      final changedStatus = _inventory(
        targets,
        detail: '11 row(s) discovered',
        flutterStatus: SimsDiscoveryStatus.failed,
      );
      final changedTarget = _inventory(<SimsLiveDeviceTarget>[
        SimsLiveDeviceTarget(
          name: 'Pixel USB renamed',
          platform: SimsLiveDevicePlatform.android,
          kind: SimsLiveDeviceKind.physical,
          availability: SimsLiveDeviceAvailability.connected,
          runtimeId: 'pixel-usb',
          launchId: null,
          sources: const <SimsDeviceDiscoverySource>{
            SimsDeviceDiscoverySource.flutterDevices,
            SimsDeviceDiscoverySource.adb,
          },
        ),
      ]);
      final firstBinding = SimsDevicePlanBinding.bind(
        _plan(<CapabilitySpec>[_consumer()]),
        first,
      );
      final changedDetailBinding = SimsDevicePlanBinding.bind(
        _plan(<CapabilitySpec>[_consumer()]),
        changedDetail,
      );

      expect(
        simsLiveDeviceInventoryDigest(changedDetail),
        simsLiveDeviceInventoryDigest(first),
      );
      expect(changedDetailBinding.assignments, firstBinding.assignments);
      expect(
        changedDetailBinding.targetStateDigests,
        firstBinding.targetStateDigests,
      );
      expect(
        simsLiveDeviceInventoryDigest(changedStatus),
        isNot(simsLiveDeviceInventoryDigest(first)),
      );
      expect(
        simsLiveDeviceInventoryDigest(changedTarget),
        isNot(simsLiveDeviceInventoryDigest(first)),
      );
    },
  );

  test('symbolic locks bind to explicit IDs and child environment', () {
    final binding = SimsDevicePlanBinding.bind(
      _plan(<CapabilitySpec>[_consumer()]),
      _inventory(<SimsLiveDeviceTarget>[
        SimsLiveDeviceTarget(
          name: 'Pixel USB',
          platform: SimsLiveDevicePlatform.android,
          kind: SimsLiveDeviceKind.physical,
          availability: SimsLiveDeviceAvailability.connected,
          runtimeId: 'pixel-usb',
          launchId: null,
          sources: const <SimsDeviceDiscoverySource>{
            SimsDeviceDiscoverySource.flutterDevices,
            SimsDeviceDiscoverySource.adb,
          },
        ),
      ]),
    );

    expect(binding.plan.rows.single.resources[1].name, 'device:pixel-usb');
    expect(binding.environment['ANDROID_SERIAL'], 'pixel-usb');
    expect(binding.assignments['device:android-physical'], 'pixel-usb');
    expect(
      binding.targetStateDigests['pixel-usb'],
      matches(RegExp(r'^[0-9a-f]{64}$')),
    );
    expect(binding.preflightVerdicts, isEmpty);

    final changedDiscoveryState = SimsDevicePlanBinding.bind(
      _plan(<CapabilitySpec>[_consumer()]),
      _inventory(<SimsLiveDeviceTarget>[
        SimsLiveDeviceTarget(
          name: 'Pixel USB renamed by discovery',
          platform: SimsLiveDevicePlatform.android,
          kind: SimsLiveDeviceKind.physical,
          availability: SimsLiveDeviceAvailability.connected,
          runtimeId: 'pixel-usb',
          launchId: null,
          sources: const <SimsDeviceDiscoverySource>{
            SimsDeviceDiscoverySource.flutterDevices,
            SimsDeviceDiscoverySource.adb,
          },
        ),
      ]),
    );
    expect(
      changedDiscoveryState.targetStateDigests['pixel-usb'],
      isNot(binding.targetStateDigests['pixel-usb']),
      reason: 'target state must not be derived from the device ID alone',
    );
  });

  test('different device rows keep assignment JSON row scoped', () {
    final binding = SimsDevicePlanBinding.bind(
      _plan(<CapabilitySpec>[_nativeIosConsumer(), _consumer()]),
      _inventory(<SimsLiveDeviceTarget>[
        _fourSimulators().first,
        SimsLiveDeviceTarget(
          name: 'Pixel USB',
          platform: SimsLiveDevicePlatform.android,
          kind: SimsLiveDeviceKind.physical,
          availability: SimsLiveDeviceAvailability.connected,
          runtimeId: 'pixel-usb',
          launchId: null,
          sources: const <SimsDeviceDiscoverySource>{
            SimsDeviceDiscoverySource.flutterDevices,
            SimsDeviceDiscoverySource.adb,
          },
        ),
      ]),
    );

    expect(binding.preflightVerdicts, isEmpty);
    expect(
      jsonDecode(
        binding.environmentByCapabilityId[_nativeIosConsumer()
            .id]!['SIMS_DEVICE_ASSIGNMENTS_JSON']!,
      ),
      <String, Object?>{
        'device:ios-simulator-a': '11111111-1111-1111-1111-111111111111',
      },
    );
    expect(
      jsonDecode(
        binding.environmentByCapabilityId[_consumer()
            .id]!['SIMS_DEVICE_ASSIGNMENTS_JSON']!,
      ),
      <String, Object?>{'device:android-physical': 'pixel-usb'},
    );
    expect(
      jsonDecode(binding.environment['SIMS_DEVICE_ASSIGNMENTS_JSON']!),
      <String, Object?>{
        'device:android-physical': 'pixel-usb',
        'device:ios-simulator-a': '11111111-1111-1111-1111-111111111111',
      },
    );
  });

  test('target absence N/A also omits a build with no runnable consumer', () {
    final build = _buildRow();
    final consumer = _consumer(dependencies: <String>[build.id]);
    final binding = SimsDevicePlanBinding.bind(
      _plan(<CapabilitySpec>[build, consumer]),
      _inventory(const <SimsLiveDeviceTarget>[]),
    );

    expect(
      binding.preflightVerdicts[consumer.id]?.status,
      SimsVerdictStatus.notApplicable,
    );
    expect(
      binding.preflightVerdicts[build.id]?.status,
      SimsVerdictStatus.notApplicable,
    );
    expect(binding.skippedBuildProfiles, <String>{'android.e2e.standard'});
  });

  test('missing automation blocks and skips a build before device work', () {
    final build = _buildRow();
    final consumer = _consumer(
      dependencies: <String>[build.id],
      automationReady: false,
    );
    final binding = SimsDevicePlanBinding.bind(
      _plan(<CapabilitySpec>[build, consumer]),
      _inventory(<SimsLiveDeviceTarget>[
        SimsLiveDeviceTarget(
          name: 'Pixel USB',
          platform: SimsLiveDevicePlatform.android,
          kind: SimsLiveDeviceKind.physical,
          availability: SimsLiveDeviceAvailability.connected,
          runtimeId: 'pixel-usb',
          launchId: null,
          sources: const <SimsDeviceDiscoverySource>{
            SimsDeviceDiscoverySource.flutterDevices,
            SimsDeviceDiscoverySource.adb,
          },
        ),
      ]),
    );

    expect(
      binding.preflightVerdicts[consumer.id]?.blocker,
      SimsBlockerKind.missingDriver,
    );
    expect(
      binding.preflightVerdicts[build.id]?.status,
      SimsVerdictStatus.blocked,
    );
    expect(binding.plan.rows.last.dependencies, isEmpty);
    expect(binding.skippedBuildProfiles, <String>{'android.e2e.standard'});
  });

  test(
    'missing staging relay blocks and avoids its otherwise usable build',
    () {
      final build = _buildRow();
      final consumer = _consumer(
        dependencies: <String>[build.id],
        targetCapabilities: const <String>['android.physical', 'relay.staging'],
      );
      final binding = SimsDevicePlanBinding.bind(
        _plan(<CapabilitySpec>[build, consumer]),
        _inventory(<SimsLiveDeviceTarget>[
          SimsLiveDeviceTarget(
            name: 'Pixel USB',
            platform: SimsLiveDevicePlatform.android,
            kind: SimsLiveDeviceKind.physical,
            availability: SimsLiveDeviceAvailability.connected,
            runtimeId: 'pixel-usb',
            launchId: null,
            sources: const <SimsDeviceDiscoverySource>{
              SimsDeviceDiscoverySource.flutterDevices,
              SimsDeviceDiscoverySource.adb,
            },
          ),
        ]),
      );

      expect(
        binding.preflightVerdicts[consumer.id]?.blocker,
        SimsBlockerKind.environment,
      );
      expect(
        binding.preflightVerdicts[build.id]?.blocker,
        SimsBlockerKind.environment,
      );
      expect(
        binding.preflightVerdicts[build.id]?.detail,
        contains('no selected consumer is runnable'),
      );
      expect(binding.skippedBuildProfiles, <String>{'android.e2e.standard'});
    },
  );

  test('missing FCM credentials block before preparing its APK', () {
    final build = _buildRow();
    final consumer = _consumer(
      dependencies: <String>[build.id],
      targetCapabilities: const <String>['android.physical', 'credentials.fcm'],
    );
    final binding = SimsDevicePlanBinding.bind(
      _plan(<CapabilitySpec>[build, consumer]),
      _inventory(<SimsLiveDeviceTarget>[
        SimsLiveDeviceTarget(
          name: 'Pixel USB',
          platform: SimsLiveDevicePlatform.android,
          kind: SimsLiveDeviceKind.physical,
          availability: SimsLiveDeviceAvailability.connected,
          runtimeId: 'pixel-usb',
          launchId: null,
          sources: const <SimsDeviceDiscoverySource>{
            SimsDeviceDiscoverySource.flutterDevices,
            SimsDeviceDiscoverySource.adb,
          },
        ),
      ]),
    );

    expect(
      binding.preflightVerdicts[consumer.id]?.blocker,
      SimsBlockerKind.credentials,
    );
    expect(binding.skippedBuildProfiles, <String>{'android.e2e.standard'});
  });

  test('absent Android target is N/A before missing FCM credentials', () {
    final build = _buildRow();
    final consumer = _consumer(
      dependencies: <String>[build.id],
      targetCapabilities: const <String>['android.physical', 'credentials.fcm'],
    );
    final binding = SimsDevicePlanBinding.bind(
      _plan(<CapabilitySpec>[build, consumer]),
      _inventory(const <SimsLiveDeviceTarget>[]),
    );

    expect(
      binding.preflightVerdicts[consumer.id]?.status,
      SimsVerdictStatus.notApplicable,
    );
    expect(
      binding.preflightVerdicts[consumer.id]?.blocker,
      SimsBlockerKind.targetUnavailable,
    );
    expect(
      binding.preflightVerdicts[build.id]?.status,
      SimsVerdictStatus.notApplicable,
    );
  });

  test('valid FCM credential allows device binding to continue', () {
    final credential = File(
      '${Directory.systemTemp.path}/sims-binding-fcm-${DateTime.now().microsecondsSinceEpoch}.json',
    )..writeAsStringSync(jsonEncode(<String, Object?>{'project_id': 'fixture'}));
    addTearDown(() {
      if (credential.existsSync()) credential.deleteSync();
    });
    final consumer = _consumer(
      targetCapabilities: const <String>['android.physical', 'credentials.fcm'],
    );
    final binding = SimsDevicePlanBinding.bind(
      _plan(<CapabilitySpec>[consumer]),
      _inventory(<SimsLiveDeviceTarget>[
        SimsLiveDeviceTarget(
          name: 'Pixel USB',
          platform: SimsLiveDevicePlatform.android,
          kind: SimsLiveDeviceKind.physical,
          availability: SimsLiveDeviceAvailability.connected,
          runtimeId: 'pixel-usb',
          launchId: null,
          sources: const <SimsDeviceDiscoverySource>{
            SimsDeviceDiscoverySource.flutterDevices,
            SimsDeviceDiscoverySource.adb,
          },
        ),
      ]),
      processEnvironment: <String, String>{
        'FIREBASE_SERVICE_ACCOUNT': credential.path,
      },
    );

    expect(binding.preflightVerdicts, isEmpty);
    expect(binding.assignments['device:android-physical'], 'pixel-usb');
  });

  test(
    'missing APNs/provider/signing inputs skip iOS build as credentials',
    () {
      final build = _iosBuildRow();
      final consumer = _iosConsumer(dependencies: <String>[build.id]);
      final binding = SimsDevicePlanBinding.bind(
        _plan(<CapabilitySpec>[build, consumer]),
        _inventory(<SimsLiveDeviceTarget>[_iphone()]),
      );

      expect(
        binding.preflightVerdicts[consumer.id]?.blocker,
        SimsBlockerKind.credentials,
      );
      expect(
        binding.preflightVerdicts[consumer.id]?.detail,
        allOf(
          contains('SIMS_IOS_NOTIFICATION_STAGING_MANIFEST'),
          contains('SIMS_IOS_NOTIFICATION_PROVIDER_DRIVER'),
          contains('SIMS_NOTIFICATION_RELAY_TARGET'),
        ),
      );
      expect(
        binding.preflightVerdicts[build.id]?.blocker,
        SimsBlockerKind.credentials,
      );
      expect(
        binding.preflightVerdicts[build.id]?.detail,
        allOf(
          contains('no selected consumer is runnable'),
          contains('SIMS_IOS_NOTIFICATION_STAGING_MANIFEST'),
        ),
      );
      expect(binding.skippedBuildProfiles, <String>{'ios.device.production'});
    },
  );

  test(
    'actual iOS provider/relay env allows binding without generic relay env',
    () {
      final fixture = _IosPreflightFixture.create();
      addTearDown(fixture.dispose);
      final build = _iosBuildRow();
      final consumer = _iosConsumer(dependencies: <String>[build.id]);
      final binding = SimsDevicePlanBinding.bind(
        _plan(<CapabilitySpec>[build, consumer]),
        _inventory(<SimsLiveDeviceTarget>[_iphone()]),
        processEnvironment: fixture.environment,
      );

      expect(
        fixture.environment.containsKey('MKNOON_RELAY_ADDRESSES'),
        isFalse,
      );
      expect(binding.preflightVerdicts, isEmpty);
      expect(binding.skippedBuildProfiles, isEmpty);
      expect(
        binding.assignments['device:ios-physical'],
        '00008150-001C3C6A3684401C',
      );
    },
  );

  test('iOS provider title cannot exceed the contact username bound', () {
    final fixture = _IosPreflightFixture.create();
    addTearDown(fixture.dispose);
    final request = File(
      fixture.environment['SIMS_IOS_NOTIFICATION_PROVIDER_REQUEST']!,
    );
    final decoded =
        jsonDecode(request.readAsStringSync()) as Map<String, dynamic>
          ..['expectedTitle'] = 'a' * 31;
    request.writeAsStringSync(jsonEncode(decoded));

    final binding = SimsDevicePlanBinding.bind(
      _plan(<CapabilitySpec>[_iosConsumer()]),
      _inventory(<SimsLiveDeviceTarget>[_iphone()]),
      processEnvironment: fixture.environment,
    );

    expect(
      binding.preflightVerdicts['notifications.ios_payload_fast_path']?.blocker,
      SimsBlockerKind.credentials,
    );
  });

  test('iOS provider alert cannot expose the decrypted message fixture', () {
    final fixture = _IosPreflightFixture.create();
    addTearDown(fixture.dispose);
    final request = File(
      fixture.environment['SIMS_IOS_NOTIFICATION_PROVIDER_REQUEST']!,
    );
    final decoded =
        jsonDecode(request.readAsStringSync()) as Map<String, dynamic>
          ..['expectedBody'] = 'fallback includes message plaintext';
    request.writeAsStringSync(jsonEncode(decoded));

    final binding = SimsDevicePlanBinding.bind(
      _plan(<CapabilitySpec>[_iosConsumer()]),
      _inventory(<SimsLiveDeviceTarget>[_iphone()]),
      processEnvironment: fixture.environment,
    );

    expect(
      binding.preflightVerdicts['notifications.ios_payload_fast_path']?.blocker,
      SimsBlockerKind.credentials,
    );
  });

  test('iOS payload producer must match the probed fingerprint', () {
    final fixture = _IosPreflightFixture.create();
    addTearDown(fixture.dispose);
    File(
      fixture.environment['SIMS_IOS_NOTIFICATION_PAYLOAD_PRODUCER']!,
    ).writeAsStringSync('# changed after probe\n', mode: FileMode.append);

    final binding = SimsDevicePlanBinding.bind(
      _plan(<CapabilitySpec>[_iosConsumer()]),
      _inventory(<SimsLiveDeviceTarget>[_iphone()]),
      processEnvironment: fixture.environment,
    );

    expect(
      binding.preflightVerdicts['notifications.ios_payload_fast_path']?.blocker,
      SimsBlockerKind.missingDriver,
    );
  });

  test('staging receiver ID overrides the first sorted physical iPhone', () {
    final fixture = _IosPreflightFixture.create();
    addTearDown(fixture.dispose);
    final binding = SimsDevicePlanBinding.bind(
      _plan(<CapabilitySpec>[_iosConsumer()]),
      _inventory(<SimsLiveDeviceTarget>[
        _iphoneWithId('00008030-001A6D2801BB802E'),
        _iphone(),
      ]),
      processEnvironment: fixture.environment,
    );

    expect(binding.preflightVerdicts, isEmpty);
    expect(
      binding.assignments['device:ios-physical'],
      '00008150-001C3C6A3684401C',
    );
    expect(
      binding.environment['SIMS_IOS_PHYSICAL_DEVICE_ID'],
      '00008150-001C3C6A3684401C',
    );
  });

  test('unavailable staging receiver is N/A before provider configuration', () {
    final fixture = _IosPreflightFixture.create();
    addTearDown(fixture.dispose);
    final build = _iosBuildRow();
    final consumer = _iosConsumer(dependencies: <String>[build.id]);
    final binding = SimsDevicePlanBinding.bind(
      _plan(<CapabilitySpec>[build, consumer]),
      _inventory(<SimsLiveDeviceTarget>[
        _iphoneWithId('00008030-001A6D2801BB802E'),
      ]),
      processEnvironment: <String, String>{
        'SIMS_IOS_NOTIFICATION_STAGING_MANIFEST':
            fixture.environment['SIMS_IOS_NOTIFICATION_STAGING_MANIFEST']!,
      },
    );

    expect(
      binding.preflightVerdicts[consumer.id]?.status,
      SimsVerdictStatus.notApplicable,
    );
    expect(
      binding.preflightVerdicts[consumer.id]?.blocker,
      SimsBlockerKind.targetUnavailable,
    );
    expect(
      binding.preflightVerdicts[build.id]?.status,
      SimsVerdictStatus.notApplicable,
    );
    expect(binding.assignments, isEmpty);
  });

  test('failed signing probe prevents central physical iOS compile', () {
    final fixture = _IosPreflightFixture.create(signingReady: false);
    addTearDown(fixture.dispose);
    final build = _iosBuildRow();
    final consumer = _iosConsumer(dependencies: <String>[build.id]);
    final binding = SimsDevicePlanBinding.bind(
      _plan(<CapabilitySpec>[build, consumer]),
      _inventory(<SimsLiveDeviceTarget>[_iphone()]),
      processEnvironment: fixture.environment,
    );

    expect(
      binding.preflightVerdicts[consumer.id]?.blocker,
      SimsBlockerKind.credentials,
    );
    expect(
      binding.preflightVerdicts[build.id]?.blocker,
      SimsBlockerKind.credentials,
    );
    expect(binding.skippedBuildProfiles, <String>{'ios.device.production'});
  });

  test(
    'production APNs attestations cannot select the development-signed build',
    () {
      for (final field in const <String>[
        'apnsEnvironment',
        'signingEntitlementEnvironment',
      ]) {
        final fixture = _IosPreflightFixture.create(
          apnsEnvironment: field == 'apnsEnvironment'
              ? 'production'
              : 'development',
          signingEntitlementEnvironment:
              field == 'signingEntitlementEnvironment'
              ? 'production'
              : 'development',
        );
        addTearDown(fixture.dispose);
        final build = _iosBuildRow();
        final consumer = _iosConsumer(dependencies: <String>[build.id]);
        final binding = SimsDevicePlanBinding.bind(
          _plan(<CapabilitySpec>[build, consumer]),
          _inventory(<SimsLiveDeviceTarget>[_iphone()]),
          processEnvironment: fixture.environment,
        );

        expect(
          binding.preflightVerdicts[consumer.id]?.blocker,
          SimsBlockerKind.credentials,
          reason: '$field must reject a production APNs attestation',
        );
        expect(
          binding.preflightVerdicts[build.id]?.blocker,
          SimsBlockerKind.credentials,
          reason: '$field must prevent the production build',
        );
        expect(binding.skippedBuildProfiles, <String>{'ios.device.production'});
      }
    },
  );

  test('generic simulators cannot trigger destructive group build/setup', () {
    final build = _iosSimulatorBuildRow();
    final consumer = _groupConsumer(dependencies: <String>[build.id]);
    final binding = SimsDevicePlanBinding.bind(
      _plan(<CapabilitySpec>[build, consumer]),
      _inventory(_fourSimulators()),
      processEnvironment: const <String, String>{
        'MKNOON_RELAY_ADDRESSES': '127.0.0.1:4001',
      },
    );

    expect(
      binding.preflightVerdicts[consumer.id]?.blocker,
      SimsBlockerKind.permissions,
    );
    expect(
      binding.preflightVerdicts[build.id]?.blocker,
      SimsBlockerKind.permissions,
    );
    expect(binding.skippedBuildProfiles, <String>{'ios.simulator.e2e'});
  });

  test('unauthorized launchable group targets are never booted', () {
    final targets = _fourSimulators()
        .map(
          (target) => SimsLiveDeviceTarget(
            name: target.name,
            platform: target.platform,
            kind: target.kind,
            availability: SimsLiveDeviceAvailability.launchable,
            runtimeId: null,
            launchId: target.runtimeId,
            sources: target.sources,
          ),
        )
        .toList(growable: false);
    final binding = SimsDevicePlanBinding.bind(
      _plan(<CapabilitySpec>[_groupConsumer()]),
      _inventory(targets),
      processEnvironment: const <String, String>{
        'MKNOON_RELAY_ADDRESSES': '127.0.0.1:4001',
      },
    );

    expect(
      binding.preflightVerdicts[_groupConsumer().id]?.blocker,
      SimsBlockerKind.permissions,
    );
    expect(binding.preparationTargets, isEmpty);
  });

  test('authorized disposable simulator IDs drive role assignment order', () {
    const authorized = <String>[
      '44444444-4444-4444-4444-444444444444',
      '22222222-2222-2222-2222-222222222222',
      '11111111-1111-1111-1111-111111111111',
      '33333333-3333-3333-3333-333333333333',
    ];
    final binding = SimsDevicePlanBinding.bind(
      _plan(<CapabilitySpec>[_groupConsumer()]),
      _inventory(_fourSimulators()),
      processEnvironment: <String, String>{
        'SIMS_IOS_DISPOSABLE_SIMULATOR_IDS': authorized.join(','),
        'MKNOON_RELAY_ADDRESSES': '127.0.0.1:4001',
      },
    );

    expect(binding.preflightVerdicts, isEmpty);
    expect(
      binding.assignments,
      containsPair('device:ios-simulator-a', authorized[0]),
    );
    expect(
      binding.assignments,
      containsPair('device:ios-simulator-b', authorized[1]),
    );
    expect(
      binding.assignments,
      containsPair('device:ios-simulator-c', authorized[2]),
    );
    expect(
      binding.assignments,
      containsPair('device:ios-simulator-d', authorized[3]),
    );
    expect(binding.environment['SIMS_IOS_SIMULATOR_IDS'], authorized.join(','));
  });

  test(
    'authorized group IDs also pin shared simulator roles in other rows',
    () {
      const authorized = <String>[
        '44444444-4444-4444-4444-444444444444',
        '22222222-2222-2222-2222-222222222222',
        '11111111-1111-1111-1111-111111111111',
        '33333333-3333-3333-3333-333333333333',
      ];
      final binding = SimsDevicePlanBinding.bind(
        _plan(<CapabilitySpec>[_nativeIosConsumer(), _groupConsumer()]),
        _inventory(_fourSimulators()),
        processEnvironment: <String, String>{
          'SIMS_IOS_DISPOSABLE_SIMULATOR_IDS': authorized.join(','),
          'MKNOON_RELAY_ADDRESSES': '127.0.0.1:4001',
        },
      );

      expect(binding.preflightVerdicts, isEmpty);
      expect(
        binding.plan.rows.first.resources.single.name,
        'device:${authorized.first}',
      );
      expect(
        binding.environmentByCapabilityId[_nativeIosConsumer()
            .id]!['SIMS_IOS_SIMULATOR_A_DEVICE_ID'],
        authorized.first,
      );
    },
  );

  test(
    'unavailable authorized simulator is N/A before relay configuration',
    () {
      const authorized = <String>[
        '11111111-1111-1111-1111-111111111111',
        '22222222-2222-2222-2222-222222222222',
        '33333333-3333-3333-3333-333333333333',
        '55555555-5555-5555-5555-555555555555',
      ];
      final build = _iosSimulatorBuildRow();
      final consumer = _groupConsumer(dependencies: <String>[build.id]);
      final binding = SimsDevicePlanBinding.bind(
        _plan(<CapabilitySpec>[build, consumer]),
        _inventory(_fourSimulators()),
        processEnvironment: <String, String>{
          'SIMS_IOS_DISPOSABLE_SIMULATOR_IDS': authorized.join(','),
        },
      );

      expect(
        binding.preflightVerdicts[consumer.id]?.status,
        SimsVerdictStatus.notApplicable,
      );
      expect(
        binding.preflightVerdicts[consumer.id]?.blocker,
        SimsBlockerKind.targetUnavailable,
      );
      expect(
        binding.preflightVerdicts[build.id]?.status,
        SimsVerdictStatus.notApplicable,
      );
      expect(binding.assignments, isEmpty);
    },
  );

  test('explicit Android target pins override sorted candidates', () {
    final binding = SimsDevicePlanBinding.bind(
      _plan(<CapabilitySpec>[_androidThreePeerConsumer()]),
      _inventory(<SimsLiveDeviceTarget>[
        _androidTarget('pixel-a', SimsLiveDeviceKind.physical),
        _androidTarget('pixel-z', SimsLiveDeviceKind.physical),
        _androidTarget('emulator-5554', SimsLiveDeviceKind.emulator),
        _androidTarget('emulator-5556', SimsLiveDeviceKind.emulator),
        _androidTarget('emulator-5558', SimsLiveDeviceKind.emulator),
      ]),
      processEnvironment: const <String, String>{
        'SIMS_ANDROID_PHYSICAL_DEVICE_ID': 'pixel-z',
        'SIMS_ANDROID_EMULATOR_DEVICE_ID': 'emulator-5556',
        'SIMS_ANDROID_EMULATOR_SECOND_DEVICE_ID': 'emulator-5554',
      },
    );

    expect(binding.preflightVerdicts, isEmpty);
    expect(binding.assignments, <String, String>{
      'device:android-physical': 'pixel-z',
      'device:android-emulator': 'emulator-5556',
      'device:android-emulator-second': 'emulator-5554',
    });
    expect(binding.environment['ANDROID_SERIAL'], 'pixel-z');
    expect(
      binding.environment['SIMS_ANDROID_EMULATOR_DEVICE_ID'],
      'emulator-5556',
    );
    expect(
      binding.environment['SIMS_ANDROID_EMULATOR_SECOND_DEVICE_ID'],
      'emulator-5554',
    );
    expect(
      binding.plan.rows.single.resources.map((lock) => lock.name),
      containsAll(<String>[
        'device:pixel-z',
        'device:emulator-5556',
        'device:emulator-5554',
      ]),
    );
  });

  test('each invalid explicit Android target pin fails closed', () {
    for (final environmentName in const <String>[
      'SIMS_ANDROID_PHYSICAL_DEVICE_ID',
      'SIMS_ANDROID_EMULATOR_DEVICE_ID',
      'SIMS_ANDROID_EMULATOR_SECOND_DEVICE_ID',
    ]) {
      final binding = SimsDevicePlanBinding.bind(
        _plan(<CapabilitySpec>[_androidThreePeerConsumer()]),
        _inventory(<SimsLiveDeviceTarget>[
          _androidTarget('pixel-a', SimsLiveDeviceKind.physical),
          _androidTarget('emulator-5554', SimsLiveDeviceKind.emulator),
          _androidTarget('emulator-5556', SimsLiveDeviceKind.emulator),
        ]),
        processEnvironment: <String, String>{environmentName: 'missing-target'},
      );

      final verdict = binding.preflightVerdicts[_androidThreePeerConsumer().id];
      expect(verdict?.status, SimsVerdictStatus.notApplicable);
      expect(verdict?.blocker, SimsBlockerKind.targetUnavailable);
      expect(verdict?.reason, targetUnavailableNaReason);
      expect(verdict?.targetCapabilityAvailable, isFalse);
      expect(binding.assignments, isEmpty);
    }
  });

  test('duplicate explicit emulator pins fail as a harness error', () {
    final binding = SimsDevicePlanBinding.bind(
      _plan(<CapabilitySpec>[_androidThreePeerConsumer()]),
      _inventory(<SimsLiveDeviceTarget>[
        _androidTarget('pixel-a', SimsLiveDeviceKind.physical),
        _androidTarget('emulator-5554', SimsLiveDeviceKind.emulator),
        _androidTarget('emulator-5556', SimsLiveDeviceKind.emulator),
      ]),
      processEnvironment: const <String, String>{
        'SIMS_ANDROID_EMULATOR_DEVICE_ID': 'emulator-5556',
        'SIMS_ANDROID_EMULATOR_SECOND_DEVICE_ID': 'emulator-5556',
      },
    );

    final verdict = binding.preflightVerdicts[_androidThreePeerConsumer().id];
    expect(verdict?.status, SimsVerdictStatus.fail);
    expect(verdict?.blocker, SimsBlockerKind.harness);
    expect(verdict?.detail, contains('Distinct device roles'));
    expect(binding.assignments, isEmpty);
  });

  test('Android control lock also honors the explicit emulator pin', () {
    final binding = SimsDevicePlanBinding.bind(
      _plan(<CapabilitySpec>[_androidControlConsumer()]),
      _inventory(<SimsLiveDeviceTarget>[
        _androidTarget('emulator-5554', SimsLiveDeviceKind.emulator),
        _androidTarget('emulator-5556', SimsLiveDeviceKind.emulator),
      ]),
      processEnvironment: const <String, String>{
        'SIMS_ANDROID_EMULATOR_DEVICE_ID': 'emulator-5556',
      },
    );

    expect(binding.preflightVerdicts, isEmpty);
    expect(
      binding.assignments['device-control:android-emulator'],
      'emulator-5556',
    );
  });

  test('unpinned Android targets retain deterministic sorted assignment', () {
    final binding = SimsDevicePlanBinding.bind(
      _plan(<CapabilitySpec>[_androidThreePeerConsumer()]),
      _inventory(<SimsLiveDeviceTarget>[
        _androidTarget('pixel-z', SimsLiveDeviceKind.physical),
        _androidTarget('pixel-a', SimsLiveDeviceKind.physical),
        _androidTarget('emulator-5558', SimsLiveDeviceKind.emulator),
        _androidTarget('emulator-5554', SimsLiveDeviceKind.emulator),
        _androidTarget('emulator-5556', SimsLiveDeviceKind.emulator),
      ]),
    );

    expect(binding.preflightVerdicts, isEmpty);
    expect(binding.assignments, <String, String>{
      'device:android-physical': 'pixel-a',
      'device:android-emulator': 'emulator-5554',
      'device:android-emulator-second': 'emulator-5556',
    });
  });
}

SimsPlan _plan(List<CapabilitySpec> rows) => SimsPlan(
  mode: SimsMode.major,
  simultaneous: true,
  releaseEligibleCandidate: true,
  manifestDigest: 'fixture',
  family: null,
  onlyId: null,
  rows: rows,
);

CapabilitySpec _buildRow() => CapabilitySpec(
  id: 'build.android.standard',
  owner: 'fixture',
  proofBoundaryId: 'fixture.build',
  assertionIds: const <String>['build.attested'],
  lane: 'reliability',
  modes: const <SimsMode>{SimsMode.major},
  families: const <String>{'fixture'},
  required: true,
  command: const <String>['@prepare-build', 'android.e2e.standard'],
  buildProfileId: 'android.e2e.standard',
  dependencies: const <String>[],
  resources: const <ResourceLock>[
    ResourceLock(
      name: 'build:android.e2e.standard',
      access: ResourceAccess.write,
    ),
  ],
  targetCapabilities: const <String>['host.android-sdk'],
  allowedNaReason: targetUnavailableNaReason,
  artifactRequired: true,
  artifactValidator: 'fixture-attestation',
  active: true,
  declaredBuildException: false,
);

CapabilitySpec _iosBuildRow() => CapabilitySpec(
  id: 'build.ios.device.production',
  owner: 'fixture',
  proofBoundaryId: 'fixture.ios.build',
  assertionIds: const <String>['ios.build.attested'],
  lane: 'reliability',
  modes: const <SimsMode>{SimsMode.major},
  families: const <String>{'fixture'},
  required: true,
  command: const <String>['@prepare-build', 'ios.device.production'],
  buildProfileId: 'ios.device.production',
  dependencies: const <String>[],
  resources: const <ResourceLock>[
    ResourceLock(
      name: 'build:ios.device.production',
      access: ResourceAccess.write,
    ),
  ],
  targetCapabilities: const <String>['host.xcode', 'credentials.apns-signing'],
  allowedNaReason: targetUnavailableNaReason,
  artifactRequired: true,
  artifactValidator: 'fixture-ios-attestation',
  active: true,
  declaredBuildException: false,
);

CapabilitySpec _iosSimulatorBuildRow() => CapabilitySpec(
  id: 'build.ios.simulator.e2e',
  owner: 'fixture',
  proofBoundaryId: 'fixture.ios.simulator.build',
  assertionIds: const <String>['ios.simulator.build.attested'],
  lane: 'reliability',
  modes: const <SimsMode>{SimsMode.major},
  families: const <String>{'fixture'},
  required: true,
  command: const <String>['@prepare-build', 'ios.simulator.e2e'],
  buildProfileId: 'ios.simulator.e2e',
  dependencies: const <String>[],
  resources: const <ResourceLock>[
    ResourceLock(name: 'build:ios.simulator.e2e', access: ResourceAccess.write),
  ],
  targetCapabilities: const <String>['host.xcode'],
  allowedNaReason: targetUnavailableNaReason,
  artifactRequired: true,
  artifactValidator: 'fixture-ios-simulator-attestation',
  active: true,
  declaredBuildException: false,
);

CapabilitySpec _groupConsumer({List<String> dependencies = const <String>[]}) =>
    CapabilitySpec(
      id: 'groups.multi_party_release',
      owner: 'fixture',
      proofBoundaryId: 'fixture.group.multi',
      assertionIds: const <String>['group.multi.passed'],
      lane: 'reliability',
      modes: const <SimsMode>{SimsMode.major},
      families: const <String>{'fixture'},
      required: true,
      command: const <String>['fixture-group-runner'],
      buildProfileId: 'ios.simulator.e2e',
      dependencies: dependencies,
      resources: const <ResourceLock>[
        ResourceLock(
          name: 'build:ios.simulator.e2e',
          access: ResourceAccess.read,
        ),
        ResourceLock(
          name: 'device:ios-simulator-a',
          access: ResourceAccess.exclusive,
        ),
        ResourceLock(
          name: 'device:ios-simulator-b',
          access: ResourceAccess.exclusive,
        ),
        ResourceLock(
          name: 'device:ios-simulator-c',
          access: ResourceAccess.exclusive,
        ),
        ResourceLock(
          name: 'device:ios-simulator-d',
          access: ResourceAccess.exclusive,
        ),
      ],
      targetCapabilities: const <String>[
        'ios.simulator.count4',
        'ios.simulators.disposable',
        'relay.staging',
      ],
      allowedNaReason: targetUnavailableNaReason,
      artifactRequired: true,
      artifactValidator: 'fixture-group-proof',
      active: true,
      declaredBuildException: false,
      automationReady: true,
    );

CapabilitySpec _nativeIosConsumer() => CapabilitySpec(
  id: 'native.ios.fixture',
  owner: 'fixture',
  proofBoundaryId: 'fixture.ios.native',
  assertionIds: const <String>['ios.native.passed'],
  lane: 'reliability',
  modes: const <SimsMode>{SimsMode.major},
  families: const <String>{'fixture'},
  required: true,
  command: const <String>['fixture-ios-native-runner'],
  buildProfileId: 'host.none',
  dependencies: const <String>[],
  resources: const <ResourceLock>[
    ResourceLock(
      name: 'device:ios-simulator-a',
      access: ResourceAccess.exclusive,
    ),
  ],
  targetCapabilities: const <String>['ios.simulator'],
  allowedNaReason: targetUnavailableNaReason,
  artifactRequired: false,
  artifactValidator: null,
  active: true,
  declaredBuildException: false,
  automationReady: true,
);

CapabilitySpec _iosConsumer({List<String> dependencies = const <String>[]}) =>
    CapabilitySpec(
      id: 'notifications.ios_payload_fast_path',
      owner: 'fixture',
      proofBoundaryId: 'fixture.ios.apns',
      assertionIds: const <String>['ios.apns.nse.passed'],
      lane: 'reliability',
      modes: const <SimsMode>{SimsMode.major},
      families: const <String>{'fixture'},
      required: true,
      command: const <String>['fixture-ios-runner'],
      buildProfileId: 'ios.device.production',
      dependencies: dependencies,
      resources: const <ResourceLock>[
        ResourceLock(
          name: 'build:ios.device.production',
          access: ResourceAccess.read,
        ),
        ResourceLock(
          name: 'device:ios-physical',
          access: ResourceAccess.exclusive,
        ),
      ],
      targetCapabilities: const <String>[
        'ios.physical',
        'credentials.apns',
        'ios.nse',
        'relay.staging',
      ],
      allowedNaReason: targetUnavailableNaReason,
      artifactRequired: true,
      artifactValidator: 'validateNotificationArtifact',
      active: true,
      declaredBuildException: false,
      automationReady: true,
    );

CapabilitySpec _consumer({
  List<String> dependencies = const <String>[],
  bool automationReady = true,
  List<String> targetCapabilities = const <String>['android.physical'],
}) => CapabilitySpec(
  id: 'android.fixture',
  owner: 'fixture',
  proofBoundaryId: 'fixture.android',
  assertionIds: const <String>['fixture.passed'],
  lane: 'reliability',
  modes: const <SimsMode>{SimsMode.major},
  families: const <String>{'fixture'},
  required: true,
  command: const <String>['fixture-runner'],
  buildProfileId: 'android.e2e.standard',
  dependencies: dependencies,
  resources: const <ResourceLock>[
    ResourceLock(
      name: 'build:android.e2e.standard',
      access: ResourceAccess.read,
    ),
    ResourceLock(
      name: 'device:android-physical',
      access: ResourceAccess.exclusive,
    ),
  ],
  targetCapabilities: targetCapabilities,
  allowedNaReason: targetUnavailableNaReason,
  artifactRequired: true,
  artifactValidator: 'fixture-proof',
  active: true,
  declaredBuildException: false,
  automationReady: automationReady,
);

CapabilitySpec _androidThreePeerConsumer() => CapabilitySpec(
  id: 'android.three-peer.fixture',
  owner: 'fixture',
  proofBoundaryId: 'fixture.android.three-peer',
  assertionIds: const <String>['fixture.three-peer.passed'],
  lane: 'reliability',
  modes: const <SimsMode>{SimsMode.major},
  families: const <String>{'fixture'},
  required: true,
  command: const <String>['fixture-three-peer-runner'],
  buildProfileId: 'android.e2e.standard',
  dependencies: const <String>[],
  resources: const <ResourceLock>[
    ResourceLock(
      name: 'device:android-physical',
      access: ResourceAccess.exclusive,
    ),
    ResourceLock(
      name: 'device:android-emulator',
      access: ResourceAccess.exclusive,
    ),
    ResourceLock(
      name: 'device:android-emulator-second',
      access: ResourceAccess.exclusive,
    ),
  ],
  targetCapabilities: const <String>[
    'android.physical',
    'android.emulator.count2',
  ],
  allowedNaReason: targetUnavailableNaReason,
  artifactRequired: false,
  artifactValidator: null,
  active: true,
  declaredBuildException: false,
  automationReady: true,
);

CapabilitySpec _androidControlConsumer() => CapabilitySpec(
  id: 'android.control.fixture',
  owner: 'fixture',
  proofBoundaryId: 'fixture.android.control',
  assertionIds: const <String>['fixture.control.passed'],
  lane: 'reliability',
  modes: const <SimsMode>{SimsMode.major},
  families: const <String>{'fixture'},
  required: true,
  command: const <String>['fixture-control-runner'],
  buildProfileId: 'android.e2e.standard',
  dependencies: const <String>[],
  resources: const <ResourceLock>[
    ResourceLock(
      name: 'device-control:android-emulator',
      access: ResourceAccess.exclusive,
    ),
  ],
  targetCapabilities: const <String>['android.emulator'],
  allowedNaReason: targetUnavailableNaReason,
  artifactRequired: false,
  artifactValidator: null,
  active: true,
  declaredBuildException: false,
  automationReady: true,
);

SimsLiveDeviceInventory _inventory(
  List<SimsLiveDeviceTarget> targets, {
  String detail = 'fixture',
  SimsDiscoveryStatus flutterStatus = SimsDiscoveryStatus.success,
}) => SimsLiveDeviceInventory(
  targets: targets,
  sourceResults: <SimsDiscoverySourceResult>[
    for (final source in SimsDeviceDiscoverySource.values)
      SimsDiscoverySourceResult(
        source: source,
        status: source == SimsDeviceDiscoverySource.flutterDevices
            ? flutterStatus
            : SimsDiscoveryStatus.success,
        detail: detail,
      ),
  ],
);

SimsLiveDeviceTarget _androidTarget(String id, SimsLiveDeviceKind kind) =>
    SimsLiveDeviceTarget(
      name: id,
      platform: SimsLiveDevicePlatform.android,
      kind: kind,
      availability: SimsLiveDeviceAvailability.connected,
      runtimeId: id,
      launchId: null,
      sources: const <SimsDeviceDiscoverySource>{
        SimsDeviceDiscoverySource.flutterDevices,
        SimsDeviceDiscoverySource.adb,
      },
    );

SimsLiveDeviceTarget _iphone() => SimsLiveDeviceTarget(
  name: 'Dedicated iPhone',
  platform: SimsLiveDevicePlatform.ios,
  kind: SimsLiveDeviceKind.physical,
  availability: SimsLiveDeviceAvailability.connected,
  runtimeId: '00008150-001C3C6A3684401C',
  launchId: null,
  sources: const <SimsDeviceDiscoverySource>{
    SimsDeviceDiscoverySource.flutterDevices,
  },
);

SimsLiveDeviceTarget _iphoneWithId(String id) => SimsLiveDeviceTarget(
  name: 'Other iPhone',
  platform: SimsLiveDevicePlatform.ios,
  kind: SimsLiveDeviceKind.physical,
  availability: SimsLiveDeviceAvailability.connected,
  runtimeId: id,
  launchId: null,
  sources: const <SimsDeviceDiscoverySource>{
    SimsDeviceDiscoverySource.flutterDevices,
  },
);

List<SimsLiveDeviceTarget> _fourSimulators() {
  const ids = <String>[
    '11111111-1111-1111-1111-111111111111',
    '22222222-2222-2222-2222-222222222222',
    '33333333-3333-3333-3333-333333333333',
    '44444444-4444-4444-4444-444444444444',
  ];
  return <SimsLiveDeviceTarget>[
    for (var index = 0; index < ids.length; index += 1)
      SimsLiveDeviceTarget(
        name: 'Disposable candidate ${index + 1}',
        platform: SimsLiveDevicePlatform.ios,
        kind: SimsLiveDeviceKind.simulator,
        availability: SimsLiveDeviceAvailability.connected,
        runtimeId: ids[index],
        launchId: null,
        sources: const <SimsDeviceDiscoverySource>{
          SimsDeviceDiscoverySource.simctl,
        },
      ),
  ];
}

final class _IosPreflightFixture {
  _IosPreflightFixture._(this.root, this.environment);

  factory _IosPreflightFixture.create({
    bool signingReady = true,
    String apnsEnvironment = 'development',
    String signingEntitlementEnvironment = 'development',
  }) {
    final root = Directory.systemTemp.createTempSync('sims-ios-preflight-');
    final staging = File('${root.path}/staging.json')
      ..writeAsStringSync(
        jsonEncode(<String, Object?>{
          'schema': 'mknoon.sims.ios-payload-fast-path-staging.v1',
          'environment': 'staging',
          'provider': 'apns',
          'providerConfigured': true,
          'providerCredentialsAvailable': true,
          'providerProbeSucceeded': true,
          'appSigningAvailable': true,
          'signingProbeSucceeded': signingReady,
          'apnsEnvironment': apnsEnvironment,
          'signingEntitlementEnvironment': signingEntitlementEnvironment,
          'signingIdentitySha256': 'a' * 64,
          'relayActive': true,
          'relayInboxSeedDriverAvailable': true,
          'dedicatedDisposableReceiver': true,
          'destructiveTestStateResetAuthorized': true,
          'providerCleanupAvailable': true,
          'productionDeploymentPerformed': false,
          'bundleId': 'com.mknoon.app',
          'receiverDeviceId': '00008150-001C3C6A3684401C',
          'peerDeviceId': 'android-peer-1234',
        }),
      );
    final request = File('${root.path}/request.json')
      ..writeAsStringSync(
        jsonEncode(<String, Object?>{
          'schema': 'mknoon.sims.ios-payload-fast-path-provider-request.v1',
          'expectedTitle': 'title',
          'expectedBody': 'body',
          'expectedMessageText': 'message',
          'receiverDeviceId': '00008150-001C3C6A3684401C',
          'peerDeviceId': 'android-peer-1234',
        }),
      );
    final provider = File('${root.path}/provider-driver')
      ..writeAsStringSync('#!/bin/sh\nexit 0\n');
    Process.runSync('chmod', <String>['755', provider.path]);
    final payloadProducer = File('${root.path}/payload-producer')
      ..writeAsStringSync('#!/bin/sh\nexit 0\n');
    final relayFixture = File('${root.path}/relay-fixture')
      ..writeAsStringSync('#!/bin/sh\nexit 0\n');
    Process.runSync('chmod', <String>['755', payloadProducer.path]);
    Process.runSync('chmod', <String>['755', relayFixture.path]);
    final authKey = File('${root.path}/AuthKey_ABCDEFGHIJ.p8')
      ..writeAsStringSync('fixture-private-key');
    Process.runSync('chmod', <String>['600', authKey.path]);
    final staged =
        jsonDecode(staging.readAsStringSync()) as Map<String, dynamic>
          ..['payloadProducerSha256'] = sha256
              .convert(payloadProducer.readAsBytesSync())
              .toString()
          ..['relayFixtureDriverSha256'] = sha256
              .convert(relayFixture.readAsBytesSync())
              .toString();
    staging.writeAsStringSync(jsonEncode(staged));
    final relayKey = File('${root.path}/relay-key')..writeAsStringSync('key');
    return _IosPreflightFixture._(root, <String, String>{
      'SIMS_IOS_NOTIFICATION_STAGING_MANIFEST': staging.path,
      'SIMS_IOS_NOTIFICATION_PROVIDER_REQUEST': request.path,
      'SIMS_IOS_NOTIFICATION_PROVIDER_DRIVER': provider.path,
      'SIMS_IOS_NOTIFICATION_PAYLOAD_PRODUCER': payloadProducer.path,
      'SIMS_IOS_NOTIFICATION_RELAY_FIXTURE_DRIVER': relayFixture.path,
      'SIMS_IOS_APNS_AUTH_KEY_PATH': authKey.path,
      'SIMS_IOS_APNS_KEY_ID': 'ABCDEFGHIJ',
      'SIMS_IOS_APNS_TEAM_ID': '397R9Q4WMX',
      'SIMS_NOTIFICATION_RELAY_TARGET': 'fixture@staging-relay',
      'SIMS_NOTIFICATION_RELAY_KEY': relayKey.path,
    });
  }

  final Directory root;
  final Map<String, String> environment;

  void dispose() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  }
}
