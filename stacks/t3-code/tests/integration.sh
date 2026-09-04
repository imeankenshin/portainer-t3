#!/usr/bin/env bash
set -euo pipefail

IMAGE_REF="${1:?usage: integration.sh IMAGE_REF}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DIND_IMAGE="docker:29.7.2-dind@sha256:ab772b0eaf0b01e5843f6574e50ccdfc34a7bdcb82bbf2decafde54a0ee884a9"
RUN_ID="${GITHUB_RUN_ID:-$$}"
PREFIX="t3-code-test-${RUN_ID}"
NETWORK="${PREFIX}-network"
DIND_CONTAINER="${PREFIX}-dind"
T3_CONTAINER="${PREFIX}-server"
CA_VOLUME="${PREFIX}-ca"
CLIENT_VOLUME="${PREFIX}-client"
NPM_CACHE_VOLUME="${PREFIX}-npm-cache"
WORKSPACE="$(mktemp -d)"

cleanup() {
    local exit_code=$?
    docker rm --force "$T3_CONTAINER" >/dev/null 2>&1 || true
    docker rm --force "$DIND_CONTAINER" >/dev/null 2>&1 || true
    docker network rm "$NETWORK" >/dev/null 2>&1 || true
    docker volume rm "$CA_VOLUME" "$CLIENT_VOLUME" "$NPM_CACHE_VOLUME" >/dev/null 2>&1 || true
    docker run --rm \
        --entrypoint chown \
        --volume "$WORKSPACE:/workspace" \
        "$IMAGE_REF" \
        -R "$(id -u):$(id -g)" /workspace \
        >/dev/null 2>&1 || true
    rm -rf "$WORKSPACE" || true
    return "$exit_code"
}
trap cleanup EXIT

cp -R "$SCRIPT_DIR/fixtures/compose-bind" "$WORKSPACE/project"

docker network create "$NETWORK" >/dev/null
docker volume create "$CA_VOLUME" >/dev/null
docker volume create "$CLIENT_VOLUME" >/dev/null
docker volume create "$NPM_CACHE_VOLUME" >/dev/null

docker run --detach \
    --name "$DIND_CONTAINER" \
    --network "$NETWORK" \
    --network-alias docker \
    --privileged \
    --env DOCKER_TLS_CERTDIR=/certs \
    --volume "$CA_VOLUME:/certs/ca" \
    --volume "$CLIENT_VOLUME:/certs/client" \
    --volume "$WORKSPACE:/workspace" \
    "$DIND_IMAGE" \
    --storage-driver=overlay2 \
    --bip=10.70.0.1/24 \
    --default-address-pool=base=10.70.128.0/17,size=24 \
    --dns=1.1.1.1 \
    --log-driver=local \
    >/dev/null

ready=false
for _ in $(seq 1 60); do
    if docker exec "$DIND_CONTAINER" docker \
        --host=tcp://localhost:2376 \
        --tlsverify \
        --tlscacert=/certs/client/ca.pem \
        --tlscert=/certs/client/cert.pem \
        --tlskey=/certs/client/key.pem \
        info --format '{{.Driver}}' 2>/dev/null \
        | grep -qx overlay2; then
        ready=true
        break
    fi
    sleep 2
done

if [ "$ready" != true ]; then
    docker logs "$DIND_CONTAINER"
    printf '%s\n' 'DinD did not become healthy' >&2
    exit 1
fi

docker run --detach \
    --name "$T3_CONTAINER" \
    --network "$NETWORK" \
    --env DOCKER_HOST=tcp://docker:2376 \
    --env DOCKER_TLS_VERIFY=1 \
    --env DOCKER_CERT_PATH=/certs/client \
    --volume "$CLIENT_VOLUME:/certs/client:ro" \
    --volume "$NPM_CACHE_VOLUME:/home/node/.npm" \
    --volume "$WORKSPACE:/workspace" \
    "$IMAGE_REF" \
    >/dev/null

server_ready=false
for _ in $(seq 1 30); do
    if docker exec "$T3_CONTAINER" node -e \
        "const s=require('net').connect(3773,'127.0.0.1');s.on('connect',()=>{s.end();process.exit(0)});s.on('error',()=>process.exit(1))" \
        >/dev/null 2>&1; then
        server_ready=true
        break
    fi
    sleep 2
done

if [ "$server_ready" != true ]; then
    docker logs "$T3_CONTAINER"
    printf '%s\n' 'T3 Code server did not become healthy' >&2
    exit 1
fi

docker rm --force "$T3_CONTAINER" >/dev/null

docker run --rm \
    --entrypoint sh \
    --volume "$NPM_CACHE_VOLUME:/home/node/.npm" \
    "$IMAGE_REF" \
    -ec 'mkdir -p /home/node/.npm/_cacache/tmp && touch /home/node/.npm/_cacache/tmp/root-owned'

docker run --rm \
    --network "$NETWORK" \
    --env DOCKER_HOST=tcp://docker:2376 \
    --env DOCKER_TLS_VERIFY=1 \
    --env DOCKER_CERT_PATH=/certs/client \
    --volume "$CLIENT_VOLUME:/certs/client:ro" \
    --volume "$NPM_CACHE_VOLUME:/home/node/.npm" \
    --volume "$WORKSPACE:/workspace" \
    "$IMAGE_REF" \
    sh -ec '
        test "$(id -u)" = 1000
        t3 --version
        opencode --version
        gh --version
        docker version
        docker compose version
        docker buildx version
        test "$(stat -c %u:%g /home/node/.npm/_cacache/tmp/root-owned)" = 1000:1000
        npm cache verify
        cd /workspace/project
        docker compose up --build --abort-on-container-exit --exit-code-from bind-test
        docker compose down --volumes --remove-orphans
        test "$(cat result.txt)" = "compose integration passed"
    '
