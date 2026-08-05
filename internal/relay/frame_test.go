package relay

import (
	"encoding/hex"
	"encoding/json"
	"errors"
	"os"
	"testing"
)

type compatibilityVector struct {
	Name       string `json:"name"`
	Sequence   uint64 `json:"sequence"`
	PayloadHex string `json:"payload_hex"`
	FrameHex   string `json:"frame_hex"`
}

func TestUDR1CompatibilityVectors(t *testing.T) {
	data, err := os.ReadFile("testdata/udr1-vectors.json")
	if err != nil {
		t.Fatal(err)
	}
	var vectors []compatibilityVector
	if err := json.Unmarshal(data, &vectors); err != nil {
		t.Fatal(err)
	}
	for _, vector := range vectors {
		t.Run(vector.Name, func(t *testing.T) {
			payload, err := hex.DecodeString(vector.PayloadHex)
			if err != nil {
				t.Fatal(err)
			}
			wantFrame, err := hex.DecodeString(vector.FrameHex)
			if err != nil {
				t.Fatal(err)
			}
			frame, err := Encode(vector.Sequence, payload)
			if err != nil {
				t.Fatal(err)
			}
			if string(frame) != string(wantFrame) {
				t.Fatalf("frame mismatch\n got: %x\nwant: %x", frame, wantFrame)
			}
			sequence, decoded, err := Decode(wantFrame)
			if err != nil {
				t.Fatal(err)
			}
			if sequence != vector.Sequence || string(decoded) != string(payload) {
				t.Fatalf("decoded sequence=%d payload=%x", sequence, decoded)
			}
		})
	}
}

func TestDecodeRejectsMalformedAndOversizedFrames(t *testing.T) {
	tests := []struct {
		name  string
		frame []byte
		want  error
	}{
		{name: "empty", frame: nil, want: ErrShortFrame},
		{name: "short", frame: []byte("UDR1short"), want: ErrShortFrame},
		{name: "magic", frame: []byte("BAD!00000000"), want: ErrMagic},
		{name: "oversize", frame: make([]byte, MaxUDPPayload+1), want: ErrOversize},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			if _, _, err := Decode(test.frame); !errors.Is(err, test.want) {
				t.Fatalf("got %v, want %v", err, test.want)
			}
		})
	}
}

func TestEncodeRejectsOversizedPayload(t *testing.T) {
	if _, err := Encode(1, make([]byte, MaxPlainPayload+1)); !errors.Is(err, ErrOversize) {
		t.Fatalf("got %v, want %v", err, ErrOversize)
	}
}

func TestSelectiveDuplication(t *testing.T) {
	if got := CopiesFor(148, 2, 300); got != 2 {
		t.Fatalf("small control packet got %d copies", got)
	}
	if got := CopiesFor(1200, 2, 300); got != 1 {
		t.Fatalf("bulk packet got %d copies", got)
	}
	if got := CopiesFor(1200, 2, 0); got != 2 {
		t.Fatalf("unlimited policy got %d copies", got)
	}
}

func FuzzDecode(f *testing.F) {
	f.Add([]byte("UDR1\x00\x00\x00\x00\x00\x00\x00\x01payload"))
	f.Add([]byte("not-a-frame"))
	f.Fuzz(func(t *testing.T, packet []byte) {
		sequence, payload, err := Decode(packet)
		if err != nil {
			return
		}
		reencoded, err := Encode(sequence, payload)
		if err != nil {
			t.Fatal(err)
		}
		if string(reencoded) != string(packet) {
			t.Fatalf("round trip mismatch: %x != %x", reencoded, packet)
		}
	})
}
