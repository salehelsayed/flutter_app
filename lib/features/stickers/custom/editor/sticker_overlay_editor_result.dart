import 'sticker_text_layers.dart';

sealed class StickerOverlayEditorResult {
  const StickerOverlayEditorResult();
}

final class StickerOverlayEditorReady extends StickerOverlayEditorResult {
  StickerOverlayEditorReady(List<StickerTextLayer> layers)
    : layers = List.unmodifiable(layers);

  final List<StickerTextLayer> layers;
}

final class StickerOverlayEditorCancelled extends StickerOverlayEditorResult {
  const StickerOverlayEditorCancelled();
}
