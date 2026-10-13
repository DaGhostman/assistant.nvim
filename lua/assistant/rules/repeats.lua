local util = require("assistant.util")

--- `xxxxx` and `dd dd dd` -> counts and bigger deletions.
---@type assistant.Rule
return {
  name = "repeats",
  desc = "xxxx / dd dd dd instead of counts",
  check = function(history, opts)
    local prev = util.prev(history)
    if not prev then
      return
    end
    local threshold = opts.threshold or 4

    if prev.key == "x" or prev.key == "X" then
      local key = prev.key
      local n = util.ended_streak(history, function(ev)
        return ev.key == key and ev.mode == "n" and not ev.arg and not ev.counted
      end)
      if n >= threshold then
        local alt = key == "x" and "`dw` / `de` delete a word, `D` deletes to the end of the line"
          or "`db` deletes the word before the cursor, `d0` deletes to the start of the line"
        return { msg = ("You pressed `%s` %d times.\n→ `%d%s` does it in one go\n→ %s"):format(key, n, n, key, alt) }
      end
    elseif prev.key == "d" then
      local n = util.ended_streak(history, function(ev)
        return ev.key == "d" and ev.mode:sub(1, 1) == "n" and not ev.arg and not ev.counted
      end)
      local times = math.floor(n / 2)
      if times >= math.max(2, threshold - 1) then
        return {
          msg = ("You pressed `dd` %d times.\n→ `%ddd` deletes %d lines at once\n→ `dap` deletes a whole paragraph, `dG` to the end of the file"):format(
            times,
            times,
            times
          ),
        }
      end
    end
  end,
}
