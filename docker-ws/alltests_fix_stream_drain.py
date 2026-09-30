"""Capture harnesses: bound the post-exit output drain in _runStreaming. `flutter build ios` leaves forked
flutter_tools processes that inherit stdout/stderr, so waiting for stream close after the command exited hung the
campaign forever. The exit code stays authoritative; output is drained for at most 30 s after exit.
Both capture files, both checkouts, exact-match guards."""
import pathlib

DRAIN = """    final exitCode = await process.exitCode;
    // A finished command can leave descendants (flutter build ios forks) that
    // inherited stdout/stderr and keep the pipes open indefinitely. The exit
    // code is authoritative; drain the remaining output for a bounded time.
    await Future.wait(<Future<void>>[outDone, errDone]).timeout(
      const Duration(seconds: 30),
      onTimeout: () async {
        await outSubscription.cancel();
        await errSubscription.cancel();
        stdout.writeln(
          'NOTE: $executable exited $exitCode; output pipes stayed open after '
          'exit, stopped draining after 30 s.',
        );
        return const <void>[];
      },
    );
"""

def streams(prefix):
    return (
        prefix
        + """    final outSubscription = process.stdout.transform(utf8.decoder).listen((
      chunk,
    ) {
      out.write(chunk);
      stdout.write(chunk);
    });
    final errSubscription = process.stderr.transform(utf8.decoder).listen((
      chunk,
    ) {
      err.write(chunk);
      stderr.write(chunk);
    });
    final outDone = outSubscription.asFuture<void>();
    final errDone = errSubscription.asFuture<void>();
"""
    )

OLD_STREAMS = """    final outDone = process.stdout.transform(utf8.decoder).forEach((chunk) {
      out.write(chunk);
      stdout.write(chunk);
    });
    final errDone = process.stderr.transform(utf8.decoder).forEach((chunk) {
      err.write(chunk);
      stderr.write(chunk);
    });
"""
files = {
    'integration_test/scripts/capture_group_reaction_notification_device.dart':
        """    final exitCode = await process.exitCode;
    await Future.wait(<Future<void>>[outDone, errDone]);
    _recordCommand(executable, args, exitCode);
""",
    'integration_test/scripts/capture_1to1_reaction_head_provenance.dart':
        """    final exitCode = await process.exitCode;
    await Future.wait([outDone, errDone]);
    if (exitCode != 0) {
      throw _CampaignFailure(
""",
}
for root in ('/Volumes/CrucialX9/flutter_app', '/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree'):
    for rel, old_wait in files.items():
        p = pathlib.Path(root, rel); s = p.read_text()
        start = s.index('Future<_CommandOutput> _runStreaming(\n')
        body_end = s.index('\n  }\n', start)
        body = s[start:body_end]
        if 'outSubscription' in body:
            continue
        assert body.count(OLD_STREAMS) == 1 and body.count(old_wait) == 1, (root, rel)
        tail = old_wait.split('\n', 2)[2]  # keep the line(s) after the old Future.wait
        body = body.replace(OLD_STREAMS, streams('')).replace(old_wait, DRAIN + tail)
        p.write_text(s[:start] + body + s[body_end:])
    print('patched', root)
