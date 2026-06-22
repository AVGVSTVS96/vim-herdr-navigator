# herdr-vim-navigator

Seamless pane navigation between [Herdr](https://herdr.dev/) panes and Vim/Neovim splits.

This is the Herdr-side helper for a `vim-tmux-navigator`-style setup:

- `Ctrl-h/j/k/l` and/or `Ctrl-Arrow` can move across Herdr panes.
- If the active Herdr pane is running Vim/Neovim, the helper sends the key into Neovim instead.
- The companion Neovim plugin then moves between Vim windows first; when it reaches an edge, it calls this helper to focus the neighboring Herdr pane.

## Why this exists

[`christoomey/vim-tmux-navigator`](https://github.com/christoomey/vim-tmux-navigator) works by pairing two halves:

1. tmux keybindings detect whether the active pane is Vim-like. If yes, tmux sends `C-h/j/k/l` into Vim; otherwise tmux selects the neighboring tmux pane.
2. the Vim plugin maps `C-h/j/k/l`, runs `wincmd h/j/k/l`, and if the current Vim window did not change, forwards the navigation back to tmux.

This project ports that idea to Herdr using the public `herdr` CLI.

## Install

For local development:

```sh
ln -sf "$PWD/bin/herdr-vim-navigator" ~/.local/bin/herdr-vim-navigator
```

Make sure `~/.local/bin` is on `PATH`.

## Herdr config

Example:

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

You can add `ctrl+left/down/up/right` bindings in the same way.

## Commands

```sh
herdr-vim-navigator dispatch left   # Herdr keybinding entrypoint
herdr-vim-navigator focus left      # called by Neovim at a Vim window edge
herdr-vim-navigator split right     # optional split helper
```

## Design notes

The helper intentionally shells out to `herdr pane ...` commands instead of using Herdr's socket protocol directly. That keeps the implementation small and stable:

- `pane process-info` identifies Vim/Neovim/FZF foreground processes.
- `pane send-keys` forwards `ctrl+h/j/k/l` into Vim-like panes.
- `pane neighbor` lets the helper prepare a small entry marker when moving into a Neovim pane.
- `pane focus` moves Herdr focus.

The helper intentionally uses live `pane process-info` rather than persistent Neovim pane registration, avoiding stale marker files when Neovim exits unexpectedly.

The entry marker lives under:

```text
${XDG_CACHE_HOME:-~/.cache}/herdr-vim-navigator/entry/<pane-id>
```

The Neovim plugin reads it on focus and jumps to the split nearest the edge that was entered.

## Tests

```sh
python3 -m unittest discover -s tests
```
