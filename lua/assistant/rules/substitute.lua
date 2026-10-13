---@class assistant.Substitute
---@field pattern string
---@field replacement string
---@field flags string
---@field ranged boolean A range was given (`%`, `'<,'>`, `1,10`)

--- Parse a `:s` command line, or return nil.
---@param cmdline string
---@return assistant.Substitute?
local function parse(cmdline)
  local ok, cmd = pcall(vim.api.nvim_parse_cmd, cmdline, {})
  if not ok or cmd.cmd ~= "substitute" or not cmd.args[1] then
    return nil
  end
  local args = cmd.args[1]
  local delim = args:sub(1, 1)
  if delim == "" or delim:match("[%w\\\"|%s]") then
    return nil
  end
  -- Split on unescaped delimiters.
  local parts, cur, i = {}, {}, 2
  while i <= #args do
    local c = args:sub(i, i)
    if c == "\\" and i < #args then
      cur[#cur + 1] = args:sub(i, i + 1)
      i = i + 2
    else
      if c == delim and #parts < 2 then
        parts[#parts + 1] = table.concat(cur)
        cur = {}
      else
        cur[#cur + 1] = c
      end
      i = i + 1
    end
  end
  parts[#parts + 1] = table.concat(cur)
  return {
    pattern = parts[1] or "",
    replacement = parts[2] or "",
    flags = parts[3] or "",
    ranged = cmd.range ~= nil and #cmd.range > 0,
  }
end

--- `:s` habits: typing the word under the cursor, repeating the last search, and
--- running the same substitution line after line.
---@type assistant.Rule
return {
  name = "substitute",
  desc = ":s habits (repeating, retyping words)",
  check = function(history, opts)
    local last = history[#history]
    if not last or last.key ~= "<Cmd>" or last.cmdtype ~= ":" or last.aborted then
      return
    end
    local sub = parse(last.cmdline)
    if not sub then
      return
    end

    -- The same range-less :s several times in a row.
    if not sub.ranged then
      local n = 0
      for i = #history, 1, -1 do
        local ev = history[i]
        if ev.key == "<Cmd>" and ev.cmdtype == ":" then
          local other = parse(ev.cmdline)
          if not other or other.ranged or other.pattern ~= sub.pattern or other.replacement ~= sub.replacement then
            break
          end
          n = n + 1
        end
      end
      if n >= (opts.threshold or 3) then
        return {
          msg = ("You ran `:s/%s/%s/` on %d lines one by one.\n"):format(sub.pattern, sub.replacement, n)
            .. ("→ `:%%s/%s/%s/g` changes the whole file at once (add `c` to confirm each one)\n"):format(
              sub.pattern,
              sub.replacement
            )
            .. "→ Select lines with `V` and type `:s/…` to change only those\n"
            .. "→ `g&` repeats the last `:s` on every line",
        }
      end
    end

    if sub.pattern ~= "" and sub.pattern == last.search_reg then
      return {
        msg = ("Your pattern `%s` is the same as your last search.\n→ Leave it empty: `:%%s//%s/g` reuses the last search (great after `*`)"):format(
          sub.pattern,
          sub.replacement
        ),
      }
    end

    local word = last.cword or ""
    if
      #word >= 3
      and (sub.pattern == word or sub.pattern == "\\<" .. word .. "\\>")
      and not vim.tbl_contains(last.cmd_keys or {}, "<C-R>")
    then
      return {
        msg = ("You typed `%s`, the word under the cursor.\n→ `<C-r><C-w>` inserts it on the command line for you (`<C-r><C-a>` for the WORD)"):format(
          word
        ),
      }
    end
  end,
}
