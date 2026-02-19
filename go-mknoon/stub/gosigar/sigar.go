// Package gosigar is a stub replacement for github.com/elastic/gosigar
// that works on iOS (where libproc.h is not available).
//
// Only the Mem struct and its Get() method are used by go-watchdog.
package gosigar

// Mem holds system memory stats. On iOS this returns zero values.
type Mem struct {
	Total      uint64
	Used       uint64
	Free       uint64
	Cached     uint64
	ActualFree uint64
	ActualUsed uint64
}

// Get populates the Mem struct. On iOS this is a no-op (returns zero values).
func (m *Mem) Get() error {
	return nil
}

// Swap holds swap stats. Stub for interface compatibility.
type Swap struct {
	Total uint64
	Used  uint64
	Free  uint64
}

// Get populates the Swap struct. Stub.
func (s *Swap) Get() error {
	return nil
}
