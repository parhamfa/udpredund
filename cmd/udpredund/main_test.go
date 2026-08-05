package main

import "testing"

func TestVersionFlag(t *testing.T) {
	if code := run([]string{"-version"}); code != 0 {
		t.Fatalf("code=%d", code)
	}
}

func TestInvalidArguments(t *testing.T) {
	if code := run([]string{"-mode", "invalid"}); code != 2 {
		t.Fatalf("code=%d", code)
	}
}
