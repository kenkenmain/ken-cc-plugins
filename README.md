# llm-bridge

Go service that bridges Discord and Terminal interfaces to Claude CLI, enabling multi-channel LLM interaction.

## Features

- **Multi-provider input** -- Connect Discord bots and local terminal simultaneously
- **Input merging** -- Messages from multiple sources merged to LLM stdin with conflict prefixing
- **Output broadcast** -- All LLM output sent to every connected channel
- **Rate limiting** -- Per-user and per-channel token-bucket rate limiting
- **Idle timeout** -- Automatic LLM process shutdown after configurable idle period
- **File attachments** -- Long outputs automatically sent as file attachments

## Prerequisites

- [Bazelisk](https://github.com/bazelbuild/bazelisk) (auto-downloads Bazel 8.5.1)
- Node.js (for Claude CLI runtime)
- Discord bot token ([setup guide](docs/deployment.md#discord-bot-setup))

## Quick Start

### Build and Test

```bash
bazel build //cmd/llm-bridge    # build the binary
bazel test //...                 # run all tests
bazel test //:lint               # run linter
```

### Run Locally

```bash
export DISCORD_BOT_TOKEN=your_token
export ANTHROPIC_API_KEY=your_key
bazel-bin/cmd/llm-bridge/llm-bridge_/llm-bridge serve --config llm-bridge.yaml
```

### Docker

```bash
cp llm-bridge.yaml.example llm-bridge.yaml
# Edit llm-bridge.yaml with your settings
docker-compose up -d
```

See [docs/deployment.md](docs/deployment.md) for systemd, Docker Compose, and Bazel OCI deployment methods.

## Configuration

Copy `llm-bridge.yaml.example` to `llm-bridge.yaml`. Minimal example:

```yaml
repos:
  my-repo:
    provider: discord
    channel_id: "123456789012345678"
    working_dir: /path/to/repo

providers:
  discord:
    bot_token: "${DISCORD_BOT_TOKEN}"
```

All defaults (LLM backend, idle timeout, rate limits, output threshold) are documented in [docs/configuration.md](docs/configuration.md).

## Commands

| Input            | Description                      |
| ---------------- | -------------------------------- |
| `/status`        | Show LLM status and idle time    |
| `/cancel`        | Send SIGINT to LLM               |
| `/restart`       | Restart LLM process              |
| `/select <repo>` | Select repo (terminal only)      |
| `/help`          | Show available commands           |
| `!commit`        | Translates to `/commit` for LLM  |

Bridge commands (`/status`, `/cancel`, `/restart`, `/help`) work in both Discord and terminal contexts. The `/select` command is terminal-only -- it switches which repository the terminal session targets. In Discord, each channel is mapped to a specific repository via the configuration file. The `!` prefix translates to `/` and forwards to the LLM, allowing Discord users to invoke Claude slash commands without conflicting with Discord's own slash command system.

## Architecture

```
cmd/llm-bridge/     Entry point (Cobra CLI)
internal/
  bridge/           Core orchestration, session management, output fanout
  config/           YAML configuration parsing
  llm/              LLM interface, Claude PTY wrapper
  provider/         Discord and Terminal providers
  ratelimit/        Token-bucket rate limiting
  router/           Command routing (/ and ! prefixes)
  output/           Output formatting, file attachments
```

For detailed data flow, concurrency model, and package internals, see [docs/architecture.md](docs/architecture.md).

## CI

GitHub Actions runs on PRs to `main` and pushes to `main`:
- Build, test, and lint
- 90% line-coverage threshold enforcement
- Docker image build verification

## Documentation

| Document | Description |
| --- | --- |
| [docs/architecture.md](docs/architecture.md) | Data flow, package breakdown, concurrency model |
| [docs/configuration.md](docs/configuration.md) | Full YAML schema, defaults, environment variables |
| [docs/deployment.md](docs/deployment.md) | Bare metal, Docker, Bazel OCI deployment guides |
| [CONTRIBUTING.md](CONTRIBUTING.md) | Development setup, testing, code style, PR process |

## License

This project does not yet have a published license. See the repository for updates.
