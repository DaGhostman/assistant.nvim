local config = require("assistant.config")
local learn = require("assistant.learn")
local stats = require("assistant.stats")
local util = require("assistant.util")

local M = {}

---@class assistant.Hint
---@field rule string Name of the rule that produced the hint
---@field msg string

---@type table<string, assistant.Hint>
local pending = {}
---@type table<string, integer>
local last_shown = {}
local last_any ---@type integer?

---@type table<string, { triggered: integer, shown: integer }>
M.stats = {}

local function stat(rule)
  M.stats[rule] = M.stats[rule] or { triggered = 0, shown = 0 }
  return M.stats[rule]
end

--- Remember a hint; it is shown on the next `flush()` if no cooldown is active.
---@param hint assistant.Hint
function M.queue(hint)
  pending[hint.rule] = hint
  local s = stat(hint.rule)
  s.triggered = s.triggered + 1
  stats.rule(hint.rule, "noticed")
end

--- Show a plain message (learning path) through the configured channel.
---@param msg string
function M.message(msg)
  local notify = config.options.notify
  if notify then
    notify(msg, { rule = "learn", msg = msg })
  else
    vim.notify(msg, vim.log.levels.INFO, { title = "Assistant", timeout = config.options.display_time })
  end
end

---@param hint assistant.Hint
local function show(hint)
  stats.rule(hint.rule, "shown")
  local focus = learn.focus_for(hint.rule)
  if focus then
    hint = vim.tbl_extend("force", hint, { msg = hint.msg .. ("\n★ Today's focus: %s (%s)"):format(focus.title, focus.short) })
  end
  util.emit("Hint", { rule = hint.rule, msg = hint.msg })
  local display = config.options.display
  if display == "ghost" or display == "both" then
    require("assistant.ghost").show_hint(hint)
  end
  if display == "ghost" then
    return
  end
  local notify = config.options.notify
  if notify then
    notify(hint.msg, hint)
  else
    vim.notify(hint.msg, vim.log.levels.INFO, { title = "Assistant", timeout = config.options.display_time })
  end
end

--- Show at most one pending hint, respecting the global and per-rule cooldowns.
function M.flush()
  local queued = pending
  pending = {}
  if next(queued) then
    learn.refresh() -- new habits noticed: maybe a relapse
  end
  local now = vim.uv.now()
  local opts = config.options
  if last_any and now - last_any < opts.cooldown.global * 1000 then
    return
  end
  for _, rule in ipairs(require("assistant.rules")) do
    local hint = queued[rule.name]
    local cooldown = (config.rule(rule.name).cooldown or opts.cooldown.rule) * 1000
    if hint and not learn.is_quiet(rule.name) and (not last_shown[rule.name] or now - last_shown[rule.name] >= cooldown) then
      last_shown[rule.name], last_any = now, now
      local s = stat(rule.name)
      s.shown = s.shown + 1
      show(hint)
      return
    end
  end
end

function M.reset()
  pending, last_shown, last_any = {}, {}, nil
end

return M
