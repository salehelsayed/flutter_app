package bridge

import (
	"errors"
	"testing"

	"github.com/mknoon/go-mknoon/node"
)

func TestDispatchMediaCustodyContract(t *testing.T) {
	t.Run("absent tuples preserve each legacy command", func(t *testing.T) {
		for _, operation := range []string{
			mediaCustodyBridgeUpload,
			mediaCustodyBridgeDownload,
			mediaCustodyBridgeAck,
		} {
			legacyCalls := 0
			strictCalls := 0
			got, err := dispatchMediaCustodyContract(
				operation,
				mediaCustodyBridgeSelection{},
				func() (string, error) { legacyCalls++; return "legacy", nil },
				func() (string, error) { strictCalls++; return "strict", nil },
			)
			if err != nil || got != "legacy" || legacyCalls != 1 || strictCalls != 0 {
				t.Fatalf("operation=%s got=%q err=%v legacy=%d strict=%d",
					operation, got, err, legacyCalls, strictCalls)
			}
		}
	})

	base := mediaCustodyBridgeSelection{
		CustodyContract: node.AckOrExpiryCustodyContract,
		CustodyKind:     node.CustodyKindDirectMediaBlobV1,
		ContentHash:     "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
	}
	strictCases := []struct {
		name      string
		operation string
		selection mediaCustodyBridgeSelection
	}{
		{name: "upload", operation: mediaCustodyBridgeUpload, selection: base},
		{name: "download", operation: mediaCustodyBridgeDownload, selection: func() mediaCustodyBridgeSelection {
			selection := base
			selection.Size = 42
			selection.Mime = "application/octet-stream"
			selection.ExpiresAtMs = 123456
			return selection
		}()},
		{name: "ack", operation: mediaCustodyBridgeAck, selection: func() mediaCustodyBridgeSelection {
			selection := base
			selection.Size = 42
			selection.Mime = "application/octet-stream"
			selection.ExpiresAtMs = 123456
			selection.CustodyRelayPeerId = "12D3KooWRelay"
			return selection
		}()},
	}
	for _, testCase := range strictCases {
		t.Run("complete "+testCase.name+" tuple selects strict", func(t *testing.T) {
			legacyCalls := 0
			strictCalls := 0
			got, err := dispatchMediaCustodyContract(
				testCase.operation,
				testCase.selection,
				func() (string, error) { legacyCalls++; return "legacy", nil },
				func() (string, error) { strictCalls++; return "strict", nil },
			)
			if err != nil || got != "strict" || legacyCalls != 0 || strictCalls != 1 {
				t.Fatalf("got=%q err=%v legacy=%d strict=%d", got, err, legacyCalls, strictCalls)
			}
		})
	}

	t.Run("partial and unknown tuples fail before dispatch", func(t *testing.T) {
		invalid := []struct {
			operation string
			selection mediaCustodyBridgeSelection
		}{
			{operation: mediaCustodyBridgeUpload, selection: mediaCustodyBridgeSelection{CustodyContract: node.AckOrExpiryCustodyContract}},
			{operation: mediaCustodyBridgeUpload, selection: mediaCustodyBridgeSelection{
				CustodyContract: "ack_or_expiry_v2",
				CustodyKind:     node.CustodyKindDirectMediaBlobV1,
				ContentHash:     base.ContentHash,
			}},
			{operation: mediaCustodyBridgeDownload, selection: base},
			{operation: mediaCustodyBridgeAck, selection: func() mediaCustodyBridgeSelection {
				selection := base
				selection.Size = 42
				selection.Mime = "application/octet-stream"
				selection.ExpiresAtMs = 123456
				return selection
			}()},
		}
		for _, testCase := range invalid {
			calls := 0
			_, err := dispatchMediaCustodyContract(
				testCase.operation,
				testCase.selection,
				func() (string, error) { calls++; return "legacy", nil },
				func() (string, error) { calls++; return "strict", nil },
			)
			if !errors.Is(err, errInvalidMediaCustodyContract) || calls != 0 {
				t.Fatalf("operation=%s selection=%#v err=%v calls=%d",
					testCase.operation, testCase.selection, err, calls)
			}
		}
	})

	t.Run("partial strict upload serializes typed ineligible outcome", func(t *testing.T) {
		withSingletonNode(t)
		response := parseJSON(t, MediaUpload(`{
			"id":"blob-partial",
			"to":"recipient",
			"mime":"application/octet-stream",
			"filePath":"/tmp/blob-partial.enc",
			"custodyContract":"ack_or_expiry_v1"
		}`))
		assertNotOk(t, response, node.MediaCustodyIneligibleCode)
	})

	t.Run("strict bridge response retains exact proof and source", func(t *testing.T) {
		response := parseJSON(t, mediaCustodyBridgeResponse(node.MediaCustodyResult{
			ID:                 "blob-1",
			CustodyKind:        node.CustodyKindDirectMediaBlobV1,
			CustodyContract:    node.AckOrExpiryCustodyContract,
			ContentHash:        base.ContentHash,
			Size:               42,
			Mime:               "application/octet-stream",
			ExpiresAtMs:        123456,
			StoreStatus:        "stored",
			CustodyRelayPeerId: "relay-peer",
		}, nil))
		assertOk(t, response)
		for key, want := range map[string]interface{}{
			"id": "blob-1", "custodyKind": node.CustodyKindDirectMediaBlobV1,
			"custodyContract": node.AckOrExpiryCustodyContract,
			"contentHash":     base.ContentHash, "size": float64(42),
			"mime": "application/octet-stream", "expiresAtMs": float64(123456),
			"storeStatus": "stored", "custodyRelayPeerId": "relay-peer",
		} {
			if got := response[key]; got != want {
				t.Fatalf("response[%s]=%#v, want %#v (response=%#v)", key, got, want, response)
			}
		}
	})
}

func TestTC365GroupMediaBlobCustody(t *testing.T) {
	base := mediaCustodyBridgeSelection{
		CustodyContract: node.AckOrExpiryCustodyContract,
		CustodyKind:     node.CustodyKindGroupMediaBlobV1,
		ContentHash:     "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
	}
	for _, tc := range []struct {
		name      string
		operation string
		selection mediaCustodyBridgeSelection
	}{
		{name: "upload", operation: mediaCustodyBridgeUpload, selection: base},
		{name: "download", operation: mediaCustodyBridgeDownload, selection: func() mediaCustodyBridgeSelection {
			selection := base
			selection.Size = 101
			selection.Mime = "application/octet-stream"
			selection.ExpiresAtMs = 2_000_000_100_001
			return selection
		}()},
		{name: "ack", operation: mediaCustodyBridgeAck, selection: func() mediaCustodyBridgeSelection {
			selection := base
			selection.Size = 202
			selection.Mime = "audio/ogg"
			selection.ExpiresAtMs = 2_000_000_200_002
			selection.CustodyRelayPeerId = "12D3KooWGroupRelay"
			return selection
		}()},
	} {
		t.Run(tc.name, func(t *testing.T) {
			calls := 0
			got, err := dispatchMediaCustodyContract(
				tc.operation,
				tc.selection,
				func() (string, error) { calls++; return "legacy", nil },
				func() (string, error) { calls++; return "group-strict", nil },
			)
			if err != nil || got != "group-strict" || calls != 1 {
				t.Fatalf("operation=%s got=%q calls=%d err=%v", tc.operation, got, calls, err)
			}
		})
	}

	direct := base
	direct.CustodyKind = node.CustodyKindDirectMediaBlobV1
	if got, err := dispatchMediaCustodyContract(
		mediaCustodyBridgeUpload,
		direct,
		func() (string, error) { return "legacy", nil },
		func() (string, error) { return "direct-strict", nil },
	); err != nil || got != "direct-strict" {
		t.Fatalf("incumbent direct selector got=%q err=%v", got, err)
	}
	crossed := base
	crossed.CustodyKind = "group_media_blob_v2"
	if _, err := dispatchMediaCustodyContract(
		mediaCustodyBridgeUpload,
		crossed,
		func() (string, error) { return "legacy", nil },
		func() (string, error) { return "strict", nil },
	); !errors.Is(err, errInvalidMediaCustodyContract) {
		t.Fatalf("crossed group kind error=%v", err)
	}

	ceilingA := int64(2_000_000_100_001)
	ceilingB := int64(2_000_000_200_002)
	for _, ceiling := range []*int64{&ceilingA, &ceilingB} {
		if err := validateInboxStoreMediaExpiryCeiling(
			node.AckOrExpiryCustodyContract,
			node.CustodyKindGroupContentV1,
			ceiling,
		); err != nil {
			t.Fatalf("group content ceiling %d: %v", *ceiling, err)
		}
	}
	if err := validateInboxStoreMediaExpiryCeiling(
		node.AckOrExpiryCustodyContract,
		node.CustodyKindGroupContentV1,
		nil,
	); err != nil {
		t.Fatalf("blob-free group content changed: %v", err)
	}
}
