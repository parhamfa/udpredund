# udpredund v0.1.0-beta.1 - read-only RouterOS verification
:local entryOwner "udpredund:v0.1-entry"
:local exitOwner "udpredund:v0.1-exit"
:local entryNat "udpredund:v0.1-entry-icmp-srcnat"
:local exitNat "udpredund:v0.1-exit-icmp-dnat"

:put "=== udpredund containers ==="
:foreach id in=[/container/find where comment=$entryOwner or comment=$exitOwner] do={
  :put ("name=" . [/container/get $id name] . " running=" . [/container/get $id running] . " start-on-boot=" . [/container/get $id start-on-boot] . " arch=" . [/container/get $id arch] . " image-id=" . [/container/get $id image-id])
}
:put "=== udpredund interfaces ==="
:foreach id in=[/interface/find where comment=$entryOwner or comment=$exitOwner] do={
  :put ("name=" . [/interface/get $id name] . " type=" . [/interface/get $id type] . " running=" . [/interface/get $id running])
}
:put "=== udpredund NAT rules ==="
:foreach id in=[/ip/firewall/nat/find where comment=$entryNat or comment=$exitNat] do={
  :put ("comment=" . [/ip/firewall/nat/get $id comment] . " disabled=" . [/ip/firewall/nat/get $id disabled] . " packets=" . [/ip/firewall/nat/get $id packets] . " bytes=" . [/ip/firewall/nat/get $id bytes])
}
:put "Verification is read-only. Inspect WireGuard handshake/loss metrics separately."
:put "Container logs are intentionally omitted because RouterOS may log environment values, including PT_KEY."
