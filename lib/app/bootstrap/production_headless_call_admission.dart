import 'package:flutter_app/core/bridge/go_bridge_client.dart';
import 'package:flutter_app/core/bridge/p2p_bridge_client.dart';
import 'package:flutter_app/core/database/app_database_version.dart';
import 'package:flutter_app/core/database/encrypted_db_opener.dart';
import 'package:flutter_app/core/database/helpers/identity_db_helpers.dart';
import 'package:flutter_app/core/database/legacy_push_transport_repair.dart';
import 'package:flutter_app/core/database/migrations/005_secret_null_checks.dart';
import 'package:flutter_app/core/database/migrations/107_direct_notification_durability.dart';
import 'package:flutter_app/core/database/production_migration_registry.dart';
import 'package:flutter_app/core/notifications/canonical_runtime_lease.dart';
import 'package:flutter_app/core/secure_storage/flutter_secure_key_store.dart';
import 'package:flutter_app/core/secure_storage/legacy_group_secret_storage_scrub.dart';
import 'package:flutter_app/core/secure_storage/migrate_secrets_to_secure_storage.dart';
import 'package:flutter_app/core/secure_storage/secure_key_store.dart';
import 'package:flutter_app/core/utils/key_conversion.dart';
import 'package:flutter_app/features/account_migration/application/account_migration_authority_repository_impl.dart';
import 'package:flutter_app/features/account_migration/domain/models/account_migration_authority_state.dart';
import 'package:flutter_app/features/call/application/incoming_call_pre_presentation_admission.dart';
import 'package:flutter_app/features/call/domain/call_signal.dart';
import 'package:flutter_app/features/call/infrastructure/call_mailbox_client.dart';
import 'package:flutter_app/features/call/infrastructure/call_trusted_roster_provider.dart';
import 'package:flutter_app/features/call/infrastructure/headless_call_admission_entrypoint.dart';
import 'package:flutter_app/features/call/infrastructure/secure_call_envelope_codec.dart';
import 'package:flutter_app/features/identity/application/linked_installation_authority.dart';
import 'package:flutter_app/features/identity/data/repositories/identity_repository_impl.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

final class HeadlessAuthenticatedMailboxEvent {
  const HeadlessAuthenticatedMailboxEvent({
    required this.event,
    required void Function() rollbackReplay,
  }) : _rollbackReplay = rollbackReplay;

  final CallSignalType event;
  final void Function() _rollbackReplay;

  void rollbackReplay() => _rollbackReplay();

  @override
  String toString() => 'HeadlessAuthenticatedMailboxEvent(redacted)';
}

typedef AuthenticateHeadlessMailboxEvent =
    Future<HeadlessAuthenticatedMailboxEvent> Function({
      required HeadlessCallAdmissionInvocation invocation,
      required CallMailboxEvent event,
    });

/// Evaluates one exact-handle mailbox page without dispatching coordinator
/// events, acknowledging custody, or starting media. All provisional replay
/// reservations are rolled back so the foreground canonical owner can
/// authenticate and consume the same rows after native presentation.
final class MailboxProductionHeadlessCallAdmissionSession
    implements ProductionHeadlessCallAdmissionSession {
  MailboxProductionHeadlessCallAdmissionSession({
    required CallMailboxClient mailboxClient,
    required AuthenticateHeadlessMailboxEvent authenticateEvent,
    required Future<HeadlessCallAdmissionCleanup> Function() closeResources,
  }) : _mailboxClient = mailboxClient,
       _authenticateEvent = authenticateEvent,
       _closeResources = closeResources;

  final CallMailboxClient _mailboxClient;
  final AuthenticateHeadlessMailboxEvent _authenticateEvent;
  final Future<HeadlessCallAdmissionCleanup> Function() _closeResources;
  Future<HeadlessCallAdmissionDisposition>? _evaluation;
  Future<HeadlessCallAdmissionCleanup>? _cleanup;

  @override
  Future<HeadlessCallAdmissionDisposition> evaluate(
    HeadlessCallAdmissionInvocation invocation,
  ) => _evaluation ??= _evaluateOnce(invocation);

  Future<HeadlessCallAdmissionDisposition> _evaluateOnce(
    HeadlessCallAdmissionInvocation invocation,
  ) async {
    late final CallMailboxRetrieveResult page;
    try {
      page = await _mailboxClient.retrieve(
        callHandle: invocation.callId,
        limit: BridgeCallMailboxClient.maxRetrieveEvents,
      );
    } catch (_) {
      return HeadlessCallAdmissionDisposition.deferred;
    }
    if (page.hasMore) return HeadlessCallAdmissionDisposition.deferred;
    if (page.events.isEmpty) {
      return HeadlessCallAdmissionDisposition.emptyOrAlreadyAcked;
    }

    final reservations = <HeadlessAuthenticatedMailboxEvent>[];
    try {
      for (final event in page.events) {
        reservations.add(
          await _authenticateEvent(invocation: invocation, event: event),
        );
      }
      if (
        reservations.any(
          (entry) =>
              entry.event == CallSignalType.reject ||
              entry.event == CallSignalType.terminate,
        )
      ) {
        return HeadlessCallAdmissionDisposition.terminal;
      }
      if (
        reservations.length == 1 &&
        reservations.single.event == CallSignalType.invite
      ) {
        return HeadlessCallAdmissionDisposition.admitted;
      }
      return HeadlessCallAdmissionDisposition.permanentReject;
    } on IncomingCallPrePresentationAdmissionException catch (error) {
      return switch (error.code) {
        IncomingCallPrePresentationAdmissionFailureCode.deferred =>
          HeadlessCallAdmissionDisposition.deferred,
        IncomingCallPrePresentationAdmissionFailureCode.duplicate ||
        IncomingCallPrePresentationAdmissionFailureCode.permanentReject =>
          HeadlessCallAdmissionDisposition.permanentReject,
      };
    } catch (_) {
      return HeadlessCallAdmissionDisposition.deferred;
    } finally {
      for (final reservation in reservations.reversed) {
        reservation.rollbackReplay();
      }
    }
  }

  @override
  Future<HeadlessCallAdmissionCleanup> close() =>
      _cleanup ??= _closeResources();
}

abstract interface class ProductionHeadlessCallAdmissionSession {
  Future<HeadlessCallAdmissionDisposition> evaluate(
    HeadlessCallAdmissionInvocation invocation,
  );

  Future<HeadlessCallAdmissionCleanup> close();
}

abstract interface class ProductionHeadlessCallAdmissionBackend {
  Future<ProductionHeadlessCallAdmissionSession?> acquire(
    HeadlessCallAdmissionInvocation invocation,
  );

  Future<HeadlessCallAdmissionCleanup> emergencyCleanup();
}

/// Owns the bounded admission run and turns every acquisition, expiry, stop,
/// evaluation, or teardown uncertainty into a no-presentation disposition.
final class ProductionHeadlessCallAdmissionRunner {
  ProductionHeadlessCallAdmissionRunner({
    required ProductionHeadlessCallAdmissionBackend backend,
    int Function()? nowMs,
  }) : _backend = backend,
       _nowMs = nowMs ??
           (() => DateTime.now().toUtc().millisecondsSinceEpoch);

  static const int maximumFutureLifetimeMs = 45 * 1000;

  final ProductionHeadlessCallAdmissionBackend _backend;
  final int Function() _nowMs;

  Future<HeadlessCallAdmissionRunReport> run({
    required HeadlessCallAdmissionInvocation invocation,
    required bool Function() isStopRequested,
  }) async {
    try {
      final now = _nowMs();
      if (isStopRequested() ||
          now < 0 ||
          invocation.expiresAtMs <= now ||
          invocation.expiresAtMs - now > maximumFutureLifetimeMs) {
        return _deferred(await _backend.emergencyCleanup());
      }
      final session = await _backend.acquire(invocation);
      if (session == null || isStopRequested()) {
        return _deferred(await _backend.emergencyCleanup());
      }
      final disposition = await session.evaluate(invocation);
      final cleanup = await session.close();
      if (!cleanup.databaseClosed || !cleanup.leaseReleased) {
        return _deferred(cleanup);
      }
      final completedAt = _nowMs();
      if (isStopRequested() ||
          completedAt < 0 ||
          completedAt >= invocation.expiresAtMs) {
        return _deferred(cleanup);
      }
      return HeadlessCallAdmissionRunReport(
        disposition: disposition,
        requiredPersistenceComplete:
            disposition != HeadlessCallAdmissionDisposition.deferred,
        databaseClosed: true,
        leaseReleased: true,
      );
    } catch (_) {
      HeadlessCallAdmissionCleanup cleanup;
      try {
        cleanup = await _backend.emergencyCleanup();
      } catch (_) {
        cleanup = const HeadlessCallAdmissionCleanup(
          databaseClosed: false,
          leaseReleased: false,
        );
      }
      return _deferred(cleanup);
    }
  }

  static HeadlessCallAdmissionRunReport _deferred(
    HeadlessCallAdmissionCleanup cleanup,
  ) => HeadlessCallAdmissionRunReport(
    disposition: HeadlessCallAdmissionDisposition.deferred,
    requiredPersistenceComplete: false,
    databaseClosed: cleanup.databaseClosed,
    leaseReleased: cleanup.leaseReleased,
  );
}

/// Android production owner for the one admission-only SQLCipher/Go runtime.
/// It starts no Flutter UI, notification owner, listener, coordinator, or
/// media graph. The exact mailbox row remains unacknowledged for foreground
/// canonical adoption.
final class AndroidProductionHeadlessCallAdmissionBackend
    implements ProductionHeadlessCallAdmissionBackend {
  AndroidProductionHeadlessCallAdmissionBackend({
    SecureKeyStore? secureKeyStore,
    CanonicalRuntimeLeaseGateway? leaseGateway,
  }) : _secureKeyStore = secureKeyStore ?? FlutterSecureKeyStore(),
       _writableSession = CanonicalWritableRuntimeSession(
         gateway: leaseGateway ?? MethodChannelCanonicalRuntimeLeaseGateway(),
       ) {
    _bindingCoordinator = CanonicalRuntimeBindingCoordinator(
      secureKeyStore: _secureKeyStore,
    );
    _migrationAuthority =
        SecureKeyStoreAccountMigrationAuthorityRepository(
          secureKeyStore: _secureKeyStore,
        );
    _linkedAuthority = LinkedInstallationAuthority(
      secureKeyStore: _secureKeyStore,
    );
  }

  final SecureKeyStore _secureKeyStore;
  final CanonicalWritableRuntimeSession _writableSession;
  late final CanonicalRuntimeBindingCoordinator _bindingCoordinator;
  late final SecureKeyStoreAccountMigrationAuthorityRepository
  _migrationAuthority;
  late final LinkedInstallationAuthority _linkedAuthority;
  Database? _database;
  GoBridgeClient? _bridge;
  MailboxProductionHeadlessCallAdmissionSession? _activeSession;
  Future<HeadlessCallAdmissionCleanup>? _cleanupInFlight;

  @override
  Future<ProductionHeadlessCallAdmissionSession?> acquire(
    HeadlessCallAdmissionInvocation invocation,
  ) async {
    if (_activeSession != null || _writableSession.hasWritableLease) {
      return null;
    }
    final binding = await _bindingCoordinator.readCurrentAccountBinding();
    if (binding == null) return null;
    final database = await _writableSession.acquireThenOpen<Database>(
      binding: binding,
      openDatabase: () => _openExistingDatabase(
        onOpened: (opened) => _database = opened,
      ),
      closeAfterOpenFailure: _closeCurrentDatabase,
      closeDatabaseOnRuntimeAttachFailure: (opened) async {
        if (opened.isOpen) await opened.close();
        return !opened.isOpen;
      },
    );
    _database = database;

    final identity = await loadPassiveIdentitySnapshot(
      dbLoadIdentityRow: () => dbLoadIdentityRow(database),
      secureKeyStore: _secureKeyStore,
    );
    if (identity == null ||
        identity.mlKemSecretKey?.trim().isNotEmpty != true ||
        await _bindingCoordinator.deriveExistingAccountBinding(
              identity.peerId,
            ) !=
            binding) {
      throw StateError('headless call authority is unavailable');
    }
    final migration = await _migrationAuthority.loadAuthority();
    if (migration != null &&
        (migration.isFailClosed ||
            !migration.allowsNormalStartup ||
            migration.state == AccountMigrationAuthorityState.noAccount ||
            (migration.accountPeerId?.trim().isNotEmpty == true &&
                migration.accountPeerId != identity.peerId))) {
      throw StateError('headless call migration authority refused');
    }
    final linked = await _linkedAuthority.load(
      expectedAccountPeerId: identity.peerId,
    );
    final physicalPeerId = selectNotificationCompletedOutcomePhysicalPeerId(
      accountPeerId: identity.peerId,
      accountPublicKey: identity.publicKey,
      authority: linked,
    );
    if (physicalPeerId == null || linked.refusesStartup) {
      throw StateError('headless call installation authority refused');
    }
    final physicalPrivateKey = linked.isActiveLinkedSecondary
        ? linked.credential!.transportPrivateKey
        : identity.privateKey;

    final bridge = GoBridgeClient();
    _bridge = bridge;
    await bridge.initialize();
    final started = await callP2PNodeStart(
      bridge,
      privateKeyHex: base64ToHex(physicalPrivateKey),
      relayAddresses: defaultRelayAddresses(),
      autoRegister: true,
      namespace: 'mknoon:chat:$physicalPeerId',
      featureFlags: defaultResilienceFeatureFlags(),
    );
    if (started['ok'] != true || started['peerId'] != physicalPeerId) {
      throw StateError('headless call transport did not start');
    }

    final admission = IncomingCallPrePresentationAdmission(
      codec: SecureCallEnvelopeCodec(
        crypto: BridgeCallEnvelopeCrypto(bridge: bridge),
        nowMs: () => DateTime.now().toUtc().millisecondsSinceEpoch,
      ),
      trustedRosterProvider: DatabaseCallTrustedRosterProvider(database),
      localAuthorityProvider: () async => CallLocalDeviceAuthority(
        accountPeerId: identity.peerId,
        devicePeerId: physicalPeerId,
        mlKemSecretKey: identity.mlKemSecretKey!,
      ),
    );
    final session = MailboxProductionHeadlessCallAdmissionSession(
      mailboxClient: BridgeCallMailboxClient(bridge: bridge),
      authenticateEvent: ({required invocation, required event}) async {
        final authenticated = await admission.authenticateMailboxEvent(
          nativeCallId: invocation.callId,
          wakeExpiresAtMs: invocation.expiresAtMs,
          event: event,
        );
        return HeadlessAuthenticatedMailboxEvent(
          event: authenticated.signal.event,
          rollbackReplay: authenticated.rollbackReplay,
        );
      },
      closeResources: _closeResources,
    );
    _activeSession = session;
    return session;
  }

  Future<Database> _openExistingDatabase({
    required void Function(Database database) onOpened,
  }) async {
    final database = await openEncryptedDatabase(
      secureKeyStore: _secureKeyStore,
      dbName: 'identity.db',
      version: currentIdentityDatabaseVersion,
      onCreate: runProductionOnCreate,
      onUpgrade: runProductionOnUpgrade,
      requireExisting: true,
      onOpened: onOpened,
    );
    await repairDirectNotificationDurabilityDeleteTriggers(database);
    await repairLegacyPushMessageTransports(database);
    await migrateSecretsToSecureStorage(
      db: database,
      secureKeyStore: _secureKeyStore,
    );
    await runSecretNullChecksMigration(database);
    await scrubLegacyGroupSecretsToSecureStorage(
      db: database,
      secureKeyStore: _secureKeyStore,
    );
    return database;
  }

  @override
  Future<HeadlessCallAdmissionCleanup> emergencyCleanup() =>
      _closeResources();

  Future<HeadlessCallAdmissionCleanup> _closeResources() {
    final inFlight = _cleanupInFlight;
    if (inFlight != null) return inFlight;
    late final Future<HeadlessCallAdmissionCleanup> attempt;
    attempt = _closeResourcesOnce().whenComplete(() {
      if (identical(_cleanupInFlight, attempt)) _cleanupInFlight = null;
    });
    _cleanupInFlight = attempt;
    return attempt;
  }

  Future<HeadlessCallAdmissionCleanup> _closeResourcesOnce() async {
    final bridge = _bridge;
    if (bridge != null && bridge.isInitialized) {
      try {
        await callP2PNodeStop(bridge);
      } catch (_) {
        // Native quiescence below remains the authoritative release fence.
      }
    }
    var runtimeQuiescent = !_writableSession.hasWritableLease;
    if (_writableSession.hasWritableLease) {
      try {
        runtimeQuiescent =
            await _writableSession.beginDrain() &&
            await _writableSession.awaitRuntimeQuiescence();
      } catch (_) {
        runtimeQuiescent = false;
      }
    }
    if (!runtimeQuiescent) return _lifecycleFacts();

    bridge?.dispose();
    _bridge = null;
    final databaseClosed = await _closeCurrentDatabase();
    var leaseReleased = !_writableSession.hasWritableLease;
    if (!leaseReleased) {
      try {
        leaseReleased = await _writableSession.releaseAfterDatabaseClose(
          databaseClosed: databaseClosed,
        );
      } catch (_) {
        leaseReleased = false;
      }
    }
    if (databaseClosed && leaseReleased) _activeSession = null;
    return HeadlessCallAdmissionCleanup(
      databaseClosed: databaseClosed,
      leaseReleased: leaseReleased,
    );
  }

  Future<bool> _closeCurrentDatabase() async {
    final database = _database;
    if (database == null) return true;
    try {
      if (database.isOpen) await database.close();
    } catch (_) {
      return false;
    }
    final closed = !database.isOpen;
    if (closed) _database = null;
    return closed;
  }

  HeadlessCallAdmissionCleanup _lifecycleFacts() =>
      HeadlessCallAdmissionCleanup(
        databaseClosed: _database?.isOpen != true,
        leaseReleased: !_writableSession.hasWritableLease,
      );
}

final AndroidProductionHeadlessCallAdmissionBackend
_productionHeadlessCallAdmissionBackend =
    AndroidProductionHeadlessCallAdmissionBackend();
final ProductionHeadlessCallAdmissionRunner
_productionHeadlessCallAdmissionRunner = ProductionHeadlessCallAdmissionRunner(
  backend: _productionHeadlessCallAdmissionBackend,
);

Future<HeadlessCallAdmissionRunReport> runProductionHeadlessCallAdmission({
  required HeadlessCallAdmissionInvocation invocation,
  required bool Function() isStopRequested,
}) => _productionHeadlessCallAdmissionRunner.run(
  invocation: invocation,
  isStopRequested: isStopRequested,
);

Future<HeadlessCallAdmissionCleanup>
cleanupProductionHeadlessCallAdmission() =>
    _productionHeadlessCallAdmissionBackend.emergencyCleanup();

Future<void> runProductionAndroidHeadlessCallAdmission(
  List<String> arguments,
) => runAndroidHeadlessCallAdmission(
  arguments,
  runAdmission: runProductionHeadlessCallAdmission,
  emergencyShutdown: cleanupProductionHeadlessCallAdmission,
);
