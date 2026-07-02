# vim-herdr-navigator

This project is a [Herdr](https://github.com/herdr-org/herdr) implementation of [vim-tmux-navigator](https://github.com/christoomey/vim-tmux-navigator). It brings seamless navigation between herdr panes and vim/nvim splits.

vim-herdr-navigator also adds support for:

- Floating picker/explorer handling in Neovim (Snacks, Telescope, mini.pick, fzf/fzf-lua, neo-tree, NvimTree, oil, netrw).
- Opt-in entry markers (`VIM_HERDR_NAVIGATOR_ENTRY_MARKERS`) to land on the split nearest the entered edge.
- Env-var config shared by both halves: `VIM_HERDR_NAVIGATOR_PATTERN` (extra Vim-like detection) and `VIM_HERDR_NAVIGATOR_ZOOM` (unzoom on move).

