--- Send Slovak reading snippets from Neovim to a Claude Code tmux pane.
---
--- Messages are emitted as a single line, because Claude Code submits its input
--- on Enter and a multi-line paste would submit early:
---
---   SK> <path>:<line> :: <text>
---   SK> <path>:<start>-<end> :: <text>
---
--- See `setup()` for the available options.

local M = {}

local config = {
  -- Any tmux target-pane spec: '{right-of}', '%12', 'session:1.2', ...
  target = '{right-of}',
  prefix = '<leader>r',
  filetypes = { 'markdown' },
}

local function warn(msg)
  vim.notify(msg, vim.log.levels.WARN, { title = 'slovak-reader' })
end

local function info(msg)
  vim.notify(msg, vim.log.levels.INFO, { title = 'slovak-reader' })
end

local function tmux(args)
  return vim.system(vim.list_extend({ 'tmux' }, args), { text = true }):wait()
end

--- Directional targets, resolved from Neovim's own pane rather than by tmux.
local DIRECTIONS = { ['{right-of}'] = 'right', ['{left-of}'] = 'left', ['{up-of}'] = 'up', ['{down-of}'] = 'down' }

--- Find the neighbouring pane in `direction`, within Neovim's own window.
---
--- tmux's own '{right-of}' is resolved against the *attached client's* active
--- pane, not against us: with no client attached, or with the Claude pane
--- focused, it happily returns Neovim's own pane or a pane in another window.
--- Geometry anchored on $TMUX_PANE is deterministic instead. Panes are laid out
--- with a one-column border, so a right neighbour starts at `right + 2`.
---@return string|nil pane id, or nil when nothing borders us that way
local function neighbour(direction, self_pane)
  local res = tmux { 'list-panes', '-t', self_pane, '-F', '#{pane_id} #{pane_left} #{pane_right} #{pane_top} #{pane_bottom}' }
  if res.code ~= 0 then
    warn(('tmux list-panes failed: %s'):format(vim.trim(res.stderr or '')))
    return nil
  end

  local panes, me = {}, nil
  for line in vim.gsplit(res.stdout or '', '\n', { trimempty = true }) do
    local id, left, right, top, bottom = line:match '^(%%%d+) (%d+) (%d+) (%d+) (%d+)$'
    if id then
      local pane = { id = id, left = tonumber(left), right = tonumber(right), top = tonumber(top), bottom = tonumber(bottom) }
      panes[#panes + 1] = pane
      if id == self_pane then
        me = pane
      end
    end
  end

  if not me then
    return nil
  end

  -- Keep panes that sit beyond our edge and still overlap us on the other axis,
  -- then take the closest one, breaking ties by position along that axis.
  local horizontal = direction == 'left' or direction == 'right'
  local best
  for _, pane in ipairs(panes) do
    local beyond, overlaps
    if direction == 'right' then
      beyond, overlaps = pane.left > me.right, pane.top <= me.bottom and pane.bottom >= me.top
    elseif direction == 'left' then
      beyond, overlaps = pane.right < me.left, pane.top <= me.bottom and pane.bottom >= me.top
    elseif direction == 'down' then
      beyond, overlaps = pane.top > me.bottom, pane.left <= me.right and pane.right >= me.left
    else
      beyond, overlaps = pane.bottom < me.top, pane.left <= me.right and pane.right >= me.left
    end

    if pane.id ~= self_pane and beyond and overlaps then
      local distance = horizontal and (direction == 'right' and pane.left or -pane.right) or (direction == 'down' and pane.top or -pane.bottom)
      local tiebreak = horizontal and pane.top or pane.left
      if not best or distance < best.distance or (distance == best.distance and tiebreak < best.tiebreak) then
        best = { id = pane.id, distance = distance, tiebreak = tiebreak }
      end
    end
  end

  return best and best.id
end

--- Resolve `config.target` to a concrete pane id (e.g. '%12').
---
--- Resolving up front matters for two reasons: `send-keys` is issued twice (text,
--- then Enter) and both must land in the same pane, and tmux target specs are
--- deceptively lossy -- `display-message -t <bogus>` exits 0 with empty output,
--- and a directional target can quietly come back as Neovim's own pane.
---@return string|nil pane id, or nil after notifying why nothing can be sent
local function resolve_pane()
  if not vim.env.TMUX or vim.env.TMUX == '' then
    warn 'Not running inside tmux ($TMUX is unset) - nothing sent.'
    return nil
  end

  local self_pane = vim.env.TMUX_PANE
  local direction = DIRECTIONS[config.target]
  local pane

  if direction then
    if not self_pane or self_pane == '' then
      warn '$TMUX_PANE is unset, so the neighbouring pane cannot be found - nothing sent.'
      return nil
    end
    pane = neighbour(direction, self_pane)
    if not pane then
      warn(('No pane to the %s of this one - nothing sent.'):format(direction))
      return nil
    end
  else
    local res = tmux { 'display-message', '-p', '-t', config.target, '#{pane_id}' }
    if res.code ~= 0 then
      warn(("tmux cannot resolve target '%s' - nothing sent.\n%s"):format(config.target, vim.trim(res.stderr or '')))
      return nil
    end
    pane = vim.trim(res.stdout or '')
    if pane == '' then
      warn(("No tmux pane matches '%s' - nothing sent."):format(config.target))
      return nil
    end
  end

  if pane == self_pane then
    warn(("Target '%s' resolves to this pane (%s) - nothing sent."):format(config.target, pane))
    return nil
  end

  return pane
end

--- Send `text` literally, so quotes, colons and backslashes reach Claude Code
--- untouched. Enter goes in a separate call as a key name rather than a literal.
local function send(pane, text, opts)
  local res = tmux { 'send-keys', '-t', pane, '-l', text }
  if res.code ~= 0 then
    warn(('tmux send-keys failed: %s'):format(vim.trim(res.stderr or '')))
    return false
  end

  if opts.enter then
    res = tmux { 'send-keys', '-t', pane, 'Enter' }
    if res.code ~= 0 then
      warn(('tmux could not send Enter: %s'):format(vim.trim(res.stderr or '')))
      return false
    end
  end

  if opts.focus then
    -- The pane may live in another window, so raise the window as well.
    tmux { 'select-window', '-t', pane }
    tmux { 'select-pane', '-t', pane }
  end

  return true
end

--- Collapse a snippet to one line: newlines become spaces, whitespace runs
--- collapse, ends are trimmed. Byte-wise `%s` is UTF-8 safe here, since
--- continuation bytes are >= 0x80 and never match.
local function one_line(text)
  -- Parenthesised: gsub() also returns a count, which must not reach vim.trim().
  return vim.trim((text:gsub('%s+', ' ')))
end

--- Path relative to the nearest ancestor holding a CLAUDE.md, else to the cwd.
local function display_path(bufnr)
  local abs = vim.api.nvim_buf_get_name(bufnr)
  if abs == '' then
    return '[No Name]'
  end

  local marker = vim.fs.find({ 'CLAUDE.md' }, { upward = true, type = 'file', limit = 1, path = vim.fs.dirname(abs) })[1]
  local root = marker and vim.fs.dirname(marker) or vim.uv.cwd()

  return vim.fs.relpath(root, abs) or abs
end

local function line_spec(first, last)
  return first == last and tostring(first) or ('%d-%d'):format(first, last)
end

--- Read the visual selection without touching any register.
--- Must run while still in visual mode, which is the case for a Lua callback
--- mapped in 'x' mode.
local function visual_selection()
  local mode = vim.fn.mode()
  local from, to = vim.fn.getpos 'v', vim.fn.getpos '.'
  -- getregion() handles charwise, linewise and blockwise alike.
  local chunks = vim.fn.getregion(from, to, { type = mode })
  local first, last = math.min(from[2], to[2]), math.max(from[2], to[2])

  return one_line(table.concat(chunks, ' ')), first, last
end

local function stop_visual()
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<Esc>', true, false, true), 'n', false)
end

--- Trim a snippet for the confirmation notice only; the sent text stays whole.
local function preview(text)
  return vim.fn.strcharlen(text) > 40 and (vim.fn.strcharpart(text, 0, 40) .. '…') or text
end

local function send_visual(opts)
  local text, first, last = visual_selection()
  stop_visual()

  if text == '' then
    warn 'Selection is empty - nothing sent.'
    return
  end

  local pane = resolve_pane()
  if not pane then
    return
  end

  local message = ('SK> %s:%s :: %s'):format(display_path(0), line_spec(first, last), text)
  -- The "ask" variant leaves a trailing ' :: ' and no Enter, so a question can
  -- be typed straight onto the line.
  if opts.ask then
    message = message .. ' :: '
  end

  if send(pane, message, { enter = not opts.ask, focus = opts.ask }) then
    info('→ Claude: ' .. preview(text))
  end
end

local function send_word()
  -- <cword> already treats Slovak letters as word characters: Neovim classifies
  -- multibyte chars via utf_class(), so Latin Extended-A (č ď ĺ ľ ň ŕ š ť ž)
  -- counts regardless of 'iskeyword' only spelling out 192-255 (á ä é í ó ô ú ý).
  local word = one_line(vim.fn.expand '<cword>')
  if word == '' or word:match '^%p+$' then
    warn 'No word under the cursor - nothing sent.'
    return
  end

  local pane = resolve_pane()
  if not pane then
    return
  end

  local line = vim.api.nvim_win_get_cursor(0)[1]
  local message = ('SK> %s:%d :: %s'):format(display_path(0), line, word)

  if send(pane, message, { enter = true }) then
    info('→ Claude: ' .. word)
  end
end

---@param opts? { target?: string, prefix?: string, filetypes?: string[] }
function M.setup(opts)
  config = vim.tbl_extend('force', config, opts or {})

  local ok, wk = pcall(require, 'which-key')
  if ok then
    wk.add { { config.prefix, group = '[R]eader → Claude', mode = { 'n', 'x' } } }
  end

  local function attach(bufnr)
    local function map(mode, suffix, fn, desc)
      vim.keymap.set(mode, config.prefix .. suffix, fn, { buffer = bufnr, desc = desc })
    end

    map('x', 'e', function()
      send_visual { ask = false }
    end, '[E]xplain selection (stay in Neovim)')

    map('x', 'a', function()
      send_visual { ask = true }
    end, '[A]sk about selection (focus Claude)')

    map('n', 'w', send_word, '[W]ord under cursor')
  end

  vim.api.nvim_create_autocmd('FileType', {
    group = vim.api.nvim_create_augroup('slovak-reader', { clear = true }),
    pattern = config.filetypes,
    desc = 'Slovak reader keymaps → Claude Code tmux pane',
    callback = function(args)
      attach(args.buf)
    end,
  })

  -- lazy.nvim re-fires FileType after an `ft`-gated load, so the buffer that
  -- triggered it is already covered. This keeps setup() correct anyway when it
  -- runs with buffers open -- re-sourcing the config, or a different load trigger.
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.tbl_contains(config.filetypes, vim.bo[bufnr].filetype) then
      attach(bufnr)
    end
  end
end

return M
