# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0](https://github.com/AVGVSTVS96/vim-herdr-navigator/releases/tag/v0.1.0) - 2026-07-02

### Added

- prebuilt helper binaries with plugin-manager install hook

### Other

- Trim v1 surface: drop split/arrows/--pane, gate auto-setup on Herdr session
- Add classic Vim adapter
- create monorepo for both plugins
- prep v1: detection fix, env-var config, CI, and docs
- Quote generated Herdr helper commands
- Polish Herdr CLI wrapper comments
- Production hardening: atomic markers, honest timeout/install docs
- Kill the herdr child on timeout (no orphaned CLI processes)
- Rewrite helper in Rust (drop Python entirely)
- Productionize helper: package layout, new CLI commands, packaging, docs
- Use live Herdr process info for detection
- Initial herdr vim navigator helper
