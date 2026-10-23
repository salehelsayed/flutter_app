import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/sims/manifest.dart';
import '../../../tool/sims/planner.dart';
import '../../../tool/sims/production_direct_ordered_replay_criteria.dart';
import '../../../tool/sims/production_direct_send_cut_criteria.dart';
import '../../../tool/sims/production_group_ordered_recovery_criteria.dart';

const _commands = {
  productionDirectOrderedReplay:
      'integration_test/scripts/run_production_direct_ordered_replay.dart',
  productionGroupOrderedRecovery:
      'integration_test/scripts/run_production_group_ordered_recovery.dart',
  productionDirectSendCut:
      'integration_test/scripts/run_production_direct_send_cut.dart',
};

void main() {
  late SimsManifest manifest;
  setUpAll(() {
    manifest = SimsManifest.loadSync(File('tool/sims/critical_features.json'));
  });

  test(
    'new Catalog journeys have one manifest owner and exact host-only metadata dispatch',
    () {
      for (final entry in _commands.entries) {
        final capability = manifest.capabilityById(entry.key)!;
        expect(capability.command, ['dart', 'run', entry.value]);
        expect(capability.artifactRequired, isTrue);
        expect(capability.artifactValidators, hasLength(1));
        expect(
          capability.artifactValidators.single,
          startsWith('validateProduction'),
        );
        expect(SimsPlanner(manifest).compile(onlyId: entry.key).selectedIds, {
          entry.key,
          'build.android.e2e.production',
        });
        final listed = Process.runSync('dart', [
          entry.value,
          '--list-scenarios',
        ]);
        expect(listed.exitCode, 0, reason: '${listed.stderr}');
        expect('${listed.stdout}'.trim(), entry.key);
      }
    },
  );

  test(
    'disposable journey device locks cover the actual simultaneous role count',
    () {
      for (final id in _commands.keys) {
        final capability = manifest.capabilityById(id)!;
        final locks = capability.resources
            .map((resource) => resource.name)
            .where((name) => name.startsWith('device:'))
            .toSet();
        expect(locks, {
          'device:android-emulator-fourth',
          'device:android-emulator',
          if (id == productionGroupOrderedRecovery)
            'device:android-emulator-second',
        });
        expect(
          capability.targetCapabilities,
          isNot(contains('android.physical')),
        );
      }
    },
  );

  test(
    'the bounded fixture control remains explicit in the checkpoint capability',
    () {
      final capability = manifest.capabilityById(productionDirectSendCut)!;
      expect(
        capability.resources.map((resource) => resource.name),
        contains('relay-mutation:local-direct-text-checkpoint-fixture'),
      );
      expect(capability.inheritedEnvironmentKeys.toSet(), {
        'MKNOON_DIRECT_TEXT_SEND_CHECKPOINT',
        'MKNOON_DIRECT_MEDIA_CUSTODY_FIXTURE_IDENTITY_SHA256',
        'MKNOON_DIRECT_MEDIA_CUSTODY_FIXTURE_PROBE_URL',
      });
    },
  );

  test(
    'runtime aliases and required complementary existing legs remain registered',
    () {
      expect(directSendCutRuntime, directOrderedReplayRuntime);
      for (final id in {
        directOrderedReplayRuntime,
        groupOrderedRecoveryRuntime,
        'production.group_catalog.private_process_death_matrix',
        'kx0002',
        'kx0003',
        'kx0005',
        'kx0006',
        'kx0007',
        'kx0008',
      }) {
        expect(manifest.capabilityById(id)!.active, isTrue);
      }
    },
  );

  test(
    'checkpoint relay wrapper remains external to the executable manifest plan',
    () {
      const wrapper =
          'integration_test/scripts/run_direct_text_send_cut_sims.dart';
      expect(
        manifest.capabilities.where(
          (capability) => capability.command.contains(wrapper),
        ),
        isEmpty,
      );
      final listed = Process.runSync('dart', [wrapper, '--list-scenarios']);
      expect(listed.exitCode, 0, reason: '${listed.stderr}');
      expect('${listed.stdout}'.trim(), productionDirectSendCut);
    },
  );

  test(
    'safe launcher exposes only the cut and build in its dedicated fixture mode',
    () {
      Map listMode(String mode) {
        final result = Process.runSync('python3', [
          'docker-ws/run_sims_safe.py',
          mode,
          '--list',
        ]);
        expect(result.exitCode, 0, reason: '${result.stderr}');
        return jsonDecode('${result.stdout}') as Map;
      }

      final dedicated = (listMode('device-text')['rows'] as List).cast<Map>();
      expect(dedicated.map((row) => row['id']).toSet(), {
        productionDirectSendCut,
        'build.android.e2e.production',
      });
      expect(dedicated.every((row) => row['status'] == 'SELECTED'), isTrue);
      final major = (listMode('major')['rows'] as List).cast<Map>();
      final cut = major.singleWhere(
        (row) => row['id'] == productionDirectSendCut,
      );
      expect(cut['status'], 'BLOCKED');
      expect(cut['blocker'], 'local_fixture_mode_required');
    },
  );

  test(
    'compatibility census classifies the new scripts as support owned by manifest execution',
    () {
      final result = Process.runSync('bash', [
        'scripts/check_reliability_simulation_discovery.sh',
        '--classifications-tsv',
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final records = '${result.stdout}'
          .split('\n')
          .where((line) => line.isNotEmpty)
          .map((line) => line.split('\t'))
          .toList();
      for (final path in [
        ..._commands.values,
        'integration_test/scripts/run_direct_text_send_cut_sims.dart',
      ]) {
        final matches = records.where(
          (record) => record.length == 4 && record[2] == path,
        );
        expect(matches, hasLength(1), reason: path);
        expect(matches.single.take(2), ['support', 'support']);
        expect(matches.single[3], contains('manifest-owned Catalog P0'));
      }
    },
  );
}
