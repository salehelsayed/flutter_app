import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_app/features/call/diagnostics/call_diagnostic_schema.dart';
import 'package:flutter_app/features/call/diagnostics/call_setup_failure.dart';

void main() {
  test(
    'BL5 classifications remain valid in the unchanged v1 relay vocabulary',
    () {
      final relay = jsonDecode(
        File('go-relay-server/call_diagnostics_schema_v1.json')
            .readAsStringSync(),
      ) as Map<String, dynamic>;
      for (final failure in CallSetupFailure.values) {
        expect(callDiagnosticSchemaV1['stage'], contains(failure.stage));
        expect(callDiagnosticSchemaV1['reason'], contains(failure.reason));
        expect(relay['stage'], contains(failure.stage));
        expect(relay['reason'], contains(failure.reason));
        expect(failure.reason, isNot('none'));
      }
    },
  );
}
