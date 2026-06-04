local M = {}

--- Dictionaries for the rustmigemo backend.
--- rustmigemo reads its own `migemo-compact-dict` (or a plain `migemo-dict`),
--- which the cmigemo C backend cannot load. Keep these separate so the right
--- dictionary is picked for the active backend.
---@type string[]
local RUSTMIGEMO_DICTS = {
  -- User-local install (rustmigemo + oguna/yet-another-migemo-dict pattern).
  vim.env.HOME .. "/.local/share/migemo/migemo-compact-dict",
  vim.env.HOME .. "/.local/share/migemo/migemo-dict",
}

--- Compiled dictionaries for the cmigemo (C implementation) backend.
---@type string[]
local CMIGEMO_DICTS = {
  "/usr/share/cmigemo/utf-8/migemo-dict", -- Debian/Ubuntu
  "/usr/share/migemo/utf-8/migemo-dict", -- Arch/Manjaro
  "/opt/homebrew/share/migemo/utf-8/migemo-dict", -- macOS (Apple Silicon)
  "/usr/local/share/migemo/utf-8/migemo-dict", -- macOS (Intel) / manual
}

--- Build the ordered candidate list for the given backend.
---@param backend? "cmigemo"|"rustmigemo"
---@return string[]
local function candidates_for(backend)
  if backend == "rustmigemo" then
    return RUSTMIGEMO_DICTS
  elseif backend == "cmigemo" then
    return CMIGEMO_DICTS
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
---@return string|nil  Dictionary path if found, nil otherwise
function M.detect(user_path, backend)
  if user_path then
    if vim.fn.filereadable(user_path) == 1 then
      return user_path
    end
    return nil
  end

  for _, path in ipairs(candidates_for(backend)) do
    if vim.fn.filereadable(path) == 1 then
      return path
    end
  end

  return nil
end

return M
