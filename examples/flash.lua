-- Example: flash.nvim integration with cmigemo.nvim
-- Add this to your lazy.nvim plugin specs.
return {
  "folke/flash.nvim",
  dependencies = { "LevNas/cmigemo.nvim", "atusy/budoux.lua" },
  event = "VeryLazy",
  ---@type Flash.Config
  opts = {
    modes = {
      char = { enabled = false },
      search = { enabled = false },
    },
  },
  config = function(_, opts)
    require("flash").setup(opts)
    local ok, cmigemo_flash = pcall(require, "cmigemo.ext.flash")
    if ok then
      cmigemo_flash.setup()
    end
  end,
  keys = {
    -- Migemo-enhanced jump: romaji input is converted to Japanese regex
    {
      "f",
      function()
        local ok, cmigemo_flash = pcall(require, "cmigemo.ext.flash")
        if ok then
          cmigemo_flash.jump()
        else
          require("flash").jump()
        end
      end,
      mode = { "n", "x", "o" },
      desc = "Flash: Migemo Jump",
    },
    -- Standard flash jump (no migemo)
    { "F", function() require("flash").jump() end,
      mode = { "n", "x", "o" }, desc = "Flash: Jump" },
    -- Bunsetsu (phrase) jump using BudouX segmenter
    {
      "gb",
      function()
        local ok, cmigemo_flash = pcall(require, "cmigemo.ext.flash")
        if ok then
          cmigemo_flash.bunsetsu()
        end
      end,
      mode = { "n", "x", "o" },
      desc = "Flash: Bunsetsu Jump (BudouX)",
    },
  },
}
