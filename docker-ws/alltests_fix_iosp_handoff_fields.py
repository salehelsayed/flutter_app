"""iOS payload driver: name WHICH handoff binding fields mismatched (field names only, never values). [roots...]"""
import pathlib, sys
rel = 'integration_test/scripts/ios_notification_payload_xcui_driver.dart'
old = """      throw _DriverFailure(
        'The private receiver handoff is not bound to the exact receiver, '
        'peer, bundle, nonce, authorized alerts and badges, and development APNs '
        'environment.',
        _assertionsAttempted,"""
new = """      // Field names only: the handoff values are private.
      final mismatched = <String>[
        if (handoff.keys.toSet().difference(exactKeys).isNotEmpty ||
            exactKeys.difference(handoff.keys.toSet()).isNotEmpty)
          'keys',
        if (handoff['schema'] != _receiverHandoffSchema) 'schema',
        if (handoff['captureNonce'] != _receiverHandoffNonce) 'captureNonce',
        if (handoff['receiverDeviceId'] != options.receiverDeviceId)
          'receiverDeviceId',
        if (handoff['peerDeviceId'] != options.peerDeviceId) 'peerDeviceId',
        if (handoff['bundleId'] != _bundleId) 'bundleId',
        if (handoff['apnsEnvironment'] != 'development') 'apnsEnvironment',
        if (!const <String>{
          'authorized',
          'provisional',
          'ephemeral',
        }.contains(handoff['notificationAuthorization']))
          'notificationAuthorization',
        if (handoff['notificationAlertSetting'] != 'enabled')
          'notificationAlertSetting',
        if (handoff['notificationBadgeSetting'] != 'enabled')
          'notificationBadgeSetting',
      ];
      throw _DriverFailure(
        'The private receiver handoff is not bound to the exact receiver, '
        'peer, bundle, nonce, authorized alerts and badges, and development APNs '
        'environment (mismatched: ${mismatched.join(', ')}).',
        _assertionsAttempted,"""
for root in (sys.argv[1:] or ['/Volumes/CrucialX9/flutter_app', '/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree']):
    p = pathlib.Path(root, rel); s = p.read_text()
    if '(mismatched: ' in s: print('already', root); continue
    assert s.count(old) == 1, root; p.write_text(s.replace(old, new)); print('patched', root)
