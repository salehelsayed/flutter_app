import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/home/presentation/widgets/qr_code_section.dart';
import 'package:flutter_app/features/home/presentation/widgets/scan_friend_card.dart';
import 'package:flutter_app/features/home/presentation/widgets/empty_circle_state.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';

/// Screen that displays the user's QR code with FTE-style layout.
///
/// Shows AmbientBackground, QRCodeSection, ScanFriendCard, and
/// EmptyCircleState with staggered entrance animations.
class QRDisplayScreen extends StatefulWidget {
  /// The JSON string to encode in the QR code (null while loading).
  final String? qrData;

  /// Called when the user presses the close button.
  final VoidCallback onClose;

  /// Called when the user taps "Scan a friend's code".
  final VoidCallback? onScanPressed;
  final BackgroundPreference backgroundPreference;

  const QRDisplayScreen({
    super.key,
    required this.qrData,
    required this.onClose,
    this.onScanPressed,
    this.backgroundPreference = BackgroundPreference.defaultBackground,
  });

  @override
  State<QRDisplayScreen> createState() => _QRDisplayScreenState();
}

class _QRDisplayScreenState extends State<QRDisplayScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
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

    // QR section entrance
    _qrOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.00, 0.42, curve: smoothCurve),
      ),
    );
    _qrSlide = Tween<Offset>(begin: const Offset(0, 0.16), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.00, 0.42, curve: smoothCurve),
          ),
        );

    // Scan card entrance (slight stagger)
    _scanOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.03, 0.45, curve: smoothCurve),
      ),
    );
    _scanSlide = Tween<Offset>(begin: const Offset(0, 0.16), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _controller,
            curve: const Interval(0.03, 0.45, curve: smoothCurve),
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
    final t = ((screenHeight - 650) / 250).clamp(0.0, 1.0);
    final horizontalPadding = lerpDouble(20, 24, t)!;
    final topGap = lerpDouble(48, 64, t)!;
    final sectionGap = lerpDouble(8, 16, t)!;
    final lowerGap = lerpDouble(8, 32, t)!;
    final bottomGap = lerpDouble(4, 16, t)!;

    return Scaffold(
      body: AmbientBackground(
        preference: widget.backgroundPreference,
        child: Stack(
          children: [
            // Main content
            SafeArea(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Column(
                          children: [
                            // Top gap for close button
                            SizedBox(height: topGap),
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
                                child: ScanFriendCard(
                                  onTap: widget.onScanPressed,
                                ),
                              ),
                            ),
                            SizedBox(height: lowerGap),
                            // Empty circle state (always visible)
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
            // Floating close button (top-left)
            Positioned(
              top: MediaQuery.of(context).padding.top + 8,
              left: 8,
              child: Builder(
                builder: (context) {
                  return IconButton(
                    icon: Icon(
                      Icons.close,
                      color: context.backgroundReadableColors.iconPrimary,
                    ),
                    onPressed: widget.onClose,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
