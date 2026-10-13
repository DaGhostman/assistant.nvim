local config = require("assistant.config")
local stats = require("assistant.stats")
local util = require("assistant.util")

--- The learning path: a daily focus skill, "learned" tracking and relapse reminders.
---
--- Progress is derived from the daily stats (how often and on how many days a skill
--- was used, how often the related habits were noticed). The only extra state is the
--- current focus, skills marked as learned and which messages were already shown.
local M = {}

---@class assistant.Lesson
---@field skill string Skill name from `stats.SKILLS`
---@field title string
---@field short string A few keys that represent the skill
---@field tip string
---@field habits string[] Rules that notice the opposite habit

--- In the order they are suggested: basics first.
---@type assistant.Lesson[]
M.LESSONS = {
  {
    skill = "counts",
    title = "Counted motions",
    short = "5j",
    tip = "Put a number before a motion: `5j` moves 5 lines, `3w` 3 words, `2dd` deletes 2 lines. `:set relativenumber` shows the distances.",
    habits = { "vertical", "repeats" },
  },
  {
    skill = "words",
    title = "Word motions",
    short = "w b e",
    tip = "`w` jumps to the next word, `b` back to the previous one, `e` to the end of the word. `W` `B` `E` skip punctuation.",
    habits = { "horizontal" },
  },
  {
    skill = "line_shortcuts",
    title = "Line shortcuts",
    short = "A I",
    tip = "`A` appends at the end of the line, `I` inserts at the start, `C` changes to the end, `D` deletes to the end, `S` replaces the line.",
    habits = { "shortcuts" },
  },
  {
    skill = "char_jumps",
    title = "Character jumps",
    short = "f t",
    tip = "`fx` jumps to the next `x` on the line, `tx` to just before it. `;` repeats the jump, `,` goes back. `F` / `T` search backwards.",
    habits = { "horizontal" },
  },
  {
    skill = "paragraphs",
    title = "Paragraph jumps",
    short = "{ }",
    tip = "`}` jumps to the next blank line, `{` to the previous one: a fast way to move between blocks of code.",
    habits = { "vertical" },
  },
  {
    skill = "textobjects",
    title = "Text objects",
    short = "ciw",
    tip = '`ciw` changes the word under the cursor, `di(` deletes inside parentheses, `ya"` yanks a quoted string. `i` = inside, `a` = around.',
    habits = { "textobjects" },
  },
  {
    skill = "dot",
    title = "Dot repeat",
    short = ".",
    tip = "`.` repeats your last change. Make a change once, move to the next spot, press `.`.",
    habits = { "repeat", "repeats" },
  },
  {
    skill = "search",
    title = "Search",
    short = "* n",
    tip = "`*` searches for the word under the cursor, `#` backwards. `n` / `N` go to the next / previous match.",
    habits = { "search" },
  },
  {
    skill = "scrolling",
    title = "Scrolling",
    short = "<C-d>",
    tip = "`<C-d>` / `<C-u>` scroll half a page down / up, `<C-f>` / `<C-b>` a full page.",
    habits = { "vertical" },
  },
  {
    skill = "jumps",
    title = "Jump list",
    short = "<C-o>",
    tip = "`<C-o>` goes back to where you were before a jump (search, `G`, `%`, …), `<C-i>` forwards again. `%` jumps to the matching bracket.",
    habits = { "jumps" },
  },
  {
    skill = "registers",
    title = "Registers",
    short = '"0p',
    tip = '`"0p` pastes your last yank even after deletes, `"_d` deletes without touching the register, `P` in visual mode replaces without yanking.',
    habits = { "registers" },
  },
  {
    skill = "comments",
    title = "Comments",
    short = "gcc",
    tip = "`gcc` toggles a comment on the line, `gc{motion}` on several (`gcip` for a paragraph, `gc3j`), `gc` in visual mode.",
    habits = { "comments" },
  },
  {
    skill = "block",
    title = "Visual block",
    short = "<C-v>",
    tip = "`<C-v>` selects a column. `I` / `A` then insert / append on every selected line at once.",
    habits = { "selections" },
  },
  {
    skill = "substitute",
    title = "Substitute",
    short = ":%s",
    tip = "`:%s/old/new/g` replaces in the whole file (`gc` to confirm each). An empty pattern `:%s//new/g` reuses the last search.",
    habits = { "substitute" },
  },
  {
    skill = "macros",
    title = "Macros",
    short = "qq @q",
    tip = "`qq` starts recording into register q, `q` stops. `@q` replays it, `@@` repeats, `10@q` runs it ten times.",
    habits = { "macro" },
  },
  {
    skill = "global",
    title = ":g and :norm",
    short = ":g",
    tip = "`:g/pattern/d` deletes every matching line, `:g/pattern/norm A;` runs keys on each. `:norm` on a selection runs keys on every line.",
    habits = { "macro" },
  },
}

---@class assistant.LessonStatus: assistant.Lesson
---@field status "new"|"learning"|"learned"|"relapsed"
---@field uses integer Uses in the window
---@field days integer Days used in the window
---@field slips integer Related habits noticed recently
---@field today integer Uses today

---@class assistant.LearnState
---@field focus_day? string
---@field focus string[]
---@field learned table<string, string> skill -> day it was learned (or skipped)
---@field relapsed table<string, string> skill -> day the relapse was announced
---@field announced_day? string
---@field done table<string, string> skill -> day its daily goal was reached

local state ---@type assistant.LearnState?
---@type table<string, assistant.LessonStatus>? Cached by `refresh()`
local cache

local function opts()
  return config.options.learn
end

local function today()
  return os.date("%Y-%m-%d") --[[@as string]]
end

local function path()
  return opts().path or (vim.fn.stdpath("data") .. "/assistant/learn.json")
end

---@return assistant.LearnState
local function load_state()
  if state then
    return state
  end
  state = { focus = {}, learned = {}, relapsed = {}, done = {} }
  local f = io.open(path(), "r")
  if f then
    local ok, data = pcall(vim.json.decode, f:read("*a"))
    f:close()
    if ok and type(data) == "table" then
      state = vim.tbl_extend("force", state, data)
    end
  end
  return state
end

local function save_state()
  local file = path()
  vim.fn.mkdir(vim.fn.fnamemodify(file, ":h"), "p")
  local f = io.open(file .. ".tmp", "w")
  if f then
    f:write(vim.json.encode(load_state()))
    f:close()
    os.rename(file .. ".tmp", file)
  end
end

--- Day keys for the last `n` days, including today.
local function last_days(n)
  local keys, now = {}, os.time()
  for i = 0, n - 1 do
    keys[#keys + 1] = os.date("%Y-%m-%d", now - i * 86400)
  end
  return keys
end

---@param skill string
---@return assistant.Lesson?
function M.lesson(skill)
  for _, l in ipairs(M.LESSONS) do
    if l.skill == skill then
      return l
    end
  end
end

--- Every lesson with its current status, computed from the stats.
---@return assistant.LessonStatus[]
function M.lessons()
  local o, st = opts(), load_state()
  local days = stats.load()
  local window, recent = last_days(o.window_days), last_days(o.relapse_days)
  local result = {}
  for _, lesson in ipairs(M.LESSONS) do
    local uses, used_days, slips = 0, 0, 0
    for _, d in ipairs(window) do
      local n = days[d] and days[d].skills and days[d].skills[lesson.skill] or 0
      uses = uses + n
      used_days = used_days + (n > 0 and 1 or 0)
    end
    for _, d in ipairs(recent) do
      for _, rule in ipairs(lesson.habits) do
        local r = days[d] and days[d].rules and days[d].rules[rule]
        slips = slips + (r and r.noticed or 0)
      end
    end
    local learned = st.learned[lesson.skill] ~= nil or (used_days >= o.learned_days and uses >= o.learned_uses)
    local status = (learned and slips >= o.relapse_threshold and "relapsed")
      or (learned and "learned")
      or (uses > 0 and "learning")
      or "new"
    local d = days[today()]
    result[#result + 1] = vim.tbl_extend("force", lesson, {
      status = status,
      uses = uses,
      days = used_days,
      slips = slips,
      today = d and d.skills and d.skills[lesson.skill] or 0,
    })
  end
  return result
end

--- Today's focus skills; picks new ones on a new day. Never shows messages.
---@param lessons? assistant.LessonStatus[]
---@return string[]
function M.ensure_focus(lessons)
  local st = load_state()
  if st.focus_day == today() then
    return st.focus
  end
  lessons = lessons or M.lessons()
  local focus = {}
  local function take(pred)
    for _, l in ipairs(lessons) do
      if #focus < opts().focus_count and pred(l) and not vim.tbl_contains(focus, l.skill) then
        focus[#focus + 1] = l.skill
      end
    end
  end
  -- Relapsed skills first, then the next ones in curriculum order.
  take(function(l)
    return l.status == "relapsed"
  end)
  take(function(l)
    return l.status == "learning" or l.status == "new"
  end)
  st.focus_day, st.focus = today(), focus
  save_state()
  return focus
end

---@class assistant.Focus: assistant.LessonStatus
---@field goal integer Daily goal
---@field done boolean Goal reached today

--- Today's focus with progress.
---@return assistant.Focus[]
function M.focus()
  local lessons = M.lessons()
  local by_skill = {}
  for _, l in ipairs(lessons) do
    by_skill[l.skill] = l
  end
  local result = {}
  for _, skill in ipairs(M.ensure_focus(lessons)) do
    local l = by_skill[skill]
    if l then
      l.today = stats.count_today(skill)
      result[#result + 1] = vim.tbl_extend("force", l, { goal = opts().daily_goal, done = l.today >= opts().daily_goal })
    end
  end
  return result
end

---@param msg string
local function message(msg)
  require("assistant.notifier").message(msg)
end

--- Recompute statuses and announce changes (learned, relapsed). Called by the
--- plugin at startup and when habits are noticed.
function M.refresh()
  if not opts().enabled then
    cache = nil
    return
  end
  local st = load_state()
  local lessons = M.lessons()
  local changed = false
  cache = {}
  for _, l in ipairs(lessons) do
    cache[l.skill] = l
    if (l.status == "learned" or l.status == "relapsed") and not st.learned[l.skill] then
      st.learned[l.skill], changed = today(), true
      util.emit("Learned", { skill = l.skill, title = l.title })
      message(("Learned: %s (%s) ✓\nHints about it will stay quiet unless the old habit comes back."):format(l.title, l.short))
    end
    if l.status == "relapsed" and not st.relapsed[l.skill] then
      st.relapsed[l.skill], changed = today(), true
      if st.focus_day == today() and not vim.tbl_contains(st.focus, l.skill) then
        table.insert(st.focus, 1, l.skill)
      end
      util.emit("Relapse", { skill = l.skill, title = l.title, slips = l.slips })
      message(("The old habit is back (%d times in %d days).\nFocus is back on %s: %s"):format(
        l.slips,
        opts().relapse_days,
        l.title,
        l.tip
      ))
    elseif l.status == "learned" and st.relapsed[l.skill] then
      st.relapsed[l.skill], changed = nil, true
    end
  end
  if st.focus_day ~= today() then
    M.ensure_focus(lessons)
  end
  if changed then
    save_state()
  end
end

--- Should hints from this rule stay quiet? True when every skill that fixes the
--- habit is learned (and not relapsing).
---@param rule string
function M.is_quiet(rule)
  if not opts().enabled or not opts().quiet_learned or not cache then
    return false
  end
  local related = false
  for _, l in pairs(cache) do
    if vim.tbl_contains(l.habits, rule) then
      related = true
      if l.status ~= "learned" then
        return false
      end
    end
  end
  return related
end

--- The focus lesson a rule belongs to, if any.
---@param rule string
---@return assistant.Lesson?
function M.focus_for(rule)
  if not opts().enabled or not state or state.focus_day ~= today() then
    return nil
  end
  for _, skill in ipairs(state.focus) do
    local l = M.lesson(skill)
    if l and vim.tbl_contains(l.habits, rule) then
      return l
    end
  end
end

--- Called by stats for every skill use: tracks the daily goal.
---@param skill string
function M.on_skill(skill)
  if not opts().enabled or not state or state.focus_day ~= today() or not vim.tbl_contains(state.focus, skill) then
    return
  end
  local count = stats.count_today(skill)
  local goal = opts().daily_goal
  util.emit("Progress", { skill = skill, today = count, goal = goal })
  if count >= goal and state.done[skill] ~= today() then
    state.done[skill] = today()
    save_state()
    local l = M.lesson(skill)
    util.emit("ChallengeDone", { skill = skill, today = count, goal = goal })
    vim.schedule(function()
      message(("Daily goal reached: %s used %d times today ✓"):format(l and l.title or skill, count))
    end)
  end
end

--- Once a day: tell the user what today's focus is.
function M.announce()
  local st = load_state()
  if not opts().enabled or not opts().announce or st.announced_day == today() then
    return
  end
  local focus = M.focus()
  if #focus == 0 then
    return
  end
  st.announced_day = today()
  save_state()
  local lines = {}
  for _, f in ipairs(focus) do
    lines[#lines + 1] = ("Today's focus: %s (%s)\n%s"):format(f.title, f.short, f.tip)
  end
  lines[#lines + 1] = ("Goal: use it %d times today. `:Assistant learn` shows your progress."):format(opts().daily_goal)
  message(table.concat(lines, "\n"))
end

--- Mark the current focus (or `skill`) as already known and pick the next one.
---@param skill? string
function M.skip(skill)
  local st = load_state()
  skill = skill or M.ensure_focus()[1]
  if not skill or not M.lesson(skill) then
    message("Nothing to skip")
    return
  end
  st.learned[skill] = today()
  st.focus_day = nil
  save_state()
  M.refresh()
  local next_focus = M.focus()[1]
  message(("Marked %s as known.%s"):format(
    M.lesson(skill).title,
    next_focus and ("\nNew focus: %s (%s)\n%s"):format(next_focus.title, next_focus.short, next_focus.tip) or ""
  ))
end

--- Forget all learning progress (the daily stats are kept).
function M.reset()
  state = { focus = {}, learned = {}, relapsed = {}, done = {} }
  save_state()
  M.refresh()
  message("Learning progress reset")
end

local ICONS = { learned = "✓", relapsed = "↺", learning = "·", new = " " }

---@param n integer
---@param of integer
local function bar(n, of)
  local filled = math.min(10, math.floor(n / math.max(of, 1) * 10))
  return string.rep("▓", filled) .. string.rep("░", 10 - filled)
end

--- Lines for the learning panel.
---@return string[] lines, assistant.Highlight[] highlights
function M.panel()
  local o = opts()
  local focus = {}
  for _, f in ipairs(M.focus()) do
    focus[f.skill] = f
  end
  local lines, hls = {}, {}
  local function add(text, group)
    lines[#lines + 1] = text
    if group then
      hls[#hls + 1] = { line = #lines - 1, col = 0, end_col = #text, group = group }
    end
  end
  local lessons = M.lessons()
  local learned = 0
  for _, l in ipairs(lessons) do
    learned = learned + ((l.status == "learned") and 1 or 0)
  end
  add(("Learning path: %d of %d learned"):format(learned, #lessons), "Title")
  add("")
  for _, l in ipairs(lessons) do
    local f = focus[l.skill]
    local icon = f and "★" or ICONS[l.status]
    local detail
    if f then
      detail = ("%s %d/%d today%s"):format(bar(f.today, f.goal), f.today, f.goal, f.done and " ✓" or "")
    elseif l.status == "learned" then
      detail = "learned"
    elseif l.status == "relapsed" then
      detail = ("old habit back: %d times in %d days"):format(l.slips, o.relapse_days)
    elseif l.status == "learning" then
      detail = ("%d uses on %d days (learned at %d on %d)"):format(l.uses, l.days, o.learned_uses, o.learned_days)
    else
      detail = "not used yet"
    end
    local text = ("%s %-20s %-8s %s"):format(icon, l.title, l.short, detail)
    add(text, f and "Special" or (l.status == "learned" and "DiagnosticOk") or (l.status == "relapsed" and "DiagnosticWarn") or nil)
  end
  for _, f in pairs(focus) do
    add("")
    add("★ " .. f.title, "Title")
    add("  " .. f.tip)
  end
  add("")
  add("`:Assistant learn skip` marks the focus as known · `:Assistant report` for trends", "Comment")
  return lines, hls
end

--- Open the learning panel.
function M.open()
  local lines, hls = M.panel()
  require("assistant.ui").float(lines, hls, { title = "Learning path", filetype = "assistant_learn" })
end

--- Add a short learning summary to the report.
---@param lines string[]
---@param hls assistant.Highlight[]
function M.append_summary(lines, hls)
  if not opts().enabled then
    return
  end
  local learned = 0
  for _, l in ipairs(M.lessons()) do
    learned = learned + ((l.status == "learned") and 1 or 0)
  end
  lines[#lines + 1] = ""
  lines[#lines + 1] = "Learning path"
  hls[#hls + 1] = { line = #lines - 1, col = 0, end_col = #lines[#lines], group = "Title" }
  lines[#lines + 1] = ("  %d of %d skills learned"):format(learned, #M.LESSONS)
  for _, f in ipairs(M.focus()) do
    lines[#lines + 1] = ("  ★ Today: %s (%s) %d/%d"):format(f.title, f.short, f.today, f.goal)
  end
end

function M.start()
  state = nil -- the path may have changed
  if not opts().enabled then
    return
  end
  M.refresh()
  vim.defer_fn(M.announce, opts().announce_delay)
end

return M
