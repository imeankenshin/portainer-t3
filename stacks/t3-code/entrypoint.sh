#!/bin/sh
set -eu

if [ "$(id -u)" -eq 0 ]; then
    install -d -m 0700 -o node -g node \
        /var/lib/t3 \
        /home/node/.config \
        /home/node/.config/docker \
        /home/node/.config/git \
        /home/node/.local/share/opencode \
        /home/node/.local/state \
        /home/node/.ssh
    install -d -m 0755 -o node -g node /workspace

    if [ -n "${GIT_USER_NAME:-}" ] \
        && ! gosu node git config --global --get user.name >/dev/null 2>&1; then
        gosu node git config --global user.name "$GIT_USER_NAME"
    fi

    if [ -n "${GIT_USER_EMAIL:-}" ] \
        && ! gosu node git config --global --get user.email >/dev/null 2>&1; then
        gosu node git config --global user.email "$GIT_USER_EMAIL"
    fi

    exec gosu node "$@"
fi

exec "$@"
