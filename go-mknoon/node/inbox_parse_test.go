package node

import (
	"errors"
	"testing"
)

func TestParseInboxStoreResponse_NewRelayFields(t *testing.T) {
	outcome, err := parseInboxStoreResponse([]byte(`{
		"status":"OK",
		"storeStatus":"stored",
		"expiresAtMs":12345,
		"occupancy":2,
		"capacity":100
	}`))
	if err != nil {
		t.Fatalf("parseInboxStoreResponse() error: %v", err)
	}
	if outcome.StoreStatus != "stored" {
		t.Fatalf("StoreStatus = %q, want stored", outcome.StoreStatus)
	}
	if outcome.ExpiresAtMs != 12345 || outcome.Occupancy != 2 || outcome.Capacity != 100 {
		t.Fatalf("outcome metadata = %#v", outcome)
	}
}

func TestParseInboxStoreResponse_InboxFullTyped(t *testing.T) {
	outcome, err := parseInboxStoreResponse([]byte(`{
		"status":"ERROR",
		"error":"INBOX_FULL",
		"storeStatus":"rejected_full",
		"occupancy":100,
		"capacity":100
	}`))
	if !errors.Is(err, ErrInboxFull) {
		t.Fatalf("error = %v, want ErrInboxFull", err)
	}
	if outcome.ErrorCode != "INBOX_FULL" {
		t.Fatalf("ErrorCode = %q, want INBOX_FULL", outcome.ErrorCode)
	}
	if outcome.StoreStatus != "rejected_full" {
		t.Fatalf("StoreStatus = %q, want rejected_full", outcome.StoreStatus)
	}
	if outcome.Occupancy != 100 || outcome.Capacity != 100 {
		t.Fatalf("outcome metadata = %#v", outcome)
	}
}

func TestParseInboxStoreResponse_OldRelayDefaults(t *testing.T) {
	outcome, err := parseInboxStoreResponse([]byte(`{"status":"OK"}`))
	if err != nil {
		t.Fatalf("parseInboxStoreResponse() error: %v", err)
	}
	if outcome.StoreStatus != "stored" {
		t.Fatalf("StoreStatus = %q, want stored", outcome.StoreStatus)
	}
	if outcome.ExpiresAtMs != 0 || outcome.Occupancy != 0 || outcome.Capacity != 0 {
		t.Fatalf("old relay metadata = %#v, want zero values", outcome)
	}
}
