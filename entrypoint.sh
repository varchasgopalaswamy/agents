#!/bin/bash
# Exit immediately if a command exits with a non-zero status
set -e
if [ -f ".claude_venv/bin/activate" ]; then
    source .claude_venv/bin/activate
fi

alias claude="claude --dangerously-skip-permissions"
alias gemini="gemini --approval-mode=yolo"
exec "$@"
