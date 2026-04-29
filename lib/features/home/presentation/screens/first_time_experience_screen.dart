import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/services/p2p_service.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/p2p/presentation/widgets/connection_status_indicator.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import '../widgets/profile_avatar_widget.dart';
import '../widgets/editable_username_widget.dart';
import '../widgets/qr_code_section.dart';
import '../widgets/scan_friend_card.dart';
import '../widgets/empty_circle_state.dart';

/// First time experience screen with staggered animations.
class FirstTimeExperienceScreen extends StatefulWidget {
  final String? qrData;
  final String username;
  final Uint8List? avatarBytes;
  final String? peerId;
  final VoidCallback? onCameraPressed;
  final ValueChanged<String>? onUsernameChanged;
  final VoidCallback? onScanPressed;
  final P2PService? p2pService;
  final BackgroundPreference backgroundPreference;

  const FirstTimeExperienceScreen({
    super.key,
    this.qrData,
    required this.username,
    this.avatarBytes,
    this.peerId,
    this.onCameraPressed,
    this.onUsernameChanged,
    this.onScanPressed,
    this.p2pService,
    this.backgroundPreference = BackgroundPreference.defaultBackground,
  });

  @override
  State<FirstTimeExperienceScreen> createState() =>
      _FirstTimeExperienceScreenState();
}

class _FirstTimeExperienceScreenState extends State<FirstTimeExperienceScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _headerOpacity;
  late Animation<Offset> _headerSlide;
  late Animation<double> _qrOpacity;
  late Animation<Offset> _qrSlide;
  late Animation<double> _scanOpacity;
  late Animation<Offset> _scanSlide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    );
    const smoothCurve = Curves.easeOutCubic;

    // Minimal stagger: all sections appear almost together.
    _headerOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.00, 0.42, curve: smoothCurve),
      ),
    );
    _headerSlide =
        Tween<Offset>(begin: const Offset(0, -0.18), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.00, 0.42, curve: smoothCurve),
          ),
        );

    // QR follows almost immediately after header.
    _qrOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.03, 0.45, curve: smoothCurve),
      ),
    );
    _qrSlide = Tween<Offset>(begin: const Offset(0, 0.16), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.03, 0.45, curve: smoothCurve),
          ),
        );

    // Scan appears with minimal delay from QR.
    _scanOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.06, 0.48, curve: smoothCurve),
      ),
    );
    _scanSlide = Tween<Offset>(begin: const Offset(0, 0.16), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.06, 0.48, curve: smoothCurve),
          ),
        );

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
    // Continuous scaling: 0.0 at 650pt (smallest), 1.0 at 900pt (largest)
    final t = ((screenHeight - 650) / 250).clamp(0.0, 1.0);
    final horizontalPadding = lerpDouble(20, 24, t)!;
    final topGap = lerpDouble(4, 8, t)!;
    final sectionGap = lerpDouble(8, 16, t)!;
    final lowerGap = lerpDouble(8, 32, t)!;
    final bottomGap = lerpDouble(4, 16, t)!;

    return AmbientBackground(
      preference: widget.backgroundPreference,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Column(
                    children: [
                      SizedBox(height: topGap),
                      // Connection status indicator at the top
                      if (widget.p2pService != null)
                        Align(
                          alignment: Alignment.topRight,
                          child: ConnectionStatusIndicator(
                            p2pService: widget.p2pService!,
                          ),
                        ),
                      SizedBox(height: topGap),
                      // Header section (avatar + username)
                      AnimatedBuilder(
                        animation: _controller,
                        builder: (context, child) {
                          return Opacity(
                            opacity: _headerOpacity.value,
                            child: SlideTransition(
                              position: _headerSlide,
                              child: child,
                            ),
                          );
                        },
                        child: _buildHeader(scaleFactor: t),
                      ),
                      SizedBox(height: sectionGap),
                      // QR code section
                      AnimatedBuilder(
                        animation: _controller,
                        builder: (context, child) {
                          return Opacity(
                            opacity: _qrOpacity.value,
                            child: SlideTransition(
                              position: _qrSlide,
                              child: child,
                            ),
                          );
                        },
                        child: RepaintBoundary(
                          child: QRCodeSection(
                            qrData: widget.qrData,
                            scaleFactor: t,
                          ),
                        ),
                      ),
                      SizedBox(height: sectionGap),
                      // Scan friend card
                      AnimatedBuilder(
                        animation: _controller,
                        builder: (context, child) {
                          return Opacity(
                            opacity: _scanOpacity.value,
                            child: SlideTransition(
                              position: _scanSlide,
                              child: child,
                            ),
                          );
                        },
                        child: RepaintBoundary(
                          child: ScanFriendCard(onTap: widget.onScanPressed),
                        ),
                      ),
                      SizedBox(height: lowerGap),
                      // Empty circle state (visible immediately)
                      const RepaintBoundary(
                        child: TickerMode(
                          enabled: true,
                          child: EmptyCircleState(),
                        ),
                      ),
                      SizedBox(height: bottomGap),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildHeader({required double scaleFactor}) {
    final avatarSize = lerpDouble(64, 80, scaleFactor)!;
    final gap = lerpDouble(6, 12, scaleFactor)!;
    return Column(
      children: [
        ProfileAvatarWidget(
          avatarBytes: widget.avatarBytes,
          peerId: widget.peerId,
          onCameraPressed: widget.onCameraPressed,
          size: avatarSize,
        ),
        SizedBox(height: gap),
        EditableUsernameWidget(
          username: widget.username,
          onUsernameChanged: widget.onUsernameChanged,
        ),
      ],
    );
  }
}
