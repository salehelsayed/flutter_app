import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/identity/presentation/widgets/brand_header.dart';
import 'package:flutter_app/features/identity/presentation/widgets/choice_card.dart';

/// Onboarding screen presenting two identity initialization options.
///
/// Features Custom1 dark theme with glassmorphism effects,
/// animated ambient backgrounds, and staggered entry animations.
class IdentityChoiceScreen extends StatefulWidget {
  /// Callback invoked when user chooses to create a new identity.
  final VoidCallback onNewHere;

  /// Callback invoked when user chooses to restore from mnemonic.
  final VoidCallback onLoadMyKey;

  const IdentityChoiceScreen({
    super.key,
    required this.onNewHere,
    required this.onLoadMyKey,
  });

  @override
  State<IdentityChoiceScreen> createState() => _IdentityChoiceScreenState();
}

class _IdentityChoiceScreenState extends State<IdentityChoiceScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _headerFadeAnimation;
  late Animation<Offset> _headerSlideAnimation;
  late Animation<double> _card1FadeAnimation;
  late Animation<Offset> _card1SlideAnimation;
  late Animation<double> _card2FadeAnimation;
  late Animation<Offset> _card2SlideAnimation;
  late Animation<double> _footerFadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    // Header animation (fade in from top)
    _headerFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );
    _headerSlideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.4, curve: Curves.easeOut),
      ),
    );

    // First card animation (fade in from bottom)
    _card1FadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.2, 0.6, curve: Curves.easeOut),
      ),
    );
    _card1SlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.2, 0.6, curve: Curves.easeOut),
      ),
    );

    // Second card animation (fade in from bottom, staggered)
    _card2FadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.35, 0.75, curve: Curves.easeOut),
      ),
    );
    _card2SlideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.35, 0.75, curve: Curves.easeOut),
      ),
    );

    // Footer animation
    _footerFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.6, 1.0, curve: Curves.easeOut),
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: AmbientBackground(
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              children: [
                const Spacer(flex: 2),
                // Brand header with fade-in from top
                FadeTransition(
                  opacity: _headerFadeAnimation,
                  child: SlideTransition(
                    position: _headerSlideAnimation,
                    child: const BrandHeader(),
                  ),
                ),
                const Spacer(flex: 2),
                // Choice cards
                FadeTransition(
                  opacity: _card1FadeAnimation,
                  child: SlideTransition(
                    position: _card1SlideAnimation,
                    child: ChoiceCard(
                      icon: Icons.add_circle_outline,
                      title: "I'm new here",
                      description: 'Generate a fresh identity',
                      onTap: widget.onNewHere,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                FadeTransition(
                  opacity: _card2FadeAnimation,
                  child: SlideTransition(
                    position: _card2SlideAnimation,
                    child: ChoiceCard(
                      icon: Icons.key_outlined,
                      title: 'Load my key',
                      description: 'Restore from recovery phrase',
                      onTap: widget.onLoadMyKey,
                    ),
                  ),
                ),
                const Spacer(flex: 2),
                // Privacy footer
                FadeTransition(
                  opacity: _footerFadeAnimation,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.lock_outline,
                              size: 14,
                              color: AppColors.textMuted.withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Only you can read your messages',
                              style: TextStyle(
                                color: AppColors.textMuted.withValues(alpha: 0.6),
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Everything stays on your phone. Nobody is watching.',
                          style: TextStyle(
                            color: AppColors.textMuted.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
