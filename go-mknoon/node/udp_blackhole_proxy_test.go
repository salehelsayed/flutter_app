package node

import (
	"net"
	"sync"
	"testing"
)

// udpBlackholeProxy sits between a node and a relay on loopback. It keys
// every client by its source socket (ip:port), so a test can blackhole exactly
// the sockets that existed before a network switch: packets from and to those
// sockets are dropped silently while the socket stays open. Only a brand-new
// socket (new source port) can get through afterwards. The relay sees each
// client socket as its own upstream session.
type udpBlackholeProxy struct {
	front    *net.UDPConn
	bindIP   net.IP
	upstream *net.UDPAddr

	mu       sync.Mutex
	sessions map[string]*udpProxySession
	order    []string
	dropped  map[string]bool
	closed   bool
	wg       sync.WaitGroup
}

type udpProxySession struct {
	client *net.UDPAddr
	back   *net.UDPConn
}

func newUDPBlackholeProxy(t *testing.T, upstream *net.UDPAddr) *udpBlackholeProxy {
	t.Helper()
	return newUDPBlackholeProxyOn(t, net.IPv4(127, 0, 0, 1), upstream)
}

// newUDPBlackholeProxyOn binds the proxy's front and per-client back sockets
// to ip. On a non-loopback ip the relay observes the back socket as the
// client's address, which is the shape of a NAT mapping.
func newUDPBlackholeProxyOn(t *testing.T, ip net.IP, upstream *net.UDPAddr) *udpBlackholeProxy {
	t.Helper()
	front, err := net.ListenUDP("udp4", &net.UDPAddr{IP: ip, Port: 0})
	if err != nil {
		t.Fatalf("proxy front listen: %v", err)
	}
	p := &udpBlackholeProxy{
		front:    front,
		bindIP:   ip,
		upstream: upstream,
		sessions: make(map[string]*udpProxySession),
		dropped:  make(map[string]bool),
	}
	p.wg.Add(1)
	go p.frontLoop()
	t.Cleanup(p.Close)
	return p
}

func (p *udpBlackholeProxy) Addr() *net.UDPAddr { return p.front.LocalAddr().(*net.UDPAddr) }

func (p *udpBlackholeProxy) frontLoop() {
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
			sess = &udpProxySession{client: client, back: back}
			p.sessions[key] = sess
			p.order = append(p.order, key)
			p.wg.Add(1)
			go p.backLoop(sess)
		}
		p.mu.Unlock()
		_, _ = sess.back.WriteToUDP(buf[:n], p.upstream)
	}
}

func (p *udpBlackholeProxy) backLoop(sess *udpProxySession) {
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
func (p *udpBlackholeProxy) BlackholeCurrentClients() []string {
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
func (p *udpBlackholeProxy) ClientSockets() []string {
	p.mu.Lock()
	defer p.mu.Unlock()
	return append([]string(nil), p.order...)
}

func (p *udpBlackholeProxy) Close() {
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

// BackAddrForClientPort returns the upstream-facing socket the proxy opened
// for the client socket bound to port: the address the relay observes for
// that client. nil when the relay never saw that client socket.
func (p *udpBlackholeProxy) BackAddrForClientPort(port int) *net.UDPAddr {
	p.mu.Lock()
	defer p.mu.Unlock()
	for _, key := range p.order {
		if sess := p.sessions[key]; sess.client.Port == port {
			return sess.back.LocalAddr().(*net.UDPAddr)
		}
	}
	return nil
}

// BlackholeClientPort drops traffic for the one client socket bound to port,
// leaving every other socket, including ones created later, untouched.
func (p *udpBlackholeProxy) BlackholeClientPort(port int) bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	for _, key := range p.order {
		if p.sessions[key].client.Port == port {
			p.dropped[key] = true
			return true
		}
	}
	return false
}
