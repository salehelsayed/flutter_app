import 'package:flutter_app/features/stickers/application/received_sticker_saver.dart'
    show ReceivedStickerEditor;
import 'package:flutter_app/features/stickers/custom/create/sticker_create_flow.dart';
import 'package:flutter_app/features/stickers/custom/create/sticker_create_screens.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker.dart';
import 'package:flutter_app/features/stickers/domain/sticker_editor_result.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Runs core's received-sticker save and shows one approved message. A
/// cancelled editor (null) shows nothing.
Future<void> saveReceivedStickerWithFeedback({
  required AppLocalizations l10n,
  required bool Function() isCurrent,
  required ReceivedStickerEditor editPhoto,
  required Future<CustomSticker?> Function(ReceivedStickerEditor editPhoto)
  save,
  required void Function(String message) show,
}) async {
  final outcome = await _outcome(
    () => save(({required sourceImagePath, required outputDirectory}) async {
      if (!isCurrent()) return const StickerEditorResult.cancelled();
      return editPhoto(
        sourceImagePath: sourceImagePath,
        outputDirectory: outputDirectory,
      );
    }),
  );
  if (!isCurrent() || outcome == null) return;
  final message = stickerCreateMessage(l10n, outcome);
  if (message != null) show(message);
}

Future<StickerCreateOutcome?> _outcome(
  Future<CustomSticker?> Function() save,
) async {
  try {
    final sticker = await save();
    return sticker == null ? null : StickerCreateSaved(sticker);
  } on CustomStickerException catch (error) {
    return StickerCreateFailed(error.code);
  } on Exception {
    return const StickerCreateFailed(CustomStickerErrorCode.storageFailure);
  }
}
