import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_app/features/groups/domain/models/group_model.dart';
import 'package:flutter_app/features/introduction/domain/models/introduction_model.dart';
import 'package:flutter_app/features/introduction/presentation/widgets/intro_group_header.dart';
import 'package:flutter_app/features/introduction/presentation/widgets/intro_row.dart';
import 'package:flutter_app/features/groups/presentation/widgets/expandable_fab.dart';
import 'package:flutter_app/features/identity/domain/models/identity_model.dart';
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
  final void Function(String introductionId) onAccept;
  final void Function(String introductionId) onPass;
  final void Function(String peerId)? onSendMessage;
  final Set<String> blockedPeerIds;

  const OrbitIntrosViewData({
    required this.groupedIntros,
    required this.introducerUsernames,
    required this.ownPeerId,
    required this.onAccept,
    required this.onPass,
    this.onSendMessage,
    this.blockedPeerIds = const {},
  });
}

enum _OrbitIntroEntryType { context, header, row, spacer }

class _OrbitIntroEntry {
  final _OrbitIntroEntryType type;
  final String? introducerUsername;
  final IntroductionModel? introduction;

  const _OrbitIntroEntry._(
    this.type, {
    this.introducerUsername,
    this.introduction,
  });

  const _OrbitIntroEntry.context() : this._(_OrbitIntroEntryType.context);

  const _OrbitIntroEntry.header(String introducerUsername)
    : this._(
        _OrbitIntroEntryType.header,
        introducerUsername: introducerUsername,
      );

  const _OrbitIntroEntry.row(IntroductionModel introduction)
    : this._(_OrbitIntroEntryType.row, introduction: introduction);

  const _OrbitIntroEntry.spacer() : this._(_OrbitIntroEntryType.spacer);
}

/// Pure UI layout for the Orbit screen.
///
/// Receives all state and callbacks from OrbitWired.
class OrbitScreen extends StatelessWidget {
  final IdentityModel? identity;
  final Uint8List? userAvatarBytes;
  final List<OrbitFriend> allFriends;
  final List<OrbitFriend> displayedFriends;
  final bool searchActive;
  final String searchQuery;
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
  final String filterTab;
  final int activeCount;
  final int archivedCount;
  final void Function(String) onFilterChanged;
  final void Function(OrbitFriend) onArchiveFriend;
  final void Function(OrbitFriend) onUnarchiveFriend;
  final void Function(OrbitFriend) onBlockFriend;
  final void Function(OrbitFriend) onUnblockFriend;
  final void Function(OrbitFriend) onDeleteFriend;
  final ValueNotifier<Key?> openRowNotifier;
  final List<OrbitGroup> groups;
  final void Function(OrbitGroup) onGroupTap;
  final void Function(GroupType) onCreateGroup;
  final void Function(OrbitGroup) onArchiveGroup;
  final void Function(OrbitGroup) onUnarchiveGroup;
  final void Function(OrbitGroup) onDeleteGroup;
  final int introsCount;
  final OrbitIntrosViewData? introsData;
  final Widget? introsWidget;
  final VoidCallback? onIntroBannerTap;

  const OrbitScreen({
    super.key,
    required this.identity,
    this.userAvatarBytes,
    required this.allFriends,
    required this.displayedFriends,
    required this.searchActive,
    required this.searchQuery,
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
    required this.filterTab,
    required this.activeCount,
    required this.archivedCount,
    required this.onFilterChanged,
    required this.onArchiveFriend,
    required this.onUnarchiveFriend,
    required this.onBlockFriend,
    required this.onUnblockFriend,
    required this.onDeleteFriend,
    required this.openRowNotifier,
    this.groups = const [],
    required this.onGroupTap,
    required this.onCreateGroup,
    required this.onArchiveGroup,
    required this.onUnarchiveGroup,
    required this.onDeleteGroup,
    this.introsCount = 0,
    this.introsData,
    this.introsWidget,
    this.onIntroBannerTap,
  });

  /// Builds a merged and sorted list of orbit items (friends + groups)
  /// for the current tab and search state.
  List<OrbitItem> _buildMergedItems() {
    final items = <OrbitItem>[];

    for (final friend in displayedFriends) {
      items.add(OrbitFriendItem(friend));
    }

    // Show groups when not searching (groups list is pre-filtered by tab in OrbitWired)
    if (!searchActive) {
      for (final group in groups) {
        items.add(OrbitGroupItem(group));
      }
    }

    // Sort by most recent activity first
    items.sort((a, b) => b.sortKey.compareTo(a.sortKey));
    return items;
  }

  @override
  Widget build(BuildContext context) {
    final userPeerId = identity?.peerId;
    final mergedItems = _buildMergedItems();

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
                  AnimatedBuilder(
                    animation: collapseAnimation,
                    builder: (context, child) {
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
                              child: child,
                            ),
                          ),
                        ),
                      );
                    },
                    child: Column(
                      children: [
                        OrbitalVisualization(
                          userPeerId: userPeerId,
                          userAvatarBytes: userAvatarBytes,
                          friends: allFriends
                              .where((f) => !f.isBlocked)
                              .toList(),
                        ),
                        const Padding(
                          padding: EdgeInsets.only(top: 20),
                          child: Text(
                            'Close Friends',
                            style: TextStyle(
                              fontSize: 14,
                              color: Color(0x99FFFFFF),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Scrollable friends list
                  Expanded(
                    child: CustomScrollView(
                      controller: scrollController,
                      physics: const BouncingScrollPhysics(),
                      cacheExtent: 600,
                      slivers: [
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                FriendsListHeader(
                                  onMyQR: onMyQR,
                                  onScanQR: onScanQR,
                                  searchActive: searchActive,
                                ),
                                if (!searchActive) ...[
                                  const SizedBox(height: 8),
                                  FriendsFilterToggle(
                                    activeFilter: filterTab,
                                    activeCount: activeCount,
                                    archivedCount: archivedCount,
                                    introsCount: introsCount,
                                    onFilterChanged: onFilterChanged,
                                  ),
                                ],
                                const SizedBox(height: 8),
                                if (introsCount > 0 && filterTab != 'intros')
                                  _buildIntroBanner(),
                              ],
                            ),
                          ),
                        ),
                        _buildContentSliver(mergedItems),
                        SliverToBoxAdapter(
                          child: SizedBox(height: searchActive ? 320 : 100),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Layer 2: Close button (bottom-right, below search)
            Positioned(
              bottom: 40,
              right: 18,
              child: OrbitCloseButton(onTap: onClose),
            ),

            // Layer 3: Search trigger (bottom-right, above X)
            AnimatedBuilder(
              animation: searchTriggerAnimation,
              builder: (context, child) {
                final t = searchTriggerAnimation.value;
                return Positioned(
                  bottom: 80,
                  right: 18,
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
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Transform.translate(
                    offset: Offset(0, (1 - t) * 300),
                    child: IgnorePointer(ignoring: t < 0.1, child: child),
                  ),
                );
              },
              child: OrbitSearchDock(
                controller: searchController,
                focusNode: searchFocusNode,
                onChanged: onSearchChanged,
                onClear: onSearchClear,
                onClose: onSearchClose,
                query: searchQuery,
              ),
            ),

            // Layer 5: ExpandableFab (create group)
            ExpandableFab(
              anchor: ExpandableFabAnchor.topRight,
              fabSize: 40,
              safeAreaPadding: MediaQuery.of(context).padding,
              items: [
                ExpandableFabItem(
                  label: 'New Group',
                  icon: Icons.group_outlined,
                  onTap: () => onCreateGroup(GroupType.chat),
                ),
                ExpandableFabItem(
                  label: 'New Announce',
                  icon: Icons.campaign_outlined,
                  onTap: () => onCreateGroup(GroupType.announcement),
                ),
                ExpandableFabItem(
                  label: 'New Q&A',
                  icon: Icons.quiz_outlined,
                  onTap: () => onCreateGroup(GroupType.qa),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIntroBanner() {
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
                    '$introsCount introduction${introsCount == 1 ? '' : 's'} pending',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xF2FFFFFF),
                    ),
                  ),
                  const Text(
                    'Review and accept to start chatting',
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

  Widget _buildContentSliver(List<OrbitItem> mergedItems) {
    if (filterTab == 'intros') {
      if (introsData != null) {
        return _buildIntroSliver(introsData!);
      }
      if (introsWidget != null) {
        return SliverToBoxAdapter(child: introsWidget!);
      }
    }

    if (searchActive && searchQuery.isNotEmpty && displayedFriends.isEmpty) {
      return SliverToBoxAdapter(child: _buildNoResults());
    }

    if (filterTab == 'archived' &&
        displayedFriends.isEmpty &&
        groups.isEmpty &&
        !searchActive) {
      return const SliverFillRemaining(
        hasScrollBody: false,
        child: ArchivedEmptyState(),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final item = mergedItems[index];
          return switch (item) {
            OrbitFriendItem(:final friend) => _buildFriendRow(friend, index),
            OrbitGroupItem(:final group) => _buildGroupRow(group, index),
          };
        }, childCount: mergedItems.length),
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
    if (data.groupedIntros.isEmpty) {
      return const [_OrbitIntroEntry.context()];
    }

    final entries = <_OrbitIntroEntry>[const _OrbitIntroEntry.context()];
    final introducerIds = data.groupedIntros.keys.toList();
    for (var groupIndex = 0; groupIndex < introducerIds.length; groupIndex++) {
      final introducerId = introducerIds[groupIndex];
      final intros = data.groupedIntros[introducerId]!;
      final introducerName =
          data.introducerUsernames[introducerId] ?? 'Unknown';

      if (groupIndex > 0) {
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
        if (data.groupedIntros.isEmpty) {
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
            'These are people your friends know well. Once you both accept, you can start chatting.',
            style: TextStyle(
              fontSize: 13,
              color: Colors.white.withValues(alpha: 0.4),
            ),
            textAlign: TextAlign.center,
          ),
        );
      case _OrbitIntroEntryType.header:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            IntroGroupHeader(introducerUsername: entry.introducerUsername!),
            const SizedBox(height: 8),
          ],
        );
      case _OrbitIntroEntryType.row:
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

        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: IntroRow(
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
          ),
        );
      case _OrbitIntroEntryType.spacer:
        return const SizedBox(height: 16);
    }
  }

  Widget _buildFriendRow(OrbitFriend friend, int index) {
    final isInnerCircle = allFriends.indexOf(friend) < 13;
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
            showInnerCircleBadge: searchActive && isInnerCircle,
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

  Widget _buildNoResults() {
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
