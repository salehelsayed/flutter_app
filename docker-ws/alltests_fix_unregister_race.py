"""TC-393-13 route-absence: the recipient is cold-relaunched right before the authenticated unregister, and its own
startup push registration can land after the unregister and re-create the route. Wait for the relaunched process's
registration to be accepted by the relay before unregistering. Probe assertions unchanged. [roots...]"""
import pathlib, sys
rel = 'integration_test/scripts/capture_1to1_reaction_head_provenance.dart'
old = """    // Clear the final exact card without tapping it, then authenticate removal
    // of the fresh recipient route while that identity is still active.
    await _launch(recipientId);
    await _openConversation(recipient, sender.username);
    await _waitForZeroAppCards('transition B exact-chat retirement');
"""
new = """    // Clear the final exact card without tapping it, then authenticate removal
    // of the fresh recipient route while that identity is still active.
    // The relaunched process registers its push route on startup; let that
    // registration land first so it cannot re-create the route after the
    // unregister below.
    await _adb(recipientId, const <String>['logcat', '-c']);
    await _launch(recipientId);
    await _waitForRecipientPushRegistrationAccepted();
    await _openConversation(recipient, sender.username);
    await _waitForZeroAppCards('transition B exact-chat retirement');
"""
roots = sys.argv[1:] or ['/Volumes/CrucialX9/flutter_app', '/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree']
for root in roots:
    p = pathlib.Path(root, rel); s = p.read_text()
    if new in s: print('already', root); continue
    assert s.count(old) == 1, root
    p.write_text(s.replace(old, new)); print('patched', root)
