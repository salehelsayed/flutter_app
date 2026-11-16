package main

import (
	"bytes"
	"errors"

	"github.com/axiomhq/hyperloglog"
)

type activeEngagementKinds uint8

const (
	activeEngagementActive activeEngagementKinds = 1 << iota
	activeEngagementChat
	activeEngagementCall
	activeEngagementGroup
)

var errActiveEngagementKinds = errors.New("invalid engagement kinds")

type activeEngagementEstimate struct{ Active, Chat, Call, Group, Reciprocal uint64 }

// One week's dense sets. The shared store owns locking, admission and durability.
type activeEngagementSketches struct {
	key      []byte
	sketches [4]*hyperloglog.Sketch
}

func newActiveEngagementSketches(key []byte) (*activeEngagementSketches, error) {
	if len(key) != 32 {
		return nil, errActiveIdentityKey
	}
	s := &activeEngagementSketches{key: bytes.Clone(key)}
	for i := range s.sketches {
		s.sketches[i] = hyperloglog.NewNoSparse()
	}
	return s, nil
}

func (s *activeEngagementSketches) insert(account string, kinds activeEngagementKinds) error {
	const allowed = activeEngagementActive | activeEngagementChat | activeEngagementCall | activeEngagementGroup
	if kinds == 0 || kinds&^allowed != 0 {
		return errActiveEngagementKinds
	}
	if account == "" {
		return errActiveIdentityAccount
	}
	kinds |= activeEngagementActive
	digest := activeIdentityDigest(s.key, account)
	for i, sketch := range s.sketches {
		if kinds&(activeEngagementKinds(1)<<i) != 0 {
			sketch.Insert(digest)
		}
	}
	return nil
}

func (s *activeEngagementSketches) estimate() (activeEngagementEstimate, error) {
	reciprocal := hyperloglog.NewNoSparse()
	for _, sketch := range s.sketches[1:3] {
		if err := reciprocal.Merge(sketch); err != nil {
			return activeEngagementEstimate{}, err
		}
	}
	return activeEngagementEstimate{
		Active: s.sketches[0].Estimate(), Chat: s.sketches[1].Estimate(),
		Call: s.sketches[2].Estimate(), Group: s.sketches[3].Estimate(),
		Reciprocal: reciprocal.Estimate(),
	}, nil
}
