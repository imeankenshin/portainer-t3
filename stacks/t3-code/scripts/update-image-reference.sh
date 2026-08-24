#!/bin/sh
set -eu

IMAGE_REF="${1:?usage: update-image-reference.sh IMAGE@sha256:DIGEST [COMPOSE_FILE]}"
COMPOSE_FILE="${2:-stacks/t3-code/compose.yml}"

case "$IMAGE_REF" in
    ghcr.io/*@sha256:*) ;;
    *)
        printf '%s\n' "invalid GHCR image reference: $IMAGE_REF" >&2
        exit 1
        ;;
esac

DIGEST="${IMAGE_REF##*@sha256:}"
case "$DIGEST" in
    *[!0-9a-f]*|'')
        printf '%s\n' "invalid sha256 digest: $DIGEST" >&2
        exit 1
        ;;
esac

if [ "${#DIGEST}" -ne 64 ]; then
    printf '%s\n' "invalid sha256 digest length: ${#DIGEST}" >&2
    exit 1
fi

if [ ! -f "$COMPOSE_FILE" ]; then
    printf '%s\n' "compose file not found: $COMPOSE_FILE" >&2
    exit 1
fi

MATCH_COUNT="$(grep -c 'T3_CODE_IMAGE:-ghcr.io/' "$COMPOSE_FILE" || true)"
if [ "$MATCH_COUNT" -ne 1 ]; then
    printf '%s\n' "expected one T3_CODE_IMAGE fallback, found $MATCH_COUNT" >&2
    exit 1
fi

TMP_FILE="${COMPOSE_FILE}.tmp"
trap 'rm -f "$TMP_FILE"' EXIT HUP INT TERM

sed "s|T3_CODE_IMAGE:-ghcr.io/[^}]*|T3_CODE_IMAGE:-${IMAGE_REF}|" \
    "$COMPOSE_FILE" > "$TMP_FILE"

if ! grep -Fq "T3_CODE_IMAGE:-${IMAGE_REF}" "$TMP_FILE"; then
    printf '%s\n' 'failed to update image reference' >&2
    exit 1
fi

mv "$TMP_FILE" "$COMPOSE_FILE"
trap - EXIT HUP INT TERM
