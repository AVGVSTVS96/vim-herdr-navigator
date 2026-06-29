if vim.g.loaded_vim_herdr_navigator == 1 then
  return
end
vim.g.loaded_vim_herdr_navigator = 1

-- Auto-setup keeps the plugin usable with package managers that do not call
-- require(...).setup(). Users can opt out before loading the plugin:
--   vim.g.vim_herdr_navigator_auto_setup = false
if vim.g.vim_herdr_navigator_auto_setup ~= false then
  vim.schedule(function()
    local ok, navigator = pcall(require, "vim-herdr-navigator")
    if ok and not navigator.is_setup() then
      navigator.setup()
    end
  end)
end
