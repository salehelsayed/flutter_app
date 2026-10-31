package main

import (
	"context"
	"crypto/rand"
	"fmt"
	"io"
	"net"
	"sync"
	"sync/atomic"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/p2p/protocol/circuitv2/client"
	"github.com/libp2p/go-libp2p/p2p/protocol/ping"
	"github.com/mknoon/relay-server/internal/circuitrelay"
	ma "github.com/multiformats/go-multiaddr"
)

// This is the relay-side causal condition from Astra's LL-24 handoff
// diagnostic: a locally retired connection still has a stream at the relay,
// while a fresh connection for the same identity has successfully reserved.
func TestLL24RelayStopUsesFreshReservation(t *testing.T) {
	for _, holdOldStream := range []bool{false, true} {
		name := "observation_without_held_stream"
		if holdOldStream {
			name = "blackholed_old_held_stream"
		}
		t.Run(name, func(t *testing.T) {
			ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
			t.Cleanup(cancel)
			var advertised atomic.Pointer[ma.Multiaddr]
			relayHost := ll24Host(t, libp2p.AddrsFactory(func([]ma.Multiaddr) []ma.Multiaddr {
				if address := advertised.Load(); address != nil {
					return []ma.Multiaddr{*address}
				}
				return nil
			}))
			service, err := relay.New(relayHost)
			if err != nil {
				t.Fatal(err)
			}
			t.Cleanup(func() { _ = service.Close() })
			// AddrsFactory deliberately hides the real relay address. Read the
			// actual listener instead, so Identify cannot bypass the proxy.
			var port string
			for _, listen := range relayHost.Network().ListenAddresses() {
				if value, err := listen.ValueForProtocol(ma.P_UDP); err == nil {
					port = value
					break
				}
			}
			if port == "" {
				t.Fatal("relay has no UDP listener")
			}
			upstream, err := net.ResolveUDPAddr("udp4", "127.0.0.1:"+port)
			if err != nil {
				t.Fatal(err)
			}
			proxy := newRelayUDPBlackholeProxy(t, upstream)
			proxyAddress := ma.StringCast(fmt.Sprintf("/ip4/127.0.0.1/udp/%d/quic-v1", proxy.Addr().Port))
			advertised.Store(&proxyAddress)
			relayInfo := peer.AddrInfo{ID: relayHost.ID(), Addrs: []ma.Multiaddr{proxyAddress}}
			key, _, err := crypto.GenerateEd25519Key(rand.Reader)
			if err != nil {
				t.Fatal(err)
			}
			old := ll24Host(t, libp2p.Identity(key))
			if _, err := client.Reserve(ctx, old, relayInfo); err != nil {
				t.Fatalf("old reservation: %v", err)
			}
			oldRemote := relayHost.Network().ConnsToPeer(old.ID())[0]
			if holdOldStream {
				received := make(chan struct{})
				release := make(chan struct{})
				t.Cleanup(func() { close(release) })
				relayHost.SetStreamHandler("/mknoon/test/ll24-held/1", func(s network.Stream) {
					defer s.Close()
					var b [1]byte
					if _, err := s.Read(b[:]); err != nil {
						return
					}
					close(received)
					<-release
				})
				s, err := old.NewStream(ctx, relayHost.ID(), "/mknoon/test/ll24-held/1")
				if err != nil {
					t.Fatal(err)
				}
				if _, err := s.Write([]byte{1}); err != nil {
					t.Fatal(err)
				}
				select {
				case <-received:
				case <-ctx.Done():
					t.Fatal("relay did not acknowledge held stream")
				}
			}
			if len(proxy.BlackholeCurrentClients()) == 0 {
				t.Fatal("old socket was not observed by the proxy")
			}
			// The app already retires locally. Its close packet cannot reach the
			// relay through the blackholed path, which is the failure condition.
			for _, conn := range old.Network().ConnsToPeer(relayHost.ID()) {
				_ = conn.Close()
			}
			fresh := ll24Host(t, libp2p.Identity(key))
			if _, err := client.Reserve(ctx, fresh, relayInfo); err != nil {
				t.Fatalf("fresh reservation using unmodified client: %v", err)
			}
			probeCtx, cancelProbe := context.WithCancel(ctx)
			select {
			case result := <-ping.Ping(probeCtx, fresh, relayHost.ID()):
				if result.Error != nil {
					t.Fatal(result.Error)
				}
			case <-ctx.Done():
				t.Fatal("fresh path did not answer ping")
			}
			cancelProbe()
			var freshRemote network.Conn
			for _, conn := range relayHost.Network().ConnsToPeer(fresh.ID()) {
				if conn.ID() != oldRemote.ID() {
					freshRemote = conn
				}
			}
			if freshRemote == nil || oldRemote.IsClosed() {
				t.Fatal("fixture must retain both the stale relay connection and the fresh one")
			}
			deadline := time.Now().Add(time.Second)
			for len(freshRemote.GetStreams()) != 0 && time.Now().Before(deadline) {
				time.Sleep(time.Millisecond)
			}
			if len(freshRemote.GetStreams()) != 0 {
				t.Fatal("fresh connection still has a setup stream")
			}
			if holdOldStream && len(oldRemote.GetStreams()) == 0 {
				t.Fatal("fixture lost the old held stream")
			}
			prober := ll24Host(t)
			circuit := proxyAddress.Encapsulate(ma.StringCast("/p2p/" + relayHost.ID().String() + "/p2p-circuit"))
			dialCtx, cancelDial := context.WithTimeout(ctx, 5*time.Second)
			defer cancelDial()
			if err := prober.Connect(dialCtx, peer.AddrInfo{ID: fresh.ID(), Addrs: []ma.Multiaddr{circuit}}); err != nil {
				t.Fatalf("inbound dial after successful fresh reservation: %v", err)
			}
			if oldRemote.IsClosed() {
				t.Fatal("fix closed the old connection instead of choosing the reservation connection")
			}
		})
	}
}

func TestLL24RelayRenewalPreservesExistingStreams(t *testing.T) {
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	t.Cleanup(cancel)
	relayHost := ll24Host(t, libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/0"))
	service, err := relay.New(relayHost)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = service.Close() })
	var tcp ma.Multiaddr
	for _, address := range relayHost.Network().ListenAddresses() {
		if _, err := address.ValueForProtocol(ma.P_TCP); err == nil {
			tcp = address
			break
		}
	}
	if tcp == nil {
		t.Fatal("relay has no TCP listener")
	}
	relayInfo := peer.AddrInfo{ID: relayHost.ID(), Addrs: []ma.Multiaddr{tcp}}
	key, _, err := crypto.GenerateEd25519Key(rand.Reader)
	if err != nil {
		t.Fatal(err)
	}
	old := ll24Host(t, libp2p.Identity(key))
	if _, err := client.Reserve(ctx, old, relayInfo); err != nil {
		t.Fatal(err)
	}
	relayHost.SetStreamHandler("/mknoon/test/ll24-live/1", func(s network.Stream) {
		defer s.Close()
		_, _ = io.Copy(s, s)
	})
	live, err := old.NewStream(ctx, relayHost.ID(), "/mknoon/test/ll24-live/1")
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = live.Close() })
	_ = live.SetDeadline(time.Now().Add(10 * time.Second))
	fresh := ll24Host(t, libp2p.Identity(key))
	if _, err := client.Reserve(ctx, fresh, relayInfo); err != nil {
		t.Fatal(err)
	}
	fresh.SetStreamHandler("/mknoon/test/ll24-fresh/1", func(s network.Stream) {
		defer s.Close()
		_, _ = io.Copy(s, s)
	})
	prober := ll24Host(t)
	circuit := tcp.Encapsulate(ma.StringCast("/p2p/" + relayHost.ID().String() + "/p2p-circuit"))
	if err := prober.Connect(ctx, peer.AddrInfo{ID: fresh.ID(), Addrs: []ma.Multiaddr{circuit}}); err != nil {
		t.Fatal(err)
	}
	// Keep traffic on the old reservation connection while several relayed
	// application streams use the new one. Renewal must not close either path.
	errors := make(chan error, 9)
	var workers sync.WaitGroup
	workers.Add(1)
	go func() {
		defer workers.Done()
		payload := []byte("old-stream-still-live")
		if _, err := live.Write(payload); err != nil {
			errors <- err
			return
		}
		got := make([]byte, len(payload))
		if _, err := io.ReadFull(live, got); err != nil || string(got) != string(payload) {
			errors <- fmt.Errorf("old stream read %q: %v", got, err)
		}
	}()
	for i := range 8 {
		workers.Add(1)
		go func() {
			defer workers.Done()
			s, err := prober.NewStream(network.WithAllowLimitedConn(ctx, "LL-24 preservation"), fresh.ID(), "/mknoon/test/ll24-fresh/1")
			if err != nil {
				errors <- err
				return
			}
			defer s.Close()
			_ = s.SetDeadline(time.Now().Add(10 * time.Second))
			payload := []byte(fmt.Sprintf("fresh-stream-%d", i))
			if _, err := s.Write(payload); err != nil {
				errors <- err
				return
			}
			got := make([]byte, len(payload))
			if _, err := io.ReadFull(s, got); err != nil || string(got) != string(payload) {
				errors <- fmt.Errorf("new stream read %q: %v", got, err)
			}
		}()
	}
	workers.Wait()
	close(errors)
	for err := range errors {
		t.Error(err)
	}
}

func ll24Host(t *testing.T, options ...libp2p.Option) host.Host {
	t.Helper()
	defaults := []libp2p.Option{
		libp2p.ListenAddrStrings("/ip4/127.0.0.1/udp/0/quic-v1"),
		libp2p.EnableRelay(), libp2p.ForceReachabilityPublic(),
	}
	h, err := libp2p.New(append(defaults, options...)...)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = h.Close() })
	return h
}
