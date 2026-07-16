import 'dart:convert';
import 'dart:io';

/// A typed, executable registry entry for a required campaign whose automated
/// driver is not implemented yet. This intentionally fails the gate with
/// BLOCKED instead of leaving an invalid command, printing a recipe as PASS,
/// or misclassifying missing automation as target N/A.
void main(List<String> arguments) {
  final detail = _value(arguments, '--detail');
  final blocker = _value(arguments, '--blocker') ?? 'missingDriver';
  if (detail == null || detail.isEmpty) {
    stderr.writeln('blocked_campaign.dart requires --detail.');
    exitCode = 64;
    return;
  }
  stdout.writeln(
    'SIMS_RESULT_JSON=${jsonEncode(<String, Object?>{'status': 'BLOCKED', 'assertionsAttempted': 0, 'artifactPresent': false, 'printOnly': false, 'blocker': blocker, 'exitCode': 78, 'detail': detail})}',
  );
  exitCode = 78;
}

String? _value(List<String> arguments, String name) {
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (argument == name && index + 1 < arguments.length) {
      return arguments[index + 1].trim();
    }
    if (argument.startsWith('$name=')) {
      return argument.substring(name.length + 1).trim();
    }
  }
  return null;
}
