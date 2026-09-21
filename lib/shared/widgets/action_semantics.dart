import 'package:flutter/material.dart';

/// Names an existing control without adding a second activation handler.
class ActionSemantics extends StatelessWidget {
  const ActionSemantics({
    super.key,
    required this.label,
    required this.enabled,
    required this.child,
  });

  final String label;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    enabled: enabled,
    label: label,
    child: Tooltip(message: label, excludeFromSemantics: true, child: child),
  );
}
