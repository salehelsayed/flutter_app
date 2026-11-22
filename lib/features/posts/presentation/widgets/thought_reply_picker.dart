import 'package:flutter/material.dart';
import 'package:flutter_app/features/orbit/domain/orbit_depth_visit.dart';
import 'package:flutter_app/features/posts/domain/thought_emoji_catalog.dart';
import 'package:flutter_app/features/posts/domain/thought_quote.dart';
import 'package:flutter_app/features/posts/domain/thought_reply_status.dart';
import 'package:flutter_app/features/stickers/presentation/custom_sticker_scope.dart';
import 'package:flutter_app/features/stickers/presentation/sticker_panel.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// The two reply tabs share a sheet so selecting an item returns to the same
/// Thought, whether it is full screen or in the depth ring.
class ThoughtReplyPicker extends StatelessWidget {
  const ThoughtReplyPicker({
    super.key,
    required this.postId,
    required this.visit,
    required this.stickersAvailable,
  });

  final String postId;
  final OrbitDepthVisit visit;
  final bool stickersAvailable;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final library = CustomStickerScope.libraryOf(context);
    final height = (MediaQuery.sizeOf(context).height * .4)
        .clamp(0.0, kStickerPanelHeight)
        .toDouble();
    return SafeArea(
      top: false,
      child: SizedBox(
        height: height + 48,
        child: DefaultTabController(
          length: 2,
          child: Column(
            children: [
              TabBar(
                tabs: [
                  Tab(
                    key: const ValueKey('thought-reply-emoji-tab'),
                    text: l10n.thought_picker_emoji_tab,
                  ),
                  Tab(
                    key: const ValueKey('thought-reply-stickers-tab'),
                    text: l10n.stickers_title,
                  ),
                ],
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _emojiTab(context, l10n),
                    if (stickersAvailable)
                      BundledStickerPanel(
                        onSend: (entry) => Navigator.of(
                          context,
                        ).pop(ThoughtStickerSelection.bundled(entry)),
                        onSendCustom: library == null
                            ? null
                            : (id) async {
                                try {
                                  final items = await library.list();
                                  final item = items
                                      .where((item) => item.id == id)
                                      .firstOrNull;
                                  if (item != null &&
                                      context.mounted &&
                                      ModalRoute.isCurrentOf(context) == true) {
                                    Navigator.of(context).pop(
                                      ThoughtStickerSelection.custom(
                                        id,
                                        item.asset.filePath,
                                      ),
                                    );
                                  }
                                } catch (_) {
                                  // A missing local sticker leaves the picker open.
                                }
                              },
                      )
                    else
                      const SizedBox.shrink(),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _emojiTab(BuildContext context, AppLocalizations l10n) {
    final recent = visit.recentEmoji;
    final columns = (MediaQuery.sizeOf(context).width / 46).floor().clamp(3, 8);
    return CustomScrollView(
      key: const ValueKey('thought-reply-emoji-grid'),
      slivers: [
        if (recent.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 0),
              child: Text(l10n.stickers_recent),
            ),
          ),
          _emojiGrid(
            count: recent.length,
            columns: columns,
            glyphAt: (index) => recent[index].glyph,
            recent: true,
          ),
        ],
        _emojiGrid(
          count: thoughtEmojiCatalog.length,
          columns: columns,
          glyphAt: (index) => thoughtEmojiCatalog[index],
          recent: false,
        ),
      ],
    );
  }

  Widget _emojiGrid({
    required int count,
    required int columns,
    required String Function(int) glyphAt,
    required bool recent,
  }) => SliverPadding(
    padding: const EdgeInsetsDirectional.fromSTEB(8, 4, 8, 8),
    sliver: SliverGrid.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisExtent: 44,
      ),
      itemCount: count,
      itemBuilder: (context, index) {
        final glyph = glyphAt(index);
        final reaction = ThoughtReaction.fromText(glyph)!;
        final pressed = visit.pressed(postId, reaction);
        return IconButton(
          key: ValueKey(
            recent
                ? 'thought-reply-recent-emoji-$glyph'
                : 'thought-reply-emoji-$glyph',
          ),
          tooltip: glyph,
          onPressed: pressed ? null : () => Navigator.of(context).pop(reaction),
          icon: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(glyph, style: const TextStyle(fontSize: 25)),
          ),
        );
      },
    ),
  );
}
