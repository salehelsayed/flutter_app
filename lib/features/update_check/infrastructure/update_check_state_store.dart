import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../domain/update_check_state.dart';
import 'update_check_state_lock.dart';

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
///
/// T4a: several writers share the file (the foreground UI, the iOS background
/// task, the Android minimal engine). Every [save] re-reads the file under
/// [UpdateCheckStateLock] right before the rename and merges with
/// [UpdateCheckState.merge], so a stale writer cannot lower the rank or the
/// sequence and cannot drop a dismissal or a notification record.
///
/// Rank floor: when a rank of 2 or more is saved, an add-only marker file
/// (`se41_rank_floor_<rank>`) is created and never deleted. [load] and [save]
/// use max(marker, stored rank), so a deleted or corrupt state file cannot
/// bring back trust in a lower-rank key.
///
/// iOS data protection: files keep the app's default class
/// (completeUntilFirstUserAuthentication; Runner.entitlements sets no
/// stricter default). Nothing here sets a protection class, so the temp file
/// and the rename get the same class. Before the first unlock the file cannot
/// be read: [load] and [save] then throw [UpdateCheckStateUnavailable] and
/// never treat the file as empty, so a locked device never resets the state.
class UpdateCheckStateStore {
  UpdateCheckStateStore({
    Future<Directory> Function()? directoryProvider,
    Future<void> Function()? beforeRenameForTest,
  }) : _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _beforeRename = beforeRenameForTest;

  static const String fileName = 'se41_update_check_state.json';
  static const String rankFloorPrefix = 'se41_rank_floor_';

  /// Ranks from this value up leave a floor marker.
  static const int rankFloorMinimum = 2;

  final Future<Directory> Function() _directoryProvider;
  final Future<void> Function()? _beforeRename;

  Future<File> _file() async =>
      File('${(await _directoryProvider()).path}/$fileName');

  /// Returns [UpdateCheckState.empty] (raised to the rank floor) when the file
  /// is missing or corrupt. Throws [UpdateCheckStateUnavailable] when the file
  /// exists but cannot be read.
  Future<UpdateCheckState> load() async {
    final file = await _file();
    final floor = await _rankFloor(file.parent);
    return _applyFloor(await _readOrEmpty(file), floor);
  }

  /// Merges [state] into the file as it is on disk now and writes the result
  /// atomically (temp file, then rename). Returns what was written.
  Future<UpdateCheckState> save(UpdateCheckState state) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    final lock = UpdateCheckStateLock(File('${file.path}.lock'));
    return lock.synchronized(() async {
      final floor = await _rankFloor(file.parent);
      final disk = _applyFloor(await _readOrEmpty(file), floor);
      final merged = _applyFloor(UpdateCheckState.merge(disk, state), floor);
      // The marker comes first: a crash after it still leaves the floor.
      if (merged.highestAcceptedRank >= rankFloorMinimum) {
        await _markRankFloor(file.parent, merged.highestAcceptedRank);
      }
      final temp = File('${file.path}.tmp');
      await temp.writeAsString(jsonEncode(merged.toJson()), flush: true);
      await _beforeRename?.call();
      await temp.rename(file.path);
      return merged;
    });
  }

  Future<UpdateCheckState> _readOrEmpty(File file) async {
    final String text;
    try {
      if (!await file.exists()) return UpdateCheckState.empty;
      text = await file.readAsString();
    } on FileSystemException catch (error) {
      throw UpdateCheckStateUnavailable(error.message);
    }
    try {
      return UpdateCheckState.fromJson(jsonDecode(text)) ??
          UpdateCheckState.empty;
    } on FormatException {
      return UpdateCheckState.empty;
    }
  }

  static UpdateCheckState _applyFloor(UpdateCheckState state, int floor) {
    if (state.highestAcceptedRank >= floor) return state;
    // The stored envelope and sequence belong to a lower rank: drop them.
    return UpdateCheckState(
      highestAcceptedRank: floor,
      lastCheckAt: state.lastCheckAt,
      dismissedLatestBuild: state.dismissedLatestBuild,
      notifiedSoftLatestBuild: state.notifiedSoftLatestBuild,
      lastHardNotifyAt: state.lastHardNotifyAt,
      hardReminderCount: state.hardReminderCount,
      notifiedHardMinBuild: state.notifiedHardMinBuild,
    );
  }

  static Future<int> _rankFloor(Directory directory) async {
    var floor = 0;
    try {
      if (!await directory.exists()) return 0;
      await for (final entity in directory.list(followLinks: false)) {
        final name = entity.uri.pathSegments.last;
        if (!name.startsWith(rankFloorPrefix)) continue;
        final rank = int.tryParse(name.substring(rankFloorPrefix.length));
        if (rank != null && rank > floor) floor = rank;
      }
    } on FileSystemException catch (error) {
      throw UpdateCheckStateUnavailable(error.message);
    }
    return floor;
  }

  static Future<void> _markRankFloor(Directory directory, int rank) async {
    final marker = File('${directory.path}/$rankFloorPrefix$rank');
    try {
      await marker.create(exclusive: true);
    } on FileSystemException {
      if (!await marker.exists()) rethrow;
    }
  }
}

/// The state file exists but cannot be read, for example on iOS before the
/// first unlock. Callers skip the run; they never reset the state.
class UpdateCheckStateUnavailable implements Exception {
  const UpdateCheckStateUnavailable(this.message);

  final String message;

  @override
  String toString() => 'UpdateCheckStateUnavailable($message)';
}
