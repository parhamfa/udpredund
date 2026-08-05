# udpredund v0.1.0-beta.1 - RouterOS entry installer
# Edit only this variable block before importing. Use a unique /24 prefix.
:local imageFile "udpredund-pingtunnel-v0.1.0-beta.1-routeros-amd64.tar"
:local exitPublicAddress "203.0.113.10"
:local pingTunnelTarget "10.254.242.3"
:local pingTunnelKey "CHANGE_ME"
:local wireGuardPeerComment "CHANGE_ME"
:local entryPrefix "10.254.241"
:local storageRoot "udpredund"

# Tested starting profile, not a universal optimum.
:local copies 2
:local maxDuplicateSize 300
:local copyGap "10ms"

:local owner "udpredund:v0.1-entry"
:local bridgeName "udrbe-br"
:local vethName "udrbe-veth"
:local envList "udrbe-env"
:local containerName "udrbe-carrier"
:local natComment "udpredund:v0.1-entry-icmp-srcnat"
:local entryGatewayCIDR ($entryPrefix . ".1/24")
:local entryContainerCIDR ($entryPrefix . ".2/24")
:local entryContainerIP ($entryPrefix . ".2")
:local entrySubnet ($entryPrefix . ".0/24")
:local udrListenPort 45111
:local ptListenPort 45211
:local exitUdrPort 46111
:local rootDir ($storageRoot . "/entry-root")
:local layerDir ($storageRoot . "/entry-layers")

:put "udpredund entry: running read-only preflight"
:if ([/system/device-mode/get container] != true) do={ :error "RouterOS container device-mode is disabled" }
:if ($exitPublicAddress = "203.0.113.10") do={ :error "set exitPublicAddress in the variable block" }
:if ([:len $pingTunnelTarget] = 0) do={ :error "set pingTunnelTarget to the exit UDR address, or 127.0.0.1 for Ubuntu" }
:if ($pingTunnelKey = "CHANGE_ME") do={ :error "set pingTunnelKey in the variable block" }
:if (($pingTunnelKey ~ "^[0-9]+\$") = false) do={ :error "pingTunnelKey must be a decimal integer from 1 through 2147483647" }
:local pingTunnelKeyNumber [:tonum $pingTunnelKey]
:if (($pingTunnelKeyNumber < 1) || ($pingTunnelKeyNumber > 2147483647)) do={ :error "pingTunnelKey must be from 1 through 2147483647" }
:if ($wireGuardPeerComment = "CHANGE_ME") do={ :error "set wireGuardPeerComment to one existing peer comment" }
:if ([:len [/file/find where name=$imageFile]] != 1) do={ :error ("image file not found or ambiguous: " . $imageFile) }
:if ([:len [/interface/bridge/find where name=$bridgeName]] > 0) do={ :error ("object collision: " . $bridgeName) }
:if ([:len [/interface/veth/find where name=$vethName]] > 0) do={ :error ("object collision: " . $vethName) }
:if ([:len [/container/find where name=$containerName]] > 0) do={ :error ("object collision: " . $containerName) }
:if ([:len [/container/envs/find where list=$envList]] > 0) do={ :error ("environment-list collision: " . $envList) }
:if ([:len [/ip/firewall/nat/find where comment=$natComment]] > 0) do={ :error ("NAT-rule collision: " . $natComment) }
:if ([:len [/interface/bridge/port/find where comment=$owner]] > 0) do={ :error ("ownership-marker collision on bridge port: " . $owner) }
:if ([:len [/ip/address/find where comment=$owner]] > 0) do={ :error ("ownership-marker collision on IP address: " . $owner) }
:if ([:len [/ip/address/find where address~$entryPrefix]] > 0) do={ :error ("address collision under prefix: " . $entryPrefix) }
:if ([:len [/file/find where name=$rootDir]] > 0) do={ :error ("root-dir collision: " . $rootDir) }
:if ([:len [/file/find where name=$layerDir]] > 0) do={ :error ("layer-dir collision: " . $layerDir) }
:if ([:len [/interface/wireguard/peers/find where comment=$wireGuardPeerComment]] != 1) do={ :error "wireGuardPeerComment must identify exactly one existing peer" }

:put "udpredund entry: preflight passed; creating repository-owned objects"
/interface/bridge/add name=$bridgeName comment=$owner
/ip/address/add address=$entryGatewayCIDR interface=$bridgeName comment=$owner
/interface/veth/add name=$vethName address=$entryContainerCIDR gateway=($entryPrefix . ".1") comment=$owner
/interface/bridge/port/add bridge=$bridgeName interface=$vethName comment=$owner

/container/envs/add list=$envList key=ROLE value="pt-client"
/container/envs/add list=$envList key=PT_SERVER value=$exitPublicAddress
/container/envs/add list=$envList key=PT_TARGET value=($pingTunnelTarget . ":" . $exitUdrPort)
/container/envs/add list=$envList key=PT_KEY value=$pingTunnelKey
/container/envs/add list=$envList key=PT_LISTEN_PORT value=$ptListenPort
/container/envs/add list=$envList key=UDR_LISTEN_PORT value=$udrListenPort
/container/envs/add list=$envList key=COPIES value=$copies
/container/envs/add list=$envList key=MAX_DUPLICATE_SIZE value=$maxDuplicateSize
/container/envs/add list=$envList key=COPY_GAP value=$copyGap
/container/envs/add list=$envList key=PT_LOGLEVEL value="error"

/ip/firewall/nat/add chain=srcnat action=masquerade protocol=icmp src-address=$entrySubnet dst-address=$exitPublicAddress disabled=yes comment=$natComment

/container/add name=$containerName file=$imageFile interface=$vethName envlists=$envList root-dir=$rootDir layer-dir=$layerDir logging=no memory-high=256MiB auto-restart-interval=0s start-on-boot=no comment=$owner

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

:local entryContainer [/container/find where name=$containerName]
:if ([$waitReady $entryContainer] = false) do={ :error "container extraction did not produce an image; start-on-boot remains disabled" }
/container/start $entryContainer
:delay 3s
:if ([/container/get $entryContainer running] != true) do={ :error "entry container failed to start; inspect /log; NAT and start-on-boot remain disabled" }
/container/set $entryContainer start-on-boot=yes auto-restart-interval=10s
/ip/firewall/nat/enable [find where comment=$natComment]

:put "udpredund entry is running. No WireGuard setting was changed."
:put "Review, then run this exact endpoint command yourself:"
:put ("/interface/wireguard/peers/set [find where comment=\"" . $wireGuardPeerComment . "\"] endpoint-address=" . $entryContainerIP . " endpoint-port=" . $udrListenPort)
