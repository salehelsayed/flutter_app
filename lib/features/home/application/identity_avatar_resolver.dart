import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'package:flutter_app/features/identity/domain/models/identity_model.dart';

typedef IdentityAvatarDocumentsDirLoader = Future<String> Function();

class IdentityAvatarResolver {
  static final Map<String, Uint8List?> _cache = <String, Uint8List?>{};
  static final Map<String, Future<Uint8List?>> _inFlight =
      <String, Future<Uint8List?>>{};
  static int _generation = 0;

  static Future<Uint8List?> resolve(
    IdentityModel identity, {
    IdentityAvatarDocumentsDirLoader? documentsDirLoader,
  }) {
    if (identity.avatarVersion == null) {
      return Future<Uint8List?>.value(identity.avatarBlob);
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
    _generation++;
    _cache.removeWhere((key, _) => key == peerId || key.startsWith('$peerId|'));
    _inFlight.removeWhere(
      (key, _) => key == peerId || key.startsWith('$peerId|'),
    );
  }

  static Future<Uint8List?> _loadFromDisk(
    IdentityModel identity, {
    IdentityAvatarDocumentsDirLoader? documentsDirLoader,
  }) async {
    final genAtStart = _generation;
    final loadDocumentsDir =
        documentsDirLoader ??
        () async => (await getApplicationDocumentsDirectory()).path;
    final documentsDir = await loadDocumentsDir();
    final avatarPath = '$documentsDir/media/avatars/${identity.peerId}.jpg';
    final cacheKey = _cacheKey(
      peerId: identity.peerId,
      avatarVersion: identity.avatarVersion,
    );
    try {
      final file = File(avatarPath);
      if (!await file.exists()) {
        if (_generation == genAtStart) {
          _cache[cacheKey] = identity.avatarBlob;
        }
        return identity.avatarBlob;
      }

      final bytes = await file.readAsBytes();
      if (_generation == genAtStart) {
        _cache[cacheKey] = bytes;
      }
      return bytes;
    } catch (_) {
      if (_generation == genAtStart) {
        _cache[cacheKey] = identity.avatarBlob;
      }
      return identity.avatarBlob;
    }
  }

  static String _cacheKey({
    required String peerId,
    required String? avatarVersion,
  }) {
    return avatarVersion == null ? peerId : '$peerId|$avatarVersion';
  }
}
