package node

import (
	"bytes"
	"context"
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"log"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/mknoon/go-mknoon/activitycalendar"
	ma "github.com/multiformats/go-multiaddr"
)

const b294ACK = `{"status":"OK","version":1,"data":{"supported":true,"accepted":true}}`

type b294Clock struct {
	mu sync.Mutex
	at time.Time
}

func (c *b294Clock) now() time.Time   { c.mu.Lock(); defer c.mu.Unlock(); return c.at }
func (c *b294Clock) set(at time.Time) { c.mu.Lock(); c.at = at; c.mu.Unlock() }

func b294Midnight(t *testing.T, day string) time.Time {
	t.Helper()
	at, err := activitycalendar.Parse(day)
	if err != nil {
		t.Fatal(err)
	}
	return at
}

func b294Wait(t *testing.T, signal <-chan struct{}, label string) {
	t.Helper()
	select {
	case <-signal:
	case <-time.After(2 * time.Second):
		t.Fatalf("%s did not reach its controlled checkpoint", label)
	}
}

func b294Result(t *testing.T, result <-chan error, label string) error {
	t.Helper()
	select {
	case err := <-result:
		return err
	case <-time.After(2 * time.Second):
		t.Fatalf("%s did not complete within the fixed fixture bound", label)
		return nil
	}
}

type b294Barrier struct {
	entered, release       chan struct{}
	enterOnce, releaseOnce sync.Once
}

func b294NewBarrier(t *testing.T) *b294Barrier {
	t.Helper()
	b := &b294Barrier{entered: make(chan struct{}), release: make(chan struct{})}
	t.Cleanup(b.open)
	return b
}

func (b *b294Barrier) open() { b.releaseOnce.Do(func() { close(b.release) }) }
func (b *b294Barrier) block() error {
	b.enterOnce.Do(func() { close(b.entered) })
	select {
	case <-b.release:
		return nil
	case <-time.After(2 * time.Second):
		return errors.New("public B294 barrier expired")
	}
}

type b294Files struct {
	mu          sync.Mutex
	beforeRead  func(string) error
	beforeWrite func(string, []byte) error
	written     [][]byte
}

func (f *b294Files) read(path string) ([]byte, error) {
	f.mu.Lock()
	hook := f.beforeRead
	f.mu.Unlock()
	if hook != nil {
		if err := hook(path); err != nil {
			return nil, err
		}
	}
	return activeIdentityReporterRead(path)
}

func (f *b294Files) write(path string, raw []byte) error {
	f.mu.Lock()
	hook := f.beforeWrite
	f.mu.Unlock()
	if hook != nil {
		if err := hook(path, bytes.Clone(raw)); err != nil {
			return err
		}
	}
	if err := activeIdentityReporterAtomicWrite(path, raw); err != nil {
		return err
	}
	f.mu.Lock()
	f.written = append(f.written, bytes.Clone(raw))
	f.mu.Unlock()
	return nil
}

func (f *b294Files) onRead(hook func(string) error) { f.mu.Lock(); f.beforeRead = hook; f.mu.Unlock() }
func (f *b294Files) onWrite(hook func(string, []byte) error) {
	f.mu.Lock()
	f.beforeWrite = hook
	f.mu.Unlock()
}
func (f *b294Files) count() int { f.mu.Lock(); defer f.mu.Unlock(); return len(f.written) }

type b294Request struct {
	relay      peer.ID
	transport  string
	generation uint64
	raw        []byte
}

// This supplies public fixture IDs and recorded exchanges only. It does not
// create a libp2p host or prove a secure-network handshake/Node adapter wiring.
type b294Transport struct {
	mu         sync.Mutex
	up         bool
	id         string
	generation uint64
	addresses  []string
	ctx        context.Context
	cancel     context.CancelFunc
	hook       func(context.Context, RelayInfo, []byte) ([]byte, error)
	requests   []b294Request
	changed    chan struct{}
}

func (n *b294Transport) start(id string, addresses []string) {
	n.mu.Lock()
	if n.cancel != nil {
		n.cancel()
	}
	n.up = true
	n.id = id
	n.generation++
	if addresses == nil {
		n.addresses = nil
	} else {
		n.addresses = append([]string{}, addresses...)
	}
	n.ctx, n.cancel = context.WithCancel(context.Background())
	n.mu.Unlock()
}

func (n *b294Transport) stop() {
	n.mu.Lock()
	n.up = false
	if n.cancel != nil {
		n.cancel()
	}
	n.mu.Unlock()
}

func (n *b294Transport) onExchange(hook func(context.Context, RelayInfo, []byte) ([]byte, error)) {
	n.mu.Lock()
	n.hook = hook
	n.mu.Unlock()
}

func (n *b294Transport) snapshot() (activeIdentityReporterTransport, bool) {
	n.mu.Lock()
	if !n.up {
		n.mu.Unlock()
		return activeIdentityReporterTransport{}, false
	}
	id, generation, ctx := n.id, n.generation, n.ctx
	var addresses []string
	if n.addresses != nil {
		addresses = append([]string{}, n.addresses...)
	}
	n.mu.Unlock()
	return activeIdentityReporterTransport{
		peerID: id, generation: generation, relayAddresses: addresses, ctx: ctx,
		current: func() bool { n.mu.Lock(); defer n.mu.Unlock(); return n.up && n.generation == generation && n.id == id },
		exchange: func(ctx context.Context, relay RelayInfo, raw []byte) ([]byte, error) {
			deadline, bounded := ctx.Deadline()
			if !bounded || time.Until(deadline) > activeIdentityReporterFlushBudget {
				return nil, errors.New("public B294 exchange lacked bounded deadline")
			}
			n.mu.Lock()
			n.requests = append(n.requests, b294Request{relay.ID, id, generation, bytes.Clone(raw)})
			hook := n.hook
			n.mu.Unlock()
			select {
			case n.changed <- struct{}{}:
			default:
			}
			if hook != nil {
				return hook(ctx, relay, bytes.Clone(raw))
			}
			if err := ctx.Err(); err != nil {
				return nil, err
			}
			return []byte(b294ACK), nil
		},
	}, true
}

func (n *b294Transport) recorded() []b294Request {
	n.mu.Lock()
	defer n.mu.Unlock()
	result := append([]b294Request(nil), n.requests...)
	for i := range result {
		result[i].raw = bytes.Clone(result[i].raw)
	}
	return result
}

type b294Harness struct {
	t                           *testing.T
	clock                       *b294Clock
	files                       *b294Files
	transport                   *b294Transport
	reporter                    *activeIdentityReporter
	config                      ActiveIdentityReporterConfig
	transportID, relayA, relayB string
	workers                     sync.WaitGroup
}

func b294New(t *testing.T) *b294Harness {
	t.Helper()
	_, account, root := b293ClientIdentity(t, 70)
	_, transport, _ := b293ClientIdentity(t, 71)
	_, relayA, _ := b293ClientIdentity(t, 72)
	_, relayB, _ := b293ClientIdentity(t, 73)
	h := &b294Harness{
		t: t, clock: &b294Clock{at: b294Midnight(t, "2026-03-28").Add(12 * time.Hour)},
		files: &b294Files{}, transport: &b294Transport{changed: make(chan struct{}, 1)},
		transportID: transport, relayA: relayA, relayB: relayB,
		config: ActiveIdentityReporterConfig{
			Fence:     ActiveIdentityReporterFence{Revision: 1, ConsentEpoch: 7, ProfileBinding: "v1:" + strings.Repeat("a", 64), AccountPeerID: account},
			StatePath: filepath.Join(t.TempDir(), "owned-activity", "state.json"), RootPrivateKeyBase64: root,
		},
	}
	h.reporter = newActiveIdentityReporter(h.deps())
	t.Cleanup(func() {
		h.transport.stop()
		done := make(chan struct{})
		go func() { h.reporter.close(); h.workers.Wait(); close(done) }()
		select {
		case <-done:
		case <-time.After(2 * time.Second):
			t.Error("reporter fixture did not cancel/join within2s")
		}
	})
	return h
}

func (h *b294Harness) deps() activeIdentityReporterDeps {
	return activeIdentityReporterDeps{now: h.clock.now, read: h.files.read, write: h.files.write, transportSnapshot: h.transport.snapshot}
}

func (h *b294Harness) async(operation func() error) <-chan error {
	result := make(chan error, 1)
	h.workers.Add(1)
	go func() { defer h.workers.Done(); result <- operation() }()
	return result
}

func (h *b294Harness) publish(fence ActiveIdentityReporterFence, enabled, preserve bool) {
	h.t.Helper()
	got, err := h.reporter.publishDesired(fence, enabled, preserve)
	if err != nil || got != fence {
		h.t.Fatalf("valid desired publication failed: fence%+v error%v", got, err)
	}
}

func (h *b294Harness) ready() {
	h.t.Helper()
	h.publish(h.config.Fence, true, false)
	if err := h.reporter.configure(h.config); err != nil {
		h.t.Fatalf("valid full configuration control: %v", err)
	}
}

func (h *b294Harness) mark() {
	h.t.Helper()
	if err := h.reporter.mark(h.config.Fence); err != nil {
		h.t.Fatal(err)
	}
}

func (h *b294Harness) flush() {
	h.t.Helper()
	if err := b294Result(h.t, h.async(func() error { return h.reporter.flush(h.config.Fence) }), "reporter flush"); err != nil {
		h.t.Fatal(err)
	}
}

func (h *b294Harness) reopen() {
	h.t.Helper()
	previous := h.reporter
	if err := b294Result(h.t, h.async(func() error { previous.close(); return nil }), "close before restart"); err != nil {
		h.t.Fatal(err)
	}
	h.reporter = newActiveIdentityReporter(h.deps())
}

func b294Address(id string, port int) string {
	return fmt.Sprintf("/ip4/127.0.0.1/tcp/%d/p2p/%s", port, id)
}

func b294Disk(t *testing.T, path string) activeIdentityReporterDisk {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var disk activeIdentityReporterDisk
	if err := json.Unmarshal(raw, &disk); err != nil {
		t.Fatal(err)
	}
	return disk
}

func b294Read(t *testing.T, path string) []byte {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return raw
}

func b294Fixed(t *testing.T, err, want error) {
	t.Helper()
	if !errors.Is(err, want) || err == nil || err.Error() != want.Error() {
		t.Fatalf("error=%v want fixed%v", err, want)
	}
}

func b294Proofs(t *testing.T, requests []b294Request, config ActiveIdentityReporterConfig) {
	t.Helper()
	if len(requests) == 0 {
		t.Fatal("no exchange reached the proof control")
	}
	key, err := base64.StdEncoding.DecodeString(config.RootPrivateKeyBase64)
	if err != nil || len(key) != ed25519.PrivateKeySize {
		t.Fatal("invalid public key fixture")
	}
	for _, request := range requests {
		var body struct{ Day, AccountPeerID, Signature string }
		var fields map[string]json.RawMessage
		if json.Unmarshal(request.raw, &fields) != nil || len(fields) != 5 || json.Unmarshal(fields["day"], &body.Day) != nil || json.Unmarshal(fields["accountPeerId"], &body.AccountPeerID) != nil || json.Unmarshal(fields["signature"], &body.Signature) != nil {
			t.Fatal("recorded request violated bounded B3 shape")
		}
		expected, err := buildActiveIdentityRequest(body.Day, config.Fence.AccountPeerID, request.transport, config.RootPrivateKeyBase64)
		if err != nil || !bytes.Equal(expected, request.raw) || body.AccountPeerID != config.Fence.AccountPeerID {
			t.Fatal("reporter did not use actual B3 builder inputs")
		}
		signature, err := base64.StdEncoding.DecodeString(body.Signature)
		if err != nil || !ed25519.Verify(ed25519.PublicKey(key[ed25519.SeedSize:]), b293ClientProof(body.Day, body.AccountPeerID, request.transport), signature) {
			t.Fatal("independent root/transport proof did not verify")
		}
	}
	if result, err := parseActiveIdentityResponse([]byte(b294ACK)); err != nil || result != activeIdentityAcknowledged {
		t.Fatal("actual B3 parser ACK control is unavailable")
	}
}

func TestB294ReporterConfigurationRefusalsHaveFixedPrivateErrors(t *testing.T) {
	control := b294New(t)
	control.ready()
	for _, tc := range []struct {
		name   string
		change func(*ActiveIdentityReporterConfig)
	}{
		{"empty-path", func(c *ActiveIdentityReporterConfig) { c.StatePath = "" }},
		{"foreign-root", func(c *ActiveIdentityReporterConfig) { _, _, c.RootPrivateKeyBase64 = b293ClientIdentity(t, 74) }},
		{"root-not-base64", func(c *ActiveIdentityReporterConfig) { c.RootPrivateKeyBase64 = "private-B294-root-not-base64" }},
		{"short-root", func(c *ActiveIdentityReporterConfig) {
			c.RootPrivateKeyBase64 = base64.StdEncoding.EncodeToString(bytes.Repeat([]byte{70}, 32))
		}},
		{"root-newline", func(c *ActiveIdentityReporterConfig) { c.RootPrivateKeyBase64 += "\n" }},
		{"inconsistent-raw-root", func(c *ActiveIdentityReporterConfig) {
			raw, err := base64.StdEncoding.DecodeString(c.RootPrivateKeyBase64)
			if err != nil {
				t.Fatal(err)
			}
			raw[0] ^= 1
			c.RootPrivateKeyBase64 = base64.StdEncoding.EncodeToString(raw)
		}},
		{"preserve-full-identity", func(c *ActiveIdentityReporterConfig) { c.PreservePendingOnUnarm = true }},
	} {
		t.Run(tc.name, func(t *testing.T) {
			h := b294New(t)
			h.ready()
			before := b294Read(t, h.config.StatePath)
			candidate := h.config
			tc.change(&candidate)
			b294Fixed(t, h.reporter.configure(candidate), errActiveIdentityReporterInput)
			if !bytes.Equal(before, b294Read(t, h.config.StatePath)) {
				t.Fatal("invalid full configuration changed durable state")
			}
		})
	}
	for _, fence := range []ActiveIdentityReporterFence{
		{Revision: 0, ConsentEpoch: 7, ProfileBinding: control.config.Fence.ProfileBinding, AccountPeerID: control.config.Fence.AccountPeerID},
		{Revision: 9007199254740992, ConsentEpoch: 7, ProfileBinding: control.config.Fence.ProfileBinding, AccountPeerID: control.config.Fence.AccountPeerID},
		{Revision: 2, ConsentEpoch: 0, ProfileBinding: control.config.Fence.ProfileBinding, AccountPeerID: control.config.Fence.AccountPeerID},
		{Revision: 2, ConsentEpoch: 7, AccountPeerID: control.config.Fence.AccountPeerID},
		{Revision: 2, ConsentEpoch: 7, ProfileBinding: "private-B294-invalid-binding", AccountPeerID: control.config.Fence.AccountPeerID},
		{Revision: 2, ConsentEpoch: 7, ProfileBinding: control.config.Fence.ProfileBinding, AccountPeerID: "private-B294-invalid-account"},
	} {
		_, err := control.reporter.publishDesired(fence, true, false)
		b294Fixed(t, err, errActiveIdentityReporterInput)
	}
	_, err := control.reporter.publishDesired(control.config.Fence, true, true)
	b294Fixed(t, err, errActiveIdentityReporterInput)
	account, err := peer.Decode(control.config.Fence.AccountPeerID)
	if err != nil {
		t.Fatal(err)
	}
	alias := control.config.Fence
	alias.Revision++
	alias.AccountPeerID = peer.ToCid(account).String()
	_, err = control.reporter.publishDesired(alias, true, false)
	b294Fixed(t, err, errActiveIdentityReporterInput)
}

func TestB294ReporterDesiredAndBetaConfigurationNeverCreateActivity(t *testing.T) {
	h := b294New(t)
	var ioAttempts atomic.Int32
	h.files.onRead(func(string) error { ioAttempts.Add(1); return errors.New("public B294 unexpected desired read") })
	h.files.onWrite(func(string, []byte) error {
		ioAttempts.Add(1)
		return errors.New("public B294 unexpected desired write")
	})
	h.publish(h.config.Fence, true, false)
	if ioAttempts.Load() != 0 {
		t.Fatal("memory-only desired publication loaded/wrote private state")
	}
	h.files.onRead(nil)
	h.files.onWrite(nil)
	b294Fixed(t, h.reporter.mark(h.config.Fence), errActiveIdentityReporterStale)
	b294Fixed(t, h.reporter.flush(h.config.Fence), errActiveIdentityReporterStale)
	if _, err := os.Stat(h.config.StatePath); !errors.Is(err, os.ErrNotExist) {
		t.Fatalf("memory-only desired publication performed file I/O: %v", err)
	}
	if err := h.reporter.configure(h.config); err != nil {
		t.Fatal(err)
	}
	h.transport.start(h.transportID, []string{b294Address(h.relayA, 4101)})
	h.flush()
	disk := b294Disk(t, h.config.StatePath)
	if disk.Marked || len(disk.Acknowledged) != 0 || len(h.transport.recorded()) != 0 {
		t.Fatal("beta enabled/configure/app opening invented qualifying communication")
	}
}

func TestB294ReporterOfflineMarkIsDurableBeforeReturning(t *testing.T) {
	h := b294New(t)
	h.ready()
	before := b294Read(t, h.config.StatePath)
	writes := h.files.count()
	barrier := b294NewBarrier(t)
	var first atomic.Bool
	h.files.onWrite(func(string, []byte) error {
		if first.CompareAndSwap(false, true) {
			return barrier.block()
		}
		return nil
	})
	marked := h.async(func() error {
		err := h.reporter.mark(h.config.Fence)
		if err == nil && h.files.count() == writes {
			return errors.New("public B294 mark ACK preceded durable writer")
		}
		return err
	})
	b294Wait(t, barrier.entered, "offline mark writer")
	select {
	case err := <-marked:
		t.Fatalf("mark returned before durable write: %v", err)
	default:
	}
	if !bytes.Equal(before, b294Read(t, h.config.StatePath)) {
		t.Fatal("blocked mark replaced authoritative snapshot")
	}
	barrier.open()
	if err := b294Result(t, marked, "offline mark"); err != nil {
		t.Fatal(err)
	}
	disk := b294Disk(t, h.config.StatePath)
	if !disk.Marked || disk.Day != "2026-03-28" || len(disk.Acknowledged) != 0 || len(h.transport.recorded()) != 0 {
		t.Fatalf("offline admission not durable without a host: %+v", disk)
	}
}

func TestB294ReporterDuplicateMarksAndSameScopeRefreshPreserveState(t *testing.T) {
	h := b294New(t)
	h.ready()
	h.mark()
	before := b294Read(t, h.config.StatePath)
	writes := h.files.count()
	for range 4 {
		h.mark()
		h.publish(h.config.Fence, true, false)
		if err := h.reporter.configure(h.config); err != nil {
			t.Fatal(err)
		}
	}
	if !bytes.Equal(before, b294Read(t, h.config.StatePath)) || h.files.count() != writes {
		t.Fatal("duplicate mark or same-root metadata refresh reset/rewrote daily state")
	}
}

func TestB294ReporterRestartRequiresMatchingCurrentOwnerBeforeRecovery(t *testing.T) {
	h := b294New(t)
	h.ready()
	h.mark()
	before := b294Read(t, h.config.StatePath)
	h.reopen()
	h.transport.start(h.transportID, []string{b294Address(h.relayA, 4101)})
	b294Fixed(t, h.reporter.flush(h.config.Fence), errActiveIdentityReporterStale)
	b294Fixed(t, h.reporter.mark(h.config.Fence), errActiveIdentityReporterStale)
	if !bytes.Equal(before, b294Read(t, h.config.StatePath)) || len(h.transport.recorded()) != 0 {
		t.Fatal("unarmed restart consumed or transmitted recovery candidate")
	}
	h.ready()
	if !b294Disk(t, h.config.StatePath).Marked {
		t.Fatal("matching current owner lost same-day offline activity")
	}
	h.flush()
	b294Proofs(t, h.transport.recorded(), h.config)
	for _, change := range []struct {
		name  string
		apply func(*ActiveIdentityReporterConfig)
	}{
		{"profile", func(c *ActiveIdentityReporterConfig) { c.Fence.ProfileBinding = "v1:" + strings.Repeat("b", 64) }},
		{"account", func(c *ActiveIdentityReporterConfig) {
			_, c.Fence.AccountPeerID, c.RootPrivateKeyBase64 = b293ClientIdentity(t, 74)
		}},
		{"epoch", func(c *ActiveIdentityReporterConfig) { c.Fence.ConsentEpoch++ }},
	} {
		t.Run(change.name, func(t *testing.T) {
			x := b294New(t)
			x.ready()
			x.mark()
			x.reopen()
			change.apply(&x.config)
			x.ready()
			if b294Disk(t, x.config.StatePath).Marked {
				t.Fatal("mismatched owner inherited pending activity")
			}
		})
	}
}

func TestB294ReporterStorageFailureRemainsRetryableWithoutNetwork(t *testing.T) {
	h := b294New(t)
	h.ready()
	before := b294Read(t, h.config.StatePath)
	var attempts atomic.Int32
	h.files.onWrite(func(string, []byte) error { attempts.Add(1); return errors.New("public B294 disk failure") })
	b294Fixed(t, h.reporter.mark(h.config.Fence), errActiveIdentityReporterStorage)
	if attempts.Load() == 0 || !bytes.Equal(before, b294Read(t, h.config.StatePath)) || len(h.transport.recorded()) != 0 {
		t.Fatal("failed local mark was ACKed or attempted network")
	}
	h.files.onWrite(nil)
	h.mark()
	if !b294Disk(t, h.config.StatePath).Marked {
		t.Fatal("unchanged qualifying bit could not recover after writer repair")
	}
	b294PrivateRestoreControls(t)
}

func TestB294ReporterConcurrentMarksJoinOneDurableGeneration(t *testing.T) {
	h := b294New(t)
	h.ready()
	writes := h.files.count()
	barrier := b294NewBarrier(t)
	var first atomic.Bool
	h.files.onWrite(func(string, []byte) error {
		if first.CompareAndSwap(false, true) {
			return barrier.block()
		}
		return nil
	})
	operation := func() error {
		err := h.reporter.mark(h.config.Fence)
		if err == nil && h.files.count() == writes {
			return errors.New("public B294 joined mark ACK preceded durable generation")
		}
		return err
	}
	a := h.async(operation)
	b294Wait(t, barrier.entered, "first concurrent mark snapshot")
	b := h.async(operation)
	barrier.open()
	for _, result := range []<-chan error{a, b} {
		if err := b294Result(t, result, "joined concurrent mark"); err != nil {
			t.Fatal(err)
		}
	}
	if !b294Disk(t, h.config.StatePath).Marked || h.files.count() != writes+1 {
		t.Fatal("same-day concurrent marks lost activity or duplicated its durable snapshot")
	}
}

func TestB294ReporterAcknowledgesEveryConfiguredAuthorityIndependently(t *testing.T) {
	h := b294New(t)
	h.ready()
	h.mark()
	h.transport.start(h.transportID, []string{b294Address(h.relayA, 4101), b294Address(h.relayB, 4102)})
	h.flush()
	requests := h.transport.recorded()
	b294Proofs(t, requests, h.config)
	counts := map[string]int{}
	for _, request := range requests {
		counts[request.relay.String()]++
	}
	if counts[h.relayA] != 1 || counts[h.relayB] != 1 || len(requests) != 2 {
		t.Fatalf("configured authority attempts=%v", counts)
	}
	acked := b294Disk(t, h.config.StatePath).Acknowledged
	if len(acked) != 2 || !b294Contains(acked, h.relayA) || !b294Contains(acked, h.relayB) {
		t.Fatalf("independent durable authority ACKs=%v", acked)
	}
	h.flush()
	if len(h.transport.recorded()) != 2 {
		t.Fatal("already ACKed authorities were retried")
	}
	for _, stalledFirst := range []bool{true, false} {
		t.Run(fmt.Sprintf("stalled-first-%t", stalledFirst), func(t *testing.T) {
			x := b294New(t)
			x.ready()
			x.mark()
			stalled := b294NewBarrier(t)
			healthy := make(chan struct{})
			var healthyOnce sync.Once
			var waiting atomic.Bool
			stalledID, healthyID := x.relayA, x.relayB
			if !stalledFirst {
				stalledID, healthyID = x.relayB, x.relayA
			}
			x.transport.onExchange(func(_ context.Context, relay RelayInfo, _ []byte) ([]byte, error) {
				if relay.ID.String() == stalledID {
					waiting.Store(true)
					defer waiting.Store(false)
					if err := stalled.block(); err != nil {
						return nil, err
					}
					return nil, errors.New("public B294 controlled stalled authority failure")
				}
				healthyOnce.Do(func() { close(healthy) })
				return []byte(b294ACK), nil
			})
			x.transport.start(x.transportID, []string{b294Address(x.relayA, 4101), b294Address(x.relayB, 4102)})
			flushed := x.async(func() error { return x.reporter.flush(x.config.Fence) })
			b294Wait(t, stalled.entered, "stalled first authority")
			b294Wait(t, healthy, "independent healthy authority")
			if !waiting.Load() {
				t.Fatal("healthy authority only ran after the stalled authority finished")
			}
			stalled.open()
			err := b294Result(t, flushed, "flush after controlled authority cancellation")
			if err != nil {
				b294Fixed(t, err, errActiveIdentityReporterUnavailable)
			}
			if got := b294Disk(t, x.config.StatePath).Acknowledged; !reflect.DeepEqual(got, []string{healthyID}) {
				t.Fatalf("independent healthy durable ACK=%v", got)
			}
		})
	}
}

func b294Contains(values []string, wanted string) bool {
	for _, value := range values {
		if value == wanted {
			return true
		}
	}
	return false
}

func TestB294ReporterRelayAliasesDefaultsAndExplicitEmptyRemainDistinct(t *testing.T) {
	h := b294New(t)
	h.ready()
	raw := []string{b294Address(h.relayA, 4101), b294Address(h.relayA, 4102), b294Address(h.relayB, 4103)}
	relays, err := activeIdentityReporterRelays(raw)
	if err != nil || len(relays) != 2 || relays[0].ID.String() != h.relayA || len(relays[0].Addrs) != 2 || relays[1].ID.String() != h.relayB {
		t.Fatalf("alias authority control=%v error%v", relays, err)
	}
	firstAddress := relays[0].Addrs[0].String()
	raw[0] = "private-B294-address-that-must-not-be-logged"
	if relays[0].Addrs[0].String() != firstAddress {
		t.Fatal("relay result retained mutable input list")
	}
	defaults := map[peer.ID]bool{}
	for _, address := range DefaultRelayAddresses() {
		parsed, err := ma.NewMultiaddr(address)
		if err != nil {
			t.Fatal(err)
		}
		info, err := peer.AddrInfoFromP2pAddr(parsed)
		if err != nil {
			t.Fatal(err)
		}
		defaults[info.ID] = true
	}
	got, err := activeIdentityReporterRelays(nil)
	if err != nil || len(got) != len(defaults) {
		t.Fatalf("nil/default authorities=%d error%v", len(got), err)
	}
	for _, relay := range got {
		if !defaults[relay.ID] {
			t.Fatal("nil list invented an unconfigured host")
		}
	}
	if got, err := activeIdentityReporterRelays([]string{}); err != nil || len(got) != 0 {
		t.Fatalf("explicit empty fell back to defaults: %v", err)
	}
	var captured bytes.Buffer
	previous := log.Writer()
	log.SetOutput(&captured)
	got, err = activeIdentityReporterRelays([]string{raw[0]})
	log.SetOutput(previous)
	if err != nil || len(got) != 0 || strings.Contains(captured.String(), raw[0]) {
		t.Fatal("invalid explicit address logged private input or invented default authority")
	}
}

func TestB294ReporterPartialACKPersistsAndOnlyOutstandingAuthorityRetries(t *testing.T) {
	h := b294New(t)
	h.ready()
	h.mark()
	h.transport.onExchange(func(_ context.Context, relay RelayInfo, _ []byte) ([]byte, error) {
		if relay.ID.String() == h.relayA {
			return nil, errors.New("public B294 first authority unavailable")
		}
		return []byte(b294ACK), nil
	})
	h.transport.start(h.transportID, []string{b294Address(h.relayA, 4101), b294Address(h.relayB, 4102)})
	err := b294Result(t, h.async(func() error { return h.reporter.flush(h.config.Fence) }), "partial authority flush")
	if err != nil {
		b294Fixed(t, err, errActiveIdentityReporterUnavailable)
	}
	if got := b294Disk(t, h.config.StatePath).Acknowledged; !reflect.DeepEqual(got, []string{h.relayB}) {
		t.Fatalf("partial durable ACK=%v", got)
	}
	if len(h.transport.recorded()) != 2 {
		t.Fatal("one failed authority hid the independently healthy authority")
	}
	h.clock.set(h.clock.now().Add(activeIdentityReporterRetryDelay - time.Second))
	h.flush()
	if len(h.transport.recorded()) != 2 {
		t.Fatal("retry backoff was bypassed by another flush")
	}
	h.clock.set(h.clock.now().Add(time.Second))
	h.transport.onExchange(nil)
	h.flush()
	requests := h.transport.recorded()
	b294Proofs(t, requests, h.config)
	counts := map[string]int{}
	for _, request := range requests {
		counts[request.relay.String()]++
	}
	if counts[h.relayA] != 2 || counts[h.relayB] != 1 {
		t.Fatalf("per-authority retry counts=%v", counts)
	}
	h.reopen()
	h.ready()
	h.flush()
	if len(h.transport.recorded()) != 3 {
		t.Fatal("matching restart lost saved per-authority ACKs")
	}
}

func TestB294ReporterUnsupportedAuthorityIsBoundedAndDoesNotSuppressOthers(t *testing.T) {
	h := b294New(t)
	h.ready()
	h.mark()
	legacy := []byte(`{"status":"ERROR","error":"Unknown action: active_identity_v1"}`)
	if result, err := parseActiveIdentityResponse(legacy); err != nil || result != activeIdentityUnsupported {
		t.Fatal("actual B3 legacy control failed")
	}
	h.transport.onExchange(func(_ context.Context, relay RelayInfo, _ []byte) ([]byte, error) {
		if relay.ID.String() == h.relayA {
			return legacy, nil
		}
		return []byte(b294ACK), nil
	})
	h.transport.start(h.transportID, []string{b294Address(h.relayA, 4101), b294Address(h.relayB, 4102)})
	h.flush()
	if got := b294Disk(t, h.config.StatePath).Acknowledged; !reflect.DeepEqual(got, []string{h.relayB}) {
		t.Fatalf("unsupported became ACK or suppressed healthy peer: %v", got)
	}
	for range 4 {
		h.flush()
	}
	if len(h.transport.recorded()) != 2 {
		t.Fatal("old relay was retried for every flush")
	}
	h.clock.set(h.clock.now().Add(activeIdentityReporterUnsupported - time.Second))
	h.flush()
	if len(h.transport.recorded()) != 2 {
		t.Fatal("unsupported retry fired before fixed bound")
	}
	h.clock.set(h.clock.now().Add(time.Second))
	h.flush()
	counts := map[string]int{}
	for _, request := range h.transport.recorded() {
		counts[request.relay.String()]++
	}
	if counts[h.relayA] != 2 || counts[h.relayB] != 1 {
		t.Fatalf("unsupported/healthy independence=%v", counts)
	}
}

func TestB294ReporterRootProofUsesCapturedTransportAndRejectsLateOldHostACK(t *testing.T) {
	h := b294New(t)
	h.ready()
	h.mark()
	barrier := b294NewBarrier(t)
	var first atomic.Bool
	h.transport.onExchange(func(_ context.Context, _ RelayInfo, _ []byte) ([]byte, error) {
		if first.CompareAndSwap(false, true) {
			if err := barrier.block(); err != nil {
				return nil, err
			}
			return []byte(b294ACK), nil
		}
		return []byte(`{"status":"OK","version":1,"data":{"supported":true,"accepted":false}}`), nil
	})
	addresses := []string{b294Address(h.relayA, 4101)}
	h.transport.start(h.transportID, addresses)
	flushed := h.async(func() error { return h.reporter.flush(h.config.Fence) })
	b294Wait(t, barrier.entered, "old supplied host exchange")
	_, replacement, _ := b293ClientIdentity(t, 75)
	h.transport.start(replacement, addresses)
	barrier.open()
	err := b294Result(t, flushed, "late old-host response")
	if err != nil {
		b294Fixed(t, err, errActiveIdentityReporterUnavailable)
	}
	if len(b294Disk(t, h.config.StatePath).Acknowledged) != 0 {
		t.Fatal("late response from replaced host became durable ACK")
	}
	h.transport.onExchange(nil)
	h.clock.set(h.clock.now().Add(activeIdentityReporterRetryDelay))
	h.flush()
	requests := h.transport.recorded()
	b294Proofs(t, requests, h.config)
	if len(requests) < 2 || requests[0].transport != h.transportID || requests[len(requests)-1].transport != replacement || requests[0].generation == requests[len(requests)-1].generation {
		t.Fatal("retry did not capture replacement transport/generation")
	}
	for _, request := range requests[1:] {
		if request.transport != replacement {
			t.Fatal("a new attempt reused the replaced supplied transport")
		}
	}
}

func TestB294ReporterOFFPublicationFencesQueuedMarksAndInFlightACKBeforeConfigure(t *testing.T) {
	h := b294New(t)
	h.ready()
	h.mark()
	exchange := b294NewBarrier(t)
	h.transport.onExchange(func(context.Context, RelayInfo, []byte) ([]byte, error) {
		if err := exchange.block(); err != nil {
			return nil, err
		}
		return []byte(b294ACK), nil
	})
	h.transport.start(h.transportID, []string{b294Address(h.relayA, 4101)})
	flushed := h.async(func() error { return h.reporter.flush(h.config.Fence) })
	b294Wait(t, exchange.entered, "pre-OFF exchange")
	dispatch := b294NewBarrier(t)
	queued := h.async(func() error {
		if err := dispatch.block(); err != nil {
			return err
		}
		return h.reporter.mark(h.config.Fence)
	})
	b294Wait(t, dispatch.entered, "old mark pre-dispatch barrier")
	off := h.config.Fence
	off.Revision++
	off.ConsentEpoch++
	published := h.async(func() error {
		got, err := h.reporter.publishDesired(off, false, false)
		if err == nil && got != off {
			return errors.New("public B294 OFF fence mismatch")
		}
		return err
	})
	if err := b294Result(t, published, "synchronous OFF while network blocked"); err != nil {
		t.Fatal(err)
	}
	b294Fixed(t, h.reporter.mark(off), errActiveIdentityReporterStale)
	dispatch.open()
	b294Fixed(t, b294Result(t, queued, "queued old mark"), errActiveIdentityReporterStale)
	exchange.open()
	err := b294Result(t, flushed, "old ACK after OFF")
	if err != nil && !errors.Is(err, errActiveIdentityReporterStale) && !errors.Is(err, errActiveIdentityReporterUnavailable) {
		t.Fatal(err)
	}
	if len(b294Disk(t, h.config.StatePath).Acknowledged) != 0 {
		t.Fatal("old ACK crossed synchronous OFF fence")
	}
	disabled := h.config
	disabled.Fence = off
	disabled.RootPrivateKeyBase64 = ""
	if err := h.reporter.configure(disabled); err != nil {
		t.Fatal(err)
	}
	if disk := b294Disk(t, h.config.StatePath); disk.Marked || len(disk.Acknowledged) != 0 {
		t.Fatal("OFF retained old pending/ACK")
	}
	on := off
	on.Revision++
	_, err = h.reporter.publishDesired(on, true, false)
	b294Fixed(t, err, errActiveIdentityReporterInput)
	on.ConsentEpoch++
	h.publish(on, true, false)
	h.config.Fence = on
	if err := h.reporter.configure(h.config); err != nil {
		t.Fatal(err)
	}
	if b294Disk(t, h.config.StatePath).Marked {
		t.Fatal("OFF→ON new epoch revived activity without new communication")
	}
}

func TestB294ReporterReorderedConfigureCannotRearmOlderScope(t *testing.T) {
	control := b294New(t)
	control.ready()
	h := b294New(t)
	barrier := b294NewBarrier(t)
	var first atomic.Bool
	h.files.onRead(func(string) error {
		if first.CompareAndSwap(false, true) {
			return barrier.block()
		}
		return nil
	})
	h.publish(h.config.Fence, true, false)
	old := h.config
	configuring := h.async(func() error { return h.reporter.configure(old) })
	b294Wait(t, barrier.entered, "older configuration read")
	newer := old
	newer.Fence.Revision++
	newer.Fence.ProfileBinding = "v1:" + strings.Repeat("b", 64)
	_, newer.Fence.AccountPeerID, newer.RootPrivateKeyBase64 = b293ClientIdentity(t, 74)
	h.publish(newer.Fence, true, false)
	if err := h.reporter.configure(newer); err != nil {
		t.Fatal(err)
	}
	before := b294Read(t, newer.StatePath)
	barrier.open()
	b294Fixed(t, b294Result(t, configuring, "older configuration completion"), errActiveIdentityReporterStale)
	if !bytes.Equal(before, b294Read(t, newer.StatePath)) {
		t.Fatal("older configuration overwrote replacement scope")
	}
	_, err := h.reporter.publishDesired(old.Fence, true, false)
	b294Fixed(t, err, errActiveIdentityReporterStale)
	conflict := newer.Fence
	conflict.ProfileBinding = "v1:" + strings.Repeat("c", 64)
	_, err = h.reporter.publishDesired(conflict, true, false)
	b294Fixed(t, err, errActiveIdentityReporterInput)
	_, err = h.reporter.publishDesired(newer.Fence, false, false)
	b294Fixed(t, err, errActiveIdentityReporterInput)
	olderEpoch := newer.Fence
	olderEpoch.Revision++
	olderEpoch.ConsentEpoch--
	_, err = h.reporter.publishDesired(olderEpoch, true, false)
	b294Fixed(t, err, errActiveIdentityReporterStale)
	h.config = newer
	h.publish(newer.Fence, true, false)
	h.mark()
	b294Fixed(t, h.reporter.mark(old.Fence), errActiveIdentityReporterStale)
	if !b294Disk(t, newer.StatePath).Marked {
		t.Fatal("valid current scope could not progress after stale refusals")
	}
}

func TestB294ReporterDisposePreservesButExplicitRetirementCannotResurrect(t *testing.T) {
	h := b294New(t)
	h.ready()
	h.mark()
	h.transport.start(h.transportID, []string{b294Address(h.relayA, 4101)})
	h.flush()
	h.transport.stop()
	before := b294Disk(t, h.config.StatePath)
	if !before.Marked || !reflect.DeepEqual(before.Acknowledged, []string{h.relayA}) {
		t.Fatal("preserve/retire positive control missing")
	}
	unarmed := h.config.Fence
	unarmed.Revision++
	unarmed.ProfileBinding = ""
	unarmed.AccountPeerID = ""
	h.publish(unarmed, true, true)
	dispose := ActiveIdentityReporterConfig{Fence: unarmed, StatePath: h.config.StatePath, PreservePendingOnUnarm: true}
	conflictingDispose := dispose
	conflictingDispose.PreservePendingOnUnarm = false
	b294Fixed(t, h.reporter.configure(conflictingDispose), errActiveIdentityReporterInput)
	rootedDispose := dispose
	rootedDispose.RootPrivateKeyBase64 = h.config.RootPrivateKeyBase64
	b294Fixed(t, h.reporter.configure(rootedDispose), errActiveIdentityReporterInput)
	if err := h.reporter.configure(dispose); err != nil {
		t.Fatal(err)
	}
	b294Fixed(t, h.reporter.mark(h.config.Fence), errActiveIdentityReporterStale)
	b294Fixed(t, h.reporter.mark(unarmed), errActiveIdentityReporterStale)
	b294Fixed(t, h.reporter.flush(unarmed), errActiveIdentityReporterStale)
	if got := b294Disk(t, h.config.StatePath); !got.Marked || !reflect.DeepEqual(got.Acknowledged, before.Acknowledged) {
		t.Fatal("disposal destroyed eligible restart candidate")
	}
	h.reopen()
	h.config.Fence.Revision = unarmed.Revision + 1
	h.ready()
	if got := b294Disk(t, h.config.StatePath); !got.Marked || !reflect.DeepEqual(got.Acknowledged, before.Acknowledged) {
		t.Fatal("matching disposal restart did not preserve committed daily state")
	}
	retired := h.config.Fence
	retired.Revision++
	retired.ProfileBinding = ""
	retired.AccountPeerID = ""
	barrier := b294NewBarrier(t)
	var first atomic.Bool
	h.files.onWrite(func(string, []byte) error {
		if first.CompareAndSwap(false, true) {
			return barrier.block()
		}
		return nil
	})
	h.publish(retired, true, false)
	// The previous profile can overtake the retirement's background I/O. Its
	// old file must already be ineligible for recovery at the desired fence.
	h.config.Fence.Revision = retired.Revision + 1
	h.publish(h.config.Fence, true, false)
	reconfigured := h.async(func() error { return h.reporter.configure(h.config) })
	b294Wait(t, barrier.entered, "retirement/reconfiguration writer")
	barrier.open()
	if err := b294Result(t, reconfigured, "same account after explicit retirement"); err != nil {
		t.Fatal(err)
	}
	if got := b294Disk(t, h.config.StatePath); got.Marked || len(got.Acknowledged) != 0 {
		t.Fatal("A→empty→A resurrected old pending/ACK at same epoch/day")
	}
	lateRetire := ActiveIdentityReporterConfig{Fence: retired, StatePath: h.config.StatePath}
	b294Fixed(t, h.reporter.configure(lateRetire), errActiveIdentityReporterStale)
	h.files.onWrite(nil)
	h.mark()
	if !b294Disk(t, h.config.StatePath).Marked {
		t.Fatal("new qualifying communication could not progress after retirement")
	}
}

func TestB294ReporterMidnightAndDSTNeverCarryOldDayACKOrInventActivity(t *testing.T) {
	h := b294New(t)
	h.ready()
	h.mark()
	barrier := b294NewBarrier(t)
	h.transport.onExchange(func(_ context.Context, _ RelayInfo, raw []byte) ([]byte, error) {
		var body struct{ Day string }
		if json.Unmarshal(raw, &body) != nil {
			return nil, errors.New("public B294 malformed request")
		}
		if body.Day == "2026-03-28" {
			if err := barrier.block(); err != nil {
				return nil, err
			}
			return []byte(b294ACK), nil
		}
		return []byte(`{"status":"OK","version":1,"data":{"supported":true,"accepted":false}}`), nil
	})
	h.transport.start(h.transportID, []string{b294Address(h.relayA, 4101)})
	oldFlush := h.async(func() error { return h.reporter.flush(h.config.Fence) })
	b294Wait(t, barrier.entered, "old-day exchange")
	h.clock.set(b294Midnight(t, "2026-03-29"))
	marked := h.async(func() error { return h.reporter.mark(h.config.Fence) })
	if err := b294Result(t, marked, "new-day mark during old network flush"); err != nil {
		t.Fatal(err)
	}
	if got := b294Disk(t, h.config.StatePath); got.Day != "2026-03-29" || !got.Marked || len(got.Acknowledged) != 0 {
		t.Fatal("new-day mutation was blocked/lost behind old-day network work")
	}
	barrier.open()
	err := b294Result(t, oldFlush, "old-day ACK completion")
	if err != nil && !errors.Is(err, errActiveIdentityReporterUnavailable) {
		t.Fatal(err)
	}
	// A current-day refusal can never make an old ACK apply to the new bit.
	err = b294Result(t, h.async(func() error { return h.reporter.flush(h.config.Fence) }), "new-day refusal")
	if err != nil && !errors.Is(err, errActiveIdentityReporterUnavailable) {
		t.Fatal(err)
	}
	if got := b294Disk(t, h.config.StatePath); got.Day != "2026-03-29" || len(got.Acknowledged) != 0 {
		t.Fatal("closed-day response acknowledged current-day pending")
	}
	h.transport.onExchange(nil)
	h.clock.set(h.clock.now().Add(activeIdentityReporterRetryDelay))
	h.flush()
	if got := b294Disk(t, h.config.StatePath).Acknowledged; !reflect.DeepEqual(got, []string{h.relayA}) {
		t.Fatal("current-day positive ACK control missing")
	}
	b294Proofs(t, h.transport.recorded(), h.config)
	for _, tc := range []struct {
		day      string
		duration time.Duration
	}{{"2026-03-29", 23 * time.Hour}, {"2026-10-25", 25 * time.Hour}} {
		t.Run(tc.day, func(t *testing.T) {
			x := b294New(t)
			start := b294Midnight(t, tc.day)
			next := start.AddDate(0, 0, 1)
			if next.Sub(start) != tc.duration {
				t.Fatal("DST positive fixture is not the required calendar day")
			}
			x.clock.set(start.Add(time.Hour))
			x.ready()
			x.mark()
			x.clock.set(next)
			x.flush()
			got := b294Disk(t, x.config.StatePath)
			if got.Day != activitycalendar.Day(next) || got.Marked || len(got.Acknowledged) != 0 || len(x.transport.recorded()) != 0 {
				t.Fatal("calendar rollover invented a new mark or retained previous day")
			}
		})
	}
}

func b294PrivateRestoreControls(t *testing.T) {
	t.Helper()
	h := b294New(t)
	h.ready()
	// This API-produced unmarked state is semantically valid. Omitting/nulling
	// its required false boolean must not pass only because Go defaults to false.
	good := b294Read(t, h.config.StatePath)
	h.reopen()
	h.ready()
	if b294Disk(t, h.config.StatePath).Marked {
		t.Fatal("valid explicit false restore control changed")
	}
	file, err := os.Stat(h.config.StatePath)
	if err != nil || file.Mode().Perm() != 0600 {
		t.Fatalf("private snapshot mode=%v error%v", file, err)
	}
	dir, err := os.Stat(filepath.Dir(h.config.StatePath))
	if err != nil || dir.Mode().Perm() != 0700 {
		t.Fatalf("private owned directory mode=%v error%v", dir, err)
	}
	if err := os.Chmod(filepath.Dir(h.config.StatePath), 0755); err != nil {
		t.Fatal(err)
	}
	h.reopen()
	h.ready()
	dir, err = os.Stat(filepath.Dir(h.config.StatePath))
	if err != nil || dir.Mode().Perm() != 0700 {
		t.Fatalf("reused owned directory was not enforced0700: %v", err)
	}
	for _, forbidden := range []string{h.config.RootPrivateKeyBase64, h.config.Fence.AccountPeerID, h.config.Fence.ProfileBinding, h.transportID, `"revision"`, `"signature"`, `"events"`, `"transportPeerId"`} {
		if strings.Contains(string(good), forbidden) {
			t.Fatal("snapshot retained private root/owner material or process revision/event history")
		}
	}
	var object map[string]json.RawMessage
	if json.Unmarshal(good, &object) != nil || len(object) == 0 || !bytes.Equal(bytes.TrimSpace(object["marked"]), []byte("false")) {
		t.Fatal("explicit false JSON restore positive control missing")
	}
	// Re-encoding a valid object may change member ordering/whitespace. It must
	// remain loadable; this compact public fixture also makes duplicate editing
	// independent of the production writer's formatting choice.
	good, err = json.Marshal(object)
	if err != nil {
		t.Fatal(err)
	}
	h.reopen()
	if err := os.WriteFile(h.config.StatePath, good, 0600); err != nil {
		t.Fatal(err)
	}
	h.ready()
	mutated := func(change func(map[string]json.RawMessage)) []byte {
		var copy map[string]json.RawMessage
		if json.Unmarshal(good, &copy) != nil {
			t.Fatal("invalid valid fixture")
		}
		change(copy)
		raw, err := json.Marshal(copy)
		if err != nil {
			t.Fatal(err)
		}
		return raw
	}
	invalid := []struct {
		name string
		raw  []byte
	}{
		{"unknown-version", mutated(func(m map[string]json.RawMessage) { m["version"] = json.RawMessage("2") })},
		{"missing-version", mutated(func(m map[string]json.RawMessage) { delete(m, "version") })},
		{"missing-scope", mutated(func(m map[string]json.RawMessage) { delete(m, "scope_id") })},
		{"null-scope", mutated(func(m map[string]json.RawMessage) { m["scope_id"] = json.RawMessage("null") })},
		{"malformed-scope", mutated(func(m map[string]json.RawMessage) { m["scope_id"] = json.RawMessage(`"not-a-scope-fingerprint"`) })},
		{"missing-epoch", mutated(func(m map[string]json.RawMessage) { delete(m, "consent_epoch") })},
		{"null-epoch", mutated(func(m map[string]json.RawMessage) { m["consent_epoch"] = json.RawMessage("null") })},
		{"noncanonical-day", mutated(func(m map[string]json.RawMessage) { m["day"] = json.RawMessage(`"2026-3-28"`) })},
		{"future-day", mutated(func(m map[string]json.RawMessage) { m["day"] = json.RawMessage(`"2026-03-29"`) })},
		{"missing-marked", mutated(func(m map[string]json.RawMessage) { delete(m, "marked") })},
		{"null-marked", mutated(func(m map[string]json.RawMessage) { m["marked"] = json.RawMessage("null") })},
		{"wrong-marked-type", mutated(func(m map[string]json.RawMessage) { m["marked"] = json.RawMessage(`"false"`) })},
		{"unknown-field", mutated(func(m map[string]json.RawMessage) {
			m["rootPrivateKeyBase64"] = json.RawMessage(`"private-B294-corrupt-input"`)
		})},
		{"case-alias-field", mutated(func(m map[string]json.RawMessage) { m["Marked"] = m["marked"]; delete(m, "marked") })},
		{"invalid-ack-id", mutated(func(m map[string]json.RawMessage) {
			m["acknowledged"] = json.RawMessage(`["private-B294-invalid-relay"]`)
		})},
		{"trailing-json", append(bytes.Clone(good), []byte(` {"extra":true}`)...)},
		{"duplicate-field", bytes.Replace(good, []byte(`"marked":false`), []byte(`"marked":false,"marked":false`), 1)},
		{"oversized-valid-json", append(bytes.Clone(good), bytes.Repeat([]byte(" "), activeIdentityReporterSnapshotLimit+1)...)},
	}
	if bytes.Equal(good, invalid[len(invalid)-2].raw) {
		t.Fatal("duplicate-field fixture failed to modify valid JSON")
	}
	for _, tc := range invalid {
		t.Run(tc.name, func(t *testing.T) {
			x := b294New(t)
			x.ready()
			x.reopen()
			if err := os.WriteFile(x.config.StatePath, tc.raw, 0600); err != nil {
				t.Fatal(err)
			}
			x.publish(x.config.Fence, true, false)
			b294Fixed(t, x.reporter.configure(x.config), errActiveIdentityReporterStorage)
			if !bytes.Equal(tc.raw, b294Read(t, x.config.StatePath)) {
				t.Fatal("invalid restore changed original failure evidence")
			}
			b294Fixed(t, x.reporter.mark(x.config.Fence), errActiveIdentityReporterStale)
		})
	}
	if err := os.WriteFile(h.config.StatePath, good, 0600); err != nil {
		t.Fatal(err)
	}
	h.reopen()
	h.ready()
	h.mark()
	before := b294Read(t, h.config.StatePath)
	partial := h.config.StatePath + ".uncommitted-public-fixture"
	if err := os.WriteFile(partial, before[:len(before)/2], 0600); err != nil {
		t.Fatal(err)
	}
	h.reopen()
	h.ready()
	if !b294Disk(t, h.config.StatePath).Marked || !bytes.Equal(before[:len(before)/2], b294Read(t, partial)) {
		t.Fatal("restore promoted/modified an unrelated temporary file")
	}
	// Valid old data is expired, not corruption and never backfilled.
	h.reopen()
	h.clock.set(h.clock.now().AddDate(0, 0, 3))
	h.ready()
	if got := b294Disk(t, h.config.StatePath); got.Marked || len(got.Acknowledged) != 0 || got.Day != activitycalendar.Day(h.clock.now()) {
		t.Fatal("stale same-scope snapshot invented current activity")
	}
}
