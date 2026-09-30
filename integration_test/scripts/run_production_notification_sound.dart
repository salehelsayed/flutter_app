import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../tool/sims/artifact_evidence.dart';
import '../../tool/sims/production_notification_sound_criteria.dart';
import '../support/production_android_journey.dart';
import '../support/production_journey_peer.dart';
import '../support/production_provider_delivery.dart';

const _scenario = 'production.notification_sound';
Map<String, Object?> _object(Object? value) =>
    Map<String, Object?>.from(value as Map);

Future<void> main(List<String> arguments) async {
  if (arguments.contains('--list-scenarios')) {
    stdout.writeln(_scenario);
    return;
  }
  Directory? output;
  SimsArtifactEvidence? evidence;
  var attempted = 0;
  try {
    final destination = Platform.environment['SIMS_PROOF_DIRECTORY'];
    if (destination == null || destination.isEmpty) {
      throw StateError('missing SIMS_PROOF_DIRECTORY');
    }
    output = await (await Directory(
      destination,
    ).absolute.create(recursive: true)).createTemp('attempt-');
    final proofDirectory = output;
    final journey = ProductionAndroidJourney.fromEnvironment(
      _scenario,
      proofDirectory,
    );
    final cases = <Map<String, Object?>>[];
    final diagnosticS16Only =
        Platform.environment['PRODUCTION_SOUND_DIAGNOSTIC_S16_ONLY'] == '1';
    final groups = <String, Map<String, Object?>>{};
    Map<String, Object?> sender = {};
    Map<String, Object?>? provider;
    final timer = Stopwatch()..start();
    try {
      await journey.prepare();
      sender = await journey.alice.command('identity');
      final receiver = await journey.bob.command('identity');
      for (final type in ['chat', 'announcement']) {
        final fixture = await journey.alice.command('prepare_group', {
          'peerId': receiver['peerId'],
          'groupType': type,
        });
        final group = _object(fixture['group']);
        await journey.bob.command('import_group', fixture);
        await journey.alice.command('mark_fixture_joined', {
          'groupId': group['id'],
          'peerId': receiver['peerId'],
          'username': receiver['username'],
        });
        groups[type] = group;
      }
      journey.alice = await journey.reopen(journey.alice);
      journey.bob = await journey.reopen(journey.bob);
      // Reopening may rotate the production FCM token during bootstrap.
      final providerToken = await journey.bob.claimProviderToken();
      for (final p in [journey.alice, journey.bob]) {
        for (final group in groups.values) {
          await p.command('adopt_prepared_group', {'groupId': group['id']});
        }
      }
      await Future<void>.delayed(const Duration(seconds: 5));
      Future<Map<String, Object?>> snapshot(ProductionJourneyPeer p) =>
          p.command('sound_snapshot', {
            'peerId': p.invocation.role == 'alice'
                ? receiver['peerId']
                : sender['peerId'],
            'groupIds': groups.values.map((g) => g['id']).toList(),
          });
      var labelIndex = 0;
      Future<void> open(
        ProductionJourneyPeer p,
        String lane,
        String label,
      ) async {
        await journey.flow(
          p,
          lane == 'direct'
              ? 'production_direct_open'
              : lane == 'announcement' && p.invocation.role == 'bob'
              ? 'production_group_open_readonly'
              : 'production_group_open',
          '${labelIndex++}-$label',
          {
            if (lane == 'direct')
              'PEER_ID':
                  (p.invocation.role == 'alice'
                          ? receiver['peerId']
                          : sender['peerId'])
                      as String,
            if (lane != 'direct') 'GROUP_ID': groups[lane]!['id']! as String,
          },
        );
      }

      Future<void> back(
        ProductionJourneyPeer p,
        String lane,
        String label,
      ) async => journey.flow(
        p,
        lane == 'announcement' && p.invocation.role == 'bob'
            ? 'production_conversation_back_readonly'
            : 'production_conversation_back',
        '${labelIndex++}-$label',
      );
      // Clear only this run's conversation cards through production navigation.
      // All later media cards are retained within their conversation lane.
      for (final lane in ['direct', 'chat', 'announcement']) {
        await open(journey.bob, lane, 'initial-open-$lane');
        await back(journey.bob, lane, 'initial-back-$lane');
      }
      String? senderLane;
      Future<void> senderIn(String lane) async {
        if (senderLane == lane) return;
        if (senderLane != null) {
          await back(journey.alice, senderLane!, 'sender-leave-$senderLane');
        }
        await open(journey.alice, lane, 'sender-open-$lane');
        senderLane = lane;
      }

      Future<List<String>> outgoingIds(List<String> texts) async =>
          waitForProductionObservation(
            'exact sender rows',
            const Duration(seconds: 30),
            () async {
              final rows = ((await snapshot(journey.alice))['messages'] as List)
                  .cast<Map>();
              final ids = <String>[];
              for (final text in texts) {
                final exact = rows
                    .where((m) => m['text'] == text && m['incoming'] == false)
                    .toList();
                if (exact.length != 1) return null;
                ids.add(exact.single['id'] as String);
              }
              return ids;
            },
          );
      Future<Map<String, Object?>> captureOs(
        String id,
        List<Map> calls, {
        List<int> prior = const [],
        ({String dump, int notificationId})? firstAudible,
        bool requireFirstAudible = false,
      }) async {
        if (requireFirstAudible && firstAudible == null) {
          throw StateError('$id first audible native card was not captured');
        }
        final late = await journey.bob.adb([
          'shell',
          'dumpsys',
          'notification',
          '--noredact',
        ]);
        final dump = firstAudible?.dump ?? '${late.stdout}';
        if (firstAudible != null &&
            calls.last['notificationId'] != firstAudible.notificationId) {
          throw StateError('$id first audible card ID changed');
        }
        final nativeBody = calls.isEmpty
            ? null
            : productionSoundNativeBody(
                dump,
                journey.bob.packageName,
                calls.last['notificationId'] as int,
              );
        final file = File('${proofDirectory.path}/$id-native.txt');
        await file.writeAsString(dump);
        await journey.runner.run('chmod', ['600', file.path]);
        if (firstAudible != null) {
          final lateFile = File('${proofDirectory.path}/$id-native-late.txt');
          await lateFile.writeAsString('${late.stdout}');
          await journey.runner.run('chmod', ['600', lateFile.path]);
        }
        if (id == 'S14_first' && nativeBody != productionSoundFirstText) {
          throw StateError(
            'S14 native first-card copy was not captured before the update',
          );
        }
        final verdict = File('${proofDirectory.path}/$id-native-input.json');
        await verdict.writeAsString(
          jsonEncode(
            productionSoundOriginalOsInput(calls, priorRecordIds: prior),
          ),
        );
        final osId = id == 'S15_control'
            ? 'S2'
            : id == 'S14_first'
            ? 'S1'
            : id;
        final result = await journey.runner.run('env', [
          'ANDROID_APP_PACKAGE=${journey.bob.packageName}',
          'dart',
          'run',
          'integration_test/scripts/run_notification_sound_smoke.dart',
          '--verify-os-capture',
          osId,
          file.path,
          verdict.path,
        ]);
        final receipt = <String, Object?>{
          'originalOracle':
              'integration_test/scripts/run_notification_sound_smoke.dart',
          'exitCode': result.exitCode,
          'stdout': '${result.stdout}',
          'stderr': '${result.stderr}',
          'captureSha256': sha256.convert(await file.readAsBytes()).toString(),
          if (firstAudible != null) ...{
            'firstAudibleCardObserved': true,
            'postSettlementCaptureSha256': sha256
                .convert(utf8.encode('${late.stdout}'))
                .toString(),
          },
          if (nativeBody != null)
            'bodySha256': sha256.convert(utf8.encode(nativeBody)).toString(),
        };
        await File(
          '${proofDirectory.path}/$id-native-receipt.json',
        ).writeAsString(jsonEncode(receipt));
        if (result.exitCode != 0) {
          throw StateError('$id original OS disposition rejected');
        }
        return receipt;
      }

      // Capture S14's first card on the device. Re-launching adb for each
      // sample missed a same-ID update that arrived 367 ms after the first
      // post; one bounded device-side loop removes those host round trips.
      Future<({String dump, int notificationId})?> firstAudibleCard(
        String caseId,
        String body,
      ) async {
        String quote(String value) => "'${value.replaceAll("'", "'\\''")}'";
        final remote =
            '/data/local/tmp/${journey.bob.invocation.nonce}-sound-first.txt';
        final script =
            'deadline=\$((\$(date +%s)+60)); '
            'while [ "\$(date +%s)" -lt "\$deadline" ]; do '
            'dumpsys notification --noredact > ${quote(remote)}; '
            'if grep -Fq ${quote('android.text=String ($body)')} ${quote(remote)}; '
            'then cat ${quote(remote)}; rm -f ${quote(remote)}; exit 0; fi; '
            'done; rm -f ${quote(remote)}; exit 1';
        final result = await journey.bob.adb([
          'shell',
          script,
        ], allowFailure: true);
        if (result.exitCode != 0) return null;
        final dump = '${result.stdout}';
        final diagnostic = File(
          '${proofDirectory.path}/$caseId-first-native-probe.txt',
        );
        await diagnostic.writeAsString(dump);
        await journey.runner.run('chmod', ['600', diagnostic.path]);
        final id = productionSoundFirstAudibleNativeId(
          dump,
          journey.bob.packageName,
          body,
        );
        return id == null ? null : (dump: dump, notificationId: id);
      }

      Future<({Map<String, Object?> os, Map<String, Object?> native})>
      captureS16Background({
        required ({String dump, int notificationId}) firstCard,
        required String marker,
        required String title,
        required String body,
      }) async {
        String lastLog = '';
        Map<String, Object?> background;
        try {
          background = await waitForProductionObservation(
            'S16 native publication and duplicate reconciliation',
            const Duration(seconds: 30),
            () async {
              final result = await journey.bob.adb([
                'logcat',
                '-d',
                '-v',
                'time',
                '-s',
                'Wave2Sound:I',
                'flutter:I',
              ]);
              lastLog = '${result.stdout}';
              final observed = productionSoundS16BackgroundEvidence(
                lastLog,
                marker,
              );
              return (observed['shownCount'] == 1 ||
                          observed['liveShownCount'] == 1) &&
                      observed['suppressedCount'] == 1
                  ? observed
                  : null;
            },
          );
        } finally {
          final logFile = File('${proofDirectory.path}/S16-background-log.txt');
          await logFile.writeAsString(lastLog);
          await journey.runner.run('chmod', ['600', logFile.path]);
        }
        final livePost =
            background['shownPath'] == 'live' &&
            background['shownCount'] == 0 &&
            background['liveShownCount'] == 1 &&
            background['liveShownDurable'] == true &&
            background['liveShownProducer'] == 'direct_message' &&
            background['liveShownDisposition'] == 'osPosted' &&
            background['liveShownSilent'] == false;
        final backgroundPost =
            (background['shownPath'] == 'legacy' ||
                background['shownPath'] == 'durable' &&
                    background['shownDurable'] == true &&
                    background['shownProducer'] == 'direct_message' &&
                    background['shownDisposition'] == 'osPosted') &&
            background['shownSilent'] == false;
        if (!(livePost || backgroundPost) ||
            background['suppressionReason'] !=
                'message_event_already_claimed') {
          throw StateError('S16 native post or duplicate disposition differs');
        }
        final late = await journey.bob.adb([
          'shell',
          'dumpsys',
          'notification',
          '--noredact',
        ]);
        final firstBody = productionSoundNativeBody(
          firstCard.dump,
          journey.bob.packageName,
          firstCard.notificationId,
        );
        final firstTitle = productionSoundNativeText(
          firstCard.dump,
          journey.bob.packageName,
          firstCard.notificationId,
          'title',
        );
        final settledBody = productionSoundNativeBody(
          '${late.stdout}',
          journey.bob.packageName,
          firstCard.notificationId,
        );
        final settledTitle = productionSoundNativeText(
          '${late.stdout}',
          journey.bob.packageName,
          firstCard.notificationId,
          'title',
        );
        if (firstBody != body ||
            settledBody != body ||
            firstTitle != title ||
            settledTitle != title) {
          throw StateError(
            'S16 native first/settled card identity or copy differs',
          );
        }
        final firstFile = File('${proofDirectory.path}/S16-native.txt');
        final lateFile = File('${proofDirectory.path}/S16-native-late.txt');
        final inputFile = File('${proofDirectory.path}/S16-native-input.json');
        await firstFile.writeAsString(firstCard.dump);
        await lateFile.writeAsString('${late.stdout}');
        await inputFile.writeAsString(
          jsonEncode(
            productionSoundOriginalOsInput([
              {'silent': background['shownSilent']},
            ]),
          ),
        );
        for (final file in [firstFile, lateFile, inputFile]) {
          await journey.runner.run('chmod', ['600', file.path]);
        }
        final result = await journey.runner.run('env', [
          'ANDROID_APP_PACKAGE=${journey.bob.packageName}',
          'dart',
          'run',
          'integration_test/scripts/run_notification_sound_smoke.dart',
          '--verify-os-capture',
          'S16',
          firstFile.path,
          inputFile.path,
        ]);
        final firstSha = sha256
            .convert(await firstFile.readAsBytes())
            .toString();
        final lateSha = sha256.convert(await lateFile.readAsBytes()).toString();
        final os = <String, Object?>{
          'originalOracle':
              'integration_test/scripts/run_notification_sound_smoke.dart',
          'exitCode': result.exitCode,
          'stdout': '${result.stdout}',
          'stderr': '${result.stderr}',
          'captureSha256': firstSha,
          'firstAudibleCardObserved': true,
          'bodySha256': sha256.convert(utf8.encode(body)).toString(),
        };
        await File(
          '${proofDirectory.path}/S16-native-receipt.json',
        ).writeAsString(jsonEncode(os));
        if (result.exitCode != 0) {
          throw StateError('S16 original OS disposition rejected');
        }
        return (
          os: os,
          native: {
            ...background,
            'firstAudibleCardObserved': true,
            'nativeId': firstCard.notificationId,
            'firstBodySha256': sha256
                .convert(utf8.encode(firstBody!))
                .toString(),
            'settledBodySha256': sha256
                .convert(utf8.encode(settledBody!))
                .toString(),
            'firstTitleSha256': sha256
                .convert(utf8.encode(firstTitle!))
                .toString(),
            'settledTitleSha256': sha256
                .convert(utf8.encode(settledTitle!))
                .toString(),
            'firstCaptureSha256': firstSha,
            'settledCaptureSha256': lateSha,
            'logSha256': sha256.convert(utf8.encode(lastLog)).toString(),
          },
        );
      }

      final scenarioIds = diagnosticS16Only
          ? <String>['S16']
          : <String>[
              for (var i = 1; i <= 16; i++) ...[
                'S$i',
                if (i == 15) 'S15_control',
              ],
            ];
      if (diagnosticS16Only) {
        await File('${proofDirectory.path}/diagnostic-mode.json').writeAsString(
          jsonEncode({'mode': 'S16-only', 'cannotCertifyCampaign': true}),
        );
      }
      for (final id in scenarioIds) {
        attempted++;
        final lane = productionSoundLane(id);
        final number = int.tryParse(id.substring(1));
        final media = number != null && number >= 5 && number <= 13;
        final suppressed = id == 'S4' || id == 'S15';
        if (!media) await senderIn(lane);
        if (suppressed) await open(journey.bob, lane, '$id-viewing');
        // The original S16 cooldown precedes its paused lifecycle. Waiting
        // after Home can let the live bridge lapse before the sender acts.
        if (id == 'S16') {
          await Future<void>.delayed(const Duration(seconds: 11));
        }
        bool? receiverOnlineAfterPause;
        if (id == 'S16') {
          await journey.flow(
            journey.bob,
            'production_background',
            '$id-background',
          );
          await waitForProductionObservation(
            'real paused lifecycle',
            const Duration(seconds: 5),
            () async => (await snapshot(journey.bob))['lifecycle'] == 'paused'
                ? true
                : null,
          );
          receiverOnlineAfterPause =
              (await journey.bob.command('identity'))['online'] == true;
        }
        // Ensure an audible first tone where the original asserts one. This
        // establishes the precondition; it does not extend any scenario bound.
        if (['S14', 'S15_control'].contains(id)) {
          await Future<void>.delayed(const Duration(seconds: 11));
        }
        final before = await snapshot(journey.bob);
        final baseline = (before['notifications'] as List).length;
        final requiresFirstAudible = id == 'S14';
        final firstBody = id == 'S14'
            ? productionSoundFirstText
            : lane == 'direct'
            ? productionSoundText[id]
            : '${sender['username']}: ${productionSoundText[id]}';
        final marker = id == 'S16'
            ? 'S16-start-${journey.bob.invocation.nonce}'
            : null;
        if (marker != null) {
          await journey.bob.adb([
            'shell',
            'log',
            '-p',
            'i',
            '-t',
            'Wave2Sound',
            marker,
          ]);
        }
        final firstAudible = (requiresFirstAudible || id == 'S16')
            ? firstAudibleCard(id, firstBody!)
            : null;
        final receiverOnline = id == 'S16'
            ? (await journey.bob.command('identity'))['online'] == true
            : null;
        Map<String, Object?>? first;
        Map<String, Object?>? firstOsReceipt;
        Map<String, Object?>? caseProvider;
        List<String> messageIds;
        if (media) {
          if (lane == 'announcement') {
            await waitForProductionObservation(
              'announcement group recovery ready',
              const Duration(seconds: 60),
              () async =>
                  (await snapshot(journey.alice))['groupRecoveryActive'] ==
                      false
                  ? true
                  : null,
            );
          }
          final result = await journey.alice.command('send_sound_descriptor', {
            'caseId': id,
            if (lane == 'direct') 'peerId': receiver['peerId'],
            if (lane != 'direct') 'groupId': groups[lane]!['id'],
          });
          if (!{
            'success',
            'successNoPeers',
            'queuedOffline',
          }.contains(result['outcome'])) {
            throw StateError(
              '$id production descriptor send failed: ${result['outcome']}',
            );
          }
          messageIds = [result['messageId'] as String];
        } else if (id == 'S14') {
          Object? flowError;
          final flow = journey
              .flow(
                journey.alice,
                'production_sound_two_messages',
                '$id-send',
                {
                  'FIRST_MESSAGE': productionSoundFirstText,
                  'FIRST_MESSAGE_PATTERN': RegExp.escape(
                    productionSoundFirstText,
                  ),
                  'SECOND_MESSAGE': productionSoundText[id]!,
                  'SECOND_MESSAGE_PATTERN': RegExp.escape(
                    productionSoundText[id]!,
                  ),
                },
              )
              .then<void>(
                (_) {},
                onError: (Object e) {
                  flowError = e;
                },
              );
          try {
            first = await waitForProductionObservation(
              'S14 first audible publication',
              const Duration(seconds: 60),
              () async {
                if (flowError != null) throw StateError('S14 UI flow failed');
                final current = await snapshot(journey.bob);
                final count = (current['notifications'] as List).length;
                if (count > baseline + 1) {
                  throw StateError('S14 first card capture was missed');
                }
                return count == baseline + 1 ? current : null;
              },
            );
            // Start capture immediately, without waiting for another Dart VM to
            // compile the original pure oracle while the UI sends message two.
            Object? captureError;
            final firstCapture =
                captureOs(
                  'S14_first',
                  (first!['notifications'] as List)
                      .cast<Map>()
                      .skip(baseline)
                      .toList(),
                  firstAudible: await firstAudible,
                  requireFirstAudible: true,
                ).then<void>(
                  (receipt) {
                    firstOsReceipt = receipt;
                  },
                  onError: (Object error) {
                    captureError = error;
                  },
                );
            await flow;
            await firstCapture;
            if (flowError != null) throw StateError('S14 UI flow failed');
            if (captureError != null) {
              throw StateError(
                'S14 first native capture failed: $captureError',
              );
            }
          } finally {
            await flow; // Never restore a device while our UI driver is active.
          }
          messageIds = await outgoingIds([
            productionSoundFirstText,
            productionSoundText[id]!,
          ]);
        } else if (id == 'S16') {
          final text = productionSoundText[id]!;
          if (receiverOnline != true) {
            throw StateError('S16 receiver bridge was offline before send');
          }
          try {
            final result = await journey.alice.command('send_sound_text', {
              'caseId': id,
              'peerId': receiver['peerId'],
              'text': text,
            });
            if (result['outcome'] != 'success') {
              throw StateError(
                'S16 connected send failed: ${result['outcome']}',
              );
            }
          } finally {
            await firstAudible;
          }
          messageIds = await outgoingIds([text]);
        } else {
          final text = productionSoundText[id]!;
          await journey.flow(
            journey.alice,
            'production_direct_send',
            '$id-send',
            {'MESSAGE': text, 'MESSAGE_PATTERN': RegExp.escape(text)},
          );
          messageIds = await outgoingIds([text]);
        }
        if (id == 'S16') {
          await waitForProductionObservation(
            'S16 exact receiver persistence before provider delivery',
            const Duration(seconds: 30),
            () async {
              final rows = ((await snapshot(journey.bob))['messages'] as List)
                  .cast<Map>();
              return rows
                          .where(
                            (row) =>
                                row['id'] == messageIds.single &&
                                row['incoming'] == true,
                          )
                          .length ==
                      1
                  ? true
                  : null;
            },
          );
          caseProvider = await proveProductionProviderDelivery(
            journey: journey,
            receiver: journey.bob,
            token: providerToken,
            caseId: id,
            data: {
              'type': 'new_message',
              'sender_id': sender['peerId']!,
              'message_id': messageIds.single,
              'title': sender['username']!,
              'body': productionSoundText[id]!,
            },
          );
        }
        await waitForProductionObservation(
          'exact receiver persistence',
          const Duration(seconds: 60),
          () async {
            final current = await snapshot(journey.bob);
            final rows = (current['messages'] as List).cast<Map>();
            return messageIds.every(
                      (id) =>
                          rows
                              .where(
                                (m) => m['id'] == id && m['incoming'] == true,
                              )
                              .length ==
                          1,
                    ) &&
                    (suppressed ||
                        id == 'S16' ||
                        (current['notifications'] as List).length >=
                            baseline + messageIds.length)
                ? true
                : null;
          },
        );
        final settling = Stopwatch()..start();
        if (suppressed) await Future<void>.delayed(const Duration(seconds: 6));
        final after = await snapshot(journey.bob);
        final calls = (after['notifications'] as List)
            .cast<Map>()
            .skip(baseline)
            .toList();
        Map<String, Object?>? backgroundNative;
        final Map<String, Object?> os;
        if (id == 'S16') {
          final firstCard = await firstAudible;
          if (firstCard == null) {
            throw StateError('S16 first audible native card was not captured');
          }
          final captured = await captureS16Background(
            firstCard: firstCard,
            marker: marker!,
            title: sender['username'] as String,
            body: productionSoundText[id]!,
          );
          os = captured.os;
          backgroundNative = captured.native;
        } else {
          os = await captureOs(
            id,
            calls,
            firstAudible: id == 'S14' ? null : await firstAudible,
            requireFirstAudible: requiresFirstAudible && id != 'S14',
            prior: id == 'S14'
                ? [
                    ((first!['notifications'] as List).last
                            as Map)['notificationId']
                        as int,
                  ]
                : [],
          );
        }
        cases.add({
          'id': id,
          'messageIds': messageIds,
          'before': before,
          'after': after,
          'osReceipt': os,
          'first': ?first,
          'firstOsReceipt': ?firstOsReceipt,
          'provider': ?caseProvider,
          'backgroundNative': ?backgroundNative,
          if (suppressed) 'suppressionWindowMs': settling.elapsedMilliseconds,
          'receiverConnectedBeforeSend': ?receiverOnline,
          'receiverOnlineAfterPause': ?receiverOnlineAfterPause,
        });
        await File(
          '${proofDirectory.path}/scenario-observations.json',
        ).writeAsString(
          jsonEncode({
            'runId': journey.runId,
            'sender': sender,
            'groups': groups,
            'cases': cases,
          }),
        );
        if (suppressed) {
          await back(journey.bob, lane, '$id-stop-viewing');
        } else if ([
          'S1',
          'S2',
          'S3',
          'S7',
          'S10',
          'S13',
          'S14',
          'S15_control',
        ].contains(id)) {
          await open(journey.bob, lane, '$id-clear-own-card');
          await back(journey.bob, lane, '$id-return-home');
        }
      }
      final failures = validateProductionNotificationSound({
        'runId': journey.runId,
        'sender': sender,
        'groups': groups,
        'cases': cases,
      });
      await File(
        '${proofDirectory.path}/oracle.json',
      ).writeAsString(jsonEncode({'failures': failures}));
      if (failures.isNotEmpty) throw StateError(failures.join('; '));
      provider = _object(cases.last['provider']);
    } catch (error, stack) {
      await File(
        '${proofDirectory.path}/scenario-failure.txt',
      ).writeAsString('$error\n$stack');
      rethrow;
    } finally {
      await journey.restore();
    }
    evidence = writeSimsArtifactEvidenceSync(
      directory: output,
      capabilityId: _scenario,
      validatorIds: ['validateProductionNotificationSound'],
      payload: {
        ...journey.provenance(),
        'status': 'PASS',
        'cases': cases,
        'sender': sender,
        'groups': groups,
        'provider': provider,
        'elapsedMs': timer.elapsedMilliseconds,
        'audibleSpeakerConfirmation':
            'not established by automated programmatic and OS evidence',
      },
    );
  } catch (error, stack) {
    if (output != null) {
      await File(
        '${output.path}/first-failure.txt',
      ).writeAsString('$error\n$stack');
    }
  }
  final passed = evidence != null;
  stdout.writeln(
    'SIMS_RESULT_JSON=${jsonEncode({'status': passed ? 'PASS' : 'FAIL', 'assertionsAttempted': attempted, 'artifactPresent': passed, 'printOnly': false, 'exitCode': passed ? 0 : 1, 'detail': passed ? 'production sound scenarios and native disposition passed' : 'production sound journey failed', if (evidence != null) 'artifactEvidence': evidence.toJson()})}',
  );
  exitCode = passed ? 0 : 1;
}
