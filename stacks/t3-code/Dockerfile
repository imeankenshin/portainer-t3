# syntax=docker/dockerfile:1.12

FROM docker:29.9.3-cli@sha256:b0d99f37f463c88cae2082083f705210296186c06632d22f6952ed43506ae520 AS docker-cli

FROM node:24-bookworm-slim@sha256:65932751ed4073ed02f5c04e494e4b2572a891b7dbea0568a863dc80341bf848 AS node

FROM ubuntu:24.04@sha256:73b999393d07f2bf65a40373778a44dc9a6d54ad7718d29247d8ff9413c4d6a8

ARG T3_VERSION="latest"
ARG OPENCODE_VERSION="~1.18.10"
ARG CODEX_VERSION="~0.157.0"
ARG NPM_VERSION="11.19.0"
ARG GH_VERSION="2.98.0"
ARG GH_AMD64_SHA256="3b8ac6b30336802fc1a858d7c084e11cdf24ac1a761ca90b68022d7d729208de"
ARG VCS_REF="unknown"
ARG SOURCE_URL="unknown"

LABEL org.opencontainers.image.title="t3-code remote development image" \
      org.opencontainers.image.description="Ubuntu 24.04 LTS T3 Code, OpenCode, and Codex environment with passwordless sudo and Docker Compose support" \
      org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      io.portainer-t3.t3.version="${T3_VERSION}" \
      io.portainer-t3.opencode.version="${OPENCODE_VERSION}" \
      io.portainer-t3.codex.version="${CODEX_VERSION}" \
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
    && useradd --uid 1000 --user-group --create-home --shell /bin/bash user \
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

COPY --from=docker-cli /usr/local/bin/docker /usr/local/bin/docker
COPY --from=docker-cli /usr/local/libexec/docker/cli-plugins /usr/local/libexec/docker/cli-plugins

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
        "@openai/codex@${CODEX_VERSION}" \
    && install -d /usr/local/share/t3-code \
    && printf 't3=%s\nopencode=%s\ncodex=%s\n' \
        "$(T3CODE_HOME=/opt/t3-code t3 --version)" "$(opencode --version)" "$(codex --version)" \
        > /usr/local/share/t3-code/versions \
    && find /opt/t3-code -mindepth 1 -maxdepth 1 ! -name runtime -exec rm -rf {} + \
    && chmod -R a+rX,go-w /opt/t3-code \
    && test -f "/opt/t3-code/runtime/versions/$(npm ls --global --json t3 | jq -r '.dependencies.t3.version')/.install-complete"

ENV HOME=/home/user \
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

COPY --chmod=0755 entrypoint.sh /usr/local/bin/t3-code-entrypoint

WORKDIR /workspace
EXPOSE 3773

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/t3-code-entrypoint"]
CMD ["t3", "serve", "--host", "0.0.0.0", "--port", "3773", "--base-dir", "/var/lib/t3", "/workspace"]
