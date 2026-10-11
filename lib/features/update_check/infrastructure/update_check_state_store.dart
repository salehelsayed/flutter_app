import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/update_check_state.dart';

/// Stores [UpdateCheckState] as a JSON file in the application-support
/// directory.
///
/// Plain app storage on purpose: it is wiped on uninstall. NOT the Keychain and
/// NOT flutter_secure_storage, because those survive an uninstall on iOS.
///
/// Android backup: the manifest sets `allowBackup="false"` and both
/// `backup_rules.xml` and `data_extraction_rules.xml` exclude every domain
/// (cloud backup and device transfer), so this file is never backed up or
/// restored. A restored copy would still be safe: it is re-verified at launch
/// and the rank and sequence rules still apply.
class UpdateCheckStateStore {
  UpdateCheckStateStore({Future<Directory> Function()? directoryProvider})
    : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory;

  static const String fileName = 'se41_update_check_state.json';

  final Future<Directory> Function() _directoryProvider;

  Future<File> _file() async =>
      File('${(await _directoryProvider()).path}/$fileName');

  /// Returns [UpdateCheckState.empty] when the file is missing or corrupt.
  Future<UpdateCheckState> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) return UpdateCheckState.empty;
      final state = UpdateCheckState.fromJson(
        jsonDecode(await file.readAsString()),
      );
      return state ?? UpdateCheckState.empty;
    } on Exception {
      return UpdateCheckState.empty;
    }
  }

  /// Atomic: writes a temp file in the same directory, then renames it over
  /// the old file.
  Future<void> save(UpdateCheckState state) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(jsonEncode(state.toJson()), flush: true);
    await temp.rename(file.path);
  }
}
