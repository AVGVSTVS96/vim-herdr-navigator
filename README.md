# vim-herdr-navigator

[![CI](https://github.com/AVGVSTVS96/vim-herdr-navigator/actions/workflows/ci.yml/badge.svg)](https://github.com/AVGVSTVS96/vim-herdr-navigator/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

Seamlessly navigate between [Herdr](https://herdr.dev/) panes and Vim/Neovim splits; a reimplementation of [`christoomey/vim-tmux-navigator`](https://github.com/christoomey/vim-tmux-navigator) in Herdr.

`Ctrl-h/j/k/l` move across Vim/Neovim splits and Herdr panes as if they were one grid: editor windows get first chance, and Herdr takes over when the cursor hits an edge.

<!-- TODO: demo gif of cross-pane navigation -->

It ships as two halves, both in this repo:

- **Vim/Neovim plugin** at the repo root (`plugin/`, `autoload/`, `lua/`, `doc/`), native Lua and classic Vimscript adapters.
- **Herdr-side helper** in [`helper/`](helper/), a small Rust binary (`vim-herdr-navigator`) driven from Herdr keybindings.

## Requirements

- Vim 8.2+ or Neovim 0.8+ (Neovim 0.10+ recommended)
- [Herdr](https://herdr.dev/)
- Cargo

## Install

Setup is three steps, in order:

1. Install the **helper binary** so `vim-herdr-navigator` is on your `PATH`.
2. Install the **Vim/Neovim plugin** with your plugin manager.
3. Add the **Herdr keybindings** that drive the helper.

### 1. Helper binary

Install the Rust helper first so `vim-herdr-navigator` is on your `PATH`:

```sh
cargo install --git https://github.com/AVGVSTVS96/vim-herdr-navigator --package vim-herdr-navigator
```

For local development from a clone:

```sh
git clone https://github.com/AVGVSTVS96/vim-herdr-navigator
cd vim-herdr-navigator
cargo build --release
ln -sf "$PWD/target/release/vim-herdr-navigator" ~/.local/bin/vim-herdr-navigator
```

Verify:

```sh
vim-herdr-navigator --version
vim-herdr-navigator doctor
```

### 2. Vim/Neovim plugin

#### lazy.nvim

```lua
{
  "AVGVSTVS96/vim-herdr-navigator",
  lazy = false,
  opts = {},
}
```

Zero config: `opts = {}` uses the defaults, and the helper is found on `PATH` as `vim-herdr-navigator`. See [Options](#options) to customize.

#### vim.pack (Neovim 0.12+)

```lua
vim.pack.add({ "https://github.com/AVGVSTVS96/vim-herdr-navigator" })
-- setup() is auto-called on load; call it explicitly only to pass options:
-- require("vim-herdr-navigator").setup({})
```

#### Vim plugin managers

Any Vim plugin manager that adds the repo root to `runtimepath` works, for example vim-plug:

```vim
Plug 'AVGVSTVS96/vim-herdr-navigator'
```

Classic Vim is configured with `g:vim_herdr_navigator_*` variables; Neovim can use `require("vim-herdr-navigator").setup({ ... })`. Both auto-setup on load by default.

### 3. Herdr keybindings

Finally, bind the keys in Herdr so it can hand them to the helper.
Set the following keybindings in your Herdr config (`~/.config/herdr/config.toml`):

```toml
[[keys.command]]
key = "ctrl+h"
type = "shell"
command = "vim-herdr-navigator dispatch left"
description = "vim-aware pane left"

[[keys.command]]
key = "ctrl+j"
type = "shell"
command = "vim-herdr-navigator dispatch down"
description = "vim-aware pane down"

[[keys.command]]
key = "ctrl+k"
type = "shell"
command = "vim-herdr-navigator dispatch up"
description = "vim-aware pane up"

[[keys.command]]
key = "ctrl+l"
type = "shell"
command = "vim-herdr-navigator dispatch right"
description = "vim-aware pane right"
```

Alternatively, the config command generates a ready-to-paste snippet for your convenience:
```sh
vim-herdr-navigator config | pbcopy
```

Paste the output into your Herdr config, then restart or reload config in Herdr.

Check installation with `vim-herdr-navigator doctor` in your shell, `:checkhealth vim-herdr-navigator` in vim, and `:help vim-herdr-navigator` for the full reference, then see [Behavior](#behavior) and [Options](#options) to customize.

## Behavior

Inside Vim/Neovim:

1. `Ctrl-h/j/k/l` first tries normal Vim window navigation with `wincmd h/j/k/l`.
2. If the current editor window did not change (an edge), the plugin calls `vim-herdr-navigator focus <direction>`.
3. The helper focuses the neighboring Herdr pane.

From a non-editor Herdr pane, Herdr keybindings call `vim-herdr-navigator dispatch <direction>`, which decides whether to move Herdr focus or send `ctrl+h/j/k/l` into Vim/Neovim.

This mirrors `vim-tmux-navigator`: Vim windows get first chance, the multiplexer gets focus at an edge.

The plugin only acts inside a Herdr session (`HERDR_ENV=1` or `HERDR_SOCKET_PATH` set); elsewhere it stays inert.

### Keymaps and LazyVim

By default (`set_keymaps = true`) the plugin owns `<C-h/j/k/l>`. It reasserts them after LazyVim installs its own window maps on `User VeryLazy`. To use your own mappings, set `set_keymaps = false` and map the [commands](#commands) yourself.

### Pickers and explorers

In Neovim, known floating pickers/explorers get extra handling: left navigation from a focused picker float goes straight to Herdr instead of bouncing focus back inside Neovim. Which filetypes count is configurable via `picker_filetype_patterns`; defaults cover Snacks picker/explorer, Telescope, mini.pick, fzf/fzf-lua, neo-tree, NvimTree, netrw, and oil.

Pickers install their own buffer-local `<C-h/j/k/l>`, so the Neovim adapter reasserts its maps buffer-locally in those buffers too; it owns these keys there as well. If you need a picker to keep one of them, narrow `picker_filetype_patterns` or change `keymaps`. In `fzf`/`fzf-lua` terminal buffers the terminal-mode mapping passes the key through to the picker.

## Default keymaps

Normal and terminal mode:

- `<C-h>`: left
- `<C-j>`: down
- `<C-k>`: up
- `<C-l>`: right

Add or change keys via the `keymaps` option, e.g. `left = { "<C-h>", "<A-Left>" }`, and mirror any additions with matching `[[keys.command]]` blocks in the Herdr config so both halves agree.

## Commands

- `:HerdrNavigateLeft`
- `:HerdrNavigateDown`
- `:HerdrNavigateUp`
- `:HerdrNavigateRight`

Use these if you set `set_keymaps = false` and want custom mappings.

## Options

Neovim defaults shown:

```lua
require("vim-herdr-navigator").setup({
  helper = "vim-herdr-navigator", -- name or path of the helper command (~ is expanded)
  set_keymaps = true,             -- false: manage keys yourself via :HerdrNavigate* commands
  save_on_switch = 0,             -- 0 never, 1 :update, 2 :wall (save before leaving Neovim)
  picker_filetype_patterns = {    -- filetypes treated as floating pickers
    "^snacks_picker",
    "^Telescope",
    "^minipick$",
    "^fzf$",
    "^fzf%-lua$",
    "^neo%-tree$",
    "^NvimTree$",
    "^netrw$",
    "^oil$",
  },
  keymaps = {                     -- keys per direction; add your own, e.g. { "<C-h>", "<A-Left>" }
    left = { "<C-h>" },
    down = { "<C-j>" },
    up = { "<C-k>" },
    right = { "<C-l>" },
  },
})
```

To call Neovim `setup()` yourself at a specific time, disable auto-setup before the plugin loads:

```lua
vim.g.vim_herdr_navigator_auto_setup = false
```

Classic Vim uses matching globals before the plugin loads:

```vim
let g:vim_herdr_navigator_helper = 'vim-herdr-navigator'
let g:vim_herdr_navigator_set_keymaps = 1
let g:vim_herdr_navigator_save_on_switch = 0
let g:vim_herdr_navigator_auto_setup = 1
```

## Environment variables

The helper reads a few optional variables. Set them in your shell rc (e.g. `~/.zshrc`) so the Herdr-spawned keybinding process inherits them, then restart Herdr.

| Variable | Default | Effect |
| --- | --- | --- |
| `VIM_HERDR_NAVIGATOR_PATTERN` | _(unset)_ | Extra regex OR-ed into the built-in Vim-like detection: the Herdr counterpart to tmux's `@vim_navigator_pattern`. Extends, never narrows, the set; case-insensitive, unanchored. |
| `VIM_HERDR_NAVIGATOR_ZOOM` | `preserve` | `unzoom` un-maximizes the pane you move out of before focusing; `preserve` keeps Herdr's native zoom. |
| `VIM_HERDR_NAVIGATOR_ENTRY_MARKERS` | _(off)_ | Set to `1` to land on the split nearest the entered edge. See [Entry markers](#entry-markers-opt-in). |

```sh
# Also keep nav keys inside ssh (treat it as "Vim-like"):
export VIM_HERDR_NAVIGATOR_PATTERN='(view|l?n?vim?x?|fzf|ssh)'
```

See [`helper/README.md`](helper/README.md#configuration) for the full reference and design notes.

## Entry markers (opt-in)

When you move from another Herdr pane into a Vim/Neovim pane, an entry marker lets the plugin land you on the split nearest the edge you entered from, instead of wherever the cursor last was. It's **off by default**.

Enable it with a single environment variable; export it in your shell rc and restart Herdr:

```sh
export VIM_HERDR_NAVIGATOR_ENTRY_MARKERS=1
```

That one switch covers both halves: the helper writes the markers, and this plugin (which inherits Herdr's environment) reads them; there's no separate `setup()` option to keep in sync.

## Development

Point the plugin at a local checkout and at a local helper build. Adjust the paths to wherever you cloned the repos:

```lua
{
  dir = "~/projects/vim-herdr-navigator", -- local clone of this repo
  name = "vim-herdr-navigator",
  lazy = false,
  opts = {
    -- point at the helper's release build during development
    -- (run `cargo build --release` at the repo root first)
    helper = "~/projects/vim-herdr-navigator/target/release/vim-herdr-navigator",
  },
}
```

Run the dependency-free editor smoke tests and the Rust helper checks:

```sh
tests/run.sh       # Neovim
tests/run-vim.sh   # Vim
cargo fmt --all --check
cargo clippy --all-targets -- -D warnings
cargo test --all
```

The smoke tests load the plugin and exercise `setup()`/commands/navigation. The Neovim smoke test also runs `:checkhealth`.

## Limitations

- **`C-\` (previous-pane toggle)** is not ported; Herdr does not yet expose last-pane to the CLI.
- **Copy mode:** navigation keys are unavailable while a pane is in Herdr's copy mode. Exit copy mode to navigate.
- **No edge wrapping:** at the outer edge of the grid a directional key is a no-op, matching typical multiplexer behavior.

See [`helper/README.md`](helper/README.md#not-yet-ported--limitations) for details.

## Credits

A reimplementation of [`christoomey/vim-tmux-navigator`](https://github.com/christoomey/vim-tmux-navigator) in [Herdr](https://herdr.dev/). Thanks to Chris Toomey, and Mislav Marohnic for their work on the original plugin.

## License

[MIT](LICENSE)
