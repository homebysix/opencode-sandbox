FROM node:22-slim

# Core tools. Python's from Debian (3.11 on bookworm) — sits fine alongside the
# Node opencode needs, so no separate base image.
# hadolint ignore=DL3008
RUN apt-get update \
  && apt-get install -y --no-install-recommends \
       git ripgrep jq curl ca-certificates \
       python3 python3-venv python3-pip \
  && rm -rf /var/lib/apt/lists/*

RUN npm i -g opencode-ai

# Auto-activate a repo's .venv if one exists at /workspace/.venv (see oc.zsh).
ENV PATH="/workspace/.venv/bin:${PATH}"

ENTRYPOINT ["opencode"]
