import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Exact-profile UI seam for the physical iOS suspension proof.
///
/// Labels come only from the durable TC-269 controller state. In particular,
/// an incoming parent message is unable to create a visible proof label.
class GroupMediaIosBackgroundE2EOverlay extends StatelessWidget {
  const GroupMediaIosBackgroundE2EOverlay({
    required this.labels,
    required this.child,
    super.key,
  });

  final ValueListenable<List<String>> labels;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<String>>(
      valueListenable: labels,
      builder: (context, values, child) {
        if (values.isEmpty) return child!;
        return Stack(
          fit: StackFit.expand,
          children: <Widget>[
            child!,
            Positioned(
              left: 8,
              right: 8,
              top: 8,
              child: SafeArea(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    for (final label in values)
                      Semantics(
                        key: ValueKey<String>('p269-ios-proof-$label'),
                        container: true,
                        label: label,
                        child: ExcludeSemantics(child: Text(label)),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
      child: child,
    );
  }
}
