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
cp start-agents.sh ~/.local/bin/start-agents
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
| `~/.config/claude` | `/home/node/.claude` | Claude config / credentials |
| `~/.ssh` | `/home/node/.ssh` | SSH keys (read-only) |
| `~/.gitconfig` | `/home/node/.gitconfig` | Git config (read-only) |

### Environment variables

The following variables are forwarded from your shell into the container if they
are set:

- `ANTHROPIC_API_KEY` / `CLAUDE_API_KEY`
- `GOOGLE_API_KEY` / `GEMINI_API_KEY`
- `OPENAI_API_KEY`
- `GITHUB_TOKEN` / `GH_TOKEN`
- `TZ` (falls back to the host timezone automatically)

### Custom image or extra flags

```bash
# Use a locally built image
start-agents my-local-agents-image:dev

# Pass extra docker/podman flags
start-agents ghcr.io/varchasgopalaswamy/agents:latest --network=host
```