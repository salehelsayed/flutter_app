import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/features/stickers/application/custom_sticker_library.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker.dart';

/// The reserved sticker marker for personal stickers on the existing wire.
const kCustomStickerMarkerId = 'custom';

/// Prepares a My stickers item once for the whole logical send, then hands it
/// to the chat's existing sticker path. The representation is core's shared
/// default; the UI never infers peer capabilities.
Future<void> sendCustomSticker({
  required CustomStickerLibrary library,
  required String id,
  required bool Function() isCurrent,

  /// Calls the given adopt callback once the chat owns the media.
  required Future<void> Function(
    String markerId,
    PendingComposerMedia media,
    void Function() adopt,
  )
  send,
  required void Function(PendingComposerMedia media) discard,
  required void Function(Object error) onPrepareError,
}) async {
  final PendingComposerMedia media;
  try {
    media = await library.prepareSend(
      id,
      representation: defaultCustomStickerSendRepresentation,
    );
  } on Exception catch (error) {
    onPrepareError(error);
    return;
  }
  if (!isCurrent()) {
    discard(media);
    return;
  }
  // Before the chat adopts it, the prepared copy has no row, lease or
  // durable owner, so a refused send must release it here.
  var adopted = false;
  try {
    await send(kCustomStickerMarkerId, media, () => adopted = true);
  } finally {
    if (!adopted) discard(media);
  }
}
