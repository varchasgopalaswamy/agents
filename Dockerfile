ARG ORACLE_IC_VERSION=23
FROM ghcr.io/oracle/oraclelinux9-instantclient:${ORACLE_IC_VERSION} AS oracle-ic

FROM node:20

ARG TZ
ENV TZ="$TZ"

ARG CLAUDE_CODE_VERSION=latest

# Install basic development tools and iptables/ipset
RUN apt-get update && apt-get install -y --no-install-recommends \
  less \
  git \
  procps \
  sudo \
  fzf \
  man-db \
  unzip \
  gnupg2 \
  gh \
  iptables \
  ipset \
  iproute2 \
  dnsutils \
  aggregate \
  jq \
  nano \
  vim \
  ripgrep \ 
  bat \
  libaio1 \
  krb5-user \
  libkrb5-dev \
  libgssapi-krb5-2 \
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Create the agent user and set up npm-global directory
RUN useradd -m -s /bin/bash agent && \
  mkdir -p /usr/local/share/npm-global && \
  chown -R agent:agent /usr/local/share

ARG USERNAME=agent

# Persist bash history.
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  && mkdir /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R $USERNAME /commandhistory

# Create workspace and config directories and set permissions
RUN mkdir -p /workspace /home/agent/.claude && \
  chown -R agent:agent /workspace /home/agent/.claude

WORKDIR /workspace

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

# Install global packages
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=$PATH:/usr/local/share/npm-global/bin

# Set the default editor and visual
ENV EDITOR=nano
ENV VISUAL=nano

RUN (curl -fsSL https://claude.ai/install.sh | bash) && (npm install -g @google/gemini-cli @openai/codex @githubnext/github-copilot-cli opencode-ai) 

# Copy and set up firewall script
COPY init-firewall.sh /usr/local/bin/
USER root
RUN chmod +x /usr/local/bin/init-firewall.sh && \
  echo "agent ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/agent-firewall && \
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
