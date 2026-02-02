# Contributing to llm-bridge

Thank you for your interest in contributing to llm-bridge. This guide will help you get started with development, testing, and contributing code.

## Table of Contents

- [Development Setup](#development-setup)
- [Building and Testing](#building-and-testing)
- [Code Style](#code-style)
- [Testing Guidelines](#testing-guidelines)
- [CI Pipeline](#ci-pipeline)
- [Bazel Workflow](#bazel-workflow)
- [Commit Messages](#commit-messages)
- [Pull Request Process](#pull-request-process)
- [Project Structure](#project-structure)

## Development Setup

### Prerequisites

1. **Bazelisk** - Install [Bazelisk](https://github.com/bazelbuild/bazelisk) to automatically download the correct Bazel version (8.5.1)
2. **Node.js** - Required for Claude CLI runtime dependency
3. **Docker & Docker Compose** - Optional, for containerized testing

Note: Go 1.23.6 is managed by Bazel via `go_sdk.download` in MODULE.bazel. No local Go installation is required.

### Clone the Repository

```bash
git clone https://github.com/anthropics/llm-bridge.git
cd llm-bridge
```

### Install Claude CLI

```bash
npm install -g @anthropic-ai/claude-code
```

This is a runtime dependency that llm-bridge spawns as a child process via PTY.

## Building and Testing

### Build Commands

```bash
# Build the main binary
make build
# or
bazel build //cmd/llm-bridge

# Build everything
bazel build //...
```

The compiled binary will be at `bazel-bin/cmd/llm-bridge/llm-bridge_/llm-bridge`.

### Test Commands

```bash
# Run all tests
make test
# or
bazel test //...

# Run tests with CI configuration (verbose output)
bazel test //... --config=ci

# Run tests with race detector
bazel test //... --config=race
```

### Lint

```bash
# Run golangci-lint
make lint
# or
bazel test //:lint
```

The linter runs outside the Bazel sandbox (`no-sandbox` tag) because it needs network access to download golangci-lint on first run.

Enabled linters (see `.golangci.yml`):
- `errcheck` - Check for unchecked errors
- `govet` - Standard Go vet checks
- `staticcheck` - Static analysis
- `unused` - Detect unused code
- `gosimple` - Suggest code simplifications
- `ineffassign` - Detect ineffectual assignments
- `typecheck` - Type checking

### Coverage

```bash
# Run coverage check with 90% threshold enforcement
make coverage
# or
bazel coverage //internal/...
./scripts/check-coverage.sh

# Generate coverage report only
bazel coverage //...

# Run coverage script self-test
bazel test //:coverage_check_test
```

Coverage enforcement:
- **Threshold**: 90% line coverage
- **Scope**: `internal/` packages only
- **Excluded**: `cmd/` package
- **Output**: LCOV format at `bazel-out/_coverage/_coverage_report.dat`

Options for `scripts/check-coverage.sh`:
```bash
./scripts/check-coverage.sh --threshold 80        # Custom threshold
./scripts/check-coverage.sh --exclude "cmd/"      # Exclude pattern
./scripts/check-coverage.sh --lcov-file custom.dat
./scripts/check-coverage.sh --self-test           # Run validation tests
```

### Regenerate BUILD Files

After changing imports or adding new Go files:

```bash
make gazelle
# or
bazel run //:gazelle
```

Gazelle automatically generates and updates BUILD.bazel files based on your Go code.

## Code Style

### Go Conventions

Follow standard Go conventions:
- Use `gofmt` formatting (enforced by golangci-lint)
- Exported identifiers must have doc comments
- Keep functions small and focused
- Use descriptive variable names
- Avoid global state where possible

### Package Organization

- `cmd/llm-bridge/` - Entry point (Cobra CLI)
- `internal/bridge/` - Core orchestration, session management, output fanout
- `internal/config/` - YAML configuration parsing
- `internal/llm/` - LLM interface, Claude PTY wrapper
- `internal/provider/` - Discord and Terminal providers
- `internal/ratelimit/` - Token-bucket rate limiting
- `internal/router/` - Command routing (/ and ! prefixes)
- `internal/output/` - Output formatting, file attachments

### Imports

Use the standard Go import grouping:
1. Standard library
2. External dependencies
3. Internal packages

Example:
```go
import (
    "context"
    "fmt"
    "time"

    "github.com/bwmarrin/discordgo"

    "github.com/anthropics/llm-bridge/internal/config"
    "github.com/anthropics/llm-bridge/internal/llm"
)
```

## Testing Guidelines

### Test File Organization

Place tests in `*_test.go` files alongside the code they test. Use the same package name to test internal implementation details, or use `package_test` for black-box testing.

### Table-Driven Tests

Prefer table-driven test patterns for testing multiple scenarios:

```go
func TestMyFunction(t *testing.T) {
    tests := []struct {
        name     string
        input    string
        expected string
    }{
        {"empty input", "", ""},
        {"normal case", "hello", "HELLO"},
        {"unicode", "café", "CAFÉ"},
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            result := MyFunction(tt.input)
            if result != tt.expected {
                t.Errorf("got %q, want %q", result, tt.expected)
            }
        })
    }
}
```

### Mock Patterns

Use lightweight mocks for testing. Examples:

- `mockLLM` (in `internal/bridge/mock_llm_test.go`) - Implements `llm.LLM` interface
- `MockProvider` (in `internal/provider/`) - Implements provider interface

Mock pattern:
```go
type mockLLM struct {
    mu           sync.Mutex
    name         string
    isRunning    bool
    sentMessages []llm.Message
    sendErr      error
    output       io.Reader
    lastActivity time.Time
}

func (m *mockLLM) Send(msg llm.Message) error {
    m.mu.Lock()
    defer m.mu.Unlock()
    if m.sendErr != nil {
        return m.sendErr
    }
    m.sentMessages = append(m.sentMessages, msg)
    return nil
}
```

### Test Coverage Goals

- Aim for **90% line coverage** on `internal/` packages
- Write 3-10 tests per feature depending on complexity
- Cover happy path, edge cases, and error paths
- Skip tests for: config-only changes, generated code, docs-only changes

### Test Naming

- Test functions: `TestFunctionName` or `TestType_Method`
- Subtests: Descriptive names in `t.Run(name, ...)`
- Examples: `TestBridge_HandleMessages_ContextCancel`

## CI Pipeline

GitHub Actions runs automatically on:
- Pull requests to `main`
- Pushes to `main`

### CI Stages

The CI pipeline runs these stages sequentially:

1. **Build** - `bazel build //...`
2. **Test** - `bazel test //... --config=ci`
3. **Coverage** - Enforce 90% threshold on `internal/` packages
4. **Lint** - `bazel test //:lint --config=ci`
5. **Docker** - Build base image + production image, verify with `--help`

### Coverage Report

Coverage reports are uploaded as artifacts on every CI run:
- Artifact name: `coverage-report`
- Format: LCOV
- Retention: 14 days

### CI Configuration

The CI workflow uses Bazel caching for faster builds:
- Bazelisk cache
- Repository cache: `~/.cache/bazel-repo`
- Disk cache: `~/.cache/bazel-disk`

## Bazel Workflow

### Hermetic Builds

Bazel provides fully hermetic builds:
- Go SDK is downloaded automatically (no local Go installation needed)
- Dependencies are versioned and cached
- Builds are reproducible across environments

### Bazel Configurations

```bash
# CI configuration (caching + verbose output)
bazel test //... --config=ci

# Race detector (the build:race config is inherited by test)
bazel test //... --config=race

# Coverage (combined LCOV report, internal packages only)
bazel coverage //...
```

See `.bazelrc` for configuration details.

### BUILD.bazel Files

Each package has a `BUILD.bazel` file that defines build targets. These are generated and maintained by Gazelle.

Example structure:
```python
load("@rules_go//go:def.bzl", "go_library", "go_test")

go_library(
    name = "bridge",
    srcs = ["bridge.go", "session.go"],
    importpath = "github.com/anthropics/llm-bridge/internal/bridge",
    visibility = ["//:__subpackages__"],
    deps = [
        "//internal/config",
        "//internal/llm",
    ],
)

go_test(
    name = "bridge_test",
    srcs = ["bridge_test.go", "mock_llm_test.go"],
    embed = [":bridge"],
)
```

### After Changing Imports

Always run Gazelle after:
- Adding new Go files
- Changing import statements
- Adding new packages

```bash
bazel run //:gazelle
```

### Docker Image Building

Two approaches for building Docker images:

1. **Bazel OCI image** (minimal, for testing):
```bash
make image
# or
bazel build //:image
bazel run //:image_load
```

2. **Multi-stage Docker** (production, includes Node.js + Claude CLI):
```bash
make docker
# or
docker build -f Dockerfile.base -t llm-bridge-base:latest .
bazel build //cmd/llm-bridge
mkdir -p .build && cp -L bazel-bin/cmd/llm-bridge/llm-bridge_/llm-bridge .build/llm-bridge
docker build -t llm-bridge:latest .
```

## Commit Messages

Follow conventional commit format:

```
<type>: <description>

[optional body]

[optional footer]
```

### Types

- `feat` - New feature
- `fix` - Bug fix
- `docs` - Documentation changes
- `chore` - Maintenance tasks
- `ci` - CI/CD changes
- `test` - Test additions or fixes
- `refactor` - Code refactoring

### Examples

```
feat: add idle timeout for LLM sessions

Automatically stop LLM processes after 10 minutes of inactivity
to reduce resource usage.

Closes #42
```

```
fix: handle nil pointer in bridge Stop method

Add nil check for session.llm before calling Stop to prevent
panic during shutdown.
```

```
docs: update architecture diagrams in README
```

## Pull Request Process

### Before Submitting

1. **Run tests locally**
```bash
make test
make lint
make coverage
```

2. **Ensure BUILD files are up to date**
```bash
make gazelle
```

3. **Write descriptive commit messages** following the format above

4. **Update documentation** if you've changed user-facing behavior

### PR Template

When you create a PR, fill out the template with:

- **Summary**: Brief description of changes
- **Type of Change**: Check all that apply
  - [ ] Bug fix
  - [ ] New feature
  - [ ] Breaking change
  - [ ] Documentation
- **Checklist**:
  - [ ] Tests pass locally
  - [ ] Code follows project style
  - [ ] Documentation updated (if needed)

### Review Process

1. CI must pass (build, test, coverage, lint)
2. At least one maintainer approval required
3. Address review feedback
4. Squash or rebase commits as needed

### PR Checklist

Before requesting review:
- [ ] All tests pass locally
- [ ] Coverage threshold met (90% on internal packages)
- [ ] Linter passes with no warnings
- [ ] Gazelle run if imports changed
- [ ] Documentation updated for user-facing changes
- [ ] Commit messages follow format
- [ ] PR description is clear and complete

## Project Structure

```
llm-bridge/
├── cmd/
│   └── llm-bridge/          # CLI entry point (Cobra commands)
│       ├── main.go
│       ├── serve.go         # Server command
│       └── BUILD.bazel
├── internal/
│   ├── bridge/              # Core orchestration
│   │   ├── bridge.go        # Main bridge logic
│   │   ├── session.go       # Session management
│   │   ├── bridge_test.go
│   │   ├── mock_llm_test.go # Test mocks
│   │   └── BUILD.bazel
│   ├── config/              # Configuration parsing
│   ├── llm/                 # LLM interface and implementations
│   │   ├── llm.go           # Interface definition
│   │   ├── claude.go        # Claude PTY wrapper
│   │   └── claude_test.go
│   ├── provider/            # Input providers
│   │   ├── provider.go      # Interface
│   │   ├── discord.go       # Discord bot
│   │   └── terminal.go      # CLI terminal
│   ├── ratelimit/           # Rate limiting
│   ├── router/              # Command routing
│   └── output/              # Output formatting
├── scripts/
│   ├── check-coverage.sh    # Coverage threshold enforcement
│   └── lint.sh              # Golangci-lint wrapper
├── .github/
│   ├── workflows/
│   │   └── ci.yml           # CI pipeline
│   ├── ISSUE_TEMPLATE/
│   └── PULL_REQUEST_TEMPLATE.md
├── BUILD.bazel              # Root build file (Gazelle, lint, OCI image)
├── MODULE.bazel             # Bazel module dependencies
├── .bazelrc                 # Bazel configuration
├── .golangci.yml            # Linter configuration
├── Makefile                 # Convenience shortcuts
├── CLAUDE.md                # Development environment docs
├── README.md                # User documentation
├── docs/
│   ├── architecture.md      # Architecture overview
│   ├── configuration.md     # Configuration reference
│   └── deployment.md        # Deployment guide

```

### Key Files

- **BUILD.bazel** - Defines build targets (Gazelle, lint, coverage test, OCI image)
- **MODULE.bazel** - Declares Bazel module and dependencies
- **.bazelrc** - Bazel build/test configurations (hermetic builds, race detector, coverage)
- **Makefile** - Convenience wrappers for common Bazel commands
- **CLAUDE.md** - Detailed development environment and architecture notes

### Architecture Documentation

For detailed architecture information, see:
- `docs/architecture.md` - Data flow, package breakdown, concurrency model
- `docs/configuration.md` - Full YAML schema, defaults, environment variables
- `docs/deployment.md` - Bare metal, Docker, Bazel OCI deployment guides
- `CLAUDE.md` - Development environment, Bazel workflow, gotchas
- `README.md` - Quick start, features, commands
- Code comments and package documentation

## Getting Help

- Review existing issues and PRs
- Check `CLAUDE.md` for development environment details
- Read package documentation in Go source files
- Ask questions in issue discussions

## License

By contributing to llm-bridge, you agree that your contributions will be licensed under the same license as the project.
