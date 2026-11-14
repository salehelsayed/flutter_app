import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_app/features/stickers/application/custom_sticker_library.dart';
import 'package:flutter_app/features/stickers/custom/create/sticker_create_screens.dart';

import 'sticker_panel.dart';

/// Makes the account's single custom sticker library visible to every route.
class CustomStickerScope extends InheritedWidget {
  const CustomStickerScope({
    super.key,
    required this.library,
    required super.child,
  });

  final CustomStickerLibrary library;

  static CustomStickerLibrary? libraryOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<CustomStickerScope>()?.library;

  @override
  bool updateShouldNotify(CustomStickerScope oldWidget) =>
      library != oldWidget.library;
}

/// The My stickers source for a sticker panel, or null when the app has no
/// library. Create opens the New sticker flow over [context].
MyStickersSource? myStickersFromScope(
  BuildContext context, {
  required ValueChanged<String> onSend,
}) {
  final library = context
      .dependOnInheritedWidgetOfExactType<CustomStickerScope>()
      ?.library;
  if (library == null) return null;
  return MyStickersSource(
    library: library,
    onSend: onSend,
    onCreate: () => unawaited(openStickerCreate(context, library: library)),
  );
}
