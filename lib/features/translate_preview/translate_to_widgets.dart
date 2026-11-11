import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/translate_preview/language_heuristic.dart';
import 'package:flutter_app/features/translate_preview/model_delivery_contract.dart';
import 'package:flutter_app/features/translate_preview/translation_preferences.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// "Deutsch", or "Same as the app" while the choice follows the app language.
String translateToLabel(BuildContext context, String? chosen) => chosen == null
    ? AppLocalizations.of(context)!.translate_to_same_as_app
    : translateLanguageNativeName(chosen)!;

/// The "Translate to" language list, opened from Settings and from a chat.
Future<void> showTranslateToSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _TranslateToSheet(),
    );

class _TranslateToSheet extends StatefulWidget {
  const _TranslateToSheet();

  @override
  State<_TranslateToSheet> createState() => _TranslateToSheetState();
}

class _TranslateToSheetState extends State<_TranslateToSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colors = context.backgroundReadableColors;
    final chosen = translationPreferences.target.value;
    final appLanguage = Localizations.localeOf(context).languageCode;
    final query = _query.trim().toLowerCase();
    final codes = [
      for (final code in translateLanguageCodes)
        if (query.isEmpty ||
            translateLanguageNativeName(code)!.toLowerCase().contains(query) ||
            translateLanguageName(code)!.toLowerCase().contains(query))
          code,
    ];
    void choose(String? code) {
      unawaited(translationPreferences.setTarget(code));
      Navigator.of(context).pop();
    }

    Widget option({
      required String title,
      required String subtitle,
      required bool selected,
      required VoidCallback onTap,
    }) => ListTile(
      title: Text(title),
      subtitle: Text(subtitle),
      selected: selected,
      trailing: selected ? Icon(Icons.check, color: colors.accent) : null,
      onTap: onTap,
    );

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.85,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 12),
            child: Text(
              l10n.translate_to_title,
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 0, 20, 8),
            child: TextField(
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                hintText: l10n.chat_search_hint,
                prefixIcon: const Icon(Icons.search_rounded),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: ListView(
              children: [
                if (query.isEmpty) ...[
                  option(
                    title: l10n.translate_to_same_as_app,
                    subtitle:
                        translateLanguageNativeName(appLanguage) ?? appLanguage,
                    selected: chosen == null,
                    onTap: () => choose(null),
                  ),
                  Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      16,
                      12,
                      16,
                      4,
                    ),
                    child: Text(
                      l10n.translate_to_all_languages,
                      style: TextStyle(fontSize: 12, color: colors.textMuted),
                    ),
                  ),
                ],
                for (final code in codes)
                  option(
                    title: translateLanguageNativeName(code)!,
                    subtitle: translateLanguageName(code)!,
                    selected: chosen == code,
                    onTap: () => choose(code),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// The chat header's translate button, shown only once the translator is on
/// the phone. It opens a small panel with the language and this chat's switch.
class ChatTranslateAction extends StatelessWidget {
  const ChatTranslateAction({
    super.key,
    required this.peerId,
    required this.delivery,
  });

  final String peerId;
  final ModelDeliveryController? delivery;

  @override
  Widget build(BuildContext context) {
    final controller = delivery;
    if (controller == null) return const SizedBox.shrink();
    return ValueListenableBuilder<ModelDeliveryState>(
      valueListenable: controller.state,
      builder: (context, state, _) =>
          state is ModelReady ? _panel(context) : const SizedBox.shrink(),
    );
  }

  Widget _panel(BuildContext context) {
    final prefs = translationPreferences;
    final colors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;
    final changes = Listenable.merge([prefs.target, prefs.chats]);
    void toggle(bool show) => unawaited(prefs.setShowTranslation(peerId, show));
    return MenuAnchor(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colors.surfaceRaised),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: colors.border),
          ),
        ),
      ),
      menuChildren: [
        ListenableBuilder(
          listenable: changes,
          builder: (_, _) => MenuItemButton(
            onPressed: () => unawaited(showTranslateToSheet(context)),
            trailingIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  translateToLabel(context, prefs.target.value),
                  style: TextStyle(color: colors.textMuted),
                ),
                Icon(Icons.chevron_right, size: 18, color: colors.iconMuted),
              ],
            ),
            child: Text(
              l10n.translate_to_title,
              style: TextStyle(color: colors.textPrimary),
            ),
          ),
        ),
        ListenableBuilder(
          listenable: changes,
          builder: (_, _) {
            final on = prefs.showsTranslationIn(peerId);
            return MenuItemButton(
              closeOnActivate: false,
              onPressed: () => toggle(!on),
              trailingIcon: Switch.adaptive(
                value: on,
                onChanged: toggle,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                l10n.translate_show_translation,
                style: TextStyle(color: colors.textPrimary),
              ),
            );
          },
        ),
      ],
      builder: (context, menu, _) => ListenableBuilder(
        listenable: prefs.chats,
        builder: (context, _) {
          final on = prefs.showsTranslationIn(peerId);
          return IconButton(
            tooltip: l10n.translator_settings_title,
            onPressed: () => menu.isOpen ? menu.close() : menu.open(),
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.translate),
                if (on)
                  PositionedDirectional(
                    top: -1,
                    end: -2,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: colors.accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
              ],
            ),
            iconSize: 22,
            color: on ? colors.accent : colors.iconSecondary,
            style: IconButton.styleFrom(fixedSize: const Size.square(44)),
          );
        },
      ),
    );
  }
}
