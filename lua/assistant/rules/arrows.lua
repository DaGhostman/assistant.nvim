local util = require("assistant.util")

local ARROWS = { ["<Up>"] = "k", ["<Down>"] = "j", ["<Left>"] = "h", ["<Right>"] = "l" }

--- Arrow keys, in insert mode or normal mode.
---@type assistant.Rule
return {
  name = "arrows",
  desc = "Arrow keys",
  check = function(history, opts)
    local prev = util.prev(history)
    if not prev or not ARROWS[prev.key] or prev.pum then
      return
    end
    local insert = util.is_insert(prev.mode)
    local n = util.ended_streak(history, function(ev)
      return ARROWS[ev.key] ~= nil and not ev.pum and util.is_insert(ev.mode) == insert
    end)
    if n < (opts.threshold or 2) then
      return
    end
    if insert then
      return {
        msg = ("You used the arrow keys %d times in insert mode.\n"):format(n)
          .. "→ `<Esc>`, move with a motion (`w`, `b`, `f{char}`, …), then `i`/`a` to keep typing\n"
          .. "→ `<C-o>{motion}` runs one normal-mode motion without leaving insert mode",
      }
    end
    return {
      msg = ("You used the arrow keys %d times.\n→ `%s` does the same without leaving the home row"):format(
        n,
        ARROWS[prev.key]
      ),
    }
  end,
}
