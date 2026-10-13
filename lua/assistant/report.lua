local stats = require("assistant.stats")

local M = {}

local SPARK = { "▁", "▂", "▃", "▄", "▅", "▆", "▇", "█" }

---@param t integer
local function day_key(t)
  return os.date("%Y-%m-%d", t) --[[@as string]]
end

--- Day keys for `count` days, ending `offset` days before `today`, oldest first.
---@param today integer os.time() of today
local function day_range(today, offset, count)
  local keys = {}
  for i = offset + count - 1, offset, -1 do
    keys[#keys + 1] = day_key(today - i * 86400)
  end
  return keys
end

---@param days table<string, assistant.Day>
---@param keys string[]
---@param get fun(day: assistant.Day): integer
local function sum(days, keys, get)
  local total = 0
  for _, k in ipairs(keys) do
    if days[k] then
      total = total + (get(days[k]) or 0)
    end
  end
  return total
end

--- Trend arrow and change, e.g. "▼ 65%".
---@return string text, boolean? improving
local function trend(now, before, lower_is_better)
  if now == before then
    return "", nil
  end
  if before == 0 then
    return "new", not lower_is_better
  end
  local pct = math.floor(math.abs(now - before) / before * 100 + 0.5)
  local up = now > before
  return ("%s %d%%"):format(up and "▲" or "▼", pct), up ~= lower_is_better
end

---@param n integer
local function num(n)
  local s = tostring(n)
  return (s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", ""))
end

--- Build the report text.
---@param days table<string, assistant.Day>
---@param period integer Number of days to compare
---@param today? integer os.time() of today
---@return string[] lines, assistant.Highlight[] highlights
function M.build(days, period, today)
  local t = today or os.time()
  local now_keys, prev_keys = day_range(t, 0, period), day_range(t, period, period)
  local lines, hls = {}, {}

  local function add(text, group)
    lines[#lines + 1] = text
    if group then
      hls[#hls + 1] = { line = #lines - 1, col = 0, end_col = #text, group = group }
    end
  end
  --- A table row with a trend column, highlighted good/bad.
  local function row(label, now, before, lower_is_better)
    local arrow, improving = trend(now, before, lower_is_better)
    local text = ("  %-46s %7s %7s  %s"):format(label, num(now), num(before), arrow)
    add(text)
    if improving ~= nil then
      hls[#hls + 1] = {
        line = #lines - 1,
        col = #text - #arrow,
        end_col = #text,
        group = improving and "DiagnosticOk" or "DiagnosticWarn",
      }
    end
  end
  local function header(title)
    add("")
    add(("%-48s %7s %7s"):format(title, "now", "before"), "Title")
  end

  add(("Assistant report: last %d days, compared with the %d days before"):format(period, period), "Title")

  local keys_now = sum(days, now_keys, function(d) return d.keys end)
  local keys_prev = sum(days, prev_keys, function(d) return d.keys end)
  if keys_now + keys_prev == 0 then
    add("")
    add("No data yet. Edit for a while and come back.")
    return lines, hls
  end
  local hjkl_now = sum(days, now_keys, function(d) return d.hjkl end)
  local hjkl_prev = sum(days, prev_keys, function(d) return d.hjkl end)
  local share_now = keys_now > 0 and math.floor(hjkl_now / keys_now * 100 + 0.5) or 0
  local share_prev = keys_prev > 0 and math.floor(hjkl_prev / keys_prev * 100 + 0.5) or 0

  header("Overview")
  row("Normal/visual mode keys", keys_now, keys_prev)
  row("Share of plain h/j/k/l presses (%)", share_now, share_prev, true)

  -- Habits: every rule that noticed something in either period.
  local habits = {}
  for _, rule in ipairs(require("assistant.rules")) do
    local get = function(d)
      return d.rules and d.rules[rule.name] and d.rules[rule.name].noticed or 0
    end
    local now, before = sum(days, now_keys, get), sum(days, prev_keys, get)
    if now + before > 0 then
      habits[#habits + 1] = { label = rule.desc, now = now, before = before }
    end
  end
  table.sort(habits, function(a, b)
    return a.now > b.now
  end)
  header("Habits noticed (fewer is better)")
  if #habits == 0 then
    add("  None. Nice!")
  end
  for _, h in ipairs(habits) do
    row(h.label, h.now, h.before, true)
  end

  -- Skills: used ones first, then the ones still to learn.
  local used, unused = {}, {}
  for _, skill in ipairs(stats.SKILLS) do
    local get = function(d)
      return d.skills and d.skills[skill.name] or 0
    end
    local now, before = sum(days, now_keys, get), sum(days, prev_keys, get)
    if now + before > 0 then
      used[#used + 1] = { label = skill.desc, now = now, before = before }
    else
      unused[#unused + 1] = skill.desc
    end
  end
  table.sort(used, function(a, b)
    return a.now > b.now
  end)
  header("Skills used (more is better)")
  for _, s in ipairs(used) do
    row(s.label, s.now, s.before, false)
  end
  if #unused > 0 then
    add("")
    add("Not tried yet", "Title")
    for _, desc in ipairs(unused) do
      add("  · " .. desc)
    end
  end

  -- Habits noticed per day, for the last two periods.
  local spark_keys = day_range(t, 0, period * 2)
  local counts, max = {}, 0
  for i, k in ipairs(spark_keys) do
    local n = 0
    for _, r in pairs(days[k] and days[k].rules or {}) do
      n = n + (r.noticed or 0)
    end
    counts[i], max = n, math.max(max, n)
  end
  local spark = {}
  for i, n in ipairs(counts) do
    spark[i] = max == 0 and SPARK[1] or SPARK[math.max(1, math.ceil(n / max * #SPARK))]
  end
  add("")
  add(("Habits noticed per day (last %d days)"):format(#spark_keys), "Title")
  add("  " .. table.concat(spark) .. ("  max %d/day"):format(max))
  add("  " .. spark_keys[1]:sub(6) .. string.rep(" ", math.max(1, #spark_keys - 10)) .. spark_keys[#spark_keys]:sub(6))
  return lines, hls
end

--- Show the report in a floating window.
---@param period? integer Days to compare (default from config)
function M.open(period)
  period = period or require("assistant.config").options.stats.report_days
  stats.save()
  local lines, hls = M.build(stats.load(), period)
  require("assistant.learn").append_summary(lines, hls)
  require("assistant.ui").float(lines, hls, { title = "Assistant", filetype = "assistant_report" })
end

return M
