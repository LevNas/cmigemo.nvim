local M = {}

--- Active compound session for the current migemo jump. Set by M.jump so that
--- migemo_mode and lookahead_exclude share the same buffer-oracle
--- segmentation; nil outside a jump (plain migemo_mode users are unaffected).
---@type CmigemoCompound|nil
local active_compound = nil

--- Create a flash search.mode function that transforms input via cmigemo.
--- Returns a Vim regex pattern for use with vim.fn.searchpos().
--- Inside M.jump the active compound session segments the input at
--- dictionary-word boundaries (e.g. seisanseini → 生産性+に) using the
--- visible buffer text as the oracle.
---@return fun(input: string): string, string?
function M.migemo_mode()
  return function(input)
    if not input or input == "" then
      return ""
    end

    if active_compound then
      local pat = active_compound:pattern(input)
      if pat then
        return "\\m" .. pat
      end
    else
      -- Pattern from cmigemo.query with rxop="vim" uses Vim's default magic
      -- mode syntax (\( \) \| for groups and alternation).
      -- Use \m prefix to ensure magic mode regardless of user settings.
      local pattern = require("cmigemo").query(input, { rxop = "vim" })
      if pattern then
        return "\\m" .. pattern
      end
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
---@param state? Flash.State
---@return string
local function visible_text(state)
  local wins = (state and state.wins and #state.wins > 0) and state.wins
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

-- (segment pattern helpers live on Compound below, with per-session caches)

--- Buffer-oracle compound segmentation (one per jump session).
---
--- migemo can only cross a word boundary when the dictionary has the whole
--- reading (seisansei → 生産性), so continuations like 生産性に or 生産性向上
--- never match with a single query. Instead of dictionary heuristics, the
--- visible buffer text is used as the oracle: the input is greedily split
--- into segments whose concatenated patterns actually match somewhere on
--- screen. Matched segmentations are memoized per input prefix, so each
--- keystroke only re-searches the short unresolved tail.
---@class CmigemoCompound
---@field ok table<string, {parts: string[], pat: string}>
---@field fail table<string, boolean>
---@field text string|nil
---@field gettext fun(): string
local Compound = {}
Compound.__index = Compound

--- Maximum number of segments (e.g. 生産性+向上+を = 3).
local MAX_SEGMENTS = 4

---@param gettext fun(): string
---@return CmigemoCompound
function Compound.new(gettext)
  return setmetatable({
    ok = {},
    fail = {},
    qcache = {}, -- romaji string -> vim pattern (false = backend returned nil)
    rcache = {}, -- vim pattern -> compiled vim.regex (false = compile failed)
    ecache = {}, -- vim pattern -> match end offsets in visible text
    probe = {}, -- query .. "\1" .. char -> hot verdict
    text = nil,
    gettext = gettext,
  }, Compound)
end

function Compound:visible()
  if not self.text then
    self.text = self.gettext()
  end
  return self.text
end

--- Memoized cmigemo query (vim regex form).
---@param s string
---@return string|nil
function Compound:q(s)
  local hit = self.qcache[s]
  if hit ~= nil then
    return hit or nil
  end
  local pat = require("cmigemo").query(s, { rxop = "vim" })
  self.qcache[s] = pat or false
  return pat
end

--- Memoized compiled regex.
---@param vimpat string
---@return vim.regex|nil
function Compound:regex(vimpat)
  local hit = self.rcache[vimpat]
  if hit ~= nil then
    return hit or nil
  end
  local ok, re = pcall(vim.regex, "\\m" .. vimpat)
  self.rcache[vimpat] = (ok and re) or false
  return ok and re or nil
end

--- Does the pattern match anywhere in the visible text?
---@param vimpat string
---@return boolean
function Compound:try(vimpat)
  local re = self:regex(vimpat)
  return re ~= nil and re:match_str(self:visible()) ~= nil
end

--- Concatenated migemo pattern for an ordered list of romaji segments.
--- Each segment's pattern is already parenthesized, so plain concatenation
--- yields "segment1 immediately followed by segment2" in regex terms.
---@param parts string[]
---@return string|nil
function Compound:parts_pattern(parts)
  local out = {}
  for _, p in ipairs(parts) do
    local pat = self:q(p)
    if not pat then
      return nil
    end
    out[#out + 1] = pat
  end
  return table.concat(out)
end

--- Memoized end offsets (0-based, exclusive) of the pattern's matches.
---@param vimpat string
---@return integer[]
function Compound:ends_of(vimpat)
  local hit = self.ecache[vimpat]
  if hit then
    return hit
  end
  local ends = {}
  local re = self:regex(vimpat)
  if re then
    local text, off, guard = self:visible(), 0, 0
    while off < #text and guard < 64 do
      guard = guard + 1
      local s, e = re:match_str(text:sub(off + 1))
      if not s then
        break
      end
      ends[#ends + 1] = off + e
      off = off + (e > s and e or s + 1)
    end
  end
  self.ecache[vimpat] = ends
  return ends
end

--- Does the pattern match starting exactly at one of the offsets?
--- (68-byte window: continuation segments are short; only the anchored
--- start matters.)
---@param vimpat string
---@param ends integer[]
---@return boolean
function Compound:anchored_any(vimpat, ends)
  local re = self:regex(vimpat)
  if not re then
    return false
  end
  local text = self:visible()
  for _, e in ipairs(ends) do
    if re:match_str(text:sub(e + 1, e + 68)) == 0 then
      return true
    end
  end
  return false
end

--- Lookahead hot check for one label-pool char against a resolved query.
--- Anchored approximation of the full resegmentation search: c is hot when
--- it can extend the last segment (checked at the head segments' match
--- ends) or open a new segment (checked at the full match ends). Boundary
--- revisions (branch c of `pattern`) are not probed — a char needing one
--- may briefly become a label until the next keystroke.
---@param query string  a query with a cached segmentation
---@param c string
---@return boolean
function Compound:probe_hot(query, c)
  local key = query .. "\1" .. c
  local hit = self.probe[key]
  if hit ~= nil then
    return hit
  end
  local st = self.ok[query]
  if not st then
    return true -- unknown state: keep the char for typing
  end
  local parts = st.parts
  local head = vim.list_slice(parts, 1, #parts - 1)
  local hot = false

  -- a) c extends the last segment
  local ext_pat = self:q(parts[#parts] .. c)
  if not ext_pat then
    hot = true -- backend failure: conservative
  elseif #head == 0 then
    hot = self:try(ext_pat)
  else
    local head_pat = self:parts_pattern(head)
    hot = head_pat ~= nil and self:anchored_any(ext_pat, self:ends_of(head_pat))
  end

  -- b) c opens a new segment right after the full match
  if not hot and #parts < MAX_SEGMENTS then
    local cpat = self:q(c)
    if cpat then
      hot = self:anchored_any(cpat, self:ends_of(st.pat))
    else
      hot = true
    end
  end

  self.probe[key] = hot
  return hot
end

--- Resolve `input` into a Vim pattern.
--- Returns the pattern and whether it actually matches the visible text.
--- Unresolved inputs (romaji mid-states) fall back to the whole-input
--- pattern so behavior degrades to the non-compound mode.
---@param input string
---@return string|nil pattern
---@return boolean matched
--- How far back a segment boundary may be revised (branch c), and how many
--- cold-start split points are tried. Bounds keep worst-case keystroke cost
--- flat; longer revisions resolve on later keystrokes instead.
local RESPLIT_WINDOW = 4
local COLDSTART_SPLITS = 12

function Compound:pattern(input)
  if input == "" then
    return nil, false
  end
  local cached = self.ok[input]
  if cached then
    return cached.pat, true
  end
  local whole = self:q(input)
  if self.fail[input] then
    return whole, false
  end

  local function attempt(parts)
    if #parts > MAX_SEGMENTS then
      return nil
    end
    local pat = self:parts_pattern(parts)
    if pat and self:try(pat) then
      self.ok[input] = { parts = parts, pat = pat }
      return pat
    end
  end

  -- 1) Whole input as a single segment (the common case).
  if whole and self:try(whole) then
    self.ok[input] = { parts = { input }, pat = whole }
    return whole, true
  end

  -- 2) Already-matched prefixes + re-segmentation of the tail. A greedy
  --    segmentation can lock onto a wrong-but-matching split (e.g.
  --    seisan+seik matching 生産+性向), so when the longest prefix dead-ends,
  --    fall back to shorter matched prefixes before giving up.
  local bases = {}
  for k, v in pairs(self.ok) do
    if #k < #input and input:sub(1, #k) == k then
      bases[#bases + 1] = { len = #k, parts = v.parts }
    end
  end
  table.sort(bases, function(x, y)
    return x.len > y.len
  end)

  for bi = 1, math.min(#bases, 3) do
    local base = bases[bi].parts
    local base_len = bases[bi].len
    local head = vim.list_slice(base, 1, #base - 1)
    local last = base[#base]
    local tail = input:sub(base_len + 1)
    -- a) Extend the last segment with the whole tail.
    local parts = vim.list_slice(head)
    parts[#parts + 1] = last .. tail
    local pat = attempt(parts)
    if pat then
      return pat, true
    end
    -- b) Keep the segmentation and open new segment(s) from the tail
    --    (longest first part first).
    for i = #tail, 1, -1 do
      parts = vim.list_slice(base)
      parts[#parts + 1] = tail:sub(1, i)
      if i < #tail then
        parts[#parts + 1] = tail:sub(i + 1)
      end
      pat = attempt(parts)
      if pat then
        return pat, true
      end
    end
    -- c) Re-split inside the merged last segment + tail (covers boundaries
    --    that sit before the previous commit, e.g. haji|meru).
    local merged = last .. tail
    for i = #merged - 1, math.max(1, #merged - RESPLIT_WINDOW), -1 do
      parts = vim.list_slice(head)
      parts[#parts + 1] = merged:sub(1, i)
      parts[#parts + 1] = merged:sub(i + 1)
      pat = attempt(parts)
      if pat then
        return pat, true
      end
    end
  end

  if #bases == 0 then
    -- No known prefix (cold start): try 2-way splits, longest head first.
    for i = #input - 1, math.max(1, #input - COLDSTART_SPLITS), -1 do
      local pat = attempt({ input:sub(1, i), input:sub(i + 1) })
      if pat then
        return pat, true
      end
    end
  end

  -- Unresolved: remember the failure and degrade to the whole-input pattern.
  self.fail[input] = true
  return whole, false
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
  if active_compound then
    -- Unresolved query → zero matches → nothing gets a label, so no
    -- exclusion is needed (and probing mid-states would be wasted work).
    local _, resolved = active_compound:pattern(query)
    if not resolved then
      return ""
    end
  end
  local cmigemo = require("cmigemo")
  local text = visible_text(state)
  local pool = state.opts.labels or ""
  local seen, hot = {}, {}
  for i = 1, #pool do
    local c = pool:sub(i, i)
    if not seen[c] then
      seen[c] = true
      local matched
      if active_compound then
        -- Anchored probe against the same segmentation the search uses.
        matched = active_compound:probe_hot(query, c)
      else
        local pat = cmigemo.query(query .. c, { rxop = "vim" })
        if pat then
          local ok, re = pcall(vim.regex, "\\m" .. pat)
          matched = (ok and re and re:match_str(text) ~= nil) or not (ok and re)
        else
          -- Backend failure / romaji mid-state with no pattern: be
          -- conservative and keep the char for typing rather than stealing
          -- it as a label.
          matched = true
        end
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

  local state
  M._compound_start(function()
    return visible_text(state)
  end)

  state = Repeat.get_state("jump", opts)

  local ok, err = pcall(state.loop, state, {
    actions = romaji_actions(state.opts.label.exclude or ""),
    jump_on_max_length = false,
  })
  M._compound_stop()
  if not ok then
    error(err)
  end
  return state
end

--- Internal: start a compound session (used by M.jump and headless tests).
---@param gettext fun(): string
---@return CmigemoCompound
function M._compound_start(gettext)
  active_compound = Compound.new(gettext)
  return active_compound
end

--- Internal: end the compound session.
function M._compound_stop()
  active_compound = nil
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
