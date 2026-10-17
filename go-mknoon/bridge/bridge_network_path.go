package bridge

import (
	"encoding/json"
	"fmt"

	"github.com/mknoon/go-mknoon/node"
)

// NetworkPathChanged delivers one default-network observation from the platform
// owner (Android ConnectivityManager default-network callback, or an iOS path
// monitor) to the node's handoff runner. Method channel name: node:network_changed
// / networkPathChanged.
//
// Input JSON:  { "ownerGeneration": <int64>, "epoch": <uint64 > 0>, "usable": <bool> }
// Returns JSON: { "ok": true, "accepted": bool, "coalesced": bool, "reason"?: string,
//
//	"epoch": N, "desiredEpoch": N, "readyEpoch": N }
//
// The call returns at once. Progress arrives as push events carrying the epoch:
// network:path_changing, then exactly one of network:relay_ready or
// network:relay_failed per attempted epoch. A stale or duplicate epoch is
// coalesced (accepted=false). An unusable path records the epoch and starts no
// work. A stopped node answers reason=not_started and does not start.
func NetworkPathChanged(paramsJSON string) (result string) {
	return withBridgeNode(func(n *node.Node) string {
		var params struct {
			OwnerGeneration int64  `json:"ownerGeneration"`
			Epoch           uint64 `json:"epoch"`
			Usable          bool   `json:"usable"`
		}
		if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
			return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
		}
		if params.Epoch == 0 {
			return errJSON("INVALID_INPUT", "epoch must be > 0")
		}
		adm := n.NetworkPathChanged(node.NetworkPathRequest{
			OwnerGeneration: params.OwnerGeneration,
			Epoch:           params.Epoch,
			Usable:          params.Usable,
		})
		resp := map[string]interface{}{
			"ok":           true,
			"accepted":     adm.Accepted,
			"coalesced":    adm.Coalesced,
			"epoch":        adm.Epoch,
			"desiredEpoch": adm.DesiredEpoch,
			"readyEpoch":   adm.ReadyEpoch,
		}
		if adm.Reason != "" {
			resp["reason"] = adm.Reason
		}
		return okJSON(resp)
	})
}

// CallMediaProtection acquires or releases the call-media protection lease
// (SE-42 D27 lease contract). While held, no relay recovery lane may fall
// back to a full host Stop/Start; in-place work still runs. Acquire before
// taking native media ownership; release the exact grant after that
// generation's media cleanup. The call answers at once, never waiting for a
// running restart.
//
// Acquire:  { "held": true, "generation": G }
//
//	granted:     { "ok": true, "held": true,  "generation": G, "incarnation": I }
//	not granted: { "ok": true, "held": false, "generation": G,
//	               "reason": "restart_in_progress" | "not_started" | "superseded" }
//
// Release:  { "held": false, "generation": G, "incarnation": I }
//
//	answer:      { "ok": true, "held": false, "released": true | false }
//
// A release clears the lease only when (G, I) is exactly the holder. Node
// Stop clears the lease and moves the incarnation, so a release from before
// a Stop can never clear a lease granted on the next host, even for the same G.
func CallMediaProtection(paramsJSON string) (result string) {
	return withBridgeNode(func(n *node.Node) string {
		var params struct {
			Held        *bool  `json:"held"`
			Generation  int64  `json:"generation"`
			Incarnation uint64 `json:"incarnation"`
		}
		if err := json.Unmarshal([]byte(paramsJSON), &params); err != nil {
			return errJSON("INVALID_INPUT", fmt.Sprintf("invalid JSON: %v", err))
		}
		if params.Held == nil {
			return errJSON("INVALID_INPUT", "missing held")
		}
		if !*params.Held {
			reply := n.ReleaseCallMediaProtection(params.Generation, params.Incarnation)
			return okJSON(map[string]interface{}{
				"ok":       true,
				"held":     false,
				"released": reply.Released,
			})
		}
		reply := n.AcquireCallMediaProtection(params.Generation)
		resp := map[string]interface{}{
			"ok":         true,
			"held":       reply.Held,
			"generation": reply.Generation,
		}
		if reply.Held {
			resp["incarnation"] = reply.Incarnation
		} else {
			resp["reason"] = reply.Reason
		}
		return okJSON(resp)
	})
}
