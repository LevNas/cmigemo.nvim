# cmigemo.nvim

Lightweight migemo search plugin for Neovim using [cmigemo](https://github.com/koron/cmigemo) (C implementation) as backend.

## Requirements

- Neovim 0.10+
- [cmigemo](https://github.com/koron/cmigemo) installed and in PATH
- cmigemo dictionary (usually installed with cmigemo)

## Installation

### lazy.nvim

```lua
{
  "LevNas/cmigemo.nvim",
  opts = {},
}
```

## Setup

```lua
require("cmigemo").setup({
  cmigemo_cmd = "cmigemo",  -- cmigemo binary path (default: "cmigemo")
  dict_path = nil,           -- dictionary path (default: auto-detect)
  query_timeout = 200,       -- response timeout in ms (default: 200)
})
```

Setup is optional. If `query()` is called without prior `setup()`, default settings are used automatically.

## API

### `require("cmigemo").query(word, opts?)`

Convert a romaji/ASCII query into a migemo regex pattern.

```lua
-- PCRE format (default) - for ripgrep, etc.
local pattern = require("cmigemo").query("nihongo")
-- => "(nihongo|にほんご|ニホンゴ|日本語|...)"

-- Vim very magic format - for Vim search, Flash, etc.
local pattern = require("cmigemo").query("kensaku", { rxop = "vim" })
-- => "\v(nihongo|にほんご|ニホンゴ|日本語|...)"
```

**Parameters:**
- `word` (string): Query word
- `opts.rxop` (`"pcre"` | `"vim"`): Regex format (default: `"pcre"`)

**Returns:** `string|nil` - Regex pattern on success, `nil` on failure

### `require("cmigemo").is_available()`

Check if cmigemo binary and dictionary are available.

**Returns:** `boolean`

### `require("cmigemo").stop()`

Stop the resident cmigemo process.

## Architecture

cmigemo.nvim runs `cmigemo -q -d <dict>` as a resident process and communicates via stdin/stdout. The process is started lazily on the first `query()` call and automatically stopped on `VimLeavePre`.

## Health Check

```vim
:checkhealth cmigemo
```

## Integration Examples

### Flash.nvim (Migemo Jump)

Add a keymap that uses cmigemo to convert romaji input into a migemo pattern for Flash's search mode. When cmigemo is unavailable, it falls back to literal search.

```lua
-- lazy.nvim plugin spec
{
  "folke/flash.nvim",
  keys = {
    {
      "F",
      mode = { "n", "x", "o" },
      function()
        require("flash").jump({
          search = {
            mode = function(str)
              if str == "" then return "" end
              local pattern = require("cmigemo").query(str, { rxop = "vim" })
              if pattern then return pattern end
              return "\\V" .. str:gsub("\\", "\\\\")
            end,
          },
        })
      end,
      desc = "Flash: Migemo Jump",
    },
  },
}
```

### Snacks.nvim Picker (Grep Migemo)

Define a custom picker source that transforms the search input through cmigemo before passing it to ripgrep. This enables romaji-to-Japanese grep search.

```lua
-- lazy.nvim plugin spec
{
  "folke/snacks.nvim",
  opts = {
    picker = {
      sources = {
        grep_migemo = {
          finder = function(opts, ctx)
            local search = ctx.filter.search
            if search ~= "" then
              local ok, cmigemo = pcall(require, "cmigemo")
              if ok then
                local pattern = cmigemo.query(search)
                if pattern then
                  ctx.filter.search = pattern
                  local result = require("snacks.picker.source.grep").grep(opts, ctx)
                  ctx.filter.search = search
                  return result
                end
              end
            end
            return require("snacks.picker.source.grep").grep(opts, ctx)
          end,
          format = "file",
          regex = true,
          show_empty = true,
          live = true,
          need_search = true,
          supports_live = true,
        },
      },
    },
  },
  keys = {
    { "<leader>fK", function() Snacks.picker.grep_migemo() end, desc = "Grep Migemo" },
  },
}
```

## License

MIT
