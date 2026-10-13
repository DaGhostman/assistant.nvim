local util = require("assistant.util")

--- Keys that add to the jump list.
local JUMPS = { G = true, n = true, N = true, ["*"] = true, ["#"] = true, ["%"] = true, ["("] = true, [")"] = true, ["{"] = true, ["}"] = true }

---@param ev assistant.Event
local function is_jump(ev)
  if ev.key == "<Cmd>" then
    return (ev.cmdtype == "/" or ev.cmdtype == "?") and not ev.aborted
  end
  return (JUMPS[ev.key] and not ev.arg and ev.mode == "n") or (ev.key == "g" and ev.arg_of == "g")
end

--- After a jump, `jjjj`/`kkkk` back to where you came from, or `gg` + `jjjj` to a line.
---@type assistant.Rule
return {
  name = "jumps",
  desc = "Walking back after a jump instead of <C-o>",
  check = function(history, opts)
    local prev = util.prev(history)
    if not prev or (prev.key ~= "j" and prev.key ~= "k") then
      return
    end
    local key = prev.key
    local n, first = util.ended_streak(history, function(ev)
      return ev.key == key and util.is_plain(ev)
    end)
    if n < (opts.threshold or 3) then
      return
    end
    local jump = util.recent(history, 1, first)[1]
    if not jump or not is_jump(jump) then
      return
    end
    local start, finish = history[first], history[#history]
    if finish.win ~= start.win then
      return
    end
    local origin = jump.pos[1]
    if math.abs(finish.pos[1] - origin) <= 1 and math.abs(start.pos[1] - origin) > 1 then
      return {
        msg = ("You pressed `%s` %d times to get back to where you were before the jump.\n"):format(key, n)
          .. "→ `<C-o>` jumps back (and `<C-i>` forwards again)\n"
          .. "→ ``` `` ``` toggles between the last two positions",
      }
    end
    if jump.key == "g" or jump.key == "G" then
      local row = finish.pos[1]
      return {
        msg = ("You pressed `%s%s` and then `%s` %d times to reach line %d.\n→ `%dG` or `:%d` goes straight there"):format(
          jump.key == "g" and "g" or "",
          jump.key,
          key,
          n,
          row,
          row,
          row
        ),
      }
    end
  end,
}
