import 'package:flutter/material.dart';
import 'package:flutter_app/features/orbit/presentation/widgets/orbit_control_circle.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

/// The search control for opening the search dock: the shared
/// [OrbitControlCircle], with a Semantics button label and an opaque hit
/// square so the corners of the circle still tap.
class OrbitSearchTrigger extends StatelessWidget {
  final VoidCallback onSearchTap;

  const OrbitSearchTrigger({super.key, required this.onSearchTap});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      button: true,
      label: AppLocalizations.of(context)!.orbit_search_trigger_semantics,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onSearchTap,
        child: const OrbitControlCircle(icon: Icons.search),
      ),
    );
  }
}
