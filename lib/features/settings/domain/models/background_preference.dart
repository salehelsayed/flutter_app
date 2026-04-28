/// User preference for the shared app background.
///
enum BackgroundPreference {
  defaultBackground,
  cosmic;

  /// Key used in SecureKeyStore for the app background preference.
  static const storageKey = 'background_preference';

  String toStorageString() {
    switch (this) {
      case BackgroundPreference.defaultBackground:
        return 'default';
      case BackgroundPreference.cosmic:
        return 'cosmic';
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
    return BackgroundPreference.defaultBackground;
  }
}
