import pathlib
p = pathlib.Path('/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-run/HANDOVER.md'); s = p.read_text()
old = """- Owned TURN container `mknoon-all-tests-foreground-turn-4a6a560b` still running (needed for foreground audio);
  remove it only at true final stop."""
new = """- Final stop done 2026-09-26: owned TURN container `mknoon-all-tests-foreground-turn-4a6a560b` REMOVED
  (recreate the foreground-turn fixture before any foreground-audio check); 6 leaked worktree-cwd Pixel logcat
  streams killed; no owned check/build/reaper processes left. Foreign processes (flutter_app-beta0924 builds,
  emulators, other sessions) untouched."""
assert s.count(old) == 1; p.write_text(s.replace(old, new)); print('ok')
