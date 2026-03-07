import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

typedef IdentityAvatarDocumentsDirLoader = Future<String> Function();

class IdentityAvatarResolver {
  static final Map<String, Uint8List?> _cache = <String, Uint8List?>{};
  static final Map<String, Future<Uint8List?>> _inFlight =
      <String, Future<Uint8List?>>{};

  static Future<Uint8List?> resolve(
    IdentityModel identity, {
    IdentityAvatarDocumentsDirLoader? documentsDirLoader,
  }) {
    if (identity.avatarBlob != null) {
      return Future<Uint8List?>.value(identity.avatarBlob);
    }
    if (identity.avatarVersion == null) {
      return Future<Uint8List?>.value(null);
    }

    final cacheKey = _cacheKey(
      peerId: identity.peerId,
      avatarVersion: identity.avatarVersion,
    );
    final cached = _cache[cacheKey];
    if (cached != null) {
      return Future<Uint8List?>.value(cached);
    }
    if (_cache.containsKey(cacheKey)) {
      return Future<Uint8List?>.value(null);
    }

    final inFlight = _inFlight[cacheKey];
    if (inFlight != null) {
      return inFlight;
    }

    final future = _loadFromDisk(
      identity,
      documentsDirLoader: documentsDirLoader,
    );
    _inFlight[cacheKey] = future;
    return future.whenComplete(() => _inFlight.remove(cacheKey));
  }

  static void invalidatePeer(String peerId) {
    _cache.removeWhere((key, _) => key == peerId || key.startsWith('$peerId|'));
    _inFlight.removeWhere(
      (key, _) => key == peerId || key.startsWith('$peerId|'),
    );
  }

  static Future<Uint8List?> _loadFromDisk(
    IdentityModel identity, {
    IdentityAvatarDocumentsDirLoader? documentsDirLoader,
  }) async {
    final loadDocumentsDir =
        documentsDirLoader ??
        () async => (await getApplicationDocumentsDirectory()).path;
    final documentsDir = await loadDocumentsDir();
    final avatarPath = '$documentsDir/media/avatars/${identity.peerId}.jpg';
    try {
      final file = File(avatarPath);
      if (!await file.exists()) {
        _cache[_cacheKey(
              peerId: identity.peerId,
              avatarVersion: identity.avatarVersion,
            )] =
            null;
        return null;
      }

      final bytes = await file.readAsBytes();
      _cache[_cacheKey(
            peerId: identity.peerId,
            avatarVersion: identity.avatarVersion,
          )] =
          bytes;
      return bytes;
    } catch (_) {
      _cache[_cacheKey(
            peerId: identity.peerId,
            avatarVersion: identity.avatarVersion,
          )] =
          null;
      return null;
    }
  }

  static String _cacheKey({
    required String peerId,
    required String? avatarVersion,
  }) {
    return avatarVersion == null ? peerId : '$peerId|$avatarVersion';
  }
}
