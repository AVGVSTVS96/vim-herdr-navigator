local M = {}

local uv = vim.uv or vim.loop

-- All mappings we install carry this desc prefix so we can recognize our own
-- maps later (e.g. when deciding whether a reapply may replace one).
local MAP_DESC_PREFIX = "herdr-vim-navigator:"

-- Markers older than this (seconds) are treated as stale and ignored. A real
-- focus-into-pane applies the marker within milliseconds of the helper writing
-- it; anything older is left over from a focus that never reached Neovim.
local MARKER_STALE_SECONDS = 10

local defaults = {
  helper = "herdr-vim-navigator",
  set_keymaps = true,
  -- After LazyVim installs its default <C-h/j/k/l> window maps on User VeryLazy,
  -- reassert ours so navigation stays edge-aware. The reapply only replaces a
  -- window-navigation map (LazyVim's `<C-w>hjkl`, a `wincmd`, etc.) or one of
  -- our own maps — never a custom user mapping. Set false to skip it entirely.
  reapply_after_lazyvim = true,
  save_on_switch = 0, -- 0 = never, 1 = :update current buffer, 2 = :wall
  picker_filetype_patterns = {
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
}

local directions = {
  left = { command = "HerdrNavigateLeft", wincmd = "h" },
  down = { command = "HerdrNavigateDown", wincmd = "j" },
  up = { command = "HerdrNavigateUp", wincmd = "k" },
  right = { command = "HerdrNavigateRight", wincmd = "l" },
}

local config = vim.deepcopy(defaults)
local did_setup = false
local warned_missing_helper = false

local function in_herdr()
  return vim.env.HERDR_ENV == "1" or vim.env.HERDR_SOCKET_PATH ~= nil
end

local function pane_id()
  -- Inside Neovim, HERDR_PANE_ID is the pane Neovim belongs to. Prefer it over
  -- HERDR_ACTIVE_PANE_ID, which is mainly useful for Herdr-launched commands.
  return vim.env.HERDR_PANE_ID or vim.env.HERDR_ACTIVE_PANE_ID
end

local function cache_home()
  return vim.env.XDG_CACHE_HOME or (vim.env.HOME .. "/.cache")
end

local function entry_dir()
  return cache_home() .. "/herdr-vim-navigator/entry"
end

local function remove_file(path)
  pcall(os.remove, path)
end

local function executable(command)
  local expanded = vim.fn.expand(command)
  if vim.fn.executable(expanded) == 1 then
    return expanded
  end
  if vim.fn.executable(command) == 1 then
    return command
  end
  return nil
end

local function notify_once_missing_helper()
  if warned_missing_helper then
    return
  end
  warned_missing_helper = true
  vim.notify(
    "herdr-vim-navigator.nvim: helper not executable: " .. tostring(config.helper),
    vim.log.levels.WARN
  )
end

local function run_helper(args)
  if not in_herdr() then
    return
  end

  local helper = executable(config.helper)
  if not helper then
    notify_once_missing_helper()
    return
  end

  local command = vim.list_extend({ helper }, args)
  if vim.system then
    vim.system(command, { text = true }, function() end)
  else
    vim.fn.jobstart(command, { detach = true })
  end
end

local function save_before_switch()
  if config.save_on_switch == 1 then
    pcall(vim.cmd, "silent update")
  elseif config.save_on_switch == 2 then
    pcall(vim.cmd, "silent wall")
  end
end

local function focus_herdr(direction)
  save_before_switch()
  if in_herdr() then
    run_helper({ "focus", direction })
  end
end

local function current_window_is_floating()
  return vim.api.nvim_win_get_config(0).relative ~= ""
end

local function is_picker_like_buffer()
  local filetype = vim.bo.filetype
  for _, pattern in ipairs(config.picker_filetype_patterns or {}) do
    if filetype:match(pattern) then
      return true
    end
  end
  return false
end

local function is_fzf_terminal()
  return vim.bo.filetype == "fzf" or vim.bo.filetype == "fzf-lua"
end

-- --------------------------------------------------------------------------- --
-- Keymap policy
-- --------------------------------------------------------------------------- --

local function desc_for(direction)
  return MAP_DESC_PREFIX .. " navigate " .. direction
end

local function maparg(mode, lhs)
  -- Returns the mapping that would fire for `lhs` in the current buffer (a
  -- buffer-local map shadows a global one), as a dict; {} when unmapped.
  return vim.fn.maparg(lhs, mode, false, true) or {}
end

local function map_is_ours(m)
  return type(m.desc) == "string" and m.desc:sub(1, #MAP_DESC_PREFIX) == MAP_DESC_PREFIX
end

local function map_is_buffer_local(m)
  return (m.buffer or 0) ~= 0
end

-- True when a mapping is a window-navigation map we may safely replace: the
-- LazyVim/standard `<C-w>hjkl` window maps, or a `wincmd h/j/k/l`. We never
-- treat an unrelated user mapping (e.g. `<C-h>` -> `:bprev`) as replaceable.
local function map_is_window_nav(m)
  local rhs = m.rhs
  if type(rhs) ~= "string" or rhs == "" then
    return false
  end
  local norm = rhs:lower():gsub("%s+", "")
  if norm:match("^<c%-w>[hjkl]$") then
    return true
  end
  if norm:match("^<c%-w><c%-[hjkl]>$") then
    return true
  end
  if norm:match("wincmd[hjkl]") then
    return true
  end
  return false
end

local function set_normal_map(lhs, direction, buffer)
  vim.keymap.set("n", lhs, function()
    M.navigate(direction)
  end, {
    silent = true,
    buffer = buffer,
    desc = desc_for(direction),
  })
end

local function set_terminal_map(lhs, direction, command, buffer)
  vim.keymap.set("t", lhs, function()
    if is_fzf_terminal() then
      return lhs
    end
    return "<C-\\><C-n><cmd>" .. command .. "<cr>"
  end, {
    expr = true,
    replace_keycodes = true,
    silent = true,
    buffer = buffer,
    desc = desc_for(direction),
  })
end

-- Decide whether we may install our global map over whatever currently holds
-- `lhs`. `safe` (used by the LazyVim reapply) refuses to replace anything but a
-- window-navigation map or one of our own; the initial install is unconditional
-- (enabling the plugin's maps is what `set_keymaps = true` opts into).
local function may_install_global(mode, lhs, safe)
  local m = maparg(mode, lhs)
  if vim.tbl_isempty(m) then
    return true
  end
  if map_is_ours(m) then
    return true
  end
  if not safe then
    return true
  end
  return map_is_window_nav(m)
end

local function install_global_keymaps(safe)
  for direction, keys in pairs(config.keymaps) do
    local spec = directions[direction]
    if spec then
      for _, lhs in ipairs(keys) do
        if may_install_global("n", lhs, safe) then
          set_normal_map(lhs, direction)
        end
        if may_install_global("t", lhs, safe) then
          set_terminal_map(lhs, direction, spec.command)
        end
      end
    end
  end
end

-- Install buffer-local maps in a picker/explorer buffer, but only where the
-- picker has not claimed the key for itself. We never override a picker's own
-- buffer-local mapping — in that case the picker's binding wins and navigation
-- out of the picker in that direction uses the picker's key instead.
local function install_picker_keymaps()
  if not is_picker_like_buffer() then
    return
  end

  local buf = vim.api.nvim_get_current_buf()
  for direction, keys in pairs(config.keymaps) do
    if directions[direction] then
      for _, lhs in ipairs(keys) do
        local m = maparg("n", lhs)
        local picker_owns_it = map_is_buffer_local(m) and not map_is_ours(m)
        if not picker_owns_it then
          set_normal_map(lhs, direction, buf)
        end
      end
    end
  end
end

-- --------------------------------------------------------------------------- --
-- Entry markers
-- --------------------------------------------------------------------------- --

function M.apply_entry_marker()
  if not in_herdr() then
    return
  end

  local id = pane_id()
  if not id or id == "" then
    return
  end

  local path = entry_dir() .. "/" .. id
  local stat = uv.fs_stat(path)
  if not stat then
    return
  end

  local file = io.open(path, "r")
  if not file then
    return
  end
  local marker = file:read("*a") or ""
  file:close()
  -- The marker is single-use: remove it whether or not we end up applying it.
  remove_file(path)

  local mtime = (stat.mtime and stat.mtime.sec) or 0
  if os.time() - mtime > MARKER_STALE_SECONDS then
    return
  end

  local wincmd = marker:gsub("%s+", "")
  if not wincmd:match("^[hjkl]$") then
    return
  end

  vim.schedule(function()
    pcall(vim.cmd, "999wincmd " .. wincmd)
  end)
end

-- --------------------------------------------------------------------------- --
-- Navigation
-- --------------------------------------------------------------------------- --

function M.navigate(direction)
  local spec = directions[direction]
  if not spec then
    return
  end

  -- Floating pickers/explorers often intercept `wincmd h` from their leftmost
  -- list/prompt window and bounce focus back inside Neovim instead of reaching
  -- the multiplexer edge. From a focused floating picker, treat left as an
  -- escape straight to Herdr; other directions still use normal Vim window
  -- navigation. Which filetypes count as pickers is configurable via
  -- `picker_filetype_patterns`.
  if is_picker_like_buffer() and current_window_is_floating() then
    if direction == "left" then
      focus_herdr(direction)
    else
      pcall(vim.cmd, "wincmd " .. spec.wincmd)
    end
    return
  end

  local current = vim.api.nvim_get_current_win()
  pcall(vim.cmd, "wincmd " .. spec.wincmd)

  if vim.api.nvim_get_current_win() ~= current then
    return
  end

  focus_herdr(direction)
end

-- --------------------------------------------------------------------------- --
-- Setup
-- --------------------------------------------------------------------------- --

local function create_commands()
  for direction, spec in pairs(directions) do
    pcall(vim.api.nvim_create_user_command, spec.command, function()
      M.navigate(direction)
    end, {})
  end
end

local function create_autocmds()
  local group = vim.api.nvim_create_augroup("HerdrVimNavigator", { clear = true })

  vim.api.nvim_create_autocmd({ "VimEnter", "FocusGained", "WinEnter" }, {
    group = group,
    callback = M.apply_entry_marker,
  })

  if config.set_keymaps and config.reapply_after_lazyvim then
    -- LazyVim installs its default <C-h/j/k/l> window maps on User VeryLazy.
    -- Reassert ours afterwards so they stay edge-aware — but only over those
    -- window maps or our own (see may_install_global), never a user's custom
    -- mapping.
    vim.api.nvim_create_autocmd("User", {
      group = group,
      pattern = "VeryLazy",
      callback = function()
        install_global_keymaps(true)
      end,
    })
  end

  if config.set_keymaps then
    -- Pickers install buffer-local maps after startup. Assert our maps
    -- buffer-locally when entering known picker buffers, without clobbering the
    -- picker's own keys.
    vim.api.nvim_create_autocmd({ "FileType", "BufEnter" }, {
      group = group,
      callback = install_picker_keymaps,
    })
  end
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  create_commands()
  if config.set_keymaps then
    install_global_keymaps(false)
  end
  create_autocmds()
  did_setup = true
end

function M.is_setup()
  return did_setup
end

-- Return the effective config (defaults merged with any setup() opts). Used by
-- `:checkhealth herdr-vim-navigator`.
function M.get_config()
  return vim.deepcopy(config)
end

-- Resolve the configured helper to an executable path, or nil if not found.
function M.resolve_helper()
  return executable(config.helper)
end

-- True when running inside a Herdr session.
function M.in_herdr()
  return in_herdr()
end

M._defaults = defaults
M._directions = directions

return M
