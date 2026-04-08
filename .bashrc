# Bash history
export PROMPT_COMMAND='history -a'
export HISTFILE=/commandhistory/.bash_history

# NPM global prefix
export NPM_CONFIG_PREFIX=/usr/local/share/npm-global

# PATH additions
export PATH="$HOME/.local/bin:/usr/local/share/npm-global/bin:$PATH"

# UV project environment
export UV_PROJECT_ENVIRONMENT=".claude_venv"

# Default editor
export EDITOR=nano
export VISUAL=nano

# Aliases
alias claude="claude --dangerously-skip-permissions"
alias gemini="gemini --approval-mode=yolo"

# Activate virtual environment if present
if [ -f ".claude_venv/bin/activate" ]; then
    source .claude_venv/bin/activate
fi
