#!/bin/bash
set -euo pipefail

AGENT_USER="${AGENT_USER:-agent}"
SUDOERS_FILE="/etc/sudoers.d/agent-user-sudo"

if [ "$(id -u)" -ne 0 ]; then
    echo "ERROR: configure-sudo-password.sh must run as root" >&2
    exit 1
fi

if ! id "$AGENT_USER" >/dev/null 2>&1; then
    echo "ERROR: user does not exist: $AGENT_USER" >&2
    exit 1
fi

if [ ! -r /dev/tty ] || [ ! -w /dev/tty ]; then
    echo "ERROR: password-based sudo setup requires an interactive TTY" >&2
    exit 1
fi

printf "Set sudo password for %s: " "$AGENT_USER" > /dev/tty
IFS= read -r -s password < /dev/tty
printf "\nConfirm sudo password for %s: " "$AGENT_USER" > /dev/tty
IFS= read -r -s confirm < /dev/tty
printf "\n" > /dev/tty

if [ -z "$password" ]; then
    echo "ERROR: sudo password cannot be empty" >&2
    exit 1
fi

if [ "$password" != "$confirm" ]; then
    password=
    confirm=
    echo "ERROR: sudo passwords did not match" >&2
    exit 1
fi

printf '%s:%s\n' "$AGENT_USER" "$password" | chpasswd
password=
confirm=

printf '%s ALL=(ALL:ALL) ALL\n' "$AGENT_USER" > "$SUDOERS_FILE"
chmod 0440 "$SUDOERS_FILE"

echo "Password-based sudo enabled for $AGENT_USER"
