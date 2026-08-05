package relay

import (
	"net"
	"sync"
)

type peerSlot struct {
	mu   sync.RWMutex
	peer *net.UDPAddr
}

// Set implements the beta's single-effective-peer policy: last valid sender wins.
// changed excludes initial discovery and reports a replacement only.
func (p *peerSlot) Set(peer *net.UDPAddr) (changed bool) {
	copyOfPeer := cloneUDPAddr(peer)
	p.mu.Lock()
	defer p.mu.Unlock()
	changed = p.peer != nil && p.peer.String() != copyOfPeer.String()
	p.peer = copyOfPeer
	return changed
}

func (p *peerSlot) Get() *net.UDPAddr {
	p.mu.RLock()
	defer p.mu.RUnlock()
	return cloneUDPAddr(p.peer)
}

func cloneUDPAddr(address *net.UDPAddr) *net.UDPAddr {
	if address == nil {
		return nil
	}
	cloned := *address
	cloned.IP = append(net.IP(nil), address.IP...)
	return &cloned
}
