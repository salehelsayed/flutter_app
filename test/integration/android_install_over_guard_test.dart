import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../integration_test/support/android_app_state_guard.dart';
import '../../integration_test/support/android_install_over_guard.dart';

final class _InstallRunner implements AndroidHostProcessRunner {
  final commands = <List<String>>[];
  int currentVersion = 7, candidateVersion = 7, installExit = 0;
  String package = 'com.example.fixture';
  String paths = 'package:/data/app/fixture/base.apk';

  @override
  Future<ProcessResult> run(String executable, List<String> arguments) async {
    commands.add([executable, ...arguments]);
    var output = '';
    var code = 0;
    if (executable == 'apkanalyzer') {
      output = arguments[1] == 'application-id' ? package : '$candidateVersion';
    } else if (arguments.contains('dumpsys')) {
      output = '  versionCode=$currentVersion minSdk=24';
    } else if (arguments.contains('path')) {
      output = paths;
    } else if (arguments.contains('pull')) {
      File(arguments.last).writeAsStringSync('retained original APK');
    } else if (arguments.contains('install')) {
      code = installExit;
    }
    return ProcessResult(1, code, output, '');
  }
}

void main() {
  late Directory temporary;
  late File candidate;
  late _InstallRunner runner;
  setUp(() {
    temporary = Directory.systemTemp.createTempSync('install-over-contract-');
    candidate = File('${temporary.path}/candidate.apk')
      ..writeAsStringSync('apk');
    runner = _InstallRunner();
  });
  tearDown(() => temporary.deleteSync(recursive: true));

  Future<AndroidInstallOverGuard> capture() => AndroidInstallOverGuard.capture(
    device: 'usb-fixture',
    packageName: 'com.example.fixture',
    candidate: candidate,
    recoveryDirectory: Directory('${temporary.path}/recovery'),
    runner: runner,
  );

  test(
    'install and restoration use exactly -r and preserve recovery APK',
    () async {
      final guard = await capture();
      await guard.install(candidate);
      await guard.restore();
      final installs = runner.commands
          .where((c) => c.contains('install'))
          .toList();
      expect(installs, hasLength(2));
      for (final command in installs) {
        expect(command.take(5), ['adb', '-s', 'usb-fixture', 'install', '-r']);
        expect(command, hasLength(6));
      }
      expect(installs.last.last, guard.originalApk.absolute.path);
      expect(guard.originalApk.existsSync(), isTrue);
      final all = runner.commands.expand((c) => c).toList();
      for (final forbidden in [
        '-d',
        '-t',
        'uninstall',
        'clear',
        'rm',
        'run-as',
      ]) {
        expect(all, isNot(contains(forbidden)));
      }
    },
  );

  for (final installed in [6, 8]) {
    test(
      'version $installed refuses before backup or device mutation',
      () async {
        runner.currentVersion = installed;
        await expectLater(capture(), throwsA(isA<AndroidAppStateBlocked>()));
        expect(
          runner.commands.any(
            (c) => c.contains('pull') || c.contains('install'),
          ),
          isFalse,
        );
        expect(Directory('${temporary.path}/recovery').existsSync(), isFalse);
      },
    );
  }

  for (final paths in ['', 'package:/base.apk\npackage:/split.apk']) {
    test('absent or split app is blocked: $paths', () async {
      runner.paths = paths;
      await expectLater(capture(), throwsA(isA<AndroidAppStateBlocked>()));
      expect(runner.commands.any((c) => c.contains('install')), isFalse);
    });
  }

  test('wrong candidate package is refused before backup', () async {
    runner.package = 'com.example.other';
    await expectLater(capture(), throwsA(isA<AndroidAppStateBlocked>()));
    expect(runner.commands.any((c) => c.contains('pull')), isFalse);
  });

  test(
    'concurrent installed-version change blocks install and restore',
    () async {
      final guard = await capture();
      await guard.install(candidate);
      runner.currentVersion = 8;
      await expectLater(
        guard.restore(),
        throwsA(isA<AndroidAppStateBlocked>()),
      );
      expect(runner.commands.where((c) => c.contains('install')), hasLength(1));
      expect(guard.originalApk.existsSync(), isTrue);
    },
  );

  test(
    'install failure has no destructive retry and retains recovery',
    () async {
      final guard = await capture();
      runner.installExit = 1;
      await expectLater(
        guard.install(candidate),
        throwsA(isA<AndroidAppStateBlocked>()),
      );
      expect(runner.commands.where((c) => c.contains('install')), hasLength(1));
      expect(guard.originalApk.existsSync(), isTrue);
      runner.installExit = 0;
      await guard.restore();
      expect(runner.commands.where((c) => c.contains('install')), hasLength(2));
    },
  );
}
