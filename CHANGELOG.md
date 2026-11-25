# Changelog

All notable changes to this project are written in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
This project uses [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.1] - 2026-11-25

### Fixed

- A switch could stop with "Claude did not quit" after 20 seconds, and Claude stayed closed, although
  Claude had quit. The app trusted the answer of macOS about the quit, and that answer could stay
  wrong. The app now checks the Claude process itself, and it waits up to 60 seconds.

### Added

- README: a link to the port for KDE Plasma on Linux, made by a different maintainer.

## [1.0.0] - 2026-11-16

First release with the name Clauds.

### Added

- Menu bar panel with one card for each Claude account.
- Switch the Claude desktop app between accounts. Each account stays signed in.
- Side by Side mode: one Claude copy for each account, all open at the same time.
- Shared Code sessions between accounts, with a record of the owner of each session.
- Share Code sessions in Side by Side. Off by default, with a warning, because it is risky.
- Live plan usage for each account: 5-hour, weekly, and weekly per-model limits, with reset times.
- Auto-switch near a limit (… menu): off, ask first, or automatic. Off by default.
- Activity indicator while usage numbers load, and a notice when they cannot load.
- Sign-in window for live usage that closes by itself.
- A claude.ai chat window for each account.
- Self-update from GitHub releases, with Sparkle. The app shows the release notes and lets the user
  install, skip, or wait. Each update must have a valid EdDSA signature.
- Start at Login.
- About window.
- Release download as a DMG file (universal, ad-hoc signed, not notarized).
- Data from the first app name ("Claude Switcher") moves to the new folder at the first start
  while Claude is closed.

[Unreleased]: https://github.com/codeFi/clauds/compare/v1.0.1...HEAD
[1.0.1]: https://github.com/codeFi/clauds/compare/v1.0.0...v1.0.1
[1.0.0]: https://github.com/codeFi/clauds/releases/tag/v1.0.0
