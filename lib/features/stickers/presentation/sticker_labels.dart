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

/// "{name} sticker" for a sticker id, or plain "Sticker" when the id names no
/// known group (an unknown or future pack).
String stickerSemanticsLabel(AppLocalizations l10n, String stickerId) {
  final groupId = stickerGroupIdOf(stickerId);
  final name = groupId == null ? null : stickerGroupLabel(l10n, groupId);
  return name == null ? l10n.sticker_preview : l10n.sticker_semantics(name);
}
