-- Dependency-free smoke test. Run via tests/run.sh (or see the command there).
-- Loads the plugin, exercises setup()/commands/health, and exits non-zero on
-- the first failure so it can run in CI.

local failures = 0

-- Make the smoke test deterministic even when it is launched from inside Herdr.
-- Individual test cases opt back into Herdr env vars when they need them.
vim.env.HERDR_ENV = nil
vim.env.HERDR_SOCKET_PATH = nil
vim.env.HERDR_PANE_ID = nil
vim.env.HERDR_ACTIVE_PANE_ID = nil

local function check(name, ok, detail)
  if ok then
    io.stdout:write("ok   - " .. name .. "\n")
  else
    failures = failures + 1
    io.stdout:write("FAIL - " .. name .. (detail and (": " .. tostring(detail)) or "") .. "\n")
  end
end

-- 1. Load the plugin file and the module.
vim.cmd("runtime plugin/herdr-vim-navigator.lua")
local ok, nav = pcall(require, "herdr-vim-navigator")
check("module loads", ok, nav)
if not ok then
  vim.cmd("cq")
end

-- 2. setup() merges options over defaults.
nav.setup({ save_on_switch = 2, helper = "custom-helper-name" })
local cfg = nav.get_config()
check("setup merges custom option", cfg.save_on_switch == 2)
check("setup keeps default keymaps", type(cfg.keymaps) == "table" and cfg.keymaps.left ~= nil)
check("is_setup() is true after setup", nav.is_setup() == true)

-- 3. User commands are created.
local commands = vim.api.nvim_get_commands({})
for _, name in ipairs({ "HerdrNavigateLeft", "HerdrNavigateDown", "HerdrNavigateUp", "HerdrNavigateRight" }) do
  check("command " .. name .. " exists", commands[name] ~= nil)
end

-- 4. resolve_helper handles a missing helper gracefully.
check("resolve_helper returns nil for missing helper", nav.resolve_helper() == nil)

-- 5. navigate() is callable without error (no Herdr session in test env).
check("navigate(left) does not error", pcall(nav.navigate, "left"))
check("navigate(bogus) does not error", pcall(nav.navigate, "nowhere"))

-- 5b. Keymaps: when set_keymaps is on, the plugin owns <C-h/j/k/l> (same model
-- as vim-tmux-navigator). Our maps carry a "Navigate <dir>" desc.
local function maparg_dict(lhs, mode)
  return vim.fn.maparg(lhs, mode or "n", false, true) or {}
end
local function is_ours(m, direction)
  return m.desc == ("Navigate " .. direction)
end
check("global <C-h> is our map", is_ours(maparg_dict("<C-h>"), "left"))

-- 5c. The VeryLazy reapply wins over LazyVim's window maps (it owns the key).
vim.keymap.set("n", "<C-Up>", "<C-w>k", { desc = "Go to Upper Window", remap = true })
vim.cmd("doautocmd User VeryLazy")
check("reapply reclaims <C-Up> over a window map", is_ours(maparg_dict("<C-Up>"), "up"))

-- 5d. Picker buffers: the plugin reasserts its maps buffer-locally so it owns
-- the keys there too.
vim.cmd("enew")
vim.bo.filetype = "fzf"
vim.keymap.set("n", "<C-j>", "<cmd>echo 'picker down'<cr>", { buffer = true, desc = "picker down" })
vim.cmd("doautocmd FileType")
check("our <C-j> reasserted in picker buffer", is_ours(maparg_dict("<C-j>"), "down"))
check("our <C-h> installed in picker buffer", is_ours(maparg_dict("<C-h>"), "left"))
vim.cmd("bwipeout!")

-- 5e. Entry markers: fresh-valid applies, stale/invalid are ignored, and every
-- marker is single-use (removed after read).
local uv = vim.uv or vim.loop
local cache = vim.fn.tempname()
vim.fn.mkdir(cache .. "/herdr-vim-navigator/entry", "p")
vim.env.XDG_CACHE_HOME = cache
vim.env.HERDR_ENV = "1"
vim.env.HERDR_PANE_ID = "testpane"
local marker_path = cache .. "/herdr-vim-navigator/entry/testpane"

local function write_marker(content, age_seconds)
  local f = assert(io.open(marker_path, "w"))
  f:write(content)
  f:close()
  if age_seconds then
    local t = os.time() - age_seconds
    uv.fs_utime(marker_path, t, t)
  end
end

local function leftmost_window()
  vim.cmd("silent! only")
  vim.cmd("vsplit | vsplit")
  vim.cmd("wincmd h")
  return vim.api.nvim_get_current_win()
end

-- Fresh, valid "l" marker should move focus away from the leftmost window.
local lm = leftmost_window()
write_marker("l", 0)
nav.apply_entry_marker()
vim.wait(100, function()
  return false
end)
check("fresh valid marker moved focus", vim.api.nvim_get_current_win() ~= lm)
check("fresh marker removed after read", uv.fs_stat(marker_path) == nil)

-- A stale marker is removed but not applied.
lm = leftmost_window()
write_marker("l", 120)
nav.apply_entry_marker()
vim.wait(50, function()
  return false
end)
check("stale marker is ignored", vim.api.nvim_get_current_win() == lm)
check("stale marker removed after read", uv.fs_stat(marker_path) == nil)

-- An invalid (non-hjkl) marker is removed but not applied.
lm = leftmost_window()
write_marker("nope", 0)
nav.apply_entry_marker()
vim.wait(50, function()
  return false
end)
check("invalid marker is ignored", vim.api.nvim_get_current_win() == lm)
check("invalid marker removed after read", uv.fs_stat(marker_path) == nil)
vim.cmd("silent! only")

-- 6. Health module loads and :checkhealth runs through the proper framework.
local health_ok, health = pcall(require, "herdr-vim-navigator.health")
check("health module loads", health_ok, health)

local hc_ok = pcall(vim.cmd, "checkhealth herdr-vim-navigator")
check(":checkhealth herdr-vim-navigator runs", hc_ok)
if hc_ok then
  local joined = table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), "\n")
  check("health output mentions the plugin", joined:find("herdr%-vim%-navigator") ~= nil)
end

io.stdout:write((failures == 0) and "\nAll smoke tests passed.\n" or ("\n" .. failures .. " failure(s).\n"))
vim.cmd(failures == 0 and "qa!" or "cq")
