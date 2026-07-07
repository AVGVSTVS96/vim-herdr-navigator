# vim-herdr-navigator

A [Herdr](https://github.com/herdr-org/herdr) port of [vim-tmux-navigator](https://github.com/christoomey/vim-tmux-navigator): seamless `Ctrl-h/j/k/l` navigation across Herdr panes and Vim/Neovim splits.

## Monorepo layout

- `helper/` — Rust binary, driven by Herdr keybindings.
- `lua/` + `plugin/vim-herdr-navigator.lua` — Neovim plugin (Lua).
- `autoload/` + `plugin/vim-herdr-navigator.vim` — Vim plugin (Vimscript).

The two sides hand off to each other: Herdr keybindings invoke the helper, which sends the key into the editor if the active pane is Vim-like, or moves Herdr focus otherwise. The editor plugin tries `wincmd` first; at a window edge it calls the helper to focus the neighboring Herdr pane.

Beyond vim-tmux-navigator, this project adds:

- Floating picker/explorer handling in Neovim (Snacks, Telescope, mini.pick, fzf/fzf-lua, neo-tree, NvimTree, oil, netrw).
- Opt-in entry markers (`VIM_HERDR_NAVIGATOR_ENTRY_MARKERS`) to land on the split nearest the entered edge.
- Env-var config shared by both halves: `VIM_HERDR_NAVIGATOR_PATTERN` (extra Vim-like detection) and `VIM_HERDR_NAVIGATOR_ZOOM` (unzoom on move).

## Rules

- Use conventional commit messages (`feat:`, `fix:`, ...): release-plz derives version bumps and changelog entries from them.
- No unnecessary comments, prefer self-documenting code and aim to have as few comments as possible, as concise as possible.

