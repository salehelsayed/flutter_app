import '../../../core/services/p2p_service.dart';
import '../../../core/utils/flow_event_emitter.dart';
import '../../../core/utils/key_conversion.dart';
import '../../account_migration/application/account_migration_runtime_network_gate.dart';
import '../../identity/application/linked_installation_authority.dart';
import '../../identity/domain/repositories/identity_repository.dart';

/// Result of starting the P2P node.
enum StartNodeResult {
  /// Node started successfully.
  success,

  /// No identity found - cannot start node.
  noIdentity,

  /// Bridge or P2P layer error.
  bridgeError,

  /// Connection error (relay unavailable, etc).
  connectionError,

  /// Account migration authority blocks runtime network side effects.
  accountMigrationBlocked,

  /// 360: persisted linked-device authority is partial, corrupt,
  /// cross-account, or otherwise unusable.
  ///
  /// This is deliberately DISTINCT from [bridgeError]. It means the node was
  /// never asked to start at all. Collapsing it into a generic failure would
  /// invite a caller to "retry", and the only safe retry for a half-written
  /// linked credential is finishing or resetting setup — never falling back to
  /// the account transport.
  linkedAuthorityRefused,
}

/// Use case for starting the P2P node.
///
/// This use case:
/// 1. Loads the user's identity from the repository
/// 2. Starts the P2P node with the identity's private key
/// 3. Auto-registers on rendezvous for discoverability
///
/// 360: [linkedAuthority] splits LOGICAL ACCOUNT identity from TRANSPORT
/// identity on a linked secondary. The account-migration network gate keeps
/// receiving the logical account peer — migration authority is an account-level
/// fact and must not be evaluated against a per-device transport — while the
/// bridge receives the credential's transport private key and peer.
///
/// Passing null (every ordinary primary call site) preserves the incumbent
/// path byte-for-byte: one identity, one peer, one gate call.
Future<StartNodeResult> startP2PNode({
  required IdentityRepository identityRepo,
  required P2PService p2pService,
  AccountMigrationNetworkGate accountMigrationNetworkGate =
      allowAccountMigrationNetworkSideEffects,
  LinkedInstallationAuthoritySnapshot? linkedAuthority,
}) async {
  emitFlowEvent(
    layer: 'FL',
    event: 'P2P_START_NODE_USE_CASE_BEGIN',
    details: {},
  );

  try {
    // Load identity from repository
    final identity = await identityRepo.loadIdentity();

    if (identity == null) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_START_NODE_USE_CASE_NO_IDENTITY',
        details: {},
      );
      return StartNodeResult.noIdentity;
    }

    // 360: resolve which key/peer pair the bridge gets, and refuse outright on
    // any partial or crossed linked authority. This happens BEFORE the network
    // gate so a fail-closed installation performs no account-scoped work.
    var transportPrivateKey = identity.privateKey;
    var transportPeerId = identity.peerId;
    if (linkedAuthority != null && !linkedAuthority.isOrdinaryPrimary) {
      if (linkedAuthority.refusesStartup) {
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_START_NODE_USE_CASE_LINKED_AUTHORITY_REFUSED',
          details: {
            'disposition': linkedAuthority.disposition.name,
            if (linkedAuthority.failClosedReason != null)
              'reason': linkedAuthority.failClosedReason,
          },
        );
        return StartNodeResult.linkedAuthorityRefused;
      }
      final credential = linkedAuthority.credential;
      if (credential == null ||
          credential.accountPeerId != identity.peerId.trim()) {
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_START_NODE_USE_CASE_LINKED_ACCOUNT_MISMATCH',
          details: {},
        );
        return StartNodeResult.linkedAuthorityRefused;
      }
      // Offline key->peer proof for BOTH identities before any node start.
      // The account half is checked too: a linked installation whose stored
      // account key no longer derives its own account peer cannot be trusted
      // to name the right logical owner in a QR the contact will bind to.
      if (!ed25519PublicKeyMatchesPeerId(
            base64PublicKey: identity.publicKey,
            claimedPeerId: identity.peerId,
          ) ||
          !ed25519PublicKeyMatchesPeerId(
            base64PublicKey: credential.transportPublicKey,
            claimedPeerId: credential.transportPeerId,
          )) {
        emitFlowEvent(
          layer: 'FL',
          event: 'P2P_START_NODE_USE_CASE_LINKED_PEER_DERIVATION_MISMATCH',
          details: {},
        );
        return StartNodeResult.linkedAuthorityRefused;
      }
      transportPrivateKey = credential.transportPrivateKey;
      transportPeerId = credential.transportPeerId;
    }

    // The gate always sees the LOGICAL account peer, never the transport peer.
    final migrationAllowsNetwork = await accountMigrationNetworkGate(
      peerId: identity.peerId,
      operation: 'p2p_start',
    );
    if (!migrationAllowsNetwork) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_START_NODE_USE_CASE_ACCOUNT_MIGRATION_BLOCKED',
        details: {'peerId': identity.peerId},
      );
      return StartNodeResult.accountMigrationBlocked;
    }

    // Start the P2P node
    // The service handles key conversion (BASE64 -> HEX) internally.
    // `startNode` retains its incumbent `autoRegister: true` contract, so the
    // renewable personal-rendezvous loop is preserved rather than replaced by
    // a one-shot registration.
    final success = await p2pService.startNode(
      transportPrivateKey,
      transportPeerId,
    );

    if (success) {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_START_NODE_USE_CASE_SUCCESS',
        details: {'peerId': transportPeerId},
      );
      return StartNodeResult.success;
    } else {
      emitFlowEvent(
        layer: 'FL',
        event: 'P2P_START_NODE_USE_CASE_BRIDGE_ERROR',
        details: {},
      );
      return StartNodeResult.bridgeError;
    }
  } catch (e) {
    emitFlowEvent(
      layer: 'FL',
      event: 'P2P_START_NODE_USE_CASE_EXCEPTION',
      details: {'error': e.toString()},
    );
    return StartNodeResult.bridgeError;
  }
}
