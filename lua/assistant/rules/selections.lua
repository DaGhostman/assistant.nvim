local util = require("assistant.util")

local OPERATORS = { d = true, y = true, c = true, [">"] = true, ["<"] = true, ["="] = true }
local MOTIONS = {
  w = true, e = true, b = true, W = true, E = true, B = true,
  ["$"] = true, ["0"] = true, ["^"] = true, ["{"] = true, ["}"] = true, G = true, ["%"] = true,
}
local CHAR_MOTIONS = { f = true, F = true, t = true, T = true }

--- `v` + one motion + operator -> operator + motion.
---@param history assistant.Event[]
local function visual_operator(history)
  local op = history[#history]
  if not OPERATORS[op.key] or op.arg or not util.is_visual(op.mode) then
    return
  end
  local keys = util.recent(history, 6, #history)
  local start
  for i = #keys, 1, -1 do
    if (keys[i].key == "v" or keys[i].key == "V") and keys[i].mode == "n" and not keys[i].arg then
      start = i
      break
    end
  end
  if not start then
    return
  end
  local visual = keys[start].key
  local between = vim.list_slice(keys, start + 1)
  local tokens = vim.tbl_map(function(ev)
    return ev.key
  end, between)
  local motion = table.concat(tokens)
  local digits = motion:match("^%d*")
  local rest = motion:sub(#digits + 1)

  local ok = false
  if visual == "v" then
    local n = #between - #digits
    local last = between[#between]
    ok = (n == 1 and MOTIONS[rest] ~= nil)
      or (n == 2 and (CHAR_MOTIONS[between[#between - 1].key] or between[#between - 1].textobj) and last.arg)
  elseif visual == "V" and #between > 0 and not rest:find("[^j]") and digits == "" then
    motion = #between .. "j"
    ok = true
  end
  if not ok then
    return
  end
  local typed = visual .. table.concat(tokens) .. op.key
  local better = op.key .. motion
  return {
    msg = ("You typed `%s`.\n→ `%s` does the same without visual mode (%s instead of %d)\nVisual mode is still handy when you want to see the selection first."):format(
      typed,
      better,
      util.plural(#better, "key"),
      #typed
    ),
  }
end

--- The same text inserted on consecutive lines, one by one -> block insert / `:norm`.
---@param history assistant.Event[]
---@param threshold integer
local function block_insert(history, threshold)
  local last = history[#history]
  if last.key ~= "<Insert>" or last.is_repeat or last.multiline or last.removed ~= "" or last.inserted == "" then
    return
  end
  local leader = util.comment_leader(last.buf)
  if leader and vim.trim(last.inserted) == leader then
    return -- the comments rule handles these
  end
  local same_col = true
  local n, row, step = 1, last.pos[1], nil
  for i = #history - 1, math.max(1, #history - 120), -1 do
    local ev = history[i]
    if ev.key == "<Insert>" then
      local d = ev.pos[1] - row
      if ev.inserted ~= last.inserted or ev.removed ~= "" or math.abs(d) ~= 1 or (step and d ~= step) then
        break
      end
      step = d
      same_col = same_col and ev.pos[2] == last.pos[2]
      n, row = n + 1, ev.pos[1]
    end
  end
  if n < threshold then
    return
  end
  local text = last.inserted
  local append = last.enter_key == "A"
  local tips = {}
  if append then
    tips[#tips + 1] = ("`<C-v>` select the lines, then `$A%s<Esc>` appends to every line"):format(text)
  elseif same_col then
    tips[#tips + 1] = ("`<C-v>` select the lines, then `I%s<Esc>` inserts on every line (block insert)"):format(text)
  end
  tips[#tips + 1] = ("Select the lines with `V`, then `:norm %s%s` runs it on each line"):format(append and "A" or "I", text)
  return {
    msg = ("You inserted `%s` on %d lines, one line at a time.\n→ %s"):format(text, n, table.concat(tips, "\n→ ")),
  }
end

--- Better ways to select: skip visual mode for single motions, edit many lines at once.
---@type assistant.Rule
return {
  name = "selections",
  desc = "Visual mode or line-by-line instead of one command",
  check = function(history, opts)
    if not history[#history] then
      return
    end
    return visual_operator(history) or block_insert(history, opts.threshold or 3)
  end,
}
