import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/models/contact_model.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Signature of [downloadProfilePicture] for dependency injection.
typedef DownloadProfilePictureFn = Future<ContactModel?> Function({
  required Bridge bridge,
  required ContactRepository contactRepo,
  required String ownerPeerId,
  required String avatarVersion,
});

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
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'DOWNLOAD_PROFILE_PICTURE_START',
    details: {'ownerPeerId': ownerPeerId, 'avatarVersion': avatarVersion},
  );

  try {
    // 1. Resolve output path
    final appDir = await getApplicationDocumentsDirectory();
    final avatarsDir = Directory(p.join(appDir.path, 'media', 'avatars'));
    if (!avatarsDir.existsSync()) {
      avatarsDir.createSync(recursive: true);
    }

    final outputPath = p.join(avatarsDir.path, '$ownerPeerId.jpg');

    // 2. Download from relay
    final result = await callP2PProfileDownload(
      bridge,
      ownerPeerId: ownerPeerId,
      outputPath: outputPath,
    );

    if (result['ok'] != true) {
      emitFlowEvent(
        layer: 'FL',
        event: 'DOWNLOAD_PROFILE_PICTURE_DOWNLOAD_FAILED',
        details: {'error': result['errorMessage']},
      );
      return null;
    }

    // 3. Evict Flutter image cache so UserAvatar picks up the new file
    FileImage(File(outputPath)).evict();

    // 4. Update contact
    final contact = await contactRepo.getContact(ownerPeerId);
    if (contact == null) return null;

    final relativePath = p.join('media', 'avatars', '$ownerPeerId.jpg');
    final updated = contact.copyWith(
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
  }
}
