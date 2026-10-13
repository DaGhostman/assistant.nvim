local util = require("assistant.util")

---@param ev assistant.Event
local function used_ctrl_r(ev)
  return vim.tbl_contains(ev.cmd_keys or {}, "<C-R>")
end

--- Is `pattern` a search for exactly `word` (optionally with `\<` `\>`)?
local function is_word_search(pattern, word)
  return word ~= "" and (pattern == word or pattern == "\\<" .. word .. "\\>")
end

--- `/word` for the word under the cursor -> `*`; `/x` for a char on the same line -> `fx`.
---@type assistant.Rule
return {
  name = "search",
  desc = "Typing searches that * or f could do",
  check = function(history)
    local last = history[#history]
    if not last then
      return
    end

    if last.key == "<Cmd>" and (last.cmdtype == "/" or last.cmdtype == "?") and not last.aborted then
      if #last.cword >= 2 and is_word_search(last.cmdline, last.cword) and not used_ctrl_r(last) then
        local key = last.cmdtype == "/" and "*" or "#"
        return {
          msg = ("You searched for `%s`, the word under the cursor.\n→ `%s` searches for it in one key (`%s` searches %s)"):format(
            last.cmdline,
            key,
            key == "*" and "#" or "*",
            key == "*" and "backwards" or "forwards"
          ),
        }
      end
      return
    end

    -- A one-character search that stayed on the line: needs the position after it.
    local cmd = util.prev(history)
    if
      cmd
      and cmd.key == "<Cmd>"
      and (cmd.cmdtype == "/" or cmd.cmdtype == "?")
      and not cmd.aborted
      and vim.fn.strchars(cmd.cmdline) == 1
      and not cmd.cmdline:match("[%.%*%[%]~\\%^%$/?]")
      and last.win == cmd.win
      and last.pos[1] == cmd.pos[1]
    then
      local forward = cmd.cmdtype == "/"
      if (forward and last.pos[2] > cmd.pos[2]) or (not forward and last.pos[2] < cmd.pos[2]) then
        local motion = (forward and "f" or "F") .. util.show(cmd.cmdline)
        return {
          msg = ("You searched `%s%s` for a character on the same line.\n→ `%s` jumps to it without the search (`;` / `,` repeat it)"):format(
            cmd.cmdtype,
            cmd.cmdline,
            motion
          ),
        }
      end
    end
  end,
}
