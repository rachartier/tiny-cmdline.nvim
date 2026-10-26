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

--- Updates wildmenu popup position.
---
--- This function is useful to update the wildmenu position after repositioning/moving tiny cmdline.
--- PUM's position is calculated before cmdline_show gets called, so we need to fix it afterwards.
---
--- This method has the drawback of causing a flicker of PUM in its old place, but no other way
--- exists.
---
--- This must be called in the main event loop, because it feeds keys.
local function fix_pum()
  local info = vim.fn.cmdcomplete_info()
  -- only the popup menu is anchored to the cmd window; a horizontal wildmenu needn't move.
  if vim.fn.wildmenumode() == 0 or info.pum_visible ~= 1 then
    return
  end
  -- An open wildmenu only follows the window when redisplayed: reopen it when nothing is
  -- selected, otherwise step the selection away and back so it stays selected
  local keys = info.selected == -1 and "<C-e><Cmd>call wildtrigger()<CR>" or "<C-n><C-p>"
  vim.api.nvim_feedkeys(vim.keycode(keys), "n", false)
end

---@class TinyCmdlineWidthConfig
---@field value string|integer Width: "60%" = fraction of editor columns, integer = absolute columns
---@field min integer Minimum width in columns
---@field max integer Maximum width in columns

---@class TinyCmdlinePositionConfig
---@field x string|integer Horizontal position: "50%" = center, integer = absolute columns from left
---@field y string|integer Vertical position: "50%" = center, integer = absolute rows from top

---@class TinyCmdlinePositionOverride
---@field x string|integer|nil
---@field y string|integer|nil

---@class TinyCmdlineTitleFormat
---@field type string|string[]|nil getcmdtype() value(s) to match; nil = any
---@field pattern string|string[]|nil Lua pattern(s) matched against getcmdline(); nil = always
---@field title string Title text to display (include leading/trailing spaces as desired)

---@class TinyCmdlineTitleConfig
---@field enabled boolean
---@field pos "left"|"center"|"right"
---@field formats TinyCmdlineTitleFormat[] Evaluated in order; first match wins

---@class TinyCmdlineConfig
---@field width TinyCmdlineWidthConfig
---@field position TinyCmdlinePositionConfig
---@field position_presets TinyCmdlinePositionConfig[]
---@field border string|nil nil = inherit vim.o.winborder at setup() time
---@field menu_col_offset integer Completion menu offset from the window's left inner edge
---@field native_types string[] Types shown at the bottom instead of centered (e.g. "/", "?")
---@field title TinyCmdlineTitleConfig
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
  position_presets = {
    {
      x = "50%",
      y = "80%",
    },
    {
      x = "50%",
      y = "20%",
    },
  },
  border = nil,
  menu_col_offset = 3,
  native_types = { "/", "?" },
  title = {
    enabled = false,
    pos = "center",
    -- evaluated in order; first match wins. Last entry is the fallback.
    formats = {
      { type = ":", pattern = { "^%s*lua%s+", "^%s*lua%s*=", "^%s*=" }, title = " Lua " },
      { type = ":", pattern = "^%s*!",          title = " Shell " },
      { type = ":", pattern = "^%s*he?l?p?%s+", title = " Help " },
      { type = "/",                             title = " Search " },
      { type = "?",                             title = " Search " },
      { type = "=",                             title = " Expression " },
      { type = "@",                             title = " Input " },
      { type = ">",                             title = " Debug " },
      {                                         title = " CmdLine " },
    },
  },
  on_reposition = nil,
}

---Desired position of the tiny cmdline.
---
---This preset stays active during a Neovim session.
---
---If 0, Tiny Cmdline uses M.config.position.
---Otherwise it is the index of M.config.position_presets.
---
---@type integer
local active_position_preset = 0

---Returns active position pointed to by active_position_preset.
---
---@return TinyCmdlinePositionConfig
local function get_active_position()
  if active_position_preset == 0 then
    return M.config.position
  else
    return M.config.position_presets[active_position_preset]
  end
end

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
  width = math.min(width, cols - b * 2)

  local active_position = get_active_position()
  local row = math.max(0, parse_dimension(active_position.y, lines - content_height - b * 2))
  local col = math.max(0, parse_dimension(active_position.x, cols - width - b * 2))
  return width, row, col, b
end

local original_ui_cmdline_pos = nil ---@type table|nil
local cmd_win_saved = nil ---@type table|nil
local ui2 = nil ---@type table|nil
local applied_title = nil ---@type string|nil

local WINHIGHLIGHT =
  "Normal:TinyCmdlineNormal,FloatBorder:TinyCmdlineBorder,FloatTitle:TinyCmdlineTitle"

---@return string
local function get_styled_winhighlight()
  -- appended to ui2's value (if any) so its Search/CurSearch/IncSearch hiding stays; later entries win
  local saved_hl = ""
  if cmd_win_saved and cmd_win_saved.winhighlight ~= "" then
    saved_hl = cmd_win_saved.winhighlight .. ","
  end
  return saved_hl .. WINHIGHLIGHT
end

--- Sets winhighlight like ui2 does.
---
---@param win integer
---@param value string
local function set_winhighlight(win, value)
  vim._with({ win = win, noautocmd = true }, function()
    vim.api.nvim_set_option_value("winhighlight", value, { scope = "local" })
  end)
end

local function type_matches(filter, t)
  if filter == nil then
    return true
  end
  if type(filter) == "string" then
    return filter == t
  end
  return vim.tbl_contains(filter, t)
end

---@return string|nil
local function compute_title()
  local cfg = M.config.title
  if not cfg or not cfg.enabled or vim.fn.getcmdtype() == "" then
    return nil
  end
  local cmdline = vim.fn.getcmdline() or ""
  for _, fmt in ipairs(cfg.formats or {}) do
    if type_matches(fmt.type, vim.fn.getcmdtype()) then
      local patterns = fmt.pattern
      if patterns == nil then
        return fmt.title
      end
      if type(patterns) == "string" then
        patterns = { patterns }
      end
      for _, p in ipairs(patterns) do
        if cmdline:match(p) then
          return fmt.title
        end
      end
    end
  end
  return nil
end

local function set_cmdheight_0()
  vim._with({ noautocmd = true, o = { splitkeep = "screen" } }, function()
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

--- Whether the tiny cmdline should be used.
---
---@return boolean
local function is_styled()
  local t = vim.fn.getcmdtype()
  return t ~= "" and not vim.tbl_contains(M.config.native_types, t)
end

--- Snapshots ui2's own window state once per styled cmdline so restore() can hand it back untouched.
---@param win integer
local function save(win)
  if cmd_win_saved and cmd_win_saved.win == win then
    return
  end
  local current = vim.api.nvim_win_get_config(win)
  cmd_win_saved = {
    win = win,
    cfg = {
      relative = current.relative,
      anchor = current.anchor,
      col = current.col,
      row = current.row,
      width = current.width,
      border = current.border,
    },
    winhighlight = vim.wo[win].winhighlight,
  }
end

-- Undoes everything reposition() changed, so native types and post-command messages get ui2's window.
local function restore()
  applied_title = nil
  vim.g.ui_cmdline_pos = original_ui_cmdline_pos
  local saved = cmd_win_saved
  if not saved then
    return
  end
  -- ui2 may have replaced the window in the meantime; a new one already has ui2's state
  if get_cmd_win() ~= saved.win then
    cmd_win_saved = nil
    return
  end
  local cfg_ok = pcall(vim.api.nvim_win_set_config, saved.win, saved.cfg)
  local hl_ok = pcall(set_winhighlight, saved.win, saved.winhighlight)
  -- on failure the window is still styled; keep the snapshot so the next save() doesn't record
  -- that as ui2's state, and the next restore() retries
  if cfg_ok and hl_ok then
    cmd_win_saved = nil
  end
end

local function reposition()
  if not is_styled() then
    return
  end
  local win = get_cmd_win()
  if not win then
    return
  end

  save(win) -- no-op unless ui2 replaced the window since the last snapshot
  local winhighlight = get_styled_winhighlight()
  if vim.wo[win].winhighlight ~= winhighlight then
    set_winhighlight(win, winhighlight)
  end
  local current = vim.api.nvim_win_get_config(win)
  local content_height = math.max(1, vim.api.nvim_win_get_height(win))
  local width, row, col, b = geometry(content_height)
  local title = compute_title()
  local borderless = M.config.border == "none" or M.config.border == nil
  local moved = current.relative ~= "editor"
    or current.row ~= row
    or current.col ~= col
    or current.width ~= width
  if moved or applied_title ~= title then
    local cfg = {
      relative = "editor",
      row = row,
      col = col,
      width = width,
      border = M.config.border,
    }
    if title and title ~= "" and not borderless then
      cfg.title = title
      cfg.title_pos = M.config.title and M.config.title.pos or "left"
    end
    pcall(vim.api.nvim_win_set_config, win, cfg)
    applied_title = title
  end
  vim.g.ui_cmdline_pos = { row + content_height + b * 2, col + b + M.config.menu_col_offset } -- blink.cmp / nvim-cmp anchor
  if moved then
    vim.api.nvim_exec_autocmds("User", { pattern = "TinyCmdlineMoved" })
  end
end

--- Whether cmdline_* functions have been monkey patched.
---@type boolean
local wrapped = false
local orig_cmdline_hide = function(...) end
local orig_cmdline_show = function(...) end

--- Shows styled cmdline if requested and manage ui2/tiny state.
local function tiny_cmdline_show(...)
  if not is_styled() then
    -- Before orig_cmdline_show, so ui2 sizes the window at its own width; also covers a native
    -- cmdline nested in a styled one, which gets no cmdline_hide in between.
    restore()
    return orig_cmdline_show(...)
  end

  -- reposition() snapshots after orig_cmdline_show, so it sees ui2's update to this event (e.g.,
  -- border).
  local r = orig_cmdline_show(...)
  -- search types need cmdheight=1 for stable IncSearch rendering
  local t = vim.fn.getcmdtype()
  if t ~= "/" and t ~= "?" then
    set_cmdheight_0()
  end
  reposition()
  return r
end

--- Restores ui2 state if needed and runs the ui2 cmdline_hide.
local function tiny_cmdline_hide(...)
  local cmdline = require("vim._core.ui2.cmdline")
  local r = orig_cmdline_hide(...)
  -- ui2 keeps the window (and its level) for nested cmdlines and blocks; restoring then
  -- would flash it at the bottom, and the next cmdline_show repositions anyway
  if cmdline.level == 0 then
    restore()
    -- defer so ui2's OptionSet doesn't re-bump cmdheight after leaving search/native types;
    -- only at level 0, as an outer search may still need cmdheight=1
    vim.schedule(set_cmdheight_0)
  end
  return r
end

local function wrap_cmdline_fns()
  if wrapped then
    return
  end
  local ok, cmdline = pcall(require, "vim._core.ui2.cmdline")
  if not ok then
    return
  end

  orig_cmdline_show = cmdline.cmdline_show
  orig_cmdline_hide = cmdline.cmdline_hide

  cmdline.cmdline_show = tiny_cmdline_show
  cmdline.cmdline_hide = tiny_cmdline_hide
  wrapped = true
end

local function wrap_and_reposition()
  wrap_cmdline_fns()
  reposition()
end

---Shifts the active position preset cyclically.
---
---@param shift integer
local function shift_active_position_preset(shift)
  active_position_preset = active_position_preset + shift
  active_position_preset = active_position_preset % (#M.config.position_presets + 1)
  reposition()
  -- Reposition by itself does not trigger a redraw. We need to force it.
  vim.cmd.redraw()
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

  vim.api.nvim_set_hl(0, "TinyCmdlineNormal", { link = "MsgArea", default = true })
  vim.api.nvim_set_hl(0, "TinyCmdlineBorder", { link = "FloatBorder", default = true })
  vim.api.nvim_set_hl(0, "TinyCmdlineTitle", { link = "FloatTitle", default = true })

  original_ui_cmdline_pos = vim.g.ui_cmdline_pos
  cmd_win_saved = nil
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
  if M.config.border == nil then
    local wb = vim.o.winborder
    M.config.border = wb ~= "" and wb or "rounded"
  end

  local group = vim.api.nvim_create_augroup("tiny-cmdline", { clear = true })
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
      vim.schedule(function()
        reposition()
        if M.config.on_reposition then
          M.config.on_reposition()
        end
      end)
    end,
  })

  vim.api.nvim_create_autocmd("User", {
    group = group,
    pattern = "TinyCmdlineMoved",
    callback = function()
      vim.schedule(fix_pum)
    end,
  })

  vim.keymap.set("c", "<Plug>(tiny-cmdline-prev-position-preset)", function()
    shift_active_position_preset(-1)
  end, { desc = "Previous tiny cmdline position", silent = true })
  vim.keymap.set("c", "<Plug>(tiny-cmdline-next-position-preset)", function()
    shift_active_position_preset(1)
  end, { desc = "Next tiny cmdline position", silent = true })

  vim.schedule(wrap_and_reposition)
end

return M
