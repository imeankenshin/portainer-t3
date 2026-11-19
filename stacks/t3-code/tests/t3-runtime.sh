#!/usr/bin/env bash
set -euo pipefail

IMAGE_REF="${1:?usage: t3-runtime.sh IMAGE_REF}"

# The bundled runtime must start without network access, replace stale or
# incomplete runtime entries in the state volume, and stay owned by the user.
docker run --rm \
    --network none \
    --volume /var/lib/t3 \
    --entrypoint sh \
    "$IMAGE_REF" \
    -ec '
        version="$(node -p "require(\"/usr/local/lib/node_modules/t3/package.json\").version")"
        test -n "$version"
        test "$(ls /opt/t3-code/runtime/versions)" = "$version"
        test -f "/opt/t3-code/runtime/versions/$version/.install-complete"
        test ! -e /root/.t3

        mkdir -p "/var/lib/t3/runtime/versions/$version"
        touch "/var/lib/t3/runtime/versions/$version/partial-download"
        ln -s /opt/t3-code/runtime/versions/0.0.0 /var/lib/t3/runtime/versions/0.0.0
        chown -R root:root /var/lib/t3/runtime

        exec /usr/local/bin/t3-code-entrypoint sh -ec '\''
            version="$(node -p "require(\"/usr/local/lib/node_modules/t3/package.json\").version")"
            runtime="/var/lib/t3/runtime/versions/$version"
            test "$(id -u)" = 1000
            test "$(readlink "$runtime")" = "/opt/t3-code/runtime/versions/$version"
            test "$(stat -c %U "$runtime")" = user
            test "$(stat -c %U /var/lib/t3/runtime/versions)" = user
            test ! -e /var/lib/t3/runtime/versions/0.0.0
            test ! -L /var/lib/t3/runtime/versions/0.0.0
            test "t3=$(t3 --version)" = "$(sed -n "/^t3=/p" /usr/local/share/t3-code/versions)"
            t3 --version | grep -Fq "$version"
            printf "T3 runtime passed\n"
        '\''
    '
