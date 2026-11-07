#!/usr/bin/env bash
set -euo pipefail

IMAGE_REF="${1:?usage: home-permissions.sh IMAGE_REF}"

docker run --rm \
    --security-opt no-new-privileges:true \
    --volume /home/node/.codex \
    --volume /home/node/.ssh \
    --entrypoint sh \
    "$IMAGE_REF" \
    -ec '
        # Reproduce existing root-owned home directories and files.
        mkdir -p /home/node/.local/share /home/node/.codex /home/node/.ssh
        printf "existing data\n" > /home/node/legacy-file
        touch /home/node/.codex/legacy-file /home/node/.ssh/legacy-file
        chown root:root /home/node /home/node/.local /home/node/.local/share \
            /home/node/legacy-file /home/node/.codex/legacy-file /home/node/.ssh/legacy-file
        chmod 0700 /home/node/.local /home/node/.local/share
        chmod 0600 /home/node/legacy-file /home/node/.codex/legacy-file /home/node/.ssh/legacy-file
        touch /tmp/outside-home
        ln -s /tmp/outside-home /home/node/outside-link

        exec /usr/local/bin/t3-code-entrypoint sh -ec '\''
            test "$(id -u)" = 1000
            test "$(cat "$HOME/legacy-file")" = "existing data"
            for dir in "$HOME" "$HOME/.local" "$HOME/.local/share" "$HOME/.codex" "$HOME/.ssh"; do
                mkdir "$dir/permission-check"
                printf "writable\n" > "$dir/permission-check/file"
                mv "$dir/permission-check/file" "$dir/permission-check/renamed"
                rm "$dir/permission-check/renamed"
                rmdir "$dir/permission-check"
            done
            for file in "$HOME/legacy-file" "$HOME/.codex/legacy-file" "$HOME/.ssh/legacy-file"; do
                printf "updated\n" >> "$file"
                chmod 0600 "$file"
                rm "$file"
            done
            test "$(stat -c %u /tmp/outside-home)" = 0
            printf "Home permissions passed\n"
        '\''
    '
