#!/bin/bash
set -euo pipefail

T3_IMAGE_RUNTIME_DIR=/opt/t3-code/runtime/versions
T3_RUNTIME_DIR=/var/lib/t3/runtime/versions
DOCKER_SOCKET=/var/run/docker.sock

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

log() {
    printf 't3-code-entrypoint: %s\n' "$*" >&2
}

# Wait until a child process has exited and return its exit status. A trapped
# signal interrupts `wait`, so keep waiting while the process still exists.
wait_for_exit() {
    local pid="$1" status=0
    while kill -0 "$pid" 2>/dev/null; do
        status=0
        wait "$pid" || status=$?
    done
    return "$status"
}

# Use the same iptables backend selection as the official docker:dind image:
# keep legacy iptables when the kernel already has legacy rules, use nftables
# otherwise, and fall back to legacy when nftables is unavailable.
select_iptables() {
    local backend=nft
    if [ -n "${DOCKER_IPTABLES_LEGACY+x}" ]; then
        [ -n "$DOCKER_IPTABLES_LEGACY" ] && backend=legacy
    else
        local tables
        for tables in /proc/net/ip_tables_names /proc/net/ip6_tables_names /proc/net/arp_tables_names; do
            if [ -r "$tables" ] && [ -n "$(cat "$tables")" ]; then
                backend=legacy
                break
            fi
        done
        if [ "$backend" = nft ] && ! iptables-nft -nL >/dev/null 2>&1 \
            && iptables-legacy -nL >/dev/null 2>&1; then
            backend=legacy
        fi
    fi
    update-alternatives --quiet --set iptables "/usr/sbin/iptables-$backend"
    update-alternatives --quiet --set ip6tables "/usr/sbin/ip6tables-$backend"
    log "using $(iptables --version)"
}

stop_dockerd() {
    local status=0
    if [ -n "${dockerd_pid:-}" ] && kill -0 "$dockerd_pid" 2>/dev/null; then
        kill -TERM "$dockerd_pid" 2>/dev/null || :
        wait_for_exit "$dockerd_pid" || status=$?
        log "dockerd stopped with status $status"
    fi
}

start_dockerd() {
    # A restarted container keeps /run, so remove the PID file of a daemon that
    # was stopped uncleanly; otherwise dockerd refuses to start.
    find /run /var/run -maxdepth 1 -iname 'docker*.pid' -delete 2>/dev/null || :
    select_iptables

    # The dind wrapper from the docker:dind image enables cgroup v2 nesting and
    # shared mount propagation before it executes dockerd.
    # shellcheck disable=SC2086 # DOCKERD_ARGS is a space-separated flag list.
    /usr/local/bin/dind dockerd \
        --host="unix://$DOCKER_SOCKET" \
        --group=docker \
        ${DOCKERD_ARGS:-} &
    dockerd_pid=$!

    local deadline=$((SECONDS + ${DOCKERD_START_TIMEOUT:-60}))
    until curl --fail --silent --output /dev/null \
        --unix-socket "$DOCKER_SOCKET" http://localhost/_ping; do
        if [ -n "$stop_signal" ]; then
            stop_dockerd
            exit 143
        fi
        if ! kill -0 "$dockerd_pid" 2>/dev/null; then
            local status=0
            wait "$dockerd_pid" || status=$?
            log "dockerd exited during startup with status $status"
            exit 1
        fi
        if [ "$SECONDS" -ge "$deadline" ]; then
            log "dockerd did not become ready within ${DOCKERD_START_TIMEOUT:-60}s"
            stop_dockerd
            exit 1
        fi
        sleep 1
    done
    log "dockerd is ready on $DOCKER_SOCKET"
}

# shellcheck disable=SC2317 # Invoked by the traps in run_with_dockerd.
forward_signal() {
    stop_signal="$1"
    if [ -n "$app_pid" ]; then
        kill -s "$1" "$app_pid" 2>/dev/null || :
    fi
}

# Run dockerd and the command side by side. On a stop signal, stop the command
# first, then stop dockerd so that it can shut down its containers cleanly.
# If dockerd exits on its own, stop the command so the restart policy can
# recreate both.
run_with_dockerd() {
    stop_signal=
    app_pid=
    dockerd_pid=
    trap 'forward_signal TERM' TERM
    trap 'forward_signal INT' INT
    trap 'forward_signal HUP' HUP

    start_dockerd

    # A background command reads /dev/null unless stdin is redirected
    # explicitly; keep the container's stdin for interactive commands.
    gosu user "$@" <&0 &
    app_pid=$!

    local exited_pid status
    while :; do
        exited_pid=
        status=0
        wait -n -p exited_pid "$app_pid" "$dockerd_pid" || status=$?
        [ -n "${exited_pid:-}" ] && break
    done

    if [ "$exited_pid" = "$app_pid" ]; then
        stop_dockerd
        exit "$status"
    fi

    log "dockerd exited unexpectedly with status $status; stopping $1"
    kill -TERM "$app_pid" 2>/dev/null || :
    wait_for_exit "$app_pid" || :
    exit 1
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
        /home/user/.claude \
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

    # Repair existing home files and mounted state before dropping privileges.
    # The T3 state volume can hold root-owned files from releases that ran T3
    # as root, such as tools/cloudflared, which then block relay client updates.
    # Do not follow symlinks, such as the runtime links into /opt/t3-code.
    find /home/user /var/lib/t3 \( ! -user user -o ! -group user \) \
        -exec chown -h user:user {} +

    if [ -n "${GIT_USER_NAME:-}" ] \
        && ! gosu user git config --global --get user.name >/dev/null 2>&1; then
        gosu user git config --global user.name "$GIT_USER_NAME"
    fi

    if [ -n "${GIT_USER_EMAIL:-}" ] \
        && ! gosu user git config --global --get user.email >/dev/null 2>&1; then
        gosu user git config --global user.email "$GIT_USER_EMAIL"
    fi

    if [ "${DOCKERD_ENABLED:-0}" = 1 ]; then
        run_with_dockerd "$@"
    fi

    exec gosu user "$@"
fi

if [ "${DOCKERD_ENABLED:-0}" = 1 ]; then
    log "DOCKERD_ENABLED requires starting the container as root; dockerd is not started"
fi

mkdir -p "$T3_RUNTIME_DIR"
link_t3_runtimes
exec "$@"
