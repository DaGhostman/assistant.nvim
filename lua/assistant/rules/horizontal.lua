local util = require("assistant.util")

--- Motions that move the cursor from `from` to `to` on `line`, cheapest first.
---@param line string
---@param from integer
---@param to integer
---@return string[]
local function candidates(line, from, to)
  local found = {} ---@type string[]
  local ch = util.char_at(line, to)
  local forward = to > from

  if forward then
    if to == util.prev_col(line, #line) then
      found[#found + 1] = "$"
    end
    local i = line:find(ch, from + 2, true)
    if i and i - 1 == to then
      found[#found + 1] = "f" .. util.show(ch)
    end
    local after = util.char_at(line, to + #ch)
    if after ~= "" then
      i = line:find(after, from + 2, true)
      if i and i - 1 == to + #ch then
        found[#found + 1] = "t" .. util.show(after)
      end
    end
  else
    local first_non_blank = line:find("%S")
    if to == 0 then
      found[#found + 1] = "0"
    elseif first_non_blank and to == first_non_blank - 1 then
      found[#found + 1] = "^"
    end
    -- Last occurrence of `ch` before the cursor.
    local last, i = nil, line:find(ch, 1, true)
    while i and i - 1 < from do
      last = i - 1
      i = line:find(ch, i + 1, true)
    end
    if last == to then
      found[#found + 1] = "F" .. util.show(ch)
    end
    local before_col = util.prev_col(line, to)
    if before_col then
      local before = util.char_at(line, before_col)
      last, i = nil, line:find(before, 1, true)
      while i and i - 1 < from - 1 do
        last = i - 1
        i = line:find(before, i + 1, true)
      end
      if last == before_col then
        found[#found + 1] = "T" .. util.show(before)
      end
    end
  end

  local starts, ends = 0, 0
  for _, w in ipairs(util.words(line)) do
    if forward then
      if w.s > from and w.s <= to then
        starts = starts + 1
        if w.s == to then
          found[#found + 1] = (starts > 1 and starts or "") .. "w"
        end
      end
      if w.e > from and w.e <= to then
        ends = ends + 1
        if w.e == to then
          found[#found + 1] = (ends > 1 and ends or "") .. "e"
        end
      end
    elseif w.s >= to and w.s < from then
      starts = starts + 1
    end
  end
  if not forward then
    for _, w in ipairs(util.words(line)) do
      if w.s == to then
        found[#found + 1] = (starts > 1 and starts or "") .. "b"
      end
    end
  end

  -- Shortest first; `f<Space>` is still only two keys.
  local function cost(motion)
    return #motion:gsub("<Space>", " ")
  end
  table.sort(found, function(a, b)
    return cost(a) < cost(b)
  end)
  return found
end

--- `llllll` / `hhhhh` -> the word or character motion that lands on the same spot.
---@type assistant.Rule
return {
  name = "horizontal",
  desc = "hhhh / llll instead of w b e f t",
  check = function(history, opts)
    local prev = util.prev(history)
    if not prev or (prev.key ~= "h" and prev.key ~= "l") then
      return
    end
    local key = prev.key
    local n, first = util.ended_streak(history, function(ev)
      return ev.key == key and util.is_plain(ev)
    end)
    if n < (opts.threshold or 4) then
      return
    end

    local start, finish = history[first], history[#history]
    local found = {}
    if finish.win == start.win and finish.pos[1] == start.pos[1] then
      if finish.pos[2] == start.pos[2] then
        return -- bumped into the start/end of the line
      end
      local line = util.get_line(start.buf, start.pos[1])
      if line then
        found = candidates(line, start.pos[2], finish.pos[2])
      end
    end

    local msg = ("You pressed `%s` %d times."):format(key, n)
    if #found > 0 then
      local best = {}
      for i = 1, math.min(3, #found) do
        best[i] = ("`%s`"):format(found[i])
      end
      msg = msg .. ("\n→ %s would land on the same spot (%d keys instead of %d)"):format(
        table.concat(best, " or "),
        #found[1]:gsub("<Space>", " "),
        n
      )
    else
      msg = msg
        .. ("\n→ `%s` move by words, `%s` jump to a character"):format(
          key == "l" and "w`/`e" or "b`/`ge",
          key == "l" and "f{char}`/`t{char}" or "F{char}`/`T{char}"
        )
    end
    return { msg = msg }
  end,
}
