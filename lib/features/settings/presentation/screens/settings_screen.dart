import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_app/features/feed/presentation/widgets/feed_navigation_bar.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_peer_id_card.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_profile_section.dart';
import 'package:flutter_app/features/settings/presentation/widgets/settings_recovery_phrase_card.dart';

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
  final void Function(String) onSwitchView;
  final String activeTab;

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
    required this.onSwitchView,
    required this.activeTab,
  });

  @override
  Widget build(BuildContext context) {
    final words = mnemonic?.split(' ') ?? [];

    return AmbientBackground(
      child: SafeArea(
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
                            color: const Color.fromRGBO(255, 255, 255, 0.08),
                            border: Border.all(
                              color:
                                  const Color.fromRGBO(255, 255, 255, 0.12),
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
                      const Expanded(
                        child: Text(
                          'Settings',
                          textAlign: TextAlign.center,
                          style: TextStyle(
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
                    if (mnemonic != null && words.length == 12) ...[
                      SettingsRecoveryPhraseCard(
                        words: words,
                        isRevealed: isMnemonicRevealed,
                        isCopied: isMnemonicCopied,
                        onToggleReveal: onToggleMnemonic,
                        onCopy: onCopyMnemonic,
                        onHide: onHideMnemonic,
                      ),
                    ],
                    // Bottom spacer for nav bar clearance
                    const SizedBox(height: 120),
                  ],
                ),
              ),
            ),
            // Navigation bar
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 10),
              child: FeedNavigationBar(
                activeTab: activeTab,
                onSwitchView: onSwitchView,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
