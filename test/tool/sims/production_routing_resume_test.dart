import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../tool/sims/production_routing_resume.dart';

void main() {
  test('a full run executes every routing unit', () {
    final resume = ProductionRoutingResume.fromEnvironment(const {});
    expect(resume.partial, isFalse);
    expect(productionRoutingResumeUnits.every(resume.runs), isTrue);
  });

  test('resuming at G5 skips earlier units and is partial', () {
    final resume = ProductionRoutingResume.fromEnvironment(const {
      'SIMS_ROUTING_RESUME_AT': 'G5',
    });
    expect(resume.partial, isTrue);
    expect(resume.runs('S1'), isFalse);
    expect(resume.runs('X3'), isFalse);
    expect(resume.runs('G4'), isFalse);
    expect(resume.runs('G5'), isTrue);
    expect(resume.runs('G8'), isTrue);
    expect(
      resume.diagnosticFailure(['G5', 'G6', 'G7', 'G8']),
      allOf(contains('resumed at G5'), contains('not a full routing proof')),
    );
  });

  test('unknown resume units are rejected', () {
    expect(
      () => ProductionRoutingResume.fromEnvironment(const {
        'SIMS_ROUTING_RESUME_AT': 'G9',
      }),
      throwsFormatException,
    );
    expect(
      () => ProductionRoutingResume.fromEnvironment(const {}).runs('Z1'),
      throwsArgumentError,
    );
  });

  test('the routing runner guards every resume unit', () {
    final source = File(
      'integration_test/scripts/run_production_routing.dart',
    ).readAsStringSync();
    for (final unit in productionRoutingResumeUnits) {
      expect(source, contains("resume.runs('$unit')"), reason: unit);
    }
    expect(source, contains('resume.diagnosticFailure('));
  });
}
