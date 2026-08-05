package relay

import (
	"container/heap"
	"context"
	"fmt"
	"log"
	"sync"
	"sync/atomic"
	"time"
)

type SendFunc func([]byte) error

type copyJob struct {
	due    time.Time
	order  uint64
	packet []byte
	send   SendFunc
}

type copyHeap []*copyJob

func (h copyHeap) Len() int { return len(h) }
func (h copyHeap) Less(i, j int) bool {
	if h[i].due.Equal(h[j].due) {
		return h[i].order < h[j].order
	}
	return h[i].due.Before(h[j].due)
}
func (h copyHeap) Swap(i, j int)   { h[i], h[j] = h[j], h[i] }
func (h *copyHeap) Push(value any) { *h = append(*h, value.(*copyJob)) }
func (h *copyHeap) Pop() any {
	old := *h
	last := old[len(old)-1]
	old[len(old)-1] = nil
	*h = old[:len(old)-1]
	return last
}

// CopyScheduler bounds delayed duplicate work. A primary write never enters
// this queue, so saturation can only discard redundant copies.
type CopyScheduler struct {
	ctx      context.Context
	cancel   context.CancelFunc
	capacity int64
	metrics  *Metrics
	logger   *log.Logger

	jobs    chan *copyJob
	errors  chan error
	done    chan struct{}
	pending atomic.Int64
	order   atomic.Uint64

	stateMu sync.RWMutex
	stopped bool
}

func NewCopyScheduler(parent context.Context, capacity int, metrics *Metrics, logger *log.Logger) *CopyScheduler {
	ctx, cancel := context.WithCancel(parent)
	scheduler := &CopyScheduler{
		ctx:      ctx,
		cancel:   cancel,
		capacity: int64(capacity),
		metrics:  metrics,
		logger:   logger,
		jobs:     make(chan *copyJob, capacity),
		errors:   make(chan error, 1),
		done:     make(chan struct{}),
	}
	go scheduler.loop()
	return scheduler
}

// Schedule queues a duplicate without blocking. It returns false when the
// bounded queue is full or shutting down.
func (s *CopyScheduler) Schedule(packet []byte, delay time.Duration, send SendFunc) bool {
	s.stateMu.RLock()
	defer s.stateMu.RUnlock()
	if s.stopped || !s.reserve() {
		s.metrics.droppedCopy.Add(1)
		return false
	}

	job := &copyJob{
		due:    time.Now().Add(delay),
		order:  s.order.Add(1),
		packet: append([]byte(nil), packet...),
		send:   send,
	}
	select {
	case s.jobs <- job:
		s.metrics.queuedCopy.Add(1)
		return true
	default:
		s.pending.Add(-1)
		s.metrics.droppedCopy.Add(1)
		return false
	}
}

func (s *CopyScheduler) Errors() <-chan error { return s.errors }

func (s *CopyScheduler) Pending() int64 { return s.pending.Load() }

func (s *CopyScheduler) Close() {
	s.stop()
	<-s.done
}

func (s *CopyScheduler) reserve() bool {
	for {
		pending := s.pending.Load()
		if pending >= s.capacity {
			return false
		}
		if s.pending.CompareAndSwap(pending, pending+1) {
			return true
		}
	}
}

func (s *CopyScheduler) stop() {
	s.stateMu.Lock()
	if !s.stopped {
		s.stopped = true
		s.cancel()
	}
	s.stateMu.Unlock()
}

func (s *CopyScheduler) loop() {
	defer close(s.done)
	queue := &copyHeap{}
	heap.Init(queue)
	var timer *time.Timer

	defer func() {
		s.stateMu.Lock()
		s.stopped = true
		s.stateMu.Unlock()

		remaining := queue.Len()
		for {
			select {
			case <-s.jobs:
				remaining++
			default:
				if remaining > 0 {
					s.pending.Add(-int64(remaining))
					s.metrics.droppedCopy.Add(uint64(remaining))
				}
				if timer != nil {
					timer.Stop()
				}
				return
			}
		}
	}()

	for {
		var timerChannel <-chan time.Time
		if queue.Len() > 0 {
			delay := time.Until((*queue)[0].due)
			if delay < 0 {
				delay = 0
			}
			if timer == nil {
				timer = time.NewTimer(delay)
			} else {
				if !timer.Stop() {
					select {
					case <-timer.C:
					default:
					}
				}
				timer.Reset(delay)
			}
			timerChannel = timer.C
		}

		select {
		case <-s.ctx.Done():
			return
		case job := <-s.jobs:
			heap.Push(queue, job)
		case <-timerChannel:
			job := heap.Pop(queue).(*copyJob)
			if err := job.send(job.packet); err != nil {
				s.metrics.sendError.Add(1)
				s.pending.Add(-1)
				s.reportError(fmt.Errorf("send delayed copy: %w", err))
				return
			}
			s.metrics.encodedOut.Add(1)
			s.pending.Add(-1)
		}
	}
}

func (s *CopyScheduler) reportError(err error) {
	if s.logger != nil {
		s.logger.Printf("copy scheduler: %v", err)
	}
	select {
	case s.errors <- err:
	default:
	}
}
