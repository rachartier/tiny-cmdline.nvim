vim.api.nvim_create_autocmd("UIEnter", {
  once = true,
  callback = function()
    local ok, m = pcall(require, "tiny-cmdline")
    if not ok or m._initialized then
      return
    end
    local opts = type(vim.g.tiny_cmdline) == "table" and vim.g.tiny_cmdline or {}
    m.setup(opts)
  end,
})
