# 📍tiny-cmdline.nvim

[![Neovim](https://img.shields.io/badge/Neovim-0.12+-blue.svg)](https://neovim.io/)

A Neovim plugin that repositions the cmdline as a centered floating window, powered by Neovim's native `ui2` system.

## Table of Contents

- [Requirements](#requirements)
- [Installation](#installation)
- [Configuration](#configuration)
- [How It Works](#how-it-works)
- [Integrations](#integrations)
  - [blink.cmp](#blinkcmp)
  - [nvim-cmp](#nvim-cmp)
  - [mini.completion](#minicompletion)
  - [Default (built-in) completion](#default-built-in-completion)
- [Troubleshooting](#troubleshooting)

## Requirements

- Neovim >= 0.12
- `cmdheight=0` (better to have for `ui2`)

## Installation

### lazy.nvim

```lua
{
    "rachartier/tiny-cmdline.nvim",
    event = "VeryLazy",
    config = function()
        vim.o.cmdheight = 0
        require("tiny-cmdline").setup()
    end,
}
```

### vim.pack (Neovim built-in, >= 0.12)

```lua
vim.o.cmdheight = 0
vim.pack.add({ "https://github.com/rachartier/tiny-cmdline.nvim" })
require("tiny-cmdline").setup()
```

## Configuration

<details>
<summary>Full default configuration</summary>

```lua
require("tiny-cmdline").setup({
    -- Fraction of editor columns used for the cmdline window width (0–1)
    width = 0.6,

    -- Border style for the floating window
    -- nil inherits vim.o.winborder at setup() time, falling back to "rounded"
    -- Set to "none" to disable the border
    border = nil,

    -- Minimum width in columns
    min_width = 40,

    -- Maximum width in columns
    max_width = 80,

    -- Horizontal offset of the completion menu anchor from the window's left inner edge
    -- Used to align blink.cmp / nvim-cmp menus with the cmdline window
    menu_col_offset = 3,

    -- Cmdline types rendered at the bottom of the screen instead of centered
    -- "/" and "?" (search) are kept native by default
    native_types = { "/", "?" },

    -- Optional callback invoked after every reposition
    on_reposition = nil,
})
```

</details>

## How It Works

tiny-cmdline hooks into Neovim's internal `vim._core.ui2` system, which manages the floating cmdline window introduced in Neovim 0.12. On every `CmdlineEnter` it repositions that window to the center of the editor, and on `CmdlineLeave` it restores the original position so that post-command messages still render correctly at the bottom.

Cmdline types listed in `native_types` (search by default) are pinned to the bottom at full width, preserving the native search experience.

The window position is also updated on `VimResized` and `TabEnter` to stay correctly centered after layout changes.

## Integrations

tiny-cmdline is compatible with the most common completion plugins. The table below summarises what, if anything, is required for each.

| Plugin | Menu repositions automatically | Extra config required |
| --- | --- | --- |
| **blink.cmp** | :heavy_check_mark: with adapter | :heavy_check_mark: see below |
| **nvim-cmp** | :heavy_check_mark: | :x: |
| **mini.completion** | :heavy_check_mark: | :x: |
| **Default (built-in)** | :heavy_check_mark: | :x: |

### blink.cmp

blink.cmp manages its own menu position independently. Use the built-in adapter so it follows the repositioned cmdline window:

```lua
require("tiny-cmdline").setup({
    on_reposition = require("tiny-cmdline").adapters.blink,
})
```


## Troubleshooting

- **Cmdline stays at the bottom**: Ensure `vim.o.cmdheight = 0` is set before `setup()`.
- **Completion menu misaligned**: Tune `menu_col_offset` to match your border/padding.
- **Border doesn't match the rest of Neovim**: Leave `border = nil` to inherit `vim.o.winborder`.
- **Search feels different**: `/` and `?` are in `native_types` by default and rendered at the bottom; remove them from that list to also center them.
