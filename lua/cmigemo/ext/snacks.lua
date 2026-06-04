local M = {}

--- Setup cmigemo.snacks integration (called during snacks config).
function M.setup()
  -- Nothing to initialize; cmigemo.setup() is handled by cmigemo.nvim itself
end

--- Custom grep finder that transforms search input via cmigemo before passing to rg.
--- Designed as a drop-in replacement for snacks.picker.source.grep.grep().
---@param opts snacks.picker.grep.Config
---@param ctx snacks.picker.finder.ctx
function M.grep(opts, ctx)
  local search = ctx.filter.search
  if not search or search == "" then
    return require("snacks.picker.source.grep").grep(opts, ctx)
  end

  local cmigemo = require("cmigemo")
  local pattern = cmigemo.query(search, { rxop = "pcre" })

  if pattern then
    -- Replace the filter search with the migemo-expanded regex
    local orig_search = ctx.filter.search
    ctx.filter.search = pattern
    local result = require("snacks.picker.source.grep").grep(opts, ctx)
    -- Restore original search to avoid side effects on display
    ctx.filter.search = orig_search
    return result
  end

  -- Fallback to default grep if cmigemo returns nil
  return require("snacks.picker.source.grep").grep(opts, ctx)
end

return M
