"""Plan 397 chat-group path: grant POST_NOTIFICATIONS to the reinstalled Android sender (as the Android-role path
does at _resetAndInstallAndroidRoles) so the OS permission dialog cannot cover the app UI. Both checkouts."""
import pathlib
rel = 'integration_test/scripts/capture_group_reaction_notification_device.dart'
old = """    await _installApk(senderId, _androidBuilds!.normalApk);
    await _clearAndroidPrivateEntries(senderId, _androidBuilds!.normalApk);
    await _startDeviceLogStream(senderId);
"""
new = """    await _installApk(senderId, _androidBuilds!.normalApk);
    await _clearAndroidPrivateEntries(senderId, _androidBuilds!.normalApk);
    // The normal build asks for notification permission on first launch; an
    // unanswered OS dialog covers the fixture UI. Grant it like the Android
    // role path does after install.
    await _grantNotificationPermission(senderId);
    await _startDeviceLogStream(senderId);
"""
for root in ('/Volumes/CrucialX9/flutter_app', '/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree'):
    p = pathlib.Path(root, rel); s = p.read_text()
    if new in s: print('already', root); continue
    assert s.count(old) == 1, root
    p.write_text(s.replace(old, new)); print('patched', root)
