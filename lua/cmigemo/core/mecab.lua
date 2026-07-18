local M = {}

--- Persistent MeCab process (same jobstart pattern as core/process.lua).
--- One query = one text line in, morpheme lines out until "EOS".
---@class MecabProcess
---@field job_id number|nil
---@field cmd string
---@field _lines string[]
---@field _done boolean
---@field _buf string
local Mecab = {}
Mecab.__index = Mecab

---@param cmd string
---@return MecabProcess
function Mecab.new(cmd)
  return setmetatable({
    job_id = nil,
    cmd = cmd,
    _lines = {},
    _done = false,
    _buf = "",
  }, Mecab)
end

function Mecab:start()
  if self.job_id and vim.fn.jobwait({ self.job_id }, 0)[1] == -1 then
    return true
  end
  self._lines = {}
  self._done = false
  self._buf = ""
  local job_id = vim.fn.jobstart({ self.cmd }, {
    on_stdout = function(_, data, _)
      for i, chunk in ipairs(data) do
        if i == 1 then
          self._buf = self._buf .. chunk
        else
          if self._buf == "EOS" then
            self._done = true
          elseif self._buf ~= "" then
            self._lines[#self._lines + 1] = self._buf
          end
          self._buf = chunk
        end
      end
    end,
    on_exit = function()
      self.job_id = nil
    end,
    stdin = "pipe",
    stdout_buffered = false,
  })
  if job_id <= 0 then
    self.job_id = nil
    return false
  end
  self.job_id = job_id
  return true
end

function Mecab:stop()
  if self.job_id then
    pcall(vim.fn.jobstop, self.job_id)
    self.job_id = nil
  end
end

--- Analyze one line of text.
--- Returns morphemes as { surface, reading|nil, col } (col = 0-based byte
--- offset in the line). reading is the ipadic 読み field (NOT 発音, whose
--- long-vowel forms like エイキョー break kana matching); nil for unknown
--- words and symbols.
---@param line string
---@param timeout number  milliseconds
---@return {surface: string, reading: string|nil, col: integer}[]|nil
function Mecab:analyze(line, timeout)
  if line == "" then
    return {}
  end
  if not self.job_id and not self:start() then
    return nil
  end
  self._lines = {}
  self._done = false
  self._buf = ""
  local ok = pcall(vim.fn.chansend, self.job_id, line .. "\n")
  if not ok then
    self.job_id = nil
    return nil
  end
  local got = vim.wait(timeout, function()
    return self._done
  end, 5)
  if not got then
    -- Same request/response desync hazard as the cmigemo pipe: a late reply
    -- would corrupt the next analyze(). Restart to return to lockstep.
    self:stop()
    return nil
  end

  local morphemes = {}
  local col = 0
  for _, l in ipairs(self._lines) do
    local surface, feats = l:match("^(.-)\t(.*)$")
    if surface and surface ~= "" then
      -- Surfaces appear in order; recover the byte offset by scanning from
      -- the current position (MeCab may skip whitespace).
      local s, e = line:find(surface, col + 1, true)
      if s then
        local reading = nil
        local fields = vim.split(feats, ",", { plain = true })
        -- ipadic: 品詞,細1,細2,細3,活用型,活用形,原形,読み,発音
        if #fields >= 8 and fields[8] ~= "*" and fields[8] ~= "" then
          reading = fields[8]
        end
        morphemes[#morphemes + 1] = { surface = surface, reading = reading, col = s - 1 }
        col = e
      end
    end
  end
  return morphemes
end

M.Mecab = Mecab

return M
