package node

import (
	"testing"
	"time"
)

func TestNextGroupKeyWouldEvictKeyInGrace(t *testing.T) {
	now := time.Date(2026, 10, 4, 12, 0, 0, 0, time.UTC)
	grace := 10 * time.Minute
	ring := func(oldestRetiredAt time.Time) *GroupKeyInfo {
		keys := make([]GroupEpochKey, 0, RetainedEpochKeys)
		for i := 0; i < RetainedEpochKeys; i++ {
			ek := GroupEpochKey{Key: "k", KeyEpoch: 10 - i}
			if i > 0 {
				ek.RetiredAtMs = now.Add(-time.Duration(i) * time.Minute).UnixMilli()
			}
			keys = append(keys, ek)
		}
		if !oldestRetiredAt.IsZero() {
			keys[RetainedEpochKeys-1].RetiredAtMs = oldestRetiredAt.UnixMilli()
		} else {
			keys[RetainedEpochKeys-1].RetiredAtMs = 0
		}
		return &GroupKeyInfo{Key: "k", KeyEpoch: 10, Keys: keys}
	}

	cases := []struct {
		name string
		info *GroupKeyInfo
		want bool
	}{
		{"ring with room", &GroupKeyInfo{Key: "k", KeyEpoch: 3, Keys: []GroupEpochKey{
			{Key: "k", KeyEpoch: 3},
			{Key: "k", KeyEpoch: 2, RetiredAtMs: now.UnixMilli()},
		}}, false},
		{"full ring, evicted key retired 2 minutes ago", ring(now.Add(-2 * time.Minute)), true},
		{"full ring, evicted key retired 11 minutes ago", ring(now.Add(-11 * time.Minute)), false},
		{"full ring, evicted key without retirement time", ring(time.Time{}), false},
		{"legacy key info without ring", &GroupKeyInfo{Key: "k", KeyEpoch: 2, PrevKey: "p", PrevKeyEpoch: 1}, false},
	}
	for _, tc := range cases {
		if got := NextGroupKeyWouldEvictKeyInGrace(tc.info, grace, now); got != tc.want {
			t.Errorf("%s: got %v, want %v", tc.name, got, tc.want)
		}
	}
}

func TestRotateGroupKeyRingStampsRetiredEpoch(t *testing.T) {
	n := New(nil)
	current := &GroupKeyInfo{Key: "k1", KeyEpoch: 1, Keys: []GroupEpochKey{{Key: "k1", KeyEpoch: 1}}}
	before := time.Now().UnixMilli()
	updated := n.rotateGroupKeyRing(current, &GroupKeyInfo{Key: "k2", KeyEpoch: 2})
	if updated.Keys[0].KeyEpoch != 2 || updated.Keys[0].RetiredAtMs != 0 {
		t.Fatalf("head = %+v, want current epoch 2 without retirement", updated.Keys[0])
	}
	if updated.Keys[1].KeyEpoch != 1 || updated.Keys[1].RetiredAtMs < before {
		t.Fatalf("previous = %+v, want epoch 1 retired at/after %d", updated.Keys[1], before)
	}
	stamped := updated.Keys[1].RetiredAtMs
	again := n.rotateGroupKeyRing(updated, &GroupKeyInfo{Key: "k3", KeyEpoch: 3})
	if again.Keys[2].KeyEpoch != 1 || again.Keys[2].RetiredAtMs != stamped {
		t.Fatalf("older = %+v, want epoch 1 keeping retirement %d", again.Keys[2], stamped)
	}
}
