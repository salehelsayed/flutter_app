import 'dart:io';

import 'package:path/path.dart' as p;

const migrationSecureValuesEstimateBytes = 64 * 1024;
const migrationMediaRootDirectories = <String>[
  'media',
  'local_media',
  'post_media',
  'pending_uploads',
];
/// Measured ceiling from the P0-7 Pixel benchmark on the protocol v2
/// entry-streamed path (2026-06-11): 200/500/1000/2000/10000 MB all passed
/// with a FLAT ~95-140 MB RSS delta — memory is size-independent (v1 OOM'd
/// at 1000 MB). The 10,000 MB run took 55.2 min wall at ~3 MB/s loopback
/// with the screen held on; the receiver-side storage preflight (2x staging
/// amplification) remains the hard disk gate. The cap equals the largest
/// measured passing run. Never remove this cap — only raise it to new
/// measured ceilings.
const accountMigrationMaxAccountBytes = 10000 * 1024 * 1024;

class AccountMigrationMoveSizeEstimate {
  final int databaseBytes;
  final int mediaBytes;
  final int secureBytes;

  const AccountMigrationMoveSizeEstimate({
    required this.databaseBytes,
    required this.mediaBytes,
    required this.secureBytes,
  });

  int get totalBytes => databaseBytes + mediaBytes + secureBytes;
}

class MigrationScannedFile {
  final String absolutePath;
  final int sizeBytes;

  const MigrationScannedFile({
    required this.absolutePath,
    required this.sizeBytes,
  });
}

abstract class MigrationSizeScanIo {
  Future<int?> fileLength(String absolutePath);

  Stream<MigrationScannedFile> listFilesRecursively(String rootAbsolutePath);
}

class MigrationDartIoSizeScanIo implements MigrationSizeScanIo {
  const MigrationDartIoSizeScanIo();

  @override
  Future<int?> fileLength(String absolutePath) async {
    try {
      final file = File(absolutePath);
      if (!await file.exists()) return null;
      return file.length();
    } on FileSystemException {
      return null;
    }
  }

  @override
  Stream<MigrationScannedFile> listFilesRecursively(
    String rootAbsolutePath,
  ) async* {
    final root = Directory(rootAbsolutePath);
    try {
      if (!await root.exists()) return;
      await for (final entity in root.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) continue;
        try {
          yield MigrationScannedFile(
            absolutePath: entity.path,
            sizeBytes: await entity.length(),
          );
        } on FileSystemException {
          // Size estimation is advisory; unreadable files are handled by the
          // real bundle builder later if the move is otherwise allowed.
        }
      }
    } on FileSystemException {
      return;
    }
  }
}

class AccountMigrationAccountSizeEstimator {
  final String databasePath;
  final String documentsRootPath;
  final MigrationSizeScanIo io;
  final int secureBytesEstimate;

  const AccountMigrationAccountSizeEstimator({
    required this.databasePath,
    required this.documentsRootPath,
    this.io = const MigrationDartIoSizeScanIo(),
    this.secureBytesEstimate = migrationSecureValuesEstimateBytes,
  });

  Future<AccountMigrationMoveSizeEstimate> call() async {
    final databaseBytes = await io.fileLength(databasePath) ?? 0;
    var mediaBytes = 0;
    for (final root in migrationMediaRootDirectories) {
      await for (final file in io.listFilesRecursively(
        p.join(documentsRootPath, root),
      )) {
        mediaBytes += file.sizeBytes;
      }
    }
    return AccountMigrationMoveSizeEstimate(
      databaseBytes: databaseBytes,
      mediaBytes: mediaBytes,
      secureBytes: secureBytesEstimate,
    );
  }
}

class AccountMigrationSizePolicy {
  final int maxAccountBytes;

  const AccountMigrationSizePolicy({required this.maxAccountBytes});

  const AccountMigrationSizePolicy.production()
    : maxAccountBytes = accountMigrationMaxAccountBytes;
}

class AccountMigrationSizeGate {
  final Future<AccountMigrationMoveSizeEstimate> Function() estimateMoveSize;
  final AccountMigrationSizePolicy policy;

  const AccountMigrationSizeGate({
    required this.estimateMoveSize,
    this.policy = const AccountMigrationSizePolicy.production(),
  });
}

String accountMigrationSizeCapBlockedMessage({
  required int totalBytes,
  required int maxAccountBytes,
}) {
  return 'This account is too large to move '
      '(${_displayMegabytes(totalBytes)} MB of '
      '${_displayMegabytes(maxAccountBytes)} MB max)';
}

String accountMigrationSizeEstimateLabel(int totalBytes) {
  return 'Account size: about ${_displayMegabytes(totalBytes)} MB';
}

/// Shown on the old phone when the new phone could not even probe its free
/// space — distinct from a genuinely full disk so the user does not start
/// deleting content over a transient probe failure.
const accountMigrationReceiverStorageUnavailableMessage =
    'The new phone could not check its free space for this move. '
    'Restart the app on the new phone and try again.';

/// Shown on the old phone when the new phone rejected the move for lack of
/// disk space. With the receiver's numbers available the copy spells out the
/// exact shortfall; without them it falls back to generic wording.
String accountMigrationReceiverStorageInsufficientMessage({
  int? requiredBytes,
  int? availableBytes,
}) {
  if (requiredBytes == null || requiredBytes <= 0 || availableBytes == null) {
    return 'The new phone does not have enough free space to receive this '
        'account. Free space on the new phone and try again.';
  }
  final shortfallMb = _displayMegabytes(requiredBytes - availableBytes);
  return 'The new phone does not have enough free space to receive this '
      'account: the move needs about ${_displayMegabytes(requiredBytes)} MB '
      'free, but only ${_displayMegabytes(availableBytes)} MB is available. '
      'Free up at least ${shortfallMb < 1 ? 1 : shortfallMb} MB on the new '
      'phone and try again.';
}

/// Whole-MB display rounding shared by all migration size copy.
int accountMigrationDisplayMegabytes(int bytes) {
  if (bytes <= 0) return 0;
  const mb = 1024 * 1024;
  return (bytes + mb - 1) ~/ mb;
}

int _displayMegabytes(int bytes) => accountMigrationDisplayMegabytes(bytes);
