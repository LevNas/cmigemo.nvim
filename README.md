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

### Flash.nvim (Migemo Jump with Custom Loop)

A custom input loop for flash.nvim that resolves the conflict between label characters and search input in migemo mode.

**Features:**
- Case-insensitive search (`\c` flag)
- Search extension takes priority over label jumping — typing a character that extends the search will never accidentally trigger a label jump
- Labels that would conflict with search extension are automatically hidden
- Zero-match input is rejected with a visual flash (red)
- CR with multiple matches is rejected with a visual flash (yellow)
- Falls back to literal search when cmigemo is unavailable

```lua
-- lazy.nvim plugin spec
{
  "folke/flash.nvim",
  event = "VeryLazy",
  opts = {
    labels = "asdfghjklqwertyuiopzxcvbnm",
    modes = {
      char = { enabled = false },
      search = { enabled = false },
    },
    jump = { pos = "start" },
  },
  config = function(_, opts)
    require("flash").setup(opts)
    vim.api.nvim_set_hl(0, "FlashNoMatch", { bg = "#4c1c1c", default = true })
    vim.api.nvim_set_hl(0, "FlashMultiLabel", { bg = "#3b3514", default = true })
  end,
  keys = {
    {
      "f",
      mode = { "n", "x", "o" },
      function()
        local State = require("flash.state")
        local Prompt = require("flash.prompt")
        local Util = require("flash.util")

        local function flash_screen(hl_group, duration_ms)
          local ns = vim.api.nvim_create_namespace("flash_migemo_effect")
          for _, win in ipairs(vim.api.nvim_list_wins()) do
            local buf = vim.api.nvim_win_get_buf(win)
            local ok, info = pcall(vim.fn.getwininfo, win)
            if ok and info[1] then
              for line = info[1].topline, info[1].botline do
                pcall(vim.api.nvim_buf_set_extmark, buf, ns, line - 1, 0, {
                  hl_eol = true,
                  line_hl_group = hl_group,
                  priority = 10000,
                })
              end
            end
          end
          vim.cmd("redraw")
          vim.wait(duration_ms or 80, function() return false end)
          for _, b in ipairs(vim.api.nvim_list_bufs()) do
            pcall(vim.api.nvim_buf_clear_namespace, b, ns, 0, -1)
          end
          vim.cmd("redraw")
        end

        -- search_pattern: migemo regex with \c for case-insensitive
        -- skip_pattern: literal ASCII only (prevents Japanese matches
        --   from excluding unrelated label characters)
        local function migemo_mode(str)
          if str == "" then return "" end
          local skip = "\\V\\c" .. str:gsub("\\", "\\\\")
          local ok, cmigemo = pcall(require, "cmigemo")
          if ok then
            local pattern = cmigemo.query(str, { rxop = "vim" })
            if pattern then return "\\c" .. pattern, skip end
          end
          return skip
        end

        local state = State.new({
          search = { mode = migemo_mode },
          jump = { pos = "start" },
        })

        -- Wrap labeler: hide labels whose character would extend the search
        local orig_labeler = state.labeler
        local lbl_cache_pat, lbl_cache_rm = nil, {}

        state.labeler = function(matches, s)
          orig_labeler(matches, s)
          local cur = s.pattern()
          if cur == "" then return end
          if cur ~= lbl_cache_pat then
            lbl_cache_pat = cur
            lbl_cache_rm = {}
            local checked = {}
            for _, m in ipairs(matches) do
              local c = m.label
              if c and not checked[c] then
                checked[c] = true
                local tp = migemo_mode(cur .. c)
                if tp ~= "" then
                  for _, win in ipairs(s.wins) do
                    local found = 0
                    pcall(vim.api.nvim_win_call, win, function()
                      found = vim.fn.search(tp, "cnw")
                    end)
                    if found > 0 then
                      lbl_cache_rm[c] = true
                      break
                    end
                  end
                end
              end
            end
          end
          if next(lbl_cache_rm) then
            for _, m in ipairs(matches) do
              if m.label and lbl_cache_rm[m.label] then m.label = nil end
            end
          end
        end

        state:update({ force = true })

        while true do
          Prompt.set(state.pattern(), state.opts.prompt.enabled)
          local c = state:get_char()

          if c == nil then
            vim.api.nvim_input("<esc>")
            state:restore()
            break
          elseif c == Util.CR then
            if #state.results <= 1 then
              state:jump()
              break
            else
              flash_screen("FlashMultiLabel", 80)
            end
          elseif c == Util.BS then
            state:update({ pattern = state.pattern:extend(c), check_jump = false })
          else
            local new_pattern = state.pattern:extend(c)
            local orig = state.pattern()

            -- Try search extension first (priority over label jump)
            state:update({ pattern = new_pattern, check_jump = false })

            if #state.results > 0 then
              if #state.results == 1 and state.opts.jump.autojump then
                state:jump()
                break
              end
            elseif not state.pattern:empty() then
              -- Zero matches: revert pattern, then try label jump
              state:update({ pattern = orig, check_jump = false })
              if state:check_jump(new_pattern) then break end
              flash_screen("FlashNoMatch", 80)
            end
          end
        end

        state:hide()
        Prompt.hide()
      end,
      desc = "Flash: Migemo Jump",
    },
  },
}
```

### Flash.nvim (`/` Search with Migemo)

Overlay migemo match highlights during Vim's native `/` and `?` search. On `<CR>`, the cmdline is replaced with the migemo pattern so that `n`/`N` navigation works with Japanese matches.

Requires flash.nvim to be loaded (e.g. via `VeryLazy` event or `keys`).

```lua
-- Place in your Neovim config (e.g. after flash.nvim setup)
local function setup_migemo_search()
  local State = require("flash.state")
  local migemo_search_state = nil
  local group = vim.api.nvim_create_augroup("flash_migemo_search", { clear = true })

  local function migemo_mode(str)
    if str == "" then return "" end
    local skip = "\\V\\c" .. str:gsub("\\", "\\\\")
    local ok, cmigemo = pcall(require, "cmigemo")
    if ok then
      local pattern = cmigemo.query(str, { rxop = "vim" })
      if pattern then return "\\c" .. pattern, skip end
    end
    return skip
  end

  vim.api.nvim_create_autocmd("CmdlineEnter", {
    group = group,
    callback = function()
      local t = vim.fn.getcmdtype()
      if t ~= "/" and t ~= "?" then return end

      migemo_search_state = State.new({
        search = {
          forward = t == "/",
          mode = migemo_mode,
          incremental = true,
        },
        highlight = { backdrop = false },
      })

      -- Replace cmdline with migemo pattern before submit
      vim.keymap.set("c", "<CR>", function()
        local raw = vim.fn.getcmdline()
        if raw ~= "" and migemo_search_state then
          local pat = migemo_mode(raw)
          if pat ~= "" then
            vim.fn.setcmdline(pat)
          end
        end
        vim.api.nvim_feedkeys(
          vim.api.nvim_replace_termcodes("<CR>", true, true, true), "n", true
        )
      end)
    end,
  })

  vim.api.nvim_create_autocmd("CmdlineChanged", {
    group = group,
    callback = function()
      if not migemo_search_state then return end
      local pattern = vim.fn.getcmdline()
      local t = vim.fn.getcmdtype()
      if pattern:sub(1, 1) == t then
        pattern = vim.fn.getreg("/") .. pattern:sub(2)
      end
      migemo_search_state:update({ pattern = pattern, check_jump = false })
    end,
  })

  vim.api.nvim_create_autocmd("CmdlineLeave", {
    group = group,
    callback = function()
      pcall(vim.keymap.del, "c", "<CR>")
      if migemo_search_state then
        migemo_search_state:hide()
        migemo_search_state = nil
      end
    end,
  })
end

-- Call after flash.nvim is loaded
-- e.g. in flash.nvim's config function:
--   config = function(_, opts)
--     require("flash").setup(opts)
--     setup_migemo_search()
--   end,
setup_migemo_search()
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
