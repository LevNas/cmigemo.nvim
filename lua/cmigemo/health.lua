local M = {}

function M.check()
  vim.health.start("cmigemo.nvim")

  -- 1. Check binary
  local cmigemo = require("cmigemo")
  local cmd = "cmigemo"
  if vim.fn.executable(cmd) == 1 then
    local handle = io.popen(cmd .. " --version 2>&1")
    local version = handle and handle:read("*l") or "unknown"
    if handle then
      handle:close()
    end
    vim.health.ok("cmigemo binary found: " .. cmd .. " (" .. (version or "unknown") .. ")")
  else
    vim.health.error("cmigemo binary not found", {
      "Install cmigemo: sudo apt install cmigemo (Debian/Ubuntu)",
      "Or: brew install cmigemo (macOS)",
    })
    return
  end

  -- 2. Check dictionary
  local dict = require("cmigemo.dict")
  local dict_path = dict.detect()
  if dict_path then
    vim.health.ok("Dictionary found: " .. dict_path)
  else
    vim.health.error("Dictionary not found", {
      "Ensure cmigemo dictionary is installed",
      "Or specify dict_path in setup()",
    })
    return
  end

  -- 3. Check process startup
  if not cmigemo.is_available() then
    vim.health.error("cmigemo is not available")
    return
  end

  -- 4. Query test
  local result = cmigemo.query("test")
  if result and result ~= "" then
    vim.health.ok("Query test passed: \"test\" -> " .. result)
  else
    vim.health.warn("Query test failed: no result for \"test\"")
  end

  -- Clean up test process
  cmigemo.stop()
end

return M
