// Package relay implements the UDR1 UDP redundancy relay.
package relay

import (
	"bytes"
	"encoding/binary"
	"errors"
)

const (
	// HeaderSize is four bytes of magic followed by a big-endian uint64 sequence.
	HeaderSize = 12
	// MaxUDPPayload is the maximum payload of an IPv4 UDP datagram.
	MaxUDPPayload = 65_507
	// MaxPlainPayload leaves enough room for the UDR1 header.
	MaxPlainPayload = MaxUDPPayload - HeaderSize
)

var (
	// Magic is deliberately unchanged from the deployed implementation.
	Magic = [4]byte{'U', 'D', 'R', '1'}

	ErrShortFrame = errors.New("UDR1 frame is shorter than its header")
	ErrMagic      = errors.New("UDR1 frame has invalid magic")
	ErrOversize   = errors.New("UDR1 frame exceeds the UDP payload limit")
)

// Encode creates a wire-compatible UDR1 frame.
func Encode(sequence uint64, payload []byte) ([]byte, error) {
	if len(payload) > MaxPlainPayload {
		return nil, ErrOversize
	}
	packet := make([]byte, HeaderSize+len(payload))
	copy(packet[:4], Magic[:])
	binary.BigEndian.PutUint64(packet[4:HeaderSize], sequence)
	copy(packet[HeaderSize:], payload)
	return packet, nil
}

// Decode validates and splits a UDR1 frame. The returned payload aliases packet.
func Decode(packet []byte) (uint64, []byte, error) {
	if len(packet) > MaxUDPPayload {
		return 0, nil, ErrOversize
	}
	if len(packet) < HeaderSize {
		return 0, nil, ErrShortFrame
	}
	if !bytes.Equal(packet[:4], Magic[:]) {
		return 0, nil, ErrMagic
	}
	return binary.BigEndian.Uint64(packet[4:HeaderSize]), packet[HeaderSize:], nil
}

// CopiesFor applies selective duplication without changing the original policy.
func CopiesFor(payloadSize, copies, maxDuplicateSize int) int {
	if maxDuplicateSize > 0 && payloadSize > maxDuplicateSize {
		return 1
	}
	return copies
}
