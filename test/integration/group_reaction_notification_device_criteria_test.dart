import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/features/groups/presentation/widgets/expandable_fab.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/capture_group_reaction_notification_device.dart'
    as fixture_driver;
import '../../integration_test/scripts/group_reaction_notification_device_criteria.dart';
import '../../integration_test/scripts/reaction_notification_proof_support.dart';

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
    test('Android reaction copy is privacy bounded and omits the emoji', () {
      final body = groupReactionNotificationExpectedAndroidReactionBody(
        'Alice',
      );

      expect(body, 'Alice reacted to your message');
      expect(body, isNot(contains('👍')));
    });

    test('lists the seven availability-bounded scenarios in stable order', () {
      expect(
        groupReactionNotificationScenarios.map((scenario) => scenario.id),
        const <String>[
          'android_group_message_unread_lifecycle',
          'android_announcement_message_unread_lifecycle',
          'android_group_reaction_recipient',
          'android_announcement_reaction_recipient',
          'android_group_reaction_recipient_background_connected',
          'ios_announcement_reaction_recipient',
          iosChatGroupMessageAndReactionScenarioId,
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

      final chatGroupIos = groupReactionNotificationScenario(
        iosChatGroupMessageAndReactionScenarioId,
      )!;
      expect(chatGroupIos.groupType, 'chat');
      expect(chatGroupIos.senderRole, 'member_message_sender_and_reactor');
      expect(chatGroupIos.recipientRole, 'chat_member_target_author');
      expect(chatGroupIos.senderPlatform, 'android');
      expect(chatGroupIos.senderDeviceKind, 'physical');
      expect(chatGroupIos.recipientPlatform, 'ios');
      expect(chatGroupIos.recipientDeviceKind, 'physical');
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
      groupReactionBackgroundConnectedScenarioId,
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

    // -----------------------------------------------------------------------
    // Plan 386 W1 (G16) — the lane grades on grammar relay v1.8.0 emits, and
    // on the relay's own counters rather than on a journal substring.
    // -----------------------------------------------------------------------

    test(
      'reaction provider evidence accepts the v1.8.0 outcome journal',
      () async {
        const scenario = 'android_group_reaction_recipient';
        final artifact = await _writeArtifactFixture(tempDirectory, scenario);
        _rewriteEvidence(
          artifact,
          'provider_fcm',
          '2026-07-12T12:00:04.000Z [PUSH] outcome=success attempt=1 '
              'total_attempts=3\n'
              '2026-07-12T12:00:05.000Z [PUSH] outcome=success '
              'fallback=strict\n',
        );

        final result = await validateGroupReactionNotificationArtifact(
          scenario: scenario,
          artifactFile: artifact,
        );

        expect(result.ok, isTrue, reason: result.detail);
      },
    );

    test(
      'reaction provider evidence rejects a journal with no accepted send',
      () async {
        const scenario = 'android_group_reaction_recipient';
        // Reused VERBATIM from the payload lane's rejection list
        // (`android_notification_payload_campaign_support_test.dart:401-417`),
        // plus `[PUSH] outcome=registered`. `registered` is named here rather
        // than left to the executor because it is the one negative that a lazy
        // repair — `contains('[PUSH]')` — would let through.
        for (final journal in const <String>[
          '2026-07-12T12:00:04.000Z [PUSH] outcome=failed attempts=3',
          '2026-07-12T12:00:04.000Z [PUSH] outcome=retrying attempt=1 '
              'total_attempts=3',
          '2026-07-12T12:00:04.000Z [PUSH] outcome=invalid_token '
              'reason=typed_unregistered',
          '2026-07-12T12:00:04.000Z [PUSH] provider unavailable '
              'outcome=provider_unavailable',
          '2026-07-12T12:00:04.000Z [PUSH] outcome=success_but_not_really',
          '2026-07-12T12:00:04.000Z [PUSH] outcome=registered',
          // The pre-v1.8.0 recipient-bearing line `8d86501e4` deleted. Accepting
          // it would let a rolled-back relay pass the repaired grammar.
          '2026-07-12T12:00:04.000Z [PUSH] Notification sent to '
              '12D3KooWRecipientPee (attempt 1/3)',
        ]) {
          final artifact = await _writeArtifactFixture(
            Directory('${tempDirectory.path}/${journal.hashCode}')
              ..createSync(recursive: true),
            scenario,
          );
          _rewriteEvidence(artifact, 'provider_fcm', '$journal\n');

          final result = await validateGroupReactionNotificationArtifact(
            scenario: scenario,
            artifactFile: artifact,
          );

          expect(result.ok, isFalse, reason: journal);
          expect(
            result.detail,
            contains('provider acceptance'),
            reason: journal,
          );
        }
      },
    );

    test('provider evidence is graded by counter delta, per lane', () async {
      for (final scenario in const <String>[
        'android_group_reaction_recipient',
        'android_group_message_unread_lifecycle',
      ]) {
        final artifact = await _writeArtifactFixture(
          Directory('${tempDirectory.path}/delta-$scenario')
            ..createSync(recursive: true),
          scenario,
        );

        final result = await validateGroupReactionNotificationArtifact(
          scenario: scenario,
          artifactFile: artifact,
        );

        expect(result.ok, isTrue, reason: '$scenario: ${result.detail}');
      }
    });

    test('a declined recipient reds', () async {
      // `route_error` emits NO journal line at all, so "at least one dispatch
      // happened" cannot see a recipient the relay silently dropped. The
      // attempted delta alone still reads 2 here — only the zero-decline
      // conjuncts catch it.
      for (final rejection in const <(String, double, double)>[
        ('route error', 1, 0),
        ('incapable skipped', 0, 1),
      ]) {
        const scenario = 'android_group_reaction_recipient';
        final artifact = await _writeArtifactFixture(
          Directory('${tempDirectory.path}/declined-${rejection.$1}')
            ..createSync(recursive: true),
          scenario,
        );
        _rewriteEvidence(
          artifact,
          'relay_metrics',
          groupReactionRelayMetricsFixture(
            routeErrorDelta: rejection.$2,
            incapableSkippedDelta: rejection.$3,
          ),
        );

        final result = await validateGroupReactionNotificationArtifact(
          scenario: scenario,
          artifactFile: artifact,
        );

        expect(result.ok, isFalse, reason: rejection.$1);
      }
    });

    test('an empty window reds', () async {
      const scenario = 'android_group_reaction_recipient';
      for (final broken in <String>[
        // No growth at all: the relay never woke anybody.
        groupReactionRelayMetricsFixture(attemptedDelta: 0),
        // One transition instead of two.
        groupReactionRelayMetricsFixture(attemptedDelta: 1),
        // A truncated file with only a baseline — must never grade as "no
        // growth", which is exactly what a lenient parser would do.
        groupReactionRelayMetricsFixture(includeFinalPhase: false),
        // A relay RESTART. The graded deltas here look perfect in isolation
        // (attempted +2); only the sentinel going backwards reveals that the
        // two phases came from different processes.
        groupReactionRelayMetricsFixture(relayRestarted: true),
        // A scrape with no liveness sentinel at all — a truncated or
        // hand-assembled file, which must never grade as a clean window.
        '$relayMetricsPhaseMarker$relayMetricsBaselinePhase\n'
            'relay_group_reaction_wake_total{outcome="attempted"} 40.0\n'
            '$relayMetricsPhaseMarker$relayMetricsFinalPhase\n'
            'relay_group_reaction_wake_total{outcome="attempted"} 42.0\n',
      ]) {
        final artifact = await _writeArtifactFixture(
          Directory('${tempDirectory.path}/empty-${broken.hashCode}')
            ..createSync(recursive: true),
          scenario,
        );
        _rewriteEvidence(artifact, 'relay_metrics', broken);

        final result = await validateGroupReactionNotificationArtifact(
          scenario: scenario,
          artifactFile: artifact,
        );

        expect(result.ok, isFalse, reason: broken);
      }
    });

    test(
      'background-connected push origin is proven by the v1.8.0 wake line',
      () async {
        const scenario = groupReactionBackgroundConnectedScenarioId;
        final artifact = await _writeArtifactFixture(tempDirectory, scenario);

        final accepted = await validateGroupReactionNotificationArtifact(
          scenario: scenario,
          artifactFile: artifact,
        );
        expect(accepted.ok, isTrue, reason: accepted.detail);

        // The deleted `remote_type=` attribute must not come back as a
        // requirement: a real v1.8.0 journal does not carry it.
        final withoutDispatch = await _writeArtifactFixture(
          Directory('${tempDirectory.path}/no-dispatch')
            ..createSync(recursive: true),
          scenario,
        );
        _rewriteEvidence(
          withoutDispatch,
          'relay',
          '2026-07-12T12:00:01.000Z [GROUP_INBOX] Stored message for group '
              'group_hash=group-257\n'
              '2026-07-12T12:00:03.500Z [GROUP_REACTION_WAKE] '
              'outcome=no_wake_recipients\n'
              '2026-07-12T12:00:04.000Z [PUSH] outcome=success attempt=1 '
              'total_attempts=3\n',
        );

        final rejected = await validateGroupReactionNotificationArtifact(
          scenario: scenario,
          artifactFile: withoutDispatch,
        );
        expect(rejected.ok, isFalse);
        expect(rejected.detail, contains('push-origin discrimination'));
      },
    );

    test('the reaction lane calls the shared v1.8.0 predicate', () {
      final criteria = File(
        'integration_test/scripts/'
        'group_reaction_notification_device_criteria.dart',
      ).readAsStringSync();
      expect(
        criteria,
        contains('relayJournalContainsAndroidProviderSend('),
        reason: 'the reaction lane must reuse Plan 380 W0\'s predicate',
      );

      // Exactly one file may DEFINE the acceptance grammar. Without this a
      // local copy passes every other row here and then drifts away from the
      // payload lane's three host pins the first time either side is edited.
      //
      // The needle is assembled at runtime from two halves so it never appears
      // verbatim in THIS file. A census that had to exclude its own path would
      // leave a hole exactly the size of a test file.
      // Joined rather than written adjacent: adjacent literals are folded by
      // the compiler AND by a plain source scan, which would put the needle
      // verbatim in this file and make the census match itself.
      final needle = <String>[
        'RegExp(',
        r"r'\[PUSH\]\s+outcome=success",
      ].join();
      final definingFiles = <String>[];
      for (final entity
          in Directory('integration_test')
              .listSync(recursive: true)
              .followedBy(Directory('lib').listSync(recursive: true))
              .followedBy(Directory('test').listSync(recursive: true))) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity
            .readAsStringSync()
            .replaceAll(RegExp(r'\s+'), '')
            .contains(needle)) {
          definingFiles.add(entity.path);
        }
      }
      expect(
        definingFiles,
        <String>[
          'integration_test/support/android_notification_payload_campaign.dart',
        ],
        reason: 'the v1.8.0 acceptance regex must have exactly one definition',
      );
    });

    test(
      'background-connected reaction proof rejects process termination',
      () async {
        const scenario = groupReactionBackgroundConnectedScenarioId;
        final artifact = await _writeArtifactFixture(tempDirectory, scenario);
        _mutateCaptureJson(artifact, 'commandJournal', (journal) {
          (journal['commands'] as List<dynamic>).add(<String, Object?>{
            'stage': 'android_reaction_lifecycle',
            'executable': 'adb',
            'args': <String>[
              '-s',
              'ANDROIDPHYSICAL123',
              'shell',
              'am',
              'kill',
              'com.mknoon.app',
            ],
            'exitCode': 0,
            'recordedAt': '2026-07-12T12:00:02.000Z',
          });
        });

        final result = await validateGroupReactionNotificationArtifact(
          scenario: scenario,
          artifactFile: artifact,
        );

        expect(result.ok, isFalse);
        expect(result.detail, contains('process termination'));
      },
    );

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

    // -----------------------------------------------------------------------
    // Plan 389 (G11) — the killed reaction lanes post a deliberate warm-up card
    // into a second group, so the graded assertions are group-scoped instead of
    // package-wide. The widening is a gate RELAXATION, so every row below that
    // proves a rejection is load-bearing, not decoration.
    // -----------------------------------------------------------------------

    const reactionScenario = 'android_group_reaction_recipient';
    const appPackage = 'com.mknoon.app';
    const gradedGroup = 'Garden Club';
    const foreignGroup = 'Other Club';
    const warmupBody = 'TC389Warm0f1e2d3c4b5a';
    final warmupGroup = groupReactionNotificationWarmupGroupName(gradedGroup);
    final reactionBody = groupReactionNotificationExpectedAndroidReactionBody(
      'Alice',
    );
    ({int id, String title, String body}) card(
      int id,
      String title,
      String body,
    ) => (id: id, title: title, body: body);

    // TC-389-01.
    test('a warm-up-group card alongside the graded card validates', () async {
      final artifact = await _writeArtifactFixture(
        tempDirectory,
        reactionScenario,
      );
      _rewriteEvidence(
        artifact,
        'android_notification_records',
        _notificationRecordBlocks(
          appPackage: appPackage,
          blocks: <String, List<({int id, String title, String body})>>{
            'notification_reaction_first.log':
                <({int id, String title, String body})>[
                  card(257, gradedGroup, reactionBody),
                  card(389, warmupGroup, warmupBody),
                ],
            'notification_reaction_replacement.log':
                <({int id, String title, String body})>[
                  card(257, gradedGroup, reactionBody),
                  card(389, warmupGroup, warmupBody),
                ],
          },
        ),
      );

      final result = await validateGroupReactionNotificationArtifact(
        scenario: reactionScenario,
        artifactFile: artifact,
      );

      expect(result.ok, isTrue, reason: result.detail);
    });

    // TC-389-02. The kill for the naive widening — "at least one graded card
    // across the accumulated list". That shape leaves `cards.length == 1`, so
    // the replacement-identity guard never fires and an artifact proving the
    // lane posted ONE card and never replaced it would validate.
    test('a replacement block without a graded card is rejected', () async {
      final artifact = await _writeArtifactFixture(
        tempDirectory,
        reactionScenario,
      );
      _rewriteEvidence(
        artifact,
        'android_notification_records',
        _notificationRecordBlocks(
          appPackage: appPackage,
          blocks: <String, List<({int id, String title, String body})>>{
            'notification_reaction_first.log':
                <({int id, String title, String body})>[
                  card(257, gradedGroup, reactionBody),
                  card(389, warmupGroup, warmupBody),
                ],
            'notification_reaction_replacement.log':
                <({int id, String title, String body})>[
                  card(389, warmupGroup, warmupBody),
                ],
          },
        ),
      );

      final result = await validateGroupReactionNotificationArtifact(
        scenario: reactionScenario,
        artifactFile: artifact,
      );

      expect(result.ok, isFalse);
      expect(result.detail, contains('exactly one graded group card'));
    });

    // TC-389-03. The allow-list is CLOSED. A widening that merely EXCLUDED the
    // warm-up group would accept any third card, and with it a duplicate card
    // in an unrelated conversation, a leaked card, and a card posted by a path
    // the lane never exercises.
    test(
      'an app card outside the graded and warm-up groups is rejected',
      () async {
        final artifact = await _writeArtifactFixture(
          tempDirectory,
          reactionScenario,
        );
        _rewriteEvidence(
          artifact,
          'android_notification_records',
          _notificationRecordBlocks(
            appPackage: appPackage,
            blocks: <String, List<({int id, String title, String body})>>{
              'notification_reaction_first.log':
                  <({int id, String title, String body})>[
                    card(257, gradedGroup, reactionBody),
                    card(389, warmupGroup, warmupBody),
                    card(701, foreignGroup, 'unrelated conversation copy'),
                  ],
              'notification_reaction_replacement.log':
                  <({int id, String title, String body})>[
                    card(257, gradedGroup, reactionBody),
                    card(389, warmupGroup, warmupBody),
                  ],
            },
          ),
        );

        final result = await validateGroupReactionNotificationArtifact(
          scenario: reactionScenario,
          artifactFile: artifact,
        );

        expect(result.ok, isFalse);
        expect(
          result.detail,
          contains('outside the graded and warm-up groups'),
        );
      },
    );

    // TC-389-04. The graded card is still pinned exactly. At HEAD this gate was
    // unreachable: the per-block count `continue`d before the card was ever
    // collected, so it only becomes operative once the count is widened.
    // Deliberately NOT "New Message" copy, so the failure isolates the body
    // equality rather than the copy scan.
    test('a graded-group card with the wrong body still reds', () async {
      final artifact = await _writeArtifactFixture(
        tempDirectory,
        reactionScenario,
      );
      _rewriteEvidence(
        artifact,
        'android_notification_records',
        _notificationRecordBlocks(
          appPackage: appPackage,
          blocks: <String, List<({int id, String title, String body})>>{
            'notification_reaction_first.log':
                <({int id, String title, String body})>[
                  card(257, gradedGroup, 'TC257Target1755600000000000'),
                  card(389, warmupGroup, warmupBody),
                ],
            'notification_reaction_replacement.log':
                <({int id, String title, String body})>[
                  card(257, gradedGroup, reactionBody),
                  card(389, warmupGroup, warmupBody),
                ],
          },
        ),
      );

      final result = await validateGroupReactionNotificationArtifact(
        scenario: reactionScenario,
        artifactFile: artifact,
      );

      expect(result.ok, isFalse);
      expect(result.detail, contains('reaction title/body mismatch'));
    });

    // TC-389-05. On device the two Orbit rows are SIBLING NODES of one
    // `<hierarchy>`, so the fixture is single-block on purpose: the most likely
    // wrong qualifier — two independent `contains` on the same block — passes a
    // two-block fixture and reds this one.
    test('unread semantics are graded per group', () async {
      final tolerated = await _writeArtifactFixture(
        Directory('${tempDirectory.path}/unread-tolerated')
          ..createSync(recursive: true),
        reactionScenario,
      );
      _rewriteEvidence(
        tolerated,
        'ui_automation',
        _uiHierarchyBlocks(<String, List<String>>{
          'ui_reaction_unread_0_before.xml': <String>[
            'Open group $gradedGroup',
          ],
          'ui_reaction_target_after_tap.xml': <String>[
            'plan257-target-message',
          ],
          'ui_reaction_unread_0_after.xml': <String>[
            'Open group $gradedGroup',
            'Open group $warmupGroup, 1 unread message',
          ],
        }),
      );

      final toleratedResult = await validateGroupReactionNotificationArtifact(
        scenario: reactionScenario,
        artifactFile: tolerated,
      );

      expect(toleratedResult.ok, isTrue, reason: toleratedResult.detail);

      final leaked = await _writeArtifactFixture(
        Directory('${tempDirectory.path}/unread-leaked')
          ..createSync(recursive: true),
        reactionScenario,
      );
      _rewriteEvidence(
        leaked,
        'ui_automation',
        _uiHierarchyBlocks(<String, List<String>>{
          'ui_reaction_unread_0_before.xml': <String>[
            'Open group $gradedGroup',
          ],
          'ui_reaction_target_after_tap.xml': <String>[
            'plan257-target-message',
          ],
          'ui_reaction_unread_0_after.xml': <String>[
            'Open group $gradedGroup, 2 unread messages',
            'Open group $warmupGroup, 1 unread message',
          ],
        }),
      );

      final leakedResult = await validateGroupReactionNotificationArtifact(
        scenario: reactionScenario,
        artifactFile: leaked,
      );

      expect(leakedResult.ok, isFalse);
      expect(
        leakedResult.detail,
        contains('reaction created unread semantics'),
      );
    });

    // TC-389-06. The message branch keeps today's PACKAGE-WIDE card contract.
    // The warm-up-titled card is the sub-case that matters: a truly foreign
    // card is rejected by the reaction form too, so only this one kills the
    // mutation that drops the `messageScenario` selector.
    test('the message branch still rejects a foreign card', () async {
      const messageScenario = 'android_group_message_unread_lifecycle';
      for (final extra in <({int id, String title, String body})>[
        card(389, warmupGroup, warmupBody),
        card(701, foreignGroup, 'unrelated conversation copy'),
      ]) {
        final artifact = await _writeArtifactFixture(
          Directory('${tempDirectory.path}/message-${extra.id}')
            ..createSync(recursive: true),
          messageScenario,
        );
        _rewriteEvidence(
          artifact,
          'android_notification_records',
          _notificationRecordBlocks(
            appPackage: appPackage,
            blocks: <String, List<({int id, String title, String body})>>{
              'notification_message_first.log':
                  <({int id, String title, String body})>[
                    card(257, gradedGroup, 'plan257-first-message'),
                    extra,
                  ],
              'notification_message_second.log':
                  <({int id, String title, String body})>[
                    card(257, gradedGroup, 'plan257-second-message'),
                  ],
            },
          ),
        );

        final result = await validateGroupReactionNotificationArtifact(
          scenario: messageScenario,
          artifactFile: artifact,
        );

        expect(result.ok, isFalse, reason: extra.title);
        expect(
          result.detail,
          contains('malformed raw card'),
          reason: extra.title,
        );
      }
    });

    // TC-389-07. The warm-up is machine-enforced. A ported `>= 2` rule would be
    // vacuous: the lane already emitted two post-kill wakes (ADD and re-ADD)
    // with no warm-up at all, and `expectedRelayWakeAttempts` is pinned to 2.
    test('the graded reaction may not ride the first post-kill wake', () async {
      for (final wakes in const <int>[0, 1, 2]) {
        final artifact = await _writeArtifactFixture(
          Directory('${tempDirectory.path}/wakes-$wakes')
            ..createSync(recursive: true),
          reactionScenario,
        );
        _rewriteEvidence(
          artifact,
          'recipient_app',
          _killedReactionRecipientApp(
            wakes: wakes,
            targetMarker: 'plan257-target-message',
          ),
        );

        final result = await validateGroupReactionNotificationArtifact(
          scenario: reactionScenario,
          artifactFile: artifact,
        );

        expect(result.ok, isFalse, reason: '$wakes wakes');
        expect(
          result.detail,
          contains('fewer than three post-kill'),
          reason: '$wakes wakes',
        );
      }

      final warmed = await _writeArtifactFixture(
        Directory('${tempDirectory.path}/wakes-3')..createSync(recursive: true),
        reactionScenario,
      );
      _rewriteEvidence(
        warmed,
        'recipient_app',
        _killedReactionRecipientApp(
          wakes: 3,
          targetMarker: 'plan257-target-message',
        ),
      );

      final result = await validateGroupReactionNotificationArtifact(
        scenario: reactionScenario,
        artifactFile: warmed,
      );

      expect(result.ok, isTrue, reason: result.detail);
    });

    // TC-389-07, negative half of the gate: the background-connected reaction
    // keeps its process alive, pays no cold-isolate cost, sends no warm-up, and
    // must NOT be held to the post-kill floor.
    test(
      'the background-connected lane is exempt from the wake floor',
      () async {
        final artifact = await _writeArtifactFixture(
          tempDirectory,
          groupReactionBackgroundConnectedScenarioId,
        );

        final result = await validateGroupReactionNotificationArtifact(
          scenario: groupReactionBackgroundConnectedScenarioId,
          artifactFile: artifact,
        );

        expect(result.ok, isTrue, reason: result.detail);
        expect(
          File(
            '${artifact.parent.path}${Platform.pathSeparator}recipient_app.log',
          ).readAsStringSync(),
          isNot(contains('PUSH_BACKGROUND_MESSAGE_RECEIVED')),
        );
      },
    );
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

    test('chat-group iOS selectors are scenario-aware', () {
      final scenario = groupReactionNotificationScenario(
        iosChatGroupMessageAndReactionScenarioId,
      )!;
      final manifest = _validStagingManifest(
        provider: 'apns',
        includeIosCapture: true,
      );
      final iosCapture = Map<String, Object?>.from(
        manifest['iosCapture']! as Map,
      )..addAll(groupReactionNotificationIosSelectorsFor(scenario));
      manifest['iosCapture'] = iosCapture;

      final accepted = validateGroupReactionNotificationStagingManifest(
        manifest,
        scenario: scenario,
      );
      expect(accepted.ok, isTrue, reason: accepted.detail);

      final legacySelectors = _validStagingManifest(
        provider: 'apns',
        includeIosCapture: true,
      );
      final rejected = validateGroupReactionNotificationStagingManifest(
        legacySelectors,
        scenario: scenario,
      );
      expect(rejected.ok, isFalse);
      expect(
        rejected.detail,
        contains('testCreateChatGroupNotificationFixture'),
      );
      expect(rejected.detail, contains('testChatGroupNotificationTap'));
    });

    test('iOS registration parser accepts only recipient relay success', () {
      expect(
        groupReactionIosRelayRegistrationSucceeded(
          '2026-08-22T20:00:00Z app [PUSH_DIAG] '
          'relay_push_registration_success platform=ios',
        ),
        isTrue,
      );
      expect(
        groupReactionIosRelayRegistrationSucceeded(
          '[PUSH] Token registered for peer (ios)',
        ),
        isFalse,
      );
      expect(
        groupReactionIosRelayRegistrationSucceeded(
          '[PUSH_DIAG] relay_push_registration_success platform=android',
        ),
        isFalse,
      );
    });

    test(
      'Plan 398 trace manifest is non-mutating and omits XCTest selectors',
      () {
        final manifest = <String, Object?>{
          'schema': plan398ExistingStateTraceManifestSchema,
          'version': 1,
          'environment': 'staging',
          'relayActive': true,
          'providerConfigured': true,
          'providerProbeSucceeded': true,
          'productionDeploymentPerformed': false,
          'allowAppDataReset': false,
          'candidateRelayRevision': 'relay-server v1.9.0',
          'candidateRelaySha256': _plan397FixtureDigest(
            'plan398-manual-trace-relay',
          ),
          'provider': 'apns',
          'relayAddresses': <String>['/dns4/staging.example/tcp/443'],
          'iosCapture': <String, Object?>{
            'bundleId': 'com.mknoon.app',
            'systemLogExecutable': 'idevicesyslog',
          },
        };

        final accepted = validatePlan398ExistingStateTraceManifest(manifest);
        expect(accepted.ok, isTrue, reason: accepted.detail);

        final reset = Map<String, Object?>.from(manifest)
          ..['allowAppDataReset'] = true;
        expect(
          validatePlan398ExistingStateTraceManifest(reset).detail,
          contains('allowAppDataReset'),
        );

        final legacyProvider = Map<String, Object?>.from(manifest)
          ..['provider'] = 'fcm';
        expect(
          validatePlan398ExistingStateTraceManifest(legacyProvider).detail,
          contains('provider'),
        );

        final selectors = Map<String, Object?>.from(manifest);
        selectors['iosCapture'] = <String, Object?>{
          ...Map<String, Object?>.from(manifest['iosCapture']! as Map),
          'notificationTapSelector': 'unused',
        };
        expect(
          validatePlan398ExistingStateTraceManifest(selectors).detail,
          contains('notificationTapSelector'),
        );
      },
    );

    test('iOS USB inventory requires exact device membership', () {
      const deviceId = '00008110-00184D622289801E';
      expect(
        groupReactionIosUsbDeviceIsPresent('$deviceId\n', deviceId),
        isTrue,
      );
      expect(
        groupReactionIosUsbDeviceIsPresent(
          '00008030-001A6D2801BB802E\n',
          deviceId,
        ),
        isFalse,
      );
      expect(
        groupReactionIosUsbDeviceIsPresent('$deviceId-extra\n', deviceId),
        isFalse,
      );
    });

    test('iOS inventory mounts DDI before exact USB classification', () {
      final source = File(
        'integration_test/scripts/capture_group_reaction_notification_device.dart',
      ).readAsStringSync();
      final methodStart = source.indexOf(
        'Future<void> _verifyLiveDeviceTopology()',
      );
      final methodEnd = source.indexOf(
        'Future<void> _preparePlan397CentralArtifacts()',
        methodStart,
      );
      expect(methodStart, greaterThanOrEqualTo(0));
      expect(methodEnd, greaterThan(methodStart));

      final method = source.substring(methodStart, methodEnd);
      final ddiMount = method.indexOf("'devicectl'");
      final usbInventory = method.indexOf("'idevice_id'");
      expect(ddiMount, greaterThanOrEqualTo(0));
      expect(method, contains("'ddiServices'"));
      expect(method, contains("'--auto-mount-ddis'"));
      expect(usbInventory, greaterThan(ddiMount));
      expect(method, contains("'-l'"));
      expect(method, isNot(contains("'xctrace'")));
    });

    test('iOS file channel remounts DDI before every CoreDevice copy', () {
      final source = File(
        'integration_test/scripts/capture_group_reaction_notification_device.dart',
      ).readAsStringSync();

      void expectMountBeforeCopy(String start, String end) {
        final methodStart = source.indexOf(start);
        final methodEnd = source.indexOf(end, methodStart);
        expect(methodStart, greaterThanOrEqualTo(0));
        expect(methodEnd, greaterThan(methodStart));

        final method = source.substring(methodStart, methodEnd);
        final mount = method.indexOf(
          'await _mountIosDeveloperDiskImageForCoreDevice();',
        );
        final copy = method.indexOf("'copy'");
        final timeout = method.indexOf("'--timeout'", copy);
        expect(mount, greaterThanOrEqualTo(0), reason: start);
        expect(copy, greaterThan(mount), reason: start);
        expect(timeout, greaterThan(copy), reason: start);
        expect(method.substring(timeout), contains("'15'"), reason: start);
      }

      expectMountBeforeCopy(
        'Future<void> _stageIosAppFile(',
        'Future<String?> _readIosAppFile(',
      );
      expectMountBeforeCopy(
        'Future<String?> _readIosAppFile(',
        'Future<void> _collectIosIdentity(',
      );
    });

    test('iOS app operations remount DDI and carry explicit timeouts', () {
      final source = File(
        'integration_test/scripts/capture_group_reaction_notification_device.dart',
      ).readAsStringSync();

      void expectBoundedCoreDeviceOperation(
        String start,
        String end,
        String operation,
        String timeout,
      ) {
        final methodStart = source.indexOf(start);
        final methodEnd = source.indexOf(end, methodStart);
        expect(methodStart, greaterThanOrEqualTo(0));
        expect(methodEnd, greaterThan(methodStart));
        final method = source.substring(methodStart, methodEnd);
        final mount = method.indexOf(
          'await _mountIosDeveloperDiskImageForCoreDevice();',
        );
        final operationIndex = method.indexOf("'$operation'");
        final timeoutIndex = method.indexOf("'--timeout'", operationIndex);
        expect(mount, greaterThanOrEqualTo(0), reason: start);
        expect(operationIndex, greaterThan(mount), reason: start);
        expect(timeoutIndex, greaterThan(operationIndex), reason: start);
        expect(
          method.substring(timeoutIndex),
          contains("'$timeout'"),
          reason: start,
        );
      }

      expectBoundedCoreDeviceOperation(
        'Future<void> _uninstallIosCandidateIfPresent()',
        'Future<void> _installIosCandidate(',
        'uninstall',
        '60',
      );
      expectBoundedCoreDeviceOperation(
        'Future<void> _installIosCandidate(',
        'Future<void> _launchIosCandidate()',
        'install',
        '120',
      );
      expectBoundedCoreDeviceOperation(
        'Future<void> _launchIosCandidate()',
        'Future<void> _stageIosAppFile(',
        'launch',
        '60',
      );
    });

    test('iOS file channel falls back to bounded House Arrest copies', () {
      final source = File(
        'integration_test/scripts/capture_group_reaction_notification_device.dart',
      ).readAsStringSync();

      expect(source, contains('bool _preferIosAfcFileChannel = false;'));
      expect(source, contains('Future<_CommandOutput> _runIosAfcCommands('));
      expect(source, contains("Process.start('afcclient'"));
      expect(source, contains('const Duration(seconds: 15)'));
      expect(source, contains('_copyIosAppFileToContainerWithAfc('));
      expect(source, contains('_copyIosAppFileFromContainerWithAfc('));
      expect(source, contains("'--stdin-command-count=\${commands.length}'"));
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

  test(
    'Plan 398 retains a native FAIL receipt as capture evidence, never environment evidence',
    () {
      final failReceipt = _plan398NativeObservationReceipt(status: 'FAIL');
      final bindings = _plan398NativeObservationBindings();

      expect(
        failReceipt['schema'],
        'mknoon.sims.ios-group-notification-observation-host-receipt.v3',
      );
      expect(
        failReceipt['diagnosticSchema'],
        'mknoon.sims.ios-group-notification-diagnostics.v2',
      );

      Plan398NativeObservationDisposition classify(
        Object? receipt, {
        required int exitCode,
      }) => classifyPlan398NativeObservationReceipt(
        subprocessExitCode: exitCode,
        receipt: receipt,
        phase: 'message',
        captureNonceSha256: bindings['captureNonceSha256']!,
        receiverDeviceIdSha256: bindings['receiverDeviceIdSha256']!,
        expectedGroupIdSha256: bindings['expectedGroupIdSha256']!,
        expectedEventIdSha256: bindings['expectedEventIdSha256']!,
        expectedTargetMessageIdSha256:
            bindings['expectedTargetMessageIdSha256']!,
        expectedCollapseIdentifierSha256:
            bindings['expectedCollapseIdentifierSha256']!,
      );

      expect(
        classify(failReceipt, exitCode: 1),
        Plan398NativeObservationDisposition.captureEvidence,
        reason: 'TC-398-04 retained native FAIL',
      );
      final passReceipt = _plan398NativeObservationReceipt(status: 'PASS');
      expect(
        classify(passReceipt, exitCode: 0),
        Plan398NativeObservationDisposition.behaviorPass,
      );
      final canonicalFail = <String, Object?>{
        ...passReceipt,
        'status': 'FAIL',
        'resultCode': 'source_inventory_mismatch',
      };
      expect(
        classify(canonicalFail, exitCode: 1),
        Plan398NativeObservationDisposition.environmentEvidence,
        reason:
            'exact canonical membership must be PASS/ok, never '
            'FAIL/source_inventory_mismatch',
      );
      expect(
        classify(passReceipt, exitCode: 1),
        Plan398NativeObservationDisposition.environmentEvidence,
        reason: 'native PASS must exit zero',
      );
      expect(
        classify(failReceipt, exitCode: 0),
        Plan398NativeObservationDisposition.environmentEvidence,
        reason: 'native FAIL must exit positive nonzero',
      );
      expect(
        classify(failReceipt, exitCode: 2),
        Plan398NativeObservationDisposition.captureEvidence,
        reason: 'any positive nonzero native FAIL exit is retained evidence',
      );

      final unstableFail = <String, Object?>{
        ...failReceipt,
        'sampledThroughDeadline': false,
        'diagnosticComplete': false,
        'resultCode': 'source_inventory_unstable',
      };
      final duplicateOnlyFail = <String, Object?>{
        ...failReceipt,
        'badSourceSeen': false,
        'resultCode': 'duplicate_seen',
      };
      final mismatchFail = <String, Object?>{
        ...failReceipt,
        'badSourceSeen': false,
        'duplicateSeen': false,
        'resultCode': 'source_inventory_mismatch',
      };
      for (final validFail in <Map<String, Object?>>[
        unstableFail,
        duplicateOnlyFail,
        mismatchFail,
      ]) {
        expect(
          classify(validFail, exitCode: 1),
          Plan398NativeObservationDisposition.captureEvidence,
          reason: '${validFail['resultCode']}',
        );
      }
      for (final contradictoryFail in <Map<String, Object?>>[
        <String, Object?>{...failReceipt, 'resultCode': 'duplicate_seen'},
        <String, Object?>{
          ...duplicateOnlyFail,
          'resultCode': 'source_inventory_mismatch',
        },
        <String, Object?>{...unstableFail, 'resultCode': 'bad_source_seen'},
        <String, Object?>{...mismatchFail, 'resultCode': 'ok'},
        <String, Object?>{...mismatchFail, 'resultCode': 'invented_failure'},
      ]) {
        expect(
          classify(contradictoryFail, exitCode: 1),
          Plan398NativeObservationDisposition.environmentEvidence,
          reason: '${contradictoryFail['resultCode']}',
        );
      }

      final transientUnionFail = _plan398NativeObservationReceipt(
        status: 'FAIL',
      );
      final transientUnionRecords =
          (transientUnionFail['diagnosticRecords']! as List)
              .cast<Map<String, Object?>>();
      final finalCanonicalHash =
          transientUnionRecords.singleWhere(
                (record) => record['expectedCollapseIdentifierMatch'] == true,
              )['requestIdentifierSha256']!
              as String;
      transientUnionFail
        ..['requestIdentifierSha256'] = <String>[finalCanonicalHash]
        ..['matchingRemoteCount'] = 1
        ..['matchingUnknownCount'] = 0
        ..['matchingTotalCount'] = 1;
      expect(transientUnionFail['diagnosticRecordCount'], 2);
      expect(
        classify(transientUnionFail, exitCode: 1),
        Plan398NativeObservationDisposition.captureEvidence,
        reason:
            'the final canonical inventory is a strict subset of the latched '
            'diagnostic union after a transient duplicate disappears',
      );

      final uncoveredFinalInventory = <String, Object?>{
        ...transientUnionFail,
        'requestIdentifierSha256': <String>[
          _plan397FixtureDigest('unrepresented-final-inventory-request'),
        ],
      };
      expect(
        classify(uncoveredFinalInventory, exitCode: 1),
        Plan398NativeObservationDisposition.environmentEvidence,
        reason: 'every final inventory hash must be represented in diagnostics',
      );
      final nonCanonicalPass = <String, Object?>{
        ...transientUnionFail,
        'status': 'PASS',
        'resultCode': 'ok',
        'badSourceSeen': false,
        'duplicateSeen': false,
      };
      expect(
        classify(nonCanonicalPass, exitCode: 0),
        Plan398NativeObservationDisposition.environmentEvidence,
        reason: 'PASS still requires exactly one canonical diagnostic record',
      );
      expect(
        classify(null, exitCode: 1),
        Plan398NativeObservationDisposition.environmentEvidence,
      );
      expect(
        classify(<String, Object?>{
          ...failReceipt,
          'diagnosticRecordCount': 99,
        }, exitCode: 1),
        Plan398NativeObservationDisposition.environmentEvidence,
      );

      final records = (failReceipt['diagnosticRecords']! as List)
          .cast<Map<String, Object?>>();
      final canonical = records.singleWhere(
        (record) => record['expectedCollapseIdentifierMatch'] == true,
      );
      final unknown = records.singleWhere(
        (record) => record['expectedCollapseIdentifierMatch'] == false,
      );
      for (final key in const <String>[
        'requestIdentifierSha256',
        'dispatchCorrelationSha256',
        'claimedCollapseIdentifierSha256',
        'providerMessageIdSha256',
      ]) {
        expect(canonical[key], matches(RegExp(r'^[0-9a-f]{64}$')), reason: key);
      }
      expect(unknown['dispatchCorrelationSha256'], isNull);
      expect(unknown['claimedCollapseIdentifierSha256'], isNull);
      expect(unknown['providerMessageIdSha256'], isNull);

      for (final mutation in <void Function(Map<String, Object?>)>[
        (receipt) => ((receipt['diagnosticRecords']! as List).first as Map)
            .remove('dispatchCorrelationSha256'),
        (receipt) => ((receipt['diagnosticRecords']! as List).first as Map)
            .remove('claimedCollapseIdentifierSha256'),
        (receipt) => ((receipt['diagnosticRecords']! as List).first as Map)
            .remove('providerMessageIdSha256'),
        (receipt) =>
            ((receipt['diagnosticRecords']! as List).first
                    as Map)['dispatchCorrelationSha256'] =
                'raw-dispatch-id',
        (receipt) =>
            ((receipt['diagnosticRecords']! as List).first
                    as Map)['providerMessageIdSha256'] =
                'A' * 64,
        (receipt) =>
            ((receipt['diagnosticRecords']! as List).cast<Map>().singleWhere(
              (record) => record['expectedCollapseIdentifierMatch'] == true,
            ))['expectedCollapseIdentifierMatch'] = false,
        (receipt) => receipt['requestIdentifierSha256'] = <String>[
          _plan397FixtureDigest('different-request'),
          _plan397FixtureDigest('different-sibling'),
        ]..sort(),
        (receipt) => receipt['diagnosticRecordCount'] = 1,
        (receipt) =>
            ((receipt['diagnosticRecords']! as List).first
                    as Map)['providerMessageId'] =
                'raw-provider-id',
      ]) {
        final mutated = _plan398NativeObservationReceipt(status: 'FAIL');
        mutation(mutated);
        expect(
          classify(mutated, exitCode: 1),
          Plan398NativeObservationDisposition.environmentEvidence,
        );
      }
    },
  );

  test(
    'Plan 398 diagnostic mode binds per-card provenance without claiming closure',
    () async {
      final root = await Directory.systemTemp.createTemp('plan398-diagnostic-');
      addTearDown(() async {
        if (root.existsSync()) await root.delete(recursive: true);
      });
      final deploymentReceipt = File('${root.path}/deployment-state.json');
      final attemptMarker = File('${root.path}/diagnostic-claim.json');
      await deploymentReceipt.writeAsString(
        jsonEncode(<String, Object?>{
          'schema': 'mknoon.plan398.staging-deployment-receipt.v1',
          'ownerRunId': 'diagnostic',
          'singleOwnerDeclared': true,
        }),
        flush: true,
      );
      await attemptMarker.writeAsString(
        jsonEncode(<String, Object?>{
          'schema': 'mknoon.plan398.diagnostic-attempt-claim.v1',
          'ownerRunId': 'diagnostic',
          'claimValue': 'fixture-claim-value',
        }),
        flush: true,
      );
      for (final file in <File>[deploymentReceipt, attemptMarker]) {
        final chmod = await Process.run('chmod', <String>['600', file.path]);
        expect(chmod.exitCode, 0);
      }
      final artifact = await _writePlan398DiagnosticArtifactFixture(
        root,
        deploymentReceipt: deploymentReceipt,
        attemptMarker: attemptMarker,
      );

      Future<GroupReactionNotificationArtifactValidation> validateArtifact() =>
          validateGroupReactionNotificationArtifact(
            scenario: iosChatGroupMessageAndReactionScenarioId,
            artifactFile: artifact,
            expectedSenderDeviceId: '21071FDF600CSC',
            expectedRecipientDeviceId: '00008150-001C3C6A3684401C',
            plan398DeploymentReceipt: deploymentReceipt,
            plan398DiagnosticAttemptMarker: attemptMarker,
          );

      final validation = await validateArtifact();
      expect(
        validation.ok,
        isTrue,
        reason: 'TC-398-06 diagnostic mode: ${validation.detail}',
      );

      final decoded = _readArtifact(artifact);
      expect(
        decoded['schema'],
        'mknoon.plan398.ios-group-message-diagnostic.v2',
      );
      expect(decoded['version'], 2);
      expect(decoded['status'], 'diagnostic_complete');
      expect(decoded['closurePassed'], isFalse);
      expect(decoded['windows'], isNull);
      expect((decoded['window'] as Map)['tap'], isNull);
      expect(
        ((decoded['window'] as Map)['nativeInventory'] as Map)['status'],
        'FAIL',
      );
      expect(
        ((decoded['window'] as Map)['provider']
            as Map)['providerSingleFirstAttempt'],
        isTrue,
      );
      final encoded = await artifact.readAsString();
      for (final rawValue in const <String>[
        'plan398-dispatch-correlation-raw',
        'plan398-provider-message-id-raw',
        'plan398-collapse',
      ]) {
        expect(encoded, isNot(contains(rawValue)), reason: rawValue);
      }

      final runner = File(
        'integration_test/scripts/run_group_reaction_notification_device.dart',
      ).readAsStringSync();
      final capture = File(
        'integration_test/scripts/capture_group_reaction_notification_device.dart',
      ).readAsStringSync();
      final proof = File(
        'integration_test/group_announcement_reaction_notification_proof_test.dart',
      ).readAsStringSync();
      expect(runner, contains("'--diagnostic-only-message-window'"));
      expect(capture, contains('diagnosticOnlyMessageWindow'));
      expect(capture, contains('providerSingleFirstAttempt'));
      expect(capture, contains('bindRelayAcceptedGroupMessageProviderAttempt'));
      expect(capture, contains("provider['relayGroupMessageDispatchSource']"));
      expect(capture, contains('closurePassed'));
      final observeStart = capture.indexOf(
        'Future<Map<String, Object?>> _observePlan397IosNotification(',
      );
      final observeEnd = capture.indexOf(
        'Future<void> _cleanupPlan397IosObservation(',
        observeStart,
      );
      expect(observeStart, greaterThanOrEqualTo(0));
      expect(observeEnd, greaterThan(observeStart));
      final observeMethod = capture.substring(observeStart, observeEnd);
      final typedCatch = observeMethod.indexOf('on _CaptureFailure');
      final broadCatch = observeMethod.indexOf('on Object');
      expect(typedCatch, greaterThanOrEqualTo(0));
      expect(broadCatch, greaterThan(typedCatch));
      expect(
        proof,
        contains('test(iosChatGroupMessageAndReactionScenarioId, () async {'),
      );
      expect(
        proof,
        contains(
          'await _validateScenario(iosChatGroupMessageAndReactionScenarioId);',
        ),
      );

      final provider = (decoded['window'] as Map)['provider'] as Map;
      provider['acceptedProviderMessageIdSha256'] = _plan397FixtureDigest(
        'different-provider-message-id',
      );
      _writeArtifact(artifact, decoded);
      final providerMismatch = await validateArtifact();
      expect(
        providerMismatch.ok,
        isTrue,
        reason:
            'provider/device message-id equality is diagnostic, not structural: '
            '${providerMismatch.detail}',
      );

      provider['acceptedProviderMessageIdSha256'] = null;
      _writeArtifact(artifact, decoded);
      final providerAbsent = await validateArtifact();
      expect(
        providerAbsent.ok,
        isTrue,
        reason:
            'a normalized Firebase response suffix may be unavailable: '
            '${providerAbsent.detail}',
      );

      provider['acceptedDispatchCorrelationSha256'] = _plan397FixtureDigest(
        'different-dispatch-correlation',
      );
      _writeArtifact(artifact, decoded);
      final dispatchMismatch = await validateArtifact();
      expect(dispatchMismatch.ok, isFalse);
      expect(
        dispatchMismatch.detail,
        contains('acceptedDispatchCorrelationSha256'),
      );
      expect(capture, contains('acceptedDispatchCorrelationSha256'));
      expect(capture, contains('acceptedProviderMessageIdSha256'));
    },
  );

  test(
    'TC-398-10 existing-state trace binds one send to redacted installed state',
    () async {
      const senderId = '21071FDF600CSC';
      const recipientId = '00008150-001C3C6A3684401C';
      final root = await Directory.systemTemp.createTemp(
        'plan398-existing-state-trace-',
      );
      addTearDown(() async {
        if (root.existsSync()) await root.delete(recursive: true);
      });
      final fixture = await _writePlan398ExistingStateTraceArtifactFixture(
        root,
      );
      final artifact = fixture.artifact;
      final traceAttemptMarker = fixture.traceAttemptMarker;

      Future<GroupReactionNotificationArtifactValidation> validateArtifact() =>
          validatePlan398ExistingStateTraceArtifact(
            artifactFile: artifact,
            traceAttemptMarker: traceAttemptMarker,
            expectedSenderDeviceId: senderId,
            expectedRecipientDeviceId: recipientId,
          );

      expect(
        plan398ExistingStateTraceArtifactSchema,
        'mknoon.plan398.ios-group-message-existing-state-trace.v1',
      );
      expect(plan398ExistingStateTraceArtifactVersion, 1);
      final accepted = await validateArtifact();
      expect(
        accepted.ok,
        isTrue,
        reason: 'TC-398-10 valid trace: ${accepted.detail}',
      );

      final liveDiagnostic = _readArtifact(artifact)
        ..['schema'] = plan398ExistingStateLiveDiagnosticArtifactSchema
        ..['authorityMode'] = plan398LiveDiagnosticAuthorityMode;
      final liveExecution =
          Map<String, dynamic>.from(liveDiagnostic['execution'] as Map)
            ..['automation'] = 'manual_message_send'
            ..['messageSendTapCount'] = 0
            ..['manualMessageSendCount'] = 1;
      liveDiagnostic['execution'] = liveExecution;
      _writeArtifact(artifact, liveDiagnostic);
      final liveAccepted = await validateArtifact();
      expect(
        liveAccepted.ok,
        isTrue,
        reason: 'live diagnostic trace rejected: ${liveAccepted.detail}',
      );
      for (final key in const <String>[
        'buildCount',
        'installCount',
        'uninstallCount',
        'appDataClearCount',
      ]) {
        expect(liveExecution[key], 0, reason: key);
      }
      liveExecution
        ..['automation'] = 'fully_automated'
        ..['messageSendTapCount'] = 1
        ..remove('manualMessageSendCount');
      _writeArtifact(artifact, liveDiagnostic);
      final automatedLive = await validateArtifact();
      expect(automatedLive.ok, isFalse);
      expect(automatedLive.detail, contains('manual_message_send'));

      liveExecution
        ..['automation'] = 'manual_message_send'
        ..['messageSendTapCount'] = 0
        ..['manualMessageSendCount'] = 1;
      liveDiagnostic['finalRunnerProductReceiptSha256'] = _plan397FixtureDigest(
        'forbidden-live-receipt',
      );
      _writeArtifact(artifact, liveDiagnostic);
      final liveWithLegacyReceipt = await validateArtifact();
      expect(liveWithLegacyReceipt.ok, isFalse);
      expect(
        liveWithLegacyReceipt.detail,
        contains('finalRunnerProductReceiptSha256'),
      );
      await _writePlan398ExistingStateTraceArtifactFixture(root);

      final encoded = await artifact.readAsString();
      for (final rawValue in const <String>[
        'tc398-existing-group-id',
        'tc398-existing-group-key',
        'tc398-existing-target-message-id',
        'tc398-sender-identity-receipt',
        'tc398-recipient-identity-receipt',
        'tc398-existing-push-token',
      ]) {
        expect(encoded, isNot(contains(rawValue)), reason: rawValue);
      }

      final manual = _readArtifact(artifact);
      final manualExecution = manual['execution'] as Map<String, dynamic>;
      manualExecution['automation'] = 'manual_message_send';
      manualExecution['messageSendTapCount'] = 0;
      manualExecution['manualMessageSendCount'] = 1;
      _writeArtifact(artifact, manual);
      final manualAccepted = await validateArtifact();
      expect(
        manualAccepted.ok,
        isTrue,
        reason: 'manual-send trace rejected: ${manualAccepted.detail}',
      );
      manualExecution['manualMessageSendCount'] = 2;
      _writeArtifact(artifact, manual);
      final secondManualSend = await validateArtifact();
      expect(secondManualSend.ok, isFalse);
      expect(secondManualSend.detail, contains('manualMessageSendCount'));

      Future<void> expectRejected(
        void Function(Map<String, dynamic> artifact) mutate,
        Matcher detailMatcher,
      ) async {
        await _writePlan398ExistingStateTraceArtifactFixture(root);
        final decoded = _readArtifact(artifact);
        mutate(decoded);
        _writeArtifact(artifact, decoded);
        final rejected = await validateArtifact();
        expect(rejected.ok, isFalse, reason: rejected.detail);
        expect(rejected.detail, detailMatcher);
      }

      await expectRejected(
        (decoded) {
          final installedState =
              decoded['installedState'] as Map<String, dynamic>;
          installedState['groupId'] = 'tc398-existing-group-id';
          installedState['targetMessageId'] =
              'tc398-existing-target-message-id';
        },
        anyOf(
          contains('groupId'),
          contains('targetMessageId'),
          contains('raw'),
        ),
      );

      await expectRejected(
        (decoded) => decoded['traceAttemptClaimSha256'] = _plan397FixtureDigest(
          'different-existing-state-trace-claim',
        ),
        contains('traceAttemptClaimSha256'),
      );

      await expectRejected((decoded) {
        final execution = decoded['execution'] as Map<String, dynamic>;
        execution['messageSendTapCount'] = 2;
      }, contains('messageSendTapCount'));
    },
  );

  group('Plan 397 central artifact contract', () {
    test('chat-group iOS scenario requires central Android and iOS artifacts', () {
      final runner = File(
        'integration_test/scripts/run_group_reaction_notification_device.dart',
      ).readAsStringSync();
      final capture = File(
        'integration_test/scripts/capture_group_reaction_notification_device.dart',
      ).readAsStringSync();
      for (final option in const <String>[
        '--prebuilt-android-apk',
        '--prebuilt-android-build-report',
        '--prebuilt-ios-bundle',
        '--prebuilt-ios-build-report',
      ]) {
        expect(runner, contains(option));
        expect(capture, contains(option));
      }
      expect(
        capture,
        contains(
          'chat_group_ios_requires_central_android_ios_artifacts_and_reports',
        ),
      );
    });

    test(
      'chat-group iOS scenario rejects stale or unbound central build reports',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'plan397-central-build-',
        );
        try {
          final fixture = _writeCentralBuildFixture(
            root,
            profileId: 'android.production_fcm',
          );
          final valid = validateGroupReactionCentralBuildArtifact(
            profileId: fixture.profileId,
            artifact: fixture.artifact,
            buildReport: fixture.report,
            now: fixture.generatedAt,
          );
          expect(valid.ok, isTrue, reason: valid.detail);

          _writeBuildReport(
            fixture.report,
            profileId: fixture.profileId,
            artifactDigest: fixture.artifactDigest,
            generatedAt: fixture.generatedAt.subtract(const Duration(hours: 2)),
          );
          final stale = validateGroupReactionCentralBuildArtifact(
            profileId: fixture.profileId,
            artifact: fixture.artifact,
            buildReport: fixture.report,
            now: fixture.generatedAt,
          );
          expect(stale.ok, isFalse);
          expect(stale.detail, contains('stale'));

          _writeBuildReport(
            fixture.report,
            profileId: fixture.profileId,
            artifactDigest: 'f' * 64,
            generatedAt: fixture.generatedAt,
          );
          final unbound = validateGroupReactionCentralBuildArtifact(
            profileId: fixture.profileId,
            artifact: fixture.artifact,
            buildReport: fixture.report,
            now: fixture.generatedAt,
          );
          expect(unbound.ok, isFalse);
          expect(unbound.detail, contains('digest'));
        } finally {
          await root.delete(recursive: true);
        }
      },
    );

    test(
      'chat-group attempt two rejects attempt-one iOS artifact digest after client repair',
      () {
        final attemptTwo = GroupReactionCentralBuildValidation(
          failures: const <String>[],
          profileId: 'ios.device.production',
          inputDigest: 'a' * 64,
          artifactDigest: 'b' * 64,
        );
        final stale = validateGroupReactionAttemptTwoIosBuildFreshness(
          attemptOneInputDigest: 'a' * 64,
          attemptOneArtifactDigest: 'b' * 64,
          attemptTwo: attemptTwo,
        );
        expect(stale.ok, isFalse);
        expect(stale.detail, contains('input digest'));
        expect(stale.detail, contains('artifact digest'));
      },
    );

    test(
      'chat-group central UI leg uses relocated xctestrun without building',
      () {
        final source = File(
          'integration_test/scripts/capture_group_reaction_notification_device.dart',
        ).readAsStringSync();
        expect(source, contains('relocateIosXctestrun('));
        expect(source, contains('iosTestWithoutBuildingArguments('));
        expect(source, contains("'SIMS_CHILD_BUILDS_FORBIDDEN': '1'"));
        expect(source, contains('chat_group_patched_xctestrun_not_prepared'));
      },
    );

    test('chat-group setup UI permits one exact automation warm retry', () {
      final source = File(
        'integration_test/scripts/capture_group_reaction_notification_device.dart',
      ).readAsStringSync();
      final methodStart = source.indexOf('Future<String> _runIosUiSelector(');
      final methodEnd = source.indexOf(
        'Future<void> _acceptIosCreatedGroupOnAndroid()',
        methodStart,
      );
      expect(methodStart, greaterThanOrEqualTo(0));
      expect(methodEnd, greaterThan(methodStart));
      final method = source.substring(methodStart, methodEnd);

      expect(method, contains('const maximumAttempts = 2;'));
      expect(method, contains('_iosFixtureCreateSelector'));
      expect(method, contains('_iosFixtureAuthorSelector'));
      expect(method, contains("stage == 'plan397_fixture_staging'"));
      expect(method, contains('Timed out while enabling automation mode.'));
      expect(method, contains("'_automation_retry'"));
      expect(
        method,
        contains(
          'final attemptLimit = permitsAutomationWarmRetry ? '
          'maximumAttempts : 1;',
        ),
      );
      expect(method, contains('PLAN397_SETUP_AUTOMATION_WARM_RETRY_USED'));
      expect(method, isNot(contains('_iosNotificationPrepareSelector')));
      expect(method, isNot(contains('_iosTapSelector')));
      expect(
        method,
        contains('await _mountIosDeveloperDiskImageForCoreDevice();'),
      );
      expect(method, contains('allowFail: true'));
    });

    test(
      'chat-group Android invite acceptance permits direct conversation destination',
      () {
        final source = File(
          'integration_test/scripts/capture_group_reaction_notification_device.dart',
        ).readAsStringSync();
        final methodStart = source.indexOf(
          'Future<void> _acceptIosCreatedGroupOnAndroid()',
        );
        final methodEnd = source.indexOf(
          'Future<void> _startIosSystemLog()',
          methodStart,
        );
        expect(methodStart, greaterThanOrEqualTo(0));
        expect(methodEnd, greaterThan(methodStart));

        final method = source.substring(methodStart, methodEnd);
        expect(method, contains("await _tapText(senderId, 'Accept');"));
        expect(method, contains('isAcceptedGroupSurface('));
        expect(method, contains('await _uiDump(senderId)'));
        expect(method, isNot(contains("'Open group \$_groupName'")));
      },
    );

    test('chat-group iOS setup app launches without debug tooling', () {
      final source = File(
        'integration_test/scripts/capture_group_reaction_notification_device.dart',
      ).readAsStringSync();
      final methodStart = source.indexOf(
        'Future<Directory> _buildIosCandidate({required bool e2eMode})',
      );
      final methodEnd = source.indexOf(
        'Future<void> _installIosCandidate(',
        methodStart,
      );
      expect(methodStart, greaterThanOrEqualTo(0));
      expect(methodEnd, greaterThan(methodStart));

      final method = source.substring(methodStart, methodEnd);
      expect(method, contains("'--profile'"));
      expect(method, isNot(contains("'--debug'")));
    });

    test('chat-group iOS setup app embeds the exact Plan 397 profile', () {
      final source = File(
        'integration_test/scripts/capture_group_reaction_notification_device.dart',
      ).readAsStringSync();
      final methodStart = source.indexOf(
        'Future<Directory> _buildIosCandidate({required bool e2eMode})',
      );
      final methodEnd = source.indexOf(
        'Future<void> _installIosCandidate(',
        methodStart,
      );
      expect(methodStart, greaterThanOrEqualTo(0));
      expect(methodEnd, greaterThan(methodStart));

      final method = source.substring(methodStart, methodEnd);
      expect(method, contains('if (_isPlan397 && e2eMode)'));
      expect(method, contains("'--dart-define=SIMS_BUILD_PROFILE_ID='"));
      expect(
        method,
        contains(r"'$groupReactionNotificationIosSetupBuildProfile'"),
      );
    });

    test('Plan 398 no-child capture consumes coordinator-prepared setup app', () {
      final runner = File(
        'integration_test/scripts/run_group_reaction_notification_device.dart',
      ).readAsStringSync();
      final capture = File(
        'integration_test/scripts/capture_group_reaction_notification_device.dart',
      ).readAsStringSync();
      final coordinator = File(
        'integration_test/scripts/ios_group_message_diagnostic_staging.py',
      ).readAsStringSync();
      final simsManifest = File(
        'tool/sims/critical_features.json',
      ).readAsStringSync();

      for (final option in const <String>[
        '--prebuilt-ios-setup-app',
        '--prebuilt-ios-setup-app-sha256',
      ]) {
        expect(runner, contains("'$option'"));
        expect(capture, contains("'$option'"));
        expect(coordinator, contains('"$option"'));
      }
      expect(capture, contains('prebuiltIosSetupApplication'));
      expect(capture, contains('prebuiltIosSetupApplicationSha256'));
      expect(capture, contains('child_iOS_build_forbidden_by_no_child_builds'));
      expect(coordinator, contains('PLAN398_XCODEBUILD_COMMAND'));
      expect(coordinator, contains('"build-for-testing"'));
      expect(coordinator, contains('"ENABLE_TESTABILITY=YES"'));
      expect(coordinator, contains('"DART_DEFINES='));
      expect(
        coordinator,
        contains('Build/Products/Release-iphoneos/Runner.app'),
      );
      expect(coordinator, isNot(contains('PLAN398_FLUTTER_COMMAND')));
      expect(
        coordinator,
        contains('ios.device.group_reaction_notification_397'),
      );
      expect(
        simsManifest,
        isNot(contains('ios.device.group_reaction_notification_397')),
        reason: 'Plan 398 explicitly forbids a new Sims profile/capability',
      );
    });

    test('chat-group iOS identity export uses the exact profile gate', () {
      final source = File(
        'lib/core/debug/intro_e2e_runner.dart',
      ).readAsStringSync();
      final methodStart = source.indexOf(
        'Future<String?> exportIdentityForIntroE2E(',
      );
      final methodEnd = source.indexOf(
        'Future<bool> prePopulateContactsFromIntroE2EConfig(',
        methodStart,
      );
      expect(methodStart, greaterThanOrEqualTo(0));
      expect(methodEnd, greaterThan(methodStart));

      final method = source.substring(methodStart, methodEnd);
      expect(method, contains('allowsGroupMediaIosIntroFileChannel('));
      expect(method, contains("'SIMS_BUILD_PROFILE_ID'"));
      expect(method, contains('writeAsBytes(bytes, flush: true)'));
      expect(method, contains('temporary.rename(file.path)'));
      expect(method, contains('sha256.convert(retained).toString()'));
      expect(method, isNot(contains('if (!kDebugMode) return;')));
    });

    test('Plan 398 setup readiness binds the current launch before identity', () {
      final profile = File(
        'lib/core/debug/group_reaction_notification_ios_setup_profile.dart',
      ).readAsStringSync();
      final root = File(
        'lib/debug/debug_e2e_composition_root.dart',
      ).readAsStringSync();
      final appDelegate = File(
        'ios/Runner/AppDelegate.swift',
      ).readAsStringSync();
      final capture = File(
        'integration_test/scripts/capture_group_reaction_notification_device.dart',
      ).readAsStringSync();
      final uiTest = File(
        'ios/RunnerUITests/NotificationTapUITests.swift',
      ).readAsStringSync();

      expect(profile, contains('mknoon.plan398.ios-setup-readiness.v3'));
      expect(profile, contains('MKNOON_398_SETUP_READINESS_ATTEMPT'));
      expect(profile, contains('MKNOON_398_SETUP_ENTRY_PROFILE_ID'));
      expect(profile, contains('nativeEntryAcknowledged'));
      expect(profile, contains('dartEntryAcknowledged'));
      expect(profile, contains('dartEntryFailure'));
      expect(profile, contains('bootstrapDocumentsFailure'));
      expect(appDelegate, contains('mknoon/plan398_ios_setup_entry'));
      expect(appDelegate, contains('native_app_delegate'));
      expect(appDelegate, contains('dart_main'));
      expect(
        root,
        contains(
          'runGroupReactionNotificationIosSetupReadiness<IdentityModel>(',
        ),
      );
      expect(
        root,
        contains('writeGroupReactionNotificationIosSetupReadinessReceipt('),
      );

      final strictStart = uiTest.indexOf(
        'func testAutomateLocalNetworkPermission()',
      );
      final campaignStart = uiTest.indexOf(
        'func testSettleLocalNetworkPermissionForCampaign()',
      );
      final campaignEnd = uiTest.indexOf(
        'func testAirplaneToggleStateDecoderContract()',
        campaignStart,
      );
      expect(strictStart, greaterThanOrEqualTo(0));
      expect(campaignStart, greaterThan(strictStart));
      expect(campaignEnd, greaterThan(campaignStart));
      expect(
        uiTest.substring(strictStart, campaignStart),
        isNot(contains('MKNOON_398_SETUP_READINESS_ATTEMPT')),
        reason: 'strict permission proof must remain independent',
      );
      expect(
        uiTest.substring(strictStart, campaignStart),
        isNot(contains('MKNOON_398_SETUP_ENTRY_PROFILE_ID')),
        reason: 'strict permission proof must remain independent',
      );
      expect(
        uiTest.substring(campaignStart, campaignEnd),
        contains('MKNOON_398_SETUP_READINESS_ATTEMPT'),
      );
      expect(
        uiTest.substring(campaignStart, campaignEnd),
        contains('MKNOON_398_SETUP_ENTRY_PROFILE_ID'),
      );

      final readiness = capture.indexOf(
        '_waitForPlan398SetupReadiness() async',
      );
      final identity = capture.indexOf(
        'Future<void> _collectIosIdentity(_Party party) async',
      );
      expect(readiness, greaterThanOrEqualTo(0));
      expect(identity, greaterThan(readiness));
      final method = capture.substring(
        readiness,
        capture.indexOf('Future<void> _prepopulateIosContact(', identity),
      );
      expect(method, contains('expectedLaunchAttemptSha256'));
      expect(method, contains('expectedIdentityExportSha256'));
      expect(
        method,
        contains('plan398_ios_setup_readiness_native_entry_failure'),
      );
      expect(capture, contains('MKNOON_398_SETUP_ENTRY_PROFILE_ID'));
      expect(method, contains("_readIosAppFile('intro_e2e_identity.json')"));
      expect(
        method.indexOf('_waitForPlan398SetupReadiness()'),
        lessThan(method.indexOf("_readIosAppFile('intro_e2e_identity.json')")),
      );
    });

    test('chat-group profile poller admits only exact setup actions', () {
      final source = File(
        'lib/core/debug/intro_e2e_runner.dart',
      ).readAsStringSync();
      final actionsStart = source.indexOf('Future<void> runIntroE2EActions(');
      final actionsEnd = source.indexOf(
        'Future<void> _runConnectivityRestoreObservation(',
        actionsStart,
      );
      final pollerStart = source.indexOf('void startIntroE2EPoller(');
      final pollerEnd = source.indexOf(
        'Future<Map<String, dynamic>?> _openConversationIfRequested(',
        pollerStart,
      );
      expect(actionsStart, greaterThanOrEqualTo(0));
      expect(actionsEnd, greaterThan(actionsStart));
      expect(pollerStart, greaterThanOrEqualTo(0));
      expect(pollerEnd, greaterThan(pollerStart));

      final actions = source.substring(actionsStart, actionsEnd);
      final poller = source.substring(pollerStart, pollerEnd);
      expect(
        actions,
        contains('allowsGroupReactionNotificationIosSetupActions('),
      );
      expect(actions, isNot(contains('if (!kDebugMode || !kE2ETestMode)')));
      expect(
        poller,
        contains('if (!kDebugMode && !allowsPlan397SetupActions)'),
      );
    });

    test('chat-group iOS setup selectors reuse one setup product', () {
      final source = File(
        'integration_test/scripts/capture_group_reaction_notification_device.dart',
      ).readAsStringSync();
      final setupLabel = source.indexOf("label: 'setup'");
      final setupStart = source.lastIndexOf(
        '_materializePlan397Xctestrun(',
        setupLabel,
      );
      final centralInstall = source.indexOf(
        "_installIosCandidate(centralApplication, mode: 'central_normal')",
      );
      final setupWindow = source.substring(setupStart, centralInstall);
      expect(setupLabel, greaterThanOrEqualTo(0));
      expect(setupStart, greaterThanOrEqualTo(0));
      expect(centralInstall, greaterThan(setupStart));
      expect(
        RegExp(
          '_materializePlan397Xctestrun\\(',
        ).allMatches(setupWindow).length,
        1,
      );
      expect(setupWindow, contains('_iosFixtureCreateSelector'));
      expect(setupWindow, contains('_iosFixtureAuthorSelector'));
      expect(setupWindow, contains('application: setupApplication'));
    });

    test('chat-group iOS normal install preserves setup container', () {
      final source = File(
        'integration_test/scripts/capture_group_reaction_notification_device.dart',
      ).readAsStringSync();
      final setupPeer = source.indexOf('final setupPeerId = recipient.peerId');
      final centralInstall = source.indexOf(
        "_installIosCandidate(centralApplication, mode: 'central_normal')",
      );
      final retained = source.indexOf(
        "_readIosAppFile('intro_e2e_identity.json')",
        centralInstall,
      );
      final segment = source.substring(setupPeer, retained);
      expect(setupPeer, greaterThanOrEqualTo(0));
      expect(centralInstall, greaterThan(setupPeer));
      expect(retained, greaterThan(centralInstall));
      expect(segment, isNot(contains("'uninstall'")));
      expect(source, contains('_plan397SetupContainerPreserved = true'));
    });

    test(
      'chat-group iOS tap uses one card container and rejects independent text lookup',
      () {
        final source = File(
          'ios/RunnerUITests/NotificationTapUITests.swift',
        ).readAsStringSync();
        final start = source.indexOf('func testChatGroupNotificationTap()');
        final end = source.indexOf(
          'func testAnnouncementReactionNotificationTap()',
          start,
        );
        final method = source.substring(start, end);
        expect(method, contains('findSameContainerNotificationCard('));
        expect(method, contains('tapSameContainerNotificationCard('));
        expect(method, contains('same_card=true matching_card_count=1'));
        expect(method, isNot(contains('notificationTextExists(')));
        expect(method, isNot(contains('tapVisibleNotificationChrome(')));
      },
    );
  });

  group('Plan 397 two-window proof contract', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('plan397-proof-');
    });

    tearDown(() async {
      if (root.existsSync()) await root.delete(recursive: true);
    });

    test(
      'accepts realistic chat-group iOS message and reaction evidence',
      () async {
        final artifact = await _writePlan397ArtifactFixture(root);
        final result = await validateGroupReactionNotificationArtifact(
          scenario: iosChatGroupMessageAndReactionScenarioId,
          artifactFile: artifact,
          expectedSenderDeviceId: '21071FDF600CSC',
          expectedRecipientDeviceId: '00008150-001C3C6A3684401C',
        );

        expect(result.ok, isTrue, reason: result.detail);
      },
    );

    test('chat-group iOS proof binds Android digest identities', () async {
      final artifact = await _writePlan397ArtifactFixture(root);
      final value = _readArtifact(artifact);
      final reaction = (value['windows'] as List<dynamic>)[1] as Map;
      final native = reaction['nativeInventory'] as Map;
      native['expectedEventIdSha256'] = 'f' * 64;
      _writeArtifact(artifact, value);

      final result = await validateGroupReactionNotificationArtifact(
        scenario: iosChatGroupMessageAndReactionScenarioId,
        artifactFile: artifact,
      );
      expect(result.ok, isFalse);
      expect(result.detail, contains('phase authority'));
    });

    test('rejects duplicate or local group source', () async {
      for (final mutation in <void Function(Map<dynamic, dynamic>)>[
        (native) => native['duplicateSeen'] = true,
        (native) {
          native['matchingRemoteCount'] = 0;
          native['matchingLocalCount'] = 1;
          native['matchingUsefulProviderCount'] = 0;
        },
      ]) {
        final directory = Directory('${root.path}/${mutation.hashCode}')
          ..createSync(recursive: true);
        final artifact = await _writePlan397ArtifactFixture(directory);
        final value = _readArtifact(artifact);
        mutation(
          ((value['windows'] as List<dynamic>)[0]
                  as Map<dynamic, dynamic>)['nativeInventory']
              as Map<dynamic, dynamic>,
        );
        _writeArtifact(artifact, value);
        final result = await validateGroupReactionNotificationArtifact(
          scenario: iosChatGroupMessageAndReactionScenarioId,
          artifactFile: artifact,
        );
        expect(result.ok, isFalse);
      }
    });

    test(
      'rejects early, transient-local, unstable, or unhashed inventory',
      () async {
        final mutations = <void Function(Map<dynamic, dynamic>)>[
          (native) => native['observationDeadlineMilliseconds'] = 3000,
          (native) => native['badSourceSeen'] = true,
          (native) => native['stableSampleCount'] = 2,
          (native) => native['requestIdentifierSha256'] = <String>['raw-id'],
        ];
        for (var index = 0; index < mutations.length; index++) {
          final directory = Directory('${root.path}/inventory-$index')
            ..createSync(recursive: true);
          final artifact = await _writePlan397ArtifactFixture(directory);
          final value = _readArtifact(artifact);
          final native =
              ((value['windows'] as List<dynamic>)[0]
                      as Map<dynamic, dynamic>)['nativeInventory']
                  as Map<dynamic, dynamic>;
          mutations[index](native);
          _writeArtifact(artifact, value);
          final result = await validateGroupReactionNotificationArtifact(
            scenario: iosChatGroupMessageAndReactionScenarioId,
            artifactFile: artifact,
          );
          expect(result.ok, isFalse, reason: '$index: ${result.detail}');
        }
      },
    );

    test('rejects deleted or unattributed provider evidence', () async {
      for (var index = 0; index < 2; index++) {
        final directory = Directory('${root.path}/provider-$index')
          ..createSync(recursive: true);
        final artifact = await _writePlan397ArtifactFixture(directory);
        final value = _readArtifact(artifact);
        final provider =
            ((value['windows'] as List<dynamic>)[index]
                    as Map<dynamic, dynamic>)['provider']
                as Map<dynamic, dynamic>;
        if (index == 0) {
          provider['deletedOrUnattributedEvidence'] = true;
        } else {
          provider['relayAttributed'] = false;
        }
        _writeArtifact(artifact, value);
        final result = await validateGroupReactionNotificationArtifact(
          scenario: iosChatGroupMessageAndReactionScenarioId,
          artifactFile: artifact,
        );
        expect(result.ok, isFalse);
      }
    });

    test('rejects any run-owned local publication', () async {
      final artifact = await _writePlan397ArtifactFixture(root);
      final value = _readArtifact(artifact);
      final window = (value['windows'] as List<dynamic>)[0] as Map;
      (window['nse'] as Map)['runOwnedLocalPublicationCount'] = 1;
      (window['diagnostics'] as Map)['runOwnedLocalPublicationCount'] = 1;
      _writeArtifact(artifact, value);

      final result = await validateGroupReactionNotificationArtifact(
        scenario: iosChatGroupMessageAndReactionScenarioId,
        artifactFile: artifact,
      );
      expect(result.ok, isFalse);
      expect(result.detail, contains('runOwnedLocalPublicationCount'));
    });

    test('rejects wrong route or final unread UI', () async {
      for (var index = 0; index < 2; index++) {
        final directory = Directory('${root.path}/tap-$index')
          ..createSync(recursive: true);
        final artifact = await _writePlan397ArtifactFixture(directory);
        final value = _readArtifact(artifact);
        final tap =
            ((value['windows'] as List<dynamic>)[index]
                    as Map<dynamic, dynamic>)['tap']
                as Map<dynamic, dynamic>;
        if (index == 0) {
          tap['routeMatched'] = false;
        } else {
          tap['finalUnreadCount'] = 1;
        }
        _writeArtifact(artifact, value);
        final result = await validateGroupReactionNotificationArtifact(
          scenario: iosChatGroupMessageAndReactionScenarioId,
          artifactFile: artifact,
        );
        expect(result.ok, isFalse);
      }
    });

    test('chat-group iOS provider evidence uses two metric windows', () async {
      final artifact = await _writePlan397ArtifactFixture(root);
      final value = _readArtifact(artifact);
      final windows = value['windows'] as List<dynamic>;
      final messageProvider = (windows[0] as Map)['provider'] as Map;
      final reactionProvider = (windows[1] as Map)['provider'] as Map;
      reactionProvider['baseline'] = messageProvider['baseline'];
      reactionProvider['baselineSha256'] = messageProvider['baselineSha256'];
      _writeArtifact(artifact, value);

      final result = await validateGroupReactionNotificationArtifact(
        scenario: iosChatGroupMessageAndReactionScenarioId,
        artifactFile: artifact,
      );
      expect(result.ok, isFalse);
      expect(result.detail, contains('distinct provider baselines'));
    });

    test(
      'chat-group ordinary message accepts shared provider floor without group-content wake counter',
      () async {
        final artifact = await _writePlan397ArtifactFixture(root);
        final value = _readArtifact(artifact);
        final windows = value['windows'] as List<dynamic>;
        final provider = (windows[0] as Map)['provider'] as Map;
        const baseline =
            '$relayMetricsLivenessSentinel 4100\n'
            '$relayPushSentCounter{result="success"} 700\n';
        const finalScrape =
            '$relayMetricsLivenessSentinel 4101\n'
            '$relayPushSentCounter{result="success"} 702\n';
        provider
          ..['metricFamily'] = relayPushSentCounter
          ..['attemptedDelta'] = null
          ..['pushSuccessDelta'] = 2
          ..['baseline'] = baseline
          ..['final'] = finalScrape
          ..['baselineSha256'] = _plan397FixtureDigest(baseline)
          ..['finalSha256'] = _plan397FixtureDigest(finalScrape)
          ..['relayAttributed'] = false
          ..['providerResultCount'] = null;
        _writeArtifact(artifact, value);

        final result = await validateGroupReactionNotificationArtifact(
          scenario: iosChatGroupMessageAndReactionScenarioId,
          artifactFile: artifact,
        );
        expect(result.ok, isTrue, reason: result.detail);
      },
    );
  });

  group('Plan 398 installed iOS notification authorization preflight', () {
    String normalizedLine(
      String authorization, {
      String alert = 'enabled',
      String badge = 'enabled',
    }) =>
        '2026-08-25T12:00:00.000Z Runner[398] [PUSH_DIAG] '
        'native_notification_settings context=did_finish_launching '
        'authorization=$authorization alert=$alert badge=$badge sound=disabled';

    String swiftRawLine(int authorization, {int alert = 2, int badge = 2}) =>
        '2026-08-25T12:00:00.000Z Runner[398] [PUSH_DIAG] '
        'native_notification_settings context=did_finish_launching '
        'authorization=UNAuthorizationStatus(rawValue: $authorization) '
        'alert=UNNotificationSetting(rawValue: $alert) '
        'badge=UNNotificationSetting(rawValue: $badge) '
        'sound=UNNotificationSetting(rawValue: 1)';

    test('accepts every normalized ready authorization status', () {
      for (final authorization in const <String>[
        'authorized',
        'provisional',
        'ephemeral',
      ]) {
        expect(
          plan398ExistingStateNotificationAuthorizationReady(
            'unrelated prefix line\n${normalizedLine(authorization)}\n',
          ),
          isTrue,
          reason: authorization,
        );
      }
    });

    test('accepts the installed Swift raw-value syslog representation', () {
      for (final authorization in const <int>[2, 3, 4]) {
        expect(
          plan398ExistingStateNotificationAuthorizationReady(
            swiftRawLine(authorization),
          ),
          isTrue,
          reason: 'UNAuthorizationStatus(rawValue: $authorization)',
        );
      }
    });

    test('rejects denied incomplete mixed and unrelated settings', () {
      final rejected = <String, String>{
        'normalized denied': normalizedLine('denied'),
        'normalized not determined': normalizedLine('notDetermined'),
        'normalized underscored not determined': normalizedLine(
          'not_determined',
        ),
        'normalized disabled alert': normalizedLine(
          'authorized',
          alert: 'disabled',
        ),
        'normalized unsupported badge': normalizedLine(
          'authorized',
          badge: 'not_supported',
        ),
        'raw not determined': swiftRawLine(0),
        'raw denied': swiftRawLine(1),
        'raw unsupported status': swiftRawLine(5),
        'raw disabled alert': swiftRawLine(2, alert: 1),
        'raw unsupported badge': swiftRawLine(2, badge: 0),
        'mixed normalized authorization':
            '2026-08-25 Runner[398] [PUSH_DIAG] '
            'native_notification_settings context=launch '
            'authorization=authorized '
            'alert=UNNotificationSetting(rawValue: 2) '
            'badge=UNNotificationSetting(rawValue: 2) sound=enabled',
        'mixed raw authorization':
            '2026-08-25 Runner[398] [PUSH_DIAG] '
            'native_notification_settings context=launch '
            'authorization=UNAuthorizationStatus(rawValue: 2) '
            'alert=enabled badge=enabled sound=enabled',
        'missing alert':
            '2026-08-25 Runner[398] [PUSH_DIAG] '
            'native_notification_settings context=launch '
            'authorization=authorized badge=enabled sound=enabled',
        'missing badge':
            '2026-08-25 Runner[398] [PUSH_DIAG] '
            'native_notification_settings context=launch '
            'authorization=authorized alert=enabled sound=enabled',
        'split fields across lines':
            '2026-08-25 Runner[398] [PUSH_DIAG] '
            'native_notification_settings context=launch '
            'authorization=authorized\nalert=enabled badge=enabled sound=enabled',
        'duplicate trailing settings tuple':
            '${normalizedLine('authorized')} '
            'authorization=denied alert=disabled badge=disabled sound=disabled',
        'duplicate diagnostic marker':
            '${normalizedLine('authorized')} [PUSH_DIAG] '
            'native_notification_settings context=echo '
            'authorization=denied alert=disabled badge=disabled sound=disabled',
        'raw unknown sound setting': swiftRawLine(2).replaceFirst(
          'sound=UNNotificationSetting(rawValue: 1)',
          'sound=UNNotificationSetting(rawValue: 9)',
        ),
        'unrelated line':
            '[PUSH_DIAG] another_event context=launch '
            'authorization=authorized alert=enabled badge=enabled sound=enabled',
      };

      for (final entry in rejected.entries) {
        expect(
          plan398ExistingStateNotificationAuthorizationReady(entry.value),
          isFalse,
          reason: entry.key,
        );
      }
    });
  });

  group('Plan 398 iOS logger liveness contract', () {
    Plan398IosLoggerLivenessFailure? classify({
      bool started = true,
      bool connected = true,
      int? exitCode,
      String stdoutLog = '',
      String stderrLog = '',
    }) => classifyPlan398IosLoggerLiveness(
      loggerStarted: started,
      loggerConnected: connected,
      observedExitCode: exitCode,
      stdoutLog: stdoutLog,
      stderrLog: stderrLog,
    );

    test('requires a started and initially connected logger', () {
      expect(
        classify(started: false, connected: false),
        Plan398IosLoggerLivenessFailure.notStarted,
      );
      expect(
        classify(connected: false),
        Plan398IosLoggerLivenessFailure.notConnected,
      );
      expect(classify(), isNull);
    });

    test('fails closed after any observed process exit', () {
      expect(classify(exitCode: 0), Plan398IosLoggerLivenessFailure.exited);
      expect(classify(exitCode: -15), Plan398IosLoggerLivenessFailure.exited);
    });

    test('fails closed on a standalone disconnect sentinel', () {
      expect(
        classify(stdoutLog: 'device line\n[disconnected]\n'),
        Plan398IosLoggerLivenessFailure.disconnected,
      );
      expect(
        classify(stderrLog: '[disconnected]'),
        Plan398IosLoggerLivenessFailure.disconnected,
      );
      expect(
        classify(stdoutLog: 'app rendered [disconnected] as ordinary text'),
        isNull,
      );
    });

    test('detects a disconnect sentinel split across raw chunks', () {
      final observer = Plan398IosLoggerDisconnectObserver();
      observer.addRawChunk(utf8.encode('device line\n[discon'));
      expect(observer.observed, isFalse);
      observer.addRawChunk(utf8.encode('nected]'));
      expect(observer.observed, isTrue);

      final prose = Plan398IosLoggerDisconnectObserver()
        ..addRawChunk(
          utf8.encode('app rendered [disconnected] as ordinary text\n'),
        );
      expect(prose.observed, isFalse);
    });

    test(
      'logger failure wins while manual acknowledgement is pending',
      () async {
        final acknowledgements = StreamController<String>();
        addTearDown(acknowledgements.close);
        Plan398IosLoggerLivenessFailure? failure;
        final waiting = waitForPlan398ManualSendAcknowledgement(
          acknowledgements: acknowledgements.stream,
          readLivenessFailure: () => failure,
          timeout: const Duration(seconds: 1),
          pollInterval: const Duration(milliseconds: 1),
        );

        await Future<void>.delayed(Duration.zero);
        failure = Plan398IosLoggerLivenessFailure.disconnected;
        final result = await waiting;

        expect(
          result.disposition,
          Plan398ManualSendWaitDisposition.loggerFailed,
        );
        expect(
          result.livenessFailure,
          Plan398IosLoggerLivenessFailure.disconnected,
        );
        expect(result.acknowledgement, isNull);
      },
    );

    test(
      'accepts one acknowledgement only while the logger stays live',
      () async {
        final result = await waitForPlan398ManualSendAcknowledgement(
          acknowledgements: Stream<String>.value('SENT'),
          readLivenessFailure: () => null,
          timeout: const Duration(seconds: 1),
          pollInterval: const Duration(milliseconds: 1),
        );

        expect(
          result.disposition,
          Plan398ManualSendWaitDisposition.acknowledged,
        );
        expect(result.acknowledgement, 'SENT');
        expect(result.livenessFailure, isNull);
      },
    );

    test(
      'final recheck rejects an acknowledgement racing logger exit',
      () async {
        var reads = 0;
        final result = await waitForPlan398ManualSendAcknowledgement(
          acknowledgements: Stream<String>.value('SENT'),
          readLivenessFailure: () =>
              reads++ == 0 ? null : Plan398IosLoggerLivenessFailure.exited,
          timeout: const Duration(seconds: 1),
          pollInterval: const Duration(days: 1),
        );

        expect(
          result.disposition,
          Plan398ManualSendWaitDisposition.loggerFailed,
        );
        expect(result.livenessFailure, Plan398IosLoggerLivenessFailure.exited);
        expect(result.acknowledgement, isNull);
      },
    );

    test('capture rechecks liveness before claim, readiness, and send', () {
      final source = File(
        'integration_test/scripts/capture_group_reaction_notification_device.dart',
      ).readAsStringSync();

      String methodBody(String startNeedle, String endNeedle) {
        final start = source.indexOf(startNeedle);
        final end = source.indexOf(endNeedle, start + startNeedle.length);
        expect(start, greaterThanOrEqualTo(0), reason: startNeedle);
        expect(end, greaterThan(start), reason: endNeedle);
        return source.substring(start, end);
      }

      final claim = methodBody(
        'Future<void> _claimPlan398ExistingStateTrace() async {',
        'Future<void> _awaitPlan398ManualExistingStateSend() async {',
      );
      expect(
        claim.indexOf("await _requirePlan398IosLoggerLive('trace_claim');"),
        lessThan(claim.indexOf('final claim =')),
      );

      final ready = methodBody(
        'Future<void> _awaitPlan398ManualExistingStateSend() async {',
        'Future<void> _finalizePlan398ExistingStateTraceTerminal({',
      );
      expect(
        ready.indexOf(
          "await _requirePlan398IosLoggerLive('manual_send_ready');",
        ),
        lessThan(ready.indexOf('PLAN398_MANUAL_SEND_READY')),
      );
      expect(ready, contains('await waitForPlan398ManualSendAcknowledgement('));
      expect(
        ready,
        contains(
          'readLivenessFailure: _currentPlan398IosLoggerLivenessFailure,',
        ),
      );
      expect(ready, contains('const Duration(milliseconds: 100)'));
      expect(ready, contains('during_manual_send_wait'));

      final run = methodBody(
        'Future<void> _runPlan398ExistingStateTrace() async {',
        'Future<Map<String, Object?>> _readPlan398FinalAuthority({',
      );
      expect(
        run.indexOf("await _requirePlan398IosLoggerLive('automated_send');"),
        lessThan(run.indexOf('await _sendGroupTextOneTap(')),
      );
      expect(source, contains('process.exitCode.then<void>((exitCode)'));
      expect(
        source,
        contains('_plan398IosLoggerObservedExitCode ??= exitCode;'),
      );
    });
  });

  group('Plan 398 durable existing-state iOS trace evidence', () {
    const authorization =
        'plan398-reviewed-final-same-container-manual-trace-v1';
    final finalProductSha256 = _plan397FixtureDigest('final-runner-product');
    final finalInstallSha256 = _plan397FixtureDigest(
      'final-runner-install-terminal',
    );
    final attempt02Sha256 = _plan397FixtureDigest('attempt-02-receipt');

    Future<Plan398TraceLogFileReference> writePrivateEvidence(
      Directory root,
      String fileName,
      String contents,
    ) => writePlan398PrivateNoReplaceEvidence(
      stableFile: File('${root.path}${Platform.pathSeparator}$fileName'),
      bytes: utf8.encode(contents),
      maximumLengthBytes: 1024 * 1024,
    );

    test(
      'tees arbitrary raw chunks before chunk-safe malformed decoding',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'plan398-raw-ios-log-',
        );
        addTearDown(() async {
          if (root.existsSync()) await root.delete(recursive: true);
        });
        final capture = Plan398TraceRawLogCapture(
          outputDirectory: root,
          stdoutLimitBytes: 1024,
          stderrLimitBytes: 1024,
        );
        await capture.prepare();
        final stdoutDecoded = StringBuffer();
        final stderrDecoded = StringBuffer();
        const stdoutChunks = <List<int>>[
          <int>[0x41, 0x00, 0xe2],
          <int>[0x82],
          <int>[0xac, 0xff, 0x0a],
        ];
        const stderrChunks = <List<int>>[
          <int>[0xf0, 0x9f],
          <int>[0x92, 0xa5, 0x00, 0xfe],
        ];

        await Future.wait(<Future<void>>[
          capture.consumeStdout(
            Stream<List<int>>.fromIterable(stdoutChunks),
            stdoutDecoded,
          ),
          capture.consumeStderr(
            Stream<List<int>>.fromIterable(stderrChunks),
            stderrDecoded,
          ),
        ]);
        final committed = await capture.closeAndCommit();

        final expectedStdout = stdoutChunks.expand((chunk) => chunk).toList();
        final expectedStderr = stderrChunks.expand((chunk) => chunk).toList();
        expect(await committed.stdout.file.readAsBytes(), expectedStdout);
        expect(await committed.stderr.file.readAsBytes(), expectedStderr);
        expect(stdoutDecoded.toString(), 'A\u0000\u20ac\ufffd\n');
        expect(stderrDecoded.toString(), '\ud83d\udca5\u0000\ufffd');
        expect(stdoutDecoded.toString().endsWith('\n'), isTrue);
        expect(stderrDecoded.toString().endsWith('\n'), isFalse);
        for (final entry in <Plan398TraceLogFileReference>[
          committed.stdout,
          committed.stderr,
        ]) {
          expect((await entry.file.stat()).mode & 0x1ff, 0x180);
          expect(await entry.file.length(), entry.lengthBytes);
          expect(
            sha256.convert(await entry.file.readAsBytes()).toString(),
            entry.sha256,
          );
        }
        expect(
          root
              .listSync()
              .map((entity) => entity.path)
              .where((path) => path.contains('private-temp')),
          isEmpty,
        );
      },
    );

    test(
      'fails closed at the raw-byte bound and removes private temps',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'plan398-raw-ios-overflow-',
        );
        addTearDown(() async {
          if (root.existsSync()) await root.delete(recursive: true);
        });
        final capture = Plan398TraceRawLogCapture(
          outputDirectory: root,
          stdoutLimitBytes: 3,
          stderrLimitBytes: 3,
        );
        await capture.prepare();

        await expectLater(
          capture.consumeStdout(
            Stream<List<int>>.value(const <int>[1, 2, 3, 4]),
            StringBuffer(),
          ),
          throwsA(isA<Plan398TraceLogOverflow>()),
        );
        await capture.disposeTemps();
        expect(
          root
              .listSync()
              .map((entity) => entity.path)
              .where((path) => path.contains('private-temp')),
          isEmpty,
        );
      },
    );

    test('hard-link publication never replaces colliding evidence', () async {
      final root = await Directory.systemTemp.createTemp(
        'plan398-raw-ios-collision-',
      );
      addTearDown(() async {
        if (root.existsSync()) await root.delete(recursive: true);
      });
      final capture = Plan398TraceRawLogCapture(
        outputDirectory: root,
        stdoutLimitBytes: 64,
        stderrLimitBytes: 64,
      );
      await capture.prepare();
      await capture.consumeStdout(
        Stream<List<int>>.value(const <int>[1, 2, 3]),
        StringBuffer(),
      );
      await capture.consumeStderr(
        Stream<List<int>>.value(const <int>[4, 5, 6]),
        StringBuffer(),
      );
      final colliding = File(
        '${root.path}${Platform.pathSeparator}'
        '$plan398ExistingStateTraceIosStdoutFileName',
      );
      const sentinel = <int>[0x53, 0x45, 0x4e, 0x54, 0x49, 0x4e, 0x45, 0x4c];
      await colliding.writeAsBytes(sentinel, flush: true);

      await expectLater(
        capture.closeAndCommit(),
        throwsA(isA<FileSystemException>()),
      );
      expect(await colliding.readAsBytes(), sentinel);
      expect(
        root
            .listSync()
            .map((entity) => entity.path)
            .where((path) => path.contains('private-temp')),
        isEmpty,
      );
    });

    test(
      'terminal receipt is private no-replace and committed after logs',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'plan398-terminal-receipt-',
        );
        addTearDown(() async {
          if (root.existsSync()) await root.delete(recursive: true);
        });
        final capture = Plan398TraceRawLogCapture(
          outputDirectory: root,
          stdoutLimitBytes: 1024,
          stderrLimitBytes: 64,
        );
        await capture.prepare();
        final publicSettings = utf8.encode(
          '2026-08-25 Runner[398] [PUSH_DIAG] '
          'native_notification_settings context=did_finish_launching '
          'authorization=authorized alert=enabled badge=enabled '
          'sound=disabled\n',
        );
        await capture.consumeStdout(
          Stream<List<int>>.value(publicSettings),
          StringBuffer(),
        );
        await capture.consumeStderr(
          Stream<List<int>>.value(const <int>[0x65, 0x72, 0x72]),
          StringBuffer(),
        );
        expect(
          File(
            '${root.path}${Platform.pathSeparator}'
            '$plan398ExistingStateTraceTerminalReceiptFileName',
          ).existsSync(),
          isFalse,
        );
        final logs = await capture.closeAndCommit();
        final journal = await writePrivateEvidence(
          root,
          plan398ExistingStateTraceCommandJournalFileName,
          '{"schema":"mknoon.plan257.command-journal.v1"}',
        );
        final pixel = await writePrivateEvidence(
          root,
          plan398PixelLogFileName('21071FDF600CSC'),
          'pixel-finalized\n',
        );
        final receipt = await writePlan398ExistingStateTraceTerminalReceipt(
          outputDirectory: root,
          scenario: iosChatGroupMessageAndReactionScenarioId,
          attempt: 'attempt-03',
          authorization: authorization,
          finalRunnerProductReceiptSha256: finalProductSha256,
          finalRunnerInstallTerminalSha256: finalInstallSha256,
          attempt02ReceiptSha256: attempt02Sha256,
          terminalStatus: 'success',
          captureExitCode: 0,
          stage: 'plan398_existing_state_message_window',
          detailCode: 'trace_window_complete',
          traceAttemptClaimed: true,
          loggerStarted: true,
          loggerConnected: true,
          loggerProcessId: 100,
          runnerProcessId: 398,
          stopDisposition: 'graceful',
          loggerExitCode: -15,
          loggerForcedTimeout: false,
          logs: logs,
          commandJournal: journal,
          pixelLog: pixel,
        );
        expect((await receipt.stat()).mode & 0x1ff, 0x180);
        final accepted = await validatePlan398ExistingStateTraceTerminalReceipt(
          receiptFile: receipt,
          expectedScenario: iosChatGroupMessageAndReactionScenarioId,
          expectedAuthorization: authorization,
          expectedFinalRunnerProductReceiptSha256: finalProductSha256,
          expectedFinalRunnerInstallTerminalSha256: finalInstallSha256,
          expectedAttempt02ReceiptSha256: attempt02Sha256,
          expectedPixelLogFileName: plan398PixelLogFileName('21071FDF600CSC'),
          requireSuccessfulTrace: true,
        );
        expect(accepted.ok, isTrue, reason: accepted.detail);

        final sentinel = await receipt.readAsBytes();
        await expectLater(
          writePlan398ExistingStateTraceTerminalReceipt(
            outputDirectory: root,
            scenario: iosChatGroupMessageAndReactionScenarioId,
            attempt: 'attempt-03',
            authorization: authorization,
            finalRunnerProductReceiptSha256: finalProductSha256,
            finalRunnerInstallTerminalSha256: finalInstallSha256,
            attempt02ReceiptSha256: attempt02Sha256,
            terminalStatus: 'typed_failure',
            captureExitCode: 1,
            stage: 'capture',
            detailCode: 'must_not_replace',
            traceAttemptClaimed: true,
            loggerStarted: true,
            loggerConnected: true,
            loggerProcessId: 101,
            runnerProcessId: 399,
            stopDisposition: 'graceful',
            loggerExitCode: -15,
            loggerForcedTimeout: false,
            logs: logs,
            commandJournal: journal,
            pixelLog: pixel,
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(await receipt.readAsBytes(), sentinel);
        expect(
          jsonDecode(await receipt.readAsString()),
          containsPair('terminalStatus', 'success'),
        );
      },
    );

    test(
      'live diagnostic terminal receipt omits legacy authority hashes',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'plan398-live-terminal-',
        );
        addTearDown(() async {
          if (root.existsSync()) await root.delete(recursive: true);
        });
        final journal = await writePrivateEvidence(
          root,
          plan398ExistingStateTraceCommandJournalFileName,
          '{"shape":"live-pre-logger"}',
        );
        final receipt = await writePlan398ExistingStateTraceTerminalReceipt(
          outputDirectory: root,
          scenario: iosChatGroupMessageAndReactionScenarioId,
          authorityMode: plan398LiveDiagnosticAuthorityMode,
          terminalStatus: 'pre_logger_failure',
          captureExitCode: 78,
          stage: 'device_inventory',
          detailCode: 'live_preflight_failed',
          traceAttemptClaimed: false,
          loggerStarted: false,
          loggerConnected: false,
          loggerProcessId: null,
          runnerProcessId: null,
          stopDisposition: 'not_started',
          loggerExitCode: -1,
          loggerForcedTimeout: false,
          commandJournal: journal,
          pixelLog: null,
        );
        final decoded = Map<String, Object?>.from(
          jsonDecode(await receipt.readAsString()) as Map,
        );
        expect(
          decoded['schema'],
          plan398ExistingStateLiveDiagnosticTerminalReceiptSchema,
        );
        expect(decoded['authorityMode'], plan398LiveDiagnosticAuthorityMode);
        for (final key in const <String>[
          'authorization',
          'finalRunnerProductReceiptSha256',
          'finalRunnerInstallTerminalSha256',
          'attempt02ReceiptSha256',
        ]) {
          expect(decoded, isNot(contains(key)), reason: key);
        }
        final validation =
            await validatePlan398ExistingStateTraceTerminalReceipt(
              receiptFile: receipt,
              expectedScenario: iosChatGroupMessageAndReactionScenarioId,
              expectedAuthorityMode: plan398LiveDiagnosticAuthorityMode,
              expectedPixelLogFileName: plan398PixelLogFileName(
                '21071FDF600CSC',
              ),
              requireSuccessfulTrace: false,
            );
        expect(validation.ok, isTrue, reason: validation.detail);
      },
    );

    test(
      'successful live diagnostic terminal receipt binds finalized logs',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'plan398-live-success-terminal-',
        );
        addTearDown(() async {
          if (root.existsSync()) await root.delete(recursive: true);
        });
        final capture = Plan398TraceRawLogCapture(
          outputDirectory: root,
          stdoutLimitBytes: 1024,
          stderrLimitBytes: 64,
        );
        await capture.prepare();
        await capture.consumeStdout(
          Stream<List<int>>.value(
            utf8.encode(
              'Runner[398] [PUSH_DIAG] native_notification_settings '
              'context=did_finish_launching authorization=authorized '
              'alert=enabled badge=enabled sound=disabled\n',
            ),
          ),
          StringBuffer(),
        );
        await capture.consumeStderr(
          Stream<List<int>>.value(const <int>[0x65, 0x72, 0x72]),
          StringBuffer(),
        );
        final logs = await capture.closeAndCommit();
        final journal = await writePrivateEvidence(
          root,
          plan398ExistingStateTraceCommandJournalFileName,
          '{"shape":"live-success"}',
        );
        final pixel = await writePrivateEvidence(
          root,
          plan398PixelLogFileName('21071FDF600CSC'),
          'pixel-live-success\n',
        );
        final receipt = await writePlan398ExistingStateTraceTerminalReceipt(
          outputDirectory: root,
          scenario: iosChatGroupMessageAndReactionScenarioId,
          authorityMode: plan398LiveDiagnosticAuthorityMode,
          terminalStatus: 'success',
          captureExitCode: 0,
          stage: 'plan398_existing_state_message_window',
          detailCode: 'trace_window_complete',
          traceAttemptClaimed: true,
          loggerStarted: true,
          loggerConnected: true,
          loggerProcessId: 100,
          runnerProcessId: 398,
          stopDisposition: 'graceful',
          loggerExitCode: -15,
          loggerForcedTimeout: false,
          logs: logs,
          commandJournal: journal,
          pixelLog: pixel,
        );
        final validation =
            await validatePlan398ExistingStateTraceTerminalReceipt(
              receiptFile: receipt,
              expectedScenario: iosChatGroupMessageAndReactionScenarioId,
              expectedAuthorityMode: plan398LiveDiagnosticAuthorityMode,
              expectedPixelLogFileName: plan398PixelLogFileName(
                '21071FDF600CSC',
              ),
              requireSuccessfulTrace: true,
            );
        expect(validation.ok, isTrue, reason: validation.detail);
        final decoded = Map<String, Object?>.from(
          jsonDecode(await receipt.readAsString()) as Map,
        );
        expect(decoded['authorityMode'], plan398LiveDiagnosticAuthorityMode);
        for (final key in const <String>[
          'attempt',
          'authorization',
          'finalRunnerProductReceiptSha256',
          'finalRunnerInstallTerminalSha256',
          'attempt02ReceiptSha256',
        ]) {
          expect(decoded, isNot(contains(key)), reason: key);
        }
      },
    );

    test('terminal receipt validates failure and pre-logger shapes', () async {
      for (final shape
          in <
            ({
              String terminalStatus,
              bool started,
              bool connected,
              String stop,
              int captureExitCode,
              bool forced,
            })
          >[
            (
              terminalStatus: 'typed_failure',
              started: true,
              connected: true,
              stop: 'graceful',
              captureExitCode: 78,
              forced: false,
            ),
            (
              terminalStatus: 'unexpected_failure',
              started: true,
              connected: true,
              stop: 'graceful',
              captureExitCode: 1,
              forced: false,
            ),
            (
              terminalStatus: 'decoder_error',
              started: true,
              connected: true,
              stop: 'graceful',
              captureExitCode: 1,
              forced: false,
            ),
            (
              terminalStatus: 'cleanup_error',
              started: true,
              connected: true,
              stop: 'graceful',
              captureExitCode: 1,
              forced: false,
            ),
            (
              terminalStatus: 'manual_timeout',
              started: true,
              connected: true,
              stop: 'graceful',
              captureExitCode: 1,
              forced: false,
            ),
            (
              terminalStatus: 'logger_forced_kill',
              started: true,
              connected: true,
              stop: 'forced_kill',
              captureExitCode: 1,
              forced: true,
            ),
            (
              terminalStatus: 'pre_logger_failure',
              started: false,
              connected: false,
              stop: 'not_started',
              captureExitCode: 78,
              forced: false,
            ),
          ]) {
        final root = await Directory.systemTemp.createTemp(
          'plan398-terminal-${shape.terminalStatus}-',
        );
        try {
          final journal = await writePrivateEvidence(
            root,
            plan398ExistingStateTraceCommandJournalFileName,
            '{"shape":"${shape.terminalStatus}"}',
          );
          final pixel = shape.terminalStatus == 'pre_logger_failure'
              ? null
              : await writePrivateEvidence(
                  root,
                  plan398PixelLogFileName('21071FDF600CSC'),
                  'pixel-${shape.terminalStatus}\n',
                );
          Plan398TraceLogCommit? logs;
          if (shape.started) {
            final raw = Plan398TraceRawLogCapture(
              outputDirectory: root,
              stdoutLimitBytes: 1024,
              stderrLimitBytes: 1024,
            );
            await raw.prepare();
            await raw.consumeStdout(
              Stream<List<int>>.value(
                utf8.encode('logger-${shape.terminalStatus}\n'),
              ),
              StringBuffer(),
            );
            await raw.consumeStderr(
              const Stream<List<int>>.empty(),
              StringBuffer(),
            );
            logs = await raw.closeAndCommit();
          }
          final receipt = await writePlan398ExistingStateTraceTerminalReceipt(
            outputDirectory: root,
            scenario: iosChatGroupMessageAndReactionScenarioId,
            attempt: 'attempt-03',
            authorization: authorization,
            finalRunnerProductReceiptSha256: finalProductSha256,
            finalRunnerInstallTerminalSha256: finalInstallSha256,
            attempt02ReceiptSha256: attempt02Sha256,
            terminalStatus: shape.terminalStatus,
            captureExitCode: shape.captureExitCode,
            stage: 'capture',
            detailCode: '${shape.terminalStatus}_detail',
            traceAttemptClaimed: false,
            loggerStarted: shape.started,
            loggerConnected: shape.connected,
            loggerProcessId: shape.started ? 100 : null,
            runnerProcessId: shape.connected ? 398 : null,
            stopDisposition: shape.stop,
            loggerExitCode: shape.started ? -15 : -1,
            loggerForcedTimeout: shape.forced,
            logs: logs,
            commandJournal: journal,
            pixelLog: pixel,
          );
          final validation =
              await validatePlan398ExistingStateTraceTerminalReceipt(
                receiptFile: receipt,
                expectedScenario: iosChatGroupMessageAndReactionScenarioId,
                expectedAuthorization: authorization,
                expectedFinalRunnerProductReceiptSha256: finalProductSha256,
                expectedFinalRunnerInstallTerminalSha256: finalInstallSha256,
                expectedAttempt02ReceiptSha256: attempt02Sha256,
                expectedPixelLogFileName: plan398PixelLogFileName(
                  '21071FDF600CSC',
                ),
                requireSuccessfulTrace: false,
              );
          expect(
            validation.ok,
            isTrue,
            reason: '${shape.terminalStatus}: ${validation.detail}',
          );
          if (shape.terminalStatus == 'pre_logger_failure') {
            final decoded = jsonDecode(await receipt.readAsString());
            expect(decoded, isA<Map<String, Object?>>());
            expect((decoded as Map<String, Object?>)['pixelLog'], isNull);
          }
        } finally {
          if (root.existsSync()) await root.delete(recursive: true);
        }
      }
    });

    test('terminal receipt rejects null Pixel outside pre-logger', () async {
      final root = await Directory.systemTemp.createTemp(
        'plan398-terminal-null-pixel-',
      );
      addTearDown(() async {
        if (root.existsSync()) await root.delete(recursive: true);
      });
      final journal = await writePrivateEvidence(
        root,
        plan398ExistingStateTraceCommandJournalFileName,
        '{"shape":"typed_failure"}',
      );
      final raw = Plan398TraceRawLogCapture(
        outputDirectory: root,
        stdoutLimitBytes: 1024,
        stderrLimitBytes: 1024,
      );
      await raw.prepare();
      await raw.consumeStdout(
        Stream<List<int>>.value(utf8.encode('logger-typed-failure\n')),
        StringBuffer(),
      );
      await raw.consumeStderr(const Stream<List<int>>.empty(), StringBuffer());
      final logs = await raw.closeAndCommit();

      Future<File> writeTypedFailure(Plan398TraceLogFileReference? pixelLog) =>
          writePlan398ExistingStateTraceTerminalReceipt(
            outputDirectory: root,
            scenario: iosChatGroupMessageAndReactionScenarioId,
            attempt: 'attempt-03',
            authorization: authorization,
            finalRunnerProductReceiptSha256: finalProductSha256,
            finalRunnerInstallTerminalSha256: finalInstallSha256,
            attempt02ReceiptSha256: attempt02Sha256,
            terminalStatus: 'typed_failure',
            captureExitCode: 78,
            stage: 'capture',
            detailCode: 'typed_failure_detail',
            traceAttemptClaimed: false,
            loggerStarted: true,
            loggerConnected: true,
            loggerProcessId: 100,
            runnerProcessId: 398,
            stopDisposition: 'graceful',
            loggerExitCode: -15,
            loggerForcedTimeout: false,
            logs: logs,
            commandJournal: journal,
            pixelLog: pixelLog,
          );

      await expectLater(writeTypedFailure(null), throwsFormatException);

      final pixel = await writePrivateEvidence(
        root,
        plan398PixelLogFileName('21071FDF600CSC'),
        'pixel-typed-failure\n',
      );
      final receipt = await writeTypedFailure(pixel);
      final tampered = Map<String, Object?>.from(
        jsonDecode(await receipt.readAsString()) as Map,
      )..['pixelLog'] = null;
      await receipt.writeAsString(jsonEncode(tampered), flush: true);
      final validation = await validatePlan398ExistingStateTraceTerminalReceipt(
        receiptFile: receipt,
        expectedScenario: iosChatGroupMessageAndReactionScenarioId,
        expectedAuthorization: authorization,
        expectedFinalRunnerProductReceiptSha256: finalProductSha256,
        expectedFinalRunnerInstallTerminalSha256: finalInstallSha256,
        expectedAttempt02ReceiptSha256: attempt02Sha256,
        expectedPixelLogFileName: plan398PixelLogFileName('21071FDF600CSC'),
        requireSuccessfulTrace: false,
      );
      expect(validation.ok, isFalse);
      expect(validation.detail, contains('omitted Pixel log'));
    });

    test(
      'real post-attempt-02 state passes while new outputs and symlinks red',
      () async {
        final root = await Directory.systemTemp.createTemp(
          'plan398-stale-trace-',
        );
        addTearDown(() async {
          if (root.existsSync()) await root.delete(recursive: true);
        });
        for (final allowed in <String>[
          plan398ExistingStateTraceFailureFileName,
          plan398ExistingStateTraceCommandJournalFileName,
          'plan398_existing_state_trace_manifest.json',
          'relay_state.json',
        ]) {
          final file = File('${root.path}${Platform.pathSeparator}$allowed');
          await file.writeAsString('{"preserved":true}', flush: true);
          await Process.run('chmod', <String>['600', file.path]);
        }
        await Directory(
          '${root.path}${Platform.pathSeparator}attempt-02-private-archive',
        ).create();
        final accepted = await validatePlan398ExistingStateTraceOutputPreflight(
          root,
        );
        expect(accepted.ok, isTrue, reason: accepted.detail);
        final stale = File(
          '${root.path}${Platform.pathSeparator}'
          '$plan398ExistingStateTraceTerminalReceiptFileName',
        );
        await stale.writeAsString('sentinel', flush: true);
        final rejected = await validatePlan398ExistingStateTraceOutputPreflight(
          root,
        );
        expect(rejected.ok, isFalse);
        expect(rejected.detail, contains('terminal_receipt'));
        await stale.delete();
        await File(
          '${root.path}${Platform.pathSeparator}'
          'plan398_existing_state_trace_ios_stdout.bin.1.private-temp',
        ).writeAsString('residue', flush: true);
        final residue = await validatePlan398ExistingStateTraceOutputPreflight(
          root,
        );
        expect(residue.ok, isFalse);
        expect(residue.detail, contains('private-temp'));
        await File(
          '${root.path}${Platform.pathSeparator}'
          'plan398_existing_state_trace_ios_stdout.bin.1.private-temp',
        ).delete();
        final dangling = Link(
          '${root.path}${Platform.pathSeparator}'
          '$plan398ExistingStateTraceTerminalReceiptFileName',
        );
        await dangling.create('${root.path}/missing-target');
        final symlink = await validatePlan398ExistingStateTraceOutputPreflight(
          root,
        );
        expect(symlink.ok, isFalse);
        expect(symlink.detail, contains('terminal_receipt'));
      },
    );

    test(
      'private publication fsyncs its directory and never replaces',
      () async {
        final root = await Directory.systemTemp.createTemp('plan398-fsync-');
        addTearDown(() async {
          if (root.existsSync()) await root.delete(recursive: true);
        });
        final stable = File('${root.path}/claim.json');
        final first = await writePlan398PrivateNoReplaceEvidence(
          stableFile: stable,
          bytes: utf8.encode('{"claim":"first"}'),
          maximumLengthBytes: 4096,
        );
        expect(
          first.sha256,
          sha256.convert(await stable.readAsBytes()).toString(),
        );
        await fsyncPlan398Directory(root);
        final sentinel = await stable.readAsBytes();
        await expectLater(
          writePlan398PrivateNoReplaceEvidence(
            stableFile: stable,
            bytes: utf8.encode('{"claim":"replacement"}'),
            maximumLengthBytes: 4096,
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(await stable.readAsBytes(), sentinel);
      },
    );

    test('capture finalizer reserves null Pixel for genuine pre-logger', () {
      final source = File(
        'integration_test/scripts/capture_group_reaction_notification_device.dart',
      ).readAsStringSync();
      expect(source, contains('_plan398TraceRawLogs = null'));
      expect(source, contains('await rawLogs.disposeTemps()'));
      expect(source, contains('loggerForcedTimeout'));
      expect(source, contains('await _flushCommandJournal()'));
      expect(
        source,
        contains(
          'final canOmitPixelLog =\n'
          "        terminalStatus == 'pre_logger_failure' &&",
        ),
      );
      expect(source, contains('pixelFile == null && !canOmitPixelLog'));
      expect(source, contains('pixelLog: _plan398PixelLogReference,'));
      expect(source, isNot(contains('pixelLog: _plan398PixelLogReference!')));
    });

    test('capture publishes success terminal after artifact verdict', () {
      final source = File(
        'integration_test/scripts/capture_group_reaction_notification_device.dart',
      ).readAsStringSync();
      final runStart = source.indexOf(
        'Future<void> _runPlan398ExistingStateTrace() async {',
      );
      final runEnd = source.indexOf(
        'Future<Map<String, Object?>> _readPlan398FinalAuthority(',
        runStart,
      );
      expect(runStart, greaterThanOrEqualTo(0));
      expect(runEnd, greaterThan(runStart));
      final runBody = source.substring(runStart, runEnd);

      int position(String needle) {
        final index = runBody.indexOf(needle);
        expect(index, greaterThanOrEqualTo(0), reason: needle);
        return index;
      }

      final cleanup = position('await cleanupTransientState();');
      final artifact = position(
        'await _writePlan398ExistingStateTraceArtifact(installedState);',
      );
      final validation = position(
        'await validatePlan398ExistingStateTraceArtifact(',
      );
      final verdict = position('await verdict.writeAsString(');
      final successTerminal = position(
        'await _finalizePlan398ExistingStateTraceTerminal(\n'
        "      requestedStatus: 'success',",
      );
      expect(cleanup, lessThan(artifact));
      expect(artifact, lessThan(validation));
      expect(validation, lessThan(verdict));
      expect(verdict, lessThan(successTerminal));

      final failureStart = source.indexOf('Future<void> writeFailure(', runEnd);
      final failureEnd = source.indexOf(
        'Future<Map<String, Object?>> _readStagingManifest() async {',
        failureStart,
      );
      expect(failureStart, greaterThanOrEqualTo(0));
      expect(failureEnd, greaterThan(failureStart));
      final failureBody = source.substring(failureStart, failureEnd);
      expect(failureBody, contains('if (_plan398TraceTransactionStarted)'));
      expect(
        RegExp(
          r'await _finalizePlan398ExistingStateTraceTerminal\(',
        ).allMatches(failureBody),
        hasLength(1),
      );
      for (final nonSuccess in const <String>{
        'manual_timeout',
        'unexpected_failure',
        'typed_failure',
      }) {
        expect(failureBody, contains("'$nonSuccess'"));
      }
      expect(failureBody, contains('requestedStatus: terminalStatus'));
      expect(failureBody, isNot(contains("requestedStatus: 'success'")));
      expect(source, contains('if (_plan398TerminalReceiptCommitted) return;'));
    });

    test('extracts exactly one fresh Runner PID from devicectl JSON', () {
      expect(
        plan398RunnerProcessIdFromDevicectlLaunchJson(<String, Object?>{
          'result': <String, Object?>{
            'process': <String, Object?>{'processIdentifier': 398},
          },
        }),
        398,
      );
      expect(
        plan398RunnerProcessIdFromDevicectlLaunchJson(<String, Object?>{
          'result': <String, Object?>{
            'processIdentifier': 398,
            'nested': <String, Object?>{'processIdentifier': 399},
          },
        }),
        isNull,
      );
      expect(
        plan398RunnerProcessIdFromDevicectlLaunchJson(<String, Object?>{
          'result': <String, Object?>{'processIdentifier': 0},
        }),
        isNull,
      );
    });

    test(
      'strict public settings parser rejects unified-log privacy tokens',
      () {
        const publicLine =
            '2026-08-25 Runner[398] [PUSH_DIAG] '
            'native_notification_settings context=did_finish_launching '
            'authorization=authorized alert=enabled badge=enabled '
            'sound=disabled';
        expect(
          plan398ExistingStateNotificationAuthorizationReady(
            publicLine,
            expectedRunnerProcessId: 398,
          ),
          isTrue,
        );
        expect(
          plan398ExistingStateNotificationAuthorizationReady(
            publicLine,
            expectedRunnerProcessId: 399,
          ),
          isFalse,
        );
        expect(
          plan398ExistingStateNotificationAuthorizationReady(
            '2026-08-25 Runner[398] [PUSH_DIAG] '
            'native_notification_settings context=did_finish_launching '
            'authorization=<private> alert=<private> badge=<private> '
            'sound=<private>',
          ),
          isFalse,
        );
      },
    );
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

final class _CentralBuildFixture {
  const _CentralBuildFixture({
    required this.profileId,
    required this.artifact,
    required this.report,
    required this.generatedAt,
    required this.artifactDigest,
  });

  final String profileId;
  final File artifact;
  final File report;
  final DateTime generatedAt;
  final String artifactDigest;
}

_CentralBuildFixture _writeCentralBuildFixture(
  Directory root, {
  required String profileId,
}) {
  final inputDigest = 'c' * 64;
  final cacheEntry = Directory(
    '${root.path}${Platform.pathSeparator}$profileId'
    '${Platform.pathSeparator}$inputDigest',
  )..createSync(recursive: true);
  final artifact = File(
    '${cacheEntry.path}${Platform.pathSeparator}artifact.apk',
  )..writeAsBytesSync(utf8.encode('plan397 central artifact'));
  final artifactDigest = groupReactionSimsArtifactDigest(artifact);
  final generatedAt = DateTime.utc(2026, 8, 22, 20);
  File(
    '${cacheEntry.path}${Platform.pathSeparator}attestation.json',
  ).writeAsStringSync(
    jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'profileId': profileId,
      'inputDigest': inputDigest,
      'artifactDigest': artifactDigest,
      'artifactPath': artifact.absolute.path,
      'redactedCommand': <String>['central-build'],
      'createdAt': generatedAt.toIso8601String(),
    }),
  );
  final report = File(
    '${root.path}${Platform.pathSeparator}$profileId-report.json',
  );
  _writeBuildReport(
    report,
    profileId: profileId,
    artifactDigest: artifactDigest,
    generatedAt: generatedAt,
  );
  return _CentralBuildFixture(
    profileId: profileId,
    artifact: artifact,
    report: report,
    generatedAt: generatedAt,
    artifactDigest: artifactDigest,
  );
}

void _writeBuildReport(
  File report, {
  required String profileId,
  required String artifactDigest,
  required DateTime generatedAt,
}) {
  report.writeAsStringSync(
    jsonEncode(<String, Object?>{
      'schemaVersion': 1,
      'generatedAt': generatedAt.toUtc().toIso8601String(),
      'builds': <String, Object?>{
        'artifactDigests': <String, String>{profileId: artifactDigest},
        'failedProfileIds': <String>[],
      },
    }),
  );
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

/// A raw `/metrics` scrape pair whose deltas are exactly what a clean
/// two-transition reaction capture produces.
///
/// Values are absolute and large on purpose: on the production relay these
/// counters carry every other user's traffic too, so a validator that read the
/// FINAL value instead of the delta would be trivially wrong and this fixture
/// makes that mistake fail.
String groupReactionRelayMetricsFixture({
  double attemptedDelta = 2,
  double routeErrorDelta = 0,
  double incapableSkippedDelta = 0,
  double pushSentDelta = 2,
  bool includeFinalPhase = true,
  bool relayRestarted = false,
}) {
  const attemptedBase = 40.0;
  const routeErrorBase = 3.0;
  const incapableBase = 1.0;
  const pushSentBase = 900.0;
  String scrape(
    double attempted,
    double routeError,
    double incapable,
    double push,
    double sentinel,
  ) =>
      // The liveness sentinel is a PLAIN counter, so it is exported from
      // registration; the two graded families are labelled CounterVecs and are
      // absent entirely until first increment.
      '$relayMetricsLivenessSentinel $sentinel\n'
      'relay_group_reaction_wake_total{outcome="attempted"} $attempted\n'
      'relay_group_reaction_wake_total{outcome="route_error"} $routeError\n'
      'relay_group_reaction_wake_total{outcome="incapable_skipped"} $incapable\n'
      'relay_group_reaction_wake_total{outcome="no_wake_recipients"} 7.0\n'
      'relay_push_sent_total{result="success"} $push\n';
  final buffer = StringBuffer()
    ..write('$relayMetricsPhaseMarker$relayMetricsBaselinePhase\n')
    ..write(
      scrape(attemptedBase, routeErrorBase, incapableBase, pushSentBase, 2320),
    );
  if (includeFinalPhase) {
    buffer
      ..write('$relayMetricsPhaseMarker$relayMetricsFinalPhase\n')
      ..write(
        scrape(
          attemptedBase + attemptedDelta,
          routeErrorBase + routeErrorDelta,
          incapableBase + incapableSkippedDelta,
          pushSentBase + pushSentDelta,
          relayRestarted ? 4 : 2325,
        ),
      );
  }
  return buffer.toString();
}

/// Replaces one evidence file's contents and re-pins its digest/length in the
/// artifact, so a rewritten fixture still passes the integrity checks that run
/// before the rule under test.
void _rewriteEvidence(File artifact, String kind, String contents) {
  final decoded = _readArtifact(artifact);
  final record = (decoded['evidence'] as List<dynamic>)
      .cast<Map<String, dynamic>>()
      .firstWhere((entry) => entry['kind'] == kind);
  final file = File(
    '${artifact.parent.path}${Platform.pathSeparator}${record['path']}',
  );
  file.writeAsStringSync(contents, flush: true);
  _updateEvidenceDigest(record, file);
  _writeArtifact(artifact, decoded);
}

String _plan397FixtureDigest(String value) =>
    sha256.convert(utf8.encode(value)).toString();

Future<File> _writePlan397ArtifactFixture(Directory root) async {
  final scenario = groupReactionNotificationScenario(
    iosChatGroupMessageAndReactionScenarioId,
  )!;
  final directory = Directory('${root.path}${Platform.pathSeparator}plan397')
    ..createSync(recursive: true);
  const senderId = '21071FDF600CSC';
  const recipientId = '00008150-001C3C6A3684401C';
  final groupId = _plan397FixtureDigest('group-id');
  final messageId = _plan397FixtureDigest('message-id');
  final targetId = _plan397FixtureDigest('target-id');
  final reactionId = _plan397FixtureDigest('reaction-id');
  final groupName = _plan397FixtureDigest('Garden Club');
  final messageText = _plan397FixtureDigest('plan397-message');
  final targetText = _plan397FixtureDigest('plan397-target');
  final androidInput = _plan397FixtureDigest('android-input');
  final androidArtifact = _plan397FixtureDigest('android-artifact');
  final iosInput = _plan397FixtureDigest('ios-input');
  final iosArtifact = _plan397FixtureDigest('ios-artifact');

  final iosManifestValue = <String, Object?>{
    'schema': 'mknoon.sims.ios-device-production-bundle.v1',
    'profileId': 'ios.device.production',
    'centralCompileCommands': 1,
    'logicalBuildCount': 1,
    'childBuildCount': 0,
    'applicationApp': 'Runner.app',
    'xctestrun': 'RunnerUITests.xctestrun',
    'testProducts': 'test-products',
  };
  final iosManifestEncoded = jsonEncode(iosManifestValue);

  final centralBuildProvenance = await _writeReferencedJson(
    directory,
    'plan397_central_build_provenance.json',
    <String, Object?>{
      'schema': 'mknoon.plan397.central-build-provenance.v1',
      'android': <String, Object?>{
        'profileId': 'android.production_fcm',
        'inputDigest': androidInput,
        'artifactDigest': androidArtifact,
        'attestationAdjacent': true,
      },
      'ios': <String, Object?>{
        'profileId': 'ios.device.production',
        'inputDigest': iosInput,
        'artifactDigest': iosArtifact,
        'attestationAdjacent': true,
      },
      'iosBundleManifestSha256': _plan397FixtureDigest(iosManifestEncoded),
      'androidChildBuildCount': 0,
      'iosNormalChildBuildCount': 0,
      'recordedAt': '2026-08-22T11:59:00.000Z',
    },
  );
  final androidBuildReport = await _writeReferencedJson(
    directory,
    'android-attempt-1-build-report.json',
    <String, Object?>{
      'builds': <String, Object?>{
        'artifactDigests': <String, Object?>{
          'android.production_fcm': androidArtifact,
        },
      },
    },
  );
  final iosBuildReport = await _writeReferencedJson(
    directory,
    'ios-attempt-1-build-report.json',
    <String, Object?>{
      'builds': <String, Object?>{
        'artifactDigests': <String, Object?>{
          'ios.device.production': iosArtifact,
        },
      },
    },
  );
  final androidAttestation = await _writeReferencedJson(
    directory,
    'android-attestation.json',
    <String, Object?>{
      'schemaVersion': 1,
      'profileId': 'android.production_fcm',
      'inputDigest': androidInput,
      'artifactDigest': androidArtifact,
    },
  );
  final iosAttestation = await _writeReferencedJson(
    directory,
    'ios-attestation.json',
    <String, Object?>{
      'schemaVersion': 1,
      'profileId': 'ios.device.production',
      'inputDigest': iosInput,
      'artifactDigest': iosArtifact,
    },
  );
  final iosBundleManifest = await _writeReferencedJson(
    directory,
    'bundle_manifest.json',
    iosManifestValue,
  );
  final setupInstall = await _writeReferencedJson(
    directory,
    'ios_setup_installed_app_inventory.json',
    <String, Object?>{'bundleIdentifier': 'com.mknoon.app', 'mode': 'setup'},
  );
  final centralInstall = await _writeReferencedJson(
    directory,
    'ios_central_normal_installed_app_inventory.json',
    <String, Object?>{
      'bundleIdentifier': 'com.mknoon.app',
      'mode': 'central_normal',
      'containerPreserved': true,
    },
  );
  final commandJournal = await _writeReferencedJson(
    directory,
    'automation_command_journal.json',
    <String, Object?>{
      'schema': 'mknoon.plan397.command-journal.v1',
      'commands': <Object?>[
        <String, Object?>{'stage': 'plan397_ios_setup_build'},
        <String, Object?>{'stage': 'plan397_central_normal_install'},
        <String, Object?>{'stage': 'plan397_message_window'},
        <String, Object?>{'stage': 'plan397_reaction_window'},
      ],
    },
  );

  Map<String, Object?> metricWindow(String phase, int offset) {
    final reaction = phase == 'reaction';
    final family = reaction
        ? relayGroupReactionWakeCounter
        : relayPushSentCounter;
    final attempted = 40 + offset;
    final pushed = 900 + offset;
    final pushDelta = reaction ? 1 : 2;
    final baseline =
        '$relayMetricsLivenessSentinel ${2300 + offset}\n'
        '${reaction ? '$family{outcome="attempted"} $attempted\n' : ''}'
        '$relayPushSentCounter{result="success"} $pushed\n';
    final finalScrape =
        '$relayMetricsLivenessSentinel ${2301 + offset}\n'
        '${reaction ? '$family{outcome="attempted"} ${attempted + 1}\n' : ''}'
        '$relayPushSentCounter{result="success"} ${pushed + pushDelta}\n';
    return <String, Object?>{
      'metricFamily': family,
      'attemptedDelta': reaction ? 1 : null,
      'pushSuccessDelta': pushDelta,
      'baseline': baseline,
      'final': finalScrape,
      'baselineSha256': _plan397FixtureDigest(baseline),
      'finalSha256': _plan397FixtureDigest(finalScrape),
      'relayAttributed': reaction,
      'providerResultCount': reaction ? 1 : null,
      'deletedOrUnattributedEvidence': false,
    };
  }

  Map<String, Object?> window(String phase, int ordinal) {
    final reaction = phase == 'reaction';
    final eventId = reaction ? reactionId : messageId;
    final observerNonce = _plan397FixtureDigest('observer-nonce-$phase');
    return <String, Object?>{
      'phase': phase,
      'ordinal': ordinal,
      'payloadKind': reaction ? 'group_reaction' : 'group_message',
      'windowIdSha256': _plan397FixtureDigest('window-$phase'),
      'observerRunIdSha256': _plan397FixtureDigest('observer-run-$phase'),
      'observerNonceSha256': observerNonce,
      'androidObservation': <String, Object?>{
        'schema': 'mknoon.plan257.sqlcipher-observation.v1',
        'phase': phase,
        'groupIdSha256': groupId,
        'messageIdSha256': messageId,
        'targetMessageIdSha256': targetId,
        'eventIdSha256': eventId,
        'reactionIdSha256': reaction ? reactionId : null,
        'reactionTargetIdSha256': reaction ? targetId : null,
        'firstIncoming': false,
        'targetIncoming': true,
        'targetRead': true,
        'reactionRows': reaction ? 1 : 0,
        'reactionEmojiSha256': reaction
            ? _plan397FixtureDigest('thumbs-up')
            : null,
        'rawIdentifiersPersisted': false,
      },
      'provider': metricWindow(phase, reaction ? 20 : 0),
      'nse': <String, Object?>{
        'payloadKind': reaction ? 'group_reaction' : 'group_message',
        'decryptOkCount': 1,
        'didReceiveCount': 1,
        'decryptFailureCount': 0,
        'timeoutCount': 0,
        'runOwnedLocalPublicationCount': 0,
        'contenderDisposition': 'not_observed',
        'contenderSuppressionCount': 0,
        'windowSha256': _plan397FixtureDigest('nse-window-$phase'),
        'rawPayloadPersisted': false,
      },
      'nativeInventory': <String, Object?>{
        'schema':
            'mknoon.sims.ios-group-notification-observation-host-receipt.v1',
        'action': 'observe-group',
        'phase': phase,
        'status': 'PASS',
        'containsSecrets': false,
        'bundleId': 'com.mknoon.app',
        'captureNonceSha256': observerNonce,
        'receiverDeviceIdSha256': _plan397FixtureDigest(recipientId),
        'expectedGroupIdSha256': groupId,
        'expectedEventIdSha256': eventId,
        'expectedTargetMessageIdSha256': targetId,
        'matchingRemoteCount': 1,
        'matchingLocalCount': 0,
        'matchingUsefulProviderCount': 1,
        'matchingSanitizedProviderCount': 0,
        'matchingFlutterLocalCount': 0,
        'matchingUnknownCount': 0,
        'matchingTotalCount': 1,
        'stableSampleCount': 3,
        'stableSampleIntervalMilliseconds': 500,
        'observationDeadlineMilliseconds': 8000,
        'sampledThroughDeadline': true,
        'badSourceSeen': false,
        'duplicateSeen': false,
        'requestIdentifierSha256': <String>[
          _plan397FixtureDigest('request-identifier-$phase'),
        ],
        'childBuildCount': 0,
        'manualActionCount': 0,
        'runnerTerminated': true,
        'preTapCleanupLaunchCount': 0,
        'resultCode': 'ok',
        'completedAt': reaction
            ? '2026-08-22T12:03:00.000Z'
            : '2026-08-22T12:01:00.000Z',
      },
      'tap': <String, Object?>{
        'selector': 'testChatGroupNotificationTap',
        'passed': true,
        'sameCardContainer': true,
        'matchingCardCount': 1,
        'titleMatched': true,
        'bodyMatched': true,
        'routeMatched': true,
        'finalUnreadCount': 0,
        'manualTaps': 0,
        'coldLaunch': true,
        'expectedTitleSha256': groupName,
        'expectedBodySha256': _plan397FixtureDigest('body-$phase'),
        'expectedRouteTextSha256': reaction ? targetText : messageText,
      },
      'diagnostics': <String, Object?>{
        'runOwnedLocalPublicationCount': 0,
        'contenderDisposition': 'not_observed',
        'contenderSuppressionCount': 0,
        'rawIdentifiersPersisted': false,
        'rawPayloadPersisted': false,
      },
      'relayJournalSha256': _plan397FixtureDigest('relay-journal-$phase'),
      'relayJournalLineCount': 1,
      'openedAt': reaction
          ? '2026-08-22T12:02:00.000Z'
          : '2026-08-22T12:00:00.000Z',
      'closedAt': reaction
          ? '2026-08-22T12:03:00.000Z'
          : '2026-08-22T12:01:00.000Z',
    };
  }

  final artifact = File(
    '${directory.path}${Platform.pathSeparator}'
    '$iosChatGroupMessageAndReactionScenarioId.json',
  );
  _writeArtifact(artifact, <String, Object?>{
    'schema': iosChatGroupMessageAndReactionArtifactSchema,
    'version': iosChatGroupMessageAndReactionArtifactVersion,
    'scenario': scenario.id,
    'testCase': scenario.testCase,
    'status': 'passed',
    'generatedBy': 'automated_capture_pipeline',
    'topology': <String, Object?>{
      'groupType': 'chat',
      'sender': <String, Object?>{
        'platform': 'android',
        'deviceKind': 'physical',
        'deviceId': senderId,
        'liveDiscovered': true,
      },
      'recipient': <String, Object?>{
        'platform': 'ios',
        'deviceKind': 'physical',
        'deviceId': recipientId,
        'liveDiscovered': true,
      },
    },
    'centralBuild': <String, Object?>{
      'android': <String, Object?>{
        'profileId': 'android.production_fcm',
        'inputDigest': androidInput,
        'artifactDigest': androidArtifact,
        'attestationAdjacent': true,
      },
      'ios': <String, Object?>{
        'profileId': 'ios.device.production',
        'inputDigest': iosInput,
        'artifactDigest': iosArtifact,
        'attestationAdjacent': true,
      },
      'setupApplicationSha256': _plan397FixtureDigest('setup-app'),
      'centralApplicationSha256': _plan397FixtureDigest('central-app'),
      'setupSelectorsReusedOneProduct': true,
      'setupChildBuildCount': 1,
      'androidChildBuildCount': 0,
      'iosNormalChildBuildCount': 0,
      'normalInstalledInPlace': true,
      'uninstallBetweenSetupAndNormal': false,
      'setupContainerPreserved': true,
    },
    'capture': <String, Object?>{
      'centralBuildProvenance': centralBuildProvenance,
      'androidBuildReport': androidBuildReport,
      'iosBuildReport': iosBuildReport,
      'androidAttestation': androidAttestation,
      'iosAttestation': iosAttestation,
      'iosBundleManifest': iosBundleManifest,
      'setupInstall': setupInstall,
      'centralNormalInstall': centralInstall,
      'commandJournal': commandJournal,
    },
    'identities': <String, Object?>{
      'groupNameSha256': groupName,
      'messageTextSha256': messageText,
      'targetTextSha256': targetText,
    },
    'windows': <Object?>[window('message', 1), window('reaction', 2)],
    'execution': <String, Object?>{
      'automation': 'fully_automated',
      'manualTaps': 0,
      'childBuildsDuringGradedWindows': 0,
      'messageSendCount': 1,
      'reactionAddCount': 1,
      'reactionRemoveCount': 0,
      'reactionReAddCount': 0,
    },
    'redaction': <String, Object?>{
      'pushTokensPersisted': false,
      'secretKeysPersisted': false,
      'ciphertextPersisted': false,
      'plaintextPayloadPersisted': false,
      'rawPeerIdsPersisted': false,
      'rawGroupOrMessageIdsPersisted': false,
    },
  });
  return artifact;
}

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
    'expectedRelayWakeAttempts': 2,
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
    add('ios_candidate_build', 'flutter', <String>[
      'build',
      'ios',
      '--profile',
    ]);
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
    if (groupReactionNotificationKeepsRecipientProcessAlive(scenario.id)) {
      add(lifecycleStage, 'adb', <String>[
        '-s',
        recipientId,
        'shell',
        'input',
        'keyevent',
        'KEYCODE_HOME',
      ]);
      add(lifecycleStage, 'adb', <String>[
        '-s',
        recipientId,
        'shell',
        'pidof',
        'com.mknoon.app',
      ]);
    } else {
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
    }
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
      final lines = <String>[
        '2026-07-12T12:00:01.000Z [GROUP_INBOX] Stored message for group '
            'group_hash=group-257 remote_type=$event '
            'group_type=${scenario.groupType}',
        '2026-07-12T12:00:02.000Z [PUSH] Queued group delivery '
            'event=$event action=add relay_store_matched=true',
        '2026-07-12T12:00:03.000Z [GROUP_INBOX] Stored message for group '
            'group_hash=group-257 remote_type=$event action=add',
        // Plan 386. Relay v1.8.0 (`8d86501e4`) emits a BARE
        // `[GROUP_REACTION_WAKE] outcome=<word>`; the `remote_type=` attribute
        // this fixture used to carry was deleted with the rest of the
        // attributed vocabulary, and `outcome=dispatched` is the word the relay
        // prints once per recipient it hands to the provider
        // (`go-relay-server/inbox.go:2797`).
        if (groupReactionNotificationKeepsRecipientProcessAlive(scenario.id))
          '2026-07-12T12:00:03.500Z [GROUP_REACTION_WAKE] outcome=dispatched',
        '2026-07-12T12:00:04.000Z [PUSH] outcome=success attempt=1 '
            'total_attempts=3',
      ];
      return '${lines.join('\n')}\n';
    case 'provider_fcm':
      // Plan 386. `[PUSH] (Group )?Notification sent to <prefix>` no longer
      // exists on any relay: `8d86501e4` deleted every attributed `[PUSH]`
      // line, and the vocabulary is frozen that way by the relay's own private
      // -value closure test. What survives is the attribution-free acceptance,
      // which is why the COUNT moved onto the relay's counters.
      return '${<String>['2026-07-12T12:00:04.000Z [PUSH] outcome=success attempt=1 '
          'total_attempts=3 event=$event delivery_matched=true', '2026-07-12T12:00:05.000Z [PUSH] outcome=success attempt=1 '
          'total_attempts=3 event=$event delivery_matched=true'].join('\n')}\n';
    case 'relay_metrics':
      return groupReactionRelayMetricsFixture();
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
      if (groupReactionNotificationKeepsRecipientProcessAlive(scenario.id)) {
        final observation = <String, Object?>{
          'schema': 'mknoon.plan315.background-connected-observation.v1',
          'scenario': scenario.id,
          'pidPresentBeforeDelivery': true,
          'connectivityEvent': 'P2P_RELAY_PRESENCE_SET_RESPONSE',
          'connectivityState': 'background',
          'connectivityOk': true,
          'homeAt': '2026-07-12T12:00:00.000Z',
          'reactionAt': '2026-07-12T12:00:03.000Z',
          'notificationAt': '2026-07-12T12:00:04.000Z',
          'minimumHomeToReactDelayMs':
              groupReactionBackgroundConnectedHomeToReactDelayMs,
          'homeToReactDelayMs':
              groupReactionBackgroundConnectedHomeToReactDelayMs,
          'notificationObservationWindowMs':
              groupReactionBackgroundConnectedObservationWindowMs,
          'reactionToNotificationMs': 1000,
        };
        return '${<String>[
          _flowLine('P2P_RELAY_PRESENCE_SET_RESPONSE', <String, Object?>{'state': 'background', 'ok': true}),
          _flowLine('PUSH_BACKGROUND_REACTION_CRYPTO_PLUGIN_OK', <String, Object?>{'processState': 'background_connected'}),
          _flowLine('PUSH_ANDROID_DATA_DECRYPT_OK', <String, Object?>{'parity': true}),
          _flowLine('GROUP_NOTIFICATION_ROUTE_TARGET_MATCHED', <String, Object?>{'targetMarker': targetMarker}),
          '$groupReactionBackgroundConnectedObservationPrefix${jsonEncode(observation)}',
          'pid_present_before_delivery=true connectivity_event=P2P_RELAY_PRESENCE_SET_RESPONSE home_to_react_delay_ms=$groupReactionBackgroundConnectedHomeToReactDelayMs notification_observation_window_ms=$groupReactionBackgroundConnectedObservationWindowMs',
        ].join('\n')}\n';
      }
      // Plan 389. THREE post-kill wakes — the throwaway warm-up text, the
      // reaction ADD and the reaction re-ADD. The lane emitted two before the
      // warm-up existed, which is why the validator's floor is three.
      return _killedReactionRecipientApp(wakes: 3, targetMarker: targetMarker);
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

/// The killed-recipient reaction lane's `recipient_app` evidence.
///
/// [wakes] is how many background pushes the isolate took AFTER the kill. The
/// capture clears the recipient's log at the kill, so every wake in this
/// evidence is post-kill by construction and no cursor is involved.
String _killedReactionRecipientApp({
  required int wakes,
  required String targetMarker,
}) {
  return '${<String>[
    for (var index = 0; index < wakes; index++)
      // No `messageId`: the real group-reaction push carries only
      // `{'kind': 'group_reaction'}`, which is exactly why the rule that reads
      // this evidence is cardinal rather than identity-bound.
      _flowLine('PUSH_BACKGROUND_MESSAGE_RECEIVED', <String, Object?>{'kind': index == 0 ? 'group_message' : 'group_reaction'}),
    _flowLine('PUSH_BACKGROUND_REACTION_CRYPTO_PLUGIN_OK', <String, Object?>{'processState': 'killed'}),
    _flowLine('PUSH_ANDROID_DATA_DECRYPT_OK', <String, Object?>{'parity': true}),
    _flowLine('GROUP_NOTIFICATION_ROUTE_TARGET_MATCHED', <String, Object?>{'targetMarker': targetMarker}),
  ].join('\n')}\n';
}

/// One `android_notification_records` evidence body, block by block.
///
/// [blocks] maps a source file name to the cards that block holds. The
/// per-block card list is open so a warm-up card, a foreign card, or a block
/// with no graded card at all can be posed — shapes the fixed two-card
/// [_notificationRecords] builder cannot express.
String _notificationRecordBlocks({
  required String appPackage,
  required Map<String, List<({int id, String title, String body})>> blocks,
}) {
  final buffer = StringBuffer();
  var second = 4;
  for (final entry in blocks.entries) {
    buffer.writeln('source_file=${entry.key}');
    for (final card in entry.value) {
      buffer
        ..writeln(
          'NotificationRecord(pkg=$appPackage id=${card.id} '
          'tag=group-${card.id} user=0)',
        )
        ..writeln('  android.title=String (${card.title})')
        ..writeln('  android.text=String (${card.body})')
        ..writeln('  android.groupKey=String (group-${card.id})')
        ..writeln(
          '  postTime=2026-07-12T12:00:'
          '${second.toString().padLeft(2, '0')}.000Z',
        );
      second += 1;
    }
  }
  return buffer.toString();
}

/// One `ui_automation` evidence body, block by block.
///
/// Each label becomes its OWN `<node>` inside the block's single `<hierarchy>`,
/// which is how the recipient's Orbit really renders two group rows. The
/// packed-into-one-node form [_uiHierarchySnapshots] uses cannot pose that.
String _uiHierarchyBlocks(Map<String, List<String>> blocks) {
  final buffer = StringBuffer();
  for (final entry in blocks.entries) {
    buffer
      ..writeln('source_file=${entry.key}')
      ..writeln('<hierarchy rotation="0">');
    for (final label in entry.value) {
      buffer.writeln('  <node text="$label" content-desc="$label"/>');
    }
    buffer.writeln('</hierarchy>');
  }
  return buffer.toString();
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
          groupReactionNotificationExpectedAndroidReactionBody(actorName),
          groupReactionNotificationExpectedAndroidReactionBody(actorName),
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

Map<String, String> _plan398NativeObservationBindings() => <String, String>{
  'captureNonceSha256': _plan397FixtureDigest('plan398-capture-nonce'),
  'receiverDeviceIdSha256': _plan397FixtureDigest('plan398-receiver'),
  'expectedGroupIdSha256': _plan397FixtureDigest('plan398-group'),
  'expectedEventIdSha256': _plan397FixtureDigest('plan398-event'),
  'expectedTargetMessageIdSha256': _plan397FixtureDigest('plan398-target'),
  'expectedCollapseIdentifierSha256': _plan397FixtureDigest('plan398-collapse'),
};

Map<String, Object?> _plan398NativeObservationReceipt({
  required String status,
}) {
  final bindings = _plan398NativeObservationBindings();
  final canonical = bindings['expectedCollapseIdentifierSha256']!;
  final sibling = _plan397FixtureDigest('plan398-sibling-request');
  final dispatchCorrelation = _plan397FixtureDigest(
    'plan398-dispatch-correlation-raw',
  );
  final providerMessageId = _plan397FixtureDigest(
    'plan398-provider-message-id-raw',
  );
  final pass = status == 'PASS';
  final records =
      <Map<String, Object?>>[
        <String, Object?>{
          'requestIdentifierSha256': canonical,
          'dispatchCorrelationSha256': dispatchCorrelation,
          'claimedCollapseIdentifierSha256':
              bindings['expectedCollapseIdentifierSha256'],
          'providerMessageIdSha256': providerMessageId,
          'triggerOrigin': 'remote',
          'sourceClass': 'usefulProviderRich',
          'reason': 'exactUseful',
          'expectedCollapseIdentifierMatch': true,
          'dispatchClaim': 'groupInbox',
        },
        if (!pass)
          <String, Object?>{
            'requestIdentifierSha256': sibling,
            'dispatchCorrelationSha256': null,
            'claimedCollapseIdentifierSha256': null,
            'providerMessageIdSha256': null,
            'triggerOrigin': 'remote',
            'sourceClass': 'unknown',
            'reason': 'unclassifiedRemote',
            'expectedCollapseIdentifierMatch': false,
            'dispatchClaim': 'absent',
          },
      ]..sort(
        (left, right) => (left['requestIdentifierSha256']! as String).compareTo(
          right['requestIdentifierSha256']! as String,
        ),
      );
  final identifiers = records
      .map((record) => record['requestIdentifierSha256']! as String)
      .toList(growable: false);
  return <String, Object?>{
    'schema': 'mknoon.sims.ios-group-notification-observation-host-receipt.v3',
    'action': 'observe-group',
    'phase': 'message',
    'status': status,
    'containsSecrets': false,
    'bundleId': 'com.mknoon.app',
    ...bindings,
    'matchingRemoteCount': pass ? 1 : 2,
    'matchingLocalCount': 0,
    'matchingUsefulProviderCount': 1,
    'matchingSanitizedProviderCount': 0,
    'matchingFlutterLocalCount': 0,
    'matchingUnknownCount': pass ? 0 : 1,
    'matchingTotalCount': pass ? 1 : 2,
    'stableSampleCount': 3,
    'stableSampleIntervalMilliseconds': 500,
    'observationDeadlineMilliseconds': 8000,
    'sampledThroughDeadline': true,
    'badSourceSeen': !pass,
    'duplicateSeen': !pass,
    'requestIdentifierSha256': identifiers,
    'diagnosticSchema': 'mknoon.sims.ios-group-notification-diagnostics.v2',
    'diagnosticRecords': records,
    'diagnosticRecordCount': records.length,
    'diagnosticOverflow': false,
    'diagnosticConflict': false,
    'diagnosticComplete': true,
    'childBuildCount': 0,
    'manualActionCount': 0,
    'runnerTerminated': true,
    'preTapCleanupLaunchCount': 0,
    'resultCode': pass ? 'ok' : 'bad_source_seen',
    'completedAt': '2026-08-23T12:00:00.000Z',
  };
}

Future<File> _writePlan398DiagnosticArtifactFixture(
  Directory root, {
  required File deploymentReceipt,
  required File attemptMarker,
}) async {
  const senderId = '21071FDF600CSC';
  const recipientId = '00008150-001C3C6A3684401C';
  final bindings = _plan398NativeObservationBindings();
  final observerNonce = _plan397FixtureDigest('plan398-observer-nonce');
  final native = _plan398NativeObservationReceipt(status: 'FAIL')
    ..['captureNonceSha256'] = observerNonce
    ..['receiverDeviceIdSha256'] = _plan397FixtureDigest(recipientId);
  final provider = <String, Object?>{
    'metricFamily': relayGroupMessageDispatchCounter,
    'relayGroupMessageDispatchSource': 'groupInbox',
    'groupInboxAcceptedDelta': 1,
    'groupInboxFailedDelta': 0,
    'groupContentAcceptedDelta': 0,
    'groupContentFailedDelta': 0,
    'providerSingleFirstAttempt': true,
    'acceptedDispatchCorrelationSha256': _plan397FixtureDigest(
      'plan398-dispatch-correlation-raw',
    ),
    'acceptedProviderMessageIdSha256': _plan397FixtureDigest(
      'plan398-provider-message-id-raw',
    ),
    'baselineSha256': _plan397FixtureDigest('plan398-metrics-before'),
    'finalSha256': _plan397FixtureDigest('plan398-metrics-after'),
    'deletedOrUnattributedEvidence': false,
  };
  final artifact = File(
    '${root.path}${Platform.pathSeparator}'
    '$iosChatGroupMessageAndReactionScenarioId.json',
  );
  await artifact.writeAsString(
    jsonEncode(<String, Object?>{
      'schema': 'mknoon.plan398.ios-group-message-diagnostic.v2',
      'version': 2,
      'scenario': iosChatGroupMessageAndReactionScenarioId,
      'testCase': 'TC-397-07/08',
      'status': 'diagnostic_complete',
      'generatedBy': 'automated_capture_pipeline',
      'diagnosticOnlyMessageWindow': true,
      'closurePassed': false,
      'disposition': 'claim_absent_or_noncandidate',
      'stagingDeploymentReceiptSha256': sha256
          .convert(await deploymentReceipt.readAsBytes())
          .toString(),
      'singleOwnerDeclared': true,
      'diagnosticAttemptClaimed': true,
      'diagnosticAttemptClaimSha256': sha256
          .convert(await attemptMarker.readAsBytes())
          .toString(),
      'topology': <String, Object?>{
        'groupType': 'chat',
        'sender': <String, Object?>{
          'platform': 'android',
          'deviceKind': 'physical',
          'deviceId': senderId,
          'liveDiscovered': true,
        },
        'recipient': <String, Object?>{
          'platform': 'ios',
          'deviceKind': 'physical',
          'deviceId': recipientId,
          'liveDiscovered': true,
        },
      },
      'buildInputs': <String, Object?>{
        'androidProfileId': 'android.production_fcm',
        'androidInputDigest': _plan397FixtureDigest('plan398-android-input'),
        'androidArtifactDigest': _plan397FixtureDigest(
          'plan398-android-artifact',
        ),
        'iosProfileId': 'ios.device.production',
        'iosInputDigest': _plan397FixtureDigest('plan398-ios-input'),
        'iosArtifactDigest': _plan397FixtureDigest('plan398-ios-artifact'),
        'setupProfileId': 'ios.device.group_reaction_notification_397',
        'setupApplicationSha256': _plan397FixtureDigest('plan398-setup-app'),
        'setupPreparationCompileCommands': 1,
        'captureChildBuildCount': 0,
        'centralApplicationSha256': _plan397FixtureDigest(
          'plan398-central-app',
        ),
        'gradedWindowChildBuildCount': 0,
      },
      'window': <String, Object?>{
        'phase': 'message',
        'ordinal': 1,
        'payloadKind': 'group_message',
        'windowIdSha256': _plan397FixtureDigest('plan398-window'),
        'observerRunIdSha256': _plan397FixtureDigest('plan398-observer-run'),
        'observerNonceSha256': observerNonce,
        'androidObservation': <String, Object?>{
          'schema': 'mknoon.plan257.sqlcipher-observation.v1',
          'phase': 'message',
          'groupIdSha256': bindings['expectedGroupIdSha256'],
          'messageIdSha256': bindings['expectedEventIdSha256'],
          'targetMessageIdSha256': bindings['expectedTargetMessageIdSha256'],
          'eventIdSha256': bindings['expectedEventIdSha256'],
          'expectedCollapseIdentifierSha256':
              bindings['expectedCollapseIdentifierSha256'],
          'reactionIdSha256': null,
          'reactionTargetIdSha256': null,
          'firstIncoming': false,
          'targetIncoming': true,
          'targetRead': true,
          'reactionRows': 0,
          'reactionEmojiSha256': null,
          'rawIdentifiersPersisted': false,
        },
        'provider': provider,
        'nse': <String, Object?>{
          'payloadKind': 'group_message',
          'decryptOkCount': 1,
          'didReceiveCount': 1,
          'decryptFailureCount': 0,
          'timeoutCount': 0,
          'runOwnedLocalPublicationCount': 0,
          'contenderDisposition': 'not_observed',
          'contenderSuppressionCount': 0,
          'windowSha256': _plan397FixtureDigest('plan398-nse-window'),
          'rawPayloadPersisted': false,
        },
        'nativeInventory': native,
        'diagnostics': <String, Object?>{
          'runOwnedLocalPublicationCount': 0,
          'contenderDisposition': 'not_observed',
          'contenderSuppressionCount': 0,
          'rawIdentifiersPersisted': false,
          'rawPayloadPersisted': false,
        },
        'relayJournalSha256': _plan397FixtureDigest('plan398-relay-journal'),
        'relayJournalLineCount': 1,
        'openedAt': '2026-08-23T12:00:00.000Z',
        'closedAt': '2026-08-23T12:01:00.000Z',
      },
      'execution': <String, Object?>{
        'automation': 'fully_automated',
        'manualTaps': 0,
        'childBuildsDuringGradedWindows': 0,
        'messageSendCount': 1,
        'reactionAddCount': 0,
        'reactionRemoveCount': 0,
        'reactionReAddCount': 0,
        'notificationTapCount': 0,
      },
      'redaction': <String, Object?>{
        'pushTokensPersisted': false,
        'secretKeysPersisted': false,
        'ciphertextPersisted': false,
        'plaintextPayloadPersisted': false,
        'rawPeerIdsPersisted': false,
        'rawGroupOrMessageIdsPersisted': false,
      },
    }),
    flush: true,
  );
  return artifact;
}

Future<({File artifact, File traceAttemptMarker})>
_writePlan398ExistingStateTraceArtifactFixture(Directory root) async {
  const senderId = '21071FDF600CSC';
  const recipientId = '00008150-001C3C6A3684401C';
  final traceAttemptMarker = File(
    '${root.path}${Platform.pathSeparator}'
    'plan398_existing_state_trace_claim.json',
  );
  await traceAttemptMarker.writeAsString(
    jsonEncode(<String, Object?>{
      'schema': 'mknoon.plan398.existing-state-trace-claim.v1',
      'ownerRunId': 'existing-state-trace',
      'singleOwnerDeclared': true,
      'claimValue': 'tc398-10-existing-state-trace-claim',
    }),
    flush: true,
  );
  final chmod = await Process.run('chmod', <String>[
    '600',
    traceAttemptMarker.path,
  ]);
  if (chmod.exitCode != 0) {
    throw StateError('could not make the trace-attempt marker private');
  }

  final legacy = await _writePlan398DiagnosticArtifactFixture(
    root,
    deploymentReceipt: traceAttemptMarker,
    attemptMarker: traceAttemptMarker,
  );
  final legacyRoot = _readArtifact(legacy);
  final window = Map<String, dynamic>.from(legacyRoot['window'] as Map);
  final native = Map<String, Object?>.from(window['nativeInventory'] as Map);
  final provider = Map<String, Object?>.from(window['provider'] as Map);
  final disposition = plan398DiagnosticDisposition(native, provider);
  if (disposition == 'incomplete_evidence') {
    throw StateError('fixture did not retain a closed diagnostic disposition');
  }

  final bindings = _plan398NativeObservationBindings();
  final artifact = File(
    '${root.path}${Platform.pathSeparator}'
    'plan398_existing_state_trace.json',
  );
  await artifact.writeAsString(
    jsonEncode(<String, Object?>{
      'schema': plan398ExistingStateTraceArtifactSchema,
      'version': plan398ExistingStateTraceArtifactVersion,
      'status': 'trace_complete',
      'closurePassed': false,
      'disposition': disposition,
      'traceAttemptClaimed': true,
      'traceAttemptClaimSha256': sha256
          .convert(await traceAttemptMarker.readAsBytes())
          .toString(),
      'topology': <String, Object?>{
        'groupType': 'chat',
        'sender': <String, Object?>{
          'platform': 'android',
          'deviceKind': 'physical',
          'deviceIdSha256': _plan397FixtureDigest(senderId),
          'liveDiscovered': true,
        },
        'recipient': <String, Object?>{
          'platform': 'ios',
          'deviceKind': 'physical',
          'deviceIdSha256': _plan397FixtureDigest(recipientId),
          'liveDiscovered': true,
        },
      },
      'installedState': <String, Object?>{
        'schema': 'mknoon.plan398.existing-state-installed-state.v1',
        'groupType': 'chat',
        'matchingChatGroupCount': 1,
        'groupIdSha256': bindings['expectedGroupIdSha256'],
        'groupKeySha256': _plan397FixtureDigest('tc398-existing-group-key'),
        'targetMessageIdSha256': bindings['expectedTargetMessageIdSha256'],
        'senderIdentityReceiptSha256': _plan397FixtureDigest(
          'tc398-sender-identity-receipt',
        ),
        'recipientIdentityReceiptSha256': _plan397FixtureDigest(
          'tc398-recipient-identity-receipt',
        ),
        'notificationAuthorizationReady': true,
        'relayPushTokenReady': true,
        'rawIdentifiersPersisted': false,
        'rawKeyMaterialPersisted': false,
        'rawIdentityReceiptsPersisted': false,
        'rawPushTokensPersisted': false,
      },
      'window': window,
      'execution': <String, Object?>{
        'automation': 'fully_automated',
        'messageSendTapCount': 1,
        'reactionTapCount': 0,
        'notificationTapCount': 0,
        'buildCount': 0,
        'installCount': 0,
        'uninstallCount': 0,
        'appDataClearCount': 0,
        'groupCreateCount': 0,
      },
      'redaction': <String, Object?>{
        'rawGroupOrTargetIdsPersisted': false,
        'rawGroupKeysPersisted': false,
        'rawIdentityReceiptsPersisted': false,
        'rawPushTokensPersisted': false,
        'rawPayloadPersisted': false,
      },
    }),
    flush: true,
  );
  return (artifact: artifact, traceAttemptMarker: traceAttemptMarker);
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
