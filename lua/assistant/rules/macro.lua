local util = require("assistant.util")

local EDITS = {
  x = true, X = true, d = true, c = true, s = true, S = true, r = true, p = true, P = true, J = true,
  ["~"] = true, [">"] = true, ["<"] = true, ["."] = true,
  i = true, a = true, I = true, A = true, o = true, O = true, C = true, D = true,
}

--- Recent keys as display tokens; command lines become one `:cmd<CR>` token.
---@param history assistant.Event[]
---@return string[] tokens, assistant.Event[] events
local function tokens(history)
  local toks, evs = {}, {}
  for i = math.max(1, #history - 150), #history do
    local ev = history[i]
    if not util.is_side(ev) and not util.is_pause(ev) then
      if ev.key == "<Cmd>" then
        if toks[#toks] == ev.cmdtype then
          toks[#toks], evs[#evs] = nil, nil
        end
        toks[#toks + 1], evs[#evs + 1] = ev.cmdtype .. ev.cmdline .. "<CR>", ev
      else
        toks[#toks + 1], evs[#evs + 1] = ev.key, ev
      end
    end
  end
  return toks, evs
end

--- Smallest chunk that repeats at least `min` times at the end of `toks`.
---@return integer? period, integer reps
local function find_period(toks, min)
  local n = #toks
  for p = 2, 12 do
    local reps = 1
    while (reps + 1) * p <= n do
      local same = true
      for j = 0, p - 1 do
        if toks[n - j] ~= toks[n - reps * p - j] then
          same = false
          break
        end
      end
      if not same then
        break
      end
      reps = reps + 1
    end
    if reps >= min then
      return p, reps
    end
  end
  return nil, 0
end

--- The same sequence of keys several times in a row -> macro, `:norm`, `:g`.
---@type assistant.Rule
return {
  name = "macro",
  desc = "Repeating key sequences instead of a macro",
  check = function(history, opts)
    local last = history[#history]
    if not last or not util.is_pause(last) then
      return -- only look once the user pauses
    end
    local toks, evs = tokens(history)
    local p, reps = find_period(toks, opts.threshold or 3)
    if not p then
      return
    end
    local chunk = vim.list_slice(toks, #toks - p + 1)
    local chunk_evs = vim.list_slice(evs, #evs - p + 1)

    local distinct, edits, normal = {}, false, false
    for i, tok in ipairs(chunk) do
      local ev = chunk_evs[i]
      distinct[tok] = true
      if tok == "q" or tok == "@" then
        return -- already using macros
      end
      if not util.is_insert(ev.mode) then
        normal = true
      end
      if util.is_insert(ev.mode) or (EDITS[tok] and not ev.arg) or (ev.key == "<Cmd>" and ev.cmdtype == ":") then
        edits = true
      end
    end
    if vim.tbl_count(distinct) < 2 or not edits or not normal then
      return
    end

    local seq = table.concat(chunk)
    if seq == "n." or seq == "N." then
      return -- already the ideal workflow
    end
    if seq == "ndd" or seq == "Ndd" then
      local pat = vim.fn.getreg("/")
      return {
        msg = ("You repeated `%s` %d times.\n→ `:g/%s/d` deletes every line matching your search at once (`:v/…/d` keeps only those)"):format(
          seq,
          reps,
          pat
        ),
      }
    end
    if seq == "j." or seq == "k." then
      return {
        msg = ("You repeated `%s` %d times.\n→ Select the lines with `V`, then `:norm .` repeats the change on every one of them"):format(seq, reps),
      }
    end

    local msg = ("You repeated `%s` %d times.\n→ Record it once: `qq%sq`, then `@q` replays it (`@@` again, `10@q` ten times)"):format(
      seq,
      reps,
      seq
    )
    if chunk[#chunk] == "j" and not seq:find("<") then
      msg = msg .. ("\n→ Or select the lines with `V` and run `:norm %s`"):format(seq:sub(1, -2))
    end
    return { msg = msg }
  end,
}
