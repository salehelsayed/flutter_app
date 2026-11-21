import 'package:flutter/foundation.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker.dart';

/// Presentation state for the My stickers tray, owned by its account scope.
final class StickerClipSaves extends ChangeNotifier {
  StickerClipSave? _active;
  CustomSticker? _saved;
  bool _disposed = false;

  bool get isSaving => _active != null;

  /// Available during the listeners' completion notification.
  CustomSticker? get saved => _saved;

  StickerClipSave? begin({required VoidCallback onDispose}) {
    if (_disposed || _active != null) return null;
    final save = StickerClipSave._(this, onDispose);
    _active = save;
    notifyListeners();
    return save;
  }

  void _finish(StickerClipSave save, CustomSticker? sticker) {
    if (!identical(_active, save)) return;
    _active = null;
    _saved = sticker;
    try {
      notifyListeners();
    } finally {
      _saved = null;
    }
  }

  @override
  void dispose() {
    final save = _active;
    _disposed = true;
    _active = null;
    save?._onDispose();
    super.dispose();
  }
}

final class StickerClipSave {
  StickerClipSave._(this._owner, this._onDispose);

  final StickerClipSaves _owner;
  final VoidCallback _onDispose;

  void finish([CustomSticker? sticker]) => _owner._finish(this, sticker);
}
