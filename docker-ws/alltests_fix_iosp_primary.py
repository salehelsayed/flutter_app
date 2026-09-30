"""iOS payload driver: a finalization failure thrown from `finally` replaced the phase's original failure, so reports
named only a cleanup step. Record the first failure and append its driver-authored detail (or type) to the
finalization failure. No assertion or deadline changes. [roots...]"""
import pathlib, sys
rel = 'integration_test/scripts/ios_notification_payload_xcui_driver.dart'
SITE_OLD = """      return _DriverResult.passed(_assertionsAttempted);
    } finally {
      final diagnostic = File("""
SITE_NEW = """      return _DriverResult.passed(_assertionsAttempted);
    } catch (error) {
      _primaryFailure ??= error;
      rethrow;
    } finally {
      final diagnostic = File("""
FIELD_OLD = "  bool _providerSetupComplete = false;\n"
FIELD_NEW = FIELD_OLD + "  Object? _primaryFailure;\n"
THROW_OLD = """  void _throwFinalizationFailures(List<Object> failures) {
    if (failures.isEmpty) return;
    throw _DriverFailure(
      'Phase finalization retained ${failures.length} bounded diagnostic, '
      'cleanup, or private-deletion failure(s) after all owners were attempted.',
      _assertionsAttempted,
    );
  }"""
THROW_NEW = """  void _throwFinalizationFailures(List<Object> failures) {
    if (failures.isEmpty) return;
    // A throw from `finally` replaces the phase's original failure; keep its
    // driver-authored detail so the report still names the first cause.
    final primary = _primaryFailure;
    final primaryDetail = switch (primary) {
      null => '',
      _DriverFailure(:final detail) => ' First failure: $detail',
      _DriverBlocked(:final blocker, :final detail) =>
        ' First failure: $blocker: $detail',
      _ => ' First failure: ${primary.runtimeType}.',
    };
    throw _DriverFailure(
      'Phase finalization retained ${failures.length} bounded diagnostic, '
      'cleanup, or private-deletion failure(s) after all owners were attempted.'
      '$primaryDetail',
      _assertionsAttempted,
    );
  }"""
for root in (sys.argv[1:] or ['/Volumes/CrucialX9/flutter_app', '/Volumes/CrucialX9/.mknoon-all-tests-y227gs8x-worktree']):
    p = pathlib.Path(root, rel); s = p.read_text()
    if '_primaryFailure' in s: print('already', root); continue
    assert s.count(SITE_OLD) == 3 and s.count(FIELD_OLD) == 1 and s.count(THROW_OLD) == 1, root
    s = s.replace(SITE_OLD, SITE_NEW).replace(FIELD_OLD, FIELD_NEW).replace(THROW_OLD, THROW_NEW)
    p.write_text(s); print('patched', root)
