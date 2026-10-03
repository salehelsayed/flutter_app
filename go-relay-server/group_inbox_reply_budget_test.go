package main

import (
	"context"
	"encoding/json"
	"fmt"
	"strings"
	"testing"
	"time"
)

// largeGroupReplayEnvelope is a stored group replay of about size bytes, like
// the membership and key-update events a long remove/re-add history leaves.
func largeGroupReplayEnvelope(messageID string, size int) string {
	return fmt.Sprintf(
		`{"kind":"group_offline_replay","messageId":%q,"ciphertext":%q}`,
		messageID,
		strings.Repeat("A", size),
	)
}

func encodedReplyBytes(t *testing.T, resp inboxResponse) int {
	t.Helper()
	data, err := json.Marshal(resp)
	if err != nil {
		t.Fatalf("marshal reply: %v", err)
	}
	return len(data)
}

// A page of large messages used to exceed maxFrameLen: the relay could not
// write it, closed the stream, and every retry asked for the same page.
func TestGroupInboxCursorPageStaysUnderFrameLimit(t *testing.T) {
	store := NewGroupInboxStore(500, time.Hour)
	const groupId = "group-reply-budget"
	const total = 40
	for i := 0; i < total; i++ {
		if err := store.StoreWithPushRecipients(
			groupId, "peer-alice",
			largeGroupReplayEnvelope(fmt.Sprintf("big-%02d", i), 8*1024),
			[]string{"peer-bob"},
		); err != nil {
			t.Fatalf("store %d: %v", i, err)
		}
	}

	var got []string
	cursor := ""
	for pages := 0; ; pages++ {
		if pages > total {
			t.Fatalf("cursor never ended after %d pages", pages)
		}
		page, next, _ := store.RetrieveWithCursorAuthorized(groupId, cursor, 50, "peer-bob")
		if len(page) == 0 {
			t.Fatalf("empty page at cursor %q after %d messages", cursor, len(got))
		}
		reply := inboxResponse{Status: "OK", GroupMessages: page, NextCursor: next}
		if size := encodedReplyBytes(t, reply); size > maxFrameLen {
			t.Fatalf("page of %d messages encodes to %d bytes, over maxFrameLen %d", len(page), size, maxFrameLen)
		}
		for _, message := range page {
			got = append(got, message.Message)
		}
		if next == "" {
			break
		}
		cursor = next
	}
	if len(got) != total {
		t.Fatalf("paged %d messages, want %d", len(got), total)
	}
	for i := range got {
		if want := fmt.Sprintf(`"big-%02d"`, i); !strings.Contains(got[i], want) {
			t.Fatalf("message %d is not %s: pages lost or reordered a message", i, want)
		}
	}
}

// One message larger than the budget is still returned on its own page.
func TestGroupInboxReplyKeepsOneOversizedMessage(t *testing.T) {
	messages := []groupInboxMessage{
		{ID: "huge", From: "peer-alice", Message: strings.Repeat("A", groupInboxReplyByteBudget+1)},
		{ID: "next", From: "peer-alice", Message: "small"},
	}
	page, resumeAfter := capGroupInboxReply(messages)
	if len(page) != 1 || page[0].ID != "huge" || resumeAfter != "huge" {
		t.Fatalf("page = %d messages, resumeAfter %q; want only the oversized message and resume after it", len(page), resumeAfter)
	}
	small := messages[1:]
	if page, resumeAfter := capGroupInboxReply(small); len(page) != 1 || resumeAfter != "" {
		t.Fatalf("small page = %d messages, resumeAfter %q; want it whole with no cursor", len(page), resumeAfter)
	}
}

// group_retrieve (since a timestamp) returns everything at once; a large
// backlog now comes back in budgeted pages with a cursor to continue.
func TestHandleInboxStream_GroupRetrieveSinceIsBudgetedWithCursor(t *testing.T) {
	push := NewPushServiceWithBackend(newMemoryPushTokenStore())
	inbox := NewInboxStore(push)
	groupInbox := NewGroupInboxStore(500, 7*24*time.Hour)
	env := setupInboxStreamEnv(t, inbox, groupInbox)
	senderPeer := env.sender.ID().String()
	recipientPeer := env.recipient.ID().String()

	const total = 30
	for i := 0; i < total; i++ {
		stream, err := env.sender.NewStream(context.Background(), env.server.ID(), InboxProtocol)
		if err != nil {
			t.Fatalf("open group_store stream: %v", err)
		}
		sendInboxReq(t, stream, inboxRequest{
			Action:           "group_store",
			GroupId:          testCanonicalGroupCursorID,
			From:             senderPeer,
			Message:          largeGroupReplayEnvelope(fmt.Sprintf("since-%02d", i), 8*1024),
			RecipientPeerIds: []string{recipientPeer},
		})
		if resp := recvInboxResp(t, stream); resp.Status != "OK" {
			t.Fatalf("group_store %d = %q %q", i, resp.Status, resp.Error)
		}
		stream.Close()
	}

	request := func(req inboxRequest) inboxResponse {
		t.Helper()
		stream, err := env.recipient.NewStream(context.Background(), env.server.ID(), InboxProtocol)
		if err != nil {
			t.Fatalf("open %s stream: %v", req.Action, err)
		}
		defer stream.Close()
		sendInboxReq(t, stream, req)
		return recvInboxResp(t, stream)
	}

	first := request(inboxRequest{Action: "group_retrieve", GroupId: testCanonicalGroupCursorID})
	if first.Status != "OK" || first.NextCursor == "" || len(first.GroupMessages) == 0 || len(first.GroupMessages) == total {
		t.Fatalf("since reply = %q with %d messages, cursor %q; want a budgeted page and a cursor", first.Status, len(first.GroupMessages), first.NextCursor)
	}
	count := len(first.GroupMessages)
	cursor := first.NextCursor
	for cursor != "" {
		page := request(inboxRequest{Action: "group_retrieve_cursor", GroupId: testCanonicalGroupCursorID, Cursor: cursor, Limit: 50})
		if page.Status != "OK" {
			t.Fatalf("cursor page = %q %q after %d messages", page.Status, page.Error, count)
		}
		count += len(page.GroupMessages)
		cursor = page.NextCursor
	}
	if count != total {
		t.Fatalf("read %d messages through since + cursor pages, want %d", count, total)
	}
}
