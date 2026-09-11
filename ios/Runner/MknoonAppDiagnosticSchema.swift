import Foundation

// Generated from tool/app_diagnostics/schema_v1.json; verified by parity tests.
internal enum MknoonAppDiagnosticSchema {
  static let required: Set<String> = ["schemaVersion", "eventId", "source", "runId", "sequence", "occurredAtMs", "elapsedMs", "feature", "stage", "outcome", "reason", "build", "platform", "values"]
  static let optional: Set<String> = ["traceId", "attemptId", "reportingRunId"]
  static let uuidFields: Set<String> = ["eventId", "traceId", "runId", "attemptId", "reportingRunId"]
  static let feature: Set<String> = ["media", "message", "private_media", "startup", "runtime", "push", "network", "storage"]
  static let stage: Set<String> = ["start", "preflight", "encrypt", "send", "store", "download", "verify", "decrypt", "commit", "receipt", "prepare", "present", "consume", "finish", "recover", "configure", "receive", "process", "snapshot", "launch", "bridge", "parse", "presentation", "recovery", "crash", "hang"]
  static let outcome: Set<String> = ["started", "ok", "success", "failed", "pending", "interrupted_unknown", "canceled", "blocked", "expired", "rejected", "timeout", "interrupted", "unknown"]
  static let reason: Set<String> = ["none", "unknown", "bootstrap", "interrupted_before_final_record", "flutter_error", "unhandled_error", "storage_failed", "bridge_unavailable", "network_unavailable", "timeout", "malformed_response", "permission_denied", "quota_exceeded", "unsupported", "user_action", "invalid_payload", "authority_rejected", "recipient_key_missing", "encryption_failed", "send_failed", "offline", "duplicate", "hash_mismatch", "auth_failed", "metadata_invalid", "io_failed", "size_mismatch", "missing_file", "retry_exhausted", "prepare_failed", "protection_failed", "authority_lost", "route_failed", "lifecycle_interrupted", "write_failed", "interrupted_unknown", "os_crash", "os_anr", "os_hang", "os_low_memory", "diagnostics_disabled", "stale_epoch", "sink_unavailable", "invalid_request", "retention_expired", "expired", "canceled", "bridge_handler_missing", "bridge_timeout", "bridge_rejected", "native_write_failed", "database_busy", "low_storage"]
  static let booleanValues: Set<String> = ["hasAttachments", "firstFrame", "canRetry", "committed", "acknowledged", "cleanupComplete", "storageHealthy", "nativeHealthy", "consentPending", "reportDelayed", "originalBuildKnown", "reportTimeIsIntervalEnd", "extensionProcess"]
  static let integerValues: Set<String> = ["durationMs", "retryCount", "queuedEvents", "droppedEvents", "count", "osReasonCode", "signal", "osMajor"]
  static let hashValues: Set<String> = ["fingerprint"]
  static let enumValues: [String: Set<String>] = [
    "phase": ["app_start", "database_ready", "identity_store_ready", "bridge_initialized", "notification_service_ready", "runtime_services_ready", "run_app_called", "firebase_ready", "documents_dir_ready", "share_launch_probe_begin", "share_launch_probe_complete", "deferred_runtime_start_begin", "deferred_runtime_start_complete", "route_pushed", "p2p_startup_begin", "p2p_startup_complete", "fte_init_state", "fte_first_frame", "fte_qr_ready"],
    "direction": ["incoming", "outgoing"],
    "transport": ["direct", "relay", "unknown"],
    "errorClass": ["state", "format", "argument", "timeout", "platform", "file_system", "other"],
    "operation": ["node_start", "node_stop", "relay_reconnect", "relay_probe", "peer_dial", "peer_disconnect", "notification_flock", "other"],
    "appLifecycle": ["unknown", "resumed", "inactive", "hidden", "paused", "detached"]
  ]
}
