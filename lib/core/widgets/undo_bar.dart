import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

typedef UndoBarCommit = FutureOr<void> Function();

/// A single-resolution handle for a visible undo window.
///
/// [cancel] is callback-free: owning screens use it from `dispose` so an
/// unmounted surface neither commits nor tries to restore UI.
class UndoBarHandle {
  UndoBarHandle._({
    required Duration window,
    required VoidCallback onUndo,
    required UndoBarCommit onCommit,
  }) : _window = window,
       _onUndo = onUndo,
       _onCommit = onCommit;

  final Duration _window;
  final VoidCallback _onUndo;
  final UndoBarCommit _onCommit;

  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _controller;
  Timer? _timer;
  bool _resolved = false;

  bool get isActive => !_resolved;

  void _attach(
    ScaffoldFeatureController<SnackBar, SnackBarClosedReason> controller,
  ) {
    _controller = controller;
  }

  void _startVisibleWindow() {
    if (_resolved || _timer != null) return;
    _timer = Timer(_window, _commit);
  }

  void undo() {
    if (!_resolve()) return;
    _controller?.close();
    _onUndo();
  }

  void cancel() {
    if (!_resolve()) return;
    _controller?.close();
  }

  void _commit() {
    if (!_resolve()) return;
    _controller?.close();
    unawaited(Future<void>.sync(_onCommit));
  }

  bool _resolve() {
    if (_resolved) return false;
    _resolved = true;
    _timer?.cancel();
    _timer = null;
    return true;
  }
}

/// Visual content for the shared reversible-action bar.
class UndoBar extends StatelessWidget {
  const UndoBar({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.person_remove_outlined, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(message)),
      ],
    );
  }
}

/// Shows the standardized reversible-action bar.
///
/// The commit timer starts when the bar becomes visible, and the SnackBar's
/// own duration is the exact same [window]. A visible Undo action therefore
/// never outlives its authority.
UndoBarHandle showUndoBar(
  BuildContext context, {
  required String message,
  required Duration window,
  required VoidCallback onUndo,
  required UndoBarCommit onCommit,
}) {
  assert(window > Duration.zero);
  final messenger = ScaffoldMessenger.of(context);
  final scheme = Theme.of(context).colorScheme;
  final l10n = AppLocalizations.of(context)!;
  // Undo authority must be the active controller, never a queued snackbar
  // behind stale feedback. This also makes owner disposal safe because the
  // returned controller is the messenger's current first entry.
  messenger.removeCurrentSnackBar();
  late final UndoBarHandle handle;
  handle = UndoBarHandle._(window: window, onUndo: onUndo, onCommit: onCommit);
  final controller = messenger.showSnackBar(
    SnackBar(
      key: const ValueKey('undo-bar'),
      content: UndoBar(message: message),
      action: SnackBarAction(
        label: l10n.feed_undo,
        textColor: scheme.primaryContainer,
        onPressed: handle.undo,
      ),
      behavior: SnackBarBehavior.floating,
      duration: window,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      onVisible: handle._startVisibleWindow,
    ),
  );
  handle._attach(controller);
  return handle;
}
