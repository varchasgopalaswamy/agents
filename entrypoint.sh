#!/bin/bash
# Exit immediately if a command exits with a non-zero status
set -e
if [ -f "/home/agent/bin/activate" ]; then
    source /home/agent/bin/activate
fi

exec "$@"
