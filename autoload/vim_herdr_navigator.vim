" Classic Vim adapter for vim-herdr-navigator.

let s:marker_stale_seconds = 10

let s:defaults = {
      \ 'helper': 'vim-herdr-navigator',
      \ 'set_keymaps': 1,
      \ 'save_on_switch': 0,
      \ 'keymaps': {
      \   'left': ['<C-h>', '<C-Left>'],
      \   'down': ['<C-j>', '<C-Down>'],
      \   'up': ['<C-k>', '<C-Up>'],
      \   'right': ['<C-l>', '<C-Right>'],
      \ },
      \ }

let s:directions = {
      \ 'left': {'command': 'HerdrNavigateLeft', 'wincmd': 'h'},
      \ 'down': {'command': 'HerdrNavigateDown', 'wincmd': 'j'},
      \ 'up': {'command': 'HerdrNavigateUp', 'wincmd': 'k'},
      \ 'right': {'command': 'HerdrNavigateRight', 'wincmd': 'l'},
      \ }

let s:config = deepcopy(s:defaults)
let s:did_setup = 0
let s:warned_missing_helper = 0

function! s:truthy_env(name) abort
  let l:value = eval('$' . a:name)
  return l:value ==# '1' || l:value ==# 'true'
endfunction

function! s:in_herdr() abort
  return $HERDR_ENV ==# '1' || (exists('$HERDR_SOCKET_PATH') && $HERDR_SOCKET_PATH !=# '')
endfunction

function! s:entry_markers_enabled() abort
  return s:truthy_env('VIM_HERDR_NAVIGATOR_ENTRY_MARKERS')
endfunction

function! s:pane_id() abort
  if exists('$HERDR_PANE_ID') && $HERDR_PANE_ID !=# ''
    return $HERDR_PANE_ID
  endif
  if exists('$HERDR_ACTIVE_PANE_ID') && $HERDR_ACTIVE_PANE_ID !=# ''
    return $HERDR_ACTIVE_PANE_ID
  endif
  return ''
endfunction

function! s:cache_home() abort
  if exists('$XDG_CACHE_HOME') && $XDG_CACHE_HOME !=# ''
    return $XDG_CACHE_HOME
  endif
  return $HOME . '/.cache'
endfunction

function! s:entry_dir() abort
  return s:cache_home() . '/vim-herdr-navigator/entry'
endfunction

function! s:resolve_helper() abort
  let l:expanded = expand(s:config.helper)
  if executable(l:expanded)
    return l:expanded
  endif
  if executable(s:config.helper)
    return s:config.helper
  endif
  return ''
endfunction

function! s:notify_once_missing_helper() abort
  if s:warned_missing_helper
    return
  endif
  let s:warned_missing_helper = 1
  echohl WarningMsg
  echomsg 'vim-herdr-navigator: helper not executable: ' . string(s:config.helper)
  echohl None
endfunction

function! s:shell_join(argv) abort
  return join(map(copy(a:argv), 'shellescape(v:val)'), ' ')
endfunction

function! s:run_helper(args) abort
  if !s:in_herdr()
    return
  endif

  let l:helper = s:resolve_helper()
  if l:helper ==# ''
    call s:notify_once_missing_helper()
    return
  endif

  let l:cmd = [l:helper] + a:args
  if exists('*job_start')
    call job_start(l:cmd, {'in_io': 'null', 'out_io': 'null', 'err_io': 'null'})
  else
    silent call system(s:shell_join(l:cmd))
  endif
endfunction

function! s:save_before_switch() abort
  if get(s:config, 'save_on_switch', 0) == 1
    silent! update
  elseif get(s:config, 'save_on_switch', 0) == 2
    silent! wall
  endif
endfunction

function! s:focus_herdr(direction) abort
  call s:save_before_switch()
  call s:run_helper(['focus', a:direction])
endfunction

function! s:create_commands() abort
  command! HerdrNavigateLeft call vim_herdr_navigator#navigate('left')
  command! HerdrNavigateDown call vim_herdr_navigator#navigate('down')
  command! HerdrNavigateUp call vim_herdr_navigator#navigate('up')
  command! HerdrNavigateRight call vim_herdr_navigator#navigate('right')
endfunction

function! s:map_rhs(direction) abort
  return ':<C-U>call vim_herdr_navigator#navigate(' . string(a:direction) . ')<CR>'
endfunction

function! s:terminal_map_rhs(direction) abort
  return '<C-W>N:call vim_herdr_navigator#navigate(' . string(a:direction) . ')<CR>'
endfunction

function! s:install_keymaps() abort
  for l:direction in keys(get(s:config, 'keymaps', {}))
    if !has_key(s:directions, l:direction)
      continue
    endif
    for l:lhs in get(s:config.keymaps, l:direction, [])
      execute 'nnoremap <silent> ' . l:lhs . ' ' . s:map_rhs(l:direction)
      if exists(':tnoremap') == 2
        execute 'tnoremap <silent> ' . l:lhs . ' ' . s:terminal_map_rhs(l:direction)
      endif
    endfor
  endfor
endfunction

function! s:create_autocmds() abort
  augroup VimHerdrNavigator
    autocmd!
    if s:entry_markers_enabled()
      autocmd VimEnter,FocusGained,WinEnter * call vim_herdr_navigator#apply_entry_marker()
    endif
  augroup END
endfunction

function! s:merge_config(opts) abort
  let s:config = deepcopy(s:defaults)

  " Vim users configure the auto-setup path via g:vim_herdr_navigator_*.
  for l:key in ['helper', 'set_keymaps', 'save_on_switch', 'keymaps']
    let l:gkey = 'vim_herdr_navigator_' . l:key
    if exists('g:' . l:gkey)
      let s:config[l:key] = deepcopy(get(g:, l:gkey))
    endif
  endfor

  for [l:key, l:value] in items(a:opts)
    if l:key ==# 'keymaps' && type(l:value) == type({})
      call extend(s:config.keymaps, deepcopy(l:value), 'force')
    else
      let s:config[l:key] = deepcopy(l:value)
    endif
  endfor
endfunction

function! vim_herdr_navigator#setup(...) abort
  let l:opts = a:0 ? a:1 : {}
  if type(l:opts) != type({})
    let l:opts = {}
  endif

  call s:merge_config(l:opts)
  call s:create_commands()
  if get(s:config, 'set_keymaps', 1)
    call s:install_keymaps()
  endif
  call s:create_autocmds()
  let s:did_setup = 1
endfunction

function! vim_herdr_navigator#is_setup() abort
  return s:did_setup
endfunction

function! vim_herdr_navigator#get_config() abort
  return deepcopy(s:config)
endfunction

function! vim_herdr_navigator#resolve_helper() abort
  return s:resolve_helper()
endfunction

function! vim_herdr_navigator#in_herdr() abort
  return s:in_herdr()
endfunction

function! vim_herdr_navigator#apply_entry_marker() abort
  if !s:entry_markers_enabled() || !s:in_herdr()
    return
  endif

  let l:id = s:pane_id()
  if l:id ==# ''
    return
  endif

  let l:path = s:entry_dir() . '/' . l:id
  if !filereadable(l:path)
    return
  endif

  let l:mtime = getftime(l:path)
  try
    let l:marker = join(readfile(l:path), "\n")
  catch
    return
  finally
    call delete(l:path)
  endtry

  if l:mtime <= 0 || localtime() - l:mtime > s:marker_stale_seconds
    return
  endif

  let l:wincmd = substitute(l:marker, '\s\+', '', 'g')
  if l:wincmd !~# '^[hjkl]$'
    return
  endif

  silent! execute '999wincmd ' . l:wincmd
endfunction

function! vim_herdr_navigator#navigate(direction) abort
  if !has_key(s:directions, a:direction)
    return
  endif

  let l:current = win_getid()
  silent! execute 'wincmd ' . s:directions[a:direction].wincmd

  if win_getid() != l:current
    return
  endif

  call s:focus_herdr(a:direction)
endfunction
