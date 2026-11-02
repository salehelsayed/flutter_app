import 'package:flutter_app/features/stickers/domain/sticker_catalog.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

String? stickerGroupLabel(AppLocalizations l10n, String groupId) =>
    switch (groupId) {
      'planet' => l10n.sticker_group_planet,
      'capybara' => l10n.sticker_group_capybara,
      'nerd_duck' => l10n.sticker_group_nerd_duck,
      'pearl' => l10n.sticker_group_pearl,
      'new_baby' => l10n.sticker_group_new_baby,
      'otter' => l10n.sticker_group_otter,
      'otter_family' => l10n.sticker_group_otter_family,
      'tux' => l10n.sticker_group_tux,
      'en' => l10n.sticker_group_en,
      'ar' => l10n.sticker_group_ar,
      'de' => l10n.sticker_group_de,
      'arab' => l10n.sticker_group_arab,
      'german' => l10n.sticker_group_german,
      _ => null,
    };

String stickerPackLabel(AppLocalizations l10n, String packId) =>
    switch (packId) {
      'orbit_crew' => l10n.sticker_pack_orbit_crew,
      'big_mood' => l10n.sticker_pack_big_mood,
      'nujoom' => l10n.sticker_pack_nujoom,
      _ => l10n.stickers_title,
    };

/// The words printed on the sticker, else "{group} sticker, {position} of
/// {count}", or plain "Sticker" for an id [catalog] does not hold (an unknown
/// or hidden pack, or a catalog not loaded yet).
String stickerSemanticsLabel(
  AppLocalizations l10n,
  StickerCatalog? catalog,
  String stickerId,
) {
  final sticker = catalog?.byId(stickerId);
  final group = catalog?.groupOf(stickerId);
  if (sticker == null || group == null) return l10n.sticker_preview;
  if (sticker.printedText case final printedText?) return printedText;
  final name = stickerGroupLabel(l10n, group.id);
  if (name == null) return l10n.sticker_preview;
  return l10n.sticker_semantics(
    name,
    group.stickers.indexOf(sticker) + 1,
    group.stickers.length,
  );
}
