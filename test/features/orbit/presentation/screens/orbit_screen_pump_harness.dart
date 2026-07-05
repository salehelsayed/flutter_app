import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/orbit/domain/models/orbit_view_mode.dart';
import 'package:flutter_app/features/orbit/presentation/screens/orbit_screen.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// 205 — a minimal, self-contained [OrbitScreen] pump for the screen-level
/// rows (canvas centering, edit-mode chrome suppression, no-results lens). It
/// builds the real production widget with ValueNotifier-backed projections and
/// no-op callbacks, so no repository/wiring stack is needed. NOT a `_test.dart`
/// file, so `feature-host-all`'s glob never runs it as a suite.
Widget buildOrbitScreenHarness({
  required OrbitViewMode viewMode,
  OrbitHeaderProjection header = const OrbitHeaderProjection(),
  OrbitViewProjection list = const OrbitViewProjection(),
  VoidCallback? onToggleView,
  ValueChanged<bool>? onInnerEdit,
  Locale locale = const Locale('en'),
}) {
  final headerVN = ValueNotifier<OrbitHeaderProjection>(header);
  final listVN = ValueNotifier<OrbitViewProjection>(list);
  return MaterialApp(
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    theme: ThemeData(extensions: const [BackgroundReadableColors.dark]),
    home: OrbitScreen(
      headerProjectionListenable: headerVN,
      listProjectionListenable: listVN,
      scrollController: ScrollController(),
      searchController: TextEditingController(),
      searchFocusNode: FocusNode(),
      collapseAnimation: const AlwaysStoppedAnimation<double>(0),
      searchDockAnimation: const AlwaysStoppedAnimation<double>(0),
      searchTriggerAnimation: const AlwaysStoppedAnimation<double>(0),
      onClose: () {},
      onFriendTap: (_) {},
      onSearchOpen: () {},
      onSearchClose: () {},
      onSearchChanged: (_) {},
      onSearchClear: () {},
      onFilterChanged: (_) {},
      onArchiveFriend: (_) {},
      onUnarchiveFriend: (_) {},
      onBlockFriend: (_) {},
      onUnblockFriend: (_) {},
      onDeleteFriend: (_) {},
      openRowNotifier: ValueNotifier<Key?>(null),
      onGroupTap: (_) {},
      onCreateGroup: (_) {},
      onArchiveGroup: (_) {},
      onUnarchiveGroup: (_) {},
      onDeleteGroup: (_) {},
      viewMode: viewMode,
      onToggleView: onToggleView,
      onInnerCircleEditSessionChanged: onInnerEdit,
    ),
  );
}
