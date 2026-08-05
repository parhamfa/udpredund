# udpredund v0.1.0-beta.1 - RouterOS exit uninstaller
# Edit this block only if you changed the matching installer value.
:local storageRoot "udpredund"

:local owner "udpredund:v0.1-exit"
:local bridgeName "udrbx-br"
:local ptVethName "udrbx-pt"
:local udrVethName "udrbx-udr"
:local ptEnvList "udrbx-pt-env"
:local udrEnvList "udrbx-udr-env"
:local ptContainerName "udrbx-pt"
:local udrContainerName "udrbx-udr"
:local natComment "udpredund:v0.1-exit-icmp-dnat"
:local ptRootDir ($storageRoot . "/exit-pt-root")
:local udrRootDir ($storageRoot . "/exit-udr-root")
:local layerDir ($storageRoot . "/exit-layers")

:put "udpredund exit uninstall: running read-only ownership checks"
:if (([:len [/container/find where name=$ptContainerName]] > 0) && ([:len [/container/find where name=$ptContainerName and comment=$owner]] != 1)) do={ :error "refusing uninstall: PingTunnel container ownership does not match" }
:if (([:len [/container/find where name=$udrContainerName]] > 0) && ([:len [/container/find where name=$udrContainerName and comment=$owner]] != 1)) do={ :error "refusing uninstall: UDR container ownership does not match" }
:if (([:len [/interface/bridge/find where name=$bridgeName]] > 0) && ([:len [/interface/bridge/find where name=$bridgeName and comment=$owner]] != 1)) do={ :error "refusing uninstall: bridge ownership does not match" }
:if (([:len [/interface/veth/find where name=$ptVethName]] > 0) && ([:len [/interface/veth/find where name=$ptVethName and comment=$owner]] != 1)) do={ :error "refusing uninstall: PingTunnel veth ownership does not match" }
:if (([:len [/interface/veth/find where name=$udrVethName]] > 0) && ([:len [/interface/veth/find where name=$udrVethName and comment=$owner]] != 1)) do={ :error "refusing uninstall: UDR veth ownership does not match" }
:if ([:len [/ip/firewall/nat/find where comment=$natComment]] > 1) do={ :error "refusing uninstall: NAT ownership marker is ambiguous" }

:local ptContainer [/container/find where name=$ptContainerName and comment=$owner]
:local udrContainer [/container/find where name=$udrContainerName and comment=$owner]
:if ([:len [/ip/firewall/nat/find where comment=$natComment]] > 0) do={ /ip/firewall/nat/disable [find where comment=$natComment] }
:if ([:len $ptContainer] > 0) do={
  /container/set $ptContainer start-on-boot=no auto-restart-interval=0s
  :delay 2s
  :if ([/container/get $ptContainer running] = true) do={ /container/stop $ptContainer; :delay 12s }
  :if ([/container/get $ptContainer running] = true) do={ :error "PingTunnel container did not stop; remaining objects were retained" }
  /container/remove $ptContainer
}
:if ([:len $udrContainer] > 0) do={
  /container/set $udrContainer start-on-boot=no auto-restart-interval=0s
  :delay 2s
  :if ([/container/get $udrContainer running] = true) do={ /container/stop $udrContainer; :delay 12s }
  :if ([/container/get $udrContainer running] = true) do={ :error "UDR container did not stop; remaining objects were retained" }
  /container/remove $udrContainer
}
:if ([:len [/ip/firewall/nat/find where comment=$natComment]] > 0) do={ /ip/firewall/nat/remove [find where comment=$natComment] }
/container/envs/remove [find where list=$ptEnvList]
/container/envs/remove [find where list=$udrEnvList]
:if ([:len [/interface/bridge/port/find where comment=$owner]] > 0) do={ /interface/bridge/port/remove [find where comment=$owner] }
:if ([:len [/interface/veth/find where name=$ptVethName and comment=$owner]] > 0) do={ /interface/veth/remove [find where name=$ptVethName and comment=$owner] }
:if ([:len [/interface/veth/find where name=$udrVethName and comment=$owner]] > 0) do={ /interface/veth/remove [find where name=$udrVethName and comment=$owner] }
:if ([:len [/ip/address/find where comment=$owner]] > 0) do={ /ip/address/remove [find where comment=$owner] }
:if ([:len [/interface/bridge/find where name=$bridgeName and comment=$owner]] > 0) do={ /interface/bridge/remove [find where name=$bridgeName and comment=$owner] }
:if ([:len [/container/find where layer-dir=$layerDir]] = 0) do={
  :if ([:len [/file/find where name=$ptRootDir]] > 0) do={ /file/remove [find where name=$ptRootDir] }
  :if ([:len [/file/find where name=$udrRootDir]] > 0) do={ /file/remove [find where name=$udrRootDir] }
  :if ([:len [/file/find where name=$layerDir]] > 0) do={ /file/remove [find where name=$layerDir] }
} else={ :put "Layer directory retained because another container references it." }
:put "udpredund exit objects removed. The uploaded image tar was retained."
