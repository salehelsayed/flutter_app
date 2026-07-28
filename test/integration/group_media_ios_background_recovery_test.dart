import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/debug/group_media_ios_disposable_profile.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/group_media_ios_background_recovery.dart';
import '../../integration_test/scripts/group_media_ios_background_recovery_evidence.dart';
import '../../integration_test/scripts/group_media_ios_fixture_driver.dart'
    as fixture_driver;
import '../../integration_test/support/android_app_state_guard.dart';
import '../../integration_test/support/group_media_android_disposable_app.dart';

void main() {
  test('P269 iOS target policy rejects every iPhone 13 product type', () {
    for (final productType in const <String>[
      'iPhone14,2',
      'iPhone14,3',
      'iPhone14,4',
      'iPhone14,5',
    ]) {
      expect(groupMediaIosReceiverProductTypeAllowed(productType), isFalse);
    }
    expect(groupMediaIosReceiverProductTypeAllowed('iPhone12,1'), isTrue);
    expect(groupMediaIosReceiverProductTypeAllowed('iPad14,2'), isFalse);
  });

  test(
    'P269 system command boundary rejects absolute nested xcode builds and permits one exact prebuilt selector',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'p269-xcode-no-build-',
      );
      addTearDown(() async {
        if (root.existsSync()) await root.delete(recursive: true);
      });
      final marker = File('${root.path}/invoked.txt');
      final guardLog = File('${root.path}/guard.log');
      final executable = File('${root.path}/xcodebuild')
        ..writeAsStringSync(
          '#!/bin/sh\n'
          'printf "invoked\\n" >>"\$SIMS_TEST_XCODE_MARKER"\n'
          'exit 0\n',
        );
      final chmod = await Process.run('chmod', <String>[
        '700',
        executable.path,
      ]);
      expect(chmod.exitCode, 0);
      const runner = SystemGroupMediaIosCommandRunner();
      final environment = <String, String>{
        'SIMS_CHILD_BUILDS_FORBIDDEN': '1',
        'SIMS_BUILD_GUARD_LOG': guardLog.path,
        'SIMS_TEST_XCODE_MARKER': marker.path,
      };

      for (final arguments in <List<String>>[
        const <String>['build-for-testing'],
        const <String>['test'],
        const <String>[],
      ]) {
        final result = await runner.run(
          GroupMediaIosCommand(
            label: 'forbidden-xcode-action',
            executable: executable.absolute.path,
            arguments: arguments,
            environment: environment,
          ),
        );
        expect(result.exitCode, 91, reason: '$arguments');
        expect(marker.existsSync(), isFalse, reason: '$arguments');
      }
      expect(guardLog.readAsLinesSync(), hasLength(3));

      final xctestrun = File('${root.path}/RunnerUITests.xctestrun')
        ..writeAsStringSync('prebuilt');
      final allowed = await runner.run(
        GroupMediaIosCommand(
          label: 'allowed-prebuilt-xcode-selector',
          executable: executable.absolute.path,
          arguments: <String>[
            'test-without-building',
            '-xctestrun',
            xctestrun.absolute.path,
            '-destination',
            'platform=iOS,id=physical-device',
            '-parallel-testing-enabled',
            'NO',
            '-only-testing:RunnerUITests/FixtureTests/testProof',
            '-resultBundlePath',
            '${root.absolute.path}/result.xcresult',
          ],
          environment: environment,
        ),
      );
      expect(allowed.exitCode, 0);
      expect(marker.readAsLinesSync(), <String>['invoked']);
      expect(guardLog.readAsLinesSync(), hasLength(3));
    },
  );

  test(
    'P269 CoreDevice timeout recovery retries only idempotent info and copy commands',
    () async {
      final recovery = _RecordingCoreDeviceRecovery();
      final delegate = _SequenceCommandRunner(<GroupMediaIosCommandResult>[
        const GroupMediaIosCommandResult(
          exitCode: 124,
          stdout: '',
          stderr: 'timeout',
        ),
        GroupMediaIosCommandResult.success('recovered'),
      ]);
      final runner = RecoveringGroupMediaIosCommandRunner(
        delegate: delegate,
        recovery: recovery,
        maxRecoveries: 1,
      );
      final recovered = await runner.run(
        const GroupMediaIosCommand(
          label: 'pull-reset-pre',
          executable: 'xcrun',
          arguments: <String>[
            'devicectl',
            'device',
            'copy',
            'from',
            '--device',
            _Fixture.receiverDeviceId,
          ],
        ),
      );
      expect(recovered.exitCode, 0);
      expect(delegate.calls, 2);
      expect(recovery.calls, 1);

      final unsafeRecovery = _RecordingCoreDeviceRecovery();
      final unsafeDelegate =
          _SequenceCommandRunner(<GroupMediaIosCommandResult>[
            const GroupMediaIosCommandResult(
              exitCode: 124,
              stdout: '',
              stderr: 'timeout',
            ),
            GroupMediaIosCommandResult.success('must not run'),
          ]);
      final unsafeRunner = RecoveringGroupMediaIosCommandRunner(
        delegate: unsafeDelegate,
        recovery: unsafeRecovery,
        maxRecoveries: 1,
      );
      final unsafe = await unsafeRunner.run(
        const GroupMediaIosCommand(
          label: 'launch-root-before-proof',
          executable: 'xcrun',
          arguments: <String>[
            'devicectl',
            'device',
            'process',
            'launch',
            '--device',
            _Fixture.receiverDeviceId,
          ],
        ),
      );
      expect(unsafe.exitCode, 124);
      expect(unsafeDelegate.calls, 1);
      expect(unsafeRecovery.calls, 0);
    },
  );

  test(
    'P269 fixture CoreDevice recovery distinguishes copy staging from expected absent reads',
    () async {
      var stagingCalls = 0;
      var stagingRecoveries = 0;
      final staging = fixture_driver.GroupMediaIosFixtureProcessRunner(
        execute: (_, _) async {
          stagingCalls += 1;
          return ProcessResult(1, stagingCalls == 1 ? 1 : 0, '', '');
        },
        recover: () async {
          stagingRecoveries += 1;
          return true;
        },
        maxRecoveries: 1,
      );
      final staged = await staging.run('xcrun', const <String>[
        'devicectl',
        'device',
        'copy',
        'to',
      ]);
      expect(staged.exitCode, 0);
      expect(stagingCalls, 2);
      expect(stagingRecoveries, 1);

      var absentCalls = 0;
      var absentRecoveries = 0;
      final absent = fixture_driver.GroupMediaIosFixtureProcessRunner(
        execute: (_, _) async {
          absentCalls += 1;
          return ProcessResult(1, 1, '', '');
        },
        recover: () async {
          absentRecoveries += 1;
          return true;
        },
      );
      final absentRead = await absent.run('xcrun', const <String>[
        'devicectl',
        'device',
        'copy',
        'from',
      ]);
      expect(absentRead.exitCode, 1);
      expect(absentCalls, 1);
      expect(absentRecoveries, 0);

      var timedOutReadCalls = 0;
      var timedOutReadRecoveries = 0;
      final timedOutRead = fixture_driver.GroupMediaIosFixtureProcessRunner(
        execute: (_, _) async {
          timedOutReadCalls += 1;
          return ProcessResult(1, timedOutReadCalls == 1 ? 124 : 0, '', '');
        },
        recover: () async {
          timedOutReadRecoveries += 1;
          return true;
        },
        maxRecoveries: 1,
      );
      final recoveredRead = await timedOutRead.run('xcrun', const <String>[
        'devicectl',
        'device',
        'copy',
        'from',
      ]);
      expect(recoveredRead.exitCode, 0);
      expect(timedOutReadCalls, 2);
      expect(timedOutReadRecoveries, 1);

      var processCalls = 0;
      var processRecoveries = 0;
      final process = fixture_driver.GroupMediaIosFixtureProcessRunner(
        execute: (_, _) async {
          processCalls += 1;
          return ProcessResult(1, 124, '', '');
        },
        recover: () async {
          processRecoveries += 1;
          return true;
        },
      );
      final processResult = await process.run('xcrun', const <String>[
        'devicectl',
        'device',
        'process',
        'launch',
      ]);
      expect(processResult.exitCode, 124);
      expect(processCalls, 1);
      expect(processRecoveries, 0);
    },
  );

  test(
    'P269 identity continuity ignores fresh QR timestamp and signature but binds stable keys',
    () {
      String qr({
        required String publicKey,
        required String timestamp,
        required String signature,
      }) => jsonEncode(<String, Object?>{
        'ns': 'account-peer',
        'pk': publicKey,
        'rv': '/dns/relay.invalid/tcp/443/wss',
        'ts': timestamp,
        'un': 'Receiver',
        'sig': signature,
      });

      final firstQr = qr(
        publicKey: 'account-public-key',
        timestamp: '2026-07-23T10:00:00.000Z',
        signature: 'signature-one',
      );
      final freshQr = qr(
        publicKey: 'account-public-key',
        timestamp: '2026-07-23T10:01:00.000Z',
        signature: 'signature-two',
      );
      expect(
        fixture_driver.groupMediaIosIdentityContinuityMatches(
          accountPeerId: 'account-peer',
          transportPeerId: 'transport-peer',
          qrPayload: firstQr,
          mlKemPublicKey: 'mlkem-public-key',
          otherAccountPeerId: 'account-peer',
          otherTransportPeerId: 'transport-peer',
          otherQrPayload: freshQr,
          otherMlKemPublicKey: 'mlkem-public-key',
        ),
        isTrue,
      );
      expect(
        fixture_driver.groupMediaIosIdentityContinuityMatches(
          accountPeerId: 'account-peer',
          transportPeerId: 'transport-peer',
          qrPayload: firstQr,
          mlKemPublicKey: 'mlkem-public-key',
          otherAccountPeerId: 'account-peer',
          otherTransportPeerId: 'transport-peer',
          otherQrPayload: qr(
            publicKey: 'changed-public-key',
            timestamp: '2026-07-23T10:01:00.000Z',
            signature: 'signature-three',
          ),
          otherMlKemPublicKey: 'mlkem-public-key',
        ),
        isFalse,
      );
    },
  );

  test(
    'P269 production Android auditing runner derives safe counts from delegated commands',
    () async {
      final delegate = _RecordingAndroidHostRunner();
      final audit = GroupMediaAndroidCommandAudit();
      final runner = GroupMediaAndroidCommandAuditingRunner(
        delegate: delegate,
        audit: audit,
      );

      await runner.run('adb', const <String>[
        '-s',
        'pixel-usb',
        'shell',
        'pm',
        'path',
        groupMediaAndroidDisposablePackageId,
      ]);
      await runner.run('adb', const <String>[
        '-s',
        'pixel-usb',
        'shell',
        'rm',
        '-f',
        '/data/local/tmp/p269-scoped.json',
      ]);
      await runner.run('adb', const <String>[
        '-s',
        'pixel-usb',
        'shell',
        'am',
        'start',
        '-n',
        '$groupMediaAndroidDisposablePackageId/com.mknoon.app.MainActivity',
      ]);

      final snapshot = audit.snapshot;
      expect(snapshot.adbCommandCount, 3);
      expect(snapshot.journalSha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(snapshot.isSafe, isTrue);
      expect(delegate.commands, hasLength(3));
    },
  );

  test(
    'P269 Android auditing runner rejects destructive commands before delegation',
    () async {
      for (final command in const <List<String>>[
        <String>[
          '-s',
          'pixel-usb',
          'shell',
          'am',
          'start',
          '-n',
          'com.mknoon.app/com.mknoon.app.MainActivity',
        ],
        <String>['-s', 'pixel-usb', 'uninstall', 'dedicated.package'],
        <String>[
          '-s',
          'pixel-usb',
          'shell',
          'pm',
          'clear',
          'dedicated.package',
        ],
        <String>['-s', 'pixel-usb', 'shell', 'rm', '-rf', 'app_flutter'],
      ]) {
        final delegate = _RecordingAndroidHostRunner();
        final audit = GroupMediaAndroidCommandAudit();
        final runner = GroupMediaAndroidCommandAuditingRunner(
          delegate: delegate,
          audit: audit,
        );

        await expectLater(
          runner.run('adb', command),
          throwsA(isA<GroupMediaAndroidDisposableFailure>()),
        );
        expect(delegate.commands, isEmpty);
        expect(audit.snapshot.adbCommandCount, 1);
        expect(audit.snapshot.isSafe, isFalse);
      }
    },
  );

  test(
    'P269 iOS controller uses exact no-build selector Home host termination root relaunch and interrupted recovery',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final events = <String>[];
      final runner = _FakeCommandRunner(fixture, events: events);
      final systemLog = _FakeSystemLogCapture(events);
      final androidBoundary = _FakeAndroidDisposableBoundary(events: events);
      final controller = GroupMediaIosBackgroundRecoveryController(
        options: fixture.options,
        commandRunner: runner,
        systemLogCapture: systemLog,
        androidDisposableBoundary: androidBoundary,
      );

      final artifact = await controller.run();

      final validation = validateGroupMediaIosBackgroundRecoveryArtifact(
        artifact,
      );
      expect(validation.ok, isTrue, reason: validation.detail);
      expect((artifact['phase_a']! as Map)['terminal_path'], 'normal');
      expect((artifact['phase_b']! as Map)['terminal_path'], 'interrupted');
      expect((artifact['phase_b']! as Map)['resume_after_drain_attempts'], 1);
      expect((artifact['phase_b']! as Map)['ui_effects'], 1);
      expect(
        runner.labels,
        isNot(contains('protect-codesign-entitlements-ui-test-bundle')),
        reason:
            'the exactly signed nested xctest intentionally has no '
            'provisioned entitlement blob',
      );

      expect(runner.labels, <String>[
        'protect-run-directory',
        'adb-live-targets',
        'adb-sender-hardware',
        'ios-live-targets',
        'ios-coredevice-details',
        'codesign',
        'bundle-id',
        'codesign-entitlements',
        'protect-codesign-entitlements-runner',
        'decode-entitlements-runner',
        'protect-codesign-entitlements-runner-json',
        'codesign-verify-share-extension',
        'bundle-id-share-extension',
        'codesign-entitlements-share-extension',
        'protect-codesign-entitlements-share-extension',
        'decode-entitlements-share-extension',
        'protect-codesign-entitlements-share-extension-json',
        'codesign-verify-notification-service',
        'bundle-id-notification-service',
        'codesign-entitlements-notification-service',
        'protect-codesign-entitlements-notification-service',
        'decode-entitlements-notification-service',
        'protect-codesign-entitlements-notification-service-json',
        'codesign-verify-ui-test-host',
        'bundle-id-ui-test-host',
        'codesign-entitlements-ui-test-host',
        'protect-codesign-entitlements-ui-test-host',
        'decode-entitlements-ui-test-host',
        'protect-codesign-entitlements-ui-test-host-json',
        'codesign-verify-ui-test-bundle',
        'bundle-id-ui-test-bundle',
        'codesign-entitlements-ui-test-bundle',
        'decode-xctestrun',
        'encode-xctestrun',
        'install-prepared-app',
        'inspect-app-after-install',
        'protect-reset-pre-request',
        'stage-reset-pre',
        'launch-reset-pre',
        'pull-reset-pre',
        'inspect-process-terminate-reset-pre',
        'terminate-reset-pre',
        'inspect-app-after-pre-reset',
        'protect-auto-setup',
        'stage-auto-setup',
        'protect-system-log',
        'launch-root-before-proof',
        'xctest-without-building',
        'fixture-phase-a',
        'launch-root-after-phase-a',
        'fixture-phase-b-claim',
        'inspect-process-host-terminate-phase-b',
        'host-terminate-phase-b',
        'fixture-phase-b-observe',
        'protect-reset-post-request',
        'stage-reset-post',
        'launch-reset-post',
        'pull-reset-post',
        'inspect-process-terminate-reset-post',
        'terminate-reset-post',
        'inspect-app-after-post-reset',
        'inspect-app-after-cleanup',
      ]);
      expect(
        events.indexOf('system-log-start'),
        lessThan(events.indexOf('xctest-without-building')),
      );
      expect(
        events.indexOf('xctest-without-building'),
        lessThan(events.indexOf('fixture-phase-a')),
      );
      expect(
        events.indexOf('system-log-stop'),
        greaterThan(events.indexOf('fixture-phase-b-observe')),
      );
      expect(
        events.indexOf('stage-reset-post'),
        greaterThan(events.indexOf('system-log-stop')),
      );
      expect(systemLog.deviceId, _Fixture.receiverDeviceId);
      expect(systemLog.output, isNotNull);
      expect(systemLog.output!.existsSync(), isFalse);
      final patchedXctestrun =
          jsonDecode(
                File(
                  '${systemLog.output!.parent.path}/patched-xctestrun.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(
        (patchedXctestrun['RunnerUITests']!
            as Map)['UITargetAppBundleIdentifier'],
        groupMediaIosDisposableBundleId,
      );
      expect(
        File(
          '${systemLog.output!.parent.path}/fixture-state.json',
        ).existsSync(),
        isFalse,
      );

      final autoSetup = runner.commands.singleWhere(
        (command) => command.label == 'stage-auto-setup',
      );
      expect(
        autoSetup.arguments,
        containsAllInOrder(<String>[
          'copy',
          'to',
          '--device',
          _Fixture.receiverDeviceId,
          '--source',
        ]),
      );
      expect(autoSetup.arguments, contains('Documents/auto_setup.json'));
      expect(autoSetup.arguments, contains('appDataContainer'));
      expect(autoSetup.arguments, contains(groupMediaIosDisposableBundleId));
      for (final fixtureCommand in runner.commands.where(
        (command) => command.label.startsWith('fixture-phase-'),
      )) {
        expect(
          _argumentAfter(fixtureCommand.arguments, '--system-log'),
          systemLog.output!.absolute.path,
        );
        expect(
          _argumentAfter(fixtureCommand.arguments, '--android-artifact'),
          fixture.androidArtifact.absolute.path,
        );
        expect(
          _argumentAfter(fixtureCommand.arguments, '--android-artifact-sha256'),
          fixture.options.androidCompanionArtifactSha256,
        );
        expect(
          _argumentAfter(fixtureCommand.arguments, '--android-command-audit'),
          endsWith('-android-command-audit.json'),
        );
        expect(
          fixtureCommand.environment,
          isNot(contains(groupMediaAndroidDisposableArtifactEnvironment)),
        );
      }

      final xctest = runner.commands.singleWhere(
        (command) => command.label == 'xctest-without-building',
      );
      expect(xctest.executable, 'xcodebuild');
      expect(xctest.arguments.first, 'test-without-building');
      expect(
        xctest.arguments,
        contains(
          '-only-testing:RunnerUITests/'
          'GroupMediaBackgroundRecoveryUITests/'
          'testReceiverBackgroundRecovery',
        ),
      );
      expect(xctest.arguments, isNot(contains('build-for-testing')));
      expect(xctest.environment['SIMS_CHILD_BUILDS_FORBIDDEN'], '1');
      expect(
        (artifact['xctest']! as Map)['local_network_permission'],
        'automated_or_pregranted',
      );

      final terminate = runner.commands.singleWhere(
        (command) => command.label == 'host-terminate-phase-b',
      );
      expect(terminate.executable, 'xcrun');
      expect(
        terminate.arguments,
        containsAllInOrder(<String>[
          'devicectl',
          'device',
          'process',
          'terminate',
          '--device',
          _Fixture.receiverDeviceId,
          '--pid',
          '4242',
          '--kill',
        ]),
      );

      for (final launch in runner.commands.where(
        (command) => command.label.startsWith('launch-root'),
      )) {
        expect(launch.arguments, contains(groupMediaIosDisposableBundleId));
        expect(launch.arguments, isNot(contains('--payload-url')));
        expect(launch.arguments, isNot(contains('--route')));
      }
      final initialRootLaunch = runner.commands.singleWhere(
        (command) => command.label == 'launch-root-before-proof',
      );
      expect(initialRootLaunch.arguments, contains('--terminate-existing'));
      final phaseAForegroundActivation = runner.commands.singleWhere(
        (command) => command.label == 'launch-root-after-phase-a',
      );
      expect(phaseAForegroundActivation.arguments, contains('--activate'));
      expect(
        phaseAForegroundActivation.arguments,
        isNot(contains('--terminate-existing')),
        reason:
            'phase B must reuse the phase-A process that XCTest is bound to',
      );
      final serializedCommands = runner.commands
          .map(
            (command) => '${command.executable} ${command.arguments.join(' ')}',
          )
          .join('\n');
      expect(serializedCommands, isNot(contains('flutter build')));
      expect(serializedCommands, isNot(contains('build-for-testing')));
      expect(serializedCommands, isNot(contains(' sleep ')));
      expect(serializedCommands, isNot(contains('uninstall')));
      expect(serializedCommands, isNot(contains('com.mknoon.app')));
      final cleanup = artifact['cleanup']! as Map<String, Object?>;
      expect(cleanup['uninstall_commands'], 0);
      expect(cleanup['app_left_installed'], isTrue);
      expect(
        (cleanup['pre_reset']! as Map)['receipt_sha256'],
        runner.resetReceiptRawDigests['pre'],
      );
      expect(
        (cleanup['post_reset']! as Map)['receipt_sha256'],
        runner.resetReceiptRawDigests['post'],
      );
      final androidCleanup =
          cleanup['android_senders']! as Map<String, Object?>;
      expect(
        androidCleanup.keys,
        orderedEquals(<String>[
          'phase-a-background-success',
          'phase-b-stop-at-post-claim',
        ]),
      );
      for (final facts in androidCleanup.values.cast<Map>()) {
        expect(facts['uninstall_commands'], 0);
        expect(facts['pm_clear_commands'], 0);
        expect(facts['broad_delete_commands'], 0);
        expect(facts['app_left_installed'], isTrue);
        expect(
          (facts['pre_reset']! as Map)['receipt_sha256'],
          isNot((facts['post_reset']! as Map)['receipt_sha256']),
        );
      }
      final androidReceiptDigests = androidCleanup.values
          .cast<Map>()
          .expand(
            (facts) => <Object?>[
              (facts['pre_reset']! as Map)['receipt_sha256'],
              (facts['post_reset']! as Map)['receipt_sha256'],
            ],
          )
          .toSet();
      expect(androidReceiptDigests, hasLength(4));
      expect(androidBoundary.actions, <String>[
        'prepare:phase-a-background-success',
        'cleanup:phase-a-background-success',
        'prepare:phase-b-stop-at-post-claim',
        'cleanup:phase-b-stop-at-post-claim',
      ]);
    },
  );

  test(
    'P269 iOS controller rejects a destructive fixture command audit instead of publishing zero counts',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final runner = _FakeCommandRunner(fixture, destructiveFixtureAudit: true);

      await expectLater(
        GroupMediaIosBackgroundRecoveryController(
          options: fixture.options,
          commandRunner: runner,
          systemLogCapture: _FakeSystemLogCapture(<String>[]),
          androidDisposableBoundary: _FakeAndroidDisposableBoundary(),
        ).run(),
        throwsA(isA<GroupMediaIosBackgroundRecoveryFailure>()),
      );
      expect(runner.labels, contains('fixture-phase-a'));
      expect(
        runner.labels.indexOf('xctest-without-building'),
        lessThan(runner.labels.indexOf('fixture-phase-a')),
      );
    },
  );

  test(
    'P269 iOS controller rejects wireless and emulator Android senders before iOS mutation',
    () async {
      final wirelessFixture = await _Fixture.create();
      addTearDown(wirelessFixture.dispose);
      final wirelessRunner = _FakeCommandRunner(
        wirelessFixture,
        androidUsbTransport: false,
      );
      await expectLater(
        GroupMediaIosBackgroundRecoveryController(
          options: wirelessFixture.options,
          commandRunner: wirelessRunner,
          androidDisposableBoundary: _FakeAndroidDisposableBoundary(),
        ).run(),
        throwsA(
          isA<GroupMediaIosBackgroundRecoveryBlocked>().having(
            (error) => error.blocker,
            'blocker',
            'targetUnavailable',
          ),
        ),
      );
      expect(wirelessRunner.labels, <String>[
        'protect-run-directory',
        'adb-live-targets',
      ]);

      final emulatorFixture = await _Fixture.create();
      addTearDown(emulatorFixture.dispose);
      final emulatorRunner = _FakeCommandRunner(
        emulatorFixture,
        androidReportsQemu: true,
      );
      await expectLater(
        GroupMediaIosBackgroundRecoveryController(
          options: emulatorFixture.options,
          commandRunner: emulatorRunner,
          androidDisposableBoundary: _FakeAndroidDisposableBoundary(),
        ).run(),
        throwsA(
          isA<GroupMediaIosBackgroundRecoveryBlocked>().having(
            (error) => error.blocker,
            'blocker',
            'targetUnavailable',
          ),
        ),
      );
      expect(emulatorRunner.labels, <String>[
        'protect-run-directory',
        'adb-live-targets',
        'adb-sender-hardware',
      ]);
    },
  );

  test(
    'P269 iOS controller fails closed on missing prepared artifacts fixture driver and physical targets',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);

      final missingBundle = GroupMediaIosBackgroundRecoveryController(
        options: fixture.options.copyWith(
          preparedBundle: Directory('${fixture.root.path}/missing.bundle'),
        ),
        commandRunner: _FakeCommandRunner(fixture),
        androidDisposableBoundary: _FakeAndroidDisposableBoundary(),
      );
      await expectLater(
        missingBundle.run(),
        throwsA(
          isA<GroupMediaIosBackgroundRecoveryBlocked>().having(
            (error) => error.blocker,
            'blocker',
            'missingArtifact',
          ),
        ),
      );

      final missingDriver = GroupMediaIosBackgroundRecoveryController(
        options: fixture.options.copyWith(
          fixtureDriver: File('${fixture.root.path}/missing-driver'),
        ),
        commandRunner: _FakeCommandRunner(fixture),
        androidDisposableBoundary: _FakeAndroidDisposableBoundary(),
      );
      await expectLater(
        missingDriver.run(),
        throwsA(
          isA<GroupMediaIosBackgroundRecoveryBlocked>().having(
            (error) => error.blocker,
            'blocker',
            'missingDriver',
          ),
        ),
      );

      final absentIos = _FakeCommandRunner(fixture, exposeIosTarget: false);
      final absentIosController = GroupMediaIosBackgroundRecoveryController(
        options: fixture.options,
        commandRunner: absentIos,
        androidDisposableBoundary: _FakeAndroidDisposableBoundary(),
      );
      await expectLater(
        absentIosController.run(),
        throwsA(
          isA<GroupMediaIosBackgroundRecoveryBlocked>().having(
            (error) => error.blocker,
            'blocker',
            'targetUnavailable',
          ),
        ),
      );
      expect(absentIos.labels, <String>[
        'protect-run-directory',
        'adb-live-targets',
        'adb-sender-hardware',
        'ios-live-targets',
      ]);
    },
  );

  test(
    'P269 iOS fixture custody rejects wrong executable symlink and post-preflight mutation',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final wrongDriver = File('${fixture.root.path}/wrong-driver')
        ..writeAsStringSync('#!/bin/sh\nexit 0\n');
      final chmod = await Process.run('chmod', <String>[
        '700',
        wrongDriver.path,
      ]);
      expect(chmod.exitCode, 0);

      final wrongRunner = _FakeCommandRunner(fixture);
      await expectLater(
        GroupMediaIosBackgroundRecoveryController(
          options: fixture.options.copyWith(fixtureDriver: wrongDriver),
          commandRunner: wrongRunner,
          androidDisposableBoundary: _FakeAndroidDisposableBoundary(),
        ).run(),
        throwsA(
          isA<GroupMediaIosBackgroundRecoveryBlocked>().having(
            (error) => error.blocker,
            'blocker',
            'missingDriver',
          ),
        ),
      );
      expect(wrongRunner.labels, isEmpty);

      final linkedDriver = Link('${fixture.root.path}/linked-driver');
      await linkedDriver.create(fixture.driver.path);
      final linkRunner = _FakeCommandRunner(fixture);
      await expectLater(
        GroupMediaIosBackgroundRecoveryController(
          options: fixture.options.copyWith(
            fixtureDriver: File(linkedDriver.path),
          ),
          commandRunner: linkRunner,
          androidDisposableBoundary: _FakeAndroidDisposableBoundary(),
        ).run(),
        throwsA(
          isA<GroupMediaIosBackgroundRecoveryBlocked>().having(
            (error) => error.blocker,
            'blocker',
            'missingDriver',
          ),
        ),
      );
      expect(linkRunner.labels, isEmpty);

      final isolatedTrusted = File('${fixture.root.path}/isolated-driver')
        ..writeAsBytesSync(fixture.driver.readAsBytesSync());
      final trustedChmod = await Process.run('chmod', <String>[
        '700',
        isolatedTrusted.path,
      ]);
      expect(trustedChmod.exitCode, 0);
      final custody = GroupMediaIosFixtureDriverCustody.capture(
        candidate: isolatedTrusted,
        trustedDriver: isolatedTrusted,
      );
      isolatedTrusted.writeAsStringSync('#!/bin/sh\nexit 99\n', flush: true);
      expect(
        custody.verifyUnchanged,
        throwsA(isA<GroupMediaIosBackgroundRecoveryFailure>()),
      );
    },
  );

  test(
    'P269 iOS controller re-attests the prepared bundle immediately before install',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final runner = _FakeCommandRunner(
        fixture,
        mutatePreparedBundleBeforeInstall: true,
      );

      await expectLater(
        GroupMediaIosBackgroundRecoveryController(
          options: fixture.options,
          commandRunner: runner,
          androidDisposableBoundary: _FakeAndroidDisposableBoundary(),
        ).run(),
        throwsA(
          isA<GroupMediaIosBackgroundRecoveryBlocked>()
              .having((error) => error.blocker, 'blocker', 'missingArtifact')
              .having(
                (error) => error.detail,
                'detail',
                contains('pre-install'),
              ),
        ),
      );
      expect(runner.labels, contains('encode-xctestrun'));
      expect(runner.labels, isNot(contains('install-prepared-app')));
    },
  );

  test(
    'P269 iOS controller suppresses publication when the prepared bundle changes during proof',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final runner = _FakeCommandRunner(
        fixture,
        mutatePreparedBundleBeforePublication: true,
      );

      await expectLater(
        GroupMediaIosBackgroundRecoveryController(
          options: fixture.options,
          commandRunner: runner,
          systemLogCapture: _FakeSystemLogCapture(<String>[]),
          androidDisposableBoundary: _FakeAndroidDisposableBoundary(),
        ).run(),
        throwsA(
          isA<GroupMediaIosBackgroundRecoveryBlocked>()
              .having((error) => error.blocker, 'blocker', 'missingArtifact')
              .having(
                (error) => error.detail,
                'detail',
                contains('artifact-publication'),
              ),
        ),
      );
      expect(runner.labels, contains('install-prepared-app'));
      expect(runner.labels, contains('inspect-app-after-cleanup'));
    },
  );

  test(
    'P269 iOS controller rejects an unbound dedicated receiver before device mutation',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);

      for (final environment in <Map<String, String>>[
        const <String, String>{
          'MKNOON_RELAY_ADDRESSES': '/dns/relay.invalid/tcp/443/wss',
        },
        const <String, String>{
          'MKNOON_RELAY_ADDRESSES': '/dns/relay.invalid/tcp/443/wss',
          groupMediaIosDedicatedDisposableDeviceEnvironment: 'another-device',
        },
      ]) {
        final runner = _FakeCommandRunner(fixture);
        final controller = GroupMediaIosBackgroundRecoveryController(
          options: fixture.options.copyWith(inheritedEnvironment: environment),
          commandRunner: runner,
          systemLogCapture: _FakeSystemLogCapture(<String>[]),
          androidDisposableBoundary: _FakeAndroidDisposableBoundary(),
        );
        await expectLater(
          controller.run(),
          throwsA(
            isA<GroupMediaIosBackgroundRecoveryBlocked>().having(
              (error) => error.blocker,
              'blocker',
              'deviceState',
            ),
          ),
        );
        expect(
          runner.commands,
          isEmpty,
          reason: 'authorization must fail before any host/device command',
        );
      }
    },
  );

  test(
    'P269 iOS controller rejects non-allowlisted entitlements before install and refuses a same-PID wrong executable before kill',
    () async {
      final entitlementFixture = await _Fixture.create();
      addTearDown(entitlementFixture.dispose);
      final unsafeRunner = _FakeCommandRunner(
        entitlementFixture,
        unsafeEntitlementsFor: 'runner',
      );
      await expectLater(
        GroupMediaIosBackgroundRecoveryController(
          options: entitlementFixture.options,
          commandRunner: unsafeRunner,
          androidDisposableBoundary: _FakeAndroidDisposableBoundary(),
        ).run(),
        throwsA(isA<GroupMediaIosBackgroundRecoveryBlocked>()),
      );
      expect(unsafeRunner.labels, isNot(contains('install-prepared-app')));

      final processFixture = await _Fixture.create();
      addTearDown(processFixture.dispose);
      final processRunner = _FakeCommandRunner(
        processFixture,
        mismatchedProcessOwner: true,
      );
      await expectLater(
        GroupMediaIosBackgroundRecoveryController(
          options: processFixture.options,
          commandRunner: processRunner,
          androidDisposableBoundary: _FakeAndroidDisposableBoundary(),
        ).run(),
        throwsA(isA<GroupMediaIosBackgroundRecoveryBlocked>()),
      );
      expect(
        processRunner.labels,
        contains('inspect-process-terminate-reset-pre'),
      );
      expect(processRunner.labels, isNot(contains('terminate-reset-pre')));

      final nonFileFixture = await _Fixture.create();
      addTearDown(nonFileFixture.dispose);
      final nonFileRunner = _FakeCommandRunner(
        nonFileFixture,
        nonFileProcessExecutable: true,
      );
      await expectLater(
        GroupMediaIosBackgroundRecoveryController(
          options: nonFileFixture.options,
          commandRunner: nonFileRunner,
          androidDisposableBoundary: _FakeAndroidDisposableBoundary(),
        ).run(),
        throwsA(isA<GroupMediaIosBackgroundRecoveryBlocked>()),
      );
      expect(
        nonFileRunner.labels,
        contains('inspect-process-terminate-reset-pre'),
      );
      expect(nonFileRunner.labels, isNot(contains('terminate-reset-pre')));
    },
  );

  test(
    'P269 iOS controller rejects absent mandatory and empty signed entitlements before install',
    () async {
      for (final label in const <String>[
        'runner',
        'share-extension',
        'notification-service',
        'ui-test-host',
      ]) {
        final missingFixture = await _Fixture.create();
        addTearDown(missingFixture.dispose);
        final missingRunner = _FakeCommandRunner(
          missingFixture,
          omittedEntitlements: <String>{label},
        );
        await expectLater(
          GroupMediaIosBackgroundRecoveryController(
            options: missingFixture.options,
            commandRunner: missingRunner,
            androidDisposableBoundary: _FakeAndroidDisposableBoundary(),
          ).run(),
          throwsA(
            isA<GroupMediaIosBackgroundRecoveryBlocked>().having(
              (error) => error.blocker,
              'blocker',
              'missingArtifact',
            ),
          ),
        );
        expect(
          missingRunner.labels,
          isNot(contains('install-prepared-app')),
          reason: label,
        );
        expect(
          missingRunner.labels,
          contains(
            label == 'runner'
                ? 'codesign-entitlements'
                : 'codesign-entitlements-$label',
          ),
          reason: label,
        );
      }

      final emptyFixture = await _Fixture.create();
      addTearDown(emptyFixture.dispose);
      final emptyRunner = _FakeCommandRunner(
        emptyFixture,
        emptyDecodedEntitlementsFor: 'runner',
      );
      await expectLater(
        GroupMediaIosBackgroundRecoveryController(
          options: emptyFixture.options,
          commandRunner: emptyRunner,
          androidDisposableBoundary: _FakeAndroidDisposableBoundary(),
        ).run(),
        throwsA(
          isA<GroupMediaIosBackgroundRecoveryBlocked>().having(
            (error) => error.blocker,
            'blocker',
            'missingArtifact',
          ),
        ),
      );
      expect(emptyRunner.labels, isNot(contains('install-prepared-app')));
    },
  );

  test(
    'P269 iOS controller permits absent UI-test entitlements only for an exactly verified signed identity',
    () async {
      for (final failure in const <String>['signature', 'identifier', 'team']) {
        final fixture = await _Fixture.create();
        addTearDown(fixture.dispose);
        final runner = _FakeCommandRunner(
          fixture,
          invalidCodeSignatureFor: failure == 'signature'
              ? 'ui-test-bundle'
              : null,
          mismatchedSignatureIdentifierFor: failure == 'identifier'
              ? 'ui-test-bundle'
              : null,
          mismatchedSignatureTeamFor: failure == 'team'
              ? 'ui-test-bundle'
              : null,
        );

        await expectLater(
          GroupMediaIosBackgroundRecoveryController(
            options: fixture.options,
            commandRunner: runner,
            androidDisposableBoundary: _FakeAndroidDisposableBoundary(),
          ).run(),
          throwsA(
            isA<GroupMediaIosBackgroundRecoveryBlocked>().having(
              (error) => error.blocker,
              'blocker',
              'missingArtifact',
            ),
          ),
        );
        expect(
          runner.labels,
          isNot(contains('install-prepared-app')),
          reason: failure,
        );
        expect(
          runner.labels,
          contains('codesign-verify-ui-test-bundle'),
          reason: failure,
        );
        if (failure != 'signature') {
          expect(
            runner.labels,
            contains('codesign-entitlements-ui-test-bundle'),
            reason: failure,
          );
        }
      }
    },
  );

  test(
    'P269 iOS controller rejects present unsafe UI-test entitlements and non-absent empty or linked blobs',
    () async {
      for (final malformed in const <String>[
        'unsafe',
        'zero-length',
        'dangling-symlink',
      ]) {
        final fixture = await _Fixture.create();
        addTearDown(fixture.dispose);
        final runner = _FakeCommandRunner(
          fixture,
          omittedEntitlements: const <String>{},
          unsafeEntitlementsFor: malformed == 'unsafe'
              ? 'ui-test-bundle'
              : null,
          zeroLengthEntitlementsFor: malformed == 'zero-length'
              ? 'ui-test-bundle'
              : null,
          danglingSymlinkEntitlementsFor: malformed == 'dangling-symlink'
              ? 'ui-test-bundle'
              : null,
        );

        await expectLater(
          GroupMediaIosBackgroundRecoveryController(
            options: fixture.options,
            commandRunner: runner,
            androidDisposableBoundary: _FakeAndroidDisposableBoundary(),
          ).run(),
          throwsA(
            isA<GroupMediaIosBackgroundRecoveryBlocked>().having(
              (error) => error.blocker,
              'blocker',
              'missingArtifact',
            ),
          ),
        );
        expect(
          runner.labels,
          isNot(contains('install-prepared-app')),
          reason: malformed,
        );
        expect(
          runner.labels,
          contains('codesign-entitlements-ui-test-bundle'),
          reason: malformed,
        );
        if (malformed == 'unsafe') {
          expect(runner.labels, contains('decode-entitlements-ui-test-bundle'));
        }
      }
    },
  );

  test(
    'P269 iOS controller suppresses a valid artifact when final reset fails',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final events = <String>[];
      final runner = _FakeCommandRunner(
        fixture,
        failPostReset: true,
        events: events,
      );
      final androidBoundary = _FakeAndroidDisposableBoundary(events: events);
      final controller = GroupMediaIosBackgroundRecoveryController(
        options: fixture.options,
        commandRunner: runner,
        systemLogCapture: _FakeSystemLogCapture(events),
        androidDisposableBoundary: androidBoundary,
      );

      await expectLater(
        controller.run(),
        throwsA(isA<GroupMediaIosBackgroundRecoveryFailure>()),
      );
      expect(events, contains('system-log-stop'));
      expect(events, contains('stage-reset-post'));
      expect(events, contains('inspect-app-after-cleanup'));
      expect(
        events.indexOf('inspect-app-after-cleanup'),
        greaterThan(events.indexOf('stage-reset-post')),
      );
      expect(androidBoundary.actions, <String>[
        'prepare:phase-a-background-success',
        'cleanup:phase-a-background-success',
        'prepare:phase-b-stop-at-post-claim',
        'cleanup:phase-b-stop-at-post-claim',
      ]);
    },
  );

  test(
    'P269 iOS controller still resets and leaves the app installed when log shutdown fails',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final events = <String>[];
      final runner = _FakeCommandRunner(fixture, events: events);
      final androidBoundary = _FakeAndroidDisposableBoundary(events: events);
      final controller = GroupMediaIosBackgroundRecoveryController(
        options: fixture.options,
        commandRunner: runner,
        systemLogCapture: _FakeSystemLogCapture(events, failStop: true),
        androidDisposableBoundary: androidBoundary,
      );

      await expectLater(
        controller.run(),
        throwsA(isA<GroupMediaIosBackgroundRecoveryFailure>()),
      );
      expect(
        events,
        containsAllInOrder(<String>[
          'system-log-stop',
          'stage-reset-post',
          'inspect-app-after-post-reset',
          'inspect-app-after-cleanup',
        ]),
      );
      expect(androidBoundary.actions, <String>[
        'prepare:phase-a-background-success',
        'cleanup:phase-a-background-success',
        'prepare:phase-b-stop-at-post-claim',
        'cleanup:phase-b-stop-at-post-claim',
      ]);
    },
  );

  test(
    'P269 iOS failed XCTest cancels and settles a foreground fixture before cleanup',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final events = <String>[];
      final runner = _FakeCommandRunner(
        fixture,
        failXctestBeforeHome: true,
        events: events,
      );
      final androidBoundary = _FakeAndroidDisposableBoundary(events: events);
      final controller = GroupMediaIosBackgroundRecoveryController(
        options: fixture.options,
        commandRunner: runner,
        systemLogCapture: _FakeSystemLogCapture(events),
        androidDisposableBoundary: androidBoundary,
      );

      await expectLater(
        controller.run(),
        throwsA(isA<GroupMediaIosBackgroundRecoveryFailure>()),
      );
      expect(
        events,
        containsAllInOrder(<String>[
          'xctest-without-building',
          'android-prepare:phase-a-background-success',
          'fixture-phase-a',
          'fixture-cancel-observed',
          'android-cleanup:phase-a-background-success',
          'system-log-stop',
          'stage-reset-post',
          'inspect-app-after-post-reset',
          'inspect-app-after-cleanup',
        ]),
      );
      expect(androidBoundary.actions, <String>[
        'prepare:phase-a-background-success',
        'cleanup:phase-a-background-success',
      ]);
      final runDirectory = Directory(
        '${fixture.proofDirectory.path}/ios-${_Fixture.runId}',
      );
      expect(
        File('${runDirectory.path}/fixture-cancel.json').existsSync(),
        isFalse,
      );
      expect(
        File('${runDirectory.path}/physical-idevicesyslog.log').existsSync(),
        isFalse,
      );
    },
  );

  test(
    'P269 iOS evidence rejects ambiguous terminal manual sleep-only and duplicate effects',
    () async {
      final fixture = await _Fixture.create();
      addTearDown(fixture.dispose);
      final artifact = await GroupMediaIosBackgroundRecoveryController(
        options: fixture.options,
        commandRunner: _FakeCommandRunner(fixture),
        systemLogCapture: _FakeSystemLogCapture(<String>[]),
        androidDisposableBoundary: _FakeAndroidDisposableBoundary(),
      ).run();
      expect(
        validateGroupMediaIosBackgroundRecoveryArtifact(artifact).ok,
        isTrue,
      );

      for (final mutation in <Map<String, Object?> Function()>[
        () => _mutate(artifact, 'phase_b', 'terminal_path', 'expired'),
        () => _mutate(artifact, 'phase_b', 'terminal_path', 'normal'),
        () => _mutate(artifact, 'phase_b', 'resume_after_drain_attempts', 2),
        () => _mutate(artifact, 'phase_b', 'ui_effects', 2),
        () => _mutate(artifact, 'phase_b', 'relaunch_route', 'group'),
        () => _mutate(artifact, 'xctest', 'home_presses', 1),
        () => _mutate(artifact, 'xctest', 'manual_steps', 1),
        () => _mutate(artifact, 'xctest', 'sleep_only_waits', 1),
        () => _mutate(artifact, 'cleanup', 'uninstall_commands', 1),
        () => _mutate(artifact, 'cleanup', 'app_left_installed', false),
        () {
          final changed = _deepCopy(artifact);
          final cleanup = changed['cleanup']! as Map<String, Object?>;
          final senders = cleanup['android_senders']! as Map<String, Object?>;
          final phaseA =
              senders['phase-a-background-success']! as Map<String, Object?>;
          phaseA['pm_clear_commands'] = 1;
          return changed;
        },
        () {
          final changed = _deepCopy(artifact);
          final cleanup = changed['cleanup']! as Map<String, Object?>;
          final senders = cleanup['android_senders']! as Map<String, Object?>;
          final phaseB =
              senders['phase-b-stop-at-post-claim']! as Map<String, Object?>;
          phaseB['broad_delete_commands'] = 1;
          return changed;
        },
        () {
          final changed = _deepCopy(artifact);
          final cleanup = changed['cleanup']! as Map<String, Object?>;
          final senders = cleanup['android_senders']! as Map<String, Object?>;
          final phaseA =
              senders['phase-a-background-success']! as Map<String, Object?>;
          final pre = phaseA['pre_reset']! as Map<String, Object?>;
          final post = phaseA['post_reset']! as Map<String, Object?>;
          post['receipt_sha256'] = pre['receipt_sha256'];
          return changed;
        },
        () {
          final changed = _deepCopy(artifact);
          final cleanup = changed['cleanup']! as Map<String, Object?>;
          final senders = cleanup['android_senders']! as Map<String, Object?>;
          final phaseA =
              senders['phase-a-background-success']! as Map<String, Object?>;
          final phaseB =
              senders['phase-b-stop-at-post-claim']! as Map<String, Object?>;
          (phaseB['pre_reset']! as Map<String, Object?>)['receipt_sha256'] =
              (phaseA['pre_reset']! as Map<String, Object?>)['receipt_sha256'];
          return changed;
        },
        () {
          final changed = _deepCopy(artifact);
          final cleanup = changed['cleanup']! as Map<String, Object?>;
          final post = cleanup['post_reset']! as Map<String, Object?>;
          post['phase'] = 'pre';
          return changed;
        },
        () {
          final changed = _deepCopy(artifact);
          final observations =
              changed['boundary_observations']! as Map<String, Object?>;
          final phase =
              observations['phase_b_recovery']! as Map<String, Object?>;
          final native = phase['native']! as Map<String, Object?>;
          native['source'] = 'runner_echo';
          phase['native_sha256'] = groupMediaIosObservationDigest(native);
          return changed;
        },
        () {
          final changed = _deepCopy(artifact);
          final observations =
              changed['boundary_observations']! as Map<String, Object?>;
          final phase =
              observations['phase_b_recovery']! as Map<String, Object?>;
          final database = phase['database']! as Map<String, Object?>;
          database['database_reopened'] = false;
          phase['database_sha256'] = groupMediaIosObservationDigest(database);
          return changed;
        },
        () {
          final changed = _deepCopy(artifact);
          final observations =
              changed['boundary_observations']! as Map<String, Object?>;
          final phase = observations['phase_b_claim']! as Map<String, Object?>;
          phase['database_sha256'] = List<String>.filled(64, '0').join();
          return changed;
        },
        () {
          final changed = _deepCopy(artifact);
          (changed['flow_events']! as List<Object?>).add(
            'phase_b_effect_visible',
          );
          return changed;
        },
      ]) {
        final changed = mutation();
        expect(
          validateGroupMediaIosBackgroundRecoveryArtifact(changed).ok,
          isFalse,
          reason: jsonEncode(changed),
        );
      }
    },
  );

  test(
    'P269 iOS UI source owns two Home presses and a route-free relaunch without a timer fallback',
    () {
      final source = File(
        'ios/RunnerUITests/GroupMediaBackgroundRecoveryUITests.swift',
      ).readAsStringSync();
      expect(
        source,
        contains('final class GroupMediaBackgroundRecoveryUITests'),
      );
      expect(source, contains('func testReceiverBackgroundRecovery() throws'));
      expect(source, contains('prepareLocalNetworkPermission(for: app)'));
      expect(source, contains('emit("local_network_permission_ready")'));
      expect(source, contains('label CONTAINS[c] %@'));
      expect(source, contains('"local network"'));
      expect(source, contains('app.buttons["Allow"]'));
      expect(source, contains('springboard.buttons["Allow"]'));
      expect(
        source,
        contains(
          'private let dedicatedBundleId = "com.mknoon.sims.groupmedia269"',
        ),
      );
      expect(source, contains('XCTAssertEqual(bundleId, dedicatedBundleId)'));
      expect(source, contains('XCTAssertNotEqual(bundleId, "com.mknoon.app")'));
      expect(
        RegExp(r'XCUIDevice\.shared\.press\(\.home\)').allMatches(source),
        hasLength(2),
      );
      expect(source, contains('app.launchArguments = []'));
      expect(source, contains('app.launchEnvironment = [:]'));
      expect(source, contains('phase_b_relaunch_root_without_group'));
      expect(source, contains('phase_b_effect_once'));
      expect(source, isNot(contains('Thread.sleep')));
      expect(source, isNot(contains('sleep(')));
      expect(source.toLowerCase(), isNot(contains('manual')));

      final driver = File(
        'integration_test/scripts/group_media_ios_fixture_driver.dart',
      ).readAsStringSync();
      final phaseA = driver.substring(
        driver.indexOf('Future<void> _phaseA()'),
        driver.indexOf('Future<void> _phaseBClaim()'),
      );
      final phaseB = driver.substring(
        driver.indexOf('Future<void> _phaseBClaim()'),
        driver.indexOf('Future<void> _phaseBRecovery()'),
      );
      for (final source in <String>[phaseA, phaseB]) {
        final stageCall = source.indexOf('await _stageIosReceiverObservation(');
        expect(stageCall, isNonNegative);
        expect(source.indexOf('_setupPhase('), lessThan(stageCall));
        expect(stageCall, lessThan(source.indexOf('await _writeReady(')));
        expect(
          source.indexOf('await _writeReady('),
          lessThan(source.indexOf('await _waitForHome(')),
        );
        expect(
          source.indexOf('await _waitForHome('),
          lessThan(source.indexOf('await _sendPhase(')),
        );
        expect(
          source.indexOf('await _sendPhase('),
          lessThan(source.indexOf('_awaitEndpointResult(')),
        );
      }

      final stageObservation = driver.substring(
        driver.indexOf('Future<void> _stageIosReceiverObservation('),
        driver.indexOf('Future<Map<String, Object?>> _awaitEndpointResult('),
      );
      expect(
        stageObservation.indexOf("await _writeIosFile('intro_e2e_config.json'"),
        lessThan(stageObservation.indexOf('await _awaitEndpointResult(')),
      );
      expect(stageObservation, contains('foregroundAcceptanceOnly: true'));

      final awaitResult = driver.substring(
        driver.indexOf('Future<Map<String, Object?>> _awaitEndpointResult('),
        driver.indexOf('bool _isForegroundObservationAcceptance('),
      );
      expect(
        awaitResult,
        matches(
          RegExp(
            r'if \(foregroundAccepted\) \{\s*'
            r'await Future<void>\.delayed\([^;]+;\s*'
            r'continue;\s*\}',
          ),
        ),
      );
      expect(
        awaitResult.indexOf('if (foregroundAccepted)'),
        lessThan(
          awaitResult.indexOf(
            "result['success'] != true || result['status'] != 'complete'",
          ),
        ),
      );
      expect(
        awaitResult.indexOf(
          "result['success'] != true || result['status'] != 'complete'",
        ),
        lessThan(awaitResult.lastIndexOf('return result;')),
      );
      expect(driver, contains("result['foregroundArmComplete'] == true"));
      expect(driver, contains("'phase-a-background-success'"));
      expect(driver, contains("'phase-b-stop-at-post-claim'"));
      expect(driver, contains("'phase-b-observe-recovery'"));
      expect(driver, contains('MKNOON_269_IOS_NATIVE event=home_background'));
      expect(driver, contains('GroupMediaAndroidCommandAuditingRunner('));
      expect(driver, contains("'adb_command_count': snapshot.adbCommandCount"));
      expect(driver, contains("'journal_sha256': snapshot.journalSha256"));
      expect(driver, isNot(contains('syntheticReceipt')));

      final project = File(
        'ios/Runner.xcodeproj/project.pbxproj',
      ).readAsStringSync();
      expect(
        RegExp(
          r'GroupMediaBackgroundRecoveryUITests\.swift in Sources',
        ).allMatches(project),
        hasLength(2),
      );
    },
  );

  test(
    'P269 production entry causally wires observation acceptance and the shared receive-task reservation',
    () {
      final intro = File(
        'lib/core/debug/intro_e2e_runner.dart',
      ).readAsStringSync();
      final introBranch = intro.substring(
        intro.indexOf(
          "if (config['transport_action'] == "
          'groupMediaIosBackgroundE2EAction)',
        ),
        intro.indexOf(
          '// The signed physical-iOS production profile exposes only',
        ),
      );
      expect(introBranch, contains('onReceiverObservationAccepted:'));
      expect(introBranch, contains('onReceiverObservationComplete:'));
      expect(
        RegExp(
          r'groupMediaIosBackgroundE2EAcceptedReceipt\(\s*'
          r'config:\s*config',
        ).allMatches(introBranch),
        hasLength(1),
      );
      expect(
        introBranch.indexOf('onReceiverObservationAccepted:'),
        lessThan(
          introBranch.indexOf('groupMediaIosBackgroundE2EAcceptedReceipt('),
        ),
      );
      expect(
        introBranch,
        isNot(
          contains("if (config['phase'] == groupMediaIosReceiverObservePhase)"),
        ),
      );

      final productionSource = File(
        'lib/app/bootstrap/production_application_bootstrap.dart',
      ).readAsStringSync();
      final compositionSource = File(
        'lib/debug/debug_e2e_composition_root.dart',
      ).readAsStringSync();
      final compositionEntryStart = compositionSource.indexOf(
        'runGroupMediaIosBackgroundE2E:',
      );
      final compositionEntry = compositionSource.substring(
        compositionEntryStart,
        compositionSource.indexOf('resolveWakeToken:', compositionEntryStart),
      );
      expect(
        productionSource,
        contains('if (debugE2EComposition?.startsIntroPoller ?? false) {'),
      );
      expect(
        productionSource,
        contains('debugE2EComposition!.startIntroPollerAfterColdRecovery('),
      );
      expect(
        compositionEntry,
        matches(
          RegExp(
            r'onReceiverObservationAccepted:\s*'
            r'onReceiverObservationAccepted',
          ),
        ),
      );
      expect(
        compositionEntry,
        matches(
          RegExp(
            r'onReceiverObservationComplete:\s*'
            r'onReceiverObservationComplete',
          ),
        ),
      );
      expect(compositionEntry, contains('reserveReceiveCriticalTask:'));
      expect(
        compositionEntry,
        matches(
          RegExp(
            r'groupMessageListener\s*'
            r'\.reserveGroupMediaReceiveCriticalTaskForForegroundHandoff',
          ),
        ),
      );
      expect(compositionEntry, contains('return reservation.release;'));

      final actionSource = File(
        'lib/core/debug/group_media_ios_background_e2e.dart',
      ).readAsStringSync();
      final action = actionSource.substring(
        actionSource.indexOf(
          'Future<Map<String, Object?>> '
          'runGroupMediaIosBackgroundE2EAction({',
        ),
        actionSource.indexOf(
          '/// Exact release-mode exception for the signed physical-iOS',
        ),
      );
      expect(action, contains('onReceiverObservationAccepted'));
      expect(action, contains('onReceiverObservationComplete'));
      expect(action, contains('reserveReceiveCriticalTask'));
      final observeCase = action.substring(
        action.indexOf('case groupMediaIosReceiverObservePhase:'),
        action.indexOf('case groupMediaIosReceiverRecoverPhase:'),
      );
      expect(observeCase, contains('onReceiverObservationAccepted'));
      expect(observeCase, contains('onReceiverObservationComplete'));
      expect(observeCase, contains('reserveReceiveCriticalTask'));
    },
  );

  test(
    'P269 native Home marker binds each XCUIApplication PID after physical background',
    () {
      final source = File(
        'ios/RunnerUITests/GroupMediaBackgroundRecoveryUITests.swift',
      ).readAsStringSync();

      expect(source, contains('let phaseAProcessId = app.processID'));
      expect(source, contains('let phaseBProcessId = app.processID'));
      expect(source, contains('emitNativeHome(processId: phaseAProcessId)'));
      expect(source, contains('emitNativeHome(processId: phaseBProcessId)'));
      expect(
        RegExp(
          r'MKNOON_269_IOS_NATIVE event=home_background pid=%d',
        ).allMatches(source),
        hasLength(1),
      );
      expect(
        source.indexOf('emitNativeHome(processId: phaseAProcessId)'),
        lessThan(source.indexOf('emit("phase_a_home")')),
      );
      expect(
        source.indexOf('emitNativeHome(processId: phaseBProcessId)'),
        lessThan(source.indexOf('emit("phase_b_home")')),
      );
      expect(
        File('ios/Runner/Info.plist').readAsStringSync(),
        contains('<string>FlutterSceneDelegate</string>'),
      );
      expect(
        File('ios/Runner/AppDelegate.swift').readAsStringSync(),
        isNot(
          contains('@objc class MknoonSceneDelegate: FlutterSceneDelegate'),
        ),
      );
      final appDelegate = File(
        'ios/Runner/AppDelegate.swift',
      ).readAsStringSync();
      expect(
        appDelegate,
        isNot(contains('event=home_background')),
        reason:
            'only the post-XCUIApplication-background marker may satisfy the '
            'exactly-once Home observation',
      );
      expect(appDelegate, contains('event=app_did_enter_background'));
    },
  );

  test(
    'P269 Runner native proof events use a public persistent unified log boundary',
    () {
      final appDelegate = File(
        'ios/Runner/AppDelegate.swift',
      ).readAsStringSync();
      final goBridge = File('ios/Runner/GoBridge.swift').readAsStringSync();

      expect(appDelegate, contains('import os.log'));
      expect(appDelegate, contains('func logGroupMediaNativeProof('));
      expect(appDelegate, contains('os_log("%{public}@"'));
      expect(
        RegExp(
          r'logGroupMediaNativeProof\(\s*'
          r'"MKNOON_269_IOS_NATIVE event=',
        ).allMatches(appDelegate),
        hasLength(2),
      );
      expect(
        goBridge,
        contains('eventLogger: @escaping (String) -> Void = { message in'),
      );
      expect(goBridge, contains('logGroupMediaNativeProof(message)'));
      expect(
        RegExp(
          r'logGroupMediaNativeProof\(\s*'
          r'"\[GoBridge\] BG_TASK_(?:GRANTED|REFUSED)',
        ).allMatches(goBridge),
        hasLength(2),
      );
    },
  );
}

Map<String, Object?> _mutate(
  Map<String, Object?> artifact,
  String section,
  String key,
  Object? value,
) {
  final changed = _deepCopy(artifact);
  (changed[section]! as Map<String, Object?>)[key] = value;
  return changed;
}

Map<String, Object?> _deepCopy(Map<String, Object?> value) =>
    (jsonDecode(jsonEncode(value))! as Map).map<String, Object?>(
      (key, item) => MapEntry('$key', item),
    );

final class _RecordingAndroidHostRunner implements AndroidHostProcessRunner {
  final List<String> commands = <String>[];

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    commands.add('$executable ${arguments.join(' ')}');
    return ProcessResult(1, 0, '', '');
  }
}

final class _RecordingCoreDeviceRecovery
    implements GroupMediaIosCoreDeviceRecovery {
  var calls = 0;

  @override
  Future<bool> recover() async {
    calls += 1;
    return true;
  }
}

final class _SequenceCommandRunner implements GroupMediaIosCommandRunner {
  _SequenceCommandRunner(this.results);

  final List<GroupMediaIosCommandResult> results;
  var calls = 0;

  @override
  Future<GroupMediaIosCommandResult> run(GroupMediaIosCommand command) async {
    final result = results[calls];
    calls += 1;
    return result;
  }

  @override
  Future<GroupMediaIosCommandResult> runStreaming(
    GroupMediaIosCommand command, {
    required Future<void> Function(String line) onLine,
  }) => run(command);
}

final class _FakeAndroidDisposableBoundary
    implements GroupMediaIosAndroidDisposableBoundary {
  _FakeAndroidDisposableBoundary({List<String>? events}) : _events = events;

  final List<String>? _events;
  final List<String> actions = <String>[];
  final Set<String> _preparedActions = <String>{};
  final Set<String> _completedActions = <String>{};

  @override
  Future<GroupMediaAndroidDisposableResetReceipt> prepare(String action) async {
    if (!_preparedActions.add(action)) {
      throw StateError('Android disposable action prepared more than once');
    }
    _record('prepare', action);
    return _receipt(action: action, phase: 'pre');
  }

  @override
  Future<GroupMediaAndroidDisposableResetReceipt?> cleanup(
    String action,
  ) async {
    if (!_preparedActions.remove(action)) {
      throw StateError('Android disposable cleanup lacks a matching prepare');
    }
    _record('cleanup', action);
    _completedActions.add(action);
    return _receipt(action: action, phase: 'post');
  }

  @override
  GroupMediaAndroidCommandAuditSnapshot commandAudit(String action) {
    if (!_completedActions.contains(action)) {
      throw StateError('Android disposable command audit is premature');
    }
    return GroupMediaAndroidCommandAuditSnapshot(
      adbCommandCount: 1,
      journalSha256: _digest('android-boundary-command-audit:$action'),
      productionPackageCommands: 0,
      uninstallCommands: 0,
      pmClearCommands: 0,
      broadDeleteCommands: 0,
    );
  }

  void _record(String operation, String action) {
    actions.add('$operation:$action');
    _events?.add('android-$operation:$action');
  }

  GroupMediaAndroidDisposableResetReceipt _receipt({
    required String action,
    required String phase,
  }) => GroupMediaAndroidDisposableResetReceipt(
    phase: phase,
    processId: phase == 'pre' ? 6269 : 6270,
    sha256Digest: _digest('android-disposable:$action:$phase'),
  );
}

final class _Fixture {
  _Fixture._({
    required this.root,
    required this.bundle,
    required this.driver,
    required this.androidArtifact,
    required this.proofDirectory,
  });

  static const senderDeviceId = 'pixel-usb';
  static const receiverDeviceId = '00008030-001A6D2801BB802E';
  static const runId = 'p269-ios-contract';

  final Directory root;
  final Directory bundle;
  final File driver;
  final File androidArtifact;
  final Directory proofDirectory;

  GroupMediaIosBackgroundRecoveryOptions get options =>
      GroupMediaIosBackgroundRecoveryOptions(
        runId: runId,
        preparedBundle: bundle,
        proofDirectory: proofDirectory,
        fixtureDriver: driver,
        senderDeviceId: senderDeviceId,
        receiverDeviceId: receiverDeviceId,
        inheritedEnvironment: const <String, String>{
          'MKNOON_RELAY_ADDRESSES': '/dns/relay.invalid/tcp/443/wss',
          groupMediaIosDedicatedDisposableDeviceEnvironment: receiverDeviceId,
        },
        androidCompanionArtifact: androidArtifact,
        androidCompanionArtifactSha256: sha256
            .convert(androidArtifact.readAsBytesSync())
            .toString(),
      );

  static Future<_Fixture> create() async {
    final root = await Directory.systemTemp.createTemp('p269-ios-controller-');
    final bundle = Directory('${root.path}/ios.device.group_media_269.bundle')
      ..createSync(recursive: true);
    final products = Directory('${bundle.path}/TestProducts')
      ..createSync(recursive: true);
    final app = Directory('${products.path}/Release-iphoneos/Runner.app')
      ..createSync(recursive: true);
    File('${app.path}/Runner').writeAsStringSync('signed-runner');
    File('${app.path}/Info.plist').writeAsStringSync('fixture-info');
    final shareExtension = Directory(
      '${app.path}/PlugIns/Share Extension.appex',
    )..createSync(recursive: true);
    File(
      '${shareExtension.path}/Share Extension',
    ).writeAsStringSync('signed-share-extension');
    File(
      '${shareExtension.path}/Info.plist',
    ).writeAsStringSync('fixture-share-info');
    final notificationService = Directory(
      '${app.path}/PlugIns/NotificationService.appex',
    )..createSync(recursive: true);
    File(
      '${notificationService.path}/NotificationService',
    ).writeAsStringSync('signed-notification-service');
    File(
      '${notificationService.path}/Info.plist',
    ).writeAsStringSync('fixture-notification-info');
    final uiHost = Directory(
      '${products.path}/Release-iphoneos/RunnerUITests-Runner.app',
    )..createSync(recursive: true);
    File(
      '${uiHost.path}/RunnerUITests-Runner',
    ).writeAsStringSync('ui-test-host-binary');
    File('${uiHost.path}/Info.plist').writeAsStringSync('ui-test-host-info');
    final uiBundle = Directory('${uiHost.path}/PlugIns/RunnerUITests.xctest')
      ..createSync(recursive: true);
    final uiBinary = File('${uiBundle.path}/RunnerUITests');
    uiBinary.writeAsStringSync('ui-test-binary');
    File('${uiBundle.path}/Info.plist').writeAsStringSync('ui-test-info');
    File(
      '${bundle.path}/RunnerUITests.xctestrun',
    ).writeAsStringSync('binary-plist-fixture');
    File('${bundle.path}/bundle_manifest.json').writeAsStringSync(
      jsonEncode(<String, Object?>{
        'schema': 'mknoon.sims.ios-device-group-media-269-bundle.v1',
        'profileId': groupMediaIosDisposableBuildProfile,
        'applicationApp': 'TestProducts/Release-iphoneos/Runner.app',
        'xctestrun': 'RunnerUITests.xctestrun',
        'testProducts': 'TestProducts',
        'centralCompileCommands': 1,
        'logicalBuildCount': 1,
        'childBuildCount': 0,
      }),
    );
    final driver = File(groupMediaIosFixtureDriverRepositoryPath).absolute;
    final androidArtifact = File('${root.path}/app-debug.apk')
      ..writeAsStringSync('dedicated-android-artifact');
    return _Fixture._(
      root: root,
      bundle: bundle,
      driver: driver,
      androidArtifact: androidArtifact,
      proofDirectory: Directory('${root.path}/proof'),
    );
  }

  Future<void> dispose() async {
    if (root.existsSync()) await root.delete(recursive: true);
  }
}

final class _FakeCommandRunner implements GroupMediaIosCommandRunner {
  _FakeCommandRunner(
    this.fixture, {
    this.exposeIosTarget = true,
    this.failPostReset = false,
    this.failXctestBeforeHome = false,
    this.unsafeEntitlementsFor,
    this.omittedEntitlements = const <String>{'ui-test-bundle'},
    this.emptyDecodedEntitlementsFor,
    this.zeroLengthEntitlementsFor,
    this.danglingSymlinkEntitlementsFor,
    this.invalidCodeSignatureFor,
    this.mismatchedSignatureIdentifierFor,
    this.mismatchedSignatureTeamFor,
    this.mismatchedProcessOwner = false,
    this.nonFileProcessExecutable = false,
    this.androidUsbTransport = true,
    this.androidReportsQemu = false,
    this.destructiveFixtureAudit = false,
    this.mutatePreparedBundleBeforeInstall = false,
    this.mutatePreparedBundleBeforePublication = false,
    List<String>? events,
  }) : events = events ?? <String>[];

  final _Fixture fixture;
  final bool exposeIosTarget;
  final bool failPostReset;
  final bool failXctestBeforeHome;
  final String? unsafeEntitlementsFor;
  final Set<String> omittedEntitlements;
  final String? emptyDecodedEntitlementsFor;
  final String? zeroLengthEntitlementsFor;
  final String? danglingSymlinkEntitlementsFor;
  final String? invalidCodeSignatureFor;
  final String? mismatchedSignatureIdentifierFor;
  final String? mismatchedSignatureTeamFor;
  final bool mismatchedProcessOwner;
  final bool nonFileProcessExecutable;
  final bool androidUsbTransport;
  final bool androidReportsQemu;
  final bool destructiveFixtureAudit;
  final bool mutatePreparedBundleBeforeInstall;
  final bool mutatePreparedBundleBeforePublication;
  final List<String> events;
  final List<GroupMediaIosCommand> commands = <GroupMediaIosCommand>[];
  final Map<String, Map<String, Object?>> _resetRequests =
      <String, Map<String, Object?>>{};
  final Map<String, String> resetReceiptRawDigests = <String, String>{};
  var _installed = true;
  var _mismatchedProcessObservationEmitted = false;
  var _nonFileProcessObservationEmitted = false;

  List<String> get labels => commands.map((command) => command.label).toList();

  String _bundleIdForCodeLabel(String label) => switch (label) {
    'runner' => groupMediaIosDisposableBundleId,
    'share-extension' => '$groupMediaIosDisposableBundleId.ShareExtension',
    'notification-service' =>
      '$groupMediaIosDisposableBundleId.NotificationService',
    'ui-test-host' =>
      '$groupMediaIosDisposableBundleId.RunnerUITests.xctrunner',
    'ui-test-bundle' => '$groupMediaIosDisposableBundleId.RunnerUITests',
    _ => throw StateError('Unexpected code object label $label'),
  };

  @override
  Future<GroupMediaIosCommandResult> run(GroupMediaIosCommand command) async {
    commands.add(command);
    events.add(command.label);
    if (command.label.startsWith('protect-')) {
      final result = await Process.run(command.executable, command.arguments);
      return GroupMediaIosCommandResult(
        exitCode: result.exitCode,
        stdout: '${result.stdout}',
        stderr: '${result.stderr}',
      );
    }
    if (command.label.startsWith('inspect-app-')) {
      final output = File(_argumentAfter(command.arguments, '--json-output'));
      output.writeAsStringSync(
        jsonEncode(<String, Object?>{
          'result': <String, Object?>{
            'apps': _installed
                ? <Object?>[
                    <String, Object?>{
                      'bundleIdentifier': groupMediaIosDisposableBundleId,
                      'url':
                          'file:///private/var/containers/Bundle/Application/'
                          'dedicated/Runner.app/',
                    },
                  ]
                : <Object?>[],
          },
        }),
      );
      return GroupMediaIosCommandResult.success('inventory');
    }
    if (command.label.startsWith('inspect-process-')) {
      final output = File(_argumentAfter(command.arguments, '--json-output'));
      final filter = _argumentAfter(command.arguments, '--filter');
      final processId = int.parse(filter.split('==').last.trim());
      final useMismatchedExecutable =
          mismatchedProcessOwner && !_mismatchedProcessObservationEmitted;
      if (useMismatchedExecutable) {
        _mismatchedProcessObservationEmitted = true;
      }
      final useNonFileExecutable =
          nonFileProcessExecutable && !_nonFileProcessObservationEmitted;
      if (useNonFileExecutable) {
        _nonFileProcessObservationEmitted = true;
      }
      output.writeAsStringSync(
        jsonEncode(<String, Object?>{
          'result': <String, Object?>{
            'runningProcesses': <Object?>[
              <String, Object?>{
                'processIdentifier': processId,
                'executable': useNonFileExecutable
                    ? 'https://invalid.example/Runner.app/Runner'
                    : useMismatchedExecutable
                    ? 'file:///private/var/containers/Bundle/Application/'
                          'other/Runner.app/Runner'
                    : 'file:///private/var/containers/Bundle/Application/'
                          'dedicated/Runner.app/Runner',
              },
            ],
          },
        }),
      );
      return GroupMediaIosCommandResult.success('process owner');
    }
    if (command.label.startsWith('codesign-entitlements')) {
      final label = command.label == 'codesign-entitlements'
          ? 'runner'
          : command.label.substring('codesign-entitlements-'.length);
      final bundleId = _bundleIdForCodeLabel(label);
      final signedIdentifier = mismatchedSignatureIdentifierFor == label
          ? '$bundleId.mismatch'
          : bundleId;
      final signedTeam = mismatchedSignatureTeamFor == label
          ? 'MISMATCHED1'
          : '397R9Q4WMX';
      final result = GroupMediaIosCommandResult(
        exitCode: 0,
        stdout: '',
        stderr: 'Identifier=$signedIdentifier\nTeamIdentifier=$signedTeam\n',
      );
      if (omittedEntitlements.contains(label)) {
        return result;
      }
      final output = File(_argumentAfter(command.arguments, '--entitlements'));
      if (zeroLengthEntitlementsFor == label) {
        output.writeAsStringSync('');
        return result;
      }
      if (danglingSymlinkEntitlementsFor == label) {
        Link(
          output.path,
        ).createSync('${fixture.root.path}/absent-entitlements');
        return result;
      }
      output.writeAsStringSync('fixture-entitlements');
      return result;
    }
    if (command.label.startsWith('decode-entitlements-')) {
      final output = File(_argumentAfter(command.arguments, '-o'));
      final label = command.label.substring('decode-entitlements-'.length);
      final bundleId = _bundleIdForCodeLabel(label);
      final entitlements = <String, Object?>{
        'application-identifier': '397R9Q4WMX.$bundleId',
        'com.apple.developer.team-identifier': '397R9Q4WMX',
        'keychain-access-groups': <String>['397R9Q4WMX.$bundleId'],
        'get-task-allow': true,
      };
      if (unsafeEntitlementsFor == label) {
        entitlements['aps-environment'] = 'production';
      }
      output.writeAsStringSync(
        jsonEncode(
          emptyDecodedEntitlementsFor == label
              ? <String, Object?>{}
              : entitlements,
        ),
      );
      return GroupMediaIosCommandResult.success('');
    }
    if (command.label.startsWith('stage-reset-')) {
      final phase = command.label.substring('stage-reset-'.length);
      if (phase == 'post' && failPostReset) {
        return const GroupMediaIosCommandResult(
          exitCode: 1,
          stdout: '',
          stderr: 'injected post-reset failure',
        );
      }
      final request =
          jsonDecode(
                File(
                  _argumentAfter(command.arguments, '--source'),
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      _resetRequests[phase] = request.cast<String, Object?>();
      File(
        _argumentAfter(command.arguments, '--json-output'),
      ).writeAsStringSync('{"result":"copied"}');
      return GroupMediaIosCommandResult.success('copied');
    }
    if (command.label.startsWith('pull-reset-')) {
      final phase = command.label.substring('pull-reset-'.length);
      final request = _resetRequests[phase]!;
      final destination = File(
        _argumentAfter(command.arguments, '--destination'),
      );
      expect(destination.existsSync(), isFalse);
      expect(
        destination.path,
        endsWith(groupMediaIosDisposableResetReceiptFile),
      );
      final raw =
          '${jsonEncode(<String, Object?>{'schema': groupMediaIosDisposableResetReceiptSchema, 'run_id': request['run_id'], 'nonce': request['nonce'], 'phase': phase, 'process_id': phase == 'pre' ? 5269 : 5270, 'bundle_id': groupMediaIosDisposableBundleId, 'profile': groupMediaIosDisposableBuildProfile, 'keychain_empty': true, 'database_absent': true, 'allowlisted_files_absent': true, 'contains_secrets': false})}\n';
      destination.writeAsStringSync(raw);
      resetReceiptRawDigests[phase] = _digest(raw);
      File(
        _argumentAfter(command.arguments, '--json-output'),
      ).writeAsStringSync('{"result":"copied"}');
      return GroupMediaIosCommandResult.success('copied');
    }
    switch (command.label) {
      case 'adb-live-targets':
        return GroupMediaIosCommandResult.success(
          'List of devices attached\n${_Fixture.senderDeviceId} device '
          '${androidUsbTransport ? 'usb:1-1' : 'product:fixture transport_id:1'}\n',
        );
      case 'adb-sender-hardware':
        return GroupMediaIosCommandResult.success(
          androidReportsQemu ? '1\n' : '0\n',
        );
      case 'ios-live-targets':
        return GroupMediaIosCommandResult.success(
          exposeIosTarget
              ? jsonEncode(<Object?>[
                  <String, Object?>{
                    'id': _Fixture.receiverDeviceId,
                    'isSupported': true,
                    'targetPlatform': 'ios',
                    'emulator': false,
                  },
                ])
              : '[]',
        );
      case 'ios-coredevice-details':
        final output = File(_argumentAfter(command.arguments, '--json-output'));
        output.writeAsStringSync(
          jsonEncode(<String, Object?>{
            'info': <String, Object?>{'outcome': 'success'},
            'result': <String, Object?>{
              'hardwareProperties': <String, Object?>{
                'udid': _Fixture.receiverDeviceId,
                'platform': 'iOS',
                'productType': 'iPhone12,1',
              },
              'deviceProperties': <String, Object?>{
                'bootState': 'booted',
                'ddiServicesAvailable': true,
              },
              'connectionProperties': <String, Object?>{
                'pairingState': 'paired',
                'transportType': 'wired',
                'tunnelState': 'connected',
              },
            },
          }),
        );
        return GroupMediaIosCommandResult.success('');
      case 'codesign':
      case 'codesign-verify-share-extension':
      case 'codesign-verify-notification-service':
      case 'codesign-verify-ui-test-host':
      case 'codesign-verify-ui-test-bundle':
        final label = switch (command.label) {
          'codesign' => 'runner',
          'codesign-verify-share-extension' => 'share-extension',
          'codesign-verify-notification-service' => 'notification-service',
          'codesign-verify-ui-test-host' => 'ui-test-host',
          'codesign-verify-ui-test-bundle' => 'ui-test-bundle',
          _ => throw StateError('Unexpected signature label'),
        };
        if (invalidCodeSignatureFor == label) {
          return const GroupMediaIosCommandResult(
            exitCode: 1,
            stdout: '',
            stderr: 'invalid fixture signature',
          );
        }
        return GroupMediaIosCommandResult.success('');
      case 'bundle-id':
        return GroupMediaIosCommandResult.success(
          '$groupMediaIosDisposableBundleId\n',
        );
      case 'bundle-id-share-extension':
        return GroupMediaIosCommandResult.success(
          '$groupMediaIosDisposableBundleId.ShareExtension\n',
        );
      case 'bundle-id-notification-service':
        return GroupMediaIosCommandResult.success(
          '$groupMediaIosDisposableBundleId.NotificationService\n',
        );
      case 'bundle-id-ui-test-host':
        return GroupMediaIosCommandResult.success(
          '$groupMediaIosDisposableBundleId.RunnerUITests.xctrunner\n',
        );
      case 'bundle-id-ui-test-bundle':
        return GroupMediaIosCommandResult.success(
          '$groupMediaIosDisposableBundleId.RunnerUITests\n',
        );
      case 'decode-xctestrun':
        final output = File(_argumentAfter(command.arguments, '-o'));
        output.writeAsStringSync(
          jsonEncode(<String, Object?>{
            'RunnerUITests': <String, Object?>{
              'TestBundlePath':
                  '__TESTROOT__/Release-iphoneos/'
                  'RunnerUITests-Runner.app/PlugIns/'
                  'RunnerUITests.xctest',
              'UITargetAppPath':
                  '/old/DerivedData/Build/Products/'
                  'Release-iphoneos/Runner.app',
            },
          }),
        );
        return GroupMediaIosCommandResult.success('');
      case 'encode-xctestrun':
        final output = File(_argumentAfter(command.arguments, '-o'));
        output.writeAsStringSync('patched-xctestrun');
        if (mutatePreparedBundleBeforeInstall) {
          _mutatePreparedBundle('before-install');
        }
        return GroupMediaIosCommandResult.success('');
      case 'install-prepared-app':
        final output = File(_argumentAfter(command.arguments, '--json-output'));
        output.writeAsStringSync('{"result":"installed"}');
        _installed = true;
        return GroupMediaIosCommandResult.success('installed');
      case 'stage-auto-setup':
        final output = File(_argumentAfter(command.arguments, '--json-output'));
        output.writeAsStringSync('{"result":"copied"}');
        return GroupMediaIosCommandResult.success('copied');
      case 'launch-root-before-proof':
      case 'launch-root-after-phase-a':
      case 'launch-reset-pre':
      case 'launch-reset-post':
      case 'terminate-reset-pre':
      case 'terminate-reset-post':
      case 'host-terminate-phase-b':
        return GroupMediaIosCommandResult.success('ok');
      case 'fixture-phase-a':
        _writeAndroidCommandAudit(command);
        if (failXctestBeforeHome) {
          _writeReady(command, phase: 'a');
          final cancel = File(_argumentAfter(command.arguments, '--cancel'));
          final deadline = DateTime.now().add(const Duration(seconds: 5));
          while (!cancel.existsSync() && DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
          }
          if (cancel.existsSync()) events.add('fixture-cancel-observed');
          return const GroupMediaIosCommandResult(
            exitCode: 1,
            stdout: '',
            stderr: 'fixture cancelled',
          );
        }
        _writeReceipt(
          command,
          _receipt(
            phase: 'a',
            barrier: 'background_receive_started',
            terminalPath: 'normal',
            nativeEndCount: 1,
            durableStatus: 'done',
            receiverPid: 4141,
            relaunchPid: null,
            resumeAttempts: 0,
            downloadAttempts: 1,
          ),
        );
        return GroupMediaIosCommandResult.success('phase a settled');
      case 'fixture-phase-b-claim':
        _writeAndroidCommandAudit(command);
        _writeReceipt(
          command,
          _receipt(
            phase: 'b_claim',
            barrier: 'durable_post_claim_pre_commit',
            terminalPath: 'none',
            nativeEndCount: 0,
            durableStatus: 'downloading',
            receiverPid: 4242,
            relaunchPid: null,
            resumeAttempts: 0,
            downloadAttempts: 1,
          ),
        );
        return GroupMediaIosCommandResult.success('phase b barrier held');
      case 'fixture-phase-b-observe':
        _writeAndroidCommandAudit(command);
        _writeReceipt(
          command,
          _receipt(
            phase: 'b_recovery',
            barrier: 'resume_after_first_group_inbox_drain',
            terminalPath: 'interrupted',
            nativeEndCount: 0,
            durableStatus: 'done',
            receiverPid: 4242,
            relaunchPid: 4343,
            resumeAttempts: 1,
            downloadAttempts: 2,
          ),
        );
        if (mutatePreparedBundleBeforePublication) {
          _mutatePreparedBundle('before-publication');
        }
        return GroupMediaIosCommandResult.success('phase b recovered');
      default:
        throw StateError('Unexpected command ${command.label}');
    }
  }

  @override
  Future<GroupMediaIosCommandResult> runStreaming(
    GroupMediaIosCommand command, {
    required Future<void> Function(String line) onLine,
  }) async {
    commands.add(command);
    events.add(command.label);
    expect(command.label, 'xctest-without-building');
    await onLine('MKNOON_269_IOS_EVENT local_network_permission_ready');
    if (failXctestBeforeHome) {
      return const GroupMediaIosCommandResult(
        exitCode: 1,
        stdout: '',
        stderr: 'injected XCTest failure',
      );
    }
    for (final marker in const <String>[
      'MKNOON_269_IOS_EVENT phase_a_ready',
      'MKNOON_269_IOS_EVENT phase_a_home',
      'MKNOON_269_IOS_EVENT phase_a_effect_once',
      'MKNOON_269_IOS_EVENT phase_b_ready',
      'MKNOON_269_IOS_EVENT phase_b_home',
      'MKNOON_269_IOS_EVENT phase_b_relaunch_root_without_group',
      'MKNOON_269_IOS_EVENT phase_b_effect_once',
    ]) {
      await onLine(marker);
    }
    return GroupMediaIosCommandResult.success('** TEST SUCCEEDED **');
  }

  void _mutatePreparedBundle(String marker) {
    File(
      '${fixture.bundle.path}/TestProducts/Release-iphoneos/Runner.app/Runner',
    ).writeAsStringSync(marker, mode: FileMode.append, flush: true);
  }

  Map<String, Object?> _receipt({
    required String phase,
    required String barrier,
    required String terminalPath,
    required int nativeEndCount,
    required String durableStatus,
    required int receiverPid,
    required int? relaunchPid,
    required int resumeAttempts,
    required int downloadAttempts,
  }) => <String, Object?>{
    'schema': groupMediaIosFixtureReceiptSchema,
    'run_id': _Fixture.runId,
    'phase': phase,
    'sender_device_sha256': _digest(
      '${_Fixture.runId}:sender:${_Fixture.senderDeviceId}',
    ),
    'receiver_device_sha256': _digest(
      '${_Fixture.runId}:receiver:${_Fixture.receiverDeviceId}',
    ),
    'ui_effect_sha256': _digest(
      phase == 'a' ? 'P269-A-${_Fixture.runId}' : 'P269-B-${_Fixture.runId}',
    ),
    'parent_message_sha256': _digest(
      'P269-PARENT-${phase == 'a' ? 'A' : 'B'}-${_Fixture.runId}',
    ),
    'receiver_pid': receiverPid,
    'relaunch_pid': relaunchPid,
    'barrier': barrier,
    'critical_task_granted': true,
    'terminal_path': terminalPath,
    'native_end_count': nativeEndCount,
    'durable_status': durableStatus,
    'download_attempts': downloadAttempts,
    'resume_after_drain_attempts': resumeAttempts,
  };

  void _writeReceipt(
    GroupMediaIosCommand command,
    Map<String, Object?> receipt,
  ) {
    final phase = receipt['phase']! as String;
    final output = File(_argumentAfter(command.arguments, '--output'));
    final transientState = File('${output.parent.path}/fixture-state.json')
      ..writeAsStringSync('sensitive-identity-material');
    Process.runSync('chmod', <String>['600', transientState.path]);
    _writeReady(command, phase: phase == 'a' ? 'a' : 'b');
    final native = <String, Object?>{
      'schema': groupMediaIosNativeObservationSchema,
      'run_id': _Fixture.runId,
      'phase': phase,
      'source': 'physical_idevicesyslog',
      'receiver_device_sha256': receipt['receiver_device_sha256'],
      'home_observed': true,
      'critical_task_granted': true,
      'terminal_path': receipt['terminal_path'],
      'native_end_count': receipt['native_end_count'],
      'receiver_pid': receipt['receiver_pid'],
      'host_kill_observed': phase == 'b_recovery',
    };
    final database = <String, Object?>{
      'schema': groupMediaIosDatabaseObservationSchema,
      'run_id': _Fixture.runId,
      'phase': phase,
      'source': 'production_sqlcipher',
      'receiver_device_sha256': receipt['receiver_device_sha256'],
      'parent_message_sha256': receipt['parent_message_sha256'],
      'ui_effect_sha256': receipt['ui_effect_sha256'],
      'database_path_sha256': _digest('production-db-path'),
      'database_reopened': true,
      'cipher_version': 'SQLCipher 4.6.1',
      'user_version': 104,
      'barrier': receipt['barrier'],
      'durable_status': receipt['durable_status'],
      'download_attempts': receipt['download_attempts'],
      'resume_after_drain_attempts': receipt['resume_after_drain_attempts'],
    };
    File(_argumentAfter(command.arguments, '--native-observation'))
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(native));
    File(_argumentAfter(command.arguments, '--database-observation'))
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(database));
    receipt['native_observation_sha256'] = groupMediaIosObservationDigest(
      native,
    );
    receipt['database_observation_sha256'] = groupMediaIosObservationDigest(
      database,
    );
    output
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(receipt));
  }

  void _writeAndroidCommandAudit(GroupMediaIosCommand command) {
    final action = _argumentAfter(command.arguments, '--action');
    final ownsAndroidSender = action != 'phase-b-observe-recovery';
    final destructive =
        destructiveFixtureAudit && action == 'phase-a-background-success';
    final audit =
        File(_argumentAfter(command.arguments, '--android-command-audit'))
          ..createSync(recursive: true)
          ..writeAsStringSync(
            jsonEncode(<String, Object?>{
              'schema': groupMediaAndroidCommandAuditSchema,
              'run_id': _Fixture.runId,
              'action': action,
              'adb_command_count': ownsAndroidSender ? 7 : 0,
              'journal_sha256': _digest('fixture-command-audit:$action'),
              'production_package_commands': 0,
              'uninstall_commands': destructive ? 1 : 0,
              'pm_clear_commands': 0,
              'broad_delete_commands': 0,
              'contains_secrets': false,
            }),
            flush: true,
          );
    Process.runSync('chmod', <String>['600', audit.path]);
  }

  void _writeReady(GroupMediaIosCommand command, {required String phase}) {
    if (!command.arguments.contains('--ready')) return;
    final ready = File(_argumentAfter(command.arguments, '--ready'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode(<String, Object?>{
          'schema': 'mknoon.group-media-ios-fixture-ready.v1',
          'run_id': _Fixture.runId,
          'action': _argumentAfter(command.arguments, '--action'),
          'media_phase': phase,
          'ready_label_sha256': _digest(
            phase == 'a'
                ? 'P269-READY-A-${_Fixture.runId}'
                : 'P269-READY-B-${_Fixture.runId}',
          ),
          'foreground_arm_complete': true,
        }),
      );
    Process.runSync('chmod', <String>['600', ready.path]);
  }
}

final class _FakeSystemLogCapture implements GroupMediaIosSystemLogCapture {
  _FakeSystemLogCapture(this.events, {this.failStop = false});

  final List<String> events;
  final bool failStop;
  File? output;
  String? deviceId;

  @override
  Future<void> start({required String deviceId, required File output}) async {
    this.deviceId = deviceId;
    this.output = output;
    events.add('system-log-start');
    output.writeAsStringSync('physical fixture log\n', mode: FileMode.append);
  }

  @override
  Future<void> stop() async {
    events.add('system-log-stop');
    if (failStop) {
      throw StateError('injected system-log stop failure');
    }
  }
}

String _argumentAfter(List<String> arguments, String option) {
  final index = arguments.indexOf(option);
  if (index < 0 || index + 1 >= arguments.length) {
    throw StateError('$option is missing');
  }
  return arguments[index + 1];
}

String _digest(String value) => sha256.convert(utf8.encode(value)).toString();
