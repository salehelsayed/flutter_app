package main

import (
	"log"
	"os"
	"path/filepath"
	"strconv"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promauto"
)

var diagnosticOwnerLimit = promauto.NewGaugeVec(prometheus.GaugeOpts{Name: "relay_diagnostics_owner_limit_bytes", Help: "Effective per-owner diagnostic byte ceiling; fixed store labels."}, []string{"store"})
var diagnosticGlobalLimit = promauto.NewGaugeVec(prometheus.GaugeOpts{Name: "relay_diagnostics_global_limit_bytes", Help: "Effective global diagnostic byte ceiling; fixed store labels."}, []string{"store"})
var diagnosticRefusals = promauto.NewCounterVec(prometheus.CounterOpts{Name: "relay_diagnostics_refusals_total", Help: "Diagnostic refusal attempts by fixed store, source and cause; not unique lost events."}, []string{"store", "source", "reason"})

// Invalid overrides retain the conservative default, never disable retained storage.
// Decimal bytes only; ParseUint rejects signs, whitespace, overflow and malformed input.
func diagnosticOwnerQuota(name string, fallback, global int) int {
	raw := os.Getenv(name)
	if raw == "" {
		return min(fallback, global)
	}
	n, err := strconv.ParseUint(raw, 10, 64)
	if err != nil || n == 0 || n > uint64(global) {
		log.Print("diagnostics owner_limit=invalid_default_used")
		return min(fallback, global)
	}
	return int(n)
}
func diagnosticRefusal(store, source, reason string) {
	switch store {
	case "app", "call":
	default:
		store = "unknown"
	}
	switch source {
	case "upload", "span", "binding", "authority", "maintenance", "configure", "clear":
	default:
		source = "unknown"
	}
	switch reason {
	case "owner_bytes", "global_bytes", "record_bytes", "record_count", "record_capacity", "persistence", "consent", "epoch", "conflict", "authority", "invalid", "queue_full":
	default:
		reason = "unknown"
	}
	diagnosticRefusals.WithLabelValues(store, source, reason).Inc()
}

// A rename may have succeeded before directory sync fails. Restore the previous
// committed bytes before another ACK. If restoration also fails, keep a bounded
// repair obligation and fail closed until it succeeds (including duplicate ACKs).
type diagnosticRepair struct {
	path  string
	prior []byte
}

func repairDiagnosticWrite(pending **diagnosticRepair, write func(string, []byte) error, remove func(string) error) error {
	if *pending == nil {
		return nil
	}
	p := *pending
	var err error
	if p.prior == nil {
		err = remove(p.path)
		if os.IsNotExist(err) {
			err = nil
		}
		if err == nil {
			// Absence alone is not a durable rollback: a prior unlink may
			// still need its directory synced, including on an absent retry.
			var dir *os.File
			parent := filepath.Dir(p.path)
			for {
				dir, err = os.Open(parent)
				if !os.IsNotExist(err) {
					break
				}
				// A write to a missing storage directory never published a
				// file. Sync its nearest surviving ancestor to settle absence.
				next := filepath.Dir(parent)
				if next == parent {
					break
				}
				parent = next
			}
			if err == nil {
				err = dir.Sync()
				_ = dir.Close()
			}
		}
	} else {
		err = write(p.path, p.prior)
	}
	if err == nil {
		*pending = nil
	}
	return err
}
func transactionalDiagnosticWrite(pending **diagnosticRepair, write func(string, []byte) error, remove func(string) error, path string, raw, prior []byte) error {
	if err := repairDiagnosticWrite(pending, write, remove); err != nil {
		return err
	}
	if err := write(path, raw); err != nil {
		*pending = &diagnosticRepair{path: path, prior: prior}
		_ = repairDiagnosticWrite(pending, write, remove)
		return err
	}
	return nil
}
