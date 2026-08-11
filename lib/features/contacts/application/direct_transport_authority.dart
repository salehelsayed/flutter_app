import 'package:sqflite_sqlcipher/sqflite.dart';

import 'package:flutter_app/core/database/helpers/direct_contact_device_bindings_db_helpers.dart';

export 'package:flutter_app/core/database/helpers/direct_contact_device_bindings_db_helpers.dart'
    show
        DirectTransportAuthorityKind,
        DirectTransportAuthorityResolution,
        dbResolveDirectTransportToLogicalContact;

/// Plan 361: the ONE shared reverse authority from an authenticated physical
/// transport peer to at most one current logical contact/account.
///
/// Receive paths resolve BEFORE decrypt (so incumbent per-kind blocked policy
/// can apply) and every durable apply re-runs the same resolution inside its
/// own SQL transaction through the DB helper.
abstract interface class DirectTransportAuthorityResolver {
  Future<DirectTransportAuthorityResolution> resolveDirectTransportAuthority(
    String transportPeerId,
  );
}

/// Database-backed production resolver.
class DatabaseDirectTransportAuthority
    implements DirectTransportAuthorityResolver {
  const DatabaseDirectTransportAuthority({required this.database});

  final Database database;

  @override
  Future<DirectTransportAuthorityResolution> resolveDirectTransportAuthority(
    String transportPeerId,
  ) => dbResolveDirectTransportToLogicalContact(
    database,
    transportPeerId: transportPeerId,
  );
}
