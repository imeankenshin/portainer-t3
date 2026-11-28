#!/usr/bin/env bash
set -euo pipefail

# Check, with the deployed compose.yml settings, that the service runs as
# `user`, that passwordless sudo works, and that `user` can use the built-in
# dockerd. A security option that blocks sudo (such as no-new-privileges), a
# service that starts as root, or a dockerd that fails to start fails the test.

IMAGE_REF="${1:?usage: compose-sudo.sh IMAGE_REF}"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
COMPOSE_FILE="$SCRIPT_DIR/../compose.yml"
PROJECT="t3-code-sudo-test-${GITHUB_RUN_ID:-$$}"
OVERRIDE_FILE="$(mktemp)"

# Let Docker allocate the test network so concurrent runs and existing networks
# cannot collide with a fixed subnet. All service settings stay as deployed.
cat > "$OVERRIDE_FILE" <<'YAML'
networks:
  default:
    ipam:
      config: !reset []
YAML

export T3_CODE_IMAGE="$IMAGE_REF"
export T3_ENVIRONMENT_NAME=sudo-test
export T3_HOST_PORT=3799
export PREVIEW_HOST_START=39000
export PREVIEW_HOST_END=39049
# Required for interpolation only; the override discards the subnet.
export STACK_SUBNET=192.0.2.0/24
export DIND_BIP=10.72.0.1/24
export DIND_ADDRESS_POOL=10.72.128.0/17
export GIT_USER_NAME="Sudo Test"
export GIT_USER_EMAIL=sudo-test@example.invalid
# The default CPU limit can exceed the CPUs of a CI runner, and Docker then
# refuses to create the container.
export CPU_LIMIT=1.0

compose() {
    docker compose --project-name "$PROJECT" \
        --file "$COMPOSE_FILE" --file "$OVERRIDE_FILE" "$@"
}

cleanup() {
    local exit_code=$?
    compose down --volumes --remove-orphans >/dev/null 2>&1 || true
    rm -f "$OVERRIDE_FILE"
    return "$exit_code"
}
trap cleanup EXIT

compose run --rm -T t3-code sh -ec '
    test "$(id -un)" = user
    test "$(id -u)" = 1000
    test "$(sudo -n id -u)" = 0
    docker info --format "{{.Driver}}" | grep -qx overlay2
'
printf 'Compose sudo passed\n'
