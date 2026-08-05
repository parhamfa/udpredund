# udpredund v0.1.0-beta.1 - RouterOS exit installer
# Edit only this variable block before importing. Use a unique /24 prefix.
:local imageFile "udpredund-pingtunnel-v0.1.0-beta.1-routeros-amd64.tar"
:local exitPublicAddress "203.0.113.10"
:local entrySourceCIDR "198.51.100.10/32"
:local allowUnrestrictedICMP false
:local pingTunnelKey "CHANGE_ME"
:local existingWireGuardPort 51820
:local exitPrefix "10.254.242"
:local storageRoot "udpredund"

# Tested starting profile, not a universal optimum.
:local copies 2
:local maxDuplicateSize 300
:local copyGap "10ms"

:local owner "udpredund:v0.1-exit"
:local bridgeName "udrbx-br"
:local ptVethName "udrbx-pt"
:local udrVethName "udrbx-udr"
:local ptEnvList "udrbx-pt-env"
:local udrEnvList "udrbx-udr-env"
:local ptContainerName "udrbx-pt"
:local udrContainerName "udrbx-udr"
:local natComment "udpredund:v0.1-exit-icmp-dnat"
:local exitGatewayCIDR ($exitPrefix . ".1/24")
:local exitGatewayIP ($exitPrefix . ".1")
:local ptContainerCIDR ($exitPrefix . ".2/24")
:local ptContainerIP ($exitPrefix . ".2")
:local udrContainerCIDR ($exitPrefix . ".3/24")
:local udrListenPort 46111
:local ptRootDir ($storageRoot . "/exit-pt-root")
:local udrRootDir ($storageRoot . "/exit-udr-root")
:local layerDir ($storageRoot . "/exit-layers")

:put "udpredund exit: running read-only preflight"
:if ([/system/device-mode/get container] != true) do={ :error "RouterOS container device-mode is disabled" }
:if ($exitPublicAddress = "203.0.113.10") do={ :error "set exitPublicAddress in the variable block" }
:if ($pingTunnelKey = "CHANGE_ME") do={ :error "set pingTunnelKey in the variable block" }
:if (($pingTunnelKey ~ "^[0-9]+\$") = false) do={ :error "pingTunnelKey must be a decimal integer from 1 through 2147483647" }
:local pingTunnelKeyNumber [:tonum $pingTunnelKey]
:if (($pingTunnelKeyNumber < 1) || ($pingTunnelKeyNumber > 2147483647)) do={ :error "pingTunnelKey must be from 1 through 2147483647" }
:if (($entrySourceCIDR = "") && ($allowUnrestrictedICMP = false)) do={ :error "entrySourceCIDR is required; set allowUnrestrictedICMP=true only after explicit review" }
:if (($entrySourceCIDR = "198.51.100.10/32") && ($allowUnrestrictedICMP = false)) do={ :error "replace the example entrySourceCIDR" }
:if ([:len [/file/find where name=$imageFile]] != 1) do={ :error ("image file not found or ambiguous: " . $imageFile) }
:if ([:len [/interface/bridge/find where name=$bridgeName]] > 0) do={ :error ("object collision: " . $bridgeName) }
:if ([:len [/interface/veth/find where name=$ptVethName]] > 0) do={ :error ("object collision: " . $ptVethName) }
:if ([:len [/interface/veth/find where name=$udrVethName]] > 0) do={ :error ("object collision: " . $udrVethName) }
:if ([:len [/container/find where name=$ptContainerName]] > 0) do={ :error ("object collision: " . $ptContainerName) }
:if ([:len [/container/find where name=$udrContainerName]] > 0) do={ :error ("object collision: " . $udrContainerName) }
:if ([:len [/container/envs/find where list=$ptEnvList]] > 0) do={ :error ("environment-list collision: " . $ptEnvList) }
:if ([:len [/container/envs/find where list=$udrEnvList]] > 0) do={ :error ("environment-list collision: " . $udrEnvList) }
:if ([:len [/ip/firewall/nat/find where comment=$natComment]] > 0) do={ :error ("NAT-rule collision: " . $natComment) }
:if ([:len [/interface/bridge/port/find where comment=$owner]] > 0) do={ :error ("ownership-marker collision on bridge port: " . $owner) }
:if ([:len [/ip/address/find where comment=$owner]] > 0) do={ :error ("ownership-marker collision on IP address: " . $owner) }
:if ([:len [/ip/address/find where address~$exitPrefix]] > 0) do={ :error ("address collision under prefix: " . $exitPrefix) }
:if ([:len [/file/find where name=$ptRootDir]] > 0) do={ :error ("root-dir collision: " . $ptRootDir) }
:if ([:len [/file/find where name=$udrRootDir]] > 0) do={ :error ("root-dir collision: " . $udrRootDir) }
:if ([:len [/file/find where name=$layerDir]] > 0) do={ :error ("layer-dir collision: " . $layerDir) }

:put "udpredund exit: preflight passed; creating repository-owned objects"
/interface/bridge/add name=$bridgeName comment=$owner
/ip/address/add address=$exitGatewayCIDR interface=$bridgeName comment=$owner
/interface/veth/add name=$ptVethName address=$ptContainerCIDR gateway=$exitGatewayIP comment=$owner
/interface/veth/add name=$udrVethName address=$udrContainerCIDR gateway=$exitGatewayIP comment=$owner
/interface/bridge/port/add bridge=$bridgeName interface=$ptVethName comment=$owner
/interface/bridge/port/add bridge=$bridgeName interface=$udrVethName comment=$owner

/container/envs/add list=$ptEnvList key=ROLE value="pt-server"
/container/envs/add list=$ptEnvList key=PT_KEY value=$pingTunnelKey
/container/envs/add list=$ptEnvList key=PT_LOGLEVEL value="error"

/container/envs/add list=$udrEnvList key=ROLE value="udr-server"
/container/envs/add list=$udrEnvList key=UDR_LISTEN_PORT value=$udrListenPort
/container/envs/add list=$udrEnvList key=UDR_NEXT value=($exitGatewayIP . ":" . $existingWireGuardPort)
/container/envs/add list=$udrEnvList key=COPIES value=$copies
/container/envs/add list=$udrEnvList key=MAX_DUPLICATE_SIZE value=$maxDuplicateSize
/container/envs/add list=$udrEnvList key=COPY_GAP value=$copyGap

:if ($allowUnrestrictedICMP = true) do={
  /ip/firewall/nat/add chain=dstnat action=dst-nat protocol=icmp dst-address=$exitPublicAddress to-addresses=$ptContainerIP disabled=yes comment=$natComment
} else={
  /ip/firewall/nat/add chain=dstnat action=dst-nat protocol=icmp dst-address=$exitPublicAddress src-address=$entrySourceCIDR to-addresses=$ptContainerIP disabled=yes comment=$natComment
}

/container/add name=$ptContainerName file=$imageFile interface=$ptVethName envlists=$ptEnvList root-dir=$ptRootDir layer-dir=$layerDir logging=no memory-high=256MiB auto-restart-interval=0s start-on-boot=no comment=$owner

:local waitReady do={
  :local id $1
  :local attempt 0
  :while ($attempt < 180) do={
    :local imageId [/container/get $id image-id]
    :if ([:len $imageId] > 0) do={ :return true }
    :delay 1s
    :set attempt ($attempt + 1)
  }
  :return false
}

:local waitRunning do={
  :local id $1
  :local attempt 0
  :while ($attempt < 15) do={
    :if ([/container/get $id running] = true) do={ :return true }
    :delay 1s
    :set attempt ($attempt + 1)
  }
  :return false
}

:local ptContainer [/container/find where name=$ptContainerName]
:if ([$waitReady $ptContainer] = false) do={ :error "PingTunnel container extraction did not produce an image; NAT and start-on-boot remain disabled" }
/container/add name=$udrContainerName file=$imageFile interface=$udrVethName envlists=$udrEnvList root-dir=$udrRootDir layer-dir=$layerDir logging=no memory-high=128MiB auto-restart-interval=0s start-on-boot=no comment=$owner
:local udrContainer [/container/find where name=$udrContainerName]
:if ([$waitReady $udrContainer] = false) do={ :error "UDR container extraction did not produce an image; NAT and start-on-boot remain disabled" }

/container/start $ptContainer
/container/start $udrContainer
:if ([$waitRunning $ptContainer] = false) do={ :error "PingTunnel container failed to start; inspect /log; NAT and start-on-boot remain disabled" }
:if ([$waitRunning $udrContainer] = false) do={ :error "UDR container failed to start; inspect /log; NAT and start-on-boot remain disabled" }
/container/set $ptContainer start-on-boot=yes auto-restart-interval=10s
/container/set $udrContainer start-on-boot=yes auto-restart-interval=10s
/ip/firewall/nat/enable [find where comment=$natComment]

:put "udpredund exit is running. No WireGuard setting, route, or existing rule was changed."
:put ("Configure the entry PT_TARGET as " . $exitPrefix . ".3:" . $udrListenPort)
