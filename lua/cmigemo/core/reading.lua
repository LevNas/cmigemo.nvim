local M = {}

--- Reading index + matcher for the MeCab reading mode.
--- The visible buffer text is analyzed into morphemes with katakana
--- readings; a romaji query (converted to kana) is matched as a prefix of
--- the reading stream, starting at morpheme boundaries and crossing
--- morphemes freely. Morphemes without a reading break the stream.

---@class ReadingLine
---@field morphemes {surface: string, col: integer, chars: string[]|nil, len: integer}[]

--- Split a katakana reading into a char array (multibyte-safe).
---@param s string
---@return string[]
local function chars_of(s)
  return vim.fn.split(s, "\\zs")
end

--- Unknown words carry no reading feature (e.g. loanwords missing from the
--- 2007-era ipadic, like スマートフォン), which breaks the reading stream
--- even though a katakana surface reads as itself. Worse, the same word can
--- tokenize differently by context (unknown here, split into known
--- morphemes there), so one partial hit masks the 0-hit migemo fallback
--- and the unknown occurrence silently drops out of the matches.
--- Synthesize the reading for pure-katakana surfaces instead.
local katakana_surface = vim.regex("^[ァ-ヶー]\\+$")

--- Build the index for a list of lines.
---@param mecab MecabProcess
---@param lines string[]
---@param timeout number
---@return ReadingLine[]|nil  index aligned with `lines`, nil on mecab failure
function M.build(mecab, lines, timeout)
  local index = {}
  for i, line in ipairs(lines) do
    local ms = mecab:analyze(line, timeout)
    if ms == nil then
      return nil
    end
    local entry = {}
    for _, m in ipairs(ms) do
      local reading = m.reading
      if not reading and katakana_surface:match_str(m.surface) then
        reading = m.surface
      end
      local chars = reading and chars_of(reading) or nil
      entry[#entry + 1] = {
        surface = m.surface,
        col = m.col,
        chars = chars,
        len = chars and #chars or 0,
      }
    end
    index[i] = { morphemes = entry }
  end
  return index
end

--- Does query char q match reading char r?
--- Long vowel mark ー loosely accepts any vowel query char (v1 tradeoff for
--- loanwords like コンピューター).
---@param q string
---@param r string
---@return boolean
local function char_match(q, r)
  if q == r then
    return true
  end
  if r == "ー" then
    return q == "ア" or q == "イ" or q == "ウ" or q == "エ" or q == "オ"
  end
  return false
end

--- Match the kana query against one line, returning byte ranges.
---@param entry ReadingLine
---@param qchars string[]  query kana chars
---@param pending string|nil  allowed chars for the char right after the kana
---@return {col: integer, end_col: integer}[]  0-based byte [start, end) ranges
local function match_line(entry, qchars, pending)
  local ms = entry.morphemes
  local out = {}
  for s = 1, #ms do
    if ms[s].chars then
      local mi, ri = s, 1
      local qi = 1
      local ok = true
      while qi <= #qchars do
        -- advance to a morpheme with remaining reading chars
        while mi <= #ms and ms[mi].chars and ri > ms[mi].len do
          mi = mi + 1
          ri = 1
        end
        if mi > #ms or not ms[mi].chars then
          ok = false
          break
        end
        if char_match(qchars[qi], ms[mi].chars[ri]) then
          qi = qi + 1
          ri = ri + 1
        else
          ok = false
          break
        end
      end
      if ok and pending then
        -- the NEXT reading char must be in the allowed row
        while mi <= #ms and ms[mi].chars and ri > ms[mi].len do
          mi = mi + 1
          ri = 1
        end
        if mi > #ms or not ms[mi].chars then
          ok = false
        else
          ok = pending:find(ms[mi].chars[ri], 1, true) ~= nil
          if ok then
            ri = ri + 1
          end
        end
      end
      if ok then
        -- span: start of morpheme s .. end of the last touched morpheme
        local last = mi
        if ri == 1 and last > s then
          last = last - 1 -- nothing consumed from mi yet
        end
        last = math.min(last, #ms)
        local m_last = ms[last]
        out[#out + 1] = {
          col = ms[s].col,
          end_col = m_last.col + #m_last.surface,
        }
      end
    end
  end
  return out
end

--- Match a kana query over the whole index.
---@param index ReadingLine[]
---@param kana string
---@param pending string|nil
---@return {lnum: integer, col: integer, end_col: integer}[]  lnum is 1-based
---        index position (caller maps to buffer line numbers)
function M.match(index, kana, pending)
  local qchars = chars_of(kana)
  if #qchars == 0 and not pending then
    return {}
  end
  local out = {}
  for lnum, entry in ipairs(index) do
    for _, r in ipairs(match_line(entry, qchars, pending)) do
      out[#out + 1] = { lnum = lnum, col = r.col, end_col = r.end_col }
    end
  end
  return out
end

return M
