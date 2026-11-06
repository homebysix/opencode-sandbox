FROM node:22-slim

# Core tools. Python's from Debian (3.11 on bookworm) — sits fine alongside the
# Node the agents need, so no separate base image. pi uses fd-find's `fdfind`.
# hadolint ignore=DL3008
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
       git ripgrep fd-find jq curl ca-certificates \
       python3 python3-venv python3-pip \
  && rm -rf /var/lib/apt/lists/*

# opencode v2 ships as @opencode/cli (opencode-ai is the v1 line). Its
# postinstall picks the platform binary, so scripts stay on for it.
# hadolint ignore=DL3016
RUN npm i -g @opencode/cli@2 \
  && npm i -g --ignore-scripts @earendil-works/pi-coding-agent

# Auto-activate a repo's .venv if one exists at /workspace/.venv (see oc.zsh).
ENV PATH="/workspace/.venv/bin:${PATH}"

# Throwaway container: no self-updates, update checks, or telemetry.
ENV OPENCODE_DISABLE_AUTOUPDATE=1 PI_OFFLINE=1 PI_TELEMETRY=0

# No ENTRYPOINT: oc.zsh passes `opencode` or `pi` as the command.
