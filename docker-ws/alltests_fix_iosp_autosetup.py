"""iOS payload driver: every attempt starts from a fresh install (cleanup uninstalls), and the production build only
creates an account through onboarding or Documents/auto_setup.json. Stage auto_setup.json into the app container right
after the verified install so the receiver has an identity, starts its node, and requests notification permission.
[roots...]"""
import pathlib, sys
rel = 'integration_test/scripts/ios_notification_payload_xcui_driver.dart'
old = """    final apps = await _installedApplicationsJson('after-install');
    if (!apps.readAsStringSync().contains(_bundleId)) {
      throw const _DriverBlocked(
        'deviceState',
        'devicectl did not confirm the installed production bundle.',
      );
    }
    _applicationInstalled = true;
  }
"""
new = """    final apps = await _installedApplicationsJson('after-install');
    if (!apps.readAsStringSync().contains(_bundleId)) {
      throw const _DriverBlocked(
        'deviceState',
        'devicectl did not confirm the installed production bundle.',
      );
    }
    _applicationInstalled = true;
    await _stageReceiverAutoSetup();
  }

  /// Cleanup uninstalls the app, so every attempt installs it fresh with no
  /// account. The production build creates one only through onboarding or
  /// Documents/auto_setup.json; without it the node never starts and the
  /// receiver bootstrap can never publish its handoff.
  Future<void> _stageReceiverAutoSetup() async {
    final local = File('${options.captureDirectory.path}/auto_setup.json')
      ..writeAsStringSync('{"username":"SimsPayloadReceiver"}\\n', flush: true);
    final copy = await _runCommand('xcrun', <String>[
      'devicectl',
      'device',
      'copy',
      'to',
      '--device',
      options.receiverDeviceId,
      '--source',
      local.path,
      '--destination',
      'Documents/auto_setup.json',
      '--domain-type',
      'appDataContainer',
      '--domain-identifier',
      _bundleId,
      '--quiet',
    ], timeout: const Duration(minutes: 2));
    if (copy.exitCode != 0) {
      throw _deviceCommandFailure(
        'The receiver auto-setup file could not be staged.',
        copy,
      );
    }
  }
"""
for root in (sys.argv[1:] or ['/Volumes/CrucialX9/flutter_app', '/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree']):
    p = pathlib.Path(root, rel); s = p.read_text()
    if '_stageReceiverAutoSetup' in s: print('already', root); continue
    assert s.count(old) == 1, root; p.write_text(s.replace(old, new)); print('patched', root)
