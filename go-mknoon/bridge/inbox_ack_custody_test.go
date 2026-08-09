package bridge

import (
	"errors"
	"testing"

	"github.com/mknoon/go-mknoon/node"
)

func TestDispatchInboxAckCustodyContract(t *testing.T) {
	t.Run("store absent contract stays legacy", func(t *testing.T) {
		legacyCalls := 0
		strictCalls := 0
		outcome, err := dispatchInboxStoreAckCustodyContract(
			"",
			"",
			func() (node.InboxStoreOutcome, error) {
				legacyCalls++
				return node.InboxStoreOutcome{StoreStatus: "stored"}, nil
			},
			func() (node.InboxStoreOutcome, error) {
				strictCalls++
				return node.InboxStoreOutcome{}, nil
			},
		)
		if err != nil || outcome.StoreStatus != "stored" || legacyCalls != 1 || strictCalls != 0 {
			t.Fatalf("legacy dispatch outcome=%#v err=%v legacy=%d strict=%d",
				outcome, err, legacyCalls, strictCalls)
		}
	})

	for _, kind := range []string{
		node.CustodyKindDirectTextV108,
		node.CustodyKindDirectReactionV109,
		node.CustodyKindDirectMutationV109,
	} {
		t.Run("exact store pair selects strict "+kind, func(t *testing.T) {
			legacyCalls := 0
			strictCalls := 0
			outcome, err := dispatchInboxStoreAckCustodyContract(
				node.AckOrExpiryCustodyContract,
				kind,
				func() (node.InboxStoreOutcome, error) {
					legacyCalls++
					return node.InboxStoreOutcome{}, nil
				},
				func() (node.InboxStoreOutcome, error) {
					strictCalls++
					return node.InboxStoreOutcome{
						StoreStatus:     "duplicate",
						CustodyContract: node.AckOrExpiryCustodyContract,
					}, nil
				},
			)
			if err != nil || outcome.CustodyContract != node.AckOrExpiryCustodyContract ||
				legacyCalls != 0 || strictCalls != 1 {
				t.Fatalf("strict dispatch outcome=%#v err=%v legacy=%d strict=%d",
					outcome, err, legacyCalls, strictCalls)
			}
		})
	}

	t.Run("partial and unknown store contracts fail before calls", func(t *testing.T) {
		for _, tc := range []struct {
			contract string
			kind     string
		}{
			{contract: node.AckOrExpiryCustodyContract},
			{kind: node.CustodyKindDirectTextV108},
			{contract: "ack_or_expiry_v2", kind: node.CustodyKindDirectTextV108},
			{contract: node.AckOrExpiryCustodyContract, kind: "direct_edit_v1"},
		} {
			calls := 0
			_, err := dispatchInboxStoreAckCustodyContract(
				tc.contract,
				tc.kind,
				func() (node.InboxStoreOutcome, error) { calls++; return node.InboxStoreOutcome{}, nil },
				func() (node.InboxStoreOutcome, error) { calls++; return node.InboxStoreOutcome{}, nil },
			)
			if !errors.Is(err, errInvalidInboxAckCustodyContract) || calls != 0 {
				t.Fatalf("contract=%q kind=%q err=%v calls=%d", tc.contract, tc.kind, err, calls)
			}
		}
	})

	t.Run("retrieve and ACK absent stay legacy exact selects strict", func(t *testing.T) {
		for _, tc := range []struct {
			contract string
			want     string
			wantErr  bool
		}{
			{contract: "", want: "legacy"},
			{contract: node.AckOrExpiryCustodyContract, want: "strict"},
			{contract: "ack_or_expiry_v2", wantErr: true},
		} {
			got, err := dispatchInboxAckCustodyContract(
				tc.contract,
				func() (string, error) { return "legacy", nil },
				func() (string, error) { return "strict", nil },
			)
			if tc.wantErr {
				if !errors.Is(err, errInvalidInboxAckCustodyContract) {
					t.Fatalf("contract %q error = %v", tc.contract, err)
				}
				continue
			}
			if err != nil || got != tc.want {
				t.Fatalf("contract %q got=%q err=%v", tc.contract, got, err)
			}
		}
	})

	t.Run("strict retrieve requires exact returned proof", func(t *testing.T) {
		for _, result := range []*node.InboxRetrievePendingResult{
			nil,
			{},
			{CustodyContract: "ack_or_expiry_v2"},
		} {
			if err := validateInboxRetrieveAckCustodyContract(
				node.AckOrExpiryCustodyContract,
				result,
			); !errors.Is(err, errInvalidInboxAckCustodyContract) {
				t.Fatalf("result=%#v error=%v", result, err)
			}
		}
		if err := validateInboxRetrieveAckCustodyContract(
			node.AckOrExpiryCustodyContract,
			&node.InboxRetrievePendingResult{CustodyContract: node.AckOrExpiryCustodyContract},
		); err != nil {
			t.Fatalf("exact retrieve proof: %v", err)
		}
		if err := validateInboxRetrieveAckCustodyContract("", &node.InboxRetrievePendingResult{}); err != nil {
			t.Fatalf("legacy retrieve result: %v", err)
		}
	})

	t.Run("strict bridge responses carry proof and exact store errors", func(t *testing.T) {
		success := parseJSON(t, inboxStoreAckCustodyBridgeResponse(node.InboxStoreOutcome{
			StoreStatus:     "stored",
			CustodyContract: node.AckOrExpiryCustodyContract,
		}, nil))
		assertOk(t, success)
		if success["custodyContract"] != node.AckOrExpiryCustodyContract {
			t.Fatalf("store response = %#v", success)
		}

		conflict := parseJSON(t, inboxStoreAckCustodyBridgeResponse(node.InboxStoreOutcome{
			ErrorCode: "CUSTODY_IDENTITY_CONFLICT",
		}, node.ErrInboxCustodyIdentityConflict))
		assertNotOk(t, conflict, "CUSTODY_IDENTITY_CONFLICT")
	})
}

func TestInboxStoreMediaExpiryCeilingBridgeContract(t *testing.T) {
	positive := int64(2_000_000_123_456)
	zero := int64(0)
	negative := int64(-1)

	if err := validateInboxStoreMediaExpiryCeiling("", "", nil); err != nil {
		t.Fatalf("omitted legacy ceiling: %v", err)
	}
	if err := validateInboxStoreMediaExpiryCeiling(
		node.AckOrExpiryCustodyContract,
		node.CustodyKindDirectReactionV109,
		nil,
	); err != nil {
		t.Fatalf("omitted reaction ceiling: %v", err)
	}
	if err := validateInboxStoreMediaExpiryCeiling(
		node.AckOrExpiryCustodyContract,
		node.CustodyKindDirectTextV108,
		&positive,
	); err != nil {
		t.Fatalf("exact media ceiling: %v", err)
	}

	for _, tc := range []struct {
		name     string
		contract string
		kind     string
		ceiling  *int64
	}{
		{
			name:     "explicit zero",
			contract: node.AckOrExpiryCustodyContract,
			kind:     node.CustodyKindDirectTextV108,
			ceiling:  &zero,
		},
		{
			name:     "negative",
			contract: node.AckOrExpiryCustodyContract,
			kind:     node.CustodyKindDirectTextV108,
			ceiling:  &negative,
		},
		{name: "legacy", ceiling: &positive},
		{
			name:     "reaction",
			contract: node.AckOrExpiryCustodyContract,
			kind:     node.CustodyKindDirectReactionV109,
			ceiling:  &positive,
		},
		{
			name:     "mutated contract",
			contract: "ack_or_expiry_v2",
			kind:     node.CustodyKindDirectTextV108,
			ceiling:  &positive,
		},
	} {
		t.Run(tc.name, func(t *testing.T) {
			if err := validateInboxStoreMediaExpiryCeiling(
				tc.contract,
				tc.kind,
				tc.ceiling,
			); !errors.Is(err, errInvalidInboxAckCustodyContract) {
				t.Fatalf("validation error = %v", err)
			}
		})
	}
}
