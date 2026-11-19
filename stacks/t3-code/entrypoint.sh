#!/bin/sh
set -eu

T3_IMAGE_RUNTIME_DIR=/opt/t3-code/runtime/versions
T3_RUNTIME_DIR=/var/lib/t3/runtime/versions

# Link runtimes bundled in the image into the persistent T3 home, where the t3
# npm launcher looks for them, so the server starts without downloading.
link_t3_runtimes() {
    for link in "$T3_RUNTIME_DIR"/*; do
        if [ -L "$link" ] && [ ! -e "$link" ]; then
            rm -f "$link"
        fi
    done

    for runtime in "$T3_IMAGE_RUNTIME_DIR"/*; do
        [ -f "$runtime/.install-complete" ] || continue
        target="$T3_RUNTIME_DIR/${runtime##*/}"
        [ -f "$target/.install-complete" ] && continue
        rm -rf "$target"
        ln -s "$runtime" "$target"
    done
}

if [ "$(id -u)" -eq 0 ]; then
    install -d -m 0755 -o user -g user /home/user
    install -d -m 0700 -o user -g user \
        /var/lib/t3 \
        /home/user/.config \
        /home/user/.config/docker \
        /home/user/.config/git \
        /home/user/.npm \
        /home/user/.codex \
        /home/user/.local \
        /home/user/.local/share \
        /home/user/.local/share/opencode \
        /home/user/.local/state \
        /home/user/.ssh
    install -d -m 0755 -o user -g user /workspace
    install -d -m 0700 -o user -g user \
        /var/lib/t3/runtime \
        "$T3_RUNTIME_DIR"
    link_t3_runtimes
    find "$T3_RUNTIME_DIR" -mindepth 1 -maxdepth 1 \
        \( ! -user user -o ! -group user \) -exec chown -h user:user {} +

    # Repair existing home files and mounted state before dropping privileges.
    # Do not follow symlinks to files outside the home directory.
    find /home/user \( ! -user user -o ! -group user \) \
        -exec chown -h user:user {} +

    if [ -n "${GIT_USER_NAME:-}" ] \
        && ! gosu user git config --global --get user.name >/dev/null 2>&1; then
        gosu user git config --global user.name "$GIT_USER_NAME"
    fi

    if [ -n "${GIT_USER_EMAIL:-}" ] \
        && ! gosu user git config --global --get user.email >/dev/null 2>&1; then
        gosu user git config --global user.email "$GIT_USER_EMAIL"
    fi

    exec gosu user "$@"
fi

mkdir -p "$T3_RUNTIME_DIR"
link_t3_runtimes
exec "$@"
