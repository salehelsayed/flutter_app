import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_app/core/debug/group_media_ios_disposable_profile.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/android_group_media_reliability_controller.dart';
import '../../integration_test/scripts/group_media_reliability_criteria.dart';
import '../../integration_test/scripts/group_media_reliability_runner_contract.dart';
import '../../integration_test/support/android_app_state_guard.dart';
import '../../integration_test/support/group_media_android_disposable_app.dart';

void main() {
  test(
    'P269 wait timeout reaches the existing runner with a closed phase',
    () async {
      final directory = await Directory.systemTemp.createTemp('p269-wait-');
      addTearDown(() => directory.delete(recursive: true));
      final artifact = File('${directory.path}/app.apk')
        ..writeAsStringSync('fixture');
      final guard = File('${directory.path}/build-guard.log')
        ..writeAsStringSync('');
      for (final phase in [
        'sender_send',
        'receiver_barrier',
        'private-peer-/path-secret',
      ]) {
        var clock = DateTime.utc(2026);
        final delays = <Duration>[];
        final result = await runGroupMediaReliabilityRunner(
          arguments: const [
            '--scenario',
            groupMediaForegroundRetryAclRoundtripScenario,
            '-d',
            'pixel-usb,emulator-5554',
          ],
          environment: {
            groupMediaReliabilityAndroidArtifactEnvironment: artifact.path,
            'SIMS_ARTIFACT_PROFILE_ID':
                groupMediaReliabilityAndroidBuildProfile,
            'SIMS_PROOF_DIRECTORY': '${directory.path}/proof',
            'SIMS_BUILD_GUARD_LOG': guard.path,
            'MKNOON_RELAY_ADDRESSES': '/dns/relay.invalid/tcp/443/wss',
          },
          executeScenario: (_) =>
              waitForAndroidGroupMediaValue<Map<String, Object?>>(
                phase,
                const Duration(milliseconds: 400),
                () async => null,
                now: () => clock,
                pause: (duration) async {
                  delays.add(duration);
                  clock = clock.add(duration);
                },
              ),
        );
        final closed = phase.startsWith('private') ? 'unknown' : phase;
        expect(result.json['status'], 'FAIL');
        expect(
          result.json['detail'],
          'Group media scenario failed at group_wait_${closed}_timeout.',
        );
        expect(jsonEncode(result.json), isNot(contains('private-peer')));
        expect(delays, [
          const Duration(milliseconds: 200),
          const Duration(milliseconds: 200),
        ]);
      }
    },
  );

  test(
    'P269 wait timeout observes before failure without changing read behavior',
    () async {
      var clock = DateTime.utc(2026);
      var observed = false;
      await expectLater(
        waitForAndroidGroupMediaValue<int>(
          'sender_send',
          const Duration(milliseconds: 200),
          () async => null,
          now: () => clock,
          pause: (duration) async {
            clock = clock.add(duration);
          },
          onTimeout: () async {
            observed = true;
            throw StateError('private observer error');
          },
        ),
        throwsA(
          isA<GroupMediaReliabilityScenarioFailure>().having(
            (e) => e.code,
            'code',
            'group_wait_sender_send_timeout',
          ),
        ),
      );
      expect(observed, isTrue);
      clock = DateTime.utc(2026);
      final result = await waitForAndroidGroupMediaValue<int>(
        'sender_send',
        const Duration(milliseconds: 200),
        () async {
          clock = clock.add(const Duration(seconds: 1));
          return 7;
        },
        now: () => clock,
        onTimeout: () async {
          fail('successful read must retain old behavior');
        },
      );
      expect(result, 7);
      final failure = StateError('same read failure');
      await expectLater(
        waitForAndroidGroupMediaValue<int>(
          'sender_send',
          const Duration(seconds: 1),
          () async => throw failure,
        ),
        throwsA(same(failure)),
      );
    },
  );

  test(
    'P269 wait timeout snapshot retains closed observations before cleanup',
    () async {
      final root = await Directory.systemTemp.createTemp('p269-wait-receipt-');
      addTearDown(() => root.delete(recursive: true));
      var clock = DateTime.utc(2026);
      var cleanupStarted = false;
      try {
        await waitForAndroidGroupMediaValue<int>(
          'receiver_barrier',
          const Duration(milliseconds: 200),
          () async => null,
          now: () => clock,
          pause: (duration) async {
            clock = clock.add(duration);
          },
          onTimeout: () async {
            expect(cleanupStarted, isFalse);
            await retainAndroidGroupMediaWaitTimeout(
              directory: root,
              phase: 'receiver_barrier',
              senderSendCompleted: true,
              observation: {
                'matchedBarrierState': true,
                'barrierName':
                    'receiver_jpeg_strict_verified_ciphertext_pre_commit',
                'barrierReached': false,
                'barrierAttempt': 0,
                'barrierPriorStatus': 'pending',
                'recoveryReleased': false,
                'jpegAttempts': 0,
                'mp4Attempts': 1,
                'voiceAttempts': 1,
                'groupId': 'secret-group',
                'processId': 999,
                'rawError': 'secret message /private/file',
              },
            );
          },
        );
        fail('timeout must fail');
      } on GroupMediaReliabilityScenarioFailure catch (error) {
        expect(error.code, 'group_wait_receiver_barrier_timeout');
        expect(root.listSync().whereType<File>(), hasLength(1));
      } finally {
        cleanupStarted = true;
      }
      final file = root.listSync().whereType<File>().single;
      final raw = await file.readAsString();
      final receipt = jsonDecode(raw) as Map;
      expect(
        file.path,
        endsWith('wait-timeout-${sha256.convert(utf8.encode(raw))}.json'),
      );
      expect(receipt['senderSendCompleted'], isTrue);
      expect(receipt['waitStage'], 'receiver_barrier');
      expect(receipt['cause'], 'timeout');
      expect(receipt['mp4Attempts'], 1);
      expect(receipt['jpegAttempts'], 0);
      expect(raw, isNot(contains('secret')));
      expect(receipt.containsKey('processId'), isFalse);
      await retainAndroidGroupMediaWaitTimeout(
        directory: Directory('${root.path}/invalid'),
        phase: 'private-path-peer',
        senderSendCompleted: false,
        observation: {
          'endpointStatus': 'secret status',
          'barrierName': 'secret name',
          'barrierPriorStatus': 'secret status',
          'jpegAttempts': -1,
          'mp4Attempts': 'secret count',
          'voiceAttempts': 100001,
          'barrierReached': 'true',
          'barrierAttempt': 1.5,
          'matchingEndpointObserved': 'true',
        },
      );
      final invalid =
          jsonDecode(
                await Directory(
                  '${root.path}/invalid',
                ).listSync().whereType<File>().single.readAsString(),
              )
              as Map;
      expect(invalid, {
        'schema': 'mknoon.group-media-wait-timeout.v1',
        'waitStage': 'unknown',
        'cause': 'timeout',
        'errorCode': 'group_wait_unknown_timeout',
        'senderSendCompleted': false,
      });
    },
  );

  test(
    'P269 strict upload controller retains only bound closed native failure',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'native-upload-receipt-',
      );
      addTearDown(() => root.delete(recursive: true));
      var index = 0;
      Future<Map> retain(Map<String, Object?> overrides) async {
        final directory = Directory('${root.path}/${index++}');
        await retainGroupMediaEndpointFailure(
          directory: directory,
          config: const {},
          safeErrorCode: 'sender_strict_preparation',
          result: {
            'senderStage': 'strict_preparation',
            'mediaKind': 'mp4',
            'preparationState': 'retained',
            'preparationHasDurableAuthority': true,
            'preparationUploadResponseOk': false,
            'preparationUploadErrorCode': 'MEDIA_CUSTODY_ADMISSION_DISABLED',
            'rawErrorMessage': 'secret',
            ...overrides,
          },
        );
        return jsonDecode(
              await directory
                  .listSync()
                  .whereType<File>()
                  .single
                  .readAsString(),
            )
            as Map;
      }

      final accepted = await retain({});
      expect(accepted['preparationUploadResponseOk'], isFalse);
      expect(
        accepted['preparationUploadErrorCode'],
        'MEDIA_CUSTODY_ADMISSION_DISABLED',
      );
      expect(jsonEncode(accepted), isNot(contains('secret')));
      for (final overrides in <Map<String, Object?>>[
        {'preparationUploadErrorCode': 'secret-code'},
        {'preparationUploadErrorCode': 'MEDIA_CUSTODY_FULL\nsecret'},
        {'preparationUploadErrorCode': 1},
        {'preparationUploadResponseOk': true},
      ]) {
        expect(
          (await retain(overrides)).containsKey('preparationUploadErrorCode'),
          isFalse,
        );
      }
      for (final overrides in <Map<String, Object?>>[
        {'senderStage': 'strict_publication'},
        {'preparationState': 'refused'},
        {'preparationHasDurableAuthority': false},
        {'preparationUploadResponseOk': 'false'},
        {'preparationUploadResponseOk': null},
      ]) {
        final result = await retain(overrides);
        expect(result.containsKey('preparationUploadResponseOk'), isFalse);
        expect(result.containsKey('preparationUploadErrorCode'), isFalse);
      }
    },
  );
  test('P269 strict sender publication preserves canonical SQL state', () {
    final artifact = _aggregateFixture();
    final row =
        ((_map(_map(artifact, 'role_databases'), 'sender')['rows']! as List)
                .first
            as Map);
    expect(row['status'], 'upload_pending');
    expect((row['strict_publication']! as Map)['status'], 'sent');
    expect(validateGroupMediaReliabilityArtifact(artifact).ok, isTrue);
    final downgraded = (jsonDecode(jsonEncode(artifact))! as Map)
        .cast<String, Object?>();
    for (final row
        in (_map(_map(downgraded, 'role_databases'), 'sender')['rows']! as List)
            .cast<Map>()) {
      row.remove('strict_publication');
      row['status'] = 'done';
    }
    expect(validateGroupMediaReliabilityArtifact(downgraded).ok, isFalse);
    for (final key in [
      'status',
      'inbox_stored',
      'is_incoming',
      'wire_envelope_present',
      'retry_payload_present',
      'message_id',
      'group_sha256',
      'sender_account_sha256',
      'attachment_content_sha256',
    ]) {
      expect(
        () => _aggregateFixture(
          mutate: (bundle) {
            for (final phase in ['senderSend', 'senderProbe']) {
              final rows =
                  _map(_map(bundle, phase), 'roleDatabase')['rows']! as List;
              final publication =
                  (rows.first as Map)['strict_publication']! as Map;
              publication[key] = switch (key) {
                'status' => 'pending',
                'inbox_stored' => false,
                'is_incoming' ||
                'wire_envelope_present' ||
                'retry_payload_present' => true,
                _ => 'wrong',
              };
            }
          },
        ),
        throwsFormatException,
        reason: key,
      );
    }
    expect(
      () => _aggregateFixture(
        mutate: (bundle) {
          for (final phase in ['senderSend', 'senderProbe']) {
            final rows =
                _map(_map(bundle, phase), 'roleDatabase')['rows']! as List;
            (rows.first as Map).remove('strict_publication');
          }
        },
      ),
      throwsFormatException,
    );
  });
  test('canonical authority must converge before current Android media', () {
    final accepted = _aggregateFixture();
    expect(accepted['strict_authority_setup'], isNotNull);
    final validation = validateGroupMediaReliabilityArtifact(accepted);
    expect(validation.ok, isTrue, reason: validation.detail);
    for (final mutate in <void Function(Map<String, Object?>)>[
      (b) => _map(b, 'receiverArm').remove('authorityBefore'),
      (b) => _map(b, 'receiverArm')['groupId'] = 'other-group',
      (b) => _map(b, 'senderSetup').remove('processId'),
      (b) => _map(b, 'senderRefresh')['processId'] = 777,
      (b) => _map(b, 'receiverReady')['processId'] = 777,
      (b) => _map(_map(b, 'receiverReady'), 'authorityAfter')['keyEpoch'] = 3,
      (b) =>
          _map(_map(b, 'receiverReady'), 'authorityAfter')['authoritySha256'] =
              '0' * 64,
      (b) =>
          _map(_map(b, 'receiverReady'), 'authorityAfter')['authorityEventAt'] =
              '2026-09-18T01:00:01Z',
      (b) => _map(
        _map(b, 'receiverReady'),
        'authorityAfter',
      )['recipientTransportSha256'] = <String>['0' * 64],
      (b) => _map(
        _map(b, 'receiverReady'),
        'authorityAfter',
      )['accountPeerIdSha256'] = '0' * 64,
      (b) => _map(
        _map(b, 'receiverReady'),
        'authorityAfter',
      )['memberRolesSha256'] = '0' * 64,
      (b) => _map(_map(b, 'receiverReady'), 'authorityAfter')['admission'] =
          'refuse',
      (b) => _map(
        _map(b, 'senderRefresh'),
        'authorityRefresh',
      )['deferredPeerCount'] = 1,
      (b) => _map(
        _map(b, 'senderRefresh'),
        'authorityRefresh',
      )['distributedDeviceCount'] = 0,
      (b) =>
          _map(_map(b, 'senderRefresh'), 'authorityRefresh')['previousEpoch'] =
              0,
      (b) => _map(
        _map(_map(b, 'senderRefresh'), 'authorityRefresh'),
        'after',
      )['keyEpoch'] = 4,
    ]) {
      expect(() => _aggregateFixture(mutate: mutate), throwsFormatException);
    }
    expect(() => _aggregateFixture(omitAuthority: true), throwsFormatException);
    // Export validation independently preserves the identity/epoch/role joins.
    for (final mutate in <void Function(Map<String, Object?>)>[
      (a) => _map(a, 'strict_authority_setup')['current_epoch'] = 9,
      (a) =>
          _map(a, 'strict_authority_setup')['authority_event_at'] = 'unknown',
      (a) => _map(
        _map(a, 'strict_authority_setup'),
        'receiver',
      )['account_sha256'] = '0' * 64,
      (a) => _map(
        _map(a, 'strict_authority_setup'),
        'receiver',
      )['after_roles_sha256'] = '0' * 64,
      (a) => _map(_map(a, 'strict_authority_setup'), 'sender')['admission'] =
          'refuse',
      (a) => _map(a, 'strict_authority_setup')['rawKey'] = 'forbidden',
    ]) {
      final changed = (jsonDecode(jsonEncode(accepted)) as Map)
          .cast<String, Object?>();
      mutate(changed);
      expect(validateGroupMediaReliabilityArtifact(changed).ok, isFalse);
    }
  });

  test(
    'authority comparison retains closed operands before rejecting an old receiver epoch',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'p269-authority-',
      );
      addTearDown(() => directory.delete(recursive: true));
      late Map<String, Object?> bundle;
      _aggregateFixture(mutate: (value) => bundle = value);
      final receiverReady = _map(bundle, 'receiverReady');
      final after = _map(receiverReady, 'authorityAfter');
      final originalEpoch = after['keyEpoch'];
      after['keyEpoch'] = 1;
      receiverReady['unretainedSecret'] = 'private-error-with-key-material';
      final pending = buildAndRetainAndroidGroupMediaAuthoritySetup(
        directory: directory,
        runId: 'authority-retention-run',
        senderSetup: _map(bundle, 'senderSetup'),
        receiverArm: _map(bundle, 'receiverArm'),
        senderRefresh: _map(bundle, 'senderRefresh'),
        receiverReady: receiverReady,
      );
      await expectLater(
        pending,
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            'Creator rotation and peer authority did not converge',
          ),
        ),
      );
      final file = directory.listSync().whereType<File>().single;
      expect(file.path, contains('authority-observations-'));
      final raw = await file.readAsString();
      final receipt = (jsonDecode(raw) as Map).cast<String, Object?>();
      expect(receipt['validation'], 'not_yet_compared');
      expect(_map(_map(receipt, 'senderRefresh'), 'before')['keyEpoch'], 1);
      expect(_map(_map(receipt, 'senderRefresh'), 'after')['keyEpoch'], 2);
      expect(
        _map(_map(receipt, 'receiverArm'), 'authorityBefore')['keyEpoch'],
        1,
      );
      expect(
        _map(_map(receipt, 'receiverReady'), 'authorityAfter')['keyEpoch'],
        1,
      );
      expect(_map(receipt, 'senderSetup')['processId'], 333);
      expect(_map(receipt, 'senderRefresh')['processId'], 333);
      expect(_map(receipt, 'receiverArm')['processId'], 111);
      expect(_map(receipt, 'receiverReady')['processId'], 111);
      for (final secret in [
        'private-error-with-key-material',
        'sender-account',
        'receiver-account',
        'sender-transport',
        'receiver-transport',
        'authority-retention-run',
      ]) {
        expect(raw, isNot(contains(secret)));
      }
      after['keyEpoch'] = originalEpoch;
      final expected = buildAndroidGroupMediaAuthoritySetup(
        runId: 'authority-retention-run',
        senderSetup: _map(bundle, 'senderSetup'),
        receiverArm: _map(bundle, 'receiverArm'),
        senderRefresh: _map(bundle, 'senderRefresh'),
        receiverReady: receiverReady,
      );
      final accepted = await buildAndRetainAndroidGroupMediaAuthoritySetup(
        directory: directory,
        runId: 'authority-retention-run',
        senderSetup: _map(bundle, 'senderSetup'),
        receiverArm: _map(bundle, 'receiverArm'),
        senderRefresh: _map(bundle, 'senderRefresh'),
        receiverReady: receiverReady,
      );
      expect(accepted, expected);
      expect(directory.listSync().whereType<File>(), hasLength(2));
      expect(await file.readAsString(), raw, reason: 'Keep the first failure.');
    },
  );

  test('current distinct Android requires exact strict custody joins', () {
    final accepted = _aggregateFixture();
    expect(accepted['strict_media_custody'], isNotNull);
    for (final mutate in <void Function(Map<String, Object?>)>[
      (b) => _map(b, 'senderSend').remove('strictMediaCustody'),
      (b) => _map(
        _map(_map(b, 'senderSend'), 'strictMediaCustody'),
        'jpeg',
      )['recipient_count'] = 2,
      (b) => _map(
        _map(_map(b, 'senderSend'), 'strictMediaCustody'),
        'jpeg',
      )['custody_fingerprint'] = '0' * 64,
      (b) => _map(
        _map(_map(b, 'senderSend'), 'strictMediaCustody'),
        'jpeg',
      )['ciphertext_size'] = 0,
      (b) => _map(
        _map(b, 'receiverRecovery'),
        'strictCustodyBoundary',
      )['local_ready'] = true,
      (b) => _map(
        _map(_map(b, 'barrierState'), 'barrier'),
        'strictCustodyBoundary',
      )['ack_source_present'] = true,
    ]) {
      expect(() => _aggregateFixture(mutate: mutate), throwsFormatException);
    }
  });

  test(
    'P269 strict preparation diagnostic survives reset retention without widening',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'group-preparation-failure-',
      );
      addTearDown(() => dir.delete(recursive: true));
      for (final (state, durable) in [
        ('retained', true),
        ('refused', false),
        ('refused', true),
        ('legacyUninitialized', false),
      ]) {
        final one = Directory('${dir.path}/$state-$durable');
        await retainGroupMediaEndpointFailure(
          directory: one,
          config: const {},
          safeErrorCode: 'sender_strict_preparation',
          result: {
            'senderStage': 'strict_preparation',
            'mediaKind': 'mp4',
            'preparationState': state,
            'preparationHasDurableAuthority': durable,
            'rawError': 'secret-native-detail',
          },
        );
        final raw = await one
            .listSync()
            .whereType<File>()
            .single
            .readAsString();
        final receipt = jsonDecode(raw);
        expect(receipt['preparationState'], state);
        expect(receipt['preparationHasDurableAuthority'], durable);
        expect(raw, isNot(contains('secret-native-detail')));
      }
      for (final (state, durable) in <(Object?, Object?)>[
        ('complete', true),
        ('retained', false),
        ('legacyUninitialized', true),
        ('secret-native-detail', false),
        ('refused', 'true'),
        ('refused', null),
      ]) {
        final one = Directory(
          '${dir.path}/invalid-${state.hashCode}-${durable.hashCode}',
        );
        await retainGroupMediaEndpointFailure(
          directory: one,
          config: const {},
          safeErrorCode: 'sender_strict_preparation',
          result: {
            'senderStage': 'strict_preparation',
            'preparationState': state,
            'preparationHasDurableAuthority': durable,
          },
        );
        final receipt = jsonDecode(
          await one.listSync().whereType<File>().single.readAsString(),
        );
        expect(receipt.containsKey('preparationState'), isFalse);
        expect(receipt.containsKey('preparationHasDurableAuthority'), isFalse);
      }
    },
  );

  test(
    'endpoint failure retention exports only closed fields before reset',
    () async {
      final dir = await Directory.systemTemp.createTemp('group-failure-');
      addTearDown(() => dir.delete(recursive: true));
      await retainGroupMediaEndpointFailure(
        directory: dir,
        config: const {},
        safeErrorCode: 'sender_strict_publication',
        result: const {
          'schema': 'fixture',
          'phase': 'sender_send',
          'runId': 'run',
          'nonce': 'nonce',
          'senderStage': 'strict_publication',
          'mediaKind': 'jpeg',
          'errorType': 'GroupMediaReliabilitySenderFailure',
          'rawSecret': 'never-export',
        },
      );
      final files = dir.listSync().whereType<File>().toList();
      expect(files, hasLength(1));
      final raw = await files.single.readAsString();
      expect(raw, isNot(contains('never-export')));
      expect(jsonDecode(raw)['senderStage'], 'strict_publication');
    },
  );

  for (final stage in ['roleDatabase', '/private/secret']) {
    test(
      'receiver recovery retention accepts only closed diagnostics: $stage',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'group-recovery-failure-',
        );
        addTearDown(() => dir.delete(recursive: true));
        await retainGroupMediaEndpointFailure(
          directory: dir,
          config: const {},
          safeErrorCode: 'receiver_jpeg_not_settled',
          result: {
            'phase': 'receiver_recover',
            'recoveryStage': stage,
            'firstUploadWork': 0,
            'firstDownloadWork': 1,
            'secondUploadWork': '/private/secret',
            'secondDownloadWork': -1,
            'downloadAttempts': {
              'jpeg': 2,
              'mp4': 1,
              'voice': 'secret',
              'secret': 4,
            },
            'rawSecret': 'secret',
          },
        );
        final raw = await dir
            .listSync()
            .whereType<File>()
            .single
            .readAsString();
        final receipt = jsonDecode(raw) as Map;
        expect(raw, isNot(contains('secret')));
        expect(receipt.containsKey('recoveryStage'), stage == 'roleDatabase');
        if (stage == 'roleDatabase') {
          expect(receipt['firstUploadWork'], 0);
          expect(receipt['firstDownloadWork'], 1);
          expect(receipt['downloadAttempts'], {'jpeg': 2, 'mp4': 1});
        }
        expect(receipt.containsKey('secondUploadWork'), isFalse);
        expect(receipt.containsKey('secondDownloadWork'), isFalse);
      },
    );
  }

  test(
    'P269 legacy receipt absence is compatible but declared null is refused',
    () {
      expect(_aggregateFixture(), isNotEmpty);
      for (final mode in <Object?>[null, 7, false, 'unknown']) {
        expect(
          () => _aggregateFixture(
            mutate: (b) => _map(b, 'senderSetup')['authorityMode'] = mode,
          ),
          throwsFormatException,
        );
      }
    },
  );

  test(
    'P269 ordinary-primary aggregation keeps all media and custody assertions',
    () {
      final accepted = _aggregateFixture(
        authorityMode: groupMediaAccountBoundAuthorityMode,
      );
      expect(accepted['authority_mode'], groupMediaAccountBoundAuthorityMode);
      expect(
        _map(accepted, 'account_vs_transport_discriminator'),
        <String, Object?>{'sender': false, 'receiver': false},
      );
      final validation = validateGroupMediaReliabilityArtifact(accepted);
      expect(validation.ok, isTrue, reason: validation.detail);
      for (final corrupt in <void Function(Map<String, Object?>)>[
        (b) => _map(b, 'senderSetup')['transportPeerId'] = 'other-transport',
        (b) => _map(b, 'senderSetup')['accountPeerId'] = 'receiver-account',
        (b) => _map(b, 'senderSend')['allowedPeers'] = <Object?>[
          'sender-account',
          'other-account',
        ],
        (b) => _map(b, 'receiverRecovery')['authorityMode'] =
            groupMediaDistinctAuthorityMode,
        (b) => _map(b, 'receiverRecovery').remove('authorityMode'),
        (b) => _map(b, 'receiverRecovery')['secondDownloadWork'] = 1,
        (b) => _map(_map(b, 'senderSend'), 'uploadsPerBlob')['voice'] = 0,
        (b) => _map(b, 'receiverRenderedKinds')['mp4'] = 0,
      ]) {
        expect(
          () => _aggregateFixture(
            authorityMode: groupMediaAccountBoundAuthorityMode,
            mutate: corrupt,
          ),
          throwsFormatException,
        );
      }
    },
  );

  test('Android role receipts require the exact current database schema', () {
    final accepted = _aggregateFixture();
    for (final role in <String>['sender', 'receiver']) {
      expect(
        _map(_map(accepted, 'role_databases'), role)['user_version'],
        currentIdentityDatabaseVersion,
      );
    }
    for (final version in <int>[104, currentIdentityDatabaseVersion + 1]) {
      for (final phase in <String, String>{
        'senderSetup': 'roleDatabaseIdentity',
        'receiverArm': 'roleDatabaseIdentity',
        'senderSend': 'roleDatabase',
        'receiverRecovery': 'roleDatabase',
        'senderProbe': 'roleDatabase',
      }.entries) {
        expect(
          () => _aggregateFixture(
            mutate: (bundle) {
              _map(_map(bundle, phase.key), phase.value)['user_version'] =
                  version;
            },
          ),
          throwsFormatException,
          reason: '${phase.key} schema $version',
        );
      }
    }
  });

  test(
    'P269 Android UI proof requires explicit awake and unlocked evidence',
    () {
      expect(
        androidGroupMediaTargetIsInteractive(
          powerDump: 'mWakefulness=Awake\nmInteractive=true',
          windowPolicyDump: 'mShowingLockscreen=false\nmInputRestricted=false',
        ),
        isTrue,
      );
      expect(
        androidGroupMediaTargetIsInteractive(
          powerDump: 'mWakefulness=Asleep\nmInteractive=false',
          windowPolicyDump: 'mShowingLockscreen=false',
        ),
        isFalse,
      );
      expect(
        androidGroupMediaTargetIsInteractive(
          powerDump: 'mWakefulness=Awake',
          windowPolicyDump: 'showing=true\nmInputRestricted=true',
        ),
        isFalse,
      );
      expect(
        androidGroupMediaTargetIsInteractive(
          powerDump: 'mWakefulness=Awake',
          windowPolicyDump: 'no keyguard facts',
        ),
        isFalse,
      );
    },
  );

  test(
    'P269 target preflight rejects a wireless sender before any mutation',
    () async {
      await _expectAndroidTargetPreflightBlocked(
        inventory: _androidInventory(
          senderRows: const <String>[
            'pixel-usb device product:pixel transport_id:1',
          ],
        ),
      );
    },
  );

  test(
    'P269 target preflight rejects a sender reporting qemu one before any mutation',
    () async {
      await _expectAndroidTargetPreflightBlocked(senderQemu: '1');
    },
  );

  test(
    'P269 target preflight rejects a noncanonical sender qemu value before any mutation',
    () async {
      await _expectAndroidTargetPreflightBlocked(senderQemu: 'false');
    },
  );

  test(
    'P269 target preflight rejects duplicate rows for either role before any mutation',
    () async {
      for (final inventory in <String>[
        _androidInventory(
          senderRows: const <String>[
            'pixel-usb device usb:1-1 product:pixel transport_id:1',
            'pixel-usb device usb:1-1 product:pixel transport_id:1',
          ],
        ),
        _androidInventory(
          receiverRows: const <String>[
            'emulator-5554 device product:sdk_gphone64_x86_64 transport_id:2',
            'emulator-5554 device product:sdk_gphone64_x86_64 transport_id:2',
          ],
        ),
      ]) {
        await _expectAndroidTargetPreflightBlocked(inventory: inventory);
      }
    },
  );

  test(
    'P269 dedicated APK rejects wrong manifest before any ADB mutation',
    () async {
      final fixture = _AndroidDisposableFixture(
        manifestApplicationId: 'com.mknoon.app',
      );
      addTearDown(fixture.dispose);

      await expectLater(
        fixture.app.installPreparedArtifact(),
        throwsA(isA<GroupMediaAndroidDisposableFailure>()),
      );

      expect(fixture.runner.adbCommands, isEmpty);
      expect(fixture.mutationCount, 0);
    },
  );

  test(
    'P269 dedicated APK install and reset leave app installed without destructive commands',
    () async {
      final fixture = _AndroidDisposableFixture();
      addTearDown(fixture.dispose);

      await fixture.app.installPreparedArtifact();
      final pre = await fixture.app.reset('pre');
      final preRawStdout = fixture.runner.receiptStdout['pre']!;
      final repeatedPre = await fixture.app.reset('pre');
      final post = await fixture.app.reset('post');

      expect(pre.phase, 'pre');
      expect(post.phase, 'post');
      expect(pre.sha256Digest, isNot(post.sha256Digest));
      expect(repeatedPre.sha256Digest, isNot(pre.sha256Digest));
      expect(
        pre.sha256Digest,
        sha256.convert(utf8.encode(preRawStdout)).toString(),
      );
      expect(
        post.sha256Digest,
        sha256
            .convert(utf8.encode(fixture.runner.receiptStdout['post']!))
            .toString(),
      );
      expect(fixture.mutationCount, 1);
      final journal = fixture.runner.adbCommands.join('\n');
      expect(journal, contains('install -r -d -t'));
      expect(
        journal,
        contains('shell pm path $groupMediaAndroidDisposablePackageId'),
      );
      expect(journal, isNot(contains('com.mknoon.app')));
      expect(journal, isNot(contains('uninstall')));
      expect(journal, isNot(contains('pm clear')));
      expect(journal, isNot(matches(RegExp(r'\brm\s+-(?:rf|fr|r|R)\b'))));
    },
  );

  test(
    'P269 dedicated APK rejects installed mismatch and stale receipt',
    () async {
      final mismatch = _AndroidDisposableFixture(installedDigestMatches: false);
      addTearDown(mismatch.dispose);
      await expectLater(
        mismatch.app.installPreparedArtifact(),
        throwsA(isA<GroupMediaAndroidDisposableFailure>()),
      );

      final stale = _AndroidDisposableFixture(staleReceipt: true);
      addTearDown(stale.dispose);
      await stale.app.installPreparedArtifact();
      await expectLater(
        stale.app.reset('pre'),
        throwsA(isA<GroupMediaAndroidDisposableFailure>()),
      );
    },
  );

  test(
    'P269 host proves old PID death and launcher-only fresh PID without sleeps or identity clearing',
    () async {
      final runner = _ProcessRunner();
      final controller = AndroidGroupMediaProcessDeathController(
        runner: runner,
        pollInterval: Duration.zero,
        maximumPolls: 4,
      );

      final evidence = await controller.forceStopAndRelaunch(
        deviceId: 'emulator-5554',
        packageName: groupMediaAndroidDisposablePackageId,
      );

      expect(evidence.oldPid, '111');
      expect(evidence.freshPid, '222');
      expect(evidence.oldPidGone, isTrue);
      expect(
        evidence.launcherComponent,
        '$groupMediaAndroidDisposablePackageId/.MainActivity',
      );
      expect(evidence.relaunchedWithoutGroupRoute, isTrue);
      expect(
        runner.commands,
        containsAllInOrder(<String>[
          'adb -s emulator-5554 shell cmd package resolve-activity --brief --user 0 $groupMediaAndroidDisposablePackageId',
          'adb -s emulator-5554 shell pidof $groupMediaAndroidDisposablePackageId',
          'adb -s emulator-5554 shell am force-stop $groupMediaAndroidDisposablePackageId',
          'adb -s emulator-5554 shell pidof $groupMediaAndroidDisposablePackageId',
          'adb -s emulator-5554 shell am start -W -n $groupMediaAndroidDisposablePackageId/.MainActivity',
          'adb -s emulator-5554 shell pidof $groupMediaAndroidDisposablePackageId',
        ]),
      );
      final journal = runner.commands.join('\n');
      expect(journal, isNot(contains('flutter build')));
      expect(journal, isNot(contains('flutter drive')));
      expect(journal, isNot(contains('uninstall')));
      expect(journal, isNot(contains('pm clear')));
      expect(journal, isNot(contains('sleep')));
      expect(journal, isNot(contains('/group/')));
    },
  );

  test(
    'P269 launcher timeout still requires the exact component and a fresh PID',
    () async {
      final runner = _ProcessRunner(launchStatus: 'timeout');
      final controller = AndroidGroupMediaProcessDeathController(
        runner: runner,
        pollInterval: Duration.zero,
        maximumPolls: 4,
      );

      final evidence = await controller.forceStopAndRelaunch(
        deviceId: 'emulator-5554',
        packageName: groupMediaAndroidDisposablePackageId,
      );

      expect(evidence.oldPid, '111');
      expect(evidence.freshPid, '222');
      expect(evidence.oldPidGone, isTrue);
      expect(evidence.relaunchedWithoutGroupRoute, isTrue);
    },
  );

  test(
    'P269 stopped-window recovery staging remains after PID death and before launcher relaunch',
    () async {
      final runner = _ProcessRunner(withStoppedWindowStage: true);
      final controller = AndroidGroupMediaProcessDeathController(
        runner: runner,
        pollInterval: Duration.zero,
        maximumPolls: 5,
      );

      await controller.forceStopAndRelaunch(
        deviceId: 'emulator-5554',
        packageName: groupMediaAndroidDisposablePackageId,
        afterStoppedBeforeLaunch: () async {
          runner.commands.add('HOST stage receiver_recover');
        },
      );

      expect(
        runner.commands,
        containsAllInOrder(<String>[
          'adb -s emulator-5554 shell am force-stop $groupMediaAndroidDisposablePackageId',
          'adb -s emulator-5554 shell pidof $groupMediaAndroidDisposablePackageId',
          'HOST stage receiver_recover',
          'adb -s emulator-5554 shell pidof $groupMediaAndroidDisposablePackageId',
          'adb -s emulator-5554 shell am start -W -n $groupMediaAndroidDisposablePackageId/.MainActivity',
        ]),
      );

      final source = File(
        'integration_test/scripts/android_group_media_reliability_controller.dart',
      ).readAsStringSync();
      final methodStart = source.indexOf(
        'Future<AndroidGroupMediaProcessTransitionEvidence> '
        'forceStopAndRelaunch',
      );
      final methodEnd = source.indexOf(
        'Future<String> launchValidatedLauncher',
        methodStart,
      );
      final method = source.substring(methodStart, methodEnd);
      final deathObserved = method.indexOf('final oldPidGone = await _pollPid');
      final stage = method.indexOf('await afterStoppedBeforeLaunch();');
      final stillStopped = method.indexOf(
        'final pidAfterStaging = await _readPid',
      );
      final launch = method.indexOf('await _launchResolvedComponent');
      expect(methodStart, greaterThanOrEqualTo(0));
      expect(methodEnd, greaterThan(methodStart));
      expect(deathObserved, greaterThanOrEqualTo(0));
      expect(stage, greaterThan(deathObserved));
      expect(stillStopped, greaterThan(stage));
      expect(launch, greaterThan(stillStopped));
    },
  );

  test(
    'P269 fixture publishes JPEG last and host settles sender before barrier observation',
    () {
      final fixtureSource = File(
        'lib/core/debug/group_media_reliability_e2e_main_actions.dart',
      ).readAsStringSync();
      final specsStart = fixtureSource.indexOf(
        'final allSpecs = <({String kind, String mime, String? asset})>[',
      );
      final specsEnd = fixtureSource.indexOf(
        'final specs = allSpecs',
        specsStart,
      );
      final specs = fixtureSource.substring(specsStart, specsEnd);
      final mp4 = specs.indexOf("kind: 'mp4'");
      final voice = specs.indexOf("kind: 'voice'");
      final jpeg = specs.indexOf("kind: 'jpeg'");
      expect(specsStart, greaterThanOrEqualTo(0));
      expect(specsEnd, greaterThan(specsStart));
      expect(mp4, greaterThanOrEqualTo(0));
      expect(voice, greaterThan(mp4));
      expect(jpeg, greaterThan(voice));
      expect(
        fixtureSource,
        contains(
          'GroupMediaReliabilityAuthorityMode.distinctAccountAndTransport',
        ),
      );
      final uploadSource = fixtureSource.substring(
        fixtureSource.indexOf(
          'Future<Map<String, Object?>> _sendGroupMediaReliabilityFixturesForKinds({',
        ),
      );
      expect(
        RegExp(
          r'groupMediaReliabilityAuthorityMatches\(',
        ).allMatches(uploadSource),
        hasLength(2),
        reason:
            'P269 must validate authority before and inside the upload leaf',
      );
      expect(
        RegExp(r'await _waitForLocalTransportPeerId\(p2pService\)').allMatches(
          fixtureSource.substring(
                0,
                fixtureSource.indexOf(
                  'Future<Map<String, Object?>> probeGroupMediaReliabilityAuthority({',
                ),
              ) +
              uploadSource,
        ),
        hasLength(2),
        reason:
            'sender setup and publication must both wait for bounded local '
            'transport readiness',
      );
      final rosterReady = fixtureSource.indexOf(
        'final members = await _waitForReceiverTransportRoster(',
      );
      final exactTopicReady = fixtureSource.indexOf(
        'await _ensureExactGroupTopicJoined(',
        rosterReady,
      );
      final lease = fixtureSource.indexOf(
        'mediaUploadInFlightTracker.tryClaimAll(',
      );
      final parentSave = fixtureSource.indexOf(
        'await groupMessageRepository.saveMessage(expectedParent);',
      );
      final productionLeaf = fixtureSource.indexOf(
        'await runForegroundGroupUploadLeaf(',
      );
      final publication = fixtureSource.indexOf(
        'final result = await sendGroupMessage(',
        productionLeaf,
      );
      expect(lease, greaterThan(specsEnd));
      expect(rosterReady, greaterThanOrEqualTo(0));
      expect(exactTopicReady, greaterThan(rosterReady));
      expect(lease, greaterThan(exactTopicReady));
      expect(
        fixtureSource,
        contains('await callGroupJoinWithConfig('),
        reason:
            'the exact target group must enter native topic/config/key state '
            'before any fixture upload or reliable publication',
      );
      expect(parentSave, greaterThan(lease));
      expect(productionLeaf, greaterThan(parentSave));
      expect(publication, greaterThan(productionLeaf));
      final publicationEnd = fixtureSource.indexOf(
        'if (result.\$2?.id != messageId',
        publication,
      );
      expect(publicationEnd, greaterThan(publication));
      expect(
        fixtureSource.substring(publication, publicationEnd),
        contains('timestamp: now,'),
        reason:
            'the pre-saved optimistic parent and canonical send must share '
            'one timestamp so message-id reuse is authorized',
      );
      expect(fixtureSource, contains("downloadStatus: 'upload_pending'"));
      expect(
        fixtureSource,
        contains('messageIds.values.toSet().length != fixtureKinds.length'),
      );
      expect(
        fixtureSource,
        contains('attachmentIds.values.toSet().length != fixtureKinds.length'),
      );
      expect(fixtureSource, contains('required String transportPeerId'));
      expect(
        fixtureSource,
        contains('groupMediaReliabilityDatabasePathFingerprint('),
      );
      expect(fixtureSource, contains('databasePath: database.path'));
      expect(
        fixtureSource,
        isNot(contains('sha256.convert(database.path.codeUnits)')),
      );

      final productionSource = File(
        'lib/app/bootstrap/production_application_bootstrap.dart',
      ).readAsStringSync();
      final compositionSource = File(
        'lib/debug/debug_e2e_composition_root.dart',
      ).readAsStringSync();
      expect(
        productionSource,
        contains('if (debugE2EComposition?.startsIntroPoller ?? false) {'),
      );
      expect(
        productionSource,
        contains('debugE2EComposition!.startIntroPollerAfterColdRecovery('),
      );
      expect(compositionSource, contains('transportPeerId: transportPeerId'));

      final productionLeafSource = File(
        'lib/features/groups/application/foreground_group_media_upload.dart',
      ).readAsStringSync();
      expect(productionLeafSource, contains('sameExactGroupRetryAttachment('));
      expect(
        productionLeafSource,
        contains('applyGroupUploadCompletionAuthority('),
      );
      expect(productionLeafSource, contains('completion.completeUploadRetry('));
      final conversationSource = File(
        'lib/features/groups/presentation/screens/group_conversation_wired.dart',
      ).readAsStringSync();
      expect(
        RegExp(
          r'_runForegroundGroupUploadLeaf\s*\(',
        ).allMatches(conversationSource),
        hasLength(3),
        reason:
            'the shared wrapper plus ordinary and voice callers must remain',
      );
      expect(
        conversationSource,
        contains('}) => runForegroundGroupUploadLeaf('),
      );

      final hostSource = File(
        'integration_test/scripts/android_group_media_reliability_controller.dart',
      ).readAsStringSync();
      final identityCalls = hostSource.indexOf(
        'final identities = await Future.wait',
      );
      final contactCall = hostSource.indexOf(
        'await _establishContacts(senderIdentity, receiverIdentity);',
      );
      final identityProbe = hostSource.indexOf("phase: 'identity_probe'");
      final bilateralContacts = hostSource.indexOf(
        'await Future.wait(<Future<Map<String, Object?>>>[',
      );
      final senderSetup = hostSource.indexOf("phase: 'sender_setup'");
      expect(identityCalls, greaterThanOrEqualTo(0));
      expect(contactCall, greaterThan(identityCalls));
      expect(senderSetup, greaterThan(contactCall));
      expect(identityProbe, greaterThanOrEqualTo(0));
      expect(bilateralContacts, greaterThanOrEqualTo(0));
      expect(
        hostSource,
        contains('receiverTransportPeerId: receiverIdentity.transportPeerId'),
      );
      expect(
        RegExp("'add_contacts': <Object\\?>\\[").allMatches(hostSource),
        hasLength(2),
      );
      expect(
        hostSource,
        isNot(contains('send_contact_requests_for_added_contacts')),
      );
      expect(hostSource, isNot(contains('contact_request_action')));
      final sendStart = hostSource.indexOf(
        'final senderSendFuture = _waitForGroupEndpoint(',
      );
      final recoveryStart = hostSource.indexOf(
        'final recoveryConfig = _groupPhaseConfig(',
        sendStart,
      );
      final sendAndBarrier = hostSource.substring(sendStart, recoveryStart);
      final senderSettled = sendAndBarrier.indexOf(
        'final senderSend = await senderSendFuture;',
      );
      final barrierObserved = sendAndBarrier.indexOf(
        'final barrier = await _waitForBarrierState(',
      );
      expect(sendStart, greaterThanOrEqualTo(0));
      expect(recoveryStart, greaterThan(sendStart));
      expect(senderSettled, greaterThanOrEqualTo(0));
      expect(barrierObserved, greaterThan(senderSettled));
    },
  );

  test(
    'P330 notification projection media fixture uses account-bound legacy authority',
    () {
      final source = File(
        'lib/debug/group_notification_projection_e2e_action.dart',
      ).readAsStringSync();
      final fixtureCall = source.indexOf(
        'await sendGroupMediaReliabilityFixtures(',
      );
      final fixtureCallEnd = source.indexOf('final media =', fixtureCall);

      expect(fixtureCall, greaterThanOrEqualTo(0));
      expect(fixtureCallEnd, greaterThan(fixtureCall));
      expect(
        source.substring(fixtureCall, fixtureCallEnd),
        contains(
          'authorityMode: '
          'GroupMediaReliabilityAuthorityMode.accountBoundLegacy,',
        ),
        reason:
            'Plan 330 reuses account IDs as transport authority for its '
            'legacy-compatible fixture topology',
      );
    },
  );

  test(
    'P269 render parser accepts only the three safe renderer labels and host orders route after recovery',
    () {
      expect(
        groupMediaRenderedKindsFromUiXml(
          '<node content-desc="P269 receiver JPEG decoded"/>'
          '<node content-desc="P269 receiver voice player ready, 0:02"/>',
        ),
        <String>{'jpeg', 'voice'},
      );
      expect(
        groupMediaRenderedKindsFromUiXml(
          '<node text="P269 receiver MP4 thumbnail decoded"/>',
        ),
        <String>{'mp4'},
      );
      expect(
        groupMediaRenderedKindsFromUiXml(
          '<node text="Media unavailable"/><node text="0:02"/>',
        ),
        isEmpty,
      );
      expect(
        androidGroupMediaRenderFailureCode(<String>{'jpeg'}),
        'android_receiver_render_missing_mp4_voice',
      );
      expect(
        androidGroupMediaRenderFailureCode(<String>{'jpeg', 'mp4', 'voice'}),
        'android_receiver_render_incomplete',
      );
      expect(
        androidGroupMediaPackageOwnsForeground(
          windowsDump:
              'mCurrentFocus=Window{abc u0 '
              'com.mknoon.sims.groupmedia269/com.mknoon.app.MainActivity}',
          packageName: 'com.mknoon.sims.groupmedia269',
        ),
        isTrue,
      );
      expect(
        androidGroupMediaPackageOwnsForeground(
          windowsDump:
              'mFocusedApp=ActivityRecord{abc u0 '
              'com.android.launcher/.Launcher}',
          packageName: 'com.mknoon.sims.groupmedia269',
        ),
        isFalse,
      );

      final source = File(
        'integration_test/scripts/android_group_media_reliability_controller.dart',
      ).readAsStringSync();
      final recovery = source.indexOf(
        'final receiverRecovery = await _waitForGroupEndpoint(',
      );
      final render = source.indexOf("phase: 'receiver_render_probe'", recovery);
      final uiProof = source.indexOf(
        'await _waitForReceiverRenderedKinds()',
        render,
      );
      final senderProbe = source.indexOf(
        'final senderProbeConfig = _groupPhaseConfig(',
        uiProof,
      );
      expect(recovery, greaterThanOrEqualTo(0));
      expect(render, greaterThan(recovery));
      expect(uiProof, greaterThan(render));
      expect(senderProbe, greaterThan(uiProof));
      expect(source, contains("'uiautomator',"));
      expect(
        source,
        contains("'dumpsys',\n        'window',\n        'displays'"),
      );
    },
  );

  test(
    'P269 Android aggregation rejects every process database retry and ACL false-green',
    () {
      final accepted = _aggregateFixture();
      expect(validateGroupMediaReliabilityArtifact(accepted).ok, isTrue);
      final acceptedPrepared = _map(accepted, 'prepared_artifact');
      final acceptedCleanup = _map(accepted, 'cleanup');
      expect(
        acceptedPrepared['application_id'],
        groupMediaAndroidDisposablePackageId,
      );
      expect(acceptedCleanup['artifact_sha256'], acceptedPrepared['sha256']);
      expect(acceptedCleanup['app_left_installed'], isTrue);
      expect(acceptedCleanup['production_package_commands'], 0);
      expect(acceptedCleanup['uninstall_commands'], 0);
      expect(acceptedCleanup['pm_clear_commands'], 0);
      expect(acceptedCleanup['broad_delete_commands'], 0);
      final acceptedDatabases = _map(accepted, 'role_databases');
      final acceptedSenderDb = _map(acceptedDatabases, 'sender');
      final acceptedReceiverDb = _map(acceptedDatabases, 'receiver');
      expect(
        acceptedSenderDb['database_path_sha256'],
        matches(RegExp(r'^[0-9a-f]{64}$')),
      );
      expect(
        acceptedReceiverDb['database_path_sha256'],
        matches(RegExp(r'^[0-9a-f]{64}$')),
      );
      expect(
        acceptedSenderDb['database_path_sha256'],
        isNot(acceptedReceiverDb['database_path_sha256']),
      );

      final mutations = <void Function(Map<String, Object?>)>[
        (bundle) => _map(bundle, 'receiverRecovery')['currentProcessId'] = 111,
        (bundle) =>
            _map(bundle, 'receiverRecovery')['priorStatus'] = 'downloading',
        (bundle) =>
            _map(_map(bundle, 'receiverRecovery'), 'downloadAttempts')['jpeg'] =
                1,
        (bundle) => _map(
          _map(bundle, 'senderProbe'),
          'roleDatabase',
        )['database_path_sha256'] = List<String>.filled(64, 'd').join(),
        (bundle) => _map(
          _map(bundle, 'senderProbe'),
          'roleDatabase',
        )['database_path_sha256'] = List<String>.filled(64, 'D').join(),
        (bundle) {
          final senderDigest = _map(
            _map(bundle, 'senderProbe'),
            'roleDatabase',
          )['database_path_sha256'];
          _map(
            _map(bundle, 'receiverArm'),
            'roleDatabaseIdentity',
          )['database_path_sha256'] = senderDigest;
          _map(
            _map(bundle, 'receiverRecovery'),
            'roleDatabase',
          )['database_path_sha256'] = senderDigest;
        },
        (bundle) => _map(bundle, 'receiverRecovery')['firstDownloadWork'] = 4,
        (bundle) => _map(bundle, 'receiverRecovery')['secondDownloadWork'] = 1,
        (bundle) =>
            (_map(bundle, 'senderSend')['allowedPeers']! as List).removeLast(),
        (bundle) => (_map(bundle, 'senderSend')['allowedPeers']! as List).add(
          'receiver-transport',
        ),
        (bundle) => _map(bundle, 'senderProbe')['processId'] = 333,
        (bundle) => _map(bundle, 'receiverRender')['renderProbeArmed'] = false,
        (bundle) => _map(bundle, 'receiverRenderedKinds')['voice'] = 0,
      ];
      for (final mutation in mutations) {
        expect(
          () => _aggregateFixture(mutate: mutation),
          throwsFormatException,
        );
      }
      expect(
        () => _aggregateFixture(
          mutateCleanup: (pre, post) => post['sender'] = pre['sender']!,
        ),
        throwsFormatException,
      );
      expect(
        () => _aggregateFixture(
          mutateCleanup: (pre, post) =>
              post['receiver'] = const GroupMediaAndroidDisposableResetReceipt(
                phase: 'post',
                processId: 0,
                sha256Digest:
                    '5555555555555555555555555555555555555555555555555555555555555555',
              ),
        ),
        throwsFormatException,
      );
      expect(
        () => _aggregateFixture(
          commandSafety: const AndroidGroupMediaCommandSafetyEvidence(
            productionPackageCommands: 0,
            uninstallCommands: 1,
            pmClearCommands: 0,
            broadDeleteCommands: 0,
          ),
        ),
        throwsFormatException,
      );
      expect(
        () => _aggregateFixture(appsLeftInstalled: false),
        throwsFormatException,
      );
    },
  );
}

const String _androidSenderTarget = 'pixel-usb';
const String _androidReceiverTarget = 'emulator-5554';

String _androidInventory({
  List<String> senderRows = const <String>[
    'pixel-usb device usb:1-1 product:pixel transport_id:1',
  ],
  List<String> receiverRows = const <String>[
    'emulator-5554 device product:sdk_gphone64_x86_64 transport_id:2',
  ],
}) => <String>[
  'List of devices attached',
  ...senderRows,
  ...receiverRows,
  '',
].join('\n');

Future<void> _expectAndroidTargetPreflightBlocked({
  String? inventory,
  String senderQemu = '0',
  String receiverQemu = '1',
}) async {
  final fixture = _AndroidTargetPreflightFixture(
    inventory: inventory ?? _androidInventory(),
    senderQemu: senderQemu,
    receiverQemu: receiverQemu,
  );
  try {
    Object? failure;
    try {
      await executeAndroidGroupMediaReliabilityScenario(
        fixture.context,
        runner: fixture.runner,
      );
    } on Object catch (error) {
      failure = error;
    }

    expect(
      fixture.runner.mutationCommands,
      isEmpty,
      reason: 'target custody must fail before app or device mutation',
    );
    expect(
      failure,
      isA<GroupMediaReliabilityBlocked>().having(
        (error) => error.blocker,
        'blocker',
        'targetUnavailable',
      ),
    );
  } finally {
    fixture.dispose();
  }
}

final class _AndroidTargetPreflightFixture {
  _AndroidTargetPreflightFixture({
    required String inventory,
    required String senderQemu,
    required String receiverQemu,
  }) {
    directory = Directory.systemTemp.createTempSync('p269-target-preflight-');
    artifact = File(
      '${directory.path}${Platform.pathSeparator}group-media-269.apk',
    )..writeAsBytesSync(utf8.encode('dedicated-p269-preflight-apk'));
    final artifactDigest = sha256
        .convert(artifact.readAsBytesSync())
        .toString();
    runner = _AndroidTargetPreflightRunner(
      inventory: inventory,
      senderQemu: senderQemu,
      receiverQemu: receiverQemu,
    );
    context = GroupMediaReliabilityRunContext(
      scenario: groupMediaForegroundRetryAclRoundtripScenario,
      runId: 'p269-target-preflight',
      preparedArtifact: GroupMediaReliabilityPreparedArtifact(
        path: artifact.absolute.path,
        profile: groupMediaReliabilityAndroidBuildProfile,
        sha256Digest: artifactDigest,
      ),
      roles: const <String, GroupMediaReliabilityRoleBinding>{
        'sender': GroupMediaReliabilityRoleBinding(
          role: 'sender',
          deviceId: _androidSenderTarget,
          identityNamespace: 'sender-preflight',
        ),
        'receiver': GroupMediaReliabilityRoleBinding(
          role: 'receiver',
          deviceId: _androidReceiverTarget,
          identityNamespace: 'receiver-preflight',
        ),
      },
      proofDirectory: Directory(
        '${directory.path}${Platform.pathSeparator}proof',
      ),
      buildGuardLog: null,
    );
  }

  late final Directory directory;
  late final File artifact;
  late final _AndroidTargetPreflightRunner runner;
  late final GroupMediaReliabilityRunContext context;

  void dispose() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}

final class _AndroidTargetPreflightRunner implements AndroidHostProcessRunner {
  _AndroidTargetPreflightRunner({
    required this.inventory,
    required this.senderQemu,
    required this.receiverQemu,
  });

  final String inventory;
  final String senderQemu;
  final String receiverQemu;
  final List<String> mutationCommands = <String>[];

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    final command = '$executable ${arguments.join(' ')}';
    if (executable != 'adb') {
      return ProcessResult(1, 0, '$groupMediaAndroidDisposablePackageId\n', '');
    }
    if (_sameArguments(arguments, const <String>['version'])) {
      return ProcessResult(1, 0, 'Android Debug Bridge version 1.0.41\n', '');
    }
    if (_sameArguments(arguments, const <String>['devices', '-l'])) {
      return ProcessResult(1, 0, inventory, '');
    }
    if (arguments.length >= 3 && arguments.first == '-s') {
      final deviceId = arguments[1];
      final tail = arguments.sublist(2);
      if (_sameArguments(tail, const <String>[
        'shell',
        'getprop',
        'ro.kernel.qemu',
      ])) {
        final value = deviceId == _androidSenderTarget
            ? senderQemu
            : receiverQemu;
        return ProcessResult(1, 0, '$value\n', '');
      }
      if (_sameArguments(tail, const <String>['shell', 'dumpsys', 'power'])) {
        return ProcessResult(
          1,
          0,
          'mWakefulness=Awake\nmInteractive=true\n',
          '',
        );
      }
      if (_sameArguments(tail, const <String>[
        'shell',
        'dumpsys',
        'window',
        'policy',
      ])) {
        return ProcessResult(
          1,
          0,
          'mShowingLockscreen=false\nmInputRestricted=false\n',
          '',
        );
      }
    }
    mutationCommands.add(command);
    return ProcessResult(1, 1, '', 'unexpected mutation');
  }

  bool _sameArguments(List<String> actual, List<String> expected) {
    if (actual.length != expected.length) return false;
    for (var index = 0; index < actual.length; index += 1) {
      if (actual[index] != expected[index]) return false;
    }
    return true;
  }
}

final class _AndroidDisposableFixture {
  _AndroidDisposableFixture({
    String manifestApplicationId = groupMediaAndroidDisposablePackageId,
    bool installedDigestMatches = true,
    bool staleReceipt = false,
  }) {
    directory = Directory.systemTemp.createTempSync('p269-android-helper-');
    artifact = File(
      '${directory.path}${Platform.pathSeparator}group-media-269.apk',
    )..writeAsBytesSync(utf8.encode('dedicated-p269-apk'));
    artifactDigest = sha256.convert(artifact.readAsBytesSync()).toString();
    runner = _AndroidDisposableRunner(
      manifestApplicationId: manifestApplicationId,
      artifactDigest: artifactDigest,
      installedDigestMatches: installedDigestMatches,
      staleReceipt: staleReceipt,
    );
    app = GroupMediaAndroidDisposableApp(
      deviceId: 'emulator-5554',
      artifact: artifact,
      expectedArtifactSha256: artifactDigest,
      runId: 'p269-helper-causal',
      workDirectory: Directory(
        '${directory.path}${Platform.pathSeparator}reset',
      ),
      runner: runner,
      pollInterval: Duration.zero,
      maximumPollsPerLaunch: 1,
      onMutationStarted: () => mutationCount += 1,
    );
  }

  late final Directory directory;
  late final File artifact;
  late final String artifactDigest;
  late final _AndroidDisposableRunner runner;
  late final GroupMediaAndroidDisposableApp app;
  var mutationCount = 0;

  void dispose() {
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}

final class _AndroidDisposableRunner implements AndroidHostProcessRunner {
  _AndroidDisposableRunner({
    required this.manifestApplicationId,
    required this.artifactDigest,
    required this.installedDigestMatches,
    required this.staleReceipt,
  });

  final String manifestApplicationId;
  final String artifactDigest;
  final bool installedDigestMatches;
  final bool staleReceipt;
  final List<String> adbCommands = <String>[];
  final Map<String, String> receiptStdout = <String, String>{};
  Map<String, Object?>? _resetRequest;
  String? _stagedRequestDigest;

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    if (executable != 'adb') {
      return ProcessResult(1, 0, '$manifestApplicationId\n', '');
    }
    adbCommands.add(arguments.join(' '));
    final command = arguments.skip(2).toList(growable: false);
    if (command.isNotEmpty && command.first == 'install') {
      return ProcessResult(1, 0, 'Success\n', '');
    }
    if (_startsWith(command, const <String>['shell', 'pm', 'path'])) {
      return ProcessResult(
        1,
        0,
        'package:/data/app/~~P269Token==/'
            'com.mknoon.sims.groupmedia269-P269Suffix==/base.apk\n',
        '',
      );
    }
    if (_startsWith(command, const <String>['shell', 'sha256sum'])) {
      final digest = installedDigestMatches
          ? artifactDigest
          : List<String>.filled(64, 'f').join();
      return ProcessResult(1, 0, '$digest  ${command.last}\n', '');
    }
    if (command.isNotEmpty && command.first == 'push') {
      final request = File(command[1]);
      final bytes = request.readAsBytesSync();
      _stagedRequestDigest = sha256.convert(bytes).toString();
      _resetRequest = (jsonDecode(utf8.decode(bytes)) as Map)
          .cast<String, Object?>();
      return ProcessResult(1, 0, '1 file pushed\n', '');
    }
    if (_startsWith(command, const <String>['shell', 'run-as']) &&
        command.contains('sha256sum')) {
      return ProcessResult(
        1,
        0,
        '${_stagedRequestDigest ?? ''}  pending\n',
        '',
      );
    }
    if (_startsWith(command, const <String>['shell', 'run-as']) &&
        command.contains('cat')) {
      final request = _resetRequest!;
      final phase = request['phase']! as String;
      final receipt = <String, Object?>{
        'schema': groupMediaIosDisposableResetReceiptSchema,
        'run_id': request['run_id'],
        'nonce': staleReceipt ? 'stale-nonce' : request['nonce'],
        'phase': phase,
        'process_id': phase == 'pre' ? 7001 : 7002,
        'bundle_id': groupMediaAndroidDisposablePackageId,
        'profile': groupMediaAndroidDisposableBuildProfile,
        'keychain_empty': true,
        'database_absent': true,
        'allowlisted_files_absent': true,
        'contains_secrets': false,
      };
      final stdout = '${jsonEncode(receipt)}\n';
      receiptStdout[phase] = stdout;
      return ProcessResult(1, 0, stdout, '');
    }
    if (_startsWith(command, const <String>[
      'shell',
      'cmd',
      'package',
      'resolve-activity',
    ])) {
      return ProcessResult(
        1,
        0,
        '$groupMediaAndroidDisposablePackageId/.MainActivity\n',
        '',
      );
    }
    if (_startsWith(command, const <String>['shell', 'am', 'start'])) {
      return ProcessResult(
        1,
        0,
        'Starting: Intent { cmp=$groupMediaAndroidDisposablePackageId/'
            '.MainActivity }\nStatus: timeout\n',
        '',
      );
    }
    if (_startsWith(command, const <String>['shell', 'pidof'])) {
      return ProcessResult(1, 1, '', '');
    }
    return ProcessResult(1, 0, '', '');
  }

  bool _startsWith(List<String> values, List<String> prefix) {
    if (values.length < prefix.length) return false;
    for (var index = 0; index < prefix.length; index += 1) {
      if (values[index] != prefix[index]) return false;
    }
    return true;
  }
}

final class _ProcessRunner implements AndroidHostProcessRunner {
  _ProcessRunner({
    this.withStoppedWindowStage = false,
    this.launchStatus = 'ok',
  });

  final bool withStoppedWindowStage;
  final String launchStatus;
  final List<String> commands = <String>[];
  var pidReads = 0;

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    commands.add('$executable ${arguments.join(' ')}');
    final tail = arguments.skip(3).join(' ');
    if (tail.startsWith('cmd package resolve-activity')) {
      return ProcessResult(
        1,
        0,
        '$groupMediaAndroidDisposablePackageId/.MainActivity\n',
        '',
      );
    }
    if (tail == 'pidof $groupMediaAndroidDisposablePackageId') {
      pidReads++;
      final stopped =
          pidReads == 2 || (withStoppedWindowStage && pidReads == 3);
      return ProcessResult(
        1,
        stopped ? 1 : 0,
        pidReads == 1
            ? '111\n'
            : stopped
            ? ''
            : '222\n',
        '',
      );
    }
    return ProcessResult(
      1,
      0,
      'Starting: Intent { cmp=$groupMediaAndroidDisposablePackageId/'
          '.MainActivity }\nStatus: $launchStatus\n',
      '',
    );
  }
}

Map<String, Object?> _aggregateFixture({
  String authorityMode = groupMediaDistinctAuthorityMode,
  void Function(Map<String, Object?> bundle)? mutate,
  void Function(
    Map<String, GroupMediaAndroidDisposableResetReceipt> pre,
    Map<String, GroupMediaAndroidDisposableResetReceipt> post,
  )?
  mutateCleanup,
  AndroidGroupMediaCommandSafetyEvidence commandSafety =
      const AndroidGroupMediaCommandSafetyEvidence(
        productionPackageCommands: 0,
        uninstallCommands: 0,
        pmClearCommands: 0,
        broadDeleteCommands: 0,
      ),
  bool appsLeftInstalled = true,
  bool omitAuthority = false,
}) {
  const runId = 'p269-aggregate';
  const messageIds = <String, String>{
    'jpeg': 'message-jpeg',
    'mp4': 'message-mp4',
    'voice': 'message-voice',
  };
  const attachmentIds = <String, String>{
    'jpeg': 'blob-jpeg',
    'mp4': 'blob-mp4',
    'voice': 'blob-voice',
  };
  final context = GroupMediaReliabilityRunContext(
    scenario: groupMediaForegroundRetryAclRoundtripScenario,
    authorityMode: authorityMode,
    runId: runId,
    preparedArtifact: GroupMediaReliabilityPreparedArtifact(
      path: '/tmp/prepared.apk',
      profile: groupMediaReliabilityAndroidBuildProfile,
      sha256Digest: List<String>.filled(64, 'c').join(),
    ),
    roles: const <String, GroupMediaReliabilityRoleBinding>{
      'sender': GroupMediaReliabilityRoleBinding(
        role: 'sender',
        deviceId: 'pixel-usb',
        identityNamespace: 'sender-namespace',
      ),
      'receiver': GroupMediaReliabilityRoleBinding(
        role: 'receiver',
        deviceId: 'emulator-5554',
        identityNamespace: 'receiver-namespace',
      ),
    },
    proofDirectory: Directory('/tmp/p269-proof'),
    buildGuardLog: null,
  );
  final senderDb = _roleDatabase(
    role: 'sender',
    runId: runId,
    messageIds: messageIds,
    attachmentIds: attachmentIds,
    pathDigest: List<String>.filled(64, 'a').join(),
  );
  final receiverDb = _roleDatabase(
    role: 'receiver',
    runId: runId,
    messageIds: messageIds,
    attachmentIds: attachmentIds,
    pathDigest: List<String>.filled(64, 'b').join(),
  );
  final bundle = <String, Object?>{
    'senderSetup': <String, Object?>{
      'groupId': 'group-id',
      'accountPeerId': 'sender-account',
      'transportPeerId': 'sender-transport',
      'processId': 333,
      'roleDatabaseIdentity': _databaseIdentity(senderDb),
    },
    'receiverArm': <String, Object?>{
      'groupId': 'group-id',
      'accountPeerId': 'receiver-account',
      'transportPeerId': 'receiver-transport',
      'processId': 111,
      'roleDatabaseIdentity': _databaseIdentity(receiverDb),
    },
    'senderSend': <String, Object?>{
      'accountPeerId': 'sender-account',
      'transportPeerId': 'sender-transport',
      'receiverAccountPeerId': 'receiver-account',
      'receiverTransportPeerId': 'receiver-transport',
      'processId': 333,
      'allowedPeers': <Object?>['sender-transport', 'receiver-transport'],
      'uploadsPerBlob': <String, Object?>{'jpeg': 1, 'mp4': 1, 'voice': 1},
      'publicationsPerMessage': <String, Object?>{
        'jpeg': 1,
        'mp4': 1,
        'voice': 1,
      },
      'roleDatabase': senderDb,
    },
    'barrierState': <String, Object?>{
      'barrier': <String, Object?>{
        'name': 'receiver_jpeg_post_claim_pre_commit',
        'reached': true,
        'priorStatus': 'downloading',
        'attempt': 1,
        'processId': 111,
      },
    },
    'receiverRecovery': <String, Object?>{
      'priorStatus': 'downloading',
      'previousProcessId': 111,
      'currentProcessId': 222,
      'processId': 222,
      'firstUploadWork': 0,
      'firstDownloadWork': 3,
      'secondUploadWork': 0,
      'secondDownloadWork': 0,
      'downloadAttempts': <String, Object?>{'jpeg': 2, 'mp4': 1, 'voice': 1},
      'roleDatabase': receiverDb,
    },
    'receiverRender': <String, Object?>{
      'processId': 222,
      'renderProbeArmed': true,
    },
    'receiverRenderedKinds': <String, Object?>{'jpeg': 1, 'mp4': 1, 'voice': 1},
    'senderProbe': <String, Object?>{
      'processId': 444,
      'firstUploadWork': 0,
      'firstDownloadWork': 0,
      'secondUploadWork': 0,
      'secondDownloadWork': 0,
      'roleDatabase': senderDb,
    },
  };
  if (authorityMode == groupMediaDistinctAuthorityMode) {
    _map(bundle, 'receiverArm')['authorityBefore'] = _authorityObservation(
      'receiver',
      1,
      false,
    );
    bundle['senderRefresh'] = <String, Object?>{
      'processId': 333,
      'authorityRefresh': <String, Object?>{
        'before': _authorityObservation('sender', 1, false),
        'after': _authorityObservation('sender', 2, true),
        'previousEpoch': 1,
        'currentEpoch': 2,
        'distributedDeviceCount': 1,
        'deferredPeerCount': 0,
      },
    };
    bundle['receiverReady'] = <String, Object?>{
      'processId': 111,
      'authorityAfter': _authorityObservation('receiver', 2, true),
    };
    final media = <String, Object?>{};
    for (final kind in const ['jpeg', 'mp4', 'voice']) {
      final fingerprint = sha256
          .convert(utf8.encode('fingerprint-$kind'))
          .toString();
      media[kind] = <String, Object?>{
        'manifest_sha256': sha256
            .convert(utf8.encode('manifest-$kind'))
            .toString(),
        'custody_fingerprint': fingerprint,
        'custody_blob_id_sha256': sha256
            .convert(utf8.encode('custody-$kind'))
            .toString(),
        'ciphertext_sha256': sha256
            .convert(utf8.encode('ciphertext-$kind'))
            .toString(),
        'ciphertext_size': 128,
        'recipient_count': 1,
        'recipient_transport_sha256': sha256
            .convert(utf8.encode('receiver-transport'))
            .toString(),
        'expires_at_ms': 1900000000000,
      };
      for (final db in [senderDb, receiverDb]) {
        for (final raw in db['rows']! as List) {
          final row = raw as Map<String, Object?>;
          if (row['media_kind'] == kind) {
            row['custody_fingerprint'] = fingerprint;
            if (identical(db, senderDb)) {
              String scoped(String value) =>
                  sha256.convert(utf8.encode('$runId\u0000$value')).toString();
              row['status'] = 'upload_pending';
              row['strict_publication'] = <String, Object?>{
                'message_id': row['message_id'],
                'group_sha256': scoped('group-id'),
                'sender_account_sha256': scoped('sender-account'),
                'attachment_content_sha256':
                    (media[kind]! as Map)['ciphertext_sha256'],
                'status': 'sent',
                'inbox_stored': true,
                'is_incoming': false,
                'wire_envelope_present': false,
                'retry_payload_present': false,
              };
            }
          }
        }
      }
    }
    _map(bundle, 'senderSend')['strictMediaCustody'] = media;
    final jpeg = media['jpeg'] as Map<String, Object?>;
    final boundary = <String, Object?>{
      'state': 'incoming_committed',
      'local_ready': false,
      'ack_source_present': false,
      'custody_projection_sha256': sha256
          .convert(utf8.encode('row'))
          .toString(),
      for (final key in const [
        'custody_fingerprint',
        'ciphertext_sha256',
        'ciphertext_size',
        'custody_blob_id_sha256',
      ])
        key: jpeg[key],
    };
    final barrier = _map(_map(bundle, 'barrierState'), 'barrier');
    barrier['name'] = 'receiver_jpeg_strict_verified_ciphertext_pre_commit';
    barrier['priorStatus'] = 'pending';
    barrier['strictCustodyBoundary'] = boundary;
    _map(bundle, 'receiverRecovery')['priorStatus'] = 'pending';
    _map(bundle, 'receiverRecovery')['strictCustodyBoundary'] = boundary;
  }
  final copied = (jsonDecode(jsonEncode(bundle))! as Map)
      .cast<String, Object?>();
  if (authorityMode == groupMediaAccountBoundAuthorityMode) {
    for (final phase in <String>[
      'senderSetup',
      'receiverArm',
      'senderSend',
      'receiverRecovery',
      'receiverRender',
      'senderProbe',
    ]) {
      _map(copied, phase)['authorityMode'] = authorityMode;
    }
    _map(copied, 'senderSetup')['transportPeerId'] = 'sender-account';
    _map(copied, 'receiverArm')['transportPeerId'] = 'receiver-account';
    _map(copied, 'senderSend')['transportPeerId'] = 'sender-account';
    _map(copied, 'senderSend')['receiverTransportPeerId'] = 'receiver-account';
    _map(copied, 'senderSend')['allowedPeers'] = <Object?>[
      'sender-account',
      'receiver-account',
    ];
  }
  mutate?.call(copied);
  final preResetReceipts = <String, GroupMediaAndroidDisposableResetReceipt>{
    'sender': _resetReceipt('pre', 501, '1'),
    'receiver': _resetReceipt('pre', 502, '2'),
  };
  final postResetReceipts = <String, GroupMediaAndroidDisposableResetReceipt>{
    'sender': _resetReceipt('post', 601, '3'),
    'receiver': _resetReceipt('post', 602, '4'),
  };
  mutateCleanup?.call(preResetReceipts, postResetReceipts);
  return aggregateAndroidGroupMediaReliabilityEvidence(
    context: context,
    authoritySetup:
        authorityMode == groupMediaDistinctAuthorityMode && !omitAuthority
        ? buildAndroidGroupMediaAuthoritySetup(
            runId: runId,
            senderSetup: _map(copied, 'senderSetup'),
            receiverArm: _map(copied, 'receiverArm'),
            senderRefresh: _map(copied, 'senderRefresh'),
            receiverReady: _map(copied, 'receiverReady'),
          )
        : null,
    senderExportedAccountPeerId: 'sender-account',
    receiverExportedAccountPeerId: 'receiver-account',
    senderSetup: _map(copied, 'senderSetup'),
    receiverArm: _map(copied, 'receiverArm'),
    senderSend: _map(copied, 'senderSend'),
    barrierState: _map(copied, 'barrierState'),
    receiverTransition: const AndroidGroupMediaProcessTransitionEvidence(
      oldPid: '111',
      freshPid: '222',
      oldPidGone: true,
      launcherComponent: '$groupMediaAndroidDisposablePackageId/.MainActivity',
      relaunchedWithoutGroupRoute: true,
    ),
    receiverRecovery: _map(copied, 'receiverRecovery'),
    receiverRender: _map(copied, 'receiverRender'),
    receiverRenderedKinds: _map(
      copied,
      'receiverRenderedKinds',
    ).cast<String, int>(),
    senderTransition: const AndroidGroupMediaProcessTransitionEvidence(
      oldPid: '333',
      freshPid: '444',
      oldPidGone: true,
      launcherComponent: '$groupMediaAndroidDisposablePackageId/.MainActivity',
      relaunchedWithoutGroupRoute: true,
    ),
    senderProbe: _map(copied, 'senderProbe'),
    messageIds: messageIds,
    attachmentIds: attachmentIds,
    preResetReceipts: preResetReceipts,
    postResetReceipts: postResetReceipts,
    commandSafety: commandSafety,
    appsLeftInstalled: appsLeftInstalled,
  );
}

GroupMediaAndroidDisposableResetReceipt _resetReceipt(
  String phase,
  int processId,
  String digestCharacter,
) => GroupMediaAndroidDisposableResetReceipt(
  phase: phase,
  processId: processId,
  sha256Digest: List<String>.filled(64, digestCharacter).join(),
);

Map<String, Object?> _roleDatabase({
  required String role,
  required String runId,
  required Map<String, String> messageIds,
  required Map<String, String> attachmentIds,
  required String pathDigest,
}) => <String, Object?>{
  'role_db_path': '$role/group-media.sqlite',
  'database_path_sha256': pathDigest,
  'cipher_version': 'SQLCipher 4.6.1',
  'user_version': currentIdentityDatabaseVersion,
  'rows': <Object?>[
    for (final kind in const <String>['jpeg', 'mp4', 'voice'])
      <String, Object?>{
        'run_id': runId,
        'media_kind': kind,
        'message_id': messageIds[kind],
        'blob_id': attachmentIds[kind],
        'status': 'done',
        'upload_retry_count': 0,
        'download_retry_count': 0,
      },
  ],
};

Map<String, Object?> _databaseIdentity(Map<String, Object?> settled) =>
    <String, Object?>{
      'role_db_path': settled['role_db_path'],
      'database_path_sha256': settled['database_path_sha256'],
      'cipher_version': settled['cipher_version'],
      'user_version': settled['user_version'],
      'rows': <Object?>[],
    };

Map<String, Object?> _map(Map<String, Object?> value, String key) =>
    (value[key]! as Map).cast<String, Object?>();

Map<String, Object?> _authorityObservation(
  String role,
  int epoch,
  bool strict,
) {
  String digest(String value) => sha256.convert(utf8.encode(value)).toString();
  return <String, Object?>{
    'schema': 'mknoon.group-media-authority.v1',
    'groupIdSha256': digest('group-id'),
    'accountPeerIdSha256': digest('$role-account'),
    'transportPeerIdSha256': digest('$role-transport'),
    'memberRolesSha256': digest('exact-roster'),
    'keyEpoch': epoch,
    'admission': strict ? 'strict' : 'refuse',
    'authoritySha256': strict ? digest('authenticated-common-authority') : null,
    'authorityEventAt': strict ? '2026-09-18T01:00:00Z' : null,
    'recipientTransportSha256': strict
        ? <String>[
            digest(
              role == 'sender' ? 'receiver-transport' : 'sender-transport',
            ),
          ]
        : <String>[],
  };
}
