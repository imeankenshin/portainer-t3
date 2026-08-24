#!/bin/sh

set -eu

# This hack can be removed if https://github.com/docker-library/docker/pull/444 gets merged.

# Remove docker pidfile if it exists to ensure Docker can start up after a bad shutdown
pidfile="/var/run/docker.pid"
if [ -f "${pidfile}" ]
then
    rm -f "${pidfile}"
fi

# Use nftables as the backend for iptables
for command in iptables iptables-restore iptables-restore-translate iptables-save iptables-translate
do
    ln -sf /sbin/xtables-nft-multi /sbin/$command
done

# Ensure that a bridge exists with the given name
ensure_bridge_exists() {
    bridge_name="${1}"
    bridge_ip_range="${2}"

    # Check if the bridge already exists
    if ip link show "${bridge_name}" >/dev/null 2>&1
    then
        echo "Bridge '${bridge_name}' already exists. Skipping creation."
        ip addr show "${bridge_name}"
        return
    fi

    echo "Bridge '${bridge_name}' does not exist. Creating..."
    ip link add "${bridge_name}" type bridge
    ip addr add "${bridge_ip_range}" dev "${bridge_name}"
    ip link set "${bridge_name}" up

    echo "Bridge '${bridge_name}' is now up with IP range '${bridge_ip_range}'."
    ip addr show "${bridge_name}"
}

# The nested daemon writes legacy rules, while Umbrel's outer daemon filters with nftables.
ensure_managed_subnet_forwarding() {
    managed_subnet="${1}"

    iptables -C DOCKER-USER -s "${managed_subnet}" -j ACCEPT 2>/dev/null ||
        iptables -I DOCKER-USER 1 -s "${managed_subnet}" -j ACCEPT
    iptables -C DOCKER-USER -d "${managed_subnet}" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT 2>/dev/null ||
        iptables -I DOCKER-USER 1 -d "${managed_subnet}" -m conntrack --ctstate RELATED,ESTABLISHED -j ACCEPT
}

if [ -n "${DOCKER_ENSURE_BRIDGE:-}" ]
then
    bridge="${DOCKER_ENSURE_BRIDGE%%:*}"
    ip_range="${DOCKER_ENSURE_BRIDGE#*:}"
    ensure_bridge_exists "${bridge}" "${ip_range}"
fi

if [ -n "${PORTAINER_MANAGED_SUBNET:-}" ]
then
    ensure_managed_subnet_forwarding "${PORTAINER_MANAGED_SUBNET}"
fi

exec dockerd-entrypoint.sh "$@"
