import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../domain/models/orbit2_layout_template.dart';
import '../../domain/models/orbit2_view_mode.dart';

IconData _templateIcon(Orbit2LayoutTemplate t) {
  switch (t) {
    case Orbit2LayoutTemplate.innerGravity:
      return Icons.filter_center_focus_rounded;
    case Orbit2LayoutTemplate.nebulaScatter:
      return Icons.blur_on_rounded;
    case Orbit2LayoutTemplate.looseHoneycomb:
      return Icons.grid_view_rounded;
    case Orbit2LayoutTemplate.tieredBands:
      return Icons.view_agenda_rounded;
  }
}

String templateLabel(AppLocalizations l10n, Orbit2LayoutTemplate t) {
  switch (t) {
    case Orbit2LayoutTemplate.innerGravity:
      return l10n.orbit2_template_gravity;
    case Orbit2LayoutTemplate.nebulaScatter:
      return l10n.orbit2_template_nebula;
    case Orbit2LayoutTemplate.looseHoneycomb:
      return l10n.orbit2_template_honeycomb;
    case Orbit2LayoutTemplate.tieredBands:
      return l10n.orbit2_template_tiered;
  }
}

/// Floating bottom control dock: expandable layout selector (+ reset) and an
/// expandable search pill. Keeps the canvas dominant.
class Orbit2Dock extends StatelessWidget {
  final Orbit2LayoutTemplate template;
  final Orbit2ViewMode viewMode;
  final bool manageMode;
  final ValueChanged<Orbit2LayoutTemplate> onTemplateSelected;
  final VoidCallback onReset;
  final VoidCallback onToggleManage;
  final VoidCallback onMessagesView;
  final ValueChanged<String> onSearchChanged;

  const Orbit2Dock({
    super.key,
    required this.template,
    required this.viewMode,
    required this.manageMode,
    required this.onTemplateSelected,
    required this.onReset,
    required this.onToggleManage,
    required this.onMessagesView,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    // Manage + search apply to the constellation only; hide them in Messages.
    final isConstellation = viewMode == Orbit2ViewMode.constellation;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Orbit2LayoutSelector(
          template: template,
          viewMode: viewMode,
          onSelected: onTemplateSelected,
          onReset: onReset,
          onMessagesView: onMessagesView,
        ),
        if (isConstellation) ...[
          const SizedBox(width: 8),
          Orbit2ManagePill(active: manageMode, onTap: onToggleManage),
        ],
        const Spacer(),
        if (isConstellation) Orbit2SearchPill(onChanged: onSearchChanged),
      ],
    );
  }
}

/// A compact icon pill toggling inner-circle Manage mode (add/remove members).
/// Icon-only so the dock never overflows when the search field expands; the
/// active state swaps to a check and tints accent.
class Orbit2ManagePill extends StatelessWidget {
  final bool active;
  final VoidCallback onTap;
  const Orbit2ManagePill({super.key, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final readable = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;
    return GestureDetector(
      key: const ValueKey('orbit2-manage-toggle'),
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: _glass(
        readable: readable,
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active
                ? AppColors.primaryAccent.withValues(alpha: 0.18)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Tooltip(
            message: active ? l10n.orbit2_manage_done : l10n.orbit2_manage,
            child: Icon(
              active ? Icons.check_rounded : Icons.group_add_rounded,
              size: 19,
              color: active ? AppColors.primaryAccent : readable.iconSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

Widget _glass({required Widget child, required BackgroundReadableColors readable}) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(16),
    child: BackdropFilter(
      // sigma 10 (was 16): the dock blurs re-sample the backdrop on every canvas
      // repaint; a smaller kernel cuts that GPU cost with a near-imperceptible
      // visual change over the fixed dark starfield.
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        decoration: BoxDecoration(
          color: readable.glassSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: readable.glassBorder),
        ),
        child: child,
      ),
    ),
  );
}

/// Collapsed: a pill showing the current template. Tap → the 4 options + Reset
/// pop up above it; choosing one switches and collapses.
class Orbit2LayoutSelector extends StatefulWidget {
  final Orbit2LayoutTemplate template;
  final Orbit2ViewMode viewMode;
  final ValueChanged<Orbit2LayoutTemplate> onSelected;
  final VoidCallback onReset;
  final VoidCallback onMessagesView;

  const Orbit2LayoutSelector({
    super.key,
    required this.template,
    required this.viewMode,
    required this.onSelected,
    required this.onReset,
    required this.onMessagesView,
  });

  @override
  State<Orbit2LayoutSelector> createState() => _Orbit2LayoutSelectorState();
}

class _Orbit2LayoutSelectorState extends State<Orbit2LayoutSelector> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final readable = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _glass(
              readable: readable,
              child: SizedBox(
                width: 172,
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _OptionRow(
                        icon: Icons.forum_rounded,
                        label: l10n.orbit2_view_messages,
                        selected: widget.viewMode == Orbit2ViewMode.messages,
                        readable: readable,
                        onTap: () {
                          widget.onMessagesView();
                          setState(() => _expanded = false);
                        },
                      ),
                      Divider(height: 10, color: readable.divider),
                      for (final t in Orbit2LayoutTemplate.values)
                        _OptionRow(
                          icon: _templateIcon(t),
                          label: templateLabel(l10n, t),
                          selected:
                              widget.viewMode == Orbit2ViewMode.constellation &&
                                  t == widget.template,
                          readable: readable,
                          onTap: () {
                            widget.onSelected(t);
                            setState(() => _expanded = false);
                          },
                        ),
                      Divider(height: 10, color: readable.divider),
                      _OptionRow(
                        icon: Icons.refresh_rounded,
                        label: l10n.orbit2_reset,
                        selected: false,
                        readable: readable,
                        onTap: () {
                          widget.onReset();
                          setState(() => _expanded = false);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          behavior: HitTestBehavior.opaque,
          child: _glass(
            readable: readable,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.viewMode == Orbit2ViewMode.messages
                        ? Icons.forum_rounded
                        : _templateIcon(widget.template),
                    size: 17,
                    color: AppColors.primaryAccent,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    widget.viewMode == Orbit2ViewMode.messages
                        ? l10n.orbit2_view_messages
                        : templateLabel(l10n, widget.template),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: readable.textPrimary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_down_rounded
                        : Icons.keyboard_arrow_up_rounded,
                    size: 18,
                    color: readable.iconMuted,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _OptionRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final BackgroundReadableColors readable;
  final VoidCallback onTap;

  const _OptionRow({
    required this.icon,
    required this.label,
    required this.selected,
    required this.readable,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected
              ? AppColors.primaryAccent.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? AppColors.primaryAccent : readable.iconSecondary,
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected
                      ? const Color(0xFF1ED760)
                      : readable.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A search affordance that expands from an icon into a field on tap.
class Orbit2SearchPill extends StatefulWidget {
  final ValueChanged<String> onChanged;
  const Orbit2SearchPill({super.key, required this.onChanged});

  @override
  State<Orbit2SearchPill> createState() => _Orbit2SearchPillState();
}

class _Orbit2SearchPillState extends State<Orbit2SearchPill> {
  bool _open = false;
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _close() {
    _controller.clear();
    widget.onChanged('');
    setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    final readable = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;

    return _glass(
      readable: readable,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        height: 40,
        width: _open ? 186 : 40,
        // Lay the content out at full width and clip to the animating box so the
        // Row never gets squeezed below its content (no transient overflow).
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.centerLeft,
            minWidth: 0,
            maxWidth: 186,
            child: SizedBox(
              width: 186,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (_open) {
                          _close();
                        } else {
                          setState(() => _open = true);
                        }
                      },
                      child: Icon(
                        _open ? Icons.close_rounded : Icons.search_rounded,
                        size: 19,
                        color: readable.iconSecondary,
                      ),
                    ),
                    if (_open) ...[
                      const SizedBox(width: 6),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          autofocus: true,
                          onChanged: widget.onChanged,
                          style: TextStyle(
                              fontSize: 13.5, color: readable.textPrimary),
                          cursorColor: AppColors.primaryAccent,
                          decoration: InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            hintText: l10n.orbit2_search_hint,
                            hintStyle: TextStyle(
                              fontSize: 13.5,
                              color: readable.placeholderText,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
