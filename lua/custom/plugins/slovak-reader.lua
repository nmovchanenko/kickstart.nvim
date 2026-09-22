-- Sends Slovak reading snippets to the Claude Code tmux pane.
-- Implementation lives in `lua/custom/slovak_reader.lua`; this spec only tells
-- lazy.nvim when to load it. `dir` points at the config itself because the code
-- is local rather than a fetched repository.
return {
  'slovak-reader',
  dir = vim.fn.stdpath 'config',
  name = 'slovak-reader',
  ft = { 'markdown' },
  config = function()
    require('custom.slovak_reader').setup()
  end,
}
