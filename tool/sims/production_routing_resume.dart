/// Diagnostic resume for the production routing campaign.
///
/// `SIMS_ROUTING_RESUME_AT=G5` (a unit id) keeps the shared setup and skips the units
/// before that unit, so a fix can be checked from the point that failed without
/// replaying passed cases. A resumed run is never a routing PASS: the original
/// 27-case receipt set requires every case in one run.
library;

/// Units in runner order. S1 carries S1-CONV; G5 carries the informational G6.
const productionRoutingResumeUnits = <String>[
  'S1', 'S2', 'S3', 'S4', 'S5', 'S6', 'S7', 'S8', 'S9', 'S10', 'S13', //
  'S11', 'S12', 'S14', 'S15', 'X1', 'X2', 'X3', //
  'G1', 'G2', 'G3', 'G4', 'G5', 'G7', 'G8',
];

final class ProductionRoutingResume {
  const ProductionRoutingResume._(this.startAt);

  factory ProductionRoutingResume.fromEnvironment(
    Map<String, String> environment,
  ) {
    final raw = environment['SIMS_ROUTING_RESUME_AT']?.trim();
    if (raw == null || raw.isEmpty) {
      return const ProductionRoutingResume._(null);
    }
    if (!productionRoutingResumeUnits.contains(raw)) {
      throw FormatException('unknown routing resume unit', raw);
    }
    return ProductionRoutingResume._(raw);
  }

  /// First unit to run; null runs everything.
  final String? startAt;

  bool get partial =>
      startAt != null && startAt != productionRoutingResumeUnits.first;

  bool runs(String unit) {
    final index = productionRoutingResumeUnits.indexOf(unit);
    if (index < 0) {
      throw ArgumentError.value(unit, 'unit', 'not a routing unit');
    }
    return startAt == null ||
        index >= productionRoutingResumeUnits.indexOf(startAt!);
  }

  /// Why a resumed run that finished its units still is not a PASS.
  String diagnosticFailure(List<String> recordedCaseIds) =>
      'resumed at $startAt: recorded ${recordedCaseIds.join(', ')} without '
      'failure; diagnostic only, not a full routing proof';
}
