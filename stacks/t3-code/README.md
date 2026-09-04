# T3 Code remote development stack

This directory is the source of truth for two isolated remote development
stacks. The work and personal stacks use the same development image, but each
owns a separate Docker daemon, network, TLS client identity, workspace, and
application state.

```text
SSH tunnel -> host loopback -> t3-code
                                |
                                | TLS 2376
                                v
                         dedicated DinD
                                |
                         project containers
```

## Files

- `Dockerfile`: non-root Node 24 image with T3 Code, OpenCode, Docker CLI,
  Compose, Buildx, GitHub CLI, and development tools.
- `compose.yml`: parameterized two-service stack deployed once per account.
- `work.env.example` and `personal.env.example`: non-secret Portainer stack
  variables.
- `tests/integration.sh`: TLS DinD and Compose bind-mount integration test.
- `.github/workflows/t3-code-image.yml`: daily amd64 build, test, scan,
  publish, SBOM/provenance, and deployment digest pull request.

Docker CLI and DinD are fixed to `29.7.2`; npm is fixed within its bundled
major line at `11.19.0`. These versions include fixes required by the Critical
vulnerability gate and are updated only through reviewed dependency changes.

## Image publishing

The repository must be hosted on GitHub before the workflow can publish. The
workflow writes `ghcr.io/<repository-owner>/t3-code` and creates a pull request
that replaces the placeholder image reference in `compose.yml` with an amd64
manifest digest.

Before the first deployment:

1. Push this project to GitHub with `main` as the default branch.
2. In repository Actions settings, allow GitHub Actions to create and approve
   pull requests and grant workflows read/write permissions.
3. Run the **T3 Code image** workflow manually.
4. Make the resulting `t3-code` package public in GitHub package settings.
5. Merge the generated image digest pull request.

The workflow also runs daily at 03:17 JST. T3 Code resolves within `0.0.x`
from a `0.0.31` floor, and OpenCode resolves within `1.18.x` from a `1.18.10`
floor. A new image does not affect either running stack until its digest pull
request is merged and that stack is manually redeployed.

## Portainer deployment

Create two Git-backed Docker Standalone stacks from the same repository and
the same `stacks/t3-code/compose.yml` path. Disable polling and webhook updates;
redeploy each stack manually after reviewing an image digest change.

Use distinct stack names such as `t3-code-work` and `t3-code-personal`. Copy
the matching example file into Portainer's stack environment variables.

On this Umbrel installation, the Portainer-managed Docker daemon shares the
host network namespace with the outer daemon but uses a different iptables
backend. `umbrel-portainer-entrypoint.sh` therefore permits only the managed
stack range `172.30.0.0/16` through the outer `DOCKER-USER` chain. Apply that
entrypoint before deploying these subnets or sibling traffic and outbound DNS
will time out.

| Variable | Work | Personal |
| --- | --- | --- |
| `T3_HOST_PORT` | `3773` | `3774` |
| `PREVIEW_HOST_START` | `31000` | `32000` |
| `PREVIEW_HOST_END` | `31049` | `32049` |
| `STACK_SUBNET` | `172.30.10.0/24` | `172.30.20.0/24` |
| `DIND_BIP` | `10.60.0.1/24` | `10.61.0.1/24` |
| `DIND_ADDRESS_POOL` | `10.60.128.0/17` | `10.61.128.0/17` |
| `GIT_USER_NAME` | work identity | personal identity |
| `GIT_USER_EMAIL` | work email | personal email |

`GIT_USER_NAME` and `GIT_USER_EMAIL` initialize missing global Git settings
only. Existing values in the stack's config volume are never overwritten.

Optional variables and defaults:

| Variable | Default |
| --- | --- |
| `DNS_PRIMARY` | `1.1.1.1` |
| `DNS_SECONDARY` | `8.8.8.8` |
| `DEV_MEMORY_LIMIT` | `2g` |
| `DEV_CPU_LIMIT` | `2.0` |
| `DIND_MEMORY_LIMIT` | `3g` |
| `DIND_CPU_LIMIT` | `6.0` |
| `T3CODE_LOG_LEVEL` | `Info` |
| `TZ` | `Asia/Tokyo` |

Do not deploy while `compose.yml` still references `ghcr.io/example` or the
all-zero digest.

## Account onboarding

Open a shell from T3 Code or the Portainer console in each `t3-code` service.
Create and register a different SSH key for each account:

```sh
ssh-keygen -t ed25519 -C "account@example.com"
cat ~/.ssh/id_ed25519.pub
ssh -T git@github.com
```

The private key remains in that stack's `ssh_data` volume. GitHub host keys
are pinned system-wide in the image. Use `gh auth login` separately in each
stack when GitHub API access is needed. OpenCode/provider logins are also done
separately and remain in the stack-specific config and data volumes.

## Connecting

T3 Code is only published on the Umbrel host loopback interface. Example SSH
tunnels:

```sh
# Work T3 Code and the first work preview port
ssh -N \
  -L 3773:127.0.0.1:3773 \
  -L 3000:127.0.0.1:31000 \
  umbrel@umbrel

# Personal T3 Code and the first personal preview port
ssh -N \
  -L 3774:127.0.0.1:3774 \
  -L 3001:127.0.0.1:32000 \
  umbrel@umbrel
```

Use T3 Code's normal pairing flow after opening the tunnel. No static T3 auth
token is stored in Compose.

## Project Compose convention

Both the development container and its DinD sidecar mount the same named
volume at `/workspace`. Relative project bind mounts therefore resolve to the
same files from both sides.

Project services that need remote access must publish into DinD ports
`30000-30049`. For example:

```yaml
services:
  app:
    ports:
      - "30000:3000"
    user: "1000:1000"
```

The work stack maps inner `30000` to host loopback `31000`; the personal stack
maps it to `32000`. Increment both sides for additional services. The SSH
tunnel then maps the selected host-loopback port to any free local port.

Run project containers that write the workspace as UID/GID 1000 whenever
possible. The development image intentionally has no sudo and runs with
`no-new-privileges`. If a project creates root-owned files, use a one-time root
console from Portainer to repair ownership rather than weakening the image.

## Persistence and backup

Each stack creates independent named volumes for:

- T3 Code state
- OpenCode state
- user, Git, GitHub CLI, and Docker CLI configuration
- npm download cache
- SSH keys
- workspace files
- DinD data
- DinD CA and client certificates

Back up the application state, user configuration, SSH keys, and workspace.
Treat the npm cache and DinD data as rebuildable caches, and do not copy raw
`/var/lib/docker` while the daemon is running. Projects with durable development
databases should define their own consistent dump and restore procedure.

## Migration from the Web Editor stack

Keep the existing `t3-code` stack unchanged until the new image workflow and
personal stack have passed their acceptance checks. The old stack currently
owns host port `3773`, so stop it before starting the new work stack.

For the safest migration:

1. Back up the old `t3-code-data`, `t3-code-opencode-data`,
   `t3-code-user-config`, and `t3-code-workspace` volumes.
2. Deploy the personal stack on `3774` and verify T3, GitHub SSH, OpenCode,
   Docker TLS, Compose build/up/down, bind mounts, DNS, and one preview tunnel.
3. Stop the old stack without deleting its volumes.
4. Deploy the work stack on `3773` and repeat the acceptance checks.
5. Copy only the old state that belongs to the selected account into the new
   purpose-specific volumes while both old and new services are stopped.
6. Retain the old volumes until both new stacks have been used successfully.

Do not copy the old image or container filesystem. All software is rebuilt
from this directory and published through GHCR.
