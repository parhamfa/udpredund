package relay

import (
	"context"
	"errors"
	"io"
	"log"
	"sync/atomic"
	"testing"
	"time"
)

func TestCopySchedulerDropsAtCapacity(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	metrics := &Metrics{}
	scheduler := NewCopyScheduler(ctx, 2, metrics, log.New(io.Discard, "", 0))
	release := make(chan struct{})
	started := make(chan struct{}, 1)
	send := func([]byte) error {
		started <- struct{}{}
		<-release
		return nil
	}
	if !scheduler.Schedule([]byte("one"), 0, send) {
		t.Fatal("first copy was not queued")
	}
	select {
	case <-started:
	case <-time.After(time.Second):
		t.Fatal("first copy did not start")
	}
	if !scheduler.Schedule([]byte("two"), 0, send) {
		t.Fatal("second copy was not queued")
	}
	if scheduler.Schedule([]byte("three"), 0, send) {
		t.Fatal("third copy exceeded capacity")
	}
	close(release)
	eventually(t, time.Second, func() bool { return scheduler.Pending() == 0 })
	scheduler.Close()
	snapshot := metrics.Snapshot()
	if snapshot.QueuedCopy != 2 || snapshot.DroppedCopy != 1 || snapshot.EncodedOut != 2 {
		t.Fatalf("unexpected metrics: %+v", snapshot)
	}
}

func TestCopySchedulerOrdersByDeadline(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	metrics := &Metrics{}
	scheduler := NewCopyScheduler(ctx, 4, metrics, log.New(io.Discard, "", 0))
	result := make(chan string, 2)
	scheduler.Schedule([]byte("late"), 30*time.Millisecond, func(packet []byte) error {
		result <- string(packet)
		return nil
	})
	scheduler.Schedule([]byte("early"), 5*time.Millisecond, func(packet []byte) error {
		result <- string(packet)
		return nil
	})
	if got := receiveString(t, result); got != "early" {
		t.Fatalf("first=%q", got)
	}
	if got := receiveString(t, result); got != "late" {
		t.Fatalf("second=%q", got)
	}
	scheduler.Close()
}

func TestPrimarySendDoesNotWaitForDuplicateCapacity(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	metrics := &Metrics{}
	scheduler := NewCopyScheduler(ctx, 1, metrics, log.New(io.Discard, "", 0))
	if !scheduler.Schedule([]byte("occupied"), time.Hour, func([]byte) error { return nil }) {
		t.Fatal("failed to occupy queue")
	}
	var primary atomic.Uint64
	started := time.Now()
	if err := sendCopies([]byte("packet"), 2, time.Second, func([]byte) error {
		primary.Add(1)
		return nil
	}, scheduler, metrics); err != nil {
		t.Fatal(err)
	}
	if elapsed := time.Since(started); elapsed > 100*time.Millisecond {
		t.Fatalf("primary path waited %s", elapsed)
	}
	if primary.Load() != 1 || metrics.Snapshot().DroppedCopy != 1 {
		t.Fatalf("primary=%d metrics=%+v", primary.Load(), metrics.Snapshot())
	}
	scheduler.Close()
}

func TestCopySchedulerPropagatesSendFailure(t *testing.T) {
	metrics := &Metrics{}
	scheduler := NewCopyScheduler(context.Background(), 1, metrics, log.New(io.Discard, "", 0))
	want := errors.New("write failed")
	scheduler.Schedule([]byte("copy"), 0, func([]byte) error { return want })
	select {
	case err := <-scheduler.Errors():
		if !errors.Is(err, want) {
			t.Fatalf("got %v, want %v", err, want)
		}
	case <-time.After(time.Second):
		t.Fatal("scheduler failure was not propagated")
	}
	scheduler.Close()
	if metrics.Snapshot().SendError != 1 {
		t.Fatalf("metrics=%+v", metrics.Snapshot())
	}
}

func receiveString(t *testing.T, channel <-chan string) string {
	t.Helper()
	select {
	case result := <-channel:
		return result
	case <-time.After(time.Second):
		t.Fatal("timed out waiting for result")
		return ""
	}
}

func eventually(t *testing.T, timeout time.Duration, condition func() bool) {
	t.Helper()
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		if condition() {
			return
		}
		time.Sleep(time.Millisecond)
	}
	t.Fatal("condition did not become true")
}
