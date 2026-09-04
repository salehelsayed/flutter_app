package callaudiooracle

import (
	"context"
	"errors"
	"io"
	"net"
	"strings"
	"sync"
	"time"

	"github.com/pion/logging"
	"github.com/pion/rtp"
	"github.com/pion/webrtc/v4"
)

const (
	opusPayloadType  = 111
	opusClockRate    = 48000
	opusChannels     = 1
	opusFrameSamples = 960
	opusFrameDelay   = 20 * time.Millisecond
	extraPacketWait  = 250 * time.Millisecond
)

type oraclePeer struct {
	connection *webrtc.PeerConnection
	track      *webrtc.TrackLocalStaticRTP
	sender     *webrtc.RTPSender
	remote     chan *webrtc.TrackRemote
	connected  chan struct{}
	failed     chan struct{}
	closed     chan struct{}

	connectedOnce sync.Once
	failedOnce    sync.Once
	closedOnce    sync.Once
}

type oracleResources struct {
	peerA   *oraclePeer
	peerB   *oraclePeer
	fixture knownFixture
	workers ownedWorkers

	closeOnce sync.Once
	clean     bool
}

type ownedWorkers struct {
	mu      sync.Mutex
	started int
	done    chan struct{}
}

type workerResult struct {
	direction DirectionResult
	err       error
}

func newOracleResources(
	ctx context.Context,
	credentials CredentialConfig,
	fixture knownFixture,
) (*oracleResources, error) {
	resources := &oracleResources{
		fixture: fixture,
		workers: ownedWorkers{done: make(chan struct{}, 8)},
	}
	peerA, err := newOraclePeer(credentials.TurnURL, credentials.PeerA, "peer-a")
	if err != nil {
		return nil, errPeerSetup
	}
	resources.peerA = peerA
	peerB, err := newOraclePeer(credentials.TurnURL, credentials.PeerB, "peer-b")
	if err != nil {
		_ = peerA.connection.Close()
		return nil, errPeerSetup
	}
	resources.peerB = peerB
	resources.workers.start(func() { drainRTCP(ctx, peerA.sender) })
	resources.workers.start(func() { drainRTCP(ctx, peerB.sender) })
	return resources, nil
}

func newOraclePeer(
	turnURL string,
	credential EphemeralCredential,
	trackID string,
) (*oraclePeer, error) {
	mediaEngine := &webrtc.MediaEngine{}
	codec := webrtc.RTPCodecParameters{
		RTPCodecCapability: webrtc.RTPCodecCapability{
			MimeType:  webrtc.MimeTypeOpus,
			ClockRate: opusClockRate,
			Channels:  opusChannels,
		},
		PayloadType: opusPayloadType,
	}
	if err := mediaEngine.RegisterCodec(codec, webrtc.RTPCodecTypeAudio); err != nil {
		return nil, errPeerSetup
	}
	loggerFactory := logging.NewDefaultLoggerFactory()
	loggerFactory.Writer = io.Discard
	loggerFactory.DefaultLogLevel = logging.LogLevelDisabled
	settings := webrtc.SettingEngine{LoggerFactory: loggerFactory}
	settings.SetICETimeouts(8*time.Second, 15*time.Second, time.Second)
	api := webrtc.NewAPI(
		webrtc.WithMediaEngine(mediaEngine),
		webrtc.WithSettingEngine(settings),
	)
	connection, err := api.NewPeerConnection(webrtc.Configuration{
		ICEServers: []webrtc.ICEServer{{
			URLs:           []string{turnURL},
			Username:       credential.Username,
			Credential:     credential.Password,
			CredentialType: webrtc.ICECredentialTypePassword,
		}},
		ICETransportPolicy: webrtc.ICETransportPolicyRelay,
	})
	if err != nil {
		return nil, errPeerSetup
	}
	track, err := webrtc.NewTrackLocalStaticRTP(
		codec.RTPCodecCapability,
		trackID,
		"known-opus-oracle",
	)
	if err != nil {
		_ = connection.Close()
		return nil, errPeerSetup
	}
	sender, err := connection.AddTrack(track)
	if err != nil {
		_ = connection.Close()
		return nil, errPeerSetup
	}
	peer := &oraclePeer{
		connection: connection,
		track:      track,
		sender:     sender,
		remote:     make(chan *webrtc.TrackRemote, 1),
		connected:  make(chan struct{}),
		failed:     make(chan struct{}),
		closed:     make(chan struct{}),
	}
	connection.OnTrack(func(track *webrtc.TrackRemote, _ *webrtc.RTPReceiver) {
		select {
		case peer.remote <- track:
		default:
			peer.fail()
		}
	})
	connection.OnConnectionStateChange(func(state webrtc.PeerConnectionState) {
		switch state {
		case webrtc.PeerConnectionStateConnected:
			peer.connectedOnce.Do(func() { close(peer.connected) })
		case webrtc.PeerConnectionStateFailed:
			peer.fail()
		case webrtc.PeerConnectionStateClosed:
			peer.closedOnce.Do(func() { close(peer.closed) })
		}
	})
	return peer, nil
}

func (peer *oraclePeer) fail() {
	peer.failedOnce.Do(func() { close(peer.failed) })
}

func (resources *oracleResources) negotiate(ctx context.Context) error {
	offer, err := resources.peerA.connection.CreateOffer(nil)
	if err != nil {
		return errPeerSignaling
	}
	offerGathered := webrtc.GatheringCompletePromise(resources.peerA.connection)
	if err := resources.peerA.connection.SetLocalDescription(offer); err != nil {
		return errPeerSignaling
	}
	if !waitSignal(ctx, offerGathered, resources.peerA.failed) {
		return errPeerConnection
	}
	localOffer := resources.peerA.connection.LocalDescription()
	if localOffer == nil ||
		resources.peerB.connection.SetRemoteDescription(*localOffer) != nil {
		return errPeerSignaling
	}

	answer, err := resources.peerB.connection.CreateAnswer(nil)
	if err != nil {
		return errPeerSignaling
	}
	answerGathered := webrtc.GatheringCompletePromise(resources.peerB.connection)
	if err := resources.peerB.connection.SetLocalDescription(answer); err != nil {
		return errPeerSignaling
	}
	if !waitSignal(ctx, answerGathered, resources.peerB.failed) {
		return errPeerConnection
	}
	localAnswer := resources.peerB.connection.LocalDescription()
	if localAnswer == nil ||
		resources.peerA.connection.SetRemoteDescription(*localAnswer) != nil {
		return errPeerSignaling
	}
	if !waitConnected(ctx, resources.peerA) ||
		!waitConnected(ctx, resources.peerB) {
		return errPeerConnection
	}
	return nil
}

func waitSignal(ctx context.Context, ready <-chan struct{}, failed <-chan struct{}) bool {
	select {
	case <-ready:
		return true
	case <-failed:
		return false
	case <-ctx.Done():
		return false
	}
}

func waitConnected(ctx context.Context, peer *oraclePeer) bool {
	select {
	case <-peer.connected:
		return true
	case <-peer.failed:
		return false
	case <-ctx.Done():
		return false
	}
}

func (resources *oracleResources) verifyRoutes(
	expectedTransport string,
) (RouteResult, RouteResult, error) {
	peerARoute, err := selectedRoute(resources.peerA, expectedTransport)
	if err != nil {
		return RouteResult{}, RouteResult{}, errPeerRoute
	}
	peerBRoute, err := selectedRoute(resources.peerB, expectedTransport)
	if err != nil {
		return RouteResult{}, RouteResult{}, errPeerRoute
	}
	if !peerARoute.RelaySelected || !peerARoute.TransportMatch ||
		!peerBRoute.RelaySelected || !peerBRoute.TransportMatch {
		return peerARoute, peerBRoute, errPeerRoute
	}
	return peerARoute, peerBRoute, nil
}

func selectedRoute(peer *oraclePeer, expectedTransport string) (RouteResult, error) {
	dtlsTransport := peer.sender.Transport()
	if dtlsTransport == nil || dtlsTransport.ICETransport() == nil {
		return RouteResult{}, errPeerRoute
	}
	pair, err := dtlsTransport.ICETransport().GetSelectedCandidatePair()
	if err != nil || pair == nil || pair.Local == nil || pair.Remote == nil {
		return RouteResult{}, errPeerRoute
	}
	return RouteResult{
		RelaySelected: pair.Local.Typ == webrtc.ICECandidateTypeRelay &&
			pair.Remote.Typ == webrtc.ICECandidateTypeRelay,
		TransportMatch: strings.EqualFold(pair.Local.Protocol.String(), expectedTransport) &&
			strings.EqualFold(pair.Remote.Protocol.String(), expectedTransport),
	}, nil
}

func (resources *oracleResources) exchange(
	ctx context.Context,
) (DirectionResult, DirectionResult, error) {
	aToBResult := make(chan workerResult, 1)
	bToAResult := make(chan workerResult, 1)
	sendAResult := make(chan error, 1)
	sendBResult := make(chan error, 1)
	sendADone := make(chan struct{})
	sendBDone := make(chan struct{})

	resources.workers.start(func() {
		defer close(sendADone)
		sendAResult <- sendKnownPayloads(
			ctx,
			resources.peerA.track,
			resources.fixture.payloads,
			10000,
			0x10203040,
		)
	})
	resources.workers.start(func() {
		defer close(sendBDone)
		sendBResult <- sendKnownPayloads(
			ctx,
			resources.peerB.track,
			resources.fixture.payloads,
			30000,
			0x50607080,
		)
	})
	resources.workers.start(func() {
		result, err := receiveKnownPayloads(
			ctx,
			resources.peerB.remote,
			sendADone,
			resources.fixture,
			10000,
			0x10203040,
		)
		aToBResult <- workerResult{direction: result, err: err}
	})
	resources.workers.start(func() {
		result, err := receiveKnownPayloads(
			ctx,
			resources.peerA.remote,
			sendBDone,
			resources.fixture,
			30000,
			0x50607080,
		)
		bToAResult <- workerResult{direction: result, err: err}
	})

	sendAErr, ok := waitError(ctx, sendAResult)
	if !ok || sendAErr != nil {
		return DirectionResult{}, DirectionResult{}, errMediaTransfer
	}
	sendBErr, ok := waitError(ctx, sendBResult)
	if !ok || sendBErr != nil {
		return DirectionResult{}, DirectionResult{}, errMediaTransfer
	}
	aToB, ok := waitWorkerResult(ctx, aToBResult)
	if !ok || aToB.err != nil {
		return DirectionResult{}, DirectionResult{}, errMediaTransfer
	}
	bToA, ok := waitWorkerResult(ctx, bToAResult)
	if !ok || bToA.err != nil {
		return DirectionResult{}, DirectionResult{}, errMediaTransfer
	}
	return aToB.direction, bToA.direction, nil
}

func sendKnownPayloads(
	ctx context.Context,
	track *webrtc.TrackLocalStaticRTP,
	payloads [][]byte,
	initialSequence uint16,
	initialTimestamp uint32,
) error {
	for index, payload := range payloads {
		select {
		case <-ctx.Done():
			return errMediaTransfer
		default:
		}
		packet := &rtp.Packet{
			Header: rtp.Header{
				Version:        2,
				PayloadType:    opusPayloadType,
				SequenceNumber: initialSequence + uint16(index),
				Timestamp: initialTimestamp +
					uint32(index*opusFrameSamples),
			},
			Payload: append([]byte(nil), payload...),
		}
		if err := track.WriteRTP(packet); err != nil {
			return errMediaTransfer
		}
		if index+1 < len(payloads) {
			timer := time.NewTimer(opusFrameDelay)
			select {
			case <-timer.C:
			case <-ctx.Done():
				if !timer.Stop() {
					<-timer.C
				}
				return errMediaTransfer
			}
		}
	}
	return nil
}

func receiveKnownPayloads(
	ctx context.Context,
	remoteTrack <-chan *webrtc.TrackRemote,
	sendDone <-chan struct{},
	fixture knownFixture,
	initialSequence uint16,
	initialTimestamp uint32,
) (DirectionResult, error) {
	var track *webrtc.TrackRemote
	select {
	case track = <-remoteTrack:
	case <-ctx.Done():
		return DirectionResult{}, errMediaTransfer
	}
	codec := track.Codec().RTPCodecCapability
	result := DirectionResult{
		CodecValid: strings.EqualFold(codec.MimeType, webrtc.MimeTypeOpus) &&
			codec.ClockRate == opusClockRate && codec.Channels == opusChannels,
		PayloadOrderExact: true,
	}
	receivedPayloads := make([][]byte, 0, len(fixture.payloads))
	for index := range fixture.payloads {
		if err := setBoundedReadDeadline(ctx, track, 15*time.Second); err != nil {
			return result, errMediaTransfer
		}
		packet, _, err := track.ReadRTP()
		if err != nil {
			return result, errMediaTransfer
		}
		if packet.SequenceNumber != initialSequence+uint16(index) ||
			packet.Timestamp != initialTimestamp+uint32(index*opusFrameSamples) {
			result.PayloadOrderExact = false
		}
		receivedPayloads = append(
			receivedPayloads,
			append([]byte(nil), packet.Payload...),
		)
	}
	select {
	case <-sendDone:
	case <-ctx.Done():
		return result, errMediaTransfer
	}
	if err := track.SetReadDeadline(time.Now().Add(extraPacketWait)); err != nil {
		return result, errMediaTransfer
	}
	_, _, extraErr := track.ReadRTP()
	var timeout net.Error
	result.PayloadCountExact = errors.As(extraErr, &timeout) && timeout.Timeout()
	receivedDigest := hashPayloadSequence(receivedPayloads)
	result.PayloadHashExact = receivedDigest == fixture.payloadDigest
	return result, nil
}

func setBoundedReadDeadline(
	ctx context.Context,
	track *webrtc.TrackRemote,
	maximum time.Duration,
) error {
	deadline := time.Now().Add(maximum)
	if contextDeadline, present := ctx.Deadline(); present && contextDeadline.Before(deadline) {
		deadline = contextDeadline
	}
	return track.SetReadDeadline(deadline)
}

func waitError(ctx context.Context, result <-chan error) (error, bool) {
	select {
	case err := <-result:
		return err, true
	case <-ctx.Done():
		return errMediaTransfer, false
	}
}

func waitWorkerResult(
	ctx context.Context,
	result <-chan workerResult,
) (workerResult, bool) {
	select {
	case value := <-result:
		return value, true
	case <-ctx.Done():
		return workerResult{}, false
	}
}

func drainRTCP(ctx context.Context, sender *webrtc.RTPSender) {
	buffer := make([]byte, 1500)
	for {
		if _, _, err := sender.Read(buffer); err != nil {
			return
		}
		select {
		case <-ctx.Done():
			return
		default:
		}
	}
}

func (workers *ownedWorkers) start(task func()) {
	workers.mu.Lock()
	workers.started++
	workers.mu.Unlock()
	go func() {
		defer func() { workers.done <- struct{}{} }()
		task()
	}()
}

func (workers *ownedWorkers) wait(timeout time.Duration) bool {
	workers.mu.Lock()
	started := workers.started
	workers.mu.Unlock()
	timer := time.NewTimer(timeout)
	defer timer.Stop()
	for range started {
		select {
		case <-workers.done:
		case <-timer.C:
			return false
		}
	}
	return true
}

func (resources *oracleResources) close() bool {
	resources.closeOnce.Do(func() {
		closeAErr := resources.peerA.connection.Close()
		closeBErr := resources.peerB.connection.Close()
		workersStopped := resources.workers.wait(5 * time.Second)
		peerAClosed := waitClosed(resources.peerA, 2*time.Second)
		peerBClosed := waitClosed(resources.peerB, 2*time.Second)
		resources.clean = closeAErr == nil && closeBErr == nil &&
			workersStopped && peerAClosed && peerBClosed
	})
	return resources.clean
}

func waitClosed(peer *oraclePeer, timeout time.Duration) bool {
	if peer.connection.ConnectionState() == webrtc.PeerConnectionStateClosed {
		return true
	}
	timer := time.NewTimer(timeout)
	defer timer.Stop()
	select {
	case <-peer.closed:
		return true
	case <-timer.C:
		return false
	}
}
