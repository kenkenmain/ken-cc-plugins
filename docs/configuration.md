# Configuration Reference

llm-bridge is configured through a single YAML file. This document describes every configuration field, its type, default value, and behavior. All information is derived from the source code in `internal/config/config.go`.

## Configuration File Path

The configuration file path is specified via the `--config` CLI flag on any command:

```
llm-bridge serve --config /etc/llm-bridge/llm-bridge.yaml
llm-bridge add-repo myrepo --config ./custom-config.yaml
```

The default value is `llm-bridge.yaml` in the current working directory, as defined by `config.DefaultPath()` which returns `filepath.Join(".", "llm-bridge.yaml")`.

## Environment Variable Expansion

Before YAML parsing, the entire configuration file contents are passed through Go's `os.ExpandEnv`. This means any `${VAR}` or `$VAR` reference in YAML values is replaced with the corresponding environment variable value. This expansion occurs at load time in `config.Load()` (line 124 of `config.go`).

Example:

```yaml
providers:
  discord:
    bot_token: "${DISCORD_BOT_TOKEN}"
```

If `DISCORD_BOT_TOKEN=xyzzy123` is set in the environment, the parsed value of `bot_token` will be `xyzzy123`.

**Warning:** Unset environment variables expand to empty strings silently. There is no error raised for missing variables -- the YAML will parse with the empty value in place. This means that if `DISCORD_BOT_TOKEN` is not set in the environment, `bot_token` will be an empty string, and the Discord provider will fail at runtime when it attempts to authenticate. Similarly, if `ANTHROPIC_API_KEY` is unset, the Claude CLI will fail when llm-bridge attempts to spawn it. Always verify that required environment variables are set before starting the service.

## Required Environment Variables

These are not read directly by the configuration loader, but are required at runtime by the systems that consume config values:

| Variable             | Required By         | Description                                     |
|----------------------|---------------------|-------------------------------------------------|
| `DISCORD_BOT_TOKEN`  | Discord provider    | Authentication token for the Discord bot. Typically injected into the config file via `${DISCORD_BOT_TOKEN}` syntax. |
| `ANTHROPIC_API_KEY`   | Claude CLI          | API key consumed by the Claude CLI process that llm-bridge spawns. Not referenced in config structs, but required in the process environment. |

## YAML Schema

The top-level configuration file maps to the `Config` struct:

```yaml
repos:       # map[string]RepoConfig
defaults:    # Defaults
providers:   # ProviderConfigs
```

### Top-Level: `Config`

Source: `internal/config/config.go` -- `type Config struct`

| Field       | YAML Key     | Go Type                     | Required | Description                              |
|-------------|--------------|-----------------------------|----------|------------------------------------------|
| `Repos`     | `repos`      | `map[string]RepoConfig`    | No       | Map of repository names to their configurations. Each key is a repository identifier used internally. |
| `Defaults`  | `defaults`   | `Defaults`                  | No       | Global default settings applied across all repositories. |
| `Providers` | `providers`  | `ProviderConfigs`           | No       | Chat provider credentials and settings.  |

---

### `RepoConfig`

Source: `internal/config/config.go` -- `type RepoConfig struct`

Defines the configuration for a single repository bridge.

Note: "Required" below means the field is required for correct operation. The configuration loader does not validate these fields -- missing values will cause runtime errors when the bridge attempts to use them (e.g., empty `channel_id` means messages will not be routed; empty `working_dir` means Claude spawns in the bridge's working directory).

| Field        | YAML Key      | Go Type  | Required | Default | Description                                                           |
|--------------|---------------|----------|----------|---------|-----------------------------------------------------------------------|
| `Provider`   | `provider`    | `string` | Yes      | --      | Chat provider for this repo. Currently supported: `"discord"`.        |
| `ChannelID`  | `channel_id`  | `string` | Yes      | --      | Provider-specific channel identifier. For Discord, this is the numeric channel snowflake ID (quoted as a string in YAML). |
| `LLM`        | `llm`         | `string` | No       | --      | LLM backend for this repo. Overrides `defaults.llm` for this specific repo. Currently only `"claude"` is implemented. |
| `WorkingDir` | `working_dir` | `string` | Yes      | --      | Filesystem path to the repository working directory. Both absolute and relative paths are accepted; relative paths are resolved relative to the bridge process's working directory. The Claude CLI process is spawned with this as its `cmd.Dir`. |

Example:

```yaml
repos:
  notification-hooks:
    provider: discord
    channel_id: "123456789012345678"
    llm: claude
    working_dir: /home/user/projects/notification-hooks
```

---

### `Defaults`

Source: `internal/config/config.go` -- `type Defaults struct`

Global defaults applied when per-repo overrides are not set. Default values are applied in `config.Load()` after YAML unmarshalling.

| Field             | YAML Key           | Go Type          | Default   | Description                                                         |
|-------------------|--------------------|------------------|-----------|---------------------------------------------------------------------|
| `LLM`             | `llm`              | `string`         | `"claude"` | Default LLM backend. Applied in `Load()` when the value is empty. Setting this to any value other than `"claude"` or `""` will cause an error at session creation time (the LLM factory only supports `"claude"`). |
| `ClaudePath`      | `claude_path`      | `string`         | `"claude"` | Filesystem path or command name for the Claude CLI binary. Default applied via `GetClaudePath()` method when the value is empty. If the path is invalid or the binary is not found, the error occurs at session creation when the PTY process fails to start. |
| `OutputThreshold` | `output_threshold` | `int`            | `1500`    | Character count threshold for LLM output. When output exceeds this length, the bridge handles it differently (e.g., sending as a file attachment). Applied in `Load()` when the value is `0`. Negative values are treated as `0` by the output handler, which then applies the default of `1500`. |
| `IdleTimeout`     | `idle_timeout`     | `string`         | `"10m"`   | Duration string (parsed by Go's `time.ParseDuration`) specifying how long a session can remain idle before cleanup. Applied in `Load()` when the value is empty. Parsed at runtime via `GetIdleTimeoutDuration()`, which falls back to 10 minutes if the string is invalid or cannot be parsed. Valid format examples: `"5m"`, `"1h"`, `"30s"`, `"1h30m"`. |
| `ResumeSession`   | `resume_session`   | `*bool` (pointer) | `true`   | Whether to resume existing Claude CLI sessions. Uses a pointer type to distinguish between "not set" and "explicitly false". Default applied via `GetResumeSession()` method when the pointer is nil. |
| `RateLimit`       | `rate_limit`       | `RateLimitConfig` | (see below) | Nested rate limiting configuration.                              |

Example:

```yaml
defaults:
  llm: claude
  claude_path: /usr/local/bin/claude
  output_threshold: 2000
  idle_timeout: 15m
  resume_session: false
  rate_limit:
    # ...
```

#### Default Application Methods

The `Defaults` struct uses two patterns for applying defaults:

1. **In `Load()`**: `LLM`, `OutputThreshold`, and `IdleTimeout` are set directly on the struct after unmarshalling if their zero-values are detected.

2. **Via getter methods**: `ClaudePath` and `ResumeSession` use getter methods (`GetClaudePath()`, `GetResumeSession()`) that return defaults when the field is empty or nil. This allows distinguishing "not configured" from "explicitly set to zero value" -- particularly important for `ResumeSession` where the pointer-to-bool pattern differentiates nil (use default true) from explicit false.

---

### `RateLimitConfig`

Source: `internal/config/config.go` -- `type RateLimitConfig struct`

Configures per-user and per-channel message rate limiting using a token bucket algorithm. All defaults are applied via getter methods on the struct, not in `Load()`.

| Field          | YAML Key        | Go Type   | Default | Description                                                     |
|----------------|-----------------|-----------|---------|-----------------------------------------------------------------|
| `Enabled`      | `enabled`       | `*bool`   | `true`  | Enable or disable rate limiting globally. Pointer type allows distinguishing "not set" (defaults to true) from "explicitly false". Accessed via `GetRateLimitEnabled()`. |
| `UserRate`     | `user_rate`     | `float64` | `0.5`   | Maximum sustained message rate per user, in messages per second. A value of `0.5` means one message every 2 seconds. Accessed via `GetUserRate()`. Default applied when value is `0`. |
| `UserBurst`    | `user_burst`    | `int`     | `3`     | Token bucket burst capacity per user. Allows this many rapid messages before rate limiting kicks in. Accessed via `GetUserBurst()`. Default applied when value is `0`. |
| `ChannelRate`  | `channel_rate`  | `float64` | `2.0`   | Maximum sustained message rate per channel, in messages per second. Accessed via `GetChannelRate()`. Default applied when value is `0`. |
| `ChannelBurst` | `channel_burst` | `int`     | `10`    | Token bucket burst capacity per channel. Accessed via `GetChannelBurst()`. Default applied when value is `0`. |

Example:

```yaml
defaults:
  rate_limit:
    enabled: true
    user_rate: 0.5
    user_burst: 3
    channel_rate: 2.0
    channel_burst: 10
```

To disable rate limiting entirely:

```yaml
defaults:
  rate_limit:
    enabled: false
```

---

### `ProviderConfigs`

Source: `internal/config/config.go` -- `type ProviderConfigs struct`

Container for chat provider configurations.

| Field     | YAML Key  | Go Type         | Required | Description                    |
|-----------|-----------|-----------------|----------|--------------------------------|
| `Discord` | `discord` | `DiscordConfig` | No       | Discord bot provider settings. |

---

### `DiscordConfig`

Source: `internal/config/config.go` -- `type DiscordConfig struct`

| Field      | YAML Key    | Go Type  | Required | Description                                              |
|------------|-------------|----------|----------|----------------------------------------------------------|
| `BotToken` | `bot_token` | `string` | Yes      | Discord bot authentication token. Should use environment variable expansion (e.g., `"${DISCORD_BOT_TOKEN}"`) to avoid storing secrets in the config file. |

---

## Complete Annotated Example

The following example shows every configuration field with comments explaining the purpose and default values. This mirrors the structure of the example file `llm-bridge.yaml.example` in the source repository, extended with all available fields.

```yaml
# llm-bridge.yaml
# Full configuration reference
# Copy this file and customize for your deployment.

# Repository definitions
# Each key is an arbitrary name used to identify the repo internally.
repos:
  notification-hooks:
    provider: discord                          # Chat provider (currently: "discord")
    channel_id: "123456789012345678"           # Discord channel snowflake ID (string)
    llm: claude                                # LLM backend (currently: "claude" only)
    working_dir: /home/user/projects/notif     # Absolute path to repo working directory

  api-server:
    provider: discord
    channel_id: "987654321098765432"
    llm: claude
    working_dir: /home/user/projects/api

# Global defaults
# These apply unless overridden at the per-repo level.
defaults:
  # Default LLM backend. Only "claude" is currently implemented.
  # Default: "claude"
  llm: claude

  # Path to the Claude CLI binary. Can be a bare command name (resolved via
  # $PATH) or an absolute path. Used when spawning Claude processes.
  # Default: "claude"
  claude_path: claude

  # Character threshold for LLM output. Responses longer than this are
  # handled differently by the output subsystem (e.g., sent as file
  # attachments in Discord rather than inline messages).
  # Default: 1500
  output_threshold: 1500

  # Idle timeout for LLM sessions. After this duration with no activity,
  # the session is cleaned up. Accepts any Go time.Duration string:
  # "30s", "5m", "1h", "1h30m", etc.
  # Default: "10m"
  idle_timeout: 10m

  # Whether to resume existing Claude CLI sessions on reconnect.
  # When true, the bridge attempts to reattach to a previous session
  # rather than starting fresh.
  # Default: true
  resume_session: true

  # Rate limiting configuration (token bucket algorithm)
  rate_limit:
    # Master switch for rate limiting. Set to false to disable all
    # rate limit checks.
    # Default: true
    enabled: true

    # Per-user sustained rate in messages per second.
    # 0.5 = one message every 2 seconds.
    # Default: 0.5
    user_rate: 0.5

    # Per-user burst capacity. Allows this many messages in rapid
    # succession before the sustained rate limit applies.
    # Default: 3
    user_burst: 3

    # Per-channel sustained rate in messages per second.
    # Default: 2.0
    channel_rate: 2.0

    # Per-channel burst capacity.
    # Default: 10
    channel_burst: 10

# Chat provider credentials
providers:
  discord:
    # Discord bot token. Use environment variable expansion to avoid
    # storing secrets directly in the config file.
    bot_token: "${DISCORD_BOT_TOKEN}"
```

## Minimal Configuration

The smallest valid configuration requires only a repo definition and the Discord bot token. All `defaults` fields will use their built-in values:

```yaml
repos:
  my-project:
    provider: discord
    channel_id: "123456789012345678"
    working_dir: /home/user/projects/my-project

providers:
  discord:
    bot_token: "${DISCORD_BOT_TOKEN}"
```

With this configuration, the effective defaults are:

- `defaults.llm`: `"claude"`
- `defaults.claude_path`: `"claude"`
- `defaults.output_threshold`: `1500`
- `defaults.idle_timeout`: `"10m"` (parsed as `10 * time.Minute`)
- `defaults.resume_session`: `true`
- `defaults.rate_limit.enabled`: `true`
- `defaults.rate_limit.user_rate`: `0.5` msg/sec
- `defaults.rate_limit.user_burst`: `3`
- `defaults.rate_limit.channel_rate`: `2.0` msg/sec
- `defaults.rate_limit.channel_burst`: `10`

## Struct Hierarchy

For reference, the full Go struct hierarchy in `internal/config/config.go`:

```
Config
  +-- Repos     map[string]RepoConfig
  |     +-- Provider    string
  |     +-- ChannelID   string
  |     +-- LLM         string
  |     +-- WorkingDir  string
  +-- Defaults  Defaults
  |     +-- LLM              string
  |     +-- ClaudePath       string
  |     +-- OutputThreshold  int
  |     +-- IdleTimeout      string
  |     +-- ResumeSession    *bool
  |     +-- RateLimit        RateLimitConfig
  |           +-- Enabled       *bool
  |           +-- UserRate      float64
  |           +-- UserBurst     int
  |           +-- ChannelRate   float64
  |           +-- ChannelBurst  int
  +-- Providers  ProviderConfigs
        +-- Discord  DiscordConfig
              +-- BotToken  string
```

## Generating Configuration via CLI

The `add-repo` subcommand can create or append to a configuration file:

```
llm-bridge add-repo <name> \
  --provider discord \
  --channel <channel-id> \
  --llm claude \
  --dir /path/to/repo \
  --config llm-bridge.yaml
```

The `--channel` and `--dir` flags are required. The `--provider` flag defaults to `"discord"` and `--llm` defaults to `"claude"`. If the config file does not exist or cannot be loaded, a new `Config` with an empty `Repos` map is created. The repo entry is then marshalled back to YAML and written to the config file path.
