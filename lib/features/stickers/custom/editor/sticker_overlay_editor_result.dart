import 'dart:typed_data';

sealed class StickerOverlayEditorResult {
  const StickerOverlayEditorResult();
}

final class StickerOverlayEditorReady extends StickerOverlayEditorResult {
  const StickerOverlayEditorReady(this.rgba);

  final Uint8List? rgba;
}

final class StickerOverlayEditorCancelled extends StickerOverlayEditorResult {
  const StickerOverlayEditorCancelled();
}
