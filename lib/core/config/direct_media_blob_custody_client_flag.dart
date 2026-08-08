/// Default-off client adoption selector for prepared ordinary-direct media.
///
/// Plan 347 proves the strict path only for an explicitly upgraded test pair.
/// Production builds omit this define and therefore retain the legacy path.
const bool kDirectMediaBlobCustodyClientEnabled = bool.fromEnvironment(
  'MKNOON_DIRECT_MEDIA_BLOB_CUSTODY_CLIENT_ENABLED',
  defaultValue: false,
);
