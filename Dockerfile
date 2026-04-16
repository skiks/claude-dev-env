FROM node:20-bookworm-slim

# Base dev tooling
RUN apt-get update && apt-get install -y --no-install-recommends \
      git \
      curl \
      wget \
      ca-certificates \
      openssh-client \
      build-essential \
      python3 \
      sudo \
      tmux \
      vim \
      nano \
      less \
      jq \
      ripgrep \
      htop \
      procps \
      tini \
    && rm -rf /var/lib/apt/lists/*

# GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
    && apt-get update && apt-get install -y --no-install-recommends gh \
    && rm -rf /var/lib/apt/lists/*

# Claude Code CLI + HAPI CLI (global npm installs)
RUN npm install -g @anthropic-ai/claude-code \
    && npm install -g @twsxtd/hapi --registry=https://registry.npmjs.org \
    && npm cache clean --force

WORKDIR /workspace

# Ensure dirs for persistent volumes exist
RUN mkdir -p /root/.config /root/.claude /root/.ssh \
    && chmod 700 /root/.ssh

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# tini handles PID 1 signals cleanly
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
