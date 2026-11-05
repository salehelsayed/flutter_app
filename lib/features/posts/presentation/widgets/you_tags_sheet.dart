import 'package:flutter/material.dart';
import 'package:flutter_app/features/posts/application/load_own_thought_tags_use_case.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

const _sheet = Color(0xFF111318);
const _ink = Color(0xFFE8ECE9);
const _muted = Color(0xFF9AA59F);
const _faint = Color(0xFF59625D);
const _hairline = Color(0x14E8ECE9);
const _chip = Color(0x14E8ECE9);
const _accent = Color(0xFF1DB954);
const _mono = TextStyle(
  fontFamily: 'Menlo',
  fontFamilyFallback: ['Courier', 'monospace'],
);

/// From this many tags the list gets a letter rail.
const _railFrom = 30;

/// The last few tags, shown as one-tap pills above the list.
const _recentCount = 3;

/// Every tag row is this tall, so a letter can be reached by index before
/// its row is built.
const _rowHeight = 48.0;

/// The author's own tags: search, the last few as pills, then all of them
/// A to Z. Pops with the tag picked, or null.
Future<OwnThoughtTag?> showYouTagsSheet(
  BuildContext context, {
  required List<OwnThoughtTag> tags,
  required DateTime now,
}) => showModalBottomSheet<OwnThoughtTag>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (_) => YouTagsSheet(tags: tags, now: now),
);

class YouTagsSheet extends StatefulWidget {
  const YouTagsSheet({super.key, required this.tags, required this.now});

  final List<OwnThoughtTag> tags;
  final DateTime now;

  @override
  State<YouTagsSheet> createState() => _YouTagsSheetState();
}

class _YouTagsSheetState extends State<YouTagsSheet> {
  final _search = TextEditingController();
  final _list = ScrollController();
  final _rows = <String, GlobalKey>{};

  late final List<OwnThoughtTag> _alphabetical = [...widget.tags]
    ..sort((a, b) => foldTag(a.key).compareTo(foldTag(b.key)));

  @override
  void dispose() {
    _search.dispose();
    _list.dispose();
    super.dispose();
  }

  /// Tags starting with the query first, then those containing it; A to Z
  /// within each.
  List<OwnThoughtTag> get _matches {
    final query = foldTag(_search.text);
    if (query.isEmpty) return _alphabetical;
    return [
      for (final tag in _alphabetical)
        if (foldTag(tag.key).startsWith(query)) tag,
      for (final tag in _alphabetical)
        if (!foldTag(tag.key).startsWith(query) &&
            foldTag(tag.key).contains(query))
          tag,
    ];
  }

  void _jumpTo(String letter) {
    final index = _alphabetical.indexWhere(
      (tag) => foldTag(tag.key).startsWith(letter),
    );
    if (index < 0 || !_list.hasClients) return;
    // The list builds rows lazily: land near the row first so it exists,
    // then line it up once it is laid out.
    _list.jumpTo(
      (index * _rowHeight).clamp(0.0, _list.position.maxScrollExtent),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final row = _rows[_alphabetical[index].key]?.currentContext;
      if (row != null) Scrollable.ensureVisible(row);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final searching = _search.text.trim().isNotEmpty;
    final matches = _matches;
    final rail = !searching && widget.tags.length >= _railFrom;
    final letters = {
      for (final tag in _alphabetical)
        if (foldTag(tag.key).isNotEmpty) foldTag(tag.key).characters.first,
    }.toList();
    final small = _mono.copyWith(color: _faint, fontSize: 11.5);
    return Padding(
      padding: EdgeInsets.only(
        top: 80,
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Material(
        color: _sheet,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: SafeArea(
          top: false,
          child: Column(
            children: [
              Container(
                width: 36,
                height: 5,
                margin: const EdgeInsets.only(top: 8, bottom: 2),
                decoration: BoxDecoration(
                  color: const Color(0x2EE8ECE9),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 2, 8, 4),
                child: Row(
                  children: [
                    const SizedBox(width: 56),
                    Expanded(
                      child: Text(
                        l10n.you_tags_title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(
                        foregroundColor: _muted,
                        minimumSize: const Size(56, 44),
                      ),
                      child: Text(l10n.you_tags_done),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: TextField(
                  key: const ValueKey('you-tags-search'),
                  controller: _search,
                  onChanged: (_) => setState(() {}),
                  style: _mono.copyWith(color: _ink, fontSize: 14),
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: const Color(0x0FFFFFFF),
                    prefixText: '# ',
                    prefixStyle: _mono.copyWith(color: _faint, fontSize: 14),
                    hintText: l10n.you_tags_find,
                    hintStyle: const TextStyle(
                      color: Color(0x66F8FAFC),
                      fontSize: 14,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0x24E8ECE9)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0x24E8ECE9)),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Stack(
                  children: [
                    ListView(
                      controller: _list,
                      padding: EdgeInsetsDirectional.fromSTEB(
                        16,
                        0,
                        rail ? 28 : 16,
                        16,
                      ),
                      children: [
                        if (!searching) ...[
                          Padding(
                            padding: const EdgeInsets.only(top: 6, bottom: 8),
                            child: Text(l10n.you_tags_recent, style: small),
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final tag in widget.tags.take(_recentCount))
                                _Pill(
                                  key: ValueKey('you-tags-recent-${tag.key}'),
                                  label: tag.label,
                                  onTap: () => Navigator.of(context).pop(tag),
                                ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.only(top: 14, bottom: 2),
                            child: Text(l10n.you_tags_all, style: small),
                          ),
                        ],
                        if (matches.isEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 28),
                            child: Column(
                              children: [
                                Text(
                                  l10n.you_tags_none(
                                    '#${_search.text.trim().replaceFirst(RegExp('^#+'), '')}',
                                  ),
                                  style: _mono.copyWith(
                                    color: _muted,
                                    fontSize: 13,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(l10n.you_tags_none_hint, style: small),
                              ],
                            ),
                          ),
                        for (final tag in matches)
                          _Row(
                            key: _rows.putIfAbsent(tag.key, GlobalKey.new),
                            tag: tag,
                            used: switch (widget.now
                                .toUtc()
                                .difference(tag.lastUsed)
                                .inDays) {
                              <= 0 => l10n.you_tags_used_today,
                              final days => l10n.you_tags_used(days),
                            },
                            onTap: () => Navigator.of(context).pop(tag),
                          ),
                      ],
                    ),
                    if (rail)
                      PositionedDirectional(
                        end: 2,
                        top: 8,
                        bottom: 8,
                        // Shrinks to fit a short screen; never overflows.
                        child: FittedBox(
                          key: const ValueKey('you-tags-rail'),
                          fit: BoxFit.scaleDown,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (final letter in letters)
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onTap: () => _jumpTo(letter),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1,
                                    ),
                                    child: Text(
                                      letter.toUpperCase(),
                                      style: _mono.copyWith(
                                        color: _faint,
                                        fontSize: 10,
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({super.key, required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _chip,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(label, style: _mono.copyWith(color: _ink, fontSize: 13)),
      ),
    ),
  );
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.tag,
    required this.used,
    required this.onTap,
  });

  final OwnThoughtTag tag;
  final String used;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    child: InkWell(
      key: ValueKey('you-tags-row-${tag.key}'),
      onTap: onTap,
      child: Container(
        height: _rowHeight,
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _hairline)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                tag.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _mono.copyWith(color: _ink, fontSize: 14),
              ),
            ),
            Text(used, style: _mono.copyWith(color: _faint, fontSize: 11)),
          ],
        ),
      ),
    ),
  );
}

/// A small one-time note under the header's #, pointing at it.
class YouTagsNote extends StatelessWidget {
  const YouTagsNote({super.key, required this.text});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsetsDirectional.only(end: 10, top: 2, bottom: 6),
    child: Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Container(
        key: const ValueKey('you-tags-note'),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFF1D2A23),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _accent.withValues(alpha: .4)),
        ),
        child: Text(text, style: const TextStyle(color: _ink, fontSize: 12)),
      ),
    ),
  );
}

const _latin = {
  'à': 'a',
  'á': 'a',
  'â': 'a',
  'ã': 'a',
  'ä': 'a',
  'å': 'a',
  'ā': 'a',
  'ç': 'c',
  'è': 'e',
  'é': 'e',
  'ê': 'e',
  'ë': 'e',
  'ē': 'e',
  'ì': 'i',
  'í': 'i',
  'î': 'i',
  'ï': 'i',
  'ñ': 'n',
  'ò': 'o',
  'ó': 'o',
  'ô': 'o',
  'õ': 'o',
  'ö': 'o',
  'ø': 'o',
  'ù': 'u',
  'ú': 'u',
  'û': 'u',
  'ü': 'u',
  'ý': 'y',
  'ÿ': 'y',
  'ß': 'ss',
  'æ': 'ae',
  'œ': 'oe',
  'أ': 'ا',
  'إ': 'ا',
  'آ': 'ا',
  'ٱ': 'ا',
  'ة': 'ه',
  'ى': 'ي',
  'ؤ': 'و',
  'ئ': 'ي',
};

/// Arabic short vowels and other marks, the superscript alef and tatweel.
final _arabicMarks = RegExp('[ً-ٰٟـ]');

/// A tag as search compares it: no leading '#', lowercase, accents and
/// Arabic marks dropped, so "Früh" matches "fruh" and "أمي" matches "امي".
String foldTag(String raw) {
  final text = raw
      .trim()
      .replaceFirst(RegExp('^#+'), '')
      .toLowerCase()
      .replaceAll(_arabicMarks, '');
  final out = StringBuffer();
  for (final char in text.characters) {
    out.write(_latin[char] ?? char);
  }
  return out.toString();
}
