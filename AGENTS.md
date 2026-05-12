# Repository Guidelines

## Project Structure & Module Organization

This repository builds and launches a containerized coding-agent environment. Core files live at the root:

- `Dockerfile` defines the base image, global CLI installs, Oracle client setup, and default entrypoint.
- `start-agents` is the Python launcher that selects Docker or Podman, prepares host config/cache paths, and mounts the current project into `/workspace`.
- `init-firewall.sh` configures outbound network restrictions inside the container.
- `entrypoint.sh` is the minimal container entrypoint.
- `.bashrc` configures the agent user shell, aliases, history, npm prefix, and uv environment.
- `.github/workflows/docker-nightly.yml` builds and pushes the image to GHCR nightly and on manual dispatch.

There is no dedicated `src/`, `tests/`, or assets directory; keep new files near the component they support.

## Build, Test, and Development Commands

- `docker build -t ghcr.io/varchasgopalaswamy/agents:latest .` builds the local image.
- `podman build -t ghcr.io/varchasgopalaswamy/agents:latest .` is the Podman equivalent.
- `./start-agents [IMAGE] [EXTRA_ARGS...]` launches the container from the current project directory.
- `python3 -m py_compile start-agents` checks the launcher for Python syntax errors.
- `bash -n entrypoint.sh init-firewall.sh` checks shell scripts for syntax errors.

## Coding Style & Naming Conventions

Use Python 3 conventions in `start-agents`: four-space indentation, `snake_case` functions, uppercase constants, type hints where helpful, and `pathlib` for paths. Shell scripts should use `#!/bin/bash`; use `set -euo pipefail` for nontrivial scripts and quote variable expansions. Keep Dockerfile package lists grouped and avoid tools without a clear container use case.

## Testing Guidelines

There is no formal test framework or coverage target. For changes, run the syntax checks above and, when Docker or Podman is available, build the image. For launcher changes, test default invocation and a custom image or extra flag, for example `./start-agents local-image:dev --network=host`.

## Commit & Pull Request Guidelines

Recent commits use short imperative messages such as `Add start-agents.sh file`, `Refine timezone helper naming in Python launcher`, and `Remove accidental pycache artifact`. Follow that style: start with a verb, keep the subject concise, and describe one logical change.

Pull requests should include a brief summary, validation commands run, and any Docker, mount, environment, or firewall behavior changes. Link related issues when available.

## Security & Configuration Tips

Do not commit API keys or host-specific credentials. The launcher only forwards supported credential environment variables such as `OPENAI_API_KEY`, `ANTHROPIC_API_KEY`, `GITHUB_TOKEN`, and `GH_TOKEN` when secret forwarding is explicitly enabled. Changes to `init-firewall.sh` should document new allowed domains and preserve explicit verification of blocked and allowed traffic.
