"""Join publication in the 32-slot overlap test (both checkouts, exact-match guard)."""
import pathlib
rel = 'test/features/push/application/background_storage_liveness_journal_test.dart'
old = """  test('overlapping writers cannot exceed the fixed 32 slots', () async {
    final journals = List<BackgroundStorageLivenessJournal>.generate(
      4,
      (_) => BackgroundStorageLivenessJournal(
        directoryResolver: () async => root,
        now: () => DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        randomNonce: () => 0,
      ),
    );
"""
new = """  test('overlapping writers cannot exceed the fixed 32 slots', () async {
    // The 200 ms caller budget is not a publication join. Under host load the
    // real writers and pruners outlive it, so wait for every publication
    // before inspecting the slots or deleting the directory.
    final journals = List<BackgroundStorageLivenessJournal>.generate(
      4,
      (_) => BackgroundStorageLivenessJournal(
        directoryResolver: () async => root,
        now: () => DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        randomNonce: () => 0,
        maxCallerImpact: const Duration(minutes: 1),
      ),
    );
"""
for root in ('/Volumes/CrucialX9/flutter_app', '/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree'):
    p = pathlib.Path(root, rel); s = p.read_text()
    if s.count(old) == 1: p.write_text(s.replace(old, new)); print('fixed', root)
    elif new in s: print('already', root)
    else: print('NO MATCH', root)
