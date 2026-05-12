#!/bin/bash
set -euo pipefail

AGENT_USER="${AGENT_USER:-agent}"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: entrypoint must start as root so it can initialize the firewall and drop privileges" >&2
    exit 1
fi

if ! id "$AGENT_USER" >/dev/null 2>&1; then
    echo "ERROR: user does not exist: $AGENT_USER" >&2
    exit 1
fi

if [ "$(id -u "$AGENT_USER")" -eq 0 ]; then
    echo "ERROR: AGENT_USER must not be root" >&2
    exit 1
fi

AGENT_HOME="$(getent passwd "$AGENT_USER" | cut -d: -f6)"
if [ -z "$AGENT_HOME" ]; then
    echo "ERROR: failed to determine home directory for $AGENT_USER" >&2
    exit 1
fi

export HOME="$AGENT_HOME"
export USER="$AGENT_USER"
export LOGNAME="$AGENT_USER"
export UV_PROJECT_ENVIRONMENT="${UV_PROJECT_ENVIRONMENT:-$HOME/.venv}"
export UV_CACHE_DIR="${UV_CACHE_DIR:-$HOME/.cache/uv}"
export UV_LINK_MODE="${UV_LINK_MODE:-copy}"

run_as_agent() {
    gosu "$AGENT_USER" "$@"
}

dir_has_entries() {
    local first_entry
    first_entry=$(find "$1" -mindepth 1 -maxdepth 1 -print -quit)
    [ -n "$first_entry" ]
}

validate_recreate_target() {
    local target="$1"
    if [ ! -e "$target" ]; then
        return
    fi
    if [ ! -d "$target" ]; then
        echo "ERROR: refusing to recreate non-directory UV_PROJECT_ENVIRONMENT=$target" >&2
        exit 1
    fi
    if [ -f "$target/pyvenv.cfg" ]; then
        return
    fi
    if dir_has_entries "$target"; then
        echo "ERROR: refusing to delete non-empty non-venv UV_PROJECT_ENVIRONMENT=$target" >&2
        exit 1
    fi
}

case "$UV_PROJECT_ENVIRONMENT" in
    ""|"/"|"/home"|"/home/agent"|"/workspace"|"/workspace/"*)
        echo "ERROR: refusing unsafe UV_PROJECT_ENVIRONMENT=$UV_PROJECT_ENVIRONMENT" >&2
        exit 1
        ;;
esac

case "$UV_CACHE_DIR" in
    ""|"/"|"/home"|"/home/agent"|"/workspace"|"/workspace/"*)
        echo "ERROR: refusing unsafe UV_CACHE_DIR=$UV_CACHE_DIR" >&2
        exit 1
        ;;
esac

run_as_agent mkdir -p "$UV_CACHE_DIR"

if [ "${AGENTS_RECREATE_VENV:-0}" = "1" ] && [ -e "$UV_PROJECT_ENVIRONMENT" ]; then
    validate_recreate_target "$UV_PROJECT_ENVIRONMENT"
    echo "Recreating Python virtual environment at $UV_PROJECT_ENVIRONMENT..."
    run_as_agent rm -rf -- "$UV_PROJECT_ENVIRONMENT"
fi

if [ ! -x "$UV_PROJECT_ENVIRONMENT/bin/python" ]; then
    venv_args=(--seed)
    if [ -n "${AGENTS_PYTHON_VERSION:-}" ]; then
        venv_args+=(--python "$AGENTS_PYTHON_VERSION")
        echo "Initializing Python $AGENTS_PYTHON_VERSION virtual environment at $UV_PROJECT_ENVIRONMENT..."
    else
        echo "Initializing Python virtual environment at $UV_PROJECT_ENVIRONMENT..."
    fi
    run_as_agent mkdir -p "$UV_PROJECT_ENVIRONMENT"
    run_as_agent uv venv "${venv_args[@]}" "$UV_PROJECT_ENVIRONMENT"
elif [ -n "${AGENTS_PYTHON_VERSION:-}" ]; then
    actual_python_version=$(run_as_agent "$UV_PROJECT_ENVIRONMENT/bin/python" -c 'import sys; print(".".join(map(str, sys.version_info[:3])))')
    if [[ "$AGENTS_PYTHON_VERSION" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]] && [[ "$actual_python_version" != "$AGENTS_PYTHON_VERSION"* ]]; then
        echo "WARNING: existing virtual environment uses Python $actual_python_version, not requested $AGENTS_PYTHON_VERSION."
        echo "         Start with --recreate-venv or use a different --venv-dir to initialize a new one."
    fi
fi

if [ "${AGENTS_ENABLE_SUDO_PASSWORD:-0}" = "1" ]; then
    /usr/local/bin/configure-sudo-password.sh
fi

if [ "${AGENTS_DISABLE_FIREWALL:-0}" != "1" ]; then
    firewall_args=()
    if [ "${AGENTS_ALLOW_HOST_NETWORK:-0}" = "1" ]; then
        firewall_args+=("--allow-host-network")
    fi
    /usr/local/bin/init-firewall.sh "${firewall_args[@]}"
fi

/usr/local/bin/revoke-bootstrap-sudo.sh >/dev/null 2>&1 || true

exec gosu "$AGENT_USER" "$@"
