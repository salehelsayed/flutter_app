import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/background_readable_colors.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/features/identity/presentation/widgets/ambient_background.dart';
import 'package:flutter_app/features/identity/presentation/widgets/brand_header.dart';
import 'package:flutter_app/features/identity/presentation/widgets/choice_card.dart';
import 'package:flutter_app/features/settings/domain/models/background_preference.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// Onboarding screen presenting two identity initialization options.
///
/// Features Custom1 dark theme with glassmorphism effects,
/// animated ambient backgrounds, and staggered entry animations.
class IdentityChoiceScreen extends StatefulWidget {
  /// Callback invoked when user chooses to create a new identity.
  final VoidCallback? onNewHere;

  /// Callback invoked when user chooses to restore from mnemonic.
  final VoidCallback? onLoadMyKey;
  final BackgroundPreference backgroundPreference;

  const IdentityChoiceScreen({
    super.key,
    required this.onNewHere,
    required this.onLoadMyKey,
    this.backgroundPreference = BackgroundPreference.defaultBackground,
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
    _headerSlideAnimation =
        Tween<Offset>(begin: const Offset(0, -0.3), end: Offset.zero).animate(
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
    _card1SlideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
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
    _card2SlideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
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
        preference: widget.backgroundPreference,
        child: Builder(
          builder: (context) {
            final readableColors = context.backgroundReadableColors;
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return SingleChildScrollView(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: constraints.maxHeight,
                        ),
                        child: Column(
                          children: [
                            SizedBox(height: constraints.maxHeight * 0.12),
                            // Brand header with fade-in from top
                            FadeTransition(
                              opacity: _headerFadeAnimation,
                              child: SlideTransition(
                                position: _headerSlideAnimation,
                                child: const BrandHeader(),
                              ),
                            ),
                            SizedBox(height: constraints.maxHeight * 0.12),
                            // Choice cards
                            Builder(
                              builder: (context) {
                                final l10n = AppLocalizations.of(context)!;
                                return Column(
                                  children: [
                                    FadeTransition(
                                      opacity: _card1FadeAnimation,
                                      child: SlideTransition(
                                        position: _card1SlideAnimation,
                                        child: ChoiceCard(
                                          icon: Icons.add_circle_outline,
                                          title: l10n.onboarding_new_here,
                                          description: l10n.onboarding_new_desc,
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
                                          title: l10n.onboarding_load_key,
                                          description:
                                              l10n.onboarding_load_desc,
                                          onTap: widget.onLoadMyKey,
                                        ),
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            SizedBox(height: constraints.maxHeight * 0.12),
                            // Privacy footer
                            FadeTransition(
                              opacity: _footerFadeAnimation,
                              child: Padding(
                                padding: const EdgeInsets.only(bottom: 24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          Icons.lock_outline,
                                          size: 14,
                                          color: readableColors.iconMuted,
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          AppLocalizations.of(
                                            context,
                                          )!.onboarding_privacy_1,
                                          style: TextStyle(
                                            color: readableColors.textMuted,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      AppLocalizations.of(
                                        context,
                                      )!.onboarding_privacy_2,
                                      style: TextStyle(
                                        color: readableColors.textMuted,
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
                    );
                  },
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
