# herdr-vim-navigator

Seamless pane navigation between [Herdr](https://herdr.dev/) panes and Neovim splits — a port of [`christoomey/vim-tmux-navigator`](https://github.com/christoomey/vim-tmux-navigator)'s core `h/j/k/l` navigation to Herdr.

This repo is the **Herdr-side helper**, a small Rust binary. Pair it with the Neovim plugin:
[**herdr-vim-navigator.nvim**](https://github.com/AVGVSTVS96/herdr-vim-navigator.nvim).

With both installed, a single set of `Ctrl-h/j/k/l` (and optionally `Ctrl-Arrow`) keys moves between Neovim splits and Herdr panes as if they were one grid:

- If the active Herdr pane is running Neovim, the key is sent into the editor.
- Neovim moves between its windows first; at an edge it calls back to focus the neighboring Herdr pane.
- In any other pane, the key just moves Herdr focus.

The Neovim integration is Neovim-only.

## Why this exists

`vim-tmux-navigator` works by pairing two halves:

1. tmux keybindings detect whether the active pane is Vim-like. If yes, tmux sends `C-h/j/k/l` into Vim; otherwise it selects the neighboring tmux pane.
2. the Vim plugin maps `C-h/j/k/l`, runs `wincmd h/j/k/l`, and if the Vim window did not change, forwards the navigation back to tmux.

This project ports that idea to Herdr using the public `herdr` CLI.

## Requirements

- [Herdr](https://herdr.dev/) (provides the `herdr` CLI on your `PATH`)
- A Rust toolchain (`cargo`, 1.74+) to install — the helper is currently built from source.

## Install

All options put a `herdr-vim-navigator` binary on your `PATH`.

**cargo install (build from git):**

```sh
cargo install --git https://github.com/AVGVSTVS96/herdr-vim-navigator
```

This builds and installs into `~/.cargo/bin` (make sure it's on your `PATH`).

**From source:**

```sh
git clone https://github.com/AVGVSTVS96/herdr-vim-navigator
cd herdr-vim-navigator
cargo build --release
# binary is at target/release/herdr-vim-navigator
```

**Symlink the release binary** onto your `PATH` (handy for local/dev use):

```sh
ln -sf "$PWD/target/release/herdr-vim-navigator" ~/.local/bin/herdr-vim-navigator
```

Make sure the install target (`~/.cargo/bin`, `~/.local/bin`, etc.) is on `PATH`.

> Prebuilt binaries via [`cargo-binstall`](https://github.com/cargo-bins/cargo-binstall)
> will be available once tagged GitHub releases with binary artifacts are
> published. Until then, use `cargo install` or a source build above.

Verify:

```sh
herdr-vim-navigator --version
herdr-vim-navigator doctor
```

## Quick start

1. Install this helper (above) and check it's healthy with `herdr-vim-navigator doctor`.
2. Add the keybindings to your Herdr config. Generate a ready-to-paste snippet:

   ```sh
   herdr-vim-navigator config            # ctrl+h/j/k/l
   herdr-vim-navigator config --arrows   # also ctrl+arrow keys
   ```

   Paste the output into your Herdr config's keybindings.
3. Install the companion plugin [herdr-vim-navigator.nvim](https://github.com/AVGVSTVS96/herdr-vim-navigator.nvim).

## Herdr config

`herdr-vim-navigator config` prints exactly this (one block per direction):

```toml
[[keys.command]]
key = "ctrl+h"
type = "shell"
command = "herdr-vim-navigator dispatch left"
description = "vim-aware pane left"

[[keys.command]]
key = "ctrl+j"
type = "shell"
command = "herdr-vim-navigator dispatch down"
description = "vim-aware pane down"

[[keys.command]]
key = "ctrl+k"
type = "shell"
command = "herdr-vim-navigator dispatch up"
description = "vim-aware pane up"

[[keys.command]]
key = "ctrl+l"
type = "shell"
command = "herdr-vim-navigator dispatch right"
description = "vim-aware pane right"
```

Pass `--arrows` to also bind `ctrl+left/down/up/right`, and `--splits` for commented split-binding examples. Use `--helper <name>` if your command isn't named `herdr-vim-navigator` (e.g. a dev path).

## Commands

```sh
herdr-vim-navigator dispatch left   # Herdr keybinding entrypoint
herdr-vim-navigator focus left      # called by Neovim at a Vim window edge
herdr-vim-navigator split right     # optional split helper (right|down)
herdr-vim-navigator config          # print a Herdr keybinding snippet
herdr-vim-navigator doctor          # environment diagnostics (alias: check)
herdr-vim-navigator --version
```

Pass `--debug` to any command to print diagnostic messages to stderr.

`doctor` reports the helper version, whether the `herdr` CLI is found, whether you're inside a Herdr session, and whether the cache dir is writable. It exits non-zero if a hard requirement (the `herdr` CLI) is missing.

## Configuration

The helper reads a few optional environment variables. Set them in your shell rc (e.g. `~/.zshrc`) so the Herdr-spawned keybinding process inherits them, then restart Herdr.

| Variable | Default | Effect |
| --- | --- | --- |
| `HERDR_VIM_NAVIGATOR_PATTERN` | _(unset)_ | A regex OR-ed into the built-in Vim-like detection. Extends, never narrows, the set — the Herdr counterpart to tmux's `@vim_navigator_pattern`. Case-insensitive, unanchored. |
| `HERDR_VIM_NAVIGATOR_ZOOM` | `preserve` | `preserve` keeps Herdr's native zoom across moves. `unzoom` un-maximizes the pane you move out of (runs `herdr pane zoom --off` before focusing). |
| `HERDR_VIM_NAVIGATOR_ENTRY_MARKERS` | _(off)_ | Set to `1` so Neovim lands on the split nearest the entered edge. One switch: the helper writes the markers and the Neovim plugin (which inherits this variable) reads them — no separate plugin option. |

```sh
# Treat extra programs as "Vim-like" (here: also keep nav keys inside ssh):
export HERDR_VIM_NAVIGATOR_PATTERN='(view|l?n?vim?x?|fzf|ssh)'
# Un-maximize on directional moves instead of preserving zoom:
export HERDR_VIM_NAVIGATOR_ZOOM=unzoom
# Enable entry markers (also set entry_markers = true in the Neovim plugin):
export HERDR_VIM_NAVIGATOR_ENTRY_MARKERS=1
```

## Not yet ported / limitations

- **`C-\` (previous-pane toggle)** is not yet ported — Herdr does not expose last-pane to the CLI. Inside Neovim you can still map `<C-\>` to `<C-w>p` yourself; a Herdr-side binding to the native `last_pane` action is also possible, but the seamless cross-pane toggle (send to Neovim if Vim, else jump to the last pane) is blocked upstream until Herdr ships a `pane focus --last` CLI command.
- **Copy mode:** navigation keys are unavailable while a pane is in Herdr's copy mode (copy mode consumes the keys). Exit copy mode to navigate.
- **No edge wrapping:** at the outer edge of the grid a directional key is a no-op — Herdr does not wrap focus around to the opposite side. This matches typical multiplexer behavior; there is nothing to configure.

## Design notes

The helper intentionally shells out to `herdr pane ...` commands instead of using Herdr's socket protocol directly. That keeps the implementation small and stable:

- `pane process-info` identifies Neovim (and FZF) foreground processes.
- `pane send-keys` forwards `ctrl+h/j/k/l` into Vim-like panes.
- `pane neighbor` lets the helper prepare a small entry marker when moving into a Neovim pane (opt-in, see [Configuration](#configuration)).
- `pane focus` moves Herdr focus.

It uses live `pane process-info` rather than persistent Neovim pane registration, avoiding stale marker files when Neovim exits unexpectedly. Each `herdr` call is bounded by a short timeout so a stuck socket can't hang a keybinding.

The entry marker lives under:

```text
${XDG_CACHE_HOME:-~/.cache}/herdr-vim-navigator/entry/<pane-id>
```

The Neovim plugin reads it on focus and jumps to the split nearest the edge that was entered.

## Development

The crate is laid out as:

- `src/main.rs` — CLI (clap) and command dispatch
- `src/herdr.rs` — `herdr` CLI invocation and JSON parsing (serde)
- `src/detect.rs` — direction table and Vim-like process detection
- `src/config.rs` — Herdr keybinding snippet rendering
- `src/doctor.rs` — environment diagnostics
- `src/marker.rs` — entry markers shared with the Neovim plugin

Build, format, lint, and test:

```sh
cargo build --release
cargo fmt
cargo clippy --all-targets
cargo test
```

Tests cover Vim-like process detection and config snippet rendering.

## License

[MIT](LICENSE)
