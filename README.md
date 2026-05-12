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
| `~/.claude` | `/home/agent/.claude` | Claude config / credentials |
| `~/.claude.json` | `/home/agent/.claude.json` | Claude settings file |
| `~/.gemini` | `/home/agent/.gemini` | Gemini config / credentials |
| `~/.codex` | `/home/agent/.codex` | Codex config / credentials |
| `~/.agents_venv` | `/home/agent/.venv` | Persistent Python virtual environment |
| `~/.cache/uv` | `/home/agent/.cache/uv` | Persistent uv cache |

### Environment variables

The launcher reads the following variables from your shell. Credentials are
forwarded into the container when set; launcher configuration variables are
parsed the same way as their matching command-line options.

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
- `AGENTS_HISTORY_DIR`, `AGENTS_VENV_DIR`, and `AGENTS_UV_CACHE_DIR` set
  persistent host paths
- `AGENTS_CONTAINER_VENV_DIR` and `AGENTS_CONTAINER_UV_CACHE_DIR` set the
  matching container paths
- `AGENTS_CLAUDE_DIR`, `AGENTS_CLAUDE_JSON`, `AGENTS_GEMINI_DIR`, and
  `AGENTS_CODEX_DIR` set agent config mount sources
- `AGENTS_MOUNT_AGENT_CONFIG=0` disables saved agent config mounts
- `AGENTS_DISABLE_FIREWALL=1` skips firewall initialization
- `AGENTS_ALLOW_HOST_NETWORK=1` allows the container to reach the host gateway
- `AGENTS_KEEP_FIREWALL_SUDO=1` keeps the one-command firewall sudo rule after startup
- `AGENTS_ALLOWED_DOMAINS` adds comma- or space-separated firewall allowlist domains
- `AGENTS_ALLOWED_CIDRS` adds comma- or space-separated firewall allowlist IPv4 CIDRs/IPs
- `AGENTS_PYTHON_VERSION` selects the Python version used when creating the venv
- `AGENTS_RECREATE_VENV=1` recreates the mounted venv on startup
- `AGENTS_ENABLE_SUDO_PASSWORD=1` prompts for password-based sudo setup during startup
- `AGENTS_EXTRA_ARGS` adds extra docker/podman run arguments

Secrets are forwarded as environment variable names, not literal `NAME=value`
arguments, so API keys are not exposed in the local `docker run`/`podman run`
process arguments.

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
  --venv-dir ~/.cache/agents/my-project-venv \
  --uv-cache-dir ~/.cache/agents/uv

# Initialize the persistent venv with a requested Python version
start-agents --python 3.12

# Recreate the mounted venv if you intentionally want a fresh interpreter/env
start-agents --python 3.12 --recreate-venv

# Add package mirrors or internal services to the firewall allowlist
start-agents \
  --allow-domain pypi.my-company.example \
  --allow-cidr 10.40.0.0/16

# Avoid mounting saved agent credentials/config into the container
start-agents --no-agent-config
```

Run `start-agents --help` for the full option list, including custom container
paths such as `--container-venv-dir` and `--container-uv-cache-dir`.

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
extra-args = ["--env", "MY_TOOL_FLAG=1"]

[start-agents.paths]
venv-dir = "~/.cache/agents/my-project-venv"
uv-cache-dir = "~/.cache/agents/uv"
container-venv-dir = "/home/agent/.venv"
container-uv-cache-dir = "/home/agent/.cache/uv"

[start-agents.python]
python-version = "3.12"
recreate-venv = false

[start-agents.firewall]
disable-firewall = false
allow-host-network = false
keep-firewall-sudo = false
allowed-domains = ["pypi.my-company.example"]
allowed-cidrs = ["10.40.0.0/16"]

[start-agents.sudo]
sudo = true
```

### Password-based sudo

By default, the `agent` user cannot run general `sudo`; only the bootstrap
firewall/password setup commands are temporarily allowed without a password.
Use `--sudo` when you want the human operator to be able to install packages or
make other root-level changes inside the container:

```bash
start-agents --sudo
```

This prompts inside the container TTY before the shell or coding agent starts.
The password is read by a root-owned helper from `/dev/tty`, sent to `chpasswd`
over stdin, and never passed as a launcher flag, environment variable, Docker
argument, mounted file, or shell command argument. After bootstrap, the
passwordless setup sudo rule is removed and `sudo -k` clears any cached sudo
timestamp.

### Python

The image explicitly installs Python 3, `python3-venv`, `python3-pip`,
`python3-dev`, `build-essential`, and uv. On startup, the entrypoint creates a
seeded persistent virtual environment at `/home/agent/.venv` if one does not
already exist. The shell activates that environment automatically and respects:

- `UV_PROJECT_ENVIRONMENT=/home/agent/.venv`
- `UV_CACHE_DIR=/home/agent/.cache/uv`
- `UV_LINK_MODE=copy`

Use `--python VERSION` or `AGENTS_PYTHON_VERSION=VERSION` to select the Python
interpreter when the venv is first created. Existing venvs are not silently
destroyed if they use a different Python version; use `--recreate-venv` or a
different `--venv-dir` when you want a fresh environment.

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
- Allows extra domains from `--allow-domain`, `--allow-domains`, or
  `AGENTS_ALLOWED_DOMAINS`
- Allows extra IPv4 CIDRs/IPs from `--allow-cidr`, `--allow-cidrs`, or
  `AGENTS_ALLOWED_CIDRS`
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
