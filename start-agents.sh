#!/usr/bin/env python3
"""
start-agents.sh — launch the agents container with podman or docker.

Install:
  cp start-agents.sh ~/.local/bin/start-agents
  chmod +x ~/.local/bin/start-agents

Usage:
  start-agents [IMAGE] [EXTRA_ARGS...]

  IMAGE        Container image to run (default: ghcr.io/varchasgopalaswamy/agents:latest)
  EXTRA_ARGS   Any additional arguments forwarded to podman/docker run

Environment variables honored at launch time (passed into the container):
  ANTHROPIC_API_KEY, CLAUDE_API_KEY
  GOOGLE_API_KEY, GEMINI_API_KEY
  OPENAI_API_KEY
  GITHUB_TOKEN, GH_TOKEN
  TZ  (defaults to the host timezone if /etc/localtime is available)
"""

from __future__ import annotations

import os
import shutil
import sys
from pathlib import Path

DEFAULT_IMAGE = "ghcr.io/varchasgopalaswamy/agents:latest"


def resolve_runtime() -> str:
    for runtime in ("podman", "docker"):
        if shutil.which(runtime):
            return runtime
    print("ERROR: neither podman nor docker found on PATH", file=sys.stderr)
    sys.exit(1)


def resolve_image_and_extra_args(argv: list[str]) -> tuple[str, list[str]]:
    if argv and not argv[0].startswith("-"):
        return argv[0], argv[1:]
    return DEFAULT_IMAGE, argv


def resolve_timezone() -> None:
    if os.environ.get("TZ"):
        return
    localtime = Path("/etc/localtime")
    if not localtime.exists():
        return
    resolved = localtime.resolve()
    marker = "/zoneinfo/"
    resolved_str = str(resolved)
    if marker in resolved_str:
        os.environ["TZ"] = resolved_str.split(marker, 1)[1]


def ensure_host_paths() -> dict[str, Path]:
    home = Path.home()
    paths = {
        "claude_dir": home / ".claude",
        "claude_json": home / ".claude.json",
        "gemini_dir": home / ".gemini",
        "codex_dir": home / ".codex",
        "venv_dir": home / ".agents_venv",
        "uv_cache_dir": home / ".cache" / "uv",
    }

    for key in ("claude_dir", "gemini_dir", "codex_dir", "venv_dir", "uv_cache_dir"):
        paths[key].mkdir(parents=True, exist_ok=True)
    paths["claude_json"].touch(exist_ok=True)
    return paths


def build_mounts(paths: dict[str, Path]) -> list[str]:
    workspace = Path.cwd()
    return [
        f"--volume={workspace}:/workspace:z",
        f"--volume={paths['claude_dir']}:/home/agent/.claude:z",
        f"--volume={paths['gemini_dir']}:/home/agent/.gemini:z",
        f"--volume={paths['codex_dir']}:/home/agent/.codex:z",
        f"--volume={paths['claude_json']}:/home/agent/.claude.json:z",
        f"--volume={paths['venv_dir']}:/home/agent/.venv:z",
        f"--volume={paths['uv_cache_dir']}:/home/agent/.cache/uv:z",
    ]


def build_env_args() -> list[str]:
    env_args: list[str] = []
    for name in (
        "ANTHROPIC_API_KEY",
        "CLAUDE_API_KEY",
        "GOOGLE_API_KEY",
        "GEMINI_API_KEY",
        "OPENAI_API_KEY",
        "GITHUB_TOKEN",
        "GH_TOKEN",
        "TZ",
    ):
        value = os.environ.get(name)
        if value:
            env_args.append(f"--env={name}={value}")
    return env_args


def main() -> None:
    runtime = resolve_runtime()
    image, extra_args = resolve_image_and_extra_args(sys.argv[1:])
    resolve_timezone()

    mounts = build_mounts(ensure_host_paths())
    env_args = build_env_args()

    print(f"Starting agents container with {runtime}...")
    print(f"  Image    : {image}")
    print(f"  Workspace: {Path.cwd()}")

    command = [
        runtime,
        "run",
        "--rm",
        "--interactive",
        "--tty",
        # NET_ADMIN and NET_RAW are required by init-firewall.sh, which uses
        # iptables/ipset to restrict outbound traffic to an allowlist of domains.
        "--cap-add=NET_ADMIN",
        "--cap-add=NET_RAW",
        *mounts,
        *env_args,
        *extra_args,
        image,
    ]
    os.execvp(runtime, command)


if __name__ == "__main__":
    main()
