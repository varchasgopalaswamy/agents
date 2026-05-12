#!/bin/bash
set -euo pipefail

export UV_PROJECT_ENVIRONMENT="${UV_PROJECT_ENVIRONMENT:-$HOME/.venv}"

if [ ! -x "$UV_PROJECT_ENVIRONMENT/bin/python" ]; then
    echo "Initializing Python virtual environment at $UV_PROJECT_ENVIRONMENT..."
    mkdir -p "$UV_PROJECT_ENVIRONMENT"
    uv venv --seed "$UV_PROJECT_ENVIRONMENT"
fi

if [ "${AGENTS_DISABLE_FIREWALL:-0}" != "1" ]; then
    firewall_args=()
    if [ "${AGENTS_ALLOW_HOST_NETWORK:-0}" = "1" ]; then
        firewall_args+=("--allow-host-network")
    fi
    if [ "${AGENTS_KEEP_FIREWALL_SUDO:-0}" = "1" ]; then
        firewall_args+=("--keep-sudo")
    fi
    sudo -n /usr/local/bin/init-firewall.sh "${firewall_args[@]}"
fi

exec "$@"
