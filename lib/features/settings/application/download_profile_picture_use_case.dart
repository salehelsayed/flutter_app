import 'dart:io';
import 'dart:math';

import 'package:flutter/painting.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/utils/transient_transport_error.dart';
import 'package:flutter_app/features/settings/application/helpers/avatar_normalization_helper.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Signature of [downloadProfilePicture] for dependency injection.
typedef DownloadProfilePictureFn =
    Future<ContactModel?> Function({
      required Bridge bridge,
      required ContactRepository contactRepo,
      required String ownerPeerId,
      required String avatarVersion,
      bool retryPendingRequest,
    });

final _activeProfileDownloads = Expando<Set<String>>();

/// Downloads a peer's profile picture from the relay and updates the contact.
///
/// 1. Resolves output path in local avatars directory
/// 2. Calls bridge to download the profile from the relay
/// 3. Updates contact with avatarPath and avatarVersion
///
/// Returns the updated [ContactModel] on success, null on failure.
Future<ContactModel?> downloadProfilePicture({
  required Bridge bridge,
  required ContactRepository contactRepo,
  required String ownerPeerId,
  required String avatarVersion,
  bool retryPendingRequest = false,
  AvatarNormalizationHelper? avatarNormalizer,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'DOWNLOAD_PROFILE_PICTURE_START',
    details: {'ownerPeerId': ownerPeerId, 'avatarVersion': avatarVersion},
  );

  File? retryRequest;
  String? downloadPath;
  var retainRequest = false;
  final active = _activeProfileDownloads[bridge] ??= <String>{};
  var ownsDownload = false;
  try {
    final contact = await contactRepo.getContact(ownerPeerId);
    if (contact == null || contact.isBlocked) return null;

    // 1. Resolve output path
    final appDir = await getApplicationDocumentsDirectory();
    final avatarsDir = Directory(p.join(appDir.path, 'media', 'avatars'));
    if (!avatarsDir.existsSync()) {
      avatarsDir.createSync(recursive: true);
    }

    retryRequest = _profileRetryRequest(avatarsDir.path, ownerPeerId);
    if (retryPendingRequest) {
      // Replays may have awaited contact/path resolution after a newer event.
      // Only a fresh request may replace the durable desired version.
      if (!retryRequest.existsSync() ||
          retryRequest.readAsStringSync() != avatarVersion) {
        return null;
      }
    } else {
      retryRequest.writeAsStringSync(avatarVersion, flush: true);
    }
    if (!active.add(ownerPeerId)) {
      retainRequest = true;
      return null;
    }
    ownsDownload = true;
    final canonicalPath = p.join(avatarsDir.path, '$ownerPeerId.jpg');
    downloadPath = p.join(
      avatarsDir.path,
      '$ownerPeerId.raw.${_uniqueSuffix()}.jpg',
    );

    // 2. Download from relay
    late final Map<String, dynamic> result;
    try {
      result = await callP2PProfileDownload(
        bridge,
        ownerPeerId: ownerPeerId,
        outputPath: downloadPath,
      );
    } catch (error) {
      retainRequest = TransientTransportError.matches(error);
      rethrow;
    }

    if (result['ok'] != true) {
      retainRequest = TransientTransportError.matches(
        result['errorMessage'],
        code: result['errorCode'],
      );
      emitFlowEvent(
        layer: 'FL',
        event: 'DOWNLOAD_PROFILE_PICTURE_DOWNLOAD_FAILED',
        details: {'error': result['errorMessage']},
      );
      return null;
    }

    // A newer profile event may have arrived while this transfer was active.
    if (retryRequest.readAsStringSync() != avatarVersion) return null;

    final normalizer = avatarNormalizer ?? AvatarNormalizationHelper();
    final committedPath = await normalizer.normalizeAvatar(
      inputPath: downloadPath,
      canonicalPath: canonicalPath,
    );

    // 3. Evict Flutter image cache so UserAvatar picks up the new file
    FileImage(File(committedPath)).evict();
    UserAvatar.invalidatePeer(ownerPeerId);

    // 4. Update contact
    final currentContact = await contactRepo.getContact(ownerPeerId);
    if (currentContact == null || currentContact.isBlocked) return null;

    final relativePath = p.join('media', 'avatars', '$ownerPeerId.jpg');
    final updated = currentContact.copyWith(
      avatarPath: relativePath,
      avatarVersion: avatarVersion,
    );
    await contactRepo.addContact(updated);

    emitFlowEvent(
      layer: 'FL',
      event: 'DOWNLOAD_PROFILE_PICTURE_SUCCESS',
      details: {'ownerPeerId': ownerPeerId, 'avatarVersion': avatarVersion},
    );

    return updated;
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'DOWNLOAD_PROFILE_PICTURE_ERROR',
      details: {'ownerPeerId': ownerPeerId, 'error': e.toString()},
    );
    return null;
  } finally {
    if (!retainRequest && retryRequest != null) {
      _clearProfileRetryRequest(retryRequest, avatarVersion);
    }
    if (ownsDownload) {
      active.remove(ownerPeerId);
      if (downloadPath != null) {
        try {
          final staged = File(downloadPath);
          if (await staged.exists()) await staged.delete();
        } catch (_) {}
      }
    }
  }
}

/// Re-drives retained requests through the existing profile download path.
/// Each known, unblocked contact receives at most one attempt per owner pass.
Future<List<ContactModel>> retryPendingProfilePictureDownloads({
  required Bridge bridge,
  required ContactRepository contactRepo,
  DownloadProfilePictureFn downloadProfilePictureFn = downloadProfilePicture,
}) async {
  final contacts = await contactRepo.getAllContacts();
  if (contacts.isEmpty) return [];
  final appDir = await getApplicationDocumentsDirectory();
  final avatarsDir = p.join(appDir.path, 'media', 'avatars');
  final updated = <ContactModel>[];
  for (final contact in contacts) {
    if (contact.isBlocked) continue;
    final request = _profileRetryRequest(avatarsDir, contact.peerId);
    if (!request.existsSync()) continue;
    final version = request.readAsStringSync();
    if (version.isEmpty) {
      _clearProfileRetryRequest(request, version);
      continue;
    }
    final recovered = await downloadProfilePictureFn(
      bridge: bridge,
      contactRepo: contactRepo,
      ownerPeerId: contact.peerId,
      avatarVersion: version,
      retryPendingRequest: true,
    );
    if (recovered != null) updated.add(recovered);
  }
  return updated;
}

File _profileRetryRequest(String avatarsDir, String peerId) =>
    File(p.join(avatarsDir, '$peerId.retry_waiting'));

void _clearProfileRetryRequest(File request, String version) {
  try {
    if (request.existsSync() && request.readAsStringSync() == version) {
      request.deleteSync();
    }
  } catch (_) {}
}

String _uniqueSuffix() {
  final now = DateTime.now().toUtc().microsecondsSinceEpoch;
  final token = Random().nextInt(1 << 32).toRadixString(16);
  return '$now-$token';
}
