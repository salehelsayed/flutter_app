import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/scripts/group_multi_party_runtime_config.dart';

void main() {
  Map<String, Object> completeRuntimeConfigJson() =>
      const GroupMultiPartyRuntimeConfig(
        sharedDir: '/data/user/0/com.mknoon.app/cache/gmp_h01_run-123',
        role: 'charlie',
        scenario: 'private_voluntary_leave_convergence',
        runId: 'run-123',
        mode: 'proof',
        restoreMnemonic: '',
        restoreIdentityPath: '',
        reuseExistingIdentity: false,
        dbName:
            'group_multi_party_private_voluntary_leave_convergence_'
            'run-123_charlie.db',
      ).toJson();

  group('resolveGroupMultiPartyConfig', () {
    test('maps a full runtime value set into typed config', () {
      final config = resolveGroupMultiPartyConfig(<String, String>{
        groupMultiPartySharedDirKey: '/tmp/gmp',
        groupMultiPartyRoleKey: 'charlie',
        groupMultiPartyScenarioKey: 'ge014',
        groupMultiPartyRunIdKey: 'run-123',
        groupMultiPartyModeKey: 'restartSeed',
        groupMultiPartyRestoreMnemonicKey: 'alpha beta gamma',
        groupMultiPartyRestoreIdentityPathKey: '/tmp/identity.json',
        groupMultiPartyReuseExistingIdentityKey: 'true',
        groupMultiPartyDbNameKey: 'scenario.db',
      });

      expect(config.sharedDir, '/tmp/gmp');
      expect(config.role, 'charlie');
      expect(config.scenario, 'ge014');
      expect(config.runId, 'run-123');
      expect(config.mode, 'restartSeed');
      expect(config.restoreMnemonic, 'alpha beta gamma');
      expect(config.restoreIdentityPath, '/tmp/identity.json');
      expect(config.reuseExistingIdentity, isTrue);
      expect(config.dbName, 'scenario.db');
      expect(
        config.stagingMechanism,
        groupMultiPartyRuntimeConfigStagingMechanism,
      );
    });

    test('defaults missing values to legacy harness values', () {
      final config = resolveGroupMultiPartyConfig(const <String, String>{});

      expect(config.sharedDir, '/tmp');
      expect(config.role, 'alice');
      expect(config.scenario, 'gm001');
      expect(config.runId, 'adhoc');
      expect(config.mode, 'proof');
      expect(config.restoreMnemonic, isEmpty);
      expect(config.restoreIdentityPath, isEmpty);
      expect(config.reuseExistingIdentity, isFalse);
      expect(config.dbName, isEmpty);
    });

    test(
      'parses bools case-insensitively and preserves empty restore fields',
      () {
        final config = resolveGroupMultiPartyConfig(<String, String>{
          groupMultiPartyRestoreMnemonicKey: '',
          groupMultiPartyRestoreIdentityPathKey: '',
          groupMultiPartyReuseExistingIdentityKey: ' TRUE ',
        });

        expect(config.restoreMnemonic, isEmpty);
        expect(config.restoreIdentityPath, isEmpty);
        expect(config.reuseExistingIdentity, isTrue);

        final falseConfig = resolveGroupMultiPartyConfig(<String, String>{
          groupMultiPartyReuseExistingIdentityKey: 'yes',
        });
        expect(falseConfig.reuseExistingIdentity, isFalse);
      },
    );
  });

  group('loadGroupMultiPartyRuntimeConfigValues', () {
    test(
      'waits for atomic final-file appearance and ignores pending',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'group_multi_party_runtime_config_atomic_',
        );
        addTearDown(() async {
          if (directory.existsSync()) {
            await directory.delete(recursive: true);
          }
        });
        final finalFile = File(
          '${directory.path}/$groupMultiPartyRuntimeConfigFileName',
        );
        final pendingFile = File('${finalFile.path}.pending');
        await pendingFile.writeAsString(
          jsonEncode(completeRuntimeConfigJson()),
          flush: true,
        );

        final pollStarted = Completer<void>();
        final releasePoll = Completer<void>();
        var completed = false;
        final load = loadGroupMultiPartyRuntimeConfigValues(
          finalConfigFile: finalFile,
          requireConfig: true,
          timeout: const Duration(seconds: 5),
          delay: (_) {
            if (!pollStarted.isCompleted) {
              pollStarted.complete();
            }
            return releasePoll.future;
          },
        ).whenComplete(() => completed = true);

        await pollStarted.future;
        expect(finalFile.existsSync(), isFalse);
        expect(pendingFile.existsSync(), isTrue);
        expect(completed, isFalse);

        await pendingFile.rename(finalFile.path);
        releasePoll.complete();

        final values = await load;
        final config = resolveGroupMultiPartyConfig(values);
        expect(config.sharedDir, contains('/cache/gmp_h01_run-123'));
        expect(config.role, 'charlie');
        expect(config.scenario, 'private_voluntary_leave_convergence');
        expect(config.runId, 'run-123');
        expect(config.dbName, endsWith('run-123_charlie.db'));
      },
    );

    test('times out while only a pending file exists', () async {
      final directory = await Directory.systemTemp.createTemp(
        'group_multi_party_runtime_config_pending_',
      );
      addTearDown(() async {
        if (directory.existsSync()) {
          await directory.delete(recursive: true);
        }
      });
      final finalFile = File(
        '${directory.path}/$groupMultiPartyRuntimeConfigFileName',
      );
      await File(
        '${finalFile.path}.pending',
      ).writeAsString(jsonEncode(completeRuntimeConfigJson()));
      var elapsed = Duration.zero;

      await expectLater(
        loadGroupMultiPartyRuntimeConfigValues(
          finalConfigFile: finalFile,
          requireConfig: true,
          timeout: const Duration(seconds: 3),
          pollInterval: const Duration(seconds: 1),
          elapsed: () => elapsed,
          delay: (duration) async {
            elapsed += duration;
          },
        ),
        throwsA(
          isA<TimeoutException>().having(
            (error) => error.message,
            'message',
            contains(finalFile.path),
          ),
        ),
      );
      expect(elapsed, const Duration(seconds: 3));
      expect(finalFile.existsSync(), isFalse);
    });

    test('rejects malformed and incomplete required final files', () async {
      final directory = await Directory.systemTemp.createTemp(
        'group_multi_party_runtime_config_invalid_',
      );
      addTearDown(() async {
        if (directory.existsSync()) {
          await directory.delete(recursive: true);
        }
      });
      final finalFile = File(
        '${directory.path}/$groupMultiPartyRuntimeConfigFileName',
      );
      await finalFile.writeAsString('{not-json', flush: true);

      await expectLater(
        loadGroupMultiPartyRuntimeConfigValues(
          finalConfigFile: finalFile,
          requireConfig: true,
        ),
        throwsFormatException,
      );

      final incomplete = completeRuntimeConfigJson()
        ..remove(groupMultiPartyDbNameKey);
      await finalFile.writeAsString(jsonEncode(incomplete), flush: true);
      await expectLater(
        loadGroupMultiPartyRuntimeConfigValues(
          finalConfigFile: finalFile,
          requireConfig: true,
        ),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            contains(groupMultiPartyDbNameKey),
          ),
        ),
      );
    });

    test('preserves missing-file fallback for non-required callers', () async {
      final directory = await Directory.systemTemp.createTemp(
        'group_multi_party_runtime_config_legacy_',
      );
      addTearDown(() async {
        if (directory.existsSync()) {
          await directory.delete(recursive: true);
        }
      });
      final values = await loadGroupMultiPartyRuntimeConfigValues(
        finalConfigFile: File(
          '${directory.path}/$groupMultiPartyRuntimeConfigFileName',
        ),
        requireConfig: false,
      );

      expect(values, isEmpty);
      expect(resolveGroupMultiPartyConfig(values).scenario, 'gm001');
    });
  });
}
