import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/group_media_ios_background_recovery_evidence.dart';
import '../../integration_test/scripts/group_media_reliability_criteria.dart';
import '../../integration_test/scripts/group_media_prepared_artifact_custody.dart';
import '../../integration_test/scripts/group_media_reliability_runner_contract.dart';
import '../../tool/sims/artifact_evidence.dart';

void main() {
  test(
    'P269 runner requires prepared main artifact two roles and one Sims evidence envelope',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'p269-runner-contract-',
      );
      addTearDown(() async {
        if (directory.existsSync()) await directory.delete(recursive: true);
      });
      final artifact = File('${directory.path}/app-debug.apk')
        ..writeAsStringSync('centrally-prepared-main-apk');
      final buildGuard = File('${directory.path}/build-guard.log')
        ..writeAsStringSync('');
      final proofDirectory = Directory('${directory.path}/proof');
      final environment = <String, String>{
        groupMediaReliabilityAndroidArtifactEnvironment: artifact.path,
        'SIMS_ARTIFACT_PROFILE_ID': groupMediaReliabilityAndroidBuildProfile,
        'SIMS_PROOF_DIRECTORY': proofDirectory.path,
        'SIMS_BUILD_GUARD_LOG': buildGuard.path,
        'MKNOON_RELAY_ADDRESSES': '/dns/relay.invalid/tcp/443/wss',
      };

      GroupMediaReliabilityRunContext? captured;
      final result = await runGroupMediaReliabilityRunner(
        arguments: const <String>[
          '--scenario',
          groupMediaForegroundRetryAclRoundtripScenario,
          '--run-id',
          'p269-contract-run',
          '-d',
          'pixel-usb,emulator-5554',
        ],
        environment: environment,
        executeScenario: (context) async {
          captured = context;
          return _acceptedArtifact(context);
        },
      );

      expect(result.exitCode, 0);
      expect(result.json['status'], 'PASS');
      expect(result.json['assertionsAttempted'], 1);
      expect(result.json['artifactPresent'], isTrue);
      expect(captured, isNotNull);
      expect(captured!.roles.keys, <String>['sender', 'receiver']);
      expect(captured!.roles['sender']!.deviceId, 'pixel-usb');
      expect(captured!.roles['receiver']!.deviceId, 'emulator-5554');
      expect(
        captured!.roles['sender']!.identityNamespace,
        isNot(captured!.roles['receiver']!.identityNamespace),
      );
      expect(captured!.preparedArtifact.path, artifact.absolute.path);
      expect(captured!.childBuildsAllowed, isFalse);
      expect(buildGuard.readAsStringSync(), isEmpty);

      final evidence = SimsArtifactEvidence.fromJson(
        result.json['artifactEvidence'],
      );
      expect(evidence.validatorIds, <String>[
        groupMediaReliabilityArtifactValidatorId,
      ]);
      final audit = auditSimsArtifactEvidence(
        evidence: evidence,
        expectedValidatorIds: const <String>[
          groupMediaReliabilityArtifactValidatorId,
        ],
      );
      expect(audit.isValid, isTrue, reason: audit.detail);
      final persisted = jsonDecode(
        File(audit.canonicalPath!).readAsStringSync(),
      );
      expect(validateGroupMediaReliabilityArtifact(persisted).ok, isTrue);
      expect(RegExp('SIMS_RESULT_JSON=').allMatches(result.sentinel).length, 1);
      expect(proofDirectory.listSync().whereType<File>(), hasLength(1));

      final wrongPreparedDigest = await runGroupMediaReliabilityRunner(
        arguments: const <String>[
          '--scenario',
          groupMediaForegroundRetryAclRoundtripScenario,
          '-d',
          'pixel-usb,emulator-5554',
        ],
        environment: environment,
        executeScenario: (context) async {
          final accepted = _acceptedArtifact(context);
          accepted['prepared_artifact'] = <String, Object?>{
            'profile': context.preparedArtifact.profile,
            'application_id': groupMediaReliabilityAndroidPackageName,
            'sha256': List<String>.filled(64, 'a').join(),
            'child_builds': 0,
          };
          return accepted;
        },
      );
      expect(wrongPreparedDigest.exitCode, 1);
      expect(wrongPreparedDigest.json['status'], 'FAIL');
      expect(wrongPreparedDigest.json['artifactPresent'], isFalse);

      final wrongRunId = await runGroupMediaReliabilityRunner(
        arguments: const <String>[
          '--scenario',
          groupMediaForegroundRetryAclRoundtripScenario,
          '-d',
          'pixel-usb,emulator-5554',
        ],
        environment: environment,
        executeScenario: (context) async =>
            _acceptedArtifact(context, artifactRunId: 'different-valid-run'),
      );
      expect(wrongRunId.exitCode, 1);
      expect(wrongRunId.json['status'], 'FAIL');
      expect(wrongRunId.json['assertionsAttempted'], 1);
      expect(wrongRunId.json['artifactPresent'], isFalse);
      expect(wrongRunId.json['detail'], contains('run_id'));

      final codedFailure = await runGroupMediaReliabilityRunner(
        arguments: const <String>[
          '--scenario',
          groupMediaForegroundRetryAclRoundtripScenario,
          '-d',
          'pixel-usb,emulator-5554',
        ],
        environment: environment,
        executeScenario: (_) async =>
            throw GroupMediaReliabilityScenarioFailure(
              'group_endpoint_sender_setup_sender_authority',
            ),
      );
      expect(codedFailure.exitCode, 1);
      expect(codedFailure.json['status'], 'FAIL');
      expect(
        codedFailure.json['detail'],
        'Group media scenario failed at '
        'group_endpoint_sender_setup_sender_authority.',
      );
      expect(
        () => GroupMediaReliabilityScenarioFailure('unsafe code: secret'),
        throwsArgumentError,
      );

      var invalidInputExecuted = false;
      final invalidInput = await runGroupMediaReliabilityRunner(
        arguments: const <String>[
          '--scenario',
          groupMediaForegroundRetryAclRoundtripScenario,
          '-d',
          'pixel-usb,pixel-usb',
        ],
        environment: environment,
        executeScenario: (_) async {
          invalidInputExecuted = true;
          throw StateError('must not execute');
        },
      );
      expect(invalidInputExecuted, isFalse);
      expect(invalidInput.exitCode, 78);
      expect(invalidInput.json['status'], 'BLOCKED');
      expect(invalidInput.json['assertionsAttempted'], 0);

      final postExecutionFormatFailure = await runGroupMediaReliabilityRunner(
        arguments: const <String>[
          '--scenario',
          groupMediaForegroundRetryAclRoundtripScenario,
          '-d',
          'pixel-usb,emulator-5554',
        ],
        environment: environment,
        executeScenario: (_) async => _MalformedProofArtifact(),
      );
      expect(postExecutionFormatFailure.exitCode, 1);
      expect(postExecutionFormatFailure.json['status'], 'FAIL');
      expect(postExecutionFormatFailure.json['assertionsAttempted'], 1);
      expect(postExecutionFormatFailure.json['blocker'], 'test');
      expect(postExecutionFormatFailure.json['artifactPresent'], isFalse);

      final missing = await runGroupMediaReliabilityRunner(
        arguments: const <String>[
          '--scenario',
          groupMediaForegroundRetryAclRoundtripScenario,
          '-d',
          'pixel-usb,emulator-5554',
        ],
        environment: <String, String>{
          ...environment,
          groupMediaReliabilityAndroidArtifactEnvironment:
              '${directory.path}/missing.apk',
        },
        executeScenario: (_) async => throw StateError('must not execute'),
      );
      expect(missing.exitCode, 78);
      expect(missing.json['status'], 'BLOCKED');
      expect(missing.json['blocker'], 'missingArtifact');
      expect(missing.json['artifactPresent'], isFalse);

      final buildViolation = await runGroupMediaReliabilityRunner(
        arguments: const <String>[
          '--scenario',
          groupMediaForegroundRetryAclRoundtripScenario,
          '-d',
          'pixel-usb,emulator-5554',
        ],
        environment: environment,
        executeScenario: (context) async {
          buildGuard.writeAsStringSync('nested-build-attempt\n');
          return _acceptedArtifact(context);
        },
      );
      expect(buildViolation.exitCode, 78);
      expect(buildViolation.json['status'], 'BLOCKED');
      expect(buildViolation.json['blocker'], 'harness');
      expect(buildViolation.json['artifactPresent'], isFalse);

      buildGuard.writeAsStringSync('');
      final actualEntrypoint = await Process.run('dart', const <String>[
        'integration_test/scripts/run_group_media_send_reliability.dart',
        '--scenario',
        groupMediaForegroundRetryAclRoundtripScenario,
        '-d',
        'pixel-usb,emulator-5554',
      ], environment: environment);
      expect(actualEntrypoint.exitCode, 78);
      final sentinelLines = '${actualEntrypoint.stdout}'
          .split('\n')
          .where((line) => line.startsWith('SIMS_RESULT_JSON='))
          .toList(growable: false);
      expect(sentinelLines, hasLength(1));
      final blockedJson =
          jsonDecode(sentinelLines.single.substring('SIMS_RESULT_JSON='.length))
              as Map<String, Object?>;
      expect(blockedJson['status'], 'BLOCKED');
      expect(
        blockedJson['blocker'],
        anyOf('missingDriver', 'targetUnavailable'),
      );
      expect(blockedJson['artifactPresent'], isFalse);

      expect(
        () => GroupMediaReliabilityRunnerArguments.parse(const <String>[
          '--scenario',
          groupMediaForegroundRetryAclRoundtripScenario,
          '-d',
          'pixel-usb;rm -rf x,emulator-5554',
        ]),
        throwsFormatException,
      );
      expect(
        () => GroupMediaReliabilityRunnerArguments.parse(const <String>[
          '--scenario',
          groupMediaForegroundRetryAclRoundtripScenario,
          '-d',
          'pixel-usb,pixel-usb',
        ]),
        throwsFormatException,
      );
      expect(
        () => GroupMediaReliabilityRunnerArguments.parse(const <String>[
          '--scenario',
          'unknown-scenario',
          '-d',
          'pixel-usb,emulator-5554',
        ]),
        throwsFormatException,
      );
      expect(
        () => GroupMediaReliabilityRunnerArguments.parse(const <String>[
          '--scenario',
          groupMediaForegroundRetryAclRoundtripScenario,
          '--artifact',
          '/tmp/unowned.apk',
        ]),
        throwsFormatException,
      );

      final source = File(
        'integration_test/scripts/run_group_media_send_reliability.dart',
      ).readAsStringSync();
      final contractSource = File(
        'integration_test/scripts/group_media_reliability_runner_contract.dart',
      ).readAsStringSync();
      expect('$source\n$contractSource', isNot(contains('flutter build')));
      expect('$source\n$contractSource', isNot(contains('flutter drive')));
      expect(
        RegExp(r'stdout\.writeln\(result\.sentinel\)').allMatches(source),
        hasLength(1),
      );
      expect(
        source,
        contains('executeAndroidGroupMediaReliabilityScenario(context)'),
      );
      expect(source, contains('GroupMediaIosBackgroundRecoveryController('));
      expect(
        contractSource,
        contains('groupMediaIosBackgroundRecoveryArtifactValidatorId'),
      );
    },
  );

  test(
    'P269 runner rejects an Android APK mutated during scenario execution',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'p269-android-runner-custody-override-',
      );
      addTearDown(() async {
        if (directory.existsSync()) await directory.delete(recursive: true);
      });
      final preparedApk = File('${directory.path}/app-debug.apk')
        ..writeAsStringSync('centrally-prepared-main-apk');
      final proofDirectory = Directory('${directory.path}/proof');

      final result = await runGroupMediaReliabilityRunner(
        arguments: const <String>[
          '--scenario',
          groupMediaForegroundRetryAclRoundtripScenario,
          '--run-id',
          'p269-android-custody-mutation',
          '-d',
          'pixel-usb,emulator-5554',
        ],
        environment: <String, String>{
          groupMediaReliabilityAndroidArtifactEnvironment: preparedApk.path,
          'SIMS_ARTIFACT_PROFILE_ID': groupMediaReliabilityAndroidBuildProfile,
          'SIMS_PROOF_DIRECTORY': proofDirectory.path,
          'MKNOON_RELAY_ADDRESSES': '/dns/relay.invalid/tcp/443/wss',
        },
        executeScenario: (context) async {
          final accepted = _acceptedArtifact(context);
          preparedApk.writeAsStringSync('mutated-after-context-custody');
          return accepted;
        },
      );

      expect(result.exitCode, 1);
      expect(result.json['status'], 'FAIL');
      expect(result.json['assertionsAttempted'], 1);
      expect(result.json['artifactPresent'], isFalse);
      expect(
        result.json['detail'],
        'The prepared Android APK changed during scenario execution.',
      );
      expect(proofDirectory.existsSync(), isFalse);
    },
  );

  test('P269 runner binds the iOS artifact root to its exact run ID', () async {
    final directory = await Directory.systemTemp.createTemp(
      'p269-ios-runner-binding-',
    );
    addTearDown(() async {
      if (directory.existsSync()) await directory.delete(recursive: true);
    });
    final preparedBundle = await Directory(
      '${directory.path}/Runner.app',
    ).create();
    final androidCompanion = File('${directory.path}/group-media.apk')
      ..writeAsStringSync('dedicated-android-companion');
    final result = await runGroupMediaReliabilityRunner(
      arguments: const <String>[
        '--scenario',
        groupMediaIosReceiverBackgroundRecoveryScenario,
        '--run-id',
        'p269-ios-contract-run',
        '-d',
        'pixel-usb,00008150-001C3C6A3684401C',
      ],
      environment: <String, String>{
        groupMediaReliabilityIosArtifactEnvironment: preparedBundle.path,
        groupMediaReliabilityAndroidArtifactEnvironment: androidCompanion.path,
        'SIMS_ARTIFACT_PROFILE_ID': groupMediaReliabilityIosBuildProfile,
        'SIMS_PROOF_DIRECTORY': '${directory.path}/proof',
        'MKNOON_RELAY_ADDRESSES': '/dns/relay.invalid/tcp/443/wss',
      },
      executeScenario: (_) async => <String, Object?>{
        'run_id': 'different-valid-ios-run',
      },
    );

    expect(result.exitCode, 1);
    expect(result.json['status'], 'FAIL');
    expect(result.json['assertionsAttempted'], 1);
    expect(result.json['artifactPresent'], isFalse);
    expect(
      result.json['detail'],
      'Artifact run_id does not match runner custody.',
    );
  });

  test(
    'P269 runner accepts and persists a valid dedicated iOS artifact envelope',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'p269-ios-runner-pass-',
      );
      addTearDown(() async {
        if (directory.existsSync()) await directory.delete(recursive: true);
      });
      final preparedBundle = Directory('${directory.path}/prepared-bundle')
        ..createSync();
      File('${preparedBundle.path}/Runner.app/Runner')
        ..createSync(recursive: true)
        ..writeAsStringSync('centrally-prepared-ios-runner');
      final androidCompanion = File('${directory.path}/group-media.apk')
        ..writeAsStringSync('dedicated-android-companion');
      final proofDirectory = Directory('${directory.path}/proof');
      final expectedBundleDigest = groupMediaPreparedDirectorySha256(
        preparedBundle,
      );
      final expectedCompanionDigest = sha256
          .convert(androidCompanion.readAsBytesSync())
          .toString();
      GroupMediaReliabilityRunContext? captured;

      final result = await runGroupMediaReliabilityRunner(
        arguments: const <String>[
          '--scenario',
          groupMediaIosReceiverBackgroundRecoveryScenario,
          '--run-id',
          'p269-ios-valid-run',
          '-d',
          'pixel-usb,00008150-001C3C6A3684401C',
        ],
        environment: <String, String>{
          groupMediaReliabilityIosArtifactEnvironment: preparedBundle.path,
          groupMediaReliabilityAndroidArtifactEnvironment:
              androidCompanion.path,
          'SIMS_ARTIFACT_PROFILE_ID': groupMediaReliabilityIosBuildProfile,
          'SIMS_PROOF_DIRECTORY': proofDirectory.path,
          'MKNOON_RELAY_ADDRESSES': '/dns/relay.invalid/tcp/443/wss',
        },
        executeScenario: (context) async {
          captured = context;
          final artifact = _acceptedIosArtifact(context);
          final validation = validateGroupMediaIosBackgroundRecoveryArtifact(
            artifact,
          );
          expect(validation.ok, isTrue, reason: validation.detail);
          return artifact;
        },
      );

      expect(result.exitCode, 0);
      expect(result.json['status'], 'PASS');
      expect(result.json['artifactPresent'], isTrue);
      expect(captured, isNotNull);
      expect(
        groupMediaReliabilityIosBuildProfile,
        'ios.device.group_media_269',
      );
      expect(captured!.preparedArtifact.sha256Digest, expectedBundleDigest);
      expect(
        captured!.androidCompanionArtifact!.sha256Digest,
        expectedCompanionDigest,
      );

      final evidence = SimsArtifactEvidence.fromJson(
        result.json['artifactEvidence'],
      );
      expect(evidence.validatorIds, <String>[
        groupMediaIosBackgroundRecoveryArtifactValidatorId,
      ]);
      final audit = auditSimsArtifactEvidence(
        evidence: evidence,
        expectedValidatorIds: const <String>[
          groupMediaIosBackgroundRecoveryArtifactValidatorId,
        ],
      );
      expect(audit.isValid, isTrue, reason: audit.detail);
      final persisted =
          jsonDecode(File(audit.canonicalPath!).readAsStringSync())
              as Map<String, Object?>;
      final persistedValidation =
          validateGroupMediaIosBackgroundRecoveryArtifact(persisted);
      expect(
        persistedValidation.ok,
        isTrue,
        reason: persistedValidation.detail,
      );
      final prepared = persisted['prepared_artifact']! as Map<String, Object?>;
      expect(prepared['profile'], groupMediaReliabilityIosBuildProfile);
      expect(prepared['bundle_sha256'], expectedBundleDigest);
      expect(
        prepared['android_profile'],
        groupMediaReliabilityAndroidBuildProfile,
      );
      expect(prepared['android_sha256'], expectedCompanionDigest);
      expect(
        prepared['android_package'],
        groupMediaReliabilityAndroidPackageName,
      );
      expect(proofDirectory.listSync().whereType<File>(), hasLength(1));
    },
  );

  test(
    'P269 runner rejects an iOS directory mutated during scenario execution',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'p269-ios-runner-custody-override-',
      );
      addTearDown(() async {
        if (directory.existsSync()) await directory.delete(recursive: true);
      });
      final preparedBundle = Directory('${directory.path}/prepared-bundle')
        ..createSync();
      File('${preparedBundle.path}/Runner.app')
        ..createSync()
        ..writeAsStringSync('centrally-prepared-ios-member');
      final androidCompanion = File('${directory.path}/group-media.apk')
        ..writeAsStringSync('dedicated-android-companion');
      final proofDirectory = Directory('${directory.path}/proof');

      final result = await runGroupMediaReliabilityRunner(
        arguments: const <String>[
          '--scenario',
          groupMediaIosReceiverBackgroundRecoveryScenario,
          '--run-id',
          'p269-ios-custody-mutation',
          '-d',
          'pixel-usb,00008150-001C3C6A3684401C',
        ],
        environment: <String, String>{
          groupMediaReliabilityIosArtifactEnvironment: preparedBundle.path,
          groupMediaReliabilityAndroidArtifactEnvironment:
              androidCompanion.path,
          'SIMS_ARTIFACT_PROFILE_ID': groupMediaReliabilityIosBuildProfile,
          'SIMS_PROOF_DIRECTORY': proofDirectory.path,
          'MKNOON_RELAY_ADDRESSES': '/dns/relay.invalid/tcp/443/wss',
        },
        executeScenario: (context) async {
          File(
            '${preparedBundle.path}/post-custody-member',
          ).writeAsStringSync('mutation-during-executor');
          return <String, Object?>{'run_id': context.runId};
        },
      );

      expect(result.exitCode, 1);
      expect(result.json['status'], 'FAIL');
      expect(result.json['assertionsAttempted'], 1);
      expect(result.json['artifactPresent'], isFalse);
      expect(
        result.json['detail'],
        'The prepared iOS bundle changed during scenario execution.',
      );
      expect(proofDirectory.existsSync(), isFalse);
    },
  );

  test('P269 iOS prepared custody binds every bundle member', () async {
    final directory = await Directory.systemTemp.createTemp(
      'p269-ios-whole-bundle-custody-',
    );
    addTearDown(() async {
      if (directory.existsSync()) await directory.delete(recursive: true);
    });
    final appFramework = Directory(
      '${directory.path}/Runner.app/Frameworks/App.framework',
    )..createSync(recursive: true);
    final unselectedAsset = File('${appFramework.path}/flutter_assets_blob')
      ..writeAsStringSync('first');
    final first = groupMediaPreparedDirectorySha256(directory);

    unselectedAsset.writeAsStringSync('second');
    final second = groupMediaPreparedDirectorySha256(directory);

    expect(first, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(second, isNot(first));
  });

  test('P269 iOS prepared custody rejects absolute symlinks', () async {
    final directory = await Directory.systemTemp.createTemp(
      'p269-ios-absolute-link-custody-',
    );
    addTearDown(() async {
      if (directory.existsSync()) await directory.delete(recursive: true);
    });
    final member = File('${directory.path}/member')
      ..writeAsStringSync('attested-member');
    Link('${directory.path}/absolute-link').createSync(member.absolute.path);

    expect(
      () => groupMediaPreparedDirectorySha256(directory),
      throwsA(isA<FileSystemException>()),
    );
  });

  test(
    'P269 iOS prepared custody rejects a symlink chain that exits and re-enters the root',
    () async {
      final parent = await Directory.systemTemp.createTemp(
        'p269-ios-link-chain-custody-',
      );
      addTearDown(() async {
        if (parent.existsSync()) await parent.delete(recursive: true);
      });
      final root = Directory('${parent.path}/prepared')..createSync();
      File('${root.path}/member').writeAsStringSync('attested-member');
      Link('${parent.path}/outside-return').createSync('prepared/member');
      final nested = Directory('${root.path}/nested')..createSync();
      Link('${nested.path}/escaping-hop').createSync('../../outside-return');
      Link('${root.path}/chain').createSync('nested/escaping-hop');

      expect(
        Link('${root.path}/chain').resolveSymbolicLinksSync(),
        File('${root.path}/member').resolveSymbolicLinksSync(),
      );
      expect(
        () => groupMediaPreparedDirectorySha256(root),
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  test(
    'group media runner lists exactly the two availability-bounded rows',
    () {
      final parsed = GroupMediaReliabilityRunnerArguments.parse(const <String>[
        '--list-scenarios',
      ]);
      expect(parsed.listScenarios, isTrue);
      expect(groupMediaReliabilityScenarioIds, const <String>[
        groupMediaForegroundRetryAclRoundtripScenario,
        groupMediaIosReceiverBackgroundRecoveryScenario,
      ]);
    },
  );
}

Map<String, Object?> _acceptedArtifact(
  GroupMediaReliabilityRunContext context, {
  String? artifactRunId,
}) {
  final runId = artifactRunId ?? context.runId;
  final senderTransport = _digest('$runId:sender-transport');
  final receiverTransport = _digest('$runId:receiver-transport');
  return <String, Object?>{
    'schema': groupMediaReliabilityArtifactSchema,
    'run_id': runId,
    'scenario': groupMediaForegroundRetryAclRoundtripScenario,
    'prepared_artifact': <String, Object?>{
      'profile': context.preparedArtifact.profile,
      'application_id': groupMediaReliabilityAndroidPackageName,
      'sha256': context.preparedArtifact.sha256Digest,
      'child_builds': 0,
    },
    'device_roles': <String, Object?>{
      'sender': <String, Object?>{
        'platform': 'android',
        'kind': 'physical',
        'device_sha256': senderTransport,
      },
      'receiver': <String, Object?>{
        'platform': 'android',
        'kind': 'emulator',
        'device_sha256': receiverTransport,
      },
    },
    'identity_fingerprints': <String, Object?>{
      'sender': <String, Object?>{
        'account_sha256': _digest('$runId:sender-account'),
        'transport_sha256': senderTransport,
      },
      'receiver': <String, Object?>{
        'account_sha256': _digest('$runId:receiver-account'),
        'transport_sha256': receiverTransport,
      },
    },
    'account_vs_transport_discriminator': <String, Object?>{
      'sender': true,
      'receiver': true,
    },
    'acl_entries': <Object?>[senderTransport, receiverTransport],
    'media': <String, Object?>{
      'uploads_per_blob': <String, Object?>{'jpeg': 1, 'mp4': 1, 'voice': 1},
      'publications_per_message': <String, Object?>{
        'jpeg': 1,
        'mp4': 1,
        'voice': 1,
      },
      'download_attempts': <String, Object?>{'jpeg': 2, 'mp4': 1, 'voice': 1},
      'rendered_surfaces': <String, Object?>{'jpeg': 1, 'mp4': 1, 'voice': 1},
    },
    'role_databases': <String, Object?>{
      for (final role in const <String>['sender', 'receiver'])
        role: <String, Object?>{
          'role_db_path': '$role/group-media.sqlite',
          'database_path_sha256': _digest('$runId:$role-database'),
          'cipher_version': 'SQLCipher 4.6.1',
          'user_version': 104,
          'reopened': true,
          'rows': <Object?>[
            for (final kind in const <String>['jpeg', 'mp4', 'voice'])
              <String, Object?>{
                'run_id': runId,
                'media_kind': kind,
                'message_id': 'message-$kind',
                'blob_id': 'blob-$kind',
                'status': 'done',
                'upload_retry_count': 0,
                'download_retry_count': 0,
              },
          ],
        },
    },
    'retry_passes': <String, Object?>{
      'second_upload_work': 0,
      'second_download_work': 0,
    },
    'cleanup': <String, Object?>{
      'application_id': groupMediaReliabilityAndroidPackageName,
      'artifact_sha256': context.preparedArtifact.sha256Digest,
      for (final role in const <String>['sender', 'receiver'])
        role: <String, Object?>{
          'pre_reset': _resetReceipt(role, 'pre'),
          'post_reset': _resetReceipt(role, 'post'),
        },
      'receipts_distinct': true,
      'app_left_installed': true,
      'production_package_commands': 0,
      'uninstall_commands': 0,
      'pm_clear_commands': 0,
      'broad_delete_commands': 0,
    },
    'flow_events': <Object?>[
      for (final entry in <(String, String, Map<String, Object?>)>[
        ('sender_uploads_settled', 'sender', <String, Object?>{'count': 3}),
        (
          'sender_publications_settled',
          'sender',
          <String, Object?>{'count': 3},
        ),
        (
          'receiver_jpeg_post_claim_pre_commit',
          'receiver',
          <String, Object?>{
            'barrier_name': 'receiver_jpeg_post_claim_pre_commit',
            'marker_atomic': true,
            'prior_status': 'downloading',
            'attempt': 1,
            'old_pid_sha256': _digest('old-pid'),
          },
        ),
        (
          'receiver_process_force_stopped',
          'host',
          <String, Object?>{
            'old_pid_sha256': _digest('old-pid'),
            'old_pid_gone': true,
          },
        ),
        (
          'receiver_process_relaunched',
          'host',
          <String, Object?>{
            'old_pid_sha256': _digest('old-pid'),
            'fresh_pid_sha256': _digest('fresh-pid'),
            'launcher_only': true,
            'pid_changed': true,
          },
        ),
        (
          'receiver_prior_status_read',
          'receiver',
          <String, Object?>{
            'prior_status': 'downloading',
            'after_relaunch': true,
            'attempt': 2,
          },
        ),
        (
          'receiver_downloads_settled',
          'receiver',
          <String, Object?>{
            'settled_attachment_count': 3,
            'first_pass_work': 3,
          },
        ),
        (
          'receiver_media_rendered',
          'receiver',
          <String, Object?>{
            'jpeg_decoder_frame': true,
            'mp4_thumbnail_frame': true,
            'voice_player_loaded': true,
          },
        ),
        (
          'second_retry_pass_zero',
          'host',
          <String, Object?>{
            'scope': 'sender_post_render',
            'upload_work': 0,
            'download_work': 0,
          },
        ),
      ].indexed)
        <String, Object?>{
          'sequence': entry.$1 + 1,
          'name': entry.$2.$1,
          'role': entry.$2.$2,
          'facts': entry.$2.$3,
        },
    ],
  };
}

Map<String, Object?> _acceptedIosArtifact(
  GroupMediaReliabilityRunContext context,
) {
  final runId = context.runId;
  final senderDigest = _digest('$runId:android-sender');
  final receiverDigest = _digest('$runId:ios-receiver');
  final databasePathDigest = _digest('$runId:production-database');
  final companion = context.androidCompanionArtifact!;
  return <String, Object?>{
    'schema': groupMediaIosBackgroundRecoveryArtifactSchema,
    'run_id': runId,
    'scenario': groupMediaIosReceiverBackgroundRecoveryScenario,
    'prepared_artifact': <String, Object?>{
      'profile': context.preparedArtifact.profile,
      'bundle_sha256': context.preparedArtifact.sha256Digest,
      'android_profile': companion.profile,
      'android_sha256': companion.sha256Digest,
      'android_package': groupMediaReliabilityAndroidPackageName,
      'child_builds': 0,
    },
    'cleanup': <String, Object?>{
      'pre_reset': _iosResetFacts('pre', '$runId:ios-main-pre'),
      'post_reset': _iosResetFacts('post', '$runId:ios-main-post'),
      'android_senders': <String, Object?>{
        'phase-a-background-success': _iosAndroidResetFacts(
          runId,
          'phase-a-background-success',
        ),
        'phase-b-stop-at-post-claim': _iosAndroidResetFacts(
          runId,
          'phase-b-stop-at-post-claim',
        ),
      },
      'uninstall_commands': 0,
      'app_left_installed': true,
    },
    'device_roles': <String, Object?>{
      'sender': <String, Object?>{
        'platform': 'android',
        'kind': 'physical',
        'device_sha256': senderDigest,
      },
      'receiver': <String, Object?>{
        'platform': 'ios',
        'kind': 'physical',
        'device_sha256': receiverDigest,
      },
    },
    'xctest': <String, Object?>{
      'selector': groupMediaIosBackgroundRecoveryXctestSelector,
      'invocations': 1,
      'home_presses': 2,
      'manual_steps': 0,
      'sleep_only_waits': 0,
      'local_network_permission': 'automated_or_pregranted',
      'result': 'passed',
    },
    'phase_a': <String, Object?>{
      'critical_task_granted': true,
      'terminal_path': 'normal',
      'native_end_count': 1,
      'durable_status': 'done',
      'download_attempts': 1,
      'ui_effects': 1,
    },
    'phase_b': <String, Object?>{
      'critical_task_granted': true,
      'barrier': 'durable_post_claim_pre_commit',
      'pre_interrupt_status': 'downloading',
      'host_terminations': 1,
      'terminal_path': 'interrupted',
      'native_end_count': 0,
      'relaunch_route': 'root_without_group',
      'resume_after_drain_attempts': 1,
      'durable_status': 'done',
      'download_attempts': 2,
      'ui_effects': 1,
      'fresh_pid': true,
    },
    'boundary_observations': <String, Object?>{
      'database_path_sha256': databasePathDigest,
      'phase_a': _iosObservationPair(
        runId: runId,
        phase: 'a',
        receiverDigest: receiverDigest,
        databasePathDigest: databasePathDigest,
        receiverPid: 4101,
      ),
      'phase_b_claim': _iosObservationPair(
        runId: runId,
        phase: 'b_claim',
        receiverDigest: receiverDigest,
        databasePathDigest: databasePathDigest,
        receiverPid: 4101,
      ),
      'phase_b_recovery': _iosObservationPair(
        runId: runId,
        phase: 'b_recovery',
        receiverDigest: receiverDigest,
        databasePathDigest: databasePathDigest,
        receiverPid: 4202,
      ),
    },
    'flow_events': List<String>.from(groupMediaIosBackgroundRecoveryFlowEvents),
  };
}

Map<String, Object?> _iosAndroidResetFacts(String runId, String action) =>
    <String, Object?>{
      'pre_reset': _iosResetFacts('pre', '$runId:$action:pre'),
      'post_reset': _iosResetFacts('post', '$runId:$action:post'),
      'uninstall_commands': 0,
      'pm_clear_commands': 0,
      'broad_delete_commands': 0,
      'app_left_installed': true,
    };

Map<String, Object?> _iosResetFacts(String phase, String receiptSeed) =>
    <String, Object?>{
      'phase': phase,
      'receipt_sha256': _digest(receiptSeed),
      'keychain_empty': true,
      'database_absent': true,
      'allowlisted_files_absent': true,
    };

Map<String, Object?> _iosObservationPair({
  required String runId,
  required String phase,
  required String receiverDigest,
  required String databasePathDigest,
  required int receiverPid,
}) {
  final isPhaseA = phase == 'a';
  final isRecovery = phase == 'b_recovery';
  final native = <String, Object?>{
    'schema': groupMediaIosNativeObservationSchema,
    'run_id': runId,
    'phase': phase,
    'source': 'physical_idevicesyslog',
    'receiver_device_sha256': receiverDigest,
    'home_observed': true,
    'critical_task_granted': true,
    'terminal_path': isPhaseA
        ? 'normal'
        : isRecovery
        ? 'interrupted'
        : 'none',
    'native_end_count': isPhaseA ? 1 : 0,
    'receiver_pid': receiverPid,
    'host_kill_observed': isRecovery,
  };
  final mediaPhase = isPhaseA ? 'A' : 'B';
  final database = <String, Object?>{
    'schema': groupMediaIosDatabaseObservationSchema,
    'run_id': runId,
    'phase': phase,
    'source': 'production_sqlcipher',
    'receiver_device_sha256': receiverDigest,
    'parent_message_sha256': _digest('P269-PARENT-$mediaPhase-$runId'),
    'ui_effect_sha256': _digest('P269-$mediaPhase-$runId'),
    'database_path_sha256': databasePathDigest,
    'database_reopened': true,
    'cipher_version': 'SQLCipher 4.6.1',
    'user_version': 104,
    'barrier': isPhaseA
        ? 'background_receive_started'
        : isRecovery
        ? 'resume_after_first_group_inbox_drain'
        : 'durable_post_claim_pre_commit',
    'durable_status': phase == 'b_claim' ? 'downloading' : 'done',
    'download_attempts': isRecovery ? 2 : 1,
    'resume_after_drain_attempts': isRecovery ? 1 : 0,
  };
  return <String, Object?>{
    'native': native,
    'database': database,
    'native_sha256': groupMediaIosObservationDigest(native),
    'database_sha256': groupMediaIosObservationDigest(database),
  };
}

Map<String, Object?> _resetReceipt(String role, String phase) =>
    <String, Object?>{
      'phase': phase,
      'receipt_sha256': _digest('$role-$phase-receipt'),
      'process_id_sha256': _digest('$role-$phase-process'),
      'profile': groupMediaReliabilityAndroidBuildProfile,
      'application_id': groupMediaReliabilityAndroidPackageName,
      'secure_storage_empty': true,
      'database_absent': true,
      'allowlisted_files_absent': true,
      'contains_secrets': false,
    };

String _digest(String value) => sha256.convert(utf8.encode(value)).toString();

final class _MalformedProofArtifact extends MapBase<String, Object?> {
  @override
  Object? operator [](Object? key) => throw const FormatException(
    'post-execution proof aggregation is malformed',
  );

  @override
  void operator []=(String key, Object? value) =>
      throw UnsupportedError('immutable');

  @override
  void clear() => throw UnsupportedError('immutable');

  @override
  Iterable<String> get keys => const <String>[];

  @override
  Object? remove(Object? key) => throw UnsupportedError('immutable');
}
