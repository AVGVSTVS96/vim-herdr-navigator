# herdr-vim-navigator.nvim

Neovim half of seamless Herdr + Neovim pane navigation.

Use this with the companion `herdr-vim-navigator` helper.

## Behavior

Inside Neovim:

1. `Ctrl-h/j/k/l` or `Ctrl-Arrow` first tries normal Vim window navigation with `wincmd h/j/k/l`.
2. If the current Neovim window did not change, the plugin calls:

   ```sh
   herdr-vim-navigator focus <direction>
   ```

3. The helper focuses the neighboring Herdr pane.

From a non-Neovim Herdr pane, Herdr keybindings call:

```sh
herdr-vim-navigator dispatch <direction>
```

That helper decides whether to move Herdr focus or send `ctrl+h/j/k/l` into Neovim.

This mirrors the core idea from `christoomey/vim-tmux-navigator`: Vim windows get first chance, the multiplexer gets focus when Vim hits an edge.

## Lazy.nvim

```lua
{
  dir = "~/Documents/GitHub/side-projects/herdr-vim-navigator.nvim",
  name = "herdr-vim-navigator.nvim",
  cond = function()
    return vim.env.HERDR_ENV == "1" or vim.env.HERDR_SOCKET_PATH ~= nil
  end,
  lazy = false,
  opts = {
    helper = "~/Documents/GitHub/side-projects/herdr-vim-navigator/bin/herdr-vim-navigator",
  },
}
```

## Default keymaps

Normal and terminal mode:

- `<C-h>` / `<C-Left>`: left
- `<C-j>` / `<C-Down>`: down
- `<C-k>` / `<C-Up>`: up
- `<C-l>` / `<C-Right>`: right

In `fzf` terminal buffers the terminal-mode mappings pass the key through to fzf.

## Commands

- `:HerdrNavigateLeft`
- `:HerdrNavigateDown`
- `:HerdrNavigateUp`
- `:HerdrNavigateRight`
- `:HerdrNavigatorRegister`
- `:HerdrNavigatorUnregister`

## Options

```lua
require("herdr-vim-navigator").setup({
  helper = "herdr-vim-navigator",
  set_keymaps = true,
  register_pane = true,
  save_on_switch = 0, -- 0 never, 1 :update, 2 :wall
  keymaps = {
    left = { "<C-h>", "<C-Left>" },
    down = { "<C-j>", "<C-Down>" },
    up = { "<C-k>", "<C-Up>" },
    right = { "<C-l>", "<C-Right>" },
  },
})
```

## Pane registration and entry markers

The plugin marks its pane here:

```text
${XDG_CACHE_HOME:-~/.cache}/herdr-vim-navigator/panes/<pane-id>
```

The helper can use that marker to know that a neighbor is Neovim.

When Herdr focuses into a Neovim pane, the helper writes an entry marker here:

```text
${XDG_CACHE_HOME:-~/.cache}/herdr-vim-navigator/entry/<pane-id>
```

The plugin reads it on focus and jumps to the Vim split nearest the edge that was entered.
