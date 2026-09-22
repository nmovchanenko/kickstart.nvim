# Slovak reader

Read Slovak markdown in Neovim, send bits of it to Claude Code in the next tmux
pane without leaving your place in the text.

The idea is that you keep reading. Hit a word you don't know, press three keys,
and the question is already in Claude's input by the time you look right. You
never lose your cursor position and you never touch the mouse.

## What you need

- tmux, with Neovim and Claude Code side by side in the same window
- Neovim 0.11 or newer (it uses `vim.fs.relpath()`, added in 0.11)
- A markdown file. The keymaps only exist in markdown buffers.

Claude Code has to be in a pane to the **right** of Neovim, in the same window.
That's the default and you can change it, see [configuration](#configuration).

Typical layout:

```
┌────────────────────┬────────────────────┐
│                    │                    │
│  nvim lekcia.md    │  claude            │
│  (you read here)   │  (answers here)    │
│                    │                    │
└────────────────────┴────────────────────┘
```

Set it up with:

```sh
cd ~/slovak
nvim texts/lekcia.md
# then, inside tmux:
# prefix + %   to split right
# claude       in the new pane
```

## The three keymaps

All of them start with `<leader>r`, and your leader is the spacebar. So
`<leader>rw` means space, then `r`, then `w`.

| Keys | Mode | What happens |
|------|------|--------------|
| `<leader>rw` | normal | Sends the word under the cursor, presses Enter. You stay in Neovim. |
| `<leader>re` | visual | Sends the selection, presses Enter. You stay in Neovim. |
| `<leader>ra` | visual | Sends the selection and waits, cursor lands in the Claude pane so you can type a question. |

Everything arrives as one line, because Claude Code submits on Enter and a
multi-line paste would fire off half a sentence.

## Examples

These all use the same file, `texts/lekcia.md`:

```markdown
# Lekcia 1

Videl som ťažký žltý kôň.
Ľúbil som   ďalšie   veci
a bolo to naozaj pekné.

Krátky riadok.
```

### One word

Put the cursor anywhere inside `ťažký` on line 3 and press `<leader>rw`.

Claude receives:

```
SK> texts/lekcia.md:3 :: ťažký
```

Diacritics work. `ň`, `ď`, `ľ`, `ĺ`, `ŕ` and the rest all count as part of the
word, so you get `ťažký` and not `ta`.

### A passage

Put the cursor on line 3, press `V`, then `jj` to take three lines, then
`<leader>re`.

Claude receives:

```
SK> texts/lekcia.md:3-5 :: Videl som ťažký žltý kôň. Ľúbil som ďalšie veci a bolo to naozaj pekné.
```

Note what happened to the text. Three lines became one, the line break turned
into a space, and that run of spaces in `som   ďalšie   veci` collapsed to
single spaces. The line range reads `3-5`.

Character-wise (`v`) and block-wise (`Ctrl-v`) selections work too. A selection
inside a single line gives you one number instead of a range:

```
SK> texts/lekcia.md:3 :: ťažký žltý
```

### Asking your own question

Select something, press `<leader>ra`. The text arrives with a trailing `:: `
and **no** Enter, and your cursor moves to the Claude pane:

```
SK> texts/lekcia.md:7 :: Krátky riadok. :: ▮
```

Type your question on the end and press Enter yourself:

```
SK> texts/lekcia.md:7 :: Krátky riadok. :: why is this instrumental?
```

This is the one that moves your focus. The other two leave you in Neovim on
purpose, so you can fire off five words in a row and read the answers later.

## The message format

```
SK> <path>:<line> :: <text>
SK> <path>:<start>-<end> :: <text>
```

The path is relative to your project root, and the root is the nearest parent
directory containing a `CLAUDE.md`. With this tree:

```
~/slovak/
├── CLAUDE.md
└── texts/
    └── lekcia.md
```

you get `texts/lekcia.md`, no matter which directory you started Neovim from.
If there's no `CLAUDE.md` anywhere above the file, the path falls back to being
relative to Neovim's working directory.

Put a `CLAUDE.md` at the root of your reading folder. It gives Claude somewhere
to keep notes about your level and what you've already covered, and it pins down
the paths in these messages.

## Configuration

The defaults need no setup. To change them, edit the `config` call in
`lua/custom/plugins/slovak-reader.lua`:

```lua
config = function()
  require('custom.slovak_reader').setup {
    target = '{right-of}',
    prefix = '<leader>r',
    filetypes = { 'markdown' },
  }
end,
```

`target` is which pane gets the text. `{right-of}`, `{left-of}`, `{up-of}` and
`{down-of}` are worked out from Neovim's own pane, so they mean what they say
even when the Claude pane is the focused one. You can also name a pane outright,
either a tmux id like `%12` or a `session:window.pane` address like `slovak:1.1`.
A fixed id is worth it if you always work in the same layout.

`prefix` is the leading keys for all three maps. `filetypes` is where they
exist. Adding `'text'` or `'org'` is fine if you read those too.

## When nothing happens

Every failure tells you why and sends nothing. The message shows up as a
notification in Neovim.

| Message | What's wrong |
|---------|--------------|
| `Not running inside tmux ($TMUX is unset)` | Neovim isn't in tmux. Start tmux first. |
| `No pane to the right of this one` | No Claude pane there. Split your window, or set `target`. |
| `$TMUX_PANE is unset` | Neovim can't tell which pane it's in, so it can't find the neighbour. Name the pane directly with `target`. |
| `Target '...' resolves to this pane` | The target points back at Neovim. Check your `target` setting. |
| `No tmux pane matches '...'` | You named a pane that's gone. Ids change when panes close, so prefer `{right-of}` or a `session:window.pane` address. |
| `No word under the cursor` | The cursor is on blank space or punctuation. |
| `Selection is empty` | Nothing selected. |

If the keys do nothing at all and you see no notification, you're probably not
in a markdown buffer. Check with `:set filetype?`.

## Things worth knowing

Your registers are safe. The selection is read with `getregion()`, so yanking
into `"` or `0` is untouched and your last yank survives.

Visual mode ends after sending, which leaves you in normal mode where you were.

Text is sent literally, so quotes, colons, backslashes and brackets in your
Slovak text arrive exactly as written and tmux doesn't try to interpret them.

Nothing is sent when a check fails, so a misconfigured target can't start typing
into your own buffer.

## Where the code is

```
lua/custom/slovak_reader.lua          the module
lua/custom/plugins/slovak-reader.lua  tells lazy.nvim when to load it
```

It loads on the first markdown file you open and costs nothing at startup
otherwise.
