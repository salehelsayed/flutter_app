"""Fixed-wake completion harness: (1) keep evidence on timeout, (2) spend a force attempt only on a successful
`jobscheduler run -f`. No assertion or deadline changes. Applies to both checkouts with exact-match guards."""
import pathlib
rel = 'integration_test/scripts/capture_1to1_reaction_head_provenance.dart'
edits = [
("""            var forceResult = 'not_forced';
            if (!unsafe) {
              // Spend this attempt only when Android will receive a force-run.
              // An active predecessor can become runnable after its PID dies.
              forcedKeys.add(forceKey);
              final result = await _adb(recipientId, <String>[
""", """            var forceResult = 'not_forced';
            if (!unsafe) {
              // Spend this attempt only when Android accepted the force-run.
              // An active predecessor can become runnable after its PID dies,
              // and a rejected force (race) must stay retryable.
              final result = await _adb(recipientId, <String>[
"""),
("""              forceResult = result.exitCode == 0 ? 'forced' : 'force_race';
            }
""", """              forceResult = result.exitCode == 0 ? 'forced' : 'force_race';
              if (result.exitCode == 0) forcedKeys.add(forceKey);
            }
"""),
("""      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    throw _CampaignFailure(
      _stage,
      '$stem did not reach canonical show, exact marker ACK, card retirement, and worker success.',
    );
""", """      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    // Keep the timeout evidence the success path would have written, plus the
    // final JobScheduler state, so the missing condition stays diagnosable.
    _writeRuntimeEvidence('$stem-timeout-runtime.jsonl', runtimeLog);
    _writeJsonEvidence('$stem-timeout-notification-snapshots.json', {
      'snapshots': snapshots,
    });
    if (requireHeadlessWorker) {
      File('${artifactDir.path}/$stem-jobscheduler-resume.log')
          .writeAsStringSync(forceAudit.toString(), flush: true);
      try {
        File('${artifactDir.path}/$stem-timeout-jobscheduler.txt')
            .writeAsStringSync(await _jobschedulerDump(), flush: true);
      } on Object {
        // Diagnostic only; the timeout below stays the reported failure.
      }
    }
    throw _CampaignFailure(
      _stage,
      '$stem did not reach canonical show, exact marker ACK, card retirement, and worker success.',
    );
"""),
]
for root in ('/Volumes/CrucialX9/flutter_app', '/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree'):
    p = pathlib.Path(root, rel); s = p.read_text()
    for old, new in edits:
        if new in s: continue
        assert s.count(old) == 1, (root, old[:60])
        s = s.replace(old, new)
    p.write_text(s); print('patched', root)
