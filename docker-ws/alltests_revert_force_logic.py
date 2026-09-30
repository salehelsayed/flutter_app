"""Restore the TC-393-12-pinned forcing logic in capture_1to1_reaction_head_provenance.dart (both checkouts):
one force per retry attempt, spent before the force-run. Keeps the timeout-evidence and stream-drain changes."""
import pathlib
rel = 'integration_test/scripts/capture_1to1_reaction_head_provenance.dart'
edits = [
("""          // WorkManager defers an early force-run and re-queues the same work
          // under a new job id, so each job id gets its own force. A re-queued
          // job is forced only once JobScheduler reports it ready; forcing it
          // during backoff would only re-queue it again.
          final forceKey = '$latestRetryAttempt:$jobId';
          final attemptAlreadyForced = forcedKeys.any(
            (key) => key.startsWith('$latestRetryAttempt:'),
          );
""", """          final forceKey = '$latestRetryAttempt';
"""),
("""            final requeuedNotReady =
                attemptAlreadyForced && !state.contains('ready');
            if (requeuedNotReady) {
              if (deferredForceKeys.add('$forceKey:not_ready')) {
                forceAudit.writeln(
                  'jobId=$jobId retry=$latestRetryAttempt '
                  'state=${state.trim()} result=awaiting_requeued_ready',
                );
              }
              await Future<void>.delayed(const Duration(milliseconds: 500));
              continue;
            }
            var forceResult = 'not_forced';
            if (!unsafe) {
              // Spend this attempt only when Android accepted the force-run.
              // An active predecessor can become runnable after its PID dies,
              // and a rejected force (race) must stay retryable.
              final result = await _adb(recipientId, <String>[
""", """            var forceResult = 'not_forced';
            if (!unsafe) {
              // Spend this attempt only when Android will receive a force-run.
              // An active predecessor can become runnable after its PID dies.
              forcedKeys.add(forceKey);
              final result = await _adb(recipientId, <String>[
"""),
("""              forceResult = result.exitCode == 0 ? 'forced' : 'force_race';
              if (result.exitCode == 0) forcedKeys.add(forceKey);
            }
""", """              forceResult = result.exitCode == 0 ? 'forced' : 'force_race';
            }
"""),
]
import sys as _sys
ROOTS = _sys.argv[1:] or ['/Volumes/CrucialX9/flutter_app', '/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree']
for root in ROOTS:
    p = pathlib.Path(root, rel); s = p.read_text()
    for old, new in edits:
        assert s.count(old) == 1, (root, old[:60])
        s = s.replace(old, new)
    p.write_text(s); print('reverted', root)
