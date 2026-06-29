" Vimscript adapter for classic Vim. Neovim uses plugin/vim-herdr-navigator.lua.
if has('nvim')
  finish
endif

if exists('g:loaded_vim_herdr_navigator') && g:loaded_vim_herdr_navigator == 1
  finish
endif
let g:loaded_vim_herdr_navigator = 1

" Auto-setup keeps the plugin usable with package managers that only add the
" repo to 'runtimepath'. Users can opt out before loading the plugin:
"   let g:vim_herdr_navigator_auto_setup = 0
if get(g:, 'vim_herdr_navigator_auto_setup', 1)
  call vim_herdr_navigator#setup()
endif
