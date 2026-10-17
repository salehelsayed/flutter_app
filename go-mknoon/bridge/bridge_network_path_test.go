package bridge

import (
	"fmt"
	"testing"
)

// SE-42 D27 bridge envelope for the default-network handoff entry and the
// call-media protection lease.

func TestNetworkPathChanged_NotInitialized(t *testing.T) {
	withNoSingletonNode(t)
	m := parseJSON(t, NetworkPathChanged(`{"ownerGeneration":1,"epoch":1,"usable":true}`))
	assertNotOk(t, m, "NOT_INITIALIZED")
}

func TestNetworkPathChanged_InvalidInput(t *testing.T) {
	withFreshSingletonNode(t)
	assertNotOk(t, parseJSON(t, NetworkPathChanged(`not json`)), "INVALID_INPUT")
	assertNotOk(t, parseJSON(t, NetworkPathChanged(`{"ownerGeneration":1,"usable":true}`)), "INVALID_INPUT")
}

func TestNetworkPathChanged_StoppedNodeAnswersNotStarted(t *testing.T) {
	withFreshSingletonNode(t)
	m := parseJSON(t, NetworkPathChanged(`{"ownerGeneration":4,"epoch":2,"usable":true}`))
	assertOk(t, m)
	if m["accepted"] != false || m["reason"] != "not_started" {
		t.Fatalf("stopped node admission = %v, want accepted=false reason=not_started", m)
	}
	if m["epoch"].(float64) != 2 || m["desiredEpoch"].(float64) != 2 || m["readyEpoch"].(float64) != 0 {
		t.Fatalf("epoch fields = %v", m)
	}
	stale := parseJSON(t, NetworkPathChanged(`{"ownerGeneration":4,"epoch":1,"usable":true}`))
	assertOk(t, stale)
	if stale["coalesced"] != true || stale["reason"] != "stale_epoch" {
		t.Fatalf("stale admission = %v, want coalesced stale_epoch", stale)
	}
}

// The lease contract fixed for the Task 15 fix round: a grant carries the
// incarnation, a refusal carries a reason, and a release clears only the exact
// (generation, incarnation).
func TestCallMediaProtection_Envelope(t *testing.T) {
	withNoSingletonNode(t)
	assertNotOk(t, parseJSON(t, CallMediaProtection(`{"held":true,"generation":1}`)), "NOT_INITIALIZED")

	withFreshSingletonNode(t)
	assertNotOk(t, parseJSON(t, CallMediaProtection(`not json`)), "INVALID_INPUT")
	assertNotOk(t, parseJSON(t, CallMediaProtection(`{"generation":1}`)), "INVALID_INPUT")

	// A stopped node has no protection to grant.
	refused := parseJSON(t, CallMediaProtection(`{"held":true,"generation":5}`))
	assertOk(t, refused)
	if refused["held"] != false || refused["reason"] != "not_started" || refused["generation"].(float64) != 5 {
		t.Fatalf("acquire on a stopped node = %v, want held=false reason=not_started generation=5", refused)
	}
	if _, has := refused["incarnation"]; has {
		t.Fatalf("a refusal must not carry an incarnation: %v", refused)
	}

	assertOk(t, parseJSON(t, StartNode(startNodeJSON(t, generateTestKeyHex(t)))))
	acquired := parseJSON(t, CallMediaProtection(`{"held":true,"generation":5}`))
	assertOk(t, acquired)
	inc, _ := acquired["incarnation"].(float64)
	if acquired["held"] != true || acquired["generation"].(float64) != 5 || inc < 1 {
		t.Fatalf("acquire = %v, want held=true generation=5 with an incarnation >= 1", acquired)
	}
	if _, has := acquired["reason"]; has {
		t.Fatalf("a grant must not carry a reason: %v", acquired)
	}
	older := parseJSON(t, CallMediaProtection(`{"held":true,"generation":4}`))
	assertOk(t, older)
	if older["held"] != false || older["reason"] != "superseded" {
		t.Fatalf("older acquire = %v, want held=false reason=superseded", older)
	}
	release := func(body string) map[string]interface{} {
		m := parseJSON(t, CallMediaProtection(body))
		assertOk(t, m)
		if m["held"] != false {
			t.Fatalf("release answer %v must report held=false", m)
		}
		return m
	}
	if m := release(fmt.Sprintf(`{"held":false,"generation":4,"incarnation":%d}`, int(inc))); m["released"] != false {
		t.Fatalf("stale-generation release = %v, want released=false", m)
	}
	if m := release(fmt.Sprintf(`{"held":false,"generation":5,"incarnation":%d}`, int(inc)+1)); m["released"] != false {
		t.Fatalf("wrong-incarnation release = %v, want released=false", m)
	}
	if m := release(`{"held":false,"generation":5}`); m["released"] != false {
		t.Fatalf("release without incarnation = %v, want released=false", m)
	}
	if m := release(fmt.Sprintf(`{"held":false,"generation":5,"incarnation":%d}`, int(inc))); m["released"] != true {
		t.Fatalf("exact release = %v, want released=true", m)
	}
	again := parseJSON(t, CallMediaProtection(`{"held":true,"generation":6}`))
	assertOk(t, again)
	if again["held"] != true || again["incarnation"].(float64) != inc {
		t.Fatalf("acquire after release = %v, want a grant in the same incarnation %v (no Stop happened)", again, inc)
	}
}
