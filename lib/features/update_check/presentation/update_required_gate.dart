import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/core/theme/app_colors.dart';
import 'package:flutter_app/features/call/application/foreground_call_capability.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

import '../application/update_check_controller.dart';
import '../domain/update_check_models.dart';
import 'update_copy.dart';
import 'update_required_back_guard.dart';
import 'update_store_launcher.dart';

/// Gives the Orbit banner (T2b) the shared [UpdateCheckController].
class UpdateCheckScope extends InheritedNotifier<UpdateCheckController> {
  const UpdateCheckScope({
    super.key,
    required UpdateCheckController controller,
    required super.child,
  }) : super(notifier: controller);

  static UpdateCheckController? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<UpdateCheckScope>()?.notifier;
}

/// The SE-41 hard overlay (T2a), mounted in `MaterialApp.builder` around the
/// app content and inside `ForegroundCallOverlay`.
///
/// Because it sits above the navigator, it covers every route: home, pushed
/// routes, and deep-link and notification routes alike. A live call surface
/// is a later layer of `ForegroundCallOverlay`, so the overlay can never
/// cover it. It is also not shown while a call is incoming, outgoing or
/// active, and comes back when the call ends.
///
/// The overlay is modal to touch, focus, accessibility and Back: the content
/// behind it gets [ExcludeFocus] and the overlay gets [BlockSemantics], the
/// same as the call surface. Blocking at the builder level also hides the
/// push-registration warning from the semantics tree. That warning keeps its
/// own route-level blocking inside the navigator so it stays reachable over
/// routes, but nothing in the app is usable while this overlay shows, so
/// hiding it here is intended.
class UpdateRequiredGate extends StatefulWidget {
  const UpdateRequiredGate({
    super.key,
    required this.controller,
    required this.callCapability,
    required this.child,
    this.backGuard,
    this.launchStore = launchUpdateStore,
  });

  final UpdateCheckController controller;
  final ForegroundCallCapability? callCapability;
  final UpdateRequiredBackGuard? backGuard;
  final UpdateStoreLauncher launchStore;
  final Widget child;

  @override
  State<UpdateRequiredGate> createState() => _UpdateRequiredGateState();
}

class _UpdateRequiredGateState extends State<UpdateRequiredGate>
    with WidgetsBindingObserver {
  StreamSubscription<ForegroundCallProjection?>? _callSubscription;
  bool _callLive = false;
  bool _navigatorCanHandlePop = false;
  bool _publishedBlocking = false;
  bool _storeLaunchFailed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _bindCall();
    // Never on the startup path: the first check runs after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.controller.start();
    });
  }

  @override
  void didUpdateWidget(covariant UpdateRequiredGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.callCapability, widget.callCapability)) {
      _bindCall();
    }
    if (!identical(oldWidget.backGuard, widget.backGuard)) {
      oldWidget.backGuard?.blocking = false;
    }
    if (!identical(oldWidget.controller, widget.controller)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.controller.start();
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_callSubscription?.cancel());
    widget.backGuard?.blocking = false;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(widget.controller.onResumed());
    }
  }

  void _bindCall() {
    unawaited(_callSubscription?.cancel());
    _callSubscription = null;
    final capability = widget.callCapability;
    ForegroundCallProjection? current;
    try {
      current = capability?.current;
    } catch (_) {
      current = null;
    }
    _callLive = _isLive(current);
    if (capability == null) return;
    try {
      _callSubscription = capability.changes.listen(
        (projection) => _setCallLive(_isLive(projection)),
        onError: (Object _) => _setCallLive(false),
        onDone: () => _setCallLive(false),
      );
    } catch (_) {
      _callLive = false;
    }
  }

  void _setCallLive(bool live) {
    if (!mounted || live == _callLive) return;
    setState(() => _callLive = live);
  }

  /// Incoming (validated or not), outgoing and active calls. An ended call
  /// shows only an informational notice, so the overlay may come back.
  static bool _isLive(ForegroundCallProjection? projection) {
    final session = projection?.session;
    return session != null && !session.isIdle && !session.isTerminal;
  }

  @override
  Widget build(BuildContext context) {
    return UpdateCheckScope(
      controller: widget.controller,
      child: ValueListenableBuilder<UpdateDecision>(
        valueListenable: widget.controller,
        builder: (context, decision, _) {
          final hard = decision is UpdateDecisionHard && !_callLive
              ? decision
              : null;
          final blocking = hard != null;
          widget.backGuard?.blocking = blocking;
          _publishFrameworkHandlesBack(blocking);
          return Stack(
            fit: StackFit.expand,
            children: <Widget>[
              ExcludeFocus(
                excluding: blocking,
                child: NotificationListener<NavigationNotification>(
                  // While blocking, the hidden navigator's "cannot pop" at its
                  // root route must not reach the engine; Android would then
                  // let Back close the task. Its last value is replayed when
                  // the overlay clears.
                  onNotification: (notification) {
                    _navigatorCanHandlePop = notification.canHandlePop;
                    return _publishedBlocking;
                  },
                  child: widget.child,
                ),
              ),
              if (hard != null)
                Positioned.fill(
                  child: BlockSemantics(
                    child: UpdateRequiredScreen(
                      decision: hard,
                      installedBuildNumber:
                          widget.controller.installedBuildNumber,
                      onUpdate: _onUpdate,
                      storeLaunchFailed: _storeLaunchFailed,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _onUpdate() async {
    var opened = false;
    try {
      opened = await widget.launchStore(
        updateStoreUrlForPlatform(widget.controller.platform),
      );
    } catch (_) {
      // A platform refusal keeps the required gate and its retry button active.
    }
    if (mounted) setState(() => _storeLaunchFailed = !opened);
  }

  void _publishFrameworkHandlesBack(bool blocking) {
    if (_publishedBlocking == blocking) return;
    _publishedBlocking = blocking;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _publishedBlocking != blocking) return;
      NavigationNotification(
        canHandlePop: blocking || _navigatorCanHandlePop,
      ).dispatch(context);
    });
  }
}

/// The blocking "update required" screen. No close button; the only action
/// opens the store.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({
    super.key,
    required this.decision,
    required this.installedBuildNumber,
    required this.onUpdate,
    this.storeLaunchFailed = false,
  });

  final UpdateDecisionHard decision;
  final String? installedBuildNumber;
  final VoidCallback onUpdate;
  final bool storeLaunchFailed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final installed = installedBuildNumber;
    return Material(
      key: const ValueKey('update-required-overlay'),
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Icon(
                    Icons.system_update_rounded,
                    size: 56,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(height: 24),
                  Semantics(
                    header: true,
                    child: Text(
                      l10n.update_required_title,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    updateRequiredBody(l10n, decision.reasonCode),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 20),
                  if (installed != null)
                    Text(
                      l10n.update_required_installed_build(installed),
                      key: const ValueKey('update-required-installed'),
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    ),
                  Text(
                    l10n.update_required_minimum_build(
                      decision.minBuild.toString(),
                    ),
                    key: const ValueKey('update-required-minimum'),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (storeLaunchFailed)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Text(
                        l10n.update_required_store_failed,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      key: const ValueKey('update-required-button'),
                      // Keyboard focus moves into the overlay, so Tab starts
                      // here; nothing behind it can take focus.
                      autofocus: true,
                      onPressed: onUpdate,
                      // Large text sizes wrap the label; keep it centred and
                      // clear of the rounded ends. Black on the green passes
                      // WCAG AA; white on it would not.
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primaryAccent,
                        foregroundColor: AppColors.background,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                      ),
                      child: Text(
                        l10n.update_required_button,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
