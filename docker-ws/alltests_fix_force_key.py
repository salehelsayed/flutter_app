"""Force each WorkManager job id once per retry attempt. WorkManager defers an early force-run and re-queues the
work under a new job id; keying by retry alone left that new, ready job unforced. Both checkouts."""
import pathlib
rel = 'integration_test/scripts/capture_1to1_reaction_head_provenance.dart'
old = """          final jobId = incumbent.single;
          final forceKey = '$latestRetryAttempt';
"""
new = """          final jobId = incumbent.single;
          // WorkManager defers an early force-run and re-queues the same work
          // under a new job id, so each job id gets its own force.
          final forceKey = '$latestRetryAttempt:$jobId';
"""
for root in ('/Volumes/CrucialX9/flutter_app', '/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree'):
    p = pathlib.Path(root, rel); s = p.read_text()
    if new in s: print('already', root); continue
    assert s.count(old) == 1, root
    p.write_text(s.replace(old, new)); print('patched', root)
