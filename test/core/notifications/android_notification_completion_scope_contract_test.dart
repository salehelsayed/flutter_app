import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('plan 331 excludes ios oem plaintext and force stop', () {
    final manifest =
        jsonDecode(File('tool/sims/critical_features.json').readAsStringSync())
            as Map<String, dynamic>;
    final capability = (manifest['capabilities'] as List<dynamic>)
        .cast<Map<String, dynamic>>()
        .singleWhere(
          (candidate) =>
              candidate['id'] == 'notifications.android_recovery_completion',
        );

    expect(capability['buildProfile'], 'android.production_fcm.fixed_wake');
    expect(capability['dependencies'], <String>[
      'build.android.production_fcm.fixed_wake',
    ]);
    expect(capability['targetCapabilities'], <String>[
      'android.physical',
      'android.emulator',
      'credentials.fcm',
      'relay.staging',
    ]);
    expect(capability['command'], <String>[
      'dart',
      'run',
      'integration_test/scripts/run_android_notification_recovery_completion.dart',
    ]);

    final capabilityText = jsonEncode(capability);
    expect(capabilityText, isNot(matches(RegExp(r'\b(?:ios|apns|swift)\b'))));
    expect(capabilityText, isNot(matches(RegExp(r'\b(?:oem|badge)\b'))));
    for (final resource
        in (capability['resources'] as List<dynamic>)
            .cast<Map<String, dynamic>>()) {
      expect(resource['name'], isNot(contains('ios')));
    }

    final runner = File(
      'integration_test/scripts/run_android_notification_recovery_completion.dart',
    ).readAsStringSync();
    final criteria = File(
      'integration_test/scripts/android_notification_recovery_completion_criteria.dart',
    ).readAsStringSync();
    final proofBinding = File(
      'integration_test/android_notification_recovery_completion_proof_test.dart',
    ).readAsStringSync();
    final sharedCapture = File(
      'integration_test/scripts/capture_1to1_reaction_head_provenance.dart',
    ).readAsStringSync();
    final executableBoundary = '$runner\n$criteria\n$proofBinding';

    expect(
      executableBoundary,
      isNot(matches(RegExp(r'\b(?:ios|apns|swift)\b', caseSensitive: false))),
    );
    expect(
      executableBoundary,
      isNot(matches(RegExp(r'\b(?:oem|badge)\b', caseSensitive: false))),
    );
    expect(runner, isNot(contains('force-stop')));
    expect(runner, isNot(contains("'input', 'tap'")));
    expect(runner, isNot(contains('flutter build')));
    expect(runner, isNot(contains('gradlew')));
    final terminationStart = sharedCapture.indexOf(
      'Future<void> _terminateRecipient()',
    );
    final terminationEnd = sharedCapture.indexOf(
      'Future<void> _backgroundRecipient()',
      terminationStart,
    );
    expect(terminationStart, greaterThanOrEqualTo(0));
    expect(terminationEnd, greaterThan(terminationStart));
    final recoveryTermination = sharedCapture.substring(
      terminationStart,
      terminationEnd,
    );
    expect(recoveryTermination, contains("'stop-app'"));
    expect(recoveryTermination, isNot(contains('force-stop')));
    expect(criteria, contains("'notificationCardTaps'"));
    expect(criteria, contains("'mainActivityLaunchesDuringKilledRecovery'"));

    final dependencyAndNativeSources = <File>[
      File('pubspec.yaml'),
      File('pubspec.lock'),
      File('android/build.gradle.kts'),
      File('android/settings.gradle.kts'),
      File('android/app/build.gradle.kts'),
      ...Directory('android/app/src/main')
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where(
            (file) =>
                file.path.endsWith('.kt') ||
                file.path.endsWith('.java') ||
                file.path.endsWith('.xml'),
          ),
    ];
    final oemBadgeDependency = RegExp(
      r'ShortcutBadger|me\.leolin|shortcut_badger|flutter_app_badger|app_badger',
      caseSensitive: false,
    );
    for (final source in dependencyAndNativeSources) {
      expect(
        source.readAsStringSync(),
        isNot(matches(oemBadgeDependency)),
        reason: '${source.path} must not introduce an OEM badge dependency',
      );
    }

    final directMigration = File(
      'lib/core/database/migrations/107_direct_notification_durability.dart',
    ).readAsStringSync();
    final groupMigration = File(
      'lib/core/database/migrations/106_group_notification_display_outbox.dart',
    ).readAsStringSync();
    final forbiddenPersistedCopy = RegExp(
      r'(^|_)(?:title|body|preview|copy|text|emoji|payload|plaintext|ciphertext|media_path|local_path|wire_envelope)($|_)',
      caseSensitive: false,
    );
    for (final entry in <(String, String, String)>[
      (
        directMigration,
        'direct_notification_display_outbox',
        'direct display outbox',
      ),
      (
        directMigration,
        'direct_notification_reconciliation_outbox',
        'direct reconciliation outbox',
      ),
      (
        groupMigration,
        'group_notification_display_outbox',
        'group display outbox',
      ),
      (
        groupMigration,
        'group_notification_reconciliation_outbox',
        'group reconciliation outbox',
      ),
    ]) {
      expect(
        _columnNames(
          _tableDefinition(entry.$1, entry.$2),
        ).where(forbiddenPersistedCopy.hasMatch),
        isEmpty,
        reason: '${entry.$3} must remain identifier/state-only',
      );
    }
  });
}

String _tableDefinition(String source, String table) {
  final match = RegExp(
    'CREATE TABLE IF NOT EXISTS ${RegExp.escape(table)} \\(([\\s\\S]*?)\\n      \\)',
  ).firstMatch(source);
  if (match == null) {
    throw StateError('Missing CREATE TABLE definition for $table');
  }
  return match.group(1)!;
}

Iterable<String> _columnNames(String tableDefinition) sync* {
  final declaration = RegExp(
    r'^\s*([a-z_][a-z0-9_]*)\s+(?:TEXT|INTEGER|REAL|BLOB)\b',
    caseSensitive: false,
  );
  for (final line in const LineSplitter().convert(tableDefinition)) {
    final match = declaration.firstMatch(line);
    if (match != null) yield match.group(1)!;
  }
}
