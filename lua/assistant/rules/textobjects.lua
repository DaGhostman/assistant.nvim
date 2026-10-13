local util = require("assistant.util")

--- Did any of the few keys before the operation use a text object already?
---@param history assistant.Event[]
local function used_textobj(history)
  for _, ev in ipairs(util.recent(history, 6, #history)) do
    if ev.textobj then
      return true
    end
  end
  return false
end

---@param buf integer
---@param row integer
local function blank(buf, row)
  local line = util.get_line(buf, row)
  return line == nil or line:match("^%s*$") ~= nil
end

--- Deletes, changes and yanks that exactly cover a text object, done the long way.
---@type assistant.Rule
return {
  name = "textobjects",
  desc = "Selecting by hand instead of text objects",
  check = function(history)
    local ev = history[#history]
    if not ev or ev.key ~= "<Yank>" or ev.is_repeat or used_textobj(history) then
      return
    end
    local op = ev.operator
    local r = ev.range
    local how = ev.visual and ("`v…" .. op .. "`") or "that"

    -- Characterwise, within one line: exactly the inside or outside of a pair?
    if ev.regtype == "v" and r[1] == r[3] and ev.line then
      local line = ev.line
      local before_col = util.prev_col(line, r[2])
      local stop = r[4] + #util.char_at(line, r[4])
      local before, after = before_col and util.char_at(line, before_col) or "", util.char_at(line, stop)
      local inner = util.PAIRS[before] == after and before or nil
      local first, lastc = util.char_at(line, r[2]), util.char_at(line, r[4])
      local outer = r[4] > r[2] and util.PAIRS[first] == lastc and first or nil
      if inner and vim.fn.strchars(ev.text) > 1 then
        return {
          msg = ("You %s everything inside `%s%s`.\n→ `%si%s` does that from anywhere inside them (`%sa%s` includes the %s)"):format(
            ({ d = "deleted", c = "changed", y = "yanked" })[op] or "selected",
            inner,
            util.PAIRS[inner],
            op,
            inner,
            op,
            inner,
            util.PAIRS[inner] == inner and "quotes" or "brackets"
          ),
        }
      elseif outer and #ev.text > 2 then
        return {
          msg = ("You %s a whole `%s…%s` block.\n→ `%sa%s` does that from anywhere inside it"):format(
            ({ d = "deleted", c = "changed", y = "yanked" })[op] or "selected",
            outer,
            util.PAIRS[outer],
            op,
            outer
          ),
        }
      end
      return
    end

    -- Linewise visual selection that is exactly a paragraph.
    if ev.regtype == "V" and ev.visual and r[3] > r[1] then
      local before_blank = r[1] == 1 or blank(ev.buf, r[1] - 1)
      local inner = true
      for row = r[1], r[3] do
        if blank(ev.buf, row) then
          inner = false
          break
        end
      end
      if before_blank and inner and blank(ev.buf, r[3] + 1) then
        return {
          msg = ("You selected a whole paragraph with %s.\n→ `%sip` does that from any line in it (`%sap` includes the blank line after)"):format(
            how,
            op,
            op
          ),
        }
      end
    end
  end,
}
