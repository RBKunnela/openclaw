# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

OpenClaw is a multi-channel AI gateway — a TypeScript/Node.js control plane that manages messaging integrations (WhatsApp, Telegram, Discord, Slack, Signal, iMessage, and 30+ more via extensions), agent routing, and plugin loading. It also ships native apps for macOS, iOS, and Android.

## Build & Development Commands

**Prerequisites:** Node 22+, pnpm (10.23.0)

```bash
pnpm install                # Install dependencies
pnpm ui:build               # Build the web UI (needed before first full build)
pnpm build                  # Full build: bundle A2UI, tsdown, generate types
```

**Development:**

```bash
pnpm openclaw ...           # Run CLI directly (tsx)
pnpm gateway:watch          # Auto-reload gateway on file changes
```

**Type-checking & Linting:**

```bash
pnpm check                  # format:check + tsgo + lint (run before commits)
pnpm tsgo                   # TypeScript type-check only
pnpm lint                   # oxlint --type-aware
pnpm format                 # oxfmt --write (auto-fix formatting)
pnpm format:check           # oxfmt --check (CI-safe)
pnpm lint:fix               # oxlint --fix + format
```

**Testing:**

```bash
pnpm test                   # Unit tests (vitest, parallelized)
pnpm test:fast              # Unit tests without parallelization script
pnpm test:coverage          # With V8 coverage (70% threshold)
pnpm test:e2e               # End-to-end tests
pnpm test:watch             # Vitest watch mode
pnpm test:live              # Live tests (requires real API keys, OPENCLAW_LIVE_TEST=1)
```

Run a single test file: `pnpm vitest run path/to/file.test.ts`

**Commits:** Use `scripts/committer "<msg>" <file...>` instead of manual `git add`/`git commit` to keep staging scoped.

## Architecture

### Core Layers

- **Gateway (control plane):** WebSocket server managing sessions, channels, tools, and events. Code in `src/gateway/`.
- **Channels:** Pluggable messaging adapters. Each channel implements the `ChannelPlugin` interface with typed adapters (config, outbound, pairing, auth, etc.). Core channels in `src/telegram/`, `src/discord/`, `src/slack/`, `src/signal/`, `src/imessage/`, `src/channels/web/` (WhatsApp).
- **Agent runtime:** Pi-based embedded AI with tool streaming. Code in `src/agents/`, using `@mariozechner/pi-*` packages.
- **Routing:** Session isolation via keys like `<agent-id>#<channel>:<peer-id>`. Code in `src/routing/`.
- **CLI:** Commander.js-based. Program builder in `src/cli/program/`, commands in `src/commands/`.

### Extension System

Extensions live under `extensions/` as workspace packages (e.g., `extensions/msteams`, `extensions/matrix`, `extensions/voice-call`). Each has its own `package.json` and an `openclaw.plugin.json` manifest. Plugin-only deps go in the extension `package.json`, not the root. Runtime deps must be in `dependencies`; avoid `workspace:*` in `dependencies`.

### Platform Apps

- macOS: `apps/macos/` (Swift, SwiftUI)
- iOS: `apps/ios/` (Swift, xcodegen for project generation)
- Android: `apps/android/` (Kotlin, Gradle)
- Shared iOS/macOS code: `apps/shared/`
- Web UI: `ui/`

### Key Patterns

- **Dependency injection:** `createDefaultDeps()` pattern in `src/cli/deps.ts` for lazy-loaded per-channel functions.
- **Runtime type validation:** `@sinclair/typebox` for schemas. Tool input schemas must use `type: "object"` at top level; no `Type.Union`/`anyOf`/`oneOf`/`allOf`. Use `stringEnum`/`optionalStringEnum` for string lists.
- **Config:** YAML/JSON5-based (`~/.openclaw/config.yaml`), validated with Zod.

## Coding Conventions

- TypeScript strict mode, ESM. Avoid `any`.
- Formatting/linting via Oxlint (`oxlint`) and Oxfmt (`oxfmt`); run `pnpm check` before commits.
- Keep files under ~500-700 LOC; split when it improves clarity.
- Tests colocated as `*.test.ts`; e2e as `*.e2e.test.ts`.
- Naming: **OpenClaw** for product/UI headings; `openclaw` for CLI, package, paths, config keys.
- Patched dependencies (`pnpm.patchedDependencies`) must use exact versions (no `^`/`~`).
- CLI progress: use `src/cli/progress.ts`; don't hand-roll spinners.
- Terminal colors: use the shared palette in `src/terminal/palette.ts`; no hardcoded colors.
- SwiftUI: prefer `Observation` framework (`@Observable`) over `ObservableObject`.
- When refactoring shared logic (routing, allowlists, pairing, commands, onboarding), consider **all** built-in + extension channels.

## Multi-Agent Safety

- Do not create/apply/drop `git stash`, switch branches, or modify `git worktree` without explicit request.
- When committing, scope to your changes only. When the user says "commit all", commit everything in grouped chunks.
- Do not run `git pull --rebase --autostash`; use plain `git pull --rebase` when the user says "push".

## Docs

- Docs in `docs/` are Mintlify-hosted at `docs.openclaw.ai`.
- Internal doc links: root-relative, no `.md`/`.mdx` extension (e.g., `[Config](/configuration)`).
- Avoid em dashes and apostrophes in headings (breaks Mintlify anchors).
- `docs/zh-CN/` is generated; do not edit unless explicitly asked.

## See Also

`AGENTS.md` contains additional operational guidance (VM ops, release workflows, NPM publish procedures, platform-specific notes).
