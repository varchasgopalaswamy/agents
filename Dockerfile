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
  && apt-get clean && rm -rf /var/lib/apt/lists/*

# Ensure default node user has access to /usr/local/share
RUN mkdir -p /usr/local/share/npm-global && \
  chown -R node:node /usr/local/share

ARG USERNAME=node

# Persist bash history.
RUN SNIPPET="export PROMPT_COMMAND='history -a' && export HISTFILE=/commandhistory/.bash_history" \
  && mkdir /commandhistory \
  && touch /commandhistory/.bash_history \
  && chown -R $USERNAME /commandhistory

# Create workspace and config directories and set permissions
RUN mkdir -p /workspace /home/node/.claude && \
  chown -R node:node /workspace /home/node/.claude

WORKDIR /workspace

ARG GIT_DELTA_VERSION=0.18.2
RUN ARCH=$(dpkg --print-architecture) && \
  wget "https://github.com/dandavison/delta/releases/download/${GIT_DELTA_VERSION}/git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  sudo dpkg -i "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb" && \
  rm "git-delta_${GIT_DELTA_VERSION}_${ARCH}.deb"

# Install Oracle Instant Client
ARG ORACLE_INSTANTCLIENT_VERSION=21.13.0.0.0
ARG ORACLE_INSTANTCLIENT_SHORT=2113000
RUN ARCH=$(dpkg --print-architecture) && \
  case "$ARCH" in \
    amd64) IC_ARCH="linux.x86_64" ;; \
    arm64) IC_ARCH="linuxaarch64" ;; \
    *) echo "Unsupported architecture: $ARCH" && exit 1 ;; \
  esac && \
  wget "https://download.oracle.com/otn_software/linux/instantclient/${ORACLE_INSTANTCLIENT_SHORT}/instantclient-basic-${IC_ARCH}-${ORACLE_INSTANTCLIENT_VERSION}dbru.zip" -O /tmp/ic-basic.zip && \
  unzip /tmp/ic-basic.zip -d /opt/oracle && \
  rm /tmp/ic-basic.zip && \
  echo /opt/oracle/instantclient_21_13 > /etc/ld.so.conf.d/oracle-instantclient.conf && \
  ldconfig

# Set up non-root user
USER node

# Install global packages
ENV NPM_CONFIG_PREFIX=/usr/local/share/npm-global
ENV PATH=$PATH:/usr/local/share/npm-global/bin

# Set the default editor and visual
ENV EDITOR=nano
ENV VISUAL=nano

RUN (curl -fsSL https://claude.ai/install.sh | bash) && (npm install -g @google/gemini-cli) 

# Copy and set up firewall script
COPY init-firewall.sh /usr/local/bin/
USER root
RUN chmod +x /usr/local/bin/init-firewall.sh && \
  echo "node ALL=(root) NOPASSWD: /usr/local/bin/init-firewall.sh" > /etc/sudoers.d/node-firewall && \
  chmod 0440 /etc/sudoers.d/node-firewall

COPY --from=ghcr.io/astral-sh/uv:latest /uv /uvx /bin/

# Copy .bashrc for the node user
COPY --chown=node:node .bashrc /home/node/.bashrc

# Copy the entrypoint script
COPY entrypoint.sh /usr/local/bin/entrypoint.sh

# Make sure the script is executable
RUN chmod +x /usr/local/bin/entrypoint.sh
USER node

# Set the entrypoint
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]

# Set the default command to bash
CMD ["/bin/bash"]
