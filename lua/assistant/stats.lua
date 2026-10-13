local config = require("assistant.config")
local util = require("assistant.util")

--- Usage statistics, persisted per day so `:Assistant report` can show trends.
---
--- Only counts are stored (no text, file names or keys typed in insert mode). Counts
--- are buffered in memory and merged into the file on save, so several Neovim
--- instances can share one stats file.
local M = {}

---@class assistant.Day
---@field keys integer Keys typed in normal/visual mode
---@field hjkl integer Plain `h`/`j`/`k`/`l` presses (no count)
---@field rules table<string, { noticed: integer, shown: integer }>
---@field skills table<string, integer>

--- Motions and commands worth learning, in the order the report lists them.
M.SKILLS = {
  { name = "counts", desc = "Counted motions (5j, 3w)" },
  { name = "words", desc = "Word motions (w b e)" },
  { name = "char_jumps", desc = "Character jumps (f t ; ,)" },
  { name = "paragraphs", desc = "Paragraph jumps ({ })" },
  { name = "scrolling", desc = "Scrolling (<C-d> <C-u>)" },
  { name = "search", desc = "Search (/ * # n N)" },
  { name = "jumps", desc = "Jump list (<C-o> <C-i> %)" },
  { name = "line_shortcuts", desc = "Line shortcuts (A I C D S)" },
  { name = "textobjects", desc = "Text objects (ciw di( yap)" },
  { name = "dot", desc = "Dot repeat (.)" },
  { name = "registers", desc = 'Registers ("0p "_d "ay)' },
  { name = "comments", desc = "Comment toggling (gc)" },
  { name = "block", desc = "Visual block (<C-v>)" },
  { name = "substitute", desc = "Substitute (:s :%s)" },
  { name = "global", desc = "Global commands (:g :norm)" },
  { name = "macros", desc = "Macros (q @)" },
}

local KEY_SKILLS = {
  w = "words", b = "words", e = "words", W = "words", B = "words", E = "words",
  f = "char_jumps", F = "char_jumps", t = "char_jumps", T = "char_jumps", [";"] = "char_jumps", [","] = "char_jumps",
  ["{"] = "paragraphs", ["}"] = "paragraphs",
  ["<C-D>"] = "scrolling", ["<C-U>"] = "scrolling", ["<C-F>"] = "scrolling", ["<C-B>"] = "scrolling",
  ["*"] = "search", ["#"] = "search", n = "search", N = "search",
  ["<C-O>"] = "jumps", ["<C-I>"] = "jumps", ["<Tab>"] = "jumps", ["%"] = "jumps",
  A = "line_shortcuts", I = "line_shortcuts", C = "line_shortcuts", D = "line_shortcuts", S = "line_shortcuts",
  ["."] = "dot",
  ["<C-V>"] = "block",
}
local COUNTABLE = { j = true, k = true, w = true, b = true, e = true, W = true, B = true, E = true, x = true, d = true, y = true, c = true }
local HJKL = { h = true, j = true, k = true, l = true }

--- Which skill (if any) an event shows the user using.
---@param ev assistant.Event
---@return string?
function M.classify(ev)
  if ev.key == "<Cmd>" then
    if ev.aborted then
      return nil
    end
    if ev.cmdtype ~= ":" then
      return "search"
    end
    local ok, cmd = pcall(vim.api.nvim_parse_cmd, ev.cmdline, {})
    if not ok then
      return nil
    end
    if cmd.cmd == "substitute" or cmd.cmd == "&" or cmd.cmd == "&&" then
      return "substitute"
    elseif cmd.cmd == "global" or cmd.cmd == "vglobal" or cmd.cmd == "normal" then
      return "global"
    end
    return nil
  end
  if util.is_side(ev) or util.is_pause(ev) or ev.count_digit then
    return nil
  end
  if ev.textobj then
    return "textobjects"
  end
  if ev.arg then
    if ev.arg_of == "g" and ev.key == "c" then
      return "comments"
    elseif ev.arg_of == '"' then
      return "registers"
    elseif (ev.arg_of == "q" or ev.arg_of == "@") and ev.key ~= ":" then
      return "macros"
    end
    return nil
  end
  if not util.is_command_mode(ev.mode) then
    return nil
  end
  if ev.counted and COUNTABLE[ev.key] then
    return "counts"
  end
  return KEY_SKILLS[ev.key]
end

---@type table<string, assistant.Day> Not yet saved
local pending = {}
---@type table<string, assistant.Day>? What was on disk at the last read or save
local saved
local dirty = false
local timer ---@type uv.uv_timer_t?
local group = vim.api.nvim_create_augroup("assistant.stats", { clear = true })

---@param day? string
---@return assistant.Day
local function bucket(day)
  day = day or os.date("%Y-%m-%d") --[[@as string]]
  pending[day] = pending[day] or { keys = 0, hjkl = 0, rules = {}, skills = {} }
  dirty = true
  return pending[day]
end

--- Record a tracked event (keys, commands).
---@param ev assistant.Event
function M.record(ev)
  if not config.options.stats.enabled then
    return
  end
  if not util.is_side(ev) and not util.is_pause(ev) and ev.key ~= "<Cmd>" and util.is_command_mode(ev.mode) then
    local day = bucket()
    day.keys = day.keys + 1
    if HJKL[ev.key] and util.is_plain(ev) then
      day.hjkl = day.hjkl + 1
    end
  end
  local skill = M.classify(ev)
  if skill then
    local day = bucket()
    day.skills[skill] = (day.skills[skill] or 0) + 1
    require("assistant.learn").on_skill(skill)
  end
end

--- Record that a rule noticed a habit (`field = "noticed"`) or showed a hint (`"shown"`).
---@param rule string
---@param field "noticed"|"shown"
function M.rule(rule, field)
  if not config.options.stats.enabled then
    return
  end
  local day = bucket()
  day.rules[rule] = day.rules[rule] or { noticed = 0, shown = 0 }
  day.rules[rule][field] = day.rules[rule][field] + 1
end

local function path()
  return config.options.stats.path or (vim.fn.stdpath("data") .. "/assistant/stats.json")
end

---@return table<string, assistant.Day>
local function read()
  local f = io.open(path(), "r")
  if not f then
    return {}
  end
  local content = f:read("*a")
  f:close()
  local ok, data = pcall(vim.json.decode, content)
  return ok and type(data) == "table" and type(data.days) == "table" and data.days or {}
end

---@param into assistant.Day
---@param from assistant.Day
local function merge_day(into, from)
  into.keys = (into.keys or 0) + (from.keys or 0)
  into.hjkl = (into.hjkl or 0) + (from.hjkl or 0)
  into.rules = into.rules or {}
  for name, r in pairs(from.rules or {}) do
    local t = into.rules[name] or { noticed = 0, shown = 0 }
    t.noticed, t.shown = t.noticed + (r.noticed or 0), t.shown + (r.shown or 0)
    into.rules[name] = t
  end
  into.skills = into.skills or {}
  for name, n in pairs(from.skills or {}) do
    into.skills[name] = (into.skills[name] or 0) + n
  end
end

---@return table<string, assistant.Day>
local function saved_days()
  saved = saved or read()
  return saved
end

--- All days: what's on disk plus what hasn't been saved yet.
---@return table<string, assistant.Day>
function M.load()
  local days = vim.deepcopy(saved_days())
  for day, data in pairs(pending) do
    days[day] = days[day] or { keys = 0, hjkl = 0, rules = {}, skills = {} }
    merge_day(days[day], data)
  end
  return days
end

--- Merge unsaved counts into the stats file.
function M.save()
  if not dirty then
    return
  end
  -- Re-read the file to pick up counts saved by other Neovim instances.
  saved = nil
  local days = M.load()
  -- Drop old days.
  local cutoff = os.date("%Y-%m-%d", os.time() - config.options.stats.keep_days * 86400)
  for day in pairs(days) do
    if day < cutoff then
      days[day] = nil
    end
  end
  local file = path()
  vim.fn.mkdir(vim.fn.fnamemodify(file, ":h"), "p")
  local tmp = file .. ".tmp"
  local f = io.open(tmp, "w")
  if not f then
    return
  end
  f:write(vim.json.encode({ version = 1, days = days }))
  f:close()
  os.rename(tmp, file)
  saved, pending, dirty = days, {}, false
end

--- How often a skill was used today (saved and unsaved).
---@param skill string
function M.count_today(skill)
  local day = os.date("%Y-%m-%d") --[[@as string]]
  local s, p = saved_days()[day], pending[day]
  return (s and s.skills and s.skills[skill] or 0) + (p and p.skills[skill] or 0)
end

function M.start()
  saved = nil -- the path may have changed
  if not config.options.stats.enabled then
    return
  end
  vim.api.nvim_clear_autocmds({ group = group })
  vim.api.nvim_create_autocmd("VimLeavePre", { group = group, callback = M.save })
  timer = timer or assert(vim.uv.new_timer())
  timer:stop()
  local every = config.options.stats.save_interval * 1000
  timer:start(every, every, vim.schedule_wrap(M.save))
end

function M.stop()
  M.save()
  vim.api.nvim_clear_autocmds({ group = group })
  if timer then
    timer:stop()
  end
end

return M
