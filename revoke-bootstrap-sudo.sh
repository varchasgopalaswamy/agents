#!/bin/bash
set -euo pipefail

KEEP_FIREWALL_SUDO=0

for arg in "$@"; do
    case "$arg" in
        --keep-firewall-sudo)
            KEEP_FIREWALL_SUDO=1
            ;;
        *)
            echo "ERROR: unknown revoke option: $arg" >&2
            exit 2
            ;;
    esac
done

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: revoke-bootstrap-sudo.sh must run as root" >&2
    exit 1
fi

rm -f /etc/sudoers.d/agent-sudo-bootstrap
if [ "$KEEP_FIREWALL_SUDO" != "1" ]; then
    rm -f /etc/sudoers.d/agent-firewall
fi
echo "Revoked passwordless sudo bootstrap permission"
