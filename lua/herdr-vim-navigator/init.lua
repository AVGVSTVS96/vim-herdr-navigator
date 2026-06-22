local M = {}

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

function M.apply_entry_marker()
  if not in_herdr() then
    return
  end

  local id = pane_id()
  if not id or id == "" then
    return
  end

  local path = entry_dir() .. "/" .. id
  local file = io.open(path, "r")
  if not file then
    return
  end

  local marker = file:read("*a") or ""
  file:close()
  remove_file(path)

  local wincmd = marker:match("[hjkl]")
  if not wincmd then
    return
  end

  vim.schedule(function()
    pcall(vim.cmd, "999wincmd " .. wincmd)
  end)
end

function M.navigate(direction)
  local spec = directions[direction]
  if not spec then
    return
  end

  -- Floating pickers/explorers often intercept `wincmd h` from their leftmost
  -- list/prompt window and bounce focus back inside Neovim instead of reaching
  -- the multiplexer edge. This mirrors the user's old tmux workaround: when
  -- focused in a known floating picker/explorer and moving left, go straight to
  -- Herdr; other directions can still use normal Vim window navigation.
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

local function create_commands()
  for direction, spec in pairs(directions) do
    pcall(vim.api.nvim_create_user_command, spec.command, function()
      M.navigate(direction)
    end, {})
  end
end

local function map_normal(lhs, direction, opts)
  opts = vim.tbl_extend("force", { silent = true, desc = "Navigate " .. direction }, opts or {})
  vim.keymap.set("n", lhs, function()
    M.navigate(direction)
  end, opts)
end

local function map_terminal(lhs, direction, command)
  vim.keymap.set("t", lhs, function()
    if is_fzf_terminal() then
      return lhs
    end
    return "<C-\\><C-n><cmd>" .. command .. "<cr>"
  end, {
    expr = true,
    replace_keycodes = true,
    silent = true,
    desc = "Navigate " .. direction,
  })
end

local function create_keymaps()
  for direction, keys in pairs(config.keymaps) do
    local spec = directions[direction]
    if spec then
      for _, lhs in ipairs(keys) do
        map_normal(lhs, direction)
        map_terminal(lhs, direction, spec.command)
      end
    end
  end
end

local function setup_picker_keymaps()
  if not is_picker_like_buffer() then
    return
  end

  for direction, keys in pairs(config.keymaps) do
    if directions[direction] then
      for _, lhs in ipairs(keys) do
        map_normal(lhs, direction, { buffer = true })
      end
    end
  end
end

local function create_autocmds()
  local group = vim.api.nvim_create_augroup("HerdrVimNavigator", { clear = true })

  vim.api.nvim_create_autocmd({ "VimEnter", "FocusGained", "WinEnter" }, {
    group = group,
    callback = M.apply_entry_marker,
  })

  -- LazyVim installs its default <C-h/j/k/l> window maps on User VeryLazy.
  -- Re-apply after that event so our edge-aware maps win without requiring
  -- users to edit their personal keymaps.lua.
  if config.set_keymaps then
    vim.api.nvim_create_autocmd("User", {
      group = group,
      pattern = "VeryLazy",
      callback = create_keymaps,
    })

    -- Pickers often install buffer-local maps after startup. Re-assert our maps
    -- buffer-locally when entering known picker buffers so Ctrl-h can escape left.
    vim.api.nvim_create_autocmd({ "FileType", "BufEnter" }, {
      group = group,
      callback = setup_picker_keymaps,
    })
  end
end

function M.setup(opts)
  config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  create_commands()
  if config.set_keymaps then
    create_keymaps()
  end
  create_autocmds()
  did_setup = true
end

function M.is_setup()
  return did_setup
end

M._defaults = defaults
M._directions = directions

return M
