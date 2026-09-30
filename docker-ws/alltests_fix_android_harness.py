"""(A) group media fixture: a slow fresh-install first frame (am start -W 'Status: timeout') is still a started launch
when the output names the exact component and the process exists; the nonce-bound endpoint result stays the proof.
(B) Android payload warm leg: arm the post-tap observer while the receiver is provably awake (right after the push);
the relay-journal provider check (evidence only, same sentAt window) now runs after arming, because Android's
cached-apps freezer can pause the backgrounded receiver during the ~70 s SSH journal poll. [roots...]"""
import pathlib, sys
A_REL = 'integration_test/scripts/group_media_ios_fixture_driver.dart'
A_OLD = """    if (result.exitCode != 0 || !'${result.stdout}'.contains('Status: ok')) {
      throw const _Failure('Android sender launch failed');
    }
  }
"""
A_NEW = """    final launchOutput = '${result.stdout}';
    if (result.exitCode != 0 || launchOutput.contains('Error:')) {
      throw const _Failure('Android sender launch failed');
    }
    if (!launchOutput.contains('Status: ok')) {
      // A fresh install can draw its first frame after am start's 10 s
      // window. A timeout still counts as started only for the exact
      // component with a live process; the endpoint result remains the proof.
      final pid = await _run('adb', <String>[
        '-s',
        options.senderDevice,
        'shell',
        'pidof',
        _packageName,
      ]);
      if (!launchOutput.contains('Status: timeout') ||
          !launchOutput.contains(component) ||
          pid.exitCode != 0 ||
          '${pid.stdout}'.trim().isEmpty) {
        throw const _Failure('Android sender launch failed');
      }
    }
  }
"""
B_REL = 'integration_test/scripts/notification_android_payload_campaign.dart'
B_OLD1 = """    await _waitForProviderSend(sentAt);
    final staged = await _waitForStagedEnvelope(sent: sent, notBefore: sentAt);
    final warmObservation = await _waitForNotificationObservation(marker);
"""
B_NEW1 = """    // Arm the post-tap observer while the push has just woken the receiver;
    // the relay-journal provider check below is evidence only and can run
    // after arming. The cached-apps freezer can pause a backgrounded receiver
    // during that long journal poll, and a frozen process never arms.
    final staged = await _waitForStagedEnvelope(sent: sent, notBefore: sentAt);
    final warmObservation = await _waitForNotificationObservation(marker);
"""
B_OLD2 = """    final armed = await _waitForActionResult(
      emulator,
      observer,
      status: 'armed',
      timeout: const Duration(seconds: 30),
    );
    if (armed['stagedEnvelopeObserved'] != true) {
      throw _Failure(
        'Warm FCM staging was not observed before the tap.',"""
B_NEW2 = """    final armed = await _waitForActionResult(
      emulator,
      observer,
      status: 'armed',
      timeout: const Duration(seconds: 30),
    );
    await _waitForProviderSend(sentAt);
    if (armed['stagedEnvelopeObserved'] != true) {
      throw _Failure(
        'Warm FCM staging was not observed before the tap.',"""
for root in (sys.argv[1:] or ['/Volumes/CrucialX9/flutter_app', '/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree']):
    for rel, pairs in ((A_REL, [(A_OLD, A_NEW)]), (B_REL, [(B_OLD1, B_NEW1), (B_OLD2, B_NEW2)])):
        p = pathlib.Path(root, rel); s = p.read_text()
        for old, new in pairs:
            if new in s: continue
            assert s.count(old) == 1, (root, rel, old[:50]); s = s.replace(old, new)
        p.write_text(s)
    print('patched', root)
