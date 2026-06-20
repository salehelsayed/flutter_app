import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:path_provider/path_provider.dart';

const _configFileName = 'group_multi_party_phase0_runtime.json';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final documentsDir = await getApplicationDocumentsDirectory();
  final configFile = File('${documentsDir.path}/$_configFileName');
  final rawConfig = await configFile.readAsString();
  final config = Map<String, dynamic>.from(jsonDecode(rawConfig) as Map);

  final scenario = _requiredString(config, 'scenario');
  final role = _requiredString(config, 'role');
  final runId = _requiredString(config, 'runId');
  final mode = _requiredString(config, 'mode');
  final dbName = _requiredString(config, 'dbName');
  final sharedDir = _requiredString(config, 'sharedDir');

  Directory(sharedDir).createSync(recursive: true);
  final marker = <String, Object?>{
    'ok': true,
    'source': 'documents-file',
    'configFile': configFile.path,
    'scenario': scenario,
    'role': role,
    'runId': runId,
    'mode': mode,
    'dbName': dbName,
    'sharedDir': sharedDir,
    'documentsDir': documentsDir.path,
    'observedAt': DateTime.now().toIso8601String(),
  };

  final markerFile = File('$sharedDir/phase0_${scenario}_$role.json');
  markerFile.writeAsStringSync(jsonEncode(marker), flush: true);
  debugPrint('[PHASE0_RUNTIME_CONFIG] ${jsonEncode(marker)}');

  runApp(const SizedBox.shrink());
}

String _requiredString(Map<String, dynamic> values, String key) {
  final value = values[key];
  if (value is! String || value.trim().isEmpty) {
    throw StateError('Missing required Phase 0 runtime config field: $key');
  }
  return value.trim();
}
