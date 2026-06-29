# vim-herdr-navigator

Seamless [Herdr](https://herdr.dev/) + Vim/Neovim pane navigation — a port of [`christoomey/vim-tmux-navigator`](https://github.com/christoomey/vim-tmux-navigator)'s core `h/j/k/l` navigation to Herdr.

This monorepo contains both halves needed today:

- the Vim/Neovim runtime plugin at the repo root (`plugin/`, `autoload/`, `lua/`, `doc/`)
- the Herdr-side Rust helper in `helper/`

A single set of `Ctrl-h/j/k/l` (and optionally `Ctrl-Arrow`) keys moves between Vim/Neovim splits and Herdr panes as if they were one grid: editor windows get first chance, and Herdr takes focus when the editor hits an edge.

## Requirements

- Vim 8.2+ or Neovim 0.8+ (Neovim 0.10+ recommended)
- [Herdr](https://herdr.dev/)
- The [`vim-herdr-navigator`](https://github.com/AVGVSTVS96/vim-herdr-navigator) helper (a small Rust binary) installed and on your `PATH`

## Install

### Helper binary

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

### Vim/Neovim plugin

#### lazy.nvim

```lua
{
  "AVGVSTVS96/vim-herdr-navigator",
  -- Only load inside a Herdr session.
  cond = function()
    return vim.env.HERDR_ENV == "1" or vim.env.HERDR_SOCKET_PATH ~= nil
  end,
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

Then wire up the Herdr side — see [Herdr config](#herdr-config).

## Behavior

Inside Vim/Neovim:

1. `Ctrl-h/j/k/l` or `Ctrl-Arrow` first tries normal Vim window navigation with `wincmd h/j/k/l`.
2. If the current editor window did not change (an edge), the plugin calls `vim-herdr-navigator focus <direction>`.
3. The helper focuses the neighboring Herdr pane.

From a non-editor Herdr pane, Herdr keybindings call `vim-herdr-navigator dispatch <direction>`, which decides whether to move Herdr focus or send `ctrl+h/j/k/l` into Vim/Neovim.

This mirrors `vim-tmux-navigator`: Vim windows get first chance, the multiplexer gets focus at an edge.

The plugin only acts inside a Herdr session (`HERDR_ENV=1` or `HERDR_SOCKET_PATH` set); elsewhere it stays inert.

### Keymaps and LazyVim

Like `vim-tmux-navigator`, enabling the plugin's maps (`set_keymaps = true`, the default) means it owns `<C-h/j/k/l>` (and `<C-Arrow>`): they are installed when `setup()` runs and reasserted after LazyVim installs its own `<C-h/j/k/l>` window maps on `User VeryLazy`, so navigation stays edge-aware without you editing your personal keymaps. To keep your own mapping on one of these keys, set `set_keymaps = false` and wire them up yourself via the [commands](#commands).

### Pickers and explorers

In Neovim, known floating pickers/explorers get extra handling: left navigation from a focused picker float goes straight to Herdr instead of bouncing focus back inside Neovim. Which filetypes count is configurable via `picker_filetype_patterns`; defaults cover Snacks picker/explorer, Telescope, mini.pick, fzf/fzf-lua, neo-tree, NvimTree, and oil.

Pickers install their own buffer-local `<C-h/j/k/l>`, so the Neovim adapter reasserts its maps buffer-locally in those buffers too — it owns these keys there as well. If you need a picker to keep one of them, narrow `picker_filetype_patterns` or change `keymaps`. In `fzf`/`fzf-lua` terminal buffers the terminal-mode mapping passes the key through to the picker.

## Default keymaps

Normal and terminal mode:

- `<C-h>` / `<C-Left>`: left
- `<C-j>` / `<C-Down>`: down
- `<C-k>` / `<C-Up>`: up
- `<C-l>` / `<C-Right>`: right

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
  keymaps = {
    left = { "<C-h>", "<C-Left>" },
    down = { "<C-j>", "<C-Down>" },
    up = { "<C-k>", "<C-Up>" },
    right = { "<C-l>", "<C-Right>" },
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

## Herdr config

The helper must be bound in Herdr's keybindings. Generate a ready-to-paste snippet with the helper:

```sh
vim-herdr-navigator config            # ctrl+h/j/k/l
vim-herdr-navigator config --arrows   # also ctrl+arrow keys
```

It prints one block per direction, e.g.:

```toml
[[keys.command]]
key = "ctrl+h"
type = "shell"
command = "vim-herdr-navigator dispatch left"
description = "vim-aware pane left"
```

## Health

```vim
:checkhealth vim-herdr-navigator
```

Reports the Neovim version, whether you're in a Herdr session, whether `setup()` ran, and whether the helper is found and runnable. `:checkhealth` is Neovim-only; Vim support is covered by the smoke test.

## Help

```vim
:help vim-herdr-navigator
```

## Entry markers (opt-in)

When you move from another Herdr pane into a Vim/Neovim pane, an entry marker lets the plugin land you on the split nearest the edge you entered from, instead of wherever the cursor last was. It's **off by default**.

Enable it with a single environment variable — export it in your shell rc and restart Herdr:

```sh
export VIM_HERDR_NAVIGATOR_ENTRY_MARKERS=1
```

That one switch covers both halves: the helper writes the markers, and this plugin (which inherits Herdr's environment) reads them — there's no separate `setup()` option to keep in sync. The marker is a single-use file under `${XDG_CACHE_HOME:-~/.cache}/vim-herdr-navigator/entry/<pane-id>`; the plugin reads it on focus, jumps to the nearest split, and removes it (markers older than 10s are ignored).

## Local development

Point the plugin at a local checkout and at a local helper build. Adjust the paths to wherever you cloned the repos:

```lua
{
  dir = "~/projects/vim-herdr-navigator", -- local clone of this repo
  name = "vim-herdr-navigator",
  cond = function()
    return vim.env.HERDR_ENV == "1" or vim.env.HERDR_SOCKET_PATH ~= nil
  end,
  lazy = false,
  opts = {
    -- point at the helper's release build during development
    -- (run `cargo build --release` at the repo root first)
    helper = "~/projects/vim-herdr-navigator/target/release/vim-herdr-navigator",
  },
}
```

## Development

Run the dependency-free editor smoke tests and the Rust helper checks:

```sh
tests/run.sh       # Neovim
tests/run-vim.sh   # Vim
cargo fmt --all --check
cargo clippy --all-targets -- -D warnings
cargo test --all
```

The smoke tests load the plugin and exercise `setup()`/commands/navigation. The Neovim smoke test also runs `:checkhealth`.

## License

[MIT](LICENSE)
