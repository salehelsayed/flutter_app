import 'dart:io';

import 'package:flutter_app/core/media/app_owned_media_path_authority.dart';
import 'package:flutter_app/core/media/media_file_manager.dart';
import 'package:flutter_app/core/media/received_media_egress.dart';
import 'package:flutter_app/core/media/received_media_egress_gateway.dart';

typedef StoredMediaPathResolver = Future<String> Function(String storedPath);
typedef DocumentsDirectoryProvider = Future<Directory> Function();

class ReceivedMediaEgressService {
  ReceivedMediaEgressService({
    ReceivedMediaEgressGateway? gateway,
    StoredMediaPathResolver? resolveStoredPath,
    DocumentsDirectoryProvider? documentsDirectory,
    AppOwnedMediaPathAuthority? pathAuthority,
  }) : _gateway = gateway ?? ReceivedMediaEgressChannel(),
       _resolveStoredPath =
           resolveStoredPath ?? MediaFileManager().resolveStoredPath,
       _pathAuthority =
           pathAuthority ??
           IoAppOwnedMediaPathAuthority(documentsDirectory: documentsDirectory);

  final ReceivedMediaEgressGateway _gateway;
  final StoredMediaPathResolver _resolveStoredPath;
  final AppOwnedMediaPathAuthority _pathAuthority;

  Future<MediaEgressResult> perform({
    required String requestId,
    required MediaEgressDestination destination,
    required List<ReceivedMediaEgressCandidate> selection,
  }) async {
    if (!isValidMediaEgressRequestId(requestId) || selection.isEmpty) {
      return MediaEgressResult(
        requestId: requestId,
        outcome: MediaEgressOutcome.rejected,
        items: const [],
      );
    }

    final firstById = <String, ReceivedMediaEgressCandidate>{};
    final conflicted = <String>{};
    for (final candidate in selection) {
      final first = firstById[candidate.attachmentId];
      if (first == null) {
        firstById[candidate.attachmentId] = candidate;
      } else if (first.storedPath != candidate.storedPath ||
          first.mime != candidate.mime) {
        conflicted.add(candidate.attachmentId);
      }
    }
    if (firstById.length > kMaxMediaEgressItems) {
      return MediaEgressResult(
        requestId: requestId,
        outcome: MediaEgressOutcome.rejected,
        items: const [],
      );
    }

    final nativeItems = <MediaEgressItem>[];
    final structural = <String, MediaEgressItemResult>{};
    for (final entry in firstById.entries) {
      final candidate = entry.value;
      if (candidate.attachmentId.trim().isEmpty ||
          conflicted.contains(entry.key)) {
        structural[entry.key] = MediaEgressItemResult(
          attachmentId: entry.key,
          outcome: MediaEgressItemOutcome.identityConflict,
        );
        continue;
      }
      if (!isSupportedMediaEgressMime(candidate.mime)) {
        structural[entry.key] = MediaEgressItemResult(
          attachmentId: entry.key,
          outcome: MediaEgressItemOutcome.unsupportedType,
        );
        continue;
      }
      String resolved;
      try {
        resolved = await _resolveStoredPath(candidate.storedPath);
      } catch (_) {
        structural[entry.key] = MediaEgressItemResult(
          attachmentId: entry.key,
          outcome: MediaEgressItemOutcome.missingFile,
        );
        continue;
      }
      final file = File(resolved);
      bool exists;
      try {
        exists = await file.exists();
      } catch (_) {
        exists = false;
      }
      if (!exists) {
        structural[entry.key] = MediaEgressItemResult(
          attachmentId: entry.key,
          outcome: MediaEgressItemOutcome.missingFile,
        );
        continue;
      }
      String? canonical;
      try {
        canonical = await _pathAuthority.authorize(resolved);
      } catch (_) {
        canonical = null;
      }
      if (canonical == null) {
        structural[entry.key] = MediaEgressItemResult(
          attachmentId: entry.key,
          outcome: MediaEgressItemOutcome.outsideOwnedRoot,
        );
        continue;
      }
      nativeItems.add(
        MediaEgressItem(
          attachmentId: entry.key,
          sourcePath: canonical,
          mime: candidate.mime.toLowerCase(),
          displayName: mediaEgressDisplayName(entry.key, candidate.mime),
        ),
      );
    }

    if (destination == MediaEgressDestination.share && structural.isNotEmpty) {
      return MediaEgressResult(
        requestId: requestId,
        outcome: MediaEgressOutcome.rejected,
        items: const [],
      );
    }
    if (nativeItems.isEmpty) {
      final items = firstById.keys
          .map((id) => structural[id]!)
          .toList(growable: false);
      return MediaEgressResult(
        requestId: requestId,
        outcome: _aggregate(items),
        items: items,
      );
    }

    final nativeResult = await _gateway.perform(
      MediaEgressRequest(
        requestId: requestId,
        destination: destination,
        items: nativeItems,
      ),
    );
    if (destination == MediaEgressDestination.share) return nativeResult;
    final nativeById = {
      for (final item in nativeResult.items) item.attachmentId: item,
    };
    final merged = firstById.keys
        .map(
          (id) =>
              structural[id] ??
              nativeById[id] ??
              MediaEgressItemResult(
                attachmentId: id,
                outcome: MediaEgressItemOutcome.platformFailure,
              ),
        )
        .toList(growable: false);
    return MediaEgressResult(
      requestId: requestId,
      outcome: _aggregate(merged),
      items: merged,
    );
  }

  MediaEgressOutcome _aggregate(List<MediaEgressItemResult> items) {
    if (items.every((item) => item.outcome == MediaEgressItemOutcome.saved)) {
      return MediaEgressOutcome.saved;
    }
    if (items.any((item) => item.outcome == MediaEgressItemOutcome.saved)) {
      return MediaEgressOutcome.partial;
    }
    if (items.any(
      (item) => item.outcome == MediaEgressItemOutcome.platformFailure,
    )) {
      return MediaEgressOutcome.platformFailure;
    }
    if (items.any(
      (item) => item.outcome == MediaEgressItemOutcome.permissionDenied,
    )) {
      return MediaEgressOutcome.permissionDenied;
    }
    // A busy native boundary means none of the native-eligible items started.
    // Structural rejects merged beside them must not rewrite that retryable
    // operation-level truth to `rejected`.
    if (items.any((item) => item.outcome == MediaEgressItemOutcome.busy)) {
      return MediaEgressOutcome.busy;
    }
    if (items.every(
      (item) => item.outcome == MediaEgressItemOutcome.cancelled,
    )) {
      return MediaEgressOutcome.cancelled;
    }
    if (items.every((item) => item.outcome == MediaEgressItemOutcome.busy)) {
      return MediaEgressOutcome.busy;
    }
    return MediaEgressOutcome.rejected;
  }
}
