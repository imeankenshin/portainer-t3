#!/usr/bin/env bash
set -euo pipefail

IMAGE_REF="${1:?usage: integration.sh IMAGE_REF}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/home-permissions.sh" "$IMAGE_REF"
bash "$SCRIPT_DIR/compose-sudo.sh" "$IMAGE_REF"
bash "$SCRIPT_DIR/t3-runtime.sh" "$IMAGE_REF"
RUN_ID="${GITHUB_RUN_ID:-$$}"
PREFIX="t3-code-test-${RUN_ID}"
T3_CONTAINER="${PREFIX}-server"
DOCKER_VOLUME="${PREFIX}-docker"
NPM_CACHE_VOLUME="${PREFIX}-npm-cache"
WORKSPACE="$(mktemp -d)"
ALPINE_IMAGE="alpine:3.22@sha256:7c8cb692ae09657cbc4a3f3cbd0e8d5a2690ba38386aaaf252dbb060bf5eb2e6"
DOCKERD_ARGS="--storage-driver=overlay2 --bip=10.70.0.1/24 --default-address-pool=base=10.70.128.0/17,size=24 --dns=1.1.1.1 --log-driver=local"

cleanup() {
    local exit_code=$?
    docker rm --force --volumes "$T3_CONTAINER" >/dev/null 2>&1 || true
    docker volume rm "$DOCKER_VOLUME" "$NPM_CACHE_VOLUME" >/dev/null 2>&1 || true
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

docker volume create "$DOCKER_VOLUME" >/dev/null
docker volume create "$NPM_CACHE_VOLUME" >/dev/null

# Run T3 Code with the built-in dockerd, as compose.yml deploys it.
docker run --detach \
    --name "$T3_CONTAINER" \
    --privileged \
    --env DOCKERD_ENABLED=1 \
    --env DOCKERD_ARGS="$DOCKERD_ARGS" \
    --volume "$DOCKER_VOLUME:/var/lib/docker" \
    --volume "$NPM_CACHE_VOLUME:/home/user/.npm" \
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

docker exec --user user --env ALPINE_IMAGE="$ALPINE_IMAGE" "$T3_CONTAINER" sh -ec '
    test -S /var/run/docker.sock
    test "$(docker info --format "{{.Driver}}")" = overlay2
    test "$(docker run --rm --volume /workspace/project:/project:ro "$ALPINE_IMAGE" \
        cat /project/source.txt)" = "shared bind mount works"
'

# Stopping the container stops T3 Code first and then shuts dockerd down.
docker stop --timeout 60 "$T3_CONTAINER" >/dev/null
if ! docker logs "$T3_CONTAINER" 2>&1 | grep -q 'dockerd stopped with status 0'; then
    docker logs "$T3_CONTAINER"
    printf '%s\n' 'dockerd did not stop cleanly' >&2
    exit 1
fi
docker rm --volumes "$T3_CONTAINER" >/dev/null

docker run --rm \
    --entrypoint sh \
    --volume "$NPM_CACHE_VOLUME:/home/user/.npm" \
    "$IMAGE_REF" \
    -ec 'mkdir -p /home/user/.npm/_cacache/tmp && touch /home/user/.npm/_cacache/tmp/root-owned'

docker run --rm \
    --privileged \
    --env DOCKERD_ENABLED=1 \
    --env DOCKERD_ARGS="$DOCKERD_ARGS" \
    --volume "$DOCKER_VOLUME:/var/lib/docker" \
    --volume "$NPM_CACHE_VOLUME:/home/user/.npm" \
    --volume "$WORKSPACE:/workspace" \
    --env ALPINE_IMAGE="$ALPINE_IMAGE" \
    "$IMAGE_REF" \
    sh -ec '
        test "$(id -u)" = 1000
        test "$(id -un)" = user
        id -nG | tr " " "\n" | grep -qx docker
        test "$HOME" = /home/user
        test "$(readlink -f /home/node)" = /home/user
        . /etc/os-release
        test "$ID" = ubuntu
        test "$VERSION_ID" = 24.04
        test "$(sudo -n id -u)" = 0
        sudo -n apt-get --version >/dev/null
        node --version
        nodejs --version
        t3 --version
        opencode --version
        codex --version
        test "$(command -v claude)" = /home/user/.local/bin/claude
        claude --version
        gh --version
        docker version
        # Images pulled by the previous container persist in /var/lib/docker.
        docker image inspect "$ALPINE_IMAGE" >/dev/null
        docker compose version
        docker buildx version
        test "$(stat -c %u:%g /home/user/.npm/_cacache/tmp/root-owned)" = 1000:1000
        npm cache verify
        cd /workspace/project
        docker compose up --build --abort-on-container-exit --exit-code-from bind-test
        docker compose down --volumes --remove-orphans
        test "$(cat result.txt)" = "compose integration passed"
    '
