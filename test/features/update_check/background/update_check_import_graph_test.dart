import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// SE-41 T4a AC4: the Android minimal engine's import graph. It may reach only
// update_check, path_provider, pinenacl, the notification helper and the l10n
// lookup. No Go bridge, SQLCipher, bootstrap or Firebase.

const _entry =
    'lib/features/update_check/background/update_check_minimal_entrypoint.dart';

final _import = RegExp(
  r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''',
  multiLine: true,
);

/// Every app file and external package the entry reaches, transitively.
({Set<String> appFiles, Set<String> packages}) _graph(String entry) {
  final appFiles = <String>{};
  final packages = <String>{};
  final queue = [entry];
  while (queue.isNotEmpty) {
    final path = queue.removeLast();
    if (!appFiles.add(path)) continue;
    final source = File(path).readAsStringSync();
    for (final match in _import.allMatches(source)) {
      final uri = match.group(1)!;
      if (uri.startsWith('dart:')) {
        packages.add(uri);
      } else if (uri.startsWith('package:flutter_app/')) {
        queue.add('lib/${uri.substring('package:flutter_app/'.length)}');
      } else if (uri.startsWith('package:')) {
        packages.add(uri.substring('package:'.length).split('/').first);
      } else {
        queue.add(File(path).parent.uri.resolve(uri).path);
      }
    }
  }
  return (appFiles: appFiles, packages: packages);
}

void main() {
  test('the minimal entry imports only the allowed graph', () {
    final graph = _graph(_entry);
    // Printed for the T4a evidence.
    // ignore: avoid_print
    print(
      'IMPORT GRAPH $_entry\n'
      'app files (${graph.appFiles.length}):\n  '
      '${(graph.appFiles.toList()..sort()).join('\n  ')}\n'
      'packages and SDK libraries (${graph.packages.length}):\n  '
      '${(graph.packages.toList()..sort()).join('\n  ')}',
    );

    for (final file in graph.appFiles) {
      final allowed =
          (file.startsWith('lib/features/update_check/') &&
              !file.startsWith('lib/features/update_check/presentation/') &&
              file !=
                  'lib/features/update_check/background/update_check_background_host.dart') ||
          file.startsWith('lib/l10n/') ||
          // The shared l10n lookup without a widget tree (no other imports).
          file == 'lib/features/push/application/notification_preview_copy.dart';
      expect(allowed, isTrue, reason: '$file is outside the allowed graph');
    }

    const allowedPackages = {
      'flutter',
      'path_provider',
      'pinenacl',
      // T1: UpdateCheckService's default build-number reader. The minimal
      // engine passes the build number in, so the plugin is never called.
      'package_info_plus',
      // Generated l10n.
      'intl',
      'flutter_localizations',
    };
    for (final package in graph.packages) {
      if (package.startsWith('dart:')) {
        expect(
          package,
          isNot(anyOf('dart:ffi', 'dart:mirrors')),
          reason: 'no native bindings',
        );
        continue;
      }
      expect(allowedPackages, contains(package), reason: package);
    }

    final everything = [...graph.appFiles, ...graph.packages].join('\n');
    for (final forbidden in [
      'go_bridge',
      'sqflite',
      'sqlcipher',
      'firebase',
      'bootstrap',
      'canonical_runtime_lease',
      'flutter_secure_storage',
      'flutter_local_notifications',
    ]) {
      expect(everything, isNot(contains(forbidden)), reason: forbidden);
    }
  });

  test('main.dart exposes the entry point with the name the worker starts', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect(
      main,
      contains(
        "@pragma('vm:entry-point')\n"
        'Future<void> androidUpdateCheckMinimalMain(',
      ),
    );
    final worker = File(
      'android/app/src/main/kotlin/com/mknoon/app/UpdateCheckBackgroundWork.kt',
    ).readAsStringSync();
    expect(worker, contains('"androidUpdateCheckMinimalMain"'));
  });
}
