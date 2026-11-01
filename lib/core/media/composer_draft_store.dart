import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/core/media/private_media_policy.dart';
import 'package:flutter_app/core/storage/exclude_from_backup.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Documents subfolder holding every chat's unsent composer draft.
const kComposerDraftsDirectory = 'composer_drafts';

const _draftFileName = 'draft.json';
const _restoredDirectoryName = 'restored';
const _draftVersion = 1;
const _restoredCopyMaxAge = Duration(hours: 24);

/// Identifies the one chat a draft belongs to.
@immutable
final class ComposerDraftKey {
  const ComposerDraftKey.direct(String peerId) : _id = 'direct:$peerId';

  const ComposerDraftKey.group(String groupId) : _id = 'group:$groupId';

  final String _id;

  bool get allowsPrivateMedia => _id.startsWith('direct:');

  /// Hashing keeps any peer or group id, including '/' or '..', inside the
  /// drafts root.
  String get folderName => sha256.convert(utf8.encode(_id)).toString();

  @override
  bool operator ==(Object other) =>
      other is ComposerDraftKey && other._id == _id;

  @override
  int get hashCode => _id.hashCode;
}

/// What the user had typed and attached but not sent. The quoted reply is
/// deliberately not part of it.
@immutable
final class ComposerDraft {
  ComposerDraft({
    required this.text,
    Iterable<PendingComposerMedia> attachments = const <PendingComposerMedia>[],
    this.privateMediaPolicy = const PrivateMediaPolicy.ordinary(),
  }) : attachments = List<PendingComposerMedia>.unmodifiable(attachments);

  static final ComposerDraft empty = ComposerDraft(text: '');

  final String text;
  final List<PendingComposerMedia> attachments;
  final PrivateMediaPolicy privateMediaPolicy;

  bool get isEmpty => text.trim().isEmpty && attachments.isEmpty;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! ComposerDraft ||
        other.text != text ||
        other.privateMediaPolicy != privateMediaPolicy ||
        other.attachments.length != attachments.length) {
      return false;
    }
    for (var i = 0; i < attachments.length; i++) {
      final a = attachments[i];
      final b = other.attachments[i];
      if (a.file.path != b.file.path ||
          a.budgetBytes != b.budgetBytes ||
          a.width != b.width ||
          a.height != b.height ||
          a.durationMs != b.durationMs) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    text,
    privateMediaPolicy,
    Object.hashAll(attachments.map((media) => media.file.path)),
  );
}

/// Keeps one unsent draft per chat across leaving the chat and app restarts.
abstract interface class ComposerDraftStore {
  factory ComposerDraftStore({
    Future<Directory> Function()? documentsDirectory,
    Future<bool> Function(String path)? excludeFromBackup,
  }) = FileComposerDraftStore;

  /// The app-wide store. Chat screens and chat deletion must share one
  /// instance so a save from a closing screen is ordered before the next
  /// screen's load.
  static final ComposerDraftStore shared = FileComposerDraftStore();

  /// Returns the saved draft, or null when there is none. Attachments point
  /// at working copies the composer may hand to a send.
  Future<ComposerDraft?> load(ComposerDraftKey key);

  /// Replaces the saved draft. Saving an empty draft clears it.
  Future<void> save(ComposerDraftKey key, ComposerDraft draft);

  /// Removes the saved draft and every copy made for it.
  Future<void> clear(ComposerDraftKey key);
}

/// Stores each chat under `Documents/composer_drafts/<sha256(key)>/` as
/// `draft.json` plus copies of the attached files.
///
/// Picked media lives in temp and cache folders the OS may purge, so a save
/// copies each attachment into the chat folder. A load copies them out again
/// to `restored/`, so a send that consumes the restored files never races a
/// later save or clear of the draft folder.
final class FileComposerDraftStore implements ComposerDraftStore {
  FileComposerDraftStore({
    Future<Directory> Function()? documentsDirectory,
    Future<bool> Function(String path)? excludeFromBackup,
  }) : _documentsDirectory =
           documentsDirectory ?? getApplicationDocumentsDirectory,
       _excludeFromBackup = excludeFromBackup ?? excludeDirectoryFromBackup;

  final Future<Directory> Function() _documentsDirectory;
  final Future<bool> Function(String path) _excludeFromBackup;
  final Map<String, Future<void>> _tails = {};
  final Map<String, _QueuedSave> _openSaves = {};
  bool _rootExcluded = false;
  int _copyCounter = 0;

  @override
  Future<ComposerDraft?> load(ComposerDraftKey key) {
    _openSaves.remove(key.folderName);
    return _serialized(key, () => _load(key));
  }

  @override
  Future<void> save(ComposerDraftKey key, ComposerDraft draft) {
    final name = key.folderName;
    final open = _openSaves[name];
    if (open != null) {
      // A save still waiting in the queue is replaced, not followed, so a
      // burst of keystrokes costs one write.
      open.draft = draft;
      return open.done;
    }
    final queued = _QueuedSave(draft);
    _openSaves[name] = queued;
    queued.done = _serialized(key, () {
      if (identical(_openSaves[name], queued)) _openSaves.remove(name);
      return _write(key, queued.draft);
    });
    return queued.done;
  }

  @override
  Future<void> clear(ComposerDraftKey key) {
    _openSaves.remove(key.folderName);
    return _serialized(key, () async {
      final root = await _root();
      await _deleteIfExists(Directory(p.join(root.path, key.folderName)));
      await _deleteIfExists(
        Directory(p.join(root.path, _restoredDirectoryName, key.folderName)),
      );
    });
  }

  Future<T> _serialized<T>(ComposerDraftKey key, Future<T> Function() body) {
    final name = key.folderName;
    final previous = _tails[name] ?? Future<void>.value();
    final result = previous.then((_) => body());
    final tail = result.then<void>((_) {}, onError: (_) {});
    _tails[name] = tail;
    unawaited(
      tail.then((_) {
        if (identical(_tails[name], tail)) _tails.remove(name);
      }),
    );
    return result;
  }

  Future<Directory> _root() async {
    final documents = await _documentsDirectory();
    return Directory(p.join(documents.path, kComposerDraftsDirectory));
  }

  Future<bool> _ensureRootExcluded(Directory root) async {
    if (_rootExcluded) return true;
    await root.create(recursive: true);
    try {
      _rootExcluded = await _excludeFromBackup(root.path);
    } on Object {
      _rootExcluded = false;
    }
    return _rootExcluded;
  }

  Future<void> _write(ComposerDraftKey key, ComposerDraft draft) async {
    final root = await _root();
    final folder = Directory(p.join(root.path, key.folderName));
    if (draft.isEmpty) {
      await _deleteIfExists(folder);
      return;
    }
    final canStoreMedia = await _ensureRootExcluded(root);
    final previous = await _readEntries(folder);
    await folder.create(recursive: true);

    final entries = <_MediaEntry>[];
    if (canStoreMedia) {
      for (final media in draft.attachments) {
        final entry = await _retain(folder, media, previous);
        if (entry != null) entries.add(entry);
      }
    }
    final policy = key.allowsPrivateMedia && entries.isNotEmpty
        ? draft.privateMediaPolicy
        : const PrivateMediaPolicy.ordinary();
    if (draft.text.trim().isEmpty && entries.isEmpty) {
      await _deleteIfExists(folder);
      return;
    }
    await _writeJson(
      folder,
      text: draft.text,
      policy: policy,
      entries: entries,
    );

    final kept = {_draftFileName, for (final entry in entries) entry.fileName};
    await for (final entity in folder.list(followLinks: false)) {
      if (!kept.contains(p.basename(entity.path))) {
        await entity.delete(recursive: true);
      }
    }
  }

  Future<_MediaEntry?> _retain(
    Directory folder,
    PendingComposerMedia media,
    List<_MediaEntry> previous,
  ) async {
    final sourcePath = media.file.path;
    if (p.isWithin(folder.path, sourcePath)) {
      final name = p.basename(sourcePath);
      if (!await File(sourcePath).exists()) return null;
      final known = previous.where((entry) => entry.fileName == name);
      return _MediaEntry.of(
        media,
        fileName: name,
        sourcePath: known.isEmpty ? sourcePath : known.first.sourcePath,
        sourceLength: await File(sourcePath).length(),
      );
    }
    final int sourceLength;
    try {
      sourceLength = await media.file.length();
    } on FileSystemException {
      return null;
    }
    for (final entry in previous) {
      if (entry.sourcePath == sourcePath &&
          entry.sourceLength == sourceLength &&
          await File(p.join(folder.path, entry.fileName)).exists()) {
        return _MediaEntry.of(
          media,
          fileName: entry.fileName,
          sourcePath: sourcePath,
          sourceLength: sourceLength,
        );
      }
    }
    final name = _newCopyName(sourcePath);
    final target = p.join(folder.path, name);
    try {
      await media.file.copy('$target.part');
      await File('$target.part').rename(target);
    } on FileSystemException {
      await _deleteFileIfExists(File('$target.part'));
      return null;
    }
    return _MediaEntry.of(
      media,
      fileName: name,
      sourcePath: sourcePath,
      sourceLength: sourceLength,
    );
  }

  Future<ComposerDraft?> _load(ComposerDraftKey key) async {
    final root = await _root();
    final folder = Directory(p.join(root.path, key.folderName));
    final json = await _readJson(folder);
    if (json == null) return null;
    final text = json['text'];
    if (text is! String) return null;
    final entries = _parseEntries(json['attachments']);
    final restoredRoot = Directory(p.join(root.path, _restoredDirectoryName));
    final keyRestored = Directory(p.join(restoredRoot.path, key.folderName));

    final restored = <PendingComposerMedia>[];
    final updatedEntries = <_MediaEntry>[];
    final inUse = <String>{};
    Directory? batch;
    for (final entry in entries) {
      final stored = File(p.join(folder.path, entry.fileName));
      if (!await stored.exists()) continue;
      var working = File(entry.sourcePath);
      final reusable =
          p.isWithin(keyRestored.path, working.path) &&
          await working.exists() &&
          await working.length() == entry.sourceLength;
      if (!reusable) {
        batch ??= Directory(
          p.join(
            keyRestored.path,
            DateTime.now().millisecondsSinceEpoch.toString(),
          ),
        );
        await batch.create(recursive: true);
        working = File(p.join(batch.path, entry.fileName));
        try {
          await stored.copy(working.path);
        } on FileSystemException {
          continue;
        }
      }
      inUse.add(working.parent.path);
      final length = await working.length();
      updatedEntries.add(
        entry.withSource(sourcePath: working.path, sourceLength: length),
      );
      restored.add(
        PendingComposerMedia(
          file: working,
          budgetBytes: entry.budgetBytes,
          width: entry.width,
          height: entry.height,
          durationMs: entry.durationMs,
        ),
      );
    }
    await _sweepRestored(restoredRoot, keep: inUse);

    final policy = key.allowsPrivateMedia && restored.isNotEmpty
        ? PrivateMediaPolicy.fromJson(json['privateMediaPolicy'])
        : const PrivateMediaPolicy.ordinary();
    final draft = ComposerDraft(
      text: text,
      attachments: restored,
      privateMediaPolicy: policy.isUnsupported
          ? const PrivateMediaPolicy.ordinary()
          : policy,
    );
    if (draft.isEmpty) return null;
    await _writeJson(
      folder,
      text: text,
      policy: draft.privateMediaPolicy,
      entries: updatedEntries,
    );
    return draft;
  }

  Future<void> _sweepRestored(
    Directory restoredRoot, {
    required Set<String> keep,
  }) async {
    if (!await restoredRoot.exists()) return;
    final cutoff = DateTime.now().subtract(_restoredCopyMaxAge);
    await for (final keyDir in restoredRoot.list(followLinks: false)) {
      if (keyDir is! Directory) continue;
      await for (final batch in keyDir.list(followLinks: false)) {
        if (keep.contains(batch.path)) continue;
        final stamp = int.tryParse(p.basename(batch.path));
        if (stamp == null ||
            DateTime.fromMillisecondsSinceEpoch(stamp).isBefore(cutoff)) {
          await batch.delete(recursive: true);
        }
      }
    }
  }

  String _newCopyName(String sourcePath) {
    final extension = p.extension(sourcePath).toLowerCase();
    _copyCounter++;
    return 'media_${DateTime.now().microsecondsSinceEpoch}_$_copyCounter$extension';
  }

  Future<void> _writeJson(
    Directory folder, {
    required String text,
    required PrivateMediaPolicy policy,
    required List<_MediaEntry> entries,
  }) async {
    final target = File(p.join(folder.path, _draftFileName));
    final temp = File('${target.path}.tmp');
    await temp.writeAsString(
      jsonEncode(<String, Object?>{
        'version': _draftVersion,
        'text': text,
        'privateMediaPolicy': policy.toJson(),
        'attachments': [for (final entry in entries) entry.toJson()],
      }),
      flush: true,
    );
    await temp.rename(target.path);
  }

  Future<Map<String, Object?>?> _readJson(Directory folder) async {
    final file = File(p.join(folder.path, _draftFileName));
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map || decoded['version'] != _draftVersion) return null;
      return Map<String, Object?>.from(decoded);
    } on FileSystemException {
      return null;
    } on FormatException {
      return null;
    }
  }

  Future<List<_MediaEntry>> _readEntries(Directory folder) async {
    final json = await _readJson(folder);
    return json == null ? const [] : _parseEntries(json['attachments']);
  }

  List<_MediaEntry> _parseEntries(Object? raw) {
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        ?_MediaEntry.tryParse(item),
    ];
  }

  Future<void> _deleteIfExists(Directory directory) async {
    if (await directory.exists()) await directory.delete(recursive: true);
  }

  Future<void> _deleteFileIfExists(File file) async {
    if (await file.exists()) await file.delete();
  }
}

final class _QueuedSave {
  _QueuedSave(this.draft);

  ComposerDraft draft;
  late final Future<void> done;
}

final class _MediaEntry {
  const _MediaEntry({
    required this.fileName,
    required this.sourcePath,
    required this.sourceLength,
    required this.budgetBytes,
    this.width,
    this.height,
    this.durationMs,
  });

  factory _MediaEntry.of(
    PendingComposerMedia media, {
    required String fileName,
    required String sourcePath,
    required int sourceLength,
  }) => _MediaEntry(
    fileName: fileName,
    sourcePath: sourcePath,
    sourceLength: sourceLength,
    budgetBytes: media.budgetBytes,
    width: media.width,
    height: media.height,
    durationMs: media.durationMs,
  );

  static _MediaEntry? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final fileName = raw['file'];
    final sourcePath = raw['source'];
    final sourceLength = raw['sourceLength'];
    final budgetBytes = raw['budgetBytes'];
    if (fileName is! String ||
        fileName != p.basename(fileName) ||
        fileName == _draftFileName ||
        sourcePath is! String ||
        sourceLength is! int ||
        budgetBytes is! int) {
      return null;
    }
    final width = raw['width'];
    final height = raw['height'];
    final durationMs = raw['durationMs'];
    return _MediaEntry(
      fileName: fileName,
      sourcePath: sourcePath,
      sourceLength: sourceLength,
      budgetBytes: budgetBytes,
      width: width is int ? width : null,
      height: height is int ? height : null,
      durationMs: durationMs is int ? durationMs : null,
    );
  }

  final String fileName;
  final String sourcePath;
  final int sourceLength;
  final int budgetBytes;
  final int? width;
  final int? height;
  final int? durationMs;

  _MediaEntry withSource({
    required String sourcePath,
    required int sourceLength,
  }) => _MediaEntry(
    fileName: fileName,
    sourcePath: sourcePath,
    sourceLength: sourceLength,
    budgetBytes: budgetBytes,
    width: width,
    height: height,
    durationMs: durationMs,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'file': fileName,
    'source': sourcePath,
    'sourceLength': sourceLength,
    'budgetBytes': budgetBytes,
    'width': width,
    'height': height,
    'durationMs': durationMs,
  };
}
