# herdr-vim-navigator.nvim

Neovim half of seamless [Herdr](https://herdr.dev/) + Neovim pane navigation — a
port of [`christoomey/vim-tmux-navigator`](https://github.com/christoomey/vim-tmux-navigator)'s core `h/j/k/l` navigation to Herdr.

A single set of `Ctrl-h/j/k/l` (and optionally `Ctrl-Arrow`) keys moves between Neovim splits and Herdr panes as if they were one grid: Neovim windows get first chance, and Herdr takes focus when Neovim hits an edge.

Pair it with the Herdr-side helper: [**herdr-vim-navigator**](https://github.com/AVGVSTVS96/herdr-vim-navigator).

## Requirements

- Neovim 0.8+ (0.10+ recommended)
- [Herdr](https://herdr.dev/)
- The [`herdr-vim-navigator`](https://github.com/AVGVSTVS96/herdr-vim-navigator) helper (a small Rust binary) installed and on your `PATH`

## Install

### lazy.nvim

```lua
{
  "AVGVSTVS96/herdr-vim-navigator.nvim",
  -- Only load inside a Herdr session.
  cond = function()
    return vim.env.HERDR_ENV == "1" or vim.env.HERDR_SOCKET_PATH ~= nil
  end,
  lazy = false,
  opts = {},
}
```

Zero config: `opts = {}` uses the defaults, and the helper is found on `PATH` as `herdr-vim-navigator`. See [Options](#options) to customize.

### vim.pack (Neovim 0.12+)

```lua
vim.pack.add({ "https://github.com/AVGVSTVS96/herdr-vim-navigator.nvim" })
-- setup() is auto-called on load; call it explicitly only to pass options:
-- require("herdr-vim-navigator").setup({})
```

### Other managers

Any manager works. After install, the plugin auto-calls `setup()` on load; pass options with `require("herdr-vim-navigator").setup({ ... })`.

Then wire up the Herdr side — see [Herdr config](#herdr-config).

## Behavior

Inside Neovim:

1. `Ctrl-h/j/k/l` or `Ctrl-Arrow` first tries normal Vim window navigation with `wincmd h/j/k/l`.
2. If the current Neovim window did not change (an edge), the plugin calls `herdr-vim-navigator focus <direction>`.
3. The helper focuses the neighboring Herdr pane.

From a non-Neovim Herdr pane, Herdr keybindings call `herdr-vim-navigator dispatch <direction>`, which decides whether to move Herdr focus or send `ctrl+h/j/k/l` into Neovim.

This mirrors `vim-tmux-navigator`: Vim windows get first chance, the multiplexer gets focus at an edge.

The plugin only acts inside a Herdr session (`HERDR_ENV=1` or `HERDR_SOCKET_PATH` set); elsewhere it stays inert.

### Keymaps and LazyVim

Like `vim-tmux-navigator`, enabling the plugin's maps (`set_keymaps = true`, the default) means it owns `<C-h/j/k/l>` (and `<C-Arrow>`): they are installed when `setup()` runs and reasserted after LazyVim installs its own `<C-h/j/k/l>` window maps on `User VeryLazy`, so navigation stays edge-aware without you editing your personal keymaps. To keep your own mapping on one of these keys, set `set_keymaps = false` and wire them up yourself via the [commands](#commands).

### Pickers and explorers

For known floating pickers/explorers, left navigation from a focused picker float goes straight to Herdr instead of bouncing focus back inside Neovim. Which filetypes count is configurable via `picker_filetype_patterns`; defaults cover Snacks picker/explorer, Telescope, mini.pick, fzf/fzf-lua, neo-tree, NvimTree, and oil.

Pickers install their own buffer-local `<C-h/j/k/l>`, so the plugin reasserts its maps buffer-locally in those buffers too — it owns these keys there as well. If you need a picker to keep one of them, narrow `picker_filetype_patterns` or change `keymaps`. In `fzf`/`fzf-lua` terminal buffers the terminal-mode mapping passes the key through to the picker.

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

Defaults shown:

```lua
require("herdr-vim-navigator").setup({
  helper = "herdr-vim-navigator", -- name or path of the helper command (~ is expanded)
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

To call `setup()` yourself at a specific time, disable auto-setup before the plugin loads:

```lua
vim.g.herdr_vim_navigator_auto_setup = false
```

## Herdr config

The helper must be bound in Herdr's keybindings. Generate a ready-to-paste snippet with the helper:

```sh
herdr-vim-navigator config            # ctrl+h/j/k/l
herdr-vim-navigator config --arrows   # also ctrl+arrow keys
```

It prints one block per direction, e.g.:

```toml
[[keys.command]]
key = "ctrl+h"
type = "shell"
command = "herdr-vim-navigator dispatch left"
description = "vim-aware pane left"
```

## Health

```vim
:checkhealth herdr-vim-navigator
```

Reports the Neovim version, whether you're in a Herdr session, whether `setup()` ran, and whether the helper is found and runnable.

## Help

```vim
:help herdr-vim-navigator
```

## Entry markers (opt-in)

When you move from another Herdr pane into a Neovim pane, an entry marker lets the plugin land you on the split nearest the edge you entered from, instead of wherever the cursor last was. It's **off by default**.

Enable it with a single environment variable — export it in your shell rc and restart Herdr:

```sh
export HERDR_VIM_NAVIGATOR_ENTRY_MARKERS=1
```

That one switch covers both halves: the helper writes the markers, and this plugin (which inherits Herdr's environment) reads them — there's no separate `setup()` option to keep in sync. The marker is a single-use file under `${XDG_CACHE_HOME:-~/.cache}/herdr-vim-navigator/entry/<pane-id>`; the plugin reads it on focus, jumps to the nearest split, and removes it (markers older than 10s are ignored).

## Local development

Point the plugin at a local checkout and at a local helper build. Adjust the paths to wherever you cloned the repos:

```lua
{
  dir = "~/projects/herdr-vim-navigator.nvim", -- local clone of this repo
  name = "herdr-vim-navigator.nvim",
  cond = function()
    return vim.env.HERDR_ENV == "1" or vim.env.HERDR_SOCKET_PATH ~= nil
  end,
  lazy = false,
  opts = {
    -- point at the helper's release build during development
    -- (run `cargo build --release` in the helper repo first)
    helper = "~/projects/herdr-vim-navigator/target/release/herdr-vim-navigator",
  },
}
```

## Development

Run the dependency-free smoke test (requires only `nvim` on `PATH`):

```sh
tests/run.sh
```

It loads the plugin, exercises `setup()`/commands, and runs `:checkhealth`.

## License

[MIT](LICENSE)
