import 'dart:io';

import 'android_app_state_guard.dart';

/// Install-over admission for a physical phone. This never creates a fresh
/// identity or resets app files. Fresh-fixture campaigns cannot use this guard
/// until their fixture protocol supports the existing application state.
final class AndroidInstallOverGuard {
  AndroidInstallOverGuard._(
    this.device,
    this.packageName,
    this.versionCode,
    this.originalApk,
    this.runner,
  );

  final String device, packageName;
  final int versionCode;
  final File originalApk;
  final AndroidHostProcessRunner runner;
  bool _installed = false;

  static Future<AndroidInstallOverGuard> capture({
    required String device,
    required String packageName,
    required File candidate,
    required Directory recoveryDirectory,
    AndroidHostProcessRunner runner = const SystemAndroidHostProcessRunner(),
  }) async {
    if (!RegExp(r'^[A-Za-z0-9._:-]{1,160}$').hasMatch(device) ||
        !RegExp(r'^[A-Za-z][A-Za-z0-9_.]{2,199}$').hasMatch(packageName) ||
        !candidate.existsSync() ||
        recoveryDirectory.existsSync()) {
      throw const AndroidAppStateBlocked('Invalid install-over admission.');
    }
    Future<String> command(String executable, List<String> arguments) async {
      final result = await runner.run(executable, arguments);
      if (result.exitCode != 0) {
        throw const AndroidAppStateBlocked(
          'Install-over metadata unavailable.',
        );
      }
      return '${result.stdout}'.trim();
    }

    final app = await command('apkanalyzer', [
      'manifest',
      'application-id',
      candidate.absolute.path,
    ]);
    final version = int.tryParse(
      await command('apkanalyzer', [
        'manifest',
        'version-code',
        candidate.absolute.path,
      ]),
    );
    final installed = await command('adb', [
      '-s',
      device,
      'shell',
      'dumpsys',
      'package',
      packageName,
    ]);
    final matches = RegExp(
      r'^\s*versionCode=(\d+)\b',
      multiLine: true,
    ).allMatches(installed).toList();
    final originalVersion = matches.length == 1
        ? int.tryParse(matches.single[1]!)
        : null;
    // An upgrade would require downgrading during exact package restoration.
    // Same-version admission makes both install and restore possible with -r.
    if (app != packageName ||
        version == null ||
        version <= 0 ||
        originalVersion != version) {
      throw const AndroidAppStateBlocked(
        'Candidate and installed version must match for rollback without downgrade.',
      );
    }
    final paths = (await command('adb', [
      '-s',
      device,
      'shell',
      'pm',
      'path',
      packageName,
    ])).split('\n');
    if (paths.length != 1 ||
        !RegExp(r'^package:/[^\r\n]+\.apk$').hasMatch(paths.single)) {
      throw const AndroidAppStateBlocked(
        'Install-over requires one existing base APK; absent/split packages are blocked.',
      );
    }
    await recoveryDirectory.create();
    if (!Platform.isWindows) {
      final mode = await runner.run('chmod', ['700', recoveryDirectory.path]);
      if (mode.exitCode != 0) {
        throw const AndroidAppStateBlocked(
          'Private recovery directory unavailable.',
        );
      }
    }
    final backup = File('${recoveryDirectory.path}/original.apk');
    await command('adb', [
      '-s',
      device,
      'pull',
      paths.single.substring('package:'.length),
      backup.path,
    ]);
    if (!backup.existsSync() || backup.lengthSync() == 0) {
      throw const AndroidAppStateBlocked('Original APK backup unavailable.');
    }
    return AndroidInstallOverGuard._(
      device,
      packageName,
      version,
      backup,
      runner,
    );
  }

  Future<void> install(File artifact) async {
    // Re-read all admission metadata immediately before each mutation, including
    // restore. Never retry an install with -d, uninstall, pm clear, or run-as rm.
    final app = await runner.run('apkanalyzer', [
      'manifest',
      'application-id',
      artifact.absolute.path,
    ]);
    final version = await runner.run('apkanalyzer', [
      'manifest',
      'version-code',
      artifact.absolute.path,
    ]);
    final installed = await runner.run('adb', [
      '-s',
      device,
      'shell',
      'dumpsys',
      'package',
      packageName,
    ]);
    final current = RegExp(
      r'^\s*versionCode=(\d+)\b',
      multiLine: true,
    ).allMatches('${installed.stdout}').toList();
    if (!artifact.existsSync() ||
        app.exitCode != 0 ||
        version.exitCode != 0 ||
        installed.exitCode != 0 ||
        '${app.stdout}'.trim() != packageName ||
        int.tryParse('${version.stdout}'.trim()) != versionCode ||
        current.length != 1 ||
        int.tryParse(current.single[1]!) != versionCode) {
      throw const AndroidAppStateBlocked(
        'Install-over state changed; no install attempted.',
      );
    }
    final result = await runner.run('adb', [
      '-s',
      device,
      'install',
      '-r',
      artifact.absolute.path,
    ]);
    // A nonzero result may still have changed package state: retain the backup
    // and require explicit restoration, using only the same install-over path.
    _installed = true;
    if (result.exitCode != 0) {
      throw const AndroidAppStateBlocked(
        'Install-over failed; recovery APK retained.',
      );
    }
  }

  Future<void> restore() async {
    if (!_installed) return;
    await install(originalApk);
    _installed = false;
    // Keep the exact recovery APK until the caller reviews campaign cleanup.
  }
}
