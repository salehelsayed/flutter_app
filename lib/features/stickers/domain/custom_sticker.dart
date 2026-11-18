import 'custom_sticker_asset.dart';

/// A committed personal-library item with an account-owned canonical asset.
final class CustomSticker {
  const CustomSticker({
    required this.id,
    required this.asset,
    required this.createdAtMs,
    required this.lastUsedAtMs,
    required this.position,
  });

  final String id;
  final NormalizedStickerAsset asset;
  final int createdAtMs;
  final int lastUsedAtMs;
  final int position;
}

/// The transport selects one representation for the complete logical send.
enum CustomStickerSendRepresentation { canonical, staticPoster }

/// Canonical bytes preserve animation. Select once for the whole logical send
/// and reuse its prepared bytes for every recipient and retry. The staticPoster
/// option remains the explicit compatibility fallback.
const CustomStickerSendRepresentation defaultCustomStickerSendRepresentation =
    CustomStickerSendRepresentation.canonical;

enum CustomStickerErrorCode {
  disabled,
  invalidAsset,
  countQuota,
  byteQuota,
  unavailable,
  notEligible,
  storageFailure,
  invalidOrder,
}

/// Stable failure codes; presentation owns the approved localized wording.
final class CustomStickerException implements Exception {
  const CustomStickerException(this.code);

  final CustomStickerErrorCode code;

  @override
  String toString() => 'CustomStickerException(${code.name})';
}
