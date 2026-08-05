#!/usr/bin/env bash
set -Eeuo pipefail

source_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly source_root
image="${IMAGE:?set IMAGE to the image under test}"
platform="${PLATFORM:-linux/amd64}"
suffix="${GITHUB_RUN_ID:-local}-$$"
suffix="${suffix//[^a-zA-Z0-9_.-]/-}"
network="udpr-e2e-$suffix"
tool_image="udpr-e2e-tool:$suffix"
echo_name="udpr-echo-$suffix"
pt_name="udpr-pt-$suffix"
udr_name="udpr-udr-$suffix"
client_name="udpr-client-$suffix"

cleanup() {
  docker container stop --timeout 3 "$client_name" "$udr_name" "$pt_name" "$echo_name" >/dev/null 2>&1 || true
  docker container rm "$client_name" "$udr_name" "$pt_name" "$echo_name" >/dev/null 2>&1 || true
  docker network rm "$network" >/dev/null 2>&1 || true
  docker image rm "$tool_image" >/dev/null 2>&1 || true
}
trap cleanup EXIT

show_logs() {
  local name
  for name in "$pt_name" "$udr_name" "$client_name"; do
    printf '%s logs:\n' "$name" >&2
    docker logs "$name" >&2 2>&1 || true
  done
}
trap 'show_logs' ERR

docker buildx build --platform "$platform" --load -f "$source_root/container/tests/Dockerfile.tool" -t "$tool_image" "$source_root" >/dev/null
docker network create "$network" >/dev/null

docker run -d --name "$echo_name" --platform "$platform" --network "$network" "$tool_image" -mode echo -address :51820 >/dev/null
echo_ip="$(docker inspect "$echo_name" --format "{{with index .NetworkSettings.Networks \"$network\"}}{{.IPAddress}}{{end}}")"

docker run -d --name "$pt_name" --platform "$platform" --cap-add NET_RAW --network "$network" \
  -e ROLE=pt-server -e PT_KEY=1732050807 "$image" >/dev/null
pt_ip="$(docker inspect "$pt_name" --format "{{with index .NetworkSettings.Networks \"$network\"}}{{.IPAddress}}{{end}}")"

docker run -d --name "$udr_name" --platform "$platform" --network "$network" \
  -e ROLE=udr-server -e UDR_LISTEN_PORT=46111 -e UDR_NEXT="$echo_ip:51820" \
  -e COPIES=2 -e MAX_DUPLICATE_SIZE=300 -e COPY_GAP=10ms "$image" >/dev/null
udr_ip="$(docker inspect "$udr_name" --format "{{with index .NetworkSettings.Networks \"$network\"}}{{.IPAddress}}{{end}}")"

docker run -d --name "$client_name" --platform "$platform" --cap-add NET_RAW --network "$network" \
  -e ROLE=pt-client -e PT_SERVER="$pt_ip" -e PT_TARGET="$udr_ip:46111" -e PT_KEY=1732050807 \
  -e PT_LISTEN_PORT=45211 -e UDR_LISTEN_PORT=45111 \
  -e COPIES=2 -e MAX_DUPLICATE_SIZE=300 -e COPY_GAP=10ms "$image" >/dev/null
client_ip="$(docker inspect "$client_name" --format "{{with index .NetworkSettings.Networks \"$network\"}}{{.IPAddress}}{{end}}")"

sleep 2
for name in "$echo_name" "$pt_name" "$udr_name" "$client_name"; do
  [[ "$(docker inspect "$name" --format '{{.State.Running}}')" == "true" ]]
done

docker run --rm --platform "$platform" --network "$network" "$tool_image" \
  -mode probe -address "$client_ip:45111" -payload "udpredund-image-e2e" -timeout 20s

sleep 6
docker logs "$client_name" 2>&1 | grep -E 'plain_in=[1-9][0-9]* .*duplicate=[1-9][0-9]*' >/dev/null
docker logs "$udr_name" 2>&1 | grep -E 'plain_in=[1-9][0-9]* .*duplicate=[1-9][0-9]*' >/dev/null

printf 'PingTunnel plus selective-C2 image E2E passed for %s\n' "$platform"
