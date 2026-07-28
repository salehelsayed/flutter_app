import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/features/groups/presentation/widgets/expandable_fab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/capture_group_reaction_notification_device.dart'
    as fixture_driver;
import '../../integration_test/scripts/group_reaction_notification_device_criteria.dart';

void main() {
  testWidgets('Orbit create FAB exposes its exact automation semantics', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: <Widget>[
              ExpandableFab(
                fabSemanticLabel: fixture_driver.orbitCreateGroupFabSemanticId,
                items: <ExpandableFabItem>[
                  ExpandableFabItem(
                    label: 'New Group',
                    icon: Icons.group_outlined,
                    onTap: () {},
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

    expect(
      find.bySemanticsLabel(fixture_driver.orbitCreateGroupFabSemanticId),
      findsOneWidget,
    );
  });

  test(
    'create FAB recovery is bounded and re-establishes Orbit once',
    () async {
      final dumps = <String>[
        _uiNode(clickable: true, bounds: '[900,100][1000,200]'),
        _uiNode(clickable: true, bounds: '[900,100][1000,200]'),
        _uiNode(
          contentDescription: fixture_driver.orbitCreateGroupFabSemanticId,
          clickable: true,
          bounds: '[900,100][1000,200]',
        ),
      ];
      var reads = 0;
      var recoveries = 0;

      final center = await fixture_driver.findOrbitCreateGroupFabWithRecovery(
        readUiDump: () async => dumps[reads++],
        reestablishOrbit: () async => recoveries += 1,
        probesBeforeRecovery: 2,
        probesAfterRecovery: 2,
        retryDelay: Duration.zero,
      );

      expect(center, (950, 150));
      expect(reads, 3);
      expect(recoveries, 1);
    },
  );

  test('create FAB recovery stops after its exact bounded probes', () async {
    var reads = 0;
    var recoveries = 0;

    final center = await fixture_driver.findOrbitCreateGroupFabWithRecovery(
      readUiDump: () async {
        reads += 1;
        return _uiNode(
          contentDescription: 'unrelated-action',
          clickable: true,
          bounds: '[900,100][1000,200]',
        );
      },
      reestablishOrbit: () async => recoveries += 1,
      probesBeforeRecovery: 2,
      probesAfterRecovery: 3,
      retryDelay: Duration.zero,
    );

    expect(center, isNull);
    expect(reads, 5);
    expect(recoveries, 1);
  });

  test('group fixture uses exact FAB semantics without force-stop recovery', () {
    final source = File(
      'integration_test/scripts/capture_group_reaction_notification_device.dart',
    ).readAsStringSync();
    final orbitSource = File(
      'lib/features/orbit/presentation/screens/orbit_screen.dart',
    ).readAsStringSync();
    expect(orbitSource, contains("fabSemanticLabel: 'orbit_create_group_fab'"));
    expect(source, contains('findOrbitCreateGroupFabWithRecovery('));
    expect(source, contains('_reestablishOrbitWithoutForceStop'));
    expect(source, isNot(contains('findTopRightClickableNodeCenter(')));
  });

  group('Plan 257 device scenario catalog', () {
    test('lists the five availability-bounded scenarios in stable order', () {
      expect(
        groupReactionNotificationScenarios.map((scenario) => scenario.id),
        const <String>[
          'android_group_message_unread_lifecycle',
          'android_announcement_message_unread_lifecycle',
          'android_group_reaction_recipient',
          'android_announcement_reaction_recipient',
          'ios_announcement_reaction_recipient',
        ],
      );
    });

    test('pins real roles, group types, platforms, and device kinds', () {
      final groupUnread = groupReactionNotificationScenario(
        'android_group_message_unread_lifecycle',
      )!;
      expect(groupUnread.groupType, 'chat');
      expect(groupUnread.senderRole, 'message_sender');
      expect(groupUnread.recipientRole, 'message_recipient');
      expect(groupUnread.senderPlatform, 'android');
      expect(groupUnread.senderDeviceKind, 'emulator');
      expect(groupUnread.recipientPlatform, 'android');
      expect(groupUnread.recipientDeviceKind, 'physical');

      final announcementReaction = groupReactionNotificationScenario(
        'ios_announcement_reaction_recipient',
      )!;
      expect(announcementReaction.groupType, 'announcement');
      expect(announcementReaction.senderRole, 'announcement_member_reactor');
      expect(announcementReaction.recipientRole, 'announcement_admin_author');
      expect(announcementReaction.senderPlatform, 'android');
      expect(announcementReaction.senderDeviceKind, 'physical');
      expect(announcementReaction.recipientPlatform, 'ios');
      expect(announcementReaction.recipientDeviceKind, 'physical');
    });
  });

  group('Plan 257 device artifact contract', () {
    late Directory tempDirectory;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp(
        'plan257-device-criteria-',
      );
    });

    tearDown(() async {
      if (tempDirectory.existsSync()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    for (final scenario in const <String>[
      'android_group_message_unread_lifecycle',
      'android_announcement_message_unread_lifecycle',
      'android_group_reaction_recipient',
      'android_announcement_reaction_recipient',
    ]) {
      test(
        'accepts raw authoritative Android evidence for $scenario',
        () async {
          final artifact = await _writeArtifactFixture(tempDirectory, scenario);

          final result = await validateGroupReactionNotificationArtifact(
            scenario: scenario,
            artifactFile: artifact,
          );

          expect(result.ok, isTrue, reason: result.detail);
        },
      );
    }

    test('accepts a centrally prepared production-FCM Android APK', () async {
      const scenario = 'android_group_message_unread_lifecycle';
      final artifact = await _writeArtifactFixture(
        tempDirectory,
        scenario,
        centralPrebuilt: true,
      );

      final result = await validateGroupReactionNotificationArtifact(
        scenario: scenario,
        artifactFile: artifact,
      );

      expect(result.ok, isTrue, reason: result.detail);
    });

    test('allows a direct central-prebuilt run to install its APK', () async {
      const scenario = 'android_group_message_unread_lifecycle';
      final artifact = await _writeArtifactFixture(
        tempDirectory,
        scenario,
        centralPrebuilt: true,
        parentPreparedAndroidState: false,
      );

      final result = await validateGroupReactionNotificationArtifact(
        scenario: scenario,
        artifactFile: artifact,
      );

      expect(result.ok, isTrue, reason: result.detail);
    });

    test(
      'rejects parent-prepared central APK without both-device SHA verification',
      () async {
        const scenario = 'android_group_message_unread_lifecycle';
        final artifact = await _writeArtifactFixture(
          tempDirectory,
          scenario,
          centralPrebuilt: true,
        );
        _mutateCaptureJson(artifact, 'commandJournal', (journal) {
          final commands = journal['commands'] as List<dynamic>;
          commands.removeWhere((raw) {
            final command = raw as Map<String, dynamic>;
            final args = command['args'] as List<dynamic>;
            return command['stage'] == 'android_role_install' &&
                args.contains('ANDROIDPHYSICAL123') &&
                args.contains('sha256sum');
          });
        });

        final result = await validateGroupReactionNotificationArtifact(
          scenario: scenario,
          artifactFile: artifact,
        );

        expect(result.ok, isFalse);
        expect(result.detail, contains('both-device pm path and SHA-256'));
      },
    );

    test(
      'rejects provider reinstall for parent-prepared central APK',
      () async {
        const scenario = 'android_group_message_unread_lifecycle';
        final artifact = await _writeArtifactFixture(
          tempDirectory,
          scenario,
          centralPrebuilt: true,
        );
        _mutateCaptureJson(artifact, 'commandJournal', (journal) {
          (journal['commands'] as List<dynamic>).add(<String, Object?>{
            'stage': 'provider_registration',
            'executable': 'adb',
            'args': <String>[
              '-s',
              'ANDROIDPHYSICAL123',
              'install',
              'candidate-normal.apk',
            ],
            'exitCode': 0,
            'recordedAt': '2026-07-12T12:00:00.000Z',
          });
        });

        final result = await validateGroupReactionNotificationArtifact(
          scenario: scenario,
          artifactFile: artifact,
        );

        expect(result.ok, isFalse);
        expect(result.detail, contains('forbidden provider reinstall'));
      },
    );

    test(
      'rejects central provenance without parent-prepared state flag',
      () async {
        const scenario = 'android_group_message_unread_lifecycle';
        final artifact = await _writeArtifactFixture(
          tempDirectory,
          scenario,
          centralPrebuilt: true,
        );
        _mutateCaptureJson(artifact, 'candidateBuild', (candidate) {
          candidate.remove('parentPreparedAndroidState');
        });

        final result = await validateGroupReactionNotificationArtifact(
          scenario: scenario,
          artifactFile: artifact,
        );

        expect(result.ok, isFalse);
        expect(
          result.detail,
          contains('central-prebuilt candidate provenance'),
        );
      },
    );

    test('legacy distinct builds still require Android role install', () async {
      const scenario = 'android_group_message_unread_lifecycle';
      final artifact = await _writeArtifactFixture(tempDirectory, scenario);
      _mutateCaptureJson(artifact, 'commandJournal', (journal) {
        final commands = journal['commands'] as List<dynamic>;
        commands.removeWhere((raw) {
          final command = raw as Map<String, dynamic>;
          return command['stage'] == 'android_role_install' &&
              (command['args'] as List<dynamic>).contains('install');
        });
      });

      final result = await validateGroupReactionNotificationArtifact(
        scenario: scenario,
        artifactFile: artifact,
      );

      expect(result.ok, isFalse);
      expect(result.detail, contains('Android-role preparation boundary'));
    });

    test('accepts installed-app exact ADD redrive for a central APK', () async {
      const scenario = 'android_group_reaction_recipient';
      final artifact = await _writeArtifactFixture(
        tempDirectory,
        scenario,
        centralPrebuilt: true,
      );

      final result = await validateGroupReactionNotificationArtifact(
        scenario: scenario,
        artifactFile: artifact,
      );

      expect(result.ok, isTrue, reason: result.detail);
    });

    test('rejects a child Flutter probe for a central APK', () async {
      const scenario = 'android_group_reaction_recipient';
      final artifact = await _writeArtifactFixture(
        tempDirectory,
        scenario,
        centralPrebuilt: true,
      );
      final decoded = _readArtifact(artifact);
      final capture = decoded['capture'] as Map<String, dynamic>;
      final journalReference =
          capture['commandJournal'] as Map<String, dynamic>;
      final journalFile = File(
        '${artifact.parent.path}${Platform.pathSeparator}'
        '${journalReference['path']}',
      );
      final journal =
          jsonDecode(journalFile.readAsStringSync()) as Map<String, dynamic>;
      (journal['commands'] as List<dynamic>).add(<String, Object?>{
        'stage': 'sqlcipher_observation',
        'executable': 'flutter',
        'args': <String>[
          'test',
          'integration_test/group_reaction_notification_sqlcipher_probe_test.dart',
        ],
        'exitCode': 0,
        'recordedAt': '2026-07-12T12:00:00.000Z',
      });
      journalFile.writeAsStringSync(jsonEncode(journal), flush: true);
      _updateEvidenceDigest(journalReference, journalFile);
      _writeArtifact(artifact, decoded);

      final result = await validateGroupReactionNotificationArtifact(
        scenario: scenario,
        artifactFile: artifact,
      );

      expect(result.ok, isFalse);
      expect(result.detail, contains('forbidden child Flutter'));
    });

    test('accepts realistic raw physical-iOS boundary evidence', () async {
      const scenario = 'ios_announcement_reaction_recipient';
      final artifact = await _writeArtifactFixture(tempDirectory, scenario);

      final result = await validateGroupReactionNotificationArtifact(
        scenario: scenario,
        artifactFile: artifact,
      );

      expect(result.ok, isTrue, reason: result.detail);
    });

    test('rejects iOS proof backed only by Android candidate hashes', () async {
      const scenario = 'ios_announcement_reaction_recipient';
      final artifact = await _writeArtifactFixture(tempDirectory, scenario);
      final decoded = _readArtifact(artifact);
      final capture = decoded['capture'] as Map<String, dynamic>;
      final candidateReference =
          capture['candidateBuild'] as Map<String, dynamic>;
      final candidateFile = File(
        '${artifact.parent.path}${Platform.pathSeparator}'
        '${candidateReference['path']}',
      );
      final candidate =
          jsonDecode(candidateFile.readAsStringSync()) as Map<String, dynamic>;
      for (final key in const <String>[
        'iosBundleId',
        'iosBuildTarget',
        'iosE2eAppSha256',
        'iosNormalAppSha256',
        'iosInstallReceipts',
      ]) {
        candidate.remove(key);
      }
      candidateFile.writeAsStringSync(jsonEncode(candidate), flush: true);
      _updateEvidenceDigest(candidateReference, candidateFile);
      _writeArtifact(artifact, decoded);

      final result = await validateGroupReactionNotificationArtifact(
        scenario: scenario,
        artifactFile: artifact,
      );

      expect(result.ok, isFalse);
      expect(
        result.detail,
        contains('lacks distinct signed physical-iOS bundle provenance'),
      );
    });

    test('rejects synthetic marker-only physical-iOS evidence', () async {
      const scenario = 'ios_announcement_reaction_recipient';
      final artifact = await _writeArtifactFixture(
        tempDirectory,
        scenario,
        markerOnly: true,
      );

      final result = await validateGroupReactionNotificationArtifact(
        scenario: scenario,
        artifactFile: artifact,
      );

      expect(result.ok, isFalse);
      expect(result.detail, contains('not raw timestamped relay custody'));
      expect(result.detail, contains('raw matching Springboard reaction card'));
    });

    test('rejects marker-only evidence with valid digests', () async {
      const scenario = 'android_group_reaction_recipient';
      final artifact = await _writeArtifactFixture(
        tempDirectory,
        scenario,
        markerOnly: true,
      );

      final result = await validateGroupReactionNotificationArtifact(
        scenario: scenario,
        artifactFile: artifact,
      );

      expect(result.ok, isFalse);
      expect(result.detail, contains('not raw timestamped relay custody'));
      expect(result.detail, contains('lacks raw'));
    });

    test('rejects Android reaction proof without exact ADD redrive', () async {
      const scenario = 'android_group_reaction_recipient';
      final artifact = await _writeArtifactFixture(tempDirectory, scenario);
      final decoded = _readArtifact(artifact);
      final evidence = decoded['evidence'] as List<dynamic>;
      final senderRecord = evidence.cast<Map<String, dynamic>>().singleWhere(
        (record) => record['kind'] == 'sender_app',
      );
      final senderFile = File(
        '${artifact.parent.path}${Platform.pathSeparator}'
        '${senderRecord['path']}',
      );
      final withoutRedrive = senderFile
          .readAsLinesSync()
          .where(
            (line) =>
                !line.startsWith('MKNOON_257_DUPLICATE_REDRIVE_OBSERVATION '),
          )
          .join('\n');
      senderFile.writeAsStringSync('$withoutRedrive\n', flush: true);
      _updateEvidenceDigest(senderRecord, senderFile);
      _writeArtifact(artifact, decoded);

      final result = await validateGroupReactionNotificationArtifact(
        scenario: scenario,
        artifactFile: artifact,
      );

      expect(result.ok, isFalse);
      expect(result.detail, contains('exact stored-ADD redrive observation'));
    });

    test('rejects retry event not bound to the observed transition', () async {
      const scenario = 'android_group_reaction_recipient';
      final artifact = await _writeArtifactFixture(tempDirectory, scenario);
      final decoded = _readArtifact(artifact);
      final evidence = decoded['evidence'] as List<dynamic>;
      final senderRecord = evidence.cast<Map<String, dynamic>>().singleWhere(
        (record) => record['kind'] == 'sender_app',
      );
      final senderFile = File(
        '${artifact.parent.path}${Platform.pathSeparator}'
        '${senderRecord['path']}',
      );
      senderFile.writeAsStringSync(
        senderFile.readAsStringSync().replaceFirst(
          '"reactionId":"retry257"',
          '"reactionId":"other257"',
        ),
        flush: true,
      );
      _updateEvidenceDigest(senderRecord, senderFile);
      _writeArtifact(artifact, decoded);

      final result = await validateGroupReactionNotificationArtifact(
        scenario: scenario,
        artifactFile: artifact,
      );

      expect(result.ok, isFalse);
      expect(result.detail, contains('distinct transition/state/target'));
    });

    test(
      'rejects exact ADD evidence without production retry launch',
      () async {
        const scenario = 'android_group_reaction_recipient';
        final artifact = await _writeArtifactFixture(tempDirectory, scenario);
        final decoded = _readArtifact(artifact);
        final capture = decoded['capture'] as Map<String, dynamic>;
        final journalReference =
            capture['commandJournal'] as Map<String, dynamic>;
        final journalFile = File(
          '${artifact.parent.path}${Platform.pathSeparator}'
          '${journalReference['path']}',
        );
        final journal =
            jsonDecode(journalFile.readAsStringSync()) as Map<String, dynamic>;
        final commands = journal['commands'] as List<dynamic>;
        commands.removeWhere((raw) {
          final command = raw as Map<String, dynamic>;
          final args = (command['args'] as List<dynamic>).cast<String>();
          return command['stage'] == 'android_reaction_lifecycle' &&
              command['executable'] == 'adb' &&
              args.contains('am') &&
              args.contains('start');
        });
        journalFile.writeAsStringSync(jsonEncode(journal), flush: true);
        _updateEvidenceDigest(journalReference, journalFile);
        _writeArtifact(artifact, decoded);

        final result = await validateGroupReactionNotificationArtifact(
          scenario: scenario,
          artifactFile: artifact,
        );

        expect(result.ok, isFalse);
        expect(result.detail, contains('production retry launch commands'));
      },
    );

    test(
      'rejects an exact ADD probe that can erase sender app state',
      () async {
        const scenario = 'android_group_reaction_recipient';
        final artifact = await _writeArtifactFixture(tempDirectory, scenario);
        final decoded = _readArtifact(artifact);
        final capture = decoded['capture'] as Map<String, dynamic>;
        final journalReference =
            capture['commandJournal'] as Map<String, dynamic>;
        final journalFile = File(
          '${artifact.parent.path}${Platform.pathSeparator}'
          '${journalReference['path']}',
        );
        final journal =
            jsonDecode(journalFile.readAsStringSync()) as Map<String, dynamic>;
        final commands = journal['commands'] as List<dynamic>;
        final probe = commands.cast<Map<String, dynamic>>().firstWhere(
          (command) =>
              command['stage'] == 'android_reaction_lifecycle' &&
              command['executable'] == 'flutter' &&
              (command['args'] as List<dynamic>).contains('drive'),
        );
        (probe['args'] as List<dynamic>).remove('--keep-app-running');
        journalFile.writeAsStringSync(jsonEncode(journal), flush: true);
        _updateEvidenceDigest(journalReference, journalFile);
        _writeArtifact(artifact, decoded);

        final result = await validateGroupReactionNotificationArtifact(
          scenario: scenario,
          artifactFile: artifact,
        );

        expect(result.ok, isFalse);
        expect(result.detail, contains('ordered exact-ADD probe'));
      },
    );

    test('rejects a self-declared generator despite raw evidence', () async {
      const scenario = 'android_announcement_reaction_recipient';
      final artifact = await _writeArtifactFixture(tempDirectory, scenario);
      final decoded = _readArtifact(artifact)
        ..['generatedBy'] = 'self_declared_fixture';
      _writeArtifact(artifact, decoded);

      final result = await validateGroupReactionNotificationArtifact(
        scenario: scenario,
        artifactFile: artifact,
      );

      expect(result.ok, isFalse);
      expect(
        result.detail,
        contains(r'$.generatedBy must equal automated_capture_pipeline'),
      );
    });

    test('rejects wrong roles even when every evidence file exists', () async {
      const scenario = 'android_announcement_reaction_recipient';
      final artifact = await _writeArtifactFixture(tempDirectory, scenario);
      final decoded = _readArtifact(artifact);
      final topology = decoded['topology'] as Map<String, dynamic>;
      final recipient = topology['recipient'] as Map<String, dynamic>;
      recipient['role'] = 'bystander';
      _writeArtifact(artifact, decoded);

      final result = await validateGroupReactionNotificationArtifact(
        scenario: scenario,
        artifactFile: artifact,
      );

      expect(result.ok, isFalse);
      expect(result.detail, contains(r'$.topology.recipient.role'));
    });

    test('rejects a digest mismatch and evidence outside the run', () async {
      const scenario = 'android_group_message_unread_lifecycle';
      final artifact = await _writeArtifactFixture(tempDirectory, scenario);
      final decoded = _readArtifact(artifact);
      final evidence = decoded['evidence'] as List<dynamic>;
      final first = evidence.first as Map<String, dynamic>;
      first['sha256'] = '0' * 64;
      _writeArtifact(artifact, decoded);

      var result = await validateGroupReactionNotificationArtifact(
        scenario: scenario,
        artifactFile: artifact,
      );
      expect(result.detail, contains('SHA-256 mismatch'));

      first
        ..['path'] = '../outside.log'
        ..['sha256'] = '0' * 64;
      _writeArtifact(artifact, decoded);
      result = await validateGroupReactionNotificationArtifact(
        scenario: scenario,
        artifactFile: artifact,
      );
      expect(result.detail, contains('must stay inside'));
    });

    test(
      'rejects persisted provider tokens despite redaction claims',
      () async {
        const scenario = 'ios_announcement_reaction_recipient';
        final artifact = await _writeArtifactFixture(tempDirectory, scenario);
        final decoded = _readArtifact(artifact);
        final evidence = decoded['evidence'] as List<dynamic>;
        final providerRecord = evidence
            .cast<Map<String, dynamic>>()
            .singleWhere((record) => record['kind'] == 'provider_apns');
        final providerFile = File(
          '${artifact.parent.path}${Platform.pathSeparator}'
          '${providerRecord['path']}',
        );
        providerFile.writeAsStringSync(
          '${providerFile.readAsStringSync()}"apnsToken":"secret"\n',
        );
        _updateEvidenceDigest(providerRecord, providerFile);
        _writeArtifact(artifact, decoded);

        final result = await validateGroupReactionNotificationArtifact(
          scenario: scenario,
          artifactFile: artifact,
        );

        expect(result.ok, isFalse);
        expect(result.detail, contains('forbidden sensitive field'));
        expect(result.detail, isNot(contains('secret')));
      },
    );

    test('persists a standardized non-success verdict on failure', () async {
      final verdict = await writeGroupReactionNotificationVerdict(
        outputDirectory: tempDirectory,
        scenario: 'android_group_reaction_recipient',
        ok: false,
        stage: 'configuration',
        status: 'configuration_blocked',
        detail: 'staging_manifest_required',
      );

      final decoded =
          jsonDecode(await verdict.readAsString()) as Map<String, dynamic>;
      expect(decoded['schema'], groupReactionNotificationVerdictSchema);
      expect(decoded['scenario'], 'android_group_reaction_recipient');
      expect(decoded['ok'], isFalse);
      expect(decoded['stage'], 'configuration');
      expect(decoded['status'], 'configuration_blocked');
      expect(decoded['detail'], 'staging_manifest_required');
    });
  });

  group('Plan 257 staging declaration contract', () {
    test('accepts a redacted Android staging declaration', () {
      final result = validateGroupReactionNotificationStagingManifest(
        _validStagingManifest(provider: 'fcm'),
        scenario: groupReactionNotificationScenario(
          'android_group_reaction_recipient',
        )!,
      );

      expect(result.ok, isTrue, reason: result.detail);
    });

    test('requires APNs and the explicit physical-iOS control contract', () {
      final result = validateGroupReactionNotificationStagingManifest(
        _validStagingManifest(provider: 'fcm'),
        scenario: groupReactionNotificationScenario(
          'ios_announcement_reaction_recipient',
        )!,
      );

      expect(result.ok, isFalse);
      expect(result.detail, contains(r'$.provider must equal apns'));
      expect(result.detail, contains(r'$.iosCapture'));
    });

    test('accepts the exact physical-iOS control contract', () {
      final result = validateGroupReactionNotificationStagingManifest(
        _validStagingManifest(provider: 'apns', includeIosCapture: true),
        scenario: groupReactionNotificationScenario(
          'ios_announcement_reaction_recipient',
        )!,
      );

      expect(result.ok, isTrue, reason: result.detail);
    });

    test('rejects production deployment and disabled data reset authority', () {
      final manifest = _validStagingManifest(provider: 'fcm')
        ..['productionDeploymentPerformed'] = true
        ..['allowAppDataReset'] = false;
      final result = validateGroupReactionNotificationStagingManifest(
        manifest,
        scenario: groupReactionNotificationScenario(
          'android_group_message_unread_lifecycle',
        )!,
      );

      expect(result.ok, isFalse);
      expect(result.detail, contains('productionDeploymentPerformed'));
      expect(result.detail, contains('allowAppDataReset'));
    });
  });

  group('Plan 257 relay process flag preflight', () {
    test(
      'probes only the live process flag when systemd uses EnvironmentFile',
      () {
        expect(groupReactionRelayProcessFlagProbe('513276'), const <String>[
          'sudo',
          'grep',
          '-z',
          '-x',
          '-E',
          r'GROUP_REACTION_PUSH_ENABLED=(1|true)',
          '/proc/513276/environ',
        ]);
      },
    );

    test('rejects an unsafe or non-running process id', () {
      expect(
        () => groupReactionRelayProcessFlagProbe('0'),
        throwsFormatException,
      );
      expect(
        () => groupReactionRelayProcessFlagProbe('1;env'),
        throwsFormatException,
      );
    });
  });
}

String _uiNode({
  String text = '',
  String contentDescription = '',
  bool clickable = false,
  String bounds = '[0,0][100,100]',
}) =>
    '<node text="$text" content-desc="$contentDescription" '
    'clickable="$clickable" bounds="$bounds" />';

Map<String, Object?> _validStagingManifest({
  required String provider,
  bool includeIosCapture = false,
}) => <String, Object?>{
  'schema': groupReactionNotificationStagingSchema,
  'version': 1,
  'environment': 'staging',
  'relayActive': true,
  'providerConfigured': true,
  'providerProbeSucceeded': true,
  'productionDeploymentPerformed': false,
  'allowAppDataReset': true,
  'candidateRelayRevision': 'plan257-candidate',
  'candidateRelaySha256': 'a' * 64,
  'provider': provider,
  'relayAddresses': <String>['/dns4/staging.example/tcp/443/wss/p2p/relay'],
  if (includeIosCapture)
    'iosCapture': <String, Object?>{
      'bundleId': 'com.mknoon.app',
      'workspace': 'ios/Runner.xcworkspace',
      'scheme': 'Runner',
      'fixtureCreateSelector':
          'RunnerUITests/NotificationTapUITests/'
          'testCreateAnnouncementReactionFixture',
      'fixtureAuthorSelector':
          'RunnerUITests/NotificationTapUITests/'
          'testAuthorAnnouncementReactionTarget',
      'notificationPrepareSelector':
          'RunnerUITests/NotificationTapUITests/'
          'testPrepareWarmNotificationTap',
      'notificationTapSelector':
          'RunnerUITests/NotificationTapUITests/'
          'testAnnouncementReactionNotificationTap',
      'systemLogExecutable': 'idevicesyslog',
    },
};

Future<File> _writeArtifactFixture(
  Directory root,
  String scenarioId, {
  bool markerOnly = false,
  bool centralPrebuilt = false,
  bool parentPreparedAndroidState = true,
}) async {
  final scenario = groupReactionNotificationScenario(scenarioId)!;
  final directory = Directory(
    '${root.path}${Platform.pathSeparator}$scenarioId',
  )..createSync(recursive: true);
  final senderId = scenario.senderDeviceKind == 'emulator'
      ? 'emulator-5554'
      : '21071FDF600CSC';
  final recipientId = scenario.recipientPlatform == 'ios'
      ? '00008150-001C3C6A3684401C'
      : 'ANDROIDPHYSICAL123';
  final measurements = _measurementsFor(scenario);
  final capture = await _writeCaptureBundle(
    directory,
    scenario: scenario,
    senderId: senderId,
    recipientId: recipientId,
    centralPrebuilt: centralPrebuilt,
    parentPreparedAndroidState: parentPreparedAndroidState,
  );
  final evidence = <Map<String, dynamic>>[];
  for (final requirement in scenario.evidenceRequirements) {
    final file = File(
      '${directory.path}${Platform.pathSeparator}${requirement.kind}.log',
    );
    final contents = markerOnly
        ? '${requirement.markers.join('\n')}\n'
        : _rawEvidence(
            kind: requirement.kind,
            scenario: scenario,
            measurements: measurements,
          );
    await file.writeAsString(contents, flush: true);
    evidence.add(<String, dynamic>{
      'kind': requirement.kind,
      'path': '${requirement.kind}.log',
      'sha256': sha256.convert(await file.readAsBytes()).toString(),
      'bytes': await file.length(),
    });
  }

  final artifact = File(
    '${directory.path}${Platform.pathSeparator}$scenarioId.json',
  );
  _writeArtifact(artifact, <String, dynamic>{
    'schema': groupReactionNotificationArtifactSchema,
    'version': groupReactionNotificationArtifactVersion,
    'scenario': scenario.id,
    'testCase': scenario.testCase,
    'status': 'passed',
    'generatedBy': 'automated_capture_pipeline',
    'capture': capture,
    'measurements': measurements,
    'topology': <String, dynamic>{
      'groupType': scenario.groupType,
      'sender': <String, dynamic>{
        'role': scenario.senderRole,
        'platform': scenario.senderPlatform,
        'deviceKind': scenario.senderDeviceKind,
        'deviceId': senderId,
        'liveDiscovered': true,
        'explicitId': true,
      },
      'recipient': <String, dynamic>{
        'role': scenario.recipientRole,
        'platform': scenario.recipientPlatform,
        'deviceKind': scenario.recipientDeviceKind,
        'deviceId': recipientId,
        'liveDiscovered': true,
        'explicitId': true,
      },
    },
    'execution': <String, dynamic>{
      'automation': 'fully_automated',
      'manualTaps': 0,
      'forceStopUsed': false,
      'candidateBuildInstalled': true,
      'stagingRelay': true,
      'realProvider': true,
    },
    'evidence': evidence,
    'redaction': <String, dynamic>{
      'pushTokensPersisted': false,
      'secretKeysPersisted': false,
      'ciphertextPersisted': false,
      'plaintextPayloadPersisted': false,
      'rawPeerIdsPersisted': false,
    },
  });
  return artifact;
}

Map<String, Object?> _measurementsFor(
  GroupReactionNotificationScenario scenario,
) {
  final messageScenario = scenario.id.endsWith('_message_unread_lifecycle');
  return <String, Object?>{
    'appPackage': 'com.mknoon.app',
    'groupName': scenario.groupType == 'announcement'
        ? 'Release Notes'
        : 'Garden Club',
    'actorName': 'Alice',
    'firstMarker': messageScenario ? 'plan257-first-message' : '',
    'secondMarker': messageScenario ? 'plan257-second-message' : '',
    'targetMarker': messageScenario ? '' : 'plan257-target-message',
    'expectedProviderSendCount': 2,
  };
}

Future<Map<String, dynamic>> _writeCaptureBundle(
  Directory directory, {
  required GroupReactionNotificationScenario scenario,
  required String senderId,
  required String recipientId,
  required bool centralPrebuilt,
  required bool parentPreparedAndroidState,
}) async {
  final configuration = await _writeReferencedJson(
    directory,
    'configuration_verdict.json',
    <String, Object?>{
      'schema': 'mknoon.plan257.configuration-verdict.v1',
      'scenario': scenario.id,
      'ok': true,
      'environment': 'staging',
      'productionDeploymentPerformed': false,
      'sender': <String, Object?>{'deviceId': senderId},
      'recipient': <String, Object?>{'deviceId': recipientId},
      'relay': <String, Object?>{
        'active': true,
        'candidateRevisionMatched': true,
        'groupReactionRolloutEnabled': true,
      },
      'provider': <String, Object?>{
        'configurationChecked': true,
        'kind': scenario.recipientPlatform == 'ios' ? 'apns' : 'fcm',
      },
    },
  );
  final iosInstallReceipts = <String, Map<String, dynamic>>{};
  if (scenario.recipientPlatform == 'ios') {
    for (final mode in const <String>['e2e', 'normal']) {
      iosInstallReceipts[mode] = await _writeReferencedJson(
        directory,
        'ios_${mode}_installed_app_inventory.json',
        <String, Object?>{
          'info': <String, Object?>{
            'deviceIdentifier': recipientId,
            'bundleIdentifier': 'com.mknoon.app',
            'mode': mode,
          },
        },
      );
    }
  }
  final candidateBuild = await _writeReferencedJson(
    directory,
    'candidate_build.json',
    <String, Object?>{
      'schema': 'mknoon.plan257.candidate-build.v1',
      'e2eApkSha256': '1' * 64,
      'normalApkSha256': centralPrebuilt ? '1' * 64 : '2' * 64,
      'sourceProvenance': centralPrebuilt
          ? 'central-prebuilt:android.production_fcm:${'1' * 64}'
          : 'revision:plan257+worktree:fixture',
      if (centralPrebuilt) ...<String, Object?>{
        'buildMode': 'central_prebuilt',
        'buildProfile': 'android.production_fcm',
        'childBuildCount': 0,
        'parentPreparedAndroidState': parentPreparedAndroidState,
      },
      if (scenario.recipientPlatform == 'ios') ...<String, Object?>{
        'iosBundleId': 'com.mknoon.app',
        'iosBuildTarget': 'build/ios/iphoneos/Runner.app',
        'iosE2eAppSha256': '3' * 64,
        'iosNormalAppSha256': '4' * 64,
        'iosInstallReceipts': <Object?>[
          for (final mode in const <String>['e2e', 'normal'])
            <String, Object?>{
              'mode': mode,
              'receipt': iosInstallReceipts[mode],
            },
        ],
      },
    },
  );
  final commandJournal = await _writeReferencedJson(
    directory,
    'command_journal.json',
    <String, Object?>{
      'schema': 'mknoon.plan257.command-journal.v1',
      'scenario': scenario.id,
      'commands': _commandJournal(
        scenario: scenario,
        senderId: senderId,
        recipientId: recipientId,
        centralPrebuilt: centralPrebuilt,
        parentPreparedAndroidState: parentPreparedAndroidState,
      ),
    },
  );
  return <String, dynamic>{
    'configuration': configuration,
    'candidateBuild': candidateBuild,
    'commandJournal': commandJournal,
  };
}

List<Map<String, Object?>> _commandJournal({
  required GroupReactionNotificationScenario scenario,
  required String senderId,
  required String recipientId,
  required bool centralPrebuilt,
  required bool parentPreparedAndroidState,
}) {
  final commands = <Map<String, Object?>>[];
  void add(String stage, String executable, List<String> args) {
    commands.add(<String, Object?>{
      'stage': stage,
      'executable': executable,
      'args': args,
      'exitCode': 0,
      'recordedAt': '2026-07-12T12:00:00.000Z',
    });
  }

  add('device_inventory', 'flutter', <String>['devices', '--machine']);
  add('device_inventory', 'adb', <String>['devices', '-l']);
  add('relay_configuration', 'ssh', <String>[
    'staging-relay',
    'systemctl',
    'show',
    'mknoon-relay',
  ]);
  final androidBuildStage = scenario.recipientPlatform == 'ios'
      ? 'ios_android_sender_build'
      : 'candidate_build';
  if (!centralPrebuilt) {
    add(androidBuildStage, 'flutter', <String>[
      'build',
      'apk',
      '--target=integration_test/group_reaction_notification_device.dart',
    ]);
    add(androidBuildStage, 'flutter', <String>[
      'build',
      'apk',
      '--target=lib/main.dart',
    ]);
  }
  final parentPreparedCentral =
      centralPrebuilt &&
      parentPreparedAndroidState &&
      scenario.recipientPlatform == 'android';
  if (parentPreparedCentral) {
    for (final deviceId in <String>[senderId, recipientId]) {
      add('android_role_install', 'adb', <String>[
        '-s',
        deviceId,
        'shell',
        'pm',
        'path',
        'com.mknoon.app',
      ]);
      add('android_role_install', 'adb', <String>[
        '-s',
        deviceId,
        'shell',
        'sha256sum',
        '/data/app/com.mknoon.app/base.apk',
      ]);
    }
  } else {
    add(
      scenario.recipientPlatform == 'ios'
          ? 'ios_android_sender_build'
          : 'android_role_install',
      'adb',
      <String>['-s', senderId, 'install', 'candidate-e2e.apk'],
    );
  }
  if (scenario.recipientPlatform == 'android') {
    if (parentPreparedCentral) {
      add('provider_registration', 'adb', <String>[
        '-s',
        recipientId,
        'shell',
        'am',
        'start',
        '-W',
        '-n',
        'com.mknoon.app/.MainActivity',
      ]);
    } else {
      add('provider_registration', 'adb', <String>[
        '-s',
        senderId,
        'install',
        'candidate-normal.apk',
      ]);
    }
  }
  if (centralPrebuilt && scenario.recipientPlatform == 'android') {
    add('sqlcipher_observation', 'adb', <String>[
      '-s',
      recipientId,
      'shell',
      'run-as',
      'com.mknoon.app',
      'cp',
      '/data/local/tmp/plan257_intro_e2e_config.json',
      'app_flutter/intro_e2e_config.json',
    ]);
  } else {
    add('sqlcipher_observation', 'flutter', <String>[
      'test',
      'integration_test/group_reaction_notification_sqlcipher_probe_test.dart',
      '-d',
      recipientId,
    ]);
  }
  if (scenario.recipientPlatform == 'ios') {
    add('ios_candidate_build', 'flutter', <String>['build', 'ios', '--debug']);
    for (final mode in const <String>['e2e', 'normal']) {
      add('ios_candidate_install', 'xcrun', <String>[
        'devicectl',
        'device',
        'install',
        'app',
        '--device',
        recipientId,
        'Runner-$mode.app',
      ]);
    }
    add('ios_fixture_staging', 'xcrun', <String>[
      'devicectl',
      'device',
      'copy',
      'to',
      '--device',
      recipientId,
      '--domain-type',
      'appDataContainer',
    ]);
    for (final selector in const <String>[
      'testCreateAnnouncementReactionFixture',
      'testAuthorAnnouncementReactionTarget',
      'testPrepareWarmNotificationTap',
      'testAnnouncementReactionNotificationTap',
    ]) {
      add('ios_xcuitest', 'xcodebuild', <String>[
        'test',
        '-destination',
        'platform=iOS,id=$recipientId',
        '-only-testing:RunnerUITests/NotificationTapUITests/$selector',
      ]);
    }
    add('ios_system_log', 'idevicesyslog', <String>[
      '--udid',
      recipientId,
      '--no-colors',
    ]);
    add('device_binding', 'xcrun', <String>[
      'devicectl',
      'device',
      'info',
      '--device',
      recipientId,
    ]);
  }
  final lifecycleStage = scenario.recipientPlatform == 'ios'
      ? 'ios_reaction_lifecycle'
      : scenario.id.endsWith('_message_unread_lifecycle')
      ? 'android_unread_lifecycle'
      : 'android_reaction_lifecycle';
  add(lifecycleStage, 'adb', <String>[
    '-s',
    senderId,
    'shell',
    'input',
    'tap',
    '540',
    '1600',
  ]);
  if (!scenario.id.endsWith('_message_unread_lifecycle')) {
    add(lifecycleStage, 'adb', <String>[
      '-s',
      senderId,
      'shell',
      'am',
      'kill',
      'com.mknoon.app',
    ]);
    add(lifecycleStage, 'adb', <String>[
      '-s',
      senderId,
      'shell',
      'pidof',
      'com.mknoon.app',
    ]);
    if (scenario.recipientPlatform == 'android') {
      if (centralPrebuilt) {
        add(lifecycleStage, 'adb', <String>[
          '-s',
          senderId,
          'shell',
          'run-as',
          'com.mknoon.app',
          'cp',
          '/data/local/tmp/plan257_intro_e2e_config.json',
          'app_flutter/intro_e2e_config.json',
        ]);
      } else {
        add(lifecycleStage, 'flutter', <String>[
          'drive',
          '--driver',
          'test_driver/integration_test.dart',
          '--target',
          'integration_test/group_reaction_notification_sqlcipher_probe_test.dart',
          '--keep-app-running',
        ]);
        add(lifecycleStage, 'adb', <String>[
          '-s',
          senderId,
          'install',
          'candidate_normal_arm64.apk',
        ]);
      }
      add(lifecycleStage, 'adb', <String>[
        '-s',
        senderId,
        'shell',
        'am',
        'start',
        '-W',
        '-n',
        'com.mknoon.app/.MainActivity',
      ]);
    }
  }
  return commands;
}

Future<Map<String, dynamic>> _writeReferencedJson(
  Directory directory,
  String name,
  Map<String, Object?> value,
) async {
  final file = File('${directory.path}${Platform.pathSeparator}$name');
  await file.writeAsString(jsonEncode(value), flush: true);
  final bytes = await file.readAsBytes();
  return <String, dynamic>{
    'path': name,
    'sha256': sha256.convert(bytes).toString(),
    'bytes': bytes.length,
  };
}

String _rawEvidence({
  required String kind,
  required GroupReactionNotificationScenario scenario,
  required Map<String, Object?> measurements,
}) {
  final messageScenario = scenario.id.endsWith('_message_unread_lifecycle');
  final event = messageScenario ? 'group_message' : 'group_reaction';
  final groupName = measurements['groupName']! as String;
  final actorName = measurements['actorName']! as String;
  final appPackage = measurements['appPackage']! as String;
  final firstMarker = measurements['firstMarker']! as String;
  final secondMarker = measurements['secondMarker']! as String;
  final targetMarker = measurements['targetMarker']! as String;
  switch (kind) {
    case 'relay':
      return '${<String>['2026-07-12T12:00:01.000Z [GROUP_INBOX] Stored message for group '
          'group_hash=group-257 remote_type=$event '
          'group_type=${scenario.groupType}', '2026-07-12T12:00:02.000Z [PUSH] Queued group delivery '
          'event=$event action=add relay_store_matched=true', '2026-07-12T12:00:03.000Z [GROUP_INBOX] Stored message for group '
          'group_hash=group-257 remote_type=$event action=add'].join('\n')}\n';
    case 'provider_fcm':
      final providerMarker = messageScenario
          ? 'Group notification sent to'
          : 'Notification sent to';
      return '${<String>['2026-07-12T12:00:04.000Z [PUSH] $providerMarker '
          'recipient_hash=device-a event=$event delivery_matched=true '
          'transition=1', '2026-07-12T12:00:05.000Z [PUSH] $providerMarker '
          'recipient_hash=device-a event=$event delivery_matched=true '
          'transition=2'].join('\n')}\n';
    case 'provider_apns':
      return '${<String>['2026-07-12T12:00:04.000Z relay[257]: [PUSH] Notification sent to '
          '[peer] (attempt 1/3)', '2026-07-12T12:00:05.000Z relay[257]: [PUSH] Notification sent to '
          '[peer] (attempt 1/3)'].join('\n')}\n';
    case 'sender_app':
      if (messageScenario) {
        return '${<String>[
          _flowLine('GROUP_SEND_MSG_USE_CASE_SUCCESS', <String, Object?>{'marker': firstMarker, 'role': scenario.senderRole}),
          _flowLine('GROUP_SEND_MSG_USE_CASE_SUCCESS', <String, Object?>{'marker': secondMarker, 'role': scenario.senderRole}),
        ].join('\n')}\n';
      }
      return '${<String>[
        _flowLine('GROUP_REACTION_SEND_QUEUED', <String, Object?>{'action': 'add', 'transition': 1, 'role': scenario.senderRole}),
        _flowLine('GROUP_REACTION_REMOVE_QUEUED', <String, Object?>{'action': 'remove', 'transition': 2, 'role': scenario.senderRole}),
        _flowLine('GROUP_REACTION_SEND_QUEUED', <String, Object?>{'action': 'add', 'transition': 3, 'role': scenario.senderRole}),
        _flowLine('RETRY_FAILED_GROUP_REACTION_REPLAY_OK', <String, Object?>{'reactionId': 'retry257', 'action': 'add'}),
        'MKNOON_257_DUPLICATE_REDRIVE_OBSERVATION ${jsonEncode(<String, Object?>{'schema': 'mknoon.plan257.duplicate-redrive-observation.v1', 'scenario': scenario.id, 'prepared': true, 'transitionIdSha256': '1' * 64, 'transitionIdPrefixSha256': sha256.convert(utf8.encode('retry257')).toString(), 'reactionStateIdSha256': '2' * 64, 'targetMessageIdSha256': '3' * 64, 'inboxRetryPayloadSha256': '4' * 64, 'notificationExtensionBound': true, 'signedEnvelopePresent': true, 'previousDeliveryStatus': 'stored'})}',
      ].join('\n')}\n';
    case 'recipient_app':
      if (scenario.recipientPlatform == 'ios') {
        return '${<String>[
          '2026-07-12T12:00:06.000Z Runner[257] [PUSH_DIAG] '
              'ios_notification_open_stored_pending',
          _flowLine('IOS_APNS_INITIAL_NOTIFICATION_OPENED', <String, Object?>{'source': 'native_initial_notification'}),
        ].join('\n')}\n';
      }
      if (messageScenario) {
        return '${<String>[
          _flowLine('GROUP_NOTIFICATION_ROUTE_TARGET_MATCHED', <String, Object?>{'group': groupName}),
          _flowLine('GROUP_CONVERSATION_READ_COMMITTED', <String, Object?>{'unreadAfter': 0}),
        ].join('\n')}\n';
      }
      return '${<String>[
        _flowLine('PUSH_BACKGROUND_REACTION_CRYPTO_PLUGIN_OK', <String, Object?>{'processState': 'killed'}),
        _flowLine('PUSH_ANDROID_DATA_DECRYPT_OK', <String, Object?>{'parity': true}),
        _flowLine('GROUP_NOTIFICATION_ROUTE_TARGET_MATCHED', <String, Object?>{'targetMarker': targetMarker}),
      ].join('\n')}\n';
    case 'android_logcat':
      return '${<String>[
        _flowLine('PUSH_BACKGROUND_REACTION_CRYPTO_PLUGIN_OK', <String, Object?>{'engine': 'background'}),
        _flowLine('PUSH_ANDROID_DATA_DECRYPT_OK', <String, Object?>{'remoteType': event}),
      ].join('\n')}\n';
    case 'sqlcipher_state':
      return _sqlCipherObservation(
        scenario: scenario,
        measurements: measurements,
      );
    case 'android_notification_records':
      return _notificationRecords(
        messageScenario: messageScenario,
        groupName: groupName,
        actorName: actorName,
        appPackage: appPackage,
        firstMarker: firstMarker,
        secondMarker: secondMarker,
      );
    case 'ui_automation':
      return _uiHierarchySnapshots(
        messageScenario: messageScenario,
        groupName: groupName,
        firstMarker: firstMarker,
        secondMarker: secondMarker,
        targetMarker: targetMarker,
      );
    case 'nse_log':
      return '${<String>[
        _flowLine('PUSH_NSE_DECRYPT_OK', <String, Object?>{'kind': 'group_reaction'}),
        _flowLine('PUSH_NSE_DECRYPT_OK', <String, Object?>{'kind': 'group_reaction'}),
      ].join('\n')}\n';
    case 'xcuitest':
      final observation = jsonEncode(<String, Object?>{
        'schema': 'mknoon.plan257.ios-notification-observation.v1',
        'title': groupName,
        'body': '$actorName reacted 👍 to your message',
        'matchingCardCount': 1,
        'containsNewMessageCopy': false,
      });
      return '${<String>["Test Case '-[RunnerUITests.NotificationTapUITests "
          "testAnnouncementReactionNotificationTap]' started.", 'MKNOON_257_IOS_NOTIFICATION_OBSERVATION $observation', 'Announcement reaction tap rendered group $groupName and target '
          '$targetMarker', 'MKNOON_257_ANNOUNCEMENT_REACTION_TAP group_rendered=true '
          'target_message_visible=true manual_taps=0 cold_launch=true', "Test Case '-[RunnerUITests.NotificationTapUITests "
          "testAnnouncementReactionNotificationTap]' passed (8.000 seconds)."].join('\n')}\n';
  }
  throw StateError('Unhandled evidence kind $kind');
}

String _flowLine(String event, Map<String, Object?> fields) {
  return '2026-07-12T12:00:00.000Z I/flutter [FLOW] '
      '${jsonEncode(<String, Object?>{'event': event, 'details': fields})}';
}

String _sqlCipherObservation({
  required GroupReactionNotificationScenario scenario,
  required Map<String, Object?> measurements,
}) {
  final messageScenario = scenario.id.endsWith('_message_unread_lifecycle');
  const targetDigest =
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
  final markers = messageScenario
      ? <Map<String, Object?>>[
          <String, Object?>{'marker': 'first', 'incoming': true, 'read': true},
          <String, Object?>{'marker': 'second', 'incoming': true, 'read': true},
        ]
      : <Map<String, Object?>>[
          <String, Object?>{
            'marker': 'target',
            'incoming': false,
            'read': true,
            'idSha256': targetDigest,
          },
        ];
  final observation = <String, Object?>{
    'schema': 'mknoon.plan257.sqlcipher-observation.v1',
    'scenario': scenario.id,
    'groupName': measurements['groupName'],
    'groupRows': 1,
    'groupType': scenario.groupType,
    'unreadCount': 0,
    'reactionMessageRows': 0,
    'markers': markers,
    'reactionRows': messageScenario ? 0 : 1,
    if (!messageScenario) 'reactionEmoji': '👍',
    if (!messageScenario) 'reactionTargetIdSha256': targetDigest,
  };
  return 'MKNOON_257_SQLCIPHER_OBSERVATION ${jsonEncode(observation)}\n';
}

String _notificationRecords({
  required bool messageScenario,
  required String groupName,
  required String actorName,
  required String appPackage,
  required String firstMarker,
  required String secondMarker,
}) {
  final sourceNames = messageScenario
      ? const <String>[
          'notification_message_first.log',
          'notification_message_second.log',
        ]
      : const <String>[
          'notification_reaction_first.log',
          'notification_reaction_replacement.log',
        ];
  final bodies = messageScenario
      ? <String>[firstMarker, secondMarker]
      : <String>[
          '$actorName reacted 👍 to your message',
          '$actorName reacted 👍 to your message',
        ];
  final buffer = StringBuffer();
  for (var index = 0; index < sourceNames.length; index++) {
    buffer
      ..writeln('source_file=${sourceNames[index]}')
      ..writeln(
        'NotificationRecord(pkg=$appPackage id=257 tag=group-257 user=0)',
      )
      ..writeln('  android.title=String ($groupName)')
      ..writeln('  android.text=String (${bodies[index]})')
      ..writeln('  android.groupKey=String (group-257)')
      ..writeln('  postTime=2026-07-12T12:00:0${index + 4}.000Z');
  }
  return buffer.toString();
}

String _uiHierarchySnapshots({
  required bool messageScenario,
  required String groupName,
  required String firstMarker,
  required String secondMarker,
  required String targetMarker,
}) {
  final snapshots = messageScenario
      ? <String, List<String>>{
          'ui_unread_0.xml': <String>['Open group $groupName'],
          'ui_unread_1.xml': <String>[
            'Open group $groupName, 1 unread message',
          ],
          'ui_unread_1_after_dismiss.xml': <String>[
            'Open group $groupName, 1 unread message',
          ],
          'ui_unread_2.xml': <String>[
            'Open group $groupName, 2 unread messages',
          ],
          'ui_conversation_after_tap.xml': <String>[firstMarker, secondMarker],
          'ui_unread_0_after_tap.xml': <String>['Open group $groupName'],
        }
      : <String, List<String>>{
          'ui_reaction_unread_0_before.xml': <String>['Open group $groupName'],
          'ui_reaction_target_after_tap.xml': <String>[targetMarker],
          'ui_reaction_unread_0_after.xml': <String>['Open group $groupName'],
        };
  final buffer = StringBuffer();
  for (final entry in snapshots.entries) {
    buffer
      ..writeln('source_file=${entry.key}')
      ..writeln('<hierarchy rotation="0">')
      ..writeln(
        '  <node text="${entry.value.join(' | ')}" '
        'content-desc="${entry.value.join(' | ')}"/>',
      )
      ..writeln('</hierarchy>');
  }
  return buffer.toString();
}

Map<String, dynamic> _readArtifact(File artifact) {
  return jsonDecode(artifact.readAsStringSync()) as Map<String, dynamic>;
}

void _mutateCaptureJson(
  File artifact,
  String captureKey,
  void Function(Map<String, dynamic> value) mutate,
) {
  final decoded = _readArtifact(artifact);
  final capture = decoded['capture'] as Map<String, dynamic>;
  final reference = capture[captureKey] as Map<String, dynamic>;
  final file = File(
    '${artifact.parent.path}${Platform.pathSeparator}${reference['path']}',
  );
  final value = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  mutate(value);
  file.writeAsStringSync(jsonEncode(value), flush: true);
  _updateEvidenceDigest(reference, file);
  _writeArtifact(artifact, decoded);
}

void _writeArtifact(File artifact, Map<String, dynamic> decoded) {
  artifact.writeAsStringSync(jsonEncode(decoded), flush: true);
}

void _updateEvidenceDigest(Map<String, dynamic> record, File file) {
  final bytes = file.readAsBytesSync();
  record['bytes'] = bytes.length;
  record['sha256'] = sha256.convert(bytes).toString();
}
