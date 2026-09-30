"""Revert the delete-then-rejoin fixture helper (blocked by the product's retained self-removal floor). [roots...]"""
import importlib.util, pathlib, sys
spec = importlib.util.spec_from_file_location('fix', pathlib.Path(__file__).with_name('alltests_fix_gmp_rejoin.py'))
src = pathlib.Path(__file__).with_name('alltests_fix_gmp_rejoin.py').read_text()
ns = {}
exec(src.split("roots = sys.argv")[0], ns)  # load constants only
rel = ns['rel']
for root in (sys.argv[1:] or ['/Volumes/CrucialX9/flutter_app', '/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree']):
    p = pathlib.Path(root, rel); s = p.read_text()
    if '_deleteSelfRemovedShellBeforeRejoin' not in s:
        print('already', root); continue
    for new, old in ((ns['CALL_NEW'], ns['CALL_OLD']), (ns['FUNC'] + ns['FUNC_ANCHOR'], ns['FUNC_ANCHOR']),
                     (ns['IMPORT_ANCHOR'] + ns['NEW_IMPORTS'], ns['IMPORT_ANCHOR']),
                     (ns['HELPER_IMPORT_ANCHOR'] + ns['HELPER_IMPORT'], ns['HELPER_IMPORT_ANCHOR'])):
        assert s.count(new) == 1, (root, new[:60]); s = s.replace(new, old)
    p.write_text(s); print('reverted', root)
