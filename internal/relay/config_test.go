package relay

import (
	"testing"
	"time"
)

func validConfig() Config {
	return Config{
		Mode:             ModeClient,
		Listen:           "127.0.0.1:10000",
		Next:             "127.0.0.1:20000",
		Copies:           2,
		MaxDuplicateSize: 300,
		Gap:              10 * time.Millisecond,
		CopyQueue:        4096,
		DedupeWindow:     30 * time.Second,
		DedupeCapacity:   65_536,
	}
}

func TestConfigValidation(t *testing.T) {
	if err := validConfig().Validate(); err != nil {
		t.Fatal(err)
	}
	tests := []struct {
		name   string
		mutate func(*Config)
	}{
		{"mode", func(c *Config) { c.Mode = "invalid" }},
		{"listen", func(c *Config) { c.Listen = "" }},
		{"next", func(c *Config) { c.Next = "" }},
		{"copies-low", func(c *Config) { c.Copies = 0 }},
		{"copies-high", func(c *Config) { c.Copies = 9 }},
		{"max-duplicate-size", func(c *Config) { c.MaxDuplicateSize = -1 }},
		{"gap", func(c *Config) { c.Gap = -time.Second }},
		{"copy-queue", func(c *Config) { c.CopyQueue = 0 }},
		{"dedupe-window", func(c *Config) { c.DedupeWindow = 0 }},
		{"dedupe-capacity", func(c *Config) { c.DedupeCapacity = 0 }},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			config := validConfig()
			test.mutate(&config)
			if err := config.Validate(); err == nil {
				t.Fatal("invalid configuration was accepted")
			}
		})
	}
}
