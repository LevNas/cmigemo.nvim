-- Example: snacks.nvim picker integration with cmigemo.nvim
-- Add this to your lazy.nvim plugin specs.
return {
  "folke/snacks.nvim",
  dependencies = { "LevNas/cmigemo.nvim" },
  ---@class snacks.Config
  opts = {
    picker = {
      enabled = true,
      sources = {
        grep = {
          -- Replace the default grep finder with cmigemo-enhanced version.
          -- Romaji input (e.g. "nihongo") is expanded to a migemo regex
          -- that matches Japanese text before being passed to ripgrep.
          finder = function(opts, ctx)
            local ok, cmigemo_snacks = pcall(require, "cmigemo.ext.snacks")
            if ok then
              return cmigemo_snacks.grep(opts, ctx)
            end
            return require("snacks.picker.source.grep").grep(opts, ctx)
          end,
        },
      },
    },
  },
  config = function(_, opts)
    require("snacks").setup(opts)
    local ok, cmigemo_snacks = pcall(require, "cmigemo.ext.snacks")
    if ok then
      cmigemo_snacks.setup()
    end
  end,
  keys = {
    { "<leader>fg", function() Snacks.picker.grep() end, desc = "Grep (with Migemo)" },
  },
}
