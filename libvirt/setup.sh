#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

POOL_NAME="postgresql-lab"
NETWORK_NAME="pg-lab-net"
STORAGE_PATH="/servers/postgresql-ha-ops-lab"
NETWORK_CIDR="192.168.60.0/24"

VIRSH=(virsh -c qemu:///system)

echo "==> Preparing storage directory"

sudo mkdir -p "$STORAGE_PATH"
sudo chown root:root "$STORAGE_PATH"
sudo chmod 0755 "$STORAGE_PATH"

echo "==> Configuring SELinux context"

if ! sudo semanage fcontext -l | grep -F "$STORAGE_PATH" >/dev/null; then
    sudo semanage fcontext \
        -a \
        -e /var/lib/libvirt/images \
        "$STORAGE_PATH"
fi

sudo restorecon -RF "$STORAGE_PATH"

echo "==> Configuring libvirt storage pool"

if ! "${VIRSH[@]}" pool-info "$POOL_NAME" >/dev/null 2>&1; then
    "${VIRSH[@]}" pool-define \
        "$SCRIPT_DIR/postgresql-lab-pool.xml"
fi

if ! "${VIRSH[@]}" pool-info "$POOL_NAME" |
    grep -E '^State:[[:space:]]*running[[:space:]]*$' >/dev/null; then

    "${VIRSH[@]}" pool-start "$POOL_NAME"
fi

"${VIRSH[@]}" pool-autostart "$POOL_NAME"

echo "==> Configuring libvirt network"

if ! "${VIRSH[@]}" net-info "$NETWORK_NAME" >/dev/null 2>&1; then

    if [[ -n "$(ip -4 route show "$NETWORK_CIDR")" ]]; then
        echo "ERROR: $NETWORK_CIDR is already in use."
        exit 1
    fi

    "${VIRSH[@]}" net-define \
        "$SCRIPT_DIR/pg-lab-net.xml"
fi

if ! "${VIRSH[@]}" net-info "$NETWORK_NAME" |
    grep -E '^Active:[[:space:]]*yes[[:space:]]*$' >/dev/null; then

    "${VIRSH[@]}" net-start "$NETWORK_NAME"
fi

"${VIRSH[@]}" net-autostart "$NETWORK_NAME"

echo
echo "==> Storage pool"
"${VIRSH[@]}" pool-info "$POOL_NAME"

echo
echo "==> Network"
"${VIRSH[@]}" net-info "$NETWORK_NAME"

echo
echo "Stage 1 libvirt infrastructure is ready."
