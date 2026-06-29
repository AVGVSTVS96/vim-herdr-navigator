local M = {}

-- Support both the modern `vim.health.start/ok/...` API (Neovim 0.10+) and the
-- older `vim.health.report_*` names, so checkhealth works across versions.
local health = vim.health or {}
local h = {
  start = health.start or health.report_start,
  ok = health.ok or health.report_ok,
  warn = health.warn or health.report_warn,
  error = health.error or health.report_error,
  info = health.info or health.report_info,
}

local function herdr_version(helper)
  if not (vim.system and helper) then
    return nil
  end
  local ok, result = pcall(function()
    return vim.system({ helper, "--version" }, { text = true }):wait(2000)
  end)
  if not ok or not result or result.code ~= 0 then
    return nil
  end
  local out = (result.stdout or "")
  return vim.trim(out):gsub("\n.*", "")
end

function M.check()
  h.start("vim-herdr-navigator")

  -- Neovim version
  local v = vim.version and vim.version() or nil
  local vstr = v and string.format("%d.%d.%d", v.major or 0, v.minor or 0, v.patch or 0) or "unknown"
  if vim.fn.has("nvim-0.8") == 1 then
    h.ok("Neovim " .. vstr)
  else
    h.warn("Neovim " .. vstr .. " — 0.8+ recommended")
  end

  -- Herdr session
  if vim.env.HERDR_ENV == "1" or vim.env.HERDR_SOCKET_PATH ~= nil then
    h.ok("Running inside a Herdr session")
  else
    h.info("Not inside a Herdr session — the plugin stays inert until HERDR_ENV=1 (this is fine outside Herdr)")
  end

  local ok, nav = pcall(require, "vim-herdr-navigator")
  if not ok then
    h.error("Could not load vim-herdr-navigator: " .. tostring(nav))
    return
  end

  -- setup() called?
  if nav.is_setup() then
    h.ok("setup() has run")
  else
    h.warn("setup() has not run yet (it is scheduled on load; harmless during startup)")
  end

  local config = nav.get_config()

  -- Helper executable
  local helper = nav.resolve_helper()
  if helper then
    local version = herdr_version(helper)
    if version and version ~= "" then
      h.ok("Helper found: " .. helper .. " (" .. version .. ")")
    else
      h.ok("Helper found: " .. helper)
    end
  else
    h.error(
      "Helper not executable: " .. tostring(config.helper),
      { "Install vim-herdr-navigator and ensure it is on PATH, or set opts.helper to its path." }
    )
  end

  -- Pane id (only meaningful inside Herdr)
  local pane = vim.env.HERDR_PANE_ID or vim.env.HERDR_ACTIVE_PANE_ID
  if pane and pane ~= "" then
    h.info("Pane id: " .. pane)
  elseif vim.env.HERDR_ENV == "1" then
    h.warn("HERDR_PANE_ID is not set; edge focus may not work")
  end

  -- Keymaps summary
  if config.set_keymaps then
    local keys = {}
    for direction, lhs in pairs(config.keymaps or {}) do
      table.insert(keys, direction .. "=" .. table.concat(lhs, ","))
    end
    h.info("Keymaps enabled: " .. table.concat(keys, "  "))
  else
    h.info("set_keymaps = false (using :HerdrNavigate* commands only)")
  end
end

return M
