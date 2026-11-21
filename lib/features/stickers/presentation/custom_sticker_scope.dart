import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_app/features/stickers/application/custom_sticker_library.dart';
import 'package:flutter_app/features/stickers/custom/create/sticker_create_screens.dart';

import 'sticker_clip_saves.dart';
import 'sticker_panel.dart';

/// Makes the account's single custom sticker library visible to every route.
class CustomStickerScope extends StatefulWidget {
  const CustomStickerScope({
    super.key,
    required this.library,
    required this.child,
  });

  final CustomStickerLibrary library;
  final Widget child;

  static CustomStickerLibrary? libraryOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_StickerScope>()?.library;

  @override
  State<CustomStickerScope> createState() => _CustomStickerScopeState();
}

class _CustomStickerScopeState extends State<CustomStickerScope> {
  var _clipSaves = StickerClipSaves();

  @override
  void didUpdateWidget(CustomStickerScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.library != oldWidget.library) {
      _clipSaves.dispose();
      _clipSaves = StickerClipSaves();
    }
  }

  @override
  void dispose() {
    _clipSaves.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _StickerScope(
    library: widget.library,
    clipSaves: _clipSaves,
    child: widget.child,
  );
}

class _StickerScope extends InheritedWidget {
  const _StickerScope({
    required this.library,
    required this.clipSaves,
    required super.child,
  });

  final CustomStickerLibrary library;
  final StickerClipSaves clipSaves;

  @override
  bool updateShouldNotify(_StickerScope oldWidget) =>
      library != oldWidget.library || clipSaves != oldWidget.clipSaves;
}

/// The My stickers source for a sticker panel, or null when the app has no
/// library. Create opens the New sticker flow over [context].
MyStickersSource? myStickersFromScope(
  BuildContext context, {
  required ValueChanged<String> onSend,
}) {
  final scope = context.dependOnInheritedWidgetOfExactType<_StickerScope>();
  if (scope == null) return null;
  return MyStickersSource(
    library: scope.library,
    onSend: onSend,
    clipSaves: scope.clipSaves,
    onCreate: () => unawaited(
      openStickerCreate(
        context,
        library: scope.library,
        clipSaves: scope.clipSaves,
      ),
    ),
  );
}
