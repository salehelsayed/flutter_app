package main

import (
	"context"
	"encoding/json"
	"log"
	"time"
)

// A sender may recover delivery custody for an original it already knows was
// delivered without asking for another notification. This is an explicit send
// policy, not recipient receipt authority or an inference from message age.
// Edits and other event types retain their existing notification behavior.
func directNotificationCustodyOnlyIdentity(
	recipientPeerID string,
	entry inboxMessage,
) (messageDispatchAdmissionIdentity, bool) {
	if !entry.SuppressNotification {
		return messageDispatchAdmissionIdentity{}, false
	}
	var envelope map[string]json.RawMessage
	if json.Unmarshal([]byte(entry.Message), &envelope) != nil {
		return messageDispatchAdmissionIdentity{}, false
	}
	if _, isEdit := envelope["eventId"]; isEdit {
		return messageDispatchAdmissionIdentity{}, false
	}
	return newDirectMessageDispatchAdmissionIdentity(recipientPeerID, entry.From, entry.Message)
}

func directNotificationCustodyOnly(recipientPeerID string, entry inboxMessage) bool {
	_, valid := directNotificationCustodyOnlyIdentity(recipientPeerID, entry)
	return valid
}

// Remember accepted custody-only stores under the same exact identity used by
// provider admission. This also suppresses an older delayed iOS wake that has
// not acquired admission yet. A failed history write cannot undo custody or
// turn the sender's explicit no-notification request into a provider send.
func (is *InboxStore) rememberDirectNotificationCustodyOnly(
	recipientPeerID string,
	entry inboxMessage,
	result InboxStoreResult,
) {
	if result != InboxStoreResultStored && result != InboxStoreResultDuplicate {
		return
	}
	identity, valid := directNotificationCustodyOnlyIdentity(recipientPeerID, entry)
	if !valid {
		return
	}
	outcome := "history_unavailable"
	if is != nil && is.push != nil && is.push.directMessageDispatchAdmission != nil {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		_, acquired, err := is.push.directMessageDispatchAdmission.TryAcquire(ctx, identity)
		if err == nil {
			outcome = "history_retained"
			if acquired {
				outcome = "history_seeded"
			}
		}
	}
	pushSentCounter.WithLabelValues("direct_custody_only_" + outcome).Inc()
	log.Printf("[DIRECT_NOTIFICATION_CUSTODY_ONLY] outcome=%s", outcome)
}
