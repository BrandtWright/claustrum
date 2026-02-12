# Claustrum

A hardened Docker container for running [Claude Code](https://claude.ai/code)
in a constrained environment.

## Why

Claude Code executes shell commands, edits files, and installs packages — all
driven by an AI model. A malicious skill, hallucination, etc., could trick the
agent into running harmful commands via prompt injection. Claustrum contains that
blast radius by running the agent inside a locked-down container with zero
capabilities, a read-only root filesystem, and strict resource limits.

## What You Get

- **Zero capabilities** — `--cap-drop=ALL`, nothing added back
- **Non-root from the start** — no privilege drop, no setuid binaries
- **Read-only root filesystem** — only `/workspace` and Claude config are writable
- **Resource limits** — memory (4 GB), CPU (2 cores), PIDs (512), file
  descriptors (4096/8192)
- **Proper signal handling** — `--init` for zombie reaping and clean shutdown
- **No privilege escalation** — `no-new-privileges` enforced

All hardening is applied via standard `docker run` flags. No wrapper scripts, no
`iptables`, no runtime privilege drops.

## Quick Start

### Build

```bash
docker build -t claustrum .
```

Claude Code is installed at build time. Rebuild with `--no-cache` to get the
latest version.

### Run

Set your API key in the environment, then run from your project directory:

```bash
export ANTHROPIC_API_KEY="sk-..."

docker run --rm -it \
    --cap-drop=ALL \
    --security-opt no-new-privileges:true \
    --read-only --init \
    --tmpfs /tmp:rw,noexec,nosuid,size=512m \
    --tmpfs /home/agent/.local/state:rw,noexec,nosuid,size=64m \
    --memory=4g --memory-swap=4g \
    --cpus=2 --pids-limit=512 \
    --ulimit nofile=4096:8192 \
    -e ANTHROPIC_API_KEY -e GIT_USER_NAME -e GIT_USER_EMAIL \
    -v "$HOME/.claude:/home/agent/.claude" \
    -v "$HOME/.claude.json:/home/agent/.claude.json" \
    -v "$(pwd):/workspace" \
    claustrum
```

Or use Compose:

```bash
cd /path/to/your/project
docker compose -f /path/to/claustrum/compose.yaml run --rm claude
```

### Debug

Drop into a shell inside the container:

```bash
docker compose -f /path/to/claustrum/compose.yaml run --rm claude bash
```

## Authentication

- **API key**: Set `ANTHROPIC_API_KEY` in your environment before running
- **Subscription**: Run `claude login` once inside the container; credentials
  persist in the `~/.claude` bind mount

## How It Works

1. **`docker build`** creates an Alpine-based image with Claude Code installed
   as the `agent` user (UID 1000). `setuid` bits are stripped from all binaries.

2. **`docker run`** applies all hardening flags — capabilities, read-only root,
   resource limits, no-new-privileges. No hardening logic lives inside the
   container.

3. **`entrypoint.sh`** runs as `agent`, configures git identity from
   environment variables, marks `/workspace` as a safe directory, then `exec`s
   into `claude`.

## Project Structure

```text
Dockerfile        # Image definition
entrypoint.sh     # Runtime git config, then exec into claude
compose.yaml      # All hardening flags in declarative form
CLAUDE.md         # Instructions for Claude Code working on this repo
README.md         # This file
SECURITY.md       # Threat model, known limitations, security checklist
```

## Security

See [SECURITY.md](SECURITY.md) for the full threat model, known limitations,
and security checklist.
