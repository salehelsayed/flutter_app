package bridge

import (
	"encoding/json"
	"errors"
	"strings"
	"testing"

	"github.com/mknoon/go-mknoon/node"
)

const bridgeWakeOutcomeTestCorrelation = "8de60f1321300162dd4b0fed8d87b2017c4fa5b459cced3ec6d3a1d52241076d"

func TestInboxWakeOutcomeBridgeStrictRequest(t *testing.T) {
	valid := `{"correlation":"` + bridgeWakeOutcomeTestCorrelation + `","wakeNotRequired":true}`
	correlation, err := parseInboxWakeOutcomeBridgeRequest(valid)
	if err != nil || correlation != bridgeWakeOutcomeTestCorrelation {
		t.Fatalf("valid strict request = %q, %v", correlation, err)
	}

	invalid := map[string]string{
		"missing boolean":       `{"correlation":"` + bridgeWakeOutcomeTestCorrelation + `"}`,
		"false boolean":         `{"correlation":"` + bridgeWakeOutcomeTestCorrelation + `","wakeNotRequired":false}`,
		"uppercase correlation": `{"correlation":"8DE60F1321300162DD4B0FED8D87B2017C4FA5B459CCED3EC6D3A1D52241076D","wakeNotRequired":true}`,
		"duplicate correlation": `{"correlation":"` + bridgeWakeOutcomeTestCorrelation + `","correlation":"` + bridgeWakeOutcomeTestCorrelation + `","wakeNotRequired":true}`,
		"recipient spoof":       `{"correlation":"` + bridgeWakeOutcomeTestCorrelation + `","wakeNotRequired":true,"to":"peer"}`,
		"sender spoof":          `{"correlation":"` + bridgeWakeOutcomeTestCorrelation + `","wakeNotRequired":true,"from":"peer"}`,
		"unknown key":           `{"correlation":"` + bridgeWakeOutcomeTestCorrelation + `","wakeNotRequired":true,"outcome":"in_chat"}`,
		"trailing JSON":         valid + `{}`,
	}
	for name, raw := range invalid {
		t.Run(name, func(t *testing.T) {
			if _, err := parseInboxWakeOutcomeBridgeRequest(raw); err == nil {
				t.Fatalf("request unexpectedly accepted: %s", raw)
			}
			response := decodeWakeOutcomeBridgeTestResponse(t, InboxWakeOutcome(raw))
			if response["ok"] != false || response["errorCode"] != "INVALID_INPUT" {
				t.Fatalf("export response = %#v", response)
			}
		})
	}

	// A valid request crosses strict parsing before singleton resolution. This
	// also proves the exported name and gomobile-compatible string signature.
	nodeMu.Lock()
	previousNode := singletonNode
	singletonNode = nil
	nodeMu.Unlock()
	t.Cleanup(func() {
		nodeMu.Lock()
		singletonNode = previousNode
		nodeMu.Unlock()
	})
	validResponse := decodeWakeOutcomeBridgeTestResponse(t, InboxWakeOutcome(valid))
	if validResponse["errorCode"] != "NOT_INITIALIZED" {
		t.Fatalf("valid export response = %#v", validResponse)
	}

	terminal := decodeWakeOutcomeBridgeTestResponse(t, inboxWakeOutcomeBridgeResponse(
		node.InboxWakeOutcomeResult{
			ParticipantCount:        2,
			AcceptedCount:           1,
			UnsupportedCount:        1,
			AllParticipantsTerminal: true,
		},
		nil,
	))
	if terminal["ok"] != true || terminal["allParticipantsTerminal"] != true ||
		terminal["retryableCount"] != float64(0) {
		t.Fatalf("terminal result = %#v", terminal)
	}

	retryable := decodeWakeOutcomeBridgeTestResponse(t, inboxWakeOutcomeBridgeResponse(
		node.InboxWakeOutcomeResult{
			ParticipantCount: 2,
			AcceptedCount:    1,
			RetryableCount:   1,
		},
		errors.New("retryable participant"),
	))
	if retryable["ok"] != false || retryable["allParticipantsTerminal"] != false ||
		retryable["errorCode"] != "INBOX_WAKE_OUTCOME_RETRYABLE" ||
		retryable["retryableCount"] != float64(1) {
		t.Fatalf("retryable result = %#v", retryable)
	}
}

func decodeWakeOutcomeBridgeTestResponse(t *testing.T, raw string) map[string]interface{} {
	t.Helper()
	var response map[string]interface{}
	if err := json.Unmarshal([]byte(raw), &response); err != nil {
		t.Fatalf("decode bridge response %q: %v", raw, err)
	}
	if strings.TrimSpace(raw) == "" {
		t.Fatal("bridge returned an empty response")
	}
	return response
}
