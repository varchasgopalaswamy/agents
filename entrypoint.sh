#!/bin/bash
set -euo pipefail

export UV_PROJECT_ENVIRONMENT="${UV_PROJECT_ENVIRONMENT:-$HOME/.venv}"
export UV_CACHE_DIR="${UV_CACHE_DIR:-$HOME/.cache/uv}"
export UV_LINK_MODE="${UV_LINK_MODE:-copy}"

case "$UV_PROJECT_ENVIRONMENT" in
    ""|"/"|"/home"|"/home/agent")
        echo "ERROR: refusing unsafe UV_PROJECT_ENVIRONMENT=$UV_PROJECT_ENVIRONMENT" >&2
        exit 1
        ;;
esac

case "$UV_CACHE_DIR" in
    ""|"/"|"/home"|"/home/agent")
        echo "ERROR: refusing unsafe UV_CACHE_DIR=$UV_CACHE_DIR" >&2
        exit 1
        ;;
esac

mkdir -p "$UV_CACHE_DIR"

if [ "${AGENTS_RECREATE_VENV:-0}" = "1" ] && [ -e "$UV_PROJECT_ENVIRONMENT" ]; then
    echo "Recreating Python virtual environment at $UV_PROJECT_ENVIRONMENT..."
    rm -rf "$UV_PROJECT_ENVIRONMENT"
fi

if [ ! -x "$UV_PROJECT_ENVIRONMENT/bin/python" ]; then
    venv_args=(--seed)
    if [ -n "${AGENTS_PYTHON_VERSION:-}" ]; then
        venv_args+=(--python "$AGENTS_PYTHON_VERSION")
        echo "Initializing Python $AGENTS_PYTHON_VERSION virtual environment at $UV_PROJECT_ENVIRONMENT..."
    else
        echo "Initializing Python virtual environment at $UV_PROJECT_ENVIRONMENT..."
    fi
    mkdir -p "$UV_PROJECT_ENVIRONMENT"
    uv venv "${venv_args[@]}" "$UV_PROJECT_ENVIRONMENT"
elif [ -n "${AGENTS_PYTHON_VERSION:-}" ]; then
    actual_python_version=$("$UV_PROJECT_ENVIRONMENT/bin/python" -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')
    if [[ "$AGENTS_PYTHON_VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] && [[ "$actual_python_version" != "$AGENTS_PYTHON_VERSION"* ]]; then
        echo "WARNING: existing virtual environment uses Python $actual_python_version, not requested $AGENTS_PYTHON_VERSION."
        echo "         Start with --recreate-venv or use a different --venv-dir to initialize a new one."
    fi
fi

if [ "${AGENTS_ENABLE_SUDO_PASSWORD:-0}" = "1" ]; then
    sudo -n /usr/local/bin/configure-sudo-password.sh
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

revoke_args=()
if [ "${AGENTS_KEEP_FIREWALL_SUDO:-0}" = "1" ]; then
    revoke_args+=("--keep-firewall-sudo")
fi
sudo -n /usr/local/bin/revoke-bootstrap-sudo.sh "${revoke_args[@]}" >/dev/null 2>&1 || true
sudo -k >/dev/null 2>&1 || true

exec "$@"
