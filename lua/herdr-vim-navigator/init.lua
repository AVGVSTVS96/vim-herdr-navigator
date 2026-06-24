local M = {}

local uv = vim.uv or vim.loop

-- Markers older than this (seconds) are treated as stale and ignored. A real
-- focus-into-pane applies the marker within milliseconds of the helper writing
-- it; anything older is left over from a focus that never reached Neovim.
local MARKER_STALE_SECONDS = 10

local defaults = {
  helper = "herdr-vim-navigator",
  set_keymaps = true,
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
-- Keymaps
--
-- Like vim-tmux-navigator, enabling the plugin's maps (`set_keymaps = true`,
-- the default) means it owns <C-h/j/k/l> (and <C-Arrow>): they are installed on
-- setup and reasserted after LazyVim's window maps. To keep your own mapping on
-- one of these keys, set `set_keymaps = false` and use the :HerdrNavigate*
-- commands.
-- --------------------------------------------------------------------------- --

local function set_normal_map(lhs, direction, buffer)
  vim.keymap.set("n", lhs, function()
    M.navigate(direction)
  end, {
    silent = true,
    buffer = buffer,
    desc = "Navigate " .. direction,
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
    desc = "Navigate " .. direction,
  })
end

local function install_global_keymaps()
  for direction, keys in pairs(config.keymaps) do
    local spec = directions[direction]
    if spec then
      for _, lhs in ipairs(keys) do
        set_normal_map(lhs, direction)
        set_terminal_map(lhs, direction, spec.command)
      end
    end
  end
end

-- Pickers/explorers install their own buffer-local <C-h/j/k/l> that would shadow
-- our global maps. Reassert ours buffer-locally so navigation works from inside
-- them too. (This is why the plugin owns these keys; pick different `keymaps` or
-- narrow `picker_filetype_patterns` if you need a picker to keep one of them.)
local function install_picker_keymaps()
  if not is_picker_like_buffer() then
    return
  end

  local buf = vim.api.nvim_get_current_buf()
  for direction, keys in pairs(config.keymaps) do
    if directions[direction] then
      for _, lhs in ipairs(keys) do
        set_normal_map(lhs, direction, buf)
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

  if config.set_keymaps then
    -- LazyVim installs its default <C-h/j/k/l> window maps on User VeryLazy.
    -- Reassert ours afterwards so they win, exactly as we own them on setup.
    vim.api.nvim_create_autocmd("User", {
      group = group,
      pattern = "VeryLazy",
      callback = install_global_keymaps,
    })

    -- Pickers install buffer-local maps after startup; reassert ours when
    -- entering known picker buffers.
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
    install_global_keymaps()
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
