package relay

import (
	"fmt"
	"log"
	"time"
)

type Mode string

const (
	ModeClient Mode = "client"
	ModeServer Mode = "server"
)

type Config struct {
	Mode             Mode
	Listen           string
	Next             string
	Copies           int
	MaxDuplicateSize int
	Gap              time.Duration
	CopyQueue        int
	DedupeWindow     time.Duration
	DedupeCapacity   int
	Metrics          *Metrics
	Logger           *log.Logger
}

func (c Config) Validate() error {
	if c.Mode != ModeClient && c.Mode != ModeServer {
		return fmt.Errorf("mode must be %q or %q", ModeClient, ModeServer)
	}
	if c.Listen == "" {
		return fmt.Errorf("listen address is required")
	}
	if c.Next == "" {
		return fmt.Errorf("next address is required")
	}
	if c.Copies < 1 || c.Copies > 8 {
		return fmt.Errorf("copies must be between 1 and 8")
	}
	if c.MaxDuplicateSize < 0 || c.MaxDuplicateSize > MaxPlainPayload {
		return fmt.Errorf("max-duplicate-size must be between 0 and %d", MaxPlainPayload)
	}
	if c.Gap < 0 {
		return fmt.Errorf("gap must not be negative")
	}
	if c.CopyQueue < 1 {
		return fmt.Errorf("copy-queue must be at least 1")
	}
	if c.DedupeWindow <= 0 {
		return fmt.Errorf("dedupe-window must be positive")
	}
	if c.DedupeCapacity < 1 {
		return fmt.Errorf("dedupe-capacity must be at least 1")
	}
	return nil
}
