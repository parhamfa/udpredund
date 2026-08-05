package relay

import (
	"context"
	"encoding/binary"
	"errors"
	"io"
	"log"
	"net"
	"sync"
	"syscall"
	"testing"
	"time"
)

func TestEndToEndSelectiveC2DeliversOneSmallPayload(t *testing.T) {
	echoAddress := startUDPEcho(t)
	serverAddress := unusedUDPAddress(t)
	clientAddress := unusedUDPAddress(t)
	serverMetrics := &Metrics{}
	clientMetrics := &Metrics{}
	server := startTestRelay(t, testRelayConfig(ModeServer, serverAddress, echoAddress, serverMetrics))
	client := startTestRelay(t, testRelayConfig(ModeClient, clientAddress, serverAddress, clientMetrics))
	waitForRelays()

	connection := dialUDP(t, clientAddress)
	payload := []byte("wireguard-small-control-datagram")
	writeUDP(t, connection, payload)
	if got := readUDP(t, connection, 2*time.Second); string(got) != string(payload) {
		t.Fatalf("got %q, want %q", got, payload)
	}
	assertNoUDP(t, connection, 100*time.Millisecond)
	eventually(t, time.Second, func() bool {
		return clientMetrics.Snapshot().QueuedCopy >= 1 &&
			serverMetrics.Snapshot().QueuedCopy >= 1 &&
			clientMetrics.Snapshot().Duplicate >= 1 &&
			serverMetrics.Snapshot().Duplicate >= 1
	})

	client.stop(t)
	server.stop(t)
}

func TestEndToEndSelectiveC2DoesNotDuplicateLargePayload(t *testing.T) {
	echoAddress := startUDPEcho(t)
	serverAddress := unusedUDPAddress(t)
	clientAddress := unusedUDPAddress(t)
	serverMetrics := &Metrics{}
	clientMetrics := &Metrics{}
	server := startTestRelay(t, testRelayConfig(ModeServer, serverAddress, echoAddress, serverMetrics))
	client := startTestRelay(t, testRelayConfig(ModeClient, clientAddress, serverAddress, clientMetrics))
	waitForRelays()

	connection := dialUDP(t, clientAddress)
	payload := make([]byte, 1200)
	for index := range payload {
		payload[index] = byte(index)
	}
	writeUDP(t, connection, payload)
	if got := readUDP(t, connection, 2*time.Second); string(got) != string(payload) {
		t.Fatal("large payload changed in transit")
	}
	time.Sleep(50 * time.Millisecond)
	if clientMetrics.Snapshot().QueuedCopy != 0 || serverMetrics.Snapshot().QueuedCopy != 0 {
		t.Fatalf("large datagram was duplicated: client=%+v server=%+v", clientMetrics.Snapshot(), serverMetrics.Snapshot())
	}

	client.stop(t)
	server.stop(t)
}

func TestEndToEndSelectiveC2SurvivesFirstCopyLoss(t *testing.T) {
	testFaultedRoundTrip(t, faultDropFirst)
}

func TestEndToEndDedupesDelayedReorderedCopies(t *testing.T) {
	testFaultedRoundTrip(t, faultReorderAndDuplicate)
}

func testFaultedRoundTrip(t *testing.T, policy faultPolicy) {
	t.Helper()
	echoAddress := startUDPEcho(t)
	serverAddress := unusedUDPAddress(t)
	proxy := startFaultProxy(t, serverAddress, policy)
	clientAddress := unusedUDPAddress(t)
	serverMetrics := &Metrics{}
	clientMetrics := &Metrics{}
	server := startTestRelay(t, testRelayConfig(ModeServer, serverAddress, echoAddress, serverMetrics))
	client := startTestRelay(t, testRelayConfig(ModeClient, clientAddress, proxy.address, clientMetrics))
	waitForRelays()

	connection := dialUDP(t, clientAddress)
	payload := []byte("selective-c2-under-controlled-impairment")
	writeUDP(t, connection, payload)
	if got := readUDP(t, connection, 3*time.Second); string(got) != string(payload) {
		t.Fatalf("got %q, want %q", got, payload)
	}
	assertNoUDP(t, connection, 150*time.Millisecond)
	eventually(t, time.Second, func() bool {
		return proxy.observedCopies() >= 4
	})

	client.stop(t)
	server.stop(t)
}

func TestOldClientInteroperatesWithNewServer(t *testing.T) {
	echoAddress := startUDPEcho(t)
	serverAddress := unusedUDPAddress(t)
	config := testRelayConfig(ModeServer, serverAddress, echoAddress, &Metrics{})
	config.Copies = 1
	server := startTestRelay(t, config)
	waitForRelays()

	connection := dialUDP(t, serverAddress)
	payload := []byte("legacy-client-to-new-server")
	writeUDP(t, connection, legacyEncode(123, payload))
	frame := readUDP(t, connection, 2*time.Second)
	_, got, ok := legacyDecode(frame)
	if !ok || string(got) != string(payload) {
		t.Fatalf("ok=%v payload=%q", ok, got)
	}
	server.stop(t)
}

func TestNewClientInteroperatesWithOldServer(t *testing.T) {
	legacyAddress := startLegacyEchoServer(t)
	clientAddress := unusedUDPAddress(t)
	config := testRelayConfig(ModeClient, clientAddress, legacyAddress, &Metrics{})
	config.Copies = 1
	client := startTestRelay(t, config)
	waitForRelays()

	connection := dialUDP(t, clientAddress)
	payload := []byte("new-client-to-legacy-server")
	writeUDP(t, connection, payload)
	if got := readUDP(t, connection, 2*time.Second); string(got) != string(payload) {
		t.Fatalf("got %q, want %q", got, payload)
	}
	client.stop(t)
}

func TestServerRejectsMalformedFrameAndContinues(t *testing.T) {
	echoAddress := startUDPEcho(t)
	serverAddress := unusedUDPAddress(t)
	metrics := &Metrics{}
	config := testRelayConfig(ModeServer, serverAddress, echoAddress, metrics)
	config.Copies = 1
	server := startTestRelay(t, config)
	waitForRelays()

	connection := dialUDP(t, serverAddress)
	writeUDP(t, connection, []byte("not-udr1"))
	eventually(t, time.Second, func() bool { return metrics.Snapshot().InvalidFrame == 1 })
	payload := []byte("valid-after-malformed")
	writeUDP(t, connection, legacyEncode(456, payload))
	frame := readUDP(t, connection, 2*time.Second)
	_, got, ok := legacyDecode(frame)
	if !ok || string(got) != string(payload) {
		t.Fatalf("ok=%v payload=%q", ok, got)
	}
	server.stop(t)
}

func TestClientDropsOversizedPlainDatagramAndContinues(t *testing.T) {
	sink, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.ParseIP("127.0.0.1")})
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = sink.Close() })
	clientAddress := unusedUDPAddress(t)
	metrics := &Metrics{}
	config := testRelayConfig(ModeClient, clientAddress, sink.LocalAddr().String(), metrics)
	client := startTestRelay(t, config)
	waitForRelays()

	connection := dialUDP(t, clientAddress)
	if _, err := connection.Write(make([]byte, MaxPlainPayload+1)); err != nil {
		if errors.Is(err, syscall.EMSGSIZE) {
			t.Skipf("host kernel refuses a legal IPv4 UDP payload at this size: %v", err)
		}
		t.Fatal(err)
	}
	eventually(t, time.Second, func() bool { return metrics.Snapshot().OversizeFrame == 1 })
	writeUDP(t, connection, []byte("small-after-oversize"))
	buffer := make([]byte, MaxUDPPayload)
	if err := sink.SetReadDeadline(time.Now().Add(2 * time.Second)); err != nil {
		t.Fatal(err)
	}
	n, _, err := sink.ReadFromUDP(buffer)
	if err != nil {
		t.Fatal(err)
	}
	if _, payload, err := Decode(buffer[:n]); err != nil || string(payload) != "small-after-oversize" {
		t.Fatalf("decode err=%v payload=%q", err, payload)
	}
	client.stop(t)
}

type relayProcess struct {
	cancel context.CancelFunc
	done   chan error
	once   sync.Once
}

func startTestRelay(t *testing.T, config Config) *relayProcess {
	t.Helper()
	ctx, cancel := context.WithCancel(context.Background())
	process := &relayProcess{cancel: cancel, done: make(chan error, 1)}
	go func() { process.done <- Run(ctx, config) }()
	t.Cleanup(func() { process.stop(t) })
	return process
}

func (p *relayProcess) stop(t *testing.T) {
	t.Helper()
	p.once.Do(func() {
		p.cancel()
		select {
		case err := <-p.done:
			if err != nil {
				t.Errorf("relay stopped with error: %v", err)
			}
		case <-time.After(2 * time.Second):
			t.Error("relay did not stop cleanly")
		}
	})
}

func testRelayConfig(mode Mode, listen, next string, metrics *Metrics) Config {
	return Config{
		Mode:             mode,
		Listen:           listen,
		Next:             next,
		Copies:           2,
		MaxDuplicateSize: 300,
		Gap:              10 * time.Millisecond,
		CopyQueue:        128,
		DedupeWindow:     30 * time.Second,
		DedupeCapacity:   1024,
		Metrics:          metrics,
		Logger:           log.New(io.Discard, "", 0),
	}
}

func startUDPEcho(t *testing.T) string {
	t.Helper()
	connection, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.ParseIP("127.0.0.1")})
	if err != nil {
		t.Fatal(err)
	}
	done := make(chan struct{})
	go func() {
		defer close(done)
		buffer := make([]byte, MaxUDPPayload)
		for {
			n, peer, readErr := connection.ReadFromUDP(buffer)
			if readErr != nil {
				return
			}
			if _, writeErr := connection.WriteToUDP(buffer[:n], peer); writeErr != nil {
				return
			}
		}
	}()
	t.Cleanup(func() {
		_ = connection.Close()
		<-done
	})
	return connection.LocalAddr().String()
}

func startLegacyEchoServer(t *testing.T) string {
	t.Helper()
	connection, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.ParseIP("127.0.0.1")})
	if err != nil {
		t.Fatal(err)
	}
	done := make(chan struct{})
	go func() {
		defer close(done)
		buffer := make([]byte, MaxUDPPayload)
		var responseSequence uint64 = 9000
		for {
			n, peer, readErr := connection.ReadFromUDP(buffer)
			if readErr != nil {
				return
			}
			_, payload, ok := legacyDecode(buffer[:n])
			if !ok {
				continue
			}
			responseSequence++
			if _, writeErr := connection.WriteToUDP(legacyEncode(responseSequence, payload), peer); writeErr != nil {
				return
			}
		}
	}()
	t.Cleanup(func() {
		_ = connection.Close()
		<-done
	})
	return connection.LocalAddr().String()
}

// legacyEncode and legacyDecode reproduce the deployed pre-public implementation.
func legacyEncode(sequence uint64, payload []byte) []byte {
	packet := make([]byte, 12+len(payload))
	copy(packet[:4], []byte{'U', 'D', 'R', '1'})
	binary.BigEndian.PutUint64(packet[4:12], sequence)
	copy(packet[12:], payload)
	return packet
}

func legacyDecode(packet []byte) (uint64, []byte, bool) {
	if len(packet) < 12 || string(packet[:4]) != "UDR1" {
		return 0, nil, false
	}
	return binary.BigEndian.Uint64(packet[4:12]), packet[12:], true
}

func unusedUDPAddress(t *testing.T) string {
	t.Helper()
	connection, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.ParseIP("127.0.0.1")})
	if err != nil {
		t.Fatal(err)
	}
	address := connection.LocalAddr().String()
	if err := connection.Close(); err != nil {
		t.Fatal(err)
	}
	return address
}

func dialUDP(t *testing.T, address string) *net.UDPConn {
	t.Helper()
	remote, err := net.ResolveUDPAddr("udp4", address)
	if err != nil {
		t.Fatal(err)
	}
	connection, err := net.DialUDP("udp4", nil, remote)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = connection.Close() })
	return connection
}

func writeUDP(t *testing.T, connection *net.UDPConn, payload []byte) {
	t.Helper()
	if _, err := connection.Write(payload); err != nil {
		t.Fatal(err)
	}
}

func readUDP(t *testing.T, connection *net.UDPConn, timeout time.Duration) []byte {
	t.Helper()
	if err := connection.SetReadDeadline(time.Now().Add(timeout)); err != nil {
		t.Fatal(err)
	}
	buffer := make([]byte, MaxUDPPayload)
	n, err := connection.Read(buffer)
	if err != nil {
		t.Fatal(err)
	}
	return append([]byte(nil), buffer[:n]...)
}

func assertNoUDP(t *testing.T, connection *net.UDPConn, timeout time.Duration) {
	t.Helper()
	if err := connection.SetReadDeadline(time.Now().Add(timeout)); err != nil {
		t.Fatal(err)
	}
	buffer := make([]byte, MaxUDPPayload)
	if _, err := connection.Read(buffer); err == nil {
		t.Fatal("received a duplicate plain payload")
	} else {
		var networkError net.Error
		if !errors.As(err, &networkError) || !networkError.Timeout() {
			t.Fatalf("unexpected read error: %v", err)
		}
	}
}

func waitForRelays() { time.Sleep(40 * time.Millisecond) }

type faultPolicy int

const (
	faultDropFirst faultPolicy = iota
	faultReorderAndDuplicate
)

type heldDatagram struct {
	payload []byte
	peer    *net.UDPAddr
}

type faultProxy struct {
	address string
	conn    *net.UDPConn
	done    chan struct{}
	mu      sync.Mutex
	counts  map[string]int
	held    map[string]heldDatagram
}

func startFaultProxy(t *testing.T, serverAddress string, policy faultPolicy) *faultProxy {
	t.Helper()
	server, err := net.ResolveUDPAddr("udp4", serverAddress)
	if err != nil {
		t.Fatal(err)
	}
	connection, err := net.ListenUDP("udp4", &net.UDPAddr{IP: net.ParseIP("127.0.0.1")})
	if err != nil {
		t.Fatal(err)
	}
	proxy := &faultProxy{
		address: connection.LocalAddr().String(),
		conn:    connection,
		done:    make(chan struct{}),
		counts:  make(map[string]int),
		held:    make(map[string]heldDatagram),
	}
	go proxy.run(server, policy)
	t.Cleanup(func() {
		_ = connection.Close()
		<-proxy.done
	})
	return proxy
}

func (p *faultProxy) run(server *net.UDPAddr, policy faultPolicy) {
	defer close(p.done)
	buffer := make([]byte, MaxUDPPayload)
	var client *net.UDPAddr
	for {
		n, peer, err := p.conn.ReadFromUDP(buffer)
		if err != nil {
			return
		}
		payload := append([]byte(nil), buffer[:n]...)
		sequence, _, decodeErr := Decode(payload)
		if decodeErr != nil {
			continue
		}
		direction := "client"
		destination := server
		if peer.String() == server.String() {
			direction = "server"
			destination = client
		} else {
			client = cloneUDPAddr(peer)
		}
		if destination == nil {
			continue
		}
		key := direction + ":" + string(binary.BigEndian.AppendUint64(nil, sequence))
		p.mu.Lock()
		p.counts[key]++
		occurrence := p.counts[key]
		if policy == faultReorderAndDuplicate && occurrence == 1 {
			p.held[key] = heldDatagram{payload: payload, peer: cloneUDPAddr(destination)}
		}
		held := p.held[key]
		p.mu.Unlock()

		switch policy {
		case faultDropFirst:
			if occurrence == 1 {
				continue
			}
			_, _ = p.conn.WriteToUDP(payload, destination)
		case faultReorderAndDuplicate:
			if occurrence == 1 {
				continue
			}
			_, _ = p.conn.WriteToUDP(payload, destination)
			if held.peer != nil {
				time.Sleep(3 * time.Millisecond)
				_, _ = p.conn.WriteToUDP(held.payload, held.peer)
				_, _ = p.conn.WriteToUDP(held.payload, held.peer)
			}
		}
	}
}

func (p *faultProxy) observedCopies() int {
	p.mu.Lock()
	defer p.mu.Unlock()
	total := 0
	for _, count := range p.counts {
		total += count
	}
	return total
}
