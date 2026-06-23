import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_navigation_bar.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../../application/orbit2_mock_data.dart';
import '../../domain/models/avatar_tier.dart';
import '../../domain/models/orbit2_friend.dart';
import '../../domain/models/orbit2_group.dart';
import '../../domain/models/orbit2_inner_item.dart';
import '../../domain/models/orbit2_layout_template.dart';
import '../../domain/models/orbit2_view_mode.dart';
import '../widgets/orbit2_backdrop.dart';
import '../widgets/orbit2_dock.dart';
import '../widgets/orbit2_floating_canvas.dart';
import '../widgets/orbit2_inbox_view.dart';
import 'orbit2_mock_chat_screen.dart';

/// Orbit2 — the unified, magnetic, floating-avatars prototype (visuals only).
class Orbit2Screen extends StatefulWidget {
  final String? userPeerId;
  final Uint8List? userAvatarBytes;
  final BackgroundPreference backgroundPreference;
  final String? activeTab;
  final void Function(String)? onSwitchView;

  const Orbit2Screen({
    super.key,
    this.userPeerId,
    this.userAvatarBytes,
    this.backgroundPreference = BackgroundPreference.defaultBackground,
    this.activeTab,
    this.onSwitchView,
  });

  @override
  State<Orbit2Screen> createState() => _Orbit2ScreenState();
}

class _Orbit2ScreenState extends State<Orbit2Screen> {
  static const List<int> _populations = [3, 6, 10, 16];

  int _populationIndex = 2;
  final List<Orbit2InnerItem> _innerItems = [];
  final List<Orbit2Friend> _canvasFriends = [];
  final List<Orbit2Group> _groups = [];
  bool _innerExpanded = false;
  int _innerResetToken = 0;
  bool _namesVisible = true;
  bool _manageMode = false;

  Orbit2LayoutTemplate _template = Orbit2LayoutTemplate.innerGravity;
  Orbit2ViewMode _viewMode = Orbit2ViewMode.constellation;
  int _layoutVersion = 0;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _rebuildMock();
  }

  void _rebuildMock() {
    final mock = Orbit2MockData.build(
      canvasCount: _populations[_populationIndex],
    );
    _innerItems
      ..clear()
      ..addAll(mock.innerCircle.map(Orbit2InnerItem.friend));
    _canvasFriends
      ..clear()
      ..addAll(mock.canvas);
    _groups
      ..clear()
      ..addAll(mock.groups);
  }

  void _openChat(Orbit2Friend friend) {
    Orbit2MockChatScreen.open(
      context,
      friend: friend,
      backgroundPreference: widget.backgroundPreference,
    );
  }

  void _openInnerChat(OrbitFriend friend) {
    _openChat(Orbit2Friend(friend: friend, tier: AvatarTier.sizeA));
  }

  void _openGroup(Orbit2Group group) {
    Orbit2MockChatScreen.openGroup(
      context,
      group: group,
      backgroundPreference: widget.backgroundPreference,
    );
  }

  void _toggleInnerExpand() {
    setState(() {
      _innerExpanded = !_innerExpanded;
      _layoutVersion++;
      _innerResetToken++; // recenter so the larger/smaller cluster fits
    });
  }

  void _toggleNames() {
    HapticFeedback.selectionClick(); // tactile confirmation the toggle fired
    setState(() {
      _namesVisible = !_namesVisible;
      _layoutVersion++; // re-space avatars for the new breathing room
      _innerResetToken++; // recenter so the grown/shrunk cluster stays on-screen
    });
  }

  void _confirm(String message, IconData icon, Color iconColor) {
    final readable = context.backgroundReadableColors;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          // Sit ABOVE the bottom dock so it never covers the controls.
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 70),
          backgroundColor: readable.surfaceRaised,
          duration: const Duration(milliseconds: 1800),
          content: Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  message,
                  style: TextStyle(color: readable.textPrimary, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
      );
  }

  void _toggleManageMode() {
    setState(() => _manageMode = !_manageMode);
  }

  void _promote(Orbit2Friend friend) {
    if (_innerItems.any((it) => it.id == friend.peerId)) return; // dedup
    HapticFeedback.mediumImpact();
    setState(() {
      _canvasFriends.removeWhere((f) => f.peerId == friend.peerId);
      _innerItems.insert(0, Orbit2InnerItem.friend(friend.friend));
    });
    if (!mounted) return;
    _confirm(
      AppLocalizations.of(context)!.orbit2_promoted(friend.username),
      Icons.adjust_rounded,
      AppColors.primaryAccent,
    );
  }

  void _promoteGroup(Orbit2Group group) {
    if (_innerItems.any((it) => it.id == group.id)) return; // dedup
    HapticFeedback.mediumImpact();
    setState(() {
      _groups.removeWhere((g) => g.id == group.id);
      _innerItems.insert(0, Orbit2InnerItem.group(group));
      _layoutVersion++;
    });
    if (!mounted) return;
    _confirm(
      AppLocalizations.of(context)!.orbit2_promoted_group(group.name),
      Icons.adjust_rounded,
      AppColors.primaryAccent,
    );
  }

  void _demoteGroup(Orbit2Group group) {
    HapticFeedback.mediumImpact();
    setState(() {
      _innerItems.removeWhere((it) => it.id == group.id);
      _groups.add(group);
      _layoutVersion++;
    });
    if (!mounted) return;
    _confirm(
      AppLocalizations.of(context)!.orbit2_removed(group.name),
      Icons.person_remove_rounded,
      context.backgroundReadableColors.iconSecondary,
    );
  }

  void _demote(OrbitFriend friend) {
    HapticFeedback.mediumImpact();
    setState(() {
      _innerItems.removeWhere((it) => it.id == friend.peerId);
      _canvasFriends.add(Orbit2Friend(friend: friend, tier: AvatarTier.sizeB));
      _layoutVersion++;
    });
    if (!mounted) return;
    _confirm(
      AppLocalizations.of(context)!.orbit2_removed(friend.username),
      Icons.person_remove_rounded,
      context.backgroundReadableColors.iconSecondary,
    );
  }

  void _selectTemplate(Orbit2LayoutTemplate t) {
    // Picking any spatial layout returns to the constellation (restoring the
    // inner circle), even if the template is unchanged.
    setState(() {
      _template = t;
      _viewMode = Orbit2ViewMode.constellation;
    });
  }

  void _showMessagesView() {
    setState(() {
      _viewMode = Orbit2ViewMode.messages;
      _manageMode = false;
    });
  }

  void _reset() {
    setState(() {
      _searchQuery = '';
      _innerExpanded = false;
      _manageMode = false;
      _layoutVersion++;
      _innerResetToken++;
    });
  }

  void _cyclePopulation() {
    setState(() {
      _populationIndex = (_populationIndex + 1) % _populations.length;
      _rebuildMock();
      _innerExpanded = false;
      _manageMode = false;
      _layoutVersion++;
      _innerResetToken++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final readable = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;
    final media = MediaQuery.of(context);
    final motionEnabled =
        !(media.disableAnimations || media.accessibleNavigation);

    return Orbit2Backdrop(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: SafeArea(
          child: Column(
            children: [
              _TopBar(
                readable: readable,
                l10n: l10n,
                population: _populations[_populationIndex],
                onCyclePopulation: _cyclePopulation,
                // The names toggle is a constellation-only view control (the
                // Messages list has no avatar labels).
                showNamesToggle: _viewMode == Orbit2ViewMode.constellation,
                namesVisible: _namesVisible,
                onToggleNames: _toggleNames,
              ),
              // The constellation hint advertises drag/long-press gestures that
              // the Messages list doesn't have — hide it there. "One Circle"
              // has no scatter to drag into either, so hide it there too.
              if (_viewMode == Orbit2ViewMode.constellation &&
                  _template != Orbit2LayoutTemplate.unifiedCircle)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    l10n.orbit2_hint,
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: readable.textMuted),
                  ),
                ),
              Expanded(
                child: Stack(
                  children: [
                    if (_viewMode == Orbit2ViewMode.messages)
                      Orbit2InboxView(
                        entries: Orbit2MockData.inboxEntries(
                          inner: _innerItems,
                          canvas: _canvasFriends,
                          groups: _groups,
                        ),
                        onOpenFriend: _openChat,
                        onOpenGroup: _openGroup,
                      )
                    else
                      Orbit2Canvas(
                        innerItems: _innerItems,
                        userPeerId: widget.userPeerId,
                        userAvatarBytes: widget.userAvatarBytes,
                        innerExpanded: _innerExpanded,
                        onToggleInnerExpand: _toggleInnerExpand,
                        floatingFriends: _canvasFriends,
                        floatingGroups: _groups,
                        template: _template,
                        layoutVersion: _layoutVersion,
                        innerResetToken: _innerResetToken,
                        searchQuery: _searchQuery,
                        motionEnabled: motionEnabled,
                        namesVisible: _namesVisible,
                        manageMode: _manageMode,
                        onOpenChat: _openChat,
                        onOpenInnerChat: _openInnerChat,
                        onOpenGroup: _openGroup,
                        onPromote: _promote,
                        onPromoteGroup: _promoteGroup,
                        onDemote: _demote,
                        onDemoteGroup: _demoteGroup,
                        onToggleNames: _toggleNames,
                      ),
                    Positioned(
                      left: 12,
                      right: 12,
                      bottom: 10,
                      child: Orbit2Dock(
                        template: _template,
                        viewMode: _viewMode,
                        manageMode: _manageMode,
                        onTemplateSelected: _selectTemplate,
                        onReset: _reset,
                        onToggleManage: _toggleManageMode,
                        onMessagesView: _showMessagesView,
                        onSearchChanged: (q) =>
                            setState(() => _searchQuery = q),
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.activeTab != null && widget.onSwitchView != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(0, 6, 0, 6),
                  child: FeedNavigationBar(
                    activeTab: widget.activeTab!,
                    onSwitchView: widget.onSwitchView!,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  final BackgroundReadableColors readable;
  final AppLocalizations l10n;
  final int population;
  final VoidCallback onCyclePopulation;
  final bool showNamesToggle;
  final bool namesVisible;
  final VoidCallback onToggleNames;

  const _TopBar({
    required this.readable,
    required this.l10n,
    required this.population,
    required this.onCyclePopulation,
    required this.showNamesToggle,
    required this.namesVisible,
    required this.onToggleNames,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 2),
      child: Row(
        children: [
          Text(
            l10n.nav_orbit2,
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.3,
              color: readable.textPrimary,
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            onTap: onCyclePopulation,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: readable.surfaceSubtle,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: readable.border.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.people_alt_rounded,
                    size: 14,
                    color: readable.iconMuted,
                  ),
                  const SizedBox(width: 5),
                  Text(
                    '$population',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: readable.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Always-visible names toggle — the reliable counterpart to the
          // double-tap-empty-space gesture, which only reaches the toggle on
          // genuinely empty canvas (occluded everywhere else).
          if (showNamesToggle) ...[
            const SizedBox(width: 8),
            GestureDetector(
              key: const ValueKey('orbit2-names-toggle'),
              onTap: onToggleNames,
              behavior: HitTestBehavior.opaque,
              child: Semantics(
                button: true,
                label: namesVisible
                    ? l10n.orbit2_names_hide
                    : l10n.orbit2_names_show,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: namesVisible
                        ? AppColors.primaryAccent.withValues(alpha: 0.14)
                        : readable.surfaceSubtle,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: namesVisible
                          ? AppColors.primaryAccent.withValues(alpha: 0.4)
                          : readable.border.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Icon(
                    namesVisible
                        ? Icons.label_rounded
                        : Icons.label_off_rounded,
                    size: 16,
                    color: namesVisible
                        ? AppColors.primaryAccent
                        : readable.iconMuted,
                  ),
                ),
              ),
            ),
          ],
          const Spacer(),
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: AppColors.primaryAccent.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primaryAccent.withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                l10n.orbit2_prototype_chip,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1ED760),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
