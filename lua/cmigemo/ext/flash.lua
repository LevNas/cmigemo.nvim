local M = {}

--- Create a flash search.mode function that transforms input via cmigemo.
--- Returns a Vim regex pattern for use with vim.fn.searchpos().
---@return fun(input: string): string, string?
function M.migemo_mode()
  return function(input)
    if not input or input == "" then
      return ""
    end

    local cmigemo = require("cmigemo")
    local pattern = cmigemo.query(input, { rxop = "vim" })
    if pattern then
      -- Pattern from cmigemo.query with rxop="vim" uses Vim's default magic
      -- mode syntax (\( \) \| for groups and alternation).
      -- Use \m prefix to ensure magic mode regardless of user settings.
      return "\\m" .. pattern
    end

    -- Fallback: exact match (same as flash "exact" mode)
    return "\\V" .. input:gsub("\\", "\\\\")
  end
end

--- Setup cmigemo.flash integration (called during flash config).
function M.setup()
  vim.api.nvim_set_hl(0, "FlashInputReject", { bg = "#3c1f1f", default = true })
end

local reject_ns = vim.api.nvim_create_namespace("cmigemo_flash_reject")

--- Briefly flash all visible lines to indicate rejected input.
local function flash_reject()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  local info = vim.fn.getwininfo(win)[1]
  for lnum = info.topline, info.botline do
    vim.api.nvim_buf_set_extmark(buf, reject_ns, lnum - 1, 0, {
      line_hl_group = "FlashInputReject",
      priority = 1000,
    })
  end
  vim.cmd.redraw()
  vim.defer_fn(function()
    vim.api.nvim_buf_clear_namespace(buf, reject_ns, 0, -1)
    vim.cmd.redraw()
  end, 100)
end

--- Build action handlers for a-z.
--- When labels are visible and the typed char matches a label → jump to label.
--- Otherwise → extend the search pattern via migemo.
--- This allows romaji input to flow naturally while labels remain accessible.
---@return table<string, fun(state: Flash.State, char: string): boolean?>
local function romaji_actions()
  local actions = {}
  for b = string.byte("a"), string.byte("z") do
    local c = string.char(b)
    actions[c] = function(state, char)
      -- Check if the char matches any visible label
      for _, m in ipairs(state.results) do
        if m.label == char then
          -- Label match found → jump
          if state:jump(char) then
            return false -- exit loop
          end
          break
        end
      end

      -- No label match → extend search pattern
      local extended = state.pattern:extend(char)
      state:update({ pattern = extended, check_jump = false })
      -- Continue loop even with 0 results (romaji mid-input like "lu")
    end
  end
  return actions
end

--- Jump with migemo-enhanced pattern matching.
--- When labels are visible, label characters trigger a jump; other characters
--- extend the search pattern. Before labels appear (< min_pattern_length),
--- all a-z input extends the search.
---@param opts? Flash.State.Config
function M.jump(opts)
  local Repeat = require("flash.repeat")

  opts = vim.tbl_deep_extend("force", opts or {}, {
    search = {
      mode = M.migemo_mode(),
    },
    label = {
      min_pattern_length = 3,
    },
  })

  local state = Repeat.get_state("jump", opts)

  state:loop({
    actions = romaji_actions(),
    jump_on_max_length = false,
  })
  return state
end

--- Jump to bunsetsu (phrase) boundaries using BudouX segmenter.
---@param opts? Flash.State.Config
---@param group_size? number 何文節をひとまとまりにするか (default: 2)
function M.bunsetsu(opts, group_size)
  local bunsetsu = require("cmigemo.ext.bunsetsu")
  if not bunsetsu.is_available() then
    vim.notify("budoux.lua is not installed", vim.log.levels.WARN, { title = "cmigemo.nvim" })
    return
  end
  local Config = require("flash.config")
  local Repeat = require("flash.repeat")
  local Util = require("flash.util")

  local state = Repeat.get_state(
    "bunsetsu",
    Config.get({ mode = "bunsetsu" }, opts, {
      matcher = bunsetsu.matcher,
      labeler = function() end,
      search = { multi_window = true, wrap = true, incremental = false, max_length = 0 },
      label = { before = { 0, 0 }, after = false },
      jump = { pos = "start" },
    })
  )
  state._bunsetsu_group_size = group_size or 2

  state:loop({
    abort = function() Util.exit() end,
    actions = {
      [";"] = "next",
      [","] = "prev",
      ["next"] = function()
        state:jump({ forward = true })
      end,
      ["prev"] = function()
        state:jump({ forward = false })
      end,
      [Util.CR] = function()
        state:jump()
        return false
      end,
    },
    jump_on_max_length = false,
  })
  return state
end

return M
