if vim.g.loaded_assistant then
  return
end
vim.g.loaded_assistant = true

local commands = { "enable", "disable", "toggle", "status", "report", "learn" }
local subcommands = { learn = { "skip", "reset" } }

vim.api.nvim_create_user_command("Assistant", function(args)
  local sub = args.fargs[1] or "status"
  if not vim.tbl_contains(commands, sub) then
    vim.notify("Assistant: unknown command " .. sub, vim.log.levels.ERROR)
    return
  end
  require("assistant")[sub](args.fargs[2])
end, {
  nargs = "*",
  complete = function(lead, cmdline)
    local sub = cmdline:match("^%S+%s+(%S+)%s")
    local options = sub and (subcommands[sub] or {}) or commands
    return vim.tbl_filter(function(c)
      return c:find(lead, 1, true) == 1
    end, options)
  end,
  desc = "Vim motion coach: enable | disable | toggle | status | report [days] | learn [skip|reset]",
})
