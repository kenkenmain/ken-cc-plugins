# llm-bridge Architecture

## High-Level Overview

llm-bridge is a Go service that bridges chat platforms (Discord, terminal) to LLM CLI tools (currently Claude). It manages per-repository LLM sessions, merges input from multiple sources, and broadcasts output back to all connected channels.

### Data Flow

```
                         +------------------+
                         |   Discord Guild  |
                         |   (per-channel)  |
                         +--------+---------+
                                  |
                    provider.Message (ChannelID, Content, AuthorID)
                                  |
                                  v
+-----------+            +--------+---------+            +--------+
|  Terminal  +----------->                  +------------>        |
|  (stdin)   |  provider |     Bridge       |  llm.Send  | Claude |
|            <-----------+  (router, rate   <------------+ (PTY)  |
+-----------+  broadcast |   limit, merge)  |  Output()  |        |
                         +--------+---------+            +--------+
                                  |
                    broadcastOutput (inline or file attachment)
                                  |
                                  v
                         +--------+---------+
                         |  All connected   |
                         |  channels/terms  |
                         +------------------+
```

### Error Handling

**Startup failures:** If a provider fails to start (e.g., invalid Discord token, WebSocket connection failure), `Bridge.Start` returns an error and the process exits. The Discord provider is only started if `BotToken` is non-empty and at least one channel ID is configured. If the Discord provider fails but the terminal provider succeeds, the bridge does not start -- the Discord error propagates immediately.

**Provider/LLM errors:** Errors during message sending (to providers or the LLM) are logged via `slog.Error` but do not crash the bridge. When `llm.Send` fails, the error is reported back to the originating channel. When `broadcastOutput` fails to send to a provider, it logs the error and continues broadcasting to remaining channels. Session creation errors (`getOrCreateSession`) are reported to the user's channel and logged.

**Cleanup:** On SIGINT/SIGTERM, the root context is cancelled. `Bridge.Stop` iterates all active sessions, calls `llm.Stop()` (SIGTERM, then kill) on each, cancels session contexts, and stops all providers. The idle timeout loop also performs cleanup: idle sessions are collected under the mutex, then stopped and notified outside the lock to avoid blocking other operations.

### Data Flow

1. A `Provider` (Discord or Terminal) receives user input and emits `provider.Message` values on a buffered channel.
2. The `Bridge` reads from each provider's message channel in a dedicated goroutine.
3. The `Router` classifies the message: bridge command (`/`), skill translation (`!`), or plain LLM input.
4. Rate limiting checks per-user and per-channel token buckets. Terminal input (empty `AuthorID`) bypasses user-level limiting.
5. The `Merger` detects multi-source conflicts within a 2-second window and prefixes messages with `[source]` when needed.
6. The `Bridge` calls `getOrCreateSession` to lazily start an LLM process if one is not already running for the target repository.
7. The formatted message is written to the LLM's PTY stdin via `llm.Send`.
8. A `readOutput` goroutine continuously reads the LLM's PTY stdout, buffers lines, and flushes every 500ms or when the buffer exceeds the configured threshold.
9. `broadcastOutput` sends the content to every channel registered to the session -- as inline text if below the threshold, or as a file attachment if above it.

## Package Breakdown

### `cmd/llm-bridge` -- Entry Point

**File:** `cmd/llm-bridge/main.go`

Cobra CLI application with two commands:

- `serve` -- Loads YAML config via `config.Load`, sets up OS signal handling (`SIGINT`/`SIGTERM`), creates a `bridge.Bridge`, and calls `Bridge.Start`.
- `add-repo` -- Appends a repository definition to the YAML config file. Requires `--channel` and `--dir` flags; defaults provider to `discord` and LLM to `claude`.

Logging uses `log/slog` with a text handler writing to stderr at `INFO` level.

### `internal/config` -- Configuration

**File:** `internal/config/config.go`

Parses a YAML configuration file with environment variable expansion (`os.ExpandEnv`).

**Structs:**

| Struct | Fields | Purpose |
|--------|--------|---------|
| `Config` | `Repos`, `Defaults`, `Providers` | Top-level configuration |
| `RepoConfig` | `Provider`, `ChannelID`, `LLM`, `WorkingDir` | Per-repository settings |
| `Defaults` | `LLM`, `ClaudePath`, `OutputThreshold`, `IdleTimeout`, `ResumeSession`, `RateLimit` | Global defaults |
| `RateLimitConfig` | `UserRate`, `UserBurst`, `ChannelRate`, `ChannelBurst`, `Enabled` | Rate limit parameters |
| `ProviderConfigs` | `Discord` | Provider-specific config |
| `DiscordConfig` | `BotToken` | Discord bot token |

**Defaults applied in `Load()` (set on the struct after YAML unmarshalling):**

| Field | Default |
|-------|---------|
| `LLM` | `"claude"` |
| `OutputThreshold` | `1500` (characters) |
| `IdleTimeout` | `"10m"` |

**Defaults applied at use-time via getter methods (not set in `Load()`):**

| Field | Getter Method | Default |
|-------|---------------|---------|
| `ClaudePath` | `GetClaudePath()` | `"claude"` |
| `ResumeSession` | `GetResumeSession()` | `true` |
| `RateLimit.Enabled` | `GetRateLimitEnabled()` | `true` |
| `UserRate` | `GetUserRate()` | `0.5` (1 message every 2 seconds) |
| `UserBurst` | `GetUserBurst()` | `3` |
| `ChannelRate` | `GetChannelRate()` | `2.0` |
| `ChannelBurst` | `GetChannelBurst()` | `10` |

**Public functions:**

- `Load(path string) (*Config, error)` -- Read, expand env vars, unmarshal YAML, apply defaults.
- `DefaultPath() string` -- Returns `"./llm-bridge.yaml"`.
- Getter methods on `Defaults` and `RateLimitConfig` for safe default handling: `GetClaudePath()`, `GetResumeSession()`, `GetIdleTimeoutDuration()`, `GetRateLimitEnabled()`, `GetUserRate()`, `GetUserBurst()`, `GetChannelRate()`, `GetChannelBurst()`.

### `internal/llm` -- LLM Interface and Claude Implementation

#### `internal/llm/llm.go` -- Interface Definition

Defines the `LLM` interface that all LLM backends must implement:

```go
type LLM interface {
    Start(ctx context.Context) error  // Spawn the LLM process
    Stop() error                      // Terminate the LLM process
    Send(msg Message) error           // Write to LLM stdin
    Output() io.Reader                // Reader for LLM stdout
    Running() bool                    // Process status check
    Cancel() error                    // Send SIGINT to the process
    LastActivity() time.Time          // Timestamp of last I/O
    UpdateActivity()                  // Refresh the activity timestamp
    Name() string                     // Backend name (e.g. "claude")
}
```

Also defines `Message` with `Source` (e.g. `"discord"`, `"terminal"`) and `Content` fields.

#### `internal/llm/claude.go` -- Claude PTY Wrapper

The `Claude` struct manages a Claude CLI process spawned inside a pseudo-terminal.

**Struct fields:**

| Field | Type | Purpose |
|-------|------|---------|
| `workingDir` | `string` | `cmd.Dir` for the subprocess |
| `resumeSession` | `bool` | Whether to pass `--resume` flag |
| `claudePath` | `string` | Path to the `claude` binary |
| `cmd` | `*exec.Cmd` | The running subprocess |
| `ptmx` | `*os.File` | PTY master file descriptor |
| `running` | `bool` | Process liveness flag |
| `lastActivity` | `time.Time` | Last I/O timestamp |
| `closeOnce` | `*sync.Once` | Prevents double-close of PTY fd |
| `mu` | `sync.Mutex` | Guards all mutable state |

**Construction** uses functional options: `WithWorkingDir(dir)`, `WithResume(bool)`, `WithClaudePath(path)`.

**Start** (`Claude.Start`):
1. Acquires mutex, checks `running` flag.
2. Builds `exec.Cmd` with optional `--resume` argument.
3. Calls `pty.Start(cmd)` from `github.com/creack/pty` to spawn the process in a PTY.
4. Allocates a new `sync.Once` for this process lifecycle.
5. Captures `ptmx`, `closeOnce`, and `cmd` into local variables to avoid races between old and new process goroutines.
6. Launches a background goroutine that calls `cmd.Wait()`, then sets `running = false` (only if `cmd` has not been replaced) and closes the PTY via the captured `sync.Once`.

**Stop** (`Claude.Stop`):
1. Sends `SIGTERM` to the process.
2. Falls back to `Process.Kill()` if `SIGTERM` fails.
3. Closes the PTY master fd via `sync.Once` to prevent double-close.
4. Sets `running = false`.

**Send** (`Claude.Send`): Writes `msg.Content + "\n"` to the PTY master fd. Updates `lastActivity`.

**Cancel** (`Claude.Cancel`): Sends `SIGINT` to the process (interrupt, not terminate).

**Output** (`Claude.Output`): Returns the PTY master `*os.File` as an `io.Reader`. The same fd is used for both reading and writing; PTY semantics mean writes go to the child's stdin and reads come from the child's stdout.

#### `internal/llm/factory.go` -- Factory

```go
func New(backend, workingDir, claudePath string, resume bool) (LLM, error)
```

Switch on `backend`: `"claude"` or `""` (default) creates a `Claude` instance. Any other value returns an error. This is the `LLMFactory` type used by `Bridge`.

### `internal/provider` -- Chat Providers

#### `internal/provider/provider.go` -- Interface Definition

```go
type Provider interface {
    Name() string                                     // "discord", "terminal"
    Start(ctx context.Context) error                  // Connect to chat service
    Stop() error                                      // Disconnect
    Send(channelID string, content string) error      // Send text to channel
    SendFile(channelID string, filename string, content []byte) error  // Send file
    Messages() <-chan Message                          // Incoming message channel
}
```

`Message` struct carries `ChannelID`, `Content`, `Author` (display name), `AuthorID` (stable unique ID for rate limiting), and `Source` (provider name).

#### `internal/provider/discord.go` -- Discord Provider

The `Discord` struct wraps `github.com/bwmarrin/discordgo`.

- **Construction:** `NewDiscord(token, channelIDs)` builds a channel allowlist map and allocates a buffered message channel (capacity 100).
- **Start:** Creates a `discordgo.Session`, registers `handleMessage` as a callback, sets intents (`GuildMessages`, `DirectMessages`, `MessageContent`), and opens the WebSocket connection.
- **handleMessage:** Filters out bot's own messages and messages from non-allowlisted channels. Constructs a `provider.Message` and sends it to the buffered channel. Drops messages if the channel is full (non-blocking select).
- **Send/SendFile:** Delegates to `discordgo.Session.ChannelMessageSend` and `ChannelFileSend` respectively. `SendFile` wraps the byte slice in a `bytes.NewReader`.
- **Stop:** Uses a `stopped` boolean guarded by mutex to prevent double-close of the messages channel.

#### `internal/provider/terminal.go` -- Terminal Provider

The `Terminal` struct provides local stdin/stdout as a provider.

- **Construction:** `NewTerminal(channelID)` reads from `os.Stdin`, writes to `os.Stdout`, with a buffered message channel (capacity 100).
- **Start:** Spawns a `readLoop` goroutine that uses `bufio.Scanner` to read lines from stdin.
- **Send:** Writes to stdout via `fmt.Fprintln`.
- **SendFile:** Prints file content between `--- filename ---` and `--- end ---` delimiters to stdout.
- **ChannelID():** Extra method not on the `Provider` interface; returns the terminal's fixed channel ID. Used by `Bridge.handleTerminalMessages` for `/select` routing.
- Terminal messages have `Author: "terminal"` and empty `AuthorID`, which means they bypass user-level rate limiting.

#### `internal/provider/mock.go` -- Test Mock

`MockProvider` implements `Provider` for testing. Tracks sent messages and files, supports injecting errors via `SetStartError`/`SetSendError`, and provides `SimulateMessage` for feeding test input.

### `internal/bridge` -- Core Orchestration

#### `internal/bridge/bridge.go` -- Bridge

The central struct that ties everything together.

**Struct fields:**

| Field | Type | Purpose |
|-------|------|---------|
| `cfg` | `*config.Config` | Loaded configuration |
| `providers` | `map[string]provider.Provider` | Active providers by name |
| `repos` | `map[string]*repoSession` | Active LLM sessions by repo name |
| `output` | `*output.Handler` | Output threshold/file logic |
| `discordFactory` | `DiscordFactory` | Creates Discord providers (injectable) |
| `terminalFactory` | `TerminalFactory` | Creates Terminal providers (injectable) |
| `llmFactory` | `LLMFactory` | Creates LLM instances (injectable) |
| `userLimiter` | `*ratelimit.Limiter` | Per-user token bucket |
| `channelLimiter` | `*ratelimit.Limiter` | Per-channel token bucket |
| `mu` | `sync.Mutex` | Guards `repos`, `terminalRepoName` |
| `terminalRepoName` | `string` | Currently selected repo for terminal |

**`repoSession` struct:**

| Field | Type | Purpose |
|-------|------|---------|
| `name` | `string` | Repository name |
| `llm` | `llm.LLM` | The LLM process |
| `channels` | `[]channelRef` | All channels receiving output |
| `cancelCtx` | `context.CancelFunc` | Session context cancellation |
| `merger` | `*Merger` | Per-repo conflict detection |

**Factory types** (`LLMFactory`, `DiscordFactory`, `TerminalFactory`) allow dependency injection for testing.

#### `internal/bridge/merger.go` -- Input Merger

The `Merger` struct detects when multiple sources send messages within a configurable conflict window (default 2 seconds) and prefixes messages with `[source]` to disambiguate for the LLM.

```go
type Merger struct {
    sources     map[string]time.Time  // last activity per source
    conflictWin time.Duration         // default: 2 * time.Second
}
```

**`FormatMessage(source, content string) string`:**
1. Acquires mutex.
2. Cleans up stale entries (sources whose last activity exceeds the conflict window).
3. Checks if any other source has been active within the window (`inConflict`).
4. Records current source's timestamp.
5. If in conflict, returns `"[source] content"`; otherwise returns `content` unmodified.

The `[source]` prefix is only added when a conflict is detected -- that is, when another source has sent a message within the conflict window. This means the first message from a new source arrives unprefixed; only once a second source sends within the window do subsequent messages from all active sources get prefixed. Once the conflict window expires without interleaving activity, messages return to unprefixed passthrough.

### `internal/router` -- Command Routing

**File:** `internal/router/router.go`

Stateless message classification with no dependencies on other internal packages.

```go
type RouteType int
const (
    RouteToLLM    RouteType = iota  // Forward to LLM process
    RouteToBridge                    // Handle as bridge command
)

type Route struct {
    Type    RouteType
    Command string  // e.g. "status", "cancel" (only for RouteToBridge)
    Args    string  // e.g. repo name after "/select"
    Raw     string  // original or translated content
}
```

**`Parse(content string) Route`:**

| Input prefix | Behavior |
|-------------|----------|
| `/` followed by a known bridge command (`status`, `cancel`, `restart`, `help`, `select`) | Returns `RouteToBridge` with parsed command and args |
| `/` followed by an unknown command | Returns `RouteToLLM` with raw content (passed through to LLM) |
| `!` prefix | Translates `!foo` to `/foo` and returns `RouteToLLM` (skill translation) |
| No prefix | Returns `RouteToLLM` with raw content |

Known bridge commands are defined in `BridgeCommands` map: `status`, `cancel`, `restart`, `help`, `select`.

### `internal/output` -- Output Handling

**File:** `internal/output/output.go`

```go
type Handler struct {
    threshold int  // default: 1500 characters
}
```

**`NewHandler(threshold int) *Handler`:** Creates a handler. Defaults threshold to 1500 if non-positive.

**`ShouldAttach(content string) bool`:** Returns `true` if `len(content) > threshold`. Used by `Bridge.broadcastOutput` to decide between inline text and file attachment.

**`FormatFile(content string) (filename string, data []byte)`:** Returns a filename like `"response-150405.md"` (using `time.Now().Format("150405")` for HHMMSS) and the content as bytes.

### `internal/ratelimit` -- Rate Limiting

**File:** `internal/ratelimit/limiter.go`

```go
type Config struct {
    Rate  float64  // tokens per second refill rate
    Burst int      // maximum burst size (bucket capacity)
}

type Limiter struct {
    cfg      Config
    limiters map[string]*rate.Limiter  // per-key token buckets
    mu       sync.Mutex
}
```

Wraps `golang.org/x/time/rate.Limiter` with per-key tracking. Each unique key (user ID or channel ID) gets its own token bucket, lazily created on first `Allow` call.

**`NewLimiter(cfg Config) *Limiter`:** Constructor.

**`Allow(key string) bool`:** Thread-safe check. Creates a `rate.NewLimiter(rate.Limit(cfg.Rate), cfg.Burst)` on first use for the key. Returns the result of `limiter.Allow()`.

**`Reset()`:** Clears all tracked keys (used in tests).

## Session Lifecycle

### Session Creation: `getOrCreateSession`

```
Bridge.handleLLMMessage
  -> repoForChannel(channelID)      -- find repo name from config
  -> getOrCreateSession(ctx, name, repo, provider)
       |
       +-- mu.Lock()
       +-- if session exists and llm.Running(): add channel, return
       +-- llmFactory(backend, workingDir, claudePath, resume)
       +-- llmInstance.Start(sessionCtx)
       +-- create repoSession with NewMerger(2s)
       +-- store in b.repos[repoName]
       +-- go readOutput(session, repoName)
       +-- mu.Unlock(), return session
```

Key details:
- Sessions are keyed by repository name in `Bridge.repos`.
- The mutex is held during the entire check-and-create to prevent duplicate sessions.
- A child context (`sessionCtx`) is derived from the parent bridge context, with its own `cancel` stored in `repoSession.cancelCtx`.
- The `Merger` is created per-session with a 2-second conflict window.
- `readOutput` is launched as a goroutine immediately after session creation.

### Output Reading: `readOutput`

```
readOutput(session, repoName)
  |
  +-- bufio.NewReader(session.llm.Output())
  +-- 500ms ticker
  +-- goroutine: read lines into buffered channel (cap 100)
  +-- select loop:
        case ticker fires: flush buffer via broadcastOutput
        case line received: append to buffer, UpdateActivity
            if buffer > OutputThreshold: flush immediately
        case channel closed: flush remaining, return
```

The 100-element buffered channel between the line-reading goroutine and the select loop prevents PTY backpressure when broadcasting is slow. The 500ms ticker provides batching -- output does not get sent on every single line but accumulates and flushes periodically.

### Idle Timeout: `checkIdleTimeouts`

```
idleTimeoutLoop(ctx)
  |
  +-- 1-minute ticker
  +-- checkIdleTimeouts(timeout)
        |
        +-- mu.Lock()
        +-- collect idle sessions (time.Since(LastActivity) > timeout)
        +-- delete from b.repos
        +-- mu.Unlock()
        +-- for each idle session:
              llm.Stop()
              cancelCtx()
              notify all channels: "LLM stopped due to idle timeout"
```

The two-phase pattern (collect under lock, stop outside lock) avoids blocking message handling and session creation while stopping idle processes.

Default idle timeout is 10 minutes, configurable via `idle_timeout` in YAML.

## Input Merging

The `Merger` in `internal/bridge/merger.go` solves the problem of multiple sources (e.g., Discord and terminal) sending messages to the same LLM session simultaneously.

**Algorithm:**

1. On each `FormatMessage(source, content)` call, clean up sources whose last activity is older than the conflict window.
2. Check if any *other* source has been active within the window.
3. Record the current source's timestamp.
4. If another source was active (conflict detected), prefix: `[discord] fix the bug` or `[terminal] show me the file`.

**Conflict window:** 2 seconds (hardcoded in `getOrCreateSession` via `NewMerger(2 * time.Second)`).

**Behavior:** When only one source is active, messages pass through unmodified. When sources interleave within the window, all messages from all sources get prefixed. This avoids ambiguity where the LLM might not know which user is speaking.

## Command Routing

The `router.Parse` function is stateless and classifies every incoming message into one of two route types.

### Bridge commands (`/`)

`/status`, `/cancel`, `/restart`, `/help`, `/select <repo>` are handled directly by the bridge without forwarding to the LLM. The `/select` command is terminal-specific and switches which repository the terminal session targets.

Bridge command handling in `Bridge.handleBridgeCommand`:

| Command | Action |
|---------|--------|
| `/status` | Reports LLM backend name, running state, repo name, idle duration |
| `/cancel` | Sends `SIGINT` to the LLM process via `llm.Cancel()` |
| `/restart` | Stops the LLM and deletes the session; next message triggers restart |
| `/help` | Returns a static help string listing commands and skills |
| `/select` | Terminal-only: switches `terminalRepoName` |

### Skill translation (`!`)

`!commit` becomes `/commit`, `!review-pr` becomes `/review-pr`, etc. The translated content is forwarded to the LLM as `RouteToLLM`. This allows Discord users to invoke LLM slash commands without conflicting with Discord's own slash command system.

### Plain text

Everything else is forwarded directly to the LLM as `RouteToLLM`.

## Rate Limiting Architecture

Rate limiting uses a two-tier token bucket system built on `golang.org/x/time/rate`.

### Per-user limiting

- **Key:** `msg.AuthorID` (Discord user ID)
- **Default rate:** 0.5 tokens/second (1 message every 2 seconds)
- **Default burst:** 3 (allows 3 rapid messages before throttling)
- **Terminal bypass:** Terminal messages have empty `AuthorID`. The `isRateLimited` method checks `msg.AuthorID != ""` before user-level limiting, so terminal input is never user-rate-limited.

### Per-channel limiting

- **Key:** `msg.ChannelID` (Discord channel ID or terminal channel ID)
- **Default rate:** 2.0 tokens/second
- **Default burst:** 10
- **No bypass:** Channel limiting applies to all sources including terminal.

### Implementation

Both limiters are `*ratelimit.Limiter` instances created in `Bridge.New` if `RateLimit.Enabled` is true (default). Each limiter lazily creates a `rate.Limiter` per key on first `Allow(key)` call. The `isRateLimited` method checks user first, then channel, and sends a rate limit notification back to the provider if either check fails.

Rate limiting is entirely skipped (both `userLimiter` and `channelLimiter` are nil) if `rate_limit.enabled` is set to `false` in config.

## Output Handling

### Threshold-based routing

When `broadcastOutput` fires, it checks `output.Handler.ShouldAttach(content)`:

- **Below threshold** (default 1500 chars): Send as inline text via `provider.Send(channelID, content)`.
- **Above threshold**: Generate a Markdown file via `output.Handler.FormatFile(content)` and send via `provider.SendFile(channelID, filename, data)`.

The filename format is `response-HHMMSS.md` based on `time.Now()`.

### 500ms ticker-based batching

The `readOutput` loop uses a `time.NewTicker(500 * time.Millisecond)` to batch output:

1. Lines accumulate in a `buffer` string.
2. Every 500ms, if the buffer is non-empty, it flushes via `broadcastOutput`.
3. If the buffer exceeds `OutputThreshold` before the ticker fires, it flushes immediately.
4. On EOF or read error, any remaining buffer is flushed before returning.

This prevents flooding chat channels with per-line messages while keeping latency under half a second for most output.

### Broadcast fan-out

`broadcastOutput` copies the session's `channels` slice under mutex, then iterates outside the lock. Every registered channel (across all providers) receives the same output. This means if both a Discord channel and a terminal are connected to the same repo, both see all LLM output.

## PTY-Based Claude Process Management

### Why PTY

Claude CLI is spawned via `github.com/creack/pty` rather than plain stdin/stdout pipes. PTY provides terminal semantics that Claude CLI expects (line editing, signal handling, terminal detection via `isatty`).

### Process lifecycle

1. **Spawn:** `pty.Start(cmd)` returns a single `*os.File` (the PTY master). This fd serves as both stdin (write to it) and stdout (read from it) for the child process.
2. **Send:** `ptmx.WriteString(content + "\n")` writes to the child's stdin.
3. **Read:** `bufio.NewReader(ptmx)` reads from the child's stdout in `readOutput`.
4. **Cancel:** `cmd.Process.Signal(syscall.SIGINT)` sends interrupt.
5. **Stop:** `cmd.Process.Signal(syscall.SIGTERM)`, falling back to `cmd.Process.Kill()` if SIGTERM fails.
6. **Close:** PTY fd is closed via `sync.Once` to prevent double-close panics.

### `sync.Once` for safe close

The `closeOnce` field is a `*sync.Once` (pointer, not value) allocated fresh on each `Start` call. This prevents a race between:
- The `Wait()` goroutine that detects process exit and closes the PTY.
- The `Stop()` method that explicitly closes the PTY during shutdown.

Both paths call `closeOnce.Do(func() { ptmx.Close() })`, guaranteeing exactly one close regardless of ordering.

### Process identity check

The `Wait()` goroutine captures `currentCmd` before launching. When it runs after process exit, it checks `c.cmd == currentCmd` before setting `c.running = false`. This prevents a stale goroutine from a previous process from incorrectly marking a newly started process as stopped.

## Concurrency Model

### Mutex usage

A single `sync.Mutex` (`Bridge.mu`) guards:
- `Bridge.repos` map (session creation, lookup, deletion)
- `Bridge.terminalRepoName` (terminal repo selection)
- Channel list snapshot in `broadcastOutput`
- Idle timeout collection in `checkIdleTimeouts`

Each `Claude` instance has its own `sync.Mutex` guarding `running`, `ptmx`, `cmd`, `lastActivity`, and `closeOnce`.

The `Merger` has its own `sync.Mutex` guarding the `sources` map.

The `ratelimit.Limiter` has its own `sync.Mutex` guarding the `limiters` map.

### Goroutines

| Goroutine | Spawned by | Purpose |
|-----------|-----------|---------|
| `handleMessages` | `Bridge.Start` | Reads from Discord provider's message channel |
| `handleTerminalMessages` | `Bridge.Start` | Reads from terminal provider's message channel |
| `idleTimeoutLoop` | `Bridge.Start` | Checks for idle sessions every minute |
| `readOutput` | `getOrCreateSession` | Reads LLM stdout and broadcasts |
| Line reader (anonymous) | `readOutput` | Reads lines from `bufio.Reader` into buffered channel |
| `cmd.Wait` watcher | `Claude.Start` | Detects process exit, cleans up PTY |
| `Terminal.readLoop` | `Terminal.Start` | Reads stdin lines into message channel |

### Buffered channels

| Channel | Capacity | Purpose |
|---------|----------|---------|
| `Discord.messages` | 100 | Incoming Discord messages |
| `Terminal.messages` | 100 | Incoming terminal lines |
| `readOutput` lines channel | 100 | PTY output lines (prevents backpressure) |
| OS signal channel | 1 | `SIGINT`/`SIGTERM` in main |

The 100-element buffers throughout the system prevent slow consumers from blocking producers. When full, messages are dropped (non-blocking select with default case in providers) or the PTY read goroutine blocks (acceptable since it just slows down reading, not writing).

## External Dependencies

| Package | Version | Purpose |
|---------|---------|---------|
| `github.com/bwmarrin/discordgo` | v0.29.0 | Discord WebSocket API client |
| `github.com/creack/pty` | v1.1.24 | PTY allocation for Claude subprocess |
| `github.com/spf13/cobra` | v1.10.2 | CLI framework (commands, flags) |
| `golang.org/x/time` | v0.5.0 | Token bucket rate limiter (`rate.Limiter`) |
| `gopkg.in/yaml.v3` | v3.0.1 | YAML configuration parsing |
