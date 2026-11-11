import 'dart:ui' show Offset, TextDirection;

import 'package:flutter/foundation.dart' show listEquals;

const int kMaxStickerTextLayers = 10;
const int kStickerTextUndoDepth = 30;
const double kMinStickerTextScale = 0.4;
const double kMaxStickerTextScale = 4;

enum StickerFontToken { sans, serif, mono }

enum StickerColourToken {
  white(0xFFFFFFFF),
  black(0xFF111111),
  yellow(0xFFFFD60A),
  red(0xFFFF3B30),
  blue(0xFF0A84FF);

  const StickerColourToken(this.argb);

  final int argb;
}

/// One text layer. [center] is normalized to the square canvas (0..1 on
/// both axes, top-left origin) so the same layer renders at any canvas size.
final class StickerTextLayer {
  const StickerTextLayer({
    required this.id,
    required this.text,
    this.font = StickerFontToken.sans,
    this.colour = StickerColourToken.white,
    this.center = const Offset(0.5, 0.5),
    this.scale = 1,
    this.rotation = 0,
  });

  final int id;
  final String text;
  final StickerFontToken font;
  final StickerColourToken colour;
  final Offset center;
  final double scale;
  final double rotation;

  /// First strong character decides, so a layer starting with Arabic (after
  /// digits, spaces or emoji) lays out right to left.
  TextDirection get direction => TextDirection.ltr;

  StickerTextLayer copyWith({
    String? text,
    StickerFontToken? font,
    StickerColourToken? colour,
    Offset? center,
    double? scale,
    double? rotation,
  }) {
    return StickerTextLayer(
      id: id,
      text: text ?? this.text,
      font: font ?? this.font,
      colour: colour ?? this.colour,
      center: center ?? this.center,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StickerTextLayer &&
      other.id == id &&
      other.text == text &&
      other.font == font &&
      other.colour == colour &&
      other.center == center &&
      other.scale == scale &&
      other.rotation == rotation;

  @override
  int get hashCode =>
      Object.hash(id, text, font, colour, center, scale, rotation);
}

final class StickerTextEditState {
  const StickerTextEditState({
    this.layers = const [],
    this.selectedId,
    this.nextId = 1,
  });

  /// Bottom to top paint order.
  final List<StickerTextLayer> layers;
  final int? selectedId;
  final int nextId;

  StickerTextLayer? get selected {
    for (final layer in layers) {
      if (layer.id == selectedId) return layer;
    }
    return null;
  }

  bool get canAddLayer => layers.length < kMaxStickerTextLayers;

  @override
  bool operator ==(Object other) =>
      other is StickerTextEditState &&
      other.selectedId == selectedId &&
      other.nextId == nextId &&
      listEquals(other.layers, layers);

  @override
  int get hashCode => Object.hash(selectedId, nextId, Object.hashAll(layers));
}

sealed class StickerTextEdit {
  const StickerTextEdit();
}

final class AddTextLayer extends StickerTextEdit {
  const AddTextLayer(this.text);
  final String text;
}

final class SelectTextLayer extends StickerTextEdit {
  const SelectTextLayer(this.id);
  final int? id;
}

/// Empty text removes the layer.
final class EditLayerText extends StickerTextEdit {
  const EditLayerText(this.id, this.text);
  final int id;
  final String text;
}

/// Absolute transform; the reducer clamps it to the canvas and scale bounds.
final class TransformTextLayer extends StickerTextEdit {
  const TransformTextLayer(
    this.id, {
    required this.center,
    required this.scale,
    required this.rotation,
  });
  final int id;
  final Offset center;
  final double scale;
  final double rotation;
}

final class SetLayerFont extends StickerTextEdit {
  const SetLayerFont(this.id, this.font);
  final int id;
  final StickerFontToken font;
}

final class SetLayerColour extends StickerTextEdit {
  const SetLayerColour(this.id, this.colour);
  final int id;
  final StickerColourToken colour;
}

final class DeleteTextLayer extends StickerTextEdit {
  const DeleteTextLayer(this.id);
  final int id;
}

StickerTextEditState reduceStickerText(
  StickerTextEditState state,
  StickerTextEdit edit,
) => state;

/// Undoable edit history. Selection changes are not undo steps; a gesture
/// (drag, pinch, rotate) is one step however many updates it delivers.
final class StickerTextHistory {
  StickerTextHistory([this._present = const StickerTextEditState()]);

  StickerTextEditState _present;
  final List<StickerTextEditState> _past = [];
  StickerTextEditState? _gestureBase;

  StickerTextEditState get present => _present;
  bool get canUndo => _past.isNotEmpty;

  void apply(StickerTextEdit edit) {
    final next = reduceStickerText(_present, edit);
    if (next == _present) return;
    if (edit is! SelectTextLayer) _push(_present);
    _present = next;
  }

  void beginGesture() => _gestureBase = _present;

  void updateGesture(StickerTextEdit edit) {
    _present = reduceStickerText(_present, edit);
  }

  void endGesture() {
    final base = _gestureBase;
    _gestureBase = null;
    if (base != null && base != _present) _push(base);
  }

  void undo() {
    if (_past.isEmpty) return;
    _present = _past.removeLast();
  }

  void _push(StickerTextEditState state) {
    _past.add(state);
    if (_past.length > kStickerTextUndoDepth) _past.removeAt(0);
  }
}
