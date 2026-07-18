local M = {}

--- Dictionaries for the rustmigemo backend.
--- rustmigemo only reads the binary `migemo-compact-dict` format, which the
--- cmigemo C backend cannot load. Keep these separate so the right dictionary
--- is picked for the active backend. A plain-text `migemo-dict` is NOT listed:
--- rustmigemo panics when fed one, killing every query.
---@type string[]
local RUSTMIGEMO_DICTS = {
  -- User-local install (rustmigemo + oguna/yet-another-migemo-dict pattern).
  vim.env.HOME .. "/.local/share/migemo/migemo-compact-dict",
}

--- Compiled dictionaries for the cmigemo (C implementation) backend.
---@type string[]
local CMIGEMO_DICTS = {
  "/usr/share/cmigemo/utf-8/migemo-dict", -- Debian/Ubuntu
  "/usr/share/migemo/utf-8/migemo-dict", -- Arch/Manjaro
  "/opt/homebrew/share/migemo/utf-8/migemo-dict", -- macOS (Apple Silicon)
  "/usr/local/share/migemo/utf-8/migemo-dict", -- macOS (Intel) / manual
}

--- Candidates derived from the backend binary's install prefix
--- (<prefix>/bin/<cmd> → <prefix>/share/{migemo,cmigemo}/utf-8/migemo-dict).
--- Symlinks are resolved first so profile indirection (Nix's
--- /run/current-system/sw, home-manager profiles, Homebrew opt links, etc.)
--- lands on the real install prefix that bundles the dictionary.
---@param cmd? string
---@return string[]
local function binary_relative_candidates(cmd)
  if not cmd or cmd == "" then
    return {}
  end
  local exe = vim.fn.exepath(cmd)
  if exe == "" then
    return {}
  end
  local prefix = vim.fn.fnamemodify(vim.fn.resolve(exe), ":h:h")
  return {
    prefix .. "/share/migemo/utf-8/migemo-dict",
    prefix .. "/share/cmigemo/utf-8/migemo-dict",
  }
end

--- Build the ordered candidate list for the given backend.
---@param backend? "cmigemo"|"rustmigemo"
---@param cmd? string  resolved backend command (enables binary-relative lookup)
---@return string[]
local function candidates_for(backend, cmd)
  if backend == "rustmigemo" then
    return RUSTMIGEMO_DICTS
  elseif backend == "cmigemo" then
    local merged = binary_relative_candidates(cmd)
    vim.list_extend(merged, CMIGEMO_DICTS)
    return merged
  end
  -- Backend unknown: try rustmigemo dicts first, then cmigemo (preserves the
  -- historical lookup order).
  local merged = {}
  vim.list_extend(merged, RUSTMIGEMO_DICTS)
  vim.list_extend(merged, CMIGEMO_DICTS)
  return merged
end

--- Detect the migemo dictionary path.
--- Checks user-provided path first, then known backend-specific locations.
---@param user_path? string  User-specified dictionary path
---@param backend? "cmigemo"|"rustmigemo"  Active backend (narrows candidates)
---@param cmd? string  Resolved backend command (for binary-relative lookup)
---@return string|nil  Dictionary path if found, nil otherwise
function M.detect(user_path, backend, cmd)
  if user_path then
    if vim.fn.filereadable(user_path) == 1 then
      return user_path
    end
    return nil
  end

  for _, path in ipairs(candidates_for(backend, cmd)) do
    if vim.fn.filereadable(path) == 1 then
      return path
    end
  end

  return nil
end

return M
