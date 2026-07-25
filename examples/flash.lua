-- Example: flash.nvim integration with cmigemo.nvim
-- Add this to your lazy.nvim plugin specs.
--
-- Keymaps follow flash.nvim's suggested defaults (s / S / r / R / <c-s>),
-- with the migemo-enhanced functions in place of their flash counterparts.
-- The opts also trim flash's per-keystroke costs (full-viewport backdrop
-- repaint, multi-window scanning): the migemo integration re-matches the
-- visible text on every keystroke, so these defaults keep it responsive
-- on slow terminals (e.g. WSL). Remove them if you prefer flash's stock
-- behavior.
return {
  "folke/flash.nvim",
  dependencies = { "LevNas/cmigemo.nvim", "atusy/budoux.lua" },
  ---@type Flash.Config
  opts = {
    search = { multi_window = false },
    highlight = { backdrop = false },
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
      "s",
      function()
        local ok, ext = pcall(require, "cmigemo.ext.flash")
        if ok then
          ext.jump()
        else
          require("flash").jump()
        end
      end,
      mode = { "n", "x", "o" },
      desc = "Flash: Migemo Jump",
    },
    -- Treesitter node selection (no query input)
    { "S", function() require("flash").treesitter() end,
      mode = { "n", "x", "o" }, desc = "Flash: Treesitter Jump" },
    -- Remote migemo operation: e.g. `yr` + romaji + label + `iw` yanks a
    -- distant word, then the cursor returns to where it was
    {
      "r",
      function()
        local ok, ext = pcall(require, "cmigemo.ext.flash")
        if ok then
          ext.remote()
        else
          require("flash").remote()
        end
      end,
      mode = "o",
      desc = "Flash: Migemo Remote",
    },
    -- Migemo treesitter search: romaji query + label selects the syntax
    -- node covering the match (matches via the migemo layer)
    {
      "R",
      function()
        local ok, ext = pcall(require, "cmigemo.ext.flash")
        if ok then
          ext.treesitter_search()
        else
          require("flash").treesitter_search()
        end
      end,
      mode = { "o", "x" },
      desc = "Flash: Migemo Treesitter Search",
    },
    -- Toggle flash labels inside a regular / search
    { "<c-s>", function() require("flash").toggle() end,
      mode = "c", desc = "Flash: Toggle Flash Search" },
    -- Bunsetsu (phrase) jump using BudouX segmenter
    {
      "gb",
      function()
        local ok, ext = pcall(require, "cmigemo.ext.flash")
        if ok then
          ext.bunsetsu()
        end
      end,
      mode = { "n", "x", "o" },
      desc = "Flash: Bunsetsu Jump (BudouX)",
    },
  },
}
