local M = {}

---@param mode string
function M.is_visual(mode)
  local c = mode:sub(1, 1)
  return c == "v" or c == "V" or c == "\22"
end

--- Normal, operator-pending or visual mode: the modes where keys are commands.
---@param mode string
function M.is_command_mode(mode)
  return mode:sub(1, 1) == "n" or M.is_visual(mode)
end

---@param mode string
function M.is_insert(mode)
  local c = mode:sub(1, 1)
  return c == "i" or c == "R"
end

--- Events that describe the result of keys rather than a key (`<Yank>`, `<Insert>`).
--- They never break up key sequences.
---@param ev assistant.Event
function M.is_side(ev)
  return ev.key == "<Yank>" or ev.key == "<Insert>"
end

--- Pause markers: `<Idle>` and `<Gap>`.
---@param ev assistant.Event
function M.is_pause(ev)
  return ev.key == "<Idle>" or ev.key == "<Gap>"
end

--- A key pressed as a standalone command in normal or visual mode: no count before
--- it, not part of a count, and not the argument of another command (`fj`, `rj`, `"j`).
---@param ev assistant.Event
function M.is_plain(ev)
  return not ev.arg and not ev.counted and not ev.count_digit and (ev.mode == "n" or M.is_visual(ev.mode))
end

--- The last `n` key events (side events skipped), oldest first.
---@param history assistant.Event[]
---@param n integer
---@param before? integer Only look at events before this index
---@return assistant.Event[]
function M.recent(history, n, before)
  local result = {}
  local i = (before or #history + 1) - 1
  while i >= 1 and #result < n do
    if not M.is_side(history[i]) then
      table.insert(result, 1, history[i])
    end
    i = i - 1
  end
  return result
end

--- The key event before the latest one.
---@param history assistant.Event[]
function M.prev(history)
  local last = history[#history]
  if not last or M.is_side(last) then
    return nil
  end
  return M.recent(history, 2)[1]
end

--- Length of the run of events matching `pred` that ended right before the latest
--- event. Returns 0 while the run is still going (the latest event matches too).
--- Side events inside the run are skipped.
---@param history assistant.Event[]
---@param pred fun(ev: assistant.Event): boolean
---@return integer count, integer index of the first event of the run
function M.ended_streak(history, pred)
  local last = history[#history]
  if not last or M.is_side(last) or pred(last) then
    return 0, 0
  end
  local n, first = 0, 0
  for i = #history - 1, 1, -1 do
    local ev = history[i]
    if not M.is_side(ev) then
      if not pred(ev) then
        break
      end
      n, first = n + 1, i
    end
  end
  return n, first
end

--- The last event before index `before` matching `pred`, and its index.
---@param history assistant.Event[]
---@param pred fun(ev: assistant.Event): boolean
---@param before? integer
---@param limit? integer Maximum number of events to look at
---@return assistant.Event?, integer?
function M.find_back(history, pred, before, limit)
  local stop = math.max(1, (before or #history + 1) - (limit or #history))
  for i = (before or #history + 1) - 1, stop, -1 do
    if pred(history[i]) then
      return history[i], i
    end
  end
end

---@param buf integer
---@param row integer 1-based
---@return string?
function M.get_line(buf, row)
  if not vim.api.nvim_buf_is_valid(buf) then
    return nil
  end
  return vim.api.nvim_buf_get_lines(buf, row - 1, row, false)[1]
end

--- The (possibly multibyte) character starting at byte `col` (0-based).
---@param line string
---@param col integer
function M.char_at(line, col)
  if col < 0 or col >= #line then
    return ""
  end
  return line:sub(col + 1, col + 1 + vim.str_utf_end(line, col + 1))
end

--- Byte column (0-based) of the character before `col`.
---@param line string
---@param col integer
function M.prev_col(line, col)
  if col <= 0 then
    return nil
  end
  return col - 1 + vim.str_utf_start(line, col)
end

-- Roughly what `w`/`e`/`b` consider a word: a run of keyword characters, or a run
-- of other non-blank characters.
local WORD = [[\k\+\|\%(\k\@!\S\)\+]]

--- Words on a line, as 0-based start and (inclusive) end byte columns.
---@param line string
---@return { s: integer, e: integer }[]
function M.words(line)
  local result, from = {}, 0
  while true do
    local m = vim.fn.matchstrpos(line, WORD, from)
    if m[2] < 0 then
      return result
    end
    result[#result + 1] = { s = m[2], e = m[3] - 1 }
    from = m[3]
  end
end

--- Render a key for display, e.g. " " -> "<Space>".
---@param key string
function M.show(key)
  return key == " " and "<Space>" or key
end

--- Opening -> closing delimiter.
M.PAIRS = {
  ["("] = ")",
  ["["] = "]",
  ["{"] = "}",
  ["<"] = ">",
  ['"'] = '"',
  ["'"] = "'",
  ["`"] = "`",
}

--- If `a` and `b` are a matching pair (in either order), return the opening one.
---@param a string
---@param b string
---@return string?
function M.pair_of(a, b)
  if M.PAIRS[a] == b then
    return a
  elseif M.PAIRS[b] == a then
    return b
  end
end

--- The comment leader of a buffer from 'commentstring' (`// %s` -> `//`).
---@param buf integer
---@return string?
function M.comment_leader(buf)
  local cs = vim.api.nvim_buf_is_valid(buf) and vim.bo[buf].commentstring or ""
  local leader = cs:match("^(.-)%s*%%s")
  return leader ~= "" and leader or nil
end

--- Pluralize: `plural(1, "key")` -> "1 key", `plural(3, "key")` -> "3 keys".
---@param n integer
---@param word string
function M.plural(n, word)
  return ("%d %s%s"):format(n, word, n == 1 and "" or "s")
end

return M
