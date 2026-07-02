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
"
" The Herdr environment is inherited at process spawn and fixed for the whole
" session, so a single check here is equivalent to gating every action. When we
" are not in a Herdr session there is nothing useful to do, so skip auto-setup
" entirely: don't load the autoload script, claim <C-h/j/k/l>, or register
" autocmds. An explicit vim_herdr_navigator#setup() still runs unconditionally
" for anyone who wants the commands to exist regardless.
if get(g:, 'vim_herdr_navigator_auto_setup', 1)
      \ && ($HERDR_ENV ==# '1' || (exists('$HERDR_SOCKET_PATH') && $HERDR_SOCKET_PATH !=# ''))
  call vim_herdr_navigator#setup()
endif
