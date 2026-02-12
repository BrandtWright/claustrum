#!/bin/bash
set -euo pipefail

# Guard against Docker auto-creating ~/.claude.json as a directory.
# This happens when the file doesn't exist on the host before bind-mounting.
if [ -d "$HOME/.claude.json" ]; then
    echo "Error: $HOME/.claude.json is a directory (expected a file)." >&2
    echo "Run 'touch ~/.claude.json' on the host and try again." >&2
    exit 1
fi

# Point global gitconfig to /tmp because the root filesystem is read-only.
# /tmp is a writable tmpfs mount, so git can write its config there.
export GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-/tmp/.gitconfig}"

# Configure git identity from env vars if provided (e.g. -e GIT_USER_NAME="...").
# This allows commits inside the container to use the correct author.
[ -n "${GIT_USER_NAME:-}" ]  && git config --global user.name "$GIT_USER_NAME"
[ -n "${GIT_USER_EMAIL:-}" ] && git config --global user.email "$GIT_USER_EMAIL"

# Mark /workspace as a safe directory. Without this, git refuses to operate
# because the bind-mounted directory is owned by the host user, not "agent".
git config --global --add safe.directory /workspace 2>/dev/null || true

# Replace this shell with the actual command (default: "claude", set by CMD
# in the Dockerfile). This ensures the command runs as PID 1 and receives
# signals (e.g. SIGTERM) directly.
exec "$@"
