import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

const _hostedArchiveSha256 =
    'ba7733c5514cf0ccb0331997b771a890f73678bcd84cdfb5f7487a88a71f1738';
const _expectHostedSqlCipher = bool.fromEnvironment('EXPECT_HOSTED_SQLCIPHER');
const _patchedTreeSha256 =
    'c4bcb962748f8bd99e4f514e6465003416dd03a502d773f51cf7493d7b763acb';
const _untouchedNonAndroidTreeSha256 =
    '9d99b174eae31ee0d391872f3a959f313cc465b12f7fed3acc71a2c99cd99ac4';
const _patchedFileCount = 171;
const _untouchedNonAndroidFileCount = 148;
const _junitDependencyLine = "    testImplementation 'junit:junit:4.13.2'\n";

const _pinnedForkFileDigests = <String, String>{
  'android/build.gradle':
      'c5538ba79ab511c68dd8189dd14ad15f102fb81e31b0b8a82eaaa29455db12a6',
  'android/src/main/java/com/davidmartos96/sqflite_sqlcipher/'
          'SqfliteSqlCipherPlugin.java':
      '8e3eaf01b834dc23f30917614f04055fecf57ad9b691d9319f161ca49beed8f6',
  'android/src/main/java/com/davidmartos96/sqflite_sqlcipher/Database.java':
      'db801df08a6cf8132ce9fcaded4331c0266b86c79699dd0d6ffaaf5c44b3891f',
  'android/src/main/java/com/davidmartos96/sqflite_sqlcipher/SqlCommand.java':
      'd60687a780f186320fb3030beb43e582087c3b4f9505da2c9e2159c2606c90ce',
  'android/src/main/java/com/davidmartos96/sqflite_sqlcipher/dev/Debug.java':
      '1b9e446b53f51f51a0b265c72d684b11a8880c147e2e138de11b85cf9dbf158f',
  'android/src/main/java/com/davidmartos96/sqflite_sqlcipher/'
          'EngineWorker.java':
      '7eb11ec5587e68f19b45331f17660a214bffc16e57f6d6905440aeb9342c6730',
  'android/src/main/java/com/davidmartos96/sqflite_sqlcipher/'
          'EngineDebugCensus.java':
      '463c05c88110a83436998058ce8f920f1397eb9687efc03b1cd51bf1d55f49d3',
  'android/src/main/java/com/davidmartos96/sqflite_sqlcipher/'
          'EngineState.java':
      '952a623012ff061f793dd95c98c36a3e725e83be4396a56b118d5366dae49c4c',
  'android/src/main/java/com/davidmartos96/sqflite_sqlcipher/'
          'HandlerThreadEngineWorker.java':
      '1a0f20ad67ebf7f4b4418445ff1aa115b75ece861a60055f39a79120d8e56a07',
  'android/src/test/java/com/davidmartos96/sqflite_sqlcipher/'
          'EngineWorkerIsolationTest.java':
      '7ac85f2b2437e9b165bc5971c41af4eafb53c8f7d2d9bfa9e44479af749e315e',
};

void main() {
  final repoRoot = _findRepoRoot();
  final vendorRoot = Directory(
    '${repoRoot.path}/third_party/sqflite_sqlcipher',
  );

  if (_expectHostedSqlCipher) {
    test('rollback resolves the exact hosted sqflite_sqlcipher 3.4.0', () {
      final pubspec = File('${repoRoot.path}/pubspec.yaml').readAsStringSync();
      expect(
        pubspec,
        isNot(
          contains(
            '  sqflite_sqlcipher:\n'
            '    path: third_party/sqflite_sqlcipher',
          ),
        ),
      );

      final lockfile = File('${repoRoot.path}/pubspec.lock').readAsStringSync();
      final lockBlock = _dependencyBlock(lockfile, 'sqflite_sqlcipher');
      expect(lockBlock, contains('dependency: "direct main"'));
      expect(lockBlock, contains('name: sqflite_sqlcipher'));
      expect(lockBlock, contains('sha256: $_hostedArchiveSha256'));
      expect(lockBlock, contains('url: "https://pub.dev"'));
      expect(lockBlock, contains('source: hosted'));
      expect(lockBlock, contains('version: "3.4.0"'));
      expect(lockBlock, isNot(contains('source: path')));

      final packageConfigFile = File(
        '${repoRoot.path}/.dart_tool/package_config.json',
      );
      final packageConfig =
          jsonDecode(packageConfigFile.readAsStringSync())
              as Map<String, Object?>;
      final packages = packageConfig['packages']! as List<Object?>;
      final resolved = packages.cast<Map<String, Object?>>().singleWhere(
        (entry) => entry['name'] == 'sqflite_sqlcipher',
      );
      final resolvedRoot = Directory(
        packageConfigFile.uri
            .resolve(resolved['rootUri']! as String)
            .toFilePath(),
      ).resolveSymbolicLinksSync();
      final hostedPubspec = File(
        '$resolvedRoot/pubspec.yaml',
      ).readAsStringSync();
      expect(hostedPubspec, contains('name: sqflite_sqlcipher'));
      expect(hostedPubspec, contains('version: 3.4.0'));
      final vendoredPath = vendorRoot.existsSync()
          ? vendorRoot.resolveSymbolicLinksSync()
          : vendorRoot.absolute.path;
      expect(resolvedRoot, isNot(vendoredPath));

      final pluginMetadata =
          jsonDecode(
                File(
                  '${repoRoot.path}/.flutter-plugins-dependencies',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      final plugins = pluginMetadata['plugins']! as Map<String, Object?>;
      final androidPlugins = (plugins['android']! as List<Object?>)
          .cast<Map<String, Object?>>();
      final plugin = androidPlugins.singleWhere(
        (entry) => entry['name'] == 'sqflite_sqlcipher',
      );
      final pluginRoot = Directory(
        plugin['path']! as String,
      ).resolveSymbolicLinksSync();
      expect(pluginRoot, resolvedRoot);
    });
    return;
  }

  test(
    'root and generated plugin resolution select the vendored 3.4.0 fork',
    () {
      final pubspec = File('${repoRoot.path}/pubspec.yaml').readAsStringSync();
      expect(
        pubspec,
        contains(
          '  sqflite_sqlcipher:\n'
          '    path: third_party/sqflite_sqlcipher',
        ),
      );

      final lockfile = File('${repoRoot.path}/pubspec.lock').readAsStringSync();
      final lockBlock = _dependencyBlock(lockfile, 'sqflite_sqlcipher');
      expect(lockBlock, contains('dependency: "direct main"'));
      expect(
        lockBlock,
        matches(RegExp(r'path: "?third_party/sqflite_sqlcipher"?')),
      );
      expect(lockBlock, contains('source: path'));
      expect(lockBlock, contains('version: "3.4.0"'));

      final packageConfigFile = File(
        '${repoRoot.path}/.dart_tool/package_config.json',
      );
      final packageConfig =
          jsonDecode(packageConfigFile.readAsStringSync())
              as Map<String, Object?>;
      final packages = packageConfig['packages']! as List<Object?>;
      final resolved = packages.cast<Map<String, Object?>>().singleWhere(
        (entry) => entry['name'] == 'sqflite_sqlcipher',
      );
      final resolvedRoot = Directory(
        packageConfigFile.uri
            .resolve(resolved['rootUri']! as String)
            .toFilePath(),
      ).resolveSymbolicLinksSync();
      expect(resolvedRoot, vendorRoot.resolveSymbolicLinksSync());

      final pluginMetadata =
          jsonDecode(
                File(
                  '${repoRoot.path}/.flutter-plugins-dependencies',
                ).readAsStringSync(),
              )
              as Map<String, Object?>;
      final plugins = pluginMetadata['plugins']! as Map<String, Object?>;
      final androidPlugins = (plugins['android']! as List<Object?>)
          .cast<Map<String, Object?>>();
      final plugin = androidPlugins.singleWhere(
        (entry) => entry['name'] == 'sqflite_sqlcipher',
      );
      final pluginRoot = Directory(
        plugin['path']! as String,
      ).resolveSymbolicLinksSync();
      expect(pluginRoot, vendorRoot.resolveSymbolicLinksSync());
    },
  );

  test('vendor tree equals the exact reviewed Android fork', () {
    final packagePubspec = File(
      '${vendorRoot.path}/pubspec.yaml',
    ).readAsStringSync();
    expect(packagePubspec, contains('version: 3.4.0'));

    final patch = File('${vendorRoot.path}/PATCH.md').readAsStringSync();
    expect(patch, contains(_hostedArchiveSha256));
    expect(patch, contains('engine-owned Android scheduler'));
    expect(patch, isNot(contains('Current boundary: behavior-neutral')));

    final buildGradle = File(
      '${vendorRoot.path}/android/build.gradle',
    ).readAsStringSync();
    expect(
      RegExp(RegExp.escape(_junitDependencyLine)).allMatches(buildGradle),
      hasLength(1),
    );

    final digest = _treeDigest(
      vendorRoot,
      include: (relative) => relative != 'PATCH.md',
    );
    expect(digest.fileCount, _patchedFileCount);
    expect(digest.sha256, _patchedTreeSha256);
  });

  test('patched scheduler files and untouched database have pinned hashes', () {
    for (final entry in _pinnedForkFileDigests.entries) {
      expect(
        _fileDigest(File('${vendorRoot.path}/${entry.key}')),
        entry.value,
        reason: entry.key,
      );
    }
  });

  test(
    'all Dart, iOS, macOS, examples, metadata, and assets stay pristine',
    () {
      final digest = _treeDigest(
        vendorRoot,
        include: (relative) =>
            relative != 'PATCH.md' && !relative.startsWith('android/'),
      );
      expect(digest.fileCount, _untouchedNonAndroidFileCount);
      expect(digest.sha256, _untouchedNonAndroidTreeSha256);
    },
  );
}

Directory _findRepoRoot() {
  var candidate = Directory.current.absolute;
  while (true) {
    if (File('${candidate.path}/pubspec.yaml').existsSync() &&
        File(
          '${candidate.path}/test/core/database/'
          'sqflite_sqlcipher_fork_contract_test.dart',
        ).existsSync()) {
      return candidate;
    }
    final parent = candidate.parent;
    if (parent.path == candidate.path) {
      throw StateError('Could not locate the flutter_app repository root.');
    }
    candidate = parent;
  }
}

String _dependencyBlock(String lockfile, String packageName) {
  final startMarker = '  $packageName:\n';
  final start = lockfile.indexOf(startMarker);
  if (start < 0) throw StateError('$packageName is absent from pubspec.lock');
  final searchStart = start + startMarker.length;
  final next = RegExp(
    r'^  [a-zA-Z0-9_]+:',
    multiLine: true,
  ).firstMatch(lockfile.substring(searchStart));
  return lockfile.substring(
    start,
    next == null ? lockfile.length : searchStart + next.start,
  );
}

({int fileCount, String sha256}) _treeDigest(
  Directory vendorRoot, {
  required bool Function(String relative) include,
}) {
  final files =
      vendorRoot
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .map(
            (file) => (
              file: file,
              relative: file.path
                  .substring(vendorRoot.path.length + 1)
                  .replaceAll('\\', '/'),
            ),
          )
          .where((entry) => include(entry.relative))
          .toList()
        ..sort((left, right) => left.relative.compareTo(right.relative));

  final bytes = BytesBuilder(copy: false);
  for (final entry in files) {
    bytes
      ..add(utf8.encode(entry.relative))
      ..addByte(0)
      ..add(entry.file.readAsBytesSync())
      ..addByte(0);
  }
  return (
    fileCount: files.length,
    sha256: sha256.convert(bytes.takeBytes()).toString(),
  );
}

String _fileDigest(File file) =>
    sha256.convert(file.readAsBytesSync()).toString();
