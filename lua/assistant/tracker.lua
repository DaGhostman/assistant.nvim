local config = require("assistant.config")
local ghost = require("assistant.ghost")
local stats = require("assistant.stats")
local notifier = require("assistant.notifier")
local rules = require("assistant.rules")
local util = require("assistant.util")

local M = {}

---@class assistant.Event
---@field key string Key as typed by the user (`keytrans` form), or a marker:
---  "<Idle>" / "<Gap>" (pauses), "<Cmd>" (a `:`, `/` or `?` command line),
---  "<Insert>" (text inserted in insert mode), "<Yank>" (text yanked, deleted or changed)
---@field mode string Mode the key was pressed in
---@field pos integer[] Cursor position before the key: { row (1-based), col (0-based byte) }
---@field buf integer
---@field win integer
---@field time integer `vim.uv.now()` when the key was pressed
---@field counted? boolean A count was typed before this key (`5j`)
---@field count_digit? boolean This key is part of a count
---@field arg? boolean This key is the argument of the previous key (`fx`, `rx`, `"a`, `ci(`)
---@field arg_of? string The key this argument belongs to
---@field textobj? boolean This key starts a text object (`i`/`a` in `di(`, `vaw`)
---@field replaced? string For `r{char}`: the character that was replaced
---@field pum? boolean The completion popup was visible
---@field is_repeat? boolean `<Insert>` / `<Yank>` caused by `.`
---
--- `<Cmd>` events:
---@field cmdtype? string ":", "/" or "?"
---@field cmdline? string
---@field aborted? boolean
---@field cmd_keys? string[] Keys typed on the command line
---@field cword? string Word under the cursor when the command line was opened
---@field search_reg? string Last search pattern when the command line was opened
---
--- `<Insert>` events:
---@field inserted? string Text added (single-line inserts only)
---@field removed? string Text removed while inserting (backspace)
---@field multiline? boolean The insert spanned several lines
---@field enter_key? string Key that started insert mode (`i`, `A`, `o`, `w` for `cw`, …)
---
--- `<Yank>` events (also deletes and changes):
---@field operator? string "y", "d" or "c"
---@field text? string
---@field regtype? string
---@field regname? string
---@field visual? boolean
---@field line? string The first affected line, before the change
---@field range? integer[] { start row, start col, end row, end col } (end col inclusive)

local MAX_HISTORY = 300

--- Keys that consume the next key as an argument (or form a two-key command).
local ARG_KEYS = {
  f = true, F = true, t = true, T = true, r = true, m = true, q = true,
  ["'"] = true, ["`"] = true, ['"'] = true, ["@"] = true,
  g = true, z = true, ["["] = true, ["]"] = true, ["<C-W>"] = true,
}

local ns = vim.api.nvim_create_namespace("assistant")
local group = vim.api.nvim_create_augroup("assistant", { clear = true })

---@type assistant.Event[]
local history = {}
local counting = false
local arg_for ---@type string? Key waiting for its argument
local timer ---@type uv.uv_timer_t?
local excluded_ft, excluded_bt = {}, {}
local cmd_state ---@type { typed: boolean, keys: string[], cword: string, search_reg: string, pos: integer[] }?
local insert_state ---@type { row: integer, line: string, lines: integer, enter_key: string?, is_repeat: boolean }?

local function reset()
  history = {}
  counting, arg_for = false, nil
  cmd_state, insert_state = nil, nil
end

local function excluded()
  return excluded_ft[vim.bo.filetype] or excluded_bt[vim.bo.buftype]
end

---@param ev assistant.Event
local function annotate(ev)
  -- Checked before the mode: Neovim reports mode "R" while `r` waits for its char.
  if arg_for then
    ev.arg, ev.arg_of, arg_for = true, arg_for, nil
    if ev.arg_of == "r" then
      ev.replaced = util.char_at(util.get_line(ev.buf, ev.pos[1]) or "", ev.pos[2])
    end
    return
  end
  if not util.is_command_mode(ev.mode) then
    counting = false
    return
  end
  local key = ev.key
  if key:match("^%d$") and (key ~= "0" or counting) then
    ev.count_digit, counting = true, true
  else
    ev.counted, counting = counting, false
    if ARG_KEYS[key] then
      -- `q` stops a recording without taking a register.
      if not (key == "q" and vim.fn.reg_recording() ~= "") then
        arg_for = key
      end
    elseif (key == "i" or key == "a") and (ev.mode:match("^no") or util.is_visual(ev.mode)) then
      ev.textobj, arg_for = true, key -- `di(`, `vaw`
    end
  end
end

---@param key string
---@return assistant.Event
local function make_event(key)
  local win = vim.api.nvim_get_current_win()
  return {
    key = key,
    mode = vim.api.nvim_get_mode().mode,
    pos = vim.api.nvim_win_get_cursor(win),
    buf = vim.api.nvim_get_current_buf(),
    win = win,
    time = vim.uv.now(),
    pum = vim.fn.pumvisible() == 1,
  }
end

--- Latest key event (pauses and side events skipped).
local function last_key()
  return util.find_back(history, function(ev)
    return not util.is_side(ev) and not util.is_pause(ev)
  end, nil, 20)
end

---@param ev assistant.Event
local function push(ev)
  history[#history + 1] = ev
  if #history > MAX_HISTORY then
    table.remove(history, 1)
  end
  stats.record(ev)
  for _, rule in ipairs(rules) do
    local opts = config.rule(rule.name)
    if opts.enabled ~= false then
      local ok, hint = pcall(rule.check, history, opts)
      if not ok and config.options.debug then
        vim.notify(("assistant: rule %s failed: %s"):format(rule.name, hint), vim.log.levels.ERROR)
      elseif ok and hint then
        hint.rule = rule.name
        notifier.queue(hint)
      end
    end
  end
end

local function restart_timer()
  if timer then
    timer:stop()
    timer:start(config.options.delay, 0, vim.schedule_wrap(M.on_idle))
  end
end

--- After `delay` ms without keys: close any running streaks and show a pending hint.
function M.on_idle()
  if vim.api.nvim_get_mode().mode:sub(1, 1) == "c" then
    return -- never interrupt typing a command; CmdlineLeave restarts the timer
  end
  ghost.clear_live()
  if not excluded() then
    push(make_event("<Idle>"))
  end
  notifier.flush()
end

---@param _ string
---@param typed string?
local function on_key(_, typed)
  -- Keys produced by mappings, macros or plugins have no `typed` value: only
  -- coach what the user actually pressed.
  if not typed or typed == "" then
    return
  end
  if excluded() then
    reset()
    return
  end
  local key = vim.fn.keytrans(typed)
  if vim.api.nvim_get_mode().mode:sub(1, 1) == "c" then
    if cmd_state then
      table.insert(cmd_state.keys, key)
    end
    if timer then
      timer:stop()
    end
    return
  end
  local ev = make_event(key)
  -- A long pause ends any running streak, even before the idle hint fires.
  local last = history[#history]
  if last and not util.is_pause(last) and ev.time - last.time > config.options.streak_gap then
    push(make_event("<Gap>"))
  end
  annotate(ev)
  push(ev)
  ghost.update(history)
  restart_timer()
end

local function on_cmdline_enter(args)
  local last = last_key()
  cmd_state = {
    -- Only command lines the user opened by typing `:`, `/` or `?` (not mappings).
    typed = last ~= nil and last.key == args.file and vim.uv.now() - last.time < 1000,
    keys = {},
    cword = vim.fn.expand("<cword>"),
    search_reg = vim.fn.getreg("/"),
    pos = vim.api.nvim_win_get_cursor(0),
  }
end

local function on_cmdline_leave()
  local state = cmd_state
  cmd_state = nil
  if not state or not state.typed or excluded() then
    return
  end
  local ev = make_event("<Cmd>")
  ev.pos = state.pos
  ev.mode = "c"
  ev.cmdtype = vim.fn.getcmdtype()
  ev.cmdline = vim.fn.getcmdline()
  ev.aborted = vim.v.event.abort
  ev.cmd_keys = state.keys
  ev.cword = state.cword
  ev.search_reg = state.search_reg
  push(ev)
  restart_timer()
end

local function on_insert_enter()
  local last = last_key()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  insert_state = {
    row = row,
    line = vim.api.nvim_get_current_line(),
    lines = vim.api.nvim_buf_line_count(0),
    enter_key = last and last.key,
    is_repeat = last ~= nil and last.key == ".",
  }
end

local function on_insert_leave()
  local state = insert_state
  insert_state = nil
  if not state or excluded() then
    return
  end
  local ev = make_event("<Insert>")
  ev.enter_key, ev.is_repeat = state.enter_key, state.is_repeat
  local after = vim.api.nvim_get_current_line()
  if ev.pos[1] ~= state.row or vim.api.nvim_buf_line_count(0) ~= state.lines then
    ev.multiline, ev.inserted, ev.removed = true, vim.fn.getreg("."), ""
  else
    -- Diff the line before and after to find what was inserted, and where.
    local before = state.line
    local p = 0
    while p < #before and p < #after and before:byte(p + 1) == after:byte(p + 1) do
      p = p + 1
    end
    local s = 0
    while s < #before - p and s < #after - p and before:byte(#before - s) == after:byte(#after - s) do
      s = s + 1
    end
    ev.inserted = after:sub(p + 1, #after - s)
    ev.removed = before:sub(p + 1, #before - s)
    ev.pos = { state.row, p }
  end
  push(ev)
end

local function on_yank()
  if excluded() then
    return
  end
  local e = vim.v.event
  local ev = make_event("<Yank>")
  local s, f = vim.api.nvim_buf_get_mark(0, "["), vim.api.nvim_buf_get_mark(0, "]")
  local last = last_key()
  ev.operator = e.operator
  ev.text = table.concat(e.regcontents, "\n")
  ev.regtype = e.regtype
  ev.regname = e.regname
  ev.visual = e.visual
  ev.range = { s[1], s[2], f[1], f[2] }
  ev.line = util.get_line(ev.buf, s[1])
  ev.is_repeat = last ~= nil and last.key == "."
  push(ev)
end

function M.start()
  excluded_ft, excluded_bt = {}, {}
  for _, ft in ipairs(config.options.excluded_filetypes) do
    excluded_ft[ft] = true
  end
  for _, bt in ipairs(config.options.excluded_buftypes) do
    excluded_bt[bt] = true
  end
  reset()
  timer = timer or assert(vim.uv.new_timer())
  vim.on_key(on_key, ns)
  vim.api.nvim_clear_autocmds({ group = group })
  vim.api.nvim_create_autocmd("CmdlineEnter", { group = group, callback = on_cmdline_enter })
  vim.api.nvim_create_autocmd("CmdlineLeave", { group = group, callback = on_cmdline_leave })
  vim.api.nvim_create_autocmd("InsertEnter", { group = group, callback = on_insert_enter })
  vim.api.nvim_create_autocmd("InsertLeave", { group = group, callback = on_insert_leave })
  vim.api.nvim_create_autocmd("TextYankPost", { group = group, callback = on_yank })
end

function M.stop()
  vim.on_key(nil, ns)
  vim.api.nvim_clear_autocmds({ group = group })
  if timer then
    timer:stop()
  end
  reset()
end

return M
