package relay

import (
	"container/list"
	"sync"
	"time"
)

type dedupeEntry struct {
	sequence uint64
	seenAt   time.Time
}

// Deduper retains at most capacity sequence numbers for at most window.
type Deduper struct {
	mu       sync.Mutex
	window   time.Duration
	capacity int
	seen     map[uint64]*list.Element
	order    *list.List
}

func NewDeduper(window time.Duration, capacity int) *Deduper {
	return &Deduper{
		window:   window,
		capacity: capacity,
		seen:     make(map[uint64]*list.Element, capacity),
		order:    list.New(),
	}
}

// First reports whether sequence is new. evicted is the number of expired or
// capacity-limited entries removed during the operation.
func (d *Deduper) First(sequence uint64, now time.Time) (first bool, evicted int) {
	d.mu.Lock()
	defer d.mu.Unlock()

	evicted += d.pruneExpired(now)
	if _, exists := d.seen[sequence]; exists {
		return false, evicted
	}

	element := d.order.PushBack(dedupeEntry{sequence: sequence, seenAt: now})
	d.seen[sequence] = element
	for len(d.seen) > d.capacity {
		d.removeOldest()
		evicted++
	}
	return true, evicted
}

func (d *Deduper) Len() int {
	d.mu.Lock()
	defer d.mu.Unlock()
	return len(d.seen)
}

func (d *Deduper) Reset() int {
	d.mu.Lock()
	defer d.mu.Unlock()
	removed := len(d.seen)
	d.seen = make(map[uint64]*list.Element, d.capacity)
	d.order.Init()
	return removed
}

func (d *Deduper) pruneExpired(now time.Time) int {
	removed := 0
	cutoff := now.Add(-d.window)
	for element := d.order.Front(); element != nil; element = d.order.Front() {
		entry := element.Value.(dedupeEntry)
		if entry.seenAt.After(cutoff) {
			break
		}
		d.removeOldest()
		removed++
	}
	return removed
}

func (d *Deduper) removeOldest() {
	element := d.order.Front()
	if element == nil {
		return
	}
	entry := element.Value.(dedupeEntry)
	delete(d.seen, entry.sequence)
	d.order.Remove(element)
}
