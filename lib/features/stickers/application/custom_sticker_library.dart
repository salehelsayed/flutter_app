import 'package:flutter_app/core/media/pending_composer_media.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker.dart';
import 'package:flutter_app/features/stickers/domain/custom_sticker_asset.dart';

/// Account-local library operations shared by the picker and editor.
///
/// Creation, mutation and send preparation are feature-gated. The implementation
/// validates source snapshots and enforces the committed canonical-byte quota.
/// Received-media eligibility remains with the existing direct/group actions.
abstract interface class CustomStickerLibrary {
  /// Committed user order: position ascending, then id.
  Future<List<CustomSticker>> list();

  /// Subscribe before the initial list load; reload after committed mutations.
  Stream<void> get changes;

  /// Copies valid content into independent library ownership.
  ///
  /// A producer retains responsibility for cleaning its source and editor temps.
  /// Duplicate canonical content retains its existing item and position.
  Future<CustomSticker> admit(NormalizedStickerAsset asset);

  Future<void> remove(String id);

  /// Atomically applies an exact permutation of the currently committed ids.
  ///
  /// Missing, duplicate, unknown or stale sets fail with invalidOrder.
  Future<void> reorder(List<String> orderedIds);

  /// Prepares one immutable representation for all group/linked recipients.
  Future<PendingComposerMedia> prepareSend(
    String id, {
    required CustomStickerSendRepresentation representation,
  });
}
