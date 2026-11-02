import 'dart:convert';

import 'package:flutter_app/core/secure_storage/flutter_secure_key_store.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/stickers/domain/sticker_selection.dart';

/// The Recent tab's ids on this phone, newest first.
class StickerRecentsStore {
  StickerRecentsStore(this._store);

  static final StickerRecentsStore shared = StickerRecentsStore(
    FlutterSecureKeyStore(),
  );

  static const String storageKey = 'stickers_recent_v1';

  final SecureKeyStore _store;

  Future<List<String>> load() async {
    try {
      final decoded = jsonDecode(await _store.read(storageKey) ?? '[]');
      return decoded is List
          ? decoded.whereType<String>().take(kMaxRecentStickers).toList()
          : const [];
    } catch (_) {
      return const [];
    }
  }

  Future<List<String>> recordSent(String stickerId) async {
    final next = withRecentSticker(await load(), stickerId);
    try {
      await _store.write(storageKey, jsonEncode(next));
    } catch (_) {
      // Recent is a convenience; a failed write must never affect the send.
    }
    return next;
  }
}
