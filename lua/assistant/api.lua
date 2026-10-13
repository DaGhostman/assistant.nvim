--- Public API for dashboards, statuslines and other plugins.
---
--- Everything here works without `setup()` (it reads the saved stats and learning
--- state), so it can be called from a start screen before the plugin is loaded.
---
--- Events (`User` autocmds, `args.data` holds the details):
---   AssistantHint          a hint was shown           { rule, msg }
---   AssistantProgress      a focus skill was used     { skill, today, goal }
---   AssistantChallengeDone the daily goal was reached { skill, today, goal }
---   AssistantLearned       a skill counts as learned  { skill, title }
---   AssistantRelapse       an old habit came back     { skill, title, slips }
local M = {}

--- Today's focus skills with progress.
---@return assistant.Focus[]
function M.focus()
  return require("assistant.learn").focus()
end

--- Every lesson of the learning path with its status
--- ("new" | "learning" | "learned" | "relapsed").
---@return assistant.LessonStatus[]
function M.lessons()
  return require("assistant.learn").lessons()
end

---@class assistant.Summary
---@field days integer Length of the period
---@field keys { now: integer, before: integer } Normal/visual mode keys
---@field hjkl_share { now: integer, before: integer } Percent of plain h/j/k/l presses
---@field habits { rule: string, desc: string, now: integer, before: integer }[] Most noticed first
---@field skills { skill: string, desc: string, now: integer, before: integer }[] Most used first
---@field learned integer Skills learned
---@field total integer Skills in the learning path

--- Numbers for the last `days` days and the `days` before.
---@param days? integer Default `stats.report_days`
---@return assistant.Summary
function M.summary(days)
  local config = require("assistant.config")
  local stats = require("assistant.stats")
  days = days or config.options.stats.report_days
  local data = stats.load()
  local now = os.time()
  local function range(offset)
    local keys = {}
    for i = offset, offset + days - 1 do
      keys[#keys + 1] = os.date("%Y-%m-%d", now - i * 86400)
    end
    return keys
  end
  local cur, prev = range(0), range(days)
  local function sum(keys, get)
    local total = 0
    for _, k in ipairs(keys) do
      total = total + (data[k] and get(data[k]) or 0)
    end
    return total
  end
  local function pair(get)
    return { now = sum(cur, get), before = sum(prev, get) }
  end

  local keys = pair(function(d) return d.keys or 0 end)
  local hjkl = pair(function(d) return d.hjkl or 0 end)
  local result = {
    days = days,
    keys = keys,
    hjkl_share = {
      now = keys.now > 0 and math.floor(hjkl.now / keys.now * 100 + 0.5) or 0,
      before = keys.before > 0 and math.floor(hjkl.before / keys.before * 100 + 0.5) or 0,
    },
    habits = {},
    skills = {},
  }
  for _, rule in ipairs(require("assistant.rules")) do
    local p = pair(function(d)
      return d.rules and d.rules[rule.name] and d.rules[rule.name].noticed or 0
    end)
    if p.now + p.before > 0 then
      result.habits[#result.habits + 1] = { rule = rule.name, desc = rule.desc, now = p.now, before = p.before }
    end
  end
  for _, skill in ipairs(stats.SKILLS) do
    local p = pair(function(d)
      return d.skills and d.skills[skill.name] or 0
    end)
    if p.now + p.before > 0 then
      result.skills[#result.skills + 1] = { skill = skill.name, desc = skill.desc, now = p.now, before = p.before }
    end
  end
  local by_now = function(a, b)
    return a.now > b.now
  end
  table.sort(result.habits, by_now)
  table.sort(result.skills, by_now)

  local learned = 0
  for _, l in ipairs(M.lessons()) do
    learned = learned + (l.status == "learned" and 1 or 0)
  end
  result.learned, result.total = learned, #require("assistant.learn").LESSONS
  return result
end

--- The full report as plain lines.
---@param days? integer
---@return string[]
function M.report_lines(days)
  local config = require("assistant.config")
  local lines, hls = require("assistant.report").build(require("assistant.stats").load(), days or config.options.stats.report_days)
  require("assistant.learn").append_summary(lines, hls)
  return lines
end

---@class assistant.DashboardOpts
---@field tip? boolean Include the focus tip (default true)
---@field stats? boolean Include the learned / hjkl line (default true)

--- A few short lines for a start screen: today's focus, its tip, overall progress.
---@param opts? assistant.DashboardOpts
---@return string[]
function M.dashboard(opts)
  opts = vim.tbl_extend("force", { tip = true, stats = true }, opts or {})
  local lines = {}
  for _, f in ipairs(M.focus()) do
    lines[#lines + 1] = ("★ Today: %s (%s)  %d/%d%s"):format(f.title, f.short, f.today, f.goal, f.done and " ✓" or "")
    if opts.tip then
      lines[#lines + 1] = (f.tip:gsub("`", ""))
    end
  end
  if opts.stats then
    local s = M.summary()
    local line = ("%d/%d skills learned"):format(s.learned, s.total)
    if s.keys.now > 0 then
      line = line .. ("  ·  hjkl %d%% of keys"):format(s.hjkl_share.now)
      if s.keys.before > 0 and s.hjkl_share.before ~= s.hjkl_share.now then
        line = line .. (" (was %d%%)"):format(s.hjkl_share.before)
      end
    end
    lines[#lines + 1] = line
  end
  return lines
end

---@class assistant.StatuslineOpts
---@field icon? string Prefix (default "★")
---@field done_icon? string Shown once the daily goal is reached (default "✓")

--- Short text for a statusline component, e.g. "★ f t 3/10". Empty when there's
--- no focus. Cheap enough to call on every redraw.
---@param opts? assistant.StatuslineOpts
---@return string
function M.statusline(opts)
  opts = opts or {}
  local learn = require("assistant.learn")
  local skill = learn.ensure_focus()[1]
  local lesson = skill and learn.lesson(skill)
  if not lesson then
    return ""
  end
  local goal = require("assistant.config").options.learn.daily_goal
  local today = require("assistant.stats").count_today(skill)
  if today >= goal then
    return ("%s %s"):format(opts.done_icon or "✓", lesson.short)
  end
  return ("%s %s %d/%d"):format(opts.icon or "★", lesson.short, today, goal)
end

return M
