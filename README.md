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
local pattern = require("cmigemo").query("kensaku")
-- => "(kensaku|けんさく|ケンサク|検索|...)"

-- Vim very magic format - for Vim search, Flash, etc.
local pattern = require("cmigemo").query("kensaku", { rxop = "vim" })
-- => "\v(kensaku|けんさく|ケンサク|検索|...)"
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

```lua
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
```

### Snacks.nvim Picker (Grep with Migemo)

```lua
require("snacks").setup({
  picker = {
    sources = {
      grep_kensaku = {
        finder = function(opts, ctx)
          local search = ctx.filter.search
          if search ~= "" then
            local pattern = require("cmigemo").query(search)
            if pattern then
              ctx.filter.search = pattern
              local result = require("snacks.picker.source.grep").grep(opts, ctx)
              ctx.filter.search = search
              return result
            end
          end
          return require("snacks.picker.source.grep").grep(opts, ctx)
        end,
        need_search = true,
        supports_live = true,
      },
    },
  },
})
```

## License

MIT
