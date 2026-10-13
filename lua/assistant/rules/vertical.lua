local util = require("assistant.util")

--- `jjjjj` / `kkkkk` -> counts, paragraph jumps, half-page scrolls.
---@type assistant.Rule
return {
  name = "vertical",
  desc = "jjjj / kkkk instead of counts or { }",
  check = function(history, opts)
    local prev = util.prev(history)
    if not prev or (prev.key ~= "j" and prev.key ~= "k") then
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
    local lines = n
    local tips = {}
    if finish.win == start.win then
      lines = math.abs(finish.pos[1] - start.pos[1])
      if lines == 0 then
        return -- bumped into the start/end of the buffer
      end
      -- Did the streak stop exactly where `}` / `{` would have gone?
      local step = key == "j" and 1 or -1
      for row = start.pos[1] + step, finish.pos[1], step do
        if util.get_line(start.buf, row) == "" then
          if row == finish.pos[1] then
            tips[#tips + 1] = ("`%s` jumps straight to the %s blank line (1 key)"):format(
              key == "j" and "}" or "{",
              key == "j" and "next" or "previous"
            )
          end
          break
        end
      end
    end

    tips[#tips + 1] = ("`%d%s` moves %d lines %s (%d keys)"):format(
      lines,
      key,
      lines,
      key == "j" and "down" or "up",
      #tostring(lines) + 1
    )
    if vim.api.nvim_win_is_valid(start.win) and lines >= vim.api.nvim_win_get_height(start.win) / 3 then
      tips[#tips + 1] = key == "j" and "`<C-d>` scrolls half a page down" or "`<C-u>` scrolls half a page up"
    end

    local msg = ("You pressed `%s` %d times.\n→ %s"):format(key, n, table.concat(tips, "\n→ "))
    if not vim.wo[start.win].relativenumber then
      msg = msg .. "\nTip: `:set relativenumber` shows how far away each line is."
    end
    return { msg = msg }
  end,
}
