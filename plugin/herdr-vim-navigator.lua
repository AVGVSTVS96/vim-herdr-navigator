if vim.g.loaded_herdr_vim_navigator == 1 then
  return
end
vim.g.loaded_herdr_vim_navigator = 1

-- Auto-setup keeps the plugin usable with package managers that do not call
-- require(...).setup(). Users can opt out before loading the plugin:
--   vim.g.herdr_vim_navigator_auto_setup = false
if vim.g.herdr_vim_navigator_auto_setup ~= false then
  vim.schedule(function()
    local ok, navigator = pcall(require, "herdr-vim-navigator")
    if ok and not navigator.is_setup() then
      navigator.setup()
    end
  end)
end
