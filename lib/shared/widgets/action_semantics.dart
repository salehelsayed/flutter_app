import 'package:flutter/material.dart';

/// Names an existing control without adding a second activation handler.
class ActionSemantics extends StatelessWidget {
  const ActionSemantics({
    super.key,
    required this.label,
    required this.enabled,
    required this.child,
    this.identifier,
  });

  final String label;
  final bool enabled;
  final Widget child;

  /// Stable automation id (Android resource-id, iOS accessibilityIdentifier).
  /// When set, the control is its own semantics node so the id cannot be
  /// absorbed by an ancestor.
  final String? identifier;

  @override
  Widget build(BuildContext context) => Semantics(
    container: identifier != null,
    identifier: identifier,
    button: true,
    enabled: enabled,
    label: label,
    child: Tooltip(message: label, excludeFromSemantics: true, child: child),
  );
}
