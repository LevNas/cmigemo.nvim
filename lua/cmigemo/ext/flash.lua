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

--- Concatenate the visible lines of the state's target windows.
---@param state Flash.State
---@return string
local function visible_text(state)
  local wins = (state.wins and #state.wins > 0) and state.wins
    or { vim.api.nvim_get_current_win() }
  local chunks = {}
  for _, win in ipairs(wins) do
    if vim.api.nvim_win_is_valid(win) then
      local buf = vim.api.nvim_win_get_buf(win)
      local info = vim.fn.getwininfo(win)[1]
      if info then
        local lines = vim.api.nvim_buf_get_lines(buf, info.topline - 1, info.botline, false)
        chunks[#chunks + 1] = table.concat(lines, "\n")
      end
    end
  end
  return table.concat(chunks, "\n")
end

--- Compute label chars to exclude for the given query by one-char lookahead.
--- A char is "hot" (excluded from labels) when `query .. char` still matches
--- somewhere in the visible windows — i.e. pressing it is a meaningful search
--- continuation, so it must extend the query instead of jumping. The predicate
--- uses the same pattern generator as the search itself, so a displayed label
--- is guaranteed to jump and a viable continuation is guaranteed to type.
--- Exposed for testing; treat as internal API.
---@param state Flash.State
---@param query string  the query the exclusion is computed for
---@return string  concatenated hot chars (flash `label.exclude` format)
function M.lookahead_exclude(state, query)
  local cmigemo = require("cmigemo")
  local text = visible_text(state)
  local pool = state.opts.labels or ""
  local seen, hot = {}, {}
  for i = 1, #pool do
    local c = pool:sub(i, i)
    if not seen[c] then
      seen[c] = true
      local pat = cmigemo.query(query .. c, { rxop = "vim" })
      local matched
      if pat then
        local ok, re = pcall(vim.regex, "\\m" .. pat)
        matched = ok and re and re:match_str(text) ~= nil
      else
        -- Backend failure / romaji mid-state with no pattern: be conservative
        -- and keep the char for typing rather than stealing it as a label.
        matched = true
      end
      if matched then
        hot[#hot + 1] = c
      end
    end
  end
  return table.concat(hot)
end

--- Build action handlers for a-z and 0-9.
--- When the typed char matches a visible label → jump to label. Otherwise →
--- extend the search pattern via migemo and refresh the lookahead exclusion,
--- so labels are only ever assigned to chars that cannot continue the query.
---@param base_exclude string  label.exclude from the jump config
---@return table<string, fun(state: Flash.State, char: string): boolean?>
local function romaji_actions(base_exclude)
  local actions = {}
  local chars = "abcdefghijklmnopqrstuvwxyz0123456789"
  for i = 1, #chars do
    local c = chars:sub(i, i)
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

      -- No label match → extend search pattern. Recompute the lookahead
      -- exclusion BEFORE update so the labeler only assigns safe chars.
      local extended = state.pattern:extend(char)
      state.opts.label.exclude = base_exclude .. M.lookahead_exclude(state, extended)
      state:update({ pattern = extended, check_jump = false })
      -- Continue loop even with 0 results (romaji mid-input like "lu")
    end
  end
  return actions
end

--- Jump with migemo-enhanced pattern matching.
--- Typed characters extend the search; label characters jump. The two never
--- conflict: one-char lookahead removes every viable search continuation from
--- the label pool before labels are assigned (see `lookahead_exclude`).
---@param opts? Flash.State.Config
function M.jump(opts)
  local Repeat = require("flash.repeat")

  opts = vim.tbl_deep_extend(
    "force",
    { label = { min_pattern_length = 1 } },
    opts or {},
    { search = { mode = M.migemo_mode() } }
  )

  local state = Repeat.get_state("jump", opts)

  state:loop({
    actions = romaji_actions(state.opts.label.exclude or ""),
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
