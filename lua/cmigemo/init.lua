local M = {}

---@class CmigemoConfig
---@field cmigemo_cmd? string  cmigemo binary path (default: "cmigemo")
---@field dict_path? string    dictionary path (default: auto-detect)
---@field query_timeout? number  response timeout in ms (default: 200)

---@type CmigemoConfig
local config = {
  cmigemo_cmd = "cmigemo",
  dict_path = nil,
  query_timeout = 200,
}

---@type CmigemoProcess|nil
local process = nil

---@type boolean
local setup_done = false

--- Resolve the dictionary path from config.
---@return string|nil
local function resolve_dict_path()
  local dict = require("cmigemo.dict")
  return dict.detect(config.dict_path)
end

--- Ensure the process is started. Returns true if ready.
---@return boolean
local function ensure_process()
  if process and process:is_running() then
    return true
  end

  local dict_path = resolve_dict_path()
  if not dict_path then
    return false
  end

  local Process = require("cmigemo.process").Process
  process = Process.new(config.cmigemo_cmd, dict_path)
  return process:start()
end

--- Configure cmigemo.nvim. Does NOT start the process (lazy startup).
---@param opts? CmigemoConfig
function M.setup(opts)
  config = vim.tbl_deep_extend("force", config, opts or {})
  setup_done = true

  -- Register cleanup autocmd
  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = vim.api.nvim_create_augroup("cmigemo_cleanup", { clear = true }),
    callback = function()
      M.stop()
    end,
  })
end

---@class CmigemoQueryOpts
---@field rxop? "pcre"|"vim"  regex format (default: "pcre")

--- Convert PCRE-style regex to Vim magic mode.
--- Escapes (, ), | with backslash outside character classes.
---@param pcre string
---@return string
local function pcre_to_vim_magic(pcre)
  local parts = {}
  local in_class = false
  local i = 1
  while i <= #pcre do
    local b = pcre:byte(i)
    if in_class then
      parts[#parts + 1] = string.char(b)
      if b == 93 then -- ]
        in_class = false
      elseif b == 92 then -- \
        i = i + 1
        if i <= #pcre then
          parts[#parts + 1] = pcre:sub(i, i)
        end
      end
    else
      if b == 91 then -- [
        in_class = true
        parts[#parts + 1] = "["
      elseif b == 40 then -- (
        parts[#parts + 1] = "\\("
      elseif b == 41 then -- )
        parts[#parts + 1] = "\\)"
      elseif b == 124 then -- |
        parts[#parts + 1] = "\\|"
      elseif b == 92 then -- \
        parts[#parts + 1] = "\\"
        i = i + 1
        if i <= #pcre then
          parts[#parts + 1] = pcre:sub(i, i)
        end
      else
        parts[#parts + 1] = string.char(b)
      end
    end
    i = i + 1
  end
  return table.concat(parts)
end

--- Query cmigemo for a migemo regex pattern.
---@param word string  query word
---@param opts? CmigemoQueryOpts
---@return string|nil  regex pattern on success, nil on failure
function M.query(word, opts)
  if not word or word == "" then
    return nil
  end

  -- Auto-setup with defaults if not yet configured
  if not setup_done then
    M.setup()
  end

  if not ensure_process() then
    return nil
  end

  opts = opts or {}
  local rxop = opts.rxop or "pcre"

  local result = process:query(word, config.query_timeout)
  if not result or result == "" then
    return nil
  end

  if rxop == "vim" then
    local vim_pattern = pcre_to_vim_magic(result)
    if pcall(vim.regex, vim_pattern) then
      return vim_pattern
    end
    -- Full pattern too complex for Vim regex engine.
    -- Fall back to character class only (matches single characters).
    local bracket_end = result:find("]", 1, true)
    if bracket_end and result:sub(1, 2) == "([" then
      local class_only = result:sub(2, bracket_end)
      if pcall(vim.regex, class_only) then
        return class_only
      end
    end
    return nil
  end

  return result
end

--- Check if cmigemo is available (binary exists and dictionary found).
---@return boolean
function M.is_available()
  if vim.fn.executable(config.cmigemo_cmd) ~= 1 then
    return false
  end
  return resolve_dict_path() ~= nil
end

--- Stop the cmigemo process.
function M.stop()
  if process then
    process:stop()
    process = nil
  end
end

return M
