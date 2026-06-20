import 'package:flutter_app/features/account_migration/application/migration_breadcrumb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late List<String> lines;

  setUp(() {
    lines = <String>[];
    debugSetMigrationBreadcrumbSink(lines.add);
  });

  // Synchronous teardown (see feedback_testwidgets_sync_io_only): a global
  // test seam must be cleared synchronously so it never leaks across tests.
  tearDown(() {
    debugSetMigrationBreadcrumbSink(null);
  });

  test('formats a single MKNOON_MIG <event> k=v line', () {
    migrationBreadcrumb('ASSEMBLY_PHASE', fields: {'phase': 'collectSecureStorage'});
    expect(lines, ['MKNOON_MIG ASSEMBLY_PHASE phase=collectSecureStorage']);
  });

  test('emits the bare event when there are no fields', () {
    migrationBreadcrumb('ASSEMBLY_OK');
    expect(lines, ['MKNOON_MIG ASSEMBLY_OK']);
  });

  test('redacts secret-bearing values (INV-A1)', () {
    migrationBreadcrumb('ASSEMBLY_FAIL', fields: {
      'phase': 'collectSecureStorage',
      'detail': 'privateKeyHex=deadbeefcafebabe',
    });
    expect(lines.single, contains('[redacted]'));
    expect(lines.single, isNot(contains('deadbeefcafebabe')));
    // Non-secret fields survive.
    expect(lines.single, contains('phase=collectSecureStorage'));
  });

  test('collapses newlines/whitespace so each breadcrumb is one line', () {
    migrationBreadcrumb('ASSEMBLY_FAIL', fields: {
      'detail': 'line one\nline two\t tab',
    });
    expect(lines.single, isNot(contains('\n')));
    expect(lines.single, 'MKNOON_MIG ASSEMBLY_FAIL detail=line one line two tab');
  });

  test('a throwing sink never propagates to the caller (INV-A3)', () {
    debugSetMigrationBreadcrumbSink((_) => throw StateError('boom'));
    expect(() => migrationBreadcrumb('ASSEMBLY_PHASE', fields: {'phase': 'p'}),
        returnsNormally);
  });

  test('with no sink set the call is a safe no-op (does not throw)', () {
    debugSetMigrationBreadcrumbSink(null);
    expect(
      () => migrationBreadcrumb('ASSEMBLY_PHASE', fields: {'phase': 'p'}),
      returnsNormally,
    );
  });
}
