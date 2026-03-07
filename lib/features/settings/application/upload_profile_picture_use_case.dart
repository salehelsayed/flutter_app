import 'dart:convert';
import 'dart:io';

import 'package:flutter/painting.dart';
import 'package:flutter_app/core/bridge/bridge.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/core/utils/flow_event_emitter.dart';
import 'package:flutter_app/features/contacts/domain/repositories/contact_repository.dart';
import 'package:flutter_app/features/home/application/identity_avatar_resolver.dart';
import 'package:flutter_app/features/home/presentation/widgets/user_avatar.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
import 'package:flutter_app/features/identity/domain/repositories/identity_repository.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

/// Uploads the user's profile picture to the relay and notifies contacts.
///
/// 1. Calls bridge to upload the file to the relay
/// 2. Copies file to local avatars directory
/// 3. Updates identity with new avatarVersion
/// 4. Broadcasts profile_update to all active contacts
Future<bool> uploadProfilePicture({
  required Bridge bridge,
  required IdentityRepository identityRepo,
  required ContactRepository contactRepo,
  required P2PService p2pService,
  required String filePath,
  required String mime,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'UPLOAD_PROFILE_PICTURE_START',
    details: {'mime': mime},
  );

  try {
    // 1. Upload to relay
    final uploadResult = await callP2PProfileUpload(
      bridge,
      mime: mime,
      filePath: filePath,
    );

    if (uploadResult['ok'] != true) {
      emitFlowEvent(
        layer: 'FL',
        event: 'UPLOAD_PROFILE_PICTURE_UPLOAD_FAILED',
        details: {'error': uploadResult['errorMessage']},
      );
      return false;
    }

    // 2. Load identity
    final identity = await identityRepo.loadIdentity();
    if (identity == null) return false;

    final avatarVersion = DateTime.now().toUtc().toIso8601String();

    // 3. Copy file to local avatars directory
    final appDir = await getApplicationDocumentsDirectory();
    final avatarsDir = Directory(p.join(appDir.path, 'media', 'avatars'));
    if (!avatarsDir.existsSync()) {
      avatarsDir.createSync(recursive: true);
    }

    final localPath = p.join(avatarsDir.path, '${identity.peerId}.jpg');
    await File(filePath).copy(localPath);

    // Evict Flutter image cache so UserAvatar picks up the new file
    FileImage(File(localPath)).evict();
    IdentityAvatarResolver.invalidatePeer(identity.peerId);
    UserAvatar.invalidatePeer(identity.peerId);

    // 4. Update identity with new avatarVersion
    final updated = IdentityModel(
      peerId: identity.peerId,
      publicKey: identity.publicKey,
      privateKey: identity.privateKey,
      mnemonic12: identity.mnemonic12,
      mlKemPublicKey: identity.mlKemPublicKey,
      mlKemSecretKey: identity.mlKemSecretKey,
      username: identity.username,
      avatarBlob: identity.avatarBlob,
      avatarVersion: avatarVersion,
      createdAt: identity.createdAt,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
    await identityRepo.saveIdentity(updated);

    // 5. Broadcast profile_update to all active contacts
    final contacts = await contactRepo.getActiveContacts();
    final envelope = jsonEncode({
      'type': 'profile_update',
      'version': '1',
      'payload': {'peerId': identity.peerId, 'avatarVersion': avatarVersion},
    });

    for (final contact in contacts) {
      try {
        final sendResult = await p2pService.sendMessageWithReply(
          contact.peerId,
          envelope,
        );
        if (!sendResult.sent || !sendResult.acknowledged) {
          await p2pService.storeInInbox(contact.peerId, envelope);
        }
      } catch (_) {
        try {
          await p2pService.storeInInbox(contact.peerId, envelope);
        } catch (_) {}
      }
    }

    emitFlowEvent(
      layer: 'FL',
      event: 'UPLOAD_PROFILE_PICTURE_SUCCESS',
      details: {
        'avatarVersion': avatarVersion,
        'contactsNotified': contacts.length,
      },
    );

    return true;
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'UPLOAD_PROFILE_PICTURE_ERROR',
      details: {'error': e.toString()},
    );
    return false;
  }
}
