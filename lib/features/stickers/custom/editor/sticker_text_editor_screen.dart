import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_app/features/stickers/domain/sticker_editor_result.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import 'sticker_still_export.dart';
import 'sticker_text_layers.dart';
import 'sticker_text_overlay.dart';

const double _moveStep = 0.05;
const double _scaleStep = 1.15;
const double _rotateStep = math.pi / 12;

/// Free multi-layer text editor over an already cut-out or cropped image.
/// Pops with [StickerEditorResult]: ready after Save sticker (the PNG is
/// written to [outputFile], which the caller owns), cancelled otherwise.
class StickerTextEditorScreen extends StatefulWidget {
  const StickerTextEditorScreen({
    super.key,
    required this.sourceBytes,
    required this.outputFile,
    this.shape = StickerShape.square,
  });

  static const canvasKey = Key('sticker_text_editor_canvas');

  final Uint8List sourceBytes;
  final File outputFile;
  final StickerShape shape;

  @override
  State<StickerTextEditorScreen> createState() =>
      _StickerTextEditorScreenState();
}

class _StickerTextEditorScreenState extends State<StickerTextEditorScreen> {
  final _history = StickerTextHistory();
  final _editController = TextEditingController();
  int? _editingId;
  bool _saving = false;
  StickerTextLayer? _gestureBase;
  int _pointersDown = 0;
  int? _pointerLayerId;

  StickerTextEditState get _state => _history.present;

  @override
  void dispose() {
    _editController.dispose();
    super.dispose();
  }

  void _apply(StickerTextEdit edit) => setState(() => _history.apply(edit));

  void _commitEditing() {
    final id = _editingId;
    if (id == null) return;
    _editingId = null;
    _history.apply(EditLayerText(id, _editController.text));
  }

  void _startEditing(StickerTextLayer layer) {
    _editController.value = TextEditingValue(
      text: layer.text,
      selection: TextSelection(baseOffset: 0, extentOffset: layer.text.length),
    );
    _editingId = layer.id;
  }

  void _addLayer(String text) {
    setState(() {
      _commitEditing();
      _history.apply(AddTextLayer(text));
      final added = _state.selected;
      if (added != null) _startEditing(added);
    });
  }

  void _tapLayer(StickerTextLayer layer) {
    setState(() {
      if (_editingId == layer.id) return;
      _commitEditing();
      if (_state.selectedId == layer.id) {
        _startEditing(layer);
      } else {
        _history.apply(SelectTextLayer(layer.id));
      }
    });
  }

  void _tapEmptyCanvas() {
    setState(() {
      _commitEditing();
      _history.apply(const SelectTextLayer(null));
    });
  }

  void _undo() {
    setState(() {
      _commitEditing();
      _history.undo();
    });
  }

  void _transformSelected({
    Offset move = Offset.zero,
    double scaleBy = 1,
    double rotateBy = 0,
  }) {
    final layer = _state.selected;
    if (layer == null) return;
    _apply(
      TransformTextLayer(
        layer.id,
        center: layer.center + move,
        scale: layer.scale * scaleBy,
        rotation: layer.rotation + rotateBy,
      ),
    );
  }

  /// A gesture moves the layer under the first finger, otherwise the
  /// selected layer, so a pinch can start anywhere on the canvas.
  void _onScaleStart() {
    final target = _pointerLayerId ?? _state.selectedId;
    if (target == null || target == _editingId) return;
    setState(() {
      _commitEditing();
      _history.apply(SelectTextLayer(target));
      _history.beginGesture();
      _gestureBase = _state.selected;
    });
  }

  void _onScaleUpdate(ScaleUpdateDetails details, double side) {
    final base = _gestureBase;
    final current = _state.selected;
    if (base == null || current == null) return;
    setState(() {
      _history.updateGesture(
        TransformTextLayer(
          current.id,
          center: current.center + details.focalPointDelta / side,
          scale: base.scale * details.scale,
          rotation: base.rotation + details.rotation,
        ),
      );
    });
  }

  void _onScaleEnd() {
    if (_gestureBase == null) return;
    setState(() {
      _gestureBase = null;
      _history.endGesture();
    });
  }

  void _cancel() {
    Navigator.of(context).pop(const StickerEditorResult.cancelled());
  }

  Future<void> _save() async {
    setState(() {
      _commitEditing();
      _saving = true;
    });
    try {
      final asset = await exportStickerStill(
        sourceBytes: widget.sourceBytes,
        layers: _state.layers,
        shape: widget.shape,
        outputFile: widget.outputFile,
      );
      if (!mounted) return;
      Navigator.of(context).pop(StickerEditorResult.ready(asset));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: l10n.btn_cancel,
            onPressed: _cancel,
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: l10n.sticker_editor_undo,
              onPressed: _history.canUndo || _editingId != null ? _undo : null,
            ),
            TextButton(
              onPressed: _saving ? null : _save,
              child: Text(l10n.sticker_editor_save),
            ),
          ],
        ),
        body: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final side = math.min(
                constraints.maxWidth - 32,
                constraints.maxHeight * 0.6,
              );
              return Column(
                children: [
                  const SizedBox(height: 8),
                  Center(child: _buildCanvas(side)),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: _buildControls(l10n),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildCanvas(double side) {
    final image = Image.memory(
      widget.sourceBytes,
      fit: BoxFit.contain,
      gaplessPlayback: true,
    );
    return SizedBox.square(
      key: StickerTextEditorScreen.canvasKey,
      dimension: side,
      child: Listener(
        onPointerDown: (_) => _pointersDown++,
        onPointerUp: (_) => _pointerLifted(),
        onPointerCancel: (_) => _pointerLifted(),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _tapEmptyCanvas,
          onScaleStart: (_) => _onScaleStart(),
          onScaleUpdate: (d) => _onScaleUpdate(d, side),
          onScaleEnd: (_) => _onScaleEnd(),
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color: Colors.white10,
                  child: widget.shape == StickerShape.circle
                      ? ClipOval(child: image)
                      : image,
                ),
              ),
              for (final layer in _state.layers) _buildLayer(layer, side),
            ],
          ),
        ),
      ),
    );
  }

  void _pointerLifted() {
    _pointersDown = math.max(0, _pointersDown - 1);
    if (_pointersDown == 0) _pointerLayerId = null;
  }

  Widget _buildLayer(StickerTextLayer layer, double side) {
    final style = stickerLayerTextStyle(layer, side);
    final selected = layer.id == _state.selectedId;
    final Widget content;
    if (layer.id == _editingId) {
      content = IntrinsicWidth(
        child: TextField(
          controller: _editController,
          autofocus: true,
          maxLines: null,
          textInputAction: TextInputAction.done,
          textAlign: TextAlign.center,
          textDirection: StickerTextLayer(
            id: 0,
            text: _editController.text,
          ).direction,
          style: style,
          cursorColor: style.color,
          decoration: const InputDecoration.collapsed(hintText: null),
          onChanged: (_) => setState(() {}),
          onSubmitted: (_) => setState(_commitEditing),
        ),
      );
    } else {
      content = Text(
        layer.text,
        style: style,
        textAlign: TextAlign.center,
        textDirection: layer.direction,
        textScaler: TextScaler.noScaling,
      );
    }
    final pad = 6 * side / kStickerCanvasPx;
    return Positioned.fill(
      child: CustomSingleChildLayout(
        delegate: _CenterAt(
          Offset(layer.center.dx * side, layer.center.dy * side),
          stickerLayerMaxWidth(side) + 2 * pad,
        ),
        child: Transform.rotate(
          angle: layer.rotation,
          child: Transform.scale(
            scale: layer.scale,
            child: Listener(
              onPointerDown: (_) {
                // Runs before the canvas listener counts this pointer.
                if (_pointersDown == 0) _pointerLayerId = layer.id;
              },
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _tapLayer(layer),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: selected ? Colors.white70 : Colors.transparent,
                      width: 1.5,
                    ),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Padding(padding: EdgeInsets.all(pad), child: content),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildControls(AppLocalizations l10n) {
    final selected = _editingId == null ? _state.selected : null;
    return Column(
      children: [
        FilledButton.icon(
          onPressed: _state.canAddLayer
              ? () => _addLayer(l10n.sticker_editor_text)
              : null,
          icon: const Icon(Icons.text_fields),
          label: Text(l10n.sticker_editor_text),
        ),
        if (selected != null) ...[
          const SizedBox(height: 12),
          _TransformBar(
            l10n: l10n,
            onMove: (delta) => _transformSelected(move: delta),
            onScale: (factor) => _transformSelected(scaleBy: factor),
            onRotate: (radians) => _transformSelected(rotateBy: radians),
            onDelete: () => _apply(DeleteTextLayer(selected.id)),
          ),
          const SizedBox(height: 12),
          _FontRow(
            l10n: l10n,
            layer: selected,
            onSelect: (font) => _apply(SetLayerFont(selected.id, font)),
          ),
          const SizedBox(height: 12),
          _ColourRow(
            l10n: l10n,
            layer: selected,
            onSelect: (colour) => _apply(SetLayerColour(selected.id, colour)),
          ),
        ],
      ],
    );
  }
}

class _CenterAt extends SingleChildLayoutDelegate {
  const _CenterAt(this.center, this.maxWidth);

  final Offset center;
  final double maxWidth;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(maxWidth: maxWidth);

  @override
  Offset getPositionForChild(Size size, Size childSize) =>
      center - Offset(childSize.width / 2, childSize.height / 2);

  @override
  bool shouldRelayout(_CenterAt oldDelegate) =>
      oldDelegate.center != center || oldDelegate.maxWidth != maxWidth;
}

class _TransformBar extends StatelessWidget {
  const _TransformBar({
    required this.l10n,
    required this.onMove,
    required this.onScale,
    required this.onRotate,
    required this.onDelete,
  });

  final AppLocalizations l10n;
  final ValueChanged<Offset> onMove;
  final ValueChanged<double> onScale;
  final ValueChanged<double> onRotate;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    Widget action(IconData icon, String tooltip, VoidCallback onPressed) {
      return IconButton(
        icon: Icon(icon),
        tooltip: tooltip,
        color: Colors.white,
        onPressed: onPressed,
      );
    }

    return Wrap(
      alignment: WrapAlignment.center,
      children: [
        action(
          Icons.north,
          l10n.sticker_editor_move_up,
          () => onMove(const Offset(0, -_moveStep)),
        ),
        action(
          Icons.south,
          l10n.sticker_editor_move_down,
          () => onMove(const Offset(0, _moveStep)),
        ),
        action(
          Icons.west,
          l10n.sticker_editor_move_left,
          () => onMove(const Offset(-_moveStep, 0)),
        ),
        action(
          Icons.east,
          l10n.sticker_editor_move_right,
          () => onMove(const Offset(_moveStep, 0)),
        ),
        action(
          Icons.zoom_in,
          l10n.sticker_editor_bigger,
          () => onScale(_scaleStep),
        ),
        action(
          Icons.zoom_out,
          l10n.sticker_editor_smaller,
          () => onScale(1 / _scaleStep),
        ),
        action(
          Icons.rotate_left,
          l10n.sticker_editor_rotate_left,
          () => onRotate(-_rotateStep),
        ),
        action(
          Icons.rotate_right,
          l10n.sticker_editor_rotate_right,
          () => onRotate(_rotateStep),
        ),
        action(Icons.delete_outline, l10n.sticker_editor_delete, onDelete),
      ],
    );
  }
}

class _FontRow extends StatelessWidget {
  const _FontRow({
    required this.l10n,
    required this.layer,
    required this.onSelect,
  });

  final AppLocalizations l10n;
  final StickerTextLayer layer;
  final ValueChanged<StickerFontToken> onSelect;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: l10n.sticker_editor_font,
      container: true,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        children: [
          for (final font in StickerFontToken.values)
            ChoiceChip(
              selected: layer.font == font,
              onSelected: (_) => onSelect(font),
              label: Text(
                l10n.sticker_editor_text,
                style: stickerLayerTextStyle(
                  layer.copyWith(font: font, colour: StickerColourToken.black),
                  kStickerCanvasPx.toDouble(),
                ).copyWith(fontSize: 16),
              ),
            ),
        ],
      ),
    );
  }
}

class _ColourRow extends StatelessWidget {
  const _ColourRow({
    required this.l10n,
    required this.layer,
    required this.onSelect,
  });

  final AppLocalizations l10n;
  final StickerTextLayer layer;
  final ValueChanged<StickerColourToken> onSelect;

  String _name(StickerColourToken colour) => switch (colour) {
    StickerColourToken.white => l10n.sticker_colour_white,
    StickerColourToken.black => l10n.sticker_colour_black,
    StickerColourToken.yellow => l10n.sticker_colour_yellow,
    StickerColourToken.red => l10n.sticker_colour_red,
    StickerColourToken.blue => l10n.sticker_colour_blue,
  };

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: l10n.sticker_editor_colour,
      container: true,
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 12,
        children: [
          for (final colour in StickerColourToken.values)
            Semantics(
              button: true,
              selected: layer.colour == colour,
              label: _name(colour),
              excludeSemantics: true,
              child: InkResponse(
                onTap: () => onSelect(colour),
                radius: 24,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Color(colour.argb),
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: layer.colour == colour
                          ? Colors.white
                          : Colors.white38,
                      width: layer.colour == colour ? 3 : 1,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
