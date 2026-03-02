package main

import (
	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

// --- Gauges (current state) ---

var connectionsActive = promauto.NewGauge(prometheus.GaugeOpts{
	Name: "relay_connections_active",
	Help: "Current number of connected peers.",
})

var inboxMessagesPending = promauto.NewGauge(prometheus.GaugeOpts{
	Name: "relay_inbox_messages_pending",
	Help: "Messages currently waiting in inbox.",
})

var inboxPeersPending = promauto.NewGauge(prometheus.GaugeOpts{
	Name: "relay_inbox_peers_pending",
	Help: "Peers with pending inbox messages.",
})

var inboxPushTokens = promauto.NewGauge(prometheus.GaugeOpts{
	Name: "relay_inbox_push_tokens",
	Help: "Registered FCM push tokens.",
})

var mediaBlobsPending = promauto.NewGauge(prometheus.GaugeOpts{
	Name: "relay_media_blobs_pending",
	Help: "Blob files currently on disk.",
})

var mediaDiskBytes = promauto.NewGauge(prometheus.GaugeOpts{
	Name: "relay_media_disk_bytes",
	Help: "Total media folder size in bytes.",
})

var profileCountGauge = promauto.NewGauge(prometheus.GaugeOpts{
	Name: "relay_profile_count",
	Help: "Profile files currently on disk.",
})

var profileDiskBytes = promauto.NewGauge(prometheus.GaugeOpts{
	Name: "relay_profile_disk_bytes",
	Help: "Total profile folder size in bytes.",
})

var rendezvousNamespacesGauge = promauto.NewGauge(prometheus.GaugeOpts{
	Name: "relay_rendezvous_namespaces",
	Help: "Active rendezvous namespaces.",
})

var rendezvousPeersGauge = promauto.NewGauge(prometheus.GaugeOpts{
	Name: "relay_rendezvous_peers",
	Help: "Registered rendezvous peers.",
})

var activeStreams = promauto.NewGaugeVec(prometheus.GaugeOpts{
	Name: "relay_active_streams",
	Help: "Concurrent protocol stream handlers.",
}, []string{"proto"})

// --- Counters (lifetime totals) ---

var connectionsCounter = promauto.NewCounter(prometheus.CounterOpts{
	Name: "relay_connections_total",
	Help: "Lifetime peer connections.",
})

var disconnectionsCounter = promauto.NewCounter(prometheus.CounterOpts{
	Name: "relay_disconnections_total",
	Help: "Lifetime peer disconnections.",
})

// Inbox counters

var inboxStoredCounter = promauto.NewCounter(prometheus.CounterOpts{
	Name: "relay_inbox_stored_total",
	Help: "Messages accepted into inbox.",
})

var inboxRetrievedCounter = promauto.NewCounter(prometheus.CounterOpts{
	Name: "relay_inbox_retrieved_total",
	Help: "Messages sent to retrieving peer.",
})

var inboxExpiredCounter = promauto.NewCounter(prometheus.CounterOpts{
	Name: "relay_inbox_expired_total",
	Help: "Messages pruned by TTL.",
})

var inboxCappedCounter = promauto.NewCounter(prometheus.CounterOpts{
	Name: "relay_inbox_capped_total",
	Help: "Messages dropped by per-peer cap overflow.",
})

// Media counters

var mediaUploadedCounter = promauto.NewCounter(prometheus.CounterOpts{
	Name: "relay_media_uploaded_total",
	Help: "Blobs uploaded.",
})

var mediaUploadedBytesCounter = promauto.NewCounter(prometheus.CounterOpts{
	Name: "relay_media_uploaded_bytes_total",
	Help: "Total bytes uploaded.",
})

var mediaDownloadedCounter = promauto.NewCounter(prometheus.CounterOpts{
	Name: "relay_media_downloaded_total",
	Help: "Blobs downloaded.",
})

var mediaDownloadedBytesCounter = promauto.NewCounter(prometheus.CounterOpts{
	Name: "relay_media_downloaded_bytes_total",
	Help: "Total bytes downloaded.",
})

var mediaDeletedCounter = promauto.NewCounterVec(prometheus.CounterOpts{
	Name: "relay_media_deleted_total",
	Help: "Blobs deleted.",
}, []string{"reason"})

var mediaDeletedBytesCounter = promauto.NewCounterVec(prometheus.CounterOpts{
	Name: "relay_media_deleted_bytes_total",
	Help: "Total bytes deleted.",
}, []string{"reason"})

var mediaExpiredCounter = promauto.NewCounter(prometheus.CounterOpts{
	Name: "relay_media_expired_total",
	Help: "Blobs removed by TTL cleanup.",
})

// Profile counters

var profileUploadedCounter = promauto.NewCounter(prometheus.CounterOpts{
	Name: "relay_profile_uploaded_total",
	Help: "Profiles uploaded.",
})

var profileDownloadedCounter = promauto.NewCounter(prometheus.CounterOpts{
	Name: "relay_profile_downloaded_total",
	Help: "Profiles downloaded.",
})

var profileDeletedCounter = promauto.NewCounter(prometheus.CounterOpts{
	Name: "relay_profile_deleted_total",
	Help: "Profiles explicitly deleted.",
})

// Push counters

var pushSentCounter = promauto.NewCounterVec(prometheus.CounterOpts{
	Name: "relay_push_sent_total",
	Help: "Push notifications attempted.",
}, []string{"result"})

// Rendezvous counters

var rendezvousRegisteredCounter = promauto.NewCounter(prometheus.CounterOpts{
	Name: "relay_rendezvous_registered_total",
	Help: "Rendezvous registrations.",
})

var rendezvousDiscoveredCounter = promauto.NewCounter(prometheus.CounterOpts{
	Name: "relay_rendezvous_discovered_total",
	Help: "Rendezvous discover requests served.",
})

var rendezvousExpiredCounter = promauto.NewCounter(prometheus.CounterOpts{
	Name: "relay_rendezvous_expired_total",
	Help: "Rendezvous registrations expired.",
})

// Group inbox counters

var groupInboxStoredCounter = promauto.NewCounter(prometheus.CounterOpts{
	Name: "relay_group_inbox_stores_total",
	Help: "Group messages accepted into group inbox.",
})

var groupInboxRetrievedCounter = promauto.NewCounter(prometheus.CounterOpts{
	Name: "relay_group_inbox_retrieves_total",
	Help: "Group messages sent to retrieving peer.",
})

var groupInboxExpiredCounter = promauto.NewCounter(prometheus.CounterOpts{
	Name: "relay_group_inbox_expired_total",
	Help: "Group messages pruned by TTL.",
})

var groupInboxCappedCounter = promauto.NewCounter(prometheus.CounterOpts{
	Name: "relay_group_inbox_capped_total",
	Help: "Group messages dropped by per-group cap overflow.",
})

var groupInboxMessagesStoredGauge = promauto.NewGauge(prometheus.GaugeOpts{
	Name: "relay_group_inbox_messages_stored",
	Help: "Group messages currently stored in group inbox.",
})

var groupInboxGroupsActiveGauge = promauto.NewGauge(prometheus.GaugeOpts{
	Name: "relay_group_inbox_groups_active",
	Help: "Groups with messages in group inbox.",
})

// Stream errors

var streamErrorsCounter = promauto.NewCounterVec(prometheus.CounterOpts{
	Name: "relay_stream_errors_total",
	Help: "Stream-level errors.",
}, []string{"proto", "kind"})

// --- Histogram (latency) ---

var streamDuration = promauto.NewHistogramVec(prometheus.HistogramOpts{
	Name:    "relay_stream_duration_seconds",
	Help:    "End-to-end stream handler time.",
	Buckets: []float64{0.01, 0.05, 0.1, 0.25, 0.5, 1, 2.5, 5, 10, 30},
}, []string{"proto", "result"})
