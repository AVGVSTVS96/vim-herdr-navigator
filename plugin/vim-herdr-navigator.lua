if vim.g.loaded_vim_herdr_navigator == 1 then
  return
end
vim.g.loaded_vim_herdr_navigator = 1

-- Auto-setup keeps the plugin usable with package managers that do not call
-- require(...).setup(). Users can opt out before loading the plugin:
--   vim.g.vim_herdr_navigator_auto_setup = false
--
-- The Herdr environment is inherited at process spawn and fixed for the whole
-- session, so a single check here is equivalent to gating every action. When we
-- are not in a Herdr session there is nothing useful to do, so skip auto-setup
-- entirely: don't require the module, claim <C-h/j/k/l>, or register autocmds.
-- An explicit require(...).setup() still runs unconditionally for anyone who
-- wants the commands to exist regardless.
if vim.g.vim_herdr_navigator_auto_setup ~= false then
  vim.schedule(function()
    if vim.env.HERDR_ENV ~= "1" and vim.env.HERDR_SOCKET_PATH == nil then
      return
    end
    local ok, navigator = pcall(require, "vim-herdr-navigator")
    if ok and not navigator.is_setup() then
      navigator.setup()
    end
  end)
end
