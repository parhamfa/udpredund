package relay

import (
	"testing"
	"time"
)

func TestDeduperAcceptsOnlyFirstCopy(t *testing.T) {
	deduper := NewDeduper(30*time.Second, 8)
	now := time.Unix(100, 0)
	if first, _ := deduper.First(99, now); !first {
		t.Fatal("first copy was rejected")
	}
	if first, _ := deduper.First(99, now.Add(time.Second)); first {
		t.Fatal("duplicate copy was accepted")
	}
}

func TestDeduperPrunesExpiredEntries(t *testing.T) {
	deduper := NewDeduper(10*time.Second, 8)
	start := time.Unix(100, 0)
	deduper.First(1, start)
	first, evicted := deduper.First(1, start.Add(10*time.Second))
	if !first || evicted != 1 {
		t.Fatalf("first=%v evicted=%d", first, evicted)
	}
}

func TestDeduperEnforcesCapacity(t *testing.T) {
	deduper := NewDeduper(time.Hour, 2)
	now := time.Unix(100, 0)
	deduper.First(1, now)
	deduper.First(2, now.Add(time.Second))
	first, evicted := deduper.First(3, now.Add(2*time.Second))
	if !first || evicted != 1 || deduper.Len() != 2 {
		t.Fatalf("first=%v evicted=%d len=%d", first, evicted, deduper.Len())
	}
	if first, _ := deduper.First(1, now.Add(3*time.Second)); !first {
		t.Fatal("capacity-evicted sequence was not accepted again")
	}
}

func TestDeduperReset(t *testing.T) {
	deduper := NewDeduper(time.Hour, 2)
	deduper.First(1, time.Now())
	if removed := deduper.Reset(); removed != 1 || deduper.Len() != 0 {
		t.Fatalf("removed=%d len=%d", removed, deduper.Len())
	}
}
