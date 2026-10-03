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
- espeak-ng, but only for the IPA keymap. Everything else works without it.

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

## The keymaps

All of them start with `<leader>r`, and your leader is the spacebar. So
`<leader>rw` means space, then `r`, then `w`.

| Keys | Mode | What happens |
|------|------|--------------|
| `<leader>rw` | normal | Sends the word under the cursor, presses Enter. You stay in Neovim. |
| `<leader>re` | visual | Sends the selection, presses Enter. You stay in Neovim. |
| `<leader>rs` | normal | Sends the word under the cursor as `SKV>`, presses Enter. Claude explains it in Slovak. You stay in Neovim. |
| `<leader>rs` | visual | Sends the selection as `SKV>`, presses Enter. Claude explains it in Slovak. You stay in Neovim. |
| `<leader>ra` | visual | Sends the selection and waits, cursor lands in the Claude pane so you can type a question. |
| `<leader>ri` | normal | Shows the IPA transcription of the word under the cursor. Stays in Neovim, sends nothing to Claude. |
| `<leader>rd` | normal | Marks the text as done, at the cursor line. Sends nothing to Claude. |
| `<leader>rx` | normal | Marks the text as dropped, at the cursor line. Sends nothing to Claude. |
| `<leader>rt` | normal | Opens a picker of all your texts, newest first. |
| `<leader>rl` | normal | Opens the most recently modified text straight away. |

Everything arrives as one line, because Claude Code submits on Enter and a
multi-line paste would fire off half a sentence.

The first eight only exist in markdown buffers, since they act on the text you're
reading. `<leader>rt` and `<leader>rl` are global, because you use them to open a
text in the first place, usually from an empty Neovim.

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

### Explained in Slovak

Put the cursor inside `ťažký` on line 3 and press `<leader>rs`.

Claude receives:

```
SKV> texts/lekcia.md:3 :: ťažký
```

It works exactly like `<leader>rw`, and in visual mode like `<leader>re`. Only
the prefix differs, see [the message format](#the-message-format).

### How is it pronounced

Put the cursor on `ťažký` and press `<leader>ri`. A notification appears in
Neovim:

```
ťažký  [tʲˈaʃkiː]
```

This one never touches the Claude pane. It shells out to `espeak-ng` and shows
the answer locally, so it costs you nothing and works with no Claude session
running. A few more:

```
kôň     [kˈuoɲ]
žlti    [ʒˈl̩tiː]
Ľúbil   [ʎˈuːbil]
pekné   [pˈekneː]
```

You need espeak-ng for this one key. The others work without it.

```sh
brew install espeak-ng          # macOS
sudo apt install espeak-ng      # Debian, Ubuntu
```

If it isn't installed you get one warning the first time you press the key, and
nothing after that.

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

This is the one that moves your focus. The others leave you in Neovim on
purpose, so you can fire off five words in a row and read the answers later.

## Opening a text

`<leader>rt` lists every markdown file in your texts folder, newest first, with
a preview:

```
╭──────────────────────── Results ─────────────────────────╮╭──── File Preview ────╮
│  1d   A2  dialóg   Ranná návšteva            191  done    ││---                   │
│  22h  B1  list     Vážení rodičia            170          ││saved: 2026-09-24     │
│  17h  B2  próza    Malý princ                12k  dropped ││source: clipboard     │
│  3h                Dnes ráno som prišiel ...              ││title: Rodinný dom... │
│> 2h   B1  inzerát  Rodinný dom v Kalinkove   380          ││type: inzerát         │
╰──────────────────────────────────────────────────────────╯╰──────────────────────╯
╭─────────────────────────── Slovak texts ─────────────────────────────────────────╮
│>                                                                        17 / 17  │
╰──────────────────────────────────────────────────────────────────────────────────╯
```

The columns are how long ago the text was saved, the level, the genre, the
title, the length in words and whether you finished it: `done` or `dropped`,
as marked with `<leader>rd` and `<leader>rx`. An unmarked text leaves that
column blank. The age comes from the `saved` field, and the
list is sorted by it too. The file's own dates are no use here: the scripts in
the texts repository rewrite the file on every mark and annotation, which
resets both its modification and creation time. A text without `saved` falls
back to the file's creation time. Long counts are shortened: `180`, `1.2k`, `12k`.

The newest text sits at the bottom, next to the prompt, already selected. That's
Telescope's normal bottom-up ordering, so the freshest thing is nearest your
fingers. Enter opens it in the current window.

Level, genre, title and length come from the [front matter](#front-matter). A
text that hasn't been annotated yet, like the `3h` one above, just has empty
columns. Each column is as wide as its longest value, so while nothing has a
level yet the column takes no room at all.

The title is the `title` field. Without it, it's the first markdown heading, or
the first line of the body if there's no heading. Front matter is never taken
for a title, so `saved:` and `source:` don't show up there. Only the first 20
lines of each file are read, once, so the list opens instantly whether you have
17 texts or 700.

Typing filters on the title, the file name, the genre, the level and the
status together.

A word that is exactly a status, a level or a genre some text has is taken
literally and matched against that column alone. Anything else is fuzzy, as
usual in Telescope, and matched across the whole line:

```
done        only texts marked done, nothing else
dropped b1  texts you gave up on, at B1
inzerát     only ads
inzerat     the same, diacritics or not
dialog done finished dialogues
princ       fuzzy: the title "Malý princ", the file name, and anything
            else with p, r, i, n, c in that order
```

The exact words are needed because fuzzy matching is loose. Fuzzy, `done` also
finds "Vychádzka **do** kniž**n**ic**e**", since those letters show up in that
order. As an exact word it only matches the status column.

Since the date is in the file name, typing `09-23` narrows to one day.

`<leader>rl` skips the picker and opens the newest text directly. It's the one
you want when you're picking up where you left off.

Both of them put you back where you stopped. If you marked the text with
`<leader>rd` or `<leader>rx`, the cursor lands on that line, centred on screen.
A text you never marked opens at the top.

## Marking where you stopped

`<leader>rd` says you finished the text, `<leader>rx` says you gave up on it.
Either way, the cursor line is where you stopped. Press it on the last line you
actually read.

```
done · line 210
```

That's all you see. Behind it, `bin/sk-status` in your texts repository writes
`status` and `read_to` into the front matter and works out how hard the text
turned out to be from the questions you asked about it. It runs in the
background, so you can keep scrolling while it does.

The file changes on disk under your open buffer, and the buffer is reloaded for
you, quietly. The front matter may have grown by a couple of lines, so the text
moves down, and the cursor moves down with it. You stay on the same sentence.

The script is found next to your `CLAUDE.md`, as `<root>/bin/sk-status`. That's
the same root the paths in `SK>` messages use, see
[the message format](#the-message-format). There's nothing to configure.

The line that gets saved counts from the start of the body, not the file. Mark
line 30 of a file whose front matter takes four lines and you get `read_to: 26`.
That number keeps pointing at the same sentence as the front matter grows,
because Neovim adds whatever the fence height is when you open the file again.

Neovim never writes the front matter itself. The scripts in the texts repository
are the only writer, and they take a lock so the background annotator and your
marks don't overwrite each other.

## Front matter

Texts can start with a block like this:

```yaml
---
saved: 2026-09-23 20:30
source: clipboard
title: Malý princ
type: próza
level: B2
words: 12801
status: dropped
read_to: 49
---
```

This module reads `title`, `type`, `level`, `words` and `status` for the picker, and
`read_to` for where to open. It writes nothing.

The fields are defined by the texts repository, in `docs/frontmatter.md` at its
root, not here. This module only reads them. If the two disagree, the repository
is right. The same goes for `CLAUDE.md` as the path anchor: someone else's
contract, and it's described once, over there.

Any field can be missing. A text with just `saved` and `source` is normal, the
annotator hasn't reached it yet. Its columns stay empty.

## The message format

```
SK> <path>:<line> :: <text>
SK> <path>:<start>-<end> :: <text>
SKV> <path>:<line> :: <text>
SKV> <path>:<start>-<end> :: <text>
```

`SKV>` is built exactly like `SK>`: same one-line text, same path, same pane.
The difference is on Claude's side: it explains the text in Slovak and doesn't
write the question to the log.

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
    espeak = 'espeak-ng',
    texts_dir = '~/Projects/github/private/vocab/texts',
  }
end,
```

`target` is which pane gets the text. `{right-of}`, `{left-of}`, `{up-of}` and
`{down-of}` are worked out from Neovim's own pane, so they mean what they say
even when the Claude pane is the focused one. You can also name a pane outright,
either a tmux id like `%12` or a `session:window.pane` address like `slovak:1.1`.
A fixed id is worth it if you always work in the same layout.

`prefix` is the leading keys for all the maps. `filetypes` is where they
exist. Adding `'text'` or `'org'` is fine if you read those too.

`texts_dir` is the folder `<leader>rt` and `<leader>rl` read. `~` is expanded
for you. If you change `prefix`, update the `keys` list in
`lua/custom/plugins/slovak-reader.lua` too, since lazy.nvim needs to know which
keys should load the plugin.

`espeak` is the binary used for IPA. Point it somewhere else if yours isn't on
`PATH`, for example `/opt/homebrew/bin/espeak-ng`. It has to take espeak-ng's
options, so plain `espeak` may or may not work depending on your version.

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
| `'espeak-ng' not found` | espeak-ng isn't installed or isn't on `PATH`. Install it, or set `espeak`. Shown once per session. |
| `... could not transcribe '...'` | espeak-ng ran but failed, usually a missing Slovak voice data file. Check with `espeak-ng -v sk --ipa -q test`. |
| `No texts folder at ...` | `texts_dir` points somewhere that isn't a directory. |
| `No markdown texts in ...` | The folder is there but holds no `.md` files. |
| `.../bin/sk-status is missing or not executable` | The texts repository has no `bin/sk-status`, or it lost its `x` bit. Check with `ls -l bin/sk-status` in the repository. |
| `No CLAUDE.md above this file, so bin/sk-status cannot be found` | The text isn't inside the texts repository, so there's no root to find the script in. |
| `Cursor is inside the front matter` | `<leader>rd` and `<leader>rx` need the cursor in the text itself. |
| `Buffer has unsaved changes` | The script works on the file on disk. Save first, `:w`, then mark. |
| `sk-status: ...` | The script ran and refused. The rest of the message is its own explanation. |

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
