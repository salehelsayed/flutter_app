import 'package:flutter/material.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import '../widgets/profile_avatar_widget.dart';
import '../widgets/editable_username_widget.dart';
import '../widgets/qr_code_section.dart';
import '../widgets/scan_friend_card.dart';
import '../widgets/empty_circle_state.dart';

/// First time experience screen with staggered animations.
class FirstTimeExperienceScreen extends StatefulWidget {
  final String? qrData;
  final String username;
  final VoidCallback? onCameraPressed;
  final ValueChanged<String>? onUsernameChanged;
  final VoidCallback? onScanPressed;

  const FirstTimeExperienceScreen({
    super.key,
    this.qrData,
    required this.username,
    this.onCameraPressed,
    this.onUsernameChanged,
    this.onScanPressed,
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
  late Animation<double> _emptyOpacity;
  late Animation<Offset> _emptySlide;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Header: 0.0-0.4 (fadeInDown)
    _headerOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );
    _headerSlide = Tween<Offset>(
      begin: const Offset(0, -0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );

    // QR: 0.15-0.55 (fadeInUp)
    _qrOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.15, 0.55, curve: Curves.easeOut),
      ),
    );
    _qrSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.15, 0.55, curve: Curves.easeOut),
      ),
    );

    // Scan: 0.3-0.7 (fadeInUp)
    _scanOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 0.7, curve: Curves.easeOut),
      ),
    );
    _scanSlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.3, 0.7, curve: Curves.easeOut),
      ),
    );

    // Empty: 0.45-0.85 (fadeInUp)
    _emptyOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.45, 0.85, curve: Curves.easeOut),
      ),
    );
    _emptySlide = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.45, 0.85, curve: Curves.easeOut),
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
    return AmbientBackground(
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            children: [
              const SizedBox(height: 8),
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
                child: _buildHeader(),
              ),
              const SizedBox(height: 16),
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
                child: QRCodeSection(qrData: widget.qrData),
              ),
              const SizedBox(height: 16),
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
                child: ScanFriendCard(onTap: widget.onScanPressed),
              ),
              const Spacer(),
              // Empty circle state
              AnimatedBuilder(
                animation: _controller,
                builder: (context, child) {
                  return Opacity(
                    opacity: _emptyOpacity.value,
                    child: SlideTransition(
                      position: _emptySlide,
                      child: child,
                    ),
                  );
                },
                child: const EmptyCircleState(),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        ProfileAvatarWidget(onCameraPressed: widget.onCameraPressed),
        const SizedBox(height: 12),
        EditableUsernameWidget(
          username: widget.username,
          onUsernameChanged: widget.onUsernameChanged,
        ),
      ],
    );
  }
}
