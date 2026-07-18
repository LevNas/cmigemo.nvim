local M = {}

---@class CmigemoConfig
---@field cmigemo_cmd? string  backend binary path (default: auto-detect cmigemo, then rustmigemo)
---@field dict_path? string    dictionary path (default: auto-detect)
---@field query_timeout? number  response timeout in ms (default: 200)
---@field mecab_cmd? string  mecab binary for the flash reading mode
---        (default: auto-detect "mecab"; unresolvable disables the mode)

---@type CmigemoConfig
local config = {
  cmigemo_cmd = nil,
  dict_path = nil,
  query_timeout = 200,
  mecab_cmd = nil,
}

--- Backend binaries to probe when `cmigemo_cmd` is not set, in priority order.
--- cmigemo first keeps existing setups unchanged; rustmigemo is a drop-in
--- fallback (same `-q -d <dict>` interface and PCRE-style output).
---@type string[]
local CMD_CANDIDATES = { "cmigemo", "rustmigemo" }

--- Resolve the backend command to run.
---@return string|nil  binary name/path, or nil if none found
local function resolve_cmd()
  if config.cmigemo_cmd then
    return config.cmigemo_cmd
  end
  for _, cmd in ipairs(CMD_CANDIDATES) do
    if vim.fn.executable(cmd) == 1 then
      return cmd
    end
  end
  return nil
end

--- Infer the backend kind from a resolved command.
---@param cmd? string
---@return "cmigemo"|"rustmigemo"|nil
local function backend_of(cmd)
  if not cmd then
    return nil
  end
  if cmd:match("rustmigemo") then
    return "rustmigemo"
  end
  return "cmigemo"
end

---@type CmigemoProcess|nil
local process = nil

---@type boolean
local setup_done = false

--- Resolve the dictionary path for the given backend.
---@param cmd? string  resolved backend command
---@return string|nil
local function resolve_dict_path(cmd)
  local dict = require("cmigemo.core.dict")
  return dict.detect(config.dict_path, backend_of(cmd), cmd)
end

--- Ensure the process is started. Returns true if ready.
---@return boolean
local function ensure_process()
  if process and process:is_running() then
    return true
  end

  local cmd = resolve_cmd()
  if not cmd then
    return false
  end

  local dict_path = resolve_dict_path(cmd)
  if not dict_path then
    return false
  end

  local Process = require("cmigemo.core.process").Process
  process = Process.new(cmd, dict_path)
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
--- Groups become NON-capturing \%(...\): Vim allows at most 9 capturing
--- groups (E872), which group-rich migemo patterns exceed as soon as
--- several are concatenated (compound segmentation). No caller uses
--- backreferences, so capturing is never needed.
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
        parts[#parts + 1] = "\\%("
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

--- Check if a backend is available (binary exists and dictionary found).
---@return boolean
function M.is_available()
  local cmd = resolve_cmd()
  if not cmd or vim.fn.executable(cmd) ~= 1 then
    return false
  end
  return resolve_dict_path(cmd) ~= nil
end

--- Resolve the backend command that would be used (cmigemo, rustmigemo, ...).
--- Intended for diagnostics (e.g. :checkhealth).
---@return string|nil
function M.resolved_cmd()
  return resolve_cmd()
end

--- The backend kind that would be used.
---@return "cmigemo"|"rustmigemo"|nil
function M.backend()
  return backend_of(resolve_cmd())
end

--- The dictionary path that would be used for the resolved backend.
---@return string|nil
function M.dict_path()
  return resolve_dict_path(resolve_cmd())
end

--- Resolve the mecab command for the reading mode (nil = mode disabled).
---@return string|nil
function M.mecab_cmd()
  if config.mecab_cmd then
    return config.mecab_cmd
  end
  if vim.fn.executable("mecab") == 1 then
    return "mecab"
  end
  return nil
end

--- Stop the cmigemo process.
function M.stop()
  if process then
    process:stop()
    process = nil
  end
end

return M
