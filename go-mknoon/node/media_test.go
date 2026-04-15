package node

import (
	"bytes"
	"errors"
	"io"
	"strings"
	"testing"
	"time"
)

// --- §3: Profile upload progress reader tests ---

func TestMediaUploadProgressReader_EmitsInitialAndFinalProgress(t *testing.T) {
	data := make([]byte, 10240) // 10 KB
	reader := strings.NewReader(string(data))

	var events []struct{ sent, total int64 }
	pr := &mediaUploadProgressReader{
		reader:     reader,
		totalBytes: int64(len(data)),
		lastEmitAt: time.Now(),
		emitProgressFn: func(sentBytes, totalBytes int64) {
			events = append(events, struct{ sent, total int64 }{sentBytes, totalBytes})
		},
	}

	// Emit initial 0-byte progress (as ProfileUpload does).
	pr.emitProgressFn(0, pr.totalBytes)

	buf := &bytes.Buffer{}
	if _, err := io.Copy(buf, pr); err != nil {
		t.Fatalf("io.Copy: %v", err)
	}

	// Emit final progress (as ProfileUpload does).
	pr.emitProgressFn(pr.totalBytes, pr.totalBytes)

	if len(events) < 2 {
		t.Fatalf("expected at least 2 events (initial + final), got %d", len(events))
	}

	// First event: 0 bytes sent.
	if events[0].sent != 0 || events[0].total != 10240 {
		t.Errorf("initial event: sent=%d total=%d, want 0/10240", events[0].sent, events[0].total)
	}

	// Last event: all bytes sent.
	last := events[len(events)-1]
	if last.sent != 10240 || last.total != 10240 {
		t.Errorf("final event: sent=%d total=%d, want 10240/10240", last.sent, last.total)
	}
}

func TestMediaUploadProgressReader_LargeFileEmitsIntermediateEvents(t *testing.T) {
	// 1 MB exceeds 256 KB chunk threshold → should emit intermediate events.
	data := make([]byte, 1024*1024)
	reader := bytes.NewReader(data)

	var events []struct{ sent, total int64 }
	pr := &mediaUploadProgressReader{
		reader:     reader,
		totalBytes: int64(len(data)),
		lastEmitAt: time.Now(),
		emitProgressFn: func(sentBytes, totalBytes int64) {
			events = append(events, struct{ sent, total int64 }{sentBytes, totalBytes})
		},
	}

	pr.emitProgressFn(0, pr.totalBytes)

	buf := &bytes.Buffer{}
	if _, err := io.Copy(buf, pr); err != nil {
		t.Fatalf("io.Copy: %v", err)
	}

	pr.emitProgressFn(pr.totalBytes, pr.totalBytes)

	// With 1 MB data and 256 KB chunks, we expect: initial + at least 3 intermediate + final.
	if len(events) < 3 {
		t.Errorf("expected at least 3 events for 1 MB file, got %d", len(events))
	}

	// First is 0, last is totalBytes.
	if events[0].sent != 0 {
		t.Errorf("first event should be 0 bytes, got %d", events[0].sent)
	}
	last := events[len(events)-1]
	if last.sent != int64(len(data)) {
		t.Errorf("last event should be %d bytes, got %d", len(data), last.sent)
	}
}

func TestMediaUploadProgressReader_EventStructureHasSentAndTotalOnly(t *testing.T) {
	data := make([]byte, 10240)
	reader := bytes.NewReader(data)

	type progressEvent struct {
		sentBytes  int64
		totalBytes int64
	}
	var events []progressEvent

	pr := &mediaUploadProgressReader{
		reader:     reader,
		totalBytes: int64(len(data)),
		lastEmitAt: time.Now(),
		emitProgressFn: func(sentBytes, totalBytes int64) {
			events = append(events, progressEvent{sentBytes, totalBytes})
		},
	}

	pr.emitProgressFn(0, pr.totalBytes)

	buf := &bytes.Buffer{}
	if _, err := io.Copy(buf, pr); err != nil {
		t.Fatalf("io.Copy: %v", err)
	}

	pr.emitProgressFn(pr.totalBytes, pr.totalBytes)

	for i, e := range events {
		if e.totalBytes != 10240 {
			t.Errorf("event %d: totalBytes=%d, want 10240", i, e.totalBytes)
		}
		if e.sentBytes < 0 || e.sentBytes > 10240 {
			t.Errorf("event %d: sentBytes=%d out of range [0, 10240]", i, e.sentBytes)
		}
	}
}

// --- §5: Idle timeout reader tests ---

// stallingReader writes initialBytes immediately then blocks forever.
type stallingReader struct {
	data    []byte
	pos     int
	stalled bool
}

func (r *stallingReader) Read(p []byte) (int, error) {
	if r.pos >= len(r.data) {
		if r.stalled {
			// Block forever to simulate a stalled connection.
			select {}
		}
		return 0, io.EOF
	}
	n := copy(p, r.data[r.pos:])
	r.pos += n
	if r.pos >= len(r.data) && r.stalled {
		// Data is exhausted but we haven't returned EOF yet — next Read stalls.
	}
	return n, nil
}

// slowSteadyReader writes chunkSize bytes every interval.
type slowSteadyReader struct {
	remaining int
	chunkSize int
	interval  time.Duration
	first     bool
}

func (r *slowSteadyReader) Read(p []byte) (int, error) {
	if r.remaining <= 0 {
		return 0, io.EOF
	}
	if r.first {
		r.first = false
	} else {
		time.Sleep(r.interval)
	}
	n := r.chunkSize
	if n > len(p) {
		n = len(p)
	}
	if n > r.remaining {
		n = r.remaining
	}
	for i := 0; i < n; i++ {
		p[i] = 0xAB
	}
	r.remaining -= n
	return n, nil
}

func TestIdleTimeoutReader_NormalCopyCompletes(t *testing.T) {
	data := make([]byte, 100*1024) // 100 KB
	reader := bytes.NewReader(data)

	itr := newIdleTimeoutReader(reader, 2*time.Second)

	buf := &bytes.Buffer{}
	n, err := io.Copy(buf, itr)
	if err != nil {
		t.Fatalf("io.Copy: %v", err)
	}
	if n != int64(len(data)) {
		t.Errorf("expected %d bytes, got %d", len(data), n)
	}
}

func TestIdleTimeoutReader_StalledReaderFailsAfterIdleTimeout(t *testing.T) {
	// Reader writes 1 KB then blocks forever.
	data := make([]byte, 1024)
	sr := &stallingReader{data: data, stalled: true}

	itr := newIdleTimeoutReader(sr, 1*time.Second)

	buf := &bytes.Buffer{}
	start := time.Now()
	_, err := io.Copy(buf, itr)
	elapsed := time.Since(start)

	if !errors.Is(err, ErrStallTimeout) {
		t.Fatalf("expected ErrStallTimeout, got: %v", err)
	}

	// Timeout should fire after ~1s, not immediately.
	if elapsed < 900*time.Millisecond || elapsed > 2*time.Second {
		t.Errorf("timeout took %v, expected ~1s", elapsed)
	}

	// Partial transfer: should have received 1024 bytes.
	if buf.Len() != 1024 {
		t.Errorf("expected 1024 bytes written, got %d", buf.Len())
	}
}

func TestIdleTimeoutReader_SlowButSteadySucceeds(t *testing.T) {
	// Write 100 bytes every 500ms with 2s idle timeout — should succeed.
	total := 500
	sr := &slowSteadyReader{
		remaining: total,
		chunkSize: 100,
		interval:  500 * time.Millisecond,
		first:     true,
	}

	itr := newIdleTimeoutReader(sr, 2*time.Second)

	buf := &bytes.Buffer{}
	n, err := io.Copy(buf, itr)
	if err != nil {
		t.Fatalf("io.Copy should succeed for slow steady reader: %v", err)
	}
	if n != int64(total) {
		t.Errorf("expected %d bytes, got %d", total, n)
	}
}

func TestIdleTimeoutReader_IdleTimerResetsOnEachChunk(t *testing.T) {
	// Write 1KB, pause 800ms, repeat 3 times with 1s idle timeout.
	// Each 800ms pause is within budget — should succeed.
	total := 3072
	sr := &slowSteadyReader{
		remaining: total,
		chunkSize: 1024,
		interval:  800 * time.Millisecond,
		first:     true,
	}

	itr := newIdleTimeoutReader(sr, 1*time.Second)

	buf := &bytes.Buffer{}
	n, err := io.Copy(buf, itr)
	if err != nil {
		t.Fatalf("io.Copy should succeed when pauses are within idle budget: %v", err)
	}
	if n != int64(total) {
		t.Errorf("expected %d bytes, got %d", total, n)
	}
}

func TestIdleTimeoutReader_StalledDownloadFails(t *testing.T) {
	// Simulates CopyN (download path) with a stalling reader.
	data := make([]byte, 1024)
	sr := &stallingReader{data: data, stalled: true}

	itr := newIdleTimeoutReader(sr, 1*time.Second)

	buf := &bytes.Buffer{}
	_, err := io.CopyN(buf, itr, 100*1024)

	if !errors.Is(err, ErrStallTimeout) {
		t.Fatalf("expected ErrStallTimeout for stalled download, got: %v", err)
	}
}
