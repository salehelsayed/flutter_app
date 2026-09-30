"""Apply the curly-braces lint fix to private_media_outbox_e2e.dart in main and worktree (exact-match guard)."""
import pathlib
old = "  if (error is TimeoutException)\n    return timeoutCodes[error.message] ?? 'unknown';\n  return 'unknown';\n"
new = "  if (error is TimeoutException) {\n    return timeoutCodes[error.message] ?? 'unknown';\n  }\n  return 'unknown';\n"
for root in ('/Volumes/CrucialX9/flutter_app', '/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree'):
    p = pathlib.Path(root, 'lib/core/debug/private_media_outbox_e2e.dart'); s = p.read_text()
    if s.count(old) == 1: p.write_text(s.replace(old, new)); print('fixed', root)
    elif new in s: print('already', root)
    else: print('NO MATCH', root)
