import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import '../../application/call_history_access.dart';
import '../../application/call_redial_controller.dart';
import '../../application/outgoing_call_capability.dart';
import '../../data/call_history_repository.dart';
import '../../data/call_history_conversation_timeline_source.dart';
import '../../../conversation/presentation/widgets/call_timeline_row.dart';

/// Browses the existing durable local history without marking chats/calls read.
class CallsPage extends StatefulWidget {
  const CallsPage({
    super.key,
    required this.browser,
    required this.changes,
    required this.redial,
    this.history,
  });
  final CallHistoryBrowser browser;
  final Stream<void> changes;
  final CallRedialController redial;

  /// Proves a missed-call row is still the contact's newest call. Without it
  /// such rows refuse to dial.
  final CallHistoryAccess? history;
  @override
  State<CallsPage> createState() => _CallsPageState();
}

class _CallsPageState extends State<CallsPage> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  StreamSubscription<void>? _subscription;
  Timer? _debounce;
  List<CallHistoryListRow> _rows = [];
  CallHistoryCursor? _next;
  int _generation = 0;
  int _total = 0;
  int _missed = 0;
  bool _missedOnly = false;
  bool _loading = false;
  bool _error = false;
  bool _redialing = false;
  @override
  void initState() {
    super.initState();
    _subscription = widget.changes.listen((_) => _load(reset: true));
    _scroll.addListener(() {
      if (_scroll.position.extentAfter < 250 &&
          !_loading &&
          !_error &&
          _next != null) {
        _load();
      }
    });
    _load(reset: true);
  }

  @override
  void dispose() {
    _generation++;
    _debounce?.cancel();
    unawaited(_subscription?.cancel());
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool reset = false}) async {
    if (!reset && (_loading || _next == null)) return;
    final generation = reset ? ++_generation : _generation;
    setState(() {
      _loading = true;
      _error = false;
      if (reset) {
        _rows = [];
        _next = null;
      }
    });
    try {
      final page = await widget.browser.browse(
        missedOnly: _missedOnly,
        search: _search.text,
        cursor: reset ? null : _next,
      );
      if (!mounted || generation != _generation) return;
      setState(() {
        final known = _rows.map((r) => r.entry.callId).toSet();
        _rows = [
          ..._rows,
          ...page.rows.where((r) => known.add(r.entry.callId)),
        ];
        _total = page.total;
        _missed = page.missed;
        _next = page.next;
      });
    } catch (_) {
      if (mounted && generation == _generation) setState(() => _error = true);
    } finally {
      if (mounted && generation == _generation) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _redial(CallHistoryListRow row) async {
    if (_redialing) return;
    final entry = row.entry;
    final history = widget.history;
    var superseded = false;
    Future<bool> Function()? isEligible;
    if (isMissedIncomingCall(entry)) {
      if (history == null) {
        superseded = true;
      } else {
        isEligible = () async {
          final latest = await history.recentCallsForContact(
            entry.contactAccountPeerId,
          );
          superseded = latest.isEmpty || latest.first.callId != entry.callId;
          return !superseded;
        };
      }
    }
    var result = OutgoingCallStartResult.unavailable;
    if (!superseded) {
      setState(() => _redialing = true);
      result = await widget.redial.start(
        entry.contactAccountPeerId,
        isCurrent: () => mounted,
        isEligible: isEligible,
      );
      if (!mounted) return;
      setState(() => _redialing = false);
    }
    if (result == OutgoingCallStartResult.started ||
        result == OutgoingCallStartResult.canceled) {
      return;
    }
    final l10n = AppLocalizations.of(context)!;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          superseded
              ? l10n.call_back_superseded
              : result == OutgoingCallStartResult.microphoneDenied
              ? l10n.call_end_permission
              : l10n.call_end_unavailable,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.calls_title),
        actions: [
          IconButton(
            tooltip: l10n.calls_refresh,
            onPressed: () => _load(reset: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _search,
              decoration: InputDecoration(
                labelText: l10n.calls_search,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  tooltip: l10n.calls_clear_search,
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _search.clear();
                    _debounce?.cancel();
                    _load(reset: true);
                  },
                ),
              ),
              onChanged: (_) {
                _debounce?.cancel();
                _debounce = Timer(
                  const Duration(milliseconds: 250),
                  () => _load(reset: true),
                );
              },
            ),
          ),
          Wrap(
            spacing: 12,
            children: [
              ChoiceChip(
                label: Text('${l10n.calls_all} ($_total)'),
                selected: !_missedOnly,
                onSelected: (_) {
                  _missedOnly = false;
                  _load(reset: true);
                },
              ),
              ChoiceChip(
                label: Text('${l10n.calls_missed} ($_missed)'),
                selected: _missedOnly,
                onSelected: (_) {
                  _missedOnly = true;
                  _load(reset: true);
                },
              ),
            ],
          ),
          if (_loading) const LinearProgressIndicator(),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _load(reset: true),
              child: ListView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (_error)
                    ListTile(
                      title: Text(l10n.calls_load_error),
                      trailing: TextButton(
                        onPressed: () => _load(reset: _rows.isEmpty),
                        child: Text(l10n.calls_refresh),
                      ),
                    ),
                  if (!_error && !_loading && _rows.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        l10n.calls_empty,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  for (final row in _rows)
                    ListTile(
                      key: ValueKey('history-${row.entry.callId.value}'),
                      title: Text(
                        row.contactName?.trim().isNotEmpty == true
                            ? row.contactName!
                            : l10n.call_unknown_contact,
                      ),
                      subtitle: Text(
                        '${callTimelineRowText(projectCallTimelineEntry(row.entry), l10n)}\n'
                        '${DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag()).add_Hm().format(row.entry.startedAt.toLocal())}',
                      ),
                      isThreeLine: true,
                      trailing: IconButton(
                        tooltip: l10n.call_back,
                        icon: const Icon(Icons.call_outlined),
                        onPressed: _redialing ? null : () => _redial(row),
                      ),
                    ),
                  if (_next != null && !_loading)
                    TextButton(
                      onPressed: () => _load(),
                      child: Text(l10n.calls_more),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
