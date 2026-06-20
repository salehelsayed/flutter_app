import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter_app/core/utils/flow_event_emitter.dart';

/// Release-visible, sanitized breadcrumb channel for Account Migration assembly.
///
/// Release/TestFlight builds gate `emitFlowEvent` off
/// (`flowEventLoggingEnabled = kDebugMode`), so the migration runtime's
/// FlowEvents never reach the device console. These breadcrumbs are a
/// deliberate, bounded, secret-redacted `debugPrint` channel that DOES surface
/// in `idevicesyslog` (as `flutter: MKNOON_MIG …`) so a "could not assemble the
/// account bundle" failure in the field names its exact phase + reason.
///
/// Grep marker on device: `idevicesyslog -m MKNOON_MIG`.
///
/// Beta diagnostic. Flip to `false` for GA (see Test-Flight-Improv plan 130, OQ-3).
const bool kAccountMigrationTelemetry = true;

/// Test seam: when set, breadcrumb lines are routed here instead of
/// `debugPrint`, so host/sim tests can assert the emitted sequence.
typedef MigrationBreadcrumbSink = void Function(String line);

MigrationBreadcrumbSink? _testSink;

@visibleForTesting
void debugSetMigrationBreadcrumbSink(MigrationBreadcrumbSink? sink) {
  _testSink = sink;
}

/// Emits a single sanitized breadcrumb line `MKNOON_MIG <event> k=v k=v …`.
///
/// Every field is run through the app's diagnostic redaction
/// ([sanitizeFlowEventDetails] for key-level redaction + [sanitizeDiagnosticText]
/// for value-level redaction) so no secret material is logged (INV-A1).
///
/// Fire-and-forget: it never throws into the caller — a misbehaving sink or a
/// formatting error must never abort assembly (INV-A3).
void migrationBreadcrumb(
  String event, {
  Map<String, Object?> fields = const {},
}) {
  final String line;
  try {
    final sanitized = sanitizeFlowEventDetails(Map<String, dynamic>.from(fields));
    final buffer = StringBuffer('MKNOON_MIG ')..write(event);
    sanitized.forEach((key, value) {
      final text = sanitizeDiagnosticText(value).replaceAll(RegExp(r'\s+'), ' ').trim();
      buffer.write(' $key=$text');
    });
    line = buffer.toString();
  } catch (_) {
    return;
  }
  final sink = _testSink;
  try {
    if (sink != null) {
      sink(line);
    } else if (kAccountMigrationTelemetry) {
      debugPrint(line);
    }
  } catch (_) {
    // Telemetry must never break the migration.
  }
}
