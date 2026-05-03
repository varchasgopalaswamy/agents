#!/bin/bash
# start-agents.sh — launch the agents container with podman or docker.
#
# Install:
#   cp start-agents.sh ~/.local/bin/start-agents
#   chmod +x ~/.local/bin/start-agents
#
# Usage:
#   start-agents [IMAGE] [EXTRA_ARGS...]
#
#   IMAGE        Container image to run (default: ghcr.io/varchasgopalaswamy/agents:latest)
#   EXTRA_ARGS   Any additional arguments forwarded to podman/docker run
#
# Environment variables honored at launch time (passed into the container):
#   ANTHROPIC_API_KEY, CLAUDE_API_KEY
#   GOOGLE_API_KEY, GEMINI_API_KEY
#   OPENAI_API_KEY
#   GITHUB_TOKEN, GH_TOKEN
#   TZ  (defaults to the host timezone if /etc/localtime is available)

set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve container runtime
# ---------------------------------------------------------------------------
if command -v podman &>/dev/null; then
    RUNTIME=podman
elif command -v docker &>/dev/null; then
    RUNTIME=docker
else
    echo "ERROR: neither podman nor docker found on PATH" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Image
# ---------------------------------------------------------------------------
IMAGE="${1:-ghcr.io/varchasgopalaswamy/agents:latest}"
# If the first argument looks like an option (starts with -) treat it as an
# extra arg and keep the default image.
if [[ "$IMAGE" == -* ]]; then
    IMAGE="ghcr.io/varchasgopalaswamy/agents:latest"
else
    shift || true   # consume the IMAGE argument
fi

# ---------------------------------------------------------------------------
# Timezone
# ---------------------------------------------------------------------------
if [[ -z "${TZ:-}" ]] && [[ -f /etc/localtime ]]; then
    TZ=$(readlink -f /etc/localtime | sed 's|.*zoneinfo/||')
fi

# ---------------------------------------------------------------------------
# Persistent directories on the host
# ---------------------------------------------------------------------------
CLAUDE_DIR="${$HOME}/.claude"
CLAUDE_JSON="${$HOME}/.claude.json"
GEMINI_DIR="${HOME}/.gemini"
CODEX_DIR="${HOME}/.codex"
VENV_DIR="${HOME}/.agents_venv"
UV_CACHE_DIR="${HOME}/.cache/uv"
mkdir -p ${CLAUDE_DIR} ${GEMINI_DIR} ${CODEX_DIR} ${VENV_DIR}
touch ${CLAUDE_JSON}

# ---------------------------------------------------------------------------
# Build volume mounts
# ---------------------------------------------------------------------------
MOUNTS=(
    # Current directory as the workspace inside the container
    "--volume=$(pwd):/workspace:z"
    "--volume=${CLAUDE_DIR}:/home/agent/.claude:z"
    "--volume=${GEMINI_DIR}:/home/agent/.gemini:z"
    "--volume=${CODEX_DIR}:/home/agent/.codex:z"
    "--volume=${CLAUDE_JSON}:/home/agent/.claude.json:z"
    "--volume=${VENV_DIR}:/home/agent/.venv:z"
    "--volume=${UV_CACHE_DIR}:/home/agent/.cache/uv:z"
)

# ---------------------------------------------------------------------------
# Environment variables forwarded into the container
# ---------------------------------------------------------------------------
ENV_VARS=()

forward_env() {
    local var="$1"
    if [[ -n "${!var:-}" ]]; then
        ENV_VARS+=("--env=${var}=${!var}")
    fi
}

forward_env ANTHROPIC_API_KEY
forward_env CLAUDE_API_KEY
forward_env GOOGLE_API_KEY
forward_env GEMINI_API_KEY
forward_env OPENAI_API_KEY
forward_env TZ

# ---------------------------------------------------------------------------
# Launch
# ---------------------------------------------------------------------------
echo "Starting agents container with ${RUNTIME}..."
echo "  Image    : ${IMAGE}"
echo "  Workspace: $(pwd)"

exec "$RUNTIME" run \
    --rm \
    --interactive \
    --tty \
    # NET_ADMIN and NET_RAW are required by init-firewall.sh, which uses
    # iptables/ipset to restrict outbound traffic to an allowlist of domains.
    --cap-add=NET_ADMIN \
    --cap-add=NET_RAW \
    "${MOUNTS[@]}" \
    "${ENV_VARS[@]}" \
    "$@" \
    "$IMAGE"
