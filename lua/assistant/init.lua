local config = require("assistant.config")

local M = {}

M.enabled = false

---@param opts? assistant.Config
function M.setup(opts)
  -- Disable first: it saves pending stats under the old configuration.
  if M.enabled then
    M.disable()
  end
  config.set(opts)
  if config.options.enabled then
    M.enable()
  end
end

function M.enable()
  require("assistant.stats").start()
  require("assistant.ghost").start()
  require("assistant.tracker").start()
  require("assistant.learn").start()
  M.enabled = true
end

function M.disable()
  require("assistant.tracker").stop()
  require("assistant.notifier").reset()
  require("assistant.ghost").stop()
  require("assistant.stats").stop()
  M.enabled = false
end

function M.toggle()
  if M.enabled then
    M.disable()
  else
    M.enable()
  end
  vim.notify("Assistant " .. (M.enabled and "enabled" or "disabled"), vim.log.levels.INFO, { title = "Assistant" })
end

--- Hints triggered and shown during this session, per rule.
function M.status()
  local lines = { ("Assistant is %s"):format(M.enabled and "enabled" or "disabled"), "" }
  local stats = require("assistant.notifier").stats
  for _, rule in ipairs(require("assistant.rules")) do
    local s = stats[rule.name] or { triggered = 0, shown = 0 }
    lines[#lines + 1] = ("%-12s %3d noticed, %3d shown"):format(rule.name, s.triggered, s.shown)
  end
  vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Assistant" })
end

--- `:Assistant learn [skip|reset]`: the learning path.
---@param action? "skip"|"reset"
function M.learn(action)
  local learn = require("assistant.learn")
  if action == "skip" then
    learn.skip()
  elseif action == "reset" then
    learn.reset()
  else
    learn.open()
  end
end

--- Open the habit report.
---@param days? integer|string Days to compare (default `stats.report_days`)
function M.report(days)
  require("assistant.report").open(tonumber(days))
end

return M
