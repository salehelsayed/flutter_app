import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/features/push/application/push_registration_health_notifier.dart';
import 'package:flutter_app/features/push/domain/push_registration_health.dart';
import 'package:flutter_app/features/push/presentation/widgets/push_registration_health_warning.dart';

const _dismissedReasonKey = 'push_registration_health_dismissed_reason_v1';

/// One app-shell owner. The Navigator keeps its parent while visibility changes.
class PushRegistrationHealthSurface extends StatefulWidget {
  const PushRegistrationHealthSurface({
    super.key,
    required this.healthListenable,
    required this.onRetry,
    required this.onOpenNotificationSettings,
    required this.child,
    this.dismissalStore,
  });

  final ValueListenable<PushRegistrationHealthViewModel> healthListenable;
  final VoidCallback onRetry;
  final VoidCallback onOpenNotificationSettings;
  final Widget child;
  final SecureKeyStore? dismissalStore;

  @override
  State<PushRegistrationHealthSurface> createState() =>
      _PushRegistrationHealthSurfaceState();
}

class _PushRegistrationHealthSurfaceState
    extends State<PushRegistrationHealthSurface> {
  String? _dismissedReason;
  PushRegistrationHealthReason? _lastReason;
  bool _loaded = false;
  bool _ignoreRestoredDismissal = false;
  Future<void> _writes = Future<void>.value();

  @override
  void initState() {
    super.initState();
    _lastReason =
        widget.healthListenable.value.reason ==
            PushRegistrationHealthReason.none
        ? null
        : widget.healthListenable.value.reason;
    widget.healthListenable.addListener(_healthChanged);
    unawaited(_restoreDismissal());
  }

  Future<void> _restoreDismissal() async {
    final store = widget.dismissalStore;
    String? reason;
    try {
      reason = await store?.read(_dismissedReasonKey);
    } catch (_) {
      // Storage failure must not prevent settings access.
    }
    if (!mounted || !identical(store, widget.dismissalStore)) return;
    setState(() {
      if (!_ignoreRestoredDismissal &&
          PushRegistrationHealthReason.values.any(
            (value) =>
                value != PushRegistrationHealthReason.none &&
                value.name == reason,
          )) {
        _dismissedReason = reason;
      }
      _loaded = true;
      _healthChanged();
    });
  }

  void _healthChanged() {
    final health = widget.healthListenable.value;
    final reason = health.reason;
    final knownReason = reason != PushRegistrationHealthReason.none;
    final reset =
        health.phase == PushRegistrationHealthPhase.healthy ||
        (health.phase == null && _lastReason != null) ||
        (knownReason &&
            ((_lastReason != null && _lastReason != reason) ||
                (_dismissedReason != null && _dismissedReason != reason.name)));
    if (reset) {
      _ignoreRestoredDismissal = true;
      if (!_loaded || _dismissedReason != null) {
        unawaited(_persistDismissal(null));
      }
      _dismissedReason = null;
    }
    if (knownReason) {
      _lastReason = reason;
    } else if (health.phase != PushRegistrationHealthPhase.checking) {
      _lastReason = null;
    }
  }

  Future<void> _persistDismissal(String? reason) {
    final store = widget.dismissalStore;
    return _writes = _writes.then((_) async {
      try {
        if (reason == null) {
          await store?.delete(_dismissedReasonKey);
        } else {
          await store?.write(_dismissedReasonKey, reason);
        }
      } catch (_) {
        // Keep the current-session dismissal even if persistence is unavailable.
      }
    });
  }

  void _dismiss() {
    final reason = widget.healthListenable.value.reason.name;
    setState(() => _dismissedReason = reason);
    unawaited(_persistDismissal(reason));
  }

  @override
  void didUpdateWidget(PushRegistrationHealthSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.healthListenable, widget.healthListenable)) {
      oldWidget.healthListenable.removeListener(_healthChanged);
      widget.healthListenable.addListener(_healthChanged);
      _healthChanged();
    }
    if (!identical(oldWidget.dismissalStore, widget.dismissalStore)) {
      _loaded = false;
      _dismissedReason = null;
      _ignoreRestoredDismissal = false;
      unawaited(_restoreDismissal());
    }
  }

  @override
  void dispose() {
    widget.healthListenable.removeListener(_healthChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    return Overlay.wrap(
      child: ValueListenableBuilder<PushRegistrationHealthViewModel>(
        valueListenable: widget.healthListenable,
        builder: (context, health, _) => LayoutBuilder(
          builder: (context, constraints) {
            final visible =
                _loaded &&
                health.warningVisible &&
                _dismissedReason != health.reason.name &&
                constraints.maxHeight >=
                    media.padding.top +
                        48 +
                        kToolbarHeight +
                        media.padding.bottom;
            return Column(
              key: const ValueKey('push-registration-health-surface'),
              children: [
                if (visible)
                  Material(
                    color: Theme.of(context).scaffoldBackgroundColor,
                    child: SafeArea(
                      bottom: false,
                      child: PushRegistrationHealthWarning(
                        healthListenable: widget.healthListenable,
                        onRetry: widget.onRetry,
                        onOpenNotificationSettings:
                            widget.onOpenNotificationSettings,
                        onDismiss: _dismiss,
                      ),
                    ),
                  ),
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: visible,
                    // Keep route-level BlockSemantics inside this boundary.
                    child: Semantics(container: true, child: widget.child),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
