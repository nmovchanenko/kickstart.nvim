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
  -- Binary used for IPA transcription; must accept espeak-ng's option syntax.
  espeak = 'espeak-ng',
  -- Folder of reading texts, one markdown file per text.
  texts_dir = '~/Projects/github/private/vocab/texts',
}

local function warn(msg)
  vim.notify(msg, vim.log.levels.WARN, { title = 'slovak-reader' })
end

local function info(msg)
  vim.notify(msg, vim.log.levels.INFO, { title = 'slovak-reader' })
end

--- Warn at most once per `kind` per session, so a missing binary or a broken
--- voice does not pop a notification on every keypress.
local warned = {}
local function warn_once(kind, msg)
  if not warned[kind] then
    warned[kind] = true
    warn(msg)
  end
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

--- The word under the cursor, or nil after warning why there isn't one.
---
--- <cword> already treats Slovak letters as word characters: Neovim classifies
--- multibyte chars via utf_class(), so Latin Extended-A (č ď ĺ ľ ň ŕ š ť ž)
--- counts regardless of 'iskeyword' only spelling out 192-255 (á ä é í ó ô ú ý).
local function cursor_word()
  local word = one_line(vim.fn.expand '<cword>')
  if word == '' or word:match '^%p+$' then
    warn 'No word under the cursor - nothing sent.'
    return nil
  end
  return word
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
  local word = cursor_word()
  if not word then
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

--- Show the IPA transcription of the word under the cursor.
---
--- Runs espeak-ng asynchronously, so a slow start never blocks scrolling.
local function show_ipa()
  local word = cursor_word()
  if not word then
    return
  end

  -- '--' keeps a word that starts with '-' from being read as an option;
  -- espeak-ng would otherwise print "invalid option" and still exit 0.
  local cmd = { config.espeak, '-v', 'sk', '--ipa', '-q', '--', word }

  local spawned = pcall(vim.system, cmd, { text = true }, function(res)
    -- on_exit runs in a fast event context, where vim.fn and the UI are off
    -- limits, so every notification goes through vim.schedule.
    vim.schedule(function()
      local ipa = vim.trim(res.stdout or '')
      if res.code ~= 0 or ipa == '' then
        warn_once(
          'ipa-failed',
          ("%s could not transcribe '%s': %s"):format(config.espeak, word, vim.trim(res.stderr or '') ~= '' and vim.trim(res.stderr) or ('exit ' .. res.code))
        )
        return
      end
      info(('%s  [%s]'):format(word, ipa))
    end)
  end)

  -- vim.system throws ENOENT rather than calling back when the binary is absent.
  if not spawned then
    warn_once('ipa-missing', ("'%s' not found - install espeak-ng for IPA."):format(config.espeak))
  end
end

--- "3m ago", "2h ago", "5d ago". Coarse on purpose: the picker only needs
--- enough to tell today's text from last week's.
local function relative_time(stamp)
  local seconds = os.time() - stamp
  if seconds < 60 then
    return 'just now'
  end
  for _, unit in ipairs { { 60, 'm', 60 }, { 3600, 'h', 24 }, { 86400, 'd', 7 }, { 604800, 'w', math.huge } } do
    local size, suffix, limit = unit[1], unit[2], unit[3]
    local count = math.floor(seconds / size)
    if count < limit then
      return count .. suffix .. ' ago'
    end
  end
  return 'long ago'
end

--- Cut to `limit` characters, counting characters rather than bytes so a
--- Slovak word never gets sliced through the middle of its UTF-8 encoding.
local function truncate(text, limit)
  if vim.fn.strcharlen(text) <= limit then
    return text
  end
  return vim.fn.strcharpart(text, 0, limit - 1) .. '…'
end

--- A readable title for one text file.
---
--- Prefers the first markdown heading, else the first non-empty body line.
--- Only the first 20 lines are read, so a folder of novels still opens fast.
--- Front matter is detected by the '---' fence alone: these files carry lines
--- like "povedal: ..." in the prose, which a looser "looks like YAML" test
--- would happily eat.
---@return string|nil title, or nil when the file is empty or unreadable
local function text_title(path)
  local ok, lines = pcall(vim.fn.readfile, path, '', 20)
  if not ok or type(lines) ~= 'table' or #lines == 0 then
    return nil
  end

  local start = 1
  if vim.trim(lines[1]) == '---' then
    local close = nil
    for i = 2, #lines do
      if vim.trim(lines[i]) == '---' then
        close = i
        break
      end
    end
    -- An unterminated fence within the first 20 lines means the body is still
    -- further down, so there is nothing to title with here.
    if not close then
      return nil
    end
    start = close + 1
  end

  local first_line
  for i = start, #lines do
    local line = vim.trim(lines[i])
    if line ~= '' then
      local heading = line:match '^#+%s+(.+)$'
      if heading then
        return truncate(vim.trim(heading), 60)
      end
      first_line = first_line or line
    end
  end

  return first_line and truncate(first_line, 60) or nil
end

--- Every markdown file in the texts folder, newest first.
---@return table[]|nil entries, or nil after notifying why there are none
local function collect_texts()
  local dir = vim.fn.expand(config.texts_dir)
  local stat = vim.uv.fs_stat(dir)
  if not stat or stat.type ~= 'directory' then
    warn(('No texts folder at %s.'):format(dir))
    return nil
  end

  local entries = {}
  for name in vim.fs.dir(dir) do
    if name:match '%.md$' then
      local path = dir .. '/' .. name
      -- fs_stat follows symlinks, so linked texts count as files.
      local info = vim.uv.fs_stat(path)
      if info and info.type == 'file' then
        entries[#entries + 1] = { path = path, name = name, mtime = info.mtime.sec }
      end
    end
  end

  if #entries == 0 then
    warn(('No markdown texts in %s.'):format(dir))
    return nil
  end

  table.sort(entries, function(a, b)
    return a.mtime > b.mtime
  end)

  return entries
end

--- Pick a text, newest first, with a preview.
local function pick_text()
  local entries = collect_texts()
  if not entries then
    return
  end

  local pickers = require 'telescope.pickers'
  local finders = require 'telescope.finders'
  local actions = require 'telescope.actions'
  local action_state = require 'telescope.actions.state'
  local entry_display = require 'telescope.pickers.entry_display'
  local conf = require('telescope.config').values

  local stamp_width = 0
  for _, entry in ipairs(entries) do
    entry.title = text_title(entry.path) or entry.name
    entry.when = relative_time(entry.mtime)
    stamp_width = math.max(stamp_width, vim.fn.strdisplaywidth(entry.when))
  end

  local displayer = entry_display.create {
    separator = '  ',
    items = { { width = stamp_width }, { remaining = true } },
  }

  pickers
    .new({}, {
      prompt_title = 'Slovak texts',
      finder = finders.new_table {
        results = entries,
        entry_maker = function(entry)
          return {
            value = entry.path,
            path = entry.path,
            -- Both the title and the file name are searchable; the date lives
            -- in the file name, so "09-23" narrows by day.
            ordinal = entry.title .. ' ' .. entry.name,
            display = function()
              return displayer { { entry.when, 'TelescopeResultsComment' }, entry.title }
            end,
          }
        end,
      },
      sorter = conf.generic_sorter {},
      previewer = conf.file_previewer {},
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local selected = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if selected then
            vim.cmd.edit(vim.fn.fnameescape(selected.value))
          end
        end)
        return true
      end,
    })
    :find()
end

--- Open the most recently modified text, no picker.
local function open_latest_text()
  local entries = collect_texts()
  if not entries then
    return
  end
  vim.cmd.edit(vim.fn.fnameescape(entries[1].path))
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
    map('n', 'i', show_ipa, '[I]PA of word under cursor')
  end

  -- Global, unlike the four above: you open a text from wherever you are, not
  -- only from inside another markdown buffer.
  vim.keymap.set('n', config.prefix .. 't', pick_text, { desc = 'Slovak [T]exts (newest first)' })
  vim.keymap.set('n', config.prefix .. 'l', open_latest_text, { desc = 'Slovak [L]atest text' })

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
