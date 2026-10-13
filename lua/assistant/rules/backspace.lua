local util = require("assistant.util")

--- Long runs of backspace in insert mode.
---@type assistant.Rule
return {
  name = "backspace",
  desc = "Long backspace runs instead of <C-w>",
  check = function(history, opts)
    local prev = util.prev(history)
    if not prev or (prev.key ~= "<BS>" and prev.key ~= "<C-H>") then
      return
    end
    local n = util.ended_streak(history, function(ev)
      return (ev.key == "<BS>" or ev.key == "<C-H>") and util.is_insert(ev.mode)
    end)
    if n < (opts.threshold or 6) then
      return
    end
    return {
      msg = ("You pressed `<BS>` %d times.\n"):format(n)
        .. "→ `<C-w>` deletes the word before the cursor\n"
        .. "→ `<C-u>` deletes everything typed on the line so far",
    }
  end,
}
