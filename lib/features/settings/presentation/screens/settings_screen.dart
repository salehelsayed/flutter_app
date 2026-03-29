import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_app/l10n/app_localizations.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_navigation_bar.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_peer_id_card.dart';
import 'package:flutter_app/features/settings/presentation/widgets/posts_nearby_settings_card.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_profile_section.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_recovery_phrase_card.dart';
import 'package:flutter_app/features/settings/domain/models/image_quality_preference.dart';
import 'package:flutter_app/features/settings/presentation/widgets/image_quality_toggle.dart';

/// Pure UI Settings screen.
///
/// Displays profile info, peer ID, and recovery phrase in glass cards
/// over the ambient background.
class SettingsScreen extends StatelessWidget {
  final String username;
  final String? peerId;
  final Uint8List? avatarBytes;
  final String? mnemonic;
  final bool isMnemonicRevealed;
  final bool isPeerIdCopied;
  final bool isMnemonicCopied;
  final VoidCallback? onBack;
  final VoidCallback? onPickAvatar;
  final ValueChanged<String>? onUsernameChanged;
  final VoidCallback? onCopyPeerId;
  final VoidCallback? onToggleMnemonic;
  final VoidCallback? onCopyMnemonic;
  final VoidCallback? onHideMnemonic;
  final ImageQualityPreference currentQuality;
  final ValueChanged<ImageQualityPreference>? onQualityChanged;
  final ImageQualityPreference currentVideoQuality;
  final ValueChanged<ImageQualityPreference>? onVideoQualityChanged;
  final bool isNearbySharingEnabled;
  final ValueChanged<bool>? onNearbySharingChanged;
  final Widget? debugSection;
  final void Function(String) onSwitchView;
  final String activeTab;
  final bool showNavigationBar;

  const SettingsScreen({
    super.key,
    required this.username,
    this.peerId,
    this.avatarBytes,
    this.mnemonic,
    this.isMnemonicRevealed = false,
    this.isPeerIdCopied = false,
    this.isMnemonicCopied = false,
    this.onBack,
    this.onPickAvatar,
    this.onUsernameChanged,
    this.onCopyPeerId,
    this.onToggleMnemonic,
    this.onCopyMnemonic,
    this.onHideMnemonic,
    this.currentQuality = ImageQualityPreference.compressed,
    this.onQualityChanged,
    this.currentVideoQuality = ImageQualityPreference.compressed,
    this.onVideoQualityChanged,
    this.isNearbySharingEnabled = false,
    this.onNearbySharingChanged,
    this.debugSection,
    required this.onSwitchView,
    required this.activeTab,
    this.showNavigationBar = true,
  });

  @override
  Widget build(BuildContext context) {
    final words = mnemonic?.split(' ') ?? [];
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;

    return AmbientBackground(
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
                      decoration: const BoxDecoration(
                        color: Color.fromRGBO(10, 10, 15, 0.8),
                        border: Border(
                          bottom: BorderSide(
                            color: Color.fromRGBO(255, 255, 255, 0.12),
                          ),
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
                                color: const Color.fromRGBO(
                                  255,
                                  255,
                                  255,
                                  0.08,
                                ),
                                border: Border.all(
                                  color: const Color.fromRGBO(
                                    255,
                                    255,
                                    255,
                                    0.12,
                                  ),
                                ),
                              ),
                              child: const Icon(
                                Icons.chevron_left,
                                size: 20,
                                color: Color.fromRGBO(255, 255, 255, 0.95),
                              ),
                            ),
                          ),
                          // Title
                          Expanded(
                            child: Text(
                              AppLocalizations.of(context)!.settings_title,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                color: Color.fromRGBO(255, 255, 255, 0.95),
                                letterSpacing: -0.01,
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
                // Scrollable content
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
                        if (peerId != null) ...[
                          SettingsPeerIdCard(
                            peerId: peerId!,
                            isCopied: isPeerIdCopied,
                            onCopy: onCopyPeerId,
                          ),
                          const SizedBox(height: 24),
                        ],
                        if (onQualityChanged != null) ...[
                          ImageQualityToggle(
                            value: currentQuality,
                            onChanged: onQualityChanged!,
                            label: AppLocalizations.of(
                              context,
                            )!.settings_photo_quality,
                          ),
                          const SizedBox(height: 24),
                        ],
                        if (onVideoQualityChanged != null) ...[
                          ImageQualityToggle(
                            value: currentVideoQuality,
                            onChanged: onVideoQualityChanged!,
                            label: AppLocalizations.of(
                              context,
                            )!.settings_video_quality,
                            icon: Icons.videocam,
                          ),
                          const SizedBox(height: 24),
                        ],
                        if (onNearbySharingChanged != null) ...[
                          PostsNearbySettingsCard(
                            sharingEnabled: isNearbySharingEnabled,
                            onChanged: onNearbySharingChanged!,
                          ),
                          const SizedBox(height: 24),
                        ],
                        if (mnemonic != null && words.length == 12) ...[
                          SettingsRecoveryPhraseCard(
                            words: words,
                            isRevealed: isMnemonicRevealed,
                            isCopied: isMnemonicCopied,
                            onToggleReveal: onToggleMnemonic,
                            onCopy: onCopyMnemonic,
                            onHide: onHideMnemonic,
                          ),
                          const SizedBox(height: 24),
                        ],
                        if (debugSection != null) debugSection!,
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
                child: FeedNavigationBar(
                  activeTab: activeTab,
                  onSwitchView: onSwitchView,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
