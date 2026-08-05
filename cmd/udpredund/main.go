package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/parhamfa/udpredund/internal/relay"
)

var (
	version = "dev"
	commit  = "unknown"
	date    = "unknown"
)

func main() {
	os.Exit(run(os.Args[1:]))
}

func run(arguments []string) int {
	flags := flag.NewFlagSet("udpredund", flag.ContinueOnError)
	flags.SetOutput(os.Stderr)
	mode := flags.String("mode", "", "client or server")
	listen := flags.String("listen", "", "UDP listen address")
	next := flags.String("next", "", "next UDP address")
	copies := flags.Int("copies", 2, "number of encoded copies")
	maxDuplicateSize := flags.Int("max-duplicate-size", 0, "duplicate only payloads at or below this size; 0 duplicates all")
	gap := flags.Duration("gap", time.Millisecond, "delay between copies")
	copyQueue := flags.Int("copy-queue", 4096, "maximum queued delayed copies")
	dedupeWindow := flags.Duration("dedupe-window", 30*time.Second, "time to retain received sequence numbers")
	dedupeCapacity := flags.Int("dedupe-capacity", 65_536, "maximum retained sequence numbers")
	metricsInterval := flags.Duration("metrics-interval", 5*time.Second, "metrics log interval; 0 disables periodic logs")
	showVersion := flags.Bool("version", false, "print version and exit")
	if err := flags.Parse(arguments); err != nil {
		return 2
	}
	if *showVersion {
		fmt.Printf("udpredund %s commit=%s built=%s\n", version, commit, date)
		return 0
	}
	if *metricsInterval < 0 {
		fmt.Fprintln(os.Stderr, "metrics-interval must not be negative")
		return 2
	}

	logger := log.New(os.Stderr, "udpredund: ", log.LstdFlags|log.Lmicroseconds)
	metrics := &relay.Metrics{}
	config := relay.Config{
		Mode:             relay.Mode(*mode),
		Listen:           *listen,
		Next:             *next,
		Copies:           *copies,
		MaxDuplicateSize: *maxDuplicateSize,
		Gap:              *gap,
		CopyQueue:        *copyQueue,
		DedupeWindow:     *dedupeWindow,
		DedupeCapacity:   *dedupeCapacity,
		Metrics:          metrics,
		Logger:           logger,
	}
	if err := config.Validate(); err != nil {
		fmt.Fprintf(os.Stderr, "configuration: %v\n", err)
		flags.Usage()
		return 2
	}

	ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()
	if *metricsInterval > 0 {
		go logMetrics(ctx, logger, metrics, *metricsInterval)
	}

	logger.Printf(
		"version=%s mode=%s listen=%s next=%s copies=%d max_duplicate_size=%d gap=%s copy_queue=%d dedupe_window=%s dedupe_capacity=%d",
		version, config.Mode, config.Listen, config.Next, config.Copies,
		config.MaxDuplicateSize, config.Gap, config.CopyQueue,
		config.DedupeWindow, config.DedupeCapacity,
	)
	if err := relay.Run(ctx, config); err != nil {
		logger.Printf("fatal: %v", err)
		logger.Printf("metrics final %s", metrics.Snapshot())
		return 1
	}
	logger.Printf("stopped cleanly; metrics final %s", metrics.Snapshot())
	return 0
}

func logMetrics(ctx context.Context, logger *log.Logger, metrics *relay.Metrics, interval time.Duration) {
	ticker := time.NewTicker(interval)
	defer ticker.Stop()
	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			logger.Printf("metrics %s", metrics.Snapshot())
		}
	}
}
