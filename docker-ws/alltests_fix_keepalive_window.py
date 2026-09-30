"""Keepalive warm-readiness wait: the harness re-reads only the last 4000 logcat lines each poll, so a [CONN]
callback for the target can scroll out of the window. Keep the latest observed callback state across polls, and
retain the observed [CONN] callback lines for the target as evidence. Deadline and conditions unchanged.
Usage: [roots...] (default both checkouts)."""
import pathlib, sys
rel = 'integration_test/scripts/android_keepalive_drop_campaign.dart'
edits = [
("""    final timer = Stopwatch()..start();
    bool? targetConnected;
    String? observedTerminal;
""", """    final timer = Stopwatch()..start();
    bool? targetConnected;
    String? observedTerminal;
    final observedCallbacks = <String>{};
"""),
("""          final events = await _flowEvents(device);
          targetConnected = keepaliveTargetConnected(
            _latestLogcat[device] ?? '',
            targetPeerId,
          );
""", """          final events = await _flowEvents(device);
          final log = _latestLogcat[device] ?? '';
          // Only the last 4000 lines are read per poll; a callback that has
          // scrolled out stays the latest one until a newer callback appears.
          targetConnected =
              keepaliveTargetConnected(log, targetPeerId) ?? targetConnected;
          for (final line in log.split('\\n')) {
            if (line.contains('[CONN] peer:') && line.contains(targetPeerId)) {
              observedCallbacks.add(line.trim());
            }
          }
"""),
("""          'elapsedMs': timer.elapsedMilliseconds,
          'deadlineMs': timeout.inMilliseconds,
        }),
      );
""", """          'elapsedMs': timer.elapsedMilliseconds,
          'deadlineMs': timeout.inMilliseconds,
          'observedTargetCallbacks': observedCallbacks.toList(),
        }),
      );
"""),
]
roots = sys.argv[1:] or ['/Volumes/CrucialX9/flutter_app', '/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree']
for root in roots:
    p = pathlib.Path(root, rel); s = p.read_text()
    if 'observedCallbacks' in s:
        print('already', root); continue
    for old, new in edits:
        assert s.count(old) == 1, (root, old[:60]); s = s.replace(old, new)
    p.write_text(s); print('patched', root)
