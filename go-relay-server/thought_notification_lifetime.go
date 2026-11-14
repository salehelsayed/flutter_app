package main

import (
	"encoding/json"
	"strconv"
	"time"

	"firebase.google.com/go/v4/messaging"
)

const thoughtNotificationLifetime = 24 * time.Hour

// Builds 126–131 carry the snapshot expiry inside ciphertext. Their existing
// outer created_at supplies the same 24-hour recipient lifetime without a new
// sender contract. Clamp a future sender clock as the recipient does; missing
// or malformed legacy timestamps retain their existing delivery behavior.
func thoughtNotificationDeadline(message string, now time.Time) time.Time {
	var envelope struct {
		CreatedAt string `json:"created_at"`
	}
	if json.Unmarshal([]byte(message), &envelope) != nil {
		return time.Time{}
	}
	createdAt, err := time.Parse(time.RFC3339Nano, envelope.CreatedAt)
	if err != nil {
		return time.Time{}
	}
	if createdAt.After(now) {
		createdAt = now
	}
	return createdAt.Add(thoughtNotificationLifetime).UTC()
}

// Add the deadline before the full/compact ciphertext budget decision. The
// initial Android TTL uses the longest serialized duration within the lifetime
// for conservative sizing; each provider attempt replaces it below.
func addThoughtPushLifetime(message *messaging.Message, deadline time.Time) {
	if deadline.IsZero() {
		return
	}
	expiresAt := deadline.UTC().Format(time.RFC3339Nano)
	message.Data["expires_at"] = expiresAt
	if message.Android != nil {
		ttl := thoughtNotificationLifetime - time.Nanosecond
		message.Android.TTL = &ttl
	}
	if message.APNS != nil {
		message.APNS.Headers["apns-expiration"] = strconv.FormatInt(deadline.Unix(), 10)
		if message.APNS.Payload != nil && message.APNS.Payload.CustomData != nil {
			message.APNS.Payload.CustomData["expires_at"] = expiresAt
		}
	}
}

// Provider retries share one absolute deadline. Refresh only the remaining
// Android TTL, and stop before a retry could alert an already-expired Thought.
// Other routes, including fixed mixed-mailbox wakes, have no Thought deadline.
func (ps *PushService) refreshThoughtPushLifetime(message *messaging.Message) *messaging.Message {
	messageType := message.Data["type"]
	expiresAt := message.Data["expires_at"]
	if message.APNS != nil && message.APNS.Payload != nil {
		if messageType == "" {
			messageType, _ = message.APNS.Payload.CustomData["type"].(string)
		}
		if expiresAt == "" {
			expiresAt, _ = message.APNS.Payload.CustomData["expires_at"].(string)
		}
	}
	if messageType != "post_create" {
		return message
	}
	deadline, err := time.Parse(time.RFC3339Nano, expiresAt)
	if err != nil {
		return message
	}
	now := ps.opaqueWakeNow()
	if !deadline.After(now) {
		return nil
	}
	if message.Android == nil {
		return message
	}
	updated := *message
	android := *message.Android
	ttl := deadline.Sub(now)
	android.TTL = &ttl
	updated.Android = &android
	return &updated
}
