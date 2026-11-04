import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// In-chat search: the typed words, the matching message ids (newest first)
/// and which one is shown. [onShow] jumps the chat to a match.
class ChatSearchController extends ChangeNotifier {
  ChatSearchController({
    required this.search,
    required this.onShow,
    this.onOpened,
    this.onClosed,
    this.debounce = const Duration(milliseconds: 200),
  });

  final Future<List<String>> Function(String query) search;
  final void Function(String messageId) onShow;
  final VoidCallback? onOpened;
  final VoidCallback? onClosed;
  final Duration debounce;

  bool _open = false;
  String _query = '';
  List<String> _hits = const [];
  int _index = 0;
  bool _searched = false;
  int _revision = 0;
  Timer? _timer;

  bool get isOpen => _open;
  String get query => _query;
  List<String> get hits => _hits;
  int get index => _index;
  String? get currentId => _hits.isEmpty ? null : _hits[_index];

  /// The words matched in the bubbles; empty until a search has answered.
  String get markedQuery => _searched ? _query.trim() : '';

  bool get noMatches => _searched && _hits.isEmpty;
  bool get canGoOlder => _index < _hits.length - 1;
  bool get canGoNewer => _index > 0;

  void open() {
    if (_open) return;
    _open = true;
    onOpened?.call();
    notifyListeners();
  }

  void close() {
    if (!_open) return;
    _timer?.cancel();
    _revision++;
    _open = false;
    _query = '';
    _hits = const [];
    _index = 0;
    _searched = false;
    notifyListeners();
    onClosed?.call();
  }

  void setQuery(String query) {
    _query = query;
    _timer?.cancel();
    final revision = ++_revision;
    _hits = const [];
    _index = 0;
    _searched = false;
    if (query.trim().isNotEmpty) {
      _timer = Timer(debounce, () => unawaited(_run(query.trim(), revision)));
    }
    notifyListeners();
  }

  Future<void> _run(String query, int revision) async {
    List<String> hits;
    try {
      hits = await search(query);
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'chat search',
        ),
      );
      hits = const [];
    }
    if (revision != _revision || !_open) return;
    _hits = hits;
    _index = 0;
    _searched = true;
    notifyListeners();
    if (hits.isNotEmpty) onShow(hits.first);
  }

  void goOlder() {
    if (!canGoOlder) return;
    _index++;
    notifyListeners();
    onShow(_hits[_index]);
  }

  void goNewer() {
    if (!canGoNewer) return;
    _index--;
    notifyListeners();
    onShow(_hits[_index]);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// The chat header while searching: back, the field, "2 of 7" and up / down.
class ChatSearchBar extends StatefulWidget {
  const ChatSearchBar({super.key, required this.controller});

  final ChatSearchController controller;

  @override
  State<ChatSearchBar> createState() => _ChatSearchBarState();
}

class _ChatSearchBarState extends State<ChatSearchBar> {
  late final TextEditingController _text = TextEditingController(
    text: widget.controller.query,
  );

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _clear() {
    _text.clear();
    widget.controller.setQuery('');
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final rc = context.backgroundReadableColors;
    // Back closes search first; the next back leaves the chat.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) widget.controller.close();
      },
      child: SafeArea(
        bottom: false,
        child: Container(
          key: const ValueKey('chat-search-bar'),
          padding: const EdgeInsetsDirectional.fromSTEB(4, 8, 4, 8),
          decoration: BoxDecoration(
            color: rc.glassSurface,
            border: Border(bottom: BorderSide(color: rc.divider, width: 0.5)),
          ),
          child: ListenableBuilder(
            listenable: widget.controller,
            builder: (context, _) {
              final search = widget.controller;
              final count = search.hits.isNotEmpty
                  ? l10n.chat_search_count(search.index + 1, search.hits.length)
                  : search.noMatches
                  ? l10n.share_no_matches
                  : null;
              return Row(
                children: [
                  IconButton(
                    tooltip: l10n.chat_search_close,
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: rc.iconPrimary,
                    onPressed: search.close,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      onChanged: search.setQuery,
                      style: TextStyle(color: rc.textPrimary, fontSize: 15),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: l10n.chat_search_hint,
                        hintStyle: TextStyle(color: rc.placeholderText),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 20,
                          color: rc.iconMuted,
                        ),
                        suffixIcon: _text.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: l10n.calls_clear_search,
                                icon: const Icon(Icons.close_rounded, size: 18),
                                color: rc.iconMuted,
                                onPressed: _clear,
                              ),
                        filled: true,
                        fillColor: rc.composerInputFill,
                        contentPadding: const EdgeInsets.symmetric(
                          vertical: 10,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: rc.divider),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: rc.accent),
                        ),
                      ),
                    ),
                  ),
                  if (count != null)
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 8),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 140),
                        child: Text(
                          count,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: rc.textMuted,
                            fontSize: 13,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ),
                  // With nothing to step through, the arrows give their room to
                  // "No matches found".
                  if (!search.noMatches) ...[
                    IconButton(
                      tooltip: l10n.chat_search_previous,
                      icon: const Icon(Icons.keyboard_arrow_up_rounded),
                      color: rc.iconPrimary,
                      disabledColor: rc.disabledForeground,
                      onPressed: search.canGoOlder ? search.goOlder : null,
                    ),
                    IconButton(
                      tooltip: l10n.chat_search_next,
                      icon: const Icon(Icons.keyboard_arrow_down_rounded),
                      color: rc.iconPrimary,
                      disabledColor: rc.disabledForeground,
                      onPressed: search.canGoNewer ? search.goNewer : null,
                    ),
                  ] else
                    const SizedBox(width: 8),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}
