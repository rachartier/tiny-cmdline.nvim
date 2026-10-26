# 📍tiny-cmdline.nvim

[![Neovim](https://img.shields.io/badge/Neovim-0.12+-blue.svg)](https://neovim.io/)

A Neovim plugin that repositions the cmdline as a centered floating window, powered by Neovim's native `ui2` system.

<img width="1085" height="625" alt="image" src="https://github.com/user-attachments/assets/a8dd229d-dff8-40b5-8727-58fb8fce7c64" />


## Table of Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [Keymaps](#keymaps)
- [Highlight Groups](#highlight-groups)
- [Events](#events)
- [How It Works](#how-it-works)
- [Integrations](#integrations)
  - [blink.cmp](#blinkcmp)
  - [nvim-cmp](#nvim-cmp)
  - [mini.cmdline](#minicmdline)
  - [Default (built-in) completion](#default-built-in-completion)
- [Troubleshooting](#troubleshooting)

## Requirements

- Neovim >= 0.12
- `cmdheight=0` (better to have for `ui2`)
- `ui2` must be enabled explicitly:
  ```lua
  require("vim._core.ui2").enable({})
  ```

## Installation

The plugin is setup-less: it auto-initializes on `UIEnter` with sensible defaults. No `setup()` call is required.

There are three ways to configure it:

- **Minimal**: just install and set `cmdheight=0`
- **`vim.g`**: set `vim.g.tiny_cmdline` before the plugin loads (no `setup()` needed)
- **`setup()`**: explicit call, takes priority over `vim.g`

### vim.pack (Neovim built-in, >= 0.12)

Minimal:

```lua
vim.o.cmdheight = 0
vim.pack.add({ "https://github.com/rachartier/tiny-cmdline.nvim" })
```

With `vim.g`:

```lua
vim.o.cmdheight = 0
vim.g.tiny_cmdline = {
    width = { value = "70%" },
}
vim.pack.add({ "https://github.com/rachartier/tiny-cmdline.nvim" })
```

With `setup()`:

```lua
vim.pack.add({
    "https://github.com/rachartier/tiny-cmdline.nvim",
    config = function()
        vim.o.cmdheight = 0
        require("tiny-cmdline").setup()
    end,
})
```

### lazy.nvim

Minimal:

```lua
{
    "rachartier/tiny-cmdline.nvim",
    init = function()
        vim.o.cmdheight = 0
    end,
}
```

With `vim.g`:

```lua
{
    "rachartier/tiny-cmdline.nvim",
    init = function()
        vim.o.cmdheight = 0
        vim.g.tiny_cmdline = {
            width = { value = "70%" },
        }
    end,
}
```

With `setup()`:

```lua
{
    "rachartier/tiny-cmdline.nvim",
    config = function()
        vim.o.cmdheight = 0
        require("tiny-cmdline").setup()
    end,
}
```

## Configuration

<details>
<summary>Full default configuration</summary>

```lua
require("tiny-cmdline").setup({
    -- Cmdline window width
    width = {
        value = "60%",  -- "N%" = fraction of editor columns, integer = absolute columns
        min = 40,       -- minimum width in columns
        max = 80,       -- maximum width in columns
    },

    -- Window position ("N%" = fraction of available space, integer = absolute columns/rows)
    position = {
        x = "50%",  -- horizontal: "0%" = left, "50%" = center, "100%" = right
        y = "50%",  -- vertical:   "0%" = top,  "50%" = center, "100%" = bottom
    },

    -- Alternative positions to cycle through with the position preset keymaps
    -- (see Keymaps). Same format as `position`.
    position_presets = {
        { x = "50%", y = "80%" },
        { x = "50%", y = "20%" },
    },

    -- Border style for the floating window
    -- nil inherits vim.o.winborder at setup() time, falling back to "rounded"
    -- Set to "none" to disable the border
    border = nil,

    -- Horizontal offset of the completion menu anchor from the window's left inner edge
    -- Used to align blink.cmp / nvim-cmp menus with the cmdline window
    menu_col_offset = 3,

    -- Cmdline types rendered at the bottom of the screen instead of centered
    -- "/" and "?" (search) are kept native by default
    native_types = { "/", "?" },

    -- Dynamic popup title (rendered on the floating border)
    -- Disabled by default; set enabled = true to opt in
    -- Has no effect when border = "none" or when the cmdline is rendered via native_types
    title = {
        enabled = false,
        pos = "center",  -- "left" | "center" | "right"
    },

    -- Optional callback invoked after every reposition
    on_reposition = nil,
})
```

</details>

## Keymaps

The plugin defines `<Plug>` mappings in cmdline mode but binds no keys by default:

| Mapping | Description |
| --- | --- |
| `<Plug>(tiny-cmdline-next-position-preset)` | Move the cmdline window to the next position preset |
| `<Plug>(tiny-cmdline-prev-position-preset)` | Move the cmdline window to the previous position preset |

Presets cycle through `position` followed by each entry of `position_presets`, wrapping around at both ends. Useful when the window covers the text you want to see while typing a command.

```lua
vim.keymap.set("c", "<A-,>", "<Plug>(tiny-cmdline-prev-position-preset)")
vim.keymap.set("c", "<A-.>", "<Plug>(tiny-cmdline-next-position-preset)")
```

## Highlight Groups

| Group | Default link | Description |
| --- | --- | --- |
| `TinyCmdlineNormal` | `MsgArea` | Background of the cmdline window |
| `TinyCmdlineBorder` | `FloatBorder` | Border of the cmdline window |
| `TinyCmdlineTitle` | `FloatTitle` | Title shown on the border |

Override them in your colorscheme or config:

```lua
vim.api.nvim_set_hl(0, "TinyCmdlineBorder", { fg = "#your_color" })
vim.api.nvim_set_hl(0, "TinyCmdlineNormal", { bg = "#your_color" })
```

## Events

| Event | Description |
| --- | --- |
| `User TinyCmdlineMoved` | Fired after the cmdline window is moved or resized (position or width changed). `vim.g.ui_cmdline_pos` is already updated when it fires. |

The event is triggered from within ui2's cmdline handlers, so wrap anything that redraws or feeds keys in `vim.schedule()`:

```lua
vim.api.nvim_create_autocmd("User", {
    pattern = "TinyCmdlineMoved",
    callback = function()
        vim.schedule(function()
            -- e.g. reposition your own completion menu using vim.g.ui_cmdline_pos
        end)
    end,
})
```

tiny-cmdline itself listens to this event to move an open wildmenu popup (built-in completion) along with the window.

## How It Works

tiny-cmdline hooks into Neovim's internal `vim._core.ui2` system, which manages the floating cmdline window introduced in Neovim 0.12. It wraps ui2's `cmdline_show` and `cmdline_hide` handlers: on every show it repositions that window to the center of the editor, and once the last cmdline level is hidden it restores ui2's original window state so that post-command messages still render correctly at the bottom. Nested cmdlines (e.g. `<C-r>=`) and cmdline blocks (e.g. `:function`) keep the centered window until they are fully closed.

Cmdline types listed in `native_types` (search by default) are left to ui2, which renders them at the bottom at full width, preserving the native search experience.

The window position is also updated on `VimResized` and `TabEnter` to stay correctly centered after layout changes.

## Integrations

tiny-cmdline is compatible with the most common completion plugins. The table below summarises compatibility details for each.

| Plugin | Menu repositions on open | Menu repositions on window resize | Extra config required |
| --- | --- | --- | --- |
| **blink.cmp** | :heavy_check_mark: with adapter | :heavy_check_mark: with adapter | :heavy_check_mark: see below |
| **nvim-cmp** | :heavy_check_mark: | :x: (not yet supported) | :x: |
| **mini.cmdline** | :heavy_check_mark: | :x: (not yet supported) | :x: |
| **Default (built-in)** | :heavy_check_mark: | :x: (not yet supported) | :x: |

### blink.cmp

blink.cmp manages its own menu position independently. Use the built-in adapter so it follows the repositioned cmdline window:

```lua
require("tiny-cmdline").setup({
    on_reposition = require("tiny-cmdline").adapters.blink,
})
```


## Troubleshooting

- **Cmdline stays at the bottom**: Ensure `vim.o.cmdheight = 0` is set before the plugin initializes (use `init` in lazy.nvim, or set it early in your config).
- **Completion menu misaligned**: Tune `menu_col_offset` to match your border/padding.
- **Border doesn't match the rest of Neovim**: Leave `border = nil` to inherit `vim.o.winborder`.
- **Search feels different**: `/` and `?` are in `native_types` by default and rendered at the bottom; remove them from that list to also center them.
- **Pending keys not shown** (e.g. `d3`, `c3`, `y3`): either move it to statusline with `vim.o.showcmdloc = "statusline"`, or just show cmdline at the bottom. If you do choose statusline just remember to put the `%S` item into your statusline configuration.
- **Macro recording indicator not shown** (`recording @a`): either add the `vim.fn.reg_recording()` in your statusline configuration, or just show cmdline at the bottom.
