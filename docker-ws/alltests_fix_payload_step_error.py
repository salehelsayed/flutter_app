"""Android payload campaign: keep the app step's error TYPE (never the free-text message) in the
'Installed main-app step ... failed.' failure, so a red names its cause. [roots...]"""
import pathlib, sys
rel = 'integration_test/scripts/notification_android_payload_campaign.dart'
old = """    final result = _object(jsonDecode(raw));
    if (result['status'] != 'complete' || result['success'] != true) {
      throw _Failure(
        'Installed main-app step ${config['stepId']} failed.',
        assertionsAttempted: _assertionsAttempted,
      );
    }"""
new = """    final result = _object(jsonDecode(raw));
    if (result['status'] != 'complete' || result['success'] != true) {
      // Only the error type is kept; the app's free-text message can carry
      // identifiers and never enters the report.
      final errorType = result['errorType'] ??
          RegExp(r'^[A-Za-z_][A-Za-z0-9_]*')
              .firstMatch('${result['error'] ?? ''}')
              ?.group(0);
      throw _Failure(
        'Installed main-app step ${config['stepId']} failed'
        '${errorType == null ? '' : ' ($errorType)'}.',
        assertionsAttempted: _assertionsAttempted,
      );
    }"""
for root in (sys.argv[1:] or ['/Volumes/CrucialX9/flutter_app', '/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree']):
    p = pathlib.Path(root, rel); s = p.read_text()
    if new in s: print('already', root); continue
    assert s.count(old) == 1, root; p.write_text(s.replace(old, new)); print('patched', root)
