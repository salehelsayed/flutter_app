/// User preference for the shared app background.
///
enum BackgroundPreference {
  defaultBackground,
  cosmic,
  cosmicMirrored,
  daylightLagoon;

  /// Key used in SecureKeyStore for the app background preference.
  static const storageKey = 'background_preference';

  String toStorageString() {
    switch (this) {
      case BackgroundPreference.defaultBackground:
        return 'default';
      case BackgroundPreference.cosmic:
        return 'cosmic';
      case BackgroundPreference.cosmicMirrored:
        return 'cosmic_mirrored';
      case BackgroundPreference.daylightLagoon:
        return 'daylight_lagoon';
    }
  }

  /// Parses a storage string. Returns [defaultBackground] for null or unknown values.
  static BackgroundPreference fromStorageString(String? value) {
    if (value == 'default') {
      return BackgroundPreference.defaultBackground;
    }
    if (value == 'cosmic') {
      return BackgroundPreference.cosmic;
    }
    if (value == 'cosmic_mirrored') {
      return BackgroundPreference.cosmicMirrored;
    }
    if (value == 'daylight_lagoon') {
      return BackgroundPreference.daylightLagoon;
    }
    return BackgroundPreference.defaultBackground;
  }
}
