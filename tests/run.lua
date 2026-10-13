-- Run with: nvim --headless -u NONE -l tests/run.lua
vim.opt.rtp:prepend(vim.fn.getcwd())

local shown = {}
local errors = {}
local notify = vim.notify
vim.notify = function(msg, level, ...)
  if level == vim.log.levels.ERROR then
    errors[#errors + 1] = msg
  end
  return notify(msg, level, ...)
end

-- Never touch the real stats file.
local stats_path = vim.fn.tempname() .. "/stats.json"

local function setup(opts)
  require("assistant").setup(vim.tbl_deep_extend("force", {
    debug = true,
    stats = { path = stats_path },
    delay = 20,
    cooldown = { global = 0, rule = 0 },
    notify = function(msg)
      shown[#shown + 1] = msg
    end,
  }, opts or {}))
end

local failures, total = 0, 0

---@param name string
---@param lines string[]
---@param cursor integer[]
---@param keys string
---@param expect string? Lua pattern the hint must match, or nil for "no hint"
---@param before? fun() Extra setup (registers, options) before the keys are typed
local function case(name, lines, cursor, keys, expect, before)
  total = total + 1
  setup()
  shown = {}
  vim.api.nvim_buf_set_lines(0, 0, -1, false, lines)
  vim.api.nvim_win_set_cursor(0, cursor)
  vim.bo.commentstring = ""
  if before then
    before()
  end
  vim.api.nvim_feedkeys(vim.keycode(keys), "tx", false)
  vim.wait(200, function()
    return #shown > 0
  end)
  local got = shown[1]
  local ok = (expect == nil and got == nil) or (expect ~= nil and got ~= nil and got:find(expect) ~= nil)
  if not ok then
    failures = failures + 1
    io.stdout:write(("FAIL %s\n  expected: %s\n  got: %s"):format(name, expect or "<no hint>", got or "<no hint>"), "\n")
  else
    io.stdout:write("ok   " .. name, "\n")
  end
end

local para = { "one", "two", "three", "four", "five", "", "seven" }

case("jjjj suggests a count", para, { 1, 0 }, "jjjj", "`4j`")
case("jjjjj onto a blank line suggests }", para, { 1, 0 }, "jjjjj", "`}`")
case("kkkk onto a blank line suggests {", { "a", "", "c", "d", "e", "f" }, { 6, 0 }, "kkkk", "`{`")
case("3 j's stays quiet", para, { 1, 0 }, "jjj", nil)
case("counted 4j stays quiet", para, { 1, 0 }, "4j", nil)
case("j as an f-argument is not a motion", para, { 1, 0 }, "fjjjj", nil)
case("j inside insert mode is text", para, { 1, 0 }, "ijjjjjj<Esc>", nil)
case("j at the end of the buffer stays quiet", para, { 7, 0 }, "jjjj", nil)

case("llll to ( suggests f(", { "print(value)" }, { 1, 0 }, "lllll", "`f%(`")
case("llll to a word start suggests w", { "local x = foo(bar)" }, { 1, 0 }, "llllll", "`w`")
case("llll to the end suggests $", { "abcdef" }, { 1, 0 }, "lllll", "`%$`")
case("hhhh to column 0 suggests 0", { "abcdef" }, { 1, 5 }, "hhhhh", "`0`")
case("hhhh to a word start suggests b", { "foo bar bazzzz" }, { 1, 13 }, "hhhhh", "`b`")

case("$a suggests A", { "abc" }, { 1, 0 }, "$ax<Esc>", "`A`")
case("^i suggests I", { "  abc" }, { 1, 4 }, "^ix<Esc>", "`I`")
case("d$ suggests D", { "abc def" }, { 1, 2 }, "d$", "`D`")
case("dwi suggests cw", { "abc def" }, { 1, 0 }, "dwix<Esc>", "`cw`")
case("ci( is not mistaken for anything", { "f(abc)" }, { 1, 3 }, "ci(x<Esc>", nil)

case("xxxx suggests a count", { "abcdefgh" }, { 1, 0 }, "xxxx", "`4x`")
case("dd dd dd suggests 3dd", para, { 1, 0 }, "dddddd", "`3dd`")
case("2dd dd stays quiet", para, { 1, 0 }, "2dddd", nil)

case("arrows in insert mode", { "abc" }, { 1, 0 }, "i<Right><Right><Right>x<Esc>", "insert mode")
case("arrows in normal mode", { "abc", "def" }, { 1, 0 }, "<Down><Up>", "`k`")
case("backspace streak suggests <C-w>", { "" }, { 1, 0 }, "ihello world<BS><BS><BS><BS><BS><BS><Esc>", "<C%-w>")

case("bcw suggests ciw", { "hello world" }, { 1, 8 }, "bcwfoo<Esc>", "`ciw`")
case("<Esc>pa suggests <C-r>\"", { "" }, { 1, 0 }, "ifoo<Esc>pax<Esc>", '<C%-r>"', function()
  vim.fn.setreg('"', "zz")
end)

-- Search and substitute
local function search_reg(pat)
  return function()
    vim.fn.setreg("/", pat)
  end
end
case("/word under cursor suggests *", { "foo bar", "baz foo" }, { 1, 0 }, "/foo<CR>", "`%*`")
case("/\\<word\\> under cursor suggests *", { "foo bar", "baz foo" }, { 1, 0 }, "/\\<foo\\><CR>", "`%*`")
case("/x on the same line suggests fx", { "abc x def" }, { 1, 0 }, "/x<CR>", "`fx`")
case("/x on another line stays quiet", { "abc", "x" }, { 1, 0 }, "/x<CR>", nil)
case("same :s line by line suggests :%s", { "foo", "foo", "foo" }, { 1, 0 }, ":s/foo/bar/<CR>j:s/foo/bar/<CR>j:s/foo/bar/<CR>", "g&")
case("ranged :s stays quiet", { "x", "foo", "foo" }, { 1, 0 }, ":%s/foo/bar/<CR>", nil, search_reg("zzz"))
case(":s with the last search suggests an empty pattern", { "x", "foo" }, { 1, 0 }, "/foo<CR>:%s/foo/bar/g<CR>", "Leave it empty")
case(":s with the word under cursor suggests <C-r><C-w>", { "foo bar" }, { 1, 0 }, ":%s/foo/baz/g<CR>", "<C%-r><C%-w>", search_reg("zzz"))
case(":s with <C-r><C-w> stays quiet", { "foo bar" }, { 1, 0 }, ":%s/<C-r><C-w>/baz/g<CR>", nil, search_reg("zzz"))
case(":e # suggests <C-^>", { "x" }, { 1, 0 }, ":e #<CR>", "<C%-^>")

-- Registers
case("yank, delete, paste, undo suggests \"0p", { "aaa bbb ccc" }, { 1, 0 }, "yiwwdwpu", '"0p')
case("re-yank after visual paste suggests v_P", { "aaa bbb ccc" }, { 1, 0 }, "yiwwviwp0yiw", "`P` in visual mode")
case("re-yank after delete suggests the black hole", { "aaa bbb ccc" }, { 1, 0 }, "yiwwdw0yiw", '`"_d')
case("visual paste twice, then undo suggests v_P", { "aaa bbb ccc" }, { 1, 0 }, "yiwwviwpwviwpu", "`P` in visual mode")
case("\"0p then undo stays quiet", { "aaa bbb ccc" }, { 1, 0 }, 'yiwwdw"0pu', nil)

-- Text objects
case('dt" inside quotes suggests di"', { 'say "hello" now' }, { 1, 5 }, 'dt"', '`di"`')
case("df) from ( suggests da(", { "x(abc) y" }, { 1, 0 }, "f(df)", "`da%(`")
case("Vjjd over a paragraph suggests dip", { "a", "b", "c", "", "d" }, { 1, 0 }, "Vjjd", "`dip`")
case('di" stays quiet', { 'say "hello" now' }, { 1, 6 }, 'di"', nil)

-- Surround
case("wrapping a word by hand suggests surround", { "foo bar" }, { 1, 4 }, 'i"<Esc>ea"<Esc>', 'wrapped `bar`.*ciw"<C%-r>""')
case("wrapping with nvim-surround installed suggests ysiw", { "foo bar" }, { 1, 4 }, "i(<Esc>ea)<Esc>", "`ysiw%)`", function()
  package.loaded["nvim-surround"] = true
end)
package.loaded["nvim-surround"] = nil
case("deleting a pair by hand suggests ds", { 'say "hi" now' }, { 1, 4 }, 'xf"x', "`ds\"`", function()
  package.loaded["nvim-surround"] = true
end)
package.loaded["nvim-surround"] = nil
case("replacing a pair with r suggests cs", { 'say "hi" now' }, { 1, 4 }, "r'f\"r'", "`cs\"'`", function()
  package.loaded["nvim-surround"] = true
end)
package.loaded["nvim-surround"] = nil
case("mini.surround mappings are used", { "foo bar" }, { 1, 4 }, "i(<Esc>ea)<Esc>", "`saiw%)`", function()
  package.loaded["mini.surround"] = true
end)
package.loaded["mini.surround"] = nil

-- Comments
local function cstring()
  vim.bo.commentstring = "// %s"
end
case("typing // suggests gcc", { "foo" }, { 1, 0 }, "I// <Esc>", "`gcc`", cstring)
case("typing // on 3 lines suggests gc2j", { "a", "b", "c" }, { 1, 0 }, "I// <Esc>jI// <Esc>jI// <Esc>", "`gc2j`", cstring)
case("deleting // suggests gcc", { "// foo" }, { 1, 0 }, "3x", "gcc", cstring)

-- Selections
case("viwy suggests yiw", { "foo bar" }, { 1, 0 }, "viwy", "`yiw`")
case("vey suggests ye", { "foo bar" }, { 1, 0 }, "vey", "`ye`")
case("Vjd suggests dj", { "a", "b", "c" }, { 1, 0 }, "Vjd", "`d1j`")
case("same insert on 3 lines suggests block insert", { "a", "b", "c" }, { 1, 0 }, "I- <Esc>jI- <Esc>jI- <Esc>", "<C%-v>.*I%- <Esc>")
case("same append on 3 lines suggests $A", { "a", "bb", "c" }, { 1, 0 }, "A;<Esc>jA;<Esc>jA;<Esc>", "%$A;")

-- Repetition
case("same change twice suggests .", { "foo", "x", "foo" }, { 1, 0 }, "ciwbar<Esc>jjciwbar<Esc>", "`%.` repeats")
case("same change after n suggests cgn", { "foo x foo" }, { 1, 0 }, "ciwbar<Esc>nciwbar<Esc>", "`cgnbar", search_reg("foo"))
case("ciw + . stays quiet", { "foo", "x", "foo" }, { 1, 0 }, "ciwbar<Esc>jj.", nil)
case("repeated key sequence suggests a macro", { "a,b", "c,d", "e,f", "g,h" }, { 1, 0 }, "0f,xj0f,xj0f,xj", "qq0f,xjq")
case("n dd n dd suggests :g", { "foo", "x", "foo", "y", "foo", "z", "foo" }, { 2, 0 }, "nddnddndd", ":g/foo/d", search_reg("foo"))
case("j. j. j. suggests :norm .", { "a", "b", "c", "d" }, { 1, 0 }, "A!<Esc>j.j.j.", ":norm %.")
case("n. n. n. stays quiet", { "foo", "foo", "foo", "foo" }, { 1, 0 }, "ciwbar<Esc>n.n.n.", nil, search_reg("foo"))

-- Jumps
local twenty = {}
for i = 1, 20 do
  twenty[i] = "line " .. i
end
case("G then k back suggests <C-o>", twenty, { 10, 0 }, "Gkkkkkkkkkk", "<C%-o>")
case("gg then jjjj suggests NG", twenty, { 10, 0 }, "ggjjjj", "`5G`")

-- Cooldowns: the second hint is suppressed by the global cooldown.
total = total + 1
setup({ cooldown = { global = 60 } })
shown = {}
vim.api.nvim_buf_set_lines(0, 0, -1, false, para)
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.api.nvim_feedkeys("jjjj", "tx", false)
vim.wait(100, function() return false end)
vim.api.nvim_feedkeys("kkkk", "tx", false)
vim.wait(100, function() return false end)
if #shown == 1 then
  io.stdout:write("ok   global cooldown suppresses the second hint", "\n")
else
  failures = failures + 1
  io.stdout:write(("FAIL global cooldown: %d hints shown"):format(#shown), "\n")
end

-- streak_gap: a pause longer than the gap splits `jj … jj` into two short streaks.
total = total + 1
setup({ delay = 300, streak_gap = 30 })
shown = {}
vim.api.nvim_buf_set_lines(0, 0, -1, false, para)
vim.api.nvim_win_set_cursor(0, { 1, 0 })
vim.api.nvim_feedkeys("jj", "tx", false)
vim.wait(80, function() return false end)
vim.api.nvim_feedkeys("jj", "tx", false)
vim.wait(500, function() return false end)
if #shown == 0 then
  io.stdout:write("ok   streak_gap splits slow key runs", "\n")
else
  failures = failures + 1
  io.stdout:write("FAIL streak_gap: got " .. shown[1], "\n")
end

-- Generic check helper for the non-hint tests below.
local function check(name, ok, detail)
  total = total + 1
  if ok then
    io.stdout:write("ok   " .. name, "\n")
  else
    failures = failures + 1
    io.stdout:write(("FAIL %s\n  %s"):format(name, detail or ""), "\n")
  end
end
local function today()
  return os.date("%Y-%m-%d")
end

-- Stats: skills and habits are counted and saved, and saves merge.
do
  local stats = require("assistant.stats")
  setup()
  local before = vim.deepcopy(stats.load()[today()] or { skills = {}, rules = {} })
  vim.api.nvim_buf_set_lines(0, 0, -1, false, para)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.api.nvim_feedkeys(vim.keycode("3jggciwx<Esc>"), "tx", false)
  stats.save()
  vim.api.nvim_feedkeys("jjjj", "tx", false)
  vim.wait(100, function() return false end)
  stats.save()
  local after = stats.load()[today()]
  check("stats count skills", (after.skills.counts or 0) == (before.skills.counts or 0) + 1
    and (after.skills.textobjects or 0) == (before.skills.textobjects or 0) + 1, vim.inspect(after.skills))
  check("stats count habits across saves", after.rules.vertical and after.rules.vertical.noticed == ((before.rules.vertical or {}).noticed or 0) + 1, vim.inspect(after.rules))
  check("stats file is written", vim.fn.filereadable(stats_path) == 1, stats_path)
end

-- Report: trends, untried skills, sparkline.
do
  local report = require("assistant.report")
  local now = os.time({ year = 2026, month = 10, day = 14, hour = 12 })
  local function d(offset)
    return os.date("%Y-%m-%d", now - offset * 86400)
  end
  local days = {
    [d(0)] = { keys = 1000, hjkl = 100, rules = { vertical = { noticed = 2, shown = 1 } }, skills = { counts = 30 } },
    [d(9)] = { keys = 1000, hjkl = 400, rules = { vertical = { noticed = 10, shown = 3 } }, skills = { counts = 5 } },
  }
  local lines = table.concat(report.build(days, 7, now), "\n")
  check("report shows habit trend", lines:find("jjjj / kkkk[^\n]+2[^\n]+10[^\n]+▼ 80%%") ~= nil, lines)
  check("report shows skill trend", lines:find("Counted motions[^\n]+30[^\n]+5[^\n]+▲ 500%%") ~= nil, lines)
  check("report shows hjkl share", lines:find("h/j/k/l presses[^\n]+10[^\n]+40") ~= nil, lines)
  check("report lists untried skills", lines:find("Not tried yet.*Text objects") ~= nil, lines)
  check("report has a sparkline", lines:find("█") ~= nil, lines)
  check("empty report says so", table.concat(report.build({}, 7, now), "\n"):find("No data yet") ~= nil)
  setup()
  local ok, err = pcall(report.open, 7)
  local ft = vim.bo.filetype
  if ok then
    vim.cmd.close()
  end
  check("report window opens", ok and ft == "assistant_report", tostring(err))
end

-- Ghost text.
do
  local live = vim.api.nvim_create_namespace("assistant.ghost.live")
  local hint = vim.api.nvim_create_namespace("assistant.ghost.hint")
  local function marks(ns)
    return vim.api.nvim_buf_get_extmarks(0, ns, 0, -1, { details = true })
  end
  local function virt(ns)
    local texts = {}
    for _, m in ipairs(marks(ns)) do
      for _, line in ipairs(m[4].virt_lines or { m[4].virt_text }) do
        for _, chunk in ipairs(line) do
          texts[#texts + 1] = chunk[1]
        end
      end
    end
    return table.concat(texts, "|")
  end

  setup({ delay = 5000 })
  vim.api.nvim_buf_set_lines(0, 0, -1, false, { "local x = foo(bar) + baz" })
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.api.nvim_feedkeys("ll", "tx", false)
  vim.wait(20, function() return false end)
  local text = virt(live)
  check("live targets for l", text:find("w") and text:find("2w") and text:find("%$"), text)
  vim.api.nvim_feedkeys("w", "tx", false)
  vim.wait(20, function() return false end)
  check("live targets clear on another key", #marks(live) == 0, virt(live))

  vim.api.nvim_buf_set_lines(0, 0, -1, false, para)
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.wo.relativenumber = false
  vim.api.nvim_feedkeys("jj", "tx", false)
  vim.wait(20, function() return false end)
  text = virt(live)
  check("live targets for j", text:find("}") and text:find("3j"), text)
  vim.wo.relativenumber = true
  vim.api.nvim_feedkeys("j", "tx", false)
  vim.wait(20, function() return false end)
  text = virt(live)
  check("relativenumber hides j counts", text:find("}") and not text:find("%dj"), text)
  vim.wo.relativenumber = false

  setup({ display = "ghost" })
  shown = {}
  vim.api.nvim_win_set_cursor(0, { 1, 0 })
  vim.api.nvim_feedkeys("jjjj", "tx", false)
  vim.wait(200, function() return #marks(hint) > 0 end)
  text = virt(hint)
  check("display = ghost shows the hint as virtual text", text:find("4j") ~= nil and #shown == 0, text)
end

for _, err in ipairs(errors) do
  failures = failures + 1
  io.stdout:write("ERROR " .. err, "\n")
end

io.stdout:write(("\n%d/%d passed"):format(total - failures, total), "\n")
os.exit(failures == 0 and 0 or 1)
