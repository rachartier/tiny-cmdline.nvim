local M = {}

M._initialized = false

---@class TinyCmdlineAdapters
M.adapters = {
  ---@type fun(): nil
  blink = function()
    local ok, menu = pcall(require, "blink.cmp.completion.windows.menu")
    if ok and menu.win and menu.win:is_open() then
      pcall(menu.update_position)
    end
  end,
}

---@class TinyCmdlineWidthConfig
---@field value string|integer Width: "60%" = fraction of editor columns, integer = absolute columns
---@field min integer Minimum width in columns
---@field max integer Maximum width in columns

---@class TinyCmdlinePositionConfig
---@field x string|integer Horizontal position: "50%" = center, integer = absolute columns from left
---@field y string|integer Vertical position: "50%" = center, integer = absolute rows from top

---@class TinyCmdlineConfig
---@field width TinyCmdlineWidthConfig
---@field position TinyCmdlinePositionConfig
---@field border string|nil nil = inherit vim.o.winborder at setup() time
---@field menu_col_offset integer Completion menu offset from the window's left inner edge
---@field native_types string[] Types shown at the bottom instead of centered (e.g. "/", "?")
---@field on_reposition fun()|nil Called after every reposition
M.config = {
  width = {
    value = "60%",
    min = 40,
    max = 80,
  },
  position = {
    x = "50%",
    y = "50%",
  },
  border = nil,
  menu_col_offset = 3,
  native_types = { "/", "?" },
  on_reposition = nil,
}

-- "60%" -> fraction of available; integer -> absolute
local function parse_dimension(value, available)
  if type(value) == "string" then
    return math.floor(available * tonumber(value:match("^(%d+)%%$")) / 100)
  end
  return math.floor(value)
end

---@param content_height integer
---@return integer width, integer row, integer col, integer b
local function geometry(content_height)
  local cols, lines = vim.o.columns, vim.o.lines
  local b = M.config.border == "none" and 0 or 1
  local width = math.max(
    M.config.width.min,
    math.min(M.config.width.max, parse_dimension(M.config.width.value, cols))
  )
  width = math.min(width, cols - 4)

  local row = math.max(0, parse_dimension(M.config.position.y, lines - content_height - b * 2))
  local col = math.max(0, parse_dimension(M.config.position.x, cols - width - b * 2))
  return width, row, col, b
end

local cmdline_type = nil ---@type string|nil
local original_ui_cmdline_pos = nil ---@type table|nil
local cmd_win_saved = nil ---@type table|nil
local ui2 = nil ---@type table|nil

local function set_cmdheight_0()
  vim._with({ noautocmd = true }, function()
    vim.o.cmdheight = 0
  end)
end

local function get_cmd_win()
  if not ui2 then
    local ok, mod = pcall(require, "vim._core.ui2")
    if not ok then
      return nil
    end
    ui2 = mod
  end
  local win = ui2.wins and ui2.wins.cmd
  return (win and vim.api.nvim_win_is_valid(win)) and win or nil
end

local function reposition()
  if not cmdline_type then
    return
  end
  local win = get_cmd_win()
  if not win then
    return
  end

  -- saved once and restored on CmdlineLeave so post-command messages render at the bottom
  if not cmd_win_saved then
    local cfg = vim.api.nvim_win_get_config(win)
    cmd_win_saved = {
      relative = cfg.relative,
      anchor = cfg.anchor,
      col = cfg.col,
      row = cfg.row,
      width = cfg.width,
      border = cfg.border,
    }
  end

  local content_height = math.max(1, vim.api.nvim_win_get_height(win))

  if vim.tbl_contains(M.config.native_types, cmdline_type) then
    pcall(vim.api.nvim_win_set_config, win, {
      relative = "editor",
      row = math.max(0, vim.o.lines - content_height),
      col = 0,
      width = vim.o.columns,
      border = "none",
    })
    vim.g.ui_cmdline_pos = original_ui_cmdline_pos
    return
  end

  local width, row, col, b = geometry(content_height)
  pcall(vim.api.nvim_win_set_config, win, {
    relative = "editor",
    row = row,
    col = col,
    width = width,
    border = M.config.border,
  })
  vim.g.ui_cmdline_pos = { row + content_height + b * 2, col + b + M.config.menu_col_offset } -- blink.cmp / nvim-cmp anchor

  if M.config.on_reposition then
    M.config.on_reposition()
  end
end

local wrapped = false
local function wrap_cmdline_show()
  if wrapped then
    return
  end
  local ok, cmdline = pcall(require, "vim._core.ui2.cmdline")
  if not ok then
    return
  end
  local orig = cmdline.cmdline_show
  cmdline.cmdline_show = function(...)
    local r = orig(...)
    if not cmdline_type then
      return r
    end

    -- ui2 sets cmdheight=1 on every show; suppress it for non-native types
    -- noautocmd prevents ui2's OptionSet handler from re-applying it
    if not vim.tbl_contains(M.config.native_types, cmdline_type) then
      set_cmdheight_0()
    end
    reposition()
    return r
  end
  wrapped = true
end

local function wrap_and_reposition()
  wrap_cmdline_show()
  reposition()
end

---@param opts TinyCmdlineConfig?
function M.setup(opts)
  if M._initialized then
    return
  end
  M._initialized = true

  if vim.fn.has("nvim-0.12") == 0 then
    vim.notify("tiny-cmdline.nvim requires Neovim >= 0.12", vim.log.levels.WARN)
    return
  end

  original_ui_cmdline_pos = vim.g.ui_cmdline_pos
  cmd_win_saved = nil
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  if M.config.border == nil then
    local wb = vim.o.winborder
    M.config.border = wb ~= "" and wb or "rounded"
  end

  local group = vim.api.nvim_create_augroup("tiny-cmdline", { clear = true })

  vim.api.nvim_create_autocmd("CmdlineEnter", {
    group = group,
    callback = function()
      cmdline_type = vim.fn.getcmdtype()
    end,
  })

  vim.api.nvim_create_autocmd("CmdlineLeave", {
    group = group,
    callback = function()
      local was_native = vim.tbl_contains(M.config.native_types, cmdline_type)
      cmdline_type = nil
      vim.g.ui_cmdline_pos = original_ui_cmdline_pos

      -- restore original position without hiding so ui2 can display post-command messages
      local win = get_cmd_win()
      if win and cmd_win_saved then
        pcall(vim.api.nvim_win_set_config, win, cmd_win_saved)
      end

      if was_native then
        -- defer so ui2's OptionSet doesn't re-bump cmdheight to 1 after a search
        vim.schedule(set_cmdheight_0)
      end
    end,
  })

  vim.api.nvim_create_autocmd("FileType", {
    group = group,
    pattern = "cmd",
    callback = function()
      vim.schedule(wrap_and_reposition)
    end,
  })

  vim.api.nvim_create_autocmd({ "VimResized", "TabEnter" }, {
    group = group,
    callback = function()
      vim.schedule(reposition)
    end,
  })

  vim.schedule(wrap_and_reposition)
end

return M
