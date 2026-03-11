import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_colors.dart';

class IdentityProgressScreen extends StatefulWidget {
  final ValueListenable<String> stageListenable;
  final VoidCallback? onFirstFrameRendered;

  const IdentityProgressScreen({
    super.key,
    required this.stageListenable,
    this.onFirstFrameRendered,
  });

  @override
  State<IdentityProgressScreen> createState() => _IdentityProgressScreenState();
}

class _IdentityProgressScreenState extends State<IdentityProgressScreen> {
  bool _reportedFirstFrame = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _reportedFirstFrame) return;
      _reportedFirstFrame = true;
      widget.onFirstFrameRendered?.call();
    });
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: SizedBox.expand(
        key: const ValueKey('identity-progress-screen'),
        child: Material(
          color: AppColors.background,
          child: DecoratedBox(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF05090C), AppColors.background],
              ),
            ),
            child: Center(
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.symmetric(
                  horizontal: 28,
                  vertical: 32,
                ),
                constraints: const BoxConstraints(maxWidth: 360),
                decoration: BoxDecoration(
                  color: const Color(0xFF10151A),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.1),
                    width: 1,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.04),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: const Center(
                        child: SizedBox(
                          width: 30,
                          height: 30,
                          child: CircularProgressIndicator(
                            color: AppColors.primaryAccent,
                            strokeWidth: 2.6,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    ValueListenableBuilder<String>(
                      valueListenable: widget.stageListenable,
                      builder: (context, stage, child) {
                        final data = _stageData(stage);
                        return AnimatedSwitcher(
                          duration: const Duration(milliseconds: 190),
                          switchInCurve: Curves.easeOutCubic,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) {
                            return FadeTransition(
                              opacity: animation,
                              child: child,
                            );
                          },
                          layoutBuilder: (currentChild, previousChildren) {
                            return AnimatedSize(
                              duration: const Duration(milliseconds: 190),
                              curve: Curves.easeOutCubic,
                              alignment: Alignment.topCenter,
                              child: currentChild ?? const SizedBox.shrink(),
                            );
                          },
                          child: Column(
                            key: ValueKey(stage),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                data.title,
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  color: AppColors.textPrimary,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.2,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                data.subtitle,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.textMuted.withValues(
                                    alpha: 0.72,
                                  ),
                                  fontSize: 13,
                                  height: 1.35,
                                ),
                              ),
                              const SizedBox(height: 24),
                              _ProgressSteps(stepStates: data.stepStates),
                              const SizedBox(height: 20),
                              Text(
                                data.footer,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: AppColors.textMuted.withValues(
                                    alpha: 0.72,
                                  ),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StageData {
  final String title;
  final String subtitle;
  final List<_ProgressStepState> stepStates;
  final String footer;

  const _StageData({
    required this.title,
    required this.subtitle,
    required this.stepStates,
    required this.footer,
  });
}

enum _ProgressStepState { pending, active, complete }

_StageData _stageData(String stage) {
  switch (stage) {
    case 'saving':
      return const _StageData(
        title: 'Securing your identity',
        subtitle: 'Saving your identity to secure storage.',
        stepStates: [_ProgressStepState.complete, _ProgressStepState.active],
        footer: 'Almost there.',
      );
    case 'generating_keys':
    default:
      return const _StageData(
        title: 'Creating your secure identity',
        subtitle:
            'Generating encryption keys on this device. This only happens once.',
        stepStates: [_ProgressStepState.active, _ProgressStepState.pending],
        footer: 'Please keep the app open.',
      );
  }
}

class _ProgressSteps extends StatelessWidget {
  final List<_ProgressStepState> stepStates;

  const _ProgressSteps({required this.stepStates});

  @override
  Widget build(BuildContext context) {
    const labels = ['Generate keys', 'Save to device'];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: List<Widget>.generate(labels.length, (index) {
        return Padding(
          padding: EdgeInsets.only(bottom: index == labels.length - 1 ? 0 : 14),
          child: Row(
            children: [
              _ProgressStepIndicator(
                stepIndex: index,
                state: stepStates[index],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  labels[index],
                  style: TextStyle(
                    color: _stepTextColor(stepStates[index]),
                    fontSize: 14,
                    fontWeight: stepStates[index] == _ProgressStepState.pending
                        ? FontWeight.w400
                        : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  Color _stepTextColor(_ProgressStepState state) {
    switch (state) {
      case _ProgressStepState.complete:
        return AppColors.textPrimary;
      case _ProgressStepState.active:
        return AppColors.textPrimary;
      case _ProgressStepState.pending:
        return AppColors.textMuted.withValues(alpha: 0.68);
    }
  }
}

class _ProgressStepIndicator extends StatelessWidget {
  final int stepIndex;
  final _ProgressStepState state;

  const _ProgressStepIndicator({required this.stepIndex, required this.state});

  @override
  Widget build(BuildContext context) {
    final key = ValueKey('identity-progress-step-$stepIndex-${state.name}');

    switch (state) {
      case _ProgressStepState.complete:
        return Container(
          key: key,
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: AppColors.primaryAccent.withValues(alpha: 0.18),
          ),
          child: const Icon(
            Icons.check_rounded,
            size: 14,
            color: AppColors.primaryAccent,
          ),
        );
      case _ProgressStepState.active:
        return Container(
          key: key,
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: AppColors.primaryAccent.withValues(alpha: 0.8),
            ),
          ),
          child: Center(
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primaryAccent,
              ),
            ),
          ),
        );
      case _ProgressStepState.pending:
        return Container(
          key: key,
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          ),
        );
    }
  }
}
