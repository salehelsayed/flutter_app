import 'dart:convert';
import 'dart:io';

import 'group_media_ios_disposable_profile.dart';

final RegExp _safeResetToken = RegExp(r'^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$');

typedef GroupMediaIosDeleteDefaultSecureStorage = Future<void> Function();
typedef GroupMediaIosReadDefaultSecureStorage =
    Future<Map<String, String>> Function();
typedef GroupMediaIosBeforePendingResetReceiptCommit = Future<void> Function();
typedef GroupMediaIosBeforeFinalResetReceiptPublish = Future<void> Function();

typedef _ResetRequest = ({String runId, String nonce, String phase});
typedef _OwnedResetPath = ({String path, FileSystemEntityType type});

const List<String> _allowlistedDocumentFiles = <String>[
  'auto_setup.json',
  'intro_e2e_config.json',
  'intro_e2e_result.json',
  'intro_e2e_result.json.tmp',
  'intro_e2e_identity.json',
  'group_media_reliability_state.json',
  'group_media_ios_background_state.json',
];

const List<String> _allowlistedDocumentDirectories = <String>[
  'p269-group-media-ios-fixtures',
  'p269-group-media-fixtures',
  'media',
  'pending_uploads',
  'local_media',
  'post_media',
];

const List<String> _allowlistedApplicationSupportDirectories = <String>[
  groupMediaIosReceiverBootstrapDirectory,
  'NotificationConversationIds',
  'ReactionNotificationClaims',
];

/// Executes the dedicated group-media harness reset before Firebase,
/// repositories, or SQLCipher are opened.
///
/// The active request is a crash-recovery token. A final receipt cannot become
/// visible until that token is absent; a pending receipt is the atomic journal
/// that closes the crash window between those two facts.
Future<bool> runGroupMediaIosDisposableResetIfRequested({
  required Directory documentsDirectory,
  required Directory databasesDirectory,
  required Directory applicationSupportDirectory,
  required String installedProfileId,
  required String installedBundleId,
  String expectedProfileId = groupMediaIosDisposableBuildProfile,
  String expectedBundleId = groupMediaIosDisposableBundleId,
  required GroupMediaIosDeleteDefaultSecureStorage deleteDefaultSecureStorage,
  required GroupMediaIosReadDefaultSecureStorage readDefaultSecureStorage,
  GroupMediaIosBeforePendingResetReceiptCommit? beforePendingResetReceiptCommit,
  GroupMediaIosBeforeFinalResetReceiptPublish? beforeFinalResetReceiptPublish,
  int? currentProcessId,
}) async {
  final documentRoot = documentsDirectory.absolute.path;
  final stagedRequest = File(
    '$documentRoot${Platform.pathSeparator}'
    '$groupMediaIosDisposableResetRequestFile',
  );
  final activeRequest = File(
    '$documentRoot${Platform.pathSeparator}'
    '$groupMediaIosDisposableResetActiveRequestFile',
  );
  final receipt = File(
    '$documentRoot${Platform.pathSeparator}'
    '$groupMediaIosDisposableResetReceiptFile',
  );
  final pendingReceipt = File('${receipt.path}.tmp');
  final writingReceipt = File('${receipt.path}.writing');
  final protocolFiles = <File>[
    stagedRequest,
    activeRequest,
    receipt,
    pendingReceipt,
    writingReceipt,
  ];
  _validateProtocolFileTypes(protocolFiles);
  if (!_isRegularFile(stagedRequest) &&
      !_isRegularFile(activeRequest) &&
      !_isRegularFile(pendingReceipt) &&
      !_isRegularFile(writingReceipt)) {
    return false;
  }
  if (installedProfileId != expectedProfileId ||
      installedBundleId != expectedBundleId) {
    throw StateError('disposable group-media reset profile rejected');
  }
  final processId = currentProcessId ?? pid;
  if (processId <= 0) {
    throw StateError('disposable group-media reset process rejected');
  }
  await _validateAllowlistedEntityTypes(
    _allowlistedPaths(
      documentsDirectory: documentsDirectory,
      databasesDirectory: databasesDirectory,
      applicationSupportDirectory: applicationSupportDirectory,
    ),
  );

  var handled = false;
  for (var transition = 0; transition < 8; transition += 1) {
    _validateProtocolFileTypes(protocolFiles);
    if (_isRegularFile(writingReceipt)) {
      // `.writing` is deliberately never authoritative: a process can die
      // after creating it or after flushing only a prefix. Discarding this
      // exact app-owned file preserves any active request for an idempotent
      // retry and any independently staged request for the following pass.
      await _deleteExactFile(writingReceipt);
    }
    if (_isRegularFile(pendingReceipt)) {
      final pending = _decodeReceipt(
        pendingReceipt,
        expectedProfileId: expectedProfileId,
        expectedBundleId: expectedBundleId,
      );
      if (_isRegularFile(activeRequest)) {
        final active = _decodeRequest(activeRequest);
        if (!_sameRequest(active, pending)) {
          throw const FormatException(
            'pending receipt does not own the active reset request',
          );
        }
        // A final receipt must never coexist with the active request that its
        // pending journal is about to retire. Removing an older receipt first
        // makes the active -> pending -> final transition observable and
        // fail-closed across interruption at every await below.
        await _deleteExactFile(receipt);
        await beforeFinalResetReceiptPublish?.call();
        await activeRequest.delete();
      }
      if (_isRegularFile(stagedRequest)) {
        final staged = _decodeRequest(stagedRequest);
        if (_sameRequest(staged, pending)) await stagedRequest.delete();
      }
      await _deleteExactFile(receipt);
      await pendingReceipt.rename(receipt.path);
      handled = true;
      if (!_isRegularFile(stagedRequest)) {
        return true;
      }
      continue;
    }

    final hasStaged = _isRegularFile(stagedRequest);
    final hasActive = _isRegularFile(activeRequest);
    if (!hasStaged && !hasActive) {
      return handled;
    }
    if (hasStaged && hasActive) {
      final staged = _decodeRequest(stagedRequest);
      final active = _decodeRequest(activeRequest);
      if (_sameRequest(staged, active)) await stagedRequest.delete();
    } else if (hasStaged) {
      await stagedRequest.rename(activeRequest.path);
    }

    final request = _decodeRequest(activeRequest);
    await _deleteExactFile(receipt);
    await _performAllowlistedReset(
      documentsDirectory: documentsDirectory,
      databasesDirectory: databasesDirectory,
      applicationSupportDirectory: applicationSupportDirectory,
      deleteDefaultSecureStorage: deleteDefaultSecureStorage,
      readDefaultSecureStorage: readDefaultSecureStorage,
    );
    final allowlistedPaths = _allowlistedPaths(
      documentsDirectory: documentsDirectory,
      databasesDirectory: databasesDirectory,
      applicationSupportDirectory: applicationSupportDirectory,
    );
    if (allowlistedPaths.any((owned) => _entityExists(owned.path))) {
      throw StateError(
        'disposable group-media allowlisted reset did not converge',
      );
    }
    await writingReceipt.writeAsString(
      '${jsonEncode(<String, Object?>{'schema': groupMediaIosDisposableResetReceiptSchema, 'run_id': request.runId, 'nonce': request.nonce, 'phase': request.phase, 'process_id': processId, 'bundle_id': installedBundleId, 'profile': installedProfileId, 'keychain_empty': true, 'database_absent': true, 'allowlisted_files_absent': true, 'contains_secrets': false})}\n',
      flush: true,
    );
    await beforePendingResetReceiptCommit?.call();
    if (_entityExists(pendingReceipt.path)) {
      throw StateError(
        'disposable group-media pending reset receipt already exists',
      );
    }
    await writingReceipt.rename(pendingReceipt.path);
    handled = true;
  }
  throw StateError('disposable group-media reset state did not converge');
}

Future<void> _performAllowlistedReset({
  required Directory documentsDirectory,
  required Directory databasesDirectory,
  required Directory applicationSupportDirectory,
  required GroupMediaIosDeleteDefaultSecureStorage deleteDefaultSecureStorage,
  required GroupMediaIosReadDefaultSecureStorage readDefaultSecureStorage,
}) async {
  final allowlistedPaths = _allowlistedPaths(
    documentsDirectory: documentsDirectory,
    databasesDirectory: databasesDirectory,
    applicationSupportDirectory: applicationSupportDirectory,
  );
  await _validateAllowlistedEntityTypes(allowlistedPaths);
  await deleteDefaultSecureStorage();
  if ((await readDefaultSecureStorage()).isNotEmpty) {
    throw StateError('disposable group-media secure reset did not converge');
  }
  for (final owned in allowlistedPaths) {
    await _deleteExactEntity(owned);
  }
}

List<_OwnedResetPath> _allowlistedPaths({
  required Directory documentsDirectory,
  required Directory databasesDirectory,
  required Directory applicationSupportDirectory,
}) {
  final documentRoot = documentsDirectory.absolute.path;
  final database =
      '${databasesDirectory.absolute.path}${Platform.pathSeparator}identity.db';
  const sqliteSuffixes = <String>['', '-wal', '-shm', '-journal'];
  return <_OwnedResetPath>[
    for (final base in <String>[
      database,
      '$database.rekey-tmp',
      '$database.pre-raw.bak',
    ])
      for (final suffix in sqliteSuffixes)
        (path: '$base$suffix', type: FileSystemEntityType.file),
    for (final name in _allowlistedDocumentFiles)
      (
        path: '$documentRoot${Platform.pathSeparator}$name',
        type: FileSystemEntityType.file,
      ),
    for (final name in _allowlistedDocumentDirectories)
      (
        path: '$documentRoot${Platform.pathSeparator}$name',
        type: FileSystemEntityType.directory,
      ),
    for (final name in _allowlistedApplicationSupportDirectories)
      (
        path:
            '${applicationSupportDirectory.absolute.path}'
            '${Platform.pathSeparator}$name',
        type: FileSystemEntityType.directory,
      ),
  ];
}

_ResetRequest _decodeRequest(File file) {
  final value = _decodeObject(file, 'reset request');
  const keys = <String>{
    'schema',
    'run_id',
    'nonce',
    'phase',
    'contains_secrets',
  };
  final runId = value['run_id'];
  final nonce = value['nonce'];
  final phase = value['phase'];
  if (value.keys.toSet().length != keys.length ||
      !value.keys.toSet().containsAll(keys) ||
      value['schema'] != groupMediaIosDisposableResetRequestSchema ||
      runId is! String ||
      !_safeResetToken.hasMatch(runId) ||
      nonce is! String ||
      !_safeResetToken.hasMatch(nonce) ||
      phase is! String ||
      !groupMediaIosDisposableResetPhases.contains(phase) ||
      value['contains_secrets'] != false) {
    throw const FormatException(
      'disposable group-media reset request rejected',
    );
  }
  return (runId: runId, nonce: nonce, phase: phase);
}

_ResetRequest _decodeReceipt(
  File file, {
  required String expectedProfileId,
  required String expectedBundleId,
}) {
  final value = _decodeObject(file, 'pending reset receipt');
  const keys = <String>{
    'schema',
    'run_id',
    'nonce',
    'phase',
    'process_id',
    'bundle_id',
    'profile',
    'keychain_empty',
    'database_absent',
    'allowlisted_files_absent',
    'contains_secrets',
  };
  final runId = value['run_id'];
  final nonce = value['nonce'];
  final phase = value['phase'];
  final processId = value['process_id'];
  if (value.keys.toSet().length != keys.length ||
      !value.keys.toSet().containsAll(keys) ||
      value['schema'] != groupMediaIosDisposableResetReceiptSchema ||
      runId is! String ||
      !_safeResetToken.hasMatch(runId) ||
      nonce is! String ||
      !_safeResetToken.hasMatch(nonce) ||
      phase is! String ||
      !groupMediaIosDisposableResetPhases.contains(phase) ||
      processId is! int ||
      processId <= 0 ||
      value['bundle_id'] != expectedBundleId ||
      value['profile'] != expectedProfileId ||
      value['keychain_empty'] != true ||
      value['database_absent'] != true ||
      value['allowlisted_files_absent'] != true ||
      value['contains_secrets'] != false) {
    throw const FormatException(
      'disposable group-media pending receipt rejected',
    );
  }
  return (runId: runId, nonce: nonce, phase: phase);
}

Map<String, Object?> _decodeObject(File file, String label) {
  if (!_isRegularFile(file)) {
    throw FormatException('disposable group-media $label is not a file');
  }
  final decoded = jsonDecode(file.readAsStringSync());
  if (decoded is! Map) {
    throw FormatException('disposable group-media $label rejected');
  }
  return decoded.map<String, Object?>((key, value) => MapEntry('$key', value));
}

bool _sameRequest(_ResetRequest left, _ResetRequest right) =>
    left.runId == right.runId &&
    left.nonce == right.nonce &&
    left.phase == right.phase;

bool _isRegularFile(File file) =>
    FileSystemEntity.typeSync(file.path, followLinks: false) ==
    FileSystemEntityType.file;

bool _entityExists(String path) =>
    FileSystemEntity.typeSync(path, followLinks: false) !=
    FileSystemEntityType.notFound;

void _validateProtocolFileTypes(Iterable<File> files) {
  for (final file in files) {
    final type = FileSystemEntity.typeSync(file.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw const FormatException(
        'disposable group-media reset token type rejected',
      );
    }
  }
}

Future<void> _validateAllowlistedEntityTypes(
  Iterable<_OwnedResetPath> entities,
) async {
  for (final entity in entities) {
    final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) continue;
    if (type != entity.type) {
      throw const FormatException(
        'disposable group-media allowlisted entity type rejected',
      );
    }
    if (type == FileSystemEntityType.directory) {
      await _validateOwnedDirectoryTree(Directory(entity.path));
    }
  }
}

Future<void> _validateOwnedDirectoryTree(Directory directory) async {
  await for (final entity in directory.list(followLinks: false)) {
    final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
    if (type == FileSystemEntityType.file) continue;
    if (type == FileSystemEntityType.directory) {
      await _validateOwnedDirectoryTree(Directory(entity.path));
      continue;
    }
    throw const FormatException(
      'disposable group-media allowlisted entity type rejected',
    );
  }
}

Future<void> _deleteExactFile(File file) async {
  final type = FileSystemEntity.typeSync(file.path, followLinks: false);
  if (type == FileSystemEntityType.notFound) return;
  if (type != FileSystemEntityType.file) {
    throw const FormatException('disposable group-media receipt type rejected');
  }
  await file.delete();
}

Future<void> _deleteExactEntity(_OwnedResetPath entity) async {
  final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
  switch (type) {
    case FileSystemEntityType.notFound:
      return;
    case FileSystemEntityType.file:
      if (entity.type != FileSystemEntityType.file) {
        throw const FormatException(
          'disposable group-media allowlisted entity type rejected',
        );
      }
      await File(entity.path).delete();
      return;
    case FileSystemEntityType.directory:
      if (entity.type != FileSystemEntityType.directory) {
        throw const FormatException(
          'disposable group-media allowlisted entity type rejected',
        );
      }
      await _validateOwnedDirectoryTree(Directory(entity.path));
      await Directory(entity.path).delete(recursive: true);
      return;
    case FileSystemEntityType.link:
    case FileSystemEntityType.unixDomainSock:
    case FileSystemEntityType.pipe:
      throw const FormatException(
        'disposable group-media allowlisted entity type rejected',
      );
    default:
      throw const FormatException(
        'disposable group-media allowlisted entity type rejected',
      );
  }
}
