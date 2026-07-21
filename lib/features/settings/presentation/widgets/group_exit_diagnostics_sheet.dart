import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/groups/domain/models/group_exit_diagnostic.dart';
import 'package:flutter_app/features/groups/domain/repositories/group_exit_diagnostic_repository.dart';
import 'package:flutter_app/features/groups/presentation/group_exit_diagnostic_presenter.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_group.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Release-visible discovery entry for the bounded group-exit history.
///
/// Loading and a successful empty read deliberately occupy no layout space,
/// preserving Settings' one-screen contract. An initial read failure remains
/// discoverable because emptiness could not be established.
class GroupExitDiagnosticsSection extends StatefulWidget {
  const GroupExitDiagnosticsSection({
    super.key,
    required this.repository,
    required this.backgroundPreference,
  });

  final GroupExitDiagnosticRepository repository;
  final BackgroundPreference backgroundPreference;

  @override
  State<GroupExitDiagnosticsSection> createState() =>
      _GroupExitDiagnosticsSectionState();
}

class _GroupExitDiagnosticsSectionState
    extends State<GroupExitDiagnosticsSection> {
  List<GroupExitDiagnostic>? _diagnostics;
  bool _initialLoadFailed = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(GroupExitDiagnosticsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.repository, widget.repository)) {
      _diagnostics = null;
      _initialLoadFailed = false;
      _load();
    }
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    setState(() {
      _diagnostics = null;
      _initialLoadFailed = false;
    });
    try {
      final diagnostics = await widget.repository.loadNewest();
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _diagnostics = _newestFirst(diagnostics));
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() => _initialLoadFailed = true);
    }
  }

  Future<void> _openSheet() async {
    final diagnostics = _diagnostics;
    if (diagnostics == null || diagnostics.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final readableColors = BackgroundReadableColors.resolve(
          widget.backgroundPreference,
        );
        return Theme(
          data: theme.copyWith(
            extensions: [
              ...theme.extensions.values.where(
                (extension) => extension is! BackgroundReadableColors,
              ),
              readableColors,
            ],
          ),
          child: FractionallySizedBox(
            heightFactor: 0.85,
            child: Material(
              color: readableColors.surfaceBase,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              clipBehavior: Clip.antiAlias,
              child: GroupExitDiagnosticsSheet(
                repository: widget.repository,
                initialDiagnostics: diagnostics,
                onDiagnosticsChanged: (updated) {
                  if (!mounted) return;
                  setState(() => _diagnostics = _newestFirst(updated));
                },
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_diagnostics == null && !_initialLoadFailed) {
      return const SizedBox.shrink(
        key: ValueKey('group-exit-diagnostics-loading-hidden'),
      );
    }

    final l10n = AppLocalizations.of(context)!;
    if (_initialLoadFailed) {
      return _visibleSection(
        l10n,
        SettingsListRow(
          key: const ValueKey('group-exit-diagnostics-unavailable-row'),
          icon: Icons.support_agent_outlined,
          label: l10n.settings_group_exit_diagnostics_title,
          subtitle:
              '${l10n.settings_group_exit_diagnostics_unavailable} '
              '${l10n.settings_group_exit_diagnostics_unavailable_hint}',
          onTap: _load,
        ),
      );
    }

    final diagnostics = _diagnostics!;
    if (diagnostics.isEmpty) {
      return const SizedBox.shrink(
        key: ValueKey('group-exit-diagnostics-empty-hidden'),
      );
    }

    return _visibleSection(
      l10n,
      SettingsListRow(
        key: const ValueKey('group-exit-diagnostics-open-row'),
        icon: Icons.support_agent_outlined,
        label: l10n.settings_group_exit_diagnostics_title,
        value: l10n.settings_group_exit_diagnostics_count(diagnostics.length),
        onTap: _openSheet,
      ),
    );
  }

  Widget _visibleSection(AppLocalizations l10n, Widget row) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsGroupCard(
          label: l10n.settings_group_exit_diagnostics_section,
          children: [row],
        ),
        const SizedBox(height: 14),
      ],
    );
  }
}

/// The release-visible history sheet. It never renders internal intent refs,
/// reason values, exception text, or any raw identifier.
class GroupExitDiagnosticsSheet extends StatefulWidget {
  const GroupExitDiagnosticsSheet({
    super.key,
    required this.repository,
    required this.initialDiagnostics,
    this.onDiagnosticsChanged,
  });

  final GroupExitDiagnosticRepository repository;
  final List<GroupExitDiagnostic> initialDiagnostics;
  final ValueChanged<List<GroupExitDiagnostic>>? onDiagnosticsChanged;

  @override
  State<GroupExitDiagnosticsSheet> createState() =>
      _GroupExitDiagnosticsSheetState();
}

enum _HistoryOperation { reload, clear }

class _GroupExitDiagnosticsSheetState extends State<GroupExitDiagnosticsSheet> {
  late List<GroupExitDiagnostic> _diagnostics;
  _HistoryOperation? _operation;
  String? _announcement;

  @override
  void initState() {
    super.initState();
    _diagnostics = _newestFirst(widget.initialDiagnostics);
  }

  Future<void> _reload() async {
    if (_operation != null) return;
    setState(() {
      _operation = _HistoryOperation.reload;
      _announcement = null;
    });
    try {
      final diagnostics = _newestFirst(await widget.repository.loadNewest());
      if (!mounted) return;
      setState(() {
        _diagnostics = diagnostics;
        _announcement = AppLocalizations.of(
          context,
        )!.settings_group_exit_diagnostics_reloaded;
      });
      widget.onDiagnosticsChanged?.call(diagnostics);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _announcement = AppLocalizations.of(
          context,
        )!.settings_group_exit_diagnostics_reload_failed;
      });
    } finally {
      if (mounted) setState(() => _operation = null);
    }
  }

  Future<void> _clear() async {
    if (_operation != null) return;
    setState(() {
      _operation = _HistoryOperation.clear;
      _announcement = null;
    });
    try {
      await widget.repository.clear();
      // Re-query after Clear: an append that linearizes after Clear must remain
      // visible instead of being erased optimistically in widget state.
      final diagnostics = _newestFirst(await widget.repository.loadNewest());
      if (!mounted) return;
      setState(() {
        _diagnostics = diagnostics;
        _announcement = AppLocalizations.of(
          context,
        )!.settings_group_exit_diagnostics_cleared;
      });
      widget.onDiagnosticsChanged?.call(diagnostics);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _announcement = AppLocalizations.of(
          context,
        )!.settings_group_exit_diagnostics_clear_failed;
      });
    } finally {
      if (mounted) setState(() => _operation = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final readableColors = context.backgroundReadableColors;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.settings_group_exit_diagnostics_title,
                    style: TextStyle(
                      color: readableColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  key: const ValueKey('group-exit-diagnostics-close'),
                  tooltip: l10n.settings_group_exit_diagnostics_close,
                  onPressed: () => Navigator.maybePop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Wrap(
                spacing: 4,
                runSpacing: 4,
                alignment: WrapAlignment.end,
                children: [
                  TextButton.icon(
                    key: const ValueKey('group-exit-diagnostics-reload'),
                    onPressed: _operation == null ? _reload : null,
                    icon: _operation == _HistoryOperation.reload
                        ? const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.refresh, size: 18),
                    label: Text(l10n.settings_group_exit_diagnostics_reload),
                  ),
                  TextButton.icon(
                    key: const ValueKey('group-exit-diagnostics-clear'),
                    onPressed: _operation == null ? _clear : null,
                    icon: _operation == _HistoryOperation.clear
                        ? const SizedBox.square(
                            dimension: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.delete_outline, size: 18),
                    label: Text(l10n.settings_group_exit_diagnostics_clear),
                  ),
                ],
              ),
            ),
            if (_announcement case final announcement?)
              Semantics(
                key: const ValueKey('group-exit-diagnostics-announcement'),
                container: true,
                liveRegion: true,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      announcement,
                      style: TextStyle(
                        color: readableColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ),
              ),
            Expanded(
              child: _diagnostics.isEmpty
                  ? Center(
                      child: Text(
                        l10n.settings_group_exit_diagnostics_empty,
                        textAlign: TextAlign.center,
                        style: TextStyle(color: readableColors.textMuted),
                      ),
                    )
                  : Semantics(
                      key: const ValueKey(
                        'group-exit-diagnostics-live-history',
                      ),
                      container: true,
                      liveRegion: true,
                      child: ListView.separated(
                        key: const ValueKey('group-exit-diagnostics-list'),
                        itemCount: _diagnostics.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 8),
                        itemBuilder: (context, index) =>
                            _DiagnosticCard(_diagnostics[index]),
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticCard extends StatelessWidget {
  const _DiagnosticCard(this.diagnostic);

  final GroupExitDiagnostic diagnostic;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final readableColors = context.backgroundReadableColors;
    final code = isolatedGroupExitPublicCode(diagnostic.publicCode);
    final groupReference = _isolatedReference(diagnostic.groupRef);
    final summary = localizedGroupExitDiagnosticSummary(
      l10n,
      diagnostic.publicCode,
    );
    final occurredAt = diagnostic.occurredAt.toLocal();
    final materialL10n = MaterialLocalizations.of(context);
    final timestamp =
        '${materialL10n.formatMediumDate(occurredAt)} · '
        '${materialL10n.formatTimeOfDay(TimeOfDay.fromDateTime(occurredAt))}';

    return Semantics(
      container: true,
      child: Container(
        key: ValueKey('group-exit-diagnostic-${diagnostic.id ?? code}'),
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: readableColors.surfaceSubtle,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: readableColors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  code,
                  textDirection: TextDirection.ltr,
                  style: TextStyle(
                    color: readableColors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.5,
                  ),
                ),
                Text(
                  timestamp,
                  style: TextStyle(
                    color: readableColors.textMuted,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              summary,
              style: TextStyle(
                color: readableColors.textPrimary,
                fontSize: 14,
                height: 1.3,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              l10n.settings_group_exit_diagnostics_group_reference(
                groupReference,
              ),
              style: TextStyle(color: readableColors.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

String _isolatedReference(String value) =>
    '$groupExitCodeLeftToRightIsolate$value'
    '$groupExitCodePopDirectionalIsolate';

List<GroupExitDiagnostic> _newestFirst(
  Iterable<GroupExitDiagnostic> diagnostics,
) {
  final sorted = List<GroupExitDiagnostic>.of(diagnostics);
  sorted.sort((left, right) {
    final leftId = left.id;
    final rightId = right.id;
    if (leftId != null && rightId != null && leftId != rightId) {
      return rightId.compareTo(leftId);
    }
    return right.occurredAt.compareTo(left.occurredAt);
  });
  return List<GroupExitDiagnostic>.unmodifiable(sorted);
}
