package main

import (
	"bytes"
	"flag"
	"fmt"
	"net"
	"os"
	"time"
)

func main() {
	mode := flag.String("mode", "", "echo or probe")
	address := flag.String("address", "", "listen or target address")
	payload := flag.String("payload", "udpredund-image-e2e", "probe payload")
	timeout := flag.Duration("timeout", 20*time.Second, "probe timeout")
	flag.Parse()
	var err error
	switch *mode {
	case "echo":
		err = echo(*address)
	case "probe":
		err = probe(*address, []byte(*payload), *timeout)
	default:
		err = fmt.Errorf("mode must be echo or probe")
	}
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func echo(address string) error {
	resolved, err := net.ResolveUDPAddr("udp4", address)
	if err != nil {
		return err
	}
	connection, err := net.ListenUDP("udp4", resolved)
	if err != nil {
		return err
	}
	defer connection.Close()
	buffer := make([]byte, 65_507)
	for {
		n, peer, readErr := connection.ReadFromUDP(buffer)
		if readErr != nil {
			return readErr
		}
		if _, writeErr := connection.WriteToUDP(buffer[:n], peer); writeErr != nil {
			return writeErr
		}
	}
}

func probe(address string, payload []byte, timeout time.Duration) error {
	resolved, err := net.ResolveUDPAddr("udp4", address)
	if err != nil {
		return err
	}
	connection, err := net.DialUDP("udp4", nil, resolved)
	if err != nil {
		return err
	}
	defer connection.Close()
	deadline := time.Now().Add(timeout)
	buffer := make([]byte, 65_507)
	for time.Now().Before(deadline) {
		if _, err := connection.Write(payload); err != nil {
			return err
		}
		_ = connection.SetReadDeadline(time.Now().Add(time.Second))
		n, err := connection.Read(buffer)
		if err == nil {
			if !bytes.Equal(buffer[:n], payload) {
				return fmt.Errorf("echo mismatch: got %q", buffer[:n])
			}
			fmt.Printf("received %q\n", payload)
			return nil
		}
		if networkError, ok := err.(net.Error); !ok || !networkError.Timeout() {
			return err
		}
	}
	return fmt.Errorf("timed out after %s", timeout)
}
