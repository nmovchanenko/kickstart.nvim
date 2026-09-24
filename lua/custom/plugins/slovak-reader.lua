-- Sends Slovak reading snippets to the Claude Code tmux pane, and opens the
-- reading texts themselves.
-- Implementation lives in `lua/custom/slovak_reader.lua`; this spec only tells
-- lazy.nvim when to load it. `dir` points at the config itself because the code
-- is local rather than a fetched repository.
return {
  'slovak-reader',
  dir = vim.fn.stdpath 'config',
  name = 'slovak-reader',
  -- The reading keymaps are markdown-only, so opening a markdown file is one
  -- trigger. The two text-opening keymaps are global and have to work from a
  -- blank Neovim, so they load it too. Keep these in step with `prefix` if you
  -- change it.
  ft = { 'markdown' },
  keys = {
    { '<leader>rt', desc = 'Slovak texts (newest first)' },
    { '<leader>rl', desc = 'Slovak latest text' },
  },
  config = function()
    require('custom.slovak_reader').setup()
  end,
}
