package relay

import (
	"context"
	"crypto/rand"
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"sync"
	"time"
)

// Run starts a client or server relay and blocks until cancellation or failure.
func Run(ctx context.Context, config Config) error {
	if err := config.Validate(); err != nil {
		return err
	}
	if config.Metrics == nil {
		config.Metrics = &Metrics{}
	}
	if config.Logger == nil {
		config.Logger = log.New(io.Discard, "", 0)
	}

	switch config.Mode {
	case ModeClient:
		return runClient(ctx, config)
	case ModeServer:
		return runServer(ctx, config)
	default:
		return fmt.Errorf("unsupported mode %q", config.Mode)
	}
}

func runClient(parent context.Context, config Config) error {
	listenAddress, err := net.ResolveUDPAddr("udp", config.Listen)
	if err != nil {
		return fmt.Errorf("resolve listen address: %w", err)
	}
	plain, err := net.ListenUDP("udp", listenAddress)
	if err != nil {
		return fmt.Errorf("listen for plain UDP: %w", err)
	}

	nextAddress, err := net.ResolveUDPAddr("udp", config.Next)
	if err != nil {
		plain.Close()
		return fmt.Errorf("resolve next address: %w", err)
	}
	tunnel, err := net.DialUDP("udp", nil, nextAddress)
	if err != nil {
		plain.Close()
		return fmt.Errorf("connect encoded UDP: %w", err)
	}

	ctx, cancel := context.WithCancel(parent)
	scheduler := NewCopyScheduler(ctx, config.CopyQueue, config.Metrics, config.Logger)
	plainPeer := &peerSlot{}
	deduper := NewDeduper(config.DedupeWindow, config.DedupeCapacity)
	sequence := initialSequence()

	workers := []func() error{
		func() error {
			buffer := make([]byte, MaxUDPPayload+1)
			for {
				n, peer, readErr := plain.ReadFromUDP(buffer)
				if readErr != nil {
					return fmt.Errorf("read plain UDP: %w", readErr)
				}
				config.Metrics.plainIn.Add(1)
				if n > MaxPlainPayload {
					config.Metrics.oversizeFrame.Add(1)
					continue
				}
				if plainPeer.Set(peer) {
					config.Metrics.peerChange.Add(1)
					config.Logger.Printf("plain peer changed; last sender is now effective")
				}
				sequence++
				packet, encodeErr := Encode(sequence, buffer[:n])
				if encodeErr != nil {
					config.Metrics.oversizeFrame.Add(1)
					continue
				}
				copies := CopiesFor(n, config.Copies, config.MaxDuplicateSize)
				if sendErr := sendCopies(packet, copies, config.Gap, func(payload []byte) error {
					_, writeErr := tunnel.Write(payload)
					return writeErr
				}, scheduler, config.Metrics); sendErr != nil {
					return fmt.Errorf("write encoded UDP: %w", sendErr)
				}
			}
		},
		func() error {
			buffer := make([]byte, MaxUDPPayload+1)
			for {
				n, readErr := tunnel.Read(buffer)
				if readErr != nil {
					return fmt.Errorf("read encoded UDP: %w", readErr)
				}
				config.Metrics.encodedIn.Add(1)
				sequenceNumber, payload, decodeErr := Decode(buffer[:n])
				if decodeErr != nil {
					countFrameError(config.Metrics, decodeErr)
					continue
				}
				first, evicted := deduper.First(sequenceNumber, time.Now())
				config.Metrics.dedupeEviction.Add(uint64(evicted))
				if !first {
					config.Metrics.duplicate.Add(1)
					continue
				}
				peer := plainPeer.Get()
				if peer == nil {
					config.Metrics.noPeer.Add(1)
					continue
				}
				if _, writeErr := plain.WriteToUDP(payload, peer); writeErr != nil {
					config.Metrics.sendError.Add(1)
					return fmt.Errorf("write plain UDP: %w", writeErr)
				}
				config.Metrics.plainOut.Add(1)
			}
		},
	}

	return supervise(ctx, cancel, scheduler, []io.Closer{plain, tunnel}, workers)
}

func runServer(parent context.Context, config Config) error {
	listenAddress, err := net.ResolveUDPAddr("udp", config.Listen)
	if err != nil {
		return fmt.Errorf("resolve listen address: %w", err)
	}
	tunnel, err := net.ListenUDP("udp", listenAddress)
	if err != nil {
		return fmt.Errorf("listen for encoded UDP: %w", err)
	}

	nextAddress, err := net.ResolveUDPAddr("udp", config.Next)
	if err != nil {
		tunnel.Close()
		return fmt.Errorf("resolve next address: %w", err)
	}
	plain, err := net.DialUDP("udp", nil, nextAddress)
	if err != nil {
		tunnel.Close()
		return fmt.Errorf("connect plain UDP: %w", err)
	}

	ctx, cancel := context.WithCancel(parent)
	scheduler := NewCopyScheduler(ctx, config.CopyQueue, config.Metrics, config.Logger)
	tunnelPeer := &peerSlot{}
	deduper := NewDeduper(config.DedupeWindow, config.DedupeCapacity)
	sequence := initialSequence()

	workers := []func() error{
		func() error {
			buffer := make([]byte, MaxUDPPayload+1)
			for {
				n, peer, readErr := tunnel.ReadFromUDP(buffer)
				if readErr != nil {
					return fmt.Errorf("read encoded UDP: %w", readErr)
				}
				config.Metrics.encodedIn.Add(1)
				sequenceNumber, payload, decodeErr := Decode(buffer[:n])
				if decodeErr != nil {
					countFrameError(config.Metrics, decodeErr)
					continue
				}
				if tunnelPeer.Set(peer) {
					config.Metrics.peerChange.Add(1)
					removed := deduper.Reset()
					config.Metrics.dedupeEviction.Add(uint64(removed))
					config.Logger.Printf("encoded peer changed; last sender is now effective")
				}
				first, evicted := deduper.First(sequenceNumber, time.Now())
				config.Metrics.dedupeEviction.Add(uint64(evicted))
				if !first {
					config.Metrics.duplicate.Add(1)
					continue
				}
				if _, writeErr := plain.Write(payload); writeErr != nil {
					config.Metrics.sendError.Add(1)
					return fmt.Errorf("write plain UDP: %w", writeErr)
				}
				config.Metrics.plainOut.Add(1)
			}
		},
		func() error {
			buffer := make([]byte, MaxUDPPayload+1)
			for {
				n, readErr := plain.Read(buffer)
				if readErr != nil {
					return fmt.Errorf("read plain UDP: %w", readErr)
				}
				config.Metrics.plainIn.Add(1)
				if n > MaxPlainPayload {
					config.Metrics.oversizeFrame.Add(1)
					continue
				}
				peer := tunnelPeer.Get()
				if peer == nil {
					config.Metrics.noPeer.Add(1)
					continue
				}
				sequence++
				packet, encodeErr := Encode(sequence, buffer[:n])
				if encodeErr != nil {
					config.Metrics.oversizeFrame.Add(1)
					continue
				}
				copies := CopiesFor(n, config.Copies, config.MaxDuplicateSize)
				if sendErr := sendCopies(packet, copies, config.Gap, func(payload []byte) error {
					_, writeErr := tunnel.WriteToUDP(payload, peer)
					return writeErr
				}, scheduler, config.Metrics); sendErr != nil {
					return fmt.Errorf("write encoded UDP: %w", sendErr)
				}
			}
		},
	}

	return supervise(ctx, cancel, scheduler, []io.Closer{tunnel, plain}, workers)
}

func sendCopies(packet []byte, copies int, gap time.Duration, send SendFunc, scheduler *CopyScheduler, metrics *Metrics) error {
	if err := send(packet); err != nil {
		metrics.sendError.Add(1)
		return err
	}
	metrics.encodedOut.Add(1)
	for copyNumber := 1; copyNumber < copies; copyNumber++ {
		scheduler.Schedule(packet, time.Duration(copyNumber)*gap, send)
	}
	return nil
}

func countFrameError(metrics *Metrics, err error) {
	if errors.Is(err, ErrOversize) {
		metrics.oversizeFrame.Add(1)
		return
	}
	metrics.invalidFrame.Add(1)
}

func supervise(
	ctx context.Context,
	cancel context.CancelFunc,
	scheduler *CopyScheduler,
	closers []io.Closer,
	workers []func() error,
) error {
	errorChannel := make(chan error, len(workers))
	var workersGroup sync.WaitGroup
	for _, worker := range workers {
		workersGroup.Add(1)
		go func(run func() error) {
			defer workersGroup.Done()
			errorChannel <- run()
		}(worker)
	}

	var result error
	select {
	case <-ctx.Done():
	case result = <-errorChannel:
	case result = <-scheduler.Errors():
	}

	cancel()
	for _, closer := range closers {
		_ = closer.Close()
	}
	scheduler.Close()
	workersGroup.Wait()

	if result != nil && !errors.Is(result, net.ErrClosed) && !errors.Is(result, context.Canceled) {
		return result
	}
	return nil
}

func initialSequence() uint64 {
	var random [8]byte
	if _, err := rand.Read(random[:]); err == nil {
		return binary.BigEndian.Uint64(random[:])
	}
	return uint64(time.Now().UnixNano())
}
