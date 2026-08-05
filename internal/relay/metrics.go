package relay

import (
	"fmt"
	"sync/atomic"
)

// Metrics contains process-lifetime counters. All fields are safe for concurrent use.
type Metrics struct {
	plainIn        atomic.Uint64
	plainOut       atomic.Uint64
	encodedIn      atomic.Uint64
	encodedOut     atomic.Uint64
	duplicate      atomic.Uint64
	invalidFrame   atomic.Uint64
	oversizeFrame  atomic.Uint64
	queuedCopy     atomic.Uint64
	droppedCopy    atomic.Uint64
	sendError      atomic.Uint64
	noPeer         atomic.Uint64
	peerChange     atomic.Uint64
	dedupeEviction atomic.Uint64
}

// MetricSnapshot is a consistent-enough lock-free view for logging and tests.
type MetricSnapshot struct {
	PlainIn        uint64
	PlainOut       uint64
	EncodedIn      uint64
	EncodedOut     uint64
	Duplicate      uint64
	InvalidFrame   uint64
	OversizeFrame  uint64
	QueuedCopy     uint64
	DroppedCopy    uint64
	SendError      uint64
	NoPeer         uint64
	PeerChange     uint64
	DedupeEviction uint64
}

func (m *Metrics) Snapshot() MetricSnapshot {
	return MetricSnapshot{
		PlainIn:        m.plainIn.Load(),
		PlainOut:       m.plainOut.Load(),
		EncodedIn:      m.encodedIn.Load(),
		EncodedOut:     m.encodedOut.Load(),
		Duplicate:      m.duplicate.Load(),
		InvalidFrame:   m.invalidFrame.Load(),
		OversizeFrame:  m.oversizeFrame.Load(),
		QueuedCopy:     m.queuedCopy.Load(),
		DroppedCopy:    m.droppedCopy.Load(),
		SendError:      m.sendError.Load(),
		NoPeer:         m.noPeer.Load(),
		PeerChange:     m.peerChange.Load(),
		DedupeEviction: m.dedupeEviction.Load(),
	}
}

func (s MetricSnapshot) String() string {
	return fmt.Sprintf(
		"plain_in=%d plain_out=%d encoded_in=%d encoded_out=%d duplicate=%d invalid_frame=%d oversize_frame=%d queued_copy=%d dropped_copy=%d send_error=%d no_peer=%d peer_change=%d dedupe_eviction=%d",
		s.PlainIn, s.PlainOut, s.EncodedIn, s.EncodedOut, s.Duplicate,
		s.InvalidFrame, s.OversizeFrame, s.QueuedCopy, s.DroppedCopy,
		s.SendError, s.NoPeer, s.PeerChange, s.DedupeEviction,
	)
}
