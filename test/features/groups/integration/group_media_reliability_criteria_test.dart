import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../../../integration_test/scripts/group_media_reliability_criteria.dart';

void main() {
  test(
    'P269 reliability criteria bind exact v1 group media artifact schema',
    () {
      final accepted = _artifactFixture();
      final acceptedResult = validateGroupMediaReliabilityArtifact(accepted);
      expect(acceptedResult.ok, isTrue, reason: acceptedResult.detail);

      final corruptions =
          <({String label, void Function(Map<String, Object?>) apply})>[
            for (final key in const <String>[
              'schema',
              'run_id',
              'scenario',
              'prepared_artifact',
              'device_roles',
              'identity_fingerprints',
              'account_vs_transport_discriminator',
              'acl_entries',
              'media',
              'role_databases',
              'retry_passes',
              'cleanup',
              'flow_events',
            ])
              (
                label: 'missing top-level $key',
                apply: (artifact) => artifact.remove(key),
              ),
            (
              label: 'wrong schema',
              apply: (artifact) => artifact['schema'] = 'mknoon.group-media.v0',
            ),
            (
              label: 'unexpected top-level evidence',
              apply: (artifact) => artifact['unvalidated'] = true,
            ),
            (
              label: 'unsafe run id',
              apply: (artifact) => artifact['run_id'] = '../other-run',
            ),
            (
              label: 'wrong scenario',
              apply: (artifact) => artifact['scenario'] =
                  groupMediaIosReceiverBackgroundRecoveryScenario,
            ),
            (
              label: 'wrong prepared profile',
              apply: (artifact) =>
                  _map(artifact, 'prepared_artifact')['profile'] =
                      'android.e2e.standard',
            ),
            (
              label: 'bad prepared digest',
              apply: (artifact) =>
                  _map(artifact, 'prepared_artifact')['sha256'] =
                      'not-a-digest',
            ),
            (
              label: 'wrong prepared application id',
              apply: (artifact) =>
                  _map(artifact, 'prepared_artifact')['application_id'] =
                      'com.mknoon.app',
            ),
            (
              label: 'child build',
              apply: (artifact) =>
                  _map(artifact, 'prepared_artifact')['child_builds'] = 1,
            ),
            (
              label: 'missing receiver device role',
              apply: (artifact) =>
                  _map(artifact, 'device_roles').remove('receiver'),
            ),
            (
              label: 'wrong sender device kind',
              apply: (artifact) =>
                  _nestedMap(artifact, 'device_roles', 'sender')['kind'] =
                      'emulator',
            ),
            (
              label: 'same device twice',
              apply: (artifact) =>
                  _nestedMap(
                    artifact,
                    'device_roles',
                    'receiver',
                  )['device_sha256'] = _nestedMap(
                    artifact,
                    'device_roles',
                    'sender',
                  )['device_sha256'],
            ),
            (
              label: 'raw identity',
              apply: (artifact) => _nestedMap(
                artifact,
                'identity_fingerprints',
                'sender',
              )['account_sha256'] = '12D3KooWrawPeerId',
            ),
            (
              label: 'account transport collision',
              apply: (artifact) =>
                  _nestedMap(
                    artifact,
                    'identity_fingerprints',
                    'receiver',
                  )['account_sha256'] = _nestedMap(
                    artifact,
                    'identity_fingerprints',
                    'receiver',
                  )['transport_sha256'],
            ),
            (
              label: 'false discriminator',
              apply: (artifact) => _map(
                artifact,
                'account_vs_transport_discriminator',
              )['sender'] = false,
            ),
            (
              label: 'ACL does not bind receiver transport',
              apply: (artifact) =>
                  (artifact['acl_entries']! as List<Object?>)[0] = _digest(
                    'unrelated-transport',
                  ),
            ),
            (
              label: 'duplicate ACL entry',
              apply: (artifact) =>
                  (artifact['acl_entries']! as List<Object?>).add(
                    _nestedMap(
                      artifact,
                      'identity_fingerprints',
                      'receiver',
                    )['transport_sha256'],
                  ),
            ),
            (
              label: 'duplicate upload',
              apply: (artifact) =>
                  _nestedMap(artifact, 'media', 'uploads_per_blob')['jpeg'] = 2,
            ),
            (
              label: 'missing publication',
              apply: (artifact) => _nestedMap(
                artifact,
                'media',
                'publications_per_message',
              ).remove('voice'),
            ),
            (
              label: 'wrong interrupted download attempts',
              apply: (artifact) =>
                  _nestedMap(artifact, 'media', 'download_attempts')['jpeg'] =
                      1,
            ),
            (
              label: 'missing rendered voice surface',
              apply: (artifact) => _nestedMap(
                artifact,
                'media',
                'rendered_surfaces',
              ).remove('voice'),
            ),
            (
              label: 'process barrier is not atomic',
              apply: (artifact) => _flowFacts(
                artifact,
                'receiver_jpeg_post_claim_pre_commit',
              )['marker_atomic'] = false,
            ),
            (
              label: 'old process did not disappear',
              apply: (artifact) => _flowFacts(
                artifact,
                'receiver_process_force_stopped',
              )['old_pid_gone'] = false,
            ),
            (
              label: 'launcher opened a route',
              apply: (artifact) => _flowFacts(
                artifact,
                'receiver_process_relaunched',
              )['launcher_only'] = false,
            ),
            (
              label: 'fresh PID reused old PID',
              apply: (artifact) {
                final oldPid = _flowFacts(
                  artifact,
                  'receiver_process_relaunched',
                )['old_pid_sha256'];
                _flowFacts(
                  artifact,
                  'receiver_process_relaunched',
                )['fresh_pid_sha256'] = oldPid;
              },
            ),
            (
              label: 'prior status was not read after relaunch',
              apply: (artifact) => _flowFacts(
                artifact,
                'receiver_prior_status_read',
              )['after_relaunch'] = false,
            ),
            (
              label: 'absolute sender DB path',
              apply: (artifact) => _nestedMap(
                artifact,
                'role_databases',
                'sender',
              )['role_db_path'] = '/Users/person/private.sqlite',
            ),
            (
              label: 'uppercase database path digest',
              apply: (artifact) => _nestedMap(
                artifact,
                'role_databases',
                'sender',
              )['database_path_sha256'] = List<String>.filled(64, 'A').join(),
            ),
            (
              label: 'roles bind the same database path digest',
              apply: (artifact) =>
                  _nestedMap(
                    artifact,
                    'role_databases',
                    'receiver',
                  )['database_path_sha256'] = _nestedMap(
                    artifact,
                    'role_databases',
                    'sender',
                  )['database_path_sha256'],
            ),
            (
              label: 'empty cipher version',
              apply: (artifact) => _nestedMap(
                artifact,
                'role_databases',
                'receiver',
              )['cipher_version'] = '',
            ),
            (
              label: 'wrong database version',
              apply: (artifact) => _nestedMap(
                artifact,
                'role_databases',
                'receiver',
              )['user_version'] = 103,
            ),
            (
              label: 'database not reopened',
              apply: (artifact) =>
                  _nestedMap(artifact, 'role_databases', 'sender')['reopened'] =
                      false,
            ),
            (
              label: 'row belongs to another run',
              apply: (artifact) =>
                  _firstRow(artifact, 'sender')['run_id'] = 'another-run',
            ),
            (
              label: 'receiver row has different blob',
              apply: (artifact) =>
                  _firstRow(artifact, 'receiver')['blob_id'] = 'blob-other',
            ),
            (
              label: 'media kinds reuse one message id',
              apply: (artifact) {
                for (final role in const <String>['sender', 'receiver']) {
                  final rows =
                      _nestedMap(artifact, 'role_databases', role)['rows']
                          as List;
                  (rows[1] as Map)['message_id'] =
                      (rows[0] as Map)['message_id'];
                }
              },
            ),
            (
              label: 'media kinds reuse one blob id',
              apply: (artifact) {
                for (final role in const <String>['sender', 'receiver']) {
                  final rows =
                      _nestedMap(artifact, 'role_databases', role)['rows']
                          as List;
                  (rows[1] as Map)['blob_id'] = (rows[0] as Map)['blob_id'];
                }
              },
            ),
            (
              label: 'row not settled',
              apply: (artifact) =>
                  _firstRow(artifact, 'receiver')['status'] = 'downloading',
            ),
            (
              label: 'retry counter has wrong type',
              apply: (artifact) =>
                  _firstRow(artifact, 'sender')['upload_retry_count'] = '0',
            ),
            (
              label: 'second upload pass did work',
              apply: (artifact) =>
                  _map(artifact, 'retry_passes')['second_upload_work'] = 1,
            ),
            (
              label: 'second download pass did work',
              apply: (artifact) =>
                  _map(artifact, 'retry_passes')['second_download_work'] = 1,
            ),
            (
              label: 'cleanup artifact digest is not prepared APK',
              apply: (artifact) =>
                  _map(artifact, 'cleanup')['artifact_sha256'] = _digest(
                    'other-apk',
                  ),
            ),
            (
              label: 'cleanup uses production package',
              apply: (artifact) => _map(artifact, 'cleanup')['application_id'] =
                  'com.mknoon.app',
            ),
            (
              label: 'cleanup reuses pre receipt as post receipt',
              apply: (artifact) =>
                  _nestedMap(artifact, 'cleanup', 'sender')['post_reset'] =
                      _nestedMap(artifact, 'cleanup', 'sender')['pre_reset'],
            ),
            (
              label: 'cleanup receipt phase is stale',
              apply: (artifact) =>
                  _cleanupReceipt(artifact, 'receiver', 'post_reset')['phase'] =
                      'pre',
            ),
            (
              label: 'cleanup receipt digest is malformed',
              apply: (artifact) => _cleanupReceipt(
                artifact,
                'sender',
                'pre_reset',
              )['receipt_sha256'] = 'not-a-digest',
            ),
            (
              label: 'cleanup receipt process digest is malformed',
              apply: (artifact) => _cleanupReceipt(
                artifact,
                'sender',
                'post_reset',
              )['process_id_sha256'] = 'not-a-digest',
            ),
            (
              label: 'cleanup receipt uses wrong profile',
              apply: (artifact) => _cleanupReceipt(
                artifact,
                'receiver',
                'pre_reset',
              )['profile'] = 'android.e2e.main',
            ),
            (
              label: 'cleanup receipt uses production package',
              apply: (artifact) => _cleanupReceipt(
                artifact,
                'receiver',
                'post_reset',
              )['application_id'] = 'com.mknoon.app',
            ),
            (
              label: 'cleanup receipt secure storage is not empty',
              apply: (artifact) => _cleanupReceipt(
                artifact,
                'sender',
                'post_reset',
              )['secure_storage_empty'] = false,
            ),
            (
              label: 'cleanup receipt database remains',
              apply: (artifact) => _cleanupReceipt(
                artifact,
                'sender',
                'post_reset',
              )['database_absent'] = false,
            ),
            (
              label: 'cleanup receipt allowlisted files remain',
              apply: (artifact) => _cleanupReceipt(
                artifact,
                'receiver',
                'post_reset',
              )['allowlisted_files_absent'] = false,
            ),
            (
              label: 'cleanup receipt contains secrets',
              apply: (artifact) => _cleanupReceipt(
                artifact,
                'receiver',
                'pre_reset',
              )['contains_secrets'] = true,
            ),
            (
              label: 'cleanup receipts are not distinct',
              apply: (artifact) =>
                  _map(artifact, 'cleanup')['receipts_distinct'] = false,
            ),
            (
              label: 'cleanup carries an unvalidated field',
              apply: (artifact) =>
                  _map(artifact, 'cleanup')['unvalidated'] = true,
            ),
            (
              label: 'cleanup uninstalled the app',
              apply: (artifact) =>
                  _map(artifact, 'cleanup')['app_left_installed'] = false,
            ),
            for (final counter in const <String>[
              'production_package_commands',
              'uninstall_commands',
              'pm_clear_commands',
              'broad_delete_commands',
            ])
              (
                label: 'cleanup $counter is nonzero',
                apply: (artifact) => _map(artifact, 'cleanup')[counter] = 1,
              ),
            (
              label: 'upload settlement count is fuzzy',
              apply: (artifact) =>
                  _flowFacts(artifact, 'sender_uploads_settled')['count'] = 2,
            ),
            (
              label: 'final zero pass scope is wrong',
              apply: (artifact) =>
                  _flowFacts(artifact, 'second_retry_pass_zero')['scope'] =
                      'receiver_pre_render',
            ),
            (
              label: 'first download pass exceeds fixture cardinality',
              apply: (artifact) => _flowFacts(
                artifact,
                'receiver_downloads_settled',
              )['first_pass_work'] = 4,
            ),
            (
              label: 'missing flow event',
              apply: (artifact) =>
                  (artifact['flow_events']! as List<Object?>).removeAt(2),
            ),
            (
              label: 'render event claims no JPEG decoder frame',
              apply: (artifact) => _flowFacts(
                artifact,
                'receiver_media_rendered',
              )['jpeg_decoder_frame'] = false,
            ),
            (
              label: 'flow event role is rebound',
              apply: (artifact) {
                final events = artifact['flow_events']! as List<Object?>;
                final render = events.cast<Map>().firstWhere(
                  (event) => event['name'] == 'receiver_media_rendered',
                );
                render['role'] = 'sender';
              },
            ),
            (
              label: 'process flow names are permuted',
              apply: (artifact) {
                final events = artifact['flow_events']! as List<Object?>;
                final first = (events[2]! as Map).cast<String, Object?>();
                final second = (events[3]! as Map).cast<String, Object?>();
                final firstName = first['name'];
                first['name'] = second['name'];
                second['name'] = firstName;
              },
            ),
            (
              label: 'unsafe flow fact',
              apply: (artifact) =>
                  ((artifact['flow_events']! as List<Object?>).first
                      as Map<String, Object?>)['facts'] = <String, Object?>{
                    'raw_peer_id': '12D3KooWmust-not-leak',
                  },
            ),
          ];

      for (final corruption in corruptions) {
        final mutated = _deepCopy(accepted);
        corruption.apply(mutated);
        final result = validateGroupMediaReliabilityArtifact(mutated);
        expect(
          result.ok,
          isFalse,
          reason: '${corruption.label} unexpectedly passed',
        );
      }
    },
  );
}

Map<String, Object?> _artifactFixture() {
  const runId = 'p269-run-001';
  final senderRows = _rows(runId);
  final receiverRows = _rows(runId);
  final senderTransport = _digest('$runId-sender-transport');
  final receiverTransport = _digest('$runId-receiver-transport');
  return <String, Object?>{
    'schema': groupMediaReliabilityArtifactSchema,
    'run_id': runId,
    'scenario': groupMediaForegroundRetryAclRoundtripScenario,
    'prepared_artifact': <String, Object?>{
      'profile': groupMediaReliabilityAndroidBuildProfile,
      'application_id': groupMediaReliabilityAndroidPackageName,
      'sha256': _digest('prepared-apk'),
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
        'account_sha256': _digest('$runId-sender-account'),
        'transport_sha256': senderTransport,
      },
      'receiver': <String, Object?>{
        'account_sha256': _digest('$runId-receiver-account'),
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
      'sender': <String, Object?>{
        'role_db_path': 'sender/group-media.sqlite',
        'database_path_sha256': _digest('$runId-sender-database'),
        'cipher_version': 'SQLCipher 4.6.1',
        'user_version': 104,
        'reopened': true,
        'rows': senderRows,
      },
      'receiver': <String, Object?>{
        'role_db_path': 'receiver/group-media.sqlite',
        'database_path_sha256': _digest('$runId-receiver-database'),
        'cipher_version': 'SQLCipher 4.6.1',
        'user_version': 104,
        'reopened': true,
        'rows': receiverRows,
      },
    },
    'retry_passes': <String, Object?>{
      'second_upload_work': 0,
      'second_download_work': 0,
    },
    'cleanup': <String, Object?>{
      'application_id': groupMediaReliabilityAndroidPackageName,
      'artifact_sha256': _digest('prepared-apk'),
      'sender': <String, Object?>{
        'pre_reset': _resetReceiptFixture('sender', 'pre'),
        'post_reset': _resetReceiptFixture('sender', 'post'),
      },
      'receiver': <String, Object?>{
        'pre_reset': _resetReceiptFixture('receiver', 'pre'),
        'post_reset': _resetReceiptFixture('receiver', 'post'),
      },
      'receipts_distinct': true,
      'app_left_installed': true,
      'production_package_commands': 0,
      'uninstall_commands': 0,
      'pm_clear_commands': 0,
      'broad_delete_commands': 0,
    },
    'flow_events': _flowEvents(),
  };
}

Map<String, Object?> _resetReceiptFixture(String role, String phase) =>
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

List<Object?> _rows(String runId) => <Object?>[
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
];

List<Object?> _flowEvents() => <Object?>[
  for (final entry in <(String, String, Map<String, Object?>)>[
    ('sender_uploads_settled', 'sender', <String, Object?>{'count': 3}),
    ('sender_publications_settled', 'sender', <String, Object?>{'count': 3}),
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
      <String, Object?>{'settled_attachment_count': 3, 'first_pass_work': 3},
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
];

Map<String, Object?> _flowFacts(Map<String, Object?> artifact, String name) =>
    (((artifact['flow_events']! as List<Object?>).cast<Map>().firstWhere(
              (event) => event['name'] == name,
            ))['facts']!
            as Map)
        .cast<String, Object?>();

Map<String, Object?> _deepCopy(Map<String, Object?> value) =>
    (jsonDecode(jsonEncode(value))! as Map).cast<String, Object?>();

Map<String, Object?> _map(Map<String, Object?> value, String key) =>
    (value[key]! as Map).cast<String, Object?>();

Map<String, Object?> _nestedMap(
  Map<String, Object?> value,
  String parent,
  String key,
) => (_map(value, parent)[key]! as Map).cast<String, Object?>();

Map<String, Object?> _cleanupReceipt(
  Map<String, Object?> value,
  String role,
  String phase,
) =>
    (_nestedMap(value, 'cleanup', role)[phase]! as Map).cast<String, Object?>();

Map<String, Object?> _firstRow(Map<String, Object?> value, String role) =>
    ((_nestedMap(value, 'role_databases', role)['rows']! as List).first as Map)
        .cast<String, Object?>();

String _digest(String seed) {
  final codeUnits = seed.codeUnits;
  return List<String>.generate(
    64,
    (index) => (codeUnits[index % codeUnits.length] % 16).toRadixString(16),
  ).join();
}
