package relay

import (
	"net"
	"testing"
)

func TestPeerSlotUsesLastSender(t *testing.T) {
	var slot peerSlot
	first := &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 1000}
	second := &net.UDPAddr{IP: net.ParseIP("127.0.0.1"), Port: 2000}
	if slot.Set(first) {
		t.Fatal("initial peer was reported as a change")
	}
	if slot.Set(first) {
		t.Fatal("same peer was reported as a change")
	}
	if !slot.Set(second) {
		t.Fatal("replacement peer was not reported")
	}
	if got := slot.Get(); got.String() != second.String() {
		t.Fatalf("got %s, want %s", got, second)
	}
}
