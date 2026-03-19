import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_app/l10n/app_localizations.dart';

class PostsNearbySettingsCard extends StatelessWidget {
  final bool sharingEnabled;
  final ValueChanged<bool> onChanged;

  const PostsNearbySettingsCard({
    super.key,
    required this.sharingEnabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color.fromRGBO(255, 255, 255, 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: const Color.fromRGBO(255, 255, 255, 0.1),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppLocalizations.of(context)!.settings_share_nearby,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        sharingEnabled ? AppLocalizations.of(context)!.settings_share_nearby_on : AppLocalizations.of(context)!.settings_share_nearby_off,
                        style: const TextStyle(
                          color: Color.fromRGBO(255, 255, 255, 0.7),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        AppLocalizations.of(context)!.settings_share_nearby_desc,
                        style: const TextStyle(
                          color: Color.fromRGBO(255, 255, 255, 0.45),
                          fontSize: 12,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Switch.adaptive(value: sharingEnabled, onChanged: onChanged),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
