local M = {}

---@type string[]
local DICT_CANDIDATES = {
  "/usr/share/cmigemo/utf-8/migemo-dict", -- Debian/Ubuntu
  "/usr/share/migemo/utf-8/migemo-dict", -- Arch/Manjaro
  "/opt/homebrew/share/migemo/utf-8/migemo-dict", -- macOS (Apple Silicon)
  "/usr/local/share/migemo/utf-8/migemo-dict", -- macOS (Intel) / manual
}

--- Detect the cmigemo dictionary path.
--- Checks user-provided path first, then known platform-specific locations.
---@param user_path? string  User-specified dictionary path
---@return string|nil  Dictionary path if found, nil otherwise
function M.detect(user_path)
  if user_path then
    if vim.fn.filereadable(user_path) == 1 then
      return user_path
    end
    return nil
  end

  for _, path in ipairs(DICT_CANDIDATES) do
    if vim.fn.filereadable(path) == 1 then
      return path
    end
  end

  return nil
end

return M
