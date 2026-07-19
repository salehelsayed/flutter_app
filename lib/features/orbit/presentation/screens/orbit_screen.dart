import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/p2p/presentation/widgets/connection_status_indicator.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/inner_circle_interactive_surface.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_navigation_bar.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/presentation/widgets/pending_group_invite_card.dart';
import 'package:flutter_app/features/introduction/application/load_introductions_use_case.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/presentation/widgets/intro_group_header.dart';
import 'package:flutter_app/features/introduction/presentation/widgets/intro_row.dart';
import 'package:flutter_app/features/groups/presentation/widgets/expandable_fab.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_group.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_view_mode.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_close_button.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_view_toggle_button.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/friend_row.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/group_row.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_search_trigger.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_search_dock.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_intro_dock.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/friends_filter_toggle.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/swipeable_friend_row.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/archived_empty_state.dart';

@immutable
class OrbitIntrosViewData {
  final Map<String, List<IntroductionModel>> groupedIntros;
  final List<FoldedIntroductionReviewItem>? foldedReviewItems;
  final Map<String, String> introducerUsernames;
  final String ownPeerId;
  final List<PendingGroupInvite> pendingGroupInvites;
  final Map<String, PendingInviteRowOutcome> inviteRowOutcomes;
  final Set<String> askNewInviteIds;
  final Set<String> unavailableInviteContactIds;
  final Set<String> processingIntroductionIds;
  final Set<String> processingPendingInviteIds;
  final void Function(String introductionId) onAccept;
  final void Function(String introductionId) onPass;
  final void Function(String introductionId)? onDelete;
  final void Function(String peerId)? onSendMessage;
  final void Function(PendingGroupInvite invite)? onAcceptPendingInvite;
  final void Function(PendingGroupInvite invite)? onDeclinePendingInvite;
  final void Function(PendingGroupInvite invite)? onRetryPendingInvite;
  final void Function(String inviteId)? onAskForNewInvite;
  final Set<String> blockedPeerIds;

  const OrbitIntrosViewData({
    required this.groupedIntros,
    this.foldedReviewItems,
    required this.introducerUsernames,
    required this.ownPeerId,
    this.pendingGroupInvites = const [],
    this.inviteRowOutcomes = const <String, PendingInviteRowOutcome>{},
    this.askNewInviteIds = const <String>{},
    this.unavailableInviteContactIds = const <String>{},
    this.processingIntroductionIds = const {},
    this.processingPendingInviteIds = const {},
    required this.onAccept,
    required this.onPass,
    this.onDelete,
    this.onSendMessage,
    this.onAcceptPendingInvite,
    this.onDeclinePendingInvite,
    this.onRetryPendingInvite,
    this.onAskForNewInvite,
    this.blockedPeerIds = const {},
  });

  int get introCount =>
      foldedReviewItems?.length ??
      groupedIntros.values.fold(0, (sum, entries) => sum + entries.length);

  Set<String> get _pendingInviteIds =>
      pendingGroupInvites.map((invite) => invite.groupId).toSet();

  int get ghostInviteCount => inviteRowOutcomes.keys
      .where((id) => !_pendingInviteIds.contains(id))
      .length;

  bool get hasInviteRows =>
      pendingGroupInvites.isNotEmpty || ghostInviteCount > 0;

  int get reviewCount =>
      introCount + pendingGroupInvites.length + ghostInviteCount;
}

@immutable
class OrbitHeaderProjection {
  final String? userPeerId;
  final Uint8List? userAvatarBytes;

  /// 1:1 friends only. Still feeds the friend-only search "inner circle" badge
  /// (`indexOf(friend) < 13`) on the all-chats/search surface, which is a
  /// deliberately friend-only cosmetic (see 197 Accepted Differences).
  final List<OrbitFriend> allFriends;

  /// 197 — the merged friends+groups ring set the Inner-Circle visualization
  /// renders, interleaved by recency (blocked friends already dropped, archived
  /// groups already excluded upstream). Built via `mergeInnerCircleItems`.
  final List<OrbitItem> innerItems;

  const OrbitHeaderProjection({
    this.userPeerId,
    this.userAvatarBytes,
    this.allFriends = const [],
    this.innerItems = const [],
  });
}

@immutable
class OrbitViewProjection {
  final List<OrbitFriend> allFriends;
  final List<OrbitFriend> displayedFriends;
  final List<OrbitGroup> groups;
  final List<OrbitItem> mergedItems;
  final int activeCount;
  final int archivedCount;
  final int introCount;
  final int pendingGroupInviteCount;
  final int reviewCount;
  final int unseenReviewCount;
  final OrbitIntrosViewData? introsData;
  final bool searchActive;
  final String searchQuery;
  final String filterTab;
  final bool showLoadingPlaceholders;

  const OrbitViewProjection({
    this.allFriends = const [],
    this.displayedFriends = const [],
    this.groups = const [],
    this.mergedItems = const [],
    this.activeCount = 0,
    this.archivedCount = 0,
    this.introCount = 0,
    this.pendingGroupInviteCount = 0,
    this.reviewCount = 0,
    this.unseenReviewCount = 0,
    this.introsData,
    this.searchActive = false,
    this.searchQuery = '',
    this.filterTab = 'all',
    this.showLoadingPlaceholders = false,
  });
}

enum _OrbitIntroEntryType {
  context,
  pendingInviteHeader,
  pendingInvite,
  pendingInviteOutcome,
  introHeader,
  introRow,
  foldedIntroRow,
  spacer,
}

// 207: right-hand cap for the intro dock slot = 64 (the 211 pill's right
// anchor) + 134 (widest pill state: 'Online ✦' + debug connection count,
// TC-207-05-measured) + 8 gap. Scaled by the ambient text scale at the mount
// so the dock always yields to the intrinsic-width pill — adjust the constant,
// never let the two overlap (TC-207-05 pins the widest state).
const double _kIntroDockRightReserve = 206;

class _OrbitIntroEntry {
  final _OrbitIntroEntryType type;
  final String? introducerUsername;
  final IntroductionModel? introduction;
  final FoldedIntroductionReviewItem? foldedIntroduction;
  final PendingGroupInvite? pendingInvite;
  final String? pendingInviteOutcomeId;
  final PendingInviteRowOutcome? pendingInviteOutcome;

  const _OrbitIntroEntry._(
    this.type, {
    this.introducerUsername,
    this.introduction,
    this.foldedIntroduction,
    this.pendingInvite,
    this.pendingInviteOutcomeId,
    this.pendingInviteOutcome,
  });

  const _OrbitIntroEntry.context() : this._(_OrbitIntroEntryType.context);

  const _OrbitIntroEntry.header(String introducerUsername)
    : this._(
        _OrbitIntroEntryType.introHeader,
        introducerUsername: introducerUsername,
      );

  const _OrbitIntroEntry.row(IntroductionModel introduction)
    : this._(_OrbitIntroEntryType.introRow, introduction: introduction);

  const _OrbitIntroEntry.foldedRow(
    FoldedIntroductionReviewItem foldedIntroduction,
  ) : this._(
        _OrbitIntroEntryType.foldedIntroRow,
        foldedIntroduction: foldedIntroduction,
      );

  const _OrbitIntroEntry.pendingInviteHeader()
    : this._(_OrbitIntroEntryType.pendingInviteHeader);

  const _OrbitIntroEntry.pendingInvite(PendingGroupInvite invite)
    : this._(_OrbitIntroEntryType.pendingInvite, pendingInvite: invite);

  const _OrbitIntroEntry.pendingInviteOutcome(
    String inviteId,
    PendingInviteRowOutcome outcome,
  ) : this._(
        _OrbitIntroEntryType.pendingInviteOutcome,
        pendingInviteOutcomeId: inviteId,
        pendingInviteOutcome: outcome,
      );

  const _OrbitIntroEntry.spacer() : this._(_OrbitIntroEntryType.spacer);
}

/// Pure UI layout for the Orbit screen.
///
/// Receives all state and callbacks from OrbitWired. 205 item 6 — a thin
/// StatefulWidget that owns the transient inner-circle edit flag; the layout
/// itself lives in [_OrbitScreenView].
class OrbitScreen extends StatefulWidget {
  final ValueListenable<OrbitHeaderProjection> headerProjectionListenable;
  final ValueListenable<OrbitViewProjection> listProjectionListenable;
  final ScrollController scrollController;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final Animation<double> collapseAnimation;
  final Animation<double> searchDockAnimation;
  final Animation<double> searchTriggerAnimation;
  final VoidCallback onClose;
  final void Function(OrbitFriend) onFriendTap;

  /// Tapping a friend's avatar specifically (opens their contact profile).
  /// Optional so lightweight callers/tests can omit it.
  final void Function(OrbitFriend)? onFriendAvatarTap;
  final VoidCallback onSearchOpen;
  final VoidCallback onSearchClose;
  final void Function(String) onSearchChanged;
  final VoidCallback onSearchClear;
  final void Function(String) onFilterChanged;
  final void Function(OrbitFriend) onArchiveFriend;
  final void Function(OrbitFriend) onUnarchiveFriend;
  final void Function(OrbitFriend) onBlockFriend;
  final void Function(OrbitFriend) onUnblockFriend;
  final void Function(OrbitFriend) onDeleteFriend;
  final ValueNotifier<Key?> openRowNotifier;
  final void Function(OrbitGroup) onGroupTap;
  final void Function(GroupType) onCreateGroup;
  final void Function(OrbitGroup) onArchiveGroup;
  final void Function(OrbitGroup) onUnarchiveGroup;
  final void Function(OrbitGroup) onDeleteGroup;

  /// "Retry now" / "Leave" for a stuck (given-up) rejoin row (G2). Optional so
  /// lightweight callers/tests can omit them.
  final void Function(OrbitGroup)? onRetryStuckRejoinGroup;
  final void Function(OrbitGroup)? onLeaveStuckGroup;
  /// 193: which surface to show. Defaults to [OrbitViewMode.allChats] so the
  /// existing bare-`OrbitScreen` pumps (loading / archived-groups / intro-route
  /// harnesses) keep rendering the classic list without change.
  final OrbitViewMode viewMode;

  /// 193: flips [viewMode]. When null the top-left toggle is not mounted, so
  /// bare-`OrbitScreen` callers stay unaffected.
  final VoidCallback? onToggleView;
  final String? activeTab;
  final void Function(String)? onSwitchView;
  final ValueListenable<int>? feedUnreadCountListenable;
  final VoidCallback? onIntroBannerTap;
  final VoidCallback? onIntroDockTap;
  final VoidCallback? onIntroDockDismissed;
  final VoidCallback? onHeaderBuild;
  final VoidCallback? onListBuild;
  final BackgroundPreference backgroundPreference;
  final BackgroundReadableTone? readableToneOverride;

  /// 198 — persists the Inner-Circle sculpt geometry. Null ⇒ no persistence
  /// (bare-`OrbitScreen` pumps that never sculpt).
  final SecureKeyStore? secureKeyStore;

  /// 198 — bubbles the edit-session active flag up to the feed↔orbit host-swipe
  /// yield gate (INV-8).
  final ValueChanged<bool>? onInnerCircleEditSessionChanged;

  /// 198 — poked by the host on the Feed→Orbit rising edge to reset the
  /// Inner-Circle transient state (expansion / labels / edit / find).
  final Listenable? innerCircleResetListenable;

  /// 206 — non-null when the host wires the Inner-Circle center self-avatar to
  /// open Settings. Threaded down to [InnerCircleInteractiveSurface].
  final VoidCallback? onSelfAvatarTap;

  /// 211 — non-null when the host wires the connection-status pill (migrated
  /// from the Feed header) into the top-right chrome next to the "+". Null ⇒
  /// no pill (bare-`OrbitScreen` pumps stay unaffected).
  final P2PService? p2pService;

  /// When true, the persistent-nav home host suppresses the center Feed/Orbit
  /// toggle bar (chromeless-Orbit landing) while keeping the rest of the nav
  /// band — rings find pill / search trigger — and all its layout reservations
  /// intact. Feed stays reachable via the host swipe and its own toggle. See
  /// [_OrbitScreenView.hideShellNav]. Defaults false so bare pumps and non-home
  /// callers keep the toggle.
  final bool hideShellNav;

  const OrbitScreen({
    super.key,
    required this.headerProjectionListenable,
    required this.listProjectionListenable,
    required this.scrollController,
    required this.searchController,
    required this.searchFocusNode,
    required this.collapseAnimation,
    required this.searchDockAnimation,
    required this.searchTriggerAnimation,
    required this.onClose,
    required this.onFriendTap,
    this.onFriendAvatarTap,
    required this.onSearchOpen,
    required this.onSearchClose,
    required this.onSearchChanged,
    required this.onSearchClear,
    required this.onFilterChanged,
    required this.onArchiveFriend,
    required this.onUnarchiveFriend,
    required this.onBlockFriend,
    required this.onUnblockFriend,
    required this.onDeleteFriend,
    required this.openRowNotifier,
    required this.onGroupTap,
    required this.onCreateGroup,
    required this.onArchiveGroup,
    required this.onUnarchiveGroup,
    required this.onDeleteGroup,
    this.onRetryStuckRejoinGroup,
    this.onLeaveStuckGroup,
    this.viewMode = OrbitViewMode.allChats,
    this.onToggleView,
    this.activeTab,
    this.onSwitchView,
    this.feedUnreadCountListenable,
    this.onIntroBannerTap,
    this.onIntroDockTap,
    this.onIntroDockDismissed,
    this.onHeaderBuild,
    this.onListBuild,
    this.backgroundPreference = BackgroundPreference.defaultBackground,
    this.readableToneOverride,
    this.secureKeyStore,
    this.onInnerCircleEditSessionChanged,
    this.innerCircleResetListenable,
    this.onSelfAvatarTap,
    this.p2pService,
    this.hideShellNav = false,
  });

  @override
  State<OrbitScreen> createState() => _OrbitScreenState();
}

/// 205 item 6 — owns the transient "inner-circle is editing" flag so the view
/// toggle (Layer 1b) unmounts while the user sculpts the inner circle, then
/// re-mounts when the session ends (209: the QR chrome that shared this gate
/// retired to the Settings tiles). The flag is derived from the surface's own
/// edit-active signal, which is ALSO forwarded upward to the 198 feed↔orbit
/// swipe-yield gate (INV-7 preserved).
class _OrbitScreenState extends State<OrbitScreen> {
  bool _innerEditing = false;

  /// Nav-line find seat: poked by the nav-band rings find pill to open the
  /// surface's find bar, plus the open-flag the pill hides on. Both are owned
  /// here (not in the hosts) so the rings find session stays screen-internal.
  final _PokeNotifier _ringsFindSignal = _PokeNotifier();
  final ValueNotifier<bool> _ringsFindOpen = ValueNotifier<bool>(false);

  void _onInnerEdit(bool active) {
    if (_innerEditing != active) {
      setState(() => _innerEditing = active);
    }
    widget.onInnerCircleEditSessionChanged?.call(active);
  }

  void _onRingsFindOpenChanged(bool open) {
    _ringsFindOpen.value = open;
  }

  @override
  void didUpdateWidget(covariant OrbitScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Flipping the surface unmounts the rings find session with it — clear
    // the open-flag so the nav-band pill is back when the rings return.
    if (widget.viewMode != oldWidget.viewMode) {
      _ringsFindOpen.value = false;
    }
  }

  @override
  void dispose() {
    _ringsFindSignal.dispose();
    _ringsFindOpen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _OrbitScreenView(
        headerProjectionListenable: widget.headerProjectionListenable,
        listProjectionListenable: widget.listProjectionListenable,
        scrollController: widget.scrollController,
        searchController: widget.searchController,
        searchFocusNode: widget.searchFocusNode,
        collapseAnimation: widget.collapseAnimation,
        searchDockAnimation: widget.searchDockAnimation,
        searchTriggerAnimation: widget.searchTriggerAnimation,
        onClose: widget.onClose,
        onFriendTap: widget.onFriendTap,
        onFriendAvatarTap: widget.onFriendAvatarTap,
        onSearchOpen: widget.onSearchOpen,
        onSearchClose: widget.onSearchClose,
        onSearchChanged: widget.onSearchChanged,
        onSearchClear: widget.onSearchClear,
        onFilterChanged: widget.onFilterChanged,
        onArchiveFriend: widget.onArchiveFriend,
        onUnarchiveFriend: widget.onUnarchiveFriend,
        onBlockFriend: widget.onBlockFriend,
        onUnblockFriend: widget.onUnblockFriend,
        onDeleteFriend: widget.onDeleteFriend,
        openRowNotifier: widget.openRowNotifier,
        onGroupTap: widget.onGroupTap,
        onCreateGroup: widget.onCreateGroup,
        onArchiveGroup: widget.onArchiveGroup,
        onUnarchiveGroup: widget.onUnarchiveGroup,
        onDeleteGroup: widget.onDeleteGroup,
        onRetryStuckRejoinGroup: widget.onRetryStuckRejoinGroup,
        onLeaveStuckGroup: widget.onLeaveStuckGroup,
        viewMode: widget.viewMode,
        onToggleView: widget.onToggleView,
        activeTab: widget.activeTab,
        onSwitchView: widget.onSwitchView,
        feedUnreadCountListenable: widget.feedUnreadCountListenable,
        onIntroBannerTap: widget.onIntroBannerTap,
        onIntroDockTap: widget.onIntroDockTap,
        onIntroDockDismissed: widget.onIntroDockDismissed,
        onHeaderBuild: widget.onHeaderBuild,
        onListBuild: widget.onListBuild,
        backgroundPreference: widget.backgroundPreference,
        readableToneOverride: widget.readableToneOverride,
        secureKeyStore: widget.secureKeyStore,
        innerCircleResetListenable: widget.innerCircleResetListenable,
        onSelfAvatarTap: widget.onSelfAvatarTap,
        p2pService: widget.p2pService,
        innerEditing: _innerEditing,
        onInnerEdit: _onInnerEdit,
        ringsFindSignal: _ringsFindSignal,
        ringsFindOpenListenable: _ringsFindOpen,
        onRingsFindOpenChanged: _onRingsFindOpenChanged,
        hideShellNav: widget.hideShellNav,
      );
}

/// Pure UI layout for the Orbit screen (all state + callbacks supplied by
/// [OrbitScreen]/[OrbitWired]). Split out of [OrbitScreen] (205 item 6) so the
/// parent can hold the transient inner-circle edit flag and gate the toggle /
/// QR chrome on it.
class _OrbitScreenView extends StatelessWidget {
  final ValueListenable<OrbitHeaderProjection> headerProjectionListenable;
  final ValueListenable<OrbitViewProjection> listProjectionListenable;
  final ScrollController scrollController;
  final TextEditingController searchController;
  final FocusNode searchFocusNode;
  final Animation<double> collapseAnimation;
  final Animation<double> searchDockAnimation;
  final Animation<double> searchTriggerAnimation;
  final VoidCallback onClose;
  final void Function(OrbitFriend) onFriendTap;
  final void Function(OrbitFriend)? onFriendAvatarTap;
  final VoidCallback onSearchOpen;
  final VoidCallback onSearchClose;
  final void Function(String) onSearchChanged;
  final VoidCallback onSearchClear;
  final void Function(String) onFilterChanged;
  final void Function(OrbitFriend) onArchiveFriend;
  final void Function(OrbitFriend) onUnarchiveFriend;
  final void Function(OrbitFriend) onBlockFriend;
  final void Function(OrbitFriend) onUnblockFriend;
  final void Function(OrbitFriend) onDeleteFriend;
  final ValueNotifier<Key?> openRowNotifier;
  final void Function(OrbitGroup) onGroupTap;
  final void Function(GroupType) onCreateGroup;
  final void Function(OrbitGroup) onArchiveGroup;
  final void Function(OrbitGroup) onUnarchiveGroup;
  final void Function(OrbitGroup) onDeleteGroup;
  final void Function(OrbitGroup)? onRetryStuckRejoinGroup;
  final void Function(OrbitGroup)? onLeaveStuckGroup;
  final OrbitViewMode viewMode;
  final VoidCallback? onToggleView;
  final String? activeTab;
  final void Function(String)? onSwitchView;
  final ValueListenable<int>? feedUnreadCountListenable;
  final VoidCallback? onIntroBannerTap;
  final VoidCallback? onIntroDockTap;
  final VoidCallback? onIntroDockDismissed;
  final VoidCallback? onHeaderBuild;
  final VoidCallback? onListBuild;
  final BackgroundPreference backgroundPreference;
  final BackgroundReadableTone? readableToneOverride;
  final SecureKeyStore? secureKeyStore;
  final Listenable? innerCircleResetListenable;
  final VoidCallback? onSelfAvatarTap;

  /// 211 — connection-status pill source (see [OrbitScreen.p2pService]).
  final P2PService? p2pService;

  /// 205 item 6 — whether the inner-circle surface is mid edit-session (gates
  /// the toggle + QR chrome).
  /// Nav-line find seat plumbing (owned by [_OrbitScreenState]): the poke
  /// signal the nav-band pill fires, the open-flag the pill hides on, and the
  /// surface's find-session sink that flips that flag.
  final _PokeNotifier ringsFindSignal;
  final ValueListenable<bool> ringsFindOpenListenable;
  final ValueChanged<bool> onRingsFindOpenChanged;

  final bool innerEditing;

  /// 205 item 6 — the surface's edit-active signal sink (flips [innerEditing]
  /// AND forwards to the 198 swipe-yield gate).
  final void Function(bool) onInnerEdit;

  /// When true, suppress the center Feed/Orbit toggle bar in the persistent-nav
  /// band while keeping the band's other nav-line affordances (rings find pill /
  /// search trigger) and all `_showsPersistentNav` layout reservations intact.
  /// Option-3 "Orbit chromeless" landing: Feed stays reachable via the host
  /// swipe + its own toggle. Flip `hideShellNav: true` in
  /// `FeedWired._buildOrbitHost` back to false to revive the toggle here.
  final bool hideShellNav;

  const _OrbitScreenView({
    required this.headerProjectionListenable,
    required this.listProjectionListenable,
    required this.scrollController,
    required this.searchController,
    required this.searchFocusNode,
    required this.collapseAnimation,
    required this.searchDockAnimation,
    required this.searchTriggerAnimation,
    required this.onClose,
    required this.onFriendTap,
    required this.onFriendAvatarTap,
    required this.onSearchOpen,
    required this.onSearchClose,
    required this.onSearchChanged,
    required this.onSearchClear,
    required this.onFilterChanged,
    required this.onArchiveFriend,
    required this.onUnarchiveFriend,
    required this.onBlockFriend,
    required this.onUnblockFriend,
    required this.onDeleteFriend,
    required this.openRowNotifier,
    required this.onGroupTap,
    required this.onCreateGroup,
    required this.onArchiveGroup,
    required this.onUnarchiveGroup,
    required this.onDeleteGroup,
    required this.onRetryStuckRejoinGroup,
    required this.onLeaveStuckGroup,
    required this.viewMode,
    required this.onToggleView,
    required this.activeTab,
    required this.onSwitchView,
    required this.feedUnreadCountListenable,
    required this.onIntroBannerTap,
    required this.onIntroDockTap,
    required this.onIntroDockDismissed,
    required this.onHeaderBuild,
    required this.onListBuild,
    required this.backgroundPreference,
    required this.readableToneOverride,
    required this.secureKeyStore,
    required this.innerCircleResetListenable,
    this.onSelfAvatarTap,
    this.p2pService,
    required this.ringsFindSignal,
    required this.ringsFindOpenListenable,
    required this.onRingsFindOpenChanged,
    required this.innerEditing,
    required this.onInnerEdit,
    required this.hideShellNav,
  });

  bool get _showsPersistentNav => activeTab != null && onSwitchView != null;

  double _persistentNavBottomOffset(BuildContext context) {
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    return math.max(16.0, safeBottom - 14.0);
  }

  double _persistentNavReservedHeight(BuildContext context) {
    return _persistentNavBottomOffset(context) + 64;
  }

  double _searchDockBottomOffset(BuildContext context) {
    if (!_showsPersistentNav) {
      return 0;
    }
    return _persistentNavReservedHeight(context) + 8;
  }

  /// 201: the surface-relative bottom reservation the Inner-Circle find pill /
  /// chip strip / corner steppers must clear so they never sit under the
  /// persistent Feed/Orbit nav band. Zero when that nav isn't shown. Mirrors the
  /// search-dock offset minus the SafeArea inset the surface already carries
  /// (the surface is wrapped in SafeArea; the nav band is screen-anchored).
  double _innerCircleBottomClearance(BuildContext context) {
    if (!_showsPersistentNav) {
      return 0;
    }
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    return math.max(0.0, _searchDockBottomOffset(context) - safeBottom);
  }

  double _contentBottomSpacer(
    BuildContext context,
    OrbitViewProjection projection,
  ) {
    if (!_showsPersistentNav) {
      return projection.searchActive ? 320 : 100;
    }

    final reservedHeight = _persistentNavReservedHeight(context);
    return projection.searchActive ? reservedHeight + 220 : reservedHeight + 96;
  }

  Widget _buildNavigationBar() {
    final activeTab = this.activeTab;
    final onSwitchView = this.onSwitchView;
    if (activeTab == null || onSwitchView == null) {
      return const SizedBox.shrink();
    }

    final unreadCountListenable = feedUnreadCountListenable;
    return ValueListenableBuilder<OrbitViewProjection>(
      valueListenable: listProjectionListenable,
      builder: (context, projection, child) {
        if (unreadCountListenable == null) {
          return FeedNavigationBar(
            activeTab: activeTab,
            onSwitchView: onSwitchView,
            orbitBadgeCount: projection.unseenReviewCount,
          );
        }

        return ValueListenableBuilder<int>(
          valueListenable: unreadCountListenable,
          builder: (context, unreadCount, nestedChild) => FeedNavigationBar(
            activeTab: activeTab,
            onSwitchView: onSwitchView,
            feedBadgeCount: unreadCount,
            orbitBadgeCount: projection.unseenReviewCount,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AmbientBackground(
      preference: backgroundPreference,
      readableToneOverride: readableToneOverride,
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            // Layer 1: the active surface — the Inner-Circle visualization
            // (default on every entry) or the classic all-chats list, per
            // [viewMode]. The two surfaces are disjoint: no list affordance
            // leaks onto the circle, and no visualization header onto the list.
            SafeArea(
              child: viewMode == OrbitViewMode.innerCircle
                  ? _buildInnerCircleSurface(context)
                  : _buildAllChatsListSurface(context),
            ),

            // Layer 1b: top-left view toggle — present on BOTH surfaces so it
            // can flip the view either way. Only mounted when a toggle handler
            // is wired, so bare-OrbitScreen pumps are unaffected. Physical
            // top-left (RTL-safe) — see OrbitViewToggleButton.
            // 205 item 6: hidden while the inner-circle surface is editing, so
            // it never occludes the edit Reset chrome nor steals its taps.
            if (onToggleView != null && !innerEditing)
              OrbitViewToggleButton(
                viewMode: viewMode,
                onToggle: onToggleView!,
              ),

            // (209: Layer 1c — the twin My QR / Scan chrome pair — retired.
            // The entries live as labeled tiles on the Settings page, reached
            // via the 206 center self-avatar.)

            // Layer 2: Close button — standalone mode only. When the
            // persistent Feed/Orbit nav is shown, the Feed tab is the way back,
            // so the redundant X is omitted.
            if (!_showsPersistentNav)
              Positioned(
                bottom: 36,
                right: 16,
                child: OrbitCloseButton(onTap: onClose),
              ),

            // Layer 3: Search trigger — standalone mode floats above the close
            // button. In persistent mode the trigger rides the nav line
            // instead, inside the nav band layer below. Search is an all-chats
            // affordance — never shown on the Inner-Circle surface.
            if (!_showsPersistentNav && viewMode == OrbitViewMode.allChats)
              AnimatedBuilder(
                animation: searchTriggerAnimation,
                builder: (context, child) {
                  final t = searchTriggerAnimation.value;
                  return Positioned(
                    bottom: 88,
                    right: 16,
                    child: Opacity(
                      opacity: t,
                      child: Transform.scale(
                        scale: 0.985 + 0.015 * t,
                        child: Transform.translate(
                          offset: Offset(0, (1 - t) * 14),
                          child: IgnorePointer(ignoring: t < 0.5, child: child),
                        ),
                      ),
                    ),
                  );
                },
                child: OrbitSearchTrigger(onSearchTap: onSearchOpen),
              ),

            // Layer 4: Search dock (slides up from bottom) — all-chats only
            // (search is a list affordance; the Inner-Circle surface never
            // mounts the dock, so its TextField cannot linger over the circle).
            if (viewMode == OrbitViewMode.allChats)
              AnimatedBuilder(
                animation: searchDockAnimation,
              builder: (context, child) {
                final t = searchDockAnimation.value;
                return Positioned(
                  bottom: _searchDockBottomOffset(context),
                  left: 0,
                  right: 0,
                  child: Transform.translate(
                    offset: Offset(0, (1 - t) * 300),
                    child: IgnorePointer(ignoring: t < 0.1, child: child),
                  ),
                );
              },
              child: ValueListenableBuilder<OrbitViewProjection>(
                valueListenable: listProjectionListenable,
                builder: (context, projection, child) => OrbitSearchDock(
                  controller: searchController,
                  focusNode: searchFocusNode,
                  onChanged: onSearchChanged,
                  onClear: onSearchClear,
                  onClose: onSearchClose,
                  query: projection.searchQuery,
                ),
              ),
            ),

            if (_showsPersistentNav)
              Positioned(
                left: 0,
                right: 0,
                bottom: _persistentNavBottomOffset(context),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      // Center keeps the Feed/Orbit bar horizontally centered
                      // without flex balancing, independent of the trigger.
                      // hideShellNav suppresses ONLY this toggle (Orbit
                      // chromeless landing). We keep it in the layout via
                      // Visibility(maintainSize) — invisible + non-interactive
                      // but still occupying the bar's box — so this Stack keeps
                      // the bar's height and the nav-line search trigger / rings
                      // find pill stay on their line. A bare SizedBox.shrink
                      // collapses the Stack to ~0 height, dropping the trigger
                      // to the band's bottom anchor where the screen edge clips
                      // it (the reported search-icon bug).
                      Center(
                        child: Visibility(
                          visible: !hideShellNav,
                          maintainSize: true,
                          maintainAnimation: true,
                          maintainState: true,
                          child: _buildNavigationBar(),
                        ),
                      ),

                      // Search trigger — rides the nav line at the physical
                      // right edge (Positioned, not directional → RTL-safe),
                      // vertically centered on the bar via the Stack
                      // alignment. All-chats only. Keeps the persistent
                      // transform set (opacity + scale, no translate) and the
                      // STRUCTURAL t<0.5 tap-inertness (IgnorePointer, per the
                      // 212 TC-212-06 trap). This layer sits after the Layer 4
                      // dock, so the fading trigger paints over the rising
                      // dock mid-transit; the settled dock rests above the
                      // nav band, clear of the trigger.
                      if (viewMode == OrbitViewMode.allChats)
                        Positioned(
                          right: 0,
                          child: AnimatedBuilder(
                            animation: searchTriggerAnimation,
                            builder: (context, child) {
                              final t = searchTriggerAnimation.value;
                              return Opacity(
                                opacity: t,
                                child: Transform.scale(
                                  scale: 0.985 + 0.015 * t,
                                  child: IgnorePointer(
                                    ignoring: t < 0.5,
                                    child: child,
                                  ),
                                ),
                              );
                            },
                            child: OrbitSearchTrigger(onSearchTap: onSearchOpen),
                          ),
                        ),

                      // Rings find pill — the Inner-Circle collapsed find
                      // affordance re-seated on the SAME nav-line slot, so
                      // both surfaces keep one bottom-right search home. The
                      // surface still owns the find session; this pill pokes
                      // it open and hides while the expanded bar is up (the
                      // bar carries its own close X).
                      if (viewMode == OrbitViewMode.innerCircle)
                        Positioned(
                          right: 0,
                          child: ValueListenableBuilder<bool>(
                            valueListenable: ringsFindOpenListenable,
                            builder: (context, findOpen, child) =>
                                findOpen ? const SizedBox.shrink() : child!,
                            child: _RingsFindPill(onTap: ringsFindSignal.poke),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

            // Layer 4c: intro dock (207) — top-row review entry for the
            // Inner-Circle view, seated immediately to the right of the
            // physical-left view toggle. Raw reviewCount gates the slot so a
            // dismissed backlog leaves the calm remnant; unseenReviewCount
            // selects dock vs remnant. Mounted before the FAB so the open-menu
            // scrim covers it.
            if (viewMode == OrbitViewMode.innerCircle && !innerEditing)
              ValueListenableBuilder<OrbitViewProjection>(
                valueListenable: listProjectionListenable,
                builder: (context, projection, child) {
                  if (projection.reviewCount == 0) {
                    return const SizedBox.shrink();
                  }

                  final textScale =
                      MediaQuery.textScalerOf(context).scale(14) / 14;
                  return Positioned(
                    key: const ValueKey('orbit-intro-dock-slot'),
                    top: MediaQuery.of(context).padding.top + 8,
                    left: 64,
                    right: _kIntroDockRightReserve * textScale,
                    height: 40,
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: OrbitIntroDock(
                        foldedReviewItems:
                            projection.introsData?.foldedReviewItems ??
                                const [],
                        pendingGroupInviteCount:
                            projection.pendingGroupInviteCount,
                        unseenCount: projection.unseenReviewCount,
                        dismissed: projection.unseenReviewCount == 0,
                        onTap: onIntroDockTap ?? () {},
                        onDismissed: onIntroDockDismissed ?? () {},
                      ),
                    ),
                  );
                },
              ),

            // Layer 4b: connection-status pill (211) — migrated from the Feed
            // header. Physical right (RTL-safe, same rationale as the toggle);
            // right = 16 (FAB inset) + 40 (FAB) + 8 gap. height:40 + Center
            // keeps the pill vertically aligned with the FAB at any text
            // scale. Hidden during sculpt-edit because the edit banner spans
            // the full top width. Mounted BEFORE the FAB so the open-menu
            // scrim covers it (196/209 precedence convention) — the FAB must
            // stay the LAST Stack child (trailing-scan element matching keeps
            // its State alive across viewMode/innerEditing flips).
            if (p2pService != null && !innerEditing)
              Positioned(
                key: const ValueKey('orbit-connection-indicator'),
                top: MediaQuery.of(context).padding.top + 8,
                right: 64,
                height: 40,
                child: Center(
                  child: ConnectionStatusIndicator(p2pService: p2pService!),
                ),
              ),

            // Layer 5: ExpandableFab (create group)
            ExpandableFab(
              anchor: ExpandableFabAnchor.topRight,
              fabSize: 40,
              safeAreaPadding: MediaQuery.of(context).padding,
              items: [
                ExpandableFabItem(
                  label: AppLocalizations.of(context)!.orbit_new_group,
                  icon: Icons.group_outlined,
                  onTap: () => onCreateGroup(GroupType.chat),
                ),
                ExpandableFabItem(
                  label: AppLocalizations.of(context)!.orbit_new_announce,
                  icon: Icons.campaign_outlined,
                  onTap: () => onCreateGroup(GroupType.announcement),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Inner-Circle surface (default view): the orbital visualization + caption,
  /// centered, with a zero-contacts hint when there are no friends yet. NO
  /// list-coupled affordances. The collapse animation is inert here (search
  /// cannot open on this surface), so the header renders fully expanded.
  Widget _buildInnerCircleSurface(BuildContext context) {
    return ValueListenableBuilder<OrbitHeaderProjection>(
      valueListenable: headerProjectionListenable,
      builder: (context, projection, child) {
        onHeaderBuild?.call();
        // 197: the rings render the merged friends+groups ring set (blocked
        // friends already dropped, archived groups already excluded upstream).
        // 198: the interactive surface owns the sculpt/find/labels/expansion
        // session state + persistence; the caption + empty hint live inside it.
        return InnerCircleInteractiveSurface(
          userPeerId: projection.userPeerId,
          userAvatarBytes: projection.userAvatarBytes,
          items: projection.innerItems,
          onFriendTap: onFriendTap,
          onGroupTap: onGroupTap,
          secureKeyStore: secureKeyStore,
          onEditSessionActiveChanged: onInnerEdit,
          resetSignal: innerCircleResetListenable,
          // Persistent mode re-seats the collapsed find pill on the nav line
          // (host chrome, see the nav band Stack); the surface then only
          // renders the expanded bar. Standalone keeps the in-surface pill.
          findOpenSignal: _showsPersistentNav ? ringsFindSignal : null,
          onFindSessionActiveChanged: onRingsFindOpenChanged,
          onSelfAvatarTap: onSelfAvatarTap,
          bottomClearance: _innerCircleBottomClearance(context),
        );
      },
    );
  }

  /// All-chats surface (alternative view): the classic friends/groups list with
  /// its QR header, filter tabs, intro banner, and search. NO visualization
  /// header. This is the pre-193 list, unchanged, minus the collapsible header.
  Widget _buildAllChatsListSurface(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ValueListenableBuilder<OrbitViewProjection>(
            valueListenable: listProjectionListenable,
            builder: (context, projection, child) {
              onListBuild?.call();
              return CustomScrollView(
                controller: scrollController,
                physics: const BouncingScrollPhysics(),
                cacheExtent: 600,
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      // The first sliver clears the top chrome strip (the
                      // top-left toggle at safeTop+8) VERTICALLY — top padding
                      // 56 (209: the QR pair retired to Settings; the toggle
                      // still occupies the strip, so the clearance stays).
                      padding: const EdgeInsets.fromLTRB(16, 56, 16, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 203 B5: the title-only FriendsListHeader was
                          // removed with its 'Close Friends' string — the
                          // filter toggle is the list's first content.
                          if (!projection.searchActive) ...[
                            const SizedBox(height: 8),
                            FriendsFilterToggle(
                              activeFilter: projection.filterTab,
                              activeCount: projection.activeCount,
                              archivedCount: projection.archivedCount,
                              introsCount: projection.reviewCount,
                              onFilterChanged: onFilterChanged,
                            ),
                          ],
                          const SizedBox(height: 8),
                          if (projection.reviewCount > 0 &&
                              projection.filterTab != 'intros')
                            _buildIntroBanner(context, projection),
                        ],
                      ),
                    ),
                  ),
                  _buildContentSliver(context, projection),
                  SliverToBoxAdapter(
                    child: SizedBox(
                      height: _contentBottomSpacer(context, projection),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildIntroBanner(
    BuildContext context,
    OrbitViewProjection projection,
  ) {
    final readableColors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;
    const accentColor = Color(0xFF157A39);

    return GestureDetector(
      onTap: onIntroBannerTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: readableColors.isLightSurface
              ? const Color(0xFFE5F4EA)
              : const Color(0x141DB954),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: readableColors.isLightSurface
                ? const Color(0xFF78B58D)
                : const Color(0x331DB954),
          ),
        ),
        child: Row(
          children: [
            const Icon(Icons.people_outline, size: 18, color: accentColor),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.orbit_pending_items(projection.reviewCount),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: readableColors.textPrimary,
                    ),
                  ),
                  Text(
                    _buildIntroBannerSubtitle(projection, l10n),
                    style: TextStyle(
                      fontSize: 11,
                      color: readableColors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: readableColors.iconMuted,
            ),
          ],
        ),
      ),
    );
  }

  String _buildIntroBannerSubtitle(
    OrbitViewProjection projection,
    AppLocalizations l10n,
  ) {
    final inviteCount = projection.pendingGroupInviteCount;
    final introCount = projection.introCount;
    if (inviteCount > 0 && introCount > 0) {
      return l10n.orbit_intro_banner_mixed(inviteCount, introCount);
    }
    if (inviteCount > 0) {
      return l10n.orbit_intro_banner_invites(inviteCount);
    }
    return l10n.orbit_intro_banner_intros;
  }

  Widget _buildContentSliver(
    BuildContext context,
    OrbitViewProjection projection,
  ) {
    if (projection.filterTab == 'intros') {
      if (projection.introsData != null) {
        return _buildIntroSliver(projection.introsData!);
      }
    }

    if (projection.filterTab != 'intros' &&
        projection.showLoadingPlaceholders &&
        projection.mergedItems.isEmpty) {
      return _buildLoadingSliver();
    }

    if (projection.searchActive &&
        projection.searchQuery.isNotEmpty &&
        projection.displayedFriends.isEmpty) {
      return SliverToBoxAdapter(
        child: _buildNoResults(context, projection.searchQuery),
      );
    }

    if (projection.filterTab == 'archived' &&
        projection.displayedFriends.isEmpty &&
        projection.groups.isEmpty &&
        !projection.searchActive) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: ArchivedEmptyState(),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final item = projection.mergedItems[index];
          return switch (item) {
            OrbitFriendItem(:final friend) => _buildFriendRow(
              friend,
              index,
              projection,
            ),
            OrbitGroupItem(:final group) => _buildGroupRow(group, index),
          };
        }, childCount: projection.mergedItems.length),
      ),
    );
  }

  Widget _buildLoadingSliver() {
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildListDelegate.fixed([
          const _OrbitLoadingRow(index: 0),
          const SizedBox(height: 8),
          const _OrbitLoadingRow(index: 1),
          const SizedBox(height: 8),
          const _OrbitLoadingRow(index: 2),
        ]),
      ),
    );
  }

  Widget _buildIntroSliver(OrbitIntrosViewData data) {
    final introEntries = _buildIntroEntries(data);
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) =>
              _buildIntroEntry(context, data, introEntries[index]),
          childCount: introEntries.length,
        ),
      ),
    );
  }

  List<_OrbitIntroEntry> _buildIntroEntries(OrbitIntrosViewData data) {
    if (data.introCount == 0 && !data.hasInviteRows) {
      return const [_OrbitIntroEntry.context()];
    }

    final entries = <_OrbitIntroEntry>[const _OrbitIntroEntry.context()];
    if (data.hasInviteRows) {
      entries.add(const _OrbitIntroEntry.pendingInviteHeader());
      entries.addAll(
        data.pendingGroupInvites.map(_OrbitIntroEntry.pendingInvite),
      );
      final pendingIds = data.pendingGroupInvites
          .map((invite) => invite.groupId)
          .toSet();
      entries.addAll(
        data.inviteRowOutcomes.entries
            .where((entry) => !pendingIds.contains(entry.key))
            .map(
              (entry) =>
                  _OrbitIntroEntry.pendingInviteOutcome(entry.key, entry.value),
            ),
      );
    }

    final foldedItems = data.foldedReviewItems;
    if (foldedItems != null) {
      if (foldedItems.isNotEmpty) {
        if (data.hasInviteRows) {
          entries.add(const _OrbitIntroEntry.spacer());
        }
        entries.addAll(foldedItems.map(_OrbitIntroEntry.foldedRow));
      }
      return entries;
    }

    final introducerIds = data.groupedIntros.keys.toList();
    for (var groupIndex = 0; groupIndex < introducerIds.length; groupIndex++) {
      final introducerId = introducerIds[groupIndex];
      final intros = data.groupedIntros[introducerId]!;
      final introducerName =
          data.introducerUsernames[introducerId] ?? 'Unknown';

      if (groupIndex > 0 || data.hasInviteRows) {
        entries.add(const _OrbitIntroEntry.spacer());
      }
      entries.add(_OrbitIntroEntry.header(introducerName));
      entries.addAll(intros.map(_OrbitIntroEntry.row));
    }
    return entries;
  }

  IntroductionStatus _ownPartyStatusForFolded(
    FoldedIntroductionReviewItem item,
  ) {
    if (item.passedCurrentViewerDecisionIntroIds.isNotEmpty) {
      return IntroductionStatus.passed;
    }
    if (item.acceptedCurrentViewerDecisionIntroIds.isNotEmpty) {
      return IntroductionStatus.accepted;
    }
    return IntroductionStatus.pending;
  }

  bool _showActionsForFolded(FoldedIntroductionReviewItem item) {
    return item.hasPendingCurrentViewerDecision &&
        !item.hasCurrentViewerResponded;
  }

  Widget _buildIntroEntry(
    BuildContext context,
    OrbitIntrosViewData data,
    _OrbitIntroEntry entry,
  ) {
    final readableColors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;

    switch (entry.type) {
      case _OrbitIntroEntryType.context:
        if (data.introCount == 0 && !data.hasInviteRows) {
          return Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text(
                l10n.intro_empty,
                style: TextStyle(fontSize: 14, color: readableColors.textMuted),
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            data.hasInviteRows
                ? l10n.orbit_pending_group_intro_desc
                : l10n.intro_tab_desc,
            style: TextStyle(fontSize: 13, color: readableColors.textMuted),
            textAlign: TextAlign.center,
          ),
        );
      case _OrbitIntroEntryType.pendingInviteHeader:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            l10n.orbit_pending_group_invites,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: readableColors.textSecondary,
              letterSpacing: 0.8,
            ),
          ),
        );
      case _OrbitIntroEntryType.pendingInvite:
        final invite = entry.pendingInvite!;
        final outcome = data.inviteRowOutcomes[invite.groupId];
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: PendingGroupInviteCard(
            invite: invite,
            isProcessing: data.processingPendingInviteIds.contains(
              invite.groupId,
            ),
            rowState: outcome?.state ?? PendingInviteRowState.idle,
            rowReason: outcome?.reason,
            onAccept: data.onAcceptPendingInvite != null
                ? () => data.onAcceptPendingInvite!(invite)
                : null,
            onDecline: data.onDeclinePendingInvite != null
                ? () => data.onDeclinePendingInvite!(invite)
                : null,
            onRetry: data.onRetryPendingInvite != null
                ? () => data.onRetryPendingInvite!(invite)
                : null,
            onAskForNewInvite:
                data.onAskForNewInvite != null &&
                    data.askNewInviteIds.contains(invite.groupId)
                ? () => data.onAskForNewInvite!(invite.groupId)
                : null,
            inviteContactUnavailable: data.unavailableInviteContactIds.contains(
              invite.groupId,
            ),
          ),
        );
      case _OrbitIntroEntryType.pendingInviteOutcome:
        final inviteId = entry.pendingInviteOutcomeId!;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: PendingInviteOutcomeRow(
            inviteId: inviteId,
            outcome: entry.pendingInviteOutcome!,
            onAskForNewInvite:
                data.onAskForNewInvite != null &&
                    data.askNewInviteIds.contains(inviteId)
                ? () => data.onAskForNewInvite!(inviteId)
                : null,
            inviteContactUnavailable: data.unavailableInviteContactIds.contains(
              inviteId,
            ),
          ),
        );
      case _OrbitIntroEntryType.introHeader:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IntroGroupHeader(introducerUsername: entry.introducerUsername!),
            const SizedBox(height: 8),
          ],
        );
      case _OrbitIntroEntryType.introRow:
        final intro = entry.introduction!;
        final amRecipient = intro.recipientId == data.ownPeerId;
        final displayUsername = amRecipient
            ? (intro.introducedUsername ?? 'Unknown')
            : (intro.recipientUsername ?? 'Unknown');
        final displayPeerId = amRecipient
            ? intro.introducedId
            : intro.recipientId;
        final ownPartyStatus = amRecipient
            ? intro.recipientStatus
            : intro.introducedStatus;
        final waitingForUsername = amRecipient
            ? (intro.introducedUsername ?? 'Unknown')
            : (intro.recipientUsername ?? 'Unknown');
        final showActions =
            ownPartyStatus == IntroductionStatus.pending &&
            intro.status == IntroductionOverallStatus.pending;
        final isOtherBlocked = data.blockedPeerIds.contains(displayPeerId);
        final introRow = IntroRow(
          introduction: intro,
          displayUsername: displayUsername,
          displayPeerId: displayPeerId,
          showActions: showActions,
          isProcessing: data.processingIntroductionIds.contains(intro.id),
          onAccept: showActions ? () => data.onAccept(intro.id) : null,
          onPass: showActions ? () => data.onPass(intro.id) : null,
          ownPartyStatus: ownPartyStatus,
          waitingForUsername: waitingForUsername,
          onSendMessage:
              intro.status == IntroductionOverallStatus.mutualAccepted &&
                  data.onSendMessage != null
              ? () => data.onSendMessage!(displayPeerId)
              : null,
          isOtherBlocked: isOtherBlocked,
        );

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: data.onDelete == null
              ? introRow
              : SwipeableFriendRow(
                  key: ValueKey('orbit-intro-${intro.id}'),
                  isArchived: false,
                  openRowNotifier: openRowNotifier,
                  onDelete: () => data.onDelete!(intro.id),
                  child: introRow,
                ),
        );
      case _OrbitIntroEntryType.foldedIntroRow:
        final item = entry.foldedIntroduction!;
        final intro = item.newestIntroduction;
        final ownPartyStatus = _ownPartyStatusForFolded(item);
        final showActions = _showActionsForFolded(item);
        final isProcessing = item.introductionIds.any(
          (id) => data.processingIntroductionIds.contains(id),
        );
        final introRow = IntroRow(
          introduction: intro,
          displayUsername: item.targetDisplayName,
          displayPeerId: item.targetPeerId,
          introducerAttributionNames: item.introducerAttributions
              .map((attribution) => attribution.displayName)
              .toList(growable: false),
          showActions: showActions,
          isProcessing: isProcessing,
          onAccept: showActions
              ? () => data.onAccept(item.displaySourceIntroductionId)
              : null,
          onPass: showActions
              ? () => data.onPass(item.displaySourceIntroductionId)
              : null,
          ownPartyStatus: ownPartyStatus,
          waitingForUsername: item.targetDisplayName,
          onSendMessage:
              intro.status == IntroductionOverallStatus.mutualAccepted &&
                  data.onSendMessage != null
              ? () => data.onSendMessage!(item.targetPeerId)
              : null,
          isOtherBlocked: data.blockedPeerIds.contains(item.targetPeerId),
        );

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: data.onDelete == null
              ? introRow
              : SwipeableFriendRow(
                  key: ValueKey(
                    'orbit-intro-${item.displaySourceIntroductionId}',
                  ),
                  isArchived: false,
                  openRowNotifier: openRowNotifier,
                  onDelete: () =>
                      data.onDelete!(item.displaySourceIntroductionId),
                  child: introRow,
                ),
        );
      case _OrbitIntroEntryType.spacer:
        return const SizedBox(height: 16);
    }
  }

  Widget _buildFriendRow(
    OrbitFriend friend,
    int index,
    OrbitViewProjection projection,
  ) {
    final isInnerCircle = projection.allFriends.indexOf(friend) < 13;
    final isArchived = friend.isArchived;
    final rowKey = ValueKey(friend.peerId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AnimatedFriendRow(
        index: index,
        child: SwipeableFriendRow(
          key: rowKey,
          isArchived: isArchived,
          isBlocked: friend.isBlocked,
          openRowNotifier: openRowNotifier,
          onArchive: () => onArchiveFriend(friend),
          onUnarchive: () => onUnarchiveFriend(friend),
          onBlock: () => onBlockFriend(friend),
          onUnblock: () => onUnblockFriend(friend),
          onDelete: () => onDeleteFriend(friend),
          child: FriendRow(
            friend: friend,
            showInnerCircleBadge: projection.searchActive && isInnerCircle,
            hideUnreadBadge: isArchived,
            onTap: () => onFriendTap(friend),
            onAvatarTap: onFriendAvatarTap == null
                ? null
                : () => onFriendAvatarTap!(friend),
          ),
        ),
      ),
    );
  }

  Widget _buildGroupRow(OrbitGroup group, int index) {
    final isArchived = group.group.isArchived;
    final rowKey = ValueKey(group.group.id);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: AnimatedFriendRow(
        index: index,
        child: SwipeableFriendRow(
          key: rowKey,
          isArchived: isArchived,
          isBlocked: false,
          openRowNotifier: openRowNotifier,
          onArchive: () => onArchiveGroup(group),
          onUnarchive: () => onUnarchiveGroup(group),
          onDelete: () => onDeleteGroup(group),
          child: GroupRow(
            group: group,
            onTap: () => onGroupTap(group),
            onRetryStuckRejoin: onRetryStuckRejoinGroup == null
                ? null
                : () => onRetryStuckRejoinGroup!(group),
            onLeaveStuckGroup: onLeaveStuckGroup == null
                ? null
                : () => onLeaveStuckGroup!(group),
          ),
        ),
      ),
    );
  }

  Widget _buildNoResults(BuildContext context, String searchQuery) {
    final readableColors = context.backgroundReadableColors;
    final l10n = AppLocalizations.of(context)!;

    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Center(
        child: Column(
          children: [
            // 205 item 3: bright no-results lens over the near-black surface.
            Icon(Icons.search, size: 40, color: readableColors.iconPrimary),
            const SizedBox(height: 16),
            Text(
              l10n.orbit_no_friends_matching(searchQuery),
              style: TextStyle(fontSize: 15, color: readableColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}

class _OrbitLoadingRow extends StatelessWidget {
  final int index;

  const _OrbitLoadingRow({required this.index});

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return Container(
      key: ValueKey('orbit-loading-row-$index'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: readableColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: readableColors.border),
      ),
      child: Row(
        children: const [
          _OrbitLoadingAvatar(),
          SizedBox(width: 14),
          Expanded(child: _OrbitLoadingTextBlock()),
          SizedBox(width: 16),
          _OrbitLoadingChevron(),
        ],
      ),
    );
  }
}

class _OrbitLoadingAvatar extends StatelessWidget {
  const _OrbitLoadingAvatar();

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: readableColors.disabledSurface,
        borderRadius: BorderRadius.circular(14),
      ),
    );
  }
}

class _OrbitLoadingTextBlock extends StatelessWidget {
  const _OrbitLoadingTextBlock();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _OrbitLoadingBar(widthFactor: 0.44, height: 14),
        SizedBox(height: 8),
        _OrbitLoadingBar(widthFactor: 0.62),
        SizedBox(height: 8),
        _OrbitLoadingBar(widthFactor: 0.34, height: 10),
      ],
    );
  }
}

class _OrbitLoadingChevron extends StatelessWidget {
  const _OrbitLoadingChevron();

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: readableColors.disabledSurface,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}

class _OrbitLoadingBar extends StatelessWidget {
  final double widthFactor;
  final double height;

  const _OrbitLoadingBar({required this.widthFactor, this.height = 12});

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;

    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: readableColors.disabledSurface,
          borderRadius: BorderRadius.circular(height / 2),
        ),
      ),
    );
  }
}

/// Minimal poke-style [Listenable] for the nav-band rings find pill →
/// [InnerCircleInteractiveSurface.findOpenSignal] seam (same shape as the
/// host-side reset signal).
class _PokeNotifier extends ChangeNotifier {
  void poke() => notifyListeners();
}

/// The Inner-Circle collapsed find pill, re-seated as nav-band chrome. Visual
/// twin of the in-surface pill it replaces in persistent mode (52px glass
/// circle, border + shadow, NO BackdropFilter — INV-212-3: a permanent blur
/// over the continuously-animating rings would re-sample per frame) and of
/// [OrbitSearchTrigger] on the all-chats surface. Deliberately its own type:
/// find-in-circle is not list search, and the "no OrbitSearchTrigger on
/// rings" test locks stay meaningful.
class _RingsFindPill extends StatelessWidget {
  final VoidCallback onTap;

  const _RingsFindPill({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.backgroundReadableColors;
    return Semantics(
      container: true,
      button: true,
      label: AppLocalizations.of(context)!.orbit_find_pill_semantics,
      child: GestureDetector(
        key: const ValueKey('orbit-find-pill'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: colors.glassSurface,
            shape: BoxShape.circle,
            border: Border.all(color: colors.glassBorder),
            boxShadow: const [
              BoxShadow(
                color: Color(0x59000000),
                blurRadius: 18,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: Icon(Icons.search, size: 24, color: colors.iconPrimary),
        ),
      ),
    );
  }
}
