/**
 * @fileoverview Flow event emission utility for M1 Identity Initialization.
 *
 * Provides a standardized way to emit flow events for observability
 * across the JS layer of the application.
 *
 * @module utils/flow_events
 */

/**
 * Parameters for emitting a flow event.
 */
export interface FlowEventParams {
  /** The layer emitting the event (always 'JS' for this module) */
  layer: 'JS';
  /** The event name following the pattern: {MILESTONE}_{LAYER}_{ENTITY}_{ACTION}_{RESULT} */
  event: string;
  /** Additional details about the event */
  details: Record<string, unknown>;
  /** The milestone identifier (defaults to 'M1_IDENTITY_INIT') */
  milestone?: string;
}

/**
 * Emits a flow event for observability.
 *
 * Flow events follow the pattern:
 * {MILESTONE}_{LAYER}_{ENTITY}_{ACTION}_{RESULT}
 *
 * @param params - The flow event parameters
 * @param params.layer - The layer emitting the event ('JS')
 * @param params.event - The event name
 * @param params.details - Additional event details
 *
 * @example
 * ```typescript
 * emitFlowEvent({
 *   layer: 'JS',
 *   event: 'ID_JS_GENERATE_IDENTITY_START',
 *   details: {},
 * });
 * ```
 */
export function emitFlowEvent({ layer, event, details, milestone }: FlowEventParams): void {
  const payload = {
    ts: new Date().toISOString(),
    milestone: milestone ?? 'M1_IDENTITY_INIT',
    layer,
    event,
    details,
  };
  console.log('[FLOW]', JSON.stringify(payload));
}
