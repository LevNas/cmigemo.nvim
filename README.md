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

```
lua/cmigemo/
├── init.lua           -- Core API (setup, query, is_available, stop)
├── health.lua         -- :checkhealth cmigemo
├── core/
│   ├── process.lua    -- Subprocess management (stdin/stdout IPC)
│   └── dict.lua       -- Dictionary auto-detection
└── ext/
    ├── flash.lua      -- flash.nvim integration (migemo jump, bunsetsu jump)
    ├── snacks.lua     -- snacks.nvim picker integration (grep migemo)
    └── bunsetsu.lua   -- BudouX phrase segmentation
examples/
├── flash.lua          -- lazy.nvim config example for flash.nvim
└── snacks-picker.lua  -- lazy.nvim config example for snacks.nvim picker
```

## Health Check

```vim
:checkhealth cmigemo
```

## Integration Examples

Configuration samples for lazy.nvim are available in the [`examples/`](examples/) directory.

- [`examples/flash.lua`](examples/flash.lua) — flash.nvim integration (migemo jump, bunsetsu jump)
- [`examples/snacks-picker.lua`](examples/snacks-picker.lua) — snacks.nvim picker integration (grep with migemo)

## Acknowledgments

- [cmigemo](https://github.com/koron/cmigemo) by MURAOKA Taro (KoRoN) — the C/Migemo engine that powers this plugin's romaji-to-Japanese pattern conversion
- [budoux.lua](https://github.com/atusy/budoux.lua) by atusy — Lua port of Google's [BudouX](https://github.com/google/budoux) line break organizer, used for bunsetsu (phrase) segmentation

## License

MIT
