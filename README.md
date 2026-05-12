# agents

A containerised environment for AI coding agents (Claude, Gemini, OpenAI Codex, …).

## Quick start

### 1. Build the image (once)

```bash
docker build -t ghcr.io/varchasgopalaswamy/agents:latest .
# or
podman build -t ghcr.io/varchasgopalaswamy/agents:latest .
```

### 2. Install the launcher script

```bash
cp start-agents ~/.local/bin/start-agents
chmod +x ~/.local/bin/start-agents
```

### 3. Start the container

```bash
# From any project directory you want to work in:
cd ~/my-project
start-agents
```

The script automatically detects whether `podman` or `docker` is available and
starts the container with the following mounts and settings:

| Host path | Container path | Purpose |
|-----------|---------------|---------|
| `$PWD` | `/workspace` | Project files (read/write) |
| `~/.local/share/agents/commandhistory` | `/commandhistory` | Persistent bash history |
| `~/.claude` | `/home/agent/.claude` | Claude config / credentials |
| `~/.claude.json` | `/home/agent/.claude.json` | Claude settings file |
| `~/.gemini` | `/home/agent/.gemini` | Gemini config / credentials |
| `~/.codex` | `/home/agent/.codex` | Codex config / credentials |
| `~/.agents_venv` | `/home/agent/.venv` | Persistent Python virtual environment |
| `~/.cache/uv` | `/home/agent/.cache/uv` | Persistent uv cache |

### Environment variables

The following variables are forwarded from your shell into the container if they
are set:

- `ANTHROPIC_API_KEY` / `CLAUDE_API_KEY`
- `GOOGLE_API_KEY` / `GEMINI_API_KEY`
- `OPENAI_API_KEY`
- `GITHUB_TOKEN` / `GH_TOKEN`
- `TZ` (falls back to the host timezone automatically)
- `AGENTS_DISABLE_FIREWALL=1` skips firewall initialization
- `AGENTS_ALLOW_HOST_NETWORK=1` allows the container to reach the host gateway
- `AGENTS_KEEP_FIREWALL_SUDO=1` keeps the one-command firewall sudo rule after startup

Secrets are forwarded as environment variable names, not literal `NAME=value`
arguments, so API keys are not exposed in the local `docker run`/`podman run`
process arguments.

### Python

The image explicitly installs Python 3, `python3-venv`, `python3-pip`,
`python3-dev`, `build-essential`, and uv. On startup, the entrypoint creates a
seeded persistent virtual environment at `/home/agent/.venv` if one does not
already exist. The shell activates that environment automatically and sets:

- `UV_PROJECT_ENVIRONMENT=/home/agent/.venv`
- `UV_CACHE_DIR=/home/agent/.cache/uv`
- `UV_LINK_MODE=copy`

For Linux hosts with a non-1000 UID/GID, build the image with matching IDs so
bind-mounted workspaces remain writable:

```bash
docker build \
  --build-arg USER_UID="$(id -u)" \
  --build-arg USER_GID="$(id -g)" \
  -t ghcr.io/varchasgopalaswamy/agents:latest .
```

### Firewall and sandboxing

The container starts the firewall automatically unless
`AGENTS_DISABLE_FIREWALL=1` is set. The firewall:

- Allows GitHub ranges from `https://api.github.com/meta`
- Allows the model/package domains listed in `init-firewall.sh`, including
  Anthropic, OpenAI, Gemini/Google auth, GitHub Copilot, npm, PyPI, and VS Code
  extension update endpoints
- Drops IPv6 outbound traffic
- Blocks host gateway access unless `AGENTS_ALLOW_HOST_NETWORK=1` is set
- Verifies that `https://example.com` is blocked and that GitHub and PyPI are
  reachable
- Removes the passwordless sudo rule for the firewall command after successful
  startup unless `AGENTS_KEEP_FIREWALL_SUDO=1` is set

The launcher also rejects dangerous runtime flags by default, including
`--privileged`, `--network=host`, host PID/IPC/UTS namespaces, extra Linux
capabilities beyond the firewall requirements, host user namespaces, running
the container as root, entrypoint overrides, unconfined security profiles, host
root mounts, runtime socket mounts, and device passthrough. To intentionally
pass one of those flags, set `AGENTS_ALLOW_UNSAFE_FLAGS=1`.

### Custom image or extra flags

```bash
# Use a locally built image
start-agents my-local-agents-image:dev

# Pass extra docker/podman flags
start-agents ghcr.io/varchasgopalaswamy/agents:latest --env MY_TOOL_FLAG=1
```
