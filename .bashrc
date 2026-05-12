# Bash history
export PROMPT_COMMAND='history -a'
export HISTFILE=/commandhistory/.bash_history

# NPM global prefix
export NPM_CONFIG_PREFIX=/usr/local/share/npm-global

# PATH additions
# UV project environment
export UV_PROJECT_ENVIRONMENT="${UV_PROJECT_ENVIRONMENT:-$HOME/.venv}"
export UV_CACHE_DIR="${UV_CACHE_DIR:-$HOME/.cache/uv}"
export UV_LINK_MODE="${UV_LINK_MODE:-copy}"

# PATH additions
export PATH="$HOME/.local/bin:$UV_PROJECT_ENVIRONMENT/bin:/usr/local/share/npm-global/bin:$PATH"

# Default editor
export EDITOR=nano
export VISUAL=nano

# Aliases
alias claude="claude --dangerously-skip-permissions"
alias gemini="gemini --approval-mode=yolo"
alias opencode="opencode"
alias codex="codex --dangerously-bypass-approvals-and-sandbox --search"

# Activate virtual environment if present
if [ -f "$UV_PROJECT_ENVIRONMENT/bin/activate" ]; then
    source "$UV_PROJECT_ENVIRONMENT/bin/activate"
fi
