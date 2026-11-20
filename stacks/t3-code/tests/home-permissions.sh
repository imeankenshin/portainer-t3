#!/usr/bin/env bash
set -euo pipefail

IMAGE_REF="${1:?usage: home-permissions.sh IMAGE_REF}"

docker run --rm \
    --volume /home/user/.codex \
    --volume /home/user/.claude \
    --volume /home/user/.ssh \
    --entrypoint sh \
    "$IMAGE_REF" \
    -ec '
        # Reproduce existing root-owned home directories and files.
        mkdir -p /home/user/.local/share /home/user/.codex /home/user/.claude /home/user/.ssh
        printf "existing data\n" > /home/user/legacy-file
        touch /home/user/.codex/legacy-file /home/user/.claude/legacy-file /home/user/.ssh/legacy-file
        chown root:root /home/user /home/user/.local /home/user/.local/share /home/user/.claude \
            /home/user/legacy-file /home/user/.codex/legacy-file /home/user/.claude/legacy-file \
            /home/user/.ssh/legacy-file
        chmod 0700 /home/user/.local /home/user/.local/share
        chmod 0600 /home/user/legacy-file /home/user/.codex/legacy-file /home/user/.claude/legacy-file \
            /home/user/.ssh/legacy-file
        touch /tmp/outside-home
        ln -s /tmp/outside-home /home/user/outside-link

        exec /usr/local/bin/t3-code-entrypoint sh -ec '\''
            test "$(id -u)" = 1000
            test "$(cat "$HOME/legacy-file")" = "existing data"
            for dir in "$HOME" "$HOME/.local" "$HOME/.local/share" "$HOME/.codex" "$HOME/.claude" "$HOME/.ssh"; do
                mkdir "$dir/permission-check"
                printf "writable\n" > "$dir/permission-check/file"
                mv "$dir/permission-check/file" "$dir/permission-check/renamed"
                rm "$dir/permission-check/renamed"
                rmdir "$dir/permission-check"
            done
            for file in "$HOME/legacy-file" "$HOME/.codex/legacy-file" "$HOME/.claude/legacy-file" \
                "$HOME/.ssh/legacy-file"; do
                printf "updated\n" >> "$file"
                chmod 0600 "$file"
                rm "$file"
            done
            test "$(stat -c %u /tmp/outside-home)" = 0
            printf "Home permissions passed\n"
        '\''
    '
