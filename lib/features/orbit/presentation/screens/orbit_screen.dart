import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_navigation_bar.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/groups/domain/models/pending_group_invite.dart';
import 'package:flutter_app/features/groups/presentation/widgets/pending_group_invite_card.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/presentation/widgets/intro_group_header.dart';
import 'package:flutter_app/features/introduction/presentation/widgets/intro_row.dart';
import 'package:flutter_app/features/groups/presentation/widgets/expandable_fab.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_friend.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_group.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_item.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_close_button.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbital_visualization.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/friends_list_header.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/friend_row.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/group_row.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_search_trigger.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_search_dock.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/friends_filter_toggle.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/swipeable_friend_row.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/archived_empty_state.dart';

@immutable
class OrbitIntrosViewData {
  final Map<String, List<IntroductionModel>> groupedIntros;
  final Map<String, String> introducerUsernames;
  final String ownPeerId;
  final List<PendingGroupInvite> pendingGroupInvites;
  final Set<String> processingPendingInviteIds;
  final void Function(String introductionId) onAccept;
  final void Function(String introductionId) onPass;
  final void Function(String introductionId)? onDelete;
  final void Function(String peerId)? onSendMessage;
  final void Function(PendingGroupInvite invite)? onAcceptPendingInvite;
  final void Function(PendingGroupInvite invite)? onDeclinePendingInvite;
  final Set<String> blockedPeerIds;

  const OrbitIntrosViewData({
    required this.groupedIntros,
    required this.introducerUsernames,
    required this.ownPeerId,
    this.pendingGroupInvites = const [],
    this.processingPendingInviteIds = const {},
    required this.onAccept,
    required this.onPass,
    this.onDelete,
    this.onSendMessage,
    this.onAcceptPendingInvite,
    this.onDeclinePendingInvite,
    this.blockedPeerIds = const {},
  });

  int get introCount =>
      groupedIntros.values.fold(0, (sum, entries) => sum + entries.length);

  int get reviewCount => introCount + pendingGroupInvites.length;
}

@immutable
class OrbitHeaderProjection {
  final String? userPeerId;
  final Uint8List? userAvatarBytes;
  final List<OrbitFriend> allFriends;

  const OrbitHeaderProjection({
    this.userPeerId,
    this.userAvatarBytes,
    this.allFriends = const [],
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
  introHeader,
  introRow,
  spacer,
}

class _OrbitIntroEntry {
  final _OrbitIntroEntryType type;
  final String? introducerUsername;
  final IntroductionModel? introduction;
  final PendingGroupInvite? pendingInvite;

  const _OrbitIntroEntry._(
    this.type, {
    this.introducerUsername,
    this.introduction,
    this.pendingInvite,
  });

  const _OrbitIntroEntry.context() : this._(_OrbitIntroEntryType.context);

  const _OrbitIntroEntry.header(String introducerUsername)
    : this._(
        _OrbitIntroEntryType.introHeader,
        introducerUsername: introducerUsername,
      );

  const _OrbitIntroEntry.row(IntroductionModel introduction)
    : this._(_OrbitIntroEntryType.introRow, introduction: introduction);

  const _OrbitIntroEntry.pendingInviteHeader()
    : this._(_OrbitIntroEntryType.pendingInviteHeader);

  const _OrbitIntroEntry.pendingInvite(PendingGroupInvite invite)
    : this._(_OrbitIntroEntryType.pendingInvite, pendingInvite: invite);

  const _OrbitIntroEntry.spacer() : this._(_OrbitIntroEntryType.spacer);
}

/// Pure UI layout for the Orbit screen.
///
/// Receives all state and callbacks from OrbitWired.
class OrbitScreen extends StatelessWidget {
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
  final VoidCallback onMyQR;
  final VoidCallback onScanQR;
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
  final String? activeTab;
  final void Function(String)? onSwitchView;
  final ValueListenable<int>? feedUnreadCountListenable;
  final VoidCallback? onIntroBannerTap;
  final VoidCallback? onHeaderBuild;
  final VoidCallback? onListBuild;

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
    required this.onMyQR,
    required this.onScanQR,
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
    this.activeTab,
    this.onSwitchView,
    this.feedUnreadCountListenable,
    this.onIntroBannerTap,
    this.onHeaderBuild,
    this.onListBuild,
  });

  bool get _showsPersistentNav => activeTab != null && onSwitchView != null;

  double _persistentNavBottomOffset(BuildContext context) {
    final safeBottom = MediaQuery.viewPaddingOf(context).bottom;
    return math.max(16.0, safeBottom - 14.0);
  }

  double _persistentNavReservedHeight(BuildContext context) {
    return _persistentNavBottomOffset(context) + 64;
  }

  double _closeButtonBottomOffset(
    BuildContext context, {
    required bool searchActive,
  }) {
    if (!_showsPersistentNav) {
      return 36;
    }

    final reservedHeight = _persistentNavReservedHeight(context);
    return searchActive ? reservedHeight + 112 : reservedHeight + 12;
  }

  double _searchTriggerBottomOffset(BuildContext context) {
    if (!_showsPersistentNav) {
      return 88;
    }
    return _persistentNavReservedHeight(context) + 64;
  }

  double _searchDockBottomOffset(BuildContext context) {
    if (!_showsPersistentNav) {
      return 0;
    }
    return _persistentNavReservedHeight(context) + 8;
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
            orbitBadgeCount: projection.reviewCount,
          );
        }

        return ValueListenableBuilder<int>(
          valueListenable: unreadCountListenable,
          builder: (context, unreadCount, nestedChild) => FeedNavigationBar(
            activeTab: activeTab,
            onSwitchView: onSwitchView,
            feedBadgeCount: unreadCount,
            orbitBadgeCount: projection.reviewCount,
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return AmbientBackground(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            // Layer 1: Scrollable content
            SafeArea(
              child: Column(
                children: [
                  // Collapsible header + orbital
                  ValueListenableBuilder<OrbitHeaderProjection>(
                    valueListenable: headerProjectionListenable,
                    builder: (context, projection, child) {
                      onHeaderBuild?.call();
                      return AnimatedBuilder(
                        animation: collapseAnimation,
                        builder: (context, animatedChild) {
                          final t = collapseAnimation.value;
                          return Align(
                            heightFactor: t,
                            child: Opacity(
                              opacity: t.clamp(0.0, 1.0),
                              child: Transform.translate(
                                offset: Offset(0, (1 - t) * -16),
                                child: Transform.scale(
                                  scale: 0.985 + 0.015 * t,
                                  alignment: Alignment.topCenter,
                                  child: animatedChild,
                                ),
                              ),
                            ),
                          );
                        },
                        child: Column(
                          children: [
                            OrbitalVisualization(
                              userPeerId: projection.userPeerId,
                              userAvatarBytes: projection.userAvatarBytes,
                              friends: projection.allFriends
                                  .where((friend) => !friend.isBlocked)
                                  .toList(),
                            ),
                            Padding(
                              padding: const EdgeInsets.only(top: 20),
                              child: Text(
                                AppLocalizations.of(
                                  context,
                                )!.orbit_close_friends,
                                style: const TextStyle(
                                  fontSize: 14,
                                  color: Color(0x99FFFFFF),
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),

                  // Scrollable friends list
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
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  8,
                                  16,
                                  0,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    FriendsListHeader(
                                      onMyQR: onMyQR,
                                      onScanQR: onScanQR,
                                      searchActive: projection.searchActive,
                                    ),
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
                                      _buildIntroBanner(projection),
                                  ],
                                ),
                              ),
                            ),
                            _buildContentSliver(projection),
                            SliverToBoxAdapter(
                              child: SizedBox(
                                height: _contentBottomSpacer(
                                  context,
                                  projection,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),

            // Layer 2: Close button
            ValueListenableBuilder<OrbitViewProjection>(
              valueListenable: listProjectionListenable,
              builder: (context, projection, child) => Positioned(
                bottom: _closeButtonBottomOffset(
                  context,
                  searchActive: projection.searchActive,
                ),
                right: 16,
                child: child!,
              ),
              child: OrbitCloseButton(onTap: onClose),
            ),

            // Layer 3: Search trigger
            AnimatedBuilder(
              animation: searchTriggerAnimation,
              builder: (context, child) {
                final t = searchTriggerAnimation.value;
                return Positioned(
                  bottom: _searchTriggerBottomOffset(context),
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

            // Layer 4: Search dock (slides up from bottom)
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
                child: Center(child: _buildNavigationBar()),
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

  Widget _buildIntroBanner(OrbitViewProjection projection) {
    return GestureDetector(
      onTap: onIntroBannerTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0x141DB954),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0x331DB954)),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.people_outline,
              size: 18,
              color: Color(0xFF1DB954),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${projection.reviewCount} item${projection.reviewCount == 1 ? '' : 's'} pending',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xF2FFFFFF),
                    ),
                  ),
                  Text(
                    _buildIntroBannerSubtitle(projection),
                    style: TextStyle(fontSize: 11, color: Color(0x66FFFFFF)),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 18, color: Color(0x66FFFFFF)),
          ],
        ),
      ),
    );
  }

  String _buildIntroBannerSubtitle(OrbitViewProjection projection) {
    final inviteCount = projection.pendingGroupInviteCount;
    final introCount = projection.introCount;
    if (inviteCount > 0 && introCount > 0) {
      return '$inviteCount group invite${inviteCount == 1 ? '' : 's'} and $introCount introduction${introCount == 1 ? '' : 's'} waiting';
    }
    if (inviteCount > 0) {
      return 'Review group invite${inviteCount == 1 ? '' : 's'} and join from Intros';
    }
    return 'Review and accept introductions to start chatting';
  }

  Widget _buildContentSliver(OrbitViewProjection projection) {
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
      return SliverToBoxAdapter(child: _buildNoResults(projection.searchQuery));
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
          (context, index) => _buildIntroEntry(data, introEntries[index]),
          childCount: introEntries.length,
        ),
      ),
    );
  }

  List<_OrbitIntroEntry> _buildIntroEntries(OrbitIntrosViewData data) {
    if (data.groupedIntros.isEmpty && data.pendingGroupInvites.isEmpty) {
      return const [_OrbitIntroEntry.context()];
    }

    final entries = <_OrbitIntroEntry>[const _OrbitIntroEntry.context()];
    if (data.pendingGroupInvites.isNotEmpty) {
      entries.add(const _OrbitIntroEntry.pendingInviteHeader());
      entries.addAll(
        data.pendingGroupInvites.map(_OrbitIntroEntry.pendingInvite),
      );
    }

    final introducerIds = data.groupedIntros.keys.toList();
    for (var groupIndex = 0; groupIndex < introducerIds.length; groupIndex++) {
      final introducerId = introducerIds[groupIndex];
      final intros = data.groupedIntros[introducerId]!;
      final introducerName =
          data.introducerUsernames[introducerId] ?? 'Unknown';

      if (groupIndex > 0 || data.pendingGroupInvites.isNotEmpty) {
        entries.add(const _OrbitIntroEntry.spacer());
      }
      entries.add(_OrbitIntroEntry.header(introducerName));
      entries.addAll(intros.map(_OrbitIntroEntry.row));
    }
    return entries;
  }

  Widget _buildIntroEntry(OrbitIntrosViewData data, _OrbitIntroEntry entry) {
    switch (entry.type) {
      case _OrbitIntroEntryType.context:
        if (data.groupedIntros.isEmpty && data.pendingGroupInvites.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(
              child: Text(
                'No introductions yet',
                style: TextStyle(fontSize: 14, color: Color(0x66FFFFFF)),
              ),
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 16),
          child: Text(
            data.pendingGroupInvites.isNotEmpty
                ? 'Review pending group invites here, then check introductions below. Once you accept, the group appears in Orbit and catches up from offline inbox.'
                : 'These are people your friends know well. Once you both accept, you can start chatting.',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.4),
            ),
            textAlign: TextAlign.center,
          ),
        );
      case _OrbitIntroEntryType.pendingInviteHeader:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            'Pending Group Invites',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.5),
              letterSpacing: 0.8,
            ),
          ),
        );
      case _OrbitIntroEntryType.pendingInvite:
        final invite = entry.pendingInvite!;
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: PendingGroupInviteCard(
            invite: invite,
            isProcessing: data.processingPendingInviteIds.contains(
              invite.groupId,
            ),
            onAccept: data.onAcceptPendingInvite != null
                ? () => data.onAcceptPendingInvite!(invite)
                : null,
            onDecline: data.onDeclinePendingInvite != null
                ? () => data.onDeclinePendingInvite!(invite)
                : null,
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
          child: GroupRow(group: group, onTap: () => onGroupTap(group)),
        ),
      ),
    );
  }

  Widget _buildNoResults(String searchQuery) {
    return Padding(
      padding: const EdgeInsets.only(top: 60),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.search,
              size: 40,
              color: Colors.white.withValues(alpha: 0.25),
            ),
            const SizedBox(height: 16),
            Text(
              'No friends matching "$searchQuery"',
              style: TextStyle(
                fontSize: 15,
                color: Colors.white.withValues(alpha: 0.3),
              ),
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
    return Container(
      key: ValueKey('orbit-loading-row-$index'),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x1FFFFFFF)),
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
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: const Color(0x12FFFFFF),
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
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: const Color(0x14FFFFFF),
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
    return FractionallySizedBox(
      widthFactor: widthFactor,
      alignment: Alignment.centerLeft,
      child: Container(
        height: height,
        decoration: BoxDecoration(
          color: const Color(0x12FFFFFF),
          borderRadius: BorderRadius.circular(height / 2),
        ),
      ),
    );
  }
}
