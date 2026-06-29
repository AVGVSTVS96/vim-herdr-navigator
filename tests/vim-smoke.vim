" Dependency-free smoke test for the classic Vim adapter. Run via
" tests/run-vim.sh. Appends human-readable output to $VIM_HERDR_NAVIGATOR_TEST_LOG
" and exits non-zero on the first failed run.

set nomore
set nocompatible

let s:failures = 0
let s:log = $VIM_HERDR_NAVIGATOR_TEST_LOG

let $HERDR_ENV = ''
let $HERDR_SOCKET_PATH = ''
let $HERDR_PANE_ID = ''
let $HERDR_ACTIVE_PANE_ID = ''
let $VIM_HERDR_NAVIGATOR_ENTRY_MARKERS = ''

function! s:out(line) abort
  if s:log !=# ''
    call writefile([a:line], s:log, 'a')
  endif
endfunction

function! s:check(name, ok, ...) abort
  if a:ok
    call s:out('ok   - ' . a:name)
  else
    let s:failures += 1
    call s:out('FAIL - ' . a:name . (a:0 ? ': ' . string(a:1) : ''))
  endif
endfunction

function! s:pcall(name, Fn, ...) abort
  try
    call call(a:Fn, a:000)
    call s:check(a:name, 1)
  catch
    call s:check(a:name, 0, v:exception)
  endtry
endfunction

runtime plugin/vim-herdr-navigator.vim

call s:check('plugin loaded', exists('g:loaded_vim_herdr_navigator') && g:loaded_vim_herdr_navigator == 1)
call s:check('auto setup ran', vim_herdr_navigator#is_setup())

call vim_herdr_navigator#setup({'save_on_switch': 2, 'helper': 'custom-helper-name'})
let s:cfg = vim_herdr_navigator#get_config()
call s:check('setup merges custom option', s:cfg.save_on_switch == 2)
call s:check('setup keeps default keymaps', type(s:cfg.keymaps) == type({}) && has_key(s:cfg.keymaps, 'left'))
call s:check('is_setup() is true after setup', vim_herdr_navigator#is_setup())

for s:name in ['HerdrNavigateLeft', 'HerdrNavigateDown', 'HerdrNavigateUp', 'HerdrNavigateRight']
  call s:check('command ' . s:name . ' exists', exists(':' . s:name) == 2)
endfor

call s:check('resolve_helper returns empty for missing helper', vim_herdr_navigator#resolve_helper() ==# '')
call s:pcall('navigate(left) does not error', function('vim_herdr_navigator#navigate'), 'left')
call s:pcall('navigate(bogus) does not error', function('vim_herdr_navigator#navigate'), 'nowhere')

let s:map = maparg("\<C-h>", 'n', 0, 1)
call s:check('global <C-h> is our map', type(s:map) == type({}) && get(s:map, 'rhs', '') =~# 'vim_herdr_navigator#navigate')

let s:cache = tempname()
call mkdir(s:cache . '/vim-herdr-navigator/entry', 'p')
let $XDG_CACHE_HOME = s:cache
let $HERDR_ENV = '1'
let $HERDR_PANE_ID = 'testpane'
let s:marker_path = s:cache . '/vim-herdr-navigator/entry/testpane'

function! s:leftmost_window() abort
  silent! only
  vsplit | vsplit
  wincmd h
  return win_getid()
endfunction

" Off without the env var: a fresh marker is ignored.
let s:lm = s:leftmost_window()
call writefile(['l'], s:marker_path)
call vim_herdr_navigator#apply_entry_marker()
call s:check('markers off without env var', win_getid() == s:lm)
call delete(s:marker_path)

" Fresh, valid marker should move focus away from the leftmost window.
let $VIM_HERDR_NAVIGATOR_ENTRY_MARKERS = '1'
let s:lm = s:leftmost_window()
call writefile(['l'], s:marker_path)
call vim_herdr_navigator#apply_entry_marker()
call s:check('fresh valid marker moved focus', win_getid() != s:lm)
call s:check('fresh marker removed after read', !filereadable(s:marker_path))

" Invalid marker is removed but not applied.
let s:lm = s:leftmost_window()
call writefile(['nope'], s:marker_path)
call vim_herdr_navigator#apply_entry_marker()
call s:check('invalid marker is ignored', win_getid() == s:lm)
call s:check('invalid marker removed after read', !filereadable(s:marker_path))
silent! only

if s:failures == 0
  call s:out('')
  call s:out('All Vim smoke tests passed.')
  qall!
else
  call s:out('')
  call s:out(s:failures . ' failure(s).')
  cquit
endif
