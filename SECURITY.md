# Security Policy

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

- Use **GitHub → Security → Report a vulnerability** (private advisory), or
- email the maintainer (see the GitHub profile of [@kzhxxn](https://github.com/kzhxxn)).

Include: affected version, macOS version, steps to reproduce, and impact. I aim to
acknowledge within **72 hours** and to ship a fix or mitigation for confirmed,
high-severity issues within **2 weeks**, coordinating disclosure with you.

## Scope & threat model

JobWatch reads/writes **launchd** jobs and can run shell commands you schedule, so:

- **Job commands run with your user privileges.** The app never uses `sudo` itself.
- **AI-generated jobs are proposals only.** Commands are shown for review before you
  create them; the create form flags risky patterns (sudo, `rm -rf`, remote-download
  to shell, permission-bypass flags, reverse shells, keychain access, system writes).
- **No network telemetry.** The app makes no outbound calls of its own. Optional AI
  features shell out to your *locally installed* `claude`/`codex` only when you ask.
- **Local data only.** Run history lives in `~/Library/Application Support/JobWatch/
  jobwatch.sqlite` (capped: 50 runs/job, 90 days). No cloud, no account.

## Supply chain

- Releases are built by GitHub Actions from tagged commits.
- Release DMGs are published with a **build provenance attestation**; verify with:
  ```bash
  gh attestation verify JobWatch-vX.Y.Z.dmg --repo kzhxxn/JobWatch
  ```
- The Homebrew cask pins the DMG **SHA256**.
- CI third-party actions are **pinned to commit SHAs**.
- Builds are ad-hoc signed (not yet notarized); see docs/NOTARIZATION.md.

## Supported versions

Only the latest release receives security fixes.
