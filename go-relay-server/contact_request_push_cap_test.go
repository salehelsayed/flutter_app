package main

import (
	"context"
	"fmt"
	"testing"
	"time"

	"firebase.google.com/go/v4/messaging"
	"github.com/alicebob/miniredis/v2"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
)

func TestContactRequestPushCap(t *testing.T) {
	for _, platform := range []string{"ios", "android"} {
		t.Run(platform, func(t *testing.T) {
			testContactRequestPushCap(t, platform)
		})
	}
}

func testContactRequestPushCap(t *testing.T, platform string) {
	t.Helper()
	redis := miniredis.RunT(t)
	t.Setenv("RELAY_BACKEND", "redis")
	t.Setenv("REDIS_URL", "redis://"+redis.Addr())
	t.Setenv("REDIS_PREFIX", "contact-cap-test:")
	t.Setenv("RELAY_CONTACT_REQUEST_PUSH_CAP_ENABLED", "true")
	t.Setenv("RELAY_APNS_VOIP_PUSH_ENABLED", "false")

	recorder := newRecordingPushSender()
	open := func() *controlPlaneStores {
		t.Helper()
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		stores, err := newControlPlaneStores(ctx, loadBackendConfigFromEnv(), DefaultServerLimits(), "")
		if err != nil {
			t.Fatalf("open relay stores: %v", err)
		}
		stores.Push.sender = recorder.Send
		t.Cleanup(func() { _ = stores.Close() })
		return stores
	}

	stores := open()
	env := setupInboxStreamEnv(t, stores.Inbox, stores.GroupInbox)
	recipient := env.recipient.ID().String()
	if err := stores.Push.RegisterToken(recipient, "synthetic-fcm-token", platform); err != nil {
		t.Fatalf("register test route: %v", err)
	}
	exchange := func(actor host.Host, request inboxRequest) inboxResponse {
		t.Helper()
		ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
		defer cancel()
		stream, err := actor.NewStream(ctx, env.server.ID(), InboxProtocol)
		if err != nil {
			t.Fatalf("open inbox stream: %v", err)
		}
		defer stream.Close()
		stopReset := context.AfterFunc(ctx, func() { _ = stream.Reset() })
		defer stopReset()
		sendInboxReq(t, stream, request)
		return recvInboxResp(t, stream)
	}

	store := func(actor host.Host, claimedFrom, message string, want InboxStoreResult) {
		t.Helper()
		response := exchange(actor, inboxRequest{
			Action: "store", From: claimedFrom, To: recipient, Message: message,
		})
		if response.Status != "OK" || response.StoreStatus != string(want) {
			t.Fatalf("store status = %q/%q (%q), want OK/%s", response.Status, response.StoreStatus, response.Error, want)
		}
	}

	request := func(id string) string {
		return fmt.Sprintf(`{"type":"contact_request","version":"2","intent":"new_request","msgId":%q}`, id)
	}
	expectVisible := func(caseName string, draft *messaging.Message) {
		t.Helper()
		if draft.Data["type"] != "contact_request" || draft.Data["body"] != "New contact request" {
			t.Errorf("%s: expected visible new contact request, got data %v", caseName, draft.Data)
		}
	}
	expectQuiet := func(caseName string, draft *messaging.Message) {
		t.Helper()
		if draft.Notification != nil || draft.Data["type"] == "contact_request" ||
			(draft.Android != nil && draft.Android.Notification != nil) ||
			(draft.APNS != nil && draft.APNS.Payload != nil && draft.APNS.Payload.Aps != nil &&
				draft.APNS.Payload.Aps.Alert != nil) {
			t.Errorf("%s: repeat request produced a visible notification", caseName)
		}
		if draft.Data["quietRecovery"] != "1" {
			t.Errorf("%s: repeat request did not use the quiet recovery carrier", caseName)
		}
	}

	first := request("first-request")
	store(env.sender, "", first, InboxStoreResultStored)
	expectVisible("first request", waitForRecordedPush(t, recorder))
	store(env.sender, "", first, InboxStoreResultDuplicate)
	assertNoRecordedPush(t, recorder)

	redis.FastForward(12 * time.Hour)
	second := request("repeat-request")
	store(env.sender, "attempted-forged-sender", second, InboxStoreResultStored)
	expectQuiet("same authenticated pair within the window", waitForRecordedPush(t, recorder))

	store(env.intruder, env.sender.ID().String(), request("independent-sender"), InboxStoreResultStored)
	expectVisible("different authenticated sender", waitForRecordedPush(t, recorder))

	unrelated := `{"type":"group_invite","id":"group-invite","groupId":"synthetic-group","groupName":"Synthetic group"}`
	store(env.sender, "", unrelated, InboxStoreResultStored)
	if draft := waitForRecordedPush(t, recorder); draft.Data["type"] != "group_invite" {
		t.Errorf("unrelated notification changed: got type %q", draft.Data["type"])
	}

	if err := stores.Close(); err != nil {
		t.Fatalf("close initial relay stores: %v", err)
	}
	stores = open()
	env.server.SetStreamHandler(InboxProtocol, func(stream network.Stream) {
		HandleInboxStream(stream, stores.Inbox, stores.GroupInbox, env.server, env.presence, nil)
	})
	third := request("repeat-after-restart")
	store(env.sender, "", third, InboxStoreResultStored)
	expectQuiet("same pair after reopening the relay stores", waitForRecordedPush(t, recorder))

	pending := exchange(env.recipient, inboxRequest{Action: "retrieve_pending", Limit: 20})
	if pending.Status != "OK" || len(pending.Messages) != 5 {
		t.Fatalf("durable pending response: status=%q, rows=%d, want OK/5", pending.Status, len(pending.Messages))
	}
	for _, expected := range []string{second, third} {
		found := false
		for _, entry := range pending.Messages {
			if entry.Message == expected && entry.From == env.sender.ID().String() && !entry.QuietRecovery {
				found = true
				break
			}
		}
		if !found {
			t.Error("provider-only demotion changed or lost a pending request")
		}
	}

	redis.FastForward(12*time.Hour + time.Second)
	store(env.sender, "", request("after-expiry"), InboxStoreResultStored)
	expectVisible("after the original 24-hour window expires", waitForRecordedPush(t, recorder))
}
