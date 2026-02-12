# =============================================================================
# Claude Code Sandboxed Container
#
# Runs as non-root from the start. No firewall, no privilege drop, no su-exec.
# All hardening (cap-drop, read-only root, resource limits) applied at runtime
# via docker run flags.
# =============================================================================

FROM alpine:3.21.3

# hadolint ignore=DL3018
RUN apk add --no-cache \
    bash curl git openssh-client libgcc libstdc++ ripgrep jq tree

RUN addgroup -g 1000 agent \
    && adduser -D -u 1000 -G agent -s /bin/bash -h /home/agent agent

USER agent
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN curl -fsSL https://claude.ai/install.sh | bash
ENV PATH="/home/agent/.local/bin:${PATH}"
ENV DISABLE_AUTOUPDATER=1

USER root
RUN mkdir -p /workspace && chown agent:agent /workspace \
    && find / -perm /6000 -type f -exec chmod a-s {} + 2>/dev/null || true

COPY --chmod=755 entrypoint.sh /usr/local/bin/entrypoint.sh

USER agent
WORKDIR /workspace
ENV HOME=/home/agent
ENV GIT_TERMINAL_PROMPT=0

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["claude"]
