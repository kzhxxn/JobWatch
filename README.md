# 🚀 JobWatch

A local-first **launchd job observability** menu bar app for macOS — see what your
scheduled jobs and background agents *actually did*, as a little pixel launch complex.

No cloud, no account, no telemetry. Zero dependencies (system SQLite only).

---

## What it does

- **Scans** `~/Library/LaunchAgents` + `/Library/LaunchAgents` and merges live
  `launchctl` state (loaded / PID / last exit code).
- **Launch base scene** (pixel art): scheduled jobs queue up and launch on their
  countdown; running daemons orbit as satellites; failed jobs explode.
- **Grouped list** by trigger kind (scheduled / always-on / on-change / at-login /
  manual) with a top **Issues** section for real failures.
- **Detail** per job: description (from the script's own header comment when present),
  schedule, last exit code, and **recorded run history** (start / duration / exit).
- **Mission-control console**: CPU · MEM · DISK · running-JOB gauges.
- **Failure notifications**, **launch-at-login**, **4 languages** (en / ko / ja / zh).

Recorded history is precise for jobs run through the bundled `jobwatch-runner`;
other jobs show an *estimated* last-run (from log mtime).

> App Store distribution isn't possible (the sandbox blocks `launchctl`), so this is
> a direct-distribution / open-source app.

## Requirements

- macOS 14 (Sonoma) or later
- To build: Xcode or a Swift 6 toolchain (`swift --version`)

## Build & run

```bash
./build-app.sh       # builds + packages JobWatch.app (ad-hoc signed)
open ./JobWatch.app  # a rocket icon appears in the menu bar
```

Move `JobWatch.app` to `/Applications` before enabling **launch at login**.

## Install (downloaded build)

Because release builds are ad-hoc signed (not notarized), macOS Gatekeeper will warn
on first open. Either:

- **Right-click → Open** once, or
- `xattr -dr com.apple.quarantine JobWatch.app`

(A notarized DMG needs an Apple Developer account; contributions welcome.)

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
