#!/bin/sh
set -eu

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

exec "$@"
