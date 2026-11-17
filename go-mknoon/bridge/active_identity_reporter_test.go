package bridge

import (
	"bytes"
	"crypto/ed25519"
	"encoding/base64"
	"encoding/json"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"

	libp2pcrypto "github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/mknoon/go-mknoon/activitycalendar"
	"github.com/mknoon/go-mknoon/node"
)

type b294BridgeHarness struct {
	t          *testing.T
	n          *node.Node
	fence      node.ActiveIdentityReporterFence
	latest     node.ActiveIdentityReporterFence
	root, path string
	workers    sync.WaitGroup
}

// Match the existing singleton isolation pattern, with a fixed bounded cleanup.
// Initialize creates a real Node.New; these fixtures never start a network host.
func b294BridgeNew(t *testing.T) *b294BridgeHarness {
	t.Helper()
	nodeMu.Lock()
	previousNode, previousAdapter := singletonNode, singletonCallbackAdapter
	singletonNode, singletonCallbackAdapter = nil, nil
	nodeMu.Unlock()
	Initialize(&noopCallback{})
	keyBytes := ed25519.NewKeyFromSeed(bytes.Repeat([]byte{81}, ed25519.SeedSize))
	key, err := libp2pcrypto.UnmarshalEd25519PrivateKey(keyBytes)
	if err != nil {
		t.Fatal(err)
	}
	account, err := peer.IDFromPrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	h := &b294BridgeHarness{t: t, n: currentCallBridgeNode(), root: base64.StdEncoding.EncodeToString(keyBytes), path: filepath.Join(t.TempDir(), "owned-local-reporter", "state.json"), fence: node.ActiveIdentityReporterFence{Revision: 1, ConsentEpoch: 7, ProfileBinding: "v1:" + strings.Repeat("a", 64), AccountPeerID: account.String()}}
	h.latest = h.fence
	if h.n == nil || h.n.Host() != nil {
		t.Fatal("Initialize did not produce a hostless node control")
	}
	t.Cleanup(func() {
		done := make(chan struct{})
		go func() {
			// Empty-preserve publication drops any live root/flush authority; it
			// does not erase the state being examined by this fixture.
			unarm := h.latest
			unarm.Revision++
			unarm.ProfileBinding = ""
			unarm.AccountPeerID = ""
			_, _ = h.n.PublishActiveIdentityReporterDesired(node.ActiveIdentityReporterDesiredRequest{Version: 1, ActiveIdentityReporterFence: unarm, Enabled: true, PreservePendingOnUnarm: true})
			_ = h.n.Stop()
			h.workers.Wait()
			nodeMu.Lock()
			singletonNode, singletonCallbackAdapter = previousNode, previousAdapter
			nodeMu.Unlock()
			close(done)
		}()
		select {
		case <-done:
		case <-time.After(2 * time.Second):
			t.Error("local reporter bridge fixture did not reset/join within2s")
		}
	})
	return h
}

func b294BridgeJSON(t *testing.T, value any) string {
	t.Helper()
	raw, err := json.Marshal(value)
	if err != nil {
		t.Fatal(err)
	}
	return string(raw)
}

func b294BridgeFence(f node.ActiveIdentityReporterFence) map[string]any {
	return map[string]any{"version": 1, "revision": f.Revision, "consentEpoch": f.ConsentEpoch, "profileBinding": f.ProfileBinding, "accountPeerId": f.AccountPeerID}
}

func (h *b294BridgeHarness) desiredPacket(f node.ActiveIdentityReporterFence, enabled, preserve bool) map[string]any {
	m := b294BridgeFence(f)
	m["enabled"] = enabled
	m["preservePendingOnUnarm"] = preserve
	return m
}
func (h *b294BridgeHarness) packet(op string, f node.ActiveIdentityReporterFence) map[string]any {
	m := b294BridgeFence(f)
	m["op"] = op
	return m
}
func (h *b294BridgeHarness) configPacket(f node.ActiveIdentityReporterFence, enabled, preserve bool, root string) map[string]any {
	m := h.packet("configure", f)
	m["enabled"] = enabled
	m["preservePendingOnUnarm"] = preserve
	m["statePath"] = h.path
	m["rootPrivateKeyBase64"] = root
	return m
}

func (h *b294BridgeHarness) callRaw(fn func(string) string, raw string) (string, map[string]any) {
	h.t.Helper()
	completed := make(chan string, 1)
	h.workers.Add(1)
	go func() { defer h.workers.Done(); completed <- fn(raw) }()
	var response string
	select {
	case response = <-completed:
	case <-time.After(2 * time.Second):
		h.t.Fatal("local bridge call exceeded fixed2s fixture bound")
	}
	var decoded map[string]any
	if json.Unmarshal([]byte(response), &decoded) != nil || decoded == nil {
		h.t.Fatal("local reporter returned a non-object JSON reply")
	}
	return response, decoded
}

func (h *b294BridgeHarness) call(fn func(string) string, packet map[string]any) (string, map[string]any) {
	h.t.Helper()
	return h.callRaw(fn, b294BridgeJSON(h.t, packet))
}

func b294BridgeSuccess(t *testing.T, response map[string]any, fields ...string) map[string]any {
	t.Helper()
	data, ok := response["data"].(map[string]any)
	if response["ok"] != true || len(response) != 2 || !ok || len(data) != len(fields) {
		t.Fatalf("local success envelope/field count invalid: %#v", response)
	}
	for _, field := range fields {
		if _, exists := data[field]; !exists {
			t.Fatalf("local reply omitted required field %s", field)
		}
	}
	return data
}

func b294BridgeError(t *testing.T, response map[string]any, code string) {
	t.Helper()
	message := map[string]string{"NOT_INITIALIZED": "call Initialize first", "INVALID_INPUT": "Invalid activity reporter request", "ACTIVE_IDENTITY_REPORTER_STALE": "Activity reporter owner is not current", "ACTIVE_IDENTITY_REPORTER_UNAVAILABLE": "Activity reporter unavailable"}[code]
	if response["ok"] != false || len(response) != 3 || response["errorCode"] != code || response["errorMessage"] != message {
		t.Fatalf("fixed local error envelope invalid: %#v", response)
	}
}

func (h *b294BridgeHarness) publish(f node.ActiveIdentityReporterFence, enabled, preserve bool) {
	h.t.Helper()
	_, response := h.call(PublishActiveIdentityReporterDesired, h.desiredPacket(f, enabled, preserve))
	data := b294BridgeSuccess(h.t, response, "revision", "consentEpoch")
	if data["revision"] != float64(f.Revision) || data["consentEpoch"] != float64(f.ConsentEpoch) {
		h.t.Fatal("desired reply changed local fence numbers")
	}
	h.latest = f
}

func (h *b294BridgeHarness) configure(f node.ActiveIdentityReporterFence, enabled, preserve bool, root string, want bool) {
	h.t.Helper()
	_, response := h.call(ActiveIdentityReporterV1, h.configPacket(f, enabled, preserve, root))
	data := b294BridgeSuccess(h.t, response, "configured", "revision", "consentEpoch")
	if data["configured"] != want || data["revision"] != float64(f.Revision) || data["consentEpoch"] != float64(f.ConsentEpoch) {
		h.t.Fatal("configure reply confused armed state or fence")
	}
}

func (h *b294BridgeHarness) mark(f node.ActiveIdentityReporterFence) {
	h.t.Helper()
	_, response := h.call(ActiveIdentityReporterV1, h.packet("mark", f))
	data := b294BridgeSuccess(h.t, response, "accepted", "revision", "consentEpoch")
	if data["accepted"] != true || data["revision"] != float64(f.Revision) || data["consentEpoch"] != float64(f.ConsentEpoch) {
		h.t.Fatal("local durable mark was not accepted with its captured fence")
	}
}

func (h *b294BridgeHarness) control() {
	h.t.Helper()
	h.publish(h.fence, true, false)
	h.configure(h.fence, true, false, h.root, true)
	h.mark(h.fence)
	if !b294BridgeDisk(h.t, h.path).Marked {
		h.t.Fatal("actual local configure+mark control did not persist activity")
	}
}

type b294BridgeState struct {
	Version      int      `json:"version"`
	Day          string   `json:"day"`
	Marked       bool     `json:"marked"`
	Acknowledged []string `json:"acknowledged"`
}

func b294BridgeDisk(t *testing.T, path string) b294BridgeState {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	var state b294BridgeState
	if json.Unmarshal(raw, &state) != nil {
		t.Fatal("local reporter state was not JSON")
	}
	return state
}
func b294BridgeBytes(t *testing.T, path string) []byte {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return raw
}

func TestB294BridgeUninitializedExportsReturnFixedErrors(t *testing.T) {
	h := b294BridgeNew(t)
	h.control()
	withNilSingleton(t)
	for _, call := range []struct {
		fn     func(string) string
		packet map[string]any
	}{{PublishActiveIdentityReporterDesired, h.desiredPacket(h.fence, true, false)}, {ActiveIdentityReporterV1, h.packet("mark", h.fence)}} {
		_, response := h.call(call.fn, call.packet)
		b294BridgeError(t, response, "NOT_INITIALIZED")
	}
	if currentCallBridgeNode() != nil {
		t.Fatal("local reporter export replaced an uninitialized Node")
	}
}

func TestB294BridgeDesiredOnlyHelperHasNoPathRootOrStorageSideEffect(t *testing.T) {
	h := b294BridgeNew(t)
	h.control()
	before := b294BridgeBytes(t, h.path)
	h.publish(h.fence, true, false)
	if !bytes.Equal(before, b294BridgeBytes(t, h.path)) {
		t.Fatal("same desired tuple performed a storage mutation")
	}
	for _, field := range []string{"op", "statePath", "rootPrivateKeyBase64"} {
		packet := h.desiredPacket(h.fence, true, false)
		packet[field] = "private-B294-desired-only-field"
		_, response := h.call(PublishActiveIdentityReporterDesired, packet)
		b294BridgeError(t, response, "INVALID_INPUT")
	}
	t.Run("fresh-node-memory-only-publication", func(t *testing.T) {
		x := b294BridgeNew(t)
		x.publish(x.fence, true, false)
		if _, err := os.Stat(x.path); !os.IsNotExist(err) {
			t.Fatalf("desired-only helper created local storage: %v", err)
		}
		_, response := x.call(ActiveIdentityReporterV1, x.packet("mark", x.fence))
		b294BridgeError(t, response, "ACTIVE_IDENTITY_REPORTER_STALE")
		if x.n.Host() != nil || currentCallBridgeNode() != x.n {
			t.Fatal("desired-only helper started/replaced Node")
		}
	})
}

func TestB294BridgeHostlessConfigureAndMarkAreDurableAcrossStop(t *testing.T) {
	h := b294BridgeNew(t)
	h.control()
	next := h.fence
	next.Revision++
	next.ProfileBinding = "v1:" + strings.Repeat("b", 64)
	h.publish(next, true, false)
	h.configure(next, true, false, h.root, true)
	if state := b294BridgeDisk(t, h.path); state.Marked || len(state.Acknowledged) != 0 {
		t.Fatal("configure marked a new profile without communication")
	}
	beforeDay := activitycalendar.Day(time.Now())
	h.mark(next)
	afterDay := activitycalendar.Day(time.Now())
	state := b294BridgeDisk(t, h.path)
	if !state.Marked || state.Version != 1 || state.Day != beforeDay && state.Day != afterDay || len(state.Acknowledged) != 0 {
		t.Fatalf("actual hostless local bridge mark state=%+v", state)
	}
	_, stopped := h.callRaw(func(string) string { return StopNode() }, "")
	if stopped["ok"] != true || currentCallBridgeNode() != h.n || h.n.Host() != nil {
		t.Fatal("Stop replaced the singleton or started a host")
	}
	h.mark(next)
	if !b294BridgeDisk(t, h.path).Marked {
		t.Fatal("host stop discarded local reporter state")
	}
}

func TestB294BridgeStrictLocalSchemaRejectsSmuggledOrMalformedInputs(t *testing.T) {
	h := b294BridgeNew(t)
	h.control()
	type malformed struct {
		name    string
		desired bool
		make    func(*b294BridgeHarness) string
	}
	change := func(op string, edit func(map[string]any)) func(*b294BridgeHarness) string {
		return func(x *b294BridgeHarness) string {
			packet := x.packet(op, x.fence)
			if op == "configure" {
				packet = x.configPacket(x.fence, true, false, x.root)
			}
			edit(packet)
			return b294BridgeJSON(x.t, packet)
		}
	}
	cases := []malformed{
		{"null", false, func(*b294BridgeHarness) string { return "null" }},
		{"array", false, func(*b294BridgeHarness) string { return "[]" }},
		{"malformed", false, func(*b294BridgeHarness) string { return `{"version":` }},
		{"missing-version", false, change("mark", func(m map[string]any) { delete(m, "version") })},
		{"null-version", false, change("mark", func(m map[string]any) { m["version"] = nil })},
		{"wrong-version", false, change("mark", func(m map[string]any) { m["version"] = 2 })},
		{"decimal-version", false, func(x *b294BridgeHarness) string {
			return strings.Replace(b294BridgeJSON(x.t, x.packet("mark", x.fence)), `"version":1`, `"version":1.0`, 1)
		}},
		{"unknown-op", false, change("mark", func(m map[string]any) { m["op"] = "capabilities" })},
		{"null-op", false, change("mark", func(m map[string]any) { m["op"] = nil })},
		{"missing-revision", false, change("mark", func(m map[string]any) { delete(m, "revision") })},
		{"null-revision", false, change("mark", func(m map[string]any) { m["revision"] = nil })},
		{"string-epoch", false, change("mark", func(m map[string]any) { m["consentEpoch"] = "7" })},
		{"missing-profile", false, change("mark", func(m map[string]any) { delete(m, "profileBinding") })},
		{"null-account", false, change("mark", func(m map[string]any) { m["accountPeerId"] = nil })},
		{"unknown-field", false, change("mark", func(m map[string]any) { m["private-B294-extra"] = "private-B294-input" })},
		{"case-alias", false, change("mark", func(m map[string]any) { m["ProfileBinding"] = m["profileBinding"]; delete(m, "profileBinding") })},
		{"duplicate-version", false, func(x *b294BridgeHarness) string {
			return strings.Replace(b294BridgeJSON(x.t, x.packet("mark", x.fence)), `"version":1`, `"version":1,"version":1`, 1)
		}},
		{"case-duplicate", false, change("mark", func(m map[string]any) { m["Revision"] = m["revision"] })},
		{"trailing-value", false, func(x *b294BridgeHarness) string {
			return b294BridgeJSON(x.t, x.packet("mark", x.fence)) + ` {"extra":true}`
		}},
		{"configure-missing-enabled", false, change("configure", func(m map[string]any) { delete(m, "enabled") })},
		{"configure-null-enabled", false, change("configure", func(m map[string]any) { m["enabled"] = nil })},
		{"configure-string-enabled", false, change("configure", func(m map[string]any) { m["enabled"] = "true" })},
		{"configure-null-root", false, change("configure", func(m map[string]any) { m["rootPrivateKeyBase64"] = nil })},
		{"configure-null-path", false, change("configure", func(m map[string]any) { m["statePath"] = nil })},
		{"configure-null-preserve", false, change("configure", func(m map[string]any) { m["preservePendingOnUnarm"] = nil })},
		{"mark-with-root", false, change("mark", func(m map[string]any) { m["rootPrivateKeyBase64"] = "private-B294-root" })},
		{"mark-with-enabled", false, change("mark", func(m map[string]any) { m["enabled"] = true })},
		{"flush-with-path", false, change("flush", func(m map[string]any) { m["statePath"] = "private-B294-path" })},
		{"flush-with-preserve", false, change("flush", func(m map[string]any) { m["preservePendingOnUnarm"] = false })},
		{"desired-with-op", true, func(x *b294BridgeHarness) string {
			m := x.desiredPacket(x.fence, true, false)
			m["op"] = "configure"
			return b294BridgeJSON(x.t, m)
		}},
		{"desired-null-enabled", true, func(x *b294BridgeHarness) string {
			m := x.desiredPacket(x.fence, true, false)
			m["enabled"] = nil
			return b294BridgeJSON(x.t, m)
		}},
		{"desired-null-preserve", true, func(x *b294BridgeHarness) string {
			m := x.desiredPacket(x.fence, true, false)
			m["preservePendingOnUnarm"] = nil
			return b294BridgeJSON(x.t, m)
		}},
		{"desired-missing-enabled", true, func(x *b294BridgeHarness) string {
			m := x.desiredPacket(x.fence, true, false)
			delete(m, "enabled")
			return b294BridgeJSON(x.t, m)
		}},
		{"desired-missing-version", true, func(x *b294BridgeHarness) string {
			m := x.desiredPacket(x.fence, true, false)
			delete(m, "version")
			return b294BridgeJSON(x.t, m)
		}},
		{"desired-duplicate-version", true, func(x *b294BridgeHarness) string {
			return strings.Replace(b294BridgeJSON(x.t, x.desiredPacket(x.fence, true, false)), `"version":1`, `"version":1,"version":1`, 1)
		}},
		{"desired-case-alias-enabled", true, func(x *b294BridgeHarness) string {
			m := x.desiredPacket(x.fence, true, false)
			m["Enabled"] = m["enabled"]
			delete(m, "enabled")
			return b294BridgeJSON(x.t, m)
		}},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			x := b294BridgeNew(t)
			x.control()
			before := b294BridgeBytes(t, x.path)
			fn := ActiveIdentityReporterV1
			if tc.desired {
				fn = PublishActiveIdentityReporterDesired
			}
			_, response := x.callRaw(fn, tc.make(x))
			b294BridgeError(t, response, "INVALID_INPUT")
			if !bytes.Equal(before, b294BridgeBytes(t, x.path)) {
				t.Fatal("malformed local request changed durable state")
			}
		})
	}
	t.Run("null-fields-from-valid-disabled-control", func(t *testing.T) {
		x := b294BridgeNew(t)
		x.control()
		off := x.fence
		off.Revision++
		off.ConsentEpoch++
		x.publish(off, false, false)
		x.configure(off, false, false, "", false)
		before := b294BridgeBytes(t, x.path)
		// False enabled, empty root and false preserve are genuinely valid here.
		// Null must fail its type boundary rather than an unrelated ON conflict
		// or missing-key rule after encoding/json supplies a zero value.
		for _, desired := range []bool{false, true} {
			packet := x.configPacket(off, false, false, "")
			fn := ActiveIdentityReporterV1
			if desired {
				packet = x.desiredPacket(off, false, false)
				fn = PublishActiveIdentityReporterDesired
			}
			packet["enabled"] = nil
			_, response := x.call(fn, packet)
			b294BridgeError(t, response, "INVALID_INPUT")
		}
		for _, field := range []string{"rootPrivateKeyBase64", "preservePendingOnUnarm"} {
			packet := x.configPacket(off, false, false, "")
			packet[field] = nil
			_, response := x.call(ActiveIdentityReporterV1, packet)
			b294BridgeError(t, response, "INVALID_INPUT")
		}
		if !bytes.Equal(before, b294BridgeBytes(t, x.path)) {
			t.Fatal("null field refusal changed valid disabled state")
		}
	})
	for _, op := range []string{"mark", "configure", "desired"} {
		packet := h.packet(op, h.fence)
		fn := ActiveIdentityReporterV1
		if op == "desired" {
			packet = h.desiredPacket(h.fence, true, false)
			fn = PublishActiveIdentityReporterDesired
		} else if op == "configure" {
			packet = h.configPacket(h.fence, true, false, h.root)
		}
		raw := b294BridgeJSON(t, packet)
		padded := raw + strings.Repeat(" ", node.ActiveIdentityReporterLocalLimit-len(raw))
		_, response := h.callRaw(fn, padded)
		var data map[string]any
		if op == "desired" {
			data = b294BridgeSuccess(t, response, "revision", "consentEpoch")
		} else if op == "configure" {
			data = b294BridgeSuccess(t, response, "configured", "revision", "consentEpoch")
		} else {
			data = b294BridgeSuccess(t, response, "accepted", "revision", "consentEpoch")
		}
		if data["revision"] != float64(h.fence.Revision) || data["consentEpoch"] != float64(h.fence.ConsentEpoch) {
			t.Fatal("bounded positive reply changed its captured fence")
		}
		_, response = h.callRaw(fn, padded+" ")
		b294BridgeError(t, response, "INVALID_INPUT")
	}
}

func TestB294BridgeFullCapturedFenceIsRequiredForLocalMarkAndFlush(t *testing.T) {
	h := b294BridgeNew(t)
	h.control()
	before := b294BridgeBytes(t, h.path)
	for _, edit := range []func(*node.ActiveIdentityReporterFence){func(f *node.ActiveIdentityReporterFence) { f.Revision++ }, func(f *node.ActiveIdentityReporterFence) { f.ConsentEpoch++ }, func(f *node.ActiveIdentityReporterFence) { f.ProfileBinding = "v1:" + strings.Repeat("b", 64) }, func(f *node.ActiveIdentityReporterFence) { f.AccountPeerID = bridgeB294OtherAccount(t) }} {
		f := h.fence
		edit(&f)
		for _, op := range []string{"mark", "flush"} {
			_, response := h.call(ActiveIdentityReporterV1, h.packet(op, f))
			b294BridgeError(t, response, "ACTIVE_IDENTITY_REPORTER_STALE")
		}
	}
	if !bytes.Equal(before, b294BridgeBytes(t, h.path)) {
		t.Fatal("stale full fence changed active owner's state")
	}
	next := h.fence
	next.Revision++
	next.ProfileBinding = "v1:" + strings.Repeat("b", 64)
	h.publish(next, true, false)
	_, response := h.call(ActiveIdentityReporterV1, h.packet("mark", h.fence))
	b294BridgeError(t, response, "ACTIVE_IDENTITY_REPORTER_STALE")
	h.configure(next, true, false, h.root, true)
	h.mark(next)
}

func bridgeB294OtherAccount(t *testing.T) string {
	t.Helper()
	raw := ed25519.NewKeyFromSeed(bytes.Repeat([]byte{82}, ed25519.SeedSize))
	key, err := libp2pcrypto.UnmarshalEd25519PrivateKey(raw)
	if err != nil {
		t.Fatal(err)
	}
	id, err := peer.IDFromPrivateKey(key)
	if err != nil {
		t.Fatal(err)
	}
	return id.String()
}

func TestB294BridgeOFFRetirementDisposalAndNewEpochStayDistinct(t *testing.T) {
	h := b294BridgeNew(t)
	h.control()
	off := h.fence
	off.Revision++
	off.ConsentEpoch++
	h.publish(off, false, false)
	_, response := h.call(ActiveIdentityReporterV1, h.packet("mark", h.fence))
	b294BridgeError(t, response, "ACTIVE_IDENTITY_REPORTER_STALE")
	h.configure(off, false, false, "", false)
	if b294BridgeDisk(t, h.path).Marked {
		t.Fatal("OFF failed to clear pending")
	}
	on := off
	on.Revision++
	_, response = h.call(PublishActiveIdentityReporterDesired, h.desiredPacket(on, true, false))
	b294BridgeError(t, response, "INVALID_INPUT")
	on.ConsentEpoch++
	h.publish(on, true, false)
	h.configure(on, true, false, h.root, true)
	if b294BridgeDisk(t, h.path).Marked {
		t.Fatal("new ON epoch invented activity")
	}
	h.mark(on)
	empty := on
	empty.Revision++
	empty.ProfileBinding = ""
	empty.AccountPeerID = ""
	h.publish(empty, true, false)
	h.configure(empty, true, false, "", false)
	restored := on
	restored.Revision = empty.Revision + 1
	h.publish(restored, true, false)
	h.configure(restored, true, false, h.root, true)
	if b294BridgeDisk(t, h.path).Marked {
		t.Fatal("same-day A→empty→A resurrected explicitly retired pending")
	}
	h.mark(restored)
	disposed := restored
	disposed.Revision++
	disposed.ProfileBinding = ""
	disposed.AccountPeerID = ""
	h.publish(disposed, true, true)
	h.configure(disposed, true, true, "", false)
	if !b294BridgeDisk(t, h.path).Marked {
		t.Fatal("disposal erased eligible inert recovery state")
	}
	_, response = h.call(ActiveIdentityReporterV1, h.packet("mark", restored))
	b294BridgeError(t, response, "ACTIVE_IDENTITY_REPORTER_STALE")
	restored.Revision = disposed.Revision + 1
	h.publish(restored, true, false)
	h.configure(restored, true, false, h.root, true)
	if !b294BridgeDisk(t, h.path).Marked {
		t.Fatal("matching scope refresh lost committed pending")
	}
}

func TestB294BridgeRepliesAndStateNeverEchoPrivateConfiguration(t *testing.T) {
	h := b294BridgeNew(t)
	h.control()
	for _, call := range []struct {
		fn     func(string) string
		packet map[string]any
		keys   []string
	}{{PublishActiveIdentityReporterDesired, h.desiredPacket(h.fence, true, false), []string{"revision", "consentEpoch"}}, {ActiveIdentityReporterV1, h.configPacket(h.fence, true, false, h.root), []string{"configured", "revision", "consentEpoch"}}, {ActiveIdentityReporterV1, h.packet("mark", h.fence), []string{"accepted", "revision", "consentEpoch"}}, {ActiveIdentityReporterV1, h.packet("flush", h.fence), []string{"queued", "revision", "consentEpoch"}}} {
		raw, response := h.call(call.fn, call.packet)
		data := b294BridgeSuccess(t, response, call.keys...)
		if data["revision"] != float64(call.packet["revision"].(int64)) || data["consentEpoch"] != float64(call.packet["consentEpoch"].(int64)) {
			t.Fatal("private reply control changed its captured request fence")
		}
		for _, secret := range []string{h.root, h.fence.AccountPeerID, h.fence.ProfileBinding, h.path, "signature"} {
			if strings.Contains(raw, secret) {
				t.Fatal("local success reply reflected scope/key/path/proof")
			}
		}
	}
	bad := h.configPacket(h.fence, true, false, "private-B294-invalid-secret")
	raw, response := h.call(ActiveIdentityReporterV1, bad)
	b294BridgeError(t, response, "INVALID_INPUT")
	if strings.Contains(raw, "private-B294-") || strings.Contains(raw, b294BridgeJSON(t, bad)) {
		t.Fatal("local error reflected untrusted configuration")
	}
	state := b294BridgeBytes(t, h.path)
	for _, forbidden := range []string{h.root, h.fence.AccountPeerID, h.fence.ProfileBinding, `"revision"`, `"signature"`, `"rootPrivateKeyBase64"`} {
		if bytes.Contains(state, []byte(forbidden)) {
			t.Fatal("actual Node adapter persisted private root/scope or process revision")
		}
	}
	file, err := os.Stat(h.path)
	if err != nil || file.Mode().Perm() != 0600 {
		t.Fatalf("local bridge file permission failed: %v", err)
	}
	dir, err := os.Stat(filepath.Dir(h.path))
	if err != nil || dir.Mode().Perm() != 0700 {
		t.Fatalf("local bridge private directory permission failed: %v", err)
	}
}

func TestB294BridgeFlushQueuesWithoutHostAndNeverClaimsRelayAcceptance(t *testing.T) {
	h := b294BridgeNew(t)
	h.control()
	observedBefore := activitycalendar.Day(time.Now())
	before := b294BridgeDisk(t, h.path)
	for range 4 {
		_, response := h.call(ActiveIdentityReporterV1, h.packet("flush", h.fence))
		data := b294BridgeSuccess(t, response, "queued", "revision", "consentEpoch")
		if data["queued"] != true || data["revision"] != float64(h.fence.Revision) || data["consentEpoch"] != float64(h.fence.ConsentEpoch) {
			t.Fatal("host-unavailable local flush was not queued with its captured fence")
		}
		if _, exists := data["accepted"]; exists {
			t.Fatal("flush confused queued work with relay ACK")
		}
	}
	after := b294BridgeDisk(t, h.path)
	observedAfter := activitycalendar.Day(time.Now())
	if len(after.Acknowledged) != 0 || h.n.Host() != nil || currentCallBridgeNode() != h.n {
		t.Fatal("queued hostless flush fabricated relay ACKs or host state")
	}
	unchanged := reflect.DeepEqual(before, after)
	if observedBefore == observedAfter && before.Day == observedBefore {
		if !after.Marked || !unchanged {
			t.Fatal("same-day queued hostless flush consumed activity or changed state")
		}
	} else if !unchanged {
		// A queued reply is admission, not an I/O-completion receipt. Across
		// midnight the old snapshot may remain unchanged while work is pending;
		// a completed expiry must advance within the observed Berlin days.
		if after.Day <= before.Day || after.Day < observedBefore || after.Day > observedAfter || after.Version != before.Version || after.Marked {
			t.Fatal("queued rollover invented activity or persisted an invalid day transition")
		}
	}
}
