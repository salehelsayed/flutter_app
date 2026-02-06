/**
 * inbox.ts
 *
 * Stub module for inbox functionality.
 * The full implementation will be added when the relay server supports inbox storage.
 */
export var ResponseStatus;
(function (ResponseStatus) {
    ResponseStatus["OK"] = "OK";
    ResponseStatus["ERROR"] = "ERROR";
    ResponseStatus["NO_MESSAGES"] = "NO_MESSAGES";
})(ResponseStatus || (ResponseStatus = {}));
/**
 * Store a message in the recipient's inbox on the relay server
 * @stub Returns error - not yet implemented
 */
export async function storeInInbox(_node, _relayPeerId, _toPeerId, _message, _metadata) {
    return {
        status: ResponseStatus.ERROR,
        messages: [],
        error: 'Inbox storage not yet implemented'
    };
}
/**
 * Retrieve messages from this node's inbox on the relay server
 * @stub Returns empty - not yet implemented
 */
export async function retrieveFromInbox(_node, _relayPeerId, _options) {
    return {
        status: ResponseStatus.NO_MESSAGES,
        messages: []
    };
}
//# sourceMappingURL=inbox.js.map