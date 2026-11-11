import 'dart:async';

import 'package:flutter_app/core/config/custom_stickers_flag.dart';
import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/features/stickers/application/custom_sticker_library.dart';
import 'package:flutter_app/features/stickers/data/sqlite_custom_sticker_library.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker_asset.dart';

/// RED scaffold only. It deliberately lacks generation fencing, lifecycle
/// barriers, activation, safe factory-error handling and change forwarding.
/// Do not wire this incomplete implementation into the application.
final class AccountCustomStickerLibrary implements CustomStickerLibrary {
  AccountCustomStickerLibrary({
    required Future<SqliteCustomStickerLibrary?> Function(
      bool Function() isCurrent,
    )
    createLibrary,
    bool enabled = kCustomStickersEnabled,
  }) : _createLibrary = createLibrary,
       _enabled = enabled;

  final Future<SqliteCustomStickerLibrary?> Function(bool Function() isCurrent)
  _createLibrary;
  final bool _enabled;
  final _changes = StreamController<void>.broadcast(sync: true);
  Future<SqliteCustomStickerLibrary?>? _initialization;

  Future<SqliteCustomStickerLibrary> _delegate() async {
    if (!_enabled) {
      throw const CustomStickerException(CustomStickerErrorCode.disabled);
    }
    // Always-current is intentionally insufficient for account replacement.
    final value = await (_initialization ??= _createLibrary(() => true));
    if (value == null) {
      _initialization = null;
      throw const CustomStickerException(CustomStickerErrorCode.unavailable);
    }
    return value;
  }

  /// Must drain already-started creation and file work without retiring.
  Future<void> drainForExport() async {}

  /// Must revoke the generation synchronously and await its permanent retirement.
  Future<void> retire() async {}

  /// Caller has verified committed activation. Must publish a fresh generation;
  /// a failed activation must remain closed until another explicit activation.
  Future<void> activate() async {}

  @override
  Stream<void> get changes => _changes.stream;

  @override
  Future<List<CustomSticker>> list() async {
    if (!_enabled) return const <CustomSticker>[];
    return (await _delegate()).list();
  }

  @override
  Future<CustomSticker> admit(NormalizedStickerAsset asset) async =>
      (await _delegate()).admit(asset);

  @override
  Future<void> remove(String id) async => (await _delegate()).remove(id);

  @override
  Future<void> reorder(List<String> orderedIds) async =>
      (await _delegate()).reorder(orderedIds);

  @override
  Future<PendingComposerMedia> prepareSend(
    String id, {
    required CustomStickerSendRepresentation representation,
  }) async =>
      (await _delegate()).prepareSend(id, representation: representation);
}
