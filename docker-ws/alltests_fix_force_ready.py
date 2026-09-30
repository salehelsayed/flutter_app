"""Refine per-job forcing: the first force of a retry attempt keeps the old rule; a job WorkManager re-queued for
the SAME attempt is forced only once JobScheduler reports it ready (forcing it during backoff just re-queues it)."""
import pathlib
rel = 'integration_test/scripts/capture_1to1_reaction_head_provenance.dart'
edits = [
("""          // WorkManager defers an early force-run and re-queues the same work
          // under a new job id, so each job id gets its own force.
          final forceKey = '$latestRetryAttempt:$jobId';
""", """          // WorkManager defers an early force-run and re-queues the same work
          // under a new job id, so each job id gets its own force. A re-queued
          // job is forced only once JobScheduler reports it ready; forcing it
          // during backoff would only re-queue it again.
          final forceKey = '$latestRetryAttempt:$jobId';
          final attemptAlreadyForced = forcedKeys.any(
            (key) => key.startsWith('$latestRetryAttempt:'),
          );
"""),
("""            ].any(state.contains);
            var forceResult = 'not_forced';
            if (!unsafe) {
""", """            ].any(state.contains);
            final requeuedNotReady =
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
"""),
]
for root in ('/Volumes/CrucialX9/flutter_app', '/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree'):
    p = pathlib.Path(root, rel); s = p.read_text()
    for old, new in edits:
        if new in s: continue
        assert s.count(old) == 1, (root, old[:50]); s = s.replace(old, new)
    p.write_text(s); print('patched', root)
