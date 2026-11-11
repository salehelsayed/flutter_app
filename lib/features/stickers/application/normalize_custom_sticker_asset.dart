import 'dart:io';

import '../domain/custom_sticker_asset.dart';

/// Tests-first API scaffold. Deliberately does not validate or normalize yet.
///
/// This is not wired to library admission or any flag-enabled entrypoint.
/// Returning the input lets the byte-level contract tests reach behavioral RED
/// without depending on a missing symbol or an intentionally thrown stub error.
Future<NormalizedStickerAsset> normalizeCustomStickerAsset(
  NormalizedStickerAsset input, {
  required Directory temporaryDirectory,
}) async => input;
