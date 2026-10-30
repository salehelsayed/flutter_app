import 'dart:convert';
import 'dart:io';

const _scenario = 'production.call.call-audio-soak';

/// KNOWN GAP [VC-024]: owner duration/resource budgets and genuine phone
/// acoustic-content producer are absent. No soak or threshold is fabricated.
void main(List<String> arguments) {
  if (arguments.length == 1 && arguments.single == '--list-scenarios') {
    stdout.writeln(_scenario);
    return;
  }
  if (arguments.isNotEmpty) {
    stderr.writeln(
      'Only --list-scenarios is supported until the owner approves soak criteria.',
    );
    exitCode = 64;
    return;
  }
  stdout.writeln(
    'SIMS_RESULT_JSON=${jsonEncode(<String, Object?>{'status': 'BLOCKED', 'blocker': 'missingDriver', 'assertionsAttempted': 0, 'artifactPresent': false, 'printOnly': false, 'exitCode': 78, 'scenario': _scenario, 'journeyId': 'VC-024', 'detail': 'KNOWN GAP [VC-024]: no approved duration/resource thresholds or phone acoustic-content producer.', 'ownerScopeDisposition': 'N/A: owner duration and resource budgets not approved', 'nativeExecutedByThisCommand': false, 'approvedDuration': null, 'approvedResourceThresholds': null, 'phoneAcousticContentProducer': 'absent', 'hardwarePolicy': 'Only live available targets/accessories may be required; unavailable accessories are N/A after actual discovery.'})}',
  );
  exitCode = 78;
}
