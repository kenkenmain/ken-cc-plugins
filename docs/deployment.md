# llm-bridge Deployment Guide

This guide covers three deployment methods for llm-bridge, a Go service that bridges Discord (and terminal) to the Claude CLI. Each method has different tradeoffs around packaging, runtime dependencies, and operational complexity.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Discord Bot Setup](#discord-bot-setup)
- [Configuration File](#configuration-file)
- [Method 1: Bare Metal / systemd (Recommended)](#method-1-bare-metal--systemd-recommended)
- [Method 2: Docker / Docker Compose](#method-2-docker--docker-compose)
- [Method 3: Bazel OCI Image](#method-3-bazel-oci-image)
- [Security Considerations](#security-considerations)
- [Monitoring and Logging](#monitoring-and-logging)
- [Troubleshooting](#troubleshooting)

---

## Prerequisites

All deployment methods require the llm-bridge source code and Bazelisk for building. The Go toolchain is managed by Bazel (version 1.23.6, downloaded automatically via `go_sdk.download` in `MODULE.bazel`) -- no local Go installation is needed.

| Requirement | Bare Metal | Docker | Bazel OCI |
|---|---|---|---|
| [Bazelisk](https://github.com/bazelbuild/bazelisk) | Yes | Yes (build step) | Yes |
| Node.js + npm | Yes (for Claude CLI) | No (bundled in image) | No (not bundled) |
| Docker | No | Yes | Yes (for `oci_load`) |
| Claude CLI (`@anthropic-ai/claude-code`) | Yes (host install) | No (bundled in base image) | No (not included) |

Install Bazelisk following the [official instructions](https://github.com/bazelbuild/bazelisk). Bazel version 8.5.1 is pinned by the project and will be downloaded automatically.

---

## Discord Bot Setup

llm-bridge connects to Discord as a bot. You must create a bot application and invite it to your server before deploying.

### 1. Create the Bot Application

1. Go to the [Discord Developer Portal](https://discord.com/developers/applications).
2. Click "New Application" and give it a name.
3. Navigate to the "Bot" tab in the left sidebar.
4. Click "Add Bot" if one is not already created.
5. Copy the bot token. Store it securely; this is your `DISCORD_BOT_TOKEN`.

### 2. Enable Required Intents

Under the "Bot" tab, scroll to "Privileged Gateway Intents" and enable:

- **Message Content Intent** -- required. Without this, the bot cannot read message text. llm-bridge processes raw message content to route commands and forward text to Claude.

Note: Server Members Intent is not required by llm-bridge. The code only registers `GuildMessages`, `DirectMessages`, and `MessageContent` intents.

The code in `internal/provider/discord.go` registers these intents:

```go
d.session.Identify.Intents = discordgo.IntentsGuildMessages |
    discordgo.IntentsDirectMessages |
    discordgo.IntentMessageContent
```

This means the bot needs:

- **GuildMessages** -- receive messages in server channels.
- **DirectMessages** -- receive direct messages to the bot.
- **MessageContent** -- access the text content of messages (privileged intent, must be enabled in the portal).

### 3. Invite the Bot to Your Server

1. Navigate to the "OAuth2" tab, then "URL Generator".
2. Select the `bot` scope.
3. Under "Bot Permissions", select at minimum:
   - Send Messages
   - Read Message History
   - Attach Files (required for long output, which llm-bridge sends as file attachments when content exceeds the output threshold)
4. Copy the generated URL and open it in a browser to invite the bot.

### 4. Get Channel IDs

Enable Developer Mode in Discord (User Settings > Advanced > Developer Mode). Right-click a channel and select "Copy Channel ID". You will need these IDs for the configuration file.

---

## Configuration File

llm-bridge reads its configuration from a YAML file. The default path is `llm-bridge.yaml` in the working directory, overridable with `--config`. Environment variables are expanded using `os.ExpandEnv`, so you can reference `${VAR_NAME}` in the YAML.

Full configuration example:

```yaml
repos:
  my-project:
    provider: discord
    channel_id: "123456789012345678"
    llm: claude
    working_dir: /home/deploy/repos/my-project

  another-repo:
    provider: discord
    channel_id: "987654321098765432"
    llm: claude
    working_dir: /home/deploy/repos/another-repo

defaults:
  llm: claude               # Only "claude" backend is supported
  claude_path: claude        # Path to Claude CLI binary (default: "claude")
  output_threshold: 1500     # Characters before output is sent as a file attachment
  idle_timeout: 10m          # Duration before idle LLM sessions are stopped
  resume_session: true       # Pass --resume flag to Claude CLI
  rate_limit:
    enabled: true            # Enable per-user and per-channel rate limiting
    user_rate: 0.5           # Messages per second per user (0.5 = 1 msg every 2s)
    user_burst: 3            # Burst capacity per user
    channel_rate: 2.0        # Messages per second per channel
    channel_burst: 10        # Burst capacity per channel

providers:
  discord:
    bot_token: ${DISCORD_BOT_TOKEN}
```

Key configuration details from `internal/config/config.go`:

- `idle_timeout` accepts any Go duration string (e.g., `5m`, `1h`, `30s`). Default is `10m`.
- `resume_session` defaults to `true` when not set. This passes `--resume` to Claude CLI, allowing sessions to persist across restarts.
- `output_threshold` defaults to `1500`. Output exceeding this length is sent as a Markdown file attachment rather than inline text.
- Rate limit values default to: user_rate=0.5, user_burst=3, channel_rate=2.0, channel_burst=10. Rate limiting is enabled by default.
- The `bot_token` field supports environment variable expansion via `${DISCORD_BOT_TOKEN}`.

---

## Method 1: Bare Metal / systemd (Recommended)

This is the simplest deployment method and is recommended for servers you control. The Go binary is statically linked (`pure = "on"`, `static = "on"` in `cmd/llm-bridge/BUILD.bazel`), so it has no runtime library dependencies. The only external runtime dependency is the Claude CLI, which is a Node.js application.

### Prerequisites

1. Install Bazelisk.
2. Install Node.js (LTS version recommended).
3. Install the Claude CLI globally:

```bash
npm install -g @anthropic-ai/claude-code
```

4. Verify the Claude CLI is available:

```bash
claude --version
```

### Build

```bash
bazel build //cmd/llm-bridge
```

The binary is output to `bazel-bin/cmd/llm-bridge/llm-bridge_/llm-bridge`. Copy it to a standard location:

```bash
sudo cp -L bazel-bin/cmd/llm-bridge/llm-bridge_/llm-bridge /usr/local/bin/llm-bridge
```

### Manual Run (Testing)

```bash
export DISCORD_BOT_TOKEN=your_token_here
export ANTHROPIC_API_KEY=your_key_here
llm-bridge serve --config /path/to/llm-bridge.yaml
```

The `ANTHROPIC_API_KEY` environment variable is required by the Claude CLI at runtime. The bridge inherits the full environment (`os.Environ()`) when spawning Claude processes, as seen in `internal/llm/claude.go`.

### systemd Service

Create a dedicated service user:

```bash
sudo useradd --system --no-create-home --shell /usr/sbin/nologin llm-bridge
```

Create the configuration directory and file:

```bash
sudo mkdir -p /etc/llm-bridge
sudo cp llm-bridge.yaml /etc/llm-bridge/llm-bridge.yaml
sudo chmod 600 /etc/llm-bridge/llm-bridge.yaml
sudo chown llm-bridge:llm-bridge /etc/llm-bridge/llm-bridge.yaml
```

Create the systemd unit file at `/etc/systemd/system/llm-bridge.service`:

```ini
[Unit]
Description=llm-bridge
After=network.target

[Service]
ExecStart=/usr/local/bin/llm-bridge serve --config /etc/llm-bridge/llm-bridge.yaml
Environment=DISCORD_BOT_TOKEN=xxx
Environment=ANTHROPIC_API_KEY=xxx
Restart=always
User=llm-bridge

[Install]
WantedBy=multi-user.target
```

For sensitive tokens, use a systemd environment file instead of inline `Environment=` directives:

```ini
[Service]
EnvironmentFile=/etc/llm-bridge/env
```

Where `/etc/llm-bridge/env` contains:

```
DISCORD_BOT_TOKEN=your_token_here
ANTHROPIC_API_KEY=your_key_here
```

Restrict permissions on the environment file:

```bash
sudo chmod 600 /etc/llm-bridge/env
sudo chown llm-bridge:llm-bridge /etc/llm-bridge/env
```

Enable and start the service:

```bash
sudo systemctl daemon-reload
sudo systemctl enable llm-bridge
sudo systemctl start llm-bridge
```

### Log Management via journald

llm-bridge uses Go's `log/slog` package with a text handler writing to stderr. systemd captures stderr and routes it to journald automatically.

View logs:

```bash
# Follow live logs
journalctl -u llm-bridge -f

# View recent logs
journalctl -u llm-bridge --since "1 hour ago"

# View logs with priority filtering
journalctl -u llm-bridge -p warning
```

Structured log fields include `config`, `repo`, `llm`, `dir`, `channels`, `error`, `user`, `author_id`, `channel`, and `idle` depending on the log event.

---

## Method 2: Docker / Docker Compose

Docker bundles Node.js, the Claude CLI, and the Go binary into a single deployable image. This is useful when you want a self-contained artifact without managing Node.js on the host. The build uses a two-stage approach.

### Two-Stage Build Process

**Stage 1: Base image** (`Dockerfile.base`) -- builds once, changes rarely:

```dockerfile
FROM alpine:3.19

RUN apk add --no-cache \
    ca-certificates \
    nodejs \
    npm \
    bash \
    git

RUN npm install -g @anthropic-ai/claude-code
RUN mkdir -p /etc/llm-bridge
```

This image contains the Node.js runtime and Claude CLI. It only needs rebuilding when you want to update the Claude CLI version.

**Stage 2: Production image** (`Dockerfile`) -- builds on each deploy:

```dockerfile
FROM llm-bridge-base:latest
COPY .build/llm-bridge /usr/local/bin/llm-bridge
ENV LLM_BRIDGE_CONFIG=/etc/llm-bridge/llm-bridge.yaml
ENTRYPOINT ["llm-bridge"]
CMD ["serve", "--config", "/etc/llm-bridge/llm-bridge.yaml"]
```

### Build Steps

Build everything with Make:

```bash
make docker
```

Or manually step by step:

```bash
# 1. Build the base image (once, or when updating Claude CLI)
docker build -f Dockerfile.base -t llm-bridge-base:latest .

# 2. Build the Go binary with Bazel
bazel build //cmd/llm-bridge

# 3. Stage the binary for Docker COPY
mkdir -p .build
cp -L bazel-bin/cmd/llm-bridge/llm-bridge_/llm-bridge .build/llm-bridge

# 4. Build the production image
docker build -t llm-bridge:latest .
```

### Docker Compose

The project includes a `docker-compose.yml`:

```yaml
version: '3.8'

services:
  llm-bridge:
    build: .
    container_name: llm-bridge
    restart: unless-stopped
    environment:
      - DISCORD_BOT_TOKEN=${DISCORD_BOT_TOKEN}
    volumes:
      # Config file (read-only)
      - ./llm-bridge.yaml:/etc/llm-bridge/llm-bridge.yaml:ro
      # Mount repo directories for Claude to access
      - /root/projects:/root/projects
      # Persist Claude session data across restarts
      - claude-data:/root/.claude
    stdin_open: true
    tty: true

volumes:
  claude-data:
```

### Volume Mounts

Three volume mounts are required:

1. **Config file** (`./llm-bridge.yaml:/etc/llm-bridge/llm-bridge.yaml:ro`) -- the YAML configuration. Mounted read-only.

2. **Repository directories** (`/root/projects:/root/projects`) -- Claude needs access to the actual code repositories it will work on. The paths in the container must match the `working_dir` values in your config. Adjust the host path to match where your repos live.

3. **Claude session data** (`claude-data:/root/.claude`) -- a named Docker volume that persists Claude CLI session state (conversation history, resume data) across container restarts. Without this volume, every restart creates a new Claude session.

### Running

```bash
# Set the bot token in the environment
export DISCORD_BOT_TOKEN=your_token_here

# Start in detached mode
docker compose up -d

# View logs
docker compose logs -f

# Stop
docker compose down
```

### Adding ANTHROPIC_API_KEY

The default `docker-compose.yml` passes `DISCORD_BOT_TOKEN` but not `ANTHROPIC_API_KEY`. Add it to the environment section:

```yaml
environment:
  - DISCORD_BOT_TOKEN=${DISCORD_BOT_TOKEN}
  - ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
```

Or use an `.env` file in the same directory as `docker-compose.yml`:

```
DISCORD_BOT_TOKEN=your_token_here
ANTHROPIC_API_KEY=your_key_here
```

---

## Method 3: Bazel OCI Image

The Bazel OCI target (`//:image`) produces a minimal Alpine-based image containing only the statically-linked Go binary. It does not include Node.js or the Claude CLI.

### When to Use

Use this method when:

- You are running llm-bridge in a context where Claude CLI is provided externally (e.g., mounted from the host, sidecar container).
- You want the smallest possible image for testing or CI verification.
- You need a pure Go deployment and will configure `claude_path` to point to a separately-managed Claude CLI installation.

For most production deployments with Claude, use [Method 2 (Docker)](#method-2-docker--docker-compose) instead, which bundles the Claude CLI runtime.

### Build and Load

```bash
# Build the OCI image and load it into the local Docker daemon
make image
```

This runs two Bazel targets:

```bash
bazel build //:image       # Build the OCI image layers
bazel run //:image_load    # Load into Docker as llm-bridge:dev
```

The image definition in the root `BUILD.bazel`:

```python
oci_image(
    name = "image",
    base = "@alpine",
    cmd = ["serve", "--config", "/etc/llm-bridge/llm-bridge.yaml"],
    entrypoint = ["/usr/local/bin/llm-bridge"],
    tars = [":binary_layer"],
)
```

The Alpine base image is pinned by digest in `MODULE.bazel` for reproducibility.

### Running

```bash
docker run -d \
  --name llm-bridge \
  -e DISCORD_BOT_TOKEN=your_token \
  -e ANTHROPIC_API_KEY=your_key \
  -v /path/to/llm-bridge.yaml:/etc/llm-bridge/llm-bridge.yaml:ro \
  -v /path/to/repos:/path/to/repos \
  llm-bridge:dev
```

Note: Without the Claude CLI available inside the container, llm-bridge will fail to spawn Claude processes. You must either mount the Claude CLI binary into the container or ensure it is accessible at the path specified by `claude_path` in the config.

---

## Security Considerations

### Token Management

- **DISCORD_BOT_TOKEN**: Grants full control of the bot. Never commit this to source control. Use environment variables, systemd `EnvironmentFile`, or Docker `.env` files.
- **ANTHROPIC_API_KEY**: Required by the Claude CLI. Same handling as the bot token. The config file supports `${VAR}` expansion (via `os.ExpandEnv` in `internal/config/config.go`), so tokens can be injected from the environment rather than stored in the YAML file.
- Set file permissions to `600` on any file containing tokens (`llm-bridge.yaml` if it contains inline tokens, environment files, `.env` files).

### Working Directory Access

Each repo in the config specifies a `working_dir` where Claude will operate. Claude is spawned as a child process (`internal/llm/claude.go`) in that directory with access to the host environment. Be aware:

- Claude can read and modify any files in the working directory and its subdirectories.
- The process inherits the full environment of the llm-bridge process (`c.cmd.Env = os.Environ()`).
- In Docker, the working directories must be bind-mounted into the container. Only mount directories that Claude should have access to.
- The project TODO list in `CLAUDE.md` notes a planned improvement for path allowlisting -- validating `working_dir` against an allowlist of base paths before spawning Claude.

### Rate Limiting for Public-Facing Deployments

Rate limiting is enabled by default and is critical for any deployment where Discord users outside your immediate team can send messages to the bot. The rate limiter uses a per-key token bucket algorithm (`internal/ratelimit/limiter.go`, backed by `golang.org/x/time/rate`).

Default limits:

| Scope | Rate | Burst |
|---|---|---|
| Per user | 0.5 msg/sec (1 message every 2 seconds) | 3 |
| Per channel | 2.0 msg/sec | 10 |

For public-facing deployments, consider tightening these values:

```yaml
defaults:
  rate_limit:
    enabled: true
    user_rate: 0.2      # 1 message every 5 seconds
    user_burst: 2
    channel_rate: 1.0
    channel_burst: 5
```

Terminal messages (which have an empty `AuthorID`) are not subject to per-user rate limiting but are subject to per-channel limits.

### Process Isolation

- Run the service as a dedicated non-root user (the systemd example uses `User=llm-bridge`).
- In Docker, the container runs processes as root by default. Consider adding a `USER` directive or running with `--user`.
- Claude is spawned via PTY (`creack/pty`) -- it has full terminal capabilities within its working directory.

---

## Monitoring and Logging

### Structured Logging

llm-bridge uses Go's `log/slog` package with a text handler. All log output goes to stderr. The logger is initialized in `cmd/llm-bridge/main.go`:

```go
slog.SetDefault(slog.New(slog.NewTextHandler(os.Stderr, &slog.HandlerOptions{
    Level: slog.LevelInfo,
})))
```

Key log events and their fields:

| Event | Level | Fields |
|---|---|---|
| Bridge starting | Info | `config` |
| Discord provider started | Info | `channels` (count) |
| Terminal provider started | Info | (none) |
| LLM session started | Info | `repo`, `llm`, `dir` |
| LLM output ended | Info | `repo`, optionally `error` |
| Idle LLM stopped | Info | `repo`, `idle` (duration) |
| Rate limited (user) | Warn | `user`, `author_id`, `channel` |
| Rate limited (channel) | Warn | `channel` |
| Session creation failed | Error | `error`, `repo` |
| Send to LLM failed | Error | `error`, `repo` |
| Broadcast failed | Error | `error`, `provider` |
| Shutdown initiated | Info | (none) |

### Idle Timeout Behavior

The bridge runs an idle timeout loop (`internal/bridge/bridge.go`, `idleTimeoutLoop`) that checks every minute for LLM sessions that have been idle longer than the configured `idle_timeout` (default: 10 minutes). When an idle session is detected:

1. The LLM process is stopped (SIGTERM, then kill if needed).
2. The session context is cancelled.
3. All connected channels receive a notification: "LLM stopped due to idle timeout (10m0s)".
4. The session is removed from the active sessions map.

The next message to that repo's channel will spawn a new Claude process. If `resume_session` is true (the default), Claude will attempt to resume the previous conversation.

### Graceful Shutdown

llm-bridge handles SIGINT and SIGTERM signals (`cmd/llm-bridge/main.go`):

```go
sigCh := make(chan os.Signal, 1)
signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
go func() {
    <-sigCh
    slog.Info("shutting down")
    cancel()
}()
```

On receiving either signal:

1. The root context is cancelled.
2. The bridge `Stop()` method runs, which iterates all active repo sessions and calls `llm.Stop()` (sends SIGTERM to each Claude process) and cancels each session context.
3. All providers are stopped (Discord session closed, terminal provider stopped).
4. The process exits cleanly.

For systemd, `Restart=always` will restart the service after shutdown. The default systemd stop timeout (90 seconds) is generally sufficient. If Claude processes take longer to terminate, increase it:

```ini
[Service]
TimeoutStopSec=120
```

---

## Troubleshooting

**"claude: command not found" at runtime**

The Claude CLI is not in the PATH. For bare metal, install with `npm install -g @anthropic-ai/claude-code`. For Docker, rebuild the base image. Alternatively, set `claude_path` in the config to the absolute path of the Claude CLI binary.

**Bot connects but does not respond to messages**

Check that the Message Content Intent is enabled in the Discord Developer Portal. Without it, the bot receives message events but the content field is empty. Also verify the channel IDs in the config match the channels where you are sending messages.

**"Rate limited" messages appearing frequently**

The default rate limits are conservative. Adjust `user_rate`, `user_burst`, `channel_rate`, and `channel_burst` in the config. Set `enabled: false` under `rate_limit` to disable entirely (not recommended for public deployments).

**LLM sessions stopping unexpectedly**

Check the idle timeout setting. The default is 10 minutes. If Claude is processing a long task silently (no output), the idle timer may expire. Increase `idle_timeout` in the config:

```yaml
defaults:
  idle_timeout: 30m
```

**Docker: Claude cannot access repository files**

Ensure the repository directories are bind-mounted into the container and the paths match the `working_dir` values in the config. The paths inside the container must be identical to the paths referenced in the YAML.

**"parse config" or "read config" errors at startup**

The configuration file could not be read or parsed. Check that the `--config` path is correct and the file is valid YAML. If you use environment variable expansion (`${VAR}`), note that unset variables expand to empty strings silently, which may produce invalid YAML structure. Run `cat llm-bridge.yaml | envsubst` to preview the expanded file.

**ANTHROPIC_API_KEY not set / Claude authentication errors**

The Claude CLI requires `ANTHROPIC_API_KEY` in the environment. llm-bridge passes its full environment to the spawned Claude process. If the key is missing, Claude will fail when the first message triggers session creation. For systemd, add it to `EnvironmentFile`. For Docker, add it to the `environment` section or `.env` file.

**Bridge starts but Discord messages are not received**

Verify the bot has been invited to the server and has permissions to read messages in the configured channels. Check that the channel IDs in your config exactly match the Discord channel snowflake IDs (enable Developer Mode in Discord to copy channel IDs). Also ensure the bot is not being blocked by Discord server permissions or role hierarchy.

**"create llm" or "start llm" errors in logs**

The LLM factory failed to create or start a Claude process. Check that `claude_path` points to a valid Claude CLI binary. If using the default value (`"claude"`), ensure the binary is in the system `PATH` for the user running llm-bridge. For Docker deployments, verify the base image includes the Claude CLI.

**High memory usage over time**

Each active LLM session holds a PTY file descriptor and associated buffers. The rate limiter also creates per-key entries that are never cleaned up. If many unique users or channels interact with the bot, the limiter map grows unboundedly. Restart the service periodically if this becomes an issue, or reduce `idle_timeout` to clean up sessions more aggressively.
