package main

// Reuses the socket-scoped protocol fixture from go-mknoon/node/udp_blackhole_proxy_test.go.

import (
	"net"
	"sync"
	"testing"
)

// relayUDPBlackholeProxy sits between a node and a relay on loopback. It keys
// every client by its source socket (ip:port), so a test can blackhole exactly
// the sockets that existed before a network switch: packets from and to those
// sockets are dropped silently while the socket stays open. Only a brand-new
// socket (new source port) can get through afterwards. The relay sees each
// client socket as its own upstream session.
type relayUDPBlackholeProxy struct {
	front    *net.UDPConn
	bindIP   net.IP
	upstream *net.UDPAddr

	mu       sync.Mutex
	sessions map[string]*relayUDPProxySession
	order    []string
	dropped  map[string]bool
	closed   bool
	wg       sync.WaitGroup
}

type relayUDPProxySession struct {
	client *net.UDPAddr
	back   *net.UDPConn
}

func newRelayUDPBlackholeProxy(t *testing.T, upstream *net.UDPAddr) *relayUDPBlackholeProxy {
	t.Helper()
	return newRelayUDPBlackholeProxyOn(t, net.IPv4(127, 0, 0, 1), upstream)
}

// newRelayUDPBlackholeProxyOn binds the proxy's front and per-client back sockets
// to ip. On a non-loopback ip the relay observes the back socket as the
// client's address, which is the shape of a NAT mapping.
func newRelayUDPBlackholeProxyOn(t *testing.T, ip net.IP, upstream *net.UDPAddr) *relayUDPBlackholeProxy {
	t.Helper()
	front, err := net.ListenUDP("udp4", &net.UDPAddr{IP: ip, Port: 0})
	if err != nil {
		t.Fatalf("proxy front listen: %v", err)
	}
	p := &relayUDPBlackholeProxy{
		front:    front,
		bindIP:   ip,
		upstream: upstream,
		sessions: make(map[string]*relayUDPProxySession),
		dropped:  make(map[string]bool),
	}
	p.wg.Add(1)
	go p.frontLoop()
	t.Cleanup(p.Close)
	return p
}

func (p *relayUDPBlackholeProxy) Addr() *net.UDPAddr { return p.front.LocalAddr().(*net.UDPAddr) }

func (p *relayUDPBlackholeProxy) frontLoop() {
	defer p.wg.Done()
	buf := make([]byte, 65535)
	for {
		n, client, err := p.front.ReadFromUDP(buf)
		if err != nil {
			return
		}
		key := client.String()
		p.mu.Lock()
		if p.closed {
			p.mu.Unlock()
			return
		}
		if p.dropped[key] {
			p.mu.Unlock()
			continue
		}
		sess := p.sessions[key]
		if sess == nil {
			back, err := net.ListenUDP("udp4", &net.UDPAddr{IP: p.bindIP, Port: 0})
			if err != nil {
				p.mu.Unlock()
				continue
			}
			sess = &relayUDPProxySession{client: client, back: back}
			p.sessions[key] = sess
			p.order = append(p.order, key)
			p.wg.Add(1)
			go p.backLoop(sess)
		}
		p.mu.Unlock()
		_, _ = sess.back.WriteToUDP(buf[:n], p.upstream)
	}
}

func (p *relayUDPBlackholeProxy) backLoop(sess *relayUDPProxySession) {
	defer p.wg.Done()
	buf := make([]byte, 65535)
	key := sess.client.String()
	for {
		n, _, err := sess.back.ReadFromUDP(buf)
		if err != nil {
			return
		}
		p.mu.Lock()
		drop := p.dropped[key]
		p.mu.Unlock()
		if drop {
			continue
		}
		_, _ = p.front.WriteToUDP(buf[:n], sess.client)
	}
}

// BlackholeCurrentClients drops traffic for every client socket seen so far
// and returns them. Sockets created after this call are unaffected.
func (p *relayUDPBlackholeProxy) BlackholeCurrentClients() []string {
	p.mu.Lock()
	defer p.mu.Unlock()
	out := make([]string, 0, len(p.order))
	for _, key := range p.order {
		p.dropped[key] = true
		out = append(out, key)
	}
	return out
}

// ClientSockets lists the distinct client sockets (ip:port) in first-seen order.
func (p *relayUDPBlackholeProxy) ClientSockets() []string {
	p.mu.Lock()
	defer p.mu.Unlock()
	return append([]string(nil), p.order...)
}

func (p *relayUDPBlackholeProxy) Close() {
	p.mu.Lock()
	if p.closed {
		p.mu.Unlock()
		return
	}
	p.closed = true
	_ = p.front.Close()
	for _, sess := range p.sessions {
		_ = sess.back.Close()
	}
	p.mu.Unlock()
	p.wg.Wait()
}
