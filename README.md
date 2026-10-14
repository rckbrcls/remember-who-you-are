# Remember Who You Are 🧠

A tiny macOS menu bar app that notices when an AI coding agent (Claude Code, Codex, Cursor) is working and nudges you to solve a LeetCode problem while you wait.

> Alpha. Expect rough edges.

## Install

```bash
curl -fsSL https://rckbrcls.com/api/remember-who-you-are/install | bash
```

Requires macOS 26 or later. The installer downloads the latest GitHub release (alpha builds included) into `/Applications`.

## How it works

- Polls the process table and treats an agent as "working" after sustained CPU activity.
- After a configurable delay (default 2 min) the menu bar icon switches to 💀 and the popover suggests a problem from a built-in list of free LeetCode problems.
- Solve, mark done, or skip with a sarcastic excuse.

## Build from source

```bash
./build-app.sh            # universal release build, wraps it in build/Remember Who You Are.app
swift test                # core logic tests
```

Updates use Sparkle. Set `RWYA_FEED_URL` and `RWYA_ED_KEY` when building to enable them.
