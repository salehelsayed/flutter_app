import 'dart:convert';
import 'dart:io';

const autoSetupConfigFileName = 'auto_setup.json';
const _compileTimeAutoSetupUsername = String.fromEnvironment(
  'AUTO_SETUP_USERNAME',
);

Future<String?> resolveAutoSetupUsername(String documentsPath) async {
  final fileUsername = await _readFileUsername(documentsPath);
  if (fileUsername != null) return fileUsername;
  return _normalizeUsername(_compileTimeAutoSetupUsername);
}

Future<String?> _readFileUsername(String documentsPath) async {
  try {
    final file = File('$documentsPath/$autoSetupConfigFileName');
    if (!await file.exists()) return null;
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map<String, dynamic>) return null;
    final username = decoded['username'];
    return username is String ? _normalizeUsername(username) : null;
  } catch (_) {
    return null;
  }
}

String? _normalizeUsername(String username) {
  final trimmed = username.trim();
  return trimmed.isEmpty ? null : trimmed;
}
