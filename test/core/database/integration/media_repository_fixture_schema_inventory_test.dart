import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 228 TC-228-13H: source-contract inventory of custom encrypted fixtures
/// that use the REAL media repository or persist the v96 media model.
///
/// A stale hand-maintained fixture schema accepts typed API changes at
/// compile time but fails at runtime on-device ("no such column:
/// owner_lane"), so this inventory pins:
///  1. the EXACT set of integration fixtures that instantiate
///     `MediaAttachmentRepositoryImpl`;
///  2. that each of them opens through the SHARED current production
///     registry (never a hand-rolled versioned migration list);
///  3. that the shared E2E seeder exposes a current-production opener
///     SEPARATE from the explicitly versioned historical one, and the
///     historical path cannot write the v96 media model.
void main() {
  List<File> dartFilesUnder(String dir) => Directory(dir)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();

  test('real media repository fixtures use current production schema', () {
    // 1. Exact inventory: which integration_test files construct the REAL
    // media repository.
    final constructors = <String>[];
    for (final file in dartFilesUnder('integration_test')) {
      final source = file.readAsStringSync();
      if (source.contains('MediaAttachmentRepositoryImpl(')) {
        constructors.add(
          file.path.replaceFirst(RegExp(r'^\./'), '').replaceAll('\\', '/'),
        );
      }
    }
    constructors.sort();
    expect(
      constructors,
      [
        'integration_test/group_multi_device_real_harness.dart',
        'integration_test/notification_sound_smoke_harness.dart',
        'integration_test/smoke_test.dart',
      ],
      reason:
          'a NEW fixture instantiating the real media repository must open '
          'through the shared current production registry AND be added to '
          'this inventory',
    );

    // 2. All confirmed fixtures open through the shared registry and no
    // longer own a hand-maintained versioned schema.
    final harness = File(
      'integration_test/group_multi_device_real_harness.dart',
    ).readAsStringSync();
    expect(harness, contains('runProductionOnCreate'));
    expect(harness, contains('currentIdentityDatabaseVersion'));
    expect(
      RegExp(r'version:\s*(11|44|79)\b').hasMatch(harness),
      isFalse,
      reason: 'the harness may not pin a historical schema version',
    );

    final notificationSound = File(
      'integration_test/notification_sound_smoke_harness.dart',
    ).readAsStringSync();
    expect(
      notificationSound,
      contains("import 'group_multi_device_real_harness.dart';"),
    );
    expect(notificationSound, contains('setupGroupMultiDeviceStack('));
    expect(
      RegExp(r'version:\s*(11|44|79)\b').hasMatch(notificationSound),
      isFalse,
      reason:
          'the notification sound harness may not pin a historical schema '
          'version',
    );

    final smoke = File('integration_test/smoke_test.dart').readAsStringSync();
    expect(smoke, contains('openCurrentProductionE2EDatabase'));
    expect(
      RegExp(r'version:\s*(11|44|79)\b').hasMatch(smoke),
      isFalse,
      reason: 'the smoke fixture may not pin a historical schema version',
    );
    // The smoke test exercises a representative owner-state round-trip.
    expect(smoke, contains('owner: MediaOwnerLane.direct'));
    expect(smoke, contains('owner: MediaOwnerLane.group'));
    expect(smoke, contains('updatePlaybackPosition'));
    expect(smoke, contains('setBookmarked'));

    // 3. The shared seeder: a current-production opener exists SEPARATELY
    // from the explicitly versioned historical bootstrap, and the historical
    // create path cannot produce the v96 media schema (it must not run
    // migration 096).
    final seeder = File(
      'integration_test/_support/test_db_seeder.dart',
    ).readAsStringSync();
    expect(seeder, contains('openCurrentProductionE2EDatabase'));
    expect(seeder, contains('runProductionOnCreate'));
    expect(seeder, contains('currentIdentityDatabaseVersion'));
    expect(seeder, contains('openE2EDatabase'));
    expect(
      seeder.contains('runMediaLibraryStateMigration'),
      isFalse,
      reason:
          'the historical seeder path must not be able to write the v96 '
          'media model',
    );
    expect(
      seeder.contains('096_media_library_state'),
      isFalse,
      reason: 'historical fixtures may not import migration 096 directly',
    );
  });
}
