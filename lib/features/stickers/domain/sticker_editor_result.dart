import 'custom_sticker_asset.dart';

/// Finishing the editor does not itself add an item to the personal library.
sealed class StickerEditorResult {
  const StickerEditorResult._();

  const factory StickerEditorResult.ready(NormalizedStickerAsset asset) =
      StickerEditorReady;

  const factory StickerEditorResult.cancelled() = StickerEditorCancelled;
}

final class StickerEditorReady extends StickerEditorResult {
  const StickerEditorReady(this.asset) : super._();

  final NormalizedStickerAsset asset;
}

final class StickerEditorCancelled extends StickerEditorResult {
  const StickerEditorCancelled() : super._();
}
