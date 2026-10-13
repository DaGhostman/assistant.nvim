# assistant.nvim

A Vim motion coach for Neovim. It watches how you actually edit and, when you pause,
suggests the motion or command that would have gotten you there faster. It doesn't block
keys and doesn't play games: you get a short hint at a natural moment, with cooldowns so
it never nags.

```
You pressed `l` 11 times.
→ `f(` would land on the same spot (2 keys instead of 11)
```

```
You yanked `config` again because it got overwritten.
→ `P` in visual mode replaces the selection without overwriting the register, so you can paste it again and again
→ `"0p` always pastes your last yank, even after deletes
```

Requires Neovim 0.10+.

## Install

[lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "DaGhostman/assistant.nvim",
  event = "VeryLazy",
  opts = {},
}
```

Or call `require("assistant").setup()` yourself.

## Ghost text

While you're repeating `h`/`j`/`k`/`l`, the targets you could have jumped to appear
right away, before any hint fires:

```
local x = foo(bar) + baz     ← pressing `ll` from the start of the line …
      w 2w   4w        $     ← … shows where w, 2w, … and $ land
```

Labels that would overlap are skipped.

For `j`/`k`, the lines below/above get `5j`, `}` (next blank line) and `<C-d>` labels at
the end (counts are skipped when `relativenumber` is on, since the number column already
shows them). They disappear on the next different key.

Hints themselves can also be shown as virtual text at the end of the cursor line
instead of, or as well as, a notification: `display = "ghost"` or `"both"`.

Highlight groups: `AssistantGhost` (j/k labels), `AssistantGhostTarget` (h/l markers),
`AssistantGhostHint` (hints).

## Report

`:Assistant report [days]` opens a summary that compares the last 7 days (or `days`)
with the 7 before:

- your share of plain `h`/`j`/`k`/`l` presses
- each habit the rules noticed, with a trend (▼ is good)
- the skills you actually use (counts, word motions, `f`/`t`, text objects, `.`, `*`,
  `cgn`, registers, `gc`, macros, …), with a trend (▲ is good)
- skills you haven't tried yet
- a per-day sparkline of habits noticed

Only counts are stored (no text, file names or keys typed in insert mode), per day, in
`stdpath("data")/assistant/stats.json`. Several Neovim instances can share the file:
each one merges its counts in on save.

## What it notices

### Moving around

| Rule         | You did                                         | It suggests                                                  |
| ------------ | ----------------------------------------------- | ------------------------------------------------------------ |
| `vertical`   | `jjjjj` / `kkkkk`                               | `5j`, `}` / `{` when you stopped on a blank line, `<C-d>` / `<C-u>` |
| `horizontal` | `llllll` / `hhhhh`                              | the motion that lands on the same spot: `f(`, `t,`, `3w`, `e`, `b`, `$`, `0`, `^` |
| `jumps`      | `G` / `/` / `n` / `%`, then `kkkk` back         | `<C-o>`, ``` `` ```                                          |
|              | `gg` + `jjjj` to reach a line                   | `{N}G`, `:{N}`                                               |
| `search`     | `/word` for the word under the cursor           | `*` / `#`                                                    |
|              | `/x` for a character on the same line           | `fx`, `;`, `,`                                               |

### Editing

| Rule          | You did                                          | It suggests                                              |
| ------------- | ------------------------------------------------ | -------------------------------------------------------- |
| `shortcuts`   | `$a`, `^i`, `d$`, `c$`, `xi`, `dwi`, `bcw`, `bdw`, `<Esc>pa` | `A`, `I`, `D`, `C`, `s`, `cw`, `ciw`, `daw`, `<C-r>"`    |
| `registers`   | yank → delete → `p` pastes the wrong thing → `u` | `"0p`, `"_d` / `"_c` / `"_x`                             |
|               | yanking the same text again after it got overwritten | `"_d…` (delete without touching the register), `"0p`  |
|               | pasting over a selection with `p`, twice         | `P` in visual mode (keeps the register)                  |
| `textobjects` | `dt"` / `ct)` / `v…d` over exactly the inside of quotes or brackets | `di"`, `ci(`, `da(`                   |
|               | `V…d` over exactly one paragraph                 | `dip`, `dap`                                             |
| `surround`    | adding, deleting or replacing a pair of quotes/brackets one char at a time | `ysiw"`, `ds"`, `cs"'` (nvim-surround), `saiw"`, `sd"`, `sr"'` (mini.surround), or the built-in `ciw"<C-r>""` |
| `comments`    | typing or deleting `// ` / `-- ` / `# ` by hand  | `gcc`, `gc{motion}`, `gcip`                              |
| `selections`  | `viwy`, `vey`, `Vjd`                             | `yiw`, `ye`, `dj`                                        |
|               | the same insert on several lines, one by one     | `<C-v>` block insert / append, `:norm I…`                |
| `substitute`  | the same `:s/a/b/` line after line               | `:%s/a/b/g`, `:'<,'>s`, `g&`                             |
|               | `:%s/word/…` with the cursor on `word`           | `<C-r><C-w>`                                             |
|               | `*` then `:%s/word/…`                            | `:%s//…/g` (empty pattern reuses the last search)        |

### Repetition

| Rule      | You did                                              | It suggests                                  |
| --------- | ---------------------------------------------------- | -------------------------------------------- |
| `repeat`  | the same change typed twice                          | `.`                                          |
|           | search, change, `n`, the same change again           | `cgn` + `.`, `:%s//new/g`                    |
| `macro`   | the same key sequence 3+ times in a row (`0f,xj`…)   | `qq…q` + `@q`, `:norm …`                     |
|           | `n dd n dd n dd`                                     | `:g/pattern/d`                               |
|           | `j. j. j.`                                           | `V…` + `:norm .`                             |
| `repeats` | `xxxx`, `dd dd dd`                                   | `4x`, `dw`, `D`, `3dd`, `dap`                |

### Basics

| Rule        | You did                          | It suggests                              |
| ----------- | -------------------------------- | ---------------------------------------- |
| `arrows`    | arrow keys                       | `hjkl`, `<Esc>` + motion, `<C-o>{motion}` |
| `backspace` | long `<BS>` runs in insert mode  | `<C-w>`, `<C-u>`                         |
| `commands`  | `:w` then `:q`, `:e #`           | `:wq` / `:x` / `ZZ`, `<C-^>`             |

Only keys you actually type are counted. Keys produced by your mappings, macros and
other plugins are ignored, as are counts (`5j`) and command arguments (`fj`, `rj`, `"j`).
When several hints are ready at once, the rule higher in this list wins.

## Configuration

Defaults:

```lua
require("assistant").setup({
  enabled = true,
  delay = 1000, -- ms without keypresses before a hint is shown
  streak_gap = 1000, -- ms between two keys before a streak (`jjjj`) counts as over
  display_time = 5000, -- ms a hint stays visible (`timeout` for nvim-notify, snacks, noice, …)
  cooldown = {
    global = 30, -- seconds between any two hints
    rule = 180, -- seconds before the same rule may show again
  },
  excluded_filetypes = { "help", "lazy", "mason", "neo-tree", "NvimTree", "oil", "TelescopePrompt", "snacks_picker_input", "minifiles", "fzf" },
  excluded_buftypes = { "nofile", "prompt", "terminal", "quickfix" },
  display = "notify", -- "notify" | "ghost" | "both": where hints appear
  ghost = {
    live = true, -- show motion targets while you repeat h/j/k/l
    live_after = 2, -- presses before the targets appear
    max_lines = 20, -- lines labelled for j/k
  },
  stats = {
    enabled = true, -- save daily counts for :Assistant report
    path = nil, -- defaults to stdpath("data") .. "/assistant/stats.json"
    save_interval = 300, -- seconds between saves (also saved on exit)
    keep_days = 120,
    report_days = 7, -- period the report compares
  },
  notify = nil, -- fun(msg, hint): custom display, defaults to vim.notify
  debug = false, -- report errors inside rules instead of ignoring them
  rules = {
    jumps = { enabled = true, threshold = 3 },
    vertical = { enabled = true, threshold = 4 },
    horizontal = { enabled = true, threshold = 4 },
    search = { enabled = true },
    shortcuts = { enabled = true },
    registers = { enabled = true },
    textobjects = { enabled = true },
    surround = { enabled = true, provider = nil }, -- "nvim-surround" | "mini.surround" | nil (auto-detect)
    comments = { enabled = true },
    selections = { enabled = true, threshold = 3 },
    substitute = { enabled = true, threshold = 3 },
    ["repeat"] = { enabled = true },
    macro = { enabled = true, threshold = 3 },
    repeats = { enabled = true, threshold = 4 },
    arrows = { enabled = true, threshold = 2 },
    backspace = { enabled = true, threshold = 6 },
    commands = { enabled = true },
  },
})
```

Each rule also accepts its own `cooldown` (seconds).

## Commands

- `:Assistant report [days]` shows habit and skill trends over time
- `:Assistant status` shows how often each habit was noticed and hinted this session
- `:Assistant enable` / `disable` / `toggle`

## Tests

```sh
nvim --headless -u NONE -l tests/run.lua
```

## Roadmap

- Learning path: daily focus motions, "learned" tracking, and reminders when old habits come back
- Strict mode (opt-in): block a repeated `hjkl` after the threshold
