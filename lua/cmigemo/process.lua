local M = {}

---@class CmigemoProcess
---@field job_id number|nil
---@field cmd string
---@field dict_path string
---@field _result string|nil
---@field _buf string
local Process = {}
Process.__index = Process

--- Create a new Process instance.
---@param cmd string  cmigemo binary path
---@param dict_path string  dictionary path
---@return CmigemoProcess
function Process.new(cmd, dict_path)
  return setmetatable({
    job_id = nil,
    cmd = cmd,
    dict_path = dict_path,
    _result = nil,
    _buf = "",
  }, Process)
end

--- Start the cmigemo process.
---@return boolean  true if started successfully
function Process:start()
  if self.job_id and vim.fn.jobwait({ self.job_id }, 0)[1] == -1 then
    return true -- already running
  end

  self._result = nil
  self._buf = ""

  local job_id = vim.fn.jobstart({ self.cmd, "-q", "-d", self.dict_path }, {
    on_stdout = function(_, data, _)
      self:_on_stdout(data)
    end,
    on_exit = function(_, _, _)
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

--- Handle stdout data from cmigemo.
--- Accumulates partial output until a complete line is received.
---@param data string[]
function Process:_on_stdout(data)
  for i, chunk in ipairs(data) do
    if i == 1 then
      self._buf = self._buf .. chunk
    else
      -- newline boundary: previous buffer is a complete line
      if self._buf ~= "" then
        self._result = self._buf
      end
      self._buf = chunk
    end
  end
end

--- Send a query and wait for the result synchronously.
---@param word string  query word
---@param timeout number  timeout in milliseconds
---@return string|nil  regex pattern or nil on failure/timeout
function Process:query(word, timeout)
  if not self.job_id then
    if not self:start() then
      return nil
    end
  end

  self._result = nil
  self._buf = ""

  local ok = pcall(vim.fn.chansend, self.job_id, word .. "\n")
  if not ok then
    -- broken pipe: process died, reset and fail
    self.job_id = nil
    return nil
  end

  local got_result = vim.wait(timeout, function()
    return self._result ~= nil
  end, 5)

  if not got_result then
    return nil
  end

  local result = self._result
  self._result = nil
  return result
end

--- Check if the process is running.
---@return boolean
function Process:is_running()
  if not self.job_id then
    return false
  end
  return vim.fn.jobwait({ self.job_id }, 0)[1] == -1
end

--- Stop the cmigemo process.
function Process:stop()
  if self.job_id then
    pcall(vim.fn.jobstop, self.job_id)
    self.job_id = nil
  end
  self._result = nil
  self._buf = ""
end

M.Process = Process

return M
