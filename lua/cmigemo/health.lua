local M = {}

function M.check()
  vim.health.start("cmigemo.nvim")

  -- 1. Check backend binary (cmigemo or rustmigemo)
  local cmigemo = require("cmigemo")
  local cmd = cmigemo.resolved_cmd()
  if not cmd then
    vim.health.error("No migemo backend found (looked for: cmigemo, rustmigemo)", {
      "Install cmigemo: sudo apt install cmigemo (Debian/Ubuntu)",
      "Or: brew install cmigemo (macOS)",
      "Or install rustmigemo and set cmigemo_cmd, e.g. mise/cargo install rustmigemo",
    })
    return
  end

  local backend = cmigemo.backend()
  if vim.fn.executable(cmd) == 1 then
    -- rustmigemo has no --version flag; only probe the cmigemo C backend.
    local version
    if backend == "cmigemo" then
      local handle = io.popen(cmd .. " --version 2>&1")
      version = handle and handle:read("*l") or nil
      if handle then
        handle:close()
      end
    end
    vim.health.ok(
      ("%s backend found: %s%s"):format(backend, cmd, version and version ~= "" and (" (" .. version .. ")") or "")
    )
  else
    vim.health.error("backend binary not found: " .. cmd)
    return
  end

  -- 2. Check dictionary
  local dict_path = cmigemo.dict_path()
  if dict_path then
    vim.health.ok("Dictionary found: " .. dict_path)
  else
    vim.health.error("Dictionary not found", {
      "Ensure a migemo dictionary is installed",
      "rustmigemo: place migemo-compact-dict at ~/.local/share/migemo/",
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

  -- 5. Check budoux.lua (optional)
  local budoux_ok, bunsetsu = pcall(require, "cmigemo.ext.bunsetsu")
  if budoux_ok and bunsetsu.is_available() then
    vim.health.ok("budoux.lua is available (bunsetsu jump enabled)")
  else
    vim.health.info("budoux.lua is not installed (bunsetsu jump disabled, optional)")
  end
end

return M
