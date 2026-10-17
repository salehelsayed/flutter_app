package node

import (
	"context"
	"errors"
	"fmt"
	"net"
	"strconv"
	"sync"
	"sync/atomic"

	"github.com/libp2p/go-libp2p"
	libp2pconfig "github.com/libp2p/go-libp2p/config"
	coreconnmgr "github.com/libp2p/go-libp2p/core/connmgr"
	ic "github.com/libp2p/go-libp2p/core/crypto"
	"github.com/libp2p/go-libp2p/core/network"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/core/pnet"
	tpt "github.com/libp2p/go-libp2p/core/transport"
	"github.com/libp2p/go-libp2p/p2p/net/swarm"
	libp2pquic "github.com/libp2p/go-libp2p/p2p/transport/quic"
	"github.com/libp2p/go-libp2p/p2p/transport/quicreuse"
	"github.com/libp2p/go-libp2p/p2p/transport/tcp"
	libp2pwebrtc "github.com/libp2p/go-libp2p/p2p/transport/webrtc"
	ws "github.com/libp2p/go-libp2p/p2p/transport/websocket"
	webtransport "github.com/libp2p/go-libp2p/p2p/transport/webtransport"
	ma "github.com/multiformats/go-multiaddr"
	"github.com/quic-go/quic-go"
)

// udpListenFunc creates the UDP socket for one fresh relay dial. nil means
// net.ListenUDP. Tests wrap it to count and observe sockets; a platform owner
// can bind the new socket to the current default network here before use.
type udpListenFunc func(network string, laddr *net.UDPAddr) (net.PacketConn, error)

// freshQUICDialPolicy decides which peers must be dialed on a brand-new UDP
// socket. While a network handoff attempt runs, the configured relay peers are
// armed for its epoch; every other dial keeps libp2p's normal socket reuse.
type freshQUICDialPolicy struct {
	mu    sync.Mutex
	armed map[peer.ID]uint64
	fresh map[string]freshConnRecord

	listenUDP udpListenFunc

	created atomic.Int64
	open    atomic.Int64

	// transport is the host's QUIC transport built by newTransport, so the
	// node can move its listeners on a network path change.
	transport atomic.Pointer[freshAwareQUICTransport]

	// disabledForTests routes armed dials through ordinary reuse and keeps
	// the listeners where they are. It exists only so a test can show what a
	// plain close-and-redial does.
	disabledForTests bool
}

type freshConnRecord struct {
	peer  peer.ID
	epoch uint64
}

func newFreshQUICDialPolicy() *freshQUICDialPolicy {
	return &freshQUICDialPolicy{
		armed: make(map[peer.ID]uint64),
		fresh: make(map[string]freshConnRecord),
	}
}

func (p *freshQUICDialPolicy) arm(epoch uint64, peers []peer.ID) {
	p.mu.Lock()
	defer p.mu.Unlock()
	for k, rec := range p.fresh {
		if rec.epoch < epoch {
			delete(p.fresh, k)
		}
	}
	for _, pid := range peers {
		p.armed[pid] = epoch
	}
}

func (p *freshQUICDialPolicy) disarm(epoch uint64) {
	p.mu.Lock()
	defer p.mu.Unlock()
	for pid, e := range p.armed {
		if e == epoch {
			delete(p.armed, pid)
		}
	}
}

func (p *freshQUICDialPolicy) disarmAll() {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.armed = make(map[peer.ID]uint64)
}

func (p *freshQUICDialPolicy) armedEpoch(pid peer.ID) (uint64, bool) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if p.disabledForTests {
		return 0, false
	}
	e, ok := p.armed[pid]
	return e, ok
}

func (p *freshQUICDialPolicy) recordFresh(c network.ConnMultiaddrs, pid peer.ID, epoch uint64) {
	p.mu.Lock()
	defer p.mu.Unlock()
	p.fresh[c.LocalMultiaddr().String()] = freshConnRecord{peer: pid, epoch: epoch}
}

// freshEpoch reports the handoff epoch whose fresh socket carries this
// connection. Ordinary (reused-socket) connections report false.
func (p *freshQUICDialPolicy) freshEpoch(c network.ConnMultiaddrs) (uint64, bool) {
	p.mu.Lock()
	defer p.mu.Unlock()
	rec, ok := p.fresh[c.LocalMultiaddr().String()]
	return rec.epoch, ok
}

func (p *freshQUICDialPolicy) createdSockets() int64 { return p.created.Load() }
func (p *freshQUICDialPolicy) openSockets() int64    { return p.open.Load() }

func (p *freshQUICDialPolicy) plainRedialForTests() bool {
	p.mu.Lock()
	defer p.mu.Unlock()
	return p.disabledForTests
}

// udpListen is the socket seam for every socket the node creates itself.
func (p *freshQUICDialPolicy) udpListen(network string, laddr *net.UDPAddr) (net.PacketConn, error) {
	if p.listenUDP != nil {
		return p.listenUDP(network, laddr)
	}
	return net.ListenUDP(network, laddr)
}

// nodeTransportOptions is libp2p.DefaultTransports with the QUIC transport
// replaced by the fresh-dial aware wrapper. Adding any Transport option turns
// the default set off, so the other four are listed explicitly in the same
// order as upstream.
func nodeTransportOptions(p *freshQUICDialPolicy) []libp2p.Option {
	return []libp2p.Option{
		libp2p.Transport(tcp.NewTCPTransport),
		libp2p.Transport(p.newTransport),
		libp2p.Transport(ws.New),
		libp2p.Transport(webtransport.New),
		libp2p.Transport(libp2pwebrtc.New),
	}
}

// newTransport has the same parameter list as quic.NewTransport so libp2p's
// dependency injection resolves it the same way.
func (p *freshQUICDialPolicy) newTransport(key ic.PrivKey, cm *quicreuse.ConnManager, psk pnet.PSK, gater coreconnmgr.ConnectionGater, rcmgr network.ResourceManager) (tpt.Transport, error) {
	inner, err := libp2pquic.NewTransport(key, cm, psk, gater, rcmgr)
	if err != nil {
		return nil, err
	}
	srk, err := libp2pconfig.PrivKeyToStatelessResetKey(key)
	if err != nil {
		return nil, err
	}
	tokenKey, err := libp2pconfig.PrivKeyToTokenGeneratorKey(key)
	if err != nil {
		return nil, err
	}
	t := &freshAwareQUICTransport{
		stock:    inner,
		inner:    inner,
		policy:   p,
		key:      key,
		gater:    gater,
		rcmgr:    rcmgr,
		srk:      srk,
		tokenKey: tokenKey,
	}
	p.transport.Store(t)
	return t, nil
}

// freshAwareQUICTransport is the host's QUIC transport. Ordinary dials go to
// the current inner transport: the stock one until the first network path
// change, then the newest generation, whose own ConnManager only knows
// sockets born on that network. A dial to a peer armed by the policy for an
// epoch leaves from that epoch's listener generation, so the connection's
// local address is a listen address and identify can learn the new NAT
// mapping from it; when the listeners could not move (fixed ListenPort) it
// gets a dedicated UDP socket instead. Listeners, hole punching and socket
// reuse keep their stock behavior inside whichever inner transport is
// current.
type freshAwareQUICTransport struct {
	mu    sync.RWMutex
	stock tpt.Transport
	inner tpt.Transport
	// innerGen is the generation inner belongs to; nil while inner is stock.
	innerGen *quicGeneration
	// generations are the transports born at path changes, oldest first.
	generations []*quicGeneration

	policy   *freshQUICDialPolicy
	key      ic.PrivKey
	gater    coreconnmgr.ConnectionGater
	rcmgr    network.ResourceManager
	srk      quic.StatelessResetKey
	tokenKey quic.TokenGeneratorKey
}

var _ tpt.Transport = (*freshAwareQUICTransport)(nil)

var errQUICNotThisTransport = errors.New("swarm serves QUIC through another transport")

func (t *freshAwareQUICTransport) current() tpt.Transport {
	t.mu.RLock()
	defer t.mu.RUnlock()
	return t.inner
}

func (t *freshAwareQUICTransport) Dial(ctx context.Context, raddr ma.Multiaddr, p peer.ID) (tpt.CapableConn, error) {
	epoch, armed := t.policy.armedEpoch(p)
	if !armed {
		return t.current().Dial(ctx, raddr, p)
	}
	if simConnect, isClient, _ := network.GetSimultaneousConnect(ctx); simConnect && !isClient {
		// A hole punch must answer from the listener socket.
		return t.current().Dial(ctx, raddr, p)
	}
	if g := t.generationFor(epoch); g != nil {
		// The listeners already moved for this epoch: dial from the new
		// listener socket. libp2p records a peer's observation of us only
		// when the connection's local ip/udp is one of our listen addresses
		// (go-libp2p v0.50.0 p2p/host/observedaddrs/manager.go:391-404), and
		// after a handoff the relay is the one peer that can report the new
		// NAT mapping hole punching needs.
		c, err := g.transport.Dial(ctx, raddr, p)
		if err != nil {
			return nil, err
		}
		t.policy.recordFresh(c, p, epoch)
		return c, nil
	}
	return t.dialFresh(ctx, raddr, p, epoch)
}

// generationFor returns the current listener generation when it was born on
// this epoch's path change, nil otherwise: the listeners were kept (fixed
// ListenPort, Listen failed) or a newer epoch already moved them again.
func (t *freshAwareQUICTransport) generationFor(epoch uint64) *quicGeneration {
	t.mu.RLock()
	defer t.mu.RUnlock()
	if t.innerGen != nil && t.innerGen.epoch == epoch {
		return t.innerGen
	}
	return nil
}

// rebindListeners moves the swarm's QUIC listeners to sockets created now, on
// the current default network, and makes those sockets the ones ordinary
// dials and this epoch's handoff dials reuse from here on. The old listener
// sockets stay open for the connections already on them and close once those
// are gone. Listen ports change. It returns how many listeners moved.
//
// Fixed ListenPort is an unsupported static-port constraint for network
// handoff: the listener keeps its old socket, because a second socket on the
// same port (SO_REUSEPORT) would split incoming packets between the two. The
// handoff then falls back to a dedicated dial-only socket for the relay, so
// the relay session still moves to the new network, but the listener, every
// later ordinary dial and the observed NAT mapping stay on the old socket. The
// app's default (ListenPort 0, random) is the supported mode.
func (t *freshAwareQUICTransport) rebindListeners(sw *swarm.Swarm, listenPort int, epoch uint64) (int, error) {
	var old []ma.Multiaddr
	for _, a := range sw.ListenAddresses() {
		if _, err := a.ValueForProtocol(ma.P_QUIC_V1); err != nil {
			continue
		}
		if sw.TransportForListening(a) != tpt.Transport(t) {
			return 0, errQUICNotThisTransport
		}
		old = append(old, a)
	}
	if len(old) == 0 {
		return 0, nil
	}
	if listenPort > 0 {
		return 0, fmt.Errorf("fixed listen port %d keeps its listener", listenPort)
	}
	fresh := make([]ma.Multiaddr, 0, len(old))
	for _, a := range old {
		fresh = append(fresh, withUDPPort(a, 0))
	}
	g, err := t.newGeneration()
	if err != nil {
		return 0, err
	}
	g.epoch = epoch
	t.mu.Lock()
	prev, prevGen := t.inner, t.innerGen
	t.inner, t.innerGen = g.transport, g
	t.generations = append(t.generations, g)
	t.mu.Unlock()

	// New listeners first so there is never a moment without one. Listen
	// fails only when no address could be opened; then the old listeners and
	// the previous transport stay, and the empty generation closes itself.
	listenErr := sw.Listen(fresh...)
	g.listening.Store(true)
	g.maybeClose()
	if listenErr != nil {
		t.mu.Lock()
		if t.inner == g.transport {
			t.inner, t.innerGen = prev, prevGen
		}
		t.mu.Unlock()
		return 0, listenErr
	}
	sw.ListenClose(old...)
	return len(fresh), nil
}

// openGenerations counts path-change transports whose ConnManager is still
// open.
func (t *freshAwareQUICTransport) openGenerations() int {
	t.mu.RLock()
	defer t.mu.RUnlock()
	open := 0
	for _, g := range t.generations {
		if !g.closed.Load() {
			open++
		}
	}
	return open
}

func withUDPPort(a ma.Multiaddr, port int) ma.Multiaddr {
	udp, err := ma.NewComponent("udp", strconv.Itoa(port))
	if err != nil {
		return a
	}
	out := make(ma.Multiaddr, 0, len(a))
	for _, c := range a {
		if c.Protocol().Code == ma.P_UDP {
			out = append(out, *udp)
			continue
		}
		out = append(out, c)
	}
	return out
}

// quicGeneration is one QUIC transport born at a network path change: its own
// ConnManager, so the only socket ordinary reuse can pick is the listener
// created on the new network, and the stock transport on top of it. It
// closes itself once every socket it created is gone (libp2p's reuse gc
// closes a socket when no listener or connection uses it any more) and at
// the latest when the host closes.
type quicGeneration struct {
	transport tpt.Transport
	cm        *quicreuse.ConnManager
	// epoch is the network path epoch whose handoff created this generation.
	epoch     uint64
	sockets   atomic.Int64
	listening atomic.Bool
	closeOnce sync.Once
	closed    atomic.Bool

	mu      sync.Mutex
	created []*generationSocket
}

func (t *freshAwareQUICTransport) newGeneration() (*quicGeneration, error) {
	g := &quicGeneration{}
	rcmgr := t.rcmgr
	cm, err := quicreuse.NewConnManager(t.srk, t.tokenKey,
		quicreuse.OverrideListenUDP(g.listenUDP(t.policy)),
		// Same inbound scoping libp2p gives its own ConnManager (config.go).
		quicreuse.ConnContext(func(ctx context.Context, clientInfo *quic.ClientInfo) (context.Context, error) {
			addr, err := quicreuse.ToQuicMultiaddr(clientInfo.RemoteAddr, quic.Version1)
			if err != nil {
				addr = nil
			}
			scope, err := rcmgr.OpenConnection(network.DirInbound, false, addr)
			if err != nil {
				return ctx, err
			}
			ctx = network.WithConnManagementScope(ctx, scope)
			context.AfterFunc(ctx, func() { scope.Done() })
			return ctx, nil
		}),
		quicreuse.VerifySourceAddress(func(addr net.Addr) bool { return rcmgr.VerifySourceAddress(addr) }),
	)
	if err != nil {
		return nil, err
	}
	tr, err := libp2pquic.NewTransport(t.key, cm, nil, t.gater, rcmgr)
	if err != nil {
		_ = cm.Close()
		return nil, err
	}
	g.cm, g.transport = cm, tr
	return g, nil
}

func (g *quicGeneration) listenUDP(p *freshQUICDialPolicy) func(string, *net.UDPAddr) (net.PacketConn, error) {
	return func(network string, laddr *net.UDPAddr) (net.PacketConn, error) {
		pc, err := p.udpListen(network, laddr)
		if err != nil {
			return nil, err
		}
		g.sockets.Add(1)
		gs := &generationSocket{PacketConn: pc, gen: g}
		g.mu.Lock()
		g.created = append(g.created, gs)
		g.mu.Unlock()
		return gs, nil
	}
}

// socketsCreated lists the sockets this generation handed to its
// ConnManager, in creation order.
func (g *quicGeneration) socketsCreated() []*generationSocket {
	g.mu.Lock()
	defer g.mu.Unlock()
	return append([]*generationSocket(nil), g.created...)
}

// maybeClose closes the generation once it has finished listening and owns
// no socket. It runs on its own goroutine because the last socket is usually
// closed by the ConnManager's own gc goroutine, which Close waits for.
func (g *quicGeneration) maybeClose() {
	if g.listening.Load() && g.sockets.Load() == 0 {
		go g.close()
	}
}

func (g *quicGeneration) close() {
	g.closeOnce.Do(func() {
		_ = g.cm.Close()
		g.closed.Store(true)
	})
}

// generationSocket is one socket of a generation; its close is what retires
// the generation.
type generationSocket struct {
	net.PacketConn
	gen  *quicGeneration
	once sync.Once
}

func (s *generationSocket) Close() error {
	err := s.PacketConn.Close()
	s.once.Do(func() {
		s.gen.sockets.Add(-1)
		s.gen.maybeClose()
	})
	return err
}

// dialFresh dials on a socket that did not exist before this call. It is the
// handoff dial's fallback when no listener generation exists for the epoch.
// Each dial gets its own dial-only quicreuse manager with reuse disabled, so
// there is exactly one socket per dial and no shared state between concurrent
// dials.
// Upstream never closes a dial-only socket after a successful dial (DialQUIC
// releases the transport on error only, and that release leaves a caller-
// supplied socket open), so the socket's lifetime is owned here: it closes
// exactly once when the dial fails or when the QUIC connection ends.
func (t *freshAwareQUICTransport) dialFresh(ctx context.Context, raddr ma.Multiaddr, p peer.ID, epoch uint64) (tpt.CapableConn, error) {
	sock := &freshSocket{policy: t.policy}
	cm, err := quicreuse.NewConnManager(t.srk, t.tokenKey, quicreuse.DisableReuseport(), quicreuse.OverrideListenUDP(sock.listen))
	if err != nil {
		return nil, err
	}
	tr, err := libp2pquic.NewTransport(t.key, cm, nil, t.gater, t.rcmgr)
	if err != nil {
		return nil, err
	}
	c, err := tr.Dial(ctx, raddr, p)
	if err != nil {
		sock.close()
		return nil, err
	}
	var qc *quic.Conn
	if !c.As(&qc) || qc == nil {
		_ = c.Close()
		sock.close()
		return nil, errors.New("fresh QUIC dial: connection does not expose its quic.Conn")
	}
	context.AfterFunc(qc.Context(), sock.close)
	t.policy.recordFresh(c, p, epoch)
	return c, nil
}

// freshSocket owns the one UDP socket of one fresh dial.
type freshSocket struct {
	policy *freshQUICDialPolicy
	mu     sync.Mutex
	conn   net.PacketConn
	once   sync.Once
}

func (s *freshSocket) listen(network string, laddr *net.UDPAddr) (net.PacketConn, error) {
	pc, err := s.policy.udpListen(network, laddr)
	if err != nil {
		return nil, err
	}
	s.mu.Lock()
	if s.conn != nil {
		s.mu.Unlock()
		_ = pc.Close()
		return nil, errors.New("fresh QUIC dial: a dial may create only one socket")
	}
	s.conn = pc
	s.mu.Unlock()
	s.policy.created.Add(1)
	s.policy.open.Add(1)
	return pc, nil
}

func (s *freshSocket) close() {
	s.once.Do(func() {
		s.mu.Lock()
		pc := s.conn
		s.mu.Unlock()
		if pc == nil {
			return
		}
		s.policy.open.Add(-1)
		_ = pc.Close()
	})
}

func (t *freshAwareQUICTransport) CanDial(addr ma.Multiaddr) bool { return t.stock.CanDial(addr) }
func (t *freshAwareQUICTransport) Listen(laddr ma.Multiaddr) (tpt.Listener, error) {
	return t.current().Listen(laddr)
}
func (t *freshAwareQUICTransport) Protocols() []int { return t.stock.Protocols() }
func (t *freshAwareQUICTransport) Proxy() bool      { return t.stock.Proxy() }
func (t *freshAwareQUICTransport) String() string {
	if s, ok := t.stock.(interface{ String() string }); ok {
		return "fresh-aware-" + s.String()
	}
	return "fresh-aware-quic"
}

func (t *freshAwareQUICTransport) ListenOrder() int {
	if lo, ok := t.stock.(interface{ ListenOrder() int }); ok {
		return lo.ListenOrder()
	}
	return 0
}

// Close runs when the host closes: every generation goes, whatever is still
// on its sockets, and the policy forgets this transport.
func (t *freshAwareQUICTransport) Close() error {
	t.policy.transport.CompareAndSwap(t, nil)
	t.mu.Lock()
	gens := t.generations
	t.generations = nil
	t.inner, t.innerGen = t.stock, nil
	t.mu.Unlock()
	for _, g := range gens {
		g.close()
	}
	if c, ok := t.stock.(interface{ Close() error }); ok {
		return c.Close()
	}
	return nil
}
