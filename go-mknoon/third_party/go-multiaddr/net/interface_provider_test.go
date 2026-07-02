package manet

import (
	"net"
	"reflect"
	"strings"
	"sync"
	"testing"
	"time"
)

// Test-Flight-Improv/190 — fork-module unit tests for the interface-address
// provider seam. These run only under `cd third_party/go-multiaddr && go test
// ./net/` (the go-mknoon module's ./... does NOT traverse this separate
// module). Marker IP 192.168.190.10 discriminates injected addrs from whatever
// real interfaces the test machine happens to have.

func ipNetAddr(ip string) net.Addr {
	parsed := net.ParseIP(ip)
	mask := net.CIDRMask(24, 32)
	if parsed.To4() == nil {
		mask = net.CIDRMask(64, 128)
	}
	return &net.IPNet{IP: parsed, Mask: mask}
}

// Catalog 1 (TC-190-01 seam floor) — InterfaceMultiaddrs must consult the
// injected provider. RED on the byte-neutral scaffold: net.go still calls
// net.InterfaceAddrs directly (upstream body), so the injected marker is
// ignored and the machine's real interfaces are returned instead.
func TestInterfaceMultiaddrsUsesInjectedProvider(t *testing.T) {
	const marker = "192.168.190.10"
	restore := SetInterfaceAddrsProviderForTests(func() ([]net.Addr, error) {
		return []net.Addr{ipNetAddr(marker)}, nil
	})
	defer restore()

	addrs, err := InterfaceMultiaddrs()
	if err != nil {
		t.Fatalf("InterfaceMultiaddrs: %v", err)
	}
	if len(addrs) != 1 {
		t.Fatalf("expected exactly the 1 injected addr, got %d: %v", len(addrs), addrs)
	}
	if got := addrs[0].String(); !strings.Contains(got, marker) {
		t.Fatalf("injected marker %s not routed into enumeration; got %s", marker, got)
	}
}

// Catalog 2 (TC-190-01 seam floor) — the provider swap must be race-safe AND
// observable in enumeration output. RED on scaffold: Set/read of the atomic var
// works but InterfaceMultiaddrs never consults it, so the swap is invisible in
// output. Mutation lock: replacing the atomic pointer with a plain package var
// makes this -race test flag the concurrent Set/read.
func TestProviderSwapIsRaceSafe(t *testing.T) {
	const marker = "192.168.190.10"
	orig := SetInterfaceAddrsProviderForTests(func() ([]net.Addr, error) {
		return []net.Addr{ipNetAddr(marker)}, nil
	})
	defer orig()

	var wg sync.WaitGroup
	stop := make(chan struct{})

	// Readers exercise the exact path basichost's addr-change ticker takes.
	for i := 0; i < 4; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for {
				select {
				case <-stop:
					return
				default:
					_, _ = InterfaceMultiaddrs()
				}
			}
		}()
	}
	// Swappers churn the provider concurrently.
	for i := 0; i < 4; i++ {
		wg.Add(1)
		go func() {
			defer wg.Done()
			for j := 0; j < 50; j++ {
				r := SetInterfaceAddrsProviderForTests(func() ([]net.Addr, error) {
					return []net.Addr{ipNetAddr("192.168.190.20")}, nil
				})
				r() // restore immediately so the final assertion is deterministic
			}
		}()
	}

	time.Sleep(50 * time.Millisecond)
	close(stop)
	wg.Wait()

	addrs, err := InterfaceMultiaddrs()
	if err != nil {
		t.Fatalf("InterfaceMultiaddrs: %v", err)
	}
	found := false
	for _, a := range addrs {
		if strings.Contains(a.String(), marker) {
			found = true
		}
	}
	if !found {
		t.Fatalf("provider swap not observed in InterfaceMultiaddrs output: %v", addrs)
	}
}

// Catalog 3 (TC-190-30 fork neutrality) — with NO injection the non-android
// default is byte-for-byte stdlib net.InterfaceAddrs. GREEN on the scaffold and
// after routing; its RED proof is the mutation (make the !android default
// deviate from stdlib, e.g. filter/reorder). Guards iOS/macOS neutrality.
func TestNonAndroidDefaultIsStdlibPassthrough(t *testing.T) {
	raw, err := net.InterfaceAddrs()
	if err != nil {
		t.Fatalf("net.InterfaceAddrs: %v", err)
	}
	var want []string
	for _, a := range raw {
		m, err := FromNetAddr(a)
		if err != nil {
			// Upstream InterfaceMultiaddrs would also error out here; skip such
			// addrs on both sides to keep the comparison apples-to-apples.
			continue
		}
		want = append(want, m.String())
	}

	got, err := InterfaceMultiaddrs()
	if err != nil {
		t.Fatalf("InterfaceMultiaddrs: %v", err)
	}
	var gotStrs []string
	for _, m := range got {
		gotStrs = append(gotStrs, m.String())
	}

	if !reflect.DeepEqual(want, gotStrs) {
		t.Fatalf("non-android default is not a stdlib passthrough:\n want %v\n got  %v", want, gotStrs)
	}
}
