package node

import (
	"errors"
	"io"
	"net"
	"os"
	"testing"
	"time"

	"github.com/libp2p/go-libp2p/core/network"
)

type uploadDeadlineTestStream struct {
	network.Stream
	conn net.Conn
}

func (s uploadDeadlineTestStream) Read(p []byte) (int, error)  { return s.conn.Read(p) }
func (s uploadDeadlineTestStream) Write(p []byte) (int, error) { return s.conn.Write(p) }
func (s uploadDeadlineTestStream) SetReadDeadline(d time.Time) error {
	return s.conn.SetReadDeadline(d)
}
func (s uploadDeadlineTestStream) SetWriteDeadline(d time.Time) error {
	return s.conn.SetWriteDeadline(d)
}

func TestMediaUploadStreamKeepsMovingIOAlive(t *testing.T) {
	for _, direction := range []string{"read", "write"} {
		t.Run(direction, func(t *testing.T) {
			t.Parallel()
			local, remote := net.Pipe()
			defer local.Close()
			defer remote.Close()
			stream := &mediaUploadStream{
				Stream:           uploadDeadlineTestStream{conn: local},
				idleTimeout:      300 * time.Millisecond,
				absoluteDeadline: time.Now().Add(3 * time.Second),
			}
			done := make(chan error, 1)
			go func() {
				for i := 0; i < 5; i++ {
					time.Sleep(80 * time.Millisecond)
					var err error
					if direction == "read" {
						_, err = remote.Write([]byte{byte(i)})
					} else {
						_, err = io.ReadFull(remote, make([]byte, 1))
					}
					if err != nil {
						done <- err
						return
					}
				}
				done <- nil
			}()
			for i := 0; i < 5; i++ {
				var err error
				if direction == "read" {
					buf := make([]byte, 1)
					_, err = io.ReadFull(stream, buf)
					if err == nil && buf[0] != byte(i) {
						t.Fatalf("byte=%d, want %d", buf[0], i)
					}
				} else {
					_, err = stream.Write([]byte{byte(i)})
				}
				if err != nil {
					t.Fatalf("moving %s stopped: %v", direction, err)
				}
			}
			if err := <-done; err != nil {
				t.Fatal(err)
			}
		})
	}
}

func TestMediaUploadStreamPreservesAbsoluteCeiling(t *testing.T) {
	local, remote := net.Pipe()
	defer local.Close()
	defer remote.Close()
	stream := &mediaUploadStream{
		Stream:           uploadDeadlineTestStream{conn: local},
		idleTimeout:      time.Second,
		absoluteDeadline: time.Now().Add(-time.Millisecond),
	}
	_, err := stream.Write([]byte{1})
	if !errors.Is(err, os.ErrDeadlineExceeded) || errors.Is(err, ErrStallTimeout) {
		t.Fatalf("absolute ceiling returned %v, want original deadline error", err)
	}
}
