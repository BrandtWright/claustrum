# Security Architecture

## Threat Model

An AI coding agent is semi-trusted software. It should help you write code, but
it processes untrusted input (your project files, third-party dependencies, web
content) and could be manipulated via **prompt injection** — a malicious file in
the repo that tricks the agent into executing harmful commands.

Threats we defend against:

| Threat | Mitigation |
| ------ | ---------- |
| Container escape | `cap-drop=ALL`, `no-new-privileges`, read-only root |
| Privilege escalation | Non-root user from start, setuid bits stripped, `no-new-privileges` |
| Host filesystem access | Only `/workspace`, `~/.claude`, and `~/.claude.json` bind-mounted; everything else isolated |
| Resource exhaustion | Memory, CPU, PID, and file-descriptor limits |
| Zombie/fork bomb | `--init` (tini) + `--pids-limit` |
| Git config credential exposure | Identity injected via env vars, not file mount |

## Container Architecture

```text
docker run --cap-drop=ALL --read-only --security-opt no-new-privileges:true ...
  │
  └─ entrypoint.sh (runs as non-root user "agent")
       │
       ├─ Configure git identity (via env vars)
       │
       └─ exec claude
```

No root startup. No privilege drop. No firewall init. The container runs as
non-root (`USER agent`) from the start with zero effective capabilities.

## Known Limitations and Residual Risk

### 1. No Egress Firewall (MEDIUM)

**Mitigation:**

- Use `--network=none` for fully offline operation (though this has limited use
  cases)
- Use Docker network policies or an external firewall for egress control
- Accept the risk: the agent needs API access to function, is much more useful
  with open access to the internet, and DNS tunneling remains possible
  regardless of firewall

### 2. Workspace Data Exposure (MEDIUM)

The agent can read EVERYTHING in your project directory, including:

- `.env` files with secrets
- `.git/config` (may contain credential helpers or inline tokens)
- Private keys accidentally committed
- Configuration files with passwords

**Mitigation:**

- Audit your project directory before mounting
- Keep secrets in a vault or env vars, not in files
- Use `.gitignore`-style hygiene: never commit secrets

### 3. Anthropic API as Exfiltration Channel (LOW)

The agent inherently sends data to `api.anthropic.com` — that's how it works.
A prompt-injected agent could embed secrets in its API requests. This is
fundamental to the architecture and cannot be fully mitigated while using the
tool.

### 4. No SSH Agent Forwarding (BY DESIGN)

SSH agent forwarding (`SSH_AUTH_SOCK`) is intentionally not configured. Mounting
the host's SSH agent socket into the container would give the AI agent the
ability to authenticate as you to any SSH-accessible resource — GitHub, GitLab,
production servers, internal infrastructure — silently and without additional
prompting.

This is more dangerous than leaking a single API key. SSH keys often grant broad
access across many systems, and a prompt-injected agent could use forwarded
credentials to clone private repos, push malicious code, or connect to remote
hosts without your knowledge.

**If you need private repo access inside the container:**

- Clone the repo on the host, then mount it into the container via `/workspace`
- Use a scoped HTTPS token (time-limited, single-repo, read-only) passed via
  environment variable
- Use a read-only deploy key restricted to a single repository

Do not mount `SSH_AUTH_SOCK` into the container.

### 5. No Disk Write Quota on Workspace (LOW)

Bind mounts don't support size limits. The agent could fill your host disk by
writing to `/workspace`. `tmpfs` mounts (for `/tmp`, caches) do have size limits.

**Mitigation:**

- Monitor disk usage
- Run on a volume with quota support
- Use `df` alerts

## Container Security Checklist

| Control | Status | Notes |
| ------- | ------ | ----- |
| Non-root user | ✅ | `USER agent` in Dockerfile, non-root from start |
| `--cap-drop=ALL` | ✅ | Zero capabilities, nothing added back |
| `no-new-privileges` | ✅ | Blocks setuid/file-cap escalation |
| Read-only root filesystem | ✅ | `/workspace`, `~/.claude`, `~/.claude.json` writable via bind mount; tmpfs for `/tmp` and state |
| Setuid bits stripped | ✅ | `find / -perm /6000 ... chmod a-s` |
| No Docker socket | ✅ | Never mounted |
| `--init` (tini) | ✅ | Proper zombie reaping + signal handling |
| Memory limit | ✅ | 4 GB, swap disabled |
| CPU limit | ✅ | 2 cores |
| PID limit | ✅ | 512 processes |
| File descriptor limit | ✅ | `ulimit nofile=4096:8192` |
| Image version pinned | ✅ | `alpine:3.21.3` |
| Git identity via env | ✅ | No `~/.gitconfig` file mounted |
| No SSH agent forwarding | ✅ | `SSH_AUTH_SOCK` never mounted; use scoped HTTPS tokens or deploy keys |
| Default `seccomp` profile | ✅ | Docker default (blocks ~44 syscalls) |
| Egress firewall | ❌ | Removed for simplicity; use Docker network policies or an external firewall |
| Custom `seccomp` profile | ❌ | Not implemented (default is reasonable) |
| Custom AppArmor profile | ❌ | Not implemented (default is reasonable) |
| Disk write quota | ❌ | Not possible with bind mounts |
