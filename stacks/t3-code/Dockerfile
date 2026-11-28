# syntax=docker/dockerfile:1.12

# The official DinD image provides the Docker CLI and plugins, the static
# Docker Engine binaries, and the dind wrapper that runs dockerd in a container.
FROM docker:29.9.3-dind@sha256:fafc2949724b06fd4e4bc53c446a09149b750693f0abe7f444e9eec1e138fe65 AS docker

FROM node:24-bookworm-slim@sha256:65932751ed4073ed02f5c04e494e4b2572a891b7dbea0568a863dc80341bf848 AS node

FROM ubuntu:24.04@sha256:73b999393d07f2bf65a40373778a44dc9a6d54ad7718d29247d8ff9413c4d6a8

ARG T3_VERSION="latest"
ARG OPENCODE_VERSION="~1.18.10"
ARG CODEX_VERSION="latest"
ARG CLAUDE_CODE_VERSION="latest"
ARG NPM_VERSION="11.19.0"
ARG GH_VERSION="2.98.0"
ARG GH_AMD64_SHA256="3b8ac6b30336802fc1a858d7c084e11cdf24ac1a761ca90b68022d7d729208de"
ARG VCS_REF="unknown"
ARG SOURCE_URL="unknown"

LABEL org.opencontainers.image.title="t3-code remote development image" \
      org.opencontainers.image.description="Ubuntu 24.04 LTS T3 Code, OpenCode, Codex, and Claude Code environment with passwordless sudo and a built-in Docker Engine" \
      org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      io.portainer-t3.t3.version="${T3_VERSION}" \
      io.portainer-t3.opencode.version="${OPENCODE_VERSION}" \
      io.portainer-t3.codex.version="${CODEX_VERSION}" \
      io.portainer-t3.claude-code.version="${CLAUDE_CODE_VERSION}" \
      io.portainer-t3.docker.version="29.9.3" \
      io.portainer-t3.npm.version="${NPM_VERSION}" \
      io.portainer-t3.gh.version="${GH_VERSION}"

# CI changes this per run so cached layers cannot retain outdated OS packages.
ARG OS_PACKAGES_REFRESH="manual"
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && apt-get update -o Acquire::Retries=5 \
    && DEBIAN_FRONTEND=noninteractive apt-get upgrade -y \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        bash \
        build-essential \
        ca-certificates \
        curl \
        git \
        gosu \
        gzip \
        iproute2 \
        iptables \
        jq \
        less \
        lsof \
        openssh-client \
        procps \
        python3 \
        ripgrep \
        sudo \
        tini \
        tzdata

# Replace the base image's default UID 1000 account with the development user.
RUN userdel --remove ubuntu \
    && groupadd --system docker \
    && useradd --uid 1000 --user-group --groups docker --create-home --shell /bin/bash user \
    && ln -s /home/user /home/node \
    && printf '%s\n' 'user ALL=(ALL:ALL) NOPASSWD: ALL' > /etc/sudoers.d/user \
    && chmod 0440 /etc/sudoers.d/user \
    && visudo --check --file=/etc/sudoers.d/user

COPY --from=node /usr/local/bin/node /usr/local/bin/node
COPY --from=node /usr/local/include/node /usr/local/include/node
COPY --from=node /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -s node /usr/local/bin/nodejs \
    && ln -s ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm \
    && ln -s ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx \
    && ln -s ../lib/node_modules/corepack/dist/corepack.js /usr/local/bin/corepack \
    && node --version \
    && npm --version

COPY --from=docker /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker /usr/local/libexec/docker/cli-plugins /usr/local/libexec/docker/cli-plugins
COPY --from=docker \
    /usr/local/bin/dockerd \
    /usr/local/bin/containerd-shim-runc-v2 \
    /usr/local/bin/ctr \
    /usr/local/bin/runc \
    /usr/local/bin/docker-proxy \
    /usr/local/bin/docker-init \
    /usr/local/bin/dind \
    /usr/local/bin/

RUN curl --fail --location --show-error --silent \
        --retry 5 --retry-all-errors \
        --output "/tmp/gh_${GH_VERSION}_linux_amd64.tar.gz" \
        "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_amd64.tar.gz" \
    && printf '%s  %s\n' \
        "${GH_AMD64_SHA256}" "/tmp/gh_${GH_VERSION}_linux_amd64.tar.gz" \
        | sha256sum --check --strict \
    && tar -xzf "/tmp/gh_${GH_VERSION}_linux_amd64.tar.gz" -C /tmp \
    && install -m 0755 \
        "/tmp/gh_${GH_VERSION}_linux_amd64/bin/gh" \
        /usr/local/bin/gh \
    && rm -rf "/tmp/gh_${GH_VERSION}_linux_amd64" \
        "/tmp/gh_${GH_VERSION}_linux_amd64.tar.gz"

RUN corepack enable

# Since 0.1.0 the t3 npm package is a launcher that downloads the platform
# runtime from GitHub Releases into $T3CODE_HOME/runtime/versions/<version> on
# first run. Download it at build time into /opt/t3-code; the entrypoint links
# it into the persistent T3 home so containers start without a download.

RUN --mount=type=cache,target=/root/.npm,sharing=locked \
    npm install --global "npm@${NPM_VERSION}" \
    && npm install --global --omit=dev \
        --allow-scripts=opencode-ai,node-pty,msgpackr-extract \
        "t3@${T3_VERSION}" \
        "opencode-ai@${OPENCODE_VERSION}" \
    && install -d /usr/local/share/t3-code \
    && printf 't3=%s\nopencode=%s\n' \
        "$(T3CODE_HOME=/opt/t3-code t3 --version)" "$(opencode --version)" \
        > /usr/local/share/t3-code/versions \
    && find /opt/t3-code -mindepth 1 -maxdepth 1 ! -name runtime -exec rm -rf {} + \
    && chmod -R a+rX,go-w /opt/t3-code \
    && test -f "/opt/t3-code/runtime/versions/$(npm ls --global --json t3 | jq -r '.dependencies.t3.version')/.install-complete"

# Let the installer pipelines below fail when curl fails.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# The official Codex installer keeps releases under $CODEX_HOME. Install them
# into /opt/codex instead of the persistent ~/.codex volume, so each image
# brings its own Codex, and link the command into /usr/local/bin.
RUN curl -fsSL https://chatgpt.com/codex/install.sh \
        | CODEX_HOME=/opt/codex CODEX_INSTALL_DIR=/usr/local/bin CODEX_NON_INTERACTIVE=1 \
            sh -s -- --release "${CODEX_VERSION}" \
    && rm -rf /opt/codex/tmp \
    && chmod -R a+rX,go-w /opt/codex

ENV HOME=/home/user \
    PATH=/home/user/.local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    CLAUDE_CONFIG_DIR=/home/user/.claude \
    XDG_CONFIG_HOME=/home/user/.config \
    XDG_STATE_HOME=/home/user/.local/state \
    DOCKER_CONFIG=/home/user/.config/docker \
    GIT_CONFIG_GLOBAL=/home/user/.config/git/config \
    T3CODE_HOME=/var/lib/t3 \
    T3CODE_HOST=0.0.0.0 \
    T3CODE_PORT=3773 \
    T3CODE_LOG_LEVEL=Info \
    TZ=Asia/Tokyo \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN install -d -m 0700 -o user -g user \
        /home/user/.config \
        /home/user/.config/docker \
        /home/user/.config/git \
        /home/user/.npm \
        /home/user/.codex \
        /home/user/.claude \
        /home/user/.local \
        /home/user/.local/share \
        /home/user/.local/share/opencode \
        /home/user/.local/state \
        /home/user/.ssh \
        /var/lib/t3 \
    && install -d -m 0755 -o user -g user /workspace \
    && printf '%s\n' \
        'github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl' \
        'github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=' \
        'github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=' \
        > /etc/ssh/ssh_known_hosts \
    && printf '%s\n' \
        'Host github.com' \
        '    StrictHostKeyChecking yes' \
        > /etc/ssh/ssh_config.d/99-github.conf

# The official Claude Code installer installs into the user's home:
# ~/.local/bin/claude and ~/.local/share/claude. Those paths stay in the image,
# outside the persistent ~/.claude volume, so each image brings its own Claude
# Code. Empty ~/.claude afterwards so build-time state and IDs do not seed the
# volume or get shared between stacks.
USER user
RUN curl -fsSL https://claude.ai/install.sh | bash -s -- "${CLAUDE_CODE_VERSION}" \
    && find /home/user/.claude -mindepth 1 -delete \
    && printf 'codex=%s\nclaude=%s\n' \
        "$(CODEX_HOME=/tmp/codex-version codex --version)" \
        "$(CLAUDE_CONFIG_DIR=/tmp/claude-version claude --version)" \
        | sudo tee -a /usr/local/share/t3-code/versions \
    && rm -rf /tmp/codex-version /tmp/claude-version
USER root

COPY --chmod=0755 entrypoint.sh /usr/local/bin/t3-code-entrypoint

# dockerd needs a data root outside the container's overlay filesystem.
VOLUME /var/lib/docker

WORKDIR /workspace
EXPOSE 3773

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/t3-code-entrypoint"]
CMD ["t3", "serve", "--host", "0.0.0.0", "--port", "3773", "--base-dir", "/var/lib/t3", "/workspace"]
