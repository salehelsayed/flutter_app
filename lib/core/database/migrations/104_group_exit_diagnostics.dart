// ignore_for_file: file_names

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../../utils/flow_event_emitter.dart';

const _migrationName = '104_group_exit_diagnostics';

const _createGroupExitDiagnosticsTableSql = '''
CREATE TABLE IF NOT EXISTS group_exit_diagnostics (
  id INTEGER PRIMARY KEY,
  occurred_at TEXT NOT NULL CHECK(
    length(occurred_at) = 24
    AND occurred_at GLOB
      '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9].[0-9][0-9][0-9]Z'
    AND strftime('%Y-%m-%dT%H:%M:%fZ', occurred_at, '+0 days') IS NOT NULL
    AND occurred_at =
      strftime('%Y-%m-%dT%H:%M:%fZ', occurred_at, '+0 days')
  ),
  group_ref TEXT NOT NULL CHECK(
    length(group_ref) = 12
    AND group_ref NOT GLOB '*[^0-9a-f]*'
  ),
  intent_ref TEXT CHECK(
    intent_ref IS NULL
    OR (
      length(intent_ref) = 24
      AND intent_ref NOT GLOB '*[^0-9a-f]*'
    )
  ),
  exit_kind TEXT NOT NULL CHECK(exit_kind IN (
    'voluntary',
    'self_removed_shell',
    'dissolved_shell'
  )),
  severity TEXT NOT NULL CHECK(severity IN ('failure', 'warning')),
  phase TEXT NOT NULL CHECK(phase IN (
    'authority',
    'role_sync',
    'notice',
    'native',
    'cleanup',
    'delivery',
    'rotation',
    'local_delete'
  )),
  public_code TEXT NOT NULL CHECK(public_code IN (
    'EX01', 'EX02', 'EX03', 'EX04', 'EX05', 'EX06',
    'EX07', 'EX08', 'EX09', 'EX10', 'EX99'
  )),
  reason_code TEXT NOT NULL CHECK(reason_code IN (
    'authority_unavailable',
    'role_sync_failed',
    'notice_prepare_failed',
    'node_not_initialized',
    'native_rejected',
    'native_uncertain',
    'cleanup_incomplete',
    'notice_delivery_degraded',
    'rotation_deferred',
    'terminal_shell_cleanup',
    'unexpected'
  )),
  CHECK(
    (
      public_code = 'EX01'
      AND reason_code = 'authority_unavailable'
      AND phase = 'authority'
      AND severity = 'failure'
      AND (
        exit_kind = 'voluntary'
        OR (
          exit_kind IN ('self_removed_shell', 'dissolved_shell')
          AND intent_ref IS NULL
        )
      )
    )
    OR (
      public_code = 'EX02'
      AND reason_code = 'role_sync_failed'
      AND phase = 'role_sync'
      AND severity = 'failure'
      AND exit_kind = 'voluntary'
    )
    OR (
      public_code = 'EX03'
      AND reason_code = 'notice_prepare_failed'
      AND phase = 'notice'
      AND severity = 'failure'
      AND exit_kind = 'voluntary'
      AND intent_ref IS NOT NULL
    )
    OR (
      public_code = 'EX04'
      AND reason_code = 'node_not_initialized'
      AND phase = 'native'
      AND severity = 'failure'
      AND exit_kind = 'voluntary'
      AND intent_ref IS NOT NULL
    )
    OR (
      public_code = 'EX05'
      AND reason_code = 'native_rejected'
      AND phase = 'native'
      AND severity = 'failure'
      AND exit_kind = 'voluntary'
      AND intent_ref IS NOT NULL
    )
    OR (
      public_code = 'EX06'
      AND reason_code = 'native_uncertain'
      AND phase = 'native'
      AND severity = 'failure'
      AND exit_kind = 'voluntary'
      AND intent_ref IS NOT NULL
    )
    OR (
      public_code = 'EX07'
      AND reason_code = 'cleanup_incomplete'
      AND phase = 'cleanup'
      AND severity = 'warning'
      AND exit_kind = 'voluntary'
      AND intent_ref IS NOT NULL
    )
    OR (
      public_code = 'EX08'
      AND reason_code = 'notice_delivery_degraded'
      AND phase = 'delivery'
      AND severity = 'warning'
      AND exit_kind = 'voluntary'
      AND intent_ref IS NOT NULL
    )
    OR (
      public_code = 'EX09'
      AND reason_code = 'rotation_deferred'
      AND phase = 'rotation'
      AND severity = 'warning'
      AND exit_kind = 'voluntary'
      AND intent_ref IS NOT NULL
    )
    OR (
      public_code = 'EX10'
      AND reason_code = 'terminal_shell_cleanup'
      AND phase = 'local_delete'
      AND severity = 'failure'
      AND exit_kind IN ('self_removed_shell', 'dissolved_shell')
      AND intent_ref IS NULL
    )
    OR (
      public_code = 'EX99'
      AND reason_code = 'unexpected'
      AND phase IN (
        'authority',
        'role_sync',
        'notice',
        'native',
        'cleanup',
        'delivery',
        'rotation'
      )
      AND severity = 'failure'
      AND exit_kind = 'voluntary'
      AND intent_ref IS NOT NULL
    )
  )
);
''';

/// Adds the bounded, release-safe group-exit diagnostic history.
///
/// The table intentionally has no foreign key or cascade. Historical facts
/// must survive deletion of both the group shell and the exit intent. Legacy
/// data is never inferred or backfilled.
Future<void> runGroupExitDiagnosticsMigration(Database db) async {
  emitFlowEvent(
    layer: 'DB',
    event: 'GROUP_EXIT_DIAGNOSTICS_MIGRATION_START',
    details: const {'migration': _migrationName},
  );

  try {
    await db.execute(_createGroupExitDiagnosticsTableSql);
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_EXIT_DIAGNOSTICS_MIGRATION_SUCCESS',
      details: const {'migration': _migrationName},
    );
  } catch (_) {
    emitFlowEvent(
      layer: 'DB',
      event: 'GROUP_EXIT_DIAGNOSTICS_MIGRATION_ERROR',
      details: const {'migration': _migrationName},
    );
    rethrow;
  }
}
