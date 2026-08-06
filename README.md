# 🚀 JobWatch

**English** · [한국어](README.ko.md)

A local-first **launchd job observability** menu bar app for macOS — see what your
scheduled jobs and background agents *actually did*, as a little pixel launch complex.

No cloud, no account, no telemetry. Zero dependencies (system SQLite only).

---

## What it does

- **Scans** `~/Library/LaunchAgents` + `/Library/LaunchAgents` and merges live
  `launchctl` state (loaded / PID / last exit code).
- **Launch base scene** (pixel art): scheduled jobs wait on the pad and launch on
  their countdown; on launch a dot ascends into the top **orbit**; daemons orbit as
  satellites; failures scatter mid-flight.
- **Grouped list** by trigger kind (scheduled / always-on / on-change / at-login /
  manual) with a top **Issues** section for real failures.
- **Detail** per job: description (from the script's own header comment when present),
  schedule, last exit code, and **recorded run history** (start / duration / exit +
  captured output).
- **Mission-control console**: CPU · MEM · DISK · running-JOB gauges.
- **Failure notifications**, **launch-at-login**, natural-language **AI job creation**
  (claude/codex), **4 languages** (en / ko / ja / zh).

Recorded history is precise for jobs run through the bundled `jobwatch-runner`;
other jobs show an *estimated* last-run (from log mtime).

> App Store distribution isn't possible (the sandbox blocks `launchctl`), so this is
> a direct-distribution / open-source app.

## Install

### Homebrew (recommended)

```bash
brew install --cask kzhxxn/tap/jobwatch
```

Homebrew verifies the download checksum. Because this build isn't notarized yet,
Gatekeeper still applies, so on **first launch** either right-click the app in
`/Applications` → **Open** once, or install skipping quarantine:

```bash
brew install --cask --no-quarantine kzhxxn/tap/jobwatch
```

Then look for the orbit icon in the menu bar.

### Download the DMG

Grab the latest `.dmg` from [Releases](https://github.com/kzhxxn/JobWatch/releases).
Because release builds are ad-hoc signed (not notarized), on first open either
**right-click → Open** once, or run `xattr -dr com.apple.quarantine JobWatch.app`.

## Requirements

- macOS 14 (Sonoma) or later
- To build from source: Xcode or a Swift 6 toolchain (`swift --version`)

## Build & run

```bash
./build-app.sh       # builds + packages JobWatch.app (ad-hoc signed)
open ./JobWatch.app  # a rocket icon appears in the menu bar
```

Move `JobWatch.app` to `/Applications` before enabling **launch at login**.
A notarized DMG needs an Apple Developer account — see [docs/NOTARIZATION.md](docs/NOTARIZATION.md).

## Dependencies

**None.** SQLite is the system `libsqlite3` built into macOS; there are no third-party
Swift packages. The history database is created automatically at
`~/Library/Application Support/JobWatch/jobwatch.sqlite`.

## Project layout

```
Sources/JobWatch/          menu bar app (SwiftUI)
  App.swift                entry point + menu bar rocket icon
  ContentView.swift        header, grouped list, drill-in detail, console
  LaunchPadView.swift      pixel launch-base scene
  Store.swift              @Observable state (scan / history / vitals / settings)
  Launchd.swift            plist scan + launchctl adapter
  RunStore.swift           reads recorded run history (SQLite)
  Inference.swift          rule-based name/description/category
  SystemVitals.swift       CPU / memory / disk sampling
Sources/jobwatch-runner/   headless runner: wraps a job, records to SQLite
```

## License

MIT © Jihun Kang
