package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"os"
	"strings"
	"time"

	"firebase.google.com/go/v4/messaging"
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
	"github.com/redis/go-redis/v9"
)

const (
	contactRequestPushCapEnabledEnv = "RELAY_CONTACT_REQUEST_PUSH_CAP_ENABLED"
	contactRequestPushCapNamespace  = "contact-request-push-cap:v1:"
	contactRequestPushCapTTL        = 24 * time.Hour
)

var contactRequestPushDemotedCounter = promauto.NewCounterVec(prometheus.CounterOpts{
	Name: "relay_contact_request_push_demoted_total",
	Help: "Eligible repeat contact request alerts demoted to a quiet wake or suppressed by the pair cap.",
}, []string{"platform"})

type contactRequestPushCap struct {
	client *redis.Client
	prefix string
}

func loadContactRequestPushCapEnabledFromEnv() bool {
	switch strings.ToLower(strings.TrimSpace(os.Getenv(contactRequestPushCapEnabledEnv))) {
	case "1", "true":
		return true
	default:
		return false
	}
}

func (cap *contactRequestPushCap) project(
	ctx context.Context,
	fromPeerID, toPeerID, platform string,
	visible *messaging.Message,
) *messaging.Message {
	digest := sha256.New()
	writeMessageDispatchAdmissionComponent(digest, contactRequestPushCapNamespace)
	writeMessageDispatchAdmissionComponent(digest, fromPeerID)
	writeMessageDispatchAdmissionComponent(digest, toPeerID)
	key := cap.prefix + contactRequestPushCapNamespace + hex.EncodeToString(digest.Sum(nil))

	first, err := cap.client.SetNX(ctx, key, "1", contactRequestPushCapTTL).Result()
	if err == nil && first {
		return visible
	}

	platform = strings.ToLower(strings.TrimSpace(platform))
	if platform != "ios" && platform != "android" {
		platform = "unknown"
	}
	if err != nil {
		pushSentCounter.WithLabelValues("contact_request_cap_claim_failed").Inc()
	} else {
		contactRequestPushDemotedCounter.WithLabelValues(platform).Inc()
	}
	quiet, _ := buildQuietRecoveryPush(platform)
	return quiet
}
