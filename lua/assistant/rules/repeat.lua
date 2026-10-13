local util = require("assistant.util")

local SEARCH_KEYS = { n = true, N = true, ["*"] = true, ["#"] = true }

--- The same change typed twice -> `.`; with a search in between -> `cgn` + `.`.
---@type assistant.Rule
return {
  name = "repeat",
  desc = "Retyping a change instead of . or cgn",
  check = function(history)
    local last = history[#history]
    if not last or last.key ~= "<Insert>" or last.is_repeat or last.multiline or last.inserted == "" then
      return
    end
    local leader = util.comment_leader(last.buf)
    if leader and vim.trim(last.inserted) == leader then
      return -- the comments rule handles these
    end
    local first, index = util.find_back(history, function(ev)
      return ev.key == "<Insert>" and not ev.is_repeat
    end, #history, 150)
    if
      not first
      or first.inserted ~= last.inserted
      or first.removed ~= last.removed
      or first.enter_key ~= last.enter_key
      or (first.buf == last.buf and math.abs(first.pos[1] - last.pos[1]) == 1)
    then
      return -- different change, or the same text on consecutive lines (selections)
    end
    if vim.fn.strchars(last.inserted) == 1 and util.PAIRS[last.inserted] then
      return -- probably wrapping something in quotes/brackets (surround)
    end

    local searched = false
    for i = index + 1, #history - 1 do
      local ev = history[i]
      if (SEARCH_KEYS[ev.key] and ev.mode == "n" and not ev.arg) or (ev.key == "<Cmd>" and ev.cmdtype ~= ":") then
        searched = true
      end
    end
    if searched then
      return {
        msg = ("You searched and typed `%s` again by hand.\n"):format(last.inserted)
          .. ("→ `cgn%s<Esc>` changes the next match, then `.` changes each following one (`n` skips one)\n"):format(
            last.inserted
          )
          .. ("→ Or `:%%s//%s/g` changes every match of the last search at once"):format(last.inserted),
      }
    end
    return {
      msg = ("You made the same change (typing `%s`) twice.\n→ `.` repeats your last change: move to the next spot and press `.`"):format(
        last.inserted
      ),
    }
  end,
}
