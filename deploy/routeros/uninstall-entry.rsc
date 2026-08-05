# udpredund v0.1.0-beta.1 - RouterOS entry uninstaller
# Edit this block only if you changed the matching installer values.
:local entryPrefix "10.254.241"
:local storageRoot "udpredund"

:local owner "udpredund:v0.1-entry"
:local bridgeName "udrbe-br"
:local vethName "udrbe-veth"
:local envList "udrbe-env"
:local containerName "udrbe-carrier"
:local natComment "udpredund:v0.1-entry-icmp-srcnat"
:local entryGatewayCIDR ($entryPrefix . ".1/24")
:local entryContainerIP ($entryPrefix . ".2")
:local udrListenPort 45111
:local rootDir ($storageRoot . "/entry-root")
:local layerDir ($storageRoot . "/entry-layers")

:put "udpredund entry uninstall: running read-only ownership checks"
:if ([:len [/interface/wireguard/peers/find where endpoint-address=$entryContainerIP and endpoint-port=$udrListenPort]] > 0) do={ :error "refusing uninstall: a WireGuard peer still targets this carrier; move the peer endpoint first" }
:if (([:len [/container/find where name=$containerName]] > 0) && ([:len [/container/find where name=$containerName and comment=$owner]] != 1)) do={ :error "refusing uninstall: entry container ownership does not match" }
:if (([:len [/interface/bridge/find where name=$bridgeName]] > 0) && ([:len [/interface/bridge/find where name=$bridgeName and comment=$owner]] != 1)) do={ :error "refusing uninstall: bridge ownership does not match" }
:if (([:len [/interface/veth/find where name=$vethName]] > 0) && ([:len [/interface/veth/find where name=$vethName and comment=$owner]] != 1)) do={ :error "refusing uninstall: veth ownership does not match" }
:if ([:len [/ip/firewall/nat/find where comment=$natComment]] > 1) do={ :error "refusing uninstall: NAT ownership marker is ambiguous" }
:if (([:len [/interface/bridge/port/find where bridge=$bridgeName and interface=$vethName]] > 0) && ([:len [/interface/bridge/port/find where bridge=$bridgeName and interface=$vethName and comment=$owner]] != 1)) do={ :error "refusing uninstall: bridge-port ownership does not match" }
:if (([:len [/ip/address/find where interface=$bridgeName and address=$entryGatewayCIDR]] > 0) && ([:len [/ip/address/find where interface=$bridgeName and address=$entryGatewayCIDR and comment=$owner]] != 1)) do={ :error "refusing uninstall: IP-address ownership does not match" }

:local containerId [/container/find where name=$containerName and comment=$owner]
:if ([:len [/ip/firewall/nat/find where comment=$natComment]] > 0) do={ /ip/firewall/nat/disable [find where comment=$natComment] }
:if ([:len $containerId] > 0) do={
  /container/set $containerId start-on-boot=no auto-restart-interval=0s
  :delay 2s
  :if ([/container/get $containerId running] = true) do={ /container/stop $containerId; :delay 12s }
  :if ([/container/get $containerId running] = true) do={ :error "entry container did not stop; remaining objects were retained" }
  /container/remove $containerId
}
:if ([:len [/ip/firewall/nat/find where comment=$natComment]] > 0) do={ /ip/firewall/nat/remove [find where comment=$natComment] }
/container/envs/remove [find where list=$envList]
:if ([:len [/interface/bridge/port/find where bridge=$bridgeName and interface=$vethName and comment=$owner]] > 0) do={ /interface/bridge/port/remove [find where bridge=$bridgeName and interface=$vethName and comment=$owner] }
:if ([:len [/interface/veth/find where name=$vethName and comment=$owner]] > 0) do={ /interface/veth/remove [find where name=$vethName and comment=$owner] }
:if ([:len [/ip/address/find where interface=$bridgeName and address=$entryGatewayCIDR and comment=$owner]] > 0) do={ /ip/address/remove [find where interface=$bridgeName and address=$entryGatewayCIDR and comment=$owner] }
:if ([:len [/interface/bridge/find where name=$bridgeName and comment=$owner]] > 0) do={ /interface/bridge/remove [find where name=$bridgeName and comment=$owner] }
:if ([:len [/container/find where layer-dir=$layerDir]] = 0) do={
  :if ([:len [/file/find where name=$rootDir]] > 0) do={ /file/remove [find where name=$rootDir] }
  :if ([:len [/file/find where name=$layerDir]] > 0) do={ /file/remove [find where name=$layerDir] }
} else={ :put "Layer directory retained because another container references it." }
:put "udpredund entry objects removed. The uploaded image tar was retained."
