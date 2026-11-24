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

func loadContactRequestPushCapEnabledFromEnv() bool {
	switch strings.ToLower(strings.TrimSpace(os.Getenv(contactRequestPushCapEnabledEnv))) {
	case "1", "true":
		return true
	default:
		return false
	}
}

func newContactRequestPushPairIdentity(fromPeerID, toPeerID string) messageDispatchAdmissionIdentity {
	digest := sha256.New()
	writeMessageDispatchAdmissionComponent(digest, contactRequestPushCapNamespace)
	writeMessageDispatchAdmissionComponent(digest, fromPeerID)
	writeMessageDispatchAdmissionComponent(digest, toPeerID)
	return messageDispatchAdmissionIdentity{
		contactRequestPair: true,
		prehashedKey:       hex.EncodeToString(digest.Sum(nil)),
	}
}

func (ps *PushService) admitContactRequestPush(
	ctx context.Context,
	identity messageDispatchAdmissionIdentity,
	platform string,
	visible *messaging.Message,
) (*messaging.Message, func()) {
	backend := ps.contactRequestPushCap
	lease, first, err := backend.TryAcquire(ctx, identity)
	if err == nil && first {
		return visible, func() {
			releaseContext, cancel := context.WithTimeout(context.WithoutCancel(ctx), 5*time.Second)
			defer cancel()
			if err := backend.Release(releaseContext, lease); err != nil {
				pushSentCounter.WithLabelValues("contact_request_cap_release_failed").Inc()
			}
		}
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
	return quiet, nil
}
