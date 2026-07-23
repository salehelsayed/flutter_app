import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/android_app_state_guard.dart';

void main() {
  test('system host runner concurrently drains both large pipes', () async {
    final root = await Directory.systemTemp.createTemp(
      'state-guard-runner-pipes-',
    );
    addTearDown(() async {
      if (root.existsSync()) await root.delete(recursive: true);
    });
    final script = File('${root.path}/large_pipes.dart')
      ..writeAsStringSync(r'''
import 'dart:io';

Future<void> main() async {
  final stdoutChunk = List<int>.filled(8192, 0x4f);
  final stderrChunk = List<int>.filled(8192, 0x45);
  for (var index = 0; index < 128; index += 1) {
    stdout.add(stdoutChunk);
    stderr.add(stderrChunk);
  }
  await stdout.flush();
  await stderr.flush();
}
''', flush: true);
    final runner = SystemAndroidHostProcessRunner(
      commandTimeout: const Duration(seconds: 20),
      terminationGrace: const Duration(seconds: 2),
    );

    final result = await runner.run(_fixtureDartExecutable(), <String>[
      script.path,
    ]);

    expect(result.exitCode, 0);
    expect((result.stdout as String).length, 128 * 8192);
    expect((result.stderr as String).length, 128 * 8192);
  });

  test('system host runner deadline includes inherited pipe closure', () async {
    if (Platform.isWindows) return;
    final root = await Directory.systemTemp.createTemp(
      'state-guard-runner-retained-pipe-',
    );
    addTearDown(() async {
      if (root.existsSync()) await root.delete(recursive: true);
    });
    final childPidFile = File('${root.path}/child-pid');
    final childScript = File('${root.path}/pipe_child.dart')
      ..writeAsStringSync(r'''
import 'dart:async';

Future<void> main() => Future<void>.delayed(const Duration(seconds: 30));
''', flush: true);
    final parentScript = File('${root.path}/pipe_parent.dart')
      ..writeAsStringSync(r'''
import 'dart:io';

Future<void> main(List<String> arguments) async {
  final child = await Process.start(
    arguments[1],
    <String>[arguments[2]],
    mode: ProcessStartMode.inheritStdio,
    runInShell: false,
  );
  File(arguments.first).writeAsStringSync('${child.pid}\n', flush: true);
}
''', flush: true);
    final runner = SystemAndroidHostProcessRunner(
      commandTimeout: const Duration(seconds: 1),
      terminationGrace: const Duration(milliseconds: 300),
    );
    final stopwatch = Stopwatch()..start();
    ProcessException? failure;
    int? childPid;
    try {
      await runner.run(_fixtureDartExecutable(), <String>[
        parentScript.path,
        childPidFile.path,
        _fixtureDartExecutable(),
        childScript.path,
      ]);
    } on ProcessException catch (error) {
      failure = error;
    } finally {
      childPid = await _waitForFixturePid(childPidFile);
      Process.killPid(childPid, ProcessSignal.sigkill);
      await _waitForProcessToDisappear(childPid);
    }
    stopwatch.stop();

    expect(failure, isNotNull);
    expect(failure!.errorCode, 124);
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
  });

  test('system host runner times out kills reaps and redacts', () async {
    if (Platform.isWindows) return;
    final root = await Directory.systemTemp.createTemp(
      'state-guard-runner-timeout-',
    );
    addTearDown(() async {
      if (root.existsSync()) await root.delete(recursive: true);
    });
    final pidFile = File('${root.path}/pid');
    final script = File('${root.path}/hang.dart')
      ..writeAsStringSync(r'''
import 'dart:async';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  ProcessSignal.sigterm.watch().listen((_) {});
  File(arguments.first).writeAsStringSync('$pid\n', flush: true);
  stdout.write('private-timeout-stdout');
  stderr.write('private-timeout-stderr');
  await stdout.flush();
  await stderr.flush();
  await Completer<void>().future;
}
''', flush: true);
    final runner = SystemAndroidHostProcessRunner(
      commandTimeout: const Duration(seconds: 1),
      terminationGrace: const Duration(milliseconds: 300),
    );
    final stopwatch = Stopwatch()..start();
    late final ProcessException failure;

    try {
      await runner.run(_fixtureDartExecutable(), <String>[
        script.path,
        pidFile.path,
        'private-timeout-argument',
      ]);
      fail('hanging command unexpectedly completed');
    } on ProcessException catch (error) {
      failure = error;
    }
    stopwatch.stop();

    expect(failure.errorCode, 124);
    expect(failure.arguments, isEmpty);
    expect('$failure', isNot(contains('private-timeout-argument')));
    expect('$failure', isNot(contains('private-timeout-stdout')));
    expect('$failure', isNot(contains('private-timeout-stderr')));
    expect(stopwatch.elapsed, lessThan(const Duration(seconds: 5)));
    final childPid = await _waitForFixturePid(pidFile);
    expect(await _waitForProcessToDisappear(childPid), isTrue);
  });

  test('system host runner rejects a nonpositive timeout', () async {
    const runner = SystemAndroidHostProcessRunner(
      commandTimeout: Duration.zero,
    );

    await expectLater(
      runner.run(_fixtureDartExecutable(), const <String>['--version']),
      throwsArgumentError,
    );
  });

  test('pure restore policy protects installed-app Keystore state', () {
    expect(
      androidPackageRestoreAction(
        originallyInstalled: false,
        currentlyInstalled: true,
      ),
      AndroidPackageRestoreAction.uninstallTestInstall,
    );
    expect(
      androidPackageRestoreAction(
        originallyInstalled: true,
        currentlyInstalled: true,
      ),
      AndroidPackageRestoreAction.reinstallOriginalInPlace,
    );
    expect(
      androidPackageRestoreAction(
        originallyInstalled: true,
        currentlyInstalled: false,
      ),
      AndroidPackageRestoreAction.failKeystoreAlreadyLost,
    );
  });

  test(
    'prepared APK identity is proven before capture mutates process',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'state-guard-capture-preflight-',
      );
      addTearDown(() async {
        if (root.existsSync()) await root.delete(recursive: true);
      });
      final artifact = File('${root.path}/candidate.apk')
        ..writeAsBytesSync(<int>[9, 8, 7, 6], flush: true);
      final adb = _FakeAdbState.installed(
        apkBytes: <List<int>>[
          <int>[1, 2, 3, 4],
        ],
        permissions: const <String, bool>{},
        running: true,
        foreground: true,
        preparedArtifactPackageName: 'org.example.unexpected',
      );

      await expectLater(
        AndroidAppStateGuard.capture(
          devices: const <String>['physical-1'],
          packageName: _packageName,
          backupLabel: 'capture-preflight-test',
          preparedArtifact: artifact,
          expectedArtifactSha256: sha256
              .convert(artifact.readAsBytesSync())
              .toString(),
          runner: adb,
        ),
        throwsA(isA<AndroidAppStateFailure>()),
      );

      expect(adb.commands, hasLength(1));
      expect(adb.commands.single, contains('apkanalyzer'));
      expect(adb.commands.single, isNot(contains('adb ')));
      expect(adb.running, isTrue);
      expect(adb.foreground, isTrue);
    },
  );

  test(
    'private archive stream timeout kills child and removes partial backup',
    () async {
      if (Platform.isWindows) return;
      final root = await Directory.systemTemp.createTemp(
        'state-guard-archive-timeout-',
      );
      addTearDown(() async {
        if (root.existsSync()) await root.delete(recursive: true);
      });
      final pidFile = File('${root.path}/pid');
      final script = File('${root.path}/archive_hang.dart')
        ..writeAsStringSync(r'''
import 'dart:async';
import 'dart:io';

Future<void> main(List<String> arguments) async {
  ProcessSignal.sigterm.watch().listen((_) {});
  File(arguments.first).writeAsStringSync('$pid\n', flush: true);
  stdout.add(List<int>.filled(16384, 0x50));
  stderr.write('private-archive-stderr');
  await stdout.flush();
  await stderr.flush();
  await Completer<void>().future;
}
''', flush: true);
      final label = 'archive-timeout-${DateTime.now().microsecondsSinceEpoch}';
      final adb = _FakeAdbState.installed(
        apkBytes: <List<int>>[
          <int>[1, 2, 3, 4],
        ],
        permissions: const <String, bool>{},
        privateEntries: const <String>{'files'},
      );
      late final AndroidAppStateBlocked failure;

      try {
        await AndroidAppStateGuard.capture(
          devices: const <String>['physical-1'],
          packageName: _packageName,
          backupLabel: label,
          runner: adb,
          privateArchiveProcessStarter: (_, _) => Process.start(
            _fixtureDartExecutable(),
            <String>[script.path, pidFile.path],
            runInShell: false,
          ),
          privateArchiveTimeout: const Duration(seconds: 1),
          processTerminationGrace: const Duration(milliseconds: 300),
        );
        fail('hanging archive stream unexpectedly completed');
      } on AndroidAppStateBlocked catch (error) {
        failure = error;
      }

      expect('$failure', contains('timed out'));
      expect('$failure', isNot(contains('private-archive-stderr')));
      expect('$failure', isNot(contains(script.path)));
      final childPid = await _waitForFixturePid(pidFile);
      expect(await _waitForProcessToDisappear(childPid), isTrue);
      final backupPrefix = 'mknoon-$label-state-';
      final survivors = Directory.systemTemp
          .listSync(followLinks: false)
          .where(
            (entity) => entity.path
                .split(Platform.pathSeparator)
                .last
                .startsWith(backupPrefix),
          )
          .toList(growable: false);
      expect(survivors, isEmpty);
    },
  );

  test(
    'originally absent package may uninstall only its test install',
    () async {
      final root = await Directory.systemTemp.createTemp('state-guard-absent-');
      addTearDown(() async {
        if (root.existsSync()) await root.delete(recursive: true);
      });
      final artifact = File('${root.path}/candidate.apk')
        ..writeAsBytesSync(<int>[1, 2, 3, 4], flush: true);
      final adb = _FakeAdbState.absent();

      final guard = await AndroidAppStateGuard.capture(
        devices: const <String>['physical-1'],
        packageName: _packageName,
        backupLabel: 'absent-test',
        runner: adb,
      );
      await guard.prepareFreshInstall(device: 'physical-1', artifact: artifact);
      final recovery = await AndroidAppStateGuard.loadRecovery(
        backupDirectory: guard.backupDirectory,
        runner: adb,
      );
      await recovery.restoreAll();

      expect(recovery.restored, isTrue);
      expect(adb.installed, isFalse);
      expect(
        adb.commands.where((command) => command.contains('uninstall')),
        hasLength(1),
      );
      expect(adb.commands.join('\n'), isNot(contains(' pm clear ')));
    },
  );

  test(
    'exact central APK is reused between fresh scenarios without reinstall',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'state-guard-reuse-central-',
      );
      addTearDown(() async {
        if (root.existsSync()) await root.delete(recursive: true);
      });
      final artifact = File('${root.path}/candidate.apk')
        ..writeAsBytesSync(<int>[9, 8, 7, 6], flush: true);
      final adb = _FakeAdbState.absent();

      final guard = await AndroidAppStateGuard.capture(
        devices: const <String>['physical-1'],
        packageName: _packageName,
        backupLabel: 'reuse-central-test',
        runner: adb,
      );
      await guard.prepareFreshInstall(device: 'physical-1', artifact: artifact);
      await guard.prepareFreshInstall(device: 'physical-1', artifact: artifact);

      final centralInstalls = adb.commands
          .where(
            (command) =>
                command.contains(' install -r -d -t ') &&
                command.contains(artifact.path),
          )
          .toList(growable: false);
      expect(centralInstalls, hasLength(1));
      expect(
        adb.commands.where(
          (command) => command.contains('shell sha256sum /data/app/'),
        ),
        isNotEmpty,
      );

      await guard.restoreAll();
      expect(guard.restored, isTrue);
      expect(adb.installed, isFalse);
    },
  );

  test(
    'prepared APK package mismatch is red before install mutation',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'state-guard-package-mismatch-',
      );
      addTearDown(() async {
        if (root.existsSync()) await root.delete(recursive: true);
      });
      final artifact = File('${root.path}/candidate.apk')
        ..writeAsBytesSync(<int>[9, 8, 7, 6], flush: true);
      final original = <List<int>>[
        <int>[1, 2, 3, 4],
      ];
      final adb = _FakeAdbState.installed(
        apkBytes: original,
        permissions: const <String, bool>{},
        preparedArtifactPackageName: 'org.example.unexpected',
      );
      final guard = await AndroidAppStateGuard.capture(
        devices: const <String>['physical-1'],
        packageName: _packageName,
        backupLabel: 'package-mismatch-test',
        runner: adb,
      );
      final commandCountBeforePreparation = adb.commands.length;

      await expectLater(
        guard.prepareFreshInstall(
          device: 'physical-1',
          artifact: artifact,
          expectedArtifactSha256: sha256
              .convert(artifact.readAsBytesSync())
              .toString(),
        ),
        throwsA(isA<AndroidAppStateFailure>()),
      );

      final preparationCommands = adb.commands.skip(
        commandCountBeforePreparation,
      );
      expect(preparationCommands, hasLength(1));
      expect(preparationCommands.single, contains('apkanalyzer'));
      expect(preparationCommands.join('\n'), isNot(contains(' install ')));
      expect(preparationCommands.join('\n'), isNot(contains('force-stop')));
      expect(adb.apkBytes, original);
      expect(adb.additionalInstalledPackages, isEmpty);

      await guard.restoreAll();
      expect(guard.restored, isTrue);
    },
  );

  test(
    'matching base plus stale split is replaced by the single prepared APK',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'state-guard-stale-split-',
      );
      addTearDown(() async {
        if (root.existsSync()) await root.delete(recursive: true);
      });
      final preparedBytes = <int>[9, 8, 7, 6];
      final artifact = File('${root.path}/candidate.apk')
        ..writeAsBytesSync(preparedBytes, flush: true);
      final original = <List<int>>[
        List<int>.from(preparedBytes),
        <int>[4, 3, 2, 1],
      ];
      final adb = _FakeAdbState.installed(
        apkBytes: original,
        permissions: const <String, bool>{},
      );
      final guard = await AndroidAppStateGuard.capture(
        devices: const <String>['physical-1'],
        packageName: _packageName,
        backupLabel: 'stale-split-test',
        runner: adb,
      );

      await guard.prepareFreshInstall(
        device: 'physical-1',
        artifact: artifact,
        expectedArtifactSha256: sha256.convert(preparedBytes).toString(),
      );

      expect(adb.apkBytes, <List<int>>[preparedBytes]);
      expect(
        adb.commands.where(
          (command) =>
              command.contains(' install -r -d -t ') &&
              command.contains(artifact.path),
        ),
        hasLength(1),
      );

      await guard.restoreAll();
      expect(adb.apkBytes, original);
    },
  );

  test(
    'old expected app cannot false-green and introduced package is restored',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'state-guard-old-app-',
      );
      addTearDown(() async {
        if (root.existsSync()) await root.delete(recursive: true);
      });
      final artifact = File('${root.path}/candidate.apk')
        ..writeAsBytesSync(<int>[9, 8, 7, 6], flush: true);
      final original = <List<int>>[
        <int>[1, 2, 3, 4],
      ];
      final adb = _FakeAdbState.installed(
        apkBytes: original,
        permissions: const <String, bool>{},
        centralInstallLeavesExpectedBytes: true,
        centralInstallExtraPackage: 'org.example.unexpected',
      );
      final guard = await AndroidAppStateGuard.capture(
        devices: const <String>['physical-1'],
        packageName: _packageName,
        backupLabel: 'old-app-test',
        runner: adb,
      );

      await expectLater(
        guard.prepareFreshInstall(
          device: 'physical-1',
          artifact: artifact,
          expectedArtifactSha256: sha256
              .convert(artifact.readAsBytesSync())
              .toString(),
        ),
        throwsA(isA<AndroidAppStateFailure>()),
      );
      expect(adb.apkBytes, original);
      expect(
        adb.additionalInstalledPackages,
        contains('org.example.unexpected'),
      );

      await guard.restoreAll();

      expect(guard.restored, isTrue);
      expect(adb.apkBytes, original);
      expect(adb.additionalInstalledPackages, isEmpty);
      expect(
        adb.commands,
        contains(contains('uninstall org.example.unexpected')),
      );
    },
  );

  test('prepared artifact expected SHA drift is red before mutation', () async {
    final root = await Directory.systemTemp.createTemp(
      'state-guard-sha-drift-',
    );
    addTearDown(() async {
      if (root.existsSync()) await root.delete(recursive: true);
    });
    final artifact = File('${root.path}/candidate.apk')
      ..writeAsBytesSync(<int>[9, 8, 7, 6], flush: true);
    final adb = _FakeAdbState.absent();
    final guard = await AndroidAppStateGuard.capture(
      devices: const <String>['physical-1'],
      packageName: _packageName,
      backupLabel: 'sha-drift-test',
      runner: adb,
    );
    final commandCountBeforePreparation = adb.commands.length;

    await expectLater(
      guard.prepareFreshInstall(
        device: 'physical-1',
        artifact: artifact,
        expectedArtifactSha256: List<String>.filled(64, 'a').join(),
      ),
      throwsA(isA<AndroidAppStateFailure>()),
    );

    expect(adb.commands, hasLength(commandCountBeforePreparation));
    expect(adb.installed, isFalse);
    await guard.restoreAll();
  });

  test(
    'installed split APKs, permissions, and background process restore in place',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'state-guard-installed-',
      );
      addTearDown(() async {
        if (root.existsSync()) await root.delete(recursive: true);
      });
      final artifact = File('${root.path}/candidate.apk')
        ..writeAsBytesSync(<int>[9, 9, 9], flush: true);
      final originalApks = <List<int>>[
        <int>[1, 3, 5, 7],
        <int>[2, 4, 6, 8],
      ];
      final adb = _FakeAdbState.installed(
        apkBytes: originalApks,
        running: true,
        foreground: false,
        permissions: <String, bool>{
          'android.permission.RECORD_AUDIO': true,
          'android.permission.POST_NOTIFICATIONS': false,
        },
      );

      final guard = await AndroidAppStateGuard.capture(
        devices: const <String>['physical-1'],
        packageName: _packageName,
        backupLabel: 'installed-test',
        runner: adb,
      );
      await guard.prepareFreshInstall(device: 'physical-1', artifact: artifact);
      expect(adb.apkBytes, <List<int>>[
        <int>[9, 9, 9],
      ]);

      await guard.restoreAll();

      expect(adb.apkBytes, originalApks);
      expect(adb.permissions['android.permission.RECORD_AUDIO'], isTrue);
      expect(adb.permissions['android.permission.POST_NOTIFICATIONS'], isFalse);
      expect(adb.running, isTrue);
      expect(adb.foreground, isFalse);
      expect(adb.commands.join('\n'), contains('install-multiple -r -d -t'));
      expect(adb.commands.join('\n'), contains('shell pm grant'));
      expect(adb.commands.join('\n'), contains('shell pm revoke'));
      expect(adb.commands.join('\n'), contains('KEYCODE_HOME'));
      expect(adb.commands.join('\n'), isNot(contains('uninstall')));
      expect(adb.commands.join('\n'), isNot(contains(' pm clear ')));
    },
  );

  test(
    'private restore preserves installer-owned cache roots and their metadata',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'state-guard-private-',
      );
      addTearDown(() async {
        if (root.existsSync()) await root.delete(recursive: true);
      });
      final artifact = File('${root.path}/candidate.apk')
        ..writeAsBytesSync(<int>[9, 9, 9], flush: true);
      final adb = _FakeAdbState.installed(
        apkBytes: <List<int>>[
          <int>[1, 3, 5, 7],
        ],
        permissions: const <String, bool>{},
        privateEntries: const <String>{'cache', 'code_cache', 'files'},
        codeCacheNonEmpty: true,
      );

      final guard = await AndroidAppStateGuard.capture(
        devices: const <String>['physical-1'],
        packageName: _packageName,
        backupLabel: 'private-test',
        runner: adb,
        privateArchiveCapturer: (_, _, entries, destination) async {
          expect(entries, <String>['cache', 'code_cache', 'files']);
          _writePrivateTarFixture(
            destination,
            entries,
            privilegedCacheDirectories: true,
            includeNestedCodeCacheDirectory: true,
          );
        },
      );
      await guard.prepareFreshInstall(device: 'physical-1', artifact: artifact);

      await guard.restoreAll();

      expect(guard.restored, isTrue);
      expect(adb.privateEntries, <String>{'cache', 'code_cache', 'files'});
      expect(adb.cacheMetadataExact, isTrue);
      expect(adb.originalInstallCount, 1);
      final extract = adb.commands.indexWhere(
        (command) => command.contains(' tar -xf '),
      );
      final restoreInstall = adb.commands.lastIndexWhere(
        (command) =>
            command.contains(' install -r -d -t ') &&
            command.contains('installed-0.apk'),
      );
      final canonicalVerify = adb.commands.lastIndexWhere(
        (command) =>
            command.contains(' tar -cf ') && command.contains('_verify.tar'),
      );
      expect(extract, greaterThanOrEqualTo(0));
      expect(restoreInstall, lessThan(extract));
      expect(canonicalVerify, greaterThan(extract));
      expect(
        adb.commands,
        contains(
          contains(r'find cache -mindepth 1 -maxdepth 1 -exec rm -rf -- {} \;'),
        ),
      );
      expect(adb.commands.join('\n'), contains(' --null -T '));
      expect(
        adb.commands,
        contains(
          contains(
            r'find code_cache -mindepth 1 -maxdepth 1 -exec rm -rf -- {} \;',
          ),
        ),
      );
      expect(adb.commands.join('\n'), isNot(contains('uninstall')));
      expect(adb.commands.join('\n'), isNot(contains(' pm clear ')));
    },
  );

  test(
    'direct exact private restore skips the post-restore APK reinstall',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'state-guard-direct-private-',
      );
      addTearDown(() async {
        if (root.existsSync()) await root.delete(recursive: true);
      });
      final artifact = File('${root.path}/candidate.apk')
        ..writeAsBytesSync(<int>[9, 9, 9], flush: true);
      final adb = _FakeAdbState.installed(
        apkBytes: <List<int>>[
          <int>[1, 3, 5, 7],
        ],
        permissions: const <String, bool>{},
        privateEntries: const <String>{'cache', 'code_cache', 'files'},
        directPrivateRestoreExact: true,
        codeCacheNonEmpty: true,
      );

      final guard = await AndroidAppStateGuard.capture(
        devices: const <String>['physical-1'],
        packageName: _packageName,
        backupLabel: 'direct-private-test',
        runner: adb,
        privateArchiveCapturer: (_, _, _, destination) async {
          _writePrivateTarFixture(destination, const <String>[
            'cache',
            'code_cache',
            'files',
          ]);
        },
      );
      await guard.prepareFreshInstall(device: 'physical-1', artifact: artifact);

      await guard.restoreAll();

      expect(guard.restored, isTrue);
      expect(adb.originalInstallCount, 1);
      expect(adb.codeCacheNonEmpty, isTrue);
      final restoreInstall = adb.commands.lastIndexWhere(
        (command) =>
            command.contains(' install -r -d -t ') &&
            command.contains('installed-0.apk'),
      );
      final extract = adb.commands.indexWhere(
        (command) => command.contains(' tar -xf '),
      );
      final verify = adb.commands.indexWhere(
        (command) =>
            command.contains(' tar -cf ') && command.contains('_verify.tar'),
      );
      expect(restoreInstall, greaterThanOrEqualTo(0));
      expect(extract, greaterThan(restoreInstall));
      expect(verify, greaterThan(extract));
      expect(adb.commands.join('\n'), isNot(contains('uninstall')));
      expect(adb.commands.join('\n'), isNot(contains(' pm clear ')));
    },
  );

  test(
    'mismatched restore repairs metadata then replays nonempty code cache',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'state-guard-code-cache-mismatch-',
      );
      addTearDown(() async {
        if (root.existsSync()) await root.delete(recursive: true);
      });
      final artifact = File('${root.path}/candidate.apk')
        ..writeAsBytesSync(<int>[9, 9, 9], flush: true);
      final adb = _FakeAdbState.installed(
        apkBytes: <List<int>>[
          <int>[1, 3, 5, 7],
        ],
        permissions: const <String, bool>{},
        privateEntries: const <String>{'code_cache', 'files'},
        codeCacheNonEmpty: true,
        privateRestoreMismatchesRemaining: 1,
      );
      final guard = await AndroidAppStateGuard.capture(
        devices: const <String>['physical-1'],
        packageName: _packageName,
        backupLabel: 'code-cache-mismatch-test',
        runner: adb,
        privateArchiveCapturer: (_, _, _, destination) async {
          _writePrivateTarFixture(
            destination,
            const <String>['code_cache', 'files'],
            privilegedCacheDirectories: true,
            includeNestedCodeCacheDirectory: true,
          );
        },
      );
      await guard.prepareFreshInstall(device: 'physical-1', artifact: artifact);

      await guard.restoreAll();

      expect(guard.restored, isTrue);
      expect(guard.backupDirectory.existsSync(), isFalse);
      expect(adb.originalInstallCount, 2);
      expect(adb.codeCacheNonEmpty, isTrue);
      expect(
        adb.commands.where((command) => command.contains(' tar -xf ')),
        hasLength(4),
      );
      expect(adb.commands.join('\n'), isNot(contains('uninstall')));
      expect(adb.commands.join('\n'), isNot(contains(' pm clear ')));
    },
  );

  test(
    'persistent private mismatch fails after replay and retains recovery',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'state-guard-persistent-mismatch-',
      );
      addTearDown(() async {
        if (root.existsSync()) await root.delete(recursive: true);
      });
      final artifact = File('${root.path}/candidate.apk')
        ..writeAsBytesSync(<int>[9, 9, 9], flush: true);
      final adb = _FakeAdbState.installed(
        apkBytes: <List<int>>[
          <int>[1, 3, 5, 7],
        ],
        permissions: const <String, bool>{},
        privateEntries: const <String>{'code_cache', 'files'},
        codeCacheNonEmpty: true,
        forcePrivateRestoreMismatch: true,
      );
      final guard = await AndroidAppStateGuard.capture(
        devices: const <String>['physical-1'],
        packageName: _packageName,
        backupLabel: 'persistent-mismatch-test',
        runner: adb,
        privateArchiveCapturer: (_, _, _, destination) async {
          _writePrivateTarFixture(
            destination,
            const <String>['code_cache', 'files'],
            privilegedCacheDirectories: true,
            includeNestedCodeCacheDirectory: true,
          );
        },
      );
      addTearDown(() async {
        if (guard.backupDirectory.existsSync()) {
          await guard.backupDirectory.delete(recursive: true);
        }
      });
      await guard.prepareFreshInstall(device: 'physical-1', artifact: artifact);

      await expectLater(
        guard.restoreAll(),
        throwsA(isA<AndroidAppStateFailure>()),
      );

      expect(guard.restored, isFalse);
      expect(guard.backupDirectory.existsSync(), isTrue);
      expect(adb.originalInstallCount, 2);
      expect(adb.codeCacheNonEmpty, isTrue);
      expect(
        adb.commands.where((command) => command.contains(' tar -xf ')),
        hasLength(4),
      );
      expect(adb.commands.join('\n'), isNot(contains('uninstall')));
      expect(adb.commands.join('\n'), isNot(contains(' pm clear ')));
    },
  );

  test(
    'retained manifest lets a later process restore every state dimension',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'state-guard-recovery-',
      );
      addTearDown(() async {
        if (root.existsSync()) await root.delete(recursive: true);
      });
      final artifact = File('${root.path}/candidate.apk')
        ..writeAsBytesSync(<int>[9, 9, 9], flush: true);
      final originalApks = <List<int>>[
        <int>[1, 3, 5, 7],
        <int>[2, 4, 6, 8],
      ];
      final originalPermissions = <String, bool>{
        'android.permission.RECORD_AUDIO': true,
        'android.permission.POST_NOTIFICATIONS': false,
      };
      final adb = _FakeAdbState.installed(
        apkBytes: originalApks,
        permissions: originalPermissions,
        privateEntries: const <String>{'cache', 'code_cache', 'files'},
        running: true,
        foreground: true,
      );
      final guard = await AndroidAppStateGuard.capture(
        devices: const <String>['physical-1'],
        packageName: _packageName,
        backupLabel: 'process-loss-test',
        runner: adb,
        privateArchiveCapturer: (_, _, _, destination) async {
          _writePrivateTarFixture(destination, const <String>[
            'cache',
            'code_cache',
            'files',
          ]);
        },
      );
      final backup = guard.backupDirectory;
      addTearDown(() async {
        if (backup.existsSync()) await backup.delete(recursive: true);
      });
      final manifest = File('${backup.path}/recovery-manifest.json');
      final manifestDigest = File('${backup.path}/recovery-manifest.sha256');
      expect(manifest.existsSync(), isTrue);
      expect(manifestDigest.existsSync(), isTrue);
      expect(
        manifestDigest.readAsStringSync().trim(),
        sha256.convert(manifest.readAsBytesSync()).toString(),
      );
      final manifestJson = jsonDecode(manifest.readAsStringSync()) as Map;
      expect(manifestJson['redacted'], isTrue);
      final deviceJson = (manifestJson['devices'] as List).single as Map;
      expect(deviceJson['process'], <String, Object?>{
        'running': true,
        'foreground': true,
      });
      expect(deviceJson['runtimePermissions'], originalPermissions);
      expect((deviceJson['apks'] as List), hasLength(2));
      expect(
        (deviceJson['privateData'] as Map)['sha256'],
        sha256
            .convert(
              File(
                '${backup.path}/physical-1/private-data.tar',
              ).readAsBytesSync(),
            )
            .toString(),
      );

      await guard.prepareFreshInstall(device: 'physical-1', artifact: artifact);
      adb.failOriginalInstall = true;
      await expectLater(
        guard.restoreAll(),
        throwsA(isA<AndroidAppStateFailure>()),
      );
      expect(backup.existsSync(), isTrue);
      expect(adb.apkBytes, <List<int>>[
        <int>[9, 9, 9],
      ]);
      expect(adb.running, isFalse);

      // Simulate a fresh host process with no in-memory snapshot.
      adb.failOriginalInstall = false;
      final recovery = await AndroidAppStateGuard.loadRecovery(
        backupDirectory: backup,
        runner: adb,
      );
      await recovery.restoreAll();

      expect(recovery.restored, isTrue);
      expect(backup.existsSync(), isFalse);
      expect(adb.apkBytes, originalApks);
      expect(adb.privateEntries, <String>{'cache', 'code_cache', 'files'});
      expect(adb.cacheMetadataExact, isTrue);
      expect(adb.permissions, originalPermissions);
      expect(adb.running, isTrue);
      expect(adb.foreground, isTrue);
      expect(adb.commands.join('\n'), isNot(contains('uninstall')));
      expect(adb.commands.join('\n'), isNot(contains(' pm clear ')));
    },
  );

  test('recovery loader rejects artifact drift before ADB mutation', () async {
    final adb = _FakeAdbState.installed(
      apkBytes: <List<int>>[
        <int>[1, 3, 5, 7],
      ],
      permissions: const <String, bool>{},
    );
    final guard = await AndroidAppStateGuard.capture(
      devices: const <String>['physical-1'],
      packageName: _packageName,
      backupLabel: 'attestation-drift-test',
      runner: adb,
    );
    addTearDown(() async {
      if (guard.backupDirectory.existsSync()) {
        await guard.backupDirectory.delete(recursive: true);
      }
    });
    final retainedApk = File(
      '${guard.backupDirectory.path}/physical-1/installed-0.apk',
    )..writeAsBytesSync(<int>[99], mode: FileMode.append, flush: true);
    expect(retainedApk.existsSync(), isTrue);
    final commandsBeforeLoad = adb.commands.length;

    await expectLater(
      AndroidAppStateGuard.loadRecovery(
        backupDirectory: guard.backupDirectory,
        runner: adb,
      ),
      throwsA(isA<AndroidAppStateFailure>()),
    );

    expect(adb.commands, hasLength(commandsBeforeLoad));
    expect(guard.backupDirectory.existsSync(), isTrue);
  });

  test(
    'restore failure retains recovery backup and cannot become PASS',
    () async {
      final root = await Directory.systemTemp.createTemp('state-guard-fail-');
      addTearDown(() async {
        if (root.existsSync()) await root.delete(recursive: true);
      });
      final artifact = File('${root.path}/candidate.apk')
        ..writeAsBytesSync(<int>[7, 7, 7], flush: true);
      final adb = _FakeAdbState.installed(
        apkBytes: <List<int>>[
          <int>[1, 2],
          <int>[3, 4],
        ],
        permissions: const <String, bool>{},
      );
      final guard = await AndroidAppStateGuard.capture(
        devices: const <String>['physical-1'],
        packageName: _packageName,
        backupLabel: 'restore-failure-test',
        runner: adb,
      );
      await guard.prepareFreshInstall(device: 'physical-1', artifact: artifact);
      adb.failOriginalInstall = true;

      await expectLater(
        guard.restoreAll(),
        throwsA(isA<AndroidAppStateFailure>()),
      );
      expect(guard.restored, isFalse);
      expect(guard.backupDirectory.existsSync(), isTrue);
      expect(adb.commands.join('\n'), isNot(contains('uninstall')));
    },
  );

  test('source contract preserves archive and PASS ordering invariants', () {
    final guardSource = File(
      'integration_test/support/android_app_state_guard.dart',
    ).readAsStringSync();
    expect(guardSource, contains("'exec-out',"));
    expect(guardSource, contains("'run-as',"));
    expect(guardSource, contains("'tar',"));
    expect(guardSource, contains("'install-multiple',"));
    expect(guardSource, contains('_restoreRuntimePermissions'));
    expect(guardSource, contains('_restoreProcessState'));
    expect(guardSource, isNot(contains("'clear',")));

    for (final path in const <String>[
      'integration_test/scripts/android_keepalive_drop_campaign.dart',
      'integration_test/scripts/run_connectivity_restore_sims.dart',
      'integration_test/scripts/android_voice_message_device_campaign.dart',
      'integration_test/scripts/android_wake_token_directionality_campaign.dart',
      'integration_test/scripts/run_intro_accept_notification_sims.dart',
      'integration_test/scripts/run_group_reaction_notification_sims.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('AndroidAppStateGuard.capture'), reason: path);
      expect(source, contains('stateGuard.restoreAll()'), reason: path);
      expect(source, isNot(contains("'clear',")), reason: path);
      expect(
        source.indexOf('stateGuard.restoreAll()'),
        lessThan(source.indexOf('writeSimsArtifactEvidenceSync')),
        reason: '$path must restore before writing PASS evidence',
      );
    }

    final dispatcher = File(
      'integration_test/scripts/run_1to1_device_real.dart',
    ).readAsStringSync();
    expect(dispatcher, contains("backupLabel: 'voice-recorder'"));
    expect(dispatcher, contains("backupLabel: 'critical-performance'"));
    expect(dispatcher, contains('_deleteResultEvidence(outcome)'));

    final notification = File(
      'integration_test/scripts/notification_android_payload_campaign.dart',
    ).readAsStringSync();
    expect(notification, contains('AndroidAppStateGuard.capture'));
    expect(notification, contains('appStateGuard.restoreAll'));
    expect(notification, isNot(contains("'clear',")));
    expect(
      notification.indexOf('appStateGuard.restoreAll'),
      lessThan(notification.indexOf('writeSimsArtifactEvidenceSync')),
    );

    for (final child in const <String>[
      'integration_test/scripts/run_intro_accept_notification_android.dart',
      'integration_test/scripts/capture_group_reaction_notification_device.dart',
    ]) {
      expect(
        File(child).readAsStringSync(),
        isNot(contains("'clear',")),
        reason: child,
      );
    }
  });
}

Future<int> _waitForFixturePid(File file) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (file.existsSync()) {
      final value = int.tryParse(file.readAsStringSync().trim());
      if (value != null && value > 0) return value;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  throw StateError('fixture subprocess did not publish its PID');
}

String _fixtureDartExecutable() {
  final binary = Platform.isWindows ? 'dart.exe' : 'dart';
  final candidates = <String>[
    if ((Platform.environment['DART_SDK'] ?? '').isNotEmpty)
      '${Platform.environment['DART_SDK']}${Platform.pathSeparator}bin'
          '${Platform.pathSeparator}$binary',
    if ((Platform.environment['FLUTTER_ROOT'] ?? '').isNotEmpty)
      '${Platform.environment['FLUTTER_ROOT']}${Platform.pathSeparator}bin'
          '${Platform.pathSeparator}cache${Platform.pathSeparator}dart-sdk'
          '${Platform.pathSeparator}bin${Platform.pathSeparator}$binary',
  ];
  var ancestor = File(Platform.resolvedExecutable).parent;
  for (var depth = 0; depth < 10; depth += 1) {
    candidates
      ..add(
        '${ancestor.path}${Platform.pathSeparator}dart-sdk'
        '${Platform.pathSeparator}bin${Platform.pathSeparator}$binary',
      )
      ..add(
        '${ancestor.path}${Platform.pathSeparator}cache'
        '${Platform.pathSeparator}dart-sdk${Platform.pathSeparator}bin'
        '${Platform.pathSeparator}$binary',
      );
    final parent = ancestor.parent;
    if (parent.path == ancestor.path) break;
    ancestor = parent;
  }
  for (final candidate in candidates) {
    if (File(candidate).existsSync()) return candidate;
  }
  return binary;
}

Future<bool> _waitForProcessToDisappear(int processId) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    final probe = await Process.run('ps', <String>[
      '-p',
      '$processId',
      '-o',
      'pid=',
    ], runInShell: false);
    if (probe.exitCode != 0 || '${probe.stdout}'.trim().isEmpty) return true;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return false;
}

const String _packageName = 'com.mknoon.app';

void _writePrivateTarFixture(
  File destination,
  Iterable<String> entries, {
  bool privilegedCacheDirectories = false,
  bool includeNestedCodeCacheDirectory = false,
}) {
  final bytes = <int>[];
  for (final entry in entries) {
    final privileged =
        privilegedCacheDirectories &&
        (entry == 'cache' || entry == 'code_cache');
    bytes.addAll(
      _tarDirectoryHeader(
        entry,
        mode: privileged ? 0x5f9 : 0x1f9,
        uid: 10000,
        gid: privileged ? 20000 : 10000,
        mtimeSeconds: 1700000000,
      ),
    );
    if (entry == 'code_cache' && includeNestedCodeCacheDirectory) {
      final engine = 'code_cache/flutter_engine';
      final engineHash = '$engine/${'a' * 40}';
      final skia = '$engineHash/skia';
      final skiaHash = '$skia/${'b' * 40}';
      for (final directory in <String>[
        engine,
        engineHash,
        skia,
        skiaHash,
        '$skiaHash/sksl',
      ]) {
        bytes.addAll(
          _tarDirectoryRecords(
            directory,
            mode: 0x5f9,
            uid: 10000,
            gid: 20000,
            mtimeSeconds: 1700000001,
          ),
        );
      }
      bytes.addAll(
        _tarFileRecords(
          '$engine/shader.bin',
          <int>[1, 2, 3],
          mode: 0x180,
          uid: 10000,
          gid: 20000,
          mtimeSeconds: 1700000002,
        ),
      );
    }
  }
  bytes.addAll(List<int>.filled(1024, 0));
  destination.writeAsBytesSync(bytes, flush: true);
}

List<int> _tarFileRecords(
  String path,
  List<int> contents, {
  required int mode,
  required int uid,
  required int gid,
  required int mtimeSeconds,
}) {
  final paddedContents = <int>[
    ...contents,
    ...List<int>.filled(
      ((contents.length + 511) ~/ 512) * 512 - contents.length,
      0,
    ),
  ];
  return <int>[
    ..._tarHeader(
      path,
      mode: mode,
      uid: uid,
      gid: gid,
      size: contents.length,
      mtimeSeconds: mtimeSeconds,
      type: 48,
    ),
    ...paddedContents,
  ];
}

List<int> _tarDirectoryHeader(
  String path, {
  required int mode,
  required int uid,
  required int gid,
  required int mtimeSeconds,
}) => _tarHeader(
  path,
  mode: mode,
  uid: uid,
  gid: gid,
  size: 0,
  mtimeSeconds: mtimeSeconds,
  type: 53,
);

List<int> _tarDirectoryRecords(
  String path, {
  required int mode,
  required int uid,
  required int gid,
  required int mtimeSeconds,
}) {
  if (ascii.encode(path).length <= 100) {
    return _tarDirectoryHeader(
      path,
      mode: mode,
      uid: uid,
      gid: gid,
      mtimeSeconds: mtimeSeconds,
    );
  }
  final longPath = <int>[...utf8.encode(path), 0];
  final paddedPath = <int>[
    ...longPath,
    ...List<int>.filled(
      ((longPath.length + 511) ~/ 512) * 512 - longPath.length,
      0,
    ),
  ];
  return <int>[
    ..._tarHeader(
      '././@LongLink',
      mode: 0x1a4,
      uid: 0,
      gid: 0,
      size: longPath.length,
      mtimeSeconds: mtimeSeconds,
      type: 76,
    ),
    ...paddedPath,
    ..._tarDirectoryHeader(
      path.substring(path.length - 100),
      mode: mode,
      uid: uid,
      gid: gid,
      mtimeSeconds: mtimeSeconds,
    ),
  ];
}

List<int> _tarHeader(
  String path, {
  required int mode,
  required int uid,
  required int gid,
  required int size,
  required int mtimeSeconds,
  required int type,
}) {
  final header = List<int>.filled(512, 0);
  void writeString(int offset, int length, String value) {
    final encoded = ascii.encode(value);
    if (encoded.length > length) throw StateError('tar fixture field overflow');
    header.setRange(offset, offset + encoded.length, encoded);
  }

  void writeOctal(int offset, int length, int value) {
    writeString(
      offset,
      length,
      '${value.toRadixString(8).padLeft(length - 1, '0')}\u0000',
    );
  }

  writeString(0, 100, path);
  writeOctal(100, 8, mode);
  writeOctal(108, 8, uid);
  writeOctal(116, 8, gid);
  writeOctal(124, 12, size);
  writeOctal(136, 12, mtimeSeconds);
  header.fillRange(148, 156, 0x20);
  header[156] = type;
  writeString(257, 6, 'ustar\u0000');
  writeString(263, 2, '00');
  final checksum = header.fold<int>(0, (sum, byte) => sum + byte);
  writeString(148, 8, '${checksum.toRadixString(8).padLeft(6, '0')}\u0000 ');
  return header;
}

final class _FakeAdbState implements AndroidHostProcessRunner {
  _FakeAdbState.absent()
    : installed = false,
      apkBytes = <List<int>>[],
      permissions = <String, bool>{},
      privateEntries = <String>{},
      preparedArtifactPackageName = _packageName,
      centralInstallLeavesExpectedBytes = false,
      centralInstallExtraPackage = null,
      directPrivateRestoreExact = false,
      forcePrivateRestoreMismatch = false,
      privateRestoreMismatchesRemaining = 0,
      codeCacheNonEmpty = false,
      _capturedCodeCacheNonEmpty = false,
      _capturedPrivateEntries = <String>{};

  _FakeAdbState.installed({
    required List<List<int>> apkBytes,
    required Map<String, bool> permissions,
    Set<String> privateEntries = const <String>{},
    this.directPrivateRestoreExact = false,
    this.forcePrivateRestoreMismatch = false,
    this.privateRestoreMismatchesRemaining = 0,
    this.codeCacheNonEmpty = false,
    this.running = false,
    this.foreground = false,
    this.preparedArtifactPackageName = _packageName,
    this.centralInstallLeavesExpectedBytes = false,
    this.centralInstallExtraPackage,
  }) : installed = true,
       apkBytes = apkBytes.map(List<int>.from).toList(),
       permissions = Map<String, bool>.from(permissions),
       privateEntries = Set<String>.from(privateEntries),
       _capturedCodeCacheNonEmpty = codeCacheNonEmpty,
       _capturedPrivateEntries = Set<String>.from(privateEntries);

  bool installed;
  List<List<int>> apkBytes;
  Map<String, bool> permissions;
  bool running = false;
  bool foreground = false;
  bool failOriginalInstall = false;
  final String preparedArtifactPackageName;
  final bool centralInstallLeavesExpectedBytes;
  final String? centralInstallExtraPackage;
  final Set<String> additionalInstalledPackages = <String>{};
  final bool directPrivateRestoreExact;
  final bool forcePrivateRestoreMismatch;
  int privateRestoreMismatchesRemaining;
  bool codeCacheNonEmpty;
  final bool _capturedCodeCacheNonEmpty;
  Set<String> privateEntries;
  final Set<String> _capturedPrivateEntries;
  bool cacheMetadataExact = true;
  int originalInstallCount = 0;
  String? _stagedArchiveDigest;
  String? _stagedMemberListDigest;
  final List<String> commands = <String>[];
  var _pid = 1;

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    commands.add('$executable ${arguments.join(' ')}');
    if (executable.split(Platform.pathSeparator).last == 'apkanalyzer') {
      if (arguments.length == 3 &&
          arguments[0] == 'manifest' &&
          arguments[1] == 'application-id') {
        return _result(0, '$preparedArtifactPackageName\n', '');
      }
      return _result(1, '', 'unsupported apkanalyzer command');
    }
    final args = arguments.length >= 2 && arguments.first == '-s'
        ? arguments.sublist(2)
        : arguments;
    if (args.isEmpty) return _result(1, '', 'missing command');

    if (args.first == 'install') {
      final source = File(args.last);
      if (!source.existsSync()) return _result(1, '', 'missing apk');
      if (source.path.endsWith('installed-0.apk')) {
        installed = true;
        apkBytes = <List<int>>[source.readAsBytesSync()];
        originalInstallCount += 1;
        cacheMetadataExact = true;
        codeCacheNonEmpty = false;
        privateEntries.addAll(
          _capturedPrivateEntries.where(
            (entry) => entry == 'cache' || entry == 'code_cache',
          ),
        );
      } else {
        if (!centralInstallLeavesExpectedBytes) {
          installed = true;
          apkBytes = <List<int>>[source.readAsBytesSync()];
        }
        final extra = centralInstallExtraPackage;
        if (extra != null) additionalInstalledPackages.add(extra);
        // Campaign permissions intentionally drift; the guard must restore
        // them.
        permissions.updateAll((_, value) => !value);
      }
      return _result(0, 'Success', '');
    }
    if (args.first == 'install-multiple') {
      if (failOriginalInstall) return _result(1, '', 'forced failure');
      final files = args
          .skip(1)
          .where((argument) => !argument.startsWith('-'))
          .map(File.new)
          .toList(growable: false);
      installed = true;
      apkBytes = files.map((file) => file.readAsBytesSync()).toList();
      originalInstallCount += 1;
      cacheMetadataExact = true;
      return _result(0, 'Success', '');
    }
    if (args.first == 'uninstall') {
      if (args.last != _packageName) {
        final removed = additionalInstalledPackages.remove(args.last);
        return _result(removed ? 0 : 1, removed ? 'Success' : '', '');
      }
      installed = false;
      apkBytes = <List<int>>[];
      running = false;
      foreground = false;
      return _result(0, 'Success', '');
    }
    if (args.first == 'pull') {
      final index = _pathIndex(args[1]);
      File(args[2]).writeAsBytesSync(apkBytes[index], flush: true);
      return _result(0, '1 file pulled', '');
    }
    if (args.first == 'push') {
      final digest = sha256.convert(File(args[1]).readAsBytesSync()).toString();
      if (args[2].endsWith('.members')) {
        _stagedMemberListDigest = digest;
      } else {
        _stagedArchiveDigest = digest;
      }
      return _result(0, '1 file pushed', '');
    }
    if (args.first != 'shell') return _result(1, '', 'unsupported');

    final shell = args.sublist(1);
    if (_starts(shell, const <String>['pm', 'list', 'packages', '-3'])) {
      final packages = <String>{
        if (installed) _packageName,
        ...additionalInstalledPackages,
      }.toList()..sort();
      return _result(
        0,
        packages.map((value) => 'package:$value').join('\n'),
        '',
      );
    }
    if (_starts(shell, <String>['pm', 'path', _packageName])) {
      if (!installed) return _result(0, '', '');
      return _result(
        0,
        List<String>.generate(
          apkBytes.length,
          (index) => 'package:${_path(index)}',
        ).join('\n'),
        '',
      );
    }
    if (_starts(shell, <String>['pidof', _packageName])) {
      return _result(0, running ? '4242' : '', '');
    }
    if (_starts(shell, const <String>['dumpsys', 'activity', 'activities'])) {
      return _result(
        0,
        foreground ? 'topResumedActivity=$_packageName/.MainActivity' : '',
        '',
      );
    }
    if (_starts(shell, <String>['dumpsys', 'package', _packageName])) {
      return _result(
        0,
        permissions.entries
            .map((entry) => '${entry.key}: granted=${entry.value}')
            .join('\n'),
        '',
      );
    }
    if (_starts(shell, <String>['am', 'force-stop', _packageName])) {
      running = false;
      foreground = false;
      return _result(0, '', '');
    }
    if (_starts(shell, <String>[
      'am',
      'start',
      '-W',
      '-n',
      '$_packageName/.MainActivity',
    ])) {
      running = true;
      foreground = true;
      return _result(0, 'Status: ok', '');
    }
    if (_starts(shell, const <String>['input', 'keyevent', 'KEYCODE_HOME'])) {
      foreground = false;
      return _result(0, '', '');
    }
    if (shell.length >= 4 && shell[0] == 'pm') {
      final operation = shell[1];
      final permission = shell[3];
      if (operation == 'grant' || operation == 'revoke') {
        permissions[permission] = operation == 'grant';
        return _result(0, '', '');
      }
    }
    if (_starts(shell, <String>['sha256sum'])) {
      final index = _pathIndex(shell[1]);
      return _result(0, '${sha256.convert(apkBytes[index])}  ${shell[1]}', '');
    }
    if (_starts(shell, <String>['run-as', _packageName, 'id'])) {
      return _result(0, 'uid=10000', '');
    }
    if (_starts(shell, <String>[
      'run-as',
      _packageName,
      'ls',
      '-1',
      '-A',
      '.',
    ])) {
      final entries = privateEntries.toList()..sort();
      return _result(0, entries.join('\n'), '');
    }
    if (_starts(shell, <String>[
      'run-as',
      _packageName,
      'ls',
      '-1',
      '-A',
      'code_cache',
    ])) {
      return _result(0, codeCacheNonEmpty ? 'shader-cache' : '', '');
    }
    if (_starts(shell, <String>['run-as', _packageName, 'du', '-sk', '.'])) {
      return _result(0, '${privateEntries.isEmpty ? 0 : 1} .', '');
    }
    if (_starts(shell, <String>['run-as', _packageName, 'cp'])) {
      return _result(0, '', '');
    }
    if (_starts(shell, <String>['run-as', _packageName, 'mkdir', '-m'])) {
      return _result(0, '', '');
    }
    if (_starts(shell, <String>['run-as', _packageName, 'touch', '-m'])) {
      return _result(0, '', '');
    }
    if (_starts(shell, <String>['run-as', _packageName, 'sha256sum'])) {
      final path = shell[3];
      final verificationMismatch =
          path.contains('_verify.tar') &&
          (forcePrivateRestoreMismatch ||
              !cacheMetadataExact ||
              privateRestoreMismatchesRemaining > 0);
      if (path.contains('_verify.tar') &&
          privateRestoreMismatchesRemaining > 0) {
        privateRestoreMismatchesRemaining -= 1;
      }
      final digest = verificationMismatch
          ? sha256.convert(<int>[0]).toString()
          : path.endsWith('.members')
          ? _stagedMemberListDigest
          : _stagedArchiveDigest;
      return _result(0, '$digest  $path', '');
    }
    if (_starts(shell, <String>['run-as', _packageName, 'tar', '-xf'])) {
      privateEntries = Set<String>.from(_capturedPrivateEntries);
      if (shell.contains('-T') || !shell.contains('--exclude')) {
        codeCacheNonEmpty = _capturedCodeCacheNonEmpty;
      }
      // run-as extraction cannot recreate Android's per-app cache gid/setgid.
      cacheMetadataExact = directPrivateRestoreExact || cacheMetadataExact;
      return _result(0, '', '');
    }
    if (_starts(shell, <String>['run-as', _packageName, 'tar', '-cf'])) {
      return _result(0, '', '');
    }
    if (_starts(shell, <String>['run-as', _packageName, 'rm', '-rf', '--'])) {
      final entry = shell.last;
      privateEntries.remove(entry);
      if (entry == 'cache' || entry == 'code_cache') {
        cacheMetadataExact = false;
      }
      return _result(0, '', '');
    }
    if (_starts(shell, <String>['run-as', _packageName, 'test', '-d'])) {
      return _result(privateEntries.contains(shell.last) ? 0 : 1, '', '');
    }
    if (_starts(shell, <String>['run-as', _packageName, 'find'])) {
      if (shell[3] == 'code_cache') codeCacheNonEmpty = false;
      return _result(0, '', '');
    }
    if (_starts(shell, <String>['run-as', _packageName, 'rm', '-f'])) {
      return _result(0, '', '');
    }
    if (_starts(shell, const <String>['rm', '-f'])) {
      return _result(0, '', '');
    }
    return _result(1, '', 'unsupported shell: ${shell.join(' ')}');
  }

  ProcessResult _result(int code, String stdout, String stderr) =>
      ProcessResult(_pid++, code, stdout, stderr);

  String _path(int index) => switch (index) {
    0 => '/data/app/base.apk',
    _ => '/data/app/split-$index.apk',
  };

  int _pathIndex(String path) {
    if (path == '/data/app/base.apk') return 0;
    final match = RegExp(r'/data/app/split-([0-9]+)\.apk$').firstMatch(path);
    if (match == null) throw StateError('unknown fake APK path: $path');
    return int.parse(match.group(1)!);
  }

  bool _starts(List<String> actual, List<String> prefix) {
    if (actual.length < prefix.length) return false;
    for (var index = 0; index < prefix.length; index += 1) {
      if (actual[index] != prefix[index]) return false;
    }
    return true;
  }
}
