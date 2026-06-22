-- Dependency-free smoke test. Run via tests/run.sh (or see the command there).
-- Loads the plugin, exercises setup()/commands/health, and exits non-zero on
-- the first failure so it can run in CI.

local failures = 0

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
