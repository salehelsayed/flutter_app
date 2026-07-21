import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_group.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_orbit_nav_button.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_profile_section.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_qr_tiles.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';

/// Pure UI Settings screen — 209 "One Screen" layout.
///
/// Profile header → My QR / Scan tiles → IDENTITY group (peer ID row with
/// copy, recovery-phrase row) → PREFERENCES group (background / photo / video
/// rows with at-rest values opening focused sub-sheets, inline nearby switch,
/// move-account row) → optional debug section. The whole page fits a 390×844
/// viewport with zero scroll at textScale 1.0 (debug cards excluded) — a
/// pinned-constants contract: avatar 72, 44px custom rows, tiles ≤72px,
/// shrink-wrapped nearby Switch (INV-209-3).
///
/// The QR tiles are a host-capability PAIR: they mount only when the host
/// supplies BOTH [onMyQr] and [onScan] (INV-209-1 — the dead posts entry
/// cannot supply the scanner bundle, spec §7.1).
class SettingsScreen extends StatelessWidget {
  final String username;
  final String? peerId;
  final Uint8List? avatarBytes;
  final String? mnemonic;
  final bool isPeerIdCopied;
  final VoidCallback? onBack;
  final VoidCallback? onPickAvatar;
  final ValueChanged<String>? onUsernameChanged;
  final VoidCallback? onCopyPeerId;
  final VoidCallback? onMyQr;
  final VoidCallback? onScan;
  final VoidCallback? onOpenBackgroundSheet;
  final VoidCallback? onOpenPhotoQualitySheet;
  final VoidCallback? onOpenVideoQualitySheet;

  /// 229: opens the Media & storage sheet (auto-download matrix + scoped
  /// storage totals/actions). Row hidden when null.
  final VoidCallback? onOpenMediaStorageSheet;
  final VoidCallback? onOpenRecoverySheet;
  final BackgroundPreference currentBackgroundPreference;
  final ImageQualityPreference currentQuality;
  final ImageQualityPreference currentVideoQuality;
  final bool isNearbySharingEnabled;
  final ValueChanged<bool>? onNearbySharingChanged;
  final VoidCallback? onMoveAccountToNewPhone;
  final Widget? groupExitDiagnosticsSection;
  final Widget? debugSection;
  final void Function(String) onSwitchView;
  final String activeTab;
  final bool showNavigationBar;
  final BackgroundReadableTone? readableToneOverride;

  const SettingsScreen({
    super.key,
    required this.username,
    this.peerId,
    this.avatarBytes,
    this.mnemonic,
    this.isPeerIdCopied = false,
    this.onBack,
    this.onPickAvatar,
    this.onUsernameChanged,
    this.onCopyPeerId,
    this.onMyQr,
    this.onScan,
    this.onOpenBackgroundSheet,
    this.onOpenPhotoQualitySheet,
    this.onOpenVideoQualitySheet,
    this.onOpenMediaStorageSheet,
    this.onOpenRecoverySheet,
    this.currentBackgroundPreference = BackgroundPreference.defaultBackground,
    this.currentQuality = ImageQualityPreference.compressed,
    this.currentVideoQuality = ImageQualityPreference.compressed,
    this.isNearbySharingEnabled = false,
    this.onNearbySharingChanged,
    this.onMoveAccountToNewPhone,
    this.groupExitDiagnosticsSection,
    this.debugSection,
    required this.onSwitchView,
    required this.activeTab,
    this.showNavigationBar = true,
    this.readableToneOverride,
  });

  String _backgroundValueLabel(AppLocalizations l10n) =>
      switch (currentBackgroundPreference) {
        BackgroundPreference.defaultBackground =>
          l10n.settings_background_default,
        BackgroundPreference.cosmic => l10n.settings_background_cosmic,
        BackgroundPreference.aurora => l10n.settings_background_aurora,
        BackgroundPreference.daylightLagoon =>
          l10n.settings_background_daylight_lagoon,
      };

  String _qualityValueLabel(
    AppLocalizations l10n,
    ImageQualityPreference quality,
  ) => quality == ImageQualityPreference.original
      ? l10n.settings_original
      : l10n.settings_compressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final words = mnemonic?.split(' ') ?? [];
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final readableColors = BackgroundReadableColors.resolve(
      currentBackgroundPreference,
      representativeToneOverride: readableToneOverride,
    );

    // INV-209-1: the tiles gate as a PAIR — both callbacks or no tiles.
    final showQrTiles = onMyQr != null && onScan != null;
    final showRecoveryRow =
        mnemonic != null && words.length == 12 && onOpenRecoverySheet != null;
    final identityRows = <Widget>[
      if (peerId != null)
        SettingsListRow(
          key: const ValueKey('settings-row-peer-id'),
          icon: Icons.fingerprint,
          label: l10n.settings_peer_id_title,
          value: peerId,
          trailing: _PeerIdCopyButton(
            isCopied: isPeerIdCopied,
            onCopy: onCopyPeerId,
          ),
        ),
      if (showRecoveryRow)
        SettingsListRow(
          key: const ValueKey('settings-row-recovery'),
          icon: Icons.key_outlined,
          label: l10n.settings_recovery_title,
          onTap: onOpenRecoverySheet,
        ),
    ];
    final preferenceRows = <Widget>[
      if (onOpenBackgroundSheet != null)
        SettingsListRow(
          key: const ValueKey('settings-row-background'),
          icon: Icons.wallpaper,
          label: l10n.settings_background,
          value: _backgroundValueLabel(l10n),
          onTap: onOpenBackgroundSheet,
        ),
      if (onOpenPhotoQualitySheet != null)
        SettingsListRow(
          key: const ValueKey('settings-row-photo-quality'),
          icon: Icons.photo_size_select_large,
          label: l10n.settings_photo_quality,
          value: _qualityValueLabel(l10n, currentQuality),
          onTap: onOpenPhotoQualitySheet,
        ),
      if (onOpenVideoQualitySheet != null)
        SettingsListRow(
          key: const ValueKey('settings-row-video-quality'),
          icon: Icons.videocam,
          label: l10n.settings_video_quality,
          value: _qualityValueLabel(l10n, currentVideoQuality),
          onTap: onOpenVideoQualitySheet,
        ),
      if (onOpenMediaStorageSheet != null)
        SettingsListRow(
          key: const ValueKey('settings-row-media-storage'),
          icon: Icons.download_for_offline_outlined,
          label: l10n.settings_media_storage,
          onTap: onOpenMediaStorageSheet,
        ),
      if (onNearbySharingChanged != null)
        SettingsListRow(
          key: const ValueKey('settings-row-nearby'),
          icon: Icons.near_me_outlined,
          label: l10n.settings_share_nearby,
          subtitle: l10n.settings_share_nearby_desc,
          value: isNearbySharingEnabled
              ? l10n.settings_share_nearby_on
              : l10n.settings_share_nearby_off,
          trailing: Switch.adaptive(
            value: isNearbySharingEnabled,
            onChanged: onNearbySharingChanged,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      if (onMoveAccountToNewPhone != null)
        SettingsListRow(
          key: const ValueKey('settings-move-account-action'),
          icon: Icons.phonelink_setup_outlined,
          label: l10n.settings_move_account_title,
          onTap: onMoveAccountToNewPhone,
        ),
    ];

    return AmbientBackground(
      preference: currentBackgroundPreference,
      readableToneOverride: readableToneOverride,
      child: Stack(
        children: [
          // Main content with top-only SafeArea
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                // Sticky header
                ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      decoration: BoxDecoration(
                        color: readableColors.glassSurface,
                        border: Border(
                          bottom: BorderSide(color: readableColors.glassBorder),
                        ),
                      ),
                      child: Row(
                        children: [
                          // Back button
                          GestureDetector(
                            onTap: onBack,
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: readableColors.surfaceSubtle,
                                border: Border.all(
                                  color: readableColors.border,
                                ),
                              ),
                              child: Icon(
                                Icons.chevron_left,
                                size: 20,
                                color: readableColors.iconPrimary,
                              ),
                            ),
                          ),
                          // Title
                          Expanded(
                            child: Text(
                              l10n.settings_title,
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: readableColors.textPrimary,
                              ),
                            ),
                          ),
                          // Right spacer
                          const SizedBox(width: 40),
                        ],
                      ),
                    ),
                  ),
                ),
                // Scrollable content (zero scroll extent on the reference
                // viewport — the One-Screen contract; shorter viewports and
                // large text scales scroll normally).
                Expanded(
                  child: SingleChildScrollView(
                    physics: const BouncingScrollPhysics(),
                    padding: EdgeInsets.only(
                      bottom: (showNavigationBar ? 60 : 24) + bottomInset,
                    ),
                    child: Column(
                      children: [
                        SettingsProfileSection(
                          peerId: peerId,
                          avatarBytes: avatarBytes,
                          username: username,
                          onPickAvatar: onPickAvatar,
                          onUsernameChanged: onUsernameChanged,
                        ),
                        if (showQrTiles) ...[
                          SettingsQrTiles(onMyQr: onMyQr!, onScan: onScan!),
                          const SizedBox(height: 14),
                        ],
                        if (identityRows.isNotEmpty) ...[
                          SettingsGroupCard(
                            label: l10n.settings_section_identity,
                            children: identityRows,
                          ),
                          const SizedBox(height: 14),
                        ],
                        if (preferenceRows.isNotEmpty) ...[
                          SettingsGroupCard(
                            label: l10n.settings_section_preferences,
                            children: preferenceRows,
                          ),
                          const SizedBox(height: 14),
                        ],
                        ?groupExitDiagnosticsSection,
                        ?debugSection,
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Floating nav bar pinned to bottom
          if (showNavigationBar)
            Positioned(
              left: 0,
              right: 0,
              bottom: bottomInset + 8,
              child: Center(
                child: SettingsOrbitNavButton(
                  onTap: () => onSwitchView('orbit'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// The peer-id row's trailing copy affordance — same check-for-2s feedback the
/// retired SettingsPeerIdCard carried (the full ID lands on the clipboard via
/// the host's onCopyPeerId).
class _PeerIdCopyButton extends StatelessWidget {
  final bool isCopied;
  final VoidCallback? onCopy;

  const _PeerIdCopyButton({required this.isCopied, required this.onCopy});

  @override
  Widget build(BuildContext context) {
    final readableColors = context.backgroundReadableColors;
    final copiedColor = readableColors.isLightSurface
        ? const Color(0xFF0F766E)
        : const Color(0xFF14B8A6);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onCopy,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: readableColors.surfaceSubtle,
          border: Border.all(color: readableColors.glassBorder),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: Icon(
            isCopied ? Icons.check : Icons.copy,
            key: ValueKey(isCopied),
            size: 15,
            color: isCopied ? copiedColor : readableColors.iconSecondary,
          ),
        ),
      ),
    );
  }
}
