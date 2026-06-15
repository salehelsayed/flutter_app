import 'dart:typed_data';

import 'package:flutter_app/features/account_migration/application/migration_segment_crypto.dart';
import 'package:flutter_app/features/account_migration/application/migration_transfer_checkpoint_store.dart';
import 'package:flutter_app/features/account_migration/domain/models/migration_transfer_manifest.dart';

enum MigrationTransferResultCode {
  success,
  noLocalPath,
  relayOrCloudForbidden,
  manifestRejected,
  missingSegment,
  sendRejected,
  checkpointConflict,
  cryptoRejected,
  transferTimedOut,
}

class MigrationTransferResult {
  final MigrationTransferResultCode code;
  final List<int> missingSegmentIndexes;

  const MigrationTransferResult._(
    this.code, {
    this.missingSegmentIndexes = const [],
  });

  const MigrationTransferResult.success()
    : this._(MigrationTransferResultCode.success);

  const MigrationTransferResult.noLocalPath()
    : this._(MigrationTransferResultCode.noLocalPath);

  const MigrationTransferResult.relayOrCloudForbidden()
    : this._(MigrationTransferResultCode.relayOrCloudForbidden);

  const MigrationTransferResult.manifestRejected()
    : this._(MigrationTransferResultCode.manifestRejected);

  const MigrationTransferResult.missingSegment(List<int> missing)
    : this._(
        MigrationTransferResultCode.missingSegment,
        missingSegmentIndexes: missing,
      );

  const MigrationTransferResult.sendRejected()
    : this._(MigrationTransferResultCode.sendRejected);

  const MigrationTransferResult.checkpointConflict()
    : this._(MigrationTransferResultCode.checkpointConflict);

  const MigrationTransferResult.cryptoRejected()
    : this._(MigrationTransferResultCode.cryptoRejected);

  const MigrationTransferResult.transferTimedOut()
    : this._(MigrationTransferResultCode.transferTimedOut);

  bool get isSuccess => code == MigrationTransferResultCode.success;
}

typedef MigrationLocalSegmentSender =
    Future<bool> Function(MigrationEncryptedSegment segment);

MigrationSegmentAssociatedData migrationSegmentAssociatedDataFor({
  required MigrationTransferManifest manifest,
  required MigrationTransferSegmentDescriptor descriptor,
}) {
  return MigrationSegmentAssociatedData(
    sessionId: manifest.sessionId,
    bundleId: manifest.bundleId,
    segmentIndex: descriptor.index,
    offset: descriptor.offset,
    plaintextLength: descriptor.plaintextLength,
    manifestSha256: manifest.manifestSha256,
  );
}

class MigrationSegmentedTransferService {
  final MigrationSegmentCrypto crypto;
  final MigrationTransferCheckpointStore checkpointStore;

  const MigrationSegmentedTransferService({
    required this.crypto,
    required this.checkpointStore,
  });

  Future<MigrationTransferResult> exportSegments({
    required MigrationTransferManifest manifest,
    required Map<int, Uint8List> plaintextSegments,
    required String recipientMlKemPublicKey,
    required bool localPathAvailable,
    bool relayOrCloudFallbackRequested = false,
    required MigrationLocalSegmentSender sendLocalSegment,
  }) async {
    if (relayOrCloudFallbackRequested) {
      return const MigrationTransferResult.relayOrCloudForbidden();
    }
    if (!localPathAvailable) {
      return const MigrationTransferResult.noLocalPath();
    }
    if (!manifest.compatibility().isAccepted) {
      return const MigrationTransferResult.manifestRejected();
    }

    final verified = await checkpointStore.loadVerified(
      sessionId: manifest.sessionId,
      bundleId: manifest.bundleId,
    );
    final verifiedIndexes = verified.map((segment) => segment.index).toSet();

    for (final descriptor in manifest.orderedSegments) {
      if (verifiedIndexes.contains(descriptor.index)) {
        continue;
      }
      final plaintext = plaintextSegments[descriptor.index];
      if (plaintext == null) {
        return MigrationTransferResult.missingSegment([descriptor.index]);
      }
      if (!_plaintextMatchesDescriptor(plaintext, descriptor)) {
        return const MigrationTransferResult.manifestRejected();
      }

      final MigrationEncryptedSegment encrypted;
      try {
        encrypted = await crypto.encryptSegment(
          plaintext: plaintext,
          recipientMlKemPublicKey: recipientMlKemPublicKey,
          associatedData: migrationSegmentAssociatedDataFor(
            manifest: manifest,
            descriptor: descriptor,
          ),
        );
      } on MigrationSegmentCryptoException {
        return const MigrationTransferResult.cryptoRejected();
      }
      if (encrypted.nonce != descriptor.nonce ||
          encrypted.ciphertextSha256 != descriptor.ciphertextSha256) {
        return const MigrationTransferResult.manifestRejected();
      }
      final sent = await sendLocalSegment(encrypted);
      if (!sent) {
        return const MigrationTransferResult.sendRejected();
      }
    }
    return const MigrationTransferResult.success();
  }

  Future<MigrationTransferResult> importSegments({
    required MigrationTransferManifest manifest,
    required Iterable<MigrationEncryptedSegment> encryptedSegments,
    required String ownMlKemSecretKey,
  }) async {
    if (!manifest.compatibility().isAccepted) {
      return const MigrationTransferResult.manifestRejected();
    }
    final descriptors = {
      for (final descriptor in manifest.segments) descriptor.index: descriptor,
    };

    for (final encrypted in encryptedSegments) {
      final descriptor = descriptors[encrypted.index];
      if (descriptor == null ||
          encrypted.nonce != descriptor.nonce ||
          encrypted.ciphertextSha256 != descriptor.ciphertextSha256) {
        return const MigrationTransferResult.manifestRejected();
      }

      final Uint8List plaintext;
      try {
        plaintext = await crypto.decryptSegment(
          encryptedSegment: encrypted,
          ownMlKemSecretKey: ownMlKemSecretKey,
          associatedData: migrationSegmentAssociatedDataFor(
            manifest: manifest,
            descriptor: descriptor,
          ),
        );
      } on MigrationSegmentCryptoException {
        return const MigrationTransferResult.cryptoRejected();
      }
      if (!_plaintextMatchesDescriptor(plaintext, descriptor)) {
        return const MigrationTransferResult.cryptoRejected();
      }

      final writeResult = await checkpointStore.markVerified(
        sessionId: manifest.sessionId,
        bundleId: manifest.bundleId,
        segment: MigrationVerifiedSegment(
          index: descriptor.index,
          plaintextLength: descriptor.plaintextLength,
          plaintextSha256: descriptor.plaintextSha256,
          ciphertextSha256: descriptor.ciphertextSha256,
        ),
      );
      if (writeResult == MigrationCheckpointWriteResult.conflict) {
        return const MigrationTransferResult.checkpointConflict();
      }
    }

    final missing = await migrationMissingSegmentIndexes(
      checkpointStore: checkpointStore,
      manifest: manifest,
    );
    if (missing.isNotEmpty) {
      return MigrationTransferResult.missingSegment(missing);
    }
    return const MigrationTransferResult.success();
  }

  bool _plaintextMatchesDescriptor(
    Uint8List plaintext,
    MigrationTransferSegmentDescriptor descriptor,
  ) {
    return plaintext.length == descriptor.plaintextLength &&
        migrationTransferSha256Hex(plaintext) == descriptor.plaintextSha256;
  }
}
