local config = require("assistant.config")
local util = require("assistant.util")

--- Ghost text: live motion targets while you repeat `hjkl`, and hints as virtual text.
local M = {}

local live_ns = vim.api.nvim_create_namespace("assistant.ghost.live")
local hint_ns = vim.api.nvim_create_namespace("assistant.ghost.hint")
local group = vim.api.nvim_create_augroup("assistant.ghost", { clear = true })
local live_buf ---@type integer?
local hint_buf ---@type integer?
local hint_timer ---@type uv.uv_timer_t?

local function highlights()
  vim.api.nvim_set_hl(0, "AssistantGhost", { link = "Comment", default = true })
  vim.api.nvim_set_hl(0, "AssistantGhostTarget", { link = "DiagnosticHint", default = true })
  vim.api.nvim_set_hl(0, "AssistantGhostHint", { link = "DiagnosticVirtualTextHint", default = true })
end

function M.clear_live()
  if live_buf and vim.api.nvim_buf_is_valid(live_buf) then
    vim.api.nvim_buf_clear_namespace(live_buf, live_ns, 0, -1)
  end
  live_buf = nil
end

function M.clear_hint()
  if hint_buf and vim.api.nvim_buf_is_valid(hint_buf) then
    vim.api.nvim_buf_clear_namespace(hint_buf, hint_ns, 0, -1)
  end
  hint_buf = nil
end

--- One line of labels at display columns, skipping labels that would overlap.
---@param labels { [1]: integer, [2]: string }[] { display column, text }
local function label_line(labels)
  table.sort(labels, function(a, b)
    return a[1] < b[1]
  end)
  local out, width = {}, 0
  for _, l in ipairs(labels) do
    if l[1] >= width then
      out[#out + 1] = string.rep(" ", l[1] - width) .. l[2]
      width = l[1] + #l[2] + 1
      out[#out + 1] = " "
    end
  end
  return table.concat(out)
end

--- Markers under the cursor line for where `w`, `2w`, … `$` (or `b`, `^`, `0`) land.
---@param buf integer
---@param win integer
---@param key "h"|"l"
local function draw_horizontal(buf, win, key)
  local row, col = unpack(vim.api.nvim_win_get_cursor(win))
  local line = util.get_line(buf, row) or ""
  local leftcol = vim.fn.winsaveview().leftcol
  local labels = {}
  local function add(byte, text)
    local dcol = vim.fn.strdisplaywidth(line:sub(1, byte)) - leftcol
    if dcol >= 0 then
      labels[#labels + 1] = { dcol, text }
    end
  end

  local words = util.words(line)
  if key == "l" then
    local n = 0
    for _, w in ipairs(words) do
      if w.s > col and n < 5 then
        n = n + 1
        add(w.s, n == 1 and "w" or n .. "w")
      end
    end
    local last = util.prev_col(line, #line)
    if last and last > col then
      add(last, "$")
    end
  else
    local n = 0
    for i = #words, 1, -1 do
      if words[i].s < col and n < 5 then
        n = n + 1
        add(words[i].s, n == 1 and "b" or n .. "b")
      end
    end
    local first = (line:find("%S") or 1) - 1
    if first < col then
      add(first, "^")
    end
    if first > 0 and col > 0 then
      add(0, "0")
    end
  end

  local text = label_line(labels)
  if text:match("%S") then
    vim.api.nvim_buf_set_extmark(buf, live_ns, row - 1, 0, {
      virt_lines = { { { text, "AssistantGhostTarget" } } },
    })
  end
end

--- Labels at the end of the lines below/above: `5j`, `}`, `<C-d>`.
---@param buf integer
---@param win integer
---@param key "j"|"k"
local function draw_vertical(buf, win, key)
  local row = vim.api.nvim_win_get_cursor(win)[1]
  local step = key == "j" and 1 or -1
  local top, bottom = vim.fn.line("w0", win), vim.fn.line("w$", win)
  local half = math.floor(vim.api.nvim_win_get_height(win) / 2)
  local counts = not vim.wo[win].relativenumber -- the number column already shows them
  local blank_found = false
  for d = 1, config.options.ghost.max_lines do
    local r = row + d * step
    if r < top or r > bottom then
      break
    end
    local parts = {}
    if not blank_found and util.get_line(buf, r) == "" then
      blank_found = true
      parts[#parts + 1] = key == "j" and "}" or "{"
    end
    if counts and d >= 2 then
      parts[#parts + 1] = d .. key
    end
    if d == half then
      parts[#parts + 1] = key == "j" and "<C-d>" or "<C-u>"
    end
    if #parts > 0 then
      vim.api.nvim_buf_set_extmark(buf, live_ns, r - 1, 0, {
        virt_text = { { "  " .. table.concat(parts, " "), "AssistantGhost" } },
        virt_text_pos = "eol",
      })
    end
  end
end

local DRAW = { h = draw_horizontal, l = draw_horizontal, j = draw_vertical, k = draw_vertical }

--- Called after every key: show live targets while a `hjkl` run is going on.
---@param history assistant.Event[]
function M.update(history)
  if not config.options.ghost.live then
    return
  end
  local last = history[#history]
  local key = last and last.key
  local n = 0
  if last and DRAW[key] and util.is_plain(last) then
    for i = #history, 1, -1 do
      local ev = history[i]
      if not util.is_side(ev) then
        if ev.key ~= key or not util.is_plain(ev) then
          break
        end
        n = n + 1
      end
    end
  end
  if n >= config.options.ghost.live_after then
    -- Draw after the key has moved the cursor.
    vim.schedule(function()
      M.clear_live()
      local buf, win = vim.api.nvim_get_current_buf(), vim.api.nvim_get_current_win()
      live_buf = buf
      pcall(DRAW[key], buf, win, key)
    end)
  elseif live_buf then
    vim.schedule(M.clear_live)
  end
end

--- Show a hint as virtual text at the end of the cursor line.
---@param hint assistant.Hint
function M.show_hint(hint)
  local short = hint.short or hint.msg:match("\n→ ([^\n]+)") or hint.msg:match("^[^\n]+")
  short = short:gsub("`", "")
  M.clear_hint()
  local buf = vim.api.nvim_get_current_buf()
  local row = vim.api.nvim_win_get_cursor(0)[1]
  hint_buf = buf
  vim.api.nvim_buf_set_extmark(buf, hint_ns, row - 1, 0, {
    virt_text = { { "  ‣ " .. short, "AssistantGhostHint" } },
    virt_text_pos = "eol",
    hl_mode = "combine",
  })
  hint_timer = hint_timer or assert(vim.uv.new_timer())
  hint_timer:stop()
  hint_timer:start(config.options.display_time or 5000, 0, vim.schedule_wrap(M.clear_hint))
end

function M.start()
  highlights()
  vim.api.nvim_clear_autocmds({ group = group })
  vim.api.nvim_create_autocmd("ColorScheme", { group = group, callback = highlights })
end

function M.stop()
  vim.api.nvim_clear_autocmds({ group = group })
  M.clear_live()
  M.clear_hint()
end

return M
