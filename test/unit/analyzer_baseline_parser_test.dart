import 'package:flutter_test/flutter_test.dart';

import '../../tool/analyzer_baseline/analyzer_baseline.dart';

void main() {
  group('analyzer baseline parser', () {
    test('extracts severity, message, location, and rule', () {
      final parsed = parseAnalyzerOutput('''
   info • The import of 'dart:async' is unnecessary • integration_test/background_reconnect_test.dart:16:8 • unnecessary_import
warning • Unused import: 'package:flutter/widgets.dart' • lib/example.dart:3:8 • unused_import
''');

      expect(parsed.malformedFindingLines, isEmpty);
      expect(parsed.findings, hasLength(2));

      final info = parsed.findings.first;
      expect(info.severity, 'info');
      expect(info.message, "The import of 'dart:async' is unnecessary");
      expect(info.path, 'integration_test/background_reconnect_test.dart');
      expect(info.line, 16);
      expect(info.column, 8);
      expect(info.rule, 'unnecessary_import');

      final warning = parsed.findings.last;
      expect(warning.severity, 'warning');
      expect(warning.path, 'lib/example.dart');
      expect(warning.rule, 'unused_import');
    });

    test('normalizes comparison keys without line and column', () {
      final parsed = parseAnalyzerOutput('''
warning • Unused import: 'package:flutter/widgets.dart' • lib/example.dart:3:8 • unused_import
warning • Unused import: 'package:flutter/widgets.dart' • lib/example.dart:4:8 • unused_import
''');

      final snapshot = snapshotWarningInfoFindings(parsed.findings);

      expect(snapshot.counts, hasLength(1));
      expect(snapshot.total, 2);
      expect(snapshot.counts.values.single, 2);
    });

    test('fails comparison when current warning count exceeds baseline', () {
      final baseline = readBaselineTsv('''
1\twarning\tunused_import\tlib/example.dart\tUnused import: 'package:flutter/widgets.dart'
''');
      final current = parseAnalyzerOutput('''
warning • Unused import: 'package:flutter/widgets.dart' • lib/example.dart:3:8 • unused_import
warning • Unused import: 'package:flutter/widgets.dart' • lib/example.dart:4:8 • unused_import
''');

      final comparison = compareAnalyzerBaseline(
        current: current,
        baseline: baseline,
      );

      expect(comparison.hasBlockingIssues, isTrue);
      expect(comparison.newDebt, hasLength(1));
      expect(comparison.newDebt.single.delta, 1);
    });

    test('fails comparison on analyzer errors', () {
      final baseline = readBaselineTsv('');
      final current = parseAnalyzerOutput('''
error • Undefined name 'missing' • lib/example.dart:10:12 • undefined_identifier
''');

      final comparison = compareAnalyzerBaseline(
        current: current,
        baseline: baseline,
      );

      expect(comparison.hasBlockingIssues, isTrue);
      expect(comparison.errors, hasLength(1));
      expect(comparison.errors.single.rule, 'undefined_identifier');
    });

    test('rejects baselined analyzer errors', () {
      expect(
        () => readBaselineTsv(
          '1\terror\tundefined_identifier\tlib/example.dart\tUndefined name',
        ),
        throwsFormatException,
      );
    });

    test('reports removed findings as non-blocking improvements', () {
      final baseline = readBaselineTsv('''
2\tinfo\tavoid_print\tintegration_test/example_test.dart\tDon't invoke 'print' in production code
''');
      final current = parseAnalyzerOutput('''
   info • Don't invoke 'print' in production code • integration_test/example_test.dart:12:3 • avoid_print
''');

      final comparison = compareAnalyzerBaseline(
        current: current,
        baseline: baseline,
      );

      expect(comparison.hasBlockingIssues, isFalse);
      expect(comparison.removedDebt, hasLength(1));
      expect(comparison.removedDebt.single.removed, 1);
    });

    test('fails closed on malformed analyzer finding rows', () {
      final current = parseAnalyzerOutput(
        'warning • Missing location separator • lib/example.dart • lint_rule',
      );
      final comparison = compareAnalyzerBaseline(
        current: current,
        baseline: readBaselineTsv(''),
      );

      expect(current.malformedFindingLines, hasLength(1));
      expect(comparison.hasBlockingIssues, isTrue);
    });
  });
}
