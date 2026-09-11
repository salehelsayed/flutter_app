package node

import (
	"fmt"
	"os"
	"time"

	"github.com/libp2p/go-libp2p/core/network"
)

// mediaUploadStream bounds the actual network I/O, including READY and the
// final receipt. Timing reads of the local file cannot interrupt a blocked
// stream Write. Stream deadlines need no per-chunk goroutine and reset only
// as the caller advances through the transfer.
type mediaUploadStream struct {
	network.Stream
	idleTimeout      time.Duration
	absoluteDeadline time.Time
}

func (s *mediaUploadStream) nextDeadline() (time.Time, bool) {
	idle := time.Now().Add(s.idleTimeout)
	if !idle.Before(s.absoluteDeadline) {
		return s.absoluteDeadline, false
	}
	return idle, true
}

func (s *mediaUploadStream) Read(p []byte) (int, error) {
	deadline, idle := s.nextDeadline()
	if err := s.Stream.SetReadDeadline(deadline); err != nil {
		return 0, err
	}
	n, err := s.Stream.Read(p)
	if idle && os.IsTimeout(err) {
		return n, fmt.Errorf("%w: %w", ErrStallTimeout, err)
	}
	return n, err
}

func (s *mediaUploadStream) Write(p []byte) (int, error) {
	deadline, idle := s.nextDeadline()
	if err := s.Stream.SetWriteDeadline(deadline); err != nil {
		return 0, err
	}
	n, err := s.Stream.Write(p)
	if idle && os.IsTimeout(err) {
		return n, fmt.Errorf("%w: %w", ErrStallTimeout, err)
	}
	return n, err
}
