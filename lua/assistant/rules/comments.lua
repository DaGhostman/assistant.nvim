local util = require("assistant.util")

---@param line string
local function first_non_blank(line)
  return (line:find("%S") or 1) - 1
end

--- Typing or deleting comment leaders (`// `, `-- `, `# `) by hand -> `gcc` / `gc{motion}`.
---@type assistant.Rule
return {
  name = "comments",
  desc = "Typing comment markers instead of gc",
  check = function(history)
    local last = history[#history]
    if not last or last.is_repeat then
      return
    end
    local leader = util.comment_leader(last.buf)
    if not leader then
      return
    end

    if last.key == "<Insert>" and not last.multiline and last.removed == "" and vim.trim(last.inserted) == leader then
      local line = util.get_line(last.buf, last.pos[1]) or ""
      if last.pos[2] ~= first_non_blank(line) then
        return
      end
      -- Count the lines commented the same way just before this one.
      local n, row = 1, last.pos[1]
      for i = #history - 1, math.max(1, #history - 80), -1 do
        local ev = history[i]
        if ev.key == "<Insert>" then
          if ev.inserted ~= last.inserted or math.abs(ev.pos[1] - row) ~= 1 then
            break
          end
          n, row = n + 1, ev.pos[1]
        end
      end
      if n > 1 then
        return {
          msg = ("You typed `%s` on %d lines.\n→ `gc{motion}` comments them all: `gc%dj`, `gcip` for a paragraph, or `gc` on a visual selection"):format(
            leader,
            n,
            n - 1
          ),
        }
      end
      return {
        msg = ("You typed `%s` by hand.\n→ `gcc` toggles a comment on the line; `gc{motion}` (`gcip`, `gc3j`) on several"):format(leader),
      }
    end

    if last.key == "<Yank>" and last.operator == "d" and not last.visual and last.range[1] == last.range[3] then
      if vim.trim(last.text) == leader and last.line and last.range[2] == first_non_blank(last.line) then
        return { msg = "You deleted a comment leader by hand.\n→ `gcc` toggles comments off as well as on (`gc{motion}` for several lines)" }
      end
    end
  end,
}
