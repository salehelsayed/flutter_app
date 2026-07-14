#!/usr/bin/env dart

import 'dart:io';

import 'group_reaction_notification_device_criteria.dart';

Future<void> main(List<String> args) async {
  try {
    final scenarioId = _valueFor(args, '--scenario') ?? 'all';
    final selected = _selectedScenarios(scenarioId);
    if (args.contains('--list-scenarios')) {
      // `dart run` may print build-hook progress without a trailing newline.
      stdout.writeln();
      for (final scenario in selected) {
        stdout.writeln(scenario.id);
      }
      return;
    }
    if (selected.length != 1) {
      _usageError('Artifact validation requires one explicit --scenario.');
      return;
    }
    final artifactPath = _valueFor(args, '--artifact');
    if (artifactPath == null) {
      _usageError('Artifact validation requires --artifact <json>.');
      return;
    }
    final result = await validateGroupReactionNotificationArtifact(
      scenario: selected.single.id,
      artifactFile: File(artifactPath),
      expectedSenderDeviceId: _valueFor(args, '--sender'),
      expectedRecipientDeviceId: _valueFor(args, '--recipient'),
    );
    if (!result.ok) {
      stderr.writeln(
        'INVALID [${selected.single.testCase}/${selected.single.id}]: '
        '${result.detail}',
      );
      exitCode = 65;
      return;
    }
    stdout.writeln(
      'VALID [${selected.single.testCase}/${selected.single.id}]: '
      'authoritative artifact contract accepted.',
    );
  } on FormatException catch (error) {
    _usageError(error.message);
  } on Object catch (error) {
    stderr.writeln('Artifact validator failed closed: ${error.runtimeType}.');
    exitCode = 70;
  }
}

String? _valueFor(List<String> args, String name) {
  for (var index = 0; index < args.length; index++) {
    final argument = args[index];
    if (argument == name) {
      if (index + 1 >= args.length || args[index + 1].startsWith('--')) {
        throw FormatException('Missing value for $name.');
      }
      return args[index + 1];
    }
    if (argument.startsWith('$name=')) {
      final value = argument.substring(name.length + 1);
      if (value.isEmpty) throw FormatException('Missing value for $name.');
      return value;
    }
  }
  return null;
}

List<GroupReactionNotificationScenario> _selectedScenarios(String id) {
  if (id == 'all') return groupReactionNotificationScenarios;
  final scenario = groupReactionNotificationScenario(id);
  if (scenario == null) {
    throw FormatException(
      'Unknown --scenario "$id". Expected all or one of: '
      '${groupReactionNotificationScenarios.map((value) => value.id).join(', ')}.',
    );
  }
  return <GroupReactionNotificationScenario>[scenario];
}

void _usageError(String message) {
  stderr.writeln(message);
  stderr.writeln(
    'Usage: dart run integration_test/scripts/'
    'validate_group_reaction_notification_artifacts.dart '
    '--scenario <id> --artifact <json> [--sender <device-id>] '
    '[--recipient <device-id>] | --list-scenarios',
  );
  exitCode = 64;
}
