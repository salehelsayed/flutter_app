#!/usr/bin/env dart

import 'dart:convert';
import 'dart:io';

import 'android_voice_message_device_campaign.dart';

List<String> _devices(List<String> args) {
  final values = <String>[];
  for (var index = 0; index < args.length; index += 1) {
    final value = args[index];
    if (value == '--device' && index + 1 < args.length) {
      values.add(args[++index].trim());
    } else if (value.startsWith('--device=')) {
      values.add(value.substring('--device='.length).trim());
    }
  }
  if (values.isNotEmpty) {
    return values.where((value) => value.isNotEmpty).toList();
  }
  return <String>[
    Platform.environment['SIMS_ANDROID_PHYSICAL_DEVICE_ID']?.trim() ?? '',
    Platform.environment['SIMS_ANDROID_EMULATOR_DEVICE_ID']?.trim() ?? '',
  ].where((value) => value.isNotEmpty).toList(growable: false);
}

String? _artifact(List<String> args) {
  for (var index = 0; index < args.length; index += 1) {
    final value = args[index];
    if (value == '--artifact' && index + 1 < args.length) {
      return args[++index].trim();
    }
    if (value.startsWith('--artifact=')) {
      return value.substring('--artifact='.length).trim();
    }
  }
  return Platform.environment['SIMS_ARTIFACT_ANDROID_E2E_MAIN']?.trim();
}

Future<void> main(List<String> args) async {
  final result = await runAndroidVoiceMessageDeviceCampaign(
    devices: _devices(args),
    artifactPath: _artifact(args),
  );
  stdout.writeln('SIMS_RESULT_JSON=${jsonEncode(result.json)}');
  exitCode = result.processExitCode;
}
