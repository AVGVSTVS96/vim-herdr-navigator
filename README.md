# herdr-vim-navigator.nvim

Neovim half of seamless [Herdr](https://herdr.dev/) + Neovim pane navigation — a
[`christoomey/vim-tmux-navigator`](https://github.com/christoomey/vim-tmux-navigator) equivalent for Herdr.

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

With `set_keymaps = true` (the default) the plugin installs its `<C-h/j/k/l>` (and `<C-Arrow>`) maps when `setup()` runs — the same opt-in model as `vim-tmux-navigator`.

LazyVim installs its own `<C-h/j/k/l>` window maps later, on `User VeryLazy`. To stay edge-aware the plugin reasserts its maps after that event (`reapply_after_lazyvim`, on by default), but **only where it is safe**: it replaces a window-navigation map (LazyVim's `<C-w>hjkl`, a `wincmd h/j/k/l`, etc.) or one of its own maps. A custom mapping you put on one of these keys is never overwritten. Set `reapply_after_lazyvim = false` to skip the reapply, or `set_keymaps = false` to manage every key yourself via the [commands](#commands).

### Pickers and explorers

For known floating pickers/explorers, left navigation from a focused picker float goes straight to Herdr instead of bouncing focus back inside Neovim. Which filetypes count is configurable via `picker_filetype_patterns`; defaults cover Snacks picker/explorer, Telescope, mini.pick, fzf/fzf-lua, neo-tree, NvimTree, and oil.

In picker buffers the plugin installs its navigation maps **only on keys the picker has not already claimed**. If a picker binds one of these keys for its own use (e.g. `<C-j>`/`<C-k>` to move the selection), that binding is preserved and navigating out of the picker in that direction uses the picker's key. In `fzf`/`fzf-lua` terminal buffers the terminal-mode mapping passes the key through to the picker.

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
  reapply_after_lazyvim = true,   -- reassert maps after LazyVim's User VeryLazy (window-nav/our maps only)
  save_on_switch = 0,             -- 0 never, 1 :update, 2 :wall (save before leaving Neovim)
  picker_filetype_patterns = {    -- filetypes treated as floating pickers
    "^snacks_picker",
    "^Telescope",
    "^minipick$",
    "^fzf$",
    "^fzf%-lua$",
    "^neo%-tree$",
    "^NvimTree$",
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

## Entry markers

The helper uses live `herdr pane process-info` to identify Neovim panes. When Herdr focuses into a Neovim pane, the helper writes an entry marker here:

```text
${XDG_CACHE_HOME:-~/.cache}/herdr-vim-navigator/entry/<pane-id>
```

The plugin reads it on focus and jumps to the Vim split nearest the edge that was entered.

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
