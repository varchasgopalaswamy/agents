ARG ORACLE_IC_VERSION=23
FROM ghcr.io/oracle/oraclelinux9-instantclient:${ORACLE_IC_VERSION} AS oracle-ic

FROM node:20

ARG TZ
ENV TZ="$TZ"

ARG CLAUDE_CODE_VERSION=latest
ARG USERNAME=agent
ARG USER_UID=1000
ARG USER_GID=1000
ARG DEBIAN_FRONTEND=noninteractive

# Install development tools, Python, and iptables/ipset.
RUN apt-get update && apt-get install -y --no-install-recommends \
  aggregate \
  bat \
  build-essential \
  ca-certificates \
  curl \
  dnsutils \
  fzf \
  gh \
  git \
  gnupg2 \
  iproute2 \
  ipset \
  iptables \
  jq \
  krb5-user \
  less \
  libaio1 \
  libgssapi-krb5-2 \
  libkrb5-dev \
  man-db \
  nano \
  pkg-config \
  procps \
  python-is-python3 \
  python3 \
  python3-dev \
  python3-pip \
  python3-venv \
  ripgrep \
  sudo \
  unzip \
  vim \
  wget \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Reuse the base image's UID 1000 user so bind-mounted workspaces are writable
# for the common Linux host case. USER_UID/USER_GID can be overridden at build time.
RUN groupmod --gid "$USER_GID" --new-name "$USERNAME" node && \
  usermod --uid "$USER_UID" --login "$USERNAME" --home "/home/$USERNAME" --move-home node && \
  mkdir -p /usr/local/share/npm-global && \
  chown -R "$USERNAME:$USERNAME" /usr/local/share

# Persist bash history.
RUN mkdir /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R "$USERNAME:$USERNAME" /commandhistory

# Create workspace, config, cache, and Python directories and set permissions.
RUN mkdir -p /workspace "/home/$USERNAME/.claude" "/home/$USERNAME/.cache/uv" "/home/$USERNAME/.venv" && \
  chown -R "$USERNAME:$USERNAME" /workspace "/home/$USERNAME/.claude" "/home/$USERNAME/.cache" "/home/$USERNAME/.venv"

WORKDIR /workspace

RUN python --version && \
  python -m venv /tmp/python-smoke && \
  /tmp/python-smoke/bin/python -m pip --version && \
  rm -rf /tmp/python-smoke

ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) && \
  wget "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  sudo dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

# Install Oracle Instant Client (copied from official Oracle image)
COPY --from=oracle-ic /usr/lib/oracle /usr/lib/oracle
RUN IC_LIB_DIR=$(find /usr/lib/oracle -maxdepth 3 -name "lib" -type d | head -1) && \
  echo "${IC_LIB_DIR}" > /etc/ld.so.conf.d/oracle-instantclient.conf && \
  ldconfig

# Set up non-root user
USER agent

# Install global packages and configure the persistent Python environment.
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV UV_PROJECT_ENVIRONMENT=/home/agent/.venv
ENV UV_CACHE_DIR=/home/agent/.cache/uv
ENV UV_LINK_MODE=copy
ENV PATH=/home/agent/.local/bin:/home/agent/.venv/bin:/usr/local/share/npm-global/bin:$PATH

# Set the default editor and visual
ENV EDITOR=nano
ENV VISUAL=nano

RUN (curl -fsSL https://claude.ai/install.sh | bash) && (npm install -g @google/gemini-cli @openai/codex @githubnext/github-copilot-cli opencode-ai) 

# Copy and set up firewall script
COPY init-firewall.sh /usr/local/bin/
USER root
RUN chmod +x /usr/local/bin/init-firewall.sh && \
  printf '%s\n' \
    'Defaults!/usr/local/bin/init-firewall.sh secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"' \
    'agent ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh' \
    > /etc/sudoers.d/agent-firewall && \
  chmod 0440 /etc/sudoers.d/agent-firewall

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Copy .bashrc for the agent user
COPY --chown=agent:agent .bashrc /home/agent/.bashrc

# Copy the entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

# Make sure the script is executable
RUN chmod +x /usr/local/bin/entrypoint.sh
USER agent

# Set the entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Set the default command to bash
CMD ["/bin/bash"]
