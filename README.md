# BurnRate

> **macOS will block the app on first open** because it isn't notarized.
> Right-click `BurnRate.app` → **Open** → **Open** to bypass Gatekeeper. Only needed once.

---

A minimal macOS menu bar app that shows your Claude Code usage as two circular dials — one for the 5-hour rolling window, one for the 7-day window.

```
 ◕  ◑   ← two dials in your menu bar
5h  7d
```

Colors shift green → orange → red as you approach your plan limits.

---

## Requirements

- macOS 12+
- Apple Silicon (arm64)
- [Claude Code](https://claude.ai/code) with a Pro or Max subscription

---

## Install

**Option A — Download (easiest)**

Download `BurnRate.zip` from the [latest release](../../releases/latest), unzip, and open `BurnRate.app`.

**Option B — Build from source**

Requires Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/nishal/burnrate
cd burnrate
bash build.sh
open BurnRate.app
```

To keep it running after reboot, copy to Applications and add to Login Items:

```bash
cp -r BurnRate.app /Applications/
```

Then: **System Settings → General → Login Items** → add BurnRate.

---

## Accurate percentages

On first launch, BurnRate automatically configures Claude Code to report live server-side rate limit data:

- **No existing statusLine** → installs `~/.config/burnrate/hook.sh` and sets it as your statusLine in `~/.claude/settings.json`
- **Existing statusLine script** → appends a small block to the end of your script (idempotent, won't double-patch)
- **Non-command statusLine** → leaves it alone; falls back to estimation

Once wired up, BurnRate shows **● live** in the menu and values match Claude Code exactly. The live data refreshes after every Claude Code response in any session.

No manual setup needed.

---

## Configuration

Create `~/.config/burnrate/config.json` to set your plan's limits (used for the estimated fallback):

```json
{
  "fiveHourLimit": 7.0,
  "sevenDayLimit": 40.0
}
```

Default values target the Claude Pro plan. Adjust if you're on Max or see large gaps between estimated and live values.

---

## How it works

BurnRate reads usage data from two sources, in priority order:

1. **`~/.burnrate-data.json`** — written by the statusLine hook after each Claude Code response. Contains exact server-side rate limit percentages. Used if the file is less than 10 minutes old.

2. **`~/.claude/projects/**/*.jsonl`** — Claude Code's local session files. BurnRate parses token usage, computes cost using model pricing tables, and expresses it as a fraction of your configured limits.

The menu shows **● live** when using source 1, **○ estimated** when falling back to source 2.

---

## Menu

Click the dials to see:

```
5h:   32%
7d:    7%
● live
──────────
Quit BurnRate  ⌘Q
```

---

## Building from source

```bash
bash build.sh
```

Requires Xcode Command Line Tools (`xcode-select --install`).
