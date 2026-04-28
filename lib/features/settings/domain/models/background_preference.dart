/// User preference for the shared app background.
///
/// Only the existing default background is user-facing today. Additional real
/// background options can be added here when their artwork and readability
/// acceptance are defined.
enum BackgroundPreference {
  defaultBackground;

  /// Key used in SecureKeyStore for the app background preference.
  static const storageKey = 'background_preference';

  String toStorageString() {
    switch (this) {
      case BackgroundPreference.defaultBackground:
        return 'default';
    }
  }

  /// Parses a storage string. Returns [defaultBackground] for null or unknown values.
  static BackgroundPreference fromStorageString(String? value) {
    if (value == 'default') {
      return BackgroundPreference.defaultBackground;
    }
    return BackgroundPreference.defaultBackground;
  }
}
