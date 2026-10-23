# CLAUDE.md

Behavioral guidelines to reduce common LLM coding mistakes. Merge with project-specific instructions as needed.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

---

**These guidelines are working if:** fewer unnecessary changes in diffs, fewer rewrites due to overcomplication, and clarifying questions come before implementation rather than after mistakes.

---

## Project: hinhnen

**What it is:** A modular wallpaper daemon for Hyprland/Wayland, written in Rust. The core idea: every layer (source, trigger, setter, cache) is independent and swappable via config alone.

**Inspired by:** Windows Spotlight and macOS dynamic wallpapers - wallpaper changes that feel alive without user intervention.

### Architecture

```
source  →  cache  →  setter
   ↑
trigger
```

| Layer | Trait | Implementations |
|-------|-------|-----------------|
| Source | `ImageSource` | `local`, `bing`, `unsplash`, `nasa_apod` |
| Setter | `Awww` (no trait) | `awww` only; auto-starts `awww-daemon` |
| Trigger | (channel) | `interval`, `dbus` (unlock), login (one-shot) |
| Cache | - | SHA256-named files, LRU eviction, JSON history |

### Key files

```
src/
├── main.rs        # CLI entry (clap), dispatches to daemon or IPC client
├── daemon.rs      # Main event loop, orchestrates all layers
├── config.rs      # TOML config structs + defaults (AppConfig)
├── history.rs     # VecDeque-based history with cursor navigation
├── cache.rs       # Image download, SHA256 dedup, size eviction
├── ipc.rs         # Unix socket server (daemon) + client (CLI)
├── source/        # ImageSource trait + per-source impl
├── awww.rs        # awww setter: ensures awww-daemon is up, runs `awww img`
└── trigger/       # Interval timer + D-Bus unlock listener
```

### Config structure (TOML)

```toml
[daemon]           # interval_secs, change_on_login, change_on_unlock
[setter]           # transition, transition_duration (legacy `backend` key ignored)
[sources]          # rotation (weighted_random | round_robin)
[[sources.list]]   # type = local | bing | unsplash | nasa_apod
[cache]            # max_size_mb, history_size, dir
```

Config lives at `~/.config/hinhnen/config.toml`. Missing file → built-in defaults.

### IPC

Unix socket at `$XDG_RUNTIME_DIR/hinhnen.sock`. JSON over newlines.
- Request: `{"cmd": "next"}` etc.
- Response: `{"result": "ok", "message": "...", "status": {...}}`

CLI commands: `daemon`, `next`, `prev`, `pause`, `resume`, `status`, `reload`, `history`

### Constraints and invariants

- **No mixed sources:** local + remote in the same config is rejected at startup.
- **`next` behaviour differs by source type:** local → cycles history; remote → fetches fresh.
- **Cache eviction never removes current history entries.**
- **History cursor truncates on new entry** (git-like: branching forward discards future).
- **Async throughout:** all I/O via Tokio; no blocking calls.
- **Graceful degradation:** source failure → try next.
- **It just works:** awww is the only setter; if `awww-daemon` isn't running, hinhnen spawns it (own process group) and waits up to 5s for `awww query` to succeed.

### Dev workflow

```bash
cargo build --release        # build
cargo test                   # 47 tests, all in-process (no daemon needed)
cargo run -- daemon          # run daemon in foreground
cargo run -- status          # query running daemon
```

Tests live alongside source files (`#[cfg(test)]` modules). Use `tempfile` for filesystem tests.

### Style

- Rust edition 2024. Match existing code style exactly.
- Error handling via `anyhow`. Propagate with `?` and `.context("...")`.
- Logging via `tracing` macros (`debug!`, `info!`, `warn!`, `error!`).
- No `unwrap()` in non-test code unless the invariant is clearly documented.
