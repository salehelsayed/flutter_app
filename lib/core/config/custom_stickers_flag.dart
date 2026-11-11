/// Keeps custom-sticker authoring and library actions out of shipping builds
/// until the complete feature has passed its device acceptance checks.
///
/// Database schema and account-data cleanup must not depend on this flag.
const bool kCustomStickersEnabled = bool.fromEnvironment(
  'CUSTOM_STICKERS_ENABLED',
  defaultValue: false,
);
