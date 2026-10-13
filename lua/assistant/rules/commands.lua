local util = require("assistant.util")

---@param ev assistant.Event?
local function ex(ev)
  if not ev or ev.key ~= "<Cmd>" or ev.cmdtype ~= ":" or ev.aborted then
    return nil
  end
  local ok, cmd = pcall(vim.api.nvim_parse_cmd, ev.cmdline, {})
  return ok and cmd or nil
end

--- Ex command habits: `:w` + `:q`, `:e #`.
---@type assistant.Rule
return {
  name = "commands",
  desc = "Ex command shortcuts (:wq, <C-^>)",
  check = function(history)
    local cmd = ex(history[#history])
    if not cmd then
      return
    end
    if (cmd.cmd == "edit" or cmd.cmd == "buffer") and cmd.args[1] == "#" then
      return { msg = ("You typed `:%s`.\n→ `<C-^>` switches to the alternate file in one key"):format(history[#history].cmdline) }
    end
    if cmd.cmd == "quit" or cmd.cmd == "quitall" then
      -- The command before this one, with only the `:` key in between.
      local keys = util.recent(history, 3)
      local prev = ex(keys[1])
      if prev and keys[2] and keys[2].key == ":" and #prev.args == 0 and #cmd.args == 0 then
        if prev.cmd == "write" and cmd.cmd == "quit" then
          return { msg = "You ran `:w` then `:q`.\n→ `:wq` (or `:x` / `ZZ`, which only write when there are changes) does both" }
        elseif prev.cmd == "wall" and cmd.cmd == "quitall" then
          return { msg = "You ran `:wa` then `:qa`.\n→ `:wqa` (or `:xa`) does both" }
        end
      end
    end
  end,
}
