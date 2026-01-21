import { generateIdentity } from '../identity/generate';
import { restoreIdentityFromMnemonic } from '../identity/restore';
import { IdentityJson } from '../types/identity';
import { emitFlowEvent } from '../utils/flow_events';

// Type definitions for bridge responses
interface SuccessResponse {
  ok: true;
  identity: IdentityJson;
}

interface ErrorResponse {
  ok: false;
  errorCode: 'INVALID_MNEMONIC' | 'INTERNAL_ERROR';
  errorMessage: string;
}

type BridgeResponse = SuccessResponse | ErrorResponse;

interface RestorePayload {
  mnemonic12: string;
}

// Handler registration function type
type HandlerFunction = (payload: unknown) => Promise<BridgeResponse>;

// Assume this registration function is provided by the bridge infrastructure
declare function registerHandler(cmd: string, handler: HandlerFunction): void;

/**
 * Handler for identity.generate command
 * Generates a new identity with fresh keypair and mnemonic
 */
async function handleIdentityGenerate(_payload: unknown): Promise<BridgeResponse> {
  emitFlowEvent({
    layer: 'JS',
    event: 'ID_JS_BRIDGE_IDENTITY_GENERATE_RECEIVED',
    details: {},
  });

  try {
    const identity = await generateIdentity();

    emitFlowEvent({
      layer: 'JS',
      event: 'ID_JS_BRIDGE_IDENTITY_GENERATE_SUCCESS',
      details: { peerId: identity.peerId },
    });

    return {
      ok: true,
      identity,
    };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error during identity generation';

    emitFlowEvent({
      layer: 'JS',
      event: 'ID_JS_BRIDGE_IDENTITY_GENERATE_ERROR',
      details: { errorCode: 'INTERNAL_ERROR', errorMessage },
    });

    return {
      ok: false,
      errorCode: 'INTERNAL_ERROR',
      errorMessage,
    };
  }
}

/**
 * Handler for identity.restore command
 * Restores identity from existing 12-word mnemonic
 */
async function handleIdentityRestore(payload: unknown): Promise<BridgeResponse> {
  emitFlowEvent({
    layer: 'JS',
    event: 'ID_JS_BRIDGE_IDENTITY_RESTORE_RECEIVED',
    details: {},
  });

  try {
    const typedPayload = payload as RestorePayload;
    const mnemonic12 = typedPayload?.mnemonic12;

    if (!mnemonic12 || typeof mnemonic12 !== 'string') {
      emitFlowEvent({
        layer: 'JS',
        event: 'ID_JS_BRIDGE_IDENTITY_RESTORE_ERROR',
        details: { errorCode: 'INVALID_MNEMONIC', errorMessage: 'Missing or invalid mnemonic12 in payload' },
      });

      return {
        ok: false,
        errorCode: 'INVALID_MNEMONIC',
        errorMessage: 'Missing or invalid mnemonic12 in payload',
      };
    }

    const identity = await restoreIdentityFromMnemonic(mnemonic12);

    emitFlowEvent({
      layer: 'JS',
      event: 'ID_JS_BRIDGE_IDENTITY_RESTORE_SUCCESS',
      details: { peerId: identity.peerId },
    });

    return {
      ok: true,
      identity,
    };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : 'Unknown error during identity restoration';
    
    // Check if this is an INVALID_MNEMONIC error
    const isInvalidMnemonic = 
      error instanceof Error && 
      (error.message.includes('invalid') || 
       error.message.includes('mnemonic') ||
       error.message.includes('checksum') ||
       error.message.includes('word'));
    
    const errorCode = isInvalidMnemonic ? 'INVALID_MNEMONIC' : 'INTERNAL_ERROR';

    emitFlowEvent({
      layer: 'JS',
      event: 'ID_JS_BRIDGE_IDENTITY_RESTORE_ERROR',
      details: { errorCode, errorMessage },
    });

    return {
      ok: false,
      errorCode,
      errorMessage,
    };
  }
}

/**
 * Registers all identity-related bridge handlers
 */
export function registerIdentityHandlers(): void {
  registerHandler('identity.generate', handleIdentityGenerate);
  registerHandler('identity.restore', handleIdentityRestore);
}

// Export individual handlers for testing
export { handleIdentityGenerate, handleIdentityRestore };
