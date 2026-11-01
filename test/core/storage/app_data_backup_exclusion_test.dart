import 'package:flutter_app/core/storage/app_data_backup_exclusion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('app data backup exclusion', () {
    test('marks the Documents folder and the App Group container', () async {
      final marked = <String>[];
      final refused = <String>[];

      await excludeAppDataFromBackup(
        isIOS: true,
        documentsPath: () async => '/app/Documents',
        appGroupPath: () async => '/group/container',
        exclude: (path) async {
          marked.add(path);
          return true;
        },
        reportRefused: refused.add,
      );

      expect(marked, ['/app/Documents', '/group/container']);
      expect(refused, isEmpty);
    });

    test('marks again on every launch', () async {
      final marked = <String>[];
      Future<void> launch() => excludeAppDataFromBackup(
        isIOS: true,
        documentsPath: () async => '/app/Documents',
        appGroupPath: () async => null,
        exclude: (path) async {
          marked.add(path);
          return true;
        },
        reportRefused: (_) {},
      );

      await launch();
      await launch();

      expect(marked, ['/app/Documents', '/app/Documents']);
    });

    test(
      'a refused or failing mark is reported by root name and the next root is still marked',
      () async {
        final marked = <String>[];
        final refused = <String>[];

        await excludeAppDataFromBackup(
          isIOS: true,
          documentsPath: () async => '/app/Documents',
          appGroupPath: () async => '/group/container',
          exclude: (path) async {
            marked.add(path);
            if (path == '/app/Documents') {
              throw StateError('backup_exclusion_failed');
            }
            return false;
          },
          reportRefused: refused.add,
        );

        expect(marked, ['/app/Documents', '/group/container']);
        expect(refused, ['documents', 'app_group']);
      },
    );

    test('a missing App Group container is skipped, not reported', () async {
      final marked = <String>[];
      final refused = <String>[];

      await excludeAppDataFromBackup(
        isIOS: true,
        documentsPath: () async => '/app/Documents',
        appGroupPath: () async => null,
        exclude: (path) async {
          marked.add(path);
          return true;
        },
        reportRefused: refused.add,
      );

      expect(marked, ['/app/Documents']);
      expect(refused, isEmpty);
    });

    test('does nothing off iOS', () async {
      final marked = <String>[];

      await excludeAppDataFromBackup(
        isIOS: false,
        documentsPath: () async => '/app/Documents',
        appGroupPath: () async => '/group/container',
        exclude: (path) async {
          marked.add(path);
          return true;
        },
        reportRefused: (_) {},
      );

      expect(marked, isEmpty);
    });
  });
}
