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
`--mount-agent-config` to mount them read-only. Add
`--writable-agent-config` only when the container should be able to modify host
agent config. Detected `.git` metadata under the workspace is mounted read-only
by default; use `--writable-vcs` only when in-container Git writes are needed.
The Python venv and uv cache are also container-local by default; use
`--persist-python` to mount host paths for reuse across sessions. Outbound
network access starts deny-by-default; add provider or registry bundles such as
`--allow-openai`, `--allow-github`, or `--allow-pypi` for the destinations you
intend to permit.

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
- `AGENTS_WRITABLE_VCS=1` allows writes to detected `.git` metadata
- `AGENTS_FORWARD_SECRET_ENV=1` forwards supported API/token environment variables
- `AGENTS_DISABLE_FIREWALL=1` skips firewall initialization
- `AGENTS_ALLOW_HOST_NETWORK=1` allows the container to reach the host gateway
- `AGENTS_ALLOW_OPENAI=1` allows OpenAI API and ChatGPT auth/web endpoints
- `AGENTS_ALLOW_ANTHROPIC=1` allows Anthropic API and Claude web endpoints
- `AGENTS_ALLOW_GOOGLE=1` allows Gemini/Google API and auth endpoints
- `AGENTS_ALLOW_GITHUB=1` allows GitHub API/web/git/release/content endpoints and GitHub meta IP ranges
- `AGENTS_ALLOW_COPILOT=1` allows GitHub Copilot service endpoints
- `AGENTS_ALLOW_PYPI=1` allows PyPI package index and file endpoints
- `AGENTS_ALLOW_NPM=1` allows the npm registry
- `AGENTS_ALLOW_VSCODE=1` allows VS Code extension marketplace and update endpoints
- `AGENTS_ALLOWED_DOMAINS` adds comma- or space-separated firewall allowlist domains
- `AGENTS_ALLOWED_CIDRS` adds comma- or space-separated firewall allowlist IPv4 CIDRs/IPs
- `AGENTS_DEBUG_FIREWALL=1` enables rate-limited firewall denial logging
- `AGENTS_PYTHON_VERSION` selects the Python version used when creating the venv
- `AGENTS_RECREATE_VENV=1` recreates the mounted venv on startup
- `AGENTS_ENABLE_SUDO_PASSWORD=1` prompts for password-based sudo setup during startup
- `AGENTS_EXTRA_ARGS` adds extra docker/podman run arguments
- `AGENTS_ALLOW_UNSAFE_HOST_PATHS` permits specific otherwise rejected launcher-owned host mount paths
- `AGENTS_ALLOW_UNSAFE_RUNTIME_FLAGS` permits specific otherwise rejected docker/podman passthrough flags
- `AGENTS_ALLOW_UNSAFE_FLAGS=1` allows otherwise rejected docker/podman passthrough flags

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

# Allow only the provider, VCS host, and package registry this session needs
start-agents --allow-openai --allow-github --allow-pypi

# Add internal services or private mirrors to the firewall allowlist
start-agents \
  --allow-domain pypi.my-company.example \
  --allow-cidr 10.40.0.0/16

# Mount saved agent credentials/config read-only
start-agents --mount-agent-config

# Permit Git commands that update refs, objects, hooks, config, or history
start-agents --writable-vcs

# Forward API/token environment variables only when needed
start-agents --forward-secret-env --allow-openai

# Bypass one rejected runtime flag, with a loud warning
start-agents --allow-unsafe-runtime-flag=--volume \
  my-image:dev --volume /tmp/tool-cache:/tool-cache

# Bypass one rejected launcher-owned host path, with a loud warning
start-agents \
  --history-dir ~/.ssh \
  --allow-unsafe-host-path ~/.ssh
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
mount-agent-config = false
writable-agent-config = false
forward-secret-env = false
writable-vcs = false
allow-unsafe-host-path = []
allow-unsafe-runtime-flag = []
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
allow-openai = true
allow-anthropic = false
allow-google = false
allow-github = true
allow-copilot = false
allow-pypi = true
allow-npm = false
allow-vscode = false
debug-firewall = false
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

### Privilege and exposure options

Several options intentionally increase what the agent can access. Treat them as
capability grants to code you may not fully trust:

- `--sudo` gives the agent a path to root inside the container and disables the
  default `no-new-privileges` setting, increasing the impact of container escape
  bugs and allowing firewall or tooling tampering after startup.
- `--disable-firewall` permits unrestricted outbound network access, enabling
  direct exfiltration to any destination.
- `--allow-host-network` permits access to services on the host gateway,
  including local databases, metadata services, dev servers, and unauthenticated
  admin panels.
- `--forward-secret-env` exposes supported API tokens to the agent process;
  tokens can be read and sent to any allowed endpoint.
- `--mount-agent-config` exposes saved agent credentials and config. Read-only
  mounts prevent modification, but not theft.
- `--writable-agent-config` allows credential/config tampering, persistence, and
  host-side agent behavior changes. It requires `--mount-agent-config`.
- `--persist-python` exposes a host venv/cache to code execution and package
  poisoning across sessions.
- `--writable-vcs` allows rewriting refs, objects, hooks, config, and history in
  the host repository.
- `--allow-unsafe-host-path PATH` bypasses launcher mount-source rejection for a
  specific host path. It can expose broad host directories, credential stores,
  runtime sockets, or VCS internals if you name those paths.
- `--allow-unsafe-runtime-flag FLAG` bypasses rejection for one specific
  docker/podman passthrough flag, for example `--volume` or `--device`. Use the
  `--allow-unsafe-runtime-flag=--flag` form when the flag itself starts with
  `--`.
- `AGENTS_ALLOW_UNSAFE_FLAGS=1` allows runtime options that may expose host
  files, devices, sockets, namespaces, ports, credentials, or bypass the
  launcher entrypoint/firewall.
- Custom `--allow-domain` and `--allow-cidr` rules create exfiltration
  destinations controlled by the chosen host or network.

Provider bundles such as `--allow-openai`, `--allow-anthropic`,
`--allow-google`, `--allow-github`, and `--allow-copilot` enable legitimate
agent operation. They also create channels where an untrusted agent can encode
workspace secrets into normal-looking API, web, git, or package requests.

The unsafe host-path and runtime-flag bypasses print an explicit warning before
the launch command. The warning is intentional: if an untrusted agent steals
tokens, rewrites files, or reaches host services through a bypass you enabled,
that is the expected risk of the option.

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
`AGENTS_DISABLE_FIREWALL=1` is set. By default, it allows no provider, package,
or source-host endpoints. It permits loopback and established traffic required
by the rules, blocks host gateway access unless `AGENTS_ALLOW_HOST_NETWORK=1`
is set, rejects runtime DNS egress after startup resolution, and applies a
default outbound deny policy.

Use `--debug-firewall` or `AGENTS_DEBUG_FIREWALL=1` to add rate-limited kernel
log rules immediately before denied DNS and default outbound rejects. Denied
packet logs use the `AGENTS-FW-DENY` prefix and may appear in `docker logs`,
`podman logs`, or the host kernel log depending on the runtime and host logging
configuration.

Use explicit bundles for expected destinations:

| Option | Allowed destinations |
|--------|----------------------|
| `--allow-openai` | `api.openai.com`, `auth.openai.com`, `chatgpt.com` |
| `--allow-anthropic` | `api.anthropic.com`, `claude.ai` |
| `--allow-google` | `accounts.google.com`, `oauth2.googleapis.com`, `www.googleapis.com`, `generativelanguage.googleapis.com`, `cloudcode-pa.googleapis.com` |
| `--allow-github` | `api.github.com`, `github.com`, `codeload.github.com`, `raw.githubusercontent.com`, `objects.githubusercontent.com`, `gist.githubusercontent.com`, `github-releases.githubusercontent.com`, plus GitHub meta IP ranges |
| `--allow-copilot` | `api.githubcopilot.com`, `copilot-proxy.githubusercontent.com` |
| `--allow-pypi` | `pypi.org`, `files.pythonhosted.org` |
| `--allow-npm` | `registry.npmjs.org` |
| `--allow-vscode` | `marketplace.visualstudio.com`, `update.code.visualstudio.com`, `vscode.blob.core.windows.net` |

The firewall is an egress destination control, not a malware scanner or package
trust system. A default launch prevents direct downloads from package registries,
GitHub release/content hosts, arbitrary mirrors, and other external source
hosts because those destinations are not allowed. Once you enable a bundle such
as `--allow-pypi`, `--allow-npm`, or `--allow-github`, the agent can download
any content those services serve, including compromised packages, malicious
repository files, release artifacts, or code generated through an allowed model
provider. Use the narrowest allowlist that fits the task, prefer pinned
dependencies and reviewed repositories, and treat custom `--allow-domain` or
`--allow-cidr` entries as explicit code-download and exfiltration channels.

Custom rules from `--allow-domain`, `--allow-domains`, or
`AGENTS_ALLOWED_DOMAINS` add extra resolved hostnames. Custom rules from
`--allow-cidr`, `--allow-cidrs`, or `AGENTS_ALLOWED_CIDRS` add extra IPv4
CIDRs/IPs. The firewall validates IPv4 octets and CIDR prefix lengths
numerically, writes resolved allowlisted hostnames to `/etc/hosts`, emits direct
destination allow rules with iptables, and fails startup if IPv6 appears
available but cannot be blocked.

Verification always checks that `https://example.com` is blocked. It only checks
allowed endpoints for bundles you enabled, so a no-bundle launch verifies the
deny-by-default posture without requiring GitHub, PyPI, or model-provider
access. The firewall removes legacy passwordless sudo bootstrap files if
present.

The launcher also rejects dangerous runtime flags by default, including
`--privileged`, custom network/DNS/namespace settings, extra capabilities,
extra mounts, `--volumes-from`, `--env-host`, runtime secrets, preserved file
descriptors, custom root filesystems, OCI hook controls, device passthrough,
published ports, entrypoint/user overrides, env-file injection, and attempts to
override launcher-controlled environment variables. The default runtime
capability set drops everything, then adds only `NET_ADMIN` for firewall setup
and `SETUID`/`SETGID` so the root entrypoint can drop to the `agent` user.
Launcher-owned mount sources reject ambiguous paths containing `:` or newlines,
broad host mounts such as `/` and the host home directory, container runtime
sockets, host credential directories, and direct VCS metadata mounts. To bypass
a specific mount-source rejection, use `--allow-unsafe-host-path PATH`. To pass
one rejected runtime flag, use `--allow-unsafe-runtime-flag=--flag`; to bypass
all runtime-flag rejection, set `AGENTS_ALLOW_UNSAFE_FLAGS=1`.

### Custom image or extra flags

```bash
# Use a locally built image
start-agents my-local-agents-image:dev

# Pass extra docker/podman flags
start-agents ghcr.io/varchasgopalaswamy/agents:latest --env MY_TOOL_FLAG=1
```
