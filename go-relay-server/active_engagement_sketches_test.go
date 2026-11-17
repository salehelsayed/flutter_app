package main

import (
	"bytes"
	"errors"
	"fmt"
	"github.com/axiomhq/hyperloglog"
	"testing"
)

func b29E1Sketches(t *testing.T) *activeEngagementSketches {
	t.Helper()
	s, err := newActiveEngagementSketches(bytes.Repeat([]byte{17}, 32))
	if err != nil {
		t.Fatal(err)
	}
	return s
}
func b29E1Insert(t *testing.T, s *activeEngagementSketches, account string, kinds activeEngagementKinds) {
	t.Helper()
	if err := s.insert(account, kinds); err != nil {
		t.Fatal(err)
	}
}
func b29E1Estimate(t *testing.T, s *activeEngagementSketches) activeEngagementEstimate {
	t.Helper()
	got, err := s.estimate()
	if err != nil {
		t.Fatal(err)
	}
	return got
}
func b29E1Bytes(t *testing.T, s *activeEngagementSketches) [4][]byte {
	t.Helper()
	var out [4][]byte
	for i, sketch := range s.sketches {
		raw, err := sketch.MarshalBinary()
		if err != nil {
			t.Fatal(err)
		}
		out[i] = raw
	}
	return out
}

func TestB29E1SketchChatCallUnionDeduplicatesCanonicalIdentity(t *testing.T) {
	s := b29E1Sketches(t)
	for range 4 {
		// Proof verification is a later unit: linked devices must supply this account.
		b29E1Insert(t, s, "account-A", activeEngagementChat)
		b29E1Insert(t, s, "account-A", activeEngagementCall)
	}
	want := activeEngagementEstimate{Active: 1, Chat: 1, Call: 1, Reciprocal: 1}
	if got := b29E1Estimate(t, s); got != want {
		t.Fatalf("got=%+v want=%+v", got, want)
	}
	b29E1Insert(t, s, "account-B", activeEngagementChat)
	want.Active = 2
	want.Chat = 2
	want.Reciprocal = 2
	if got := b29E1Estimate(t, s); got != want {
		t.Fatalf("distinct account got=%+v want=%+v", got, want)
	}
}

func TestB29E1SketchGroupOnlyAndActiveOnlyExcludeReciprocal(t *testing.T) {
	s := b29E1Sketches(t)
	b29E1Insert(t, s, "group-person", activeEngagementGroup)
	b29E1Insert(t, s, "active-person", activeEngagementActive)
	want := activeEngagementEstimate{Active: 2, Group: 1}
	if got := b29E1Estimate(t, s); got != want {
		t.Fatalf("got=%+v want=%+v", got, want)
	}
}

func TestB29E1SketchKindCombinationsAlwaysIncludeActive(t *testing.T) {
	for kinds := activeEngagementKinds(1); kinds < 16; kinds++ {
		t.Run(fmt.Sprint(kinds), func(t *testing.T) {
			s := b29E1Sketches(t)
			b29E1Insert(t, s, "one-person", kinds)
			want := activeEngagementEstimate{Active: 1}
			if kinds&activeEngagementChat != 0 {
				want.Chat = 1
				want.Reciprocal = 1
			}
			if kinds&activeEngagementCall != 0 {
				want.Call = 1
				want.Reciprocal = 1
			}
			if kinds&activeEngagementGroup != 0 {
				want.Group = 1
			}
			if got := b29E1Estimate(t, s); got != want {
				t.Fatalf("got=%+v want=%+v", got, want)
			}
		})
	}
}

func TestB29E1SketchUnionIsReadOnlyAndReturnsAllFiveKinds(t *testing.T) {
	s := b29E1Sketches(t)
	b29E1Insert(t, s, "chat-person", activeEngagementChat)
	b29E1Insert(t, s, "call-person", activeEngagementCall)
	b29E1Insert(t, s, "group-person", activeEngagementGroup)
	before := b29E1Bytes(t, s)
	for range 3 {
		if got := b29E1Estimate(t, s); got != (activeEngagementEstimate{Active: 3, Chat: 1, Call: 1, Group: 1, Reciprocal: 2}) {
			t.Fatalf("got=%+v", got)
		}
	}
	after := b29E1Bytes(t, s)
	for i := range before {
		if !bytes.Equal(before[i], after[i]) {
			t.Fatalf("estimate changed kind %d", i)
		}
	}
}

func TestB29E1SketchSameDenseHashDomainAsDaily(t *testing.T) {
	s := b29E1Sketches(t)
	b29E1Insert(t, s, "canonical-account-A", 15)
	daily := b29Sketches(t)
	b29Insert(t, daily, "2026-11-14", "canonical-account-A")
	expected, err := daily.days["2026-11-14"].MarshalBinary()
	if err != nil {
		t.Fatal(err)
	}
	prototype, err := hyperloglog.NewNoSparse().MarshalBinary()
	if err != nil {
		t.Fatal(err)
	}
	for i, raw := range b29E1Bytes(t, s) {
		if len(raw) != len(prototype) || !bytes.Equal(raw, expected) {
			t.Fatalf("kind %d is not same dense keyed identity set", i)
		}
		if bytes.Contains(raw, []byte("canonical-account-A")) {
			t.Fatalf("kind %d retains raw identity", i)
		}
	}
}

func TestB29E1SketchOwnsKeyAndWeekBucketsStayIndependent(t *testing.T) {
	key := bytes.Repeat([]byte{17}, 32)
	s, err := newActiveEngagementSketches(key)
	if err != nil {
		t.Fatal(err)
	}
	b29E1Insert(t, s, "person", activeEngagementChat)
	key[0] ^= 0xff
	b29E1Insert(t, s, "person", activeEngagementCall)
	if got := b29E1Estimate(t, s); got != (activeEngagementEstimate{Active: 1, Chat: 1, Call: 1, Reciprocal: 1}) {
		t.Fatalf("key mutation changed union: %+v", got)
	}
	other := b29E1Sketches(t)
	b29E1Insert(t, other, "different-week-person", activeEngagementGroup)
	if got := b29E1Estimate(t, s); got.Group != 0 || got.Active != 1 {
		t.Fatalf("another week changed existing bucket: %+v", got)
	}
	if got := b29E1Estimate(t, other); got != (activeEngagementEstimate{Active: 1, Group: 1}) {
		t.Fatalf("separate week=%+v", got)
	}
}

func TestB29E1SketchRejectsInvalidInputsWithoutPartialActiveInsertion(t *testing.T) {
	s := b29E1Sketches(t)
	b29E1Insert(t, s, "valid-person", activeEngagementChat)
	if got := b29E1Estimate(t, s); got.Active != 1 {
		t.Fatalf("valid control=%+v", got)
	}
	before := b29E1Bytes(t, s)
	for _, kinds := range []activeEngagementKinds{0, 16, 17, 255} {
		if err := s.insert("forbidden-person", kinds); !errors.Is(err, errActiveEngagementKinds) {
			t.Errorf("kinds=%d error=%v", kinds, err)
		}
	}
	if err := s.insert("", activeEngagementChat); !errors.Is(err, errActiveIdentityAccount) {
		t.Errorf("empty account error=%v", err)
	}
	for _, key := range [][]byte{nil, {1}, bytes.Repeat([]byte{17}, 31), bytes.Repeat([]byte{17}, 33)} {
		if _, err := newActiveEngagementSketches(key); !errors.Is(err, errActiveIdentityKey) {
			t.Errorf("key length=%d error=%v", len(key), err)
		}
	}
	after := b29E1Bytes(t, s)
	for i := range before {
		if !bytes.Equal(before[i], after[i]) {
			t.Fatalf("invalid input changed kind %d", i)
		}
	}
}

func TestB29E1SketchLargeOverlapUsesUnionNotAddition(t *testing.T) {
	s := b29E1Sketches(t)
	for i := range 10000 {
		kinds := activeEngagementChat
		if i >= 5000 {
			kinds = activeEngagementCall
		}
		if i >= 2500 && i < 7500 {
			kinds = activeEngagementChat | activeEngagementCall
		}
		b29E1Insert(t, s, fmt.Sprintf("person-%d", i), kinds)
	}
	got := b29E1Estimate(t, s)
	if got.Reciprocal < 9500 || got.Reciprocal > 10500 || got.Active != got.Reciprocal || got.Group != 0 {
		t.Fatalf("union=%+v want10000 within5%% and active same set", got)
	}
	if got.Chat < 7125 || got.Chat > 7875 || got.Call < 7125 || got.Call > 7875 {
		t.Fatalf("kind estimates=%+v want7500 within5%%", got)
	}
}
