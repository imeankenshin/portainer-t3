# syntax=docker/dockerfile:1.12

FROM docker:29.7.2-cli@sha256:e650b7a58d7f56be91d4f7be799196380a3bbc1bcbc41f1f4dff1b36ac309e1e AS docker-cli

FROM node:24-bookworm-slim@sha256:65932751ed4073ed02f5c04e494e4b2572a891b7dbea0568a863dc80341bf848

ARG T3_VERSION="~0.0.31"
ARG OPENCODE_VERSION="~1.18.10"
ARG NPM_VERSION="11.19.0"
ARG GH_VERSION="2.98.0"
ARG GH_AMD64_SHA256="3b8ac6b30336802fc1a858d7c084e11cdf24ac1a761ca90b68022d7d729208de"
ARG VCS_REF="unknown"
ARG SOURCE_URL="unknown"

LABEL org.opencontainers.image.title="t3-code remote development image" \
      org.opencontainers.image.description="Non-root T3 Code and OpenCode environment with Docker Compose support" \
      org.opencontainers.image.source="${SOURCE_URL}" \
      org.opencontainers.image.revision="${VCS_REF}" \
      io.portainer-t3.t3.version="${T3_VERSION}" \
      io.portainer-t3.opencode.version="${OPENCODE_VERSION}" \
      io.portainer-t3.docker.version="29.7.2" \
      io.portainer-t3.npm.version="${NPM_VERSION}" \
      io.portainer-t3.gh.version="${GH_VERSION}"

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt/lists,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && apt-get update -o Acquire::Retries=5 \
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
        tini \
        tzdata

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

RUN --mount=type=cache,target=/root/.npm,sharing=locked \
    npm install --global "npm@${NPM_VERSION}" \
    && npm install --global --omit=dev \
        --allow-scripts=opencode-ai,node-pty,msgpackr-extract \
        "t3@${T3_VERSION}" \
        "opencode-ai@${OPENCODE_VERSION}" \
    && install -d /usr/local/share/t3-code \
    && printf 't3=%s\nopencode=%s\n' \
        "$(t3 --version)" "$(opencode --version)" \
        > /usr/local/share/t3-code/versions

ENV HOME=/home/node \
    XDG_CONFIG_HOME=/home/node/.config \
    XDG_STATE_HOME=/home/node/.local/state \
    DOCKER_CONFIG=/home/node/.config/docker \
    GIT_CONFIG_GLOBAL=/home/node/.config/git/config \
    T3CODE_HOME=/var/lib/t3 \
    T3CODE_HOST=0.0.0.0 \
    T3CODE_PORT=3773 \
    T3CODE_LOG_LEVEL=Info \
    TZ=Asia/Tokyo \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

RUN install -d -m 0700 -o node -g node \
        /home/node/.config \
        /home/node/.config/docker \
        /home/node/.config/git \
        /home/node/.local/share/opencode \
        /home/node/.local/state \
        /home/node/.ssh \
        /var/lib/t3 \
    && install -d -m 0755 -o node -g node /workspace \
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
