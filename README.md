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

The launcher is a uv script that installs its Python dependency
(`configargparse`) into an isolated uv environment on first run.

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

Saved Claude/Gemini/Codex config directories are not mounted by default. Use
`--agent-config` to mount them read-only, or `--writable-agent-config` as an
explicit opt-in when the container should be able to modify host agent config.
The Python venv and uv cache are also container-local by default; use
`--persist-python` to mount host paths for reuse across sessions.

### Environment variables

The launcher reads the following variables from your shell. Credentials are only
forwarded when `--forward-secret-env` or `AGENTS_FORWARD_SECRET_ENV=1` is set;
launcher configuration variables are parsed the same way as their matching
command-line options.

- `ANTHROPIC_API_KEY` / `CLAUDE_API_KEY`
- `GOOGLE_API_KEY` / `GEMINI_API_KEY`
- `OPENAI_API_KEY`
- `GITHUB_TOKEN` / `GH_TOKEN`
- `TZ` (falls back to the host timezone automatically)
- `AGENTS_CONFIG` reads launcher defaults from a TOML file
- `AGENTS_IMAGE`, `AGENTS_RUNTIME`, `AGENTS_WORKSPACE`, and
  `AGENTS_CONTAINER_NAME` set the main launch target
- `AGENTS_DRY_RUN=1` prints the generated run command
- `AGENTS_TTY=0` disables interactive TTY allocation
- `AGENTS_HISTORY_DIR` sets the persistent bash history host path
- `AGENTS_PERSIST_PYTHON=1` mounts the Python venv and uv cache from the host
- `AGENTS_VENV_DIR` and `AGENTS_UV_CACHE_DIR` set Python persistence host paths
- `AGENTS_CONTAINER_VENV_DIR` and `AGENTS_CONTAINER_UV_CACHE_DIR` set the
  matching container paths
- `AGENTS_CLAUDE_DIR`, `AGENTS_CLAUDE_JSON`, `AGENTS_GEMINI_DIR`, and
  `AGENTS_CODEX_DIR` set agent config mount sources
- `AGENTS_MOUNT_AGENT_CONFIG=1` mounts saved agent config read-only
- `AGENTS_WRITABLE_AGENT_CONFIG=1` makes mounted agent config read/write
- `AGENTS_FORWARD_SECRET_ENV=1` forwards supported API/token environment variables
- `AGENTS_DISABLE_FIREWALL=1` skips firewall initialization
- `AGENTS_ALLOW_HOST_NETWORK=1` allows the container to reach the host gateway
- `AGENTS_ALLOWED_DOMAINS` adds comma- or space-separated firewall allowlist domains
- `AGENTS_ALLOWED_CIDRS` adds comma- or space-separated firewall allowlist IPv4 CIDRs/IPs
- `AGENTS_PYTHON_VERSION` selects the Python version used when creating the venv
- `AGENTS_RECREATE_VENV=1` recreates the mounted venv on startup
- `AGENTS_ENABLE_SUDO_PASSWORD=1` prompts for password-based sudo setup during startup
- `AGENTS_EXTRA_ARGS` adds extra docker/podman run arguments

When secret forwarding is enabled, secrets are forwarded as environment variable
names, not literal `NAME=value` arguments, so API keys are not exposed in the
local `docker run`/`podman run` process arguments.

Run `start-agents --help` to see each launcher option with its environment
variable binding.

### Launcher options

Launcher-owned options must appear before the image name. Unknown options are
still passed through to `docker run`/`podman run` for compatibility.

Useful examples:

```bash
# Show the generated run command without starting the container
start-agents --dry-run

# Use a specific runtime and workspace
start-agents --runtime docker --workspace ~/src/my-project

# Use custom persistent Python and uv cache locations
start-agents \
  --persist-python \
  --venv-dir ~/.cache/agents/my-project-venv \
  --uv-cache-dir ~/.cache/agents/uv

# Initialize the container-local venv with a requested Python version
start-agents --python 3.12

# Recreate the venv if you intentionally want a fresh interpreter/env
start-agents --python 3.12 --recreate-venv

# Add package mirrors or internal services to the firewall allowlist
start-agents \
  --allow-domain pypi.my-company.example \
  --allow-cidr 10.40.0.0/16

# Mount saved agent credentials/config read-only
start-agents --agent-config

# Forward API/token environment variables only when needed
start-agents --forward-secret-env
```

Run `start-agents --help` for the full option list, including custom
`/home/agent/...` container paths such as `--container-venv-dir` and
`--container-uv-cache-dir`.

### TOML config files

You can put launcher options in a TOML file and run:

```bash
start-agents --config ~/.config/start-agents/project.toml
```

You can combine `--config` with command-line options and environment variables.
The launcher uses `ConfigArgParse` with its TOML parser, so precedence is:
command-line options, then environment variables, then config file values, then
defaults. TOML keys are the long option names without leading dashes.

Example config:

```toml
[start-agents]
image = "ghcr.io/varchasgopalaswamy/agents:latest"
runtime = "docker"
workspace = "~/src/my-project"
name = "agents-my-project"
dry-run = false
tty = true
mount-agent-config = true
writable-agent-config = false
forward-secret-env = false
extra-args = ["--env", "MY_TOOL_FLAG=1"]

[start-agents.paths]
venv-dir = "~/.cache/agents/my-project-venv"
uv-cache-dir = "~/.cache/agents/uv"
container-venv-dir = "/home/agent/.venv"
container-uv-cache-dir = "/home/agent/.cache/uv"

[start-agents.python]
persist-python = false
python-version = "3.12"
recreate-venv = false

[start-agents.firewall]
disable-firewall = false
allow-host-network = false
allowed-domains = ["pypi.my-company.example"]
allowed-cidrs = ["10.40.0.0/16"]

[start-agents.sudo]
sudo = true
```

### Password-based sudo

By default, the `agent` user cannot run general `sudo`. The entrypoint starts as
root, performs bootstrap work, initializes the firewall, removes legacy
passwordless bootstrap sudo files if present, and then drops to the `agent`
user. Use `--sudo` when you want the human operator to be able to install
packages or make other root-level changes inside the container:

```bash
start-agents --sudo
```

This prompts inside the container TTY before the shell or coding agent starts.
The password is read by a root-owned helper from `/dev/tty`, sent to `chpasswd`
over stdin, and never passed as a launcher flag, environment variable, Docker
argument, mounted file, or shell command argument. After bootstrap, the
default `no-new-privileges` runtime setting is omitted so password-based sudo
can work.

### Python

The image explicitly installs Python 3, `python3-venv`, `python3-pip`,
`python3-dev`, `build-essential`, and uv. On startup, the entrypoint creates a
seeded container-local virtual environment at `/home/agent/.venv` if one does
not already exist. The shell activates that environment automatically and
respects:

- `UV_PROJECT_ENVIRONMENT=/home/agent/.venv`
- `UV_CACHE_DIR=/home/agent/.cache/uv`
- `UV_LINK_MODE=copy`

Use `--python VERSION` or `AGENTS_PYTHON_VERSION=VERSION` to select the Python
interpreter when the venv is first created. Use `--persist-python` when you
want to reuse the venv and uv cache from host paths across sessions. Existing
persistent venvs are not silently destroyed if they use a different Python
version; use `--recreate-venv` or a different `--venv-dir` when you want a
fresh environment.

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
- Omits telemetry-only domains from the default allowlist
- Allows extra domains from `--allow-domain`, `--allow-domains`, or
  `AGENTS_ALLOWED_DOMAINS`
- Allows extra IPv4 CIDRs/IPs from `--allow-cidr`, `--allow-cidrs`, or
  `AGENTS_ALLOWED_CIDRS`
- Writes resolved allowlisted hostnames to `/etc/hosts`, then blocks runtime
  DNS egress to reduce DNS-based exfiltration
- Emits direct destination allow rules with iptables
- Drops IPv6 outbound traffic
- Blocks host gateway access unless `AGENTS_ALLOW_HOST_NETWORK=1` is set
- Verifies that `https://example.com` is blocked and that GitHub and PyPI are
  reachable
- Removes legacy passwordless sudo bootstrap files if present

The launcher also rejects dangerous runtime flags by default, including
`--privileged`, custom network/DNS/namespace settings, extra capabilities,
extra mounts, device passthrough, published ports, entrypoint/user overrides,
env-file injection, and attempts to override launcher-controlled environment
variables. The default runtime capability set drops everything, then adds only
`NET_ADMIN` for firewall setup and `SETUID`/`SETGID` so the root entrypoint can
drop to the `agent` user. Launcher-owned mount sources also reject broad host
mounts such as `/`, the host home directory, and container runtime sockets. To
intentionally pass one of those flags, set `AGENTS_ALLOW_UNSAFE_FLAGS=1`.

### Custom image or extra flags

```bash
# Use a locally built image
start-agents my-local-agents-image:dev

# Pass extra docker/podman flags
start-agents ghcr.io/varchasgopalaswamy/agents:latest --env MY_TOOL_FLAG=1
```
